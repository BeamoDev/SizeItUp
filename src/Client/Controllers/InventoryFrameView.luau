--!strict
-- Binds the authored HUD.Frame.Inventory overlay: one menu for chairs, pets and titles.
--   Frame.Frame          the Chairs / Pets / Titles side buttons; Header.ActiveStroke is enabled on the open one
--   Header.Close         closes (InventoryController wires it and the side buttons)
--   ChairContainer, PetsContainer, TitleContainer   scrolling grids; only the open tab's grid is visible
--   InfoCard             hover / click card placed beside an item: TextLabel "~ Name ~", Info, Rarity (with its UIGradient)
--                        and an ImageButton that closes it
-- Cards are clones of ReplicatedStorage.Assets.UI.PetChairTemplate (chairs and pets) and .TitleTemplate, made the first
-- time a tab opens and then reused, one per owned item:
--   ViewportFrame  the chair model (or pet)          Title      the title text, coloured and shimmering
--   Level          "Lvl N", only while equipped      ItemName   the name, only while not equipped
--   Equip / Unequip  the visible one matches the card's state
--   Equipped: white background, both OuterUIStrokes and EquippedGradient on.
--   Unequipped: background 0,89,166, strokes off, UnequippedGradient on.
-- Order: highest pet level / most valuable chair / best title first. Equipping never moves a card.
-- Equipping eases the background colour, pops the card and swaps Equip / Unequip with a scale in/out; buttons grow when
-- hovered and shrink when pressed.
local Style = require(script.Parent.UIStyle)
local FrameSlide = require(script.Parent.FrameSlide)
local InventoryFrameView = {}
InventoryFrameView.__index = InventoryFrameView

local TABS = { "Chairs", "Pets", "Titles" }
local CONTAINERS = { Chairs = "ChairContainer", Pets = "PetsContainer", Titles = "TitleContainer" }
local UNEQUIPPED_COLOR = Color3.fromRGB(0, 89, 166)
local EQUIPPED_COLOR = Color3.new(1, 1, 1)
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local INFO_IN, INFO_OUT = 0.2, 0.13
local BUTTON_IN, BUTTON_OUT = 0.22, 0.14
local POP_SECONDS = 0.38
local HOVER_SCALE, PRESS_SCALE = 1.08, 0.92

local function clickable(node: Instance?): GuiButton?
	if not node then return nil end
	if node:IsA("GuiButton") then return node end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end

local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c = 1.70158
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

-- Dark, light, dark of the title's own colour, so the sliding gradient reads as a clean shimmer.
local function titleGradient(base: Color3): ColorSequence
	local dark, light = base:Lerp(Color3.new(0, 0, 0), 0.35), base:Lerp(Color3.new(1, 1, 1), 0.65)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, dark), ColorSequenceKeypoint.new(0.5, light), ColorSequenceKeypoint.new(1, dark) })
end

local function scaleOf(node: Instance): UIScale
	local scale = node:FindFirstChild("InventoryScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "InventoryScale"
		scale.Parent = node
	end
	return scale :: UIScale
end

function InventoryFrameView.new(catalog: any, input: UserInputService?, guiService: GuiService?)
	local UI = Style.Authoring
	local root = UI.Need(UI.Overlays, "Inventory", "GuiObject")
	local missing: {string} = {}
	local function deep(within: Instance, name: string, class: string): any
		for _, node in within:GetDescendants() do
			if node.Name == name and node:IsA(class) then return node end
		end
		table.insert(missing, within:GetFullName() .. ".." .. name .. " (" .. class .. ")")
		return nil
	end
	local self: any = setmetatable({
		Catalog = catalog, Gui = root, Age = 0, Tabs = {}, Containers = {}, Cards = { Chairs = {}, Pets = {}, Titles = {} }, Previews = {},
		Anims = {}, Connections = {}, Info = { T = 0, Target = false }, Input = input, GuiService = guiService,
	}, InventoryFrameView)
	-- The side buttons hold a Header with an ActiveStroke (unlike the Header.Titles folder or other same-named nodes).
	for _, tab in TABS do
		local found
		for _, node in root:GetDescendants() do
			if node.Name == tab and node:IsA("GuiObject") and node:FindFirstChild("ActiveStroke", true) then found = node;break end
		end
		if found then
			local stroke = found:FindFirstChild("ActiveStroke", true)
			local button = clickable(found)
			if stroke and stroke:IsA("UIStroke") and button then self.Tabs[tab] = { Button = button, Holder = found, Stroke = stroke }
			else table.insert(missing, found:GetFullName() .. " (a button with Header.ActiveStroke)") end
		else table.insert(missing, root:GetFullName() .. ".." .. tab .. " (side button with Header.ActiveStroke)") end
		self.Containers[tab] = deep(root, CONTAINERS[tab], "GuiObject")
	end
	local closeHolder = deep(root, "Close", "GuiObject")
	self.Close = clickable(closeHolder)
	self.CloseHolder = closeHolder
	if closeHolder and not self.Close then table.insert(missing, closeHolder:GetFullName() .. " (a button, or a child button)") end
	local info = deep(root, "InfoCard", "GuiObject")
	if info then
		self.InfoCard = info
		self.InfoName = deep(info, "TextLabel", "TextLabel")
		self.InfoRarity = deep(info, "Rarity", "TextLabel")
		-- The description is "Info" (or a frame of that name holding the text), else the card's own "InfoCard" label
		-- or, failing that, its remaining text label.
		local function textIn(node: Instance?): TextLabel?
			if not node then return nil end
			if node:IsA("TextLabel") then return node end
			return node:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel?
		end
		local text = textIn(info:FindFirstChild("Info", true)) or textIn(info:FindFirstChild("InfoCard", true)) or (if info:IsA("TextLabel") then info else nil)
		if not text then
			for _, node in info:GetDescendants() do
				if node:IsA("TextLabel") and node ~= self.InfoName and node ~= self.InfoRarity then text = node;break end
			end
		end
		self.InfoText = text
		if not text then table.insert(missing, info:GetFullName() .. ".Info (TextLabel)") end
		local closeIcon = info:FindFirstChild("ImageButton", true)
		self.InfoClose = clickable(closeIcon)
		if self.InfoClose then pcall(function()
			table.insert(self.Connections, self.InfoClose.Activated:Connect(function() self:HideInfo(true) end))
		end) end
		if not self.InfoClose then table.insert(missing, info:GetFullName() .. ".ImageButton (a button)") end
	end
	-- The card templates live beside the other authored assets.
	local assets = Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	self.PetChairTemplate = ui and ui:FindFirstChild("PetChairTemplate")
	self.TitleTemplate = ui and ui:FindFirstChild("TitleTemplate")
	if not self.PetChairTemplate then table.insert(missing, "ReplicatedStorage.Assets.UI.PetChairTemplate") end
	if not self.TitleTemplate then table.insert(missing, "ReplicatedStorage.Assets.UI.TitleTemplate") end
	assert(#missing == 0, "Missing authored UI: " .. table.concat(missing, ", "))
	for _, container in self.Containers do
		local layout = container:FindFirstChildWhichIsA("UIGridStyleLayout")
		if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		container.Visible = false
	end
	self.InfoScale = scaleOf(self.InfoCard)
	self.InfoCard.Visible = false
	-- Side buttons and Close grow on hover and shrink when pressed.
	for _, entry in self.Tabs do self:Juice(entry.Button, entry.Holder) end
	self:Juice(self.Close, self.CloseHolder)
	self:Juice(self.InfoClose, self.InfoClose)
	self.Slide = FrameSlide.new(root)
	Style.SetEnabled(root, false)
	return self
end

-- Registers a scale animation on a holder: hover / press feedback, plus show / hide swaps when it is a card button.
function InventoryFrameView.Anim(self: any, holder: GuiObject, visible: boolean?): any
	local anim = { Node = holder, Scale = scaleOf(holder), Presence = if visible == false then 0 else 1, Target = visible ~= false, Hover = 1, HoverTarget = 1, Swaps = visible ~= nil }
	table.insert(self.Anims, anim)
	return anim
end

-- Hover grows a button, pressing shrinks it (the events only exist in the real engine).
function InventoryFrameView.Juice(self: any, button: GuiButton?, holder: GuiObject?, anim: any?)
	if not button or not holder then return anim end
	anim = anim or self:Anim(holder)
	pcall(function()
		table.insert(self.Connections, button.MouseEnter:Connect(function() anim.HoverTarget = HOVER_SCALE end))
		table.insert(self.Connections, button.MouseLeave:Connect(function() anim.HoverTarget = 1 end))
		table.insert(self.Connections, button.MouseButton1Down:Connect(function() anim.HoverTarget = PRESS_SCALE end))
		table.insert(self.Connections, button.MouseButton1Up:Connect(function() anim.HoverTarget = HOVER_SCALE end))
	end)
	return anim
end

-- Builds the card for one owned item the first time it is needed.
function InventoryFrameView.Card(self: any, tab: string, id: string): any
	local cards = self.Cards[tab]
	local existing = cards[id]
	if existing and existing.Node.Parent then return existing end
	local template = if tab == "Titles" then self.TitleTemplate else self.PetChairTemplate
	local node = template:Clone()
	node.Name, node.Visible = id, true
	node.Parent = self.Containers[tab]
	local card: any = { Id = id, Tab = tab, Node = node, Strokes = {}, Equip = {}, Unequip = {}, Eq = 0, Pop = 1 }
	for _, child in node:GetChildren() do
		if child:IsA("UIStroke") and string.sub(child.Name, 1, 13) == "OuterUIStroke" then table.insert(card.Strokes, child) end
	end
	-- Each stroke carries one gradient per rarity: only the item's own rarity is enabled.
	local item = self.Catalog.Items[tab][id]
	if tab ~= "Titles" then
		for _, stroke in card.Strokes do Style.SelectRarityGradients(stroke, item.Rarity or "Common") end
	end
	card.EquippedGradient = node:FindFirstChild("EquippedGradient")
	card.UnequippedGradient = node:FindFirstChild("UnequippedGradient")
	card.Level, card.ItemName, card.Title = node:FindFirstChild("Level"), node:FindFirstChild("ItemName"), node:FindFirstChild("Title")
	card.Scale = scaleOf(node)
	for _, name in { "Equip", "Unequip" } do
		local holder = node:FindFirstChild(name)
		local button = clickable(holder)
		card[name] = { Holder = holder, Button = button }
		if holder then card[name].Anim = self:Anim(holder, false);self:Juice(button, holder, card[name].Anim) end
	end
	if tab ~= "Titles" then
		local viewport = node:FindFirstChildWhichIsA("ViewportFrame", true)
		if viewport then
			Style.Preview(node, item, tab, viewport)
			card.Viewport = viewport
		end
	elseif card.Title then
		card.Title.Text, card.Title.TextColor3 = item.Name, Color3.new(1, 1, 1)
		local gradient = card.Title:FindFirstChildOfClass("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "TitleGradient"
			gradient.Parent = card.Title
		end
		gradient.Color = titleGradient(Color3.fromRGB(table.unpack(item.Color)))
		card.Gradient = gradient
		card.Phase = (#id % 7) * 0.9
	end
	if card.ItemName then card.ItemName.Text = item.Name end
	-- Hovering or clicking a pet card opens the info card beside it (chairs and titles have none).
	if tab == "Pets" then pcall(function()
		table.insert(self.Connections, node.MouseEnter:Connect(function() self:ShowInfo(tab, id, node, false) end))
		table.insert(self.Connections, node.MouseLeave:Connect(function() if not self.Info.Pinned then self:HideInfo() end end))
		table.insert(self.Connections, node.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then self:ShowInfo(tab, id, node, true) end
		end))
	end) end
	cards[id] = card
	return card
end

local function setVisible(node: Instance?, visible: boolean) if node then (node :: any).Visible = visible end end

-- Applies the equipped / unequipped look. `animate` starts the pop and the button swap; otherwise it snaps.
function InventoryFrameView.Style(self: any, card: any, tab: string, equipped: boolean, level: number?, animate: boolean)
	local changed = card.Equipped ~= nil and card.Equipped ~= equipped
	card.Equipped = equipped
	card.EqTarget = if equipped then 1 else 0
	if not animate or card.Eq == nil then card.Eq = card.EqTarget end
	if changed and animate then card.Pop = 0 end
	card.Node.BackgroundColor3 = UNEQUIPPED_COLOR:Lerp(EQUIPPED_COLOR, card.Eq)
	for _, stroke in card.Strokes do stroke.Enabled = equipped end
	if card.EquippedGradient then card.EquippedGradient.Enabled = equipped end
	if card.UnequippedGradient then card.UnequippedGradient.Enabled = not equipped end
	for name, on in { Equip = not equipped, Unequip = equipped } do
		local entry = card[name]
		if entry.Anim then
			entry.Anim.Target = on
			if on then setVisible(entry.Holder, true) end
			if not animate or not changed then entry.Anim.Presence = if on then 1 else 0;setVisible(entry.Holder, on) end
		else setVisible(entry.Holder, on) end
	end
	if tab == "Pets" then
		-- A pet shows its level while equipped and its name while not.
		if card.Level then card.Level.Visible = equipped;if level then card.Level.Text = "Lvl " .. level end end
		if card.ItemName then card.ItemName.Visible = not equipped end
	else
		setVisible(card.Level, false)
		setVisible(card.ItemName, true)
	end
end

function InventoryFrameView.SetTab(self: any, tab: string)
	if self.Tab ~= tab then self:HideInfo(true) end
	self.Tab = tab
	for name, container in self.Containers do container.Visible = name == tab end
	for name, entry in self.Tabs do entry.Stroke.Enabled = name == tab end
end

function InventoryFrameView.Show(self: any, visible: boolean)
	if visible == (self.Open == true) then return end
	self.Open = visible
	if visible then self.Slide:Show() else self:HideInfo(true);self.Slide:Hide();table.clear(self.Previews) end
end

-- What the info card says about an item.
function InventoryFrameView.Describe(self: any, tab: string, id: string): (string, string, string?)
	local item = self.Catalog.Items[tab][id]
	if tab == "Pets" then
		return item.Name, item.AbilityText or "A friendly pet that follows you around.", item.Rarity
	elseif tab == "Chairs" then
		return item.Name, if item.RewardOnly then "A reward chair. Sit on it at any table." else "Sit in style at any table.", item.Rarity or "Common"
	end
	return item.Name, "A title you earned by leveling up. It shows above your head.", nil
end

-- Colours the Rarity label's UIGradient for the rarity (a rainbow for Mythic).
function InventoryFrameView.Rarity(self: any, rarity: string?)
	local label = self.InfoRarity
	label.Visible = rarity ~= nil
	if rarity then Style.RarityLabel(label, rarity, self.Catalog.PetRarityStyles) end
end

-- Whether a real mouse is driving this session right now (vs. touch/gamepad).
function InventoryFrameView.HasMouse(self: any): boolean
	return self.Input ~= nil and self.GuiService ~= nil and self.Input.MouseEnabled == true
end

-- Opens the info card beside `anchor` (or, on PC, at the cursor -- see PlaceInfoAtCursor); a click pins it until it
-- is closed.
function InventoryFrameView.ShowInfo(self: any, tab: string, id: string, anchor: GuiObject, pinned: boolean)
	if tab ~= "Pets" or not self.Open or (self.Info.Pinned and not pinned) then return end
	local name, text, rarity = self:Describe(tab, id)
	self.InfoName.Text = "~ " .. name .. " ~"
	self.InfoText.Text = text
	self:Rarity(rarity)
	self.Info.Pinned, self.Info.Id, self.Info.Anchor = pinned, id, anchor
	if self:HasMouse() then self:PlaceInfoAtCursor() else self:PlaceInfo(anchor) end
	self.Info.Target = true
	self.InfoCard.Visible = true
end

function InventoryFrameView.HideInfo(self: any, immediate: boolean?)
	self.Info.Target, self.Info.Pinned, self.Info.Id, self.Info.Anchor = false, false, nil, nil
	if immediate then self.Info.T = 0;self.InfoCard.Visible = false;self.InfoScale.Scale = 1 end
end

-- Puts the info card beside the player's actual cursor (right and below it, or flipped when there is no room),
-- inside the frame. GetMouseLocation is in viewport-pixel space; AbsolutePosition matches it only when this
-- overlay's ScreenGui ignores the inset, so the GuiInset is subtracted otherwise (the same conversion the direct
-- object-drag/hover code uses).
function InventoryFrameView.PlaceInfoAtCursor(self: any)
	local card = self.InfoCard
	local parent = card.Parent :: GuiObject?
	if not (parent and self:HasMouse()) then return end
	pcall(function()
		local gap = 18
		local viewport = self.Input:GetMouseLocation()
		local point = if Style.IgnoreInset(self.Gui) then viewport else viewport - self.GuiService:GetGuiInset()
		local pa, ps, size = parent.AbsolutePosition, parent.AbsoluteSize, card.AbsoluteSize
		local x = point.X + gap
		if x + size.X > pa.X + ps.X then x = point.X - size.X - gap end
		x = math.clamp(x, pa.X, math.max(pa.X, pa.X + ps.X - size.X))
		local y = math.clamp(point.Y + gap, pa.Y, math.max(pa.Y, pa.Y + ps.Y - size.Y))
		card.AnchorPoint = Vector2.zero
		card.Position = UDim2.fromOffset(x - pa.X, y - pa.Y)
	end)
end

-- Puts the info card to the right of the item (or to its left when there is no room), inside the frame. Used on
-- touch, where there is no cursor to follow.
function InventoryFrameView.PlaceInfo(self: any, anchor: GuiObject)
	local card = self.InfoCard
	local parent = card.Parent :: GuiObject?
	if not parent then return end
	self.InfoScale.Scale = 1
	-- Absolute geometry only exists once the engine has laid the frame out.
	pcall(function()
		local gap = 8
		local pa, ps, ca, cs, size = parent.AbsolutePosition, parent.AbsoluteSize, anchor.AbsolutePosition, anchor.AbsoluteSize, card.AbsoluteSize
		local x = ca.X + cs.X + gap
		if x + size.X > pa.X + ps.X then x = ca.X - size.X - gap end
		x = math.max(pa.X, x)
		local y = math.clamp(ca.Y, pa.Y, math.max(pa.Y, pa.Y + ps.Y - size.Y))
		card.AnchorPoint = Vector2.zero
		card.Position = UDim2.fromOffset(x - pa.X, y - pa.Y)
	end)
end

-- Shows the open tab's owned items, updating existing cards in place. Returns nothing to bind beyond `actions`.
function InventoryFrameView.Render(self: any, state: any, tab: string, actions: any)
	if not self.Open or not self.Cards[tab] then return end
	self:SetTab(tab)
	local owned = state.Owned[tab] or {}
	local progress = state.PetProgress or {}
	local rows = {}
	for _, id in self.Catalog.Order[tab] do
		local count = owned[id] or 0
		if count > 0 then
			local item = self.Catalog.Items[tab][id]
			local equipped, lastSlot, level = false, nil, nil
			if tab == "Pets" then
				local copies = 0
				for slot, pet in state.Equipped.Pets do if pet == id then copies += 1;lastSlot = slot end end
				equipped, level = copies > 0, if progress[id] then progress[id].Level else 1
			else equipped = state.Equipped[tab] == id end
			local rank = if tab == "Pets" then (RARITY_RANK[item.Rarity] or 1) elseif tab == "Chairs" then (item.Price or 0) else (table.find(self.Catalog.Order.Titles, id) or 0)
			table.insert(rows, { Id = id, Name = item.Name, Equipped = equipped, Level = level or 0, Rank = rank, Slot = lastSlot })
		end
	end
	-- Equipping never moves a card: highest level / value first, then name.
	table.sort(rows, function(a: any, b: any)
		if a.Level ~= b.Level then return a.Level > b.Level end
		if a.Rank ~= b.Rank then return a.Rank > b.Rank end
		return a.Name < b.Name
	end)
	local present = {}
	table.clear(self.Previews)
	local full = #(state.Equipped.Pets or {}) >= (state.MaxPets or 6)
	for order, row in rows do
		present[row.Id] = true
		local fresh = not (self.Cards[tab][row.Id] and self.Cards[tab][row.Id].Node.Parent)
		local card = self:Card(tab, row.Id)
		card.Node.LayoutOrder = order
		card.Node.Visible = true
		self:Style(card, tab, row.Equipped, if tab == "Pets" then row.Level else nil, not fresh)
		if card.Viewport then table.insert(self.Previews, card.Viewport) end
		if card.Equip.Button then
			card.Equip.Button.Active = not (tab == "Pets" and full)
			table.insert(actions, { Button = card.Equip.Button, Action = "Equip", Payload = { Category = tab, Id = row.Id } })
		end
		if card.Unequip.Button then
			if tab == "Pets" then table.insert(actions, { Button = card.Unequip.Button, Action = "UnequipPet", Payload = { Slot = row.Slot } })
			else table.insert(actions, { Button = card.Unequip.Button, Action = "Equip", Payload = { Category = tab, Id = "" } }) end
		end
	end
	-- Items no longer owned leave their card behind hidden rather than being rebuilt later.
	for id, card in self.Cards[tab] do if not present[id] then card.Node.Visible = false end end
	if self.Info.Id and not present[self.Info.Id] then self:HideInfo(true) end
end

-- Level-only pushes update the labels without rebuilding anything.
function InventoryFrameView.UpdatePetProgress(self: any, progress: any)
	for id, card in self.Cards.Pets do
		local info = progress[id]
		if info and card.Level and card.Node.Visible then card.Level.Text = "Lvl " .. info.Level end
	end
end

function InventoryFrameView.Step(self: any, dt: number)
	self.Slide:Step(dt)
	if not self.Open and not self.Slide:IsActive() then return end
	self.Age += dt
	if self.Open then
		for _, viewport in self.Previews do Style.RotatePetPreview(viewport, self.Age) end
	end
	-- Equipping: the background eases between colours and the card gives a small pop.
	local ease = 1 - math.exp(-14 * dt)
	for _, cards in self.Cards do
		for _, card in cards do
			if card.EqTarget and card.Eq ~= card.EqTarget then
				card.Eq += (card.EqTarget - card.Eq) * ease
				if math.abs(card.EqTarget - card.Eq) < 0.005 then card.Eq = card.EqTarget end
				card.Node.BackgroundColor3 = UNEQUIPPED_COLOR:Lerp(EQUIPPED_COLOR, card.Eq)
			end
			if card.Pop < 1 then
				card.Pop = math.min(1, card.Pop + dt / POP_SECONDS)
				card.Scale.Scale = 1 + 0.1 * math.sin(math.pi * card.Pop)
			end
			if card.Gradient and card.Node.Visible then card.Gradient.Offset = Vector2.new(math.sin(self.Age * 1.4 + card.Phase) * 0.6, 0) end
		end
	end
	-- Buttons: swap in / out with a scale, and follow hover / press.
	local hoverEase = 1 - math.exp(-18 * dt)
	for _, anim in self.Anims do
		if anim.Swaps then
			anim.Presence = math.clamp(anim.Presence + (if anim.Target then dt / BUTTON_IN else -dt / BUTTON_OUT), 0, 1)
			anim.Node.Visible = anim.Target or anim.Presence > 0
		end
		anim.Hover += (anim.HoverTarget - anim.Hover) * hoverEase
		local swap = if not anim.Swaps then 1 elseif anim.Target then backOut(anim.Presence) else anim.Presence
		anim.Scale.Scale = math.max(0.0001, swap * anim.Hover)
	end
	-- The info card pops in and shrinks away, following the cursor on PC (or staying beside its anchor on touch)
	-- for as long as it is showing.
	local info = self.Info
	info.T = math.clamp(info.T + (if info.Target then dt / INFO_IN else -dt / INFO_OUT), 0, 1)
	if info.Target then
		if self:HasMouse() then self:PlaceInfoAtCursor() elseif info.Anchor then self:PlaceInfo(info.Anchor) end
		self.InfoScale.Scale = 0.85 + 0.15 * backOut(info.T)
	else self.InfoScale.Scale = 0.85 + 0.15 * info.T end
	if not info.Target and info.T <= 0 then self.InfoCard.Visible = false end
end

function InventoryFrameView.Destroy(self: any)
	self.Open = false
	table.clear(self.Previews)
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	for _, cards in self.Cards do for _, card in cards do card.Node:Destroy() end end
	self.Cards = { Chairs = {}, Pets = {}, Titles = {} }
	self:HideInfo(true)
	self.Slide:Reset()
end

return InventoryFrameView

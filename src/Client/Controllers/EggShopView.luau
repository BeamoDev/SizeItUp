--!strict
-- Binds the authored HUD.Frames.Eggs, opened by the E prompt on an egg stand (Workspace.Game.Interactables.Eggs). One egg is shown at a
-- time, chosen by the stand; nothing is generated except a viewport where a slot or the icon has none, and one invisible
-- click target on each slot (slots have no button of their own).
--   Frame.Body.Slot1-6      the egg's six pets: ONLY a ViewportFrame (ItemName is hidden); OuterUIStrokeclicking selects it (backgrounds, gradients and viewport colours are never touched)
--   Frame.Body.Selected     the info card of the selected pet:
--     Icon                  rotating preview of the pet
--     Level                 "Lvl 1 Frog" (level and name)
--     ItemName              the pet's perk
--     OuterUIStroke2        holds one UIGradient per rarity (Common, UnCommon, Rare, Epic, Gold = Legendary, Mythic); only the
--                           selected pet's rarity is enabled
--     Buy                   buys the pet with Cash (or Gems, for a shop whose CosmeticCatalog.PetShops Currency is
--                           "Keys" -- the Exquisite egg); hidden once you own it
--     Equip / Unequip       Equip is always visible (it only works for an owned, unequipped pet); Unequip shows for an equipped one and removes that copy
--   Frame.Header.Title      Title.TextLabel reads "Common Egg" / "Uncommon Egg" / "Exquisite Egg"; its UIGradient and Title.OuterUIStroke
--                           are the authored faint yellow for Common, green for Uncommon and gold for Exquisite
-- The server owns prices, ownership and the equip limit; this only shows state and returns the same actions as before.
local Style = require(script.Parent.UIStyle)
local FrameSlide = require(script.Parent.FrameSlide)
local EggShopView = {}
EggShopView.__index = EggShopView

local SLOTS = 6
-- The authored gradient names under OuterUIStroke2 for each catalog rarity.
local GRADIENT_NAMES =
	{ Common = "Common", Uncommon = "UnCommon", Rare = "Rare", Epic = "Epic", Legendary = "Gold", Mythic = "Mythic" }
local SPOTLIGHT = 1.35 -- the selected slot's stroke is this much thicker
-- The header's colours per egg (Starter keeps whatever faint yellow the frame was authored with).
local TITLE_LOOKS = {
	Lucky = { Text = { { 0, { 170, 255, 170 } }, { 1, { 40, 200, 80 } } }, Stroke = { 8, 92, 34 } },
	Secret = { Text = { { 0, { 255, 240, 130 } }, { 1, { 255, 170, 30 } } }, Stroke = { 140, 82, 0 } },
}
local function sequence(stops: any): ColorSequence
	local keys = {}
	for _, stop in stops do
		table.insert(keys, ColorSequenceKeypoint.new(stop[1], Color3.fromRGB(table.unpack(stop[2]))))
	end
	return ColorSequence.new(keys)
end

local function clickable(node: Instance?): GuiButton?
	if not node then
		return nil
	end
	if node:IsA("GuiButton") then
		return node
	end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end

local function need(parent: Instance, name: string, class: string?): any
	local node = parent:FindFirstChild(name)
	assert(
		node and (not class or node:IsA(class)),
		"Missing authored UI: " .. parent:GetFullName() .. "." .. name .. (if class then " (" .. class .. ")" else "")
	)
	return node
end

local function tint(look: any): Color3
	return Color3.fromRGB(table.unpack(look.Tint))
end

-- The viewport inside a holder (created only when the holder has none), with its camera.
local function viewportIn(holder: Instance): ViewportFrame
	local view = if holder:IsA("ViewportFrame") then holder else holder:FindFirstChildWhichIsA("ViewportFrame", true)
	if not view then
		view = Instance.new("ViewportFrame")
		view.Name, view.Size, view.BackgroundTransparency = "ViewportFrame", UDim2.fromScale(1, 1), 1
		view.Parent = holder
	end
	-- ViewportFrame.Ambient/LightColor default to black (no light at all) until something sets them; an authored
	-- viewport almost never has these touched in Studio, which was leaving every pet rendered fully unlit -- present
	-- in the tree, but invisible on screen. Always give it the same light as every other pet preview in the game.
	view.Ambient, view.LightColor = Color3.new(0.7, 0.7, 0.7), Color3.new(1, 1, 1)
	local camera = view:FindFirstChild("PreviewCamera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Name, camera.FieldOfView = "PreviewCamera", 38
		camera.CFrame = CFrame.lookAt(Vector3.new(3, 2, 5), Vector3.zero)
		camera.Parent = view
	end
	view.CurrentCamera = camera
	view:SetAttribute("RotatingPet", true)
	return view
end

local function showPet(view: ViewportFrame, pet: any)
	for _, child in view:GetChildren() do
		if child.Name == "PetModel" or child:IsA("Model") then
			child:Destroy()
		end
	end
	if Style.PetVisual and Style.PetModels and Style.PetModels:FindFirstChild(pet.AssetId) then
		Style.PetVisual.Create(Style.PetModels, pet.AssetId, view, 2.3, pet)
	end
end

function EggShopView.new(catalog: any)
	local UI = Style.Authoring
	local root = UI.Need(UI.Overlays, "Eggs", "GuiObject")
	local frame = need(root, "Frame")
	local body = need(frame, "Body")
	local selected = need(body, "Selected")
	local self: any = setmetatable({
		Catalog = catalog,
		Gui = root,
		Selected = selected,
		Slots = {},
		Open = false,
		Time = 0,
		Previews = {},
		Info = {
			Level = need(selected, "Level", "TextLabel"),
			Perk = need(selected, "ItemName", "TextLabel"),
			Icon = need(selected, "Icon", "GuiObject"),
			Buy = need(selected, "Buy", "GuiObject"),
			Equip = need(selected, "Equip", "GuiObject"),
			Unequip = need(selected, "Unequip", "GuiObject"),
		},
		Gradients = {},
	}, EggShopView)
	self.Info.BuyButton, self.Info.EquipButton, self.Info.UnequipButton =
		clickable(self.Info.Buy), clickable(self.Info.Equip), clickable(self.Info.Unequip)
	assert(
		self.Info.BuyButton and self.Info.EquipButton and self.Info.UnequipButton,
		"Missing authored UI: " .. selected:GetFullName() .. ".Buy/Equip/Unequip (buttons)"
	)
	for _, child in need(selected, "OuterUIStroke2"):GetChildren() do
		if child:IsA("UIGradient") then
			self.Gradients[child.Name] = child
		end
	end
	for index = 1, SLOTS do
		local slot = need(body, "Slot" .. index, "GuiObject")
		-- Only the viewport shows: any ItemName label is hidden.
		local itemName = slot:FindFirstChild("ItemName")
		if itemName and itemName:IsA("GuiObject") then
			itemName.Visible = false
		end
		-- Slots are plain frames, so each gets one invisible button to click.
		local hit = slot:FindFirstChild("SlotClick")
		if not hit then
			hit = Instance.new("TextButton")
			hit.Name, hit.Text, hit.Size, hit.BackgroundTransparency, hit.ZIndex, hit.Selectable =
				"SlotClick", "", UDim2.fromScale(1, 1), 1, 20, false
			hit.Parent = slot
		end
		local stroke = slot:FindFirstChild("OuterUIStroke")
		self.Slots[index] = {
			Frame = slot,
			Button = hit,
			Stroke = if stroke and stroke:IsA("UIStroke") then stroke else nil,
			Rest = if stroke and stroke:IsA("UIStroke") then stroke.Thickness else 0,
			Equipped = slot:FindFirstChild("EquippedGradient"),
			View = viewportIn(slot),
		}
	end
	local closeHolder = root:FindFirstChild("Close", true)
	self.Close = clickable(closeHolder)
	local header = frame:FindFirstChild("Header")
	local title = header and header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		-- The egg name is the Title's own TextLabel child (or the Title itself when it has none).
		local inner = title:FindFirstChild("TextLabel")
		self.Title = if inner and inner:IsA("TextLabel") then inner else title
		-- Both the Title and its TextLabel child display the egg name (never a default "TextLabel").
		self.TitleOuter = title
		self.TitleGradient = self.Title:FindFirstChildWhichIsA("UIGradient")
		local stroke = title:FindFirstChild("OuterUIStroke")
		self.TitleStroke = if stroke and stroke:IsA("UIStroke") then stroke else nil
		-- What the frame was authored with is the Common (Starter) look.
		self.TitleRest = {
			Color = if self.TitleGradient then self.TitleGradient.Color else nil,
			Stroke = if self.TitleStroke then self.TitleStroke.Color else nil,
		}
	end
	self.IconView = viewportIn(self.Info.Icon)
	self.Slide = FrameSlide.new(root)
	Style.SetEnabled(root, false)
	return self
end

-- Refreshes the whole frame for one egg and appends {Button, Action, Payload} entries to `actions`.
function EggShopView.Render(self: any, state: any, shopId: string, selectedId: string?, actions: any)
	local catalog = self.Catalog
	local shop = catalog.PetShops[shopId]
	local id = if selectedId and table.find(shop.Pets, selectedId) then selectedId else shop.Pets[1]
	self.SelectedId = id
	if self.Title then
		self.Title.Text = shop.Name
		if self.TitleOuter then
			self.TitleOuter.Text = shop.Name
		end
		local look = TITLE_LOOKS[shopId]
		if self.TitleGradient then
			self.TitleGradient.Color = if look
				then sequence(look.Text)
				else (self.TitleRest.Color or self.TitleGradient.Color)
		end
		if self.TitleStroke then
			self.TitleStroke.Color = if look
				then Color3.fromRGB(table.unpack(look.Stroke))
				else (self.TitleRest.Stroke or self.TitleStroke.Color)
		end
	end
	-- New egg: load its six pets into the slots.
	if self.ShopId ~= shopId then
		self.ShopId = shopId
		for index, slot in self.Slots do
			showPet(slot.View, catalog.Items.Pets[shop.Pets[index]])
		end
	end
	for index, slot in self.Slots do
		local petId = shop.Pets[index]
		local pet = catalog.Items.Pets[petId]
		-- The slot's and viewport's colours are never changed; the selected slot only gets a slightly thicker stroke.
		if slot.Stroke then
			slot.Stroke.Thickness = slot.Rest * (if petId == id then SPOTLIGHT else 1)
		end
		table.insert(actions, { Button = slot.Button, Action = "SelectPet", Payload = { Id = petId } })
	end
	-- The info card.
	local pet = catalog.Items.Pets[id]
	local progress = (state.PetProgress or {})[id]
	self.Info.Level.Text = catalog.PetDisplayName(id, progress and progress.Level)
	self.Info.Perk.Text = pet.AbilityText
	local wanted = GRADIENT_NAMES[pet.Rarity]
	for name, gradient in self.Gradients do
		gradient.Enabled = name == wanted
	end
	if self.IconId ~= id then
		self.IconId = id
		showPet(self.IconView, pet)
	end
	local owned = (state.Owned.Pets[id] or 0) > 0
	local available = not state.AvailablePets or state.AvailablePets[id] == true
	local slotIndex = table.find(state.Equipped.Pets, id)
	local full = #state.Equipped.Pets >= (state.MaxPets or 6)
	-- Buy disappears once the pet is owned; the price shows in any text label inside the button. A shop marked
	-- Currency="Keys" (the Exquisite egg) prices and pays in Gems instead of Cash.
	local gems = shop.Currency == "Keys"
	self.Info.Buy.Visible = not owned
	self.Info.BuyButton.Active = available and (if gems then state.Keys else state.Cash) >= pet.Price
	local priceLabel = self.Info.Buy:FindFirstChildWhichIsA("TextLabel", true)
	if priceLabel then
		priceLabel.Text = if not available
			then "Unavailable"
			elseif gems then tostring(pet.Price) .. (if pet.Price == 1 then " Gem" else " Gems")
			else Style.Money(pet.Price)
	end
	table.insert(
		actions,
		{ Button = self.Info.BuyButton, Action = "BuyPet", Payload = { Shop = shopId, Id = id, Token = state.Token } }
	)
	-- Only one of the state-dependent buttons is shown at a time: Equip for owned, unequipped pets and Unequip for
	-- the currently equipped copy. This keeps the card from showing both actions together.
	local canEquip = owned and slotIndex == nil and not full
	local canUnequip = slotIndex ~= nil
	self.Info.Equip.Visible = canEquip
	self.Info.EquipButton.Active = canEquip
	self.Info.Unequip.Visible = canUnequip
	self.Info.UnequipButton.Active = canUnequip
	if canEquip then
		table.insert(
			actions,
			{ Button = self.Info.EquipButton, Action = "Equip", Payload = { Category = "Pets", Id = id } }
		)
	elseif canUnequip then
		table.insert(
			actions,
			{ Button = self.Info.UnequipButton, Action = "UnequipPet", Payload = { Slot = slotIndex or 1 } }
		)
	end
end

function EggShopView.Show(self: any, open: boolean)
	self.Open = open
	if open then
		self.Slide:Show()
	else
		self.Slide:Hide()
	end
end

-- Slide in/out and preview rotation (only while open).
function EggShopView.Step(self: any, dt: number)
	self.Slide:Step(dt)
	if not self.Open then
		return
	end
	self.Time = (self.Time + dt) % 15
	for _, slot in self.Slots do
		Style.RotatePetPreview(slot.View, self.Time)
	end
	Style.RotatePetPreview(self.IconView, self.Time)
end

function EggShopView.Destroy(self: any)
	self.Open = false
	self.Slide:Reset()
	for _, slot in self.Slots do
		if slot.Button and slot.Button.Parent then
			slot.Button:Destroy()
		end
	end
end

return EggShopView

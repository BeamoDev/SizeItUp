--!strict
-- Binds the authored HUD.Frame.LuckyBlocks overlay (Arrows, Lower, Upper) and presents the four mystery blocks.
-- It creates no UI of its own (the block viewport is only made if the authored Container has none):
--   Arrows.Container   holds the spinning block viewport; Arrows.L / Arrows.R browse left and right
--   Lower.Cost1 / Cost10   A = currency icon (Cash or Gems), TextLabel = price for one / ten (ten has the bulk discount)
--   Lower.Pets         one clone of Assets.UI.PetLuckyBlockTemp per pet: rarity outline, pet viewport, drop chance
--   Lower.OpenButton / OpenButton10   buy and open one / ten blocks (the server still owns price, odds and the pets)
--   Upper.Block.Status the block's name; its UIGradient and OuterUIStroke take the block's colour
--   Upper.CloseButton  closes it
-- Opening slides the pieces in, switching blocks shrinks the block to nothing and grows the next one back, and
-- closing slides everything out again. While it is open the camera sits high above the world under a heavy blur.
-- It exposes the same interface as BlockPreviewView, so InventoryController drives it unchanged.
local Style = require(script.Parent.UIStyle)
local BlockPreviewView = require(script.Parent.BlockPreviewView)
local LuckyBlockView = {}
LuckyBlockView.__index = LuckyBlockView

LuckyBlockView.SetupViewport = BlockPreviewView.SetupViewport
LuckyBlockView.RefreshModel = BlockPreviewView.RefreshModel
LuckyBlockView.BeginSwipe = BlockPreviewView.BeginSwipe
LuckyBlockView.EndSwipe = BlockPreviewView.EndSwipe
function LuckyBlockView.UpdatePetProgress(_self: any, _progress: any) end

local BLUR_SIZE = 32
local CASH_ICON = "rbxassetid://109114110793698"
local GEM_ICON = "rbxassetid://79449944506530"
local VIEWPORT_SCALE = 1.25
local OPEN_SECONDS, CLOSE_SECONDS = 0.75, 0.4
local CONTENT_OUT, CONTENT_IN = 0.2, 0.55
local CONTENT_START = 0.35
-- Catalog rarity -> the gradient child of the template's OuterUIStroke that shows it.
local RARITY_GRADIENT = { Common = "Common", Uncommon = "UnCommon", Rare = "Rare", Epic = "Epic", Legendary = "Gold", Mythic = "Mythic" }
-- ShopCatalog.BlockPreviewModels design -> the Status plate colours and the viewport lighting.
local DESIGNS: {[string]: any} = {
	Purple = { Top = Color3.fromRGB(214, 150, 255), Bottom = Color3.fromRGB(122, 44, 214), Stroke = Color3.fromRGB(72, 20, 132), Light = Color3.fromRGB(205, 150, 255), Ambient = Color3.fromRGB(96, 78, 130) },
	Red = { Top = Color3.fromRGB(255, 140, 140), Bottom = Color3.fromRGB(205, 32, 52), Stroke = Color3.fromRGB(128, 14, 30), Light = Color3.fromRGB(255, 150, 130), Ambient = Color3.fromRGB(128, 78, 78) },
	Gold = { Top = Color3.fromRGB(255, 244, 130), Bottom = Color3.fromRGB(255, 168, 28), Stroke = Color3.fromRGB(140, 84, 8), Light = Color3.fromRGB(255, 224, 140), Ambient = Color3.fromRGB(128, 112, 74) },
	Grey = { Top = Color3.fromRGB(240, 243, 250), Bottom = Color3.fromRGB(128, 134, 152), Stroke = Color3.fromRGB(66, 70, 86), Light = Color3.fromRGB(215, 226, 255), Ambient = Color3.fromRGB(102, 106, 120) },
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function shift(base: UDim2, dx: number, dy: number): UDim2
	return UDim2.new(base.X.Scale + dx, base.X.Offset, base.Y.Scale + dy, base.Y.Offset)
end

local function commas(value: number): string
	local reversed = string.reverse(tostring(math.floor(value)))
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	grouped = string.gsub(string.reverse(grouped), "^,", "")
	return grouped
end

function LuckyBlockView.new(_playerGui: any, catalog: any, shop: any)
	local UI = Style.Authoring
	local need = UI.Need
	local root = need(UI.Overlays, "LuckyBlocks", "GuiObject")
	local arrows = need(root, "Arrows", "GuiObject")
	local container = need(arrows, "Container", "GuiObject")
	local lower, upper = need(root, "Lower", "GuiObject"), need(root, "Upper", "GuiObject")
	local cost = lower:FindFirstChild("Cost1") or need(lower, "Cost", "GuiObject")
	local cost10 = lower:FindFirstChild("Cost10")
	local block = need(upper, "Block", "GuiObject")
	local status = need(block, "Status", "TextLabel")
	local self: any = setmetatable({
		Catalog = catalog, Shop = shop, Gui = root, Room = root, Age = 0, Presence = 0, Content = 0, PetPreviews = {}, PendingPreviews = {}, Cards = {},
		Previous = need(arrows, "L", "GuiButton"), Next = need(arrows, "R", "GuiButton"), Surface = container,
		CostIcon = need(cost, "A", "ImageLabel"), CostText = need(cost, "TextLabel", "TextLabel"),
		Cost10Icon = cost10 and cost10:FindFirstChild("A"), Cost10Text = cost10 and cost10:FindFirstChild("TextLabel"),
		OpenButton10 = lower:FindFirstChild("OpenButton10"),
		PetsFrame = need(lower, "Pets", "GuiObject"), OpenButton = need(lower, "OpenButton", "GuiButton"),
		Close = need(upper, "CloseButton", "GuiButton"),
		Upper = upper, Lower = lower,
		Status = status, StatusStroke = need(status, "OuterUIStroke", "UIStroke"), StatusGradient = need(status, "UIGradient", "UIGradient"),
	}, LuckyBlockView)
	self.Base = { Upper = upper.Position, Lower = lower.Position, Previous = self.Previous.Position, Next = self.Next.Position, Status = status.Position, Pets = self.PetsFrame.Position }
	-- No white selection outline when a button is clicked.
	for _, button in { self.Previous, self.Next, self.OpenButton, self.Close } do button.Selectable = false end
	container.Active = true
	-- Nothing on screen reads this; the controller writes server messages here.
	self.Message = Instance.new("TextLabel")
	local viewport = container:FindFirstChild("BlockViewport") or container:FindFirstChildWhichIsA("ViewportFrame")
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name, viewport.Size, viewport.BackgroundTransparency, viewport.Active = "BlockViewport", UDim2.fromScale(1, 1), 1, false
		viewport.Parent = container
	end
	viewport.Active = false
	self.ViewBase = { Size = viewport.Size, Center = UDim2.fromScale(0.5, 0.5) }
	self.Viewport = viewport
	self:SetupViewport()
	-- Only the block itself: no plinth under it.
	for _, name in { "DisplayPlinth", "PlinthTrim" } do
		local extra = self.World:FindFirstChild(name)
		if extra then extra:Destroy() end
	end
	self:Rest()
	Style.SetEnabled(root, false)
	return self
end

function LuckyBlockView.Template(self: any): any
	local assets = Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("PetLuckyBlockTemp")
	if template and template:IsA("GuiObject") then return template end
	return nil
end

-- Clone the pet card template once per pet in the block's pool: rarity outline, spinning pet, drop chance.
function LuckyBlockView.BuildPets(self: any, item: any, pets: {string}, total: number)
	for _, child in self.PetsFrame:GetChildren() do
		if child:GetAttribute("LuckyPetCard") then child:Destroy() end
	end
	self.PetPreviews, self.PendingPreviews, self.Cards = {}, {}, {}
	local template = self:Template()
	if not template then return end
	for order, id in pets do
		local pet = self.Catalog.Items.Pets[id]
		local card = template:Clone()
		card.Name, card.LayoutOrder, card.Visible = "Pet" .. order, order, true
		card:SetAttribute("LuckyPetCard", true)
		local outline = card:FindFirstChild("OuterUIStroke")
		local wanted = RARITY_GRADIENT[pet.Rarity] or "Common"
		if outline then
			for _, child in outline:GetChildren() do
				local on = child.Name == wanted
				if child:IsA("UIGradient") then child.Enabled = on elseif child:IsA("GuiObject") then child.Visible = on end
			end
		end
		local chance = card:FindFirstChild("TextLabel")
		if chance and chance:IsA("TextLabel") then chance.Text, chance.ZIndex = string.format("%g%%", item.Weights[id] / total * 100), 3 end
		local viewport = Instance.new("ViewportFrame")
		viewport.Name, viewport.Size, viewport.Position = "PetViewport", UDim2.fromScale(0.9, 0.72), UDim2.fromScale(0.05, 0.04)
		viewport.BackgroundTransparency, viewport.ZIndex, viewport.Active = 1, 1, false
		viewport.Parent = card
		Style.Preview(card, pet, "Pets", viewport)
		table.insert(self.PetPreviews, viewport)
		if pet.AssetId and not viewport:FindFirstChild("PetModel") then self.PendingPreviews[viewport] = pet.AssetId end
		card.Parent = self.PetsFrame
	end
end

function LuckyBlockView.ShowPrice(self: any)
	local want = self.Want
	if not want then return end
	-- Owned (unopened) blocks of this kind open free: the single price reads "x2 Owned" with no currency icon.
	self.CostIcon.Image = if want.Gems then GEM_ICON else CASH_ICON
	self.CostIcon.Visible = want.Owned <= 0
	self.CostText.Text = if want.Owned > 0 then "x" .. commas(want.Owned) .. " Owned" else commas(want.Price)
	if self.Cost10Icon and self.Cost10Icon:IsA("ImageLabel") then self.Cost10Icon.Image = if want.Gems then GEM_ICON else CASH_ICON end
	if self.Cost10Text and self.Cost10Text:IsA("TextLabel") then self.Cost10Text.Text = commas(want.BulkPrice) end
end

-- Swaps everything that belongs to one block (model, name plate colours, lighting, pet cards, price). It runs
-- while the content is faded and shrunk to nothing so the change is never seen.
function LuckyBlockView.Apply(self: any)
	local want = self.Want
	if not want then return end
	self.NeedApply = false
	self.Selected = want.Selected
	self:RefreshModel()
	local design = self.Shop.BlockPreviewModels and self.Shop.BlockPreviewModels[want.Selected]
	local look = DESIGNS[design] or DESIGNS.Purple
	self.Look = look
	self.Status.Text = want.Item.Name
	self.StatusGradient.Color = ColorSequence.new(look.Top, look.Bottom)
	self.StatusStroke.Color = look.Stroke
	self:BuildPets(want.Item, want.Pets, want.Total)
	self:ShowPrice()
	self:Pose()
end

function LuckyBlockView.Render(self: any, state: any, selected: string, actions: any)
	local index = table.find(self.Shop.BlockOrder, selected) or 1
	selected = self.Shop.BlockOrder[index]
	local item = self.Shop.Containers[selected]
	local pets, total, available = {}, 0, true
	for _, id in item.PetOrder or self.Catalog.Order.Pets do
		if (item.Weights[id] or 0) > 0 then
			table.insert(pets, id);total += item.Weights[id]
			if state.AvailablePets and not state.AvailablePets[id] then available = false end
		end
	end
	local gems = item.Currency == "Keys"
	local price, balance = if gems then item.Keys else item.Cash, if gems then state.Keys else state.Cash
	local owned = (state.OwnedBlocks and state.OwnedBlocks[selected]) or 0
	local affordable = available and (owned > 0 or (state.AllowedRandom == true and price > 0 and balance >= price))
	local bulk = self.Shop.BulkHatch
	local bulkPrice = if bulk then math.floor(price * bulk.Count * (1 - bulk.Discount)) else price
	self.Want = { Selected = selected, Item = item, Pets = pets, Total = total, Gems = gems, Price = price, BulkPrice = bulkPrice, Owned = owned }
	-- The button always reaches the server, which owns the price and explains any refusal.
	self.OpenButton.Active = true
	if self.OpenButton:IsA("ImageButton") then self.OpenButton.ImageColor3 = if affordable then Color3.new(1, 1, 1) else Color3.fromRGB(150, 152, 170) end
	table.insert(actions, { Button = self.OpenButton, Action = "Hatch", Payload = { Container = selected, Payment = item.Currency, Token = state.Token } })
	-- Opening ten at once: the same request with the bulk count (the server prices it with the discount).
	local ten = self.OpenButton10
	if ten and bulk then
		ten.Active = true
		if ten:IsA("ImageButton") then
			local canAfford = available and state.AllowedRandom == true and price > 0 and balance >= bulkPrice
			ten.ImageColor3 = if canAfford then Color3.new(1, 1, 1) else Color3.fromRGB(150, 152, 170)
		end
		table.insert(actions, { Button = ten, Action = "Hatch", Payload = { Container = selected, Payment = item.Currency, Token = state.Token, Count = bulk.Count } })
	end
	local ok, message = pcall(function()
		if self.Selected ~= selected then
			self.NeedApply = true
			if self.Content <= 0 then self:Apply() end
		elseif not self.NeedApply then
			self:ShowPrice()
		end
	end)
	if not ok then
		self.NeedApply = false
		warn("Lucky block content failed: " .. tostring(message))
	end
end

-- Puts every animated piece where the current Presence (open/close) and Content (block swap) put it.
function LuckyBlockView.Pose(self: any)
	local presence, content = self.Presence, self.Content
	local slide = if self.Open then backOut(presence) else smooth(presence)
	local away = 1 - slide
	self.Upper.Position = shift(self.Base.Upper, 0, -0.6 * away)
	self.Lower.Position = shift(self.Base.Lower, 0, 0.6 * away)
	self.Previous.Position = shift(self.Base.Previous, -0.9 * away, 0)
	self.Next.Position = shift(self.Base.Next, 0.9 * away, 0)
	local shown = smooth(content)
	local grow = if self.Rising then backOut(content) else shown
	local look = self.Look or DESIGNS.Purple
	local viewport = self.Viewport
	local scale = VIEWPORT_SCALE * grow
	local base = self.ViewBase.Size
	viewport.AnchorPoint, viewport.Position = Vector2.new(0.5, 0.5), self.ViewBase.Center
	viewport.Size = UDim2.new(base.X.Scale * scale, base.X.Offset * scale, base.Y.Scale * scale, base.Y.Offset * scale)
	-- A dim ambient and a tinted key light that circles the block make its edges and faces stand out.
	local sweep = self.Age * 0.9
	viewport.Ambient = look.Ambient
	viewport.LightColor = look.Light:Lerp(Color3.new(1, 1, 1), 0.3 + 0.15 * math.sin(self.Age * 2.2))
	viewport.LightDirection = Vector3.new(-math.cos(sweep), -0.85, -math.sin(sweep))
	if self.Model then
		self.Model:PivotTo(CFrame.new(0, math.sin(self.Age * 1.8) * 0.12, 0) * CFrame.Angles(0, self.Age * 0.6 + (1 - shown) * math.pi * 2, 0))
	end
	-- The name plate slides up out of sight and the next one drops in; the pet cards slide down and the next ones rise.
	self.Status.Position = shift(self.Base.Status, 0, -1.6 * (1 - grow))
	self.PetsFrame.Position = shift(self.Base.Pets, 0, 1.2 * (1 - grow))
end

-- The far, blurred backdrop: high above the world, looking toward the distance, drifting slowly.
function LuckyBlockView.EnterScene(self: any)
	if self.Scene then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size = "ScaleLuckyBlockBlur", 0
	blur.Parent = game:GetService("Lighting")
	self.Scene = { Camera = camera, Type = camera.CameraType, CFrame = camera.CFrame, Focus = camera.Focus, Fov = camera.FieldOfView, Blur = blur, Age = 0 }
	camera.CameraType = Enum.CameraType.Scriptable
	self:StepScene(0)
end

function LuckyBlockView.StepScene(self: any, dt: number)
	local scene = self.Scene
	if not scene then return end
	scene.Age += dt
	local look = scene.CFrame.LookVector * Vector3.new(1, 0, 1)
	local flat = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local direction = CFrame.Angles(0, scene.Age * 0.03, 0):VectorToWorldSpace(flat)
	local eye = scene.CFrame.Position + Vector3.new(0, 90, 0) - direction * 40
	scene.Camera.CFrame = CFrame.lookAt(eye, eye + direction * 900 + Vector3.new(0, -60, 0))
	scene.Camera.FieldOfView = 60
	scene.Blur.Size = BLUR_SIZE * smooth(self.Presence)
end

function LuckyBlockView.LeaveScene(self: any)
	local scene = self.Scene
	if not scene then return end
	self.Scene = nil
	if scene.Camera.Parent then
		scene.Camera.CameraType, scene.Camera.CFrame, scene.Camera.Focus, scene.Camera.FieldOfView = scene.Type, scene.CFrame, scene.Focus, scene.Fov
	end
	scene.Blur:Destroy()
end

-- Closing plays out in Step; the frame hides and the camera returns only when it has slid away.
function LuckyBlockView.Show(self: any, visible: boolean)
	self.Drag = nil
	if visible == (self.Open == true) then return end
	self.Open = visible
	if visible then
		self.Shown = true
		Style.SetEnabled(self.Gui, true)
		self:EnterScene()
		self:Pose()
	end
end

-- Hidden, the authored pieces sit exactly where they were built.
function LuckyBlockView.Rest(self: any)
	self:Pose()
	self.Upper.Position, self.Lower.Position = self.Base.Upper, self.Base.Lower
	self.Previous.Position, self.Next.Position, self.Status.Position, self.PetsFrame.Position = self.Base.Previous, self.Base.Next, self.Base.Status, self.Base.Pets
end

function LuckyBlockView.Finish(self: any)
	self.Shown, self.Open, self.Presence, self.Content = false, false, 0, 0
	self.Selected, self.Want, self.NeedApply = nil, nil, false
	self:Rest()
	Style.SetEnabled(self.Gui, false)
	self:LeaveScene()
end

function LuckyBlockView.Step(self: any, dt: number)
	if not self.Shown then return end
	self.Age += dt
	local duration = if self.Open then OPEN_SECONDS else CLOSE_SECONDS
	self.Presence = math.clamp(self.Presence + (if self.Open then dt else -dt) / duration, 0, 1)
	if not self.Open and self.Presence <= 0 then
		self:Finish()
		return
	end
	if self.NeedApply and self.Content <= 0 then
		local ok, message = pcall(self.Apply, self)
		if not ok then self.NeedApply = false;warn("Lucky block content failed: " .. tostring(message)) end
	end
	self.Rising = self.Open and self.Presence >= CONTENT_START and not self.NeedApply
	if self.Rising then self.Content = math.min(1, self.Content + dt / CONTENT_IN)
	else self.Content = math.max(0, self.Content - dt / CONTENT_OUT) end
	self:StepScene(dt)
	self:Pose()
	for _, preview in self.PetPreviews do Style.RotatePetPreview(preview, self.Age) end
	if self.Age >= (self.PreviewRetryAt or 0) then
		self.PreviewRetryAt = self.Age + 1
		self:RefreshModel()
		for preview, id in self.PendingPreviews do
			if Style.PetVisual and Style.PetModels and Style.PetModels:FindFirstChild(id) then
				local model = Style.PetVisual.Create(Style.PetModels, id, preview, 2.3, self.Catalog.Items.Pets[id])
				if model then
					for _, child in preview:GetChildren() do if child:IsA("BasePart") then child:Destroy() end end
					self.PendingPreviews[preview] = nil
				end
			end
		end
	end
	local size = self.Viewport.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 1.5
	self.Camera.FieldOfView = math.clamp(42 / math.min(1, math.max(0.35, aspect)), 42, 80)
end

function LuckyBlockView.Destroy(self: any)
	self:Show(false)
	self:Finish()
	if self.Model then self.Model:Destroy();self.Model = nil end
	self.ModelSource = nil
	for _, child in self.PetsFrame:GetChildren() do
		if child:GetAttribute("LuckyPetCard") then child:Destroy() end
	end
end

return LuckyBlockView

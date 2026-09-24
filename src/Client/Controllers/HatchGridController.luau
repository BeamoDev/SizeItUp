--!strict
-- The hatch reveal for the authored HUD.Frames.HatchReveal that holds only Backdrop, Title, Continue and a HatchContainer
-- (a UIGridLayout plus a Template). Every item being opened gets its own clone of Template:
--   RewardViewport  the box (a lucky block or egg) that spins, then shrinks away and is replaced by the pet
--   sunburst        hidden while hatching, then tinted with the pet's rarity colour and slowly spinning
--   Rarity, Title1  hidden while hatching, then the rarity and "Lvl N Name" of the pet
-- One opening spins the lucky block; ten spin eggs (random ones from ReplicatedStorage.Assets.Eggs).
-- Opening one item makes its cell big (the grid's CellSize becomes {0.6,0},{0.6,0}); ten keep the authored cells.
-- Title always shows "Hatching..." while the boxes open and "OPENED!" afterwards; Continue appears when everything is open.
-- Same interface as HatchController (Start, Step, Stop, Destroy, Reward, PetProgress) so InventoryController drives either.
local Style = require(script.Parent.UIStyle)
local Grid = {}
Grid.__index = Grid

local SPIN_SECONDS = 2.4
local SPIN_TURNS = 3
local POP_SECONDS = 0.7
local REVEAL_STAGGER = 0.12 -- each next pet appears this much later
local DOT_SECONDS = 0.4
local SUNBURST_DEGREES_PER_SECOND = 14
local SUNBURST_OPACITY = 0.6 -- ImageTransparency of the revealed sunburst (light beams), much more transparent
local VIEWPORT_BASE_SCALE = 1.5 -- each reward viewport is shown at 1.5x its authored size
local SINGLE_CELL = UDim2.new(0.6, 0, 0.6, 0)
local TEN_CELL = UDim2.new(0.2, 0, 0.25, 0)
local VIEWPORT_GROW = 0.14 -- each viewport frame slowly grows while its item spins, then snaps back the instant it opens
local VIEWPORT_SNAP_SECONDS = 0.2
local PET_MODEL_EXTENT = 2.5 * 1.5 -- the revealed pet model is shown at 1.5x its previous display size
local SPIN_RATE = 0.35 * 2 -- each revealed pet spins at 2x its previous speed

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
end
local function backIn(t: number): number
	t = math.clamp(t, 0, 1)
	return 2.70158 * t ^ 3 - 1.70158 * t ^ 2
end

-- Reuses or creates the viewport's camera and stand-in box. (Same contract as HatchController.SetupViewport.)
local function setupViewport(viewport: ViewportFrame): Part
	local existing = viewport:FindFirstChild("RewardCamera")
	local camera = Style.Node(viewport, "RewardCamera", "Camera")
	if not existing then camera.CFrame, camera.FieldOfView = CFrame.new(0, 0, 7), 40 end
	viewport.CurrentCamera = camera
	local egg = Style.Node(viewport, "RewardModel", "Part")
	egg.Anchored, egg.Material = true, Enum.Material.SmoothPlastic
	egg.CanCollide, egg.CanTouch, egg.CanQuery = false, false, false
	egg.Transparency = 0
	return egg
end

local function clickable(node: Instance): GuiButton
	local button = if node:IsA("GuiButton") then node else node:FindFirstChildWhichIsA("GuiButton", true)
	assert(button, "Missing authored UI: " .. node:GetFullName() .. " (a button)")
	return button :: GuiButton
end

-- Whether this HatchReveal frame is the new grid layout.
function Grid.Matches(frame: Instance?): boolean
	return frame ~= nil and frame:FindFirstChild("HatchContainer") ~= nil
end

function Grid.new(playerGui: PlayerGui, starterGui: any, catalog: any, shop: any, equip: any)
	local UI = Style.Authoring
	local need = UI.Need
	local root = need(UI.Overlays, "HatchReveal", "GuiObject")
	local container = need(root, "HatchContainer", "GuiObject")
	local layout = need(container, "UIGridLayout", "UIGridLayout")
	local template = need(container, "Template", "GuiObject")
	local self: any = setmetatable({
		Gui = root, PlayerGui = playerGui, StarterGui = starterGui, Catalog = catalog, Shop = shop, Equip = equip,
		Container = container, Layout = layout, Template = template, Title = need(root, "Title", "TextLabel"),
		Continue = clickable(need(root, "Continue", "GuiObject")), ContinueRoot = root:FindFirstChild("Continue"),
		DefaultCell = layout.CellSize, Cells = {}, Hidden = {}, Core = {}, PetProgress = {},
	}, Grid)
	template.Visible = false
	Style.SetEnabled(root, false)
	self.Continue.Visible = false
	self.Connections = { self.Continue.Activated:Connect(function() if self.Done then self:Stop() end end) }
	return self
end

-- The egg models a multi-opening spins (Assets.Eggs: Common, Uncommon, Exquisite ...), in a stable order.
function Grid.EggSources(self: any): {Instance}
	local assets = Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local eggs = assets and assets:FindFirstChild("Eggs")
	local list = {}
	if eggs then
		for _, child in eggs:GetChildren() do
			if child:IsA("Model") or child:IsA("BasePart") then table.insert(list, child) end
		end
		table.sort(list, function(a, b) return a.Name < b.Name end)
	end
	return list
end

-- Every clone: its viewport, box, and the labels/sunburst that belong to it.
function Grid.BuildCell(self: any, index: number, reward: any, petId: string, eggs: {Instance}?)
	local clone = self.Template:Clone()
	clone.Name = "Hatch" .. index
	clone.Visible = true
	if clone:IsA("GuiObject") then clone.LayoutOrder = index end
	local viewport = clone:FindFirstChild("RewardViewport")
	local sunburst = clone:FindFirstChild("sunburst")
	local rarity, title = clone:FindFirstChild("Rarity"), clone:FindFirstChild("Title1")
	local cell: any = { Node = clone, PetId = petId, Viewport = viewport, Sunburst = sunburst, Rarity = rarity, Title = title, Revealed = false }
	if sunburst and sunburst:IsA("ImageLabel") then sunburst.ImageTransparency = 1 end
	if rarity and rarity:IsA("TextLabel") then rarity.Visible = false end
	if title and title:IsA("TextLabel") then title.Visible = false end
	if viewport and viewport:IsA("ViewportFrame") then
		cell.Egg = setupViewport(viewport)
		-- Shown at 1.5x its authored size (a separate, constant UIScale) with a second UIScale on top for the "slowly
		-- grows while spinning, snaps back on reveal" touch -- multiple UIScales on one object multiply together.
		local base = viewport:FindFirstChild("RewardViewportBaseScale") or Instance.new("UIScale")
		base.Name, base.Scale, base.Parent = "RewardViewportBaseScale", VIEWPORT_BASE_SCALE, viewport
		cell.ViewportScale = viewport:FindFirstChild("RewardViewportScale") or Instance.new("UIScale")
		cell.ViewportScale.Name, cell.ViewportScale.Parent = "RewardViewportScale", viewport
		local container = self.Shop.Containers[reward.Container or "Egg"]
		local shape = if container then container.Shape else "Egg"
		cell.Egg.Shape = if shape == "Egg" then Enum.PartType.Ball else Enum.PartType.Block
		cell.Egg.Size = if shape == "Egg" then Vector3.new(2.4, 3, 2.4) else Vector3.one * 2.5
		cell.Egg.Color = if shape == "Egg" then Color3.fromRGB(255, 236, 174) else Style.Purple
		cell.BaseSize = cell.Egg.Size
		-- Mystery blocks show their real lucky block design instead of the plain cube.
		local design = shape == "Block" and self.Shop.BlockPreviewModels and self.Shop.BlockPreviewModels[reward.Container or ""]
		local assets = design and Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
		local pack = assets and assets:FindFirstChild("LuckyBlocks")
		local source = pack and pack:FindFirstChild(design)
		-- Several at once open eggs instead of blocks.
		if eggs and #eggs > 0 then source = eggs[math.random(#eggs)] end
		if source and Style.BlockVisual then
			cell.BoxModel = Style.BlockVisual.Create(source, viewport)
			if cell.BoxModel then cell.Egg.Transparency = 1;cell.BoxScale = cell.BoxModel:GetScale() end
		end
	end
	clone.Parent = self.Container
	return cell
end

function Grid.Start(self: any, reward: any, progress: any?)
	self:Stop()
	self.Reward, self.Age, self.Done = reward, 0, false
	self.PetProgress = progress or {}
	Style.Play("SpinStart")
	for _, gui in Style.Roots(self.PlayerGui) do
		if (gui:IsA("ScreenGui") or gui:IsA("GuiObject")) and gui ~= self.Gui then self.Hidden[gui] = Style.IsEnabled(gui);Style.SetVisible(gui, false) end
	end
	for _, kind in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health } do
		pcall(function() self.Core[kind] = self.StarterGui:GetCoreGuiEnabled(kind);self.StarterGui:SetCoreGuiEnabled(kind, false) end)
	end
	local pets = reward.Pets or { reward.PetId }
	local eggs = if #pets > 1 then self:EggSources() else nil
	-- One item fills a big cell; several keep the authored cells.
	self.Layout.CellSize = if #pets == 1 then SINGLE_CELL elseif #pets == 10 then TEN_CELL else self.DefaultCell
	for index, petId in pets do table.insert(self.Cells, self:BuildCell(index, reward, petId, eggs)) end
	self.Title.Text = "Hatching."
	self.Continue.Visible = false
	if self.ContinueRoot and self.ContinueRoot:IsA("GuiObject") then self.ContinueRoot.Visible = false end
	Style.SetEnabled(self.Gui, true)
end

function Grid.Reveal(self: any, cell: any)
	cell.Revealed = true
	if cell.BoxModel then cell.BoxModel:Destroy();cell.BoxModel = nil end
	local item = self.Catalog.Items.Pets[cell.PetId]
	if not item then return end
	if cell.Egg then
		cell.Egg.Shape, cell.Egg.Color = Enum.PartType.Block, Color3.fromRGB(table.unpack(item.Color))
		if Style.PetVisual and cell.Viewport then
			cell.PetModel = Style.PetVisual.Create(Style.PetModels, cell.PetId, cell.Viewport, PET_MODEL_EXTENT, item)
			if cell.PetModel then cell.Egg.Transparency = 1;cell.PetScale = cell.PetModel:GetScale() end
		end
	end
	local look = self.Catalog.PetRarityStyles[item.Rarity] or self.Catalog.PetRarityStyles.Common
	cell.Look = look
	if cell.Rarity and cell.Rarity:IsA("TextLabel") then
		Style.RarityLabel(cell.Rarity, item.Rarity, self.Catalog.PetRarityStyles)
		cell.Rarity.Visible = true
	end
	if cell.Title and cell.Title:IsA("TextLabel") then
		-- Just the pet's own name here (no "Lvl N" prefix), unlike PetDisplayName elsewhere.
		local name: string = item.Name
		cell.Title.Text = (name:gsub("^Evolved%s+", ""))
		Style.PetRarity(cell.Title, item)
		cell.Title.Visible = true
	end
	if cell.Sunburst and cell.Sunburst:IsA("ImageLabel") then
		cell.Sunburst.ImageColor3 = Color3.fromRGB(table.unpack(look.Tint))
		cell.Sunburst.ImageTransparency = SUNBURST_OPACITY
	end
end

function Grid.Step(self: any, dt: number)
	if not self.Reward then return end
	self.Age += dt
	local age = self.Age
	local hatchSeconds = Style.Pacing.HatchSeconds
	if age < hatchSeconds then
		self.Title.Text = "Hatching" .. string.rep(".", math.floor(age / DOT_SECONDS) % 3 + 1)
		-- Three full turns that start and end slowly, then every box shrinks away.
		local angle = smooth(age / SPIN_SECONDS) * SPIN_TURNS * math.pi * 2
		local scale = backOut(age / 0.35)
		if age > SPIN_SECONDS then scale *= 1 - backIn((age - SPIN_SECONDS) / (hatchSeconds - SPIN_SECONDS)) end
		scale = math.max(scale, 0.001)
		for _, cell in self.Cells do
			if cell.BoxModel then cell.BoxModel:ScaleTo(cell.BoxScale * scale);cell.BoxModel:PivotTo(CFrame.Angles(0, angle, 0))
			elseif cell.Egg then cell.Egg.Size = cell.BaseSize * scale;cell.Egg.CFrame = CFrame.Angles(0, angle, 0) end
			if cell.ViewportScale then cell.ViewportScale.Scale = 1 + VIEWPORT_GROW * math.clamp(age / hatchSeconds, 0, 1) end
		end
		return
	end
	local t = age - hatchSeconds
	local allRevealed = true
	for index, cell in self.Cells do
		local local_t = t - (index - 1) * REVEAL_STAGGER
		if local_t < 0 then
			allRevealed = false
			if cell.Egg then cell.Egg.Size = Vector3.one * 0.001 end
			continue
		end
		if not cell.Revealed then Style.Play("EggOpen");self:Reveal(cell) end
		if cell.ViewportScale then cell.ViewportScale.Scale = 1 + VIEWPORT_GROW * (1 - math.clamp(local_t / VIEWPORT_SNAP_SECONDS, 0, 1)) end
		local pop = math.max(backOut(local_t / POP_SECONDS), 0.001)
		if cell.Egg then
			cell.Egg.Size = Vector3.one * 2.5 * pop
			cell.Egg.CFrame = CFrame.Angles(0, local_t * SPIN_RATE, 0)
			if cell.PetModel then cell.PetModel:ScaleTo(cell.PetScale * pop);cell.PetModel:PivotTo(cell.Egg.CFrame) end
		end
		if Style.PetVisual and Style.PetVisual.Step then
			if cell.PetModel then Style.PetVisual.Step(cell.PetModel, local_t, true) end
			if cell.Title and Style.PetVisual.StepLabel then Style.PetVisual.StepLabel(cell.Title, local_t) end
			if cell.Rarity and Style.PetVisual.StepLabel then Style.PetVisual.StepLabel(cell.Rarity, local_t) end
		end
		-- The sunburst turns slowly (Mythic cycles through the rainbow).
		if cell.Sunburst and cell.Sunburst:IsA("ImageLabel") then
			cell.Sunburst.Rotation = (local_t * SUNBURST_DEGREES_PER_SECOND) % 360
			if cell.Look and cell.Look.Rainbow then cell.Sunburst.ImageColor3 = Color3.fromHSV((local_t * 0.15) % 1, 0.6, 1) end
		end
		if local_t < POP_SECONDS then allRevealed = false end
	end
	if allRevealed and not self.Done then
		self.Done = true
		self.Title.Text = "OPENED!"
		self.Continue.Visible = true
		if self.ContinueRoot and self.ContinueRoot:IsA("GuiObject") then self.ContinueRoot.Visible = true end
	end
end

function Grid.Stop(self: any)
	for _, cell in self.Cells do
		if cell.PetModel then cell.PetModel:Destroy() end
		if cell.BoxModel then cell.BoxModel:Destroy() end
		cell.Node:Destroy()
	end
	table.clear(self.Cells)
	self.Layout.CellSize = self.DefaultCell
	self.Reward, self.Done = nil, false
	Style.SetEnabled(self.Gui, false)
	for gui, enabled in self.Hidden do
		if gui.Parent then
			local requested = gui:GetAttribute("RuntimeEnabled")
			Style.SetVisible(gui, if requested ~= nil then requested else enabled)
		end
	end
	table.clear(self.Hidden)
	for kind, enabled in self.Core do pcall(function() self.StarterGui:SetCoreGuiEnabled(kind, enabled) end) end
	table.clear(self.Core)
end

function Grid.Destroy(self: any)
	self:Stop()
	for _, connection in self.Connections do connection:Disconnect() end
	Style.Dispose(self.Gui)
end

return Grid

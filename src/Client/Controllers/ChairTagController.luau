--!strict
-- Styles and updates the authored tag on every shop chair (Workspace.Game.Interactables.Chairs.Chairs.<Name>.Tag):
--   ChairName  "Glass Chair", coloured by the chair, with an animated effect on the exclusive ones
--   Price      this player's own view: the price until they own it, then "Owned"
-- Purely local. The server only marks each chair model with ChairShopId and sets default text.
local ChairTagController = {}
ChairTagController.__index = ChairTagController

local SCAN_SECONDS = 2
-- Exclusive chairs: colour-shifting or shimmering name text. Anything else gets a plain rarity colour.
local EFFECTS: { [string]: any } = {
	Moon = { Kind = "Gradient", Base = { 225, 140, 70 }, Speed = 1.1 },
	Throne = { Kind = "Gradient", Base = { 255, 205, 45 }, Speed = 1.6 },
	RGB = { Kind = "Rainbow", Speed = 1.3 },
	Electric = { Kind = "Electric" },
}

local function tint(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end
local function threeStop(base: Color3): ColorSequence
	local dark, light = base:Lerp(Color3.new(0, 0, 0), 0.35), base:Lerp(Color3.new(1, 1, 1), 0.65)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, dark),
		ColorSequenceKeypoint.new(0.5, light),
		ColorSequenceKeypoint.new(1, dark),
	})
end
local function rainbow(): ColorSequence
	local keys = {}
	for index = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 0.75, 1)))
	end
	return ColorSequence.new(keys)
end
local function formatPrice(price: number): string
	local reversed = string.reverse(tostring(math.floor(price)))
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	grouped = string.gsub(string.reverse(grouped), "^,", "")
	return "$" .. grouped
end

function ChairTagController.new(
	world: any,
	catalog: any,
	runService: any,
	getState: () -> any,
	clock: (() -> number)?,
	isInGame: (() -> boolean)?
)
	local self: any = setmetatable(
		{
			World = world,
			Catalog = catalog,
			GetState = getState,
			IsInGame = isInGame,
			Clock = clock or os.clock,
			Entries = {},
			InGame = false,
			ScanTimer = SCAN_SECONDS,
		},
		ChairTagController
	)
	self.Connection = runService.Heartbeat:Connect(function(dt: number)
		self:Step(dt)
	end)
	return self
end

-- Chair outlines and floating shop tags remain authored objects. Capture their current state when gameplay begins
-- so locally hiding them never overwrites an intentionally disabled authored visual.
function ChairTagController.RegisterVisuals(self: any, entry: any, model: any)
	entry.Visuals = entry.Visuals or {}
	entry.HiddenVisuals = entry.HiddenVisuals or {}
	local function register(descendant: any)
		if descendant:IsA("Highlight") or descendant:IsA("BillboardGui") then
			entry.Visuals[descendant] = true
			if self.InGame and entry.HiddenVisuals[descendant] == nil then
				entry.HiddenVisuals[descendant] = descendant.Enabled
				descendant.Enabled = false
			end
		end
	end
	for _, descendant in model:GetDescendants() do
		register(descendant)
	end
	entry.VisualAdded = entry.VisualAdded or model.DescendantAdded:Connect(register)
end

function ChairTagController.SetInGame(self: any, inGame: boolean)
	if self.InGame == inGame then
		return
	end
	self.InGame = inGame
	for model, entry in self.Entries do
		self:RegisterVisuals(entry, model)
		if inGame then
			for visual in entry.Visuals do
				if visual.Parent and entry.HiddenVisuals[visual] == nil then
					entry.HiddenVisuals[visual] = visual.Enabled
					visual.Enabled = false
				end
			end
		else
			for visual, wasEnabled in entry.HiddenVisuals do
				if visual.Parent then
					visual.Enabled = wasEnabled
				end
			end
			table.clear(entry.HiddenVisuals)
		end
	end
end

function ChairTagController.Track(self: any, model: any)
	local existing = self.Entries[model]
	if existing then
		return
	end
	local id = model:GetAttribute("ChairShopId")
	local item = type(id) == "string" and self.Catalog.Items.Chairs[id]
	local tag = model:FindFirstChild("Tag")
	local nameLabel = tag and tag:FindFirstChild("ChairName", true)
	local priceLabel = tag and tag:FindFirstChild("Price", true)
	if not item or not nameLabel or not priceLabel then
		return
	end
	local entry: any = {
		Id = id,
		Item = item,
		Name = nameLabel,
		Price = priceLabel,
		Effect = EFFECTS[id],
		Phase = #self.Entries * 0.7,
	}
	nameLabel.Text = item.Name .. " Chair"
	local effect = entry.Effect
	if effect and (effect.Kind == "Gradient" or effect.Kind == "Rainbow") then
		local gradient = nameLabel:FindFirstChild("ChairGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "ChairGradient"
			gradient.Parent = nameLabel
		end
		gradient.Color = if effect.Kind == "Rainbow" then rainbow() else threeStop(tint(effect.Base))
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		entry.Gradient = gradient
	elseif not effect then
		nameLabel.TextColor3 = tint(item.Color)
	end
	-- The optional Tag.Rarity label shows the chair's rarity (COMMON ... MYTHIC) in that rarity's gradient; Mythic cycles rainbow.
	local rarityLabel = tag:FindFirstChild("Rarity", true)
	local style = self.Catalog.PetRarityStyles and self.Catalog.PetRarityStyles[item.Rarity]
	if rarityLabel and rarityLabel:IsA("TextLabel") and style then
		rarityLabel.Text = string.upper(item.Rarity)
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		local gradient = rarityLabel:FindFirstChildWhichIsA("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "RarityGradient"
			gradient.Parent = rarityLabel
		end
		gradient.Color = if item.Rarity == "Mythic"
			then rainbow()
			else ColorSequence.new({
				ColorSequenceKeypoint.new(0, tint(style.Tint)),
				ColorSequenceKeypoint.new(1, tint(style.Accent)),
			})
		entry.RarityGradient, entry.RarityMythic = gradient, item.Rarity == "Mythic"
	end
	self.Entries[model] = entry
	self:RegisterVisuals(entry, model)
end

function ChairTagController.Scan(self: any)
	local gameRoot = self.World:FindFirstChild("Game")
	local interactables = gameRoot and gameRoot:FindFirstChild("Interactables")
	local root = (interactables and interactables:FindFirstChild("Chairs"))
		or (gameRoot and gameRoot:FindFirstChild("Chairs"))
		or self.World:FindFirstChild("Chairs")
	if root then
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Model") and descendant:GetAttribute("ChairShopId") ~= nil then
				self:Track(descendant)
			end
		end
	end
	for model in self.Entries do
		if not model.Parent then
			local entry = self.Entries[model]
			if entry.VisualAdded then entry.VisualAdded:Disconnect() end
			self.Entries[model] = nil
		end
	end
end

function ChairTagController.Step(self: any, dt: number)
	self.ScanTimer += dt
	if self.ScanTimer >= SCAN_SECONDS then
		self.ScanTimer = 0
		self:Scan()
	end
	local inGame = self.IsInGame ~= nil and self.IsInGame() == true
	self:SetInGame(inGame)
	local state = self.GetState()
	local now = self.Clock()
	for _, entry in self.Entries do
		if state and state.Owned and state.Owned.Chairs then
			local owned = state.Owned.Chairs[entry.Id] ~= nil
			if entry.Owned ~= owned then
				entry.Owned = owned
				entry.Price.Text = if owned then "Owned" else formatPrice(entry.Item.Price)
			end
		end
		if entry.RarityMythic then
			-- The rainbow rarity slowly rotates through the colour wheel.
			entry.RarityGradient.Rotation = (now * 40) % 360
		end
		local effect = entry.Effect
		if effect then
			if entry.Gradient then
				-- Sine ping-pong: the bright band glides across and eases at each end.
				entry.Gradient.Offset = Vector2.new(math.sin(now * effect.Speed + entry.Phase), 0)
			elseif effect.Kind == "Electric" then
				-- Irregular crackle between hot yellow and white, with a blue-white glow on the outline.
				local flicker = math.abs(math.sin(now * 23 + entry.Phase)) * math.abs(math.sin(now * 7.3))
				entry.Name.TextColor3 = Color3.fromRGB(255, 225, 40)
					:Lerp(Color3.new(1, 1, 1), if flicker > 0.6 then 1 else flicker)
				entry.Name.TextStrokeColor3 = Color3.fromRGB(20, 40, 120):Lerp(Color3.fromRGB(120, 200, 255), flicker)
			end
		end
	end
end

function ChairTagController.Destroy(self: any)
	self:SetInGame(false)
	self.Connection:Disconnect()
	for _, entry in self.Entries do
		if entry.VisualAdded then entry.VisualAdded:Disconnect() end
	end
	table.clear(self.Entries)
end

return ChairTagController

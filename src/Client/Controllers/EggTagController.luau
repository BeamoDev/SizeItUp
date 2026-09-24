--!strict
-- Styles the EggName label on each authored egg stand (Workspace.Game.Interactables.Eggs.<Egg>.Tag.EggName). Purely local: it only
-- sets text colour, a UIGradient and a UIStroke on that label, never positions or sizes.
--   Starter (Common Egg)      a bland, plain grey-white name
--   Lucky (Uncommon Egg)      green, with a bright shine sweeping across it
--   Secret (Exquisite Egg)    a colour-shifting cosmic gradient, a pulsing glow outline and a sweeping shine
local EggTagController = {}
EggTagController.__index = EggTagController

local SCAN_SECONDS = 2
local SHINE_SECONDS = 2.2
local BLAND = Color3.fromRGB(200, 205, 214)
local GREEN, GREEN_LIGHT = Color3.fromRGB(46, 200, 84), Color3.fromRGB(170, 255, 175)

local function tint(item: Instance, name: string, class: string): any
	local existing = item:FindFirstChild(name)
	if existing and existing:IsA(class) then return existing end
	local created = Instance.new(class)
	created.Name = name
	created.Parent = item
	return created
end

-- A base colour with a narrow bright band that sweeps across as Offset moves from -1 to 1.
local function shineSequence(base: Color3, light: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base), ColorSequenceKeypoint.new(0.4, base), ColorSequenceKeypoint.new(0.5, light),
		ColorSequenceKeypoint.new(0.6, base), ColorSequenceKeypoint.new(1, base),
	})
end
-- A wide, repeating colour wheel that slides across the text.
local function cosmic(phase: number): ColorSequence
	local keys = {}
	for index = 0, 6 do
		local hue = (0.72 + index / 6 * 0.55 + phase) % 1
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(hue, 0.7, 1)))
	end
	return ColorSequence.new(keys)
end

function EggTagController.new(world: any, runService: any, clock: (() -> number)?)
	local self: any = setmetatable({ World = world, Clock = clock or os.clock, Entries = {}, ScanTimer = 0 }, EggTagController)
	self.Connection = runService.Heartbeat:Connect(function(dt: number) self:Step(dt) end)
	return self
end

function EggTagController.Track(self: any, model: any)
	if self.Entries[model] then return end
	local shopId = model:GetAttribute("PetShopId")
	local tag = model:FindFirstChild("Tag")
	local label = tag and tag:FindFirstChild("EggName", true)
	if type(shopId) ~= "string" or not label or not label:IsA("TextLabel") then return end
	local entry: any = { Label = label, Shop = shopId }
	if shopId == "Starter" then
		label.TextColor3 = BLAND
	elseif shopId == "Lucky" then
		label.TextColor3 = Color3.new(1, 1, 1)
		entry.Gradient = tint(label, "EggShine", "UIGradient")
		entry.Gradient.Color = shineSequence(GREEN, GREEN_LIGHT)
	elseif shopId == "Secret" then
		label.TextColor3 = Color3.new(1, 1, 1)
		entry.Gradient = tint(label, "EggCosmic", "UIGradient")
		entry.Stroke = tint(label, "EggGlow", "UIStroke")
		entry.Stroke.Color, entry.Stroke.Thickness = Color3.fromRGB(150, 70, 255), 2
	end
	self.Entries[model] = entry
end

function EggTagController.Step(self: any, dt: number)
	self.ScanTimer -= dt
	if self.ScanTimer <= 0 then
		self.ScanTimer = SCAN_SECONDS
		local game = self.World:FindFirstChild("Game")
		local interactables = game and game:FindFirstChild("Interactables")
		local eggs = (interactables and interactables:FindFirstChild("Eggs")) or (game and game:FindFirstChild("Eggs"))
		if eggs then for _, model in eggs:GetChildren() do self:Track(model) end end
	end
	local time = self.Clock()
	for model, entry in self.Entries do
		if not model.Parent or not entry.Label.Parent then
			self.Entries[model] = nil
			continue
		end
		if entry.Shop == "Lucky" then
			-- One shine sweep every couple of seconds, then a short rest.
			local sweep = (time % (SHINE_SECONDS * 1.5)) / SHINE_SECONDS
			entry.Gradient.Offset = Vector2.new(math.clamp(-1 + sweep * 2, -1, 1), 0)
		elseif entry.Shop == "Secret" then
			entry.Gradient.Color = cosmic(time * 0.12)
			entry.Gradient.Rotation = 15 * math.sin(time * 1.4)
			entry.Stroke.Thickness = 2 + 1.5 * (0.5 + 0.5 * math.sin(time * 3))
			entry.Stroke.Color = Color3.fromHSV((0.72 + time * 0.08) % 1, 0.75, 1)
		end
	end
end

function EggTagController.Destroy(self: any)
	self.Connection:Disconnect()
	for _, entry in self.Entries do
		if entry.Gradient then entry.Gradient:Destroy() end
		if entry.Stroke then entry.Stroke:Destroy() end
	end
	self.Entries = {}
end

return EggTagController

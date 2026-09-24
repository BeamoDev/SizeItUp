--!strict
-- A small, occasional attention cue for the hint button. The caller steps it from the
-- existing HUD render loop so it does not create another RenderStepped connection.
local HintWobble = {}
HintWobble.__index = HintWobble

local FIRST_DELAY_MIN = 3.5
local FIRST_DELAY_MAX = 5.5
local REPEAT_DELAY_MIN = 8
local REPEAT_DELAY_MAX = 13
local DURATION = 0.72
local ROTATION_DEGREES = 6.5
local SCALE_AMOUNT = 0.055

local function randomDelay(random: Random, first: boolean): number
	return if first
		then random:NextNumber(FIRST_DELAY_MIN, FIRST_DELAY_MAX)
		else random:NextNumber(REPEAT_DELAY_MIN, REPEAT_DELAY_MAX)
end

function HintWobble.new(target: GuiObject)
	local scale = target:FindFirstChild("HintWobbleScale")
	local owned = false
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "HintWobbleScale"
		scale.Parent = target
		owned = true
	end
	assert(scale:IsA("UIScale"), "HintWobbleScale must be a UIScale")

	local random = Random.new()
	return setmetatable({
		Target = target,
		Scale = scale,
		OwnedScale = owned,
		BaseRotation = target.Rotation,
		Random = random,
		Enabled = false,
		Elapsed = nil,
		Delay = randomDelay(random, true),
		Direction = 1,
	}, HintWobble)
end

function HintWobble.Reset(self: any)
	self.Elapsed = nil
	if self.Target.Parent then
		self.Target.Rotation = self.BaseRotation
	end
	if self.Scale.Parent then
		self.Scale.Scale = 1
	end
end

function HintWobble.SetEnabled(self: any, enabled: boolean)
	if self.Enabled == enabled then
		return
	end
	self.Enabled = enabled
	self:Reset()
	self.Delay = randomDelay(self.Random, enabled)
end

function HintWobble.Step(self: any, dt: number)
	local target = self.Target
	if not self.Enabled or not target.Parent or not target.Visible then
		self:Reset()
		return
	end

	dt = math.clamp(dt, 0, 1 / 15)
	if self.Elapsed == nil then
		self.Delay -= dt
		if self.Delay > 0 then
			return
		end
		self.Elapsed = 0
		self.Direction = if self.Random:NextInteger(0, 1) == 0 then -1 else 1
	end

	self.Elapsed += dt
	local progress = math.clamp(self.Elapsed / DURATION, 0, 1)
	-- The sine envelope starts and finishes exactly at the authored pose. Four small
	-- swings make it readable without the button looking shaky or demanding attention.
	local envelope = math.sin(math.pi * progress)
	local swing = math.sin(math.pi * 4 * progress) * envelope
	target.Rotation = self.BaseRotation + self.Direction * ROTATION_DEGREES * swing
	self.Scale.Scale = 1 + SCALE_AMOUNT * envelope * envelope

	if progress >= 1 then
		self:Reset()
		self.Delay = randomDelay(self.Random, false)
	end
end

function HintWobble.Destroy(self: any)
	self.Enabled = false
	self:Reset()
	if self.OwnedScale and self.Scale.Parent then
		self.Scale:Destroy()
	end
end

return HintWobble

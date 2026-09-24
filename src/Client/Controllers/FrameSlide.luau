--!strict
-- Slides an authored overlay frame up from the bottom of the screen when it opens and back down and out when it
-- closes (or another frame takes over). The frame rests exactly where it was authored; Step drives the motion and
-- hides the frame only once it has fully left the screen.
local Style = require(script.Parent.UIStyle)
local Slide = {}
Slide.__index = Slide

local IN_SECONDS, OUT_SECONDS = 0.55, 0.4

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 4
end

function Slide.new(root: GuiObject)
	local authored = Style.Authoring
	local rest = if authored and authored.Pose then authored.Pose(root).Position else root.Position
	return setmetatable({ Root = root, Rest = rest, Presence = 0, Open = false }, Slide)
end

function Slide.Apply(self: any)
	local rest = self.Rest
	-- A full parent height below its resting place is always off screen.
	self.Root.Position = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale + (1 - ease(self.Presence)), rest.Y.Offset)
end

-- Starts (or reverses into) opening; it appears at the bottom and rises.
function Slide.Show(self: any)
	if self.Open then return end
	self.Open = true
	Style.SetEnabled(self.Root, true)
	self:Apply()
end

function Slide.Hide(self: any) self.Open = false end

-- Whether the frame is on screen at all, including while it slides away.
function Slide.IsActive(self: any): boolean return self.Open or self.Presence > 0 end

function Slide.Step(self: any, dt: number)
	if not self:IsActive() then return end
	self.Presence = math.clamp(self.Presence + (if self.Open then dt / IN_SECONDS else -dt / OUT_SECONDS), 0, 1)
	self:Apply()
	if not self.Open and self.Presence <= 0 then Style.SetEnabled(self.Root, false) end
end

-- Snaps closed at its resting position (teardown).
function Slide.Reset(self: any)
	self.Open, self.Presence = false, 0
	self.Root.Position = self.Rest
	Style.SetEnabled(self.Root, false)
end

return Slide

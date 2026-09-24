--!strict
-- The authored HUD.PurchaseOverlay (a Frame) and its LoadingCircle (an ImageLabel): shown for any Robux purchase attempt,
-- from the moment the request is sent until the server confirms it (or a Roblox purchase prompt closes, or a short
-- failsafe elapses). Backdrop fades 1 -> 0.2 transparency and the circle fades 1 -> 0 while spinning; both reverse the
-- same way on hide. Purely presentational: it never blocks or changes the purchase itself. Optional -- nil when the
-- overlay is not authored.
local FADE_SECONDS = 0.35
local SPIN_DEGREES_PER_SECOND = 220
local FAILSAFE_SECONDS = 8 -- in case nothing ever confirms (e.g. a lost purchase-finished event)

local PurchaseOverlay = {}
PurchaseOverlay.__index = PurchaseOverlay

function PurchaseOverlay.new(hud: Instance?): any?
	local root = hud and hud:FindFirstChild("PurchaseOverlay")
	local circle = root and root:FindFirstChild("LoadingCircle")
	if not (root and root:IsA("GuiObject") and circle and circle:IsA("ImageLabel")) then return nil end
	root.Visible = false
	circle.ImageTransparency = 1
	return setmetatable({ Root = root, Circle = circle, Wanted = false, Amount = 0, Rotation = 0, Age = 0 }, PurchaseOverlay)
end

function PurchaseOverlay.Show(self: any)
	self.Wanted, self.Age = true, 0
	self.Root.Visible = true
end

function PurchaseOverlay.Hide(self: any)
	self.Wanted = false
end

function PurchaseOverlay.Step(self: any, dt: number)
	dt = math.max(0, dt)
	if self.Wanted then self.Age += dt end
	if self.Wanted and self.Age >= FAILSAFE_SECONDS then self.Wanted = false end
	local goal = if self.Wanted then 1 else 0
	self.Amount = math.clamp(self.Amount + (goal - self.Amount) * math.min(1, dt / FADE_SECONDS), 0, 1)
	if math.abs(goal - self.Amount) < 1e-3 then self.Amount = goal end
	self.Root.BackgroundTransparency = 1 - self.Amount * 0.8
	self.Circle.ImageTransparency = 1 - self.Amount
	if self.Amount > 0 then
		self.Rotation = (self.Rotation + dt * SPIN_DEGREES_PER_SECOND) % 360
		self.Circle.Rotation = self.Rotation
	end
	self.Root.Visible = self.Amount > 0 or self.Wanted
end

function PurchaseOverlay.Destroy(self: any)
	self.Wanted, self.Amount = false, 0
	self.Root.Visible = false
	self.Root.BackgroundTransparency, self.Circle.ImageTransparency = 1, 1
end

return PurchaseOverlay

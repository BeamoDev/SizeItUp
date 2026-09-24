--!strict
-- Thin wrapper around HapticService for the resize "juice": a short pulse on an input device that supports it (mainly
-- gamepads today). Every call is guarded; a platform without haptics does nothing. Never required -- MatchController
-- works fine with no Haptic dependency at all.
local HapticFeedback = {}
HapticFeedback.__index = HapticFeedback

local INPUTS = { Enum.UserInputType.Gamepad1, Enum.UserInputType.Gamepad2, Enum.UserInputType.Gamepad3, Enum.UserInputType.Gamepad4 }
local MOTOR = Enum.VibrationMotor.Large

function HapticFeedback.new(hapticService: any?): any
	return setmetatable({ Service = hapticService }, HapticFeedback)
end

-- strength: 0-1. Fires and forgets; a later pulse simply restarts the short decay.
function HapticFeedback.Pulse(self: any, strength: number, seconds: number?)
	local service = self.Service
	if not service then return end
	local duration = seconds or 0.08
	for _, input in INPUTS do
		local ok, supported = pcall(function() return service:IsVibrationSupported(input) and service:IsMotorSupported(input, MOTOR) end)
		if ok and supported then
			pcall(function() service:SetMotor(input, MOTOR, math.clamp(strength, 0, 1)) end)
			task.delay(duration, function() pcall(function() service:SetMotor(input, MOTOR, 0) end) end)
		end
	end
end

function HapticFeedback.Destroy(self: any)
	local service = self.Service
	if not service then return end
	for _, input in INPUTS do pcall(function() service:SetMotor(input, MOTOR, 0) end) end
end

return HapticFeedback

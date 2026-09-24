--!strict
local PrizeRoll = {}
-- hold: seconds at the end spent resting on the real prize (defaults to the last quarter).
function PrizeRoll.Amount(prize: number, elapsed: number, duration: number, hold: number?): number
	local flicker = math.max(0.01, duration - (hold or duration * 0.25))
	local progress = math.clamp(elapsed / flicker, 0, 1)
	if progress >= 1 then return prize end
	local values = { 100, 500, 200, 1000, 150, 750, 350, 250 }
	-- Four changes per second of flicker (12 over the old 3s, 18 over today's 4.5s), easing out onto the prize, so a
	-- longer flicker keeps the same lively pace instead of just slowing down.
	local changes = math.max(1, math.floor(flicker * 4 + 0.5))
	local step = math.floor(changes * (1 - (1 - progress) ^ 3))
	return values[(step * 5 + prize) % #values + 1]
end
return PrizeRoll

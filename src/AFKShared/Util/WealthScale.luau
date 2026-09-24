--!strict
-- Rewards that grow with how much Cash a player already holds, so they still tempt rich players, but much more slowly
-- than their wealth so the economy stays balanced. Identical copies live in Shared/Util and AFKShared/Util.
-- Two curves (pass the curve name):
--   AFK      AFK world Cash/Gem prizes: paid every 30-60s, so gentle. Base up to $25,000 held, then each 10x more
--            Cash is about 2.2x the prize, capped at 8x (so AFK never out-earns playing matches).
--   Invite   the friend invite reward: rare and brings new players, so generous. Base up to $5,000 held, then each
--            10x more Cash is about 3.2x the reward, capped at 25x.
-- Gems use the square root of the Cash scale on either curve (Gems are also sold for Robux).
local Wealth = {}
Wealth.Curves = {
	AFK = { Reference = 25000, Exponent = 0.35, MaxScale = 8 },
	Invite = { Reference = 5000, Exponent = 0.5, MaxScale = 25 },
}

function Wealth.Scale(cash: number?, curve: string?): number
	local shape = Wealth.Curves[curve or "AFK"] or Wealth.Curves.AFK
	local held = math.max(tonumber(cash) or 0, shape.Reference)
	return math.clamp((held / shape.Reference) ^ shape.Exponent, 1, shape.MaxScale)
end

function Wealth.GemScale(cash: number?, curve: string?): number
	return math.sqrt(Wealth.Scale(cash, curve))
end

-- A tidy amount: $5 steps under $100, $25 under $1,000, $100 under $10,000, $500 above.
local function tidy(value: number): number
	local step = if value < 100 then 5 elseif value < 1000 then 25 elseif value < 10000 then 100 else 500
	return math.max(step, math.floor(value / step + 0.5) * step)
end

-- The Cash reward for someone holding `cash`: the base amount up to the curve's Reference, then scaled and tidied.
function Wealth.Cash(base: number, cash: number?, curve: string?): number
	local scale = Wealth.Scale(cash, curve)
	return if scale <= 1 then base else tidy(base * scale)
end

-- The Gem reward for someone holding `cash`: never below the base amount.
function Wealth.Gems(base: number, cash: number?, curve: string?): number
	return math.max(base, math.floor(base * Wealth.GemScale(cash, curve) + 0.5))
end

return Wealth

--!strict
-- Only server catalog entries reach Grant. Expirations use wall time, including offline time.
local PotionService = {}
function PotionService.Grant(data: any, product: any, now: number)
	assert(product.Kind == "Potion" and (product.Boost == "Cash" or product.Boost == "Streak" or product.Boost == "Wins"), "Invalid potion")
	assert(type(product.Seconds) == "number" and product.Seconds > 0 and product.Seconds % 1 == 0 and product.Seconds < math.huge, "Invalid potion duration")
	data.Potions[product.Boost] = math.max(now, data.Potions[product.Boost] or 0) + product.Seconds
end
function PotionService.Multiplier(data: any, boost: string, now: number): number
	return if data and data.Potions and (data.Potions[boost] or 0) > now then 2 else 1
end
function PotionService.Snapshot(data: any, now: number)
	return { Now = now, Cash = data.Potions.Cash, Streak = data.Potions.Streak, Wins = data.Potions.Wins }
end
return PotionService

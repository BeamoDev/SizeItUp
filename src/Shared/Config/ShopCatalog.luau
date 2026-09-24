--!strict
-- Zero IDs never prompt purchases. FreeShop grants the displayed packs without Robux.
-- Every ProductId/PassId below is a real, created product (Studio > Monetize). Live: every Product/Pass button
-- now prompts a real Robux purchase for every player.
local catalog = {
	FreeShop = false,
	FreeSteal = false,
	StealCooldownSeconds = 3,
	Products = {
		Cash800 = { Name = "800 Cash", Kind = "Cash", Amount = 800, ProductId = 3714177497 },
		Cash2000 = { Name = "2,000 Cash", Kind = "Cash", Amount = 2000, ProductId = 3714177522 },
		Cash5000 = { Name = "5,000 Cash", Kind = "Cash", Amount = 5000, ProductId = 3714177547 },
		Cash15000 = { Name = "15,000 Cash", Kind = "Cash", Amount = 15000, ProductId = 3714177582 },
		Cash40000 = { Name = "40,000 Cash", Kind = "Cash", Amount = 40000, ProductId = 3714177636 },
		Key1 = { Name = "1 Gem", Kind = "Keys", Amount = 1, ProductId = 3714177655 },
		Key10 = { Name = "10 Gems", Kind = "Keys", Amount = 10, ProductId = 3714177731 },
		Key50 = { Name = "50 Gems", Kind = "Keys", Amount = 50, ProductId = 3714177762 },
		Steal = { Name = "Steal Cash", Kind = "StealCredits", Amount = 1, ProductId = 3714178150 },
		-- A one-time bundle: one Mythic pet, Cash and a 2x Cash potion (EconomyRuntime special-cases the
		-- "GoldenDeal" Id, the same way it already special-cases "VIP", since this grants three things at once).
		GoldenDeal = {
			Name = "Golden Deal",
			Kind = "GoldenDeal",
			Pet = "Helios",
			Cash = 2500,
			PotionBoost = "Cash",
			PotionSeconds = 604800, -- 1 Week
			ProductId = 3714177421,
		},
		-- Heart, Sabotage and Hint credits are saved per profile: a receipt banks one, and the match spends it (buying a
		-- lost heart back, a troll effect, a hint), replaying the request that opened the prompt.
		RefillHeart = { Name = "Refill Heart", Kind = "HeartCredits", Amount = 1, ProductId = 3714177790 },
		Sabotage = { Name = "Sabotage", Kind = "SabotageCredits", Amount = 1, ProductId = 3714178732 },
		Hint = { Name = "Hint", Kind = "HintCredits", Amount = 1, ProductId = 3714178653 },
	},
	Order = { "Cash800", "Cash2000", "Cash5000", "Cash15000", "Cash40000", "Key1", "Key10", "Key50" },
	-- Opening several blocks at once: this many for a price that is this fraction lower than buying them one by one.
	BulkHatch = { Count = 10, Discount = 0.1 },
	BlockOrder = { "Abyssal", "Oceanic", "Solar", "Universal" },
	BlockPreviewModels = { Abyssal="Purple", Oceanic="Red", Solar="Gold", Universal="Grey" }, -- only the Purple, Red, Gold and Grey designs
	Passes = {
		-- Three things: a one-time Cash+Gems bundle, the exclusive Void chair, and permanently 8 pet slots
		-- instead of 6 (InventoryService.petCap reads data.VIP directly, not this table).
		VIP = { Name = "VIP Bundle", PassId = 1990250427, Cash = 2000, Keys = 10, Chair = "Void" },
		-- A modest one-time bundle to convert a first purchase cheaply.
		StarterPack = { Name = "Starter Pack", PassId = 1989542423, Cash = 500, Chair = "Glass" },
		-- Permanent unlocks, granted once and re-checked (UserOwnsGamePassAsync) on join in case the grant was missed.
		Open10 = { Name = "Open 10", PassId = 1988576429 }, -- unlocks the existing BulkHatch (10-at-once) discount path
		TwoXCash = { Name = "2x Cash", PassId = 1988510464 }, -- a permanent match-cash multiplier, stacks with timed Cash potions
	},
	Containers = {
		Egg = { Name = "Starter Egg", Cash = 100, Keys = 0, Shape = "Egg", Weights = { Bunny = 50, Cat = 30, Fox = 15, Dragon = 5 } },
		Lucky = { Name = "Lucky Block", Cash = 250, Keys = 1, Shape = "Block", Weights = { Bunny = 30, Cat = 35, Fox = 25, Dragon = 10 } },
		Secret = { Name = "Secret Block", Cash = 1000, Keys = 2, Shape = "Block", Weights = { Bunny = 10, Cat = 25, Fox = 40, Dragon = 25 } },
	},
}
-- Product IDs stay unconfigured until real developer products are connected.
-- Retain old definitions for presentation compatibility, never new sales.
for _,container in catalog.Containers do container.Retired=true end
for _,pool in {
	{"Abyssal",1500,0,{170,65,240},{"DarkDragon","AbyssDemon","AbyssalCerberus","EvolvedAbyssalHydra"}},
	{"Oceanic",4000,0,{45,210,245},{"OceanicKitty","OceanicStar","OceanicWingedLord","EvolvedOceanicTrio"}},
	{"Solar",0,10,{255,175,30},{"SunCat","SunDoubull","SunFlare","EvolvedSolis"}},
	{"Universal",0,20,{235,75,220},{"UniversalMegalodon","UniversalPhoenix","UniversalLeviathan","EvolvedUniversalYatagarasu"}},
} do
	local weights={}
	for index,id in pool[5] do weights[id]=({60,28,10,2})[index] end
	catalog.Containers[pool[1]]={Name=pool[1].." Mystery Block",Currency=if pool[2]>0 then "Cash" else "Keys",Cash=pool[2],Keys=pool[3],Color=pool[4],Shape="Block",Weights=weights,PetOrder=pool[5]}
end
catalog.PotionOrder = {}
local POTION_PRODUCT_IDS = {
	PotionCashHour = 3714178454, PotionCashDay = 3714178478, PotionCashWeek = 3714178496,
	PotionStreakHour = 3714178345, PotionStreakDay = 3714178367, PotionStreakWeek = 3714178388,
	PotionWinsHour = 3714178264, PotionWinsDay = 3714178286, PotionWinsWeek = 3714178316,
}
for _, boost in { "Cash", "Streak", "Wins" } do
	for _, duration in { { "Hour", "1 Hour", 3600 }, { "Day", "1 Day", 86400 }, { "Week", "1 Week", 604800 } } do
		local id = "Potion" .. boost .. duration[1]
		catalog.Products[id] = { Name = "2x " .. boost .. " / " .. duration[2], Kind = "Potion", Boost = boost, Seconds = duration[3], DurationLabel = duration[2], ProductId = POTION_PRODUCT_IDS[id] or 0 }
		table.insert(catalog.PotionOrder, id)
	end
end
return catalog

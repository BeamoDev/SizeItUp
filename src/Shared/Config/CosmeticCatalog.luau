--!strict
-- Public display data. Purchases and ownership are enforced by the server.
local catalog = {
	RemoteName = "ScaleCosmetics",
	Egg = { Name = "Starter Egg", Price = 100, HatchSeconds = 2.4 },
	PetLevels = { BaseXP = 203, StepXP = 47, MaxLevel = 100, XPPerSecond = 1 },
	Order = {
		Pets = { "Bunny", "Cat", "Fox", "Dragon" },
		Chairs = { "Classic" },
		-- Titles are earned by leveling up (PlayerLevelService.UnlockTitles), lowest level first.
		Titles = {
			"IttyBitty",
			"SquintChampion",
			"NailedIt",
			"RulerRookie",
			"NotEvenClose",
			"BigBrain",
			"ShrinkRay",
			"GiantWhisperer",
			"ScaleWizard",
			"AbsolutelyMassive",
		},
	},
	Items = {
		Pets = {
			Bunny = { Name = "Bunny", Rarity = "Common", Weight = 50, Color = { 240, 185, 220 } },
			Cat = { Name = "Cat", Rarity = "Uncommon", Weight = 30, Color = { 120, 195, 255 } },
			Fox = { Name = "Fox", Rarity = "Rare", Weight = 15, Color = { 255, 155, 65 } },
			Dragon = { Name = "Dragon", Rarity = "Legendary", Weight = 5, Color = { 180, 115, 255 } },
		},
		-- Only the chairs that exist as authored models: the free Basic chair plus the shop stock below.
		Chairs = {
			Classic = { Name = "Classic", Color = { 215, 215, 225 } },
		},
		-- Earned at the player level shown; RewardOnly keeps them out of starter inventories.
		Titles = {
			IttyBitty = { Name = "Microscopic", Color = { 235, 235, 240 }, Level = 1, RewardOnly = true },
			SquintChampion = { Name = "Take Your Time...", Color = { 190, 235, 120 }, Level = 2, RewardOnly = true },
			NailedIt = { Name = "Nailed It", Color = { 90, 225, 140 }, Level = 4, RewardOnly = true },
			RulerRookie = { Name = "Trust Me Bro", Color = { 120, 195, 255 }, Level = 6, RewardOnly = true },
			NotEvenClose = { Name = "Not Even Close", Color = { 255, 140, 110 }, Level = 8, RewardOnly = true },
			BigBrain = { Name = "That Big?!", Color = { 255, 130, 200 }, Level = 10, RewardOnly = true },
			ShrinkRay = { Name = "Size Matters", Color = { 100, 240, 230 }, Level = 13, RewardOnly = true },
			GiantWhisperer = { Name = "Buuiilt Different", Color = { 255, 190, 70 }, Level = 16, RewardOnly = true },
			ScaleWizard = { Name = "Scale Wizard", Color = { 185, 130, 255 }, Level = 20, RewardOnly = true },
			AbsolutelyMassive = { Name = "Absolutely Massive", Color = { 255, 215, 60 }, Level = 25, RewardOnly = true },
		},
	},
}
-- World chair displays: the free Basic chair (Classic) plus purchased stock. The old colour chairs are gone.
catalog.ChairShopOrder = { "Classic", "Glass", "Goop", "Slime", "Flower", "Moon", "RGB", "Electric", "Throne", "Void" }
-- Authored Workspace.Game.Interactables.Chairs.Chairs models whose names differ from their catalog ID.
catalog.ChairModelIds = { Basic = "Classic", ElectricChair = "Electric" }
catalog.Items.Chairs.Classic.Name = "Basic"
catalog.Items.Chairs.Classic.Color = { 151, 94, 52 }
catalog.Items.Chairs.Classic.Rarity = "Common"
catalog.Items.Chairs.Classic.Price = 0
catalog.Items.Chairs.Classic.Visual = "Wooden"
local chairStock = {
	{ "Glass", 800, "Common", { 160, 230, 255 } },
	{ "Goop", 1000, "Uncommon", { 160, 130, 255 } },
	{ "Slime", 1600, "Uncommon", { 92, 235, 100 } },
	{ "Flower", 2500, "Uncommon", { 255, 215, 45 } },
	{ "Moon", 4000, "Rare", { 210, 136, 70 } },
	{ "RGB", 5500, "Rare", { 255, 60, 230 } },
	{ "Electric", 10000, "Rare", { 240, 255, 70 } },
	{ "Throne", 25000, "Legendary", { 255, 195, 35 } },
	{ "Void", 60000, "Mythic", { 110, 60, 255 } },
}
for _, stock in chairStock do
	local id = stock[1]
	catalog.Items.Chairs[id] =
		{ Name = id, Price = stock[2], Rarity = stock[3], Color = stock[4], PurchaseOnly = true, Visual = id }
	table.insert(catalog.Order.Chairs, id)
end
-- Six direct-purchase pets per stand. Existing pets/ownership and legacy egg odds survive.
catalog.PetShops = {
	Starter = { Name = "Starter Pets", Pets = { "Bunny", "Cat", "Fox", "Dragon", "Owl", "Phoenix" } },
	Lucky = { Name = "Lucky Pets", Pets = { "Slime", "Bee", "Panda", "Tiger", "Unicorn", "Griffin" } },
	Secret = { Name = "Secret Pets", Pets = { "Spirit", "Golem", "Hydra", "Kitsune", "Celestial", "Infinity" } },
}
catalog.PetShopOrder = { "Starter", "Lucky", "Secret" }
-- The Exquisite/Secret egg's shop prices in Gems (its PetShops.Secret.Currency), not Cash. At the real
-- 15 Robux-per-Gem rate this tops out around 300 Robux for the rarest pet instead of nearly 1,800.
local prices = { { 100, 300, 800, 1800, 4000, 8000 }, { 1000, 2500, 5000, 10000, 18000, 30000 }, {
	2,
	3,
	5,
	8,
	12,
	20,
} }
local periods = { { 20, 10, 15, 8, 10, 5 }, { 16, 9, 12, 7, 8, 4 }, { 12, 8, 10, 6, 6, 3 } }
local colors =
	{ { 130, 235, 160 }, { 255, 213, 75 }, { 191, 128, 255 }, { 255, 136, 109 }, { 113, 222, 255 }, { 255, 159, 228 } }
for tier, shopId in catalog.PetShopOrder do
	for index, id in catalog.PetShops[shopId].Pets do
		if not catalog.Items.Pets[id] then
			catalog.Items.Pets[id] = {
				Name = id,
				Rarity = if index <= 2 then "Uncommon" elseif index <= 4 then "Rare" else "Legendary",
				Weight = 0,
				Color = colors[index],
			}
			table.insert(catalog.Order.Pets, id)
		end
		local pet = catalog.Items.Pets[id]
		local heal = index % 2 == 1
		pet.Price, pet.PetShop = prices[tier][index], shopId
		pet.Ability =
			{ Kind = if heal then "Heal" else "Hint", Every = periods[tier][index], Unit = if heal
				then "Turns"
				else "Rounds" }
		pet.AbilityText = if heal
			then "Every "
				.. periods[tier][index]
				.. " of your turns with this pet, heal 1 heart (up to 3). Progress saves between games."
			else "Every "
				.. periods[tier][index]
				.. " rounds you play with this pet, get a free size hint. Progress saves between games."
	end
end
-- Preserve previously shipped IDs/abilities for saved inventories. Only the release
-- roster below is sold now; unused PetDatabase identities receive no gameplay data.
for _, pet in catalog.Items.Pets do
	pet.Legacy = true
	pet.Active = false
	pet.Price = nil
	pet.PetShop = nil
end
catalog.PetShops = {
	Starter = { Name = "Common Egg", Pets = { "Bunny", "Cat", "Dog", "Fox", "Bear", "Bull" } },
	Lucky = { Name = "Uncommon Egg", Pets = { "Alien", "Deer", "Lizard", "Rabbit", "Dragon", "WaterDragon" } },
	Secret = {
		Name = "Exquisite Egg",
		Pets = { "Fairy", "GlowingBear", "Spider", "Hydra", "Unicorn", "WingedFairy" },
		Currency = "Keys",
	},
}
local function activate(name: string, group: string, rarity: string, kind: string, every: number, tint: any)
	local id = name:gsub("[^%w]", "")
	local pet = catalog.Items.Pets[id]
	if not pet then
		pet = { Weight = 0 }
		catalog.Items.Pets[id] = pet
		table.insert(catalog.Order.Pets, id)
	end
	pet.Name, pet.Rarity, pet.Color, pet.Active, pet.Legacy = name, rarity, tint, true, false
	pet.AssetPath = string.split(group, "/")
	table.insert(pet.AssetPath, name)
	pet.Ability = { Kind = kind, Every = every, Unit = if kind == "Heal" then "Turns" else "Rounds" }
	pet.AbilityText = if kind == "Heal"
		then "Every " .. every .. " of your turns with this pet, heal 1 heart (up to 3). Progress saves between games."
		else "Every " .. every .. " rounds you play with this pet, get a free size hint. Progress saves between games."
	return pet
end
local eggNames = {
	{ "Bunny", "Cat", "Dog", "Fox", "Bear", "Bull" },
	{ "Alien", "Deer", "Lizard", "Rabbit", "Dragon", "Water Dragon" },
	{ "Fairy", "Glowing Bear", "Spider", "Hydra", "Unicorn", "Winged Fairy" },
}
local eggRarities = {
	{ "Common", "Common", "Common", "Uncommon", "Uncommon", "Rare" },
	{ "Uncommon", "Uncommon", "Rare", "Rare", "Epic", "Legendary" },
	{ "Rare", "Rare", "Epic", "Epic", "Legendary", "Mythic" },
}
for tier, shopId in catalog.PetShopOrder do
	for index, name in eggNames[tier] do
		local pet = activate(
			name,
			catalog.PetShops[shopId].Name,
			eggRarities[tier][index],
			if index % 2 == 1 then "Heal" else "Hint",
			periods[tier][index],
			colors[index]
		)
		pet.Price, pet.PetShop = prices[tier][index], shopId
	end
end
catalog.MysteryPools = {
	Abyssal = { "DarkDragon", "DarkFairy", "AbyssalHydra", "EvolvedAbyssalHydra" },
	Oceanic = { "OceanicBunny", "OceanicFox", "OceanicDiamond", "EvolvedOceanicDiamond" },
	Solar = { "SunBunny", "SunFox", "SunFlare", "EvolvedSolis" },
	Universal = { "UniversalHybrid", "UniversalPhoenix", "UniversalLeviathan", "EvolvedUniversalYatagarasu" },
}
local mysteries = {
	{ "Abyssal Egg", { "Dark Dragon", "Dark Fairy", "Abyssal Hydra", "Evolved Abyssal Hydra" } },
	{ "Oceanic Egg", { "Oceanic Bunny", "Oceanic Fox", "Oceanic Diamond", "Evolved Oceanic Diamond" } },
	{ "Solis Egg", { "Sun Bunny", "Sun Fox", "Sun Flare", "Evolved Solis" } },
	{ "Universal Egg", { "Universal Hybrid", "Universal Phoenix", "Universal Leviathan", "Evolved Universal Yatagarasu" } },
}
for _, pool in mysteries do
	for index, name in pool[2] do
		activate(
			name,
			pool[1] .. (if index == 4 then "/Evolved" else ""),
			({ "Rare", "Epic", "Legendary", "Mythic" })[index],
			if index % 2 == 1 then "Heal" else "Hint",
			({ 12, 7, 8, 3 })[index],
			colors[index + 2]
		)
	end
end
-- Current release roster. The first release above stays in the catalog as legacy so saved ownership, XP and ability
-- progress keep working; only the pets below are sold. Objects (Ruler, Stopwatch, Tape, Magnifying Glass, Compass, Measuring Mug, Microscope, Scale) are pets too.
for _, pet in catalog.Items.Pets do
	if pet.Active then
		pet.Active, pet.Legacy, pet.Price, pet.PetShop = false, true, nil, nil
	end
end
local function place(
	name: string,
	group: string,
	rarity: string,
	kind: string,
	every: number,
	tint: any,
	assetName: string?
)
	local pet = activate(name, group, rarity, kind, every, tint)
	if assetName then
		pet.AssetPath[#pet.AssetPath] = assetName
	end
	pet.Name = name
	return pet
end
-- {display name, ServerStorage.Pets.Active folder, asset name when it differs}; six per egg, cheapest first.
local shopRoster = {
	Starter = {
		{ "Bunny", "Common Egg" },
		{ "Compass", "Objects" },
		{ "Ruler", "Objects" },
		{ "Fox", "Common Egg" },
		{ "Stopwatch", "Objects" },
		{ "Scale", "Objects" },
	},
	Lucky = {
		{ "Measuring Mug", "Objects", "MeasuringMug" },
		{ "Tape", "Objects" },
		{ "Magnifying Glass", "Objects", "MagnifyingGlass" },
		{ "Ice Cream Kitty", "Ice Cream Egg" },
		{ "Dragon", "Uncommon Egg" },
		{ "Water Dragon", "Uncommon Egg" },
	},
	Secret = {
		{ "Fairy", "Exquisite Egg" },
		{ "Glowing Bear", "Exquisite Egg" },
		{ "Microscope", "Objects" },
		{ "Unicorn", "Exquisite Egg" },
		{ "Galactic Queen", "Galactic Egg" },
		{ "Helios", "Godly Egg" },
	},
}
for tier, shopId in catalog.PetShopOrder do
	local names = {}
	for index, entry in shopRoster[shopId] do
		local pet = place(
			entry[1],
			entry[2],
			eggRarities[tier][index],
			if index % 2 == 1 then "Heal" else "Hint",
			periods[tier][index],
			colors[index],
			entry[3]
		)
		pet.Price, pet.PetShop = prices[tier][index], shopId
		table.insert(names, (entry[1]:gsub("[^%w]", "")))
	end
	catalog.PetShops[shopId].Pets = names
end
-- Frog left the Lucky egg for the Measuring Mug: it stays as a legacy pet so saved copies, XP and progress survive.
do
	local frog = activate("Frog", "Frog Egg", eggRarities[2][1], "Heal", periods[2][1], colors[1])
	frog.Active, frog.Legacy, frog.Price, frog.PetShop = false, true, nil, nil
end
local mysteryRoster = {
	Abyssal = { "Abyssal Egg", { { "Dark Dragon" }, { "Abyss Demon" }, { "Abyssal Cerberus" }, {
		"Evolved Abyssal Hydra",
		true,
	} } },
	Oceanic = {
		"Oceanic Egg",
		{ { "Oceanic Kitty" }, { "Oceanic Star" }, { "Oceanic Winged Lord" }, { "Evolved Oceanic Trio", true } },
	},
	Solar = { "Solis Egg", { { "Sun Cat" }, { "Sun Doubull" }, { "Sun Flare" }, { "Evolved Solis", true } } },
	Universal = {
		"Universal Egg",
		{ { "Universal Megalodon" }, { "Universal Phoenix" }, { "Universal Leviathan" }, {
			"Evolved Universal Yatagarasu",
			true,
			"Universal Yatagarasu",
		} },
	},
}
catalog.MysteryPools = {}
for poolId, pool in mysteryRoster do
	local ids = {}
	for index, entry in pool[2] do
		place(
			entry[1],
			pool[1] .. (if entry[2] then "/Evolved" else ""),
			({ "Rare", "Epic", "Legendary", "Mythic" })[index],
			if index % 2 == 1 then "Heal" else "Hint",
			({ 12, 7, 8, 3 })[index],
			colors[index + 2],
			entry[3]
		)
		table.insert(ids, (entry[1]:gsub("[^%w]", "")))
	end
	catalog.MysteryPools[poolId] = ids
end
for id, item in catalog.Items.Pets do
	item.AssetId = id
end
-- Pet abilities. Every active pet has its own; strength scales with rarity (Common..Mythic) and duplicate
-- copies never stack: only the best pet of each kind counts. Turn-based kinds (Heal/Hint/Shield) keep a saved
-- per-pet counter; the rest are passive or once per game. Every ability keeps an integer Every (1 when unused)
-- so saved progress reconciles the same way everywhere.
local rarityIndex = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
catalog.AbilityKinds = {
	Heal = {
		Unit = "Turns",
		Every = { 20, 15, 12, 8, 6, 4 },
		Text = function(a)
			return "Every "
				.. a.Every
				.. " of your turns with this pet, heal 1 heart (up to 3). Progress saves between games."
		end,
	},
	Hint = {
		Unit = "Rounds",
		Every = { 10, 9, 8, 6, 5, 3 },
		Text = function(a)
			return "Every "
				.. a.Every
				.. " rounds you play with this pet, get a free hint. Progress saves between games."
		end,
	},
	Shield = {
		Unit = "Turns",
		Every = { 8, 7, 6, 5, 4, 3 },
		Text = function(a)
			return "Every " .. a.Every .. " of your turns, get a Shield that blocks the next heart you would lose."
		end,
	},
	SecondChance = {
		Power = { 3, 4, 5, 6, 8, 10 },
		Text = function(a)
			return "Once per game, if you miss the target by " .. a.Power .. " points or less, you keep your heart."
		end,
	},
	LowerBar = {
		Power = { 2, 3, 4, 6, 8, 10 },
		Text = function(a)
			return "Your accuracy target is " .. a.Power .. " points lower."
		end,
	},
	ExtraTime = {
		Power = { 3, 4, 5, 6, 8, 10 },
		Text = function(a)
			return "You get +" .. a.Power .. " seconds on every turn you play."
		end,
	},
	InkRefill = {
		Power = { 1, 1, 1, 1, 2, 2 },
		Text = function(a)
			return "When you are watching, you can splat ink "
				.. a.Power
				.. " extra time"
				.. (if a.Power == 1 then "" else "s")
				.. " each turn."
		end,
	},
	LongInk = {
		Power = { 2, 3, 3, 4, 5, 6 },
		Text = function(a)
			return "Your ink splats stay on screen " .. a.Power .. " seconds longer."
		end,
	},
	CashBonus = {
		Power = { 10, 15, 20, 30, 40, 50 },
		Text = function(a)
			return "Win a game and get " .. a.Power .. "% extra Cash on top of the prize."
		end,
	},
	KeyFinder = {
		Power = { 20, 25, 30, 40, 50, 60 },
		Text = function(a)
			return a.Power .. "% chance to find a bonus Gem whenever you win a game."
		end,
	},
	Revive = {
		Power = { 1, 1, 1, 1, 1, 1 },
		Text = function()
			return "Once per game, if you would be knocked out, you stay in with 1 heart instead."
		end,
	},
	StreakSaver = {
		Power = { 20, 25, 30, 40, 50, 60 },
		Text = function(a)
			return a.Power .. "% chance to keep your win streak when you lose a game."
		end,
	},
	SharpEye = {
		Power = { 10, 15, 20, 30, 40, 50 },
		Text = function(a)
			return "Score 90 or more on a guess and earn $" .. a.Power .. " Cash."
		end,
	},
}
local abilityByPet = {
	Bunny = "Heal",
	Cat = "Hint",
	Dog = "ExtraTime",
	Fox = "SecondChance",
	Bear = "Shield",
	Bull = "LowerBar",
	Alien = "KeyFinder",
	Deer = "Heal",
	Lizard = "InkRefill",
	Rabbit = "SharpEye",
	Dragon = "Shield",
	WaterDragon = "SecondChance",
	Fairy = "Hint",
	GlowingBear = "Heal",
	Spider = "LongInk",
	Hydra = "LowerBar",
	Unicorn = "CashBonus",
	WingedFairy = "Revive",
	DarkDragon = "InkRefill",
	DarkFairy = "LongInk",
	AbyssalHydra = "LowerBar",
	EvolvedAbyssalHydra = "Shield",
	OceanicBunny = "Heal",
	OceanicFox = "Hint",
	OceanicDiamond = "CashBonus",
	EvolvedOceanicDiamond = "StreakSaver",
	SunBunny = "ExtraTime",
	SunFox = "SharpEye",
	SunFlare = "Shield",
	EvolvedSolis = "Revive",
	UniversalHybrid = "StreakSaver",
	UniversalPhoenix = "KeyFinder",
	UniversalLeviathan = "SecondChance",
	EvolvedUniversalYatagarasu = "Revive",
	-- Current roster. The objects fit their jobs: Ruler lowers the bar, Stopwatch adds time, Tape gives a second chance,
	-- Magnifying Glass sharpens your eye.
	Ruler = "LowerBar",
	Stopwatch = "ExtraTime",
	Tape = "SecondChance",
	MagnifyingGlass = "SharpEye",
	Compass = "Hint",
	MeasuringMug = "Heal",
	Microscope = "KeyFinder",
	Scale = "StreakSaver",
	Frog = "KeyFinder",
	IceCreamKitty = "StreakSaver",
	GalacticQueen = "SecondChance",
	Helios = "Revive",
	AbyssDemon = "LongInk",
	AbyssalCerberus = "Shield",
	OceanicKitty = "Heal",
	OceanicStar = "CashBonus",
	OceanicWingedLord = "StreakSaver",
	EvolvedOceanicTrio = "ExtraTime",
	SunCat = "ExtraTime",
	SunDoubull = "SharpEye",
	UniversalMegalodon = "LowerBar",
}
for id, kind in abilityByPet do
	local pet = catalog.Items.Pets[id]
	local definition = catalog.AbilityKinds[kind]
	local tier = rarityIndex[pet.Rarity]
	-- Heal/Hint pets keep their existing interval so saved progress stays meaningful.
	local kept = if pet.Ability and pet.Ability.Kind == kind then pet.Ability.Every else nil
	pet.Ability = {
		Kind = kind,
		Every = kept or (if definition.Every then definition.Every[tier] else 1),
		Power = if definition.Power then definition.Power[tier] else nil,
		Unit = definition.Unit or "None",
	}
	pet.AbilityText = definition.Text(pet.Ability)
end
for id, item in catalog.Items.Pets do
	if item.Active then
		assert(abilityByPet[id], "active pet without an ability: " .. id)
	end
end
-- Cosmetic-only presentation. Rarity never changes saved abilities or odds.
catalog.PetRarityStyles = {
	Common = { Tint = { 220, 230, 245 }, Accent = { 255, 255, 255 }, Extent = 1.45, Hover = -1.45, Bob = 0.12, Speed = 3, Orbits = 0 },
	Uncommon = { Tint = { 80, 245, 120 }, Accent = { 165, 255, 90 }, Extent = 1.65, Hover = -1.15, Bob = 0.18, Speed = 3, Orbits = 0 },
	Rare = { Tint = { 55, 200, 255 }, Accent = { 130, 245, 255 }, Extent = 1.9, Hover = -0.7, Bob = 0.22, Speed = 2.8, Orbits = 1 },
	Epic = { Tint = { 197, 95, 255 }, Accent = { 255, 105, 230 }, Extent = 2.15, Hover = -0.2, Bob = 0.25, Speed = 2.5, Orbits = 2, Trail = true },
	Legendary = { Tint = { 255, 205, 45 }, Accent = { 255, 140, 35 }, Extent = 2.55, Hover = 0.5, Bob = 0.3, Speed = 2.3, Orbits = 2, Trail = true },
	Mythic = {
		Tint = { 255, 100, 190 },
		Accent = { 100, 240, 255 },
		Extent = 2.95,
		Hover = 1.1,
		Bob = 0.35,
		Speed = 2,
		Orbits = 3,
		Trail = true,
		Rainbow = true,
	},
}
local petLooks = {
	Bunny = { Bob = 0.28, Speed = 4.5 },
	Bull = { Extent = 2.4, Hover = -1.1, Bob = 0.08 },
	Bear = { Extent = 2.1, Hover = -1.15, Bob = 0.1 },
	Spider = { Extent = 1.85, Hover = -1.5, Bob = 0.06 },
	Fairy = { Extent = 1.55, Hover = 0.85, Bob = 0.35 },
	WingedFairy = { Extent = 2.35, Hover = 1.8 },
	Dragon = { Extent = 2.6, Hover = 0.9, Bob = 0.38 },
	WaterDragon = { Extent = 2.8, Hover = 0.7, EffectTint = { 55, 200, 255 } },
	GlowingBear = { Extent = 2.5, Hover = -0.6, Orbits = 2, EffectTint = { 110, 255, 155 } },
	Hydra = { Extent = 2.8, Hover = -0.5 },
	AbyssalHydra = { Extent = 2.95, Hover = 0.3 },
	EvolvedAbyssalHydra = { Extent = 3.3, Hover = 1 },
	OceanicDiamond = { Extent = 2.6, Hover = 1.1, EffectTint = { 70, 220, 255 } },
	EvolvedOceanicDiamond = { Extent = 3.1, Hover = 1.6 },
	SunFlare = { Extent = 2.7, Hover = 0.9, EffectTint = { 255, 170, 35 } },
	EvolvedSolis = { Extent = 3.2, Hover = 1.45 },
	UniversalPhoenix = { Extent = 2.7, Hover = 1.25 },
	UniversalLeviathan = { Extent = 3.2, Hover = 0.9 },
	EvolvedUniversalYatagarasu = { Extent = 3.35, Hover = 1.9 },
}
for id, item in catalog.Items.Pets do
	item.Presentation = table.clone(catalog.PetRarityStyles[item.Rarity] or catalog.PetRarityStyles.Common)
	for key, value in petLooks[id] or {} do
		item.Presentation[key] = value
	end
end
function catalog.PetDisplayName(id: string, level: number?): string
	local item = catalog.Items.Pets[id]
	-- "Evolved" is an internal roster qualifier, never shown: "Evolved Abyssal Hydra" displays as "Abyssal Hydra".
	local name = item.Name:gsub("^Evolved%s+", "")
	return "Lvl " .. math.clamp(math.floor(level or 1), 1, catalog.PetLevels.MaxLevel) .. " " .. name
end
return table.freeze(catalog)

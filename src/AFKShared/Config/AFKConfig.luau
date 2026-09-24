--!strict
return {
	PlaceId = 95238940314216,
	MainPlaceId = 97619904048927,
	RequiredWins = 5,
	RemoteName = "ScaleAFK",
	-- Every reward comes after a random wait between these many seconds; a clock boost halves the wait.
	RewardMinSeconds = 30,
	RewardMaxSeconds = 60,
	BoostSeconds = 600, -- A clock grants ten minutes of twice-as-frequent AFK rewards.
	HistoryLimit = 90,
	RecentSlots = 15, -- HUD.AFK.Left.RewardsEarnt holds 1 (newest) to 15 (oldest).
	-- Icons by reward Kind (the same Cash and Gem art the main lobby uses). Pet, Chair and Block have no flat image:
	-- they show their real model in the card's authored ViewportFrame (AFKView.Fill); Boost stays iconless.
	Icons = {
		Cash = "rbxassetid://109114110793698",
		Keys = "rbxassetid://79449944506530",
		Boost = "",
		Pet = "",
		Chair = "",
		Block = "",
		Egg = "",
	},
	-- Text gradients by reward Kind: Cash green to yellow, Gems purple to white to cyan, other rewards cyan to white.
	Gradients = {
		Cash = { { 0, { 0, 255, 72 } }, { 1, { 255, 255, 0 } } },
		Keys = { { 0, { 247, 0, 255 } }, { 0.5, { 255, 255, 255 } }, { 1, { 0, 251, 255 } } },
		Boost = { { 0, { 0, 251, 255 } }, { 1, { 255, 255, 255 } } },
		Pet = { { 0, { 255, 205, 60 } }, { 1, { 255, 255, 255 } } },
		Chair = { { 0, { 130, 235, 160 } }, { 1, { 255, 255, 255 } } },
		Block = { { 0, { 190, 110, 255 } }, { 1, { 255, 255, 255 } } },
		Egg = { { 0, { 255, 170, 90 } }, { 1, { 255, 255, 255 } } },
	},
	-- Every reward cycle the server draws a fresh offer: one prize per slot (Right.Container.Reward1-5, in this order),
	-- each slot a rarity tier. A tier picks one of its Options (by Weight), then a random amount or item from it, and
	-- the tier gets a random chance from its Weight range; the chances are scaled to add up to exactly 100%.
	-- Balance (average over many rewards): about $80 Cash per reward, about 2 Gems per hour of AFK, and the pricier
	-- the item the rarer it is. Kinds: Cash, Keys (Gems), Pet, Chair, Block (a Lucky Block saved unopened for the main
	-- game) and Egg (hatches a random pet from that egg's shop, cheaper pets likelier).
	Offer = {
		{ -- Common
			Weight = { 60, 80 },
			Options = { { Kind = "Cash", Amount = { 10, 70, 5 } } },
		},
		{ -- Uncommon
			Weight = { 12, 28 },
			Options = { { Kind = "Cash", Amount = { 75, 250, 25 } } },
		},
		{ -- Rare
			Weight = { 3, 9 },
			Options = {
				{ Kind = "Cash", Amount = { 500, 1500, 50 } },
				{ Kind = "Keys", Amount = { 1, 2, 1 } },
				{ Kind = "Pet", Pool = { "Bunny", "Compass", "Ruler", "MeasuringMug", "Fox" } },
				{ Kind = "Chair", Pool = { "Glass", "Goop" } },
				{ Kind = "Egg", Pool = { "Starter" } },
			},
		},
		{ -- Epic
			Weight = { 0.4, 1.6 },
			Options = {
				{ Kind = "Cash", Amount = { 2000, 4000, 100 } },
				{ Kind = "Keys", Amount = { 3, 5, 1 } },
				{ Kind = "Pet", Pool = { "Tape", "Stopwatch", "MagnifyingGlass", "Scale" } },
				{ Kind = "Chair", Pool = { "Slime", "Flower", "Moon" } },
				{ Kind = "Block", Pool = { "Abyssal", "Oceanic" } },
				{ Kind = "Egg", Pool = { "Lucky" } },
			},
		},
		{ -- Legendary
			Weight = { 0.03, 0.2 },
			Options = {
				{ Kind = "Cash", Amount = { 7500, 15000, 500 } },
				{ Kind = "Keys", Amount = { 8, 15, 1 } },
				{ Kind = "Pet", Pool = { "IceCreamKitty", "Dragon", "WaterDragon", "Fairy", "GlowingBear" } },
				{ Kind = "Chair", Pool = { "RGB", "Electric" } },
				{ Kind = "Block", Pool = { "Solar", "Universal" } },
				{ Kind = "Egg", Pool = { "Secret" } },
			},
		},
	},
	-- Lucky Blocks: name and ReplicatedStorage.Assets.LuckyBlocks model (the main game's ShopCatalog.BlockPreviewModels).
	Blocks = {
		Abyssal = { Name = "Abyssal Block", Design = "Purple" },
		Oceanic = { Name = "Oceanic Block", Design = "Red" },
		Solar = { Name = "Solar Block", Design = "Gold" },
		Universal = { Name = "Universal Block", Design = "Grey" },
	},
	-- Eggs (CosmeticCatalog.PetShops ids): the model is the first of Models found in ReplicatedStorage.Assets.Eggs.
	Eggs = {
		Starter = { Models = { "Common", "CommonEgg", "Common Egg" } },
		Lucky = { Models = { "Uncommon", "UncommonEgg", "Uncommon Egg" } },
		Secret = { Models = { "Exquisite", "Equisite", "ExquisiteEgg", "Exquisite Egg" } },
	},
	-- A chair the player already owns pays this share of its price in Cash instead.
	OwnedChairCash = 0.25,
	-- The offer shown before the first packet arrives (and a fixed example for tests); odds sum to 100.
	Rewards = {
		{ Id = "Cash50", Kind = "Cash", Amount = 50, Chance = 84.4, Label = "$50" },
		{ Id = "Cash250", Kind = "Cash", Amount = 250, Chance = 14, Label = "$250" },
		{ Id = "Key", Kind = "Keys", Amount = 1, Chance = 1, Label = "1 Gem" },
		{ Id = "PetBunny", Kind = "Pet", Amount = 1, Chance = 0.3, Label = "Bunny", PetId = "Bunny" },
		{ Id = "ChairGlass", Kind = "Chair", Amount = 1, Chance = 0.3, Label = "Glass Chair", ChairId = "Glass" },
	},
	-- Sounds (SoundService.SFX) play at this fraction of their authored volume in the AFK world: Reward when a
	-- reward arrives, and a tick every second of the countdown.
	SoundVolume = 0.3,
	RewardSounds = { "Reward", "Purchase", "Notification" },
	TickSounds = { "TickUp", "Click" },
}

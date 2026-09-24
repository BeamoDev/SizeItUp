--!strict
-- Identity-only index for ServerStorage.Pets.Active. No prices, odds or abilities here.
-- PetLibrary also discovers every model in the real folder, including unseen packs.
local database = { Entries = {}, Order = {} }
local groups = {
	{"Abyssal Egg", "Abyss Demon|AbyssScorn|Abyssal Cerberus|Abyssal Hydra|Dark Dragon|Dark Fairy|Dark Lizard", "Evolved Abyssal Cerberus|Evolved Abyssal Hydra"},
	{"Coconut Egg", "Coconut Bat|Coconut Bunny|Coconut Cat|Coconut Dog|Coconut Jellyfish|Coconut Mouse|Coconut Omega Bull|Coconut Winged Lord|The Big Coconut", "Evolved The Big Coconut"},
	{"Common Egg", "Bear|Bull|Bunny|Cat|Dog|Fox"},
	{"Desert Egg", "Desert Ico v2|Desert Missle|Desert Shard|Desert Shardia|Desert Symbol|Sun Prism|Sun Star|The Sun Home", "Evolved Sun Prism|Evolved The Sun Home"},
	{"Divine Egg", "Divine Sun|Polygonis|The Star of Lakshmi"},
	{"Dungeon Eggs/Beach Dungeon Egg", "Beach Core|Beach Dungeon Dominus|Beach Dungeon Exoticis|Beach Dungeon Serpent", "Evolved Beach Core"},
	{"Dungeon Eggs/Dark Dungeon Egg", "Dark Dungeon Blob|Dark Dungeon Exoticis|Dark Dungeon Serpent|Dark Heart", "Evolved Dark Heart"},
	{"Dungeon Eggs/Dark Dungeon Egg", "Death Dungeon Blob|Death Dungeon Exoticis|Death Dungeon Serpent|The Soul of Death", "Evolved The Soul of Death"},
	{"Dungeon Eggs/Frost Dungeon Egg", "Frost Dungeon Blob|Frost Dungeon Exoticis|Frost Dungeon Serpent|Frost Heart", "Evolved Frost Heart"},
	{"Dungeon Eggs/Future Dungeon Egg", "Future Dungeon Dominus|Future Dungeon Exoticis|Future Dungeon Serpent|Futuristic Core", "Evolved Futuristic Core"},
	{"Dungeon Eggs/Lava Dungeon Egg", "Lava Dungeon Blob|Lava Dungeon Exoticis|Lava Dungeon Serpent|Lava Heart", "Evolved Lava Heart"},
	{"Dungeon Eggs/Poisonous Dungeon Egg", "Poison Dungeon Blob|Poison Dungeon Exoticis|Poison Dungeon Serpent|Poison Heart", "Evolved Poison Heart"},
	{"Dungeon Eggs/Space Dungeon Egg", "Space Core|Space Dungeon Dominus|Space Dungeon Exoticis|Space Dungeon Serpent", "Evolved Space Core"},
	{"Exquisite Egg", "Fairy|Glowing Bear|Hydra|Skewnet|Spider|Unicorn|Winged Fairy"},
	{"Frog Egg", "Blue Frog|Frog|Frog Snake|Frog Twins|Hungry Frogs", "Evolved Frog Twins|Evolved Hungry Frogs"},
	{"Galactic Egg", "Galactic Angel|Galactic Hedgehog|Galactic Lord|Galactic Overlord|Galactic Plushie|Galactic Queen|Galactic Saturn|Galactic System", "Evolved Galactic Lord|Evolved Galactic Overlord"},
	{"Godly Egg", "Aether|Crepitus|Gloxcinia|Helios|Hyperion|Primus|Sand Dweller|Varan", "Evolved Aether|Evolved Hyperion|Evolved Primus"},
	{"Objects", "Compass|MagnifyingGlass|MeasuringMug|Microscope|Ruler|Scale|Stopwatch|Tape"},
	{"Ice Cream Egg", "Ice Cream Bat|Ice Cream Blob|Ice Cream Bunny|Ice Cream Doggy|Ice Cream Doubull|Ice Cream Fox|Ice Cream Kitty|Ice Cream Mouse|Ice Cream Shock"},
	{"Jungle Egg", "Jungle Hexa|Jungle Icosphere|Jungle Platinium|Jungle Plaza|Jungle Polygonis|Jungle Saturn|Jungle Shardia|Jungle UV|The Monkey", "Evolved The Monkey"},
	{"Limited Eggs/500k Egg", "500K Aetherian|500K Bat|500K Demon|500K Doggy|500K Fairy|500K Sinister|500K Slime|500K Spider|500K Spikua", "Evolved 500K Aetherian"},
	{"Limited Eggs/Alien Egg", "Alien Aetherian|Alien Bunny|Alien Doggy|Alien Ico|Alien Kitty|Alien Serpent|UFO", "Evolved Alien Aetherian|Evolved Alien Ico|Evolved UFO"},
	{"Magma Egg", "Godly Plume|Lava Golem|Lava Jellyfish|Lava King|Lava Master|Lava Plume|Lava Trio|Lava Veltal|Plume Family", "Evolved Godly Plume|Evolved Lava Master|Evolved Lava Trio"},
	{"Merry Egg", "Merry Deer|Merry Doggy|Merry Doubull|Merry Fox|Merry Kitty|Merry Lord|Merry Omega Bull|Merry Winged Leviathan|Merry Wyvern", "Evolved Merry Doubull|Evolved Merry Lord|Evolved Merry Winged Leviathan|Evolved Merry Wyvern"},
	{"Oceanic Egg", "Oceanic Bear|Oceanic Bunny|Oceanic Diamond|Oceanic Dog|Oceanic Doubull|Oceanic Fox|Oceanic Kitty|Oceanic Star|Oceanic Trio|Oceanic Winged Lord", "Evolved Oceanic Diamond|Evolved Oceanic Doubull|Evolved Oceanic Trio|Evolved Oceanic Winged Lord"},
	{"Omega Egg", "Omega Desert Ico V2|Omega Missle|Omega Silo|Omega Star|Omega Sun|Prism", "Evolved Omega Sun|Evolved Prism"},
	{"Radioactive Egg", "Radioactive Bunny|Radioactive Doggy|Radioactive Doubull|Radioactive Fox|Radioactive Kitty|Radioactive Mouse|Radioactive Serpent|Radioactive Star", "Evolved Radioactive Doubull|Evolved Radioactive Serpent"},
	{"Sand Egg", "Sand Bull|Sand Bunny|Sand Cat|Sand Dog|Sand Fox|Sand Lord|Sand Mouse|Sandy Vortex", "Evolved Sand Lord|Evolved Sandy Vortex"},
	{"Slush Egg", "Slush Atherian|Slush Bat|Slush Bull|Slush Bunny|Slush Doggy|Slush Hydra|Slush Kitty|Slush Mouse|Slush Serpent"},
	{"Solis Egg", "Solis|Sun Bunny|Sun Cat|Sun Dog|Sun Doubull|Sun Flare|Sun Fox|Sun Mouse|Sun Star", "Evolved Solis|Evolved Sun Flare"},
	{"Star Egg", "Star Plate|Super Sun Eclipsa|Super Sun Ico v2|Super Sun Missle|Super Sun Omega|Super Sun Prism|Super Sun Shardia|Super Sun Silo|Super Sun Star", "Evolved Super Sun Eclipsa|Evolved Super Sun Prism"},
	{"Uncommon Egg", "Alien|Deer|Dragon|Lizard|Rabbit|Star|Water Dragon"},
	{"Underworld Egg", "Arcc|HellBlaze Hydra Lord|HellBlaze OverLord", "Evolved Arcc"},
	{"Universal Egg", "Universal Hybrid|Universal Leviathan|Universal Lord|Universal Megalodon|Universal Phoenix|Universal Unicorn|Universal Varan|Universal Yatagarasu|Wicked Universal", "Evolved Universal Leviathan|Evolved Universal Lord|Evolved Universal Yatagarasu|Evolved Wicked Universal"},
}
for _,group in groups do
	for column=2,3 do
		for _,name in string.split(group[column] or "","|") do
			if name=="" then continue end
			local id=name:gsub("[^%w]","")
			if database.Entries[id] then id=group[1]:gsub("[^%w]","").."_"..id end
			local path=string.split(group[1],"/")
			if column==3 then table.insert(path,"Evolved") end
			table.insert(path,name)
			database.Entries[id]={Id=id,Name=name,Group=group[1],Path=path,Evolved=column==3}
			table.insert(database.Order,id)
		end
	end
end
-- These names were visible with their parent offscreen; runtime discovery resolves it.
for _,name in {"Fiery Lizard","Hellfire Dragon","Hellfire Hydra","Raging Bull"} do
	local id=name:gsub("[^%w]","")
	database.Entries[id]={Id=id,Name=name,Group="Unresolved",Evolved=false}
	table.insert(database.Order,id)
end
return database

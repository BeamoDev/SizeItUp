--!strict
-- Tune reward amounts and timings here. GroupId=0 uses the experience owner group.
return table.freeze({
	GroupId = 34241464,
	-- Cash only, per friend who joins through your invite, scaled to the Cash you hold (Shared/Util/WealthScale, Invite
	-- curve): $250 up to $5,000 held, $2,500 at $500,000, up to $6,250.
	InviteCash = 250,
	DailySeconds = 86400,
	Daily = {
		{ Id = "Day1", Name = "Day 1", Cash = 200 },
		{ Id = "Day2", Name = "Day 2", Cash = 500, BoostSeconds = 600, Chair = "Flower" },
		{ Id = "Day3", Name = "Day 3", Cash = 750, Keys = 1 },
		{ Id = "Day4", Name = "Day 4", Cash = 1000, BoostSeconds = 900 },
		{ Id = "Day5", Name = "Day 5", Cash = 1500, Keys = 2 },
		{ Id = "Day6", Name = "Day 6", Cash = 2000, BoostSeconds = 1200 },
		{ Id = "Day7", Name = "Day 7", Cash = 3000, Keys = 3, Pet = "Fox" },
	},
	-- Stable IDs identify lifetime, single-claim milestones in saved profiles.
	Timed = {
		{ Id = "Time2", Name = "2 minutes", Seconds = 120, Cash = 200 },
		{ Id = "Time5", Name = "5 minutes", Seconds = 300, BoostSeconds = 600 },
		{ Id = "Time10", Name = "10 minutes", Seconds = 600, Cash = 500 },
		{ Id = "Time15", Name = "15 minutes", Seconds = 900, Keys = 1 },
		{ Id = "Time20", Name = "20 minutes", Seconds = 1200, Cash = 1000 },
		{ Id = "Time30", Name = "30 minutes", Seconds = 1800, BoostSeconds = 900 },
		{ Id = "Time45", Name = "45 minutes", Seconds = 2700, Keys = 2 },
		{ Id = "Time60", Name = "60 minutes", Seconds = 3600, Cash = 2500 },
	},

	-- Redeemable codes (Store > Codes). Keys are the code in capitals; each works once per player.
	-- WELCOME is the default sample: edit or replace it with your own. A code may give Cash and/or Keys (Gems).
	Codes = {
		WELCOME = { Cash = 500 },
		RELEASE = { Cash = 2500 },
		MASSIVE = { Cash = 250 },
		SECRETDEVCODE67 = { Cash = 250000 },

	},
	-- Roblox badge IDs and player-facing descriptions for the collectable badge set shown in the game.
	Badges = {
		HowBigIsIt = {
			Id = 4207174537875932,
			Name = "How Big Is It?",
			Description = "Play Size It Up! for the first time.",
		},
		SizeMatters = { Id = 4482863259102638, Name = "Size Matters", Description = "Win your first round." },
		NailedIt = { Id = 3999572929929833, Name = "Nailed It", Description = "Make an extremely accurate size guess." },
		TrustMeBro = {
			Id = 3774081972809243,
			Name = "Trust Me Bro",
			Description = "Lock in a fast guess and get it right.",
		},
		NotEvenClose = {
			Id = 3805459749904768,
			Name = "Not Even Close",
			Description = "Make a hilariously inaccurate guess.",
		},
		ThatBig = { Id = 331132366111706, Name = "THAT BIG?!", Description = "Encounter an extremely large object." },
		Microscopic = {
			Id = 3313975587669861,
			Name = "Microscopic",
			Description = "Encounter an extremely tiny object.",
		},
		TakeYourTime = {
			Id = 4449682446655449,
			Name = "Take Your Time...",
			Description = "Use almost the entire round timer before guessing.",
		},
		BuiltDifferent = { Id = 803737718816704, Name = "Built Different", Description = "Win 10 rounds." },
		ProfessionalGuesser = {
			Id = 1951527487326165,
			Name = "Professional Guesser",
			Description = "Win 50 rounds.",
		},
		TouchGrass = { Id = 4224914815177432, Name = "Touch Grass", Description = "Win 250 rounds." },
		BiggerRuler = {
			Id = 3001157534919506,
			Name = "We’re Gonna Need a Bigger Ruler",
			Description = "Encounter the largest object in the game.",
		},
	},
	Group = { Id = "Group", Name = "Group rewards", Cash = 500, BoostSeconds = 600, Chair = "Goop" },
})

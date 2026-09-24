--!strict
return {
	AFKPlaceId = 95238940314216,
	AFKRequiredWins = 5,
	DataStoreName = "ScaleItUp_Profiles_v1",
	-- Set true ONLY for a deliberate unsaved Studio test. Live servers always save.
	MemoryOnlyInStudio = false,
	LeaseSeconds = 180, AutosaveSeconds = 45,
	PrizeRollSeconds = 7.5, -- 1s beat, 4.5s cash flicker (1.5x the old 3s), then 2s holding the final prize (GameConfig.PrizeHoldSeconds).
	Prizes = { 100, 150, 200, 250, 350, 500, 750, 1000 },
	-- Tables and chairs are authored in Workspace. Only pet stands are generated.
	-- Player level tuning (backend only, not displayed yet). Level 1 needs BaseXP; each level needs StepXP more.
	PlayerLevels = {
		BaseXP = 100, StepXP = 50, MaxLevel = 100,
		MatchPlayedXP = 25, MatchWonXP = 75,
		PlaytimeSeconds = 30, PlaytimeXP = 1, -- PlaytimeXP for every PlaytimeSeconds online in the main place
	},
}

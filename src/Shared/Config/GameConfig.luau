--!strict
local config = {
	Title = "Scale It Up!",
	TableTag = "ScaleTable",
	-- Practice bots keep private negative IDs and use the legacy bot portrait. Ambient population NPCs separately
	-- receive a real positive AvatarUserId so their portraits look like ordinary players.
	BotUserIdCeiling = -900000000,
	BotMugshotImage = "rbxassetid://119109062685227",
	NPCPopulation = {
		Enabled = true,
		TargetVisiblePopulationMin = 12, -- chosen once per server; one real player therefore gets 11-14 NPCs
		TargetVisiblePopulationMax = 15,
		MinimumBots = 0,
		MaximumBots = 14,
		ReconcileSeconds = 1.5,
		JoinIntervalMin = 2,
		JoinIntervalMax = 5,
		TableChance = 0.75,
		MinimumWalkers = 2,
		WanderWaitMin = 0.4,
		WanderWaitMax = 3.5,
		WalkSpeedMin = 9,
		WalkSpeedMax = 15,
		WalkAcceleration = 13,
		WalkDeceleration = 18,
		WaypointVariation = 0.45,
		PathRetries = 3,
		RouteBendChance = 0.72,
		WaypointPauseChance = 0.13,
		LocalStrollChance = 0.34,
		SocialWalkChance = 0.22,
		RunawaySpeed = 55,
		RunawayFallDistance = 40,
		RunawayRadius = 350,
		HumanTableJoinChance = 1,
		HumanTableJoinDelayMin = 0,
		HumanTableJoinDelayMax = 0,
		BotOnlyMatchChance = 0.75,
		BotOnlyMatchDelayMin = 3,
		BotOnlyMatchDelayMax = 12,
		SeatWaitMin = 40,
		SeatWaitMax = 90,
		LifetimeMin = 120,
		LifetimeMax = 300,
		CosmeticChangeMin = 75,
		CosmeticChangeMax = 180,
		-- Most ambient players should look new/casual. The final tier is the only one allowed to equip the best chair,
		-- so Void remains close to a 2% sight instead of filling the lobby.
		ProgressTierChances = { 0.63, 0.22, 0.09, 0.04, 0.02 },
		VIPTierChances = { 0, 0.01, 0.05, 0.18, 0.55 },
		-- Fake activity should make the server feel alive without taking over chat. Some due slots intentionally say
		-- nothing, and occasional long quiet periods make the feed feel organic instead of clock-driven.
		ChatIntervalMin = 75,
		ChatIntervalMax = 160,
		ChatSkipChance = 0.35,
		ChatLongQuietChance = 0.24,
		ChatLongQuietMin = 120,
		ChatLongQuietMax = 300,
	},
	BotDifficulty = {
		NewPlayerMatches = 5,
		NewPlayerWins = 2,
		SkilledMatches = 15,
		SkilledWins = 8,
		SkilledBestChain = 8,
		IntermediateHumanWinChance = 0.72,
		SkilledHumanWinChance = 0.5,
		CloseMarginMin = 1.5,
		CloseMarginMax = 5.5,
	},
	DefaultMode = "Classic",
	ModeVoteSeconds = 10,
	ModeOrder = { "Classic", "Endless", "BestOfFive", "SuddenDeath" },
	Modes = {
		Classic = {
			Name = "Classic",
			Description = "3 lives, lowest score loses one",
			Lives = 3,
			Color = { 255, 120, 145 },
		},
		Endless = {
			Name = "Endless",
			Description = "Survive as the target rises",
			Lives = 3,
			Color = { 110, 85, 235 },
		},
		BestOfFive = {
			Name = "Best of Five",
			Description = "5 rounds, highest total wins",
			Lives = 3,
			Rounds = 5,
			Color = { 30, 165, 220 },
		},
		SuddenDeath = {
			Name = "Sudden Death",
			Description = "1 life, lowest score is out",
			Lives = 1,
			Color = { 240, 135, 30 },
		},
	},
	StartingHearts = 3,
	ChainMilestoneRounds = 5,
	ChainMilestoneCash = 100,
	ChainMilestoneKeys = 1,
	ChainHealAccuracy = 90,
	ChainHealStreak = 3,
	-- A watcher's ink or troll effect (fog, lag, wobble) lasts a random InkSplatMinSeconds-InkSplatSeconds, rolled once
	-- on the server per effect (never past the turn; a Long Ink pet adds its seconds on top).
	InkSplatMinSeconds = 12,
	InkSplatSeconds = 18,
	HintCash = 0, -- hints are Robux-based (no Cash deduction); a product will set the price
	HintSeconds = 10,
	HintCloseTolerance = 0.20, -- Broad guidance, never a precision answer finder.
	HintMessages = {
		Bigger = { Title = "TRY BIGGER", Body = "Your guess looked too small. Try making it bigger!" },
		Smaller = { Title = "TRY SMALLER", Body = "Your guess looked too big. Try making it smaller!" },
		Close = { Title = "IN THE BALLPARK!", Body = "Your guess was in the right ballpark. Trust your eyes!" },
	},
	HeartCash = 0, -- Unused while Bootstrap wires SpendHeartCredit: a lost heart is bought back with the Robux Refill Heart product.
	SharpEyeAccuracy = 90, -- Sharp Eye pets pay out on guesses at or above this accuracy.
	GreatGuessAccuracy = 97, -- Every player (not only Sharp Eye pet owners) earns a small Cash bonus at or above this accuracy.
	GreatGuessCash = 15,
	SabotagesPerTurn = 3, -- Sabotage buttons stay on screen; a watcher can use them this many times per turn, one effect at a time.
	BotSabotageChancePerHumanTurn = 0.005, -- At most one watching bot rolls this once per human turn (0.5%).
	MaxHints = 4, -- Hints are repeatable after each scan expires, up to this many purchases per turn.
	ComboAccuracyThreshold = 90, -- "Within 10%" of the answer: a round counts toward the combo streak at or above this accuracy.
	ComboBonusThreshold = 3, -- Consecutive within-10% rounds needed before the combo starts paying a bonus.
	ComboBonusStep = 0.15, -- +15% Cash per combo point beyond the threshold.
	ComboBonusMaxCash = 1, -- The Cash combo bonus caps at +100% (2x total).
	ComboBonusMaxWinsBonus = 3, -- Bonus Wins on top of the normal award caps here.
	CountdownSeconds = 3, -- The table shows Starting in 3...2...1.
	-- Balanced puzzle pacing: readable reveals without repeated long holds.
	GoSeconds = 0, -- The match starts right after the prize is held; no separate GO beat.
	PrizeHoldSeconds = 2, -- The prize stays on the final amount this long before the match starts.
	LockInSeconds = 1.5,
	LockEnterSeconds = 0.4,
	LockExitSeconds = 0.35,
	IntroSeconds = 0, -- Rounds enter GUESSING immediately; no intro hold.
	GuessSeconds = 35,
	-- If a watcher opens the Sabotage developer-product prompt during a bot turn, freeze the bot with a full turn
	-- remaining. This safety cap prevents a disconnected prompt from holding every seated player forever.
	BotPurchasePromptTimeoutSeconds = 120,
	AccuracyCountSeconds = 2,
	-- Result colours from each player's own point of view (see ResultColor): slot 1 is always you, then the others
	-- in seat order, so both clients of a duel see themselves blue and the opponent red-pink.
	--   1v1       you blue, them red-pink
	--   1v1v1     P1 (you) purple, P2 blue, P3 red-pink
	--   1v1v1v1   P1 (you) pink, P2 blue, P3 red, P4 green
	ResultPalettes = {
		[2] = { { 65, 140, 255 }, { 255, 80, 120 } },
		[3] = { { 159, 44, 245 }, { 65, 140, 255 }, { 255, 80, 120 } },
		[4] = { { 255, 105, 170 }, { 65, 140, 255 }, { 255, 70, 75 }, { 53, 237, 65 } },
	},
	ResultActualTransparency = 0.76,
	ResultGuessTransparency = 0.18,
	ResultFillTransparency = 0.84,
	ResultReferenceSeconds = 1.5,
	ResultActualAppearSeconds = 1,
	ResultActualHoldSeconds = 2,
	ResultGreyFadeSeconds = 0.8,
	ResultAnnounceSeconds = 1.5,
	ResultGrowSeconds = 2,
	ResultGuessHoldSeconds = 2,
	ResultGuessFadeSeconds = 0.6,
	ResultFinalHoldSeconds = 1,
	ResultCardEnterSeconds = 0.8,
	ResultHudExitSeconds = 0.7,
	AccuracySettleSeconds = 0.5,
	ResultHoldSeconds = 3,
	SizeRevealSeconds = 4,
	TableReturnSeconds = 2,
	-- One seated player at a time after the reveal: tick (safe/heal) or a lost heart, then the next player.
	-- The reaction beat now lasts longer so the left-panel heart pop and the camera shift feel deliberate.
	TableReactionSlotSeconds = 5,
	HeartFlashSeconds = 2,
	TableCameraFieldOfView = 52,
	TableFocusRadius = 1.5,
	TableBlurIntensity = 0.9,
	UseLabeledBricks = false,
	ObjectPreviewFolder = "ScaleObjectPreviews",
	-- Keep vague, asset-specific objects available for previews without choosing them in rounds.
	-- Use catalog IDs here; duplicate runtime variants inherit their base ID's exclusion.
	ObjectSelectionExclusions = {
		Picture = true,
		Scene = true,
		Plants = true,
	},
	MaxPreviewExtent = 80,
	-- The end-of-match screen: the Winner/Loser banner pops, holds and shrinks, then Points slide in and hold; the table
	-- ejects the players (and the lobby wipe begins) once it is done. Cancelled matches skip it.
	EndBannerPopSeconds = 1.05,
	EndBannerHoldSeconds = 1.2,
	EndBannerShrinkSeconds = 0.75,
	EndPointsSeconds = 1.2,
	EndPointsHoldSeconds = 1,
	EndCancelSeconds = 1.5,
	CompletionSeconds = 10,
	ResetSeconds = 1,
	WinnerCash = 100,
	MinimumGuessMeters = 0.02,
	MaximumGuessMeters = 500,
	MaximumPairHeightRatio = 4,
	TieErrorTolerance = 0.001,
	GuessUpdatesPerSecond = 12,
	GuessBurst = 6,
	ClientSendInterval = 0.1,
	CameraFieldOfView = 24,
	CameraMinimumFieldOfView = 12,
	CameraFollowSpeed = 12,
	CameraTweenSeconds = 0.6,
	StudsPerMeter = 1, -- Objects display at their real measured height: 1 stud per metre. MaxPreviewExtent still caps the largest side.
	-- The arena's Wall, Wall1-3 and Floor textures all tile at this many studs (U and V alike), so the grid stays small
	-- enough to judge tiny objects against. The authored default of 12 studs made the squares huge next to a mouse or a coin.
	ArenaTileStuds = 2,
	ModelGapStuds = 2, -- Largest edge-to-edge gap; smaller objects get a proportionally smaller one.
	ModelGapFraction = 0.2, -- Gap as a fraction of the reference height, so tiny objects are not pushed far apart.
	ModelGapMinStuds = 0.02,
	ScaleSmoothSpeed = 18,
	ScaleMaxOctavesPerSecond = 2,
	ScaleMaximumFrameSeconds = 1 / 30,
	TransitionCoverSeconds = 0.5,
	TransitionRevealSeconds = 0.65,
}
function config.RequiredAccuracy(round: number): number
	return math.min(95, 60 + 2 * math.max(0, math.floor(round) - 1))
end
-- The RGB colour of a result slot (1 = you, then the others in seat order, as RevealPresentation.Order lays them
-- out) at a table of this many players. Guess models, mugshot backgrounds, rulers and points all use it.
function config.ResultColor(slot: number, count: number): { number }
	local palette = config.ResultPalettes[math.clamp(math.floor(count), 2, 4)]
	return palette[math.clamp(math.floor(slot), 1, #palette)]
end
function config.RevealIntroSeconds(): number
	return config.ResultReferenceSeconds
		+ config.ResultActualAppearSeconds
		+ config.ResultActualHoldSeconds
		+ config.ResultGreyFadeSeconds
end
function config.RevealSlotSeconds(): number
	return config.ResultAnnounceSeconds
		+ config.ResultGrowSeconds
		+ config.ResultGuessHoldSeconds
		+ config.ResultGuessFadeSeconds
end
function config.RevealDuration(count: number): number
	-- The final guess stays visible: omit its unused fade slot.
	return config.RevealIntroSeconds()
		+ config.RevealSlotSeconds() * count
		- (if count > 0 then config.ResultGuessFadeSeconds else 0)
		+ config.ResultFinalHoldSeconds
end
function config.TableReactionDuration(count: number): number
	return config.TableReactionSlotSeconds * math.max(1, math.floor(count))
end
-- Streak/combo bonus: consecutive within-10% guesses raise the winner's Cash prize and Wins award (see ComboAccuracyThreshold
-- and friends above). A streak at or below the threshold pays nothing extra, matching normal play exactly.
function config.ComboMultiplier(streak: number): number
	local bonus = math.max(0, (streak or 0) - config.ComboBonusThreshold) * config.ComboBonusStep
	return 1 + math.min(bonus, config.ComboBonusMaxCash)
end
function config.ComboWinsBonus(streak: number, baseWins: number): number
	local bonus = math.floor(baseWins * (config.ComboMultiplier(streak) - 1) + 0.5)
	return baseWins + math.min(bonus, config.ComboBonusMaxWinsBonus)
end
config.RevealSeconds = config.RevealDuration(2)
config.TableReactionSeconds = config.TableReactionDuration(2)
config.EndSeconds = config.EndBannerPopSeconds
	+ config.EndBannerHoldSeconds
	+ config.EndBannerShrinkSeconds
	+ config.EndPointsSeconds
	+ config.EndPointsHoldSeconds
return table.freeze(config)

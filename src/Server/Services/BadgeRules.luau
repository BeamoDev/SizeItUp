--!strict
-- Which RewardCatalog.Badges a player has earned. Pure rules (no Roblox calls); EconomyRuntime.AwardBadge hands the
-- badges out (skipping ones already owned or with no real ID yet).
local BadgeRules = {}

BadgeRules.WinTiers = { { 1, "SizeMatters" }, { 10, "BuiltDifferent" }, { 50, "ProfessionalGuesser" }, { 250, "TouchGrass" } }
BadgeRules.NailedAccuracy = 99 -- Nailed It: an extremely accurate size guess.
BadgeRules.WayOffRatio = 3 -- Not Even Close: at least 3x too big or too small.
BadgeRules.FastSeconds, BadgeRules.FastAccuracy = 5, 90 -- Trust Me Bro: a fast lock that is right.
BadgeRules.LateSeconds = 3 -- Take Your Time: locked with this little (or no) time left.
BadgeRules.HugeMeters, BadgeRules.TinyMeters = 40, 0.15 -- THAT BIG / Microscopic (heights run 0.1-60 m).

-- On joining and after each match: the first-play badge and the match-win milestones.
function BadgeRules.ForProfile(data: any): { string }
	local earned = { "HowBigIsIt" }
	for _, tier in BadgeRules.WinTiers do
		if (data.Wins or 0) >= tier[1] then
			table.insert(earned, tier[2])
		end
	end
	return earned
end

-- At a round's reveal, for one player who guessed in it.
--   accuracy, guess, actual     their scored guess and the true height (metres)
--   reference                   the reference object's height (metres)
--   largest                     the tallest object height in the game's catalog
--   used                        { Seconds = time into their turn when it locked, Length = the turn's length, Manual = pressed Lock In }
function BadgeRules.ForRound(accuracy: number, guess: number, actual: number, reference: number, largest: number?, used: any?): { string }
	local earned = {}
	if accuracy >= BadgeRules.NailedAccuracy then
		table.insert(earned, "NailedIt")
	end
	if guess >= actual * BadgeRules.WayOffRatio or guess * BadgeRules.WayOffRatio <= actual then
		table.insert(earned, "NotEvenClose")
	end
	if used then
		if used.Manual and used.Seconds <= BadgeRules.FastSeconds and accuracy >= BadgeRules.FastAccuracy then
			table.insert(earned, "TrustMeBro")
		end
		if used.Seconds >= used.Length - BadgeRules.LateSeconds then
			table.insert(earned, "TakeYourTime")
		end
	end
	local tallest, shortest = math.max(actual, reference), math.min(actual, reference)
	if tallest >= BadgeRules.HugeMeters then
		table.insert(earned, "ThatBig")
	end
	if shortest <= BadgeRules.TinyMeters then
		table.insert(earned, "Microscopic")
	end
	if largest and tallest >= largest - 1e-9 then
		table.insert(earned, "BiggerRuler")
	end
	return earned
end

return BadgeRules

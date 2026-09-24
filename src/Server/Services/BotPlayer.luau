--!strict
-- "Play vs Bot": how a bot seat plays one guessing turn so it reads like a person on the slider. Pure planning and
-- sampling (no Instances, no remotes); Bootstrap decides when to Submit / Lock the values sampled here.
--   Target  where the bot means to end up: close to the humans' demonstrated/profile-estimated accuracy, just above
--           or below it according to the match's frozen difficulty/outcome plan.
--   Plan    a short look at the objects, one quick coarse drag from the round's starting size (sometimes past the
--           mark), a pause to judge it, one to four smaller corrections, a last check, then Lock In. Every move
--           travels in log space with eased starts and stops at human drag speeds, below the watchers' 2-octave/s
--           preview cap, so they see each drag rather than jumps. A turn usually takes 5-15 seconds, occasionally
--           around 20, and always locks at least LockMargin seconds before the deadline.
--   Sample  the size at a moment (moving or resting).
local BotPlayer = {}
BotPlayer.LockMargin = 4

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function BotPlayer.Difficulty(random: any, profiles: { any }, tuning: any): any
	local totalMatches, totalWins, totalBest = 0, 0, 0
	for _, data in profiles do
		totalMatches += data.Matches or 0
		totalWins += data.Wins or 0
		totalBest += data.BestChainRound or 0
	end
	local humans = math.max(1, #profiles)
	local matchesPlayed, wins, bestChain = totalMatches / humans, totalWins / humans, totalBest / humans
	local winRate = math.clamp(wins / math.max(1, matchesPlayed), 0, 1)
	local skill = math.clamp(
		math.min(1, matchesPlayed / math.max(1, tuning.SkilledMatches or 15)) * 0.45
			+ winRate * 0.35
			+ math.min(1, bestChain / math.max(1, tuning.SkilledBestChain or 8)) * 0.2,
		0,
		1
	)
	local isNew = matchesPlayed <= (tuning.NewPlayerMatches or 5) and wins <= (tuning.NewPlayerWins or 2)
	local isSkilled = matchesPlayed >= (tuning.SkilledMatches or 15)
		or wins >= (tuning.SkilledWins or 8)
		or bestChain >= (tuning.SkilledBestChain or 8)
	local humanWinChance = if isNew then 1
		elseif isSkilled then tuning.SkilledHumanWinChance or 0.5
		else tuning.IntermediateHumanWinChance or 0.72
	return {
		FavorHumans = random:NextNumber() < humanWinChance,
		NewPlayer = isNew,
		SkilledPlayer = isSkilled,
		ExpectedAccuracy = 58 + skill * 34,
		CloseMarginMin = tuning.CloseMarginMin or 1.5,
		CloseMarginMax = tuning.CloseMarginMax or 5.5,
		Rounds = {},
	}
end

function BotPlayer.Target(
	random: any,
	actual: number,
	minimum: number,
	maximum: number,
	humanAccuracy: number?,
	strategy: any?
): number
	local roll = random:NextNumber()
	local accuracy
	if strategy then
		local reference = humanAccuracy or strategy.ExpectedAccuracy or 76
		local margin = random:NextNumber(strategy.CloseMarginMin or 1.5, strategy.CloseMarginMax or 5.5)
		accuracy = reference + (if strategy.TrailHumans then -margin else margin)
		-- Small irregularity prevents every NPC on a multi-seat table from landing on the same score. Decisive rounds
		-- stay on their intended side of the player; ordinary rounds can wobble a little more.
		local noise = if strategy.Decisive then random:NextNumber(-0.6, 0.6) else random:NextNumber(-1.8, 1.8)
		accuracy += noise
	elseif roll < 0.12 then
		accuracy = random:NextNumber(40, 70)
	elseif roll < 0.22 then
		accuracy = random:NextNumber(92, 99)
	elseif humanAccuracy then
		accuracy = humanAccuracy + random:NextNumber(-12, 8)
	else
		accuracy = random:NextNumber(70, 92)
	end
	local miss = (100 - math.clamp(accuracy, 30, 99.5)) / 100
	local guess = if random:NextNumber() < 0.5 then actual * (1 + miss) else actual * (1 - miss)
	return math.clamp(guess, minimum, maximum)
end

function BotPlayer.Plan(
	random: any,
	start: number,
	final: number,
	minimum: number,
	maximum: number,
	now: number,
	deadline: number
): any
	start = math.clamp(start, minimum, maximum)
	final = math.clamp(final, minimum, maximum)
	local moves = {}
	local careful = random:NextNumber() < 0.2
	-- The turn's scene wipe plays first, then a look at both objects before the first drag.
	local clock = now + random:NextNumber(1.3, 2.6)
	local current = start
	local function move(to: number, speed: number)
		to = math.clamp(to, minimum, maximum)
		local octaves = math.abs(math.log(to / current) / math.log(2))
		local duration = math.clamp(octaves / speed, 0.25, 2.8)
		table.insert(moves, { From = current, To = to, Start = clock, Finish = clock + duration })
		clock += duration
		current = to
	end
	local function pause(low: number, high: number)
		clock += random:NextNumber(low, high)
	end
	local gap = math.log(final / start)
	if math.abs(gap) < 0.08 then
		-- Already about right: nudge away a little to check it, the way a player tests a size.
		local away = (if random:NextNumber() < 0.5 then -1 else 1) * random:NextNumber(0.12, 0.3)
		move(start * math.exp(away), random:NextNumber(0.6, 1))
	else
		local reach = if random:NextNumber() < 0.35 then random:NextNumber(1.1, 1.35) else random:NextNumber(0.6, 0.9)
		move(start * math.exp(gap * reach), random:NextNumber(0.8, 1.3))
	end
	local corrections = if careful then random:NextInteger(3, 4) else random:NextInteger(1, 3)
	for index = 1, corrections do
		if careful then
			pause(0.8, 2)
		else
			pause(0.45, 1.5)
		end
		if random:NextNumber() < 0.18 then
			pause(1.2, 3)
		end
		local to = if index == corrections
			then final
			else current * math.exp(math.log(final / current) * random:NextNumber(0.55, 1.2))
		move(to, random:NextNumber(0.35, 0.9))
	end
	pause(0.5, 1.3)
	local lockAt = clock
	-- Never run the timer down: a plan that ran long is squeezed in ahead of the deadline.
	local latest = deadline - BotPlayer.LockMargin
	if lockAt > latest then
		local span = math.max(0.5, latest - now)
		local factor = span / math.max(0.001, lockAt - now)
		for _, step in moves do
			step.Start = now + (step.Start - now) * factor
			step.Finish = now + (step.Finish - now) * factor
		end
		lockAt = now + span
	end
	return { Start = start, Final = final, Moves = moves, LockAt = lockAt }
end

function BotPlayer.Sample(plan: any, now: number): number
	local value = plan.Start
	for _, step in plan.Moves do
		if now >= step.Finish then
			value = step.To
		elseif now > step.Start then
			return step.From * (step.To / step.From) ^ smooth((now - step.Start) / (step.Finish - step.Start))
		else
			return value
		end
	end
	return value
end

-- Given a table's seated occupants (seat index -> player or bot) and its match players (if any), returns every bot
-- there once no human is seated any more. Bootstrap uses this to cancel an abandoned active game; ambient population
-- NPCs may still sit at a pre-match table waiting for somebody, while explicit practice bots are removed.
function BotPlayer.Orphaned(occupants: { [number]: any }, matchPlayers: { any }?, isBot: (any) -> boolean): { any }
	local bots, humans = {}, 0
	for _, occupant in occupants do
		if isBot(occupant) then
			table.insert(bots, occupant)
		else
			humans += 1
		end
	end
	for _, player in matchPlayers or {} do
		if isBot(player) and not table.find(bots, player) then
			table.insert(bots, player)
		end
	end
	return if humans == 0 then bots else {}
end

return BotPlayer

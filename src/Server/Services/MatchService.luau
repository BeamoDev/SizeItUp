--!strict
-- Pure state machine. Adapters supply server time, IDs, transport and table cleanup.
local MatchService = {}
MatchService.__index = MatchService
local function avatarUserId(player: any): number
	if typeof(player) == "table" then
		local avatar = rawget(player, "AvatarUserId")
		if type(avatar) == "number" and avatar > 0 then return avatar end
	end
	return player.UserId
end
function MatchService.new(config: any, rounds: any, currency: any, adapters: any)
	return setmetatable(
		{ Config = config, Rounds = rounds, Currency = currency, Adapters = adapters, Matches = {}, ByPlayer = {}, TickMatches = {} },
		MatchService
	)
end
function MatchService.Publish(self: any, match: any)
	for _, player in match.Players do
		-- A released spectator may already be in another match. Old results must never reclaim their HUD.
		if self.ByPlayer[player] == match then self.Adapters.Send(player, self:Snapshot(match, player)) end
	end
	self.Adapters.StateChanged(match)
end
function MatchService.Start(self: any, tableRecord: any, players: { any }, arena: any)
	assert(#players >= 2 and #players <= 4, "Invalid match capacity")
	local mode = tableRecord.Mode or self.Config.DefaultMode
	assert(self.Config.Modes[mode], "Unknown game mode")
	local lives = if mode == "SuddenDeath" then 1 else self.Config.StartingHearts
	local unique = {}
	for _, player in players do
		assert(not unique[player] and not self.ByPlayer[player], "Player already matched")
		unique[player] = true
	end
	local match = {
		MatchId = self.Adapters.NewId(),
		Table = tableRecord,
		Players = table.clone(players),
		Hearts = table.create(#players, lives),
		StartingHearts = lives,
		Scores = table.create(#players, 0),
		CurrentRound = 0,
		Prize = tableRecord.Prize or self.Config.WinnerCash,
		Mode = mode,
		AccuracyStreaks = table.create(#players, 0),
		ComboStreak = table.create(#players, 0),
		Departed = {},
		Arena = arena,
		Buckets = {},
		Finished = false,
		Reward = 0,
		Selection = {},
		TurnOrder = {},
		TurnIndex = 0,
		RoundState = "ROUND_INTRO",
		Deadline = self.Adapters.Now(),
	}
	self.Matches[match.MatchId] = match
	-- Reserve before any adapter can fail so table recovery can find the match.
	for _, player in match.Players do
		self.ByPlayer[player] = match
	end
	match.PetTurns, match.PetRosters, match.PetEffects, match.PetState, match.Notices = {}, {}, {}, {}, {}
	for index, player in players do
		match.PetTurns[index] = 0
		match.PetRosters[index] = if self.Adapters.Pets then self.Adapters.Pets(player) else {}
		match.PetEffects[index] = if self.Adapters.PetEffects
			then self.Adapters.PetEffects(match.PetRosters[index])
			else {}
		match.PetState[index] = { Shield = false, SecondUsed = false, ReviveUsed = false }
		match.Notices[index] = {}
	end
	self:NextRound(match)
	return match
end
function MatchService.NextRound(self: any, match: any)
	match.CurrentObjectPair = self.Rounds:Create(match.CurrentObjectPair, match.Selection, match.Mode == "Endless")
	match.CurrentRound += 1
	match.RequiredAccuracy = if match.Mode == "Endless" then self.Config.RequiredAccuracy(match.CurrentRound) else nil
	match.RoundId = self.Adapters.NewId()
	match.Guesses = table.create(#match.Players, match.CurrentObjectPair.InitialGuess)
	match.Buckets = {}
	match.TurnIndex, match.ActiveIndex, match.TurnId = 0, nil, nil
	match.LockedAt, match.LockedAutomatically = nil, nil
	match.TurnOrder = {}
	-- Advance from last round's starting seat, skipping eliminated/departed players.
	local previousStart = match.StartSeat or 0
	for offset = 1, #match.Players do
		local index = (previousStart + offset - 1) % #match.Players + 1
		if match.Hearts[index] > 0 and not match.Departed[index] then
			table.insert(match.TurnOrder, index)
		end
	end
	match.StartSeat = match.TurnOrder[1] or previousStart
	match.GuessDirty, match.LockRequested, match.LastWatchPublish = false, false, -math.huge
	match.Reveal = nil
	match.RevealStartedAt = nil
	match.HeartAppliedAt = nil
	-- How much of each player's turn they used this round (badges: a fast lock, or using almost all the time).
	match.TurnUsed = {}
	-- Publish the first playable turn immediately, with its owner and turn ID.
	self:AdvanceTurn(match, self.Adapters.Now())
end
-- Short kid-friendly messages ("Bear's Shield saved your heart!") delivered in the player's snapshot.
function MatchService.Notice(self: any, match: any, index: number, text: string, kind: string?)
	local list = match.Notices and match.Notices[index]
	if not list or text == "" then
		return
	end
	table.insert(list, { Id = self.Adapters.NewId(), Text = text, Kind = kind or "Help", At = self.Adapters.Now() })
	while #list > 6 do
		table.remove(list, 1)
	end
end
-- The accuracy this player must reach: the round's target minus their pets' Lower Bar.
function MatchService.RequiredFor(self: any, match: any, index: number): number?
	if not match.RequiredAccuracy then
		return nil
	end
	local bar = match.PetEffects[index] and match.PetEffects[index].LowerBar
	return math.max(1, match.RequiredAccuracy - (if bar then bar.Power else 0))
end
function MatchService.AbilityAdjust(self: any, match: any): any
	local adjust = {}
	for index in match.Players do
		local effects, state = match.PetEffects[index] or {}, match.PetState[index]
		adjust[index] = {
			Bar = if effects.LowerBar then effects.LowerBar.Power else 0,
			Second = if effects.SecondChance and not state.SecondUsed then effects.SecondChance.Power else nil,
			Shield = state.Shield,
			Revive = effects.Revive ~= nil and not state.ReviveUsed,
		}
	end
	return adjust
end
-- Consume the save a pet just made (the round's outcome already decided it) and announce it.
function MatchService.CommitSave(self: any, match: any, index: number, kind: string)
	local state, effects = match.PetState[index], match.PetEffects[index]
	if kind == "SecondChance" then
		state.SecondUsed = true
		self:Notice(match, index, "Second Chance! Heart kept!", "Help")
	elseif kind == "Shield" then
		state.Shield = false
		self:Notice(match, index, "Shield saved your heart!", "Help")
	elseif kind == "Revive" then
		state.ReviveUsed = true
		self:Notice(match, index, "Revived with 1 heart!", "Help")
	end
end
-- Classic-style single heart loss: a Shield or Revive can absorb it.
function MatchService.ProtectLoss(self: any, match: any, index: number): boolean
	local state, effects = match.PetState[index], match.PetEffects[index]
	if state.Shield then
		self:CommitSave(match, index, "Shield")
		return true
	end
	if effects.Revive and not state.ReviveUsed and match.Hearts[index] == 1 then
		self:CommitSave(match, index, "Revive")
		return true
	end
	return false
end
-- Settle an already-scored Classic/Sudden Death result exactly once. Departure handling uses the same path as
-- TABLE_RETURN so a player leaving during the reveal cannot bypass (or incorrectly consume past) a pet save.
function MatchService.ApplyClassicRound(self: any, match: any, now: number)
	if match.HeartAppliedAt then
		return
	end
	local loser = match.Reveal and match.Reveal.Loser
	if loser and loser ~= 0 and match.Hearts[loser] > 0 and not self:ProtectLoss(match, loser) then
		match.Hearts[loser] = math.max(0, match.Hearts[loser] - 1)
		if match.Hearts[loser] == 0 then
			self:Eliminated(match, loser)
		end
	end
	match.HeartAppliedAt = now
end
-- Streak/combo bonus: a within-10%-accuracy round extends this player's ComboStreak; anything worse resets it to 0.
-- Called once, right after match.Reveal is scored (every mode, since Reveal.Errors always covers every seated player).
-- The streak itself only feeds Config.ComboMultiplier/ComboWinsBonus at the eventual Cash/Wins award; it never touches
-- hearts or scoring here.
function MatchService.UpdateCombo(self: any, match: any)
	match.ComboStreak = match.ComboStreak or table.create(#match.Players, 0)
	for index, hp in match.Hearts do
		if hp > 0 and not match.Departed[index] then
			local accuracy = self.Rounds.Math.Accuracy(match.Reveal.Errors[index])
			local streak = if accuracy + 1e-7 >= self.Config.ComboAccuracyThreshold
				then (match.ComboStreak[index] or 0) + 1
				else 0
			match.ComboStreak[index] = streak
			if streak > self.Config.ComboBonusThreshold then
				self:Notice(match, index, string.format("Combo x%.1f!", self.Config.ComboMultiplier(streak)), "Help")
			end
		end
	end
end
-- Sharp Eye pets pay cash for a great guess, once per round.
function MatchService.AwardSharpEye(self: any, match: any)
	if match.SharpEyeRound == match.CurrentRound or not match.Reveal or not self.Adapters.PetCash then
		return
	end
	match.SharpEyeRound = match.CurrentRound
	for index, error in match.Reveal.Errors do
		local effect = match.PetEffects[index] and match.PetEffects[index].SharpEye
		if
			effect
			and not match.Departed[index]
			and self.Rounds.Math.Accuracy(error) >= self.Config.SharpEyeAccuracy
		then
			self.Adapters.PetCash(match, index, effect.Power)
			local grouped = string.gsub(string.reverse(tostring(effect.Power)), "(%d%d%d)", "%1,")
			grouped = string.gsub(string.reverse(grouped), "^,", "")
			self:Notice(
				match,
				index,
				"Sharp guess! +$" .. grouped,
				"Help"
			)
		end
	end
end
-- Every player (not only Sharp Eye pet owners) earns a small Cash bonus for a really good guess, once per round. It pays
-- and syncs right away (via the same PetCash adapter) so the Lobby balance visibly ticks up while the results/table
-- return is still on screen.
function MatchService.AwardGreatGuess(self: any, match: any)
	if match.GreatGuessRound == match.CurrentRound or not match.Reveal or not self.Adapters.PetCash then
		return
	end
	match.GreatGuessRound = match.CurrentRound
	for index, error in match.Reveal.Errors do
		if not match.Departed[index] and self.Rounds.Math.Accuracy(error) >= self.Config.GreatGuessAccuracy then
			self.Adapters.PetCash(match, index, self.Config.GreatGuessCash)
			self:Notice(match, index, "Great guess! +$" .. self.Config.GreatGuessCash, "Help")
		end
	end
end
function MatchService.AdvanceTurn(self: any, match: any, now: number)
	match.ActiveHint, match.HintCount, match.HintUsed, match.FreeHint = nil, 0, false, false
	match.InkUsed, match.Ink, match.Effects = {}, nil, {}
	match.LockRequested, match.GuessDirty = false, false
	match.LockedAt, match.LockedAutomatically = nil, nil
	repeat
		match.TurnIndex += 1
		match.ActiveIndex = match.TurnOrder[match.TurnIndex]
	until not match.ActiveIndex or match.Hearts[match.ActiveIndex] > 0
	if match.ActiveIndex then
		match.TurnId = self.Adapters.NewId()
		match.RoundState = "GUESSING"
		match.Deadline = now + self.Config.GuessSeconds
		match.PetTurns[match.ActiveIndex] += 1
		local owner = match.ActiveIndex
		if self.Adapters.PetTurn then
			local hearts, hint, messages, shield = self.Adapters.PetTurn(
				match.PetRosters[owner],
				match.PetTurns[owner],
				match.CurrentRound,
				match.Hearts[owner],
				match.StartingHearts
			)
			match.Hearts[owner] = hearts
			-- A pet only earns a free hint charge; the exact-size highlight starts when the player presses Hint.
			match.FreeHint = hint == true
			if shield then
				match.PetState[owner].Shield = true
			end
			for _, text in messages or {} do
				self:Notice(match, owner, text, "Help")
			end
		end
		-- Passive pet abilities that shape this turn.
		local effects = match.PetEffects[owner]
		if effects.ExtraTime then
			match.Deadline += effects.ExtraTime.Power
			self:Notice(match, owner, "+" .. effects.ExtraTime.Power .. " seconds!", "Help")
		end
		if effects.LowerBar and match.RequiredAccuracy then
			self:Notice(match, owner, "Target lowered by " .. effects.LowerBar.Power .. "!", "Help")
		end
		match.TurnStartedAt, match.TurnLength = now, match.Deadline - now
	else
		match.TurnId = nil
		match.Reveal = self.Rounds:Score(
			match.CurrentObjectPair,
			match.Guesses,
			match.Hearts,
			match.RequiredAccuracy,
			match.AccuracyStreaks,
			match.Mode,
			self:AbilityAdjust(match)
		)
		self:UpdateCombo(match)
		if match.Mode == "BestOfFive" then
			match.Reveal.Loser = 0
			match.Reveal.RoundWinners = {}
			local best = -1
			for index, hp in match.Hearts do
				if hp > 0 then
					best = math.max(best, self.Rounds.Math.Accuracy(match.Reveal.Errors[index]))
				end
			end
			for index, hp in match.Hearts do
				if hp > 0 then
					match.Reveal.RoundWinners[index] = math.abs(
						self.Rounds.Math.Accuracy(match.Reveal.Errors[index]) - best
					) < 1e-7
				end
			end
		end
		match.RoundState = "ROUND_REVEAL"
		match.RevealStartedAt = now
		if self.Adapters.RoundRevealed then
			for index, player in match.Players do
				if not match.Departed[index] then
					self.Adapters.RoundRevealed(player)
				end
			end
		end
		local count = 0
		for _, hearts in match.Hearts do
			if hearts > 0 then
				count += 1
			end
		end
		match.Deadline = now + self.Config.RevealDuration(count)
	end
	self:Publish(match)
end
function MatchService.ShowLock(self: any, match: any, now: number)
	match.ActiveHint, match.Ink, match.Effects = nil, nil, {}
	match.LockedAt, match.LockedAutomatically = now, not match.LockRequested
	if match.ActiveIndex and match.TurnStartedAt then
		match.TurnUsed = match.TurnUsed or {}
		match.TurnUsed[match.ActiveIndex] = {
			Seconds = now - match.TurnStartedAt,
			Length = match.TurnLength or self.Config.GuessSeconds,
			Manual = match.LockRequested == true,
		}
	end
	match.RoundState, match.Deadline = "TURN_LOCKED", now + self.Config.LockInSeconds
	match.GuessDirty = false
	self:Publish(match)
end
function MatchService.GrantHint(self: any, match: any, now: number)
	match.HintUsed = true
	match.HintCount = (match.HintCount or 0) + 1
	-- Purchased credits and pet hints grant the same exact-size visual. Snapshot sends this only to the active owner.
	match.ActiveHint = {
		Id = self.Adapters.NewId(),
		Actual = match.CurrentObjectPair.Actual,
		StartedAt = now,
		ExpiresAt = math.min(match.Deadline, now + (self.Config.HintSeconds or 10)),
	}
	self:Notice(match, match.ActiveIndex, self.Config.HintMessage.Body, "Help")
end
-- Sabotage: a watcher sets one of these off on every player's screen in the match (the thrower watches it land too).
-- Free, limited per watcher per turn, and it never reveals anything about the answer. Different effects run together;
-- only a kind that is already running cannot be started again until it ends.
local SABOTAGE = {
	Ink = { Label = "Ink splat", Notice = "sent Ink splat!" },
	Lag = { Label = "Lag", Notice = "sent Lag!" },
	FogBank = { Label = "Fog bank", Notice = "sent Fog!" },
	Wobble = { Label = "Wobble", Notice = "sent Wobble!" },
}
function MatchService.CanUseInkSplat(self: any, match: any, player: any): boolean
	local index = table.find(match.Players, player)
	local now = self.Adapters.Now()
	return index ~= nil
		and not match.Departed[index]
		and not match.Finished
		and match.RoundState == "GUESSING"
		and match.ActiveIndex ~= nil
		and index ~= match.ActiveIndex
		and not match.LockRequested
		and now < match.Deadline
		and (match.InkUsed and match.InkUsed[index] or 0)
			< (self.Config.SabotagesPerTurn or 3) + (if match.PetEffects[index].InkRefill
				then match.PetEffects[index].InkRefill.Power
				else 0)
end
-- The Sabotage adapters are optional so existing tests that never supply them keep testing the mechanic for
-- free; Bootstrap wires them for real so every use spends a purchased SabotageCredit (no product, no throw).
function MatchService.UseInkSplat(self: any, player: any, matchId: any, roundId: any, turnId: any, kind: any?): (boolean, string?)
	local match = self.ByPlayer[player]
	kind = kind or "Ink"
	if type(kind) ~= "string" or not SABOTAGE[kind] then
		return false
	end
	if
		not match
		or match.MatchId ~= matchId
		or match.RoundId ~= roundId
		or match.TurnId ~= turnId
		or not self:CanUseInkSplat(match, player)
	then
		return false
	end
	local now = self.Adapters.Now()
	match.Effects = match.Effects or {}
	for _, running in match.Effects do
		if running.Kind == kind and now < running.ExpiresAt then
			return false
		end
	end
	if self.Adapters.SpendSabotageCredit and not self.Adapters.SpendSabotageCredit(player) then
		return false, "NoCredit"
	end
	local thrower = table.find(match.Players, player)
	local effects = match.PetEffects[thrower]
	local used = (match.InkUsed[thrower] or 0) + 1
	match.InkUsed[thrower] = used
	local longer = if effects.LongInk then effects.LongInk.Power else 0
	-- Each effect gets its own random length between InkSplatMinSeconds and InkSplatSeconds.
	local shortest = self.Config.InkSplatMinSeconds or self.Config.InkSplatSeconds
	local roll = if self.Adapters.Random then self.Adapters.Random() else math.random()
	local seconds = shortest + (self.Config.InkSplatSeconds - shortest) * roll
	local event = {
		Id = self.Adapters.NewId(),
		Kind = kind,
		StartedAt = now,
		ExpiresAt = math.min(now + seconds + longer, match.Deadline),
		Seed = (math.floor(now * 1000) + match.TurnIndex * 7919) % 1000003 + 1,
		ThrowerUserId = player.UserId,
	}
	table.insert(match.Effects, event)
	match.Ink = event
	for index in match.Players do
		if index ~= thrower and not match.Departed[index] then
			self:Notice(match, index, string.sub(player.DisplayName, 1, 12) .. " " .. SABOTAGE[kind].Notice, "Sabotage")
		end
	end
	-- The thrower is told it worked.
	self:Notice(match, thrower, SABOTAGE[kind].Label .. " sent!", "Help")
	if used > 1 and effects.InkRefill then
		self:Notice(match, thrower, "Extra ink!", "Help")
	end
	self:Publish(match)
	return true
end
-- A hint costs Robux: a pet-earned free hint is used first, then one saved HintCredit (bought with the Hint developer
-- product; SpendHintCredit adapter). With neither, it returns false, "NoCredit" and Bootstrap prompts the purchase,
-- replaying this request once the receipt grants the credit. Without that adapter (tests) HintCash, if any, is spent.
function MatchService.BuyHint(self: any, player: any, matchId: any, roundId: any, turnId: any): (boolean, string?)
	local match = self.ByPlayer[player]
	local now = self.Adapters.Now()
	if
		not match
		or match.Finished
		or match.MatchId ~= matchId
		or match.RoundId ~= roundId
		or match.TurnId ~= turnId
		or match.RoundState ~= "GUESSING"
		or match.LockRequested
		or match.Players[match.ActiveIndex] ~= player
		or (match.HintCount or 0) >= (self.Config.MaxHints or 4)
		or (match.ActiveHint and now < match.ActiveHint.ExpiresAt)
		or match.Hearts[match.ActiveIndex] <= 0
		or now >= match.Deadline
	then
		return false
	end
	-- Spend and activate without yielding; repeated clicks during a hint cannot charge again.
	-- A pet-earned free hint is used first and costs nothing.
	if match.FreeHint then
		match.FreeHint = false
	elseif self.Adapters.SpendHintCredit then
		if not self.Adapters.SpendHintCredit(player) then
			return false, "NoCredit"
		end
	elseif (self.Config.HintCash or 0) > 0 and not self.Currency:Spend(player, self.Config.HintCash) then
		return false
	end
	self:GrantHint(match, now)
	self:Publish(match)
	return true
end
-- Buys a lost heart back whenever its owner clicks one during a live match, including while another player is guessing
-- or during a reveal/reaction. The MatchId still binds the request to this player's live match; round/turn IDs are
-- intentionally advisory so a receipt that arrives after the turn changes can still fulfil the purchase.
function MatchService.BuyHeart(self: any, player: any, matchId: any, roundId: any, turnId: any): (boolean, string?)
	local match = self.ByPlayer[player]
	local index = match and table.find(match.Players, player)
	if
		not match
		or match.Finished
		or match.MatchId ~= matchId
		or not index
		or match.Departed[index]
		or match.Mode == "BestOfFive"
	then
		return false
	end
	if match.Hearts[index] >= match.StartingHearts then
		return false
	end
	if self.Adapters.SpendHeartCredit then
		if not self.Adapters.SpendHeartCredit(player) then
			return false, "NoCredit"
		end
	else
		local cost = self.Config.HeartCash or 0
		if cost > 0 and not self.Currency:Spend(player, cost) then
			return false
		end
	end
	match.Hearts[index] += 1
	self:Publish(match)
	return true
end
-- Queue completion for Tick's protected state-machine path. The final value and
-- lock are accepted atomically, independently of the live-preview rate limit.
function MatchService.Lock(self: any, player: any, matchId: any, roundId: any, turnId: any, guess: any): boolean
	local match = self.ByPlayer[player]
	if
		not match
		or match.Finished
		or match.MatchId ~= matchId
		or match.RoundId ~= roundId
		or match.RoundState ~= "GUESSING"
		or match.TurnId ~= turnId
		or match.LockRequested
		or match.Players[match.ActiveIndex] ~= player
		or match.Hearts[match.ActiveIndex] <= 0
		or self.Adapters.Now() >= match.Deadline
	then
		return false
	end
	local pair = match.CurrentObjectPair
	if not self.Rounds.Math.IsGuess(guess, pair.GuessMinimum, pair.GuessMaximum) then
		return false
	end
	match.Guesses[match.ActiveIndex], match.LockRequested = guess, true
	if self.Adapters.GuessLocked then
		self.Adapters.GuessLocked(player)
	end
	return true
end
function MatchService.Submit(self: any, player: any, matchId: any, roundId: any, guess: any): boolean
	local match = self.ByPlayer[player]
	if
		not match
		or match.Finished
		or match.MatchId ~= matchId
		or match.RoundId ~= roundId
		or match.RoundState ~= "GUESSING"
	then
		return false
	end
	local index = table.find(match.Players, player)
	if not index or index ~= match.ActiveIndex or match.Hearts[index] <= 0 or match.LockRequested then
		return false
	end
	local now = self.Adapters.Now()
	if now >= match.Deadline then
		return false
	end
	local bucket = match.Buckets[player] or { Tokens = self.Config.GuessBurst, At = now }
	match.Buckets[player] = bucket
	bucket.Tokens = math.min(
		self.Config.GuessBurst,
		bucket.Tokens + math.max(0, now - bucket.At) * self.Config.GuessUpdatesPerSecond
	)
	bucket.At = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	local pair = match.CurrentObjectPair
	if not self.Rounds.Math.IsGuess(guess, pair.GuessMinimum, pair.GuessMaximum) then
		return false
	end
	match.Guesses[index] = guess
	match.GuessDirty = true
	return true
end
function MatchService.Finish(self: any, match: any, winner: number?, reason: string)
	if match.Finished then
		return
	end
	-- Mark settled BEFORE callbacks; reentrant departures cannot issue a second reward.
	match.Finished = true
	match.Winner = winner
	match.Reason = reason
	match.RoundState = "MATCH_END"
	-- A finished match plays the whole end screen; a cancelled one is over almost at once.
	match.Deadline = self.Adapters.Now()
		+ (if winner or match.Completed then self.Config.EndSeconds else self.Config.EndCancelSeconds)
	if winner then
		match.Reward = self.Currency:Award(match, match.Players[winner], match.Prize)
		if self.Adapters.Settle then
			self.Adapters.Settle(match, winner)
		end
	end
	-- Everyone still in a finished (not cancelled) match completed a game: analytics hook.
	if (winner or match.Completed) and self.Adapters.Finished then
		for index, player in match.Players do
			if not match.Departed[index] then
				pcall(self.Adapters.Finished, player, match)
			end
		end
	end
	self:Publish(match)
end
function MatchService.Eliminated(self: any, match: any, index: number)
	if self.Adapters.Eliminated then
		self.Adapters.Eliminated(match, index)
	end
end
-- Apply every heart before callbacks; a completed round can only settle once.
function MatchService.ApplyChainRound(self: any, match: any, now: number)
	if match.HeartAppliedAt then
		return
	end
	match.HeartAppliedAt = now
	local eliminated = {}
	for index, outcome in match.Reveal.Outcomes do
		if match.Hearts[index] > 0 then
			match.Hearts[index] = outcome.HeartsAfter
			if outcome.HeartsAfter == 0 then
				table.insert(eliminated, index)
			end
			match.AccuracyStreaks[index] = outcome.StreakAfter
			if outcome.Saved then
				self:CommitSave(match, index, outcome.Saved)
			end
		end
	end
	for _, index in eliminated do
		self:Eliminated(match, index)
	end
	if self.Adapters.RoundComplete then
		self.Adapters.RoundComplete(match)
	end
end
function MatchService.ForfeitChain(self: any, match: any, missing: any)
	if match.Finished then
		return
	end
	local changed = false
	for index in match.Players do
		if missing[index] and not match.Departed[index] then
			match.Departed[index] = true
			changed = changed or match.Hearts[index] > 0
		end
	end
	if not changed then
		return
	end
	-- Preserve a scored terminal result when somebody exits during its animation.
	if match.Reveal then
		local projected = {}
		for index, outcome in match.Reveal.Outcomes do
			if match.Hearts[index] > 0 and outcome.HeartsAfter > 0 then
				table.insert(projected, index)
			end
		end
		if #projected <= 1 then
			self:ApplyChainRound(match, self.Adapters.Now())
			match.Completed = true
			self:Finish(match, projected[1], "Match complete")
			return
		end
	end
	for index in match.Players do
		if missing[index] and match.Hearts[index] > 0 then
			match.Hearts[index] = 0
			match.AccuracyStreaks[index] = 0
			self:Eliminated(match, index)
		end
	end
	local survivors = {}
	for index, hp in match.Hearts do
		if hp > 0 then
			table.insert(survivors, index)
		end
	end
	if #survivors <= 1 then
		if match.Reveal and not match.HeartAppliedAt then
			self:ApplyChainRound(match, self.Adapters.Now())
			if survivors[1] and match.Hearts[survivors[1]] <= 0 then
				table.clear(survivors)
			end
		end
		match.Completed = true
		self:Finish(match, survivors[1], "Match ended by departure")
	else
		self:Publish(match)
	end
end
function MatchService.ApplyCupRound(self: any, match: any, now: number)
	if match.HeartAppliedAt then
		return
	end
	match.HeartAppliedAt = now
	for index, hp in match.Hearts do
		if hp > 0 and not match.Departed[index] then
			match.Scores[index] += self.Rounds.Math.Accuracy(match.Reveal.Errors[index])
		end
	end
end
function MatchService.FinishCup(self: any, match: any)
	local best, winner, tied = -1, nil, false
	for index, hp in match.Hearts do
		if hp > 0 and not match.Departed[index] then
			local score = match.Scores[index]
			if score > best + 1e-7 then
				best, winner, tied = score, index, false
			elseif math.abs(score - best) <= 1e-7 then
				tied = true
			end
		end
	end
	match.Completed = true
	self:Finish(match, if tied then nil else winner, "Five rounds complete")
end
function MatchService.Forfeit(self: any, match: any, missing1: any, missing2: boolean?)
	if match.Mode == "BestOfFive" then
		if match.Finished then
			return
		end
		local missing = if type(missing1) == "table" then missing1 else { missing1, missing2 }
		if not table.find(missing, true) then
			return
		end
		-- Once all five rounds are scored, leaving during the review cannot change the winner.
		if match.Reveal and match.CurrentRound >= self.Config.Modes.BestOfFive.Rounds then
			self:ApplyCupRound(match, self.Adapters.Now())
			self:FinishCup(match)
			return
		end
		local changed = false
		for index in match.Players do
			if missing[index] and not match.Departed[index] then
				match.Departed[index], match.Hearts[index] = true, 0
				changed = true
				self:Eliminated(match, index)
			end
		end
		if not changed then
			return
		end
		local remaining = {}
		for index, hp in match.Hearts do
			if hp > 0 then
				table.insert(remaining, index)
			end
		end
		if #remaining <= 1 then
			match.Completed = #remaining == 1
			self:Finish(match, remaining[1], "Match ended by departure")
		else
			self:Publish(match)
		end
		return
	end
	if match.Mode == "Endless" then
		self:ForfeitChain(match, if type(missing1) == "table" then missing1 else { missing1, missing2 })
		return
	end
	if type(missing1) == "table" then
		local missing = missing1
		if match.Finished then
			return
		end
		if #match.Players == 2 then
			self:Forfeit(match, missing[1], missing[2])
			return
		end
		local activeMissing = false
		for index in match.Players do
			if missing[index] then
				match.Departed[index] = true
			end
			if missing[index] and match.Hearts[index] > 0 then
				activeMissing = true
			end
		end
		if not activeMissing then
			return
		end
		local changed = false
		if
			match.Reveal
			and not match.HeartAppliedAt
			and match.Reveal.Loser ~= 0
			and match.Hearts[match.Reveal.Loser] == 1
		then
			-- Preserve a scored elimination even if the player exits during its animation.
			self:ApplyClassicRound(match, self.Adapters.Now())
			changed = true
		end
		for index in match.Players do
			if missing[index] and match.Hearts[index] > 0 then
				match.Hearts[index] = 0
				self:Eliminated(match, index)
				changed = true
			end
		end
		if not changed then
			return
		end
		local survivors = {}
		for index, hearts in match.Hearts do
			if hearts > 0 then
				table.insert(survivors, index)
			end
		end
		if #survivors <= 1 then
			self:Finish(match, survivors[1], "Match ended by elimination")
		else
			self:Publish(match)
		end
		return
	end
	if match.Finished or not (missing1 or missing2) then
		return
	end
	if missing1 then match.Departed[1] = true end
	if missing2 then match.Departed[2] = true end
	if missing1 and missing2 then
		self:Finish(match, nil, "Cancelled: everyone left")
	elseif match.Hearts[1] == 0 or match.Hearts[2] == 0 then
		self:Finish(match, if match.Hearts[1] > 0 then 1 else 2, "Match complete")
	elseif
		match.Reveal
		and match.Reveal.Loser ~= 0
		and not match.HeartAppliedAt
		and match.Hearts[match.Reveal.Loser] == 1
	then
		-- Delaying the heart animation must not let an exit reverse a scored final round.
		self:ApplyClassicRound(match, self.Adapters.Now())
		if match.Hearts[match.Reveal.Loser] == 0 then
			self:Finish(match, 3 - match.Reveal.Loser, "Match complete")
		else
			self:Finish(match, if missing1 then 2 else 1, "Match ended by forfeit")
		end
	elseif missing1 or missing2 then
		self:Finish(match, if missing1 then 2 else 1, "Match ended by forfeit")
	end
end
function MatchService.Remove(self: any, match: any)
	if self.Matches[match.MatchId] ~= match then
		return
	end
	for _, player in match.Players do
		if self.ByPlayer[player] == match then
			self.ByPlayer[player] = nil
		end
	end
	-- Keep the match registered until cleanup succeeds. If an adapter fails transiently, the next heartbeat can retry
	-- the idempotent cleanup instead of losing the only reference while its table stays stuck in-match.
	self.Adapters.Cleanup(match)
	self.Matches[match.MatchId] = nil
end
function MatchService.Cancel(self: any, match: any, reason: string)
	self:Finish(match, nil, reason)
end
function MatchService.TickMatch(self: any, match: any, now: number)
	local expired = false
	if match.ActiveHint and now >= match.ActiveHint.ExpiresAt then
		match.ActiveHint = nil
		expired = true
	end
	for index = #(match.Effects or {}), 1, -1 do
		if now >= match.Effects[index].ExpiresAt then
			table.remove(match.Effects, index)
			expired = true
		end
	end
	if match.Ink and now >= match.Ink.ExpiresAt then
		match.Ink = nil
		expired = true
	end
	if expired then
		self:Publish(match)
	end
	if match.RoundState == "GUESSING" then
		if match.Hearts[match.ActiveIndex] <= 0 then
			self:AdvanceTurn(match, now)
		elseif match.LockRequested or now >= match.Deadline then
			self:ShowLock(match, now)
		elseif match.GuessDirty and now - match.LastWatchPublish >= self.Config.ClientSendInterval then
			match.GuessDirty, match.LastWatchPublish = false, now
			self:Publish(match)
		end
		return
	end
	if now < match.Deadline then
		return
	end
	if match.RoundState == "MATCH_END" then
		self:Remove(match)
	elseif match.RoundState == "ROUND_INTRO" or match.RoundState == "TURN_LOCKED" then
		self:AdvanceTurn(match, now)
	elseif match.RoundState == "ROUND_REVEAL" then
		match.RoundState = "TABLE_RETURN"
		match.Deadline = now + self.Config.TableReturnSeconds
		self:Publish(match)
	elseif match.RoundState == "TABLE_RETURN" then
		-- The cutscene shows one slot per player who played this round (still alive before hearts settle);
		-- players already out earlier are not shown again (ReactionCycle.Lineup uses the same rule).
		local shown = 0
		for _, hearts in match.Hearts do
			if hearts > 0 then
				shown += 1
			end
		end
		self:AwardSharpEye(match)
		self:AwardGreatGuess(match)
		if match.Mode == "BestOfFive" and not match.HeartAppliedAt then
			self:ApplyCupRound(match, now)
		elseif match.Mode == "Endless" then
			self:ApplyChainRound(match, now)
		elseif not match.HeartAppliedAt then
			self:ApplyClassicRound(match, now)
		end
		match.HeartAppliedAt = match.HeartAppliedAt or now
		match.RoundState = "TABLE_REACTION"
		match.Deadline = now + self.Config.TableReactionDuration(shown)
		self:Publish(match)
	elseif match.RoundState == "TABLE_REACTION" then
		local survivors = {}
		for index, hearts in match.Hearts do
			if hearts > 0 then
				table.insert(survivors, index)
			end
		end
		if #survivors <= 1 then
			match.Completed = true
			self:Finish(match, survivors[1], "Match complete")
		elseif match.Mode == "BestOfFive" and match.CurrentRound >= self.Config.Modes.BestOfFive.Rounds then
			self:FinishCup(match)
		else
			self:NextRound(match)
		end
	end
end
function MatchService.Tick(self: any)
	local now = self.Adapters.Now()
	-- TickMatch can remove its match. Keep the stable iteration snapshot, but reuse it across the 20 Hz loop.
	local pending = self.TickMatches or {}
	self.TickMatches = pending
	table.clear(pending)
	for _, match in self.Matches do
		table.insert(pending, match)
	end
	for _, match in pending do
		if self.Matches[match.MatchId] ~= match then
			continue
		end
		local ok, err = xpcall(function()
			self:TickMatch(match, now)
		end, debug.traceback)
		if not ok then
			self.Adapters.Warn(err)
			-- Remove mappings even if presentation/transport itself failed.
			pcall(function()
				self:Cancel(match, "Cancelled: server error")
			end)
			local removed, removeError = pcall(function()
				self:Remove(match)
			end)
			if not removed then
				self.Adapters.Warn(removeError)
			end
		end
	end
end
function MatchService.Snapshot(self: any, match: any, player: any)
	local own = table.find(match.Players, player) or 1
	local other = if own == 1 then 2 else 1
	for index in match.Players do
		if index ~= own and match.Hearts[index] > 0 then
			other = index
			break
		end
	end
	local pair = match.CurrentObjectPair
	local function publicObject(id: string)
		local source = self.Rounds.Catalog[id]
		return {
			Id = source.Id,
			DisplayName = source.DisplayName,
			ModelName = source.ModelName,
			MeasurementType = source.MeasurementType,
		}
	end
	local snapshot: any = {
		State = match.RoundState,
		MatchId = match.MatchId,
		RoundId = match.RoundId,
		Mode = match.Mode,
		RequiredAccuracy = self:RequiredFor(match, own),
		AccuracyStreak = match.AccuracyStreaks[own],
		Combo = match.ComboStreak and match.ComboStreak[own] or 0,
		ModeName = self.Config.Modes[match.Mode].Name,
		RoundLimit = self.Config.Modes[match.Mode].Rounds,
		TotalAccuracy = match.Scores[own],
		NextMilestone = (if match.HeartAppliedAt
			then math.floor(match.CurrentRound / self.Config.ChainMilestoneRounds) + 1
			else math.ceil(match.CurrentRound / self.Config.ChainMilestoneRounds)) * self.Config.ChainMilestoneRounds,
		Round = match.CurrentRound,
		Deadline = match.Deadline,
		Arena = match.Arena,
		YourHearts = match.Hearts[own],
		OpponentHearts = match.Hearts[other],
		OpponentName = match.Players[other].DisplayName,
		OpponentUserId = match.Players[other].UserId,
		OpponentAvatarUserId = avatarUserId(match.Players[other]),
		YourUserId = player.UserId,
		YourAvatarUserId = avatarUserId(player),
		Eliminated = match.Hearts[own] <= 0,
		CanLeaveSpectating = not match.Finished and match.Hearts[own] <= 0 and not match.Departed[own],
		Prize = match.Prize,
		Participants = {},
		TurnId = match.TurnId,
		TurnIndex = match.TurnIndex,
		TurnCount = #match.TurnOrder,
		CanGuess = match.RoundState == "GUESSING"
			and own == match.ActiveIndex
			and not match.LockRequested
			and match.Hearts[own] > 0,
	}
	snapshot.CanUseInkSplat = self:CanUseInkSplat(match, player)
	-- Recent messages for this player only ("Bear's Shield saved your heart!", "Beamo sent Ink splat!").
	snapshot.Notices = {}
	local noticeNow = self.Adapters.Now()
	for _, notice in match.Notices[own] or {} do
		if noticeNow - notice.At <= 10 then
			table.insert(snapshot.Notices, table.clone(notice))
		end
	end
	snapshot.PetShield = match.PetState[own].Shield
	local ink = match.Ink
	-- Everyone in the match gets the event and renders it, the thrower included (they see it hit the other player).
	if not match.Finished and ink and self.Adapters.Now() < ink.ExpiresAt then
		snapshot.InkSplat = table.clone(ink)
	end
	-- Every effect still running (the newest is also InkSplat, for older clients).
	if not match.Finished and match.Effects then
		local live = {}
		for _, event in match.Effects do
			if self.Adapters.Now() < event.ExpiresAt then
				table.insert(live, table.clone(event))
			end
		end
		if #live > 0 then
			snapshot.InkSplats = live
			snapshot.InkSplat = snapshot.InkSplat or live[#live]
		end
	end
	if snapshot.CanGuess and self.Adapters.Now() < match.Deadline then
		snapshot.HintCash = self.Config.HintCash
		snapshot.HintUsed = match.HintUsed == true
		snapshot.FreeHint = match.FreeHint == true
		local hintNow = self.Adapters.Now()
		local activeHint = match.ActiveHint and hintNow < match.ActiveHint.ExpiresAt
		snapshot.CanBuyHint = (match.HintCount or 0) < (self.Config.MaxHints or 4)
			and not activeHint
			and (
				(self.Config.HintCash or 0) <= 0
				or match.FreeHint == true
				or self.Currency:GetBalance(player) >= self.Config.HintCash
			)
		if activeHint and match.RoundState == "GUESSING" then
			snapshot.Hint = table.clone(match.ActiveHint)
		end
	end
	if match.ActiveIndex then
		local active = match.Players[match.ActiveIndex]
		snapshot.ActivePlayerUserId, snapshot.ActivePlayerName = active.UserId, active.DisplayName
		snapshot.ActivePlayerAvatarUserId = avatarUserId(active)
		snapshot.ActivePlayerUsername = active.Name or active.DisplayName
		snapshot.WatchedGuess = match.Guesses[match.ActiveIndex]
	end
	if match.RoundState == "TURN_LOCKED" then
		snapshot.LockedAt, snapshot.LockedAutomatically = match.LockedAt, match.LockedAutomatically
		for turn = match.TurnIndex + 1, #match.TurnOrder do
			local index = match.TurnOrder[turn]
			if match.Hearts[index] > 0 then
				snapshot.NextPlayerName = match.Players[index].DisplayName
				break
			end
		end
	end
	for index, participant in match.Players do
		table.insert(
			snapshot.Participants,
			{
				UserId = participant.UserId,
				AvatarUserId = avatarUserId(participant),
				Name = participant.DisplayName,
				Username = participant.Name or participant.DisplayName,
				Hearts = match.Hearts[index],
				Points = match.Scores[index],
			}
		)
	end
	if pair then
		snapshot.Reference = publicObject(pair.ReferenceId)
		snapshot.Target = publicObject(pair.TargetId)
		snapshot.Reference.Hue, snapshot.Target.Hue = pair.ReferenceHue, pair.TargetHue
		snapshot.ReferenceMeters = pair.ReferenceMeters
		snapshot.GuessMinimum, snapshot.GuessMaximum = pair.GuessMinimum, pair.GuessMaximum
		snapshot.Guess = match.Guesses[own]
	end
	if match.RoundState == "TABLE_RETURN" or match.RoundState == "TABLE_REACTION" then
		local focus = if match.Reveal.Loser ~= 0 then match.Reveal.Loser else other
		if match.Reveal.Outcomes then
			snapshot.HeartChanges = {}
			for index, outcome in match.Reveal.Outcomes do
				if outcome.HeartDelta ~= 0 and not match.Departed[index] then
					table.insert(
						snapshot.HeartChanges,
						{ UserId = match.Players[index].UserId, HeartDelta = outcome.HeartDelta }
					)
					if index == own then
						focus = own
					end
				end
			end
		end
		local target = match.Players[focus]
		snapshot.TableFocusUserId = target.UserId
		if self.Adapters.ReactionView then
			snapshot.TableView = self.Adapters.ReactionView(match, player, target)
		end
		snapshot.HeartAppliedAt = match.HeartAppliedAt
		if match.Reveal.Loser ~= 0 and not match.Reveal.Outcomes and match.Mode ~= "BestOfFive" then
			snapshot.LoserUserId = match.Players[match.Reveal.Loser].UserId
		end
	end
	if
		match.RoundState == "ROUND_REVEAL"
		or match.RoundState == "TABLE_RETURN"
		or match.RoundState == "TABLE_REACTION"
	then
		local result = match.Reveal
		local ownOutcome = result.Outcomes and result.Outcomes[own]
		snapshot.Reveal = {
			StartedAt = match.RevealStartedAt,
			Mode = match.Mode,
			RequiredAccuracy = self:RequiredFor(match, own),
			YourOutcome = ownOutcome,
			YourHeartsAfter = if ownOutcome
				then ownOutcome.HeartsAfter
				else math.max(
					0,
					match.Hearts[own] - (if result.Loser == own and not match.HeartAppliedAt then 1 else 0)
				),
			Actual = result.Actual,
			YourGuess = result.Guesses[own],
			OpponentGuess = result.Guesses[other],
			YourAccuracy = self.Rounds.Math.Accuracy(result.Errors[own]),
			OpponentAccuracy = self.Rounds.Math.Accuracy(result.Errors[other]),
			Result = if match.Mode == "BestOfFive"
				then "SCORE ADDED!"
				elseif result.Outcomes then (if not ownOutcome
					then "SPECTATING"
					elseif not ownOutcome.Passed then "ROUND LOST!"
					else "SAFE!")
				elseif result.Loser == 0 then "TIE!"
				elseif result.Loser == own then "ROUND LOST!"
				else "ROUND WON!",
		}
		snapshot.Reveal.Results = {}
		-- Turn rotation must not reorder reveal colours or the local-first presentation.
		local revealOrder = table.clone(match.TurnOrder)
		table.sort(revealOrder)
		local closestError = math.huge
		for _, index in revealOrder do
			if (result.Outcomes and result.Outcomes[index]) or match.Hearts[index] > 0 or result.Loser == index then
				closestError = math.min(closestError, result.Errors[index])
			end
		end
		for _, index in revealOrder do
			if (result.Outcomes and result.Outcomes[index]) or match.Hearts[index] > 0 or result.Loser == index then
				table.insert(
					snapshot.Reveal.Results,
					{
						UserId = match.Players[index].UserId,
						AvatarUserId = avatarUserId(match.Players[index]),
						Name = match.Players[index].DisplayName,
						Username = match.Players[index].Name or match.Players[index].DisplayName,
						Guess = result.Guesses[index],
						Accuracy = self.Rounds.Math.Accuracy(result.Errors[index]),
						Loser = if match.Mode == "BestOfFive"
							then not result.RoundWinners[index]
							elseif result.Outcomes then not result.Outcomes[index].Passed
							else result.Loser == index,
						Passed = result.Outcomes and result.Outcomes[index].Passed,
						HeartDelta = result.Outcomes and result.Outcomes[index].HeartDelta,
						HeartsAfter = if result.Outcomes
							then result.Outcomes[index].HeartsAfter
							else math.max(
								0,
								match.Hearts[index]
									- (if result.Loser == index and not match.HeartAppliedAt then 1 else 0)
							),
						Closest = if result.RoundWinners
							then result.RoundWinners[index]
							else result.Errors[index] <= closestError + self.Config.TieErrorTolerance,
					}
				)
			end
		end
	elseif match.RoundState == "MATCH_END" then
		snapshot.Result = if not match.Winner
			then (if match.Completed then "DRAW / MATCH COMPLETE" else "MATCH CANCELLED")
			elseif match.Winner == own then "YOU WIN!"
			else "YOU LOST!"
		snapshot.Reward = if match.Winner == own then match.Reward else 0
		-- The XP this match was worth, for the Points shown on the end screen.
		snapshot.MatchXP = if (match.Winner or match.Completed) and self.Adapters.MatchXP
			then self.Adapters.MatchXP(match.Winner == own)
			else nil
		snapshot.Message = match.Reason
	end
	return snapshot
end
return MatchService

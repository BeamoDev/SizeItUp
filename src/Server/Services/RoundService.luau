--!strict
local RoundService = {}
RoundService.__index = RoundService
local function pairUses(history: any,a: string,b: string): number
	if a>b then a,b=b,a end
	return (history.PairUses[a] and history.PairUses[a][b]) or 0
end
local function chooseVaried(self: any,history: any,count: number,decode: any,previous: any,chain: boolean): number
	local best,bestRank,ties=nil,nil,0
	for index=1,count do
		local a,b=decode(index)
		-- Preserve direction-cycle guarantees while avoiding immediate reversals
		-- whenever this remaining pool offers an alternative.
		if count>1 and previous and ((chain and b==previous.ReferenceId)
			or (not chain and a==previous.ReferenceId and b==previous.TargetId)) then continue end
		local aUses,bUses=history.ObjectUses[a] or 0,history.ObjectUses[b] or 0
		local aLast,bLast=history.LastSeen[a] or -math.huge,history.LastSeen[b] or -math.huge
		local recent=(if not chain and history.Round-aLast<3 then 1 else 0)+(if history.Round-bLast<3 then 1 else 0)
		-- A/B and B/A share pairing history. The mandatory chain reference does
		-- not count against a candidate's freshness or recent-object penalty.
		local rank={pairUses(history,a,b),(if bUses==0 then 0 else 1)+(if not chain and aUses>0 then 1 else 0),recent,
			bUses+(if chain then 0 else aUses),if chain then bLast else math.max(aLast,bLast)}
		local comparison=0
		if bestRank then
			for i,value in rank do if value~=bestRank[i] then comparison=if value<bestRank[i] then -1 else 1;break end end
		else comparison=-1 end
		if comparison<0 then best,bestRank,ties=index,rank,1
		elseif comparison==0 then ties+=1;if self.Random:NextInteger(1,ties)==ties then best=index end end
	end
	assert(best,"No available variety candidate")
	return best
end
function RoundService.new(config: any, mathUtil: any, catalog: any, measurements: any, random: any, getIds: () -> {string})
	return setmetatable({ Config = config, Math = mathUtil, Catalog = catalog, Measurements = measurements, Random = random, GetIds = getIds }, RoundService)
end
function RoundService.Create(self: any, previous: any, selection: any?, chain: boolean?)
	local ids = table.clone(self.GetIds())
	table.sort(ids)
	assert(#ids >= 2, "At least two usable ServerStorage.Objects assets are required")
	local history = selection or {}
	history.ObjectUses=history.ObjectUses or {};history.LastSeen=history.LastSeen or {};history.PairUses=history.PairUses or {}
	history.Round=history.Round or 0
	local signatureParts = { tostring(self.Config.MaximumPairHeightRatio) }
	for _, id in ids do
		table.insert(signatureParts, id .. "=" .. tostring(self.Measurements[id]))
	end
	local signature = table.concat(signatureParts, "\0")
	-- Cache eligibility across matches. Private asset overrides participate in
	-- the signature, so changing a measurement cannot leave stale pairings.
	if self.PoolSignature ~= signature then
		local pool, neighbors = {}, {}
		for referenceIndex, reference in ids do
			local a = self.Measurements[reference]
			for targetIndex, target in ids do
				local b = self.Measurements[target]
				if referenceIndex ~= targetIndex
					and self.Math.IsGuess(a, self.Config.MinimumGuessMeters, self.Config.MaximumGuessMeters)
					and self.Math.IsGuess(b, self.Config.MinimumGuessMeters, self.Config.MaximumGuessMeters)
					and math.max(a, b) / math.min(a, b) <= self.Config.MaximumPairHeightRatio then
					table.insert(pool, (referenceIndex - 1) * #ids + targetIndex)
					neighbors[reference] = neighbors[reference] or {}
					table.insert(neighbors[reference], target)
				end
			end
		end
		self.PoolSignature, self.PairPool = signature, pool
		self.Neighbors = neighbors
	end
	local total = #self.PairPool
	assert(total > 0, "At least two usable objects within MaximumPairHeightRatio are required")
	local function decode(value: number): (string, string)
		local encoded = self.PairPool[value]
		local referenceIndex = math.floor((encoded - 1) / #ids) + 1
		local targetIndex = (encoded - 1) % #ids + 1
		return ids[referenceIndex], ids[targetIndex]
	end
	local reference, target
	if chain then
		if history.ChainSignature ~= signature then history.ChainSignature, history.Outgoing = signature, {} end
		if previous then reference = previous.TargetId else reference = decode(self.Random:NextInteger(1, total)) end
		local eligible = self.Neighbors[reference]
		assert(eligible and #eligible > 0, "Chain reference no longer has a usable similar-size target")
		local remaining = history.Outgoing[reference]
		if not remaining or #remaining == 0 then remaining = table.clone(eligible);history.Outgoing[reference] = remaining end
		local pick=chooseVaried(self,history,#remaining,function(index)return reference,remaining[index]end,previous,true)
		target = table.remove(remaining, pick)
	else
		if history.Signature ~= signature or not history.Remaining or history.Remaining == 0 then
			history.Signature, history.Remaining, history.Swaps = signature, total, {}
		end
		-- Keep an ordered-pair bag with sparse swap removal, but rank its remaining
		-- candidates by match history instead of choosing a purely random pair.
		local index=chooseVaried(self,history,history.Remaining,function(i)return decode(history.Swaps[i] or i)end,previous,false)
		local encoded = history.Swaps[index] or index
		reference, target = decode(encoded)
		history.Swaps[index] = history.Swaps[history.Remaining] or history.Remaining
		history.Swaps[history.Remaining] = nil
		history.Remaining -= 1
	end
	local actual, referenceSize = self.Measurements[target], self.Measurements[reference]
	assert(self.Math.IsGuess(actual, self.Config.MinimumGuessMeters, self.Config.MaximumGuessMeters), "Invalid target measurement")
	assert(self.Math.IsFinite(referenceSize) and referenceSize > 0, "Invalid reference measurement")
	history.Round+=1
	for _,id in {reference,target} do history.ObjectUses[id]=(history.ObjectUses[id] or 0)+1;history.LastSeen[id]=history.Round end
	local a,b=reference,target;if a>b then a,b=b,a end
	history.PairUses[a]=history.PairUses[a] or {};history.PairUses[a][b]=(history.PairUses[a][b] or 0)+1
	-- Publish a broad power-of-two band, never exact multiples of the answer.
	-- All answers in one band share limits and the same initial-size distribution.
	local band = 2 ^ math.floor(math.log(actual) / math.log(2))
	local minimum = math.max(self.Config.MinimumGuessMeters, band / 2)
	local maximum = math.min(self.Config.MaximumGuessMeters, band * 4)
	local initial = self.Math.FromAlpha(self.Random:NextNumber(), minimum, maximum)
	local hue = self.Random:NextNumber()
	return { ReferenceId = reference, TargetId = target, ReferenceMeters = referenceSize, Actual = actual, InitialGuess = initial,
		GuessMinimum = minimum, GuessMaximum = maximum,
		ReferenceHue = hue, TargetHue = (hue + 0.35 + self.Random:NextNumber() * 0.3) % 1 }
end
-- adjust[index] = { Bar = points off the target, Second = miss margin, Shield = bool, Revive = bool } from pet abilities.
function RoundService.Score(self: any, pair: any, guesses: {number}, hearts: {number}?, required: number?, streaks: any?, mode: string?, adjust: any?)
	local errors, worst, loser, tied = {}, -1, 0, false
	for index, guess in guesses do
		errors[index] = self.Math.Error(guess, pair.Actual)
		local rankedError=if mode=="Classic" or mode=="SuddenDeath" then 1-self.Math.Accuracy(errors[index])/100 else errors[index]
		if not hearts or hearts[index] > 0 then
			if rankedError > worst + self.Config.TieErrorTolerance then worst, loser, tied = rankedError, index, false
			elseif math.abs(rankedError - worst) <= self.Config.TieErrorTolerance then tied = true end
		end
	end
	local result: any = { Loser = if tied then 0 else loser, Errors = errors, Guesses = table.clone(guesses), Actual = pair.Actual }
	if required then
		result.Outcomes, result.Loser = {}, 0
		for index, hp in hearts do
			if hp > 0 then
				local accuracy = self.Math.Accuracy(errors[index])
				local pets = adjust and adjust[index] or {}
				local need = math.max(1, required - (pets.Bar or 0))
				local passed = accuracy + 1e-7 >= need
				local saved
				if not passed and pets.Second and need - accuracy <= pets.Second + 1e-7 then passed, saved = true, "SecondChance" end
				local streak = if accuracy + 1e-7 >= self.Config.ChainHealAccuracy then (streaks[index] or 0) + 1 else 0
				local heal = streak >= self.Config.ChainHealStreak
				local after = if not passed then hp - 1 elseif heal then math.min(self.Config.StartingHearts, hp + 1) else hp
				if not passed then
					-- A Shield blocks the loss; Revive keeps a player on their last heart. Both count as safe.
					if pets.Shield then after, passed, saved = hp, true, "Shield"
					elseif pets.Revive and hp - 1 <= 0 then after, passed, saved = 1, true, "Revive" end
				end
				result.Outcomes[index] = { Passed = passed, HeartDelta = after - hp, HeartsAfter = after, StreakAfter = if heal then 0 else streak, Required = need, Saved = saved }
				if not passed and result.Loser == 0 then result.Loser = index end
			end
		end
	end
	return result
end
return RoundService

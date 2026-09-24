--!strict
-- Seat observations come from the server adapter, never a join remote.
local TableService = {}
TableService.__index = TableService
local function avatarUserId(player: any): number
	if typeof(player) == "table" then
		local avatar = rawget(player, "AvatarUserId")
		if type(avatar) == "number" and avatar > 0 then return avatar end
	end
	return player.UserId
end
function TableService.new(config: any, matches: any, adapters: any)
	return setmetatable({ Config = config, Matches = matches, Adapters = adapters, Records = {}, Owners = {}, VoteSequence=0, TickRecords = {} }, TableService)
end
function TableService.Add(self: any, key: any)
	if self.Records[key] then return end
	local record = { Key = key, Players = {}, State = "EMPTY", LastNotice = "", RetryAt = 0, Capacity = if self.Adapters.Capacity then self.Adapters.Capacity(key) else 2 }
	self.Records[key] = record
	self.Adapters.SetState(record, "EMPTY")
	return record
end
function TableService.Notify(self: any, record: any, state: string, message: string?)
	record.State = state
	record.Message = message
	self.Adapters.SetState(record, state)
	local notice = state .. (message or "") .. tostring(record.Deadline)..":"..tostring(record.VoteRevision)
	if record.LastNotice == notice then return end
	record.LastNotice = notice
	for _, player in record.Players do self.Adapters.Send(player, self:Snapshot(record,player)) end
end
function TableService.Snapshot(self: any, record: any, player: any?)
	local counts={}
	local voters={}
	local voterAvatars={}
	for voter,id in record.Votes or {} do
		counts[id]=(counts[id] or 0)+1
		voters[id]=voters[id] or {}
		table.insert(voters[id],voter.UserId)
		voterAvatars[tostring(voter.UserId)]=avatarUserId(voter)
	end
	-- Who voted for what is public at the table (their mugshots show on the mode buttons), listed in a stable order.
	for _,list in voters do table.sort(list) end
	return { State = record.State, Message = record.Message, Deadline = record.Deadline, Capacity = record.Capacity, Prize = record.Prize, RollStarted = record.RollStarted, RollDuration = record.RollDuration,
		Mode=record.Mode,VoteId=record.VoteId,VoteCounts=counts,Voters=voters,VoterAvatars=voterAvatars,YourVote=record.Votes and record.Votes[player],
		-- How many seats are actually filled right now: lets the client offer "Play vs Bot" only while truly alone.
		SeatedCount=#record.Players }
end
function TableService.Vote(self: any,player: any,voteId: any,mode: any): boolean
	if type(voteId)~="string" or #voteId>64 or type(mode)~="string" or #mode>32 or not self.Config.Modes[mode] then return false end
	local record=self.Owners[player]
	if not record or record.Removed or record.State~="VOTING" or record.VoteId~=voteId then return false end
	-- Re-read seats/deaths before accepting; stale occupants cannot vote between heartbeats.
	self:Update(record)
	local now=self.Adapters.Now()
	if self.Owners[player]~=record or record.State~="VOTING" or record.VoteId~=voteId or now>=record.Deadline then return false end
	if record.Votes[player]==mode then return true end
	if record.VoteAt[player] and now-record.VoteAt[player]<0.2 then return false end
	record.VoteAt[player],record.Votes[player]=now,mode
	record.VoteRevision=(record.VoteRevision or 0)+1
	-- Voting ends early only when every seated player has picked the SAME mode; split votes (or anyone still to
	-- vote) keep the timer running, and a vote can still change until it ends.
	for _,seated in record.Players do
		if record.Votes[seated]~=mode then self:Notify(record,"VOTING");return true end
	end
	self:FinishVote(record,now)
	return true
end
function TableService.FinishVote(self: any,record: any,now: number)
	record.Mode=self:ResolveVote(record)
	record.Deadline=now+self.Config.CountdownSeconds
	self:Notify(record,"COUNTDOWN",self.Config.Modes[record.Mode].Name.." selected!")
end
function TableService.ResolveVote(self: any,record: any): string
	local counts,best,candidates={},0,{}
	for _,mode in record.Votes do counts[mode]=(counts[mode] or 0)+1 end
	for _,mode in self.Config.ModeOrder do
		local count=counts[mode] or 0
		if count>best then best=count;candidates={mode}
		elseif count==best and count>0 then table.insert(candidates,mode) end
	end
	if best==0 then return self.Config.DefaultMode end
	return candidates[if self.Adapters.PickVote then self.Adapters.PickVote(#candidates) else math.random(1,#candidates)]
end
function TableService.Release(self: any, record: any, player: any, completion: any?)
	if self.Owners[player] == record then
		self.Owners[player] = nil
		self.Adapters.Send(player, { State = "IDLE", Completion = completion, Deadline = if completion then self.Adapters.Now()+self.Config.CompletionSeconds else nil })
	end
end
function TableService.CleanupMatch(self: any, match: any)
	local record = match.Table
	record.Match = nil
	record.Mode,record.VoteId,record.Votes,record.VoteAt,record.VoteRevision=nil,nil,nil,nil,nil
	record.Deadline = self.Adapters.Now() + self.Config.ResetSeconds
	local function attempt(callback)
		local ok,err=pcall(callback);if not ok then self.Adapters.Warn(err) end
		return ok
	end
	attempt(function() self:Notify(record, "RESETTING") end)
	for _, player in record.Players do
		local ejected=attempt(function() self.Adapters.Eject(record, player) end)
		local won=match.Winner and match.Players[match.Winner]==player
		attempt(function() self:Release(record, player, if ejected then {
			Cancelled=match.Winner==nil and not match.Completed,
			Result=if not match.Winner then (if match.Completed then "DRAW / MATCH COMPLETE" else "MATCH CANCELLED") elseif won then "YOU WIN!" else "YOU LOST!",
			Reward=if won then match.Reward else 0, Message=match.Reason,
		} else nil) end)
	end
	record.Players = {}
	if record.Removed then self.Records[record.Key] = nil end
end
function TableService.Remove(self: any, key: any)
	local record = self.Records[key]
	if not record then return end
	record.Removed = true
	if record.Match then
		self.Matches:Cancel(record.Match, "Match cancelled: table removed")
		self.Matches:Remove(record.Match)
	else
		for _, player in record.Players do self:Release(record, player) end
		self.Records[key] = nil
	end
end
function TableService.Update(self: any, record: any)
	if record.Removed then return end
	local now = self.Adapters.Now()
	local seated = self.Adapters.Occupants(record)
	local present = {}
	local seatedCount = 0
	for index = 1, record.Capacity do
		local player = seated[index]
		if player and self.Adapters.Alive(player) then
			present[player] = true
			seatedCount += 1
		end
	end
	record.SeatedCount = seatedCount
	if record.Match then
		local match = record.Match
		for player in present do
			if not table.find(match.Players, player) then self.Adapters.Eject(record, player) end
		end
		if not self.Adapters.Valid(record) then self.Matches:Cancel(match, "Cancelled: seats removed")
		else
			local missing = {};for index, player in match.Players do missing[index] = not present[player] end
			if table.find(missing, true) then self.Matches:Forfeit(match, missing) end
		end
		return
	end
	if record.State == "RESETTING" then
		for player in present do self.Adapters.Eject(record, player) end
		if now >= record.Deadline and next(present) == nil then
			record.Deadline = nil
			self:Notify(record, "EMPTY")
		end
		return
	end
	local changed = false
	for i = #record.Players, 1, -1 do
		local player = record.Players[i]
		if not present[player] then
			table.remove(record.Players, i)
			self:Release(record, player)
			changed = true
		end
	end
	for index = 1, record.Capacity do
		local player = seated[index]
		if player and present[player] and not table.find(record.Players, player) then
			if self.Owners[player] or self.Matches.ByPlayer[player] then self.Adapters.Eject(record, player)
			else
				self.Owners[player] = record
				table.insert(record.Players, player)
				changed = true
				-- A newly seated player (analytics hook).
				if self.Adapters.Seated then pcall(self.Adapters.Seated, player, record) end
			end
		end
	end
	-- Turn order follows seat numbers, not arrival order. Swapping seats also
	-- invalidates pre-match timing, even when the same people remain seated.
	local ordered={}
	for index=1,record.Capacity do
		local player=seated[index]
		if player and present[player] and self.Owners[player]==record and not table.find(ordered,player) then table.insert(ordered,player) end
	end
	for index,player in ordered do if record.Players[index]~=player then changed=true;break end end
	record.Players=ordered
	if changed then
		record.Mode,record.VoteId,record.Votes,record.VoteAt,record.VoteRevision=nil,nil,nil,nil,nil
		record.Prize, record.RollStarted, record.RollDuration = nil, nil, nil
		record.Deadline = nil
		record.LastNotice = ""
		record.RetryAt = 0
		self:Notify(record, if #record.Players == 0 then "EMPTY" else "WAITING_FOR_PLAYER", "Waiting for opponent...")
	end
	if #record.Players ~= record.Capacity then return end
	if record.State=="VOTING" then
		if not self.Adapters.Valid(record) then
			record.VoteId,record.Votes,record.Mode,record.Deadline=nil,nil,nil,nil
			self:Notify(record,"WAITING_FOR_PLAYER","Table needs setup");return
		end
		if now>=record.Deadline then self:FinishVote(record,now) end
		return
	end
	if record.State == "PRIZE_ROLL" then
		if now >= record.Deadline then record.Deadline = now + self.Config.GoSeconds;self:Notify(record, "GO") end
		return
	end
	if record.State == "COUNTDOWN" and now >= record.Deadline then
		if self.Adapters.Prize then
			record.Prize, record.RollDuration = self.Adapters.Prize(record)
			record.RollStarted, record.Deadline = now, now + record.RollDuration
			self:Notify(record, "PRIZE_ROLL")
		else
			record.Deadline = now + self.Config.GoSeconds
			self:Notify(record, "GO")
		end
		return
	end
	if record.State ~= "COUNTDOWN" and record.State ~= "GO" then
		if now < record.RetryAt then return end
		local arena, reason = self.Adapters.Prepare(record)
		if not arena then
			record.RetryAt = now + 1
			self:Notify(record, "WAITING_FOR_PLAYER", reason or "Table needs setup")
			return
		end
		record.Arena = arena
		if (self.Config.ModeVoteSeconds or 0)>0 and record.Capacity>=3 then
			self.VoteSequence+=1
			record.VoteId="Vote_"..self.VoteSequence
			record.Votes,record.VoteAt,record.VoteRevision,record.Mode={},{},0,nil
			record.Deadline=now+self.Config.ModeVoteSeconds
			self:Notify(record,"VOTING")
		else
			-- A bot match (see Bootstrap's PlayBot handler) pins ForcedMode so it is always Classic,
			-- independent of whatever the table's normal DefaultMode is configured to.
			record.Mode=record.ForcedMode or self.Config.DefaultMode
			record.Deadline = now + self.Config.CountdownSeconds
			self:Notify(record, "COUNTDOWN")
		end
	elseif record.State == "GO" and now >= record.Deadline then
		local arena, reason = self.Adapters.Prepare(record)
		if not arena then
			record.Deadline = nil
			record.Prize, record.RollStarted, record.RollDuration = nil, nil, nil
			self:Notify(record, "WAITING_FOR_PLAYER", reason)
			return
		end
		-- No yields between the final seat check and reserving both match mappings.
		record.State = "IN_MATCH"
		record.Match = self.Matches:Start(record, record.Players, arena)
		self.Adapters.SetState(record, "IN_MATCH")
		if record.Match and self.Adapters.MatchStarted then
			for _, player in record.Players do pcall(self.Adapters.MatchStarted, player, record) end
		end
	end
end
function TableService.Tick(self: any)
	-- Update can remove/reset records, so keep the defensive snapshot without allocating a new table every 20 Hz tick.
	local pending = self.TickRecords or {}
	self.TickRecords = pending
	table.clear(pending)
	for _, record in self.Records do
		table.insert(pending, record)
	end
	for _, record in pending do
		if self.Records[record.Key] ~= record then
			continue
		end
		local ok, err = xpcall(function() self:Update(record) end, debug.traceback)
		if not ok then
			self.Adapters.Warn(err)
			-- Start can fail after reservation but before returning its match.
			local match = record.Match
			if not match then
				local firstPlayer = record.Players[1]
				local candidate = firstPlayer and self.Matches.ByPlayer[firstPlayer]
				-- A stale seat/owner entry must never let one table cancel another table's match.
				if candidate and candidate.Table == record then
					match = candidate
				end
			end
			if match then
				record.Match = match
				pcall(function() self.Matches:Cancel(match, "Cancelled: server error") end)
				local removed, removeError = pcall(function() self.Matches:Remove(match) end)
				if not removed then self.Adapters.Warn(removeError) end
			else
				for _, player in record.Players do
					if self.Matches.ByPlayer[player] then
						-- Preserve the other table's live client state while discarding this stale ownership claim.
						if self.Owners[player] == record then
							self.Owners[player] = nil
						end
					else
						self:Release(record, player)
					end
				end
				record.Players = {}
				record.Mode,record.VoteId,record.Votes,record.VoteAt,record.VoteRevision=nil,nil,nil,nil,nil
				record.Deadline = self.Adapters.Now() + self.Config.ResetSeconds
				self:Notify(record, "RESETTING")
			end
		end
	end
end
return TableService

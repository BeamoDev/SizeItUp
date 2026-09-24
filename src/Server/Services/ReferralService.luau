--!strict
-- Roblox's server-side referral identity is the only input. Clients cannot claim.
-- Durable mailboxes deliver across servers/offline; the leased profile owns grants.
local Service = {};Service.__index = Service
local function validId(id: any): boolean
	return type(id)=="number" and id>0 and id<2^53 and id%1==0
end
-- cash: a flat Cash amount per referred friend, or function(data) -> cash, gems (the reward for this inviter right
-- now, e.g. scaled to the Cash they hold).
function Service.new(profiles: any, store: any, cash: any, adapters: any)
	return setmetatable({Profiles=profiles,Store=store,Cash=cash,A=adapters,Busy={},Seen={},Attempts={},Next={},NextInbox={},Notices={},GemNotices={}},Service)
end
function Service.Run(self: any, player: any, readInbox: boolean?)
	if self.Busy[player] or not self.A.Available(player) then return end
	local data=self.Profiles:Get(player.UserId);if not data then return end
	self.Busy[player]=true
	local ok,problem=pcall(function()
		local function deliver(): boolean
			if not data.PendingReferral then return true end
			local inviter=data.PendingReferral
			-- Save proof of the pending delivery before the mailbox operation yields.
			if not self.Profiles:Save(player.UserId) then return false end
			self.Store:UpdateAsync("Inviter_"..inviter,function(old)
				local pending=if type(old)=="table" then table.clone(old) else {}
				pending[tostring(player.UserId)]=true
				return pending
			end)
			if self.Profiles:Get(player.UserId)~=data or not self.A.Available(player) then return false end
			data.PendingReferral=nil
			if not self.Profiles:Save(player.UserId) then data.PendingReferral=inviter;return false end
			return true
		end
		-- Finish an earlier join's journal before recording a different inviter.
		if not deliver() then return end
		if not self.Seen[player] and (self.Attempts[player] or 0)<10 then
			self.Attempts[player]=(self.Attempts[player] or 0)+1
			local read,join=pcall(self.A.JoinData,player)
			if self.Profiles:Get(player.UserId)~=data or not self.A.Available(player) then return end
			local inviter=read and type(join)=="table" and join.ReferredByPlayerId
			if validId(inviter) and inviter~=player.UserId then
				self.Seen[player]=true;data.PendingReferral=inviter
				if not deliver() then return end
			end
		end
		if readInbox==false then return end
		local inbox=self.Store:GetAsync("Inviter_"..player.UserId)
		if type(inbox)~="table" or not next(inbox) then return end
		if self.Profiles:Get(player.UserId)~=data or not self.A.Available(player) then return end
		local processed,total,gemTotal={},0,0
		for id,verified in inbox do
			if type(id)=="string" and validId(tonumber(id)) and tonumber(id)~=player.UserId and verified==true then
				processed[id]=true
				if not data.InviteRewards[id] then
					local cash,gems=self.Cash,0
					if type(self.Cash)=="function" then cash,gems=self.Cash(data) end
					data.InviteRewards[id]=true;data.Cash+=cash;data.TotalEarned+=cash;total+=cash
					data.Keys+=gems or 0;gemTotal+=gems or 0
				end
			end
		end
		-- Grant plus dedupe markers must be durable before acknowledging delivery.
		self.Notices[player]=(self.Notices[player] or 0)+total
		self.GemNotices[player]=(self.GemNotices[player] or 0)+gemTotal
		if not self.Profiles:Save(player.UserId) then return end
		local notice,gemNotice=self.Notices[player] or 0,self.GemNotices[player] or 0
		if notice>0 or gemNotice>0 then self.A.Granted(player,notice,gemNotice);self.Notices[player],self.GemNotices[player]=nil,nil end
		self.Store:UpdateAsync("Inviter_"..player.UserId,function(old)
			local pending=if type(old)=="table" then table.clone(old) else {}
			for id in processed do pending[id]=nil end
			return pending
		end)
	end)
	self.Busy[player]=nil
	if not ok then self.A.Warn("Referral delivery will retry: "..tostring(problem)) end
end
function Service.Tick(self: any,player: any,now: number)
	if self.Busy[player] or now<(self.Next[player] or 0) then return end
	self.Next[player]=now+(if not self.Seen[player] and (self.Attempts[player] or 0)<10 then 1 else 30)
	local readInbox=now>=(self.NextInbox[player] or 0)
	if readInbox then self.NextInbox[player]=now+30 end
	self.A.Spawn(function()self:Run(player,readInbox)end)
end
function Service.Remove(self: any,player: any)
	self.Next[player],self.Seen[player],self.Attempts[player]=nil,nil,nil
	self.NextInbox[player],self.Notices[player],self.GemNotices[player]=nil,nil,nil
end
return Service

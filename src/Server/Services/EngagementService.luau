--!strict
-- Rewards and claim markers mutate the same leased profile before any save yield.
local Service={};Service.__index=Service
function Service.new(catalog: any, adapters: any)
	return setmetatable({Catalog=catalog,A=adapters,Busy={}},Service)
end
function Service.Tick(self: any,data: any,elapsed: number)
	local now=self.A.Now();local progress=data.Rewards
	-- Play Time rewards are lifetime milestones. Never clear progress or claims.
	local seconds=math.max(0,elapsed)
	local boosted=math.clamp(progress.BoostUntil-(now-seconds),0,seconds)
	progress.TimedSeconds=math.min(86400,progress.TimedSeconds+seconds+boosted)
end
function Service.Snapshot(self: any,data: any)
	local now=self.A.Now();local p=data.Rewards
	local readyAt=if p.DailyDay==0 then now else p.DailyAt+self.Catalog.DailySeconds
	local completed=if p.DailyDay==#self.Catalog.Daily and now>=readyAt then 0 else p.DailyDay
	return {Now=now,DailyCompleted=completed,DailyNext=p.DailyDay%#self.Catalog.Daily+1,DailyReadyAt=readyAt,
		TimedSeconds=p.TimedSeconds,TimedClaims=table.clone(p.TimedClaims),
		BoostUntil=p.BoostUntil,GroupClaimed=p.GroupClaimed,GroupId=self.A.GroupId}
end
function Service.Grant(self: any,data: any,reward: any,now: number)
	data.Cash+=reward.Cash or 0;data.TotalEarned+=reward.Cash or 0;data.Keys+=reward.Keys or 0
	if reward.BoostSeconds then data.Rewards.BoostUntil=math.max(now,data.Rewards.BoostUntil)+reward.BoostSeconds end
	if reward.Chair then data.Owned.Chairs[reward.Chair]=1 end
	if reward.Pet then data.Owned.Pets[reward.Pet]=(data.Owned.Pets[reward.Pet] or 0)+1 end
end
function Service.Claim(self: any,player: any,category: any,id: any)
	if self.Busy[player] then return false,"A claim is already processing." end
	self.Busy[player]=true
	local success,claimed,message,reason=pcall(function()
		local data=self.A.Data(player)
		if not data or not self.A.Available(player) then return false,"Rewards unavailable." end
		local now=self.A.Now();local p=data.Rewards;local reward
		if category=="Daily" then
			local index=p.DailyDay%#self.Catalog.Daily+1
			reward=self.Catalog.Daily[index]
			if reward.Id~=id then return false,"Claim the next day first." end
			if p.DailyDay>0 and now<p.DailyAt+self.Catalog.DailySeconds then return false,"Not ready yet." end
			p.DailyDay,p.DailyAt=index,now
		elseif category=="Play Time" then
			for _,item in self.Catalog.Timed do if item.Id==id then reward=item;break end end
			if not reward then return false,"Unknown reward." end
			if p.TimedClaims[id] then return false,"Already claimed!" end
			if p.TimedSeconds<reward.Seconds then return false,"Keep playing to unlock!" end
			p.TimedClaims[id]=true
		elseif category=="Group" and id==self.Catalog.Group.Id then
			if p.GroupClaimed then return false,"Group reward already claimed." end
			if self.A.GroupId<=0 then return false,"Group rewards are coming soon." end
			local ok,member=pcall(self.A.Member,player,self.A.GroupId)
			-- Membership checks yield: a teleport or lease loss must prevent the grant.
			if self.A.Data(player)~=data or not self.A.Available(player) then return false,"Profile changed. Try again." end
			if not ok then return false,"Group check failed. Try again." end
			if not member then return false,"Join the group first!","JoinGroup" end
			reward=self.Catalog.Group;p.GroupClaimed=true;now=self.A.Now()
		else return false,"Unknown reward." end
		self:Grant(data,reward,now)
		local saved=self.A.Save(player)
		return true,if saved then reward.Name.." claimed!" else "Reward added. Saving..."
	end)
	self.Busy[player]=nil
	if not success then error(claimed) end
	return claimed,message,reason
end
return Service

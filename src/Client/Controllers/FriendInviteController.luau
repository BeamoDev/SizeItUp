--!strict
-- One optional alert per join. Presence and permission calls never block loading
-- or the render callback; only a user click opens the platform confirmation.
local Controller = {}
Controller.__index = Controller

function Controller.new(d: any)
	local self: any = setmetatable({D=d, Connections={}, Done=false, Scanning=false, Shown=false, Pending=false, Age=0}, Controller)
	self.View = d.View.new(d.Player:WaitForChild("PlayerGui"))
	table.insert(self.Connections, self.View.Close.Activated:Connect(function() self:Dismiss() end))
	table.insert(self.Connections, self.View.Invite.Activated:Connect(function() self:Invite() end))
	table.insert(self.Connections, d.RunService.RenderStepped:Connect(function(dt) self:Step(dt) end))
	return self
end

function Controller.Eligible(self: any, friend: any): boolean
	return type(friend)=="table" and friend.IsOnline==true and type(friend.VisitorId)=="number"
		and friend.VisitorId>0 and friend.VisitorId~=self.D.Player.UserId
		and type(friend.UserName)=="string" and friend.UserName~=""
		and self.D.Players:GetPlayerByUserId(friend.VisitorId)==nil
		-- Only friends who are not already playing this game (any server of it, or its AFK place).
		and not (self.D.GameId and friend.GameId~=nil and tostring(friend.GameId)==tostring(self.D.GameId))
		and not (self.D.PlaceIds and friend.PlaceId~=nil and self.D.PlaceIds[friend.PlaceId]==true)
end

function Controller.Scan(self: any)
	self.Scanning, self.ScanAge = true, self.Age
	self.D.Spawn(function()
		local ok, friends = pcall(function() return self.D.Player:GetFriendsOnlineAsync(200) end)
		if self.Destroyed or self.Done then return end
		if ok and type(friends)=="table" then
			for _,friend in friends do
				if not self:Eligible(friend) then continue end
				local allowed, canInvite = pcall(function() return self.D.SocialService:CanSendGameInviteAsync(self.D.Player, friend.VisitorId) end)
				if self.Destroyed or self.Done then return end
				if allowed and canInvite and self:Eligible(friend) then
					self.Friend = {Id=friend.VisitorId, Name=friend.UserName}
					self.FoundAt, self.Scanning = self.Age, false
					return
				end
			end
		end
		self.Scanning=false
		self:Dismiss()
	end)
end

function Controller.Invite(self: any)
	if self.Destroyed or self.Done or self.Pending or not self.Shown or not (if self.View.IsVisible then self.View:IsVisible() else self.View.Gui.Enabled)
		or not self.D.Ready() or not self.D.CanShow() then return end
	self.Pending=true
	self.View:SetEnabled(false)
	self.D.Spawn(function()
		local friend=self.Friend
		local ok, allowed=pcall(function() return self.D.SocialService:CanSendGameInviteAsync(self.D.Player, friend.Id) end)
		if self.Destroyed or self.Done then return end
		-- Permission checks yield: revalidate the active scene and recipient.
		if not self.D.Ready() or not self.D.CanShow() or self.D.Players:GetPlayerByUserId(friend.Id) then self.Pending=false;self.View:SetEnabled(true);return end
		if not ok or not allowed then self.Pending=false;self.View:SetEnabled(true);self.View.Message.Text="Invites unavailable right now";return end
		local options=Instance.new("ExperienceInviteOptions")
		options.Name, options.InviteUser, options.PromptMessage = "OnlineFriendInviteOptions", friend.Id, "Invite your friend to Scale It Up!"
		local prompted=pcall(function() self.D.SocialService:PromptGameInvite(self.D.Player, options) end)
		options:Destroy()
		if self.Destroyed or self.Done then return end
		-- The alert stays until Close is clicked, so the button simply becomes available again.
		self.Pending=false;self.View:SetEnabled(true)
		if not prompted then self.View.Message.Text="Invites unavailable right now" end
	end)
end

function Controller.Step(self: any, dt: number)
	if self.Destroyed or self.Done then return end
	self.Age+=math.max(0,dt)
	if self.Scanning and self.Age-self.ScanAge>15 then self:Dismiss();return end
	if not self.D.Ready() or not self.D.CanShow() then
		-- Hidden while a match or menu has the screen, and shown again afterwards; only Close removes it.
		if self.Shown and not self.Suspended then self.Suspended=true;self.View:Hide() end
		return
	end
	if self.Suspended then self.Suspended=nil;self.View:Show(self.Friend) end
	if self.Scanning then return end
	if not self.Friend then self:Scan();return end
	-- Presence is cached by Roblox. Do not display a queued candidate indefinitely.
	if not self.Shown and self.D.Players:GetPlayerByUserId(self.Friend.Id) then self:Dismiss();return end
	if not self.Shown then
		self.Shown=true
		local cash=self.D.RewardCash
		if type(cash)=="function" then cash=cash() end
		local rewarded=self.D.Rewarded and self.D.Rewarded(self.Friend.Id)
		self.Friend.RewardCash=if rewarded then 0 else (cash or 250)
		self.View:Show(self.Friend)
	end
	self.View:Step(dt)
end

function Controller.Dismiss(self: any)
	if self.Destroyed then return end
	self.Done=true
	self.View:Hide()
end

function Controller.Destroy(self: any)
	if self.Destroyed then return end
	self.Destroyed=true
	for _,connection in self.Connections do connection:Disconnect() end
	self.View:Destroy()
end
return Controller

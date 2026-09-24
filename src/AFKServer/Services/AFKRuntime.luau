--!strict
local Schema = require(script.Parent.ProfileSchema)
local Profiles = require(script.Parent.ProfileService)
local RewardService = require(script.Parent.RewardService)
local TravelService = require(script.Parent.TravelService)
local PetProgression = require(script.Parent.PetProgressionService)
local Runtime = {}
Runtime.__index = Runtime
function Runtime.new(d: any)
	local self: any = setmetatable({ D = d, Connections = {}, Loading = {}, PendingLoad = {}, Limits = {}, Clock = 0, SaveClock = 0, Closing = false }, Runtime)
	local store
	if d.RunService:IsStudio() and d.DataConfig.MemoryOnlyInStudio then
		local memory = {}
		store = { UpdateAsync = function(_, key, transform)
			local value = transform(Schema.Copy(memory[key]));if value then memory[key] = Schema.Copy(value) end;return value
		end }
		warn("AFK World: explicitly configured unsaved Studio session")
	else store = d.DataStore:GetDataStore(d.DataConfig.DataStoreName) end
	self.Profiles = Profiles.new(store, Schema, d.Catalog, d.DataConfig, {
		Now = os.time, Wait = task.wait, JobId = d.Http:GenerateGUID(false),
		Lost = function(id) local player = d.Players:GetPlayerByUserId(id);if player then player:Kick("Save session expired. Please rejoin.") end end,
	})
	self.Rewards = RewardService.new(d.Config, Random.new(), d.Catalog, d.Wealth)
	self.Remote = Instance.new("RemoteEvent");self.Remote.Name = d.Config.RemoteName;self.Remote.Parent = d.Storage
	self.Travel = TravelService.new({
		PlaceId = d.PlaceId, IsStudio = function() return d.RunService:IsStudio() end,
		Present = function(player) return player.Parent == d.Players end,
		CanTravel = function(player)
			local entry = self.Profiles.Entries[player.UserId]
			return not self.Closing and self.Profiles:Get(player.UserId) ~= nil and entry ~= nil and not entry.Busy
		end,
		SetTraveling = function(player, value) player:SetAttribute("Traveling", value) end,
		Release = function(player) return self.Profiles:Save(player.UserId, true) end,
		Recover = function(player)
			local data = self.Profiles:Load(player.UserId)
			if not data or player.Parent ~= d.Players or self.Closing then
				if data then self.Profiles:Save(player.UserId, true) end;return false
			end
			-- Pause the reward timer during a failed teleport instead of awarding missed time.
			local session = self.Rewards.Sessions[player.UserId]
			if session then session.Next = d.World:GetServerTimeNow() + session.Interval end
			return true
		end,
		Message = function(player, message) self:Send(player, message) end,
		Kick = function(player, message) player:Kick(message) end,
		Teleport = function(destination, player) d.Teleport:TeleportAsync(destination, { player }) end,
	})
	table.insert(self.Connections, d.Teleport.TeleportInitFailed:Connect(function(player, _, _, destination) self.Travel:Recover(player, destination) end))
	table.insert(self.Connections, self.Remote.OnServerEvent:Connect(function(player, action, ...)
		if select("#", ...) ~= 0 or (action ~= "Ready" and action ~= "Return") or self.Closing then return end
		local now = d.World:GetServerTimeNow()
		if now < (self.Limits[player] or 0) then return end
		self.Limits[player] = now + 0.75
		if action == "Ready" then self:Send(player, "") else self.Travel:Start(player, d.Config.MainPlaceId) end
	end))
	-- Purchases belong to the main game's receipt handler. Never acknowledge an ungranted receipt here.
	d.Marketplace.ProcessReceipt = function() return Enum.ProductPurchaseDecision.NotProcessedYet end
	return self
end
-- AFK players stand exactly where they spawn: their character's root is anchored as soon as it exists.
function Runtime.Anchor(self: any, player: Player)
	local function hold(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then root.Anchored = true end
	end
	self.Anchors = self.Anchors or {}
	if self.Anchors[player] then self.Anchors[player]:Disconnect() end
	self.Anchors[player] = player.CharacterAdded:Connect(hold)
	if player.Character then task.spawn(hold, player.Character) end
end
function Runtime.Add(self: any, player: Player)
	if self.Closing or self.Loading[player] or (self.Rewards.Sessions[player.UserId] and self.Profiles:Get(player.UserId)) then return end
	self.Loading[player] = true
	local data = self.Profiles:Load(player.UserId)
	self.Loading[player] = nil
	if not data then
		-- A DataStore hiccup should not cost the player their session; stay in the AFK world and retry.
		if player.Parent then self.PendingLoad[player] = self.D.World:GetServerTimeNow() + 5 end
		return
	end
	self.PendingLoad[player] = nil
	if self.Closing or player.Parent ~= self.D.Players then self.Profiles:Save(player.UserId, true);return end
	local required = self.D.Config.RequiredWins or 5
	if (data.Wins or 0) < required then
		self:Send(player, "AFK World requires " .. required .. " wins.")
		self.Travel:Start(player, self.D.Config.MainPlaceId)
		return
	end
	self.Rewards:Add(player.UserId, data, self.D.World:GetServerTimeNow(), os.time())
	local stats = Instance.new("Folder");stats.Name = "leaderstats";stats.Parent = player
	for _, name in { "Wins", "Streak" } do local stat = Instance.new("IntValue");stat.Name = name;stat.Value = data[name];stat.Parent = stats end
	self:Send(player, "")
end
function Runtime.Send(self: any, player: Player, message: string?)
	if player.Parent ~= self.D.Players then return end
	local data, session = self.Profiles:Get(player.UserId), self.Rewards.Sessions[player.UserId]
	local packet: any = { Ready = data ~= nil and session ~= nil, Traveling = player:GetAttribute("Traveling") == true, Message = message }
	if data and session then
		packet.Cash, packet.Earned, packet.History = data.Cash, session.Earned, Schema.Copy(session.History)
		packet.NextReward, packet.Interval, packet.Sequence = session.Next, session.Interval, session.Sequence
		-- The current random offer (Right.Container.Reward1-5): items, amounts and chances for the next reward.
		packet.Offer = Schema.Copy(session.Offer)
		packet.BoostRemaining = math.max(0, data.AFKBoostUntil - os.time())
		player:SetAttribute("Cash", data.Cash);player:SetAttribute("Keys", data.Keys)
	end
	self.Remote:FireClient(player, packet)
end
function Runtime.Tick(self: any, dt: number)
	if self.Closing then return end
	self.Clock += dt;self.SaveClock += dt
	if self.Clock >= 1 then
		local elapsed = math.floor(self.Clock);self.Clock -= elapsed
		local now = self.D.World:GetServerTimeNow()
		for player, retryAt in self.PendingLoad do
			if not self.Loading[player] and now >= retryAt then
				if player.Parent == self.D.Players then self:Add(player) else self.PendingLoad[player] = nil end
			end
		end
		for _, player in self.D.Players:GetPlayers() do
			local data = self.Profiles:Get(player.UserId)
			if data and not player:GetAttribute("Traveling") then
				data.TimePlayed += elapsed;data.AFKTimePlayed += elapsed
				PetProgression.Tick(data,self.D.Catalog.PetLevels,elapsed)
				local reward = self.Rewards:Tick(player.UserId, data, now, os.time())
				-- NextReward uses the shared server clock, so the client advances its own countdown. A full packet (including
				-- copied history and offer data) is only needed when a reward actually changes that state.
				if reward then
					self:Send(player)
					task.spawn(function() self.Profiles:Save(player.UserId) end)
				end
			end
		end
	end
	if self.SaveClock >= self.D.DataConfig.AutosaveSeconds then
		self.SaveClock = 0
		local pending = {}
		for id, entry in self.Profiles.Entries do
			if not entry.Busy then table.insert(pending, { Id = id, Closing = entry.Closing }) end
		end
		-- Avoid launching one yielding datastore task per player on the same heartbeat in large AFK servers.
		local nextIndex = 0
		for _ = 1, math.min(8, #pending) do
			task.spawn(function()
				while true do
					nextIndex += 1
					local item = pending[nextIndex]
					if not item then return end
					local current = self.Profiles.Entries[item.Id]
					if current and not current.Busy then self.Profiles:Save(item.Id, item.Closing) end
				end
			end)
		end
	end
end
function Runtime.Remove(self: any, player: Player)
	self.Travel:Remove(player);self.Rewards:Remove(player.UserId);self.Limits[player] = nil;self.PendingLoad[player] = nil
	if self.Anchors and self.Anchors[player] then self.Anchors[player]:Disconnect();self.Anchors[player] = nil end
	self.Profiles:Save(player.UserId, true)
end
function Runtime.Close(self: any)
	self.Closing = true
	for _, connection in self.Connections do connection:Disconnect() end
	local anchors = self.Anchors
	for _, connection in anchors or {} do
		connection:Disconnect()
	end
	if anchors then table.clear(anchors) end
	local remaining = 0
	for id in self.Profiles.Entries do remaining += 1;task.spawn(function() self.Profiles:Save(id, true);remaining -= 1 end) end
	local deadline = os.clock() + 25
	while (remaining > 0 or next(self.Loading)) and os.clock() < deadline do task.wait(0.1) end
end
return Runtime

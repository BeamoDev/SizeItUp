--!strict
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local CurrencyService = require(script.Parent.CurrencyService)
local InventoryService = require(script.Parent.InventoryService)
local TransferService = require(script.Parent.TransferService)
local EngagementService = require(script.Parent.EngagementService)
local PotionService = require(script.Parent.PotionService)
local PetProgression = require(script.Parent.PetProgressionService)
local PlayerLevel = require(script.Parent.PlayerLevelService)
local ReferralService = require(script.Parent.ReferralService)
local ChainProgress = require(script.Parent.ChainProgress)
-- Money is always shown with thousands separators: 80000 -> "$80,000".
local function money(amount: number): string
	local text = tostring(math.floor(math.abs(amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (if amount < 0 then "-$" else "$") .. string.gsub(string.reverse(grouped), "^,", "")
end
local EconomyRuntime = {}
EconomyRuntime.__index = EconomyRuntime
function EconomyRuntime.new(d: any)
	local self: any = setmetatable(
		{
			D = d,
			Connections = {},
			Limits = {},
			ActionBusy = {},
			StealAt = {},
			CodeAt = {},
			PurchaseAt = {},
			PendingBotSteal = {},
			Policy = {},
			ShopClaims = {},
			Clock = 0,
			SaveClock = 0,
			Closing = false,
			Loading = {},
			PendingLoad = {},
		},
		EconomyRuntime
	)
	local store, referralStore
	self.Memory = d.RunService:IsStudio() and d.Config.MemoryOnlyInStudio
	if self.Memory then
		local memory = {}
		store = {
			UpdateAsync = function(_, key, transform)
				local value = transform(ProfileSchema.Copy(memory[key]))
				if value then
					memory[key] = ProfileSchema.Copy(value)
				end
				return value
			end,
		}
		local inboxes = {}
		referralStore = {
			GetAsync = function(_, key)
				return ProfileSchema.Copy(inboxes[key])
			end,
			UpdateAsync = function(_, key, transform)
				local value = transform(ProfileSchema.Copy(inboxes[key]))
				if value then
					inboxes[key] = ProfileSchema.Copy(value)
				end
				return value
			end,
		}
		warn("Scale It Up: explicitly configured unsaved Studio session")
	else
		store = d.DataStore:GetDataStore(d.Config.DataStoreName)
		referralStore = d.DataStore:GetDataStore(d.Config.DataStoreName .. "_InviteInbox")
	end
	self.Profiles = ProfileService.new(store, ProfileSchema, d.Catalog, d.Config, {
		Now = os.time,
		Wait = task.wait,
		JobId = d.Http:GenerateGUID(false),
		Lost = function(id)
			local player = d.Players:GetPlayerByUserId(id)
			if player then
				player:Kick("Your save session expired. Please rejoin to protect your data.")
			end
		end,
	})
	-- The invite reward is Cash only, grown with the Cash the inviter holds when it is paid (d.Wealth, WealthScale).
	local inviteReward = if d.Wealth
		then function(data)
			return d.Wealth.Cash(d.Rewards.InviteCash, data.Cash, "Invite"), 0
		end
		else d.Rewards.InviteCash
	self.Referrals = ReferralService.new(self.Profiles, referralStore, inviteReward, {
		JoinData = function(player)
			return player:GetJoinData()
		end,
		Available = function(player)
			return not self.Closing and player.Parent == d.Players and not player:GetAttribute("Traveling")
		end,
		Granted = function(player, amount)
			self:Sync(player)
			self:Send(player, "Invite reward! +" .. money(amount), { Passive = true })
		end,
		Spawn = task.spawn,
		Warn = warn,
	})
	self.Currency = CurrencyService.new(function(player, cash)
		player:SetAttribute("Cash", cash)
	end, function(player)
		return self.Profiles:Get(player.UserId)
	end, function(player, match)
		match.RewardedAt = match.RewardedAt or os.time()
		local potion = PotionService.Multiplier(self.Profiles:Get(player.UserId), "Cash", match.RewardedAt)
		-- Consecutive within-10% guesses (match.ComboStreak, set by MatchService.UpdateCombo) also raise the Cash prize.
		-- self.D.Config here is EconomyConfig, not GameConfig, so the combo math is reached through the separate
		-- GameConfig dependency; a caller that leaves it out (an older fixture) simply gets no combo bonus.
		local combo = 1
		if self.D.GameConfig and self.D.GameConfig.ComboMultiplier then
			local index = table.find(match.Players, player)
			combo = self.D.GameConfig.ComboMultiplier(
				if index and match.ComboStreak then match.ComboStreak[index] or 0 else 0
			)
		end
		return potion * combo
	end)
	self.Inventory = InventoryService.new(d.Catalog, self.Currency, {
		NewId = function()
			return d.Http:GenerateGUID(false)
		end,
		Now = function()
			return d.World:GetServerTimeNow()
		end,
		Random = Random.new(),
		Busy = d.Busy,
		Shop = d.Shop,
		AvailablePets = d.AvailablePets,
		Data = function(player)
			return self.Profiles:Get(player.UserId)
		end,
		Allowed = function(player)
			return self.Policy[player] == true and self.Profiles:Get(player.UserId) ~= nil
		end,
		OwnsOpen10 = function(player)
			local data = self.Profiles:Get(player.UserId)
			return data ~= nil and self:OwnsPass(data, "Open10")
		end,
	})
	self.Transfers = TransferService.new(self.Profiles, function()
		return d.Http:GenerateGUID(false)
	end, function(id)
		return d.Players:GetPlayerByUserId(id) ~= nil
	end, {
		CanBegin = function(buyerId, targetId)
			local buyer, target = d.Players:GetPlayerByUserId(buyerId), d.Players:GetPlayerByUserId(targetId)
			return not self.Closing
				and buyer ~= nil
				and target ~= nil
				and not self.ActionBusy[target]
				and self:Near(buyer, target)
		end,
		OnDebited = function(buyerId, targetId, amount)
			local buyer, target = d.Players:GetPlayerByUserId(buyerId), d.Players:GetPlayerByUserId(targetId)
			if target and amount > 0 then
				self:Sync(target)
				self:Send(
					target,
					string.sub(if buyer then buyer.DisplayName else "Someone", 1, 12)
						.. " stole "
						.. money(amount)
						.. "!",
					{ Passive = true, CashStolen = { UserId = buyerId, Amount = amount } }
				)
			end
		end,
	})
	self.Rewards = EngagementService.new(d.Rewards, {
		Now = os.time,
		GroupId = d.GroupId,
		Data = function(player)
			return self.Profiles:Get(player.UserId)
		end,
		Available = function(player)
			return not self.Closing and player.Parent == d.Players and not d.Busy(player)
		end,
		Member = function(player, groupId)
			-- A fresh server group-list request avoids a cached negative Player membership.
			local groups = d.Groups:GetGroupsAsync(player.UserId)
			assert(type(groups) == "table", "Invalid membership response")
			for _, group in groups do
				if type(group) == "table" and group.Id == groupId then
					return true
				end
			end
			return false
		end,
		Save = function(player)
			return self.Profiles:Save(player.UserId)
		end,
	})
	local remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = d.Catalog.RemoteName, d.Storage
	self.Remote = remote
	table.insert(
		self.Connections,
		remote.OnServerEvent:Connect(function(player, action, payload, ...)
			if
				player.Parent ~= d.Players
				or select("#", ...) ~= 0
				or type(action) ~= "string"
				or #action > 24
				or type(payload) ~= "table"
			then
				return
			end
			local now = os.clock()
			local bucket = self.Limits[player] or { Time = now, Tokens = 10 }
			bucket.Tokens = math.min(10, bucket.Tokens + (now - bucket.Time) * 4)
			bucket.Time = now
			self.Limits[player] = bucket
			if bucket.Tokens < 1 or self.ActionBusy[player] or self.Closing then
				return
			end
			bucket.Tokens -= 1
			self.ActionBusy[player] = true
			local ok, err = pcall(function()
				self:Request(player, action, payload)
			end)
			self.ActionBusy[player] = nil
			if not ok then
				warn("Economy request: " .. tostring(err))
				self:Send(player, "Could not complete that action. Try again.")
			end
		end)
	)
	d.Marketplace.ProcessReceipt = function(receipt)
		return self:Receipt(receipt)
	end
	return self
end
function EconomyRuntime.AwardBadge(self: any, player: Player, key: string): boolean
	if not player or player.Parent ~= self.D.Players or type(key) ~= "string" or key == "" then
		return false
	end
	local catalog = self.D.Rewards and self.D.Rewards.Badges
	local badge = catalog and catalog[key]
	if not badge or not self.D.BadgeService then
		return false
	end
	local data = self.Profiles:Get(player.UserId)
	if not data then
		return false
	end
	local badgeId = tonumber(badge.Id)
	if not badgeId or badgeId <= 0 then
		return false
	end
	data.Badges = type(data.Badges) == "table" and data.Badges or {}
	local mark = tostring(badgeId)
	-- Already recorded (awarded before, or found owned): no Roblox call at all. One request per badge at a time.
	self.BadgeBusy = self.BadgeBusy or {}
	local busy = tostring(player.UserId) .. ":" .. mark
	if data.Badges[mark] or self.BadgeBusy[busy] then
		return false
	end
	-- Roblox only awards badges from live game servers: in Studio AwardBadge just returns false. Say so once and
	-- skip (nothing is recorded, so the badge is awarded for real in a live server).
	if self.D.RunService and self.D.RunService:IsStudio() then
		if not self.BadgeStudioNoted then
			self.BadgeStudioNoted = true
			-- Roblox only awards badges in live servers.
			print("Badges skipped in Studio.")
		end
		return false
	end
	self.BadgeBusy[busy] = true
	local checked, has = pcall(function()
		return self.D.BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
	end)
	local awarded, result = false, nil
	if checked and has ~= true and player.Parent == self.D.Players then
		awarded, result = pcall(function()
			return self.D.BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not awarded or result == false then
			-- Say why: a disabled badge, or one created for a different experience, is refused by Roblox.
			local reason = tostring(result)
			local infoOk, info = pcall(function()
				return self.D.BadgeService:GetBadgeInfoAsync(badgeId)
			end)
			if infoOk and type(info) == "table" then
				local universe = type(info.AwardingUniverse) == "table" and info.AwardingUniverse.Id or nil
				local here = self.D.GameId
				if info.IsEnabled == false then
					reason = "the badge is disabled (enable it on the Creator Dashboard)"
				elseif universe and here and here ~= 0 and universe ~= here then
					reason = "the badge belongs to experience " .. tostring(universe) .. ", this is " .. tostring(here)
				end
			end
			warn("Badge award failed: " .. key .. " (" .. tostring(badgeId) .. ") / " .. reason)
		end
	end
	self.BadgeBusy[busy] = nil
	-- Record owned or newly awarded badges in the (still leased) profile so they are never requested again.
	local current = self.Profiles:Get(player.UserId)
	local granted = awarded and result ~= false
	if current and ((checked and has == true) or granted) then
		current.Badges = type(current.Badges) == "table" and current.Badges or {}
		current.Badges[mark] = true
		if granted then
			self.Profiles:Save(player.UserId)
		end
	end
	return granted
end
-- Every badge BadgeRules says this player has earned from their profile (first play, match-win milestones).
function EconomyRuntime.CheckBadges(self: any, player: Player)
	local data = self.Profiles:Get(player.UserId)
	if not data or not self.D.BadgeRules then
		return
	end
	for _, key in self.D.BadgeRules.ForProfile(data) do
		self:AwardBadge(player, key)
	end
end

function EconomyRuntime.Sync(self: any, player: Player)
	local data = self.Profiles:Get(player.UserId)
	if not data then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	for _, name in { "Wins", "Streak" } do
		local value = stats:FindFirstChild(name)
		if not value then
			value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		if (value :: IntValue).Value ~= data[name] then
			(value :: IntValue).Value = data[name]
		end
	end
	local function attribute(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	attribute("Cash", data.Cash)
	attribute("Keys", data.Keys)
	-- Read by the client chat to show the gold [VIP] tag.
	attribute("VIP", data.VIP == true)
	-- Titles are earned by leveling up: unlock any the level now allows and say so.
	local levels = self.D.Config and self.D.Config.PlayerLevels
	if levels and self.D.Catalog then
		local unlocked = PlayerLevel.UnlockTitles(data, self.D.Catalog, levels)
		if #unlocked > 0 then
			self:Send(player, "New title unlocked: " .. table.concat(unlocked, ", ") .. "!", { Passive = true })
		end
	end
	if levels then
		self.SyncedLevels = self.SyncedLevels or {}
		local level = PlayerLevel.Info(data.PlayerXP, levels).Level
		local prior = self.SyncedLevels[player]
		self.SyncedLevels[player] = level
		if prior and level > prior and self.D.LeveledUp then
			self.D.LeveledUp(player)
		end
	end
	for index = 1, 8 do
		local id = data.Equipped.Pets[index]
		local info = if id then PetProgression.Info((data.PetXP or {})[id] or 0, self.D.Catalog.PetLevels) else nil
		attribute("Pet" .. index, id)
		attribute("PetLevel" .. index, if info then info.Level else nil)
		-- How far through its current level the pet is (0-1), for the pet tag's level bar; a maxed pet is full.
		attribute(
			"PetFill" .. index,
			if info
				then (if info.Max or info.Required <= 0 then 1 else math.clamp(info.XP / info.Required, 0, 1))
				else nil
		)
	end
end
-- Consecutive UTC days logged in: today extends yesterday's run, any longer gap starts again at one.
local function recordLogin(data: any)
	if not os then
		return
	end
	local day = math.floor(os.time() / 86400)
	local last = data.LoginDay or 0
	if last == day then
		return
	end
	data.LoginStreak = if last == day - 1 then (data.LoginStreak or 0) + 1 else 1
	data.LoginDay = day
end
function EconomyRuntime.Add(self: any, player: Player)
	if self.Closing or self.Loading[player] then
		return
	end
	local existing = self.Inventory.Profiles[player]
	if existing and existing.Data and existing.Data == self.Profiles:Get(player.UserId) then
		return
	end
	self.Loading[player] = true
	player:SetAttribute("DataReady", false)
	local data = self.Profiles:Load(player.UserId)
	if not data then
		self.Loading[player] = nil
		-- A DataStore hiccup should not cost the player their session; stay in the game and retry.
		if player.Parent then
			self.PendingLoad[player] = self.D.World:GetServerTimeNow() + 5
		end
		return
	end
	self.PendingLoad[player] = nil
	if player.Parent ~= self.D.Players or self.Closing then
		self.Profiles:Save(player.UserId, true)
		self.Loading[player] = nil
		return
	end
	local monetized = false
	-- Steal credits also turn Robux into spendable Cash indirectly.
	for _, product in self.D.Shop.Products do
		if product.ProductId > 0 then
			monetized = true
		end
	end
	self.Policy[player] = not monetized
	if monetized then
		local ok, policy = pcall(function()
			return self.D.Policy:GetPolicyInfoForPlayerAsync(player)
		end)
		self.Policy[player] = ok and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == false
	end
	if player.Parent ~= self.D.Players or self.Closing or self.Profiles:Get(player.UserId) ~= data then
		self.Policy[player] = nil
		if self.Profiles:Get(player.UserId) == data then
			self.Profiles:Save(player.UserId, true)
		end
		self.Loading[player] = nil
		return
	end
	self.Loading[player] = nil
	recordLogin(data)
	self.Inventory:AddPlayer(player)
	self.ShopClaims[player] = { Token = self.D.Http:GenerateGUID(false), Next = 0 }
	self:Sync(player)
	player:SetAttribute("DataReady", true)
	if data.PendingTransfer then
		task.spawn(function()
			self.Transfers:Run(player.UserId)
			self:Sync(player)
		end)
	end
	-- A pass bought outside this specific purchase flow (the item page, before this feature existed, etc.) would
	-- otherwise never grant its contents: PromptGamePassPurchaseFinished only fires for a purchase made just now.
	if not self.Memory then
		task.spawn(function()
			for id, pass in self.D.Shop.Passes or {} do
				if pass.PassId > 0 and not self:OwnsPass(data, id) then
					local ok, owns = pcall(function()
						return self.D.Marketplace:UserOwnsGamePassAsync(player.UserId, pass.PassId)
					end)
					if ok and owns and player.Parent == self.D.Players and self.Profiles:Get(player.UserId) == data then
						self:GrantPass(data, id)
						if self.Profiles:Save(player.UserId) then
							self:Sync(player)
						end
					end
				end
			end
		end)
	end
	self:Send(player, "")
end
-- Whether data already has a pass's contents (VIP keeps its own long-standing flag; everything else shares OwnedPasses).
function EconomyRuntime.OwnsPass(self: any, data: any, passId: string): boolean
	if passId == "VIP" then
		return data.VIP == true
	end
	return data.OwnedPasses ~= nil and data.OwnedPasses[passId] == true
end
-- Grants a pass's contents once (marks it owned first, so a save failure cannot cause a double-grant on retry).
function EconomyRuntime.GrantPass(self: any, data: any, passId: string)
	local pass = (self.D.Shop.Passes or {})[passId]
	if not pass then
		return
	end
	if passId == "VIP" then
		data.VIP = true
	else
		data.OwnedPasses = if type(data.OwnedPasses) == "table" then data.OwnedPasses else {}
		data.OwnedPasses[passId] = true
	end
	data.Cash += pass.Cash or 0
	data.Keys += pass.Keys or 0
	if pass.Chair then
		data.Owned.Chairs[pass.Chair] = 1
	end
end
function EconomyRuntime.Snapshot(self: any, player: Player)
	local state = self.Inventory:Snapshot(player)
	local data = self.Profiles:Get(player.UserId)
	if not state or not data then
		return nil
	end
	state.Keys, state.StealCredits = data.Keys, data.StealCredits
	state.InviteRewards = table.clone(data.InviteRewards)
	-- What one invited friend is worth to this player right now (scaled to their Cash), for the invite alert.
	state.InviteCash = if self.D.Wealth then self.D.Wealth.Cash(self.D.Rewards.InviteCash, data.Cash, "Invite") else self.D.Rewards.InviteCash
	state.VIP = data.VIP == true
	state.Rewards = self.Rewards:Snapshot(data)
	state.Potions = PotionService.Snapshot(data, os.time())
	state.PetProgress = PetProgression.Snapshot(data, self.D.Catalog.PetLevels)
	state.PlayerLevel = PlayerLevel.Info(data.PlayerXP, self.D.Config.PlayerLevels)
	state.FreeShop = self.D.Shop.FreeShop == true
	state.ShopToken = self.ShopClaims[player] and self.ShopClaims[player].Token
	state.AllowedRandom, state.Saving = self.Policy[player] == true, not self.Memory
	state.Stats = {}
	for _, name in
		{
			"Wins",
			"Streak",
			"HighestStreak",
			"Matches",
			"TimePlayed",
			"Hatches",
			"TotalEarned",
			"BestChainRound",
			"BestTeamChainRound",
		}
	do
		state.Stats[name] = data[name]
	end
	return state
end
function EconomyRuntime.Send(self: any, player: Player, message: string, extra: any?)
	if player.Parent ~= self.D.Players then
		return
	end
	local packet = extra or {}
	packet.State, packet.Message = self:Snapshot(player), message
	self.Remote:FireClient(player, packet)
end
local function small(value: any, maximum: number?): boolean
	return type(value) == "string" and #value <= (maximum or 64)
end
function EconomyRuntime.ResolveTarget(self: any, userId: number): any
	return (if userId>0 then self.D.Players:GetPlayerByUserId(userId) else nil) or (self.D.ResolveBot and self.D.ResolveBot(userId))
end
function EconomyRuntime.TargetData(self: any, target: any): any
	if typeof(target)=="table" and target.ManagedPopulation then return target.Profile and target.Profile.Data end
	return target and self.Profiles:Get(target.UserId)
end
function EconomyRuntime.Public(self: any, target: any)
	local data = self:TargetData(target)
	if not data then
		return nil
	end
	local profile: any = {
		UserId = target.UserId,
		AvatarUserId = if typeof(target)=="table" then target.AvatarUserId or target.UserId else target.UserId,
		Username = target.Name,
		DisplayName = target.DisplayName,
		Equipped = ProfileSchema.Copy(data.Equipped),
	}
	profile.VIP = data.VIP == true
	profile.LoginStreak = data.LoginStreak or 0
	profile.PlayerLevel = PlayerLevel.Info(data.PlayerXP, self.D.Config.PlayerLevels)
	profile.Level = profile.PlayerLevel.Level
	for _, stat in
		{
			"Wins",
			"Streak",
			"HighestStreak",
			"Matches",
			"TimePlayed",
			"Hatches",
			"TotalEarned",
			"BestChainRound",
			"BestTeamChainRound",
		}
	do
		profile[stat] = data[stat]
	end
	return profile
end
function EconomyRuntime.Near(self: any, player: Player, target: any): boolean
	local targetIsPlayer=target and typeof(target)=="Instance" and target:IsA("Player")
	local targetIsBot=typeof(target)=="table" and target.ManagedPopulation==true and target.Character and target.Character.Parent~=nil
	if
		not target
		or target == player
		or player.Parent ~= self.D.Players
		or (not targetIsPlayer and not targetIsBot)
		or (targetIsPlayer and target.Parent ~= self.D.Players)
		or self.D.Busy(player)
	then
		return false
	end
	local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	return a ~= nil
		and b ~= nil
		and ownHumanoid ~= nil
		and targetHumanoid ~= nil
		and ownHumanoid.Health > 0
		and targetHumanoid.Health > 0
		and not ownHumanoid.SeatPart
		and (a.Position - b.Position).Magnitude <= 12
		and self.Profiles:Get(player.UserId) ~= nil
		and self:TargetData(target) ~= nil
end
function EconomyRuntime.StealBot(self: any, player: Player, bot: any, free: boolean): (boolean, any?)
	local buyer, target = self.Profiles:Get(player.UserId), self:TargetData(bot)
	if not buyer or not target or self.ActionBusy[bot] or target.Cash<=0 then return false end
	self.ActionBusy[bot]=true
	local amount=target.Cash
	local oldCash,oldCredits,oldPending=buyer.Cash,buyer.StealCredits,buyer.PendingStealTarget
	target.Cash=0
	buyer.Cash+=amount
	if not free then buyer.StealCredits=math.max(0,buyer.StealCredits-1) end
	buyer.PendingStealTarget=nil
	local ok,saved=pcall(function() return self.Profiles:Save(player.UserId) end)
	if not ok or not saved then
		target.Cash=amount
		buyer.Cash,buyer.StealCredits,buyer.PendingStealTarget=oldCash,oldCredits,oldPending
		self.ActionBusy[bot]=nil
		return false
	end
	self.ActionBusy[bot]=nil
	if bot.Character and bot.Character.Parent then bot.Character:SetAttribute("Cash",target.Cash) end
	return true,{Amount=amount}
end
-- Walking into Workspace.Game.Triggers.LuckyBlocksTrigger opens the Lucky Blocks menu on its first block.
function EconomyRuntime.OpenLuckyBlocks(self: any, player: Player)
	if self.Closing or player.Parent ~= self.D.Players or self.D.Busy(player) then
		return
	end
	if not self.Profiles:Get(player.UserId) or not self.Inventory.Profiles[player] then
		return
	end
	-- A region where paid random items are restricted never gets the frame at all, walking into the world trigger
	-- included -- just a short alert. The client gates its own direct open (the HUD button) the same way.
	if self.Policy[player] ~= true then
		self:Send(player, "Not allowed in your region.")
		return
	end
	local first = self.D.Shop.BlockOrder[1]
	if first then
		self:Send(player, "", { OpenContainer = first })
	end
end
function EconomyRuntime.PurchaseChair(self: any, player: Player, id: string)
	if
		self.Closing
		or self.ActionBusy[player]
		or self.Transfers.Busy[player.UserId]
		or player.Parent ~= self.D.Players
		or self.D.Busy(player)
	then
		return
	end
	if not self.Profiles:Get(player.UserId) then
		return
	end
	self.ActionBusy[player] = true
	local success, problem = pcall(function()
		local data = self.Profiles:Get(player.UserId)
		local hadChair = data and type(id) == "string" and data.Owned.Chairs[id] ~= nil
		local ok, message = self.Inventory:BuyChair(player, id)
		if ok and not self.Profiles:Save(player.UserId) then
			message = "Chair updated. Saving..."
		end
		-- A newly bought chair opens the inventory on its Chairs tab.
		local bought = ok and not hadChair
		self:Sync(player)
		self:Send(player, message, if bought then { OpenInventory = "Chairs", Purchased = true } else nil)
	end)
	self.ActionBusy[player] = nil
	if not success then
		warn("Chair purchase: " .. tostring(problem))
		self:Send(player, "Could not complete that action. Try again.")
	end
end
-- Sends a player to the AFK place (from the AFK portal prompt): needs a loaded profile and no active match.
function EconomyRuntime.SendToAFK(self: any, player: Player): boolean
	if self.Closing or not self.Travel or player.Parent ~= self.D.Players or self.D.Busy(player) then
		return false
	end
	local data = self.Profiles:Get(player.UserId)
	if not data or self.ActionBusy[player] then
		return false
	end
	local required = self.D.Config.AFKRequiredWins or 5
	if (data.Wins or 0) < required then
		self:Send(player, "AFK World requires " .. required .. " wins.")
		return false
	end
	return self.Travel:Start(player, self.D.Config.AFKPlaceId)
end
function EconomyRuntime.Request(self: any, player: Player, action: string, p: any)
	local data = self.Profiles:Get(player.UserId)
	-- Before the profile has loaded there is nothing to answer: stay quiet (no alert) and the state is pushed when it loads.
	if not data or not self.Inventory.Profiles[player] then
		return
	end
	if action == "AFK" and self.Travel then
		self:SendToAFK(player)
		return
	end
	if action == "Refresh" then
		self:Send(player, "")
		return
	end
	if action == "Profile" then
		if
			p.UserId ~= nil
			and (
				type(p.UserId) ~= "number"
				or p.UserId ~= p.UserId
				or p.UserId == 0
				or math.abs(p.UserId) >= 2 ^ 53
				or p.UserId % 1 ~= 0
			)
		then
			self:Send(player, "Invalid player.")
			return
		end
		local target = if type(p.UserId) == "number" then self:ResolveTarget(p.UserId) else player
		self:Send(
			player,
			if target then "" else "Player left the server.",
			{ Profile = target and self:Public(target) }
		)
		return
	end
	if self.Transfers.Busy[player.UserId] then
		self:Send(player, "Transfer in progress. Wait.")
		return
	end
	if self.D.Busy(player) then
		self:Send(player, "Finish your match first.")
		return
	end
	if action == "ClaimReward" and small(p.Category, 16) and small(p.Id, 32) then
		local claimed, message, reason = self.Rewards:Claim(player, p.Category, p.Id)
		self:Sync(player)
		self:Send(
			player,
			message,
			{
				JoinGroupId = if reason == "JoinGroup" then self.D.GroupId else nil,
				RewardClaimed = if claimed then true else nil,
			}
		)
		return
	end
	local ok, result = false, "Invalid action (" .. string.sub(action, 1, 24) .. ")."
	local openInventory
	local purchased, claimedReward = false, false
	if action == "BuyPet" and small(p.Token) and small(p.Shop) and small(p.Id) then
		ok, result = self.Inventory:BuyPet(player, p.Token, p.Shop, p.Id)
		if ok and not self.Profiles:Save(player.UserId) then
			result = "Pet added. Saving..."
		end
		-- Buying a pet just confirms itself; the inventory is not opened.
		if ok then
			purchased = true
		end
	elseif action == "Hatch" and small(p.Token) and small(p.Container) and small(p.Payment) then
		ok, result = self.Inventory:Buy(player, p.Token, p.Container, p.Payment, p.Count)
		local saved = not ok or self.Profiles:Save(player.UserId)
		if ok and self.D.HatchedPet then
			self.D.HatchedPet(player)
		end
		self:Sync(player)
		self:Send(
			player,
			if ok then (if saved then "" else "Pet added. Saving...") else result,
			-- Opening an owned block (e.g. from the AFK world) is not a purchase.
			{ Hatch = if ok then result else nil, Purchased = if ok and not result.FromStock then true else nil }
		)
		return
	elseif action == "Equip" and small(p.Category) and small(p.Id) then
		ok, result = self.Inventory:Equip(player, p.Category, p.Id)
	elseif action == "UnequipPet" then
		ok, result = self.Inventory:UnequipPet(player, p.Slot)
	elseif action == "Product" and small(p.Id) then
		local product = self.D.Shop.Products[p.Id]
		local pass = (self.D.Shop.Passes or {})[p.Id]
		if self.D.Shop.FreeShop then
			local claim = self.ShopClaims[player]
			local now = self.D.World:GetServerTimeNow()
			if not claim or not small(p.Token) or p.Token ~= claim.Token then
				result = "Refresh the shop and try again."
			elseif now < claim.Next then
				result = "Wait before claiming again."
			elseif pass then
				if self:OwnsPass(data, p.Id) then
					result = pass.Name .. " already claimed."
				else
					claim.Token, claim.Next = self.D.Http:GenerateGUID(false), now + 1
					self:GrantPass(data, p.Id)
					ok = true
					result = if self.Profiles:Save(player.UserId)
						then "Free " .. pass.Name .. " claimed!"
						else "Items added. Saving..."
				end
			elseif
				not product
				or (
					product.Kind ~= "Cash"
					and product.Kind ~= "Keys"
					and product.Kind ~= "Potion"
					and product.Kind ~= "GoldenDeal"
				)
			then
				result = "Invalid product."
			else
				claim.Token, claim.Next = self.D.Http:GenerateGUID(false), now + 1
				if product.Kind == "Potion" then
					PotionService.Grant(data, product, os.time())
				elseif product.Kind == "GoldenDeal" then
					data.Cash += product.Cash or 0
					if product.Pet then
						data.Owned.Pets[product.Pet] = (data.Owned.Pets[product.Pet] or 0) + 1
					end
					if product.PotionBoost then
						PotionService.Grant(data, { Kind = "Potion", Boost = product.PotionBoost, Seconds = product.PotionSeconds }, os.time())
					end
				else
					data[product.Kind] += product.Amount
				end
				ok = true
				result = if self.Profiles:Save(player.UserId)
					then "Free " .. product.Name .. " claimed!"
					else "Items added. Saving..."
			end
		elseif pass then
			if self:OwnsPass(data, p.Id) then
				result = pass.Name .. " already owned!"
			elseif pass.PassId <= 0 then
				result = "Coming soon!"
			elseif self.Memory then
				result = "Needs a saved server."
			elseif self.D.World:GetServerTimeNow() < (self.PurchaseAt[player] or 0) then
				result = "Wait before opening another purchase."
			else
				self.PurchaseAt[player] = self.D.World:GetServerTimeNow() + 1
				self.D.Marketplace:PromptGamePassPurchase(player, pass.PassId)
				ok, result = true, ""
			end
		elseif not product or product.Kind == "StealCredits" then
			result = "Invalid product."
		elseif product.ProductId <= 0 then
			result = "Coming soon!"
		elseif self.Memory then
			result = "Needs a saved server."
		elseif self.D.World:GetServerTimeNow() < (self.PurchaseAt[player] or 0) then
			result = "Wait before opening another purchase."
		else
			self.PurchaseAt[player] = self.D.World:GetServerTimeNow() + 1
			self.D.Marketplace:PromptProductPurchase(player, product.ProductId)
			ok, result = true, ""
		end
	elseif action == "Code" and small(p.Code, 32) then
		-- Store > Codes: one redemption per code per player, with a short pause between attempts.
		local now = os.clock()
		local key = string.upper((string.gsub(p.Code, "^%s*(.-)%s*$", "%1")))
		local reward = self.D.Rewards.Codes and self.D.Rewards.Codes[key]
		if now < (self.CodeAt[player] or 0) then
			result = "Wait a moment."
		elseif key == "" then
			result = "Enter a code."
		else
			self.CodeAt[player] = now + 2
			if not reward then
				result = "Invalid code."
			elseif data.RedeemedCodes[key] then
				result = "Already used!"
			else
				data.RedeemedCodes[key] = true
				data.Cash += reward.Cash or 0
				data.TotalEarned += reward.Cash or 0
				data.Keys += reward.Keys or 0
				ok, claimedReward = true, true
				local parts = {}
				if (reward.Cash or 0) > 0 then
					table.insert(parts, "+" .. money(reward.Cash))
				end
				if (reward.Keys or 0) > 0 then
					table.insert(parts, "+" .. reward.Keys .. (if reward.Keys == 1 then " Gem" else " Gems"))
				end
				result = if self.Profiles:Save(player.UserId)
					then "Code redeemed! " .. table.concat(parts, " ")
					else "Code added. Saving..."
			end
		end
	elseif
		action == "Steal"
		and type(p.UserId) == "number"
		and p.UserId == p.UserId
		and math.abs(p.UserId) < 2 ^ 53
		and p.UserId % 1 == 0
		and (small(p.Token) or self.D.Shop.FreeSteal == true)
	then
		local target = self:ResolveTarget(p.UserId)
		local targetData = self:TargetData(target)
		local inventory = self.Inventory.Profiles[player]
		local now = self.D.World:GetServerTimeNow()
		-- While stealing is free there is no purchase to guard, so the token is not needed (cooldown and range still apply).
		if self.D.Shop.FreeSteal ~= true and p.Token ~= inventory.Token then
			result = "That changed. Try again."
		elseif now < (self.StealAt[player] or 0) then
			result = "Wait before stealing again."
		elseif
			not data.PendingTransfer
			and (not self:Near(player, target) or self.ActionBusy[target] or self.Transfers.Busy[target.UserId])
		then
			result = "Get closer to steal."
		elseif not data.PendingTransfer and (not targetData or targetData.Cash <= 0) then
			result = "They have no Cash!"
		elseif data.PendingTransfer or self.D.Shop.FreeSteal or data.StealCredits > 0 then
			inventory.Token = self.D.Http:GenerateGUID(false)
			self.StealAt[player] = now + self.D.Shop.StealCooldownSeconds
			local transfer
			if data.PendingTransfer then
				ok,transfer=self.Transfers:Run(player.UserId,target and target.UserId,self.D.Shop.FreeSteal==true)
			elseif typeof(target)=="table" and target.ManagedPopulation then
				ok,transfer=self:StealBot(player,target,self.D.Shop.FreeSteal==true)
			else
				ok, transfer = self.Transfers:Run(player.UserId, target and target.UserId, self.D.Shop.FreeSteal == true)
			end
			result = if ok
				then "Stole " .. money(transfer.Amount) .. "!"
				elseif data.PendingTransfer then "Transfer in progress. Wait."
				else "Player left."
		elseif self.D.Shop.Products.Steal.ProductId <= 0 then
			result = "Stealing is coming soon!"
		elseif self.Memory then
			result = "Needs a saved server."
		elseif now < (self.PurchaseAt[player] or 0) then
			result = "Wait before opening another purchase."
		else
			self.PurchaseAt[player] = now + 1
			if typeof(target)=="table" and target.ManagedPopulation then
				self.PendingBotSteal[player]={UserId=target.UserId}
				data.PendingStealTarget=nil
			else
				self.PendingBotSteal[player]=nil
				data.PendingStealTarget = target.UserId
			end
			if self.Profiles:Save(player.UserId) then
				local prompted=pcall(function()
					self.D.Marketplace:PromptProductPurchase(player,self.D.Shop.Products.Steal.ProductId)
				end)
				if prompted then ok,result=true,"" else self:CancelStealPrompt(player);result="Could not open purchase. Try again." end
			else
				self:CancelStealPrompt(player)
				result="Could not save. Try again."
			end
		end
	end
	-- Free shop claims that succeeded are purchases too (a Robux prompt opening is not).
	if action == "Product" and ok and result ~= "" then
		purchased = true
	end
	local extra
	if openInventory or purchased or claimedReward then
		extra = { OpenInventory = openInventory, Purchased = purchased or nil, RewardClaimed = claimedReward or nil }
	end
	self:Sync(player)
	self:Send(player, result, extra)
end
function EconomyRuntime.Receipt(self: any, receipt: any)
	local retry = Enum.ProductPurchaseDecision.NotProcessedYet
	if
		type(receipt) ~= "table"
		or type(receipt.PlayerId) ~= "number"
		or receipt.PlayerId ~= receipt.PlayerId
		or receipt.PlayerId <= 0
		or receipt.PlayerId >= 2 ^ 53
		or receipt.PlayerId % 1 ~= 0
		or type(receipt.ProductId) ~= "number"
		or receipt.ProductId ~= receipt.ProductId
		or receipt.ProductId <= 0
		or receipt.ProductId >= 2 ^ 53
		or receipt.ProductId % 1 ~= 0
		or (type(receipt.PurchaseId) ~= "string" and type(receipt.PurchaseId) ~= "number")
	then
		return retry
	end
	local player = self.D.Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and self.Profiles:Get(receipt.PlayerId)
	if not data or self.Memory or player:GetAttribute("Traveling") then
		return retry
	end
	local product
	for _, item in self.D.Shop.Products do
		if item.ProductId > 0 and item.ProductId == receipt.ProductId then
			product = item
			break
		end
	end
	if not product then
		return retry
	end
	local id = tostring(receipt.PurchaseId)
	if not data.Receipts[id] then
		if product.Kind == "Potion" then
			PotionService.Grant(data, product, os.time())
		elseif product.Kind == "GoldenDeal" then
			data.Cash += product.Cash or 0
			if product.Pet then
				data.Owned.Pets[product.Pet] = (data.Owned.Pets[product.Pet] or 0) + 1
			end
			if product.PotionBoost then
				PotionService.Grant(data, { Kind = "Potion", Boost = product.PotionBoost, Seconds = product.PotionSeconds }, os.time())
			end
		else
			data[product.Kind] += product.Amount
		end
		data.Receipts[id] = true
	end
	if not self.Profiles:Save(receipt.PlayerId) then
		return retry
	end
	self:Sync(player)
	local hasPendingSteal = product.Kind == "StealCredits" and (data.PendingStealTarget or self.PendingBotSteal[player])
	-- Replayed purchases send their specific result below, so do not precede it with a vague purchase message.
	if
		not (
			(product.Kind == "HintCredits" and self.D.RetryHint)
			or (product.Kind == "HeartCredits" and self.D.RetryHeart)
			or hasPendingSteal
		)
	then
		self:Send(player, "Purchase received!")
	end
	if self.D.Purchased then
		self.D.Purchased(player)
	end
	local pendingBotSteal=self.PendingBotSteal[player]
	if product.Kind == "StealCredits" and (data.PendingStealTarget or pendingBotSteal) then
		self.PendingBotSteal[player]=nil
		local pendingTarget=if pendingBotSteal then pendingBotSteal.UserId else data.PendingStealTarget
		task.spawn(function()
			local target = self:ResolveTarget(pendingTarget)
			local completed, transfer = false, nil
			if typeof(target)=="table" and target.ManagedPopulation then
				-- Proximity was validated before opening the native purchase UI. NPC movement during that UI must not
				-- cancel a paid steal, so the exact server-stored NPC target is fulfilled wherever it moved.
				completed, transfer = self:StealBot(player,target,false)
			elseif pendingTarget > 0 then
				-- The receipt is authoritative and the target ID was stored before prompting. This flag bypasses only the
				-- second proximity check; TransferService still validates profiles, Cash, journals and receipt credit.
				completed, transfer = self.Transfers:Run(player.UserId, pendingTarget, false, true)
			end
			if not completed and not data.PendingTransfer then
				-- The target actually vanished or had no Cash. Keep the purchased credit usable, but discard the stale
				-- automatic target so the next press can select somebody else.
				if data.PendingStealTarget==pendingTarget then data.PendingStealTarget=nil end
				self.Profiles:Save(player.UserId)
			end
			self:Sync(player)
			if target and typeof(target)=="Instance" then
				self:Sync(target)
			end
			local message = if completed and transfer
				then "Stole " .. money(transfer.Amount) .. "!"
				elseif data.PendingTransfer then "Steal is finishing..."
				else "Target unavailable - steal ready to use again."
			self:Send(player, message)
		end)
	end
	if product.Kind == "HeartCredits" and self.D.RetryHeart then
		task.spawn(function()
			self.D.RetryHeart(player)
		end)
	end
	if product.Kind == "HintCredits" and self.D.RetryHint then
		task.spawn(function()
			self.D.RetryHint(player)
		end)
	end
	if product.Kind == "SabotageCredits" and data.PendingSabotage and self.D.RetrySabotage then
		local pending = data.PendingSabotage
		data.PendingSabotage = nil
		task.spawn(function()
			self.D.RetrySabotage(player, pending)
		end)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
-- MarketplaceService.PromptGamePassPurchaseFinished: gamepasses do not go through ProcessReceipt, only this event
-- (plus the join-time UserOwnsGamePassAsync check in Add, for a pass bought outside this exact flow).
function EconomyRuntime.GamePassPurchaseFinished(self: any, player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or self.Closing or player.Parent ~= self.D.Players then
		return
	end
	local data = self.Profiles:Get(player.UserId)
	if not data then
		return
	end
	local passId
	for id, pass in self.D.Shop.Passes or {} do
		if pass.PassId == gamePassId then
			passId = id
			break
		end
	end
	if not passId or self:OwnsPass(data, passId) then
		return
	end
	self:GrantPass(data, passId)
	if self.Profiles:Save(player.UserId) then
		self:Sync(player)
		self:Send(player, "Purchase received!")
		if self.D.Purchased then
			self.D.Purchased(player)
		end
	end
end
local function petEffects(match: any, index: number): any
	return if match.PetEffects and match.PetEffects[index] then match.PetEffects[index] else {}
end
-- Sharp Eye payouts arrive mid-match, straight into the wallet.
function EconomyRuntime.PetCash(self: any, match: any, index: number, amount: number)
	if
		type(match) ~= "table"
		or type(index) ~= "number"
		or index % 1 ~= 0
		or type(amount) ~= "number"
		or amount ~= amount
		or amount <= 0
		or amount >= math.huge
		or amount % 1 ~= 0
		or amount > 1000000
		or (match.Departed and match.Departed[index])
	then
		return
	end
	local player = match.Players and match.Players[index]
	local data = player and self.Profiles:Get(player.UserId)
	if data then
		data.Cash += amount
		data.TotalEarned += amount
		self:Sync(player)
	end
end
-- A Streak Saver pet gives a chance to keep the win streak through a loss.
function EconomyRuntime.LoseStreak(self: any, match: any, index: number, player: any, data: any)
	local saver = petEffects(match, index).StreakSaver
	if saver and data.Streak > 0 and (self.D.Roll or math.random)() * 100 < saver.Power then
		self:Send(player, saver.Name .. " saved your win streak!")
		return
	end
	data.Streak = 0
end
function EconomyRuntime.Settle(self: any, match: any, winner: number)
	match.StatRecorded = match.StatRecorded or {}
	match.RewardedAt = match.RewardedAt or os.time()
	-- Records before this match settles, for the chat announcements below.
	local before: any = {}
	for index, player in match.Players do
		local data = if match.StatRecorded[index] then nil else self.Profiles:Get(player.UserId)
		if data then
			before[index] = { Wins = data.Wins, Streak = data.Streak }
		end
	end
	for index, player in match.Players do
		if match.StatRecorded[index] then
			continue
		end
		local data = self.Profiles:Get(player.UserId)
		if data then
			match.StatRecorded[index] = true
			data.Matches += 1
			PlayerLevel.MatchFinished(data, self.D.Config.PlayerLevels, index == winner)
			if index == winner then
				local potionWins = PotionService.Multiplier(data, "Wins", match.RewardedAt)
				local wins = potionWins
				if self.D.GameConfig and self.D.GameConfig.ComboWinsBonus then
					local comboStreak = if match.ComboStreak then match.ComboStreak[index] or 0 else 0
					wins = self.D.GameConfig.ComboWinsBonus(comboStreak, potionWins)
				end
				data.Wins += wins
				data.Streak += PotionService.Multiplier(data, "Streak", match.RewardedAt)
				data.HighestStreak = math.max(data.HighestStreak, data.Streak)
				data.Keys += 1
				local effects, messages = petEffects(match, index), {}
				if effects.CashBonus and (match.Reward or 0) > 0 then
					local bonus = math.floor(match.Reward * effects.CashBonus.Power / 100)
					if bonus > 0 then
						data.Cash += bonus
						data.TotalEarned += bonus
						table.insert(messages, effects.CashBonus.Name .. " added +$" .. bonus .. " to your prize!")
					end
				end
				if effects.KeyFinder and (self.D.Roll or math.random)() * 100 < effects.KeyFinder.Power then
					data.Keys += 1
					table.insert(messages, effects.KeyFinder.Name .. " found a bonus Gem!")
				end
				if #messages > 0 then
					self:Send(player, table.concat(messages, " "))
				end
			else
				self:LoseStreak(match, index, player, data)
			end
			self:Sync(player)
		end
	end
	self:AnnounceResult(match, winner, before)
end
-- Chat news for a settled match: the winner's win/streak milestones and the most notable player they beat.
function EconomyRuntime.AnnounceResult(self: any, match: any, winner: number, before: any)
	local News, publish = self.D.ChatNews, self.News
	local won = before[winner]
	local winnerPlayer = match.Players[winner]
	if not News or not publish or not won or not winnerPlayer or winnerPlayer.Parent ~= self.D.Players then
		return
	end
	local data = self.Profiles:Get(winnerPlayer.UserId)
	if not data then
		return
	end
	local name = winnerPlayer.DisplayName
	local best: any, bestScore = nil, -1
	for index, player in match.Players do
		local record = before[index]
		if index ~= winner and record and News.BeatWorthy(record.Wins, record.Streak) then
			local score = record.Streak * 1000 + record.Wins
			if score > bestScore then
				best, bestScore = { Player = player, Streak = record.Streak }, score
			end
		end
	end
	if best then
		publish({ Kind = "Beat", Name = name, Other = best.Player.DisplayName, Streak = best.Streak })
	end
	local wins = News.Crossed(News.WinMilestones, won.Wins, data.Wins)
	if wins then
		publish({ Kind = "Wins", Name = name, Count = wins })
	end
	local streak = News.Crossed(News.StreakMilestones, won.Streak, data.Streak)
	if streak then
		publish({ Kind = "Streak", Name = name, Count = streak })
	end
end
function EconomyRuntime.RoundComplete(self: any, match: any, config: any)
	local updated = ChainProgress.Apply(match, config, function(player)
		return self.Profiles:Get(player.UserId)
	end)
	for _, entry in updated do
		self:Sync(entry.Player)
		self:Send(
			entry.Player,
			if entry.Milestone
				then "ROUND "
					.. match.CurrentRound
					.. " MILESTONE! +"
					.. money(config.ChainMilestoneCash)
					.. " / +"
					.. config.ChainMilestoneKeys
					.. " Gem"
				else "",
			{ Passive = true }
		)
	end
end
function EconomyRuntime.Eliminated(self: any, match: any, index: number)
	match.StatRecorded = match.StatRecorded or {}
	if match.StatRecorded[index] then
		return
	end
	local player = match.Players[index]
	local data = self.Profiles:Get(player.UserId)
	if data then
		data.Matches += 1
		PlayerLevel.MatchFinished(data, self.D.Config.PlayerLevels, false)
		self:LoseStreak(match, index, player, data)
		match.StatRecorded[index] = true
		self:Sync(player)
	end
end
function EconomyRuntime.Tick(self: any, dt: number)
	if self.Closing then
		return
	end
	self.Clock += dt
	self.SaveClock += dt
	if self.Clock >= 1 then
		local elapsed = math.floor(self.Clock)
		self.Clock -= elapsed
		local now = self.D.World:GetServerTimeNow()
		for player, retryAt in self.PendingLoad do
			if not self.Loading[player] and now >= retryAt then
				if player.Parent == self.D.Players then
					self:Add(player)
				else
					self.PendingLoad[player] = nil
				end
			end
		end
		for _, player in self.D.Players:GetPlayers() do
			local data = self.Profiles:Get(player.UserId)
			if data and not player:GetAttribute("Traveling") then
				data.TimePlayed += elapsed
				self.Rewards:Tick(data, elapsed)
				PlayerLevel.Tick(data, self.D.Config.PlayerLevels, elapsed)
				PetProgression.Tick(data, self.D.Catalog.PetLevels, elapsed)
				self:Sync(player)
				self.Referrals:Tick(player, self.D.World:GetServerTimeNow())
				if math.floor(data.TimePlayed / 5) ~= math.floor((data.TimePlayed - elapsed) / 5) then
					self.Remote:FireClient(
						player,
						{ PetProgress = PetProgression.Snapshot(data, self.D.Catalog.PetLevels) }
					)
				end
			end
		end
	end
	if self.SaveClock >= self.D.Config.AutosaveSeconds then
		self.SaveClock = 0
		local pending = {}
		for id, entry in self.Profiles.Entries do
			if not entry.Busy then
				table.insert(pending, { Id = id, Closing = entry.Closing })
			end
		end
		-- Bound autosave concurrency. Large servers no longer create one yielding task and datastore request per player
		-- on the same frame, while every eligible profile is still saved during this autosave pass.
		local nextIndex = 0
		for _ = 1, math.min(8, #pending) do
			task.spawn(function()
				while not self.Closing do
					nextIndex += 1
					local item = pending[nextIndex]
					if not item then return end
					local current = self.Profiles.Entries[item.Id]
					if current and not current.Busy then
						self.Profiles:Save(item.Id, item.Closing)
					end
				end
			end)
		end
	end
end
function EconomyRuntime.CancelStealPrompt(self: any,player: Player)
	self.PendingBotSteal[player]=nil
	local data=self.Profiles:Get(player.UserId)
	if data and data.PendingStealTarget then
		data.PendingStealTarget=nil
		task.spawn(function() self.Profiles:Save(player.UserId) end)
	end
end
function EconomyRuntime.Remove(self: any, player: Player)
	self.Referrals:Remove(player)
	self.Inventory:RemovePlayer(player)
	self.Currency:RemovePlayer(player)
	self.Policy[player], self.Limits[player], self.ActionBusy[player] = nil, nil, nil
	self.ShopClaims[player] = nil
	self.StealAt[player], self.CodeAt[player], self.PurchaseAt[player] = nil, nil, nil
	self.PendingBotSteal[player]=nil
	self.PendingLoad[player] = nil
	if self.SyncedLevels then self.SyncedLevels[player] = nil end
	self.Profiles:Save(player.UserId, true)
end
function EconomyRuntime.Close(self: any)
	self.Closing = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	local remaining = 0
	for id in self.Profiles.Entries do
		remaining += 1
		task.spawn(function()
			self.Profiles:Save(id, true)
			remaining -= 1
		end)
	end
	local deadline = os.clock() + 25
	while (remaining > 0 or next(self.Loading)) and os.clock() < deadline do
		task.wait(0.1)
	end
end
return EconomyRuntime

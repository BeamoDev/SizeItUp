--!strict
-- Populates the authored lobby with lightweight fake players cloned from ServerStorage.Characters.NPC.
-- NPCs wander between authored attractions, wait at tables and sometimes fill ambient bot-only matches.
-- Every seated NPC still uses the normal TableService / MatchService path.
local NPCPopulationService = {}
NPCPopulationService.__index = NPCPopulationService

-- Mix several common Roblox username eras instead of giving every NPC a plain first name. The word lists are
-- deliberately broad, while the combinations make repeats across servers very unlikely.
local ADJECTIVES = {
	"Arctic", "Astro", "Blazing", "Blue", "Bold", "Chill", "Cloudy", "Cosmic", "Cozy", "Crimson",
	"Electric", "Faded", "Frosty", "Golden", "Hidden", "Hyper", "Icy", "Jolly", "Lucky", "Lunar",
	"Minty", "Neon", "Night", "Pixel", "Purple", "Quick", "Quiet", "Retro", "Royal", "Silent",
	"Silver", "Sleepy", "Solar", "Speedy", "Starry", "Stormy", "Sunny", "Tiny", "Turbo", "Wild",
}
local NOUNS = {
	"Axolotl", "Badger", "Bean", "Bear", "Bee", "Berry", "Biscuit", "Boba", "Bunny", "Cactus",
	"Cat", "Comet", "Crow", "Dino", "Doodle", "Dragon", "Duck", "Echo", "Falcon", "Finch",
	"Fox", "Frog", "Gecko", "Ghost", "Glitch", "Koala", "Mango", "Mochi", "Noodle", "Nova",
	"Orbit", "Otter", "Panda", "Pebble", "Penguin", "Phoenix", "Pickle", "Pigeon", "Raven", "Rocket",
	"Shark", "Sloth", "Socks", "Sparrow", "Sprout", "Toast", "Viper", "Waffle", "Wolf", "Yeti",
}
local NAME_BITS = {
	"adi", "aria", "ash", "benji", "cam", "dani", "eli", "emi", "finn", "gia", "iza", "jax",
	"jay", "jo", "kace", "kai", "kenz", "leo", "lex", "liv", "luca", "mari", "max", "mika",
	"niko", "noa", "oli", "remi", "ria", "rio", "sammy", "shay", "theo", "val", "zane", "zo",
}
local SYLLABLES = { "ae", "ari", "aze", "cy", "dra", "eko", "eli", "ka", "kyo", "lumi", "ny", "ori", "rae", "rix", "sai", "sen", "vex", "xen", "yuki", "zen" }
local ENDINGS = { "byte", "core", "ix", "ly", "on", "ora", "ster", "sy", "ton", "verse", "zy" }

-- Known public Roblox accounts provide valid, varied headshots. An NPC template may override this with a
-- positive AvatarUserId attribute, which is useful when its authored outfit has a matching account avatar.
local AVATAR_USER_IDS = {
	156, 261, 19358, 80254, 1086460, 2837719, 7596872, 11362504, 33233502, 519140279,
}

local function shuffledCopy(random: Random, values: { any }): { any }
	local result = table.clone(values)
	for index = #result, 2, -1 do
		local other = random:NextInteger(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

local function modelPart(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function addParts(root: Instance?, result: { BasePart })
	if not root then return end
	if root:IsA("BasePart") then table.insert(result, root) end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then table.insert(result, descendant) end
	end
end

local PHYSICS_ACTUATORS = {
	AlignOrientation = true,
	AlignPosition = true,
	AngularVelocity = true,
	BodyAngularVelocity = true,
	BodyForce = true,
	BodyGyro = true,
	BodyPosition = true,
	BodyThrust = true,
	BodyVelocity = true,
	LinearVelocity = true,
	RocketPropulsion = true,
	Torque = true,
	VectorForce = true,
}

local function clearAssemblyMotion(character: Instance)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function stopWalking(bot: any)
	if not bot.Humanoid or not bot.Humanoid.Parent then return end
	-- Clear both the destination and directional input before another route or seat takes over.
	if bot.Root and bot.Root.Parent then bot.Humanoid:MoveTo(bot.Root.Position) end
	bot.Humanoid:Move(Vector3.zero)
	bot.Humanoid.Jump = false
end

local function currentWalk(self: any, bot: any, token: number): boolean
	return not self.Destroyed and self:Owns(bot) and token == bot.MoveToken
		and bot.Root.Parent ~= nil and bot.Humanoid.Parent ~= nil and bot.Humanoid.Health > 0
		and bot.State ~= "SEATING" and not bot.Humanoid.Sit and not bot.Humanoid.SeatPart
		and not self.D.IsMatched(bot) and not self.D.Bindings:SeatAttachment(bot.Character)
end

local function finiteVector(value: Vector3): boolean
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

function NPCPopulationService.new(d: any)
	local config = d.Config or {}
	local runtime = d.World:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = d.World
	end
	local runtimeRoot = runtime:FindFirstChild("NPC")
	if not runtimeRoot then
		runtimeRoot = Instance.new("Folder")
		runtimeRoot.Name = "NPC"
		runtimeRoot.Parent = runtime
	end

	local self: any = setmetatable({
		D = d,
		Config = config,
		Root = runtimeRoot,
		Random = Random.new(),
		Bots = {},
		BotSet = {},
		Reservations = {},
		HumanTablePlans = setmetatable({}, { __mode = "k" }),
		BotTablePlans = setmetatable({}, { __mode = "k" }),
		Connections = {},
		AvatarIds = {},
		AvatarCycle = 0,
		NextId = d.BotUserIdCeiling,
		Clock = 0,
		NextPopulationAt = 0,
		NextInterestRefresh = 0,
		Interests = {},
		Destroyed = false,
	}, NPCPopulationService)
	self.AvatarIds = shuffledCopy(self.Random, AVATAR_USER_IDS)
	self.PopulationTarget = self.Random:NextInteger(
		self.Config.TargetVisiblePopulationMin or 12,
		self.Config.TargetVisiblePopulationMax or 15
	)
	self.NextChatAt = d.Now() + self.Random:NextNumber(self.Config.ChatIntervalMin or 75, self.Config.ChatIntervalMax or 160)
	local characters = d.ServerStorage:FindFirstChild("Characters")
	local templates = characters and characters:FindFirstChild("NPC")
	if templates then
		table.insert(self.Connections, templates.ChildAdded:Connect(function() self.TemplateCache = nil end))
		table.insert(self.Connections, templates.ChildRemoved:Connect(function() self.TemplateCache = nil end))
	end
	self:RefreshInterests()
	return self
end

function NPCPopulationService.Templates(self: any): { Model }
	if self.TemplateCache then return self.TemplateCache end
	local characters = self.D.ServerStorage:FindFirstChild("Characters")
	local folder = characters and characters:FindFirstChild("NPC")
	local result = {}
	if folder then
		for _, child in folder:GetChildren() do
			local root = child:IsA("Model") and child:FindFirstChild("HumanoidRootPart")
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and root and root:IsA("BasePart") then
				table.insert(result, child)
			end
		end
	end
	self.TemplateCache = result
	return result
end

local function pick(random: Random, values: { string }): string
	return values[random:NextInteger(1, #values)]
end

local function number(random: Random, minimumDigits: number, maximumDigits: number): string
	local digits = random:NextInteger(minimumDigits, maximumDigits)
	return tostring(random:NextInteger(if digits == 1 then 0 else 10 ^ (digits - 1), 10 ^ digits - 1))
end

function NPCPopulationService.NameTaken(self: any, candidate: string): boolean
	local lower = string.lower(candidate)
	for _, player in self.D.Players:GetPlayers() do
		if string.lower(player.Name) == lower then return true end
	end
	for _, bot in self.Bots do
		if string.lower(bot.Name) == lower then return true end
	end
	return false
end

function NPCPopulationService.Identity(self: any): (string, string)
	local random = self.Random
	for _ = 1, 40 do
		local adjective, noun = pick(random, ADJECTIVES), pick(random, NOUNS)
		local style = random:NextInteger(1, 10)
		local username, alias
		if style == 1 then
			username, alias = adjective .. noun .. (if random:NextNumber() < 0.42 then number(random, 1, 3) else ""), noun
		elseif style == 2 then
			username, alias = string.lower(noun) .. "_" .. string.lower(adjective) .. (if random:NextNumber() < 0.25 then number(random, 1, 2) else ""), adjective .. " " .. noun
		elseif style == 3 then
			local nameBit = pick(random, NAME_BITS)
			username, alias = nameBit .. number(random, 2, 4), string.upper(string.sub(nameBit, 1, 1)) .. string.sub(nameBit, 2)
		elseif style == 4 then
			username, alias = "its" .. noun .. (if random:NextNumber() < 0.5 then number(random, 1, 3) else ""), noun
		elseif style == 5 then
			username, alias = "ii" .. noun .. "ii" .. (if random:NextNumber() < 0.3 then number(random, 1, 2) else ""), noun
		elseif style == 6 then
			local invented = pick(random, SYLLABLES) .. pick(random, SYLLABLES) .. pick(random, ENDINGS)
			username, alias = invented .. (if random:NextNumber() < 0.45 then number(random, 1, 3) else ""), invented
		elseif style == 7 then
			username, alias = string.lower(adjective) .. string.lower(noun) .. number(random, 1, 2), adjective .. " " .. noun
		elseif style == 8 then
			username, alias = string.lower(noun) .. number(random, 3, 5), noun
		elseif style == 9 then
			local initial = string.char(random:NextInteger(65, 90))
			username, alias = initial .. noun .. number(random, 1, 3), initial .. " " .. noun
		else
			username, alias = "The" .. noun .. (if random:NextNumber() < 0.65 then number(random, 1, 3) else ""), "The " .. noun
		end
		username = string.sub(string.gsub(username, "[^%w_]", ""), 1, 20)
		if #username >= 3 and not self:NameTaken(username) then
			local displayRoll = random:NextNumber()
			local displayName = if displayRoll < 0.68 then username
				elseif displayRoll < 0.83 then alias
				elseif displayRoll < 0.95 then adjective .. " " .. noun
				else string.upper(alias)
			return username, string.sub(displayName, 1, 20)
		end
	end
	local fallback = "player" .. tostring(math.abs(self.NextId))
	return string.sub(fallback, 1, 20), "Player " .. number(random, 2, 4)
end

function NPCPopulationService.Avatar(self: any, template: Model): number
	local authored = template:GetAttribute("AvatarUserId")
	if type(authored) == "number" and authored > 0 then return math.floor(authored) end
	self.AvatarCycle += 1
	if self.AvatarCycle > #self.AvatarIds then
		self.AvatarIds = shuffledCopy(self.Random, AVATAR_USER_IDS)
		self.AvatarCycle = 1
	end
	return self.AvatarIds[self.AvatarCycle]
end

function NPCPopulationService.SpawnFrame(self: any): CFrame
	local preferred, spawns = self.PreferredSpawns or {}, self.Spawns or {}
	if #spawns == 0 then
		self:RefreshInterests()
		preferred, spawns = self.PreferredSpawns or {}, self.Spawns or {}
	end
	local choices = if #preferred > 0 then preferred else spawns
	if #choices > 0 then
		local spawn = choices[self.Random:NextInteger(1, #choices)]
		if spawn.Parent and spawn.Enabled then
			return spawn.CFrame * CFrame.new(self.Random:NextNumber(-2, 2), 3.5, self.Random:NextNumber(-2, 2))
		end
		self:RefreshInterests()
		return self:SpawnFrame()
	end
	local gameRoot = self.D.World:FindFirstChild("Game")
	if gameRoot and gameRoot:IsA("Model") then return gameRoot:GetPivot() * CFrame.new(0, 5, 0) end
	return CFrame.new(0, 5, 0)
end

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local PET_WEIGHTS = { 64, 25, 8, 2, 0.8, 0.2 }

local function progressTier(random: Random, chances: { number }): number
	local roll, total = random:NextNumber(), 0
	for index, chance in chances do
		total += chance
		if roll < total then return index - 1 end
	end
	return #chances - 1
end

local function weightedChoice(random: Random, choices: { any }): any?
	local total = 0
	for _, choice in choices do total += choice.Weight end
	if total <= 0 then return nil end
	local roll = random:NextNumber(0, total)
	for _, choice in choices do
		roll -= choice.Weight
		if roll <= 0 then return choice.Value end
	end
	return choices[#choices].Value
end

local function weightedPets(self: any, maximumRarity: number, count: number): { string }
	local choices = {}
	for id, item in self.D.Catalog.Items.Pets do
		local rank = RARITY_RANK[item.Rarity] or 1
		if
			item.Active == true
			and rank <= maximumRarity
			and (not self.D.AvailablePets or self.D.AvailablePets[id])
		then
			table.insert(choices, { Value = id, Weight = PET_WEIGHTS[rank] or 0.1 })
		end
	end
	local selected = {}
	for _ = 1, math.min(count, #choices) do
		local id = weightedChoice(self.Random, choices)
		if not id then break end
		table.insert(selected, id)
		for index, choice in choices do
			if choice.Value == id then table.remove(choices, index);break end
		end
	end
	return selected
end

local function chairForTier(self: any, tier: number): string?
	local order = self.D.Catalog.ChairShopOrder or {}
	if tier >= 4 then return table.find(order, "Void") and "Void" or order[#order] end
	local chance = ({ 0, 0.30, 0.58, 0.82 })[tier + 1] or 0
	if self.Random:NextNumber() >= chance then return nil end
	local maximumIndex = ({ 1, 5, 8, 9 })[tier + 1] or 1
	local choices = {}
	for index = 2, math.min(maximumIndex, #order) do
		-- Earlier, cheaper chairs dominate; each step toward the premium end becomes exponentially less common.
		table.insert(choices, { Value = order[index], Weight = 1 / (index - 1) ^ 1.65 })
	end
	return weightedChoice(self.Random, choices)
end

function NPCPopulationService.Profile(self: any, forcedTier: number?, forcedVIP: boolean?): any
	local random, catalog = self.Random, self.D.Catalog
	local tier = forcedTier or progressTier(random, self.Config.ProgressTierChances or { 0.63, 0.22, 0.09, 0.04, 0.02 })
	local vipChance = (self.Config.VIPTierChances or { 0, 0.01, 0.05, 0.18, 0.55 })[tier + 1] or 0
	local vip=if forcedVIP~=nil then forcedVIP else random:NextNumber()<vipChance
	local matchRanges={{0,8},{10,75},{70,280},{250,950},{850,3200}}
	local range=matchRanges[tier+1]
	local matches=random:NextInteger(range[1],range[2])
	local winRate=random:NextNumber(0.32+tier*0.045,0.52+tier*0.06)
	local wins=math.clamp(math.floor(matches*winRate+0.5),0,matches)
	local streak=if wins==0 or random:NextNumber()<(0.68-tier*0.08) then 0 else random:NextInteger(1,math.min(wins,3+tier*5))
	local highestStreak=if wins==0 then 0 else math.max(streak,random:NextInteger(math.min(wins,1+tier),math.min(wins,5+tier*12)))
	local titles = catalog.Order and catalog.Order.Titles or {}
	local petOwnedCount
	if tier == 0 then petOwnedCount = if random:NextNumber() < 0.08 then 1 else 0
	elseif tier == 1 then petOwnedCount = if random:NextNumber() < 0.62 then 0 else random:NextInteger(1, 2)
	elseif tier == 2 then petOwnedCount = random:NextInteger(1, 2)
	elseif tier == 3 then petOwnedCount = random:NextInteger(1, 3)
	else petOwnedCount = random:NextInteger(2, 4) end
	local maximumPetRarity = ({ 1, 2, 3, 5, 6 })[tier + 1]
	local ownedPets = weightedPets(self, maximumPetRarity, petOwnedCount)
	local chair = chairForTier(self, tier)
	local titleChance = ({ 0.08, 0.30, 0.62, 0.82, 0.94 })[tier + 1]
	local title
	if #titles > 0 and random:NextNumber() < titleChance then
		local maximumTitle = math.min(#titles, math.max(1, 1 + tier * 2))
		title = titles[random:NextInteger(1, maximumTitle)]
	end
	local equippedPets={}
	local equippedPetCap = ({ 1, 1, 2, 3, 4 })[tier + 1]
	for index=1,math.min(#ownedPets,equippedPetCap) do equippedPets[index]=ownedPets[index] end
	local equipped = { Pets = equippedPets, Chairs = chair, Titles = title }
	local owned = { Pets = {}, Chairs = {}, Titles = {} }
	for _, id in ownedPets do owned.Pets[id] = random:NextInteger(1,if tier>=3 then 3 else 1) end
	owned.Chairs.Classic = 1
	if chair then owned.Chairs[chair] = 1 end
	if title then owned.Titles[title] = 1 end
	local timePlayed=if matches==0 then random:NextInteger(30,8*60) else matches*random:NextInteger(5*60,14*60)+random:NextInteger(0,2*3600)
	local hatches=math.max(petOwnedCount,math.floor(matches*random:NextNumber(0.4,1.8))+petOwnedCount*random:NextInteger(1,8))
	local cashRanges={{0,350},{100,2500},{750,9000},{3000,35000},{12000,120000}}
	local cashRange=cashRanges[tier+1]
	local cash=if tier==0 and random:NextNumber()<0.35 then 0 else random:NextInteger(cashRange[1],cashRange[2])
	local totalEarned=math.max(cash,math.floor(matches*random:NextNumber(130,480)+hatches*random:NextNumber(20,90)))
	local levelConfig=self.D.LevelConfig or {BaseXP=100,StepXP=50,MaxLevel=100}
	local playerXP=math.floor(matches*25+wins*75+math.floor(timePlayed/30))
	local maximumXP=(levelConfig.MaxLevel-1)*levelConfig.BaseXP+levelConfig.StepXP*(levelConfig.MaxLevel-2)*(levelConfig.MaxLevel-1)/2
	local data = {
		VIP = vip,
		Streak = streak,
		Wins = wins,
		Matches = matches,
		HighestStreak = highestStreak,
		Cash = cash,
		TimePlayed = timePlayed,
		Hatches = hatches,
		TotalEarned = totalEarned,
		BestChainRound = if tier==0 then random:NextInteger(0,3) else random:NextInteger(tier*2,tier*8+5),
		BestTeamChainRound = if tier==0 then 0 else random:NextInteger(math.max(0,tier-1),tier*5),
		LoginStreak = if tier==0 then random:NextInteger(0,2) else random:NextInteger(1,4+tier*7),
		PlayerXP = math.min(maximumXP,playerXP),
		NPCProgressTier = tier,
		Equipped = equipped,
		Owned = owned,
		PetXP = {},
		PetAbilityProgress = {},
	}
	return { Owned = owned, Equipped = equipped, Data = data, Token = "NPC", HatchAt = math.huge }
end

function NPCPopulationService.ApplyAttributes(self: any, bot: any)
	local character, data = bot.Character, bot.Profile.Data
	character:SetAttribute("ScaleBotUserId", bot.UserId)
	character:SetAttribute("AvatarUserId", bot.AvatarUserId)
	character:SetAttribute("ScaleNPC", true)
	character:SetAttribute("VIP", data.VIP)
	character:SetAttribute("Streak", data.Streak)
	character:SetAttribute("Cash", data.Cash)
	for slot = 1, 8 do
		character:SetAttribute("Pet" .. slot, nil)
		character:SetAttribute("PetLevel" .. slot, nil)
		character:SetAttribute("PetFill" .. slot, nil)
	end
	local tier=data.NPCProgressTier or 1
	for slot, id in data.Equipped.Pets do
		character:SetAttribute("Pet" .. slot, id)
		character:SetAttribute("PetLevel" .. slot, self.Random:NextInteger(math.max(1,tier*3),math.min(100,6+tier*20)))
		character:SetAttribute("PetFill" .. slot, self.Random:NextNumber())
	end
end

function NPCPopulationService.ChangeCosmetics(self: any, bot: any)
	local data=bot.Profile.Data
	local rolled = self:Profile(data.NPCProgressTier,data.VIP)
	bot.Profile.Owned = rolled.Owned
	bot.Profile.Equipped = rolled.Equipped
	bot.Profile.Data.Owned = rolled.Data.Owned
	bot.Profile.Data.Equipped = rolled.Data.Equipped
	self:ApplyAttributes(bot)
	bot.NextCosmeticAt = self.D.Now() + self.Random:NextNumber(self.Config.CosmeticChangeMin or 75, self.Config.CosmeticChangeMax or 180)
end

function NPCPopulationService.ScheduleChat(self: any, now: number)
	local delay = self.Random:NextNumber(self.Config.ChatIntervalMin or 75, self.Config.ChatIntervalMax or 160)
	if self.Random:NextNumber() < (self.Config.ChatLongQuietChance or 0.24) then
		delay += self.Random:NextNumber(self.Config.ChatLongQuietMin or 120, self.Config.ChatLongQuietMax or 300)
	end
	self.NextChatAt = now + delay
end

function NPCPopulationService.PublishActivity(self: any, packet: any): boolean
	local now = self.D.Now()
	if not self.D.News or now < (self.NextChatAt or 0) then return false end
	self:ScheduleChat(now)
	self.LastChatKind = packet.Kind
	self.D.News(packet)
	return true
end

function NPCPopulationService.ChatActivity(self: any)
	local now = self.D.Now()
	-- A due activity slot can be silent. Schedule the next full interval now so an idle/empty server never retries
	-- every few seconds and later dumps a burst into chat.
	if self.Random:NextNumber() < (self.Config.ChatSkipChance or 0.35) then
		self:ScheduleChat(now)
		return
	end
	local choices = {}
	for _, bot in self.Bots do
		if bot.ManagedPopulation and not bot.Departing and bot.Character.Parent then table.insert(choices, bot) end
	end
	if #choices == 0 then
		self:ScheduleChat(now)
		return
	end
	local bot = choices[self.Random:NextInteger(1, #choices)]
	local data, catalog = bot.Profile.Data, self.D.Catalog
	local tier = math.clamp(math.floor(data.NPCProgressTier or 0), 0, 4)
	local petChance = if self.LastChatKind == "BotPet" then 0.28 elseif self.LastChatKind == "BotChair" then 0.78 else 0.55
	if self.Random:NextNumber() < petChance then
		local maximumPetRarity = ({ 1, 2, 3, 5, 6 })[tier + 1]
		local pets = weightedPets(self, maximumPetRarity, 1)
		if #pets == 0 then
			self:ScheduleChat(now)
			return
		end
		local id = pets[1]
		local item = catalog.Items.Pets[id]
		data.Owned.Pets[id] = (data.Owned.Pets[id] or 0) + 1
		local equippedCap = ({ 1, 1, 2, 3, 4 })[tier + 1]
		if #data.Equipped.Pets < equippedCap and not table.find(data.Equipped.Pets, id) then
			table.insert(data.Equipped.Pets, id)
		end
		self:ApplyAttributes(bot)
		self:PublishActivity({ Kind = "BotPet", Name = bot.DisplayName, Item = item.Name or id, Rarity = item.Rarity })
		return
	end
	local id = chairForTier(self, tier)
	if not id then
		self:ScheduleChat(now)
		return
	end
	local item = catalog.Items.Chairs[id]
	data.Owned.Chairs[id], data.Equipped.Chairs = 1, id
	self:PublishActivity({ Kind = "BotChair", Name = bot.DisplayName, Item = item.Name or id, Rarity = item.Rarity })
end

function NPCPopulationService.MatchFinished(self: any, bot: any, won: boolean)
	if not self:Owns(bot) then return end
	local data = bot.Profile.Data
	data.Matches = (data.Matches or 0) + 1
	if won then
		data.Wins = (data.Wins or 0) + 1
		data.Streak = (data.Streak or 0) + 1
		data.HighestStreak = math.max(data.HighestStreak or 0, data.Streak)
		self:ApplyAttributes(bot)
		self:PublishActivity({ Kind = "BotWin", Name = bot.DisplayName, Count = data.Streak })
	else
		data.Streak = 0
		self:ApplyAttributes(bot)
	end
end

local function animationSource(character: Model, wanted: string, fallback: string): Animation
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Animation") and string.lower(descendant.Name) == string.lower(wanted) then return descendant end
	end
	local animation = Instance.new("Animation")
	animation.Name, animation.AnimationId = "ScaleNPC" .. wanted, fallback
	return animation
end

function NPCPopulationService.Animate(self: any, bot: any)
	local authored = bot.Character:FindFirstChild("Animate")
	-- An authored server Script can animate itself. Default player Animate LocalScripts do not run for NPC Models,
	-- so those use standard R6 tracks driven by the Humanoid's real state. The service always owns the high-priority
	-- sit pose because some authored roaming scripts only supply idle/walk animation.
	local authoredRuns = authored and authored:IsA("Script") and not authored.Disabled
	local animator = bot.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator");animator.Parent = bot.Humanoid end
	local r15 = bot.Humanoid.RigType == Enum.HumanoidRigType.R15
	local okSit, sit = pcall(function() return animator:LoadAnimation(animationSource(bot.Character, "SitAnim", if r15 then "rbxassetid://2506281703" else "rbxassetid://178130996")) end)
	if not okSit then return end
	sit.Looped, sit.Priority = true, Enum.AnimationPriority.Action
	if authoredRuns then
		bot.AnimationTracks = { sit }
		bot.AnimationConnections = {
			bot.Humanoid.Seated:Connect(function(active)
				if active and not sit.IsPlaying then sit:Play(0.15)
				elseif not active and sit.IsPlaying then sit:Stop(0.15) end
			end),
		}
		return
	end
	local okWalk, walk = pcall(function() return animator:LoadAnimation(animationSource(bot.Character, "WalkAnim", if r15 then "rbxassetid://507777826" else "rbxassetid://180426354")) end)
	local okIdle, idle = pcall(function() return animator:LoadAnimation(animationSource(bot.Character, "Animation1", if r15 then "rbxassetid://507766666" else "rbxassetid://180435571")) end)
	if not okWalk or not okIdle then return end
	walk.Looped, idle.Looped, sit.Looped = true, true, true
	walk.Priority, idle.Priority, sit.Priority = Enum.AnimationPriority.Movement, Enum.AnimationPriority.Idle, Enum.AnimationPriority.Action
	idle:Play(0.2)
	bot.AnimationTracks = { walk, idle, sit }
	bot.AnimationConnections = {
		bot.Humanoid.Running:Connect(function(speed)
			if speed > 0.5 and not bot.Humanoid.Sit then
				if idle.IsPlaying then idle:Stop(0.18) end
				if not walk.IsPlaying then walk:Play(0.18) end
				walk:AdjustSpeed(math.clamp(speed / 12, 0.65, 1.45))
			elseif not bot.Humanoid.Sit then
				if walk.IsPlaying then walk:Stop(0.18) end
				if not idle.IsPlaying then idle:Play(0.18) end
			end
		end),
		bot.Humanoid.Seated:Connect(function(active)
			if active then
				if walk.IsPlaying then walk:Stop(0.15) end
				if idle.IsPlaying then idle:Stop(0.15) end
				if not sit.IsPlaying then sit:Play(0.15) end
			else
				if sit.IsPlaying then sit:Stop(0.15) end
				if not idle.IsPlaying then idle:Play(0.2) end
			end
		end),
	}
end

function NPCPopulationService.Create(self: any): any?
	local templates = self:Templates()
	if #templates == 0 then
		if not self.WarnedMissing then
			self.WarnedMissing = true
			self.D.Warn("Scale It Up: ServerStorage.Characters.NPC needs at least one Model with a Humanoid and HumanoidRootPart")
		end
		return nil
	end
	local template = templates[self.Random:NextInteger(1, #templates)]
	local character = template:Clone()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = modelPart(character)
	if not humanoid or not root then character:Destroy();return nil end
	self.NextId -= 1
	local username, displayName = self:Identity()
	character.Name = username
	character:SetAttribute("ScaleNPCSource", template.Name)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			-- NPCs collide for navigation but never need touch transmitters or server raycast selection.
			descendant.CanTouch, descendant.CanQuery = false, false
			pcall(function() descendant:SetNetworkOwner(nil) end)
		elseif descendant:IsA("BaseScript") and descendant.Name ~= "Animate" then
			-- This service exclusively owns movement. Preserve only the optional authored animation script.
			descendant.Disabled = true
		elseif PHYSICS_ACTUATORS[descendant.ClassName] then
			-- Imported character packs sometimes contain old BodyMovers or constraints that continuously pull the rig.
			descendant:Destroy()
		end
	end
	-- One touch-enabled root lets authored Water triggers recover NPCs without restoring touch transmitters on
	-- every limb and accessory.
	root.CanTouch = true
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	-- Imported rigs must start under Humanoid control, not in a physics-only display pose.
	humanoid.EvaluateStateMachine = true
	humanoid.PlatformStand, humanoid.Sit, humanoid.AutoRotate = false, false, true
	local cruiseSpeed = self.Random:NextNumber(self.Config.WalkSpeedMin or 9, self.Config.WalkSpeedMax or 15)
	humanoid.WalkSpeed = 0
	character:PivotTo(self:SpawnFrame())
	character.Parent = self.Root
	clearAssemblyMotion(character)
	if self.D.AttachBotTag then self.D.AttachBotTag(character) end
	pcall(function() root:SetNetworkOwner(nil) end)
	local bot = {
		IsBot = true,
		ManagedPopulation = true,
		UserId = self.NextId,
		AvatarUserId = self:Avatar(template),
		Name = username,
		DisplayName = displayName,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Profile = self:Profile(),
		State = "IDLE",
		MoveToken = 0,
		CruiseSpeed = cruiseSpeed,
		CurrentSpeed = 0,
		DesiredSpeed = 0,
		JoinedAt = self.D.Now(),
		DepartAt = self.D.Now() + self.Random:NextNumber(self.Config.LifetimeMin or 120, self.Config.LifetimeMax or 300),
		NextCosmeticAt = self.D.Now() + self.Random:NextNumber(self.Config.CosmeticChangeMin or 75, self.Config.CosmeticChangeMax or 180),
		NextDecision = self.D.Now() + self.Random:NextNumber(1, 4),
		SafeOrigin = root.Position,
		Personality = {
			Pause = self.Random:NextNumber(0.55, 1.65),
			Detour = self.Random:NextNumber(0.65, 1.45),
			Social = self.Random:NextNumber(),
			Restless = self.Random:NextNumber(),
		},
	}
	table.insert(self.Bots, bot)
	self.BotSet[bot] = true
	self.D.CharacterBots[character] = bot
	self.D.Profiles[bot] = bot.Profile
	self:ApplyAttributes(bot)
	self:Animate(bot)
	self.D.CollectionService:AddTag(character, "ScaleBot")
	self.D.CollectionService:AddTag(character, "ScalePopulationNPC")
	return bot
end

function NPCPopulationService.Owns(self: any, bot: any): boolean
	return self.BotSet[bot] == true
end

function NPCPopulationService.UpdateSpeed(self: any, bot: any, dt: number)
	local current, target = bot.CurrentSpeed or 0, bot.DesiredSpeed or 0
	local rate = if target > current then self.Config.WalkAcceleration or 13 else self.Config.WalkDeceleration or 18
	local change = rate * math.min(dt, 0.1)
	if math.abs(target - current) <= change then current = target
	else current += (if target > current then change else -change) end
	bot.CurrentSpeed = math.max(0, current)
	if bot.Humanoid and bot.Humanoid.Parent and not bot.Humanoid.SeatPart then
		bot.Humanoid.WalkSpeed = bot.CurrentSpeed
	end
end

function NPCPopulationService.ClearReservation(self: any, bot: any)
	if bot.ReservedSeat and self.Reservations[bot.ReservedSeat] == bot then self.Reservations[bot.ReservedSeat] = nil end
	bot.ReservedSeat, bot.ReservedRecord = nil, nil
end

function NPCPopulationService.CancelMove(self: any, bot: any)
	bot.MoveToken += 1
	bot.DesiredSpeed = 0
	stopWalking(bot)
	if bot.Humanoid and bot.Humanoid.Parent then bot.Humanoid.AutoRotate = true end
	self:ClearReservation(bot)
end

function NPCPopulationService.RecoverWater(self: any, bot: any, destination: Vector3)
	if not self:Owns(bot) then return end
	self:CancelMove(bot)
	bot.CurrentSpeed, bot.DesiredSpeed, bot.Humanoid.WalkSpeed = 0, 0, 0
	bot.DriftStartedAt, bot.LastSeat, bot.LeaveAt = nil, nil, nil
	bot.Departing, bot.SafeOrigin, bot.State = false, destination, "IDLE"
	bot.WaterRecoveryUntil = self.D.Now() + self.Config.WaterRecoveryPauseSeconds
	bot.NextDecision = bot.WaterRecoveryUntil
end

function NPCPopulationService.Remove(self: any, bot: any)
	local index = table.find(self.Bots, bot)
	if not index then return end
	self:CancelMove(bot)
	for _, connection in bot.AnimationConnections or {} do connection:Disconnect() end
	for _, track in bot.AnimationTracks or {} do track:Stop(0) end
	if self.D.RemoveVisual then self.D.RemoveVisual(bot) end
	self.D.Profiles[bot] = nil
	if self.D.CharacterBots[bot.Character] == bot then self.D.CharacterBots[bot.Character] = nil end
	self.BotSet[bot] = nil
	table.remove(self.Bots, index)
	if bot.Character and bot.Character.Parent then bot.Character:Destroy() end
end

function NPCPopulationService.Release(self: any, bot: any)
	if not self:Owns(bot) then return end
	local humanoid = bot.Humanoid
	local seat = self.D.Bindings:SeatAttachment(bot.Character) or (humanoid and humanoid.SeatPart) or bot.ReservedSeat or bot.LastSeat
	bot.LastSeat = nil
	local outward = bot.Root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if seat and seat:IsA("BasePart") then
		local record = self.D.Owner(bot)
		if not record then
			for _, candidate in self.D.Records() do
				if seat:IsDescendantOf(candidate.Key) then record = candidate;break end
			end
		end
		if record then
			outward = Vector3.new(seat.Position.X - record.Key:GetPivot().Position.X, 0, seat.Position.Z - record.Key:GetPivot().Position.Z)
		end
	end
	if outward.Magnitude < 0.05 then outward = Vector3.new(0, 0, -1) else outward = outward.Unit end
	local exitPoint = if seat and seat:IsA("BasePart") then seat.Position + outward * 5 else bot.Root.Position + outward * 5
	self:CancelMove(bot)
	local releaseToken = bot.MoveToken
	if humanoid and humanoid.Parent then
		self.D.Bindings:DetachSeat(bot.Character, humanoid)
		humanoid.AutoRotate = true
	end
	if seat and seat:IsA("BasePart") then
		-- Move clear of the seat's touch area immediately; the remaining distance is walked naturally below.
		bot.Character:PivotTo(bot.Character:GetPivot() + outward * math.max(1.8, seat.Size.Z * 0.5 + 0.8))
		clearAssemblyMotion(bot.Character)
	end
	bot.DesiredSpeed = 0
	bot.CurrentSpeed = 0
	bot.State = "LEAVING_SEAT"
	bot.LeaveAt = nil
	bot.NextDecision = nil
	task.defer(function()
		if not self:Owns(bot) or bot.MoveToken ~= releaseToken or self.D.IsMatched(bot) then return end
		if humanoid and humanoid.Parent then self.D.Bindings:DetachSeat(bot.Character, humanoid) end
		self:Walk(bot, self:GroundPoint(exitPoint, bot), function()
			if self:Owns(bot) and not self.D.IsMatched(bot) then self:Wander(bot) end
		end)
	end)
end

function NPCPopulationService.BeginDeparture(self: any, bot: any)
	if not self:Owns(bot) or bot.Departing or self.D.IsMatched(bot) or bot.Humanoid.SeatPart then return end
	bot.Departing = true
	local destination = self:SpawnFrame().Position
	self:Walk(bot, destination, function()
		if self:Owns(bot) then self:Remove(bot) end
	end)
end

function NPCPopulationService.GroundPoint(self: any, point: Vector3, bot: any): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Root, bot.Character }
	params.IgnoreWater = false
	local function dry(hit: RaycastResult?): boolean
		if not hit or hit.Material == Enum.Material.Water then return false end
		local map = self.D.World:FindFirstChild("Map")
		return not (hit.Instance.Name == "Water" and map and hit.Instance:IsDescendantOf(map))
	end
	local hit = self.D.World:Raycast(point + Vector3.new(0, 18, 0), Vector3.new(0, -45, 0), params)
	if dry(hit) and hit then return hit.Position + Vector3.new(0, 0.1, 0) end
	-- Never direct a Humanoid toward empty space. A missed random destination becomes a harmless stay-put point.
	local current = bot.Root.Position
	local currentHit = self.D.World:Raycast(current + Vector3.new(0, 18, 0), Vector3.new(0, -45, 0), params)
	return if dry(currentHit) and currentHit then currentHit.Position + Vector3.new(0, 0.1, 0) else current
end

function NPCPopulationService.RecoverRunaway(self: any, bot: any): boolean
	if self.D.IsMatched(bot) or bot.Humanoid.SeatPart or bot.State == "SEATING" or self.D.Bindings:SeatAttachment(bot.Character) then
		bot.DriftStartedAt = nil
		return false
	end
	local position, velocity = bot.Root.Position, bot.Root.AssemblyLinearVelocity
	local origin = bot.SafeOrigin or self:SpawnFrame().Position
	local maximumSpeed = self.Config.RunawaySpeed or 55
	local maximumFall = self.Config.RunawayFallDistance or 40
	local maximumRadius = self.Config.RunawayRadius or 350
	local offset = position - origin
	local runaway = not finiteVector(position)
		or not finiteVector(velocity)
		or velocity.Magnitude > maximumSpeed
		or position.Y < origin.Y - maximumFall
		or Vector3.new(offset.X, 0, offset.Z).Magnitude > maximumRadius
	local humanoid = bot.Humanoid
	local state = humanoid:GetState()
	local disabled = not humanoid.EvaluateStateMachine or humanoid.PlatformStand
		or state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.PlatformStanding
		or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local drifting = humanoid.FloorMaterial ~= Enum.Material.Air
		and horizontalSpeed >= (self.Config.DriftSpeed or 2)
		and (humanoid.MoveDirection.Magnitude < 0.05 or (bot.CurrentSpeed or 0) < 0.1)
	local now = self.D.Now()
	if disabled or drifting then bot.DriftStartedAt = bot.DriftStartedAt or now
	else bot.DriftStartedAt = nil end
	-- Ignore brief bumps, deceleration and normal jumps. Persistent low-speed sliding otherwise evades RunawaySpeed.
	local stalled = bot.DriftStartedAt and now - bot.DriftStartedAt >= (self.Config.DriftSeconds or 2)
	if not runaway and not stalled then return false end

	self:CancelMove(bot)
	bot.Character:SetAttribute("ScaleNPCRecoveryReason", if runaway then "Runaway" elseif disabled then "HumanoidDisabled" else "UncommandedDrift")
	bot.Humanoid.EvaluateStateMachine = true
	bot.Humanoid.Sit = false
	bot.Humanoid.PlatformStand = false
	bot.Humanoid.AutoRotate = true
	bot.Character:PivotTo(self:SpawnFrame())
	stopWalking(bot)
	clearAssemblyMotion(bot.Character)
	pcall(function() bot.Root:SetNetworkOwner(nil) end)
	bot.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	bot.DriftStartedAt = nil
	bot.SafeOrigin = bot.Root.Position
	bot.Departing = false
	bot.LastSeat = nil
	bot.LeaveAt = nil
	bot.CurrentSpeed = 0
	bot.DesiredSpeed = 0
	bot.Humanoid.WalkSpeed = 0
	bot.State = "IDLE"
	bot.NextDecision = self.D.Now() + self.Random:NextNumber(0.8, 2)
	return true
end

-- Break longer walks into irregular destinations before pathfinding each leg. NPCs therefore cross the same lobby
-- in different arcs instead of sharing one attraction-to-attraction line.
function NPCPopulationService.Route(self: any, bot: any, destination: Vector3): { Vector3 }
	local start = bot.Root.Position
	local flatDelta = Vector3.new(destination.X - start.X, 0, destination.Z - start.Z)
	local distance = flatDelta.Magnitude
	if distance < 7 then return { self:GroundPoint(destination, bot) } end
	local direction = flatDelta.Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local bends = if distance > 45 then self.Random:NextInteger(2, 4)
		elseif distance > 20 then self.Random:NextInteger(1, 3)
		else self.Random:NextInteger(0, 2)
	if self.Random:NextNumber() > (self.Config.RouteBendChance or 0.72) then bends = 0 end
	local route = {}
	for index = 1, bends do
		local alpha = index / (bends + 1)
		local width = math.min(12, distance * 0.22) * bot.Personality.Detour
		local bend = start:Lerp(destination, alpha) + side * self.Random:NextNumber(-width, width)
		table.insert(route, self:GroundPoint(bend, bot))
	end
	table.insert(route, self:GroundPoint(destination, bot))
	return route
end

function NPCPopulationService.LookAround(self: any, bot: any, token: number)
	if not currentWalk(self, bot, token) then return end
	bot.State = "PAUSING"
	bot.DesiredSpeed = 0
	stopWalking(bot)
	task.wait(self.Random:NextNumber(0.12, 0.28))
	if not currentWalk(self, bot, token) then return end
	bot.Humanoid.AutoRotate = false
	for _ = 1, self.Random:NextInteger(1, 2) do
		if not currentWalk(self, bot, token) then return end
		local angle = self.Random:NextNumber(-1.2, 1.2)
		local facing = CFrame.Angles(0, angle, 0):VectorToWorldSpace(bot.Root.CFrame.LookVector)
		local flatFacing = Vector3.new(facing.X, 0, facing.Z)
		if flatFacing.Magnitude > 0.01 then
			local start = bot.Root.CFrame.Rotation
			local goal = CFrame.lookAt(Vector3.zero, flatFacing)
			local steps = self.Random:NextInteger(5, 9)
			for step = 1, steps do
				if not currentWalk(self, bot, token) then return end
				local alpha = step / steps
				alpha = alpha * alpha * (3 - 2 * alpha)
				-- Only turn: don't repeatedly pin a falling or bumped rig to an old position.
				bot.Root.CFrame = CFrame.new(bot.Root.Position) * start:Lerp(goal, alpha)
				task.wait(0.03)
			end
		end
		task.wait(self.Random:NextNumber(0.2, 0.75) * bot.Personality.Pause)
	end
	if currentWalk(self, bot, token) then bot.Humanoid.AutoRotate = true end
end

function NPCPopulationService.Walk(self: any, bot: any, destination: Vector3, arrived: (() -> ())?)
	if not self:Owns(bot) or not bot.Root.Parent or not bot.Humanoid.Parent then return end
	bot.MoveToken += 1
	local token = bot.MoveToken
	stopWalking(bot)
	local route = self:Route(bot, destination)
	bot.State = "WALKING"
	bot.Humanoid.AutoRotate = true
	bot.DesiredSpeed = bot.CruiseSpeed * self.Random:NextNumber(0.92, 1.05)
	task.spawn(function()
		local completed = true
		for routeIndex, routePoint in route do
			local legComplete = false
			for _ = 1, self.Config.PathRetries or 3 do
				if not currentWalk(self, bot, token) then return end
				local points: { any } = {}
				local path: any = nil
				local ok = pcall(function()
					path = self.D.Pathfinding:CreatePath({
						AgentRadius = 2,
						AgentHeight = 5,
						AgentCanJump = true,
						Costs = { Water = math.huge },
						WaypointSpacing = self.Random:NextNumber(3.5, 6),
					})
					path:ComputeAsync(bot.Root.Position, routePoint)
				end)
				if not currentWalk(self, bot, token) then return end
				if ok and path and path.Status == Enum.PathStatus.Success then
					points = path:GetWaypoints()
				else
					-- A failed route is not permission to walk straight through water or off the island.
					break
				end
				local blocked, waypointIndex = false, 0
				local blockedConnection = if path then path.Blocked:Connect(function(index)
					if currentWalk(self, bot, token) and index >= waypointIndex then
						blocked = true
						-- Interrupt MoveToFinished immediately; the next bounded attempt computes around the new obstruction.
						stopWalking(bot)
					end
				end) else nil
				legComplete = true
				for pointIndex, waypoint in points do
					waypointIndex = pointIndex
					if not currentWalk(self, bot, token) then
						if blockedConnection then blockedConnection:Disconnect() end
						return
					end
					local target = waypoint.Position
					-- Tiny lateral misses keep several NPCs from tracing the exact same path without pushing them off navmesh.
					if pointIndex < #points and waypoint.Action ~= Enum.PathWaypointAction.Jump then
						local delta = Vector3.new(target.X - bot.Root.Position.X, 0, target.Z - bot.Root.Position.Z)
						if delta.Magnitude > 1 then
							local side = Vector3.new(-delta.Unit.Z, 0, delta.Unit.X)
							target += side * self.Random:NextNumber(-(self.Config.WaypointVariation or 0.45), self.Config.WaypointVariation or 0.45)
						end
					end
					local finalPoint = routeIndex == #route and pointIndex == #points
					local pauseAfter = pointIndex > 1
						and not finalPoint
						and self.Random:NextNumber() < (self.Config.WaypointPauseChance or 0.13) * bot.Personality.Pause
					bot.DesiredSpeed = bot.CruiseSpeed * (if finalPoint then 0.62 elseif pauseAfter then 0.7 else self.Random:NextNumber(0.92, 1.05))
					if waypoint.Action == Enum.PathWaypointAction.Jump then
						bot.DesiredSpeed = bot.CruiseSpeed * 0.72
						task.wait(self.Random:NextNumber(0.04, 0.11))
						if not currentWalk(self, bot, token) then
							if blockedConnection then blockedConnection:Disconnect() end
							return
						end
						bot.Humanoid.Jump = true
					end
					if blocked then legComplete = false;break end
					local reached: boolean? = nil
					local moveConnection = bot.Humanoid.MoveToFinished:Connect(function(success) reached = success end)
					bot.Humanoid:MoveTo(target)
					local expires = self.D.Now() + (self.Config.WaypointTimeoutSeconds or 8)
					while reached == nil and not blocked and currentWalk(self, bot, token) and self.D.Now() < expires do
						task.wait(0.1)
					end
					moveConnection:Disconnect()
					if not currentWalk(self, bot, token) then
						if blockedConnection then blockedConnection:Disconnect() end
						return
					end
					if blocked or not reached then legComplete = false;break end
					if pauseAfter then
						self:LookAround(bot, token)
						if not currentWalk(self, bot, token) then
							if blockedConnection then blockedConnection:Disconnect() end
							return
						end
						bot.State = "WALKING"
						bot.DesiredSpeed = bot.CruiseSpeed * self.Random:NextNumber(0.9, 1.04)
					end
				end
				if blockedConnection then blockedConnection:Disconnect() end
				if legComplete then break end
				bot.DesiredSpeed = 0
				stopWalking(bot)
				task.wait(self.Random:NextNumber(0.08, 0.22))
				if not currentWalk(self, bot, token) then return end
				bot.DesiredSpeed = bot.CruiseSpeed * self.Random:NextNumber(0.88, 1.02)
			end
			if not legComplete then completed = false;break end
			if routeIndex < #route and self.Random:NextNumber() < 0.35 then task.wait(self.Random:NextNumber(0.1, 0.45)) end
		end
		if not currentWalk(self, bot, token) then return end
		bot.DesiredSpeed = 0
		stopWalking(bot)
		if completed and arrived then arrived() end
		if not completed and bot.Departing then self:Remove(bot);return end
		if token == bot.MoveToken and bot.State == "WALKING" then
			if not completed then self:ClearReservation(bot) end
			bot.State = "IDLE"
			bot.NextDecision = self.D.Now() + self.Random:NextNumber(self.Config.WanderWaitMin or 0.4, self.Config.WanderWaitMax or 3.5)
		end
	end)
end

function NPCPopulationService.TableBoundCount(self: any): number
	local count = 0
	for _, other in self.Bots do
		if other.ManagedPopulation and (other.Humanoid.SeatPart or other.ReservedSeat or other.State == "TO_SEAT") then
			count += 1
		end
	end
	return count
end

function NPCPopulationService.CanSeatPopulation(self: any, bot: any, record: any?): boolean
	if self.D.Now() < (bot.WaterRecoveryUntil or 0) then return false end
	if not bot.ManagedPopulation then return true end
	if record and select(1, self:SeatCounts(record)) > 0 then return true end
	local managed = 0
	for _, other in self.Bots do if other.ManagedPopulation then managed += 1 end end
	local minimumWalkers = math.clamp(self.Config.MinimumWalkers or 2, 0, managed)
	return managed - self:TableBoundCount() > minimumWalkers
end

function NPCPopulationService.CanCompleteTable(self: any, record: any, humans: number, bots: number, reserved: number): boolean
	local now = self.D.Now()
	if humans > 0 then
		self.BotTablePlans[record] = nil
		local ids = {}
		for _, occupant in self.D.Bindings:Occupants(record) do
			if not self.D.IsBot(occupant) then table.insert(ids, tostring(occupant.UserId)) end
		end
		table.sort(ids)
		local key = table.concat(ids, ",")
		local plan = self.HumanTablePlans[record]
		if not plan or plan.Key ~= key or now >= plan.ExpiresAt then
			plan = {
				Key = key,
				-- Multi-seat tables need several arrivals to start. Always fill those after a natural delay;
				-- two-seat tables retain the existing occasional no-show behavior.
				Enabled = record.Capacity >= 3
					or self.Random:NextNumber() < (self.Config.HumanTableJoinChance or 0.95),
				At = now + self.Random:NextNumber(self.Config.HumanTableJoinDelayMin or 1.5, self.Config.HumanTableJoinDelayMax or 6),
				ExpiresAt = now + 60,
			}
			self.HumanTablePlans[record] = plan
		end
		return plan.Enabled and now >= plan.At
	end
	self.HumanTablePlans[record] = nil
	if bots + reserved == 0 then return false end
	local plan = self.BotTablePlans[record]
	if not plan or now >= plan.ExpiresAt or (not plan.Enabled and now >= plan.RetryAt) then
		local enabled = self.Random:NextNumber() < (self.Config.BotOnlyMatchChance or 0.75)
		plan = {
			Enabled = enabled,
			At = now + self.Random:NextNumber(self.Config.BotOnlyMatchDelayMin or 3, self.Config.BotOnlyMatchDelayMax or 12),
			RetryAt = now + self.Random:NextNumber(30, 55),
			ExpiresAt = now + 75,
		}
		self.BotTablePlans[record] = plan
	end
	return plan.Enabled and now >= plan.At
end

function NPCPopulationService.SeatCounts(self: any, record: any): (number, number, number)
	local humans, bots, reserved = 0, 0, 0
	for _, occupant in self.D.Bindings:Occupants(record) do
		if self.D.IsBot(occupant) then bots += 1 else humans += 1 end
	end
	local seats = self.D.Bindings:Seats(record) or {}
	for _, seat in seats do if self.Reservations[seat] then reserved += 1 end end
	return humans, bots, reserved
end

function NPCPopulationService.ChooseSeat(self: any, requireHuman: boolean?): (any?, Seat?)
	local best, bestSeat, bestScore = nil, nil, -math.huge
	for _, record in self.D.Records() do
		if record.Removed or record.Match or record.State == "RESETTING" or record.Capacity > 4 then continue end
		local seats = self.D.Bindings:Seats(record)
		if not seats then continue end
		local humans, bots, reserved = self:SeatCounts(record)
		if requireHuman and humans <= 0 then continue end
		local completing = self:CanCompleteTable(record, humans, bots, reserved)
		-- A bot-only table usually waits with an open seat, but some naturally commit to a complete fake match.
		-- A human waiting alone is guaranteed a response and then fills every remaining seat.
		local allowed = if completing then record.Capacity - humans else (if humans > 0 then bots + reserved else record.Capacity - 1)
		if bots + reserved >= allowed then continue end
		for _, seat in seats do
			if not seat.Occupant and not self.Reservations[seat] then
				local score = humans * 100 + (if completing then 45 else 0) + bots * 6 + self.Random:NextNumber()
				if score > bestScore then best, bestSeat, bestScore = record, seat, score end
			end
		end
	end
	return best, bestSeat
end

-- Human seats take priority over ambient wandering. Reserve each open seat immediately so exactly one NPC heads to
-- it, including every remaining seat at three- and four-player tables, without waiting for a normal decision timer.
function NPCPopulationService.DispatchHumanTable(self: any, now: number)
	if now < (self.NextHumanDispatchAt or 0) then return end
	local record, seat = self:ChooseSeat(true)
	if not record or not seat then
		-- Empty-table ambience must not make this search run on every population heartbeat.
		self.NextHumanDispatchAt = now + 0.1
		return
	end
	local selected, selectedDistanceSquared = nil, math.huge
	for _, bot in self.Bots do
		local canReroute = false
		if bot.State == "TO_SEAT" and bot.ReservedRecord then
			canReroute = select(1, self:SeatCounts(bot.ReservedRecord)) == 0
		end
		if
			bot.ManagedPopulation
			and not bot.Departing
			and not bot.Humanoid.SeatPart
			and not self.D.IsMatched(bot)
			and ((not bot.ReservedSeat and (bot.State == "IDLE" or bot.State == "WALKING")) or canReroute)
		then
			local offset = bot.Root.Position - seat.Position
			local distanceSquared = offset:Dot(offset)
			if distanceSquared < selectedDistanceSquared then
				selected, selectedDistanceSquared = bot, distanceSquared
			end
		end
	end
	if selected then
		self.NextHumanDispatchAt = now + 0.05
		self:GoSit(selected, record, seat)
		return
	end
	-- If every ambient NPC is merely waiting at an empty table, free the nearest eligible one. The following
	-- heartbeat dispatches it after Roblox releases its SeatWeld; active matches are never interrupted.
	for _, bot in self.Bots do
		if bot.ManagedPopulation and not bot.Departing and bot.Humanoid.SeatPart and not self.D.IsMatched(bot) then
			local owner = self.D.Owner(bot)
			if owner and select(1, self:SeatCounts(owner)) == 0 then
				self.NextHumanDispatchAt = now + 0.25
				self:Release(bot)
				return
			end
		end
	end
end

function NPCPopulationService.Seat(self: any, bot: any, record: any, seat: Seat)
	if not self:Owns(bot) or not seat:IsDescendantOf(self.D.World) or (seat.Occupant and seat.Occupant ~= bot.Humanoid) then
		self:ClearReservation(bot)
		return
	end
	bot.MoveToken += 1
	local token = bot.MoveToken
	bot.State = "SEATING"
	bot.DesiredSpeed = 0
	stopWalking(bot)
	bot.Humanoid.AutoRotate = true
	seat.Disabled = false
	-- Preserve a live occupant's weld even before SeatPart/Occupant have caught up.
	local staleWeld = seat:FindFirstChild("SeatWeld")
	if not seat.Occupant and staleWeld and staleWeld:IsA("Weld") then
		local weldedCharacter = staleWeld.Part1 and staleWeld.Part1:FindFirstAncestorOfClass("Model")
		local weldedHumanoid = weldedCharacter and weldedCharacter:FindFirstChildOfClass("Humanoid")
		if weldedHumanoid and weldedHumanoid ~= bot.Humanoid and weldedHumanoid.Health > 0 then
			self:ClearReservation(bot)
			bot.State, bot.NextDecision = "IDLE", self.D.Now()
			return
		end
		if weldedHumanoid ~= bot.Humanoid then staleWeld:Destroy() end
	end
	-- Let Roblox position the rig and create the normal SeatWeld. Never pivot a potentially welded character.
	if not self.D.Bindings:SeatAttachment(bot.Character) then seat:Sit(bot.Humanoid) end
	task.spawn(function()
		for attempt = 1, 4 do
			task.wait(if attempt == 1 then 0.12 else 0.18)
			if token ~= bot.MoveToken or not self:Owns(bot) or not bot.Humanoid.Parent or not seat:IsDescendantOf(self.D.World) then return end
			if seat.Occupant == bot.Humanoid and bot.Humanoid.SeatPart == seat then
				self:ClearReservation(bot)
				bot.LastSeat = seat
				bot.State, bot.DesiredSpeed, bot.CurrentSpeed = "SEATED", 0, 0
				bot.Humanoid.WalkSpeed = 0
				bot.LeaveAt = self.D.Now() + self.Random:NextNumber(self.Config.SeatWaitMin or 40, self.Config.SeatWaitMax or 90)
				return
			end
			if seat.Occupant and seat.Occupant ~= bot.Humanoid then break end
			-- Give every attempt a verification window, including the last one. An existing weld must settle untouched.
			if attempt < 4 and not seat:FindFirstChild("SeatWeld") and not self.D.Bindings:SeatAttachment(bot.Character) then
				seat:Sit(bot.Humanoid)
			end
		end
		if token ~= bot.MoveToken then return end
		-- Failed seating must move away immediately instead of leaving the NPC frozen on the chair.
		self:Release(bot)
	end)
end

function NPCPopulationService.GoSit(self: any, bot: any, record: any, seat: Seat)
	if not self:CanSeatPopulation(bot, record) then self:Wander(bot);return end
	self:ClearReservation(bot)
	self.Reservations[seat], bot.ReservedSeat, bot.ReservedRecord = bot, seat, record
	bot.State = "TO_SEAT"
	local center = record.Key:GetPivot().Position
	local outward = Vector3.new(seat.Position.X - center.X, 0, seat.Position.Z - center.Z)
	if outward.Magnitude < 0.1 then outward = seat.CFrame.LookVector else outward = outward.Unit end
	local approach = seat.Position + outward * math.max(2.5, seat.Size.Z + 0.8)
	self:Walk(bot, approach, function()
		if not self:Owns(bot) or self.Reservations[seat] ~= bot then return end
		if record.Removed or record.Match or seat.Occupant or not seat:IsDescendantOf(self.D.World) then
			self:ClearReservation(bot)
			bot.State, bot.NextDecision = "IDLE", self.D.Now() + 2
			return
		end
		self:Seat(bot, record, seat)
	end)
end

function NPCPopulationService.RefreshInterests(self: any)
	local interests, preferred, spawns = {}, {}, {}
	local gameRoot = self.D.World:FindFirstChild("Game")
	if gameRoot then
		local triggers = gameRoot:FindFirstChild("Triggers")
		local interactables = gameRoot:FindFirstChild("Interactables")
		addParts((triggers and triggers:FindFirstChild("LuckyBlocksTrigger")) or gameRoot:FindFirstChild("LuckyBlocksTrigger"), interests)
		local eggs = (interactables and interactables:FindFirstChild("Eggs")) or gameRoot:FindFirstChild("Eggs")
		if eggs then
			for _, model in eggs:GetChildren() do
				local body = model:FindFirstChild("Body")
				if body and body:IsA("BasePart") then table.insert(interests, body) end
			end
		end
		local afk = (triggers and triggers:FindFirstChild("AFK")) or gameRoot:FindFirstChild("AFK")
		if afk then addParts(afk, interests) end
		local chairs = (interactables and interactables:FindFirstChild("Chairs")) or gameRoot:FindFirstChild("Chairs")
		if chairs then
			chairs = chairs:FindFirstChild("Chairs") or chairs
			for _, model in chairs:GetChildren() do
				local part = modelPart(model)
				if part then table.insert(interests, part) end
			end
		end
	end
	for _, descendant in self.D.World:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			local insideArena = descendant:FindFirstAncestor("ScaleArenas") or descendant:FindFirstAncestor("ObjectArena")
			if not insideArena then
				table.insert(interests, descendant)
				table.insert(spawns, descendant)
				local lower = string.lower(descendant.Name)
				if lower == "spawnlocation" or string.find(lower, "lobby", 1, true) or lower == "spawn" then
					table.insert(preferred, descendant)
				end
			end
		end
	end
	self.Interests, self.PreferredSpawns, self.Spawns = interests, preferred, spawns
end

function NPCPopulationService.Wander(self: any, bot: any)
	if self.D.Now() >= self.NextInterestRefresh then
		self.NextInterestRefresh = self.D.Now() + 10
		self:RefreshInterests()
	end
	local roll = self.Random:NextNumber()
	local destination = nil
	-- Some NPCs take short unscripted strolls from wherever they are instead of hopping between named landmarks.
	if roll < (self.Config.LocalStrollChance or 0.34) then
		local radius = self.Random:NextNumber(7, 28) * (0.7 + bot.Personality.Restless * 0.6)
		local angle = self.Random:NextNumber(0, math.pi * 2)
		destination = bot.Root.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	elseif roll < (self.Config.LocalStrollChance or 0.34) + (self.Config.SocialWalkChance or 0.22) * (0.55 + bot.Personality.Social) then
		-- Social NPCs drift near a real player or another roaming NPC, but stop several studs away.
		local anchors = {}
		for _, player in self.D.Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then table.insert(anchors, root) end
		end
		for _, other in self.Bots do
			if other ~= bot and other.Root.Parent and not other.Humanoid.SeatPart then table.insert(anchors, other.Root) end
		end
		if #anchors > 0 then
			local anchor = anchors[self.Random:NextInteger(1, #anchors)]
			local angle, radius = self.Random:NextNumber(0, math.pi * 2), self.Random:NextNumber(5, 10)
			destination = anchor.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end
	end
	if not destination and #self.Interests > 0 then
		local interest = self.Interests[self.Random:NextInteger(1, #self.Interests)]
		local angle, radius = self.Random:NextNumber(0, math.pi * 2), self.Random:NextNumber(2, 10)
		destination = interest.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	if not destination then bot.NextDecision = self.D.Now() + self.Random:NextNumber(1, 3);return end
	self:Walk(bot, destination, function()
		local token = bot.MoveToken
		if self.Random:NextNumber() < 0.62 then self:LookAround(bot, token) end
		if token == bot.MoveToken then
			bot.State = "IDLE"
			bot.NextDecision = self.D.Now() + self.Random:NextNumber(self.Config.WanderWaitMin or 0.4, self.Config.WanderWaitMax or 3.5) * bot.Personality.Pause
		end
	end)
end

function NPCPopulationService.Target(self: any): number
	local real = #self.D.Players:GetPlayers()
	local target = math.clamp(
		(self.PopulationTarget or 12) - real,
		self.Config.MinimumBots or 0,
		self.Config.MaximumBots or 14
	)
	-- Keep enough population to fill every waiting human table even when the rest of the NPCs are already in matches.
	local matched, humanTableDemand = 0, 0
	for _, bot in self.Bots do
		if bot.ManagedPopulation and self.D.IsMatched(bot) then matched += 1 end
	end
	for _, record in self.D.Records() do
		if not record.Removed and not record.Match and record.State ~= "RESETTING" and record.Capacity <= 4 then
			local humans = select(1, self:SeatCounts(record))
			if humans > 0 and humans < record.Capacity then
				humanTableDemand += record.Capacity - humans
			end
		end
	end
	target = math.max(target, matched + humanTableDemand)
	return math.clamp(target, self.Config.MinimumBots or 0, self.Config.MaximumBots or 14)
end

function NPCPopulationService.Reconcile(self: any)
	local target = self:Target()
	local managed = 0
	for _, bot in self.Bots do if bot.ManagedPopulation then managed += 1 end end
	self.D.World:SetAttribute("NPCCount", #self.Bots)
	self.D.World:SetAttribute("DisplayedPopulation", #self.D.Players:GetPlayers() + #self.Bots)
	if managed < target then
		self:Create()
	elseif managed > target then
		local waiting
		for index = #self.Bots, 1, -1 do
			local bot = self.Bots[index]
			if bot.ManagedPopulation and not self.D.IsMatched(bot) and not bot.Humanoid.SeatPart and bot.State ~= "TO_SEAT" then
				self:BeginDeparture(bot)
				return
			elseif bot.ManagedPopulation and not self.D.IsMatched(bot) and bot.Humanoid.SeatPart then
				waiting = waiting or bot
			end
		end
		-- If every spare NPC is waiting at a table, stand one up; the next reconciliation walks it out naturally.
		if waiting then self:Release(waiting) end
	end
end

function NPCPopulationService.Step(self: any, dt: number)
	if self.Destroyed or self.Config.Enabled == false then return end
	self.Clock += dt
	local now = self.D.Now()
	if now >= self.NextPopulationAt then
		self.NextPopulationAt = now + self.Random:NextNumber(self.Config.JoinIntervalMin or 1.5, self.Config.JoinIntervalMax or 4.5)
		self:Reconcile()
	end
	if now >= (self.NextChatAt or math.huge) then self:ChatActivity() end
	self:DispatchHumanTable(now)
	for index = #self.Bots, 1, -1 do
		local bot = self.Bots[index]
		if not bot.Character.Parent or not bot.Humanoid.Parent or bot.Humanoid.Health <= 0 then
			self:Remove(bot)
			continue
		end
		if self:RecoverRunaway(bot) then continue end
		if now < (bot.WaterRecoveryUntil or 0) then continue end
		self:UpdateSpeed(bot, dt)
		if bot.Departing then continue end
		if self.D.IsMatched(bot) then bot.State, bot.DesiredSpeed = "MATCH", 0;continue end
		if bot.Humanoid.SeatPart then
			bot.State, bot.DesiredSpeed = "SEATED", 0
			local record = self.D.Owner(bot)
			local humans = record and select(1, self:SeatCounts(record)) or 0
			if bot.ManagedPopulation and humans == 0 and ((bot.LeaveAt and now >= bot.LeaveAt) or now >= bot.DepartAt) then self:Release(bot) end
			continue
		end
		if bot.State == "MATCH" or bot.State == "SEATED" then
			-- Covers unexpected weld loss and cancellation paths that did not call Release: leave the chair area now.
			self:Release(bot)
			continue
		end
		if bot.ManagedPopulation and now >= bot.DepartAt and bot.State == "IDLE" then self:BeginDeparture(bot);continue end
		if bot.ManagedPopulation and now >= bot.NextCosmeticAt and bot.State == "IDLE" then self:ChangeCosmetics(bot) end
		if bot.State == "IDLE" and now >= (bot.NextDecision or 0) then
			local record, seat = self:ChooseSeat()
			local tableChance = (self.Config.TableChance or 0.75) * (0.55 + bot.Personality.Social * 0.75)
			if record and seat and self.Random:NextNumber() < tableChance then
				self:GoSit(bot, record, seat)
			else
				self:Wander(bot)
			end
		end
	end
end

function NPCPopulationService.Destroy(self: any)
	self.Destroyed = true
	for index = #self.Bots, 1, -1 do self:Remove(self.Bots[index]) end
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	self.D.World:SetAttribute("NPCCount", nil)
	self.D.World:SetAttribute("DisplayedPopulation", nil)
end

return NPCPopulationService

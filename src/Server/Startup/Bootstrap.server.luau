--!strict
local Players = game:GetService("Players")
local Storage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = Storage:WaitForChild("Shared")
local Root = script.Parent.Parent
local Config = require(Shared.Config.GameConfig)
local Catalog = require(Shared.Config.ObjectData)
local ScaleMath = require(Shared.Util.ScaleMath)
local Names = require(Shared.Network.MatchRemotes)
local MatchService = require(Root.Services.MatchService)
local PetAbilityService = require(Root.Services.PetAbilityService)
local RoundService = require(Root.Services.RoundService)
local TableService = require(Root.Services.TableService)
local EconomyRuntime = require(Root.Services.EconomyRuntime)
local TravelService = require(Root.Services.TravelService)
local LeaderboardService = require(Root.Services.LeaderboardService)
local EconomyConfig = require(Root.Config.EconomyConfig)
local ChatNews = require(Shared.Util.ChatNews)
local Shop = require(Shared.Config.ShopCatalog)
local Rewards = require(Shared.Config.RewardCatalog)
local WorldBindings = require(Root.World.WorldBindings)
local WaterRespawn = require(Root.World.WaterRespawn)
local LuckyBlocksTrigger = require(Root.World.LuckyBlocksTrigger)
local Measurements = require(Root.Config.ObjectMeasurements)
local LobbySetup = require(Root.World.LobbySetup)
local TableDisplay = require(Root.World.TableDisplay)
local Cosmetics = require(Shared.Config.CosmeticCatalog)
local CosmeticDisplay = require(Root.World.CosmeticDisplay)
local ChairShop = require(Root.World.ChairShop)
local EggShops = require(Root.World.EggShops)
local ChairFx = require(Root.World.ChairFx)
local AFKPortal = require(Root.World.AFKPortal)
local AnalyticsFunnel = require(Root.Services.AnalyticsFunnel)
local BotPlayer = require(Root.Services.BotPlayer)
local NPCPopulationService = require(Root.Services.NPCPopulationService)
local PracticeBotService = require(Root.Services.PracticeBotService)
local BadgeRules = require(Root.Services.BadgeRules)
local ChairVisual = require(Shared.Util.ChairVisual)
local ObjectVisual = require(Shared.Util.ObjectVisual)
local ObjectLibrary = require(Root.World.ObjectLibrary)
local PetLibrary = require(Root.World.PetLibrary)
local botTagMissingWarned = false
local function attachBotTag(character: Model)
	local assets = Storage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("BotTag")
	if not (template and template:IsA("BillboardGui")) then
		if not botTagMissingWarned then
			botTagMissingWarned = true
			warn("Scale It Up: ReplicatedStorage.Assets.UI.BotTag must be a BillboardGui")
		end
		return
	end
	local old = character:FindFirstChild("BotTag")
	if old then old:Destroy() end
	local tag = template:Clone()
	tag.Name = "BotTag"
	tag.Enabled = false
	tag.Adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	tag.Parent = character
end
local _, availablePets = PetLibrary.Build(
	game:GetService("ServerStorage"),
	Storage,
	require(Shared.Config.PetDatabase),
	Cosmetics,
	ObjectVisual,
	CollectionService,
	warn
)
local objectModels, objectMeasurements, objectCatalog = ObjectLibrary.Build(
	game:GetService("ServerStorage"),
	Storage,
	Catalog,
	Measurements,
	Config,
	ObjectVisual,
	CollectionService,
	warn
)
if not Config.UseLabeledBricks then
	Catalog = objectCatalog
end

LobbySetup.Ensure(workspace, CollectionService, EconomyConfig, Config.TableTag)
local waterRespawn = WaterRespawn.new(workspace, Players, CollectionService, Config.WaterRespawn)

local function instance(parent: Instance, name: string, className: string): any
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, name .. " has wrong class")
		return existing
	end
	local created = Instance.new(className)
	created.Name, created.Parent = name, parent
	return created
end
local remotes = instance(Storage, Names.Folder, "Folder")
local stateRemote = instance(remotes, Names.State, "RemoteEvent")
local guessRemote = instance(remotes, Names.Guess, "RemoteEvent")
local lockRemote = instance(remotes, Names.Lock, "RemoteEvent")
local hintRemote = instance(remotes, Names.Hint, "RemoteEvent")
local heartRemote = instance(remotes, Names.Heart, "RemoteEvent")
local inkSplatRemote = instance(remotes, Names.InkSplat, "RemoteEvent")
local readyRemote = instance(remotes, Names.Ready, "RemoteEvent")
local leaveSpectatorRemote = instance(remotes, Names.LeaveSpectator, "RemoteEvent")
local voteRemote = instance(remotes, Names.ModeVote, "RemoteEvent")
local chatNewsRemote = instance(remotes, Names.ChatNews, "RemoteEvent")
local playBotRemote = instance(remotes, Names.PlayBot, "RemoteEvent")
local obsoleteTutorialRemote = remotes:FindFirstChild("Tutorial")
if obsoleteTutorialRemote then obsoleteTutorialRemote:Destroy() end
local revisions: { [Player]: number } = {}
-- The hint request each player is buying with Robux right now (see the Hint remote and RetryHint).
local pendingHints: { [Player]: any } = {}
-- The lost heart each player is buying back with Robux right now (see the Heart remote and RetryHeart).
local pendingHearts: { [Player]: any } = {}
-- A sabotage purchase prompt opened while a bot owns the turn. Keyed by the real purchaser's UserId because
-- MarketplaceService.PromptProductPurchaseFinished reports a UserId rather than a Player instance.
local pendingSabotagePrompts: { [number]: any } = {}
local botPromptHeldMatches: { [any]: boolean } = setmetatable({}, { __mode = "k" })
local readyAt: { [Player]: number } = {}
local remoteAt: { [Player]: { [string]: number } } = {}
local leaving: { [Player]: boolean } = {}
local function allowRemote(player: Player, key: string, interval: number): boolean
	if player.Parent ~= Players or leaving[player] then return false end
	local now = workspace:GetServerTimeNow()
	local limits = remoteAt[player]
	if not limits then
		limits = {}
		remoteAt[player] = limits
	end
	if now < (limits[key] or 0) then return false end
	limits[key] = now + interval
	return true
end
-- A bot stub is a plain Lua table (typeof "table"); a real Player is an Instance (typeof "Instance"), and
-- indexing an undefined property directly on an Instance throws instead of returning nil, so this must
-- check typeof first before ever reading .IsBot off something that might be a real Player.
local function isBot(player: any): boolean
	return typeof(player) == "table" and player.IsBot == true
end
local function send(player: Player, snapshot: any)
	-- A bot stub is never a real Player: nothing to FireClient to.
	if isBot(player) or player.Parent ~= Players or leaving[player] then
		return
	end
	revisions[player] = (revisions[player] or 0) + 1
	snapshot.Revision = revisions[player]
	stateRemote:FireClient(player, snapshot)
end
local tables: any
local matches: any
local funnel: any
local world: any
local economy = EconomyRuntime.new({
	Players = Players,
	Storage = Storage,
	World = workspace,
	Http = HttpService,
	RunService = RunService,
	DataStore = game:GetService("DataStoreService"),
	Marketplace = game:GetService("MarketplaceService"),
	Policy = game:GetService("PolicyService"),
	Catalog = Cosmetics,
	Shop = Shop,
	Config = EconomyConfig,
	GameConfig = Config,
	AvailablePets = availablePets,
	Rewards = Rewards,
	Groups = game:GetService("GroupService"),
	ChatNews = ChatNews,
	-- Roblox badges (RewardCatalog.Badges): EconomyRuntime.AwardBadge hands out what BadgeRules says was earned.
	BadgeService = game:GetService("BadgeService"),
	GameId = game.GameId, -- a badge must belong to this experience to be awarded
	Wealth = require(Shared.Util.WealthScale), -- invite rewards grow with the Cash a player holds
	BadgeRules = BadgeRules,
	GroupId = if Rewards.GroupId > 0
		then Rewards.GroupId
		elseif game.CreatorType == Enum.CreatorType.Group then game.CreatorId
		else 0,
	Busy = function(player)
		return (not isBot(player) and player:GetAttribute("Traveling") == true)
			or (tables and tables.Owners[player] ~= nil)
			or (matches and matches.ByPlayer[player] ~= nil)
	end,
	ResolveBot = function(userId: number)
		if not world then return nil end
		for _, bot in world.Bots do
			if bot.ManagedPopulation and bot.UserId == userId and bot.Character and bot.Character.Parent then return bot end
		end
		return nil
	end,
	-- A watcher who tapped a troll button with no SabotageCredits gets prompted to buy one (see
	-- inkSplatRemote below); once the receipt lands this replays that exact same attempt so the
	-- effect actually fires instead of just banking the credit silently.
	-- A Hint bought with Robux: once the receipt grants the HintCredit, the hint the player asked for is given right
	-- away (spending that credit) if their turn is still running; otherwise the credit stays saved for the next hint.
	RetryHint = function(player: Player)
		local pending = pendingHints[player]
		pendingHints[player] = nil
		if pending and matches then
			matches:BuyHint(player, pending.MatchId, pending.RoundId, pending.TurnId)
		end
	end,
	-- A Refill Heart bought with Robux: the heart the player asked for comes back right away (spending the credit) if
	-- their turn is still running; otherwise the credit stays saved for the next time they buy a heart back.
	RetryHeart = function(player: Player)
		local pending = pendingHearts[player]
		pendingHearts[player] = nil
		if pending and matches then
			matches:BuyHeart(player, pending.MatchId, pending.RoundId, pending.TurnId)
		end
	end,
	RetrySabotage = function(player: Player, pending: any)
		if matches then
			matches:UseInkSplat(player, pending.MatchId, pending.RoundId, pending.TurnId, pending.Kind)
		end
	end,
	Purchased = function(player: Player)
		funnel:Log(player, AnalyticsFunnel.Purchased)
	end,
	LeveledUp = function(player: Player)
		funnel:Log(player, AnalyticsFunnel.LeveledUp)
	end,
	HatchedPet = function(player: Player)
		funnel:Log(player, AnalyticsFunnel.HatchedPet)
	end,
})
-- Chat news goes to everyone; the server decides what is worth announcing.
economy.News = function(packet: any)
	chatNewsRemote:FireAllClients(packet)
end
local leaderboards = LeaderboardService.new({
	Players = Players,
	Workspace = workspace,
	Storage = Storage,
	DataStore = game:GetService("DataStoreService"),
	IsStudio = RunService:IsStudio(),
	Warn = warn,
	Clock = os.clock,
	Wait = task.wait,
	Spawn = task.spawn,
	Delay = task.delay,
	Enum = Enum,
	GetStat = function(player: Player, stat: string): number?
		local data = economy.Profiles:Get(player.UserId)
		local value = data and data[stat]
		return if type(value) == "number" then value else nil
	end,
})
local teleport = game:GetService("TeleportService")
economy.Travel = TravelService.new({
	PlaceId = game.PlaceId,
	IsStudio = function()
		return RunService:IsStudio()
	end,
	Present = function(player)
		return player.Parent == Players
	end,
	CanTravel = function(player)
		local entry = economy.Profiles.Entries[player.UserId]
		return not economy.Closing
			and not economy.D.Busy(player)
			and entry ~= nil
			and not entry.Busy
			and economy.Profiles:Get(player.UserId) ~= nil
			and not entry.Data.PendingTransfer
			and not economy.Transfers.Busy[player.UserId]
	end,
	SetTraveling = function(player, value)
		player:SetAttribute("Traveling", value)
	end,
	Message = function(player, message)
		economy:Send(player, message)
	end,
	Release = function(player)
		return economy.Profiles:Save(player.UserId, true)
	end,
	Recover = function(player)
		economy:Add(player)
		return economy.Profiles:Get(player.UserId) ~= nil
	end,
	Kick = function(player, message)
		player:Kick(message)
	end,
	Teleport = function(destination, player)
		teleport:TeleportAsync(destination, { player })
	end,
})
table.insert(
	economy.Connections,
	teleport.TeleportInitFailed:Connect(function(player, _, _, destination)
		economy.Travel:Recover(player, destination)
	end)
)
local currency, inventory = economy.Currency, economy.Inventory
local luckyBlocksTrigger = LuckyBlocksTrigger.new(workspace, Players, function(player)
	economy:OpenLuckyBlocks(player)
end)
world = WorldBindings.new(workspace, Storage, Players, Catalog, Config)
waterRespawn.Bindings = world
local npcPopulation: any
local practiceBots = PracticeBotService.new({
	World = workspace,
	ServerStorage = ServerStorage,
	CollectionService = CollectionService,
	Bindings = world,
	CharacterBots = world.Bots,
	Profiles = inventory.Profiles,
	BotUserIdCeiling = Config.BotUserIdCeiling,
	AttachBotTag = attachBotTag,
})
local function destroyBot(bot: any)
	if not bot then
		return
	end
	if npcPopulation and npcPopulation:Owns(bot) then
		npcPopulation:Remove(bot)
		return
	end
	practiceBots:Remove(bot)
end
local tableDisplay =
	TableDisplay.new(Config, Catalog, require(Shared.Util.PrizeRoll), objectModels, ObjectVisual, world)
local rounds = RoundService.new(
	Config,
	ScaleMath,
	Catalog,
	if Config.UseLabeledBricks then Measurements else objectMeasurements,
	Random.new(),
	function()
		return world:ModelIds()
	end
)
-- Funnel analytics ("Onboarding V2"): see AnalyticsFunnel.luau for the full ten-step chain.
local analyticsOk, analyticsService = pcall(function()
	return game:GetService("AnalyticsService")
end)
funnel = AnalyticsFunnel.new(if analyticsOk then analyticsService else nil, function()
	return HttpService:GenerateGUID(false)
end)
-- Round badges for one player at a reveal (see BadgeRules.ForRound): their accuracy and guess, both objects' heights,
-- the tallest object in the game and how much of their turn they used. Runs in its own thread (badge calls yield).
local function roundBadges(player: Player)
	local match = matches and matches.ByPlayer[player]
	local index = match and table.find(match.Players, player)
	local reveal = match and match.Reveal
	if not (index and reveal and reveal.Errors[index] and reveal.Guesses[index]) then
		return
	end
	local pair = match.CurrentObjectPair
	local largest = 0
	for _, id in world:ModelIds() do
		local height = rounds.Measurements[id]
		if type(height) == "number" then
			largest = math.max(largest, height)
		end
	end
	local earned = BadgeRules.ForRound(
		ScaleMath.Accuracy(reveal.Errors[index]),
		reveal.Guesses[index],
		pair.Actual,
		pair.ReferenceMeters,
		if largest > 0 then largest else nil,
		match.TurnUsed and match.TurnUsed[index]
	)
	for _, key in earned do
		economy:AwardBadge(player, key)
	end
end
matches = MatchService.new(Config, rounds, currency, {
	Finished = function(player: Player, match: any)
		if isBot(player) then
			if npcPopulation then
				npcPopulation:MatchFinished(player, match and match.Winner and match.Players[match.Winner] == player)
			end
			return
		end
		funnel:Log(player, AnalyticsFunnel.Finished)
		if match and match.Winner and match.Players[match.Winner] == player then
			funnel:Log(player, AnalyticsFunnel.Won)
		end
	end,
	GuessLocked = function(player: Player)
		if not isBot(player) then
			funnel:Log(player, AnalyticsFunnel.LockedGuess)
		end
	end,
	RoundRevealed = function(player: Player)
		if not isBot(player) then
			funnel:Log(player, AnalyticsFunnel.SawReveal)
			task.spawn(roundBadges, player)
		end
	end,
	Now = function()
		return workspace:GetServerTimeNow()
	end,
	NewId = function()
		return HttpService:GenerateGUID(false)
	end,
	Send = send,
	Warn = warn,
	Pets = function(player)
		local data = if isBot(player)
			then inventory.Profiles[player] and inventory.Profiles[player].Data
			else economy.Profiles:Get(player.UserId)
		return PetAbilityService.Capture(data, Cosmetics)
	end,
	PetTurn = PetAbilityService.Turn,
	PetEffects = PetAbilityService.Effects,
	PetCash = function(match, index, amount)
		economy:PetCash(match, index, amount)
	end,
	Settle = function(match, winner)
		economy:Settle(match, winner)
		for _, participant in match.Players do
			if not isBot(participant) then
				leaderboards:QueuePlayerSync(participant)
				-- Match-win milestone badges (Wins was just updated).
				task.spawn(function()
					economy:CheckBadges(participant)
				end)
			end
		end
	end,
	RoundComplete = function(match)
		economy:RoundComplete(match, Config)
	end,
	-- The XP a finished match is worth (the same amounts EconomyRuntime.Settle awards), for the end-of-match banner.
	MatchXP = function(won: boolean)
		return EconomyConfig.PlayerLevels.MatchPlayedXP + (if won then EconomyConfig.PlayerLevels.MatchWonXP else 0)
	end,
	Eliminated = function(match, index)
		economy:Eliminated(match, index)
	end,
	ReactionView = function(match: any, player: Player, opponent: Player)
		return world:ReactionView(match.Table, player, opponent)
	end,
	StateChanged = function(match: any)
		local state = if match.Finished then "ENDING" else "IN_MATCH"
		match.Table.State = state
		match.Table.Key:SetAttribute("MatchState", state)
	end,
	Cleanup = function(match: any)
		tables:CleanupMatch(match)
		for _, participant in match.Players do
			if isBot(participant) then
				if participant.ManagedPopulation and npcPopulation then npcPopulation:Release(participant)
				else destroyBot(participant) end
			end
		end
		match.Table.ForcedMode = nil
	end,
	-- Every troll-panel use spends one purchased SabotageCredit; see the inkSplatRemote handler below, which
	-- prompts the real Sabotage product when a use fails for lack of credit.
	-- Every hint beyond a pet's free one spends a HintCredit bought with the Hint developer product.
	-- Buying a lost heart back spends a HeartCredit bought with the Refill Heart developer product.
	SpendHeartCredit = function(player: Player): boolean
		local data = economy.Profiles:Get(player.UserId)
		if not data or (data.HeartCredits or 0) <= 0 then
			return false
		end
		data.HeartCredits -= 1
		return true
	end,
	SpendHintCredit = function(player: Player): boolean
		local data = economy.Profiles:Get(player.UserId)
		if not data or (data.HintCredits or 0) <= 0 then
			return false
		end
		data.HintCredits -= 1
		return true
	end,
	SpendSabotageCredit = function(player: any): boolean
		-- A very rare planned bot troll uses the normal validated match path without touching a real player's purchase data.
		if isBot(player) then return true end
		local data = economy.Profiles:Get(player.UserId)
		if not data or (data.SabotageCredits or 0) <= 0 then
			return false
		end
		data.SabotageCredits -= 1
		return true
	end,
})
local prizeRandom = Random.new()
tables = TableService.new(Config, matches, {
	Seated = function(player: Player)
		if not isBot(player) then
			funnel:Log(player, AnalyticsFunnel.Seated)
		end
	end,
	MatchStarted = function(player: Player)
		if not isBot(player) then funnel:Log(player, AnalyticsFunnel.Started) end
	end,
	PickVote = function(count)
		return prizeRandom:NextInteger(1, count)
	end,
	Capacity = function(model)
		local value = model:GetAttribute("Capacity")
		return if type(value) == "number" then math.clamp(math.floor(value), 2, 4) else 2
	end,
	Prize = function()
		return EconomyConfig.Prizes[prizeRandom:NextInteger(1, #EconomyConfig.Prizes)], EconomyConfig.PrizeRollSeconds
	end,
	Now = function()
		return workspace:GetServerTimeNow()
	end,
	Send = send,
	Warn = warn,
	SetState = function(record: any, state: string)
		record.Key:SetAttribute("MatchState", state)
	end,
	Alive = function(player: Player)
		if isBot(player) then
			return world:Alive(player)
		end
		return not leaving[player]
			and not player:GetAttribute("Traveling")
			and economy.Profiles:Get(player.UserId) ~= nil
			and world:Alive(player)
	end,
	Occupants = function(record: any)
		return world:Occupants(record)
	end,
	Prepare = function(record: any)
		return world:Prepare(record)
	end,
	Valid = function(record: any)
		return world:Valid(record)
	end,
	Eject = function(record: any, player: Player)
		world:Eject(record, player)
	end,
})
local cosmeticDisplay = CosmeticDisplay.new(workspace, Cosmetics, ChairVisual, Storage)
local chairFx = ChairFx.new()

local bindings: { [Instance]: { RBXScriptConnection } } = {}
local globalConnections: { RBXScriptConnection } = {}
table.insert(
	globalConnections,
	game:GetService("MarketplaceService").PromptGamePassPurchaseFinished
		:Connect(function(player, gamePassId, wasPurchased)
			economy:GamePassPurchaseFinished(player, gamePassId, wasPurchased)
		end)
)
local seatsDirty = false
local function unbind(model: Instance)
	local connections = bindings[model]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	bindings[model] = nil
	local record = tables.Records[model]
	if record then
		tableDisplay:Remove(record)
	end
	tables:Remove(model)
end
local function bind(model: Instance)
	if bindings[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			object.Anchored = true
		end
	end
	local record = tables:Add(model)
	tableDisplay:Update(record, workspace:GetServerTimeNow())
	local connections = {}
	bindings[model] = connections
	record.SeatCacheManaged = true
	-- Coalesce seat signals until the next heartbeat; read BOTH current occupants.
	-- Polling also handles authored seat replacement, death, and unexpected empty seats.
	for _, child in model:GetDescendants() do
		if child:IsA("Seat") then
			table.insert(
				connections,
				child:GetPropertyChangedSignal("Occupant"):Connect(function()
					seatsDirty = true
				end)
			)
		end
	end
	table.insert(
		connections,
		model.DescendantAdded:Connect(function(child)
			if not child:IsA("Seat") then
				return
			end
			record.BoundSeats, seatsDirty = nil, true
			table.insert(
				connections,
				child:GetPropertyChangedSignal("Occupant"):Connect(function()
					seatsDirty = true
				end)
			)
		end)
	)
	table.insert(
		connections,
		model.DescendantRemoving:Connect(function(child)
			if child:IsA("Seat") then
				record.BoundSeats, seatsDirty = nil, true
			end
		end)
	)
	table.insert(
		connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				unbind(model)
			end
		end)
	)
end
table.insert(globalConnections, CollectionService:GetInstanceAddedSignal(Config.TableTag):Connect(bind))
table.insert(globalConnections, CollectionService:GetInstanceRemovedSignal(Config.TableTag):Connect(unbind))
table.insert(
	globalConnections,
	workspace.DescendantAdded:Connect(function(model)
		if model:IsA("Model") then
			LobbySetup.Register(workspace, CollectionService, model, Config.TableTag)
			if CollectionService:HasTag(model, Config.TableTag) then
				bind(model)
			end
		end
	end)
)
for _, model in CollectionService:GetTagged(Config.TableTag) do
	bind(model)
end
npcPopulation = NPCPopulationService.new({
	Config = Config.NPCPopulation,
	LevelConfig = EconomyConfig.PlayerLevels,
	BotUserIdCeiling = Config.BotUserIdCeiling,
	Players = Players,
	World = workspace,
	ServerStorage = ServerStorage,
	Storage = Storage,
	Pathfinding = game:GetService("PathfindingService"),
	CollectionService = CollectionService,
	Catalog = Cosmetics,
	AvailablePets = availablePets,
	Bindings = world,
	CharacterBots = world.Bots,
	Profiles = inventory.Profiles,
	Records = function() return tables.Records end,
	Owner = function(bot) return tables.Owners[bot] end,
	IsMatched = function(bot) return matches.ByPlayer[bot] ~= nil end,
	IsBot = isBot,
	Now = function() return workspace:GetServerTimeNow() end,
	Warn = warn,
	News = function(packet) chatNewsRemote:FireAllClients(packet) end,
	RemoveVisual = function(bot) cosmeticDisplay:Remove(bot) end,
	AttachBotTag = attachBotTag,
})

waterRespawn.BeforeBotReturn = function(character, destination)
	local bot = world.Bots[character]
	if bot and npcPopulation:Owns(bot) then npcPopulation:RecoverWater(bot, destination) end
end

local function promptBelongsToTurn(entry: any, match: any, now: number): boolean
	if
		not match
		or match.Finished
		or match.MatchId ~= entry.MatchId
		or match.RoundId ~= entry.RoundId
		or match.TurnId ~= entry.TurnId
		or match.RoundState ~= "GUESSING"
		or match.LockRequested
		or now - entry.OpenedAt >= (Config.BotPurchasePromptTimeoutSeconds or 120)
	then
		return false
	end
	local player = Players:GetPlayerByUserId(entry.UserId)
	local index = player and table.find(match.Players, player)
	return index ~= nil
		and not match.Departed[index]
		and index ~= match.ActiveIndex
		and match.Hearts[index] > 0
end

local function promptTargetsBot(entry: any, match: any, now: number): boolean
	if not promptBelongsToTurn(entry, match, now) then return false end
	local active = match.Players[match.ActiveIndex]
	return active ~= nil and isBot(active)
end

local function matchHasOpenBotPrompt(match: any, now: number): boolean
	for userId, entry in pendingSabotagePrompts do
		local player = Players:GetPlayerByUserId(userId)
		if not player or not promptBelongsToTurn(entry, entry.Match, now) then
			pendingSabotagePrompts[userId] = nil
		elseif entry.Match == match and promptTargetsBot(entry, entry.Match, now) then
			return true
		end
	end
	return false
end

local function releaseBotPromptHold(match: any, now: number)
	if not match or matchHasOpenBotPrompt(match, now) then return end
	if botPromptHeldMatches[match] then
		botPromptHeldMatches[match] = nil
		match.BotPurchasePromptHeldAt = nil
		match.BotPurchasePromptPublishAt = nil
		-- Replan from the visible size so closing the prompt never causes an immediate, stale Lock In.
		match.BotTurnId = nil
		if not match.Finished then matches:Publish(match) end
	end
end

local function finishBotSabotagePrompt(userId: number)
	local entry = pendingSabotagePrompts[userId]
	if not entry then return end
	pendingSabotagePrompts[userId] = nil
	releaseBotPromptHold(entry.Match, workspace:GetServerTimeNow())
end

local function beginSabotagePrompt(player: Player, match: any, request: any): boolean
	local existing = pendingSabotagePrompts[player.UserId]
	if existing and promptBelongsToTurn(existing, existing.Match, workspace:GetServerTimeNow()) then
		return false
	end
	finishBotSabotagePrompt(player.UserId)
	local now = workspace:GetServerTimeNow()
	local entry = {
		UserId = player.UserId,
		MatchId = request.MatchId,
		RoundId = request.RoundId,
		TurnId = request.TurnId,
		OpenedAt = now,
		Match = match,
	}
	if not promptBelongsToTurn(entry, match, now) then return false end
	pendingSabotagePrompts[player.UserId] = entry
	-- Only a bot needs its plan/deadline held while Roblox's purchase UI is open. Real opponents continue normally.
	if not promptTargetsBot(entry, match, now) then return true end
	pendingSabotagePrompts[player.UserId] = {
		UserId = player.UserId,
		Match = match,
		MatchId = request.MatchId,
		RoundId = request.RoundId,
		TurnId = request.TurnId,
		OpenedAt = now,
	}
	botPromptHeldMatches[match] = true
	match.BotPurchasePromptHeldAt = now
	match.BotPurchasePromptPublishAt = now + 1
	match.Deadline = math.max(match.Deadline, now + Config.GuessSeconds)
	matches:Publish(match)
	return true
end

local function updateBotSabotagePromptHolds(now: number)
	local heldNow = {}
	for userId, entry in pendingSabotagePrompts do
		local player = Players:GetPlayerByUserId(userId)
		local match = entry.Match
		if not player or not promptBelongsToTurn(entry, match, now) then
			pendingSabotagePrompts[userId] = nil
		elseif promptTargetsBot(entry, match, now) then
			heldNow[match] = true
		end
	end
	for match in botPromptHeldMatches do
		if heldNow[match] then
			local previous = match.BotPurchasePromptHeldAt or now
			match.Deadline += math.max(0, now - previous)
			match.BotPurchasePromptHeldAt = now
			if now >= (match.BotPurchasePromptPublishAt or 0) then
				match.BotPurchasePromptPublishAt = now + 1
				matches:Publish(match)
			end
		else
			releaseBotPromptHold(match, now)
		end
	end
end

local function addPlayer(player: Player)
	funnel:Log(player, AnalyticsFunnel.Joined)
	task.spawn(function()
		economy:Add(player)
		-- "How Big Is It?" on the first visit, plus any win milestones reached before badges were handed out.
		economy:CheckBadges(player)
	end)
end
table.insert(globalConnections, Players.PlayerAdded:Connect(addPlayer))
for _, player in Players:GetPlayers() do
	addPlayer(player)
end
table.insert(
	globalConnections,
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = true
		finishBotSabotagePrompt(player.UserId)
		funnel:Remove(player)
		leaderboards:QueuePlayerSync(player)
		-- Reconcile while identity is still available, before clearing the wallet.
		tables:Tick()
		cosmeticDisplay:Remove(player)
		economy.Travel:Remove(player)
		economy:Remove(player)
		revisions[player], readyAt[player], remoteAt[player], leaving[player], pendingHints[player] = nil, nil, nil, nil, nil
		pendingHearts[player] = nil
end)
)
table.insert(
	globalConnections,
	game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local hint = Shop.Products.Hint
		if hint and productId == hint.ProductId then
			-- Receipts clear successful purchases through RetryHint. A cancelled prompt has no receipt, so unlock it here.
			if not purchased then
				local player = Players:GetPlayerByUserId(userId)
				if player then pendingHints[player] = nil end
			end
			return
		end
		local refill = Shop.Products.RefillHeart
		if refill and productId == refill.ProductId then
			-- A successful developer-product receipt clears this through RetryHeart. Cancellation has no receipt, so
			-- release the request here and let the next click open a fresh prompt.
			if not purchased then
				local player = Players:GetPlayerByUserId(userId)
				if player then pendingHearts[player] = nil end
			end
			return
		end
		local steal=Shop.Products.Steal
		if steal and productId==steal.ProductId then
			if not purchased then
				local player=Players:GetPlayerByUserId(userId)
				if player then economy:CancelStealPrompt(player) end
			end
			return
		end
		local sabotage = Shop.Products.Sabotage
		if not sabotage or productId ~= sabotage.ProductId then return end
		finishBotSabotagePrompt(userId)
		-- A cancelled prompt must not leave a saved attempt that a later, unrelated receipt could replay.
		if not purchased then
			local player = Players:GetPlayerByUserId(userId)
			local data = player and economy.Profiles:Get(userId)
			if data and data.PendingSabotage then
				data.PendingSabotage = nil
				task.spawn(function() economy.Profiles:Save(userId) end)
			end
		end
	end)
)
table.insert(
	globalConnections,
	guessRemote.OnServerEvent:Connect(function(player, matchId, roundId, guess, ...)
		if
			select("#", ...) ~= 0
			or type(matchId) ~= "string"
			or #matchId > 64
			or type(roundId) ~= "string"
			or #roundId > 64
		then
			return
		end
		if not allowRemote(player, "Guess", 1 / 30) then return end
		matches:Submit(player, matchId, roundId, guess)
	end)
)
table.insert(
	globalConnections,
	lockRemote.OnServerEvent:Connect(function(player, matchId, roundId, turnId, guess, ...)
		if
			select("#", ...) ~= 0
			or type(matchId) ~= "string"
			or #matchId > 64
			or type(roundId) ~= "string"
			or #roundId > 64
			or type(turnId) ~= "string"
			or #turnId > 64
		then
			return
		end
		if not allowRemote(player, "Lock", 0.1) then return end
		matches:Lock(player, matchId, roundId, turnId, guess)
	end)
)
table.insert(
	globalConnections,
	readyRemote.OnServerEvent:Connect(function(player, ...)
		if select("#", ...) ~= 0 then
			return
		end
		local now = workspace:GetServerTimeNow()
		if readyAt[player] and now - readyAt[player] < 0.5 then
			return
		end
		readyAt[player] = now
		local match, record = matches.ByPlayer[player], tables.Owners[player]
		send(
			player,
			if match
				then matches:Snapshot(match, player)
				elseif record then tables:Snapshot(record, player)
				else { State = "IDLE" }
		)
	end)
)
table.insert(
	globalConnections,
	voteRemote.OnServerEvent:Connect(function(player, voteId, mode, ...)
		if
			select("#", ...) ~= 0
			or type(voteId) ~= "string"
			or #voteId > 64
			or type(mode) ~= "string"
			or #mode > 32
		then
			return
		end
		if not allowRemote(player, "Vote", 0.1) then return end
		tables:Vote(player, voteId, mode)
	end)
)
table.insert(
	globalConnections,
	hintRemote.OnServerEvent:Connect(function(player, matchId, roundId, turnId, ...)
		if
			select("#", ...) ~= 0
			or type(matchId) ~= "string"
			or #matchId > 64
			or type(roundId) ~= "string"
			or #roundId > 64
			or type(turnId) ~= "string"
			or #turnId > 64
		then
			return
		end
		if not allowRemote(player, "Hint", 0.25) then return end
		if pendingHints[player] then return end
		-- No free pet hint and no saved credit: prompt the Robux Hint product; the receipt replays this request.
		local ok, reason = matches:BuyHint(player, matchId, roundId, turnId)
		local hint = Shop.Products.Hint
		if not ok and reason == "NoCredit" and not economy.Memory and hint and hint.ProductId > 0 then
			pendingHints[player] = { MatchId = matchId, RoundId = roundId, TurnId = turnId }
			local prompted = pcall(function()
				economy.D.Marketplace:PromptProductPurchase(player, hint.ProductId)
			end)
			if not prompted then pendingHints[player] = nil end
		end
	end)
)
table.insert(
	globalConnections,
	heartRemote.OnServerEvent:Connect(function(player, matchId, roundId, turnId, ...)
		if
			select("#", ...) ~= 0
			or type(matchId) ~= "string"
			or #matchId > 64
			or type(roundId) ~= "string"
			or #roundId > 64
			or type(turnId) ~= "string"
			or #turnId > 64
		then
			return
		end
		if not allowRemote(player, "Heart", 0.25) then return end
		if pendingHearts[player] then return end
		-- No saved credit: prompt the Robux Refill Heart product; the receipt replays this request.
		local ok, reason = matches:BuyHeart(player, matchId, roundId, turnId)
		local refill = Shop.Products.RefillHeart
		if not ok and reason == "NoCredit" and not economy.Memory and refill and refill.ProductId > 0 then
			pendingHearts[player] = { MatchId = matchId, RoundId = roundId, TurnId = turnId }
			local prompted = pcall(function()
				economy.D.Marketplace:PromptProductPurchase(player, refill.ProductId)
			end)
			if not prompted then pendingHearts[player] = nil end
		end
	end)
)
table.insert(
	globalConnections,
	inkSplatRemote.OnServerEvent:Connect(function(player, matchId, roundId, turnId, kind, ...)
		if
			select("#", ...) ~= 0
			or type(matchId) ~= "string"
			or #matchId > 64
			or type(roundId) ~= "string"
			or #roundId > 64
			or type(turnId) ~= "string"
			or #turnId > 64
		then
			return
		end
		-- Which sabotage (Ink, Lag, FogBank, Wobble); nothing means the classic ink splat.
		if kind ~= nil and (type(kind) ~= "string" or #kind > 16) then
			return
		end
		if not allowRemote(player, "Sabotage", 0.15) then return end
		local ok, reason = matches:UseInkSplat(player, matchId, roundId, turnId, kind)
		if not ok and reason == "NoCredit" and not economy.Memory then
			local sabotage = Shop.Products.Sabotage
			if sabotage and sabotage.ProductId > 0 then
				local match = matches.ByPlayer[player]
				-- Start the hold before the durable profile write, which may yield long enough for a nearly-finished bot
				-- plan to lock and make the purchase useless.
				if not beginSabotagePrompt(player, match, {
					MatchId = matchId,
					RoundId = roundId,
					TurnId = turnId,
				}) then return end
				local data = economy.Profiles:Get(player.UserId)
				if data then
					-- Saved before prompting so Receipt() can replay this exact attempt once the credit lands,
					-- instead of the effect never firing even though the purchase succeeded.
					data.PendingSabotage = { MatchId = matchId, RoundId = roundId, TurnId = turnId, Kind = kind }
					economy.Profiles:Save(player.UserId)
				end
				local prompted = pcall(function()
					economy.D.Marketplace:PromptProductPurchase(player, sabotage.ProductId)
				end)
				if not prompted then
					finishBotSabotagePrompt(player.UserId)
					if data and data.PendingSabotage then
						data.PendingSabotage = nil
						task.spawn(function() economy.Profiles:Save(player.UserId) end)
					end
				end
			end
		end
	end)
)
-- The lobby Play Bot button uses this server-validated path and remains separate from the visual seat guide.
local function fillBotTable(player: Player): boolean
		local record = tables.Owners[player]
		if
			not record
			or record.Removed
			or record.Capacity < 2
			or record.State ~= "WAITING_FOR_PLAYER"
			or #record.Players ~= 1
			or record.Players[1] ~= player
		then
			return false
		end
		local needed = record.Capacity - 1
		local spawned = {}
		for _ = 1, needed do
			local bot = practiceBots:Spawn(record)
			if not bot then
				break
			end
			table.insert(spawned, bot)
		end
		if #spawned ~= needed then
			-- Never leave a half-filled practice request behind when one of several seats/templates failed.
			for _, bot in spawned do practiceBots:Remove(bot) end
			return false
		end
		if record.Capacity == 2 then
			-- Only a 1v1 skips the vote entirely; larger tables use their normal mode vote.
			record.ForcedMode = "Classic"
		end
		return true
	end
table.insert(
	globalConnections,
	playBotRemote.OnServerEvent:Connect(function(player, ...)
		if select("#", ...) ~= 0 then return end
		if not allowRemote(player, "PlayBot", 1) then return end
		fillBotTable(player)
	end)
)
-- The bot's turn (see BotPlayer): it aims near the humans' own accuracy this match, then drags from the round's
-- starting size like a person -- a look, a coarse drag, a few corrections, Lock In -- well before the timer runs out.
local botRandom = Random.new()
local function botMatchStrategy(match: any): any
	if match.BotDifficultyStrategy then return match.BotDifficultyStrategy end
	local tuning = Config.BotDifficulty or {}
	local profiles = {}
	for _, participant in match.Players do
		if not isBot(participant) then
			local data = economy.Profiles:Get(participant.UserId)
			if data then table.insert(profiles, data) end
		end
	end
	match.BotDifficultyStrategy = BotPlayer.Difficulty(botRandom, profiles, tuning)
	return match.BotDifficultyStrategy
end

local function botTurnStrategy(match: any): any
	local strategy = botMatchStrategy(match)
	local plan = strategy.Rounds[match.CurrentRound]
	if plan then return plan end
	local humanDanger, botDanger = false, false
	for index, hearts in match.Hearts do
		if hearts > 0 and not match.Departed[index] then
			if isBot(match.Players[index]) then botDanger = botDanger or hearts <= 1
			else humanDanger = humanDanger or hearts <= 1 end
		end
	end
	local roundLimit = Config.Modes[match.Mode] and Config.Modes[match.Mode].Rounds
	local decisive = match.Mode == "SuddenDeath"
		or (roundLimit ~= nil and match.CurrentRound >= roundLimit)
		or humanDanger
		or botDanger
	local trailHumans
	if decisive then
		-- The frozen match outcome is enforced most strongly when somebody is on their final heart/round.
		trailHumans = strategy.FavorHumans
	else
		-- Let either side take early hearts so even beginner matches develop into a close-looking contest.
		trailHumans = botRandom:NextNumber() < (if strategy.FavorHumans then 0.62 else 0.38)
	end
	plan = {
		TrailHumans = trailHumans,
		Decisive = decisive,
		ExpectedAccuracy = strategy.ExpectedAccuracy,
		CloseMarginMin = strategy.CloseMarginMin,
		CloseMarginMax = strategy.CloseMarginMax,
	}
	strategy.Rounds[match.CurrentRound] = plan
	return plan
end
-- The humans' accuracy so far: this round's locked human guesses, blended into a running memory for the match.
local function humanAccuracy(match: any): number?
	local pair = match.CurrentObjectPair
	local total, count = 0, 0
	for turn = 1, match.TurnIndex - 1 do
		local index = match.TurnOrder[turn]
		local player = index and match.Players[index]
		if player and not isBot(player) and not match.Departed[index] and match.Hearts[index] > 0 then
			total += ScaleMath.Accuracy(ScaleMath.Error(match.Guesses[index], pair.Actual))
			count += 1
		end
	end
	if count > 0 then
		local latest = total / count
		match.BotHumanAccuracy = if match.BotHumanAccuracy then (match.BotHumanAccuracy + latest) * 0.5 else latest
	end
	return match.BotHumanAccuracy
end
local function stepBotTurns()
	local now = workspace:GetServerTimeNow()
	for _, record in tables.Records do
		local match = record.Match
		if not (match and not match.Finished and match.RoundState == "GUESSING" and not match.LockRequested) then
			continue
		end
		local active = match.Players[match.ActiveIndex]
		if not (active and isBot(active)) then
			continue
		end
		if botPromptHeldMatches[match] then
			continue
		end
		local pair = match.CurrentObjectPair
		if match.BotTurnId ~= match.TurnId then
			local strategy = botTurnStrategy(match)
			local final =
				BotPlayer.Target(botRandom, pair.Actual, pair.GuessMinimum, pair.GuessMaximum, humanAccuracy(match), strategy)
			match.BotTurnId, match.BotSent, match.BotLastSubmitAt = match.TurnId, nil, -math.huge
			match.BotPlan = BotPlayer.Plan(
				botRandom,
				match.Guesses[match.ActiveIndex],
				final,
				pair.GuessMinimum,
				pair.GuessMaximum,
				now,
				match.Deadline
			)
		end
		local plan = match.BotPlan
		if now >= plan.LockAt then
			matches:Lock(active, match.MatchId, match.RoundId, match.TurnId, plan.Final)
		elseif now - match.BotLastSubmitAt >= 0.1 then
			-- Live drags go out about ten times a second, like a real slider; resting sends nothing.
			local value = BotPlayer.Sample(plan, now)
			if value ~= match.BotSent then
				match.BotLastSubmitAt = now
				if matches:Submit(active, match.MatchId, match.RoundId, value) then
					match.BotSent = value
				end
			end
		end
	end
end

-- At most one seated bot gets a single roll when a real player's turn begins. The tiny per-turn chance and delayed
-- activation make this an occasional surprise; the existing MatchService validation still owns duration, overlap,
-- target membership, notices and replication.
local BOT_SABOTAGE_KINDS = { "Ink", "Lag", "FogBank", "Wobble" }
local function stepBotSabotages()
	local now = workspace:GetServerTimeNow()
	for _, record in tables.Records do
		local match = record.Match
		if not (match and not match.Finished and match.RoundState == "GUESSING" and not match.LockRequested) then
			continue
		end
		local active = match.Players[match.ActiveIndex]
		if not active or isBot(active) then continue end
		if match.BotSabotageTurnId ~= match.TurnId then
			match.BotSabotageTurnId, match.BotSabotagePlan = match.TurnId, nil
			local watchers = {}
			for index, participant in match.Players do
				if
					index ~= match.ActiveIndex
					and isBot(participant)
					and not match.Departed[index]
					and match.Hearts[index] > 0
				then
					table.insert(watchers, participant)
				end
			end
			local remaining = match.Deadline - now
			if
				#watchers > 0
				and remaining >= 7
				and botRandom:NextNumber() < (Config.BotSabotageChancePerHumanTurn or 0.005)
			then
				match.BotSabotagePlan = {
					Bot = watchers[botRandom:NextInteger(1, #watchers)],
					Kind = BOT_SABOTAGE_KINDS[botRandom:NextInteger(1, #BOT_SABOTAGE_KINDS)],
					At = now + botRandom:NextNumber(4, math.min(14, remaining - 2)),
				}
			end
		end
		local plan = match.BotSabotagePlan
		if plan and not plan.Done and now >= plan.At then
			plan.Done = true
			matches:UseInkSplat(plan.Bot, match.MatchId, match.RoundId, match.TurnId, plan.Kind)
		end
	end
end
-- Bots only play with the human who called them: once no human is seated at their table (they stood up, left the
-- game or died), the bots go at once. Before a match they are simply removed and the table empties; during or after
-- one the match is cancelled and removed, whose cleanup destroys its bots. Runs before tables:Tick, so a human
-- walking out of a bot game cancels it rather than handing the bot a forfeit win.
local function dismissOrphanedBots()
	for _, record in tables.Records do
		local match = record.Match
		local bots = BotPlayer.Orphaned(world:Occupants(record), match and match.Players, isBot)
		if #bots > 0 then
			if match then
				-- Managed lobby NPCs are allowed to play complete matches with each other. Practice bots still belong
				-- to the real player who requested them, so that match is cancelled if its human leaves.
				local ambientOnly = true
				for _, bot in bots do if not bot.ManagedPopulation then ambientOnly = false;break end end
				if ambientOnly then continue end
				if not match.Finished then
					matches:Cancel(match, "Match cancelled")
				end
				matches:Remove(match)
			else
				-- Ambient NPCs are allowed to wait at a table for a real player. Explicit practice bots
				-- still disappear if the player who requested them leaves before the match begins.
				for _, bot in bots do
					if bot.PracticeBot then destroyBot(bot) end
				end
			end
			record.ForcedMode = nil
		end
	end
end
-- Every bot seated at a 3v3/4v4 table (2-seat duels skip voting entirely) casts its own random mode vote a
-- little after the vote opens, exactly like a real player clicking a mode button -- never instantly, and the
-- plan resets whenever VoteId changes (a fresh window, e.g. after a roster change restarts the vote).
local function stepBotVotes()
	local now = workspace:GetServerTimeNow()
	for _, record in tables.Records do
		if record.State == "VOTING" and record.VoteId and record.Votes then
			for _, seated in record.Players do
				if isBot(seated) and not record.Votes[seated] then
					record.BotVotePlan = record.BotVotePlan or {}
					local plan = record.BotVotePlan[seated]
					if not plan or plan.VoteId ~= record.VoteId then
						local window = math.max(1, (record.Deadline or now + 5) - now - 1)
						plan = { VoteId = record.VoteId, At = now + 0.5 + math.random() * math.min(6, window) }
						record.BotVotePlan[seated] = plan
					end
					if now >= plan.At then
						tables:Vote(seated, record.VoteId, Config.ModeOrder[math.random(1, #Config.ModeOrder)])
					end
				end
			end
		end
	end
end
local function bindChairPrompt(prompt: ProximityPrompt, stand: Instance, chairId: string, container: Instance)
	table.insert(
		globalConnections,
		prompt.Triggered:Connect(function(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local origin = if stand:IsA("BasePart") then stand.Position else stand:GetPivot().Position
			if
				prompt.Enabled
				and stand:IsDescendantOf(container)
				and container:IsDescendantOf(workspace)
				and root
				and humanoid
				and humanoid.Health > 0
				and not humanoid.SeatPart
				and (root.Position - origin).Magnitude <= prompt.MaxActivationDistance + 6
			then
				-- Buys, equips or unequips server-side; the client only chooses which chair it stands next to.
				economy:PurchaseChair(player, chairId)
			end
		end)
	)
end
-- The authored egg stands (Workspace.Game.Interactables.Eggs): E opens that egg's pet shop, after the same distance/state checks.
local function bindEggPrompt(prompt: ProximityPrompt, body: BasePart, shopId: string, container: Instance)
	table.insert(
		globalConnections,
		prompt.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if
				prompt.Enabled
				and root
				and body:IsDescendantOf(container)
				and container:IsDescendantOf(workspace)
				and not economy.D.Busy(player)
				and economy.Profiles:Get(player.UserId)
				and (root.Position - body.Position).Magnitude <= prompt.MaxActivationDistance + 6
			then
				economy:Send(player, "", { OpenPetShop = shopId })
			end
		end)
	)
end
local lobby = workspace:FindFirstChild("ScaleGeneratedLobby")
if lobby then
	for _, object in lobby:GetDescendants() do
		if object:IsA("ProximityPrompt") and object.Parent:GetAttribute("ChairShopId") then
			bindChairPrompt(object, object.Parent, object.Parent:GetAttribute("ChairShopId"), lobby)
		elseif object:IsA("ProximityPrompt") and object.Parent:GetAttribute("ContainerId") then
			table.insert(
				globalConnections,
				object.Triggered:Connect(function(player)
					local parent = object.Parent
					local character = player.Character
					local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local containerId = parent and parent:GetAttribute("ContainerId")
					local shopId = parent and parent:GetAttribute("PetShopId")
					local validDestination = (type(shopId) == "string" and Cosmetics.PetShops[shopId] ~= nil)
						or (type(containerId) == "string" and Shop.Containers[containerId] ~= nil)
					if
						object.Enabled
						and parent
						and parent:IsA("BasePart")
						and parent:IsDescendantOf(lobby)
						and lobby:IsDescendantOf(workspace)
						and validDestination
						and characterRoot
						and humanoid
						and humanoid.Health > 0
						and not humanoid.SeatPart
						and not economy.D.Busy(player)
						and economy.Profiles:Get(player.UserId)
						and (characterRoot.Position - parent.Position).Magnitude <= object.MaxActivationDistance + 6
					then
						economy:Send(
							player,
							"",
							if shopId
								then { OpenPetShop = shopId }
								else { OpenContainer = containerId }
						)
					end
				end)
			)
		end
	end
end
local gameFolder = workspace:FindFirstChild("Game")
local interactables = gameFolder and gameFolder:FindFirstChild("Interactables")
local triggers = gameFolder and gameFolder:FindFirstChild("Triggers")
local chairsRoot = (interactables and interactables:FindFirstChild("Chairs"))
	or (gameFolder and gameFolder:FindFirstChild("Chairs"))
	or workspace:FindFirstChild("Chairs")
chairsRoot = chairsRoot and (chairsRoot:FindFirstChild("Chairs") or chairsRoot)
if chairsRoot then
	for _, entry in ChairShop.Bind(chairsRoot, Cosmetics, warn) do
		bindChairPrompt(entry.Prompt, entry.Model, entry.Id, chairsRoot)
		chairFx:Add(entry.Model)
	end
end
-- Workspace.Game.Triggers.AFK.Hitbox: running into it teleports the player to the AFK place.
local afkPortal = AFKPortal.Bind((triggers and triggers:FindFirstChild("AFK")) or (gameFolder and gameFolder:FindFirstChild("AFK")), function(player)
	return economy:SendToAFK(player)
end, warn, Players)
if afkPortal then
	table.insert(globalConnections, afkPortal.Connection)
	table.insert(globalConnections, afkPortal.Leaving)
end
local eggsRoot = (interactables and interactables:FindFirstChild("Eggs")) or (gameFolder and gameFolder:FindFirstChild("Eggs"))
if eggsRoot then
	for _, entry in EggShops.Bind(eggsRoot, Cosmetics, warn) do
		bindEggPrompt(entry.Prompt, entry.Body, entry.ShopId, eggsRoot)
	end
end
-- Living participants stay seated. Eliminated spectators regain jumping and may release their table immediately.
table.insert(globalConnections, leaveSpectatorRemote.OnServerEvent:Connect(function(player, matchId, ...)
	if select("#", ...) ~= 0 or type(matchId) ~= "string" or #matchId > 64 then return end
	if not allowRemote(player, "LeaveSpectator", 0.2) then return end
	tables:LeaveSpectator(player, matchId)
end))
local jumpLocked: { [any]: any } = {}
local seatedNow: { [any]: boolean } = {}
local function restoreJump(lock: any)
	local humanoid = lock and lock.Humanoid
	if humanoid and humanoid.Parent then
		humanoid.JumpPower, humanoid.JumpHeight = lock.JumpPower, lock.JumpHeight
	end
end
local function updateSeatJumpLocks()
	table.clear(seatedNow)
	for _, record in tables.Records do
		local activeMatch = record.Match ~= nil and record.Match.Players ~= nil
		for _, player in world:Occupants(record) do
			local index = activeMatch and table.find(record.Match.Players, player)
			if index and record.Match.Hearts[index] > 0 and not record.Match.Departed[index] then
				seatedNow[player] = true
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local lock = jumpLocked[player]
				if humanoid and (not lock or lock.Humanoid ~= humanoid) then
					restoreJump(lock)
					jumpLocked[player] = {
						Humanoid = humanoid,
						JumpPower = humanoid.JumpPower,
						JumpHeight = humanoid.JumpHeight,
					}
					humanoid.JumpPower, humanoid.JumpHeight = 0, 0
				end
			end
		end
	end
	for player, lock in jumpLocked do
		if not seatedNow[player] then
			jumpLocked[player] = nil
			restoreJump(lock)
		end
	end
end
local accumulated = 0
table.insert(
	globalConnections,
	RunService.Heartbeat:Connect(function(dt)
		economy:Tick(dt)
		-- Every Heartbeat, not the batched/throttled tick below: an anchored part's CFrame never interpolates on
		-- the client, so a full, regular update rate is what keeps the Void's Float turn/bob looking smooth.
		chairFx:Step(dt)
		accumulated += dt
		if accumulated < 0.05 and not seatsDirty then
			return
		end
		local elapsed = accumulated
		accumulated = 0
		seatsDirty = false
		waterRespawn:Step(elapsed)
		npcPopulation:Step(elapsed)
		dismissOrphanedBots()
		tables:Tick()
		-- Freeze bot turns before MatchService checks their deadline, while Roblox's purchase prompt is unresolved.
		updateBotSabotagePromptHolds(workspace:GetServerTimeNow())
		matches:Tick()
		stepBotTurns()
		stepBotSabotages()
		stepBotVotes()
		tableDisplay:Tick(tables.Records, workspace:GetServerTimeNow())
		cosmeticDisplay:Tick(inventory.Profiles, workspace:GetServerTimeNow(), elapsed)
		updateSeatJumpLocks()
	end)
)
game:BindToClose(function()
	leaderboards:Stop()
	waterRespawn:Destroy()
	luckyBlocksTrigger:Destroy()
	for _, connection in globalConnections do
		connection:Disconnect()
	end
	for model in bindings do
		unbind(model)
	end
	npcPopulation:Destroy()
	practiceBots:Destroy()
	tableDisplay:Destroy()
	chairFx:Destroy()
	cosmeticDisplay:Destroy()
	economy:Close()
end)
leaderboards:Start()
print("Scale It Up! server ready; using authored 2v2 / 3v3 / 4v4 tables")

--!strict
local Storage = game:GetService("ReplicatedStorage")
local Controllers = script.Parent.Parent.Controllers
local player = game:GetService("Players").LocalPlayer
-- Bind the owner's grouped HUD before any controller can request UI nodes.
require(Controllers.AuthoredUI).Attach(player:WaitForChild("PlayerGui"), game:GetService("StarterGui"))
-- Gold [VIP] chat tag for VIP players.
local chatTag = require(Controllers.ChatTagController).new(game:GetService("TextChatService"), game:GetService("Players"))
script.Destroying:Connect(function() chatTag.Destroy() end)
-- Allowlisted bot diagnostics. BotTag is server-cloned disabled and revealed only on approved clients.
local botTags = require(Controllers.BotTagController).new(player, game:GetService("CollectionService"))
script.Destroying:Connect(function() botTags:Destroy() end)
-- Server chat news (beats, win and streak milestones) as system messages.
task.spawn(function()
	local Shared = Storage:WaitForChild("Shared")
	local Names = require(Shared.Network.MatchRemotes)
	local remote = Storage:WaitForChild(Names.Folder):WaitForChild(Names.ChatNews, 30)
	if not remote then return end
	local news = require(Controllers.ChatNewsController).new(remote, game:GetService("TextChatService"), require(Shared.Util.ChatNews).Format)
	script.Destroying:Connect(function() news.Destroy() end)
end)
local bootstrapReady, assetsPending = false, 0
local inventory: any
local loading = require(Controllers.LoadingController).new({
	PlayerGui = player:WaitForChild("PlayerGui"), Lighting = game:GetService("Lighting"),
	StarterGui = game:GetService("StarterGui"), RunService = game:GetService("RunService"),
	World = workspace, -- the Game.Triggers/Interactables world signs hide while loading
	Ready = function(age)
		return bootstrapReady and game:IsLoaded() and player:GetAttribute("DataReady") == true
			and inventory ~= nil and inventory.State ~= nil and (assetsPending == 0 or age >= 20)
	end,
})
-- Show the custom overlay before dismissing Roblox's default screen.
game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen()
script.Destroying:Connect(function() loading:Destroy() end)
local function start()
	local Shared = Storage:WaitForChild("Shared")
	local Names = require(Shared.Network.MatchRemotes)
	local remotes = Storage:WaitForChild(Names.Folder)
	local config = require(Shared.Config.GameConfig)
	-- Warm mesh/texture content in the lobby, outside the render/scale callbacks.
	local preloadConnection: RBXScriptConnection?
	if not config.UseLabeledBricks then
		local models = Storage:WaitForChild(config.ObjectPreviewFolder)
		local content = game:GetService("ContentProvider")
		local function preload(model: Instance)
			assetsPending += 1
			task.spawn(function()
				local ok, problem = pcall(function() content:PreloadAsync({model}) end)
				assetsPending -= 1
				if not ok then warn("Scale object content: " .. tostring(problem)) end
			end)
		end
		preloadConnection = models.ChildAdded:Connect(preload)
		for _, model in models:GetChildren() do preload(model) end
	end
	-- No white selection outline on clicked buttons: GUI navigation is a gamepad feature this game does not use.
	pcall(function()
		local guiService = game:GetService("GuiService")
		guiService.AutoSelectGuiEnabled = false
		guiService.GuiNavigationEnabled = false
	end)
	-- Roblox outlines whichever button becomes the selected object in white; clear it the moment it happens.
	local selectionGuard, labelGradients, sfx, alerts, haptic
	pcall(function()
		-- Resize "juice": a short controller vibration alongside the pitched tick/landmark sounds. Optional everywhere.
		local hapticModule = Controllers:FindFirstChild("HapticFeedback")
		if hapticModule then haptic = require(hapticModule).new(game:GetService("HapticService")) end
		local guard = Controllers:FindFirstChild("SelectionGuard")
		if guard then selectionGuard = require(guard).new(game:GetService("GuiService"), game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui"), game:GetService("UserInputService")) end
		-- Sound effects (SoundService.SFX) and the ambience playlist (SoundService.Music), plus UIEffects' button sound.
		local sfxModule = Controllers:FindFirstChild("SfxController")
		local soundService = game:GetService("SoundService")
		local folder = soundService:FindFirstChild("SFX") or soundService:WaitForChild("SFX", 5)
		local music = soundService:FindFirstChild("Music") or soundService:WaitForChild("Music", 3)
		if sfxModule and folder then
			local effects
			local effectsModule = Shared:FindFirstChild("UIEffects")
			if effectsModule then pcall(function() effects = require(effectsModule) end) end
			sfx = require(sfxModule).new({
				Folder = folder, Music = music, Container = soundService, Player = player, PlayerGui = player:WaitForChild("PlayerGui"),
				Input = game:GetService("UserInputService"), RunService = game:GetService("RunService"), UIEffects = effects,
				-- The ambience starts right away, so the loading intro is not silent.
			})
			require(Controllers.UIStyle).Sfx = sfx
			sfx:Play("LoadingIntro")
		end
		-- Alerts clone the authored HUD.Alerts.Template and fade in and out.
		local alertModule = Controllers:FindFirstChild("AlertController")
		local hud = require(Controllers.AuthoredUI).HUD
		if alertModule and hud then
			alerts = require(alertModule).new(hud, game:GetService("RunService"))
			require(Controllers.UIStyle).Alerts = alerts
		end
		-- The Lucky Blocks sign's text slowly cycles through the rainbow.
		local cycle = Controllers:FindFirstChild("LabelGradientController")
		if cycle then labelGradients = require(cycle).new(workspace, game:GetService("RunService")) end
	end)
	local cosmetics = require(Shared.Config.CosmeticCatalog)
	require(Controllers.UIStyle).ChairVisual = require(Shared.Util.ChairVisual)
	local petModels=Storage:WaitForChild("ScalePetPreviews")
	local petVisual=require(Shared.Util.PetVisual)
	local style=require(Controllers.UIStyle)
	style.PetModels,style.PetVisual=petModels,petVisual
	style.AssetStorage,style.BlockVisual=Storage,require(Controllers.BlockVisual)
	assetsPending+=1
	task.spawn(function()
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(petModels:GetChildren()) end)
		assetsPending-=1
	end)
	-- HUD.PurchaseOverlay (optional): fades in with a spinning LoadingCircle for any Robux purchase and back out once
	-- the server confirms it or the purchase prompt closes.
	local purchaseOverlay
	pcall(function() purchaseOverlay = require(Controllers.PurchaseOverlayController).new(require(Controllers.AuthoredUI).HUD) end)
	local marketplace
	pcall(function() marketplace = game:GetService("MarketplaceService") end)
	inventory = require(Controllers.InventoryController).new({
		Player = game:GetService("Players").LocalPlayer,
		Players = game:GetService("Players"), StarterGui = game:GetService("StarterGui"),
		CollectionService = game:GetService("CollectionService"),
		Prompts = game:GetService("ProximityPromptService"), Sfx = sfx, Alerts = alerts, Storage = Storage,
		PurchaseOverlay = purchaseOverlay, Marketplace = marketplace,
		World = workspace, Input = game:GetService("UserInputService"), GuiService = game:GetService("GuiService"), RunService = game:GetService("RunService"),
		Catalog = cosmetics, Remote = Storage:WaitForChild(cosmetics.RemoteName),
		Rewards = require(Shared.Config.RewardCatalog), GroupService = game:GetService("GroupService"),
		MatchState = remotes:WaitForChild(Names.State), View = require(Controllers.InventoryView),
		PlayBot = remotes:WaitForChild(Names.PlayBot),
		Shop = require(Shared.Config.ShopCatalog), HatchController = require(Controllers.HatchController), DetailsController = require(Controllers.PlayerDetailsController),
	})
	local followers = require(Controllers.PetFollowerController).new(game:GetService("Players"), workspace, game:GetService("RunService"), cosmetics,petModels,petVisual,require(Shared.Util.PetEffects),Storage)
	-- Each egg stand's CyclePets viewport shows a rotating pet from that egg's own loot pool.
	local eggStandPreviews = require(Controllers.EggStandPreviewController).new(workspace, game:GetService("RunService"), cosmetics)
	local titleShimmer = require(Controllers.TitleGradientController).new(workspace, game:GetService("RunService"))
	local spectatorDisplay = require(Controllers.SpectatorDisplayController).new(game:GetService("Players").LocalPlayer, game:GetService("CollectionService"), require(Shared.Config.GameConfig).TableTag)
	local displayConnection = game:GetService("RunService").RenderStepped:Connect(function(dt) spectatorDisplay:Step(dt) end)
	local controller = require(Controllers.MatchController).new({
		Player = game:GetService("Players").LocalPlayer,
		Players = game:GetService("Players"),
		Storage = Storage, World = workspace, StarterGui = game:GetService("StarterGui"),
		RunService = game:GetService("RunService"), Input = game:GetService("UserInputService"), GuiService = game:GetService("GuiService"),
		Config = require(Shared.Config.GameConfig), Math = require(Shared.Util.ScaleMath),
		State = remotes:WaitForChild(Names.State), Guess = remotes:WaitForChild(Names.Guess), Lock = remotes:WaitForChild(Names.Lock), Ready = remotes:WaitForChild(Names.Ready),
		Sfx = sfx, Alerts = alerts, Haptic = haptic, PrizeRoll = require(Shared.Util.PrizeRoll), Hint = remotes:WaitForChild(Names.Hint), Heart = remotes:WaitForChild(Names.Heart),
		-- Ink, troll effects and hint ranges draw inside the authored HUD.Effects frame when it exists.
		Effects=function() local hud=require(Controllers.AuthoredUI).HUD;return hud and hud:FindFirstChild("Effects") end,
		ModeVote=remotes:WaitForChild(Names.ModeVote),ModeVoteView=require(Controllers.ModeVoteView),
		LeaveSpectator = remotes:WaitForChild(Names.LeaveSpectator),
		InkSplat = remotes:WaitForChild(Names.InkSplat), InkSplatController = require(Controllers.InkSplatController), SabotageController = require(Controllers.SabotageEffectController),
		UIController = require(Controllers.UIController), ScaleController = require(Controllers.ScaleController),
		PreviewController = require(Controllers.PreviewController), CameraController = require(Controllers.CameraController),
		ReactionController = require(Controllers.ReactionController), ReactionCycle = require(Controllers.ReactionCycle),
		TransitionController = require(Controllers.TransitionController),
	})
	local afkSign = require(Controllers.AFKSignController).new(workspace, game:GetService("RunService"))
	local eggTags = require(Controllers.EggTagController).new(workspace, game:GetService("RunService"))
	local chairTags = require(Controllers.ChairTagController).new(
		workspace,
		cosmetics,
		game:GetService("RunService"),
		function() return inventory and inventory.State end,
		nil,
		function() return controller:IsInGame() end
	)
	local cashPrivacy = require(Controllers.CashPrivacyController).new(player, workspace, function() return controller.Snapshot end, game:GetService("RunService"))
	local invites = require(Controllers.FriendInviteController).new({
		Player=player, Players=game:GetService("Players"), SocialService=game:GetService("SocialService"),
		RunService=game:GetService("RunService"), Spawn=task.spawn, View=require(Controllers.FriendInviteView),
		-- The Cash reward shown is this player's current one (scaled to their Cash by the server).
		RewardCash=function()
			local state=inventory and inventory.State
			return (state and state.InviteCash) or require(Shared.Config.RewardCatalog).InviteCash
		end,
		GameId=game.GameId, PlaceIds={[game.PlaceId]=true,[95238940314216]=true,[97619904048927]=true},
		Rewarded=function(id)return inventory.State and inventory.State.InviteRewards and inventory.State.InviteRewards[tostring(id)]==true end,
		Ready=function() return bootstrapReady and loading.Destroyed and player:GetAttribute("DataReady")==true end,
		CanShow=function()
			local character=player.Character
			local humanoid=character and character:FindFirstChildOfClass("Humanoid")
			return controller.Snapshot~=nil and controller.Snapshot.State=="IDLE"
				and not controller.Transition:IsActive() and not inventory.Busy and inventory.Page==nil and inventory.Hatch.Reward==nil
				and not game:GetService("GuiService").MenuIsOpen and humanoid~=nil and humanoid.Health>0
		end,
	})
	-- Teleporting to/from the AFK world: the lobby HUD slides away (InventoryController) and the loading screen covers
	-- everything until the teleport happens; a failed teleport clears Traveling, so it fades out and the UI returns.
	local travelLoading
	local function onTraveling()
		if player:GetAttribute("Traveling") ~= true or not loading.Destroyed then return end
		if travelLoading and not travelLoading.Destroyed then return end
		travelLoading = require(Controllers.LoadingController).new({
			PlayerGui = player:WaitForChild("PlayerGui"), Lighting = game:GetService("Lighting"),
			StarterGui = game:GetService("StarterGui"), RunService = game:GetService("RunService"),
			MinimumSeconds = 0, World = workspace,
			Ready = function() return player:GetAttribute("Traveling") ~= true end,
		})
	end
	local travelConnection = player:GetAttributeChangedSignal("Traveling"):Connect(onTraveling)
	script.Destroying:Connect(function()
		travelConnection:Disconnect()
		if travelLoading then travelLoading:Destroy() end
		if preloadConnection then preloadConnection:Disconnect() end
		if selectionGuard then selectionGuard:Destroy() end
		if labelGradients then labelGradients:Destroy() end
		if sfx then sfx:Destroy() end
		if alerts then alerts:Destroy() end
		if haptic then haptic:Destroy() end
		eggStandPreviews:Destroy()
		afkSign:Destroy();eggTags:Destroy();chairTags:Destroy();cashPrivacy:Destroy();titleShimmer:Destroy();invites:Destroy();displayConnection:Disconnect();spectatorDisplay:Destroy();followers:Destroy();controller:Destroy();inventory:Destroy()
	end)
	bootstrapReady = true
end
local ok, problem = xpcall(start, debug.traceback)
if not ok then loading:Destroy();error(problem) end

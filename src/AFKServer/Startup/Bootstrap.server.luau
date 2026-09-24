--!strict
local Storage = game:GetService("ReplicatedStorage")
local Shared = Storage:WaitForChild("AFKShared")
local Root = script.Parent.Parent
local Config = require(Shared.Config.AFKConfig)
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() or game.PlaceId == Config.PlaceId, "AFKServer must only run in the AFK place")
local Players = game:GetService("Players")
-- Real pet models for the reward viewports (ServerStorage.Pets.Active -> ReplicatedStorage.AFKPreviews.Pets).
local _, missingPets = require(Root.World.AFKPreviews).Build(
	game:GetService("ServerStorage"),
	Storage,
	Config,
	require(Shared.Config.CosmeticCatalog)
)
if #missingPets > 0 then
	warn("AFK World: reward pets not found in ServerStorage.Pets.Active: " .. table.concat(missingPets, ", "))
end
local runtime = require(Root.Services.AFKRuntime).new({
	Players = Players, Storage = Storage, World = workspace, RunService = RunService,
	DataStore = game:GetService("DataStoreService"), Http = game:GetService("HttpService"),
	Teleport = game:GetService("TeleportService"), Marketplace = game:GetService("MarketplaceService"),
	Config = Config, DataConfig = require(Root.Config.DataConfig), Catalog = require(Shared.Config.CosmeticCatalog), PlaceId = game.PlaceId,
	Wealth = require(Shared.Util.WealthScale), -- AFK Cash/Gem prizes grow with the Cash a player holds
})
local function add(player: Player)
	-- No generated/wrapper scenery: this is the normal authored map. An optional AFKSpawn (anywhere in it) picks
	-- the spot; otherwise Roblox's own default spawn behavior already places players at the map's normal spawn.
	local spawn = workspace:FindFirstChild("AFKSpawn", true)
	if spawn and spawn:IsA("SpawnLocation") then player.RespawnLocation = spawn end
	runtime:Anchor(player)
	task.spawn(function() runtime:Add(player) end)
end
table.insert(runtime.Connections, Players.PlayerAdded:Connect(add))
table.insert(runtime.Connections, Players.PlayerRemoving:Connect(function(player) runtime:Remove(player) end))
table.insert(runtime.Connections, RunService.Heartbeat:Connect(function(dt) runtime:Tick(dt) end))
for _, player in Players:GetPlayers() do add(player) end
game:BindToClose(function() runtime:Close() end)

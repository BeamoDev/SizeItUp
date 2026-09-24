--!strict
local Storage=game:GetService("ReplicatedStorage")
local Shared=Storage:WaitForChild("AFKShared")
local Config=require(Shared.Config.AFKConfig)
local Root=script.Parent.Parent
local controller=require(Root.Controllers.AFKController).new({
	Player=game:GetService("Players").LocalPlayer,World=workspace,RunService=game:GetService("RunService"),
	Remote=Storage:WaitForChild(Config.RemoteName),Config=Config,View=require(Root.Interface.AFKView),
	-- Reward models for the viewports: AFKPreviews (pets) and Assets (chairs, lucky blocks).
	Storage=Storage,Catalog=require(Shared.Config.CosmeticCatalog),Lighting=game:GetService("Lighting"),
	-- Reward and countdown sounds (played at AFKConfig.SoundVolume).
	Sounds=game:GetService("SoundService"):FindFirstChild("SFX") or game:GetService("SoundService"):WaitForChild("SFX",5),
})
script.Destroying:Connect(function() controller:Destroy() end)

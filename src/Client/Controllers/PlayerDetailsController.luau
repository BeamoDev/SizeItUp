--!strict
local Style = require(script.Parent.UIStyle)
local PlayerDetailsController = {}
PlayerDetailsController.__index = PlayerDetailsController
local function targetCash(target: any): number
	local value=target and target.CashSource and target.CashSource:GetAttribute("Cash")
	return if type(value)=="number" and value==value then math.max(0,math.floor(value)) else 0
end

-- The nearby-player billboard is the authored ReplicatedStorage.Assets.UI.PlayerDetails (a BillboardGui with Details and
-- Steal buttons): it is cloned into PlayerGui here and nothing about it is created in code. Without that asset the
-- controller does nothing.
function PlayerDetailsController.BindBillboard(playerGui: PlayerGui, storage: any?)
	local gui=playerGui:FindFirstChild("PlayerDetails")
	local owned=false
	if not gui then
		local assets=storage and storage:FindFirstChild("Assets")
		local ui=assets and assets:FindFirstChild("UI")
		local template=ui and ui:FindFirstChild("PlayerDetails")
		if not template then
			warn("Missing authored UI: ReplicatedStorage.Assets.UI.PlayerDetails (nearby-player buttons are off)")
			return nil,nil,nil,false
		end
		gui=template:Clone();owned=true
	end
	assert(gui:IsA("BillboardGui"),"PlayerDetails must be a BillboardGui")
	gui.Enabled,gui.ResetOnSpawn,gui.Active=false,false,true
	local function button(name: string,text: string)
		local item=gui:FindFirstChild(name,true)
		assert(item and item:IsA("GuiButton"),"Missing authored UI: PlayerDetails."..name.." (a button)")
		Style.Caption(item,text)
		return item
	end
	local details,steal=button("Details","Profile"),button("Steal","Steal")
	gui.Parent=playerGui
	return gui,details,steal,owned
end
function PlayerDetailsController.new(d: any, action: any)
	local gui,details,steal,owned=PlayerDetailsController.BindBillboard(d.Player:WaitForChild("PlayerGui"),d.Storage)
	if not gui then return setmetatable({D=d,Inert=true,Connections={},Timer=0,PetPrompts={}},PlayerDetailsController) end
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	local self: any=setmetatable({
		D=d,Gui=gui,Steal=steal,OwnedGui=owned,Timer=0,Action=action,PetPrompts={},
		Candidates={},Raycast=raycast,RaycastFilter={},
	},PlayerDetailsController)
	local function request(kind)
		if not self.Blocked and gui.Enabled and self.Target and #self.PetPrompts==0 and (kind~="Steal" or targetCash(self.Target)>0) then action(kind,{UserId=self.Target.UserId}) end
	end
	self.Connections={details.Activated:Connect(function() request("Profile") end),steal.Activated:Connect(function() request("Steal") end),d.Input.InputBegan:Connect(function(input,processed)
		if processed or not gui.Enabled or #self.PetPrompts>0 then return end
		if input.KeyCode==Enum.KeyCode.F then request("Profile") elseif input.KeyCode==Enum.KeyCode.E then request("Steal") end
	end)}
	if d.Prompts then
		table.insert(self.Connections,d.Prompts.PromptShown:Connect(function(prompt)
			if prompt.Parent and (prompt.Parent:GetAttribute("PetShopId") or prompt.Parent:GetAttribute("ContainerId") or prompt.Parent:GetAttribute("ChairShopId")) and not table.find(self.PetPrompts,prompt) then
				table.insert(self.PetPrompts,prompt);self.Target=nil;gui.Enabled=false
			end
		end))
		table.insert(self.Connections,d.Prompts.PromptHidden:Connect(function(prompt)
			local index=table.find(self.PetPrompts,prompt);if index then table.remove(self.PetPrompts,index) end
		end))
	end
	return self
end
function PlayerDetailsController.Step(self: any, dt: number, blocked: boolean)
	if self.Inert then return end
	-- PromptHidden is normally paired with PromptShown, but a streamed-out/destroyed prompt may disappear without it.
	-- Prune those references so one stale shop prompt cannot suppress nearby-player actions for the rest of the session.
	for index = #self.PetPrompts, 1, -1 do
		if not self.PetPrompts[index].Parent then table.remove(self.PetPrompts, index) end
	end
	self.Blocked=blocked
	if blocked or #self.PetPrompts>0 then self.Target=nil;self.Gui.Enabled=false;self.Gui.Adornee=nil;return end
	self.Timer+=dt;if self.Timer<0.12 then return end;self.Timer=0
	self.Target=nil;self.Gui.Enabled=false;self.Gui.Adornee=nil
	local own=self.D.Player.Character;local root=own and own:FindFirstChild("HumanoidRootPart");local camera=self.D.World.CurrentCamera
	if not root or not camera then return end
	local maximumDistanceSquared=12*12
	local candidates=self.Candidates
	table.clear(candidates)
	local function consider(character: Model?,userId: number?,cashSource: Instance)
		local head=character and character:FindFirstChild("Head");local target=character and character:FindFirstChild("HumanoidRootPart")
		local humanoid=character and character:FindFirstChildOfClass("Humanoid")
		if not userId or not head or not head:IsA("BasePart") or not target or not target:IsA("BasePart") or not humanoid or humanoid.Health<=0 then return end
		local offset=target.Position-root.Position
		local distanceSquared=offset:Dot(offset)
		local _,visible=camera:WorldToViewportPoint(head.Position)
		if distanceSquared<maximumDistanceSquared and visible then
			table.insert(candidates,{DistanceSquared=distanceSquared,UserId=userId,Character=character,CashSource=cashSource,Head=head})
		end
	end
	for _,player in self.D.Players:GetPlayers() do
		if player~=self.D.Player then consider(player.Character,player.UserId,player) end
	end
	if self.D.CollectionService then
		for _,character in self.D.CollectionService:GetTagged("ScalePopulationNPC") do
			if character:IsA("Model") and character:IsDescendantOf(self.D.World) then
				local userId=character:GetAttribute("ScaleBotUserId")
				consider(character,if type(userId)=="number" then userId else nil,character)
			end
		end
	end
	-- Test visibility nearest-first. The previous scan could raycast every successively closer candidate; this normally
	-- needs one raycast and remains equivalent when the closest character is behind an obstacle.
	table.sort(candidates,function(a,b) return a.DistanceSquared<b.DistanceSquared end)
	for _,candidate in candidates do
		local filter=self.RaycastFilter
		filter[1],filter[2]=own,candidate.Character
		self.Raycast.FilterDescendantsInstances=filter
		if not self.D.World:Raycast(camera.CFrame.Position,candidate.Head.Position-camera.CFrame.Position,self.Raycast) then
			self.Target=candidate
			self.Gui.Adornee=candidate.Head
			break
		end
	end
	self.Gui.Enabled=self.Target~=nil
	if self.Target then
		local cash=targetCash(self.Target)
		-- Steal only shows (as "Steal $1234") while the player has Cash to take.
		self.Steal.Visible=cash>0
		self.Steal.Active=cash>0
		if cash>0 then Style.Caption(self.Steal,"Steal "..Style.Money(cash)) end
	end
end
function PlayerDetailsController.Destroy(self: any)
	for _,connection in self.Connections do connection:Disconnect() end
	if self.Inert then return end
	self.Target=nil;self.Gui.Enabled=false;self.Gui.Adornee=nil
	table.clear(self.Candidates)
	table.clear(self.RaycastFilter)
	self.Raycast.FilterDescendantsInstances = {}
	if self.OwnedGui then self.Gui:Destroy() end
end
return PlayerDetailsController

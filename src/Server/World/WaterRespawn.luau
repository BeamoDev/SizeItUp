--!strict
-- Authored water is a return trigger, not damage or a character reload.
local WaterRespawn = {}
WaterRespawn.__index = WaterRespawn

local function footClearance(character: Model, humanoid: Humanoid, root: BasePart): number
	local leg = character:FindFirstChild("Left Leg") -- R6's HipHeight excludes its legs.
	return humanoid.HipHeight + root.Size.Y / 2 + (if leg and leg:IsA("BasePart") then leg.Size.Y else 0)
end

-- Segment against an oriented water volume. Feet can reach a thin surface while the touch-enabled root stays dry.
local function crossesWater(water: BasePart, bottom: Vector3, top: Vector3, radius: number): boolean
	local start = water.CFrame:PointToObjectSpace(bottom)
	local delta = water.CFrame:VectorToObjectSpace(top - bottom)
	local half = water.Size * 0.5 + Vector3.new(radius, 0, radius)
	local enter, leave = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local origin, direction, extent = start[axis], delta[axis], half[axis]
		if math.abs(direction) < 1e-6 then
			if math.abs(origin) > extent then return false end
		else
			local a, b = (-extent - origin) / direction, (extent - origin) / direction
			enter, leave = math.max(enter, math.min(a, b)), math.min(leave, math.max(a, b))
			if enter > leave then return false end
		end
	end
	return true
end

local function supportedAbove(water: BasePart, support: RaycastResult?): boolean
	return support ~= nil and support.Instance ~= water and support.Material ~= Enum.Material.Water
		and water.CFrame:PointToObjectSpace(support.Position).Y >= water.Size.Y * 0.5 - 0.01
end

function WaterRespawn.GroundParams(self: any, character: Model): RaycastParams
	local excluded: { Instance } = { character }
	local runtime = self.World:FindFirstChild("Runtime")
	if runtime then table.insert(excluded, runtime) end
	for _, player in self.Players:GetPlayers() do
		if player.Character then table.insert(excluded, player.Character) end
	end
	for _, bot in self.CollectionService:GetTagged("ScaleBot") do table.insert(excluded, bot) end
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, excluded
	params.RespectCanCollide, params.IgnoreWater = true, false
	return params
end

function WaterRespawn.Landing(self: any, marker: BasePart, clearance: number, root: BasePart, params: RaycastParams): CFrame?
	local cf, size = marker.CFrame, marker.Size
	local halfHeight = (math.abs(cf.RightVector.Y)*size.X + math.abs(cf.UpVector.Y)*size.Y + math.abs(cf.LookVector.Y)*size.Z) / 2
	local start = cf.Position + Vector3.yAxis * (halfHeight + self.Config.LandingSearchUp)
	local hit = self.World:Raycast(start, -Vector3.yAxis * (self.Config.LandingSearchUp + self.Config.LandingSearchDown), params)
	if not hit or hit.Material == Enum.Material.Water or self.Parts[hit.Instance] or hit.Normal.Y < 0.65 then return nil end
	-- RespawnPoints can be non-collidable markers below the floor. Place feet above the actual supporting surface.
	local position = Vector3.new(cf.Position.X, math.max(hit.Position.Y, cf.Position.Y + halfHeight) + clearance + self.Config.LandingClearance, cf.Position.Z)
	-- Validate where the feet will settle as well as the raised teleport pose; a lift must not hide wet ground.
	local bottom = hit.Position - Vector3.yAxis * self.Config.BotSurfaceMargin
	local top = position + Vector3.yAxis * (root.Size.Y * 0.5 + 2)
	for water in self.Parts do
		if crossesWater(water, bottom, top, math.min(root.Size.X, root.Size.Z) * 0.5) and not supportedAbove(water, hit) then return nil end
	end
	-- A raised marker must not put the torso/head inside a ceiling above its supporting floor.
	if self.World:Raycast(hit.Position + Vector3.yAxis * 0.05, top - hit.Position, params) then return nil end
	local facing = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if facing.Magnitude < 0.01 then facing = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(position, position + facing)
end

function WaterRespawn.Destination(self: any, character: Model, humanoid: Humanoid, root: BasePart, player: Player?, blocked: any): (BasePart?, CFrame?)
	local params = self:GroundParams(character)
	local clearance = footClearance(character, humanoid, root)
	local function nearest(candidates: { BasePart }): (BasePart?, CFrame?)
		table.sort(candidates, function(a, b) return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude end)
		for _, candidate in candidates do
			if not blocked[candidate] then
				local landing = self:Landing(candidate, clearance, root, params)
				if landing then return candidate, landing end
			end
		end
		return nil, nil
	end
	local markers = {}
	for marker in self.Markers do
		if marker:IsDescendantOf(self.World) then table.insert(markers, marker) end
	end
	local marker, landing = nearest(markers)
	if marker then return marker, landing end
	local assigned = player and player.RespawnLocation
	if assigned and assigned:IsDescendantOf(self.World) and not blocked[assigned] then
		local target = self:Landing(assigned, clearance, root, params)
		if target then return assigned, target end
	end
	local spawns = {}
	for _, instance in self.World:GetDescendants() do
		if instance:IsA("SpawnLocation") and instance.Enabled then table.insert(spawns, instance) end
	end
	return nearest(spawns)
end

function WaterRespawn.Touch(self: any, water: BasePart, hit: BasePart, swept: boolean?): boolean?
	if not self.Parts[water] or not water:IsDescendantOf(self.World) then return end
	local character: any = hit.Parent
	local player
	local bot = false
	while character and character ~= self.World do
		if character:IsA("Model") then
			player = self.Players:GetPlayerFromCharacter(character)
			bot = self.CollectionService:HasTag(character, "ScaleBot")
		end
		if player or bot then break end
		character = character.Parent
	end
	if player then
		if player.Parent ~= self.Players or player.Character ~= character then return end
	elseif not bot or not character:IsDescendantOf(self.World) or character:FindFirstAncestorOfClass("WorldModel") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
	local now = self.World:GetServerTimeNow()
	if now < (self.Cooldowns[character] or 0) then return end
	local clearance = footClearance(character, humanoid, root)
	local bottom = root.Position - Vector3.yAxis * (clearance + self.Config.BotSurfaceMargin)
	local top = root.Position + Vector3.yAxis * root.Size.Y * 0.5
	-- Queued Touched callbacks can arrive after a teleport. Require contact at the current location.
	if not swept and not crossesWater(water, bottom, top, math.min(root.Size.X, root.Size.Z) * 0.5)
		and not crossesWater(water, hit.Position, hit.Position, 0) then return end
	local support = self.World:Raycast(root.Position, bottom - root.Position, self:GroundParams(character))
	if supportedAbove(water, support) then return end
	local recovery = self.Recoveries[character]
	if not recovery or now - recovery.At > self.Config.RepeatWindowSeconds
		or (root.Position - recovery.Position).Magnitude > self.Config.RepeatRadiusStuds then
		recovery = { Blocked = {} }
	elseif recovery.Destination then
		recovery.Blocked[recovery.Destination] = true
	end
	local destination, target = self:Destination(character, humanoid, root, player, recovery.Blocked)
	if not destination or not target then
		-- Report missing safe authored land rather than teleport repeatedly to the same failed spot.
		self.Cooldowns[character] = now + 0.75
		if not recovery.Warned then warn("Scale water recovery: no safe RespawnPoint or enabled SpawnLocation for " .. character.Name) end
		recovery.Warned, recovery.At, recovery.Position = true, now, root.Position
		self.Recoveries[character] = recovery
		return
	end
	recovery.Destination, recovery.Position, recovery.At, recovery.Warned = destination, target.Position, now, nil
	self.Recoveries[character] = recovery
	self.Cooldowns[character] = now + 0.75
	self.PreviousFeet[character] = nil

	-- Invalidate the route/seating coroutine before teleporting; MoveTo alone cannot stop its next waypoint.
	if bot and self.BeforeBotReturn then self.BeforeBotReturn(character, target.Position) end
	if self.Bindings then
		self.Bindings:DetachSeat(character, humanoid)
	else
		local seat = humanoid.SeatPart
		humanoid.Sit = false
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld and weld:IsA("Weld") and weld.Part1 and weld.Part1:IsDescendantOf(character) then weld:Destroy() end
	end
	character:PivotTo(target * root.CFrame:Inverse() * character:GetPivot())
	if bot then
		-- Cancel the path that led into the water so the NPC does not immediately walk back toward it.
		humanoid:Move(Vector3.zero)
		humanoid:MoveTo(root.Position)
		humanoid.EvaluateStateMachine, humanoid.PlatformStand, humanoid.AutoRotate = true, false, true
		humanoid.Jump = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		character:SetAttribute("ScaleNPCRecoveryReason", "Water")
		character:SetAttribute("ScaleNPCWaterDestination", destination:GetFullName())
		character:SetAttribute("ScaleNPCWaterReturnCount", (character:GetAttribute("ScaleNPCWaterReturnCount") or 0) + 1)
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
	return true
end

function WaterRespawn.Step(self: any, dt: number)
	self.Elapsed += dt
	if self.Elapsed < self.Config.BotCheckSeconds then return end
	self.Elapsed = 0
	if not next(self.Parts) then return end
	for _, character in self.CollectionService:GetTagged("ScaleBot") do
		if not character:IsA("Model") or not character:IsDescendantOf(self.World)
			or character:FindFirstAncestorOfClass("WorldModel") then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then continue end
		local bottom = root.Position - Vector3.yAxis * (footClearance(character, humanoid, root) + self.Config.BotSurfaceMargin)
		local top = root.Position + Vector3.yAxis * root.Size.Y * 0.5
		local previous = self.PreviousFeet[character]
		self.PreviousFeet[character] = { Root = root, Position = bottom }
		local swept = previous and previous.Root == root
			and (previous.Position - bottom).Magnitude <= self.Config.BotSweepMaxStuds
		local radius = math.min(root.Size.X, root.Size.Z) * 0.5
		for water in self.Parts do
			-- Sweep between checks as well, so a falling rig cannot skip a thin Water surface in one tick.
			if crossesWater(water, bottom, top, radius)
				or (swept and crossesWater(water, previous.Position, bottom, radius)) then
				if self:Touch(water, root, true) then break end
			end
		end
	end
end

function WaterRespawn.Bind(self: any, object: Instance)
	local map = self.World:FindFirstChild("Map")
	if object:IsA("BasePart") and object.Name == "RespawnPoint"
		and ((map and object:IsDescendantOf(map)) or object.Parent == self.World) then self.Markers[object] = true end
	-- Only the Water surface, not Deco or the RespawnPoint inside its model.
	if self.Parts[object] or not object:IsA("BasePart") or object.Name ~= "Water"
		or not map or not object:IsDescendantOf(map) then return end
	local entry = { CanTouch = object.CanTouch }
	self.Parts[object] = entry
	object.CanTouch = true
	entry.Connection = object.Touched:Connect(function(hit) self:Touch(object, hit) end)
end

function WaterRespawn.Unbind(self: any, object: Instance)
	self.Markers[object] = nil
	local entry = self.Parts[object]
	if not entry then return end
	entry.Connection:Disconnect()
	object.CanTouch = entry.CanTouch
	self.Parts[object] = nil
end

function WaterRespawn.new(world: Workspace, players: Players, collectionService: any, config: any)
	local self = setmetatable({ World = world, Players = players, CollectionService = collectionService, Config = config, Elapsed = 0, Markers = {}, Parts = {}, Cooldowns = setmetatable({}, {__mode="k"}), PreviousFeet = setmetatable({}, {__mode="k"}), Recoveries = setmetatable({}, {__mode="k"}), Connections = {} }, WaterRespawn)
	table.insert(self.Connections, world.DescendantAdded:Connect(function(object) self:Bind(object) end))
	table.insert(self.Connections, world.DescendantRemoving:Connect(function(object) self:Unbind(object) end))
	for _, object in world:GetDescendants() do self:Bind(object) end
	return self
end

function WaterRespawn.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	for object in self.Parts do self:Unbind(object) end
	table.clear(self.Connections)
	table.clear(self.Cooldowns)
	table.clear(self.Markers)
	table.clear(self.PreviousFeet)
	table.clear(self.Recoveries)
	self.BeforeBotReturn, self.Bindings = nil, nil
end

return WaterRespawn

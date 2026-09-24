--!strict
-- Authored water is a return trigger, not damage or a character reload.
local WaterRespawn = {}
WaterRespawn.__index = WaterRespawn

function WaterRespawn.Destination(self: any, water: BasePart, player: Player?): BasePart?
	local ancestor = water.Parent
	while ancestor and ancestor ~= self.World do
		local marker = ancestor:FindFirstChild("RespawnPoint", true)
		if marker and marker:IsA("BasePart") then return marker end
		ancestor = ancestor.Parent
	end
	local marker = self.World:FindFirstChild("RespawnPoint")
	if marker and marker:IsA("BasePart") then return marker end
	local spawn = player and player.RespawnLocation
	if spawn and spawn:IsDescendantOf(self.World) then return spawn end
	return self.World:FindFirstChildWhichIsA("SpawnLocation", true)
end

function WaterRespawn.Touch(self: any, water: BasePart, hit: BasePart)
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
	elseif not bot or not character:IsDescendantOf(self.World) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
	local now = self.World:GetServerTimeNow()
	if now < (self.Cooldowns[character] or 0) then return end
	local destination = self:Destination(water, player)
	if not destination then return end
	self.Cooldowns[character] = now + 0.75

	local seat = humanoid.SeatPart
	humanoid.Sit = false
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and weld.Part1 and weld.Part1:IsDescendantOf(character) then weld:Destroy() end
	local leg = character:FindFirstChild("Left Leg") -- R6's HipHeight excludes its legs.
	local clearance = humanoid.HipHeight + root.Size.Y / 2 + (if leg and leg:IsA("BasePart") then leg.Size.Y else 0) + 0.15
	local cf, size = destination.CFrame, destination.Size
	local halfHeight = (math.abs(cf.RightVector.Y)*size.X + math.abs(cf.UpVector.Y)*size.Y + math.abs(cf.LookVector.Y)*size.Z) / 2
	local target = cf + Vector3.new(0, halfHeight + clearance, 0)
	character:PivotTo(target * root.CFrame:Inverse() * character:GetPivot())
	if bot then
		-- Cancel the path that led into the water so the NPC does not immediately walk back toward it.
		humanoid:Move(Vector3.zero)
		humanoid:MoveTo(root.Position)
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
end

function WaterRespawn.Bind(self: any, object: Instance)
	local map = self.World:FindFirstChild("Map")
	-- Only the Water surface, not Deco or the RespawnPoint inside its model.
	if self.Parts[object] or not object:IsA("BasePart") or object.Name ~= "Water"
		or not map or not object:IsDescendantOf(map) then return end
	local entry = { CanTouch = object.CanTouch }
	self.Parts[object] = entry
	object.CanTouch = true
	entry.Connection = object.Touched:Connect(function(hit) self:Touch(object, hit) end)
end

function WaterRespawn.Unbind(self: any, object: Instance)
	local entry = self.Parts[object]
	if not entry then return end
	entry.Connection:Disconnect()
	object.CanTouch = entry.CanTouch
	self.Parts[object] = nil
end

function WaterRespawn.new(world: Workspace, players: Players, collectionService: any)
	local self = setmetatable({ World = world, Players = players, CollectionService = collectionService, Parts = {}, Cooldowns = setmetatable({}, {__mode="k"}), Connections = {} }, WaterRespawn)
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
end

return WaterRespawn

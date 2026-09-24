--!strict
-- Walking into the authored LuckyBlocksTrigger (Workspace.Game.Triggers.LuckyBlocksTrigger, a part or a model of parts) opens the
-- Lucky Blocks menu for that player. It fires once per visit: the player has to step away before it can open again, so
-- closing the menu while still standing in the trigger does not reopen it. The trigger keeps its authored look.
local LuckyBlocksTrigger = {}
LuckyBlocksTrigger.__index = LuckyBlocksTrigger

local TRIGGER_NAME = "LuckyBlocksTrigger"
local RELEASE_DELAY = 0.35

-- The player whose character this part belongs to, if any.
function LuckyBlocksTrigger.PlayerOf(self: any, hit: Instance): (Player?, Model?)
	local node: any = hit.Parent
	while node and node ~= self.World do
		if node:IsA("Model") then
			local player = self.Players:GetPlayerFromCharacter(node)
			if player then return player, node end
		end
		node = node.Parent
	end
	return nil, nil
end

function LuckyBlocksTrigger.Touch(self: any, hit: BasePart)
	local player, character = self:PlayerOf(hit)
	if not player or not character or player.Parent ~= self.Players or player.Character ~= character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if self.Active[player] then return end
	self.Active[player] = true
	self.Open(player)
end

-- After the last touch ends, the visit is over once none of the player's parts are still in the trigger.
function LuckyBlocksTrigger.Release(self: any, player: Player)
	local character = player.Character
	if character then
		for part in self.Parts do
			for _, touching in part:GetTouchingParts() do
				if touching:IsDescendantOf(character) then return end
			end
		end
	end
	self.Active[player] = nil
end

function LuckyBlocksTrigger.Bind(self: any, object: Instance)
	if not object:IsA("BasePart") or self.Parts[object] then return end
	local root: Instance? = object
	local inside = false
	while root and root ~= self.World do
		if root.Name == TRIGGER_NAME then inside = true;break end
		root = root.Parent
	end
	if not inside then return end
	local entry: any = { CanTouch = object.CanTouch }
	self.Parts[object] = entry
	object.CanTouch = true
	entry.Touched = object.Touched:Connect(function(hit: BasePart) self:Touch(hit) end)
	entry.Ended = object.TouchEnded:Connect(function(hit: BasePart)
		local player = self:PlayerOf(hit)
		if player then task.delay(RELEASE_DELAY, function() self:Release(player) end) end
	end)
end

function LuckyBlocksTrigger.Unbind(self: any, object: Instance)
	local entry = self.Parts[object]
	if not entry then return end
	entry.Touched:Disconnect()
	entry.Ended:Disconnect()
	;(object :: BasePart).CanTouch = entry.CanTouch
	self.Parts[object] = nil
end

function LuckyBlocksTrigger.new(world: any, players: any, open: (Player) -> ())
	local self: any = setmetatable({ World = world, Players = players, Open = open, Parts = {}, Active = {}, Connections = {} }, LuckyBlocksTrigger)
	table.insert(self.Connections, world.DescendantAdded:Connect(function(object: Instance) self:Bind(object) end))
	table.insert(self.Connections, world.DescendantRemoving:Connect(function(object: Instance) self:Unbind(object) end))
	table.insert(self.Connections, players.PlayerRemoving:Connect(function(player: Player) self.Active[player] = nil end))
	for _, object in world:GetDescendants() do self:Bind(object) end
	return self
end

function LuckyBlocksTrigger.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	for object in self.Parts do self:Unbind(object) end
	table.clear(self.Active)
end

return LuckyBlocksTrigger

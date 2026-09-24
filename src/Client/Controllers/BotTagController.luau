--!strict
-- Every bot owns a disabled server-cloned BotTag. Enabling it here changes only this client's replicated copy,
-- so ordinary players never see the diagnostic marker.
local BotTagController = {}
BotTagController.__index = BotTagController

local ALLOWED_USER_IDS = {
	[1790165114] = true,
	[2044711693] = true,
}

local function setEnabled(character: Instance, enabled: boolean)
	local tag = character:FindFirstChild("BotTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = enabled
	end
end

function BotTagController.new(player: Player, collectionService: any)
	local self: any = setmetatable({
		Connections = {},
		CharacterConnections = {},
		CollectionService = collectionService,
	}, BotTagController)
	if not ALLOWED_USER_IDS[player.UserId] then
		return self
	end
	local function track(character: Instance)
		if self.CharacterConnections[character] then
			return
		end
		setEnabled(character, true)
		-- Collection tags and descendants can arrive in separate replication packets. Catch a late BotTag without
		-- polling every frame or scanning Workspace repeatedly.
		self.CharacterConnections[character] = character.ChildAdded:Connect(function(child)
			if child.Name == "BotTag" and child:IsA("BillboardGui") then
				child.Enabled = true
			end
		end)
	end
	local function untrack(character: Instance)
		local connection = self.CharacterConnections[character]
		if connection then
			connection:Disconnect()
		end
		self.CharacterConnections[character] = nil
	end
	for _, character in collectionService:GetTagged("ScaleBot") do
		track(character)
	end
	table.insert(
		self.Connections,
		collectionService:GetInstanceAddedSignal("ScaleBot"):Connect(function(character)
			track(character)
		end)
	)
	table.insert(self.Connections, collectionService:GetInstanceRemovedSignal("ScaleBot"):Connect(untrack))
	return self
end

function BotTagController.Destroy(self: any)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	for character, connection in self.CharacterConnections do
		connection:Disconnect()
		self.CharacterConnections[character] = nil
	end
	for _, character in self.CollectionService:GetTagged("ScaleBot") do
		setEnabled(character, false)
	end
end

return BotTagController

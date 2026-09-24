--!strict
-- Billboard and miniature visibility is local: seated participants do not see their table's spectator
-- signs or the tabletop reference/target miniatures (TableDisplay.SetMiniature tags each with
-- TableMiniature=true). Everyone else at/near the server still sees them normally.
local Controller = {}
Controller.__index = Controller
function Controller.new(player: Player, collection: CollectionService, tag: string)
	return setmetatable(
		{ Player = player, Collection = collection, Tag = tag, HiddenGuis = {}, HiddenParts = {}, Timer = 0 },
		Controller
	)
end
function Controller.Step(self: any, dt: number)
	self.Timer += dt
	if self.Timer < 0.1 then
		return
	end
	self.Timer = 0
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat ~= self.Seat or (seat and (not self.Table or not seat:IsDescendantOf(self.Table))) then
		self.Seat, self.Table = seat, nil
		if seat then
			for _, model in self.Collection:GetTagged(self.Tag) do
				if seat:IsDescendantOf(model) then
					self.Table = model
					break
				end
			end
		end
	end
	local retainedGuis, retainedParts = {}, {}
	local root = self.Table
		and (self.Table:FindFirstChild("TableDisplay") or self.Table:FindFirstChild("ScaleTableDisplay"))
	if seat and root then
		for _, object in root:GetDescendants() do
			if object:IsA("BillboardGui") then
				table.insert(retainedGuis, object)
				if object.Enabled then
					object.Enabled = false
				end
			elseif object:IsA("BasePart") and object:GetAttribute("TableMiniature") then
				table.insert(retainedParts, object)
				object.LocalTransparencyModifier = 1
			end
		end
	end
	for _, gui in self.HiddenGuis do
		if not table.find(retainedGuis, gui) and gui.Parent then
			gui.Enabled = gui:GetAttribute("PublicVisible") ~= false
		end
	end
	for _, part in self.HiddenParts do
		if not table.find(retainedParts, part) and part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	self.HiddenGuis, self.HiddenParts = retainedGuis, retainedParts
end
function Controller.Destroy(self: any)
	for _, gui in self.HiddenGuis do
		if gui.Parent then
			gui.Enabled = gui:GetAttribute("PublicVisible") ~= false
		end
	end
	for _, part in self.HiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(self.HiddenGuis)
	table.clear(self.HiddenParts)
end
return Controller

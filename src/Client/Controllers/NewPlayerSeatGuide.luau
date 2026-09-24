--!strict
-- A small first-match guide: point new players at the nearest free seat on an available authored 1v1 table.
-- It owns only local clones/attachments and disappears permanently for this session once the player sits.
local Guide = {}
Guide.__index = Guide

local function tableSurface(model: Model): BasePart?
	local furniture = model:FindFirstChild("Table")
	local exact = furniture and furniture:FindFirstChild("Top")
	if exact and exact:IsA("BasePart") then
		return exact
	end
	if furniture and furniture:IsA("BasePart") then
		return furniture
	end
	for _, name in { "TableTop", "Tabletop" } do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

function Guide.new(d: any)
	local self: any = setmetatable({ D = d, Connections = {}, Owned = {}, Clock = 0, Done = false }, Guide)
	table.insert(
		self.Connections,
		d.Player.CharacterAdded:Connect(function()
			self:Clear()
		end)
	)
	table.insert(
		self.Connections,
		d.Player:GetAttributeChangedSignal("NewPlayerSeatGuide"):Connect(function()
			if d.Player:GetAttribute("NewPlayerSeatGuide") ~= true then
				self.Done = true
				self:Clear()
			end
		end)
	)
	table.insert(
		self.Connections,
		d.RunService.Heartbeat:Connect(function(dt)
			self.Clock += dt
			if self.Clock < 0.25 then
				return
			end
			self.Clock = 0
			self:Step()
		end)
	)
	self:Step()
	return self
end

function Guide.Clear(self: any)
	for _, object in self.Owned do
		if object.Parent then
			object:Destroy()
		end
	end
	table.clear(self.Owned)
	self.Seat, self.Table = nil, nil
end

function Guide.NearestSeat(self: any): (Seat?, Model?)
	local character = self.D.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	local bestSeat, bestTable, bestDistance = nil, nil, math.huge
	for _, candidate in self.D.CollectionService:GetTagged(self.D.Config.TableTag) do
		if
			not candidate:IsA("Model")
			or not candidate:IsDescendantOf(self.D.World)
			or candidate:GetAttribute("Capacity") ~= 2
		then
			continue
		end
		local state = candidate:GetAttribute("MatchState")
		if state and state ~= "EMPTY" and state ~= "WAITING_FOR_PLAYER" then
			continue
		end
		for _, object in candidate:GetDescendants() do
			if object:IsA("Seat") and object.Occupant == nil then
				local distance = (object.Position - root.Position).Magnitude
				if distance < bestDistance then
					bestSeat, bestTable, bestDistance = object, candidate, distance
				end
			end
		end
	end
	return bestSeat, bestTable
end

function Guide.Build(self: any, seat: Seat, model: Model)
	self:Clear()
	local character = self.D.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local assets = self.D.Storage:FindFirstChild("Assets")
	local guideAssets = assets and assets:FindFirstChild("Tutorial")
	local surface = tableSurface(model)
	if not root or not root:IsA("BasePart") or not guideAssets or not surface then
		return
	end

	local source = Instance.new("Attachment")
	source.Name, source.Position, source.Parent = "SeatGuideBeamAttachment", Vector3.new(0, 1.5, 0), root
	table.insert(self.Owned, source)
	local destination = Instance.new("Attachment")
	destination.Name = "SeatGuideDestination"
	destination.Position = Vector3.new(0, seat.Size.Y / 2 + 0.5, 0)
	destination.Parent = seat
	table.insert(self.Owned, destination)

	local beamAsset = guideAssets:FindFirstChild("TutorialBeam")
	if beamAsset then
		local clone = beamAsset:Clone()
		clone.Parent = source
		table.insert(self.Owned, clone)
		local function bind(object: Instance)
			if object:IsA("Beam") then
				object.Attachment0, object.Attachment1 = source, destination
				object.FaceCamera, object.Enabled = true, true
			end
		end
		bind(clone)
		for _, object in clone:GetDescendants() do
			bind(object)
		end
	end

	local arrowAsset = guideAssets:FindFirstChild("HoverArrow")
	if arrowAsset then
		local clone = arrowAsset:Clone()
		local arrow: BillboardGui?
		if clone:IsA("BillboardGui") then
			arrow = clone
		elseif clone:IsA("GuiObject") then
			local gui = Instance.new("BillboardGui")
			gui.Name, gui.Size = "HoverArrow", UDim2.fromOffset(96, 96)
			clone.AnchorPoint, clone.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			if clone.Size.X.Offset == 0 and clone.Size.Y.Offset == 0 then
				clone.Size = UDim2.fromScale(1, 1)
			end
			clone.Parent = gui
			arrow = gui
		else
			clone:Destroy()
		end
		if arrow then
			arrow.Adornee, arrow.AlwaysOnTop, arrow.LightInfluence = surface, true, 0
			arrow.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			arrow.Enabled, arrow.Parent = true, surface
			table.insert(self.Owned, arrow)
		end
	end
	self.Seat, self.Table = seat, model
end

function Guide.Step(self: any)
	if self.Done or self.D.Player:GetAttribute("DataReady") ~= true then
		return
	end
	if self.D.Player:GetAttribute("NewPlayerSeatGuide") ~= true then
		self.Done = true
		self:Clear()
		return
	end
	local character = self.D.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		self.Done = true
		self:Clear()
		return
	end
	local seat, model = self:NearestSeat()
	if seat ~= self.Seat or model ~= self.Table then
		if seat and model then
			self:Build(seat, model)
		else
			self:Clear()
		end
	end
end

function Guide.Destroy(self: any)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:Clear()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

return Guide

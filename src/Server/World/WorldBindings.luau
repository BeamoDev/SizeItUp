--!strict
local WorldBindings = {}
WorldBindings.__index = WorldBindings
function WorldBindings.new(workspaceService: any, replicatedStorage: any, players: any, catalog: any, config: any?)
	return setmetatable(
		{
			Workspace = workspaceService,
			Storage = replicatedStorage,
			Players = players,
			Catalog = catalog,
			Config = config,
			-- Bot "players" are plain Lua stub tables (never real Player instances -- Roblox has no way to fake
			-- one), keyed here by their seated NPC character so Occupants() can find them the same way a real
			-- seated Player is found. NPCPopulationService and PracticeBotService own the two bot lifecycles.
			Bots = {},
		},
		WorldBindings
	)
end
function WorldBindings.ModelIds(self: any): { string }
	local exclusions = self.Config and self.Config.ObjectSelectionExclusions or {}
	local function selectable(id: string): boolean
		local baseId = id:gsub("__%d+$", "")
		return exclusions[id] ~= true and exclusions[baseId] ~= true
	end
	if self.Config and self.Config.UseLabeledBricks then
		local ids = {}
		for id in self.Catalog do
			if selectable(id) then table.insert(ids, id) end
		end
		table.sort(ids)
		return ids
	end
	local models = self.Storage:FindFirstChild(self.Config.ObjectPreviewFolder)
	local ids = {}
	if models then
		for id, definition in self.Catalog do
			if not selectable(id) then continue end
			local model = models:FindFirstChild(definition.ModelName)
			if model and model:IsA("Model") and model.Archivable and model:FindFirstChildWhichIsA("BasePart", true) then
				local _, size = model:GetBoundingBox()
				if size.Y > 0.001 and size.Y < math.huge then
					table.insert(ids, id)
				end
			end
		end
	end
	table.sort(ids)
	return ids
end
function WorldBindings.Seats(self: any, record: any)
	local model = record.Key
	-- Bootstrap invalidates this cache on Seat additions/removals. Avoid traversing
	-- every replicated tabletop miniature on every server heartbeat.
	if record.SeatCacheManaged and record.BoundSeats then
		local valid = true
		for _, seat in record.BoundSeats do
			if not seat:IsDescendantOf(model) then
				valid = false
				break
			end
		end
		if valid then
			return record.BoundSeats
		end
		record.BoundSeats = nil
	end
	local seats = {}
	local display = model:FindFirstChild("TableDisplay") or model:FindFirstChild("ScaleTableDisplay")
	for _, object in model:GetDescendants() do
		if object:IsA("Seat") and (not display or not object:IsDescendantOf(display)) then
			table.insert(seats, object)
		end
	end
	if #seats ~= (record.Capacity or model:GetAttribute("Capacity") or 2) then
		return nil
	end
	-- Keep one seat order for the lifetime of this roster, including duplicate Chair names.
	local cached = record.BoundSeats
	if cached and #cached == #seats then
		local unchanged = true
		for _, seat in cached do
			if not table.find(seats, seat) then
				unchanged = false
				break
			end
		end
		if unchanged then
			return cached
		end
	end
	local center = Vector3.zero
	for _, seat in seats do
		center += seat.CFrame.Position
	end
	center /= #seats
	local function index(seat: any): number
		local assembly = seat
		while assembly.Parent and assembly.Parent ~= model do
			assembly = assembly.Parent
		end
		local explicit = seat:GetAttribute("SeatIndex")
			or tonumber(assembly.Name:match("^Seat([1-4])$"))
			or tonumber(seat.Name:match("^Seat([1-4])$"))
		return if type(explicit) == "number" and explicit >= 1 and explicit <= 4 then explicit else 5
	end
	table.sort(seats, function(a, b)
		local ai, bi = index(a), index(b)
		if ai ~= bi then
			return ai < bi
		end
		local ap, bp = a.CFrame.Position - center, b.CFrame.Position - center
		local aa, ba = math.atan2(ap.Z, ap.X), math.atan2(bp.Z, bp.X)
		if aa ~= ba then
			return aa < ba
		end
		return ap.Magnitude < bp.Magnitude
	end)
	record.BoundSeats = seats
	return seats
end
function WorldBindings.TablePlacement(self: any, record: any): CFrame?
	local model = record.Key
	-- The authored Top is the exact display surface; surrounding Circle/parts
	-- and old placement markers must not move the cash display away from it.
	local furniture = model:FindFirstChild("Table")
	local surface = furniture and furniture:FindFirstChild("Top")
	if surface and surface:IsA("BasePart") then
		return surface.CFrame * CFrame.new(0, surface.Size.Y / 2 + 0.03, 0)
	end
	local display = model:FindFirstChild("TableDisplay") or model:FindFirstChild("ScaleTableDisplay")
	local function authored(name: string)
		local result = model:FindFirstChild(name, true)
		return if result and (not display or not result:IsDescendantOf(display)) then result else nil
	end
	local marker = authored("SpectatorDisplay")
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	local top = authored("Tabletop") or authored("TableTop")
	if top and top:IsA("BasePart") then
		return top.CFrame * CFrame.new(0, top.Size.Y / 2 + 0.03, 0)
	end
	-- Bounds belong to the authored Table only, never chair backs, Circle or runtime signs.
	if furniture and (furniture:IsA("Model") or furniture:IsA("BasePart")) then
		local parts = if furniture:IsA("BasePart") then { furniture } else furniture:GetDescendants()
		local low, high = Vector3.one * math.huge, Vector3.one * -math.huge
		local found = false
		for _, p in parts do
			if not p:IsA("BasePart") or p.Transparency >= 1 then
				continue
			end
			found = true
			local cf, size = p.CFrame, p.Size
			local function extent(axis: string): number
				return (
					math.abs(cf.RightVector[axis]) * size.X
					+ math.abs(cf.UpVector[axis]) * size.Y
					+ math.abs(cf.LookVector[axis]) * size.Z
				) / 2
			end
			local half = Vector3.new(extent("X"), extent("Y"), extent("Z"))
			local a, b = cf.Position - half, cf.Position + half
			low = Vector3.new(math.min(low.X, a.X), math.min(low.Y, a.Y), math.min(low.Z, a.Z))
			high = Vector3.new(math.max(high.X, b.X), math.max(high.Y, b.Y), math.max(high.Z, b.Z))
		end
		if found then
			return CFrame.new((low.X + high.X) / 2, high.Y + 0.03, (low.Z + high.Z) / 2)
		end
	end
	local seats = self:Seats(record)
	if not seats then
		return nil
	end
	local center = Vector3.zero
	for _, seat in seats do
		center += seat.CFrame.Position
	end
	return CFrame.new(center / #seats + Vector3.new(0, 1.3, 0))
end
-- SeatPart/Occupant can still be settling when SeatWeld already connects the rig to furniture.
-- Inspect the actual joints before moving a bot; moving any welded body part can move the seat too.
function WorldBindings.SeatAttachment(self: any, character: Model): (BasePart?, Weld?)
	for _, part in character:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		for _, joint in part:GetJoints() do
			if not joint:IsA("Weld") or joint.Name ~= "SeatWeld" then continue end
			local other = if joint.Part0 == part then joint.Part1 else joint.Part0
			if other and (other:IsA("Seat") or other:IsA("VehicleSeat")) and not other:IsDescendantOf(character) then
				return other, joint
			end
		end
	end
	return nil, nil
end

function WorldBindings.DetachSeat(self: any, character: Model, humanoid: Humanoid)
	humanoid.Sit = false
	local _, weld = self:SeatAttachment(character)
	while weld do
		-- Only a SeatWeld actually attached to this character is removed; other occupants are untouched.
		weld:Destroy()
		_, weld = self:SeatAttachment(character)
	end
end

function WorldBindings.Alive(self: any, player: any): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- A bot stub is a plain Lua table, never really parented to the Players service; only check typeof
	-- before reading .IsBot, since indexing an undefined property on a real Player Instance throws.
	if typeof(player) == "table" and player.IsBot then
		return humanoid ~= nil and humanoid.Health > 0
	end
	return player.Parent == self.Players and humanoid ~= nil and humanoid.Health > 0
end
function WorldBindings.Occupants(self: any, record: any)
	local seats = self:Seats(record)
	local occupants = {}
	if seats then
		for i, seat in seats do
			local humanoid = seat.Occupant
			if humanoid and humanoid.Health > 0 then
				local player = self.Players:GetPlayerFromCharacter(humanoid.Parent) or self.Bots[humanoid.Parent]
				if player and player.Character == humanoid.Parent then
					occupants[i] = player
				end
			end
		end
	end
	return occupants
end
-- Wall, Wall1-3 and Floor keep one common, small texture tiling (GameConfig.ArenaTileStuds) so the grid suits small objects.
local TILED_PARTS = { "Wall", "Wall1", "Wall2", "Wall3", "Floor" }
function WorldBindings.TileArena(self: any, arena: Instance)
	local studs = self.Config and self.Config.ArenaTileStuds
	if type(studs) ~= "number" or studs <= 0 then
		return
	end
	self.Tiled = self.Tiled or setmetatable({}, { __mode = "k" })
	if self.Tiled[arena] == studs then
		return
	end
	self.Tiled[arena] = studs
	for _, name in TILED_PARTS do
		local part = arena:FindFirstChild(name)
		if part then
			for _, child in part:GetChildren() do
				if child:IsA("Texture") then
					child.StudsPerTileU, child.StudsPerTileV = studs, studs
				end
			end
		end
	end
end
function WorldBindings.Arena(self: any, record: any)
	local arenas = self.Workspace:FindFirstChild("ScaleArenas")
	local name = record.Key:GetAttribute("ArenaName")
	local gameRoot = self.Workspace:FindFirstChild("Game")
	local zones = gameRoot and gameRoot:FindFirstChild("Zones")
	local authored = (zones and zones:FindFirstChild("ObjectArena")) or (gameRoot and gameRoot:FindFirstChild("ObjectArena"))
		or self.Workspace:FindFirstChild("ObjectArena")
	local arena = type(name) == "string"
		and (if name == "ObjectArena" then authored else arenas and arenas:FindFirstChild(name))
	if not arena or not (arena:IsA("Model") or arena:IsA("Folder")) then
		return nil, "Set this table's ArenaName to a model in Workspace.ScaleArenas, or add Workspace.Game.Zones.ObjectArena"
	end
	if self.Workspace.StreamingEnabled then
		if arena:IsA("Folder") then
			return nil, "With StreamingEnabled, make ObjectArena a Model set to Persistent"
		end
		if arena.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
			return nil, "Set the arena ModelStreamingMode to Persistent for remote viewing"
		end
	end
	local camera = arena:FindFirstChild("CameraPart")
	if not camera or not camera:IsA("BasePart") or not camera.Anchored then
		return nil, "Arena needs an anchored CameraPart"
	end
	if math.abs(camera.CFrame.LookVector.Y) > 0.1 then
		return nil, "CameraPart must face the objects horizontally (no pitch/roll)"
	end
	if camera.CFrame.UpVector:Dot(Vector3.yAxis) < 0.99 then
		return nil, "CameraPart must be upright"
	end
	-- Preserve the authored comparison layout. These markers define the exact floor positions and spacing selected in
	-- Studio; runtime code must never create, move, resize or otherwise rewrite them.
	local reference, target = arena:FindFirstChild("ReferenceSpawn"), arena:FindFirstChild("TargetSpawn")
	for _, marker in { reference, target } do
		if not marker or not marker:IsA("BasePart") or not marker.Anchored then
			return nil, "Arena needs anchored ReferenceSpawn and TargetSpawn BaseParts"
		end
	end
	if math.abs(reference.Position.Y - target.Position.Y) > 0.05 then
		return nil, "Arena spawn markers must share a baseline (same Y)"
	end
	if (target.Position - reference.Position):Dot(camera.CFrame.RightVector) <= 0 then
		return nil, "ReferenceSpawn must be left of TargetSpawn from CameraPart"
	end
	if math.abs((target.Position - reference.Position):Dot(camera.CFrame.LookVector)) > 0.05 then
		return nil, "Arena spawn markers must be at the same viewing depth"
	end
	self:TileArena(arena)
	return { Reference = reference.CFrame, Target = target.CFrame, Camera = camera.CFrame }
end
function WorldBindings.Valid(self: any, record: any): boolean
	return record.Key:IsDescendantOf(self.Workspace) and self:Seats(record) ~= nil and self:Arena(record) ~= nil
end
function WorldBindings.Prepare(self: any, record: any)
	if not self:Seats(record) then
		return nil, "Table needs exactly " .. (record.Capacity or 2) .. " Seat instances inside its chairs"
	end
	if #self:ModelIds() < 2 then
		return nil, "Add at least two supported Models or MeshParts to ServerStorage.Objects, then restart Play"
	end
	return self:Arena(record)
end
function WorldBindings.Eject(self: any, record: any, player: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsDescendantOf(record.Key) then
		-- Only stand the player up. The character, seat and chair are never moved.
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld and weld:IsA("Weld") and weld.Part1 and weld.Part1:IsDescendantOf(character) then
			weld:Destroy()
		end
	end
end
function WorldBindings.ReactionView(self: any, _record: any, _viewer: any, target: any)
	local function headPosition(participant: any): Vector3
		local character = participant.Character
		local head = character and character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head.Position
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if not seat then
			local seats = self:Seats(_record)
			local fallback = seats and seats[1]
			return if fallback then fallback.Position + Vector3.new(0, 2.5, 0) else Vector3.zero
		end
		return seat.CFrame.Position + Vector3.new(0, 2.5, 0)
	end
	local focus = headPosition(target)
	local character = target.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local facing = if head and head:IsA("BasePart") then head.CFrame.LookVector else Vector3.new(0, 0, -1)
	local flat = facing * Vector3.new(1, 0, 1)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	-- Frame the losing avatar from in front, identically for every participant.
	local eye = focus + forward * 7 + forward:Cross(Vector3.yAxis) * 1.6 + Vector3.new(0, 0.5, 0)
	return { Camera = CFrame.lookAt(eye, focus), Focus = focus }
end
return WorldBindings

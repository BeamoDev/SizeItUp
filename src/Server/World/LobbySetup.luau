--!strict
local LobbySetup = {}
local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, class: string?): any
	local p = Instance.new(class or "Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, frame, color
	p.Anchored, p.Material, p.TopSurface, p.BottomSurface = true, Enum.Material.SmoothPlastic, Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent;return p
end
local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name);if existing then return existing end
	local result = Instance.new("Folder");result.Name, result.Parent = name, parent;return result
end
-- Tables and the arena live in Workspace.Game.Zones. Legacy direct children remain readable for local fixtures.
local function gameChild(world: any, name: string): any
	local root = world:FindFirstChild("Game")
	local zones = root and root:FindFirstChild("Zones")
	return (zones and zones:FindFirstChild(name)) or (root and root:FindFirstChild(name)) or world:FindFirstChild(name)
end
local function marker(parent: Instance, name: string, frame: CFrame)
	local p = part(parent, name, Vector3.one, frame, Color3.new())
	p.Transparency, p.CanCollide, p.CanTouch, p.CanQuery = 1, false, false, false;return p
end
function LobbySetup.EnsureArena(world: any)
	local authored = gameChild(world, "ObjectArena")
	if authored then return authored end
	local arenas = folder(world, "ScaleArenas")
	local arena = arenas:FindFirstChild("ScaleGeneratedArena")
	if not arena then
		arena = Instance.new("Model");arena.Name, arena.ModelStreamingMode = "ScaleGeneratedArena", Enum.ModelStreamingMode.Persistent
		local frame = CFrame.new(0, 500, 0)
		part(arena, "Floor", Vector3.new(180, 1, 100), frame * CFrame.new(0, -0.5, 0), Color3.fromRGB(51, 74, 95))
		marker(arena, "CameraPart", frame * CFrame.new(0, 5, 35))
		arena.Parent = arenas
	end
	return arena
end
function LobbySetup.Register(world: any, collection: any, model: any, tableTag: string): boolean
	if not model:IsA("Model") or not model.Parent then return false end
	local container = model.Parent.Parent
	local gameRoot = world:FindFirstChild("Game")
	local zones = gameRoot and gameRoot:FindFirstChild("Zones")
	if container ~= world and container ~= gameRoot and container ~= zones then return false end
	local capacity = ({["2v2"]=2,["3v3"]=3,["4v4"]=4})[model.Parent.Name]
	if not capacity or model.Name ~= model.Parent.Name .. "Tables" then return false end
	model:SetAttribute("Capacity", capacity)
	model:SetAttribute("PreserveAuthoredChairs", true)
	if not model:GetAttribute("ArenaName") or model:GetAttribute("ArenaName") == "" then
		model:SetAttribute("ArenaName", LobbySetup.EnsureArena(world).Name)
	end
	if not collection:HasTag(model, tableTag) then collection:AddTag(model, tableTag) end
	return true
end
function LobbySetup.Ensure(world: any, collection: any, config: any, tableTag: string)
	-- Migrate only the known generated stands. Authored scenery is not owned here.
	local generated=world:FindFirstChild("ScaleGeneratedLobby")
	if generated and generated:GetAttribute("ScaleGenerated")==true then
		for _, child in generated:GetChildren() do
			local oldTable = child:IsA("Model") and child.Name:match("^Table%d%d$")
				and child:GetAttribute("ArenaName") == "ScaleGeneratedArena" and child:FindFirstChild("Tabletop") and child:FindFirstChild("Seat1")
			local oldShop = child.Name == "ChairShop" and child:FindFirstChild("ShowroomPath")
			if oldTable or oldShop then
				if collection:HasTag(child, tableTag) then collection:RemoveTag(child, tableTag) end
				child:Destroy()
			end
		end
		for _,id in {"Abyssal","Oceanic","Solar","Universal"} do
			local block=generated:FindFirstChild(id.."Block")
			if block and block:GetAttribute("ContainerId")==id and not block:GetAttribute("PetShopId") then block:Destroy() end
		end
	end
	-- The map owns all tables and chairs. Register the existing assemblies in place.
	for _, name in {"2v2", "3v3", "4v4"} do
		local group = gameChild(world, name)
		if group then for _, model in group:GetChildren() do LobbySetup.Register(world, collection, model, tableTag) end end
	end
	-- Egg stands are authored in Workspace.Game.Interactables.Eggs and bound by EggShops.
	return generated
end
return LobbySetup

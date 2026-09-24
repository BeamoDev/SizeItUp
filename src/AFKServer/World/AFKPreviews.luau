--!strict
-- The AFK screen's reward viewports need real models on the client. Chairs and Lucky Blocks already replicate
-- (ReplicatedStorage.Assets.Chairs / .LuckyBlocks); usable pets live in ServerStorage.Pets.Active, which clients cannot see.
-- This copies every pet the AFK rewards can give (tier pools and egg hatches) into ReplicatedStorage.AFKPreviews.Pets.<PetId>, stripped of
-- scripts, sounds and prompts, anchored and non-colliding. The Pets originals are never changed.
local Previews = {}

local function supported(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Model") or instance:IsA("BasePart"))
end

local function normalized(name: string): string
	return string.lower(name:gsub("[^%w]", ""))
end

local function findAsset(pack: Instance, id: string, item: any): Instance?
	-- Active is intentionally flat. Prefer the authored asset name, then the display name and stable pet ID.
	local assetName = if type(item.AssetPath) == "table" then item.AssetPath[#item.AssetPath] else nil
	local candidates = { item.Name, id }
	if assetName then
		table.insert(candidates, 1, assetName)
	end
	for _, name in candidates do
		local child = type(name) == "string" and pack:FindFirstChild(name) or nil
		if supported(child) then
			return child
		end
	end
	for _, name in candidates do
		if type(name) == "string" then
			local key = normalized(name)
			local found: Instance? = nil
			for _, child in pack:GetChildren() do
				if supported(child) and normalized(child.Name) == key then
					if found then
						return nil
					end
					found = child
				end
			end
			if found then
				return found
			end
		end
	end
	return nil
end

local function sanitize(source: Instance, name: string): Model
	local copy = source:Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	else
		model = Instance.new("Model")
		copy.Parent = model
	end
	model.Name = name
	for _, item in model:GetDescendants() do
		if
			item:IsA("LuaSourceContainer")
			or item:IsA("Sound")
			or item:IsA("ProximityPrompt")
			or item:IsA("ClickDetector")
		then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored, item.CanCollide, item.CanTouch, item.CanQuery = true, false, false, false
		end
	end
	return model
end

-- Returns the published folder and the pet IDs that could not be found.
function Previews.Build(serverStorage: Instance, storage: Instance, config: any, catalog: any): (Folder, { string })
	local folder = Instance.new("Folder")
	folder.Name = "AFKPreviews"
	local pets = Instance.new("Folder")
	pets.Name = "Pets"
	pets.Parent = folder
	local petsRoot = serverStorage:FindFirstChild("Pets")
	local pack = petsRoot and petsRoot:FindFirstChild("Active")
	local missing = {}
	-- Every pet an AFK reward can be: the fixed list and every Offer pet pool.
	local ids = {}
	for _, reward in config.Rewards do
		if reward.Kind == "Pet" and reward.PetId then
			table.insert(ids, reward.PetId)
		end
	end
	-- Every tier option: its pet pool, and every pet an offered egg can hatch.
	for _, tier in config.Offer or {} do
		for _, option in tier.Options or { tier } do
			if option.Kind == "Pet" then
				for _, id in option.Pool do
					table.insert(ids, id)
				end
			elseif option.Kind == "Egg" then
				for _, eggId in option.Pool do
					local shop = catalog.PetShops and catalog.PetShops[eggId]
					for _, id in (shop and shop.Pets) or {} do
						table.insert(ids, id)
					end
				end
			end
		end
	end
	for _, id in ids do
		if not pets:FindFirstChild(id) then
			local item = catalog.Items.Pets[id]
			local asset = pack and item and findAsset(pack, id, item)
			if asset then
				sanitize(asset, id).Parent = pets
			else
				table.insert(missing, id)
			end
		end
	end
	local previous = storage:FindFirstChild(folder.Name)
	if previous then
		previous:Destroy()
	end
	folder.Parent = storage
	return folder, missing
end

return Previews

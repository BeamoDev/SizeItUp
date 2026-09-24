--!strict
-- Identity discovery is separate from the deliberately small playable catalog.
local PetLibrary = {}
function PetLibrary.Build(serverStorage, storage, database, catalog, visual, collection, report)
	local previews = Instance.new("Folder")
	previews.Name = "ScalePetPreviews"
	local index = Instance.new("Folder")
	index.Name = "ScalePetDatabase"
	local assets, byName, byNormalizedName = {}, {}, {}
	local function normalized(name)
		return string.lower(name:gsub("[^%w]", ""))
	end
	local petsRoot = serverStorage:FindFirstChild("Pets")
	local pack = petsRoot and petsRoot:FindFirstChild("Active")
	if pack then
		for _, child in pack:GetChildren() do
			if child:IsA("BasePart") or (child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart", true)) then
				local asset = { Source = child, Path = { child.Name }, Name = child.Name }
				table.insert(assets, asset)
				byName[child.Name] = byName[child.Name] or {}
				table.insert(byName[child.Name], asset)
				local key = normalized(child.Name)
				byNormalizedName[key] = byNormalizedName[key] or {}
				table.insert(byNormalizedName[key], asset)
			end
		end
	end
	local function resolve(path, name, id)
		local candidates = { name, id }
		if path and path[#path] then
			table.insert(candidates, 1, path[#path])
		end
		for _, candidate in candidates do
			local matches = candidate and byName[candidate]
			if matches then
				if #matches == 1 then
					return matches[1]
				end
				return nil, "multiple direct assets named " .. candidate
			end
		end
		for _, candidate in candidates do
			local matches = candidate and byNormalizedName[normalized(candidate)]
			if matches then
				if #matches == 1 then
					return matches[1]
				end
				return nil, "multiple direct assets match " .. candidate
			end
		end
		return nil, "asset was not found"
	end
	local registered, used = {}, {}
	local function row(id, name, path, evolved, asset)
		local entry = Instance.new("Folder")
		entry.Name = id
		entry:SetAttribute("DisplayName", name)
		entry:SetAttribute("AssetPath", path and table.concat(path, "/") or "")
		local group = path and table.clone(path) or {}
		table.remove(group)
		entry:SetAttribute("Group", table.concat(group, "/"))
		entry:SetAttribute("Evolved", evolved == true)
		entry:SetAttribute("Available", asset ~= nil)
		entry:SetAttribute("Active", catalog.Items.Pets[id] ~= nil and catalog.Items.Pets[id].Active == true)
		entry.Parent = index
		used[id] = true
		if asset then
			registered[asset] = true
		end
	end
	for _, id in database.Order do
		local item = database.Entries[id]
		local asset = resolve(item.Path, item.Name, id)
		row(id, item.Name, asset and asset.Path or item.Path, item.Evolved, asset)
	end
	for _, asset in assets do
		if registered[asset] then
			continue
		end
		local key = table.concat(asset.Path, "/")
		local hash = 5381
		for i = 1, #key do
			hash = (hash * 33 + string.byte(key, i)) % 2147483647
		end
		local base = asset.Name:gsub("[^%w]", ""):sub(1, 40) .. "_" .. tostring(hash)
		local id = base
		local suffix = 1
		while used[id] do
			suffix += 1
			id = base .. "_" .. suffix
		end
		row(id, asset.Name, asset.Path, table.find(asset.Path, "Evolved") ~= nil, asset)
	end
	local available, missing, problems = {}, {}, {}
	for _, id in catalog.Order.Pets do
		local item = catalog.Items.Pets[id]
		local asset, resolutionProblem = resolve(item.AssetPath, item.Name, id)
		available[id] = false
		if asset then
			local ok, model = pcall(visual.Normalize, asset.Source, collection)
			if ok and model then
				model.Name = id
				model.Parent = previews
				available[id] = true
			end
			if item.Active and not available[id] then
				table.insert(problems, item.Name .. " at " .. table.concat(asset.Path, "/") .. ": " .. tostring(model))
			end
		elseif item.Active then
			local assetName = item.AssetPath and item.AssetPath[#item.AssetPath] or item.Name
			table.insert(
				problems,
				item.Name
					.. ": expected direct model Pets/Active/"
					.. assetName
					.. " ("
					.. tostring(resolutionProblem)
					.. ")"
			)
		end
		if item.Active and not available[id] then
			table.insert(missing, item.Name)
		end
		local entry = index:FindFirstChild(id)
		if entry then
			entry:SetAttribute("Available", available[id])
		end
	end
	for _, pair in { { storage, previews }, { serverStorage, index } } do
		local previous = pair[1]:FindFirstChild(pair[2].Name)
		if previous then
			previous:Destroy()
		end
		pair[2].Parent = pair[1]
	end
	if #missing > 0 and report then
		report("Pets: unavailable release pets (purchases disabled): " .. table.concat(missing, ", "))
		for _, problem in problems do
			report("Pets detail: " .. problem)
		end
	end
	return previews, available, index
end
return PetLibrary

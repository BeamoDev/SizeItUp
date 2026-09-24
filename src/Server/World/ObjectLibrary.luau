--!strict
local ObjectLibrary = {}
function ObjectLibrary.Build(serverStorage: any, storage: any, catalog: any, defaults: any, config: any, visual: any, collection: any, report: (string) -> ())
	local folder = Instance.new("Folder")
	folder.Name = config.ObjectPreviewFolder
	assert(not storage:FindFirstChild(folder.Name), "Reserved runtime folder already exists: " .. folder.Name)
	local answers, definitions = {}, {}
	local objects = serverStorage:FindFirstChild("Objects")
	if objects then
		for id, definition in catalog do
			local variant = 0
			for _, source in objects:GetChildren() do
				if source.Name ~= definition.ModelName then continue end
				variant += 1
				-- Duplicate authored names (e.g. the two Deer) get distinct runtime
				-- identities. Never rename/move the owner's ServerStorage originals.
				local runtimeId = if variant == 1 then id else id .. "__" .. variant
				local height = source:GetAttribute("HeightMeters")
				if height == nil then height = defaults[id] end
				if type(height) ~= "number" or height ~= height or height < config.MinimumGuessMeters or height > config.MaximumGuessMeters then
					report("Skipping " .. id .. ": HeightMeters must be within the guess range")
					continue
				end
				local ok, model = pcall(visual.Normalize, source, collection)
				if ok then
					local normalizedHeight = model:GetAttribute("NormalizedVisibleHeight")
					if type(normalizedHeight) ~= "number" or math.abs(normalizedHeight - 1) > 0.005 then
						model:Destroy()
						report("Skipping " .. runtimeId .. ": visible geometry did not normalize to one stud")
						continue
					end
					model.Name, model.Parent = runtimeId, folder
					answers[runtimeId] = height
					definitions[runtimeId] = {
						Id = runtimeId, ModelName = runtimeId,
						DisplayName = definition.DisplayName .. (if variant == 1 then "" else " (" .. variant .. ")"),
						MeasurementType = definition.MeasurementType, Category = definition.Category,
					}
				else report("Skipping ServerStorage.Objects." .. id .. ": " .. tostring(model)) end
			end
		end
	else report("Add Models or MeshParts to ServerStorage.Objects before starting Play") end
	-- Publish complete, sanitized templates before any matches can start.
	folder.Parent = storage
	if #folder:GetChildren() < 2 then report("At least two usable ServerStorage.Objects assets are required to play") end
	return folder, answers, definitions
end
return ObjectLibrary

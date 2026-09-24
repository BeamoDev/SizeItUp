--!strict
-- Visual-only copies. Never move or modify the authored source.
local ObjectVisual = {}
function ObjectVisual.ClearCustomAttributes(object: Instance)
	for key in object:GetAttributes() do
		-- Roblox import metadata (e.g. RBX_ReimportId) is protected:
		-- even deleting it requires CoreScript permissions. Preserve
		-- reserved attributes; still remove all custom/gameplay data.
		if key:sub(1, 3) ~= "RBX" then object:SetAttribute(key, nil) end
	end
end
local function allowed(item: Instance): boolean
	return item:IsA("Model") or item:IsA("Folder") or item:IsA("BasePart")
		or item:IsA("DataModelMesh") or item:IsA("Decal") or item:IsA("SurfaceAppearance")
		or item:IsA("Attachment")
end
local function hasVisibleSurface(part: BasePart): boolean
	for _, item in part:GetChildren() do
		if (item:IsA("Decal") or item:IsA("Texture")) and item.Transparency < 1 then
			return true
		end
	end
	return false
end
-- Imported models often contain a huge, fully transparent bounds/root part. Measuring that part and then deleting it
-- on the client makes the remaining car/ship/etc. appear tiny. Remove it before measuring while preserving any real
-- nested geometry at the same world transforms. A transparent surface carrying a visible decal remains display geometry.
local function stripInvisibleHelpers(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and child.Transparency >= 1 and not hasVisibleSurface(child) then
			local adopted = {}
			for _, nested in child:GetChildren() do
				if nested:IsA("BasePart") or nested:IsA("Model") or nested:IsA("Folder") then
					nested.Parent = parent
					table.insert(adopted, nested)
				end
			end
			child:Destroy()
			for _, nested in adopted do
				stripInvisibleHelpers(nested)
			end
		elseif child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			stripInvisibleHelpers(child)
		end
	end
end
function ObjectVisual.Normalize(source: Instance, collection: any?): Model
	assert(source:IsA("Model") or source:IsA("BasePart"), "Expected a Model or BasePart")
	assert(source.Archivable, source.Name .. " must be Archivable")
	local container = Instance.new("Model")
	local result = Instance.new("Model")
	local ok, problem = pcall(function()
		local copy = source:Clone()
		copy.Parent = container -- Still outside the DataModel: scripts cannot run.
		local function sanitize(parent: Instance)
			ObjectVisual.ClearCustomAttributes(parent)
			if collection then
				for _, tag in collection:GetTags(parent) do collection:RemoveTag(parent, tag) end
			end
			for _, child in parent:GetChildren() do
				if allowed(child) then sanitize(child) else child:Destroy() end
			end
			if parent:IsA("BasePart") then
				parent.Anchored, parent.CanCollide, parent.CanTouch, parent.CanQuery = true, false, false, false
			end
		end
		sanitize(copy)
		stripInvisibleHelpers(container)
		assert(container:FindFirstChildWhichIsA("BasePart", true), "Object has no parts")
		local bounds, size = container:GetBoundingBox()
		assert(size.Y > 0.001 and size.Magnitude < math.huge, "Object has invalid bounds")
		-- Flatten first. Scaling an outer temporary Model before pulling parts out of a nested imported Model can discard
		-- part of the effective scale. A fresh flat model has one unambiguous scale basis.
		for _, part in container:GetDescendants() do
			if part:IsA("BasePart") then part.Parent = result end
		end
		result.Name = source.Name
		local flatBounds, flatSize = result:GetBoundingBox()
		assert(flatSize.Y > 0.001 and flatSize.Magnitude < math.huge, "Object has invalid flattened bounds")
		result.WorldPivot = CFrame.new(flatBounds.Position)
		result:ScaleTo(result:GetScale() / flatSize.Y)
		result:PivotTo(CFrame.new(0, 0.5, 0))
		local _, normalizedSize = result:GetBoundingBox()
		-- Correct import/model-scale rounding once on the already-flat copy. The authored source remains untouched.
		if normalizedSize.Y > 0.001 and math.abs(normalizedSize.Y - 1) > 0.005 then
			result:ScaleTo(result:GetScale() / normalizedSize.Y)
			result:PivotTo(CFrame.new(0, 0.5, 0))
			_, normalizedSize = result:GetBoundingBox()
		end
		assert(math.abs(normalizedSize.Y - 1) <= 0.005, "Object could not be normalized to one visible stud")
		-- Import diagnostics are safe to replicate: they describe only authored geometry, never the private answer.
		result:SetAttribute("SourceVisibleSize", size)
		result:SetAttribute("NormalizedVisibleSize", normalizedSize)
		result:SetAttribute("NormalizedVisibleHeight", normalizedSize.Y)
	end)
	container:Destroy()
	if not ok then result:Destroy();error(problem) end
	return result
end
function ObjectVisual.Miniature(source: Model, parent: Instance, frame: CFrame, extent: number): Model
	local model = source:Clone()
	model.Name = source.Name .. "Miniature"
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * extent / math.max(size.X, size.Y, size.Z))
	model:PivotTo(frame)
	local bounds, scaledSize = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, frame.Position.Y - (bounds.Position.Y - scaledSize.Y * 0.5), 0))
	model.Parent = parent
	return model
end
-- A miniature that fits perfectly inside a box: scaled uniformly (never stretched) until it just touches the box's tightest side,
-- standing on the box's floor and centred on it. `box` is the box's centre frame (upright, so only its heading counts) and
-- `size` its dimensions in that frame. Returns the model.
function ObjectVisual.MiniatureFit(source: Model, parent: Instance, box: CFrame, size: Vector3): Model
	local model = source:Clone()
	model.Name = source.Name .. "Miniature"
	local _, natural = model:GetBoundingBox()
	-- Table previews face across the table. Their quarter-turn swaps the source width/depth relative to the authored
	-- fit box, so account for that before scaling rather than letting wide models spill over its short edge.
	local fit = math.min(size.X / math.max(natural.Z, 1e-4), size.Y / math.max(natural.Y, 1e-4), size.Z / math.max(natural.X, 1e-4))
	model:ScaleTo(model:GetScale() * fit)
	local floor = box * CFrame.new(0, -size.Y * 0.5, 0) * CFrame.Angles(0, math.pi * 0.5, 0)
	model:PivotTo(floor)
	local bounds, scaled = model:GetBoundingBox()
	-- Centre on the box horizontally and rest on its floor.
	local offset = floor.Position - Vector3.new(bounds.Position.X, bounds.Position.Y - scaled.Y * 0.5, bounds.Position.Z)
	model:PivotTo(model:GetPivot() + offset)
	model.Parent = parent
	return model
end
return ObjectVisual

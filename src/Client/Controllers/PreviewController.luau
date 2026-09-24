--!strict
local BrickVisual = require(script.Parent.BrickVisual)
local RevealPresentation = require(script.Parent.RevealPresentation)
local mousePickOffsets = { { 0, 0 } }
local touchPickOffsets =
	{ { 0, 0 }, { -12, 0 }, { 12, 0 }, { 0, -12 }, { 0, 12 }, { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } }
local PreviewController = {}
PreviewController.__index = PreviewController
function PreviewController.new(storage: ReplicatedStorage, world: Workspace, config: any, mathUtil: any)
	return setmetatable({ Storage = storage, World = world, Config = config, Math = mathUtil }, PreviewController)
end
local function clone(source: Model, parent: Instance)
	assert(source.Archivable, source.Name .. " must be Archivable")
	local model = source:Clone()
	-- Remove behavior before parenting the local model into Workspace.
	for _, child in model:GetDescendants() do
		if
			child:IsA("LuaSourceContainer")
			or child:IsA("Sound")
			or child:IsA("ProximityPrompt")
			or child:IsA("ClickDetector")
		then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored, child.CanCollide, child.CanTouch, child.CanQuery = true, false, false, false
			-- Invisible rig/bounds helpers must not hold visible feet above the floor.
			-- Preserve transparent surfaces that carry visible decals, and any nested geometry.
			local decorated = false
			for _, item in child:GetChildren() do
				if (item:IsA("Decal") or item:IsA("Texture")) and item.Transparency < 1 then
					decorated = true
				end
			end
			if child.Transparency >= 1 and not decorated then
				for _, item in child:GetChildren() do
					if item:IsA("BasePart") or item:IsA("Model") or item:IsA("Folder") then
						item.Parent = model
					end
				end
				child:Destroy()
			else
				child.CastShadow = true
			end
		elseif child:IsA("Humanoid") then
			child.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	model.Parent = parent
	-- A normalized upright pivot makes arbitrary authored pivot offsets harmless.
	if model.PrimaryPart then
		model.PrimaryPart = nil
	end
	local bounds, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(bounds.Position)
	local uprightBounds, uprightSize = model:GetBoundingBox()
	assert(size.Y > 0 and uprightSize.Y > 0, "Model has no measurable height")
	local normalizedHeight = source:GetAttribute("NormalizedVisibleHeight")
	if type(normalizedHeight) == "number" then
		assert(
			math.abs(uprightSize.Y - normalizedHeight) <= math.max(0.005, normalizedHeight * 0.005),
			"Visible preview bounds changed after replication"
		)
	end
	model.WorldPivot = CFrame.new(uprightBounds.Position)
	return { Model = model, Height = uprightSize.Y, Size = uprightSize, Scale = model:GetScale() }
end
local function place(object: any, height: number, location: CFrame)
	-- Every production template is one visible stud tall. Scaling by requested display height here converts the
	-- public reference metres/current guess into studs while retaining the source model's real proportions.
	if object.DisplayHeight ~= height then
		object.Model:ScaleTo(object.Scale * height / object.Height)
		object.DisplayHeight = height
	end
	local bounds, size = object.Model:GetBoundingBox()
	local intended = location * object.Model:GetPivot():ToObjectSpace(bounds)
	local halfHeight = (
		math.abs(intended.RightVector.Y) * size.X
		+ math.abs(intended.UpVector.Y) * size.Y
		+ math.abs(intended.LookVector.Y) * size.Z
	) * 0.5
	local bottom = intended.Position.Y - halfHeight
	-- Compute the grounded pivot before moving the model. A tiny floating-point
	-- allowance prevents rounding below the floor at distant arena coordinates.
	local clearance = math.max(0.00001, (math.abs(location.Position.Y) + halfHeight) * 2 ^ -22)
	object.Model:PivotTo(location + Vector3.new(0, location.Position.Y - bottom + clearance, 0))
	local brick = object.Model:FindFirstChild("Brick")
	local label = brick and brick:FindFirstChild("ObjectLabel")
	if label and label:IsA("BillboardGui") then
		-- Keep text legible and above the top even after large model scale changes.
		local labelWidth = math.max(4, height * 0.55)
		label.Size = UDim2.fromScale(labelWidth, labelWidth * 0.22)
		label.StudsOffsetWorldSpace = Vector3.new(0, height * 0.5 + 0.8, 0)
	end
end
-- Gap between reference and target scales with the reference, up to ModelGapStuds.
local function gapFor(config: any, referenceStuds: number): number
	return math.clamp(referenceStuds * config.ModelGapFraction, config.ModelGapMinStuds, config.ModelGapStuds)
end
local function contactShadow(object: any, parent: Instance, floorY: number, opacity: number, name: string)
	local shadow = object.ContactShadow
	if not shadow then
		local plane = Instance.new("Part")
		plane.Name = name
		plane.Anchored, plane.CanCollide, plane.CanTouch, plane.CanQuery, plane.CastShadow =
			true, false, false, false, false
		plane.Transparency = 1
		local surface = Instance.new("SurfaceGui")
		surface.Name, surface.Face, surface.AlwaysOnTop = "ContactShading", Enum.NormalId.Top, false
		surface.SizingMode, surface.CanvasSize = Enum.SurfaceGuiSizingMode.FixedSize, Vector2.new(128, 128)
		surface.LightInfluence, surface.MaxDistance, surface.Active = 0, 0, false
		surface.Parent = plane
		local layers = {}
		for i = 1, 8 do
			local layer = Instance.new("Frame")
			layer.Name = "SoftEdge" .. i
			layer.AnchorPoint, layer.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			local radius = 1 - (i - 1) * 0.085
			layer.Size = UDim2.fromScale(radius, radius)
			layer.BorderSizePixel, layer.BackgroundColor3, layer.Active, layer.ZIndex = 0, Color3.new(0, 0, 0), false, i
			local corner = Instance.new("UICorner")
			corner.Name = "RoundContact"
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = layer
			layer.Parent = surface
			layers[i] = layer
		end
		plane.Parent = parent
		shadow = { Plane = plane, Surface = surface, Layers = layers }
		object.ContactShadow = shadow
	end
	shadow.Surface.Enabled = opacity > 0
	if opacity <= 0 then
		return
	end
	local bounds, size = object.Model:GetBoundingBox()
	local x = (
		math.abs(bounds.RightVector.X) * size.X
		+ math.abs(bounds.UpVector.X) * size.Y
		+ math.abs(bounds.LookVector.X) * size.Z
	)
	local z = (
		math.abs(bounds.RightVector.Z) * size.X
		+ math.abs(bounds.UpVector.Z) * size.Y
		+ math.abs(bounds.LookVector.Z) * size.Z
	)
	-- Sibling geometry cannot alter model bounds, scoring, picking or camera framing.
	-- The top face sits just above the shared floor, independent of model height.
	shadow.Plane.Size = Vector3.new(math.max(0.01, x * 0.95), 0.01, math.max(0.01, z * 0.95))
	local lift = math.max(0.003, math.abs(floorY) * 2 ^ -22)
	shadow.Plane.CFrame = CFrame.new(bounds.Position.X, floorY + lift - 0.005, bounds.Position.Z)
	if shadow.Opacity ~= opacity then
		for _, layer in shadow.Layers do
			layer.BackgroundTransparency = 1 - 0.045 * opacity
		end
		shadow.Opacity = opacity
	end
end
function PreviewController.Start(self: any, snapshot: any)
	self:Clear()
	-- The preview's models live in Workspace.Runtime.Models (Workspace itself when that folder does not exist).
	local runtime = self.World:FindFirstChild("Runtime")
	local home = (runtime and runtime:FindFirstChild("Models")) or self.World
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "ScaleItUpLocalPreview", home
	self.Folder = folder
	if self.Config.UseLabeledBricks then
		self.Reference = { Model = BrickVisual.Create(snapshot.Reference, folder), Height = 4, Scale = 1 }
		self.Target = { Model = BrickVisual.Create(snapshot.Target, folder), Height = 4, Scale = 1 }
	else
		local models = self.Storage:FindFirstChild(self.Config.ObjectPreviewFolder)
		local reference = models and models:FindFirstChild(snapshot.Reference.ModelName)
		local target = models and models:FindFirstChild(snapshot.Target.ModelName)
		assert(
			reference and reference:IsA("Model") and target and target:IsA("Model"),
			"Comparison models have not loaded"
		)
		self.Reference = clone(reference, folder)
		self.Target = clone(target, folder)
		self.TargetSource = target
	end
	self.Arena = snapshot.Arena
	self.StudsPerMeter = self.Config.StudsPerMeter
	self.ReferenceMeters = snapshot.ReferenceMeters
	self:Set(snapshot.Guess, true)
	self:Present(nil)
end
-- The size the mystery model is drawn at: its real value, except during a Lag spike, when it shows the size held
-- from the spike's start times the glitch's jump factor. Only the drawing changes; Value stays the real guess.
local function shownMeters(self: any, value: number): number
	local glitch = self.Glitch
	if not glitch or not glitch.Spike or self.ResultKey then
		return value
	end
	return (self.GlitchHeld or value) * glitch.Factor
end
function PreviewController.Set(self: any, meters: number, immediate: boolean?)
	self.DesiredValue = meters
	if immediate or self.Value == nil then
		self.ScaleVelocity = 0
		self:Draw(meters, shownMeters(self, meters))
	end
end
-- Lag's glitch for this frame (SabotageEffectController.Glitch), or nil. A new spike holds the size it starts at.
function PreviewController.SetGlitch(self: any, glitch: any?)
	if glitch and glitch.Spike then
		if self.GlitchEpisode ~= glitch.Episode then
			self.GlitchEpisode, self.GlitchHeld = glitch.Episode, self.Value
		end
	else
		self.GlitchEpisode, self.GlitchHeld = nil, nil
	end
	self.Glitch = glitch
end
function PreviewController.HitMystery(self: any, position: Vector3, touch: boolean?): boolean
	local camera = self.World.CurrentCamera
	if not camera or not self.Folder or not self.Target or self.ResultKey then
		return false
	end
	if not self.PickParams then
		local parts = {}
		for _, part in self.Target.Model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				-- Only visible parts of this local clone are pickable; originals,
				-- reference, hints and invisible helper geometry stay untouched.
				part.CanQuery = true
				table.insert(parts, part)
			end
		end
		local params = RaycastParams.new()
		params.IncludeInstances = parts
		params.IgnoreWater, params.RespectCanCollide = true, false
		self.PickParams = params
	end
	-- InputObject.Position already uses inset-adjusted screen coordinates.
	local bounds, size = self.Target.Model:GetBoundingBox()
	-- A small touch allowance helps pick thin/small models with a fingertip.
	-- Each sample still has to hit visible target geometry, never a huge GUI box.
	local offsets = if touch then touchPickOffsets else mousePickOffsets
	for _, offset in offsets do
		local ray = camera:ScreenPointToRay(position.X + offset[1], position.Y + offset[2])
		local distance = math.min(15000, (bounds.Position - ray.Origin).Magnitude + size.Magnitude + 1)
		local hit = self.World:Raycast(ray.Origin, ray.Direction * distance, self.PickParams)
		if hit and hit.Instance:IsDescendantOf(self.Target.Model) then
			return true
		end
	end
	return false
end
function PreviewController.SetViewBasis(self: any, basis: CFrame?)
	if basis and basis ~= self.ViewBasis then
		self.ViewBasis, self.ViewDirty = basis, true
	end
end
function PreviewController.Step(self: any, dt: number)
	if not self.Folder or not self.DesiredValue or not self.Value then
		return
	end
	local value, velocity = self.Math.SmoothApproach(self.Value, self.DesiredValue, self.ScaleVelocity, dt, self.Config)
	self.ScaleVelocity = velocity
	local shown = shownMeters(self, value)
	if value ~= self.Value or shown ~= self.ShownMeters or self.ViewDirty then
		self:Draw(value, shown)
	end
end
local function horizontalBounds(model: Model, right: Vector3): (number, number)
	local cf, size = model:GetBoundingBox()
	local half = (
		math.abs(right:Dot(cf.RightVector)) * size.X
		+ math.abs(right:Dot(cf.UpVector)) * size.Y
		+ math.abs(right:Dot(cf.LookVector)) * size.Z
	) * 0.5
	local center = cf.Position:Dot(right)
	return center - half, center + half
end
-- meters: the real selected size. shown: the size to draw the mystery model at (a Lag glitch), meters by default.
function PreviewController.Draw(self: any, meters: number, shown: number?)
	if not self.Folder then
		return
	end
	self.ShownMeters = shown or meters
	self.CachedPoints, self.CachedTargetPoints = nil, nil
	local arena = self.Arena
	local referencePosition, targetPosition = arena.Reference.Position, arena.Target.Position
	local baseline = (referencePosition + targetPosition) * 0.5
	-- Huge ship/animal pairings stay inside a sensible render budget. Apply the
	-- SAME display conversion to both, preserving their exact relative height.
	local units = self.StudsPerMeter
	if self.Config.MaxPreviewExtent and self.Reference.Size and self.Target.Size then
		local a, b = self.Reference.Size, self.Target.Size
		local largest = math.max(
			math.max(a.X, a.Y, a.Z) / self.Reference.Height * self.ReferenceMeters,
			math.max(b.X, b.Y, b.Z) / self.Target.Height * meters
		)
		for _, object in self.ResultGuesses or {} do
			largest = math.max(largest, math.max(b.X, b.Y, b.Z) / self.Target.Height * object.Meters)
		end
		units = math.min(units, self.Config.MaxPreviewExtent / largest)
	end
	if self.ResultKey then
		self:DrawResults(units)
		self.Value = meters
		self.ViewDirty = false
		return
	end
	-- The same unit conversion and floor apply to both models at every tween step.
	-- Re-layout only the local copies along the authored camera axis. Keep their
	-- corrected front orientation, equal depth and reference-left / target-right order.
	local facing = CFrame.new(baseline) * CFrame.Angles(0, math.pi, 0)
	place(self.Reference, self.ReferenceMeters * units, facing)
	place(self.Target, self.ShownMeters * units, facing)
	local horizontal = (self.ViewBasis or arena.Camera).RightVector * Vector3.new(1, 0, 1)
	local right = if horizontal.Magnitude > 0.001 then horizontal.Unit else Vector3.xAxis
	local _, aRight = horizontalBounds(self.Reference.Model, right)
	local bLeft = horizontalBounds(self.Target.Model, right)
	local middle = ((referencePosition + targetPosition) * 0.5):Dot(right)
	local gap = gapFor(self.Config, self.ReferenceMeters * units)
	self.Gap = gap
	self.Reference.Model:PivotTo(self.Reference.Model:GetPivot() + right * (middle - gap * 0.5 - aRight))
	self.Target.Model:PivotTo(self.Target.Model:GetPivot() + right * (middle + gap * 0.5 - bLeft))
	self.Value = meters
	self.ViewDirty = false
	contactShadow(self.Reference, self.Folder, baseline.Y, 1, "ReferenceContactShadow")
	contactShadow(self.Target, self.Folder, baseline.Y, 1, "MysteryContactShadow")
end
-- Public reference measurement only; display studs never become measurement text.
function PreviewController.ReferenceMeasurement(self: any)
	if not self.Folder or not self.Reference then
		return nil
	end
	local bounds, size = self.Reference.Model:GetBoundingBox()
	return bounds, size, self.ReferenceMeters
end
function PreviewController.MysteryMeasurement(self: any)
	if not self.Folder or not self.Target then
		return nil
	end
	local object = self.Target
	if self.ResultKey then
		local sequence = RevealPresentation.Sequence(self.ResultAge or 0, self.Config, #self.ResultGuesses)
		if sequence.Phase == "REFERENCE" then
			return nil
		end
		if sequence.Index then
			object = nil
			for _, guess in self.ResultGuesses do
				if guess.RevealSlot == sequence.Index then
					object = guess
					break
				end
			end
			if not object or (object.ResultOpacity or 0) <= 0 then
				return nil
			end
		elseif (self.ResultActualAlpha or 0) <= 0 then
			return nil
		end
	end
	-- Use visible geometry, never the reserved full-size reveal/camera bounds.
	local bounds, size = object.Model:GetBoundingBox()
	local meters, userId, color = nil, nil, nil
	if self.ResultKey then
		meters = if object == self.Target
			then self.ResultActual
			else object.Meters * math.max(0.0001, (1 - math.cos((object.GrowProgress or 0) * math.pi)) * 0.5)
		-- Only an actual guess growing has an owner; the true-size answer is nobody's attempt.
		if object ~= self.Target then
			userId, color = object.UserId, object.ResultColor
		end
	end
	-- Measurements leave this controller only after the server reveals the round.
	return bounds, size, meters, userId, color
end
function PreviewController.Points(self: any): ({ Vector3 }, { Vector3 })
	if self.CachedPoints then
		return self.CachedPoints, self.CachedTargetPoints
	end
	local points, targetPoints = {}, {}
	if not self.Folder then
		return points, targetPoints
	end
	local objects = { self.Reference, self.Target }
	for _, object in self.ResultGuesses or {} do
		table.insert(objects, object)
	end
	for index, object in objects do
		local cf, size
		if self.ResultKey and object.ResultBounds then
			-- Frame only what is actually visible right now, not the full end-of-reveal layout: the true-size
			-- ghost before it starts growing, and every guess before its own slot (or once it has fully faded
			-- out after its slot), would otherwise hold the camera zoomed out for a guess that is not on screen.
			local visible = object == self.Reference
				or (object == self.Target and (self.ResultActualGrow or 0) > 0)
				or (object ~= self.Reference and object ~= self.Target and (object.ResultOpacity or 0) > 0)
			if visible then
				cf, size = object.Model:GetBoundingBox()
			end
		else
			cf, size = object.Model:GetBoundingBox()
		end
		if not cf then
			continue
		end
		for _, x in { -0.5, 0.5 } do
			for _, y in { -0.5, 0.5 } do
				for _, z in { -0.5, 0.5 } do
					local point = cf:PointToWorldSpace(size * Vector3.new(x, y, z))
					table.insert(points, point)
					if index >= 2 then
						table.insert(targetPoints, point)
					end
				end
			end
		end
	end
	self.CachedPoints, self.CachedTargetPoints = points, targetPoints
	return points, targetPoints
end
local function resultStyle(object, color, transparency, folder, name, fill, preserve: boolean?)
	object.ResultParts = {}
	object.ResultTextures = {}
	for _, part in object.Model:GetDescendants() do
		if part:IsA("BasePart") then
			-- Retain invisible helper geometry as invisible.
			local originalTransparency = part.Transparency
			table.insert(
				object.ResultParts,
				{
					Part = part,
					Transparency = math.max(originalTransparency, transparency),
					OriginalTransparency = originalTransparency,
					OriginalColor = part.Color,
				}
			)
			part.CastShadow = false
			if preserve then
				if part:IsA("MeshPart") then
					table.insert(object.ResultTextures, part)
				end
			else
				part.Transparency = math.max(part.Transparency, transparency)
				part.Color, part.Material = color, Enum.Material.SmoothPlastic
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
			end
		elseif part:IsA("SpecialMesh") or part:IsA("Decal") or part:IsA("Texture") or part:IsA("SurfaceAppearance") then
			if preserve then
				table.insert(object.ResultTextures, part)
			elseif part:IsA("SpecialMesh") then
				part.TextureId = ""
				part.VertexColor = Vector3.one
			else
				part:Destroy()
			end
		elseif part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
			part:Destroy()
		end
	end
	object.ResultColor = color
	local highlight = Instance.new("Highlight")
	highlight.Name, highlight.Adornee, highlight.DepthMode = name, object.Model, Enum.HighlightDepthMode.Occluded
	highlight.FillColor, highlight.OutlineColor = color, color
	highlight.FillTransparency, highlight.OutlineTransparency = fill, 1
	highlight.Parent = folder
	object.ResultHighlight = highlight
end
function PreviewController.ShowResults(self: any, snapshot: any, now: number?)
	if not self.Folder or snapshot.State ~= "ROUND_REVEAL" or not snapshot.Reveal or not snapshot.Reveal.Results then
		return
	end
	local key = snapshot.MatchId .. ":" .. snapshot.RoundId
	if self.ResultKey == key then
		return
	end
	self:ClearHint()
	self:ClearGlow()
	self.ResultKey, self.ResultActual, self.ResultGuesses = key, snapshot.Reveal.Actual, {}
	self.ResultStartedAt = snapshot.Reveal.StartedAt
		or (snapshot.Deadline and snapshot.Deadline - self.Config.RevealDuration(#snapshot.Reveal.Results))
		or now
		or 0
	self.ResultAge = math.max(0, (now or self.ResultStartedAt) - self.ResultStartedAt)
	-- Copy every accepted guess before tinting the original target as the answer. Each guess is coloured by its slot
	-- from this player's point of view (you first, then seat order) and the table size (Config.ResultColor).
	local ordered = RevealPresentation.Order(snapshot.Reveal.Results, snapshot.YourUserId)
	local count = #snapshot.Reveal.Results
	for _, entry in snapshot.Reveal.Results do
		local model = self.Target.Model:Clone()
		model.Name = "ResultGuess_" .. entry.UserId
		model.Parent = self.Folder
		local _, size = model:GetBoundingBox()
		local object = {
			Model = model,
			Height = size.Y,
			Scale = model:GetScale(),
			Size = size,
			Meters = entry.Guess,
			UserId = entry.UserId,
			Accuracy = math.clamp(entry.Accuracy or 0, 0, 100),
		}
		local slot = table.find(ordered, entry) or 1
		local color = Color3.fromRGB(table.unpack(self.Config.ResultColor(slot, count)))
		resultStyle(
			object,
			color,
			self.Config.ResultGuessTransparency,
			self.Folder,
			"GuessHighlight_" .. entry.UserId,
			self.Config.ResultFillTransparency
		)
		-- Strong guesses get a short world-space sparkle/glow. Strength ramps from 80 to 100 accuracy and is driven
		-- by the same reveal progress as the model and score, so it adds no time to the sequence.
		object.ResultStrength = math.clamp((object.Accuracy - 80) / 20, 0, 1)
		-- Celebration belongs only to the local player's result. Particle size is assigned after final result
		-- placement, when the visible bounds are known, so a tiny item never inherits car-sized sparkles.
		if object.ResultStrength > 0 and entry.UserId == snapshot.YourUserId then
			local anchor = model:FindFirstChildWhichIsA("BasePart", true)
			if anchor then
				local sparkles = Instance.new("ParticleEmitter")
				sparkles.Name, sparkles.Enabled = "AccuracySparkles", false
				sparkles.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
				sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				sparkles.LightEmission = 0.7
				sparkles.Lifetime = NumberRange.new(0.35, 0.6)
				sparkles.Rate = 7 + object.ResultStrength * 9
				sparkles.Rotation = NumberRange.new(0, 360)
				sparkles.RotSpeed = NumberRange.new(-100, 100)
				sparkles.Speed = NumberRange.new(0.08, 0.22)
				sparkles.SpreadAngle = Vector2.new(180, 180)
				sparkles.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.05),
					NumberSequenceKeypoint.new(0.72, 0.2),
					NumberSequenceKeypoint.new(1, 1),
				})
				sparkles.Parent = anchor
				object.ResultSparkles = sparkles
			end
		end
		table.insert(self.ResultGuesses, object)
	end
	for slot, entry in ordered do
		for _, object in self.ResultGuesses do
			if object.UserId == entry.UserId then
				object.RevealSlot = slot
			end
		end
	end
	self.Target.Model.Name = "ActualSizeModel"
	resultStyle(
		self.Target,
		Color3.fromRGB(150, 158, 170),
		self.Config.ResultActualTransparency,
		self.Folder,
		"ActualSizeHighlight",
		0.94,
		true
	)
	self:Set(self.ResultActual, true)
end
-- Places a growing result model at this height on its floor spot, then slides it so its left edge stays on the
-- shared column edge: it grows left to right, never back towards the reference.
function PreviewController.GrowLeftAligned(self: any, object: any, height: number)
	place(object, height, object.ResultLocation)
	local right = self.ResultRight
	if right and self.ResultColumnLeft then
		local left = horizontalBounds(object.Model, right)
		object.Model:PivotTo(object.Model:GetPivot() + right * (self.ResultColumnLeft - left))
	end
end
function PreviewController.DrawResults(self: any, units: number)
	local arena = self.Arena
	local baseline = (arena.Reference.Position + arena.Target.Position) * 0.5
	local facing = CFrame.new(baseline) * CFrame.Angles(0, math.pi, 0)
	local horizontal = (self.ViewBasis or arena.Camera).RightVector * Vector3.new(1, 0, 1)
	local right = if horizontal.Magnitude > 0.001 then horizontal.Unit else Vector3.xAxis
	local objects = { self.Reference, self.Target }
	for _, object in self.ResultGuesses do
		table.insert(objects, object)
	end
	local widths = {}
	local targetWidth = 0
	for index, object in objects do
		local meters = if index == 1
			then self.ReferenceMeters
			elseif index == 2 then self.ResultActual
			else object.Meters
		place(object, meters * units, facing)
		local left, edge = horizontalBounds(object.Model, right)
		widths[index] = edge - left
		if index > 1 then
			targetWidth = math.max(targetWidth, widths[index])
		end
	end
	local gap = gapFor(self.Config, self.ReferenceMeters * units)
	self.Gap = gap
	local total = widths[1] + gap + targetWidth
	local cursor = baseline:Dot(right) - total * 0.5
	-- The answer and every guess share one left edge, the gap beside the reference (like the guessing layout), so a
	-- growing model only ever extends to the right (see growLeftAligned) and the framing only ever widens.
	local columnLeft = cursor + widths[1] + gap
	self.ResultRight, self.ResultColumnLeft = right, columnLeft
	for index, object in objects do
		local left = horizontalBounds(object.Model, right)
		local shift = if index == 1 then cursor - left else columnLeft - left
		object.Model:PivotTo(object.Model:GetPivot() + right * shift)
		-- Reserve the completed layout for a steady camera and fixed horizontal
		-- positions. Growth changes only visible geometry, never submitted sizes.
		object.ResultBounds, object.ResultSize = object.Model:GetBoundingBox()
		if object.ResultSparkles then
			local extent = math.max(object.ResultSize.X, object.ResultSize.Y, object.ResultSize.Z)
			local particleSize = math.clamp(extent * 0.035, 0.015, 0.85)
			object.ResultSparkles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, particleSize * 0.55),
				NumberSequenceKeypoint.new(0.45, particleSize),
				NumberSequenceKeypoint.new(1, 0),
			})
		end
		local pivot = object.Model:GetPivot()
		object.ResultLocation = pivot + Vector3.new(0, baseline.Y - pivot.Position.Y, 0)
		object.ResultHeight = object.DisplayHeight
	end
	self:AnimateResults(self.ResultAge or 0, true)
end
function PreviewController.AnimateResults(self: any, age: number, force: boolean?)
	if not self.ResultKey then
		return
	end
	self.ResultAge = math.max(self.ResultAge or 0, age)
	local sequence = RevealPresentation.Sequence(self.ResultAge, self.Config, #self.ResultGuesses)
	local fade = sequence.Grey
	local grow = sequence.ActualGrow
	-- The real-size object grows up from the floor, then fades out completely and leaves a white outline behind.
	if force or fade ~= self.ResultFade or grow ~= self.ResultActualGrow then
		self.ResultFade, self.ResultActualAlpha, self.ResultActualGrow = fade, sequence.ActualAlpha, grow
		-- Camera framing must track what is actually visible right now, not the full end-of-reveal layout.
		self.CachedPoints, self.CachedTargetPoints = nil, nil
		-- The real-size object grows from the floor in its own colours, then fades to a translucent grey ghost.
		for _, entry in self.Target.ResultParts do
			local opacity = entry.OriginalTransparency + (entry.Transparency - entry.OriginalTransparency) * fade
			-- Solid from the first moment it grows (nothing fades in): hidden only before it starts.
			entry.Part.Transparency = if grow > 0 then opacity else 1
			entry.Part.Color = entry.OriginalColor:Lerp(self.Target.ResultColor, fade)
		end
		if self.Target.ResultHighlight then
			self.Target.ResultHighlight.OutlineTransparency = if grow > 0 then 0.2 + 0.65 * fade else 1
			self.Target.ResultHighlight.FillTransparency = if grow > 0 then 0.94 else 1
		end
		-- Roblox models cannot ScaleTo(0): the zero frame is hidden and scaling starts as soon as growth is positive.
		if grow > 0 then
			local eased = (1 - math.cos(grow * math.pi)) * 0.5
			self:GrowLeftAligned(self.Target, self.Target.ResultHeight * math.max(0.0001, eased))
		end
	end
	-- Each guess grows up in its own colour, then fades out completely before the next one appears.
	for _, object in self.ResultGuesses do
		local index = sequence.Index or 0
		local active = index == object.RevealSlot
		local passed = index > object.RevealSlot
		local progress = if active then sequence.Growth elseif passed then 1 else 0
		local started = passed or (active and progress > 0)
		-- How solid the body still is: it stays until the slot's fade, then it is gone.
		local body = if not started then 0 elseif passed then 0 else sequence.Opacity
		if force or object.GrowProgress ~= progress or object.ResultOpacity ~= body then
			object.GrowProgress, object.ResultOpacity = progress, body
			self.CachedPoints, self.CachedTargetPoints = nil, nil
			local eased = (1 - math.cos(progress * math.pi)) * 0.5
			-- Roblox models cannot ScaleTo(0). The zero frame is fully hidden;
			-- start scaling only when growth becomes positive.
			if progress > 0 then
				self:GrowLeftAligned(object, object.ResultHeight * math.max(0.0001, eased))
			end
			for _, entry in object.ResultParts do
				local opacity = 1 - (1 - entry.Transparency) * body
				entry.Part.Transparency = if started then opacity else 1
			end
		end
		local strength = object.ResultStrength or 0
		if object.ResultHighlight then
			local shimmer = 0.82 + 0.18 * math.sin(self.ResultAge * 11 + object.RevealSlot)
			object.ResultHighlight.Enabled = active and body > 0
			object.ResultHighlight.OutlineTransparency = 1 - body * (0.2 + 0.75 * strength) * shimmer
			object.ResultHighlight.FillTransparency = 1 - body * 0.14 * strength
		end
		if object.ResultSparkles then
			object.ResultSparkles.Enabled = active and progress >= 0.58 and body > 0.08
		end
		contactShadow(
			object,
			self.Folder,
			object.ResultLocation.Position.Y,
			body,
			"GuessContactShadow_" .. object.UserId
		)
	end
	local floorY = (self.Arena.Reference.Position.Y + self.Arena.Target.Position.Y) * 0.5
	contactShadow(self.Reference, self.Folder, floorY, 1, "ReferenceContactShadow")
	contactShadow(
		self.Target,
		self.Folder,
		floorY,
		math.clamp(grow * 2, 0, 1) * (1 - 0.6 * fade),
		"MysteryContactShadow"
	)
end
function PreviewController.ClearHint(self: any)
	if self.HintScan then
		self.HintScan:Destroy()
	end
	if self.HintRing then
		self.HintRing:Destroy()
	end
	self.HintData, self.HintScan, self.HintRing = nil, nil, nil
end
function PreviewController.SetHint(self: any, hint: any, now: number)
	if not self.Folder or not self.Target or type(hint) ~= "table" or not hint.ExpiresAt or now >= hint.ExpiresAt then
		self:ClearHint()
		return
	end
	if self.HintData and self.HintData.Id == hint.Id then
		return
	end
	self:ClearHint()
	self.HintData = hint
	-- Cosmetic feedback follows the current guess and cannot reveal the answer.
	local function effect(name: string)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
		part.Material, part.Color, part.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 222, 80), 1
		part.Parent = self.Folder
		return part
	end
	self.HintScan = effect("HintAssistScan")
	self.HintRing = effect("HintAssistRing")
	self.HintRing.Shape = Enum.PartType.Cylinder
	self:StepHint(now)
end
function PreviewController.StepHint(self: any, now: number)
	local data = self.HintData
	if not data then
		return
	end
	if now >= data.ExpiresAt then
		self:ClearHint()
		return
	end
	local age = math.max(0, now - (data.StartedAt or data.ExpiresAt - (self.Config.HintSeconds or 10)))
	local opacity = math.min(1, age / 0.7, math.max(0, data.ExpiresAt - now) / 0.8)
	local frame, size = self.Target.Model:GetBoundingBox()
	local floor = frame.Position.Y - size.Y * 0.5
	local sweep = (age / 3) % 1
	self.HintScan.Size = Vector3.new(math.max(0.05, size.X * 1.06), 0.025, math.max(0.05, size.Z * 1.06))
	self.HintScan.CFrame = CFrame.new(frame.Position.X, floor + size.Y * sweep, frame.Position.Z)
	self.HintScan.Transparency = 1 - 0.3 * opacity * math.sin(sweep * math.pi)
	local radius = math.max(size.X, size.Z, 0.1) * (0.4 + 0.8 * sweep)
	self.HintRing.Size = Vector3.new(0.025, radius, radius)
	self.HintRing.CFrame = CFrame.new(frame.Position.X, floor + 0.015, frame.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	self.HintRing.Transparency = 1 - 0.25 * opacity * (1 - sweep)
end
function PreviewController.ClearGlow(self: any)
	if self.TargetGlow then
		self.TargetGlow:Destroy()
		self.TargetGlow = nil
	end
	if self.ReferenceGlow then
		self.ReferenceGlow:Destroy()
		self.ReferenceGlow = nil
	end
end
function PreviewController.SetObjectHovered(self: any, hovered: boolean)
	-- Keep the existing white outline steady. Only deliberate mouse hover adds
	-- a faint fill; no competing highlight instances or pulsing effects.
	-- A Lag spike's glitch colours own the fill while they flicker.
	if self.TargetGlow and not (self.Glitch and self.Glitch.Spike) then
		self.TargetGlow.FillTransparency = if hovered and not self.ResultKey then 0.93 else 1
	end
end
function PreviewController.Present(self: any, view: any)
	if not self.Folder then
		self:ClearGlow()
		return
	end
	if self.ResultKey then
		if view then
			self:AnimateResults(view.Age or 0)
		end
		return
	end
	if not self.TargetGlow then
		local highlight = Instance.new("Highlight")
		highlight.Name, highlight.Adornee = "TargetGlow", self.Target.Model
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor, highlight.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
		highlight.FillTransparency, highlight.OutlineTransparency = 1, 0
		highlight.Parent = self.Target.Model
		self.TargetGlow = highlight
	end
	-- Keep a steady white outline through scaling, watching and reveal; only a Lag glitch recolours it.
	local glitch = self.Glitch
	self.TargetGlow.FillTransparency = if glitch then glitch.Fill else 1
	self.TargetGlow.FillColor = if glitch then glitch.Color else Color3.new(1, 1, 1)
	self.TargetGlow.OutlineColor = if glitch then glitch.Color else Color3.new(1, 1, 1)
	self.TargetGlow.OutlineTransparency = 0
	if not view then
		if self.ReferenceGlow then
			self.ReferenceGlow:Destroy()
			self.ReferenceGlow = nil
		end
		return
	end
	if not self.ReferenceGlow then
		local highlight = Instance.new("Highlight")
		highlight.Name, highlight.Adornee = "ReferenceGlow", self.Reference.Model
		highlight.DepthMode, highlight.Parent = Enum.HighlightDepthMode.Occluded, self.Reference.Model
		self.ReferenceGlow = highlight
	end
	local counting = view.Phase == "COUNT"
	self.ReferenceGlow.FillTransparency = 1
	self.ReferenceGlow.OutlineColor = Color3.fromRGB(125, 225, 255)
	self.ReferenceGlow.OutlineTransparency = if counting then 0.6 else 0.85
end
function PreviewController.Clear(self: any)
	self:ClearHint()
	self:ClearGlow()
	if self.Folder then
		self.Folder:Destroy()
	end
	self.Folder, self.Reference, self.Target, self.Arena = nil, nil, nil, nil
	self.Value, self.DesiredValue, self.ShownMeters = nil, nil, nil
	self.Glitch, self.GlitchEpisode, self.GlitchHeld = nil, nil, nil
	self.ScaleVelocity = 0
	self.PickParams = nil
	self.ViewBasis, self.ViewDirty = nil, false
	self.ResultKey, self.ResultActual, self.ResultGuesses = nil, nil, nil
	self.ResultAge, self.ResultStartedAt, self.ResultFade = nil, nil, nil
	self.ResultActualAlpha, self.ResultTexturesCleared = nil, nil
	self.ResultRight, self.ResultColumnLeft = nil, nil
	self.CachedPoints, self.CachedTargetPoints = nil, nil
end
return PreviewController

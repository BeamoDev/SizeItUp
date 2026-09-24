--!strict
local CameraController = {}
CameraController.__index = CameraController
function CameraController.new(
	world: Workspace,
	player: Player,
	input: UserInputService,
	config: any,
	interrupted: () -> ()
)
	local self: any = setmetatable(
		{ World = world, Player = player, Input = input, Config = config, Interrupted = interrupted },
		CameraController
	)
	self.Connection = world:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if self.Saved then
			self:Stop()
			interrupted()
		end
	end)
	return self
end
function CameraController.Start(self: any, arena: any)
	self:ClearTableEffect()
	self.ResultSettle = nil
	if not self.Saved then
		local camera = self.World.CurrentCamera
		assert(camera, "No current camera")
		self.Saved = {
			Camera = camera,
			Type = camera.CameraType,
			Subject = camera.CameraSubject,
			CFrame = camera.CFrame,
			Focus = camera.Focus,
			Fov = camera.FieldOfView,
			Mouse = self.Input.MouseBehavior,
			Icon = self.Input.MouseIconEnabled,
		}
		self.From = camera.CFrame
		self.Elapsed = 0
	end
	self.From, self.FromFov, self.Elapsed = self.Saved.Camera.CFrame, self.Saved.Camera.FieldOfView, 0
	self.Mode = "ARENA"
	self.Arena = arena
	local baseline = if arena.Reference and arena.Target
		then (arena.Reference.Position + arena.Target.Position) * 0.5
		else Vector3.zero
	self.ArenaOrigin = baseline
	self.FramingEye, self.FramingFov = nil, nil
	self.ViewBasis = arena.Camera.Rotation
	self.Saved.Camera.CameraType = Enum.CameraType.Scriptable
	self.Input.MouseBehavior, self.Input.MouseIconEnabled = Enum.MouseBehavior.Default, true
end
-- A short presentation settle before the result sequence starts. It uses the live framing destination, so a large
-- final guess remains safely in frame while the camera eases out of the last interactive movement.
function CameraController.BeginResultSettle(self: any, key: string)
	if self.ResultSettleKey == key or not self.Saved then
		return
	end
	local camera = self.Saved.Camera
	self.ResultSettleKey = key
	self.ResultSettle = { Elapsed = 0, Duration = 0.15, From = camera.CFrame, FromFov = camera.FieldOfView }
end
local function isTableMiniature(instance: Instance): boolean
	if not instance:IsA("BasePart") then
		return false
	end
	local name = instance.Name
	return name == "ReferenceMiniature" or name == "TargetMiniature"
end

local function isChairFx(item: Instance): boolean
	if
		not (
			item:IsA("ParticleEmitter")
			or item:IsA("PointLight")
			or item:IsA("Sparkles")
			or item:IsA("Trail")
			or item:IsA("Highlight")
		)
	then
		return false
	end
	local name = item.Name or ""
	return string.sub(name, 1, 7) == "ChairFx"
end

function CameraController.ClearTableEffect(self: any)
	if self.HiddenCutscene then
		for _, entry in self.HiddenCutscene do
			if not entry.Object or not entry.Object.Parent then
				continue
			end
			if entry.Object:IsA("BasePart") then
				entry.Object.Transparency = entry.StoredTransparency
				entry.Object.LocalTransparencyModifier = entry.StoredLocalTransparencyModifier
				entry.Object.Visible = entry.StoredVisible
			elseif
				entry.Object:IsA("ParticleEmitter")
				or entry.Object:IsA("PointLight")
				or entry.Object:IsA("Sparkles")
				or entry.Object:IsA("Trail")
			then
				entry.Object.Enabled = entry.StoredEnabled
			end
		end
		self.HiddenCutscene = nil
	end
	if self.DepthOfField then
		self.DepthOfField:Destroy()
		self.DepthOfField = nil
	end
	self.TableView, self.TargetPlayer = nil, nil
end

function CameraController.HideTableCutscene(self: any)
	if self.HiddenCutscene then
		return
	end
	self.HiddenCutscene = {}
	for _, object in self.World:GetDescendants() do
		if not object.Parent then
			continue
		end
		if object:IsA("Model") and object.Name == "TableDisplay" then
			for _, child in object:GetDescendants() do
				if isTableMiniature(child) then
					table.insert(self.HiddenCutscene, {
						Object = child,
						StoredTransparency = child.Transparency,
						StoredLocalTransparencyModifier = child.LocalTransparencyModifier,
						StoredVisible = child.Visible,
					})
					child.Transparency = 1
					child.LocalTransparencyModifier = 1
					child.Visible = false
				end
			end
		end
		if isChairFx(object) then
			table.insert(self.HiddenCutscene, {
				Object = object,
				StoredEnabled = object.Enabled,
			})
			object.Enabled = false
		end
	end
end

function CameraController.StartTable(self: any, view: any, target: Player?)
	assert(view, "Missing table camera framing")
	if not self.Saved then
		self:Start({ Camera = view.Camera })
	end
	if self.Mode ~= "TABLE" then
		self.From, self.FromFov, self.Elapsed = self.Saved.Camera.CFrame, self.Saved.Camera.FieldOfView, 0
		local effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "ScaleItUpTableFocus"
		effect.NearIntensity, effect.FarIntensity = self.Config.TableBlurIntensity, self.Config.TableBlurIntensity
		effect.InFocusRadius, effect.FocusDistance =
			self.Config.TableFocusRadius, (view.Camera.Position - view.Focus).Magnitude
		effect.Parent = self.Saved.Camera
		self.DepthOfField = effect
	end
	self.Mode, self.TableView = "TABLE", view
	self:HideTableCutscene()
	if target ~= nil then
		self.TargetPlayer = target
	end
end
-- Ease from the current pose onto the next seated player. Each reaction slot must start a fresh look, or the first
-- avatar keeps the camera while the HUD cycles through everyone else.
function CameraController.FocusTablePlayer(self: any, target: Player?)
	if self.TargetPlayer == target then
		return
	end
	if self.Saved and self.Mode == "TABLE" then
		self:HideTableCutscene()
		self.From, self.FromFov, self.Elapsed = self.Saved.Camera.CFrame, self.Saved.Camera.FieldOfView, 0
	end
	self.TargetPlayer = target
end
function CameraController.StepTable(self: any, dt: number)
	local view, camera = self.TableView, self.Saved.Camera
	local character = self.TargetPlayer and self.TargetPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local focus = view.Focus
	if head and head:IsA("BasePart") then
		focus = head.Position
	end
	local anchor = view.Camera.Position
	if head and head:IsA("BasePart") then
		-- Match WorldBindings.ReactionView exactly. The newer root-based close-up could use a seated NPC's adjusted
		-- root orientation and put the camera beside or behind it when the reaction advanced to that bot.
		local flat = head.CFrame.LookVector * Vector3.new(1, 0, 1)
		local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		anchor = focus + forward * 7 + forward:Cross(Vector3.yAxis) * 1.6 + Vector3.new(0, 0.5, 0)
	end
	local desired = CFrame.lookAt(anchor, focus)
	self.Elapsed += dt
	local alpha = math.clamp(self.Elapsed / self.Config.CameraTweenSeconds, 0, 1)
	local eased = 1 - (1 - alpha) ^ 3
	camera.CFrame = self.From:Lerp(desired, eased)
	camera.FieldOfView = self.FromFov + (self.Config.TableCameraFieldOfView - self.FromFov) * eased
	camera.Focus = CFrame.new(focus)
	self.DepthOfField.FocusDistance = (camera.CFrame.Position - focus).Magnitude
	self.Input.MouseBehavior = Enum.MouseBehavior.Default
	-- A faint handheld wobble once the cut has settled: still cameras read as static shots; a little constant
	-- drift (never a shake on the cut itself) reads as someone actually holding it.
	self.TableJitterClock = (self.TableJitterClock or 0) + dt
	local jitter = math.clamp(alpha * 3, 0, 1) * 0.7 -- degrees of handheld sway (2x the original 0.35)
	local jt = self.TableJitterClock
	local wobbleX = (math.noise(jt * 0.6, self.TableJitterSeed or 0) - 0) * jitter
	local wobbleY = (math.noise(jt * 0.5, (self.TableJitterSeed or 0) + 31.7) - 0) * jitter
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(wobbleY), math.rad(wobbleX), 0)
end
function CameraController.Step(self: any, dt: number, points: { Vector3 }, targetPoints: { Vector3 }?)
	if not self.Saved then
		return
	end
	if self.Mode == "TABLE" then
		self:StepTable(dt)
		return
	end
	if #points == 0 then
		return
	end
	local camera = self.Saved.Camera
	local basis = self.ViewBasis or self.Arena.Camera.Rotation
	local origin = self.ArenaOrigin
	local function bounds(list: { Vector3 })
		local minimum, maximum =
			Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, point in list do
			local value = basis:VectorToObjectSpace(point - origin)
			minimum =
				Vector3.new(math.min(minimum.X, value.X), math.min(minimum.Y, value.Y), math.min(minimum.Z, value.Z))
			maximum =
				Vector3.new(math.max(maximum.X, value.X), math.max(maximum.Y, value.Y), math.max(maximum.Z, value.Z))
		end
		return minimum, maximum
	end
	local minimum, maximum = bounds(points)
	local hasTarget = targetPoints ~= nil and #targetPoints > 0
	local targetMin, targetMax = minimum, maximum
	if hasTarget then
		targetMin, targetMax = bounds(targetPoints :: { Vector3 })
	end
	local size, targetSize = maximum - minimum, targetMax - targetMin
	local center = (minimum + maximum) * 0.5
	local aspect = math.max(0.25, camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y))
	-- Read the platform's actual near plane; protect both objects.
	local near = math.abs(camera.NearPlaneZ or -0.5) + 0.05
	local wantedFov = self.Config.CameraFieldOfView
	if hasTarget then
		-- A long lens with a matching dolly back reduces perspective distortion.
		-- Never pan into the target: the reference must remain a usable ruler.
		local fraction = targetSize.Y / math.max(size.Y, 0.0001)
		local compression = math.clamp(1 - fraction / 0.5, 0, 1)
		wantedFov += (self.Config.CameraMinimumFieldOfView - wantedFov) * compression
	end
	local alpha = 1 - math.exp(-self.Config.CameraFollowSpeed * math.max(0, dt))
	self.FramingFov = if self.SnapNext or not self.FramingFov
		then wantedFov
		else self.FramingFov + (wantedFov - self.FramingFov) * alpha
	local fov = self.FramingFov
	local tanY = math.tan(math.rad(fov * 0.5))
	local function eyeFor(low: Vector3, high: Vector3, verticalFill: number, horizontalFill: number)
		local extent = high - low
		local midpoint = (low + high) * 0.5
		local distance =
			math.max(extent.Y / (2 * tanY * verticalFill), extent.X / (2 * tanY * aspect * horizontalFill), near)
		return Vector3.new(midpoint.X, midpoint.Y, high.Z + distance)
	end
	local desiredEye = eyeFor(minimum, maximum, 0.42, 0.74)
	-- Smooth framing in the authored camera's coordinate system.
	local eye = if self.SnapNext or not self.FramingEye then desiredEye else self.FramingEye:Lerp(desiredEye, alpha)
	-- Growing rapidly or resizing the viewport can outpace a smooth follow.
	-- Pull back only as far as needed to keep BOTH models safely visible.
	local safeZ = eye.Z
	for _, point in points do
		local value = basis:VectorToObjectSpace(point - origin)
		safeZ = math.max(
			safeZ,
			value.Z + near,
			value.Z + math.abs(value.X - eye.X) / (tanY * aspect * 0.84),
			value.Z + math.abs(value.Y - eye.Y) / (tanY * 0.5)
		)
	end
	eye = Vector3.new(eye.X, eye.Y, safeZ)
	self.FramingEye = eye
	local focus = origin + basis:VectorToWorldSpace(center)
	local desired = CFrame.new(origin + basis:VectorToWorldSpace(eye)) * basis
	self.Elapsed += dt
	local progress = math.clamp(self.Elapsed / self.Config.CameraTweenSeconds, 0, 1)
	if self.SnapNext or progress >= 1 then
		camera.CFrame = desired
	else
		camera.CFrame = self.From:Lerp(desired, 1 - (1 - progress) ^ 3)
	end
	local settledFov = fov
	if self.ResultSettle then
		local settle = self.ResultSettle
		settle.Elapsed += math.max(0, dt)
		local at = math.clamp(settle.Elapsed / settle.Duration, 0, 1)
		local eased = at * at * (3 - 2 * at)
		camera.CFrame = settle.From:Lerp(camera.CFrame, eased)
		settledFov = settle.FromFov + (fov - settle.FromFov) * eased
		if at >= 1 then
			self.ResultSettle = nil
		end
	end
	-- Wobble (a watcher's troll) rolls the view gently; it is recomputed every frame, so it never accumulates.
	-- The 2D overlays (rulers, hint ranges) keep the un-rolled view (see Steady), so they never tilt with the wobble.
	self.Unrolled = if self.Sway and self.Sway ~= 0 then camera.CFrame else nil
	if self.Sway and self.Sway ~= 0 then
		camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, self.Sway)
	end
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = settledFov
	-- Lag (a watcher's troll) freezes the picture in bursts: the camera holds the pose it had when the burst began.
	if self.Frozen then
		if not self.Held then
			self.Held = { camera.CFrame, camera.FieldOfView }
		end
		camera.CFrame, camera.FieldOfView = self.Held[1], self.Held[2]
	else
		self.Held = nil
	end
	self.Input.MouseBehavior = Enum.MouseBehavior.Default
end
-- A stand-in for the camera that projects with the view BEFORE the wobble's roll is applied. The reference/mystery rulers and
-- the hint ranges are drawn through it, so they stay upright (same Y axis) while a Wobble rolls the picture. Without a roll it is
-- simply the real camera.
function CameraController.Steady(self: any, camera: any): any
	local base = self.Unrolled
	if not base or not camera then
		return camera
	end
	local size, fov = camera.ViewportSize, camera.FieldOfView
	local function project(_: any, point: Vector3): (Vector3, boolean)
		local offset = base:PointToObjectSpace(point)
		local depth = -offset.Z
		local scale = (size.Y * 0.5) / math.tan(math.rad(fov) * 0.5) / math.max(math.abs(depth), 1e-4)
		return Vector3.new(size.X * 0.5 + offset.X * scale, size.Y * 0.5 - offset.Y * scale, depth), depth > 0
	end
	return {
		CFrame = base,
		ViewportSize = size,
		FieldOfView = fov,
		WorldToViewportPoint = project,
		WorldToScreenPoint = project,
	}
end
function CameraController.Snap(self: any, points: { Vector3 }, targetPoints: { Vector3 }?)
	if not self.Saved then
		return
	end
	self.Elapsed = self.Config.CameraTweenSeconds
	self.SnapNext = true
	self:Step(0, points, targetPoints)
	self.SnapNext = nil
end
function CameraController.Stop(self: any)
	self:ClearTableEffect()
	self.Mode = nil
	self.ViewBasis = nil
	self.FramingEye, self.FramingFov = nil, nil
	self.ResultSettle, self.ResultSettleKey = nil, nil
	local saved = self.Saved
	if not saved then
		return
	end
	self.Saved, self.Arena = nil, nil
	local character = self.Player.Character
	local fallback = character and character:FindFirstChildOfClass("Humanoid")
	local subject = if saved.Subject and saved.Subject.Parent then saved.Subject else fallback
	for _, camera in { saved.Camera, self.World.CurrentCamera } do
		if camera and camera.Parent then
			camera.CameraType = saved.Type
			camera.CameraSubject = subject
			camera.CFrame, camera.Focus, camera.FieldOfView = saved.CFrame, saved.Focus, saved.Fov
		end
	end
	-- Never hand back a locked or hidden cursor: a stale LockCenter/hidden icon left the mouse missing after games.
	-- Roblox's own camera scripts re-lock it themselves if the player really is in shift lock or first person.
	self.Input.MouseBehavior, self.Input.MouseIconEnabled = Enum.MouseBehavior.Default, true
end
function CameraController.Destroy(self: any)
	self:Stop()
	self.Connection:Disconnect()
end
return CameraController

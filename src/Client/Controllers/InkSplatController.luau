--!strict
-- Ink splat sabotage: a watcher's ink sprays onto every other player's screen in the match.
-- Purely local and cosmetic, driven by server timestamps. It sits beneath the HUD
-- (negative DisplayOrder, nothing Active), so the slider, Lock In and direct dragging
-- keep working. Every size derives from the screen's SHORTER side and every position
-- from screen fractions, so it looks right on phones, tablets, desktops and ultrawides.
local InkSplat = {}
InkSplat.__index = InkSplat

local BLOB_COUNT = 7
local SPAWN_GAP = 0.11 -- seconds between splats landing
local IMPACT_SECONDS = 0.22
local DRIP_SECONDS = 2.4
local FADE_SECONDS = 1.2 -- gentle fade before the effect ends
local RELEASE_SECONDS = 0.3 -- quick fade when the turn ends early
local INK = Color3.fromRGB(16, 12, 38)
local SHEEN = Color3.fromRGB(190, 175, 255)
local BASE_TRANSPARENCY = 0.04

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end
local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function generator(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483647
	if state <= 0 then
		state = 1
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Pure and deterministic: the same seed always plans the same splats. Lengths are in units
-- of u (the shorter screen side); centres are screen fractions kept away from the very edges.
function InkSplat.Plan(seed: number): { any }
	local rand = generator(seed)
	local function between(low: number, high: number): number
		return low + (high - low) * rand()
	end
	local blobs = {}
	for index = 1, BLOB_COUNT do
		local radius = between(0.10, 0.16)
		local blob: any = {
			Cx = between(0.15, 0.85),
			Cy = between(0.22, 0.78),
			Radius = radius,
			Delay = (index - 1) * SPAWN_GAP,
			Lobes = { { Dx = 0, Dy = 0, R = radius } },
			Droplets = {},
			Drips = {},
		}
		for _ = 1, 2 do
			local angle = between(0, math.pi * 2)
			table.insert(
				blob.Lobes,
				{
					Dx = math.cos(angle) * radius * 0.6,
					Dy = math.sin(angle) * radius * 0.6,
					R = radius * between(0.55, 0.75),
				}
			)
		end
		for _ = 1, math.floor(between(6, 10)) do
			table.insert(blob.Droplets, {
				Angle = between(0, math.pi * 2),
				Distance = radius * between(1.2, 2.2),
				R = radius * between(0.1, 0.3),
				Delay = between(0, 0.06),
			})
		end
		for _ = 1, math.floor(between(2, 4)) do
			table.insert(
				blob.Drips,
				{
					Dx = between(-0.6, 0.6) * radius,
					Width = radius * between(0.16, 0.26),
					Length = radius * between(0.9, 2),
					Delay = between(0.15, 0.5),
				}
			)
		end
		table.insert(blobs, blob)
	end
	return blobs
end

function InkSplat.new(deps: any)
	return setmetatable({ D = deps, Parts = {} }, InkSplat)
end

local function paint(gui: Frame, shape: boolean)
	gui.BackgroundColor3, gui.BorderSizePixel, gui.Active = INK, 0, false
	gui.AnchorPoint = if shape then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = gui
end

-- The authored HUD.Effects frame (when the HUD has one) hosts this overlay; otherwise it gets its own ScreenGui.
local function holder(deps: any, name: string, order: number): (Instance, Instance)
	local effects = if deps.Effects then deps.Effects() else nil
	if effects and effects:IsA("GuiObject") then
		local frame = Instance.new("Frame")
		frame.Name, frame.Size, frame.BackgroundTransparency, frame.BorderSizePixel, frame.Active =
			name, UDim2.fromScale(1, 1), 1, 0, false
		frame.ZIndex = order
		effects.Visible = true
		return frame, effects
	end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = name, false, true, order
	return gui, deps.PlayerGui
end

function InkSplat.Build(self: any, plan: { any })
	local gui, parent = holder(self.D, "ScaleInkSplat", -50)
	local root = Instance.new("Frame")
	root.Name, root.Size, root.BackgroundTransparency, root.BorderSizePixel, root.Active =
		"Ink", UDim2.fromScale(1, 1), 1, 0, false
	root.Parent = gui
	self.Gui, self.Root, self.Plan, self.Parts = gui, root, plan, {}
	for _, blob in plan do
		local ring = Instance.new("Frame")
		ring.Name, ring.AnchorPoint, ring.BackgroundTransparency, ring.BorderSizePixel, ring.Active =
			"ImpactRing", Vector2.new(0.5, 0.5), 1, 0, false
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(0.5, 0)
		ringCorner.Parent = ring
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color, ringStroke.Thickness, ringStroke.Transparency = SHEEN, 5, 1
		ringStroke.Parent = ring
		ring.Parent = root
		table.insert(self.Parts, { Kind = "ImpactRing", Frame = ring, Stroke = ringStroke, Blob = blob, Spec = blob.Lobes[1] })
		for _, lobe in blob.Lobes do
			local frame = Instance.new("Frame")
			frame.Name = "Lobe"
			paint(frame, false)
			frame.Parent = root
			table.insert(self.Parts, { Kind = "Lobe", Frame = frame, Blob = blob, Spec = lobe })
		end
		for _, droplet in blob.Droplets do
			local frame = Instance.new("Frame")
			frame.Name = "Droplet"
			paint(frame, false)
			frame.Parent = root
			table.insert(self.Parts, { Kind = "Droplet", Frame = frame, Blob = blob, Spec = droplet })
		end
		for _, drip in blob.Drips do
			local frame = Instance.new("Frame")
			frame.Name = "Drip"
			paint(frame, true)
			frame.Parent = root
			table.insert(self.Parts, { Kind = "Drip", Frame = frame, Blob = blob, Spec = drip })
		end
		local sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		paint(sheen, false)
		sheen.BackgroundColor3 = SHEEN
		sheen.Parent = root
		table.insert(self.Parts, { Kind = "Sheen", Frame = sheen, Blob = blob, Spec = blob.Lobes[1] })
	end
	local banner = Instance.new("TextLabel")
	banner.Name, banner.AnchorPoint, banner.BackgroundTransparency, banner.BorderSizePixel, banner.Active =
		"Banner", Vector2.new(0.5, 0.5), 1, 0, false
	banner.Size, banner.Position = UDim2.fromScale(0.75, 0.18), UDim2.fromScale(0.5, 0.46)
	banner.Font, banner.Text, banner.TextScaled = Enum.Font.GothamBlack, "SPLAT!", true
	banner.ZIndex = 10
	banner.TextColor3, banner.TextStrokeColor3, banner.TextStrokeTransparency = SHEEN, INK, 0
	banner.Parent = root
	table.insert(self.Parts, { Kind = "Banner", Frame = banner })
	gui.Parent = parent
end

-- Lay every shape out for the current viewport, event age and fade.
function InkSplat.Layout(self: any, age: number, fade: number, viewport: Vector2)
	local u = math.min(viewport.X, viewport.Y)
	for _, part in self.Parts do
		if part.Kind == "Banner" then
			local pop = easeOutBack(clamp01(age / 0.28))
			local linger = 1 - clamp01((age - 1.05) / 0.45)
			part.Frame.Visible = linger > 0
			part.Frame.TextTransparency = 1 - fade * linger
			part.Frame.TextStrokeTransparency = 1 - fade * linger
			part.Frame.Size = UDim2.fromScale(0.75 * pop, 0.18 * pop)
			part.Frame.Rotation = math.sin(age * 14) * 4 * linger
			continue
		end
		local blob, spec, frame = part.Blob, part.Spec, part.Frame
		local t = age - blob.Delay
		local cx, cy = blob.Cx * viewport.X, blob.Cy * viewport.Y
		local diameter, x, y, tone = 0, cx, cy, BASE_TRANSPARENCY
		if part.Kind == "ImpactRing" then
			if t >= 0 then
				local ringAge = clamp01(t / 0.42)
				diameter = blob.Radius * u * (1.5 + ringAge * 2.4)
				part.Stroke.Transparency = 1 - fade * (1 - ringAge)
				part.Stroke.Thickness = math.max(1, 7 * (1 - ringAge))
			else
				part.Stroke.Transparency = 1
			end
		elseif part.Kind == "Lobe" then
			diameter = 2 * spec.R * u * easeOutBack(clamp01(t / IMPACT_SECONDS))
			x, y = cx + spec.Dx * u, cy + spec.Dy * u
		elseif part.Kind == "Droplet" then
			local local_t = t - spec.Delay
			diameter = 2 * spec.R * u * easeOutBack(clamp01(local_t / 0.2))
			local travel = spec.Distance * u * easeOutQuad(clamp01(local_t / 0.3))
			x, y = cx + math.cos(spec.Angle) * travel, cy + math.sin(spec.Angle) * travel
		elseif part.Kind == "Sheen" then
			local main = blob.Lobes[1]
			diameter = 0.5 * main.R * u * easeOutBack(clamp01((t - 0.05) / IMPACT_SECONDS))
			x, y = cx - main.R * u * 0.35, cy - main.R * u * 0.4
			tone = 0.8
		end
		if part.Kind == "Drip" then
			local length = spec.Length * u * easeOutQuad(clamp01((t - spec.Delay) / DRIP_SECONDS))
			local width = spec.Width * u
			frame.Visible = length > 0.5
			frame.Size = UDim2.fromOffset(width, length)
			frame.Position = UDim2.fromOffset(cx + spec.Dx * u, cy + blob.Radius * u * 0.55)
		else
			frame.Visible = diameter > 0.5
			frame.Size = UDim2.fromOffset(diameter, diameter)
			frame.Position = UDim2.fromOffset(x, y)
		end
		if part.Kind ~= "ImpactRing" then
			frame.BackgroundTransparency = 1 - (1 - tone) * fade
		end
	end
end

function InkSplat.Clear(self: any)
	if self.Gui then
		self.Gui:Destroy()
	end
	self.Gui, self.Root, self.Plan, self.Id, self.ReleasedAt = nil, nil, nil, nil, nil
	self.Parts = {}
end

-- snapshot: the local player's match snapshot (nil outside a match). now: shared server time.
function InkSplat.Step(self: any, snapshot: any, now: number)
	-- Only the ink splat itself is drawn here; Lag, FogBank and Wobble belong to SabotageEffectController.
	-- Effects run side by side, so pick the ink among everything currently running.
	local event = nil
	if snapshot then
		for _, candidate in snapshot.InkSplats or { snapshot.InkSplat } do
			if candidate.Kind == nil or candidate.Kind == "Ink" then
				event = candidate
			end
		end
	end
	local live = event ~= nil
		and snapshot.MatchId ~= nil
		and snapshot.State == "GUESSING"
		and now >= event.StartedAt
		and now < event.ExpiresAt
	if live then
		local id = tostring(snapshot.MatchId) .. ":" .. tostring(event.Id)
		if self.Id ~= id then
			self:Clear()
			self.Id = id
			self:Build(InkSplat.Plan(event.Seed))
		end
		self.ReleasedAt = nil
		self.Event = event
		self:Layout(now - event.StartedAt, clamp01((event.ExpiresAt - now) / FADE_SECONDS), self.D.Viewport())
		return
	end
	if not self.Gui then
		return
	end
	-- The effect ended (turn locked, expired, or you threw it): fade out quickly, then remove.
	self.ReleasedAt = self.ReleasedAt or now
	local fade = 1 - clamp01((now - self.ReleasedAt) / RELEASE_SECONDS)
	if fade <= 0 or not self.Event then
		self:Clear()
		return
	end
	self:Layout(
		math.max(0, self.ReleasedAt - self.Event.StartedAt),
		math.min(fade, clamp01((self.Event.ExpiresAt - self.ReleasedAt) / FADE_SECONDS)),
		self.D.Viewport()
	)
end

function InkSplat.Destroy(self: any)
	self:Clear()
end

return InkSplat

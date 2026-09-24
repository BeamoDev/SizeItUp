--!strict
-- The troll effects a watcher can set off besides ink: Lag, FogBank and Wobble. The server puts one event
-- (InkSplat with a Kind) in every player's snapshot for a few seconds; everyone in the match sees it, the thrower too.
-- Purely visual: nothing is Active (the slider, Lock In and dragging keep working), nothing reveals the answer, and the
-- shapes all come from the screen's shorter side. Wobble is a gentle camera roll (Sway) applied by CameraController.
--   Lag        seeded "lag spikes": the camera freezes (Frozen, applied by CameraController) while the mystery
--              model glitches -- it jumps to a new size about 14 times a second, its white outline flickers magenta /
--              cyan / green with a coloured fill, and input seems to stop until the spike ends and the model snaps
--              back (Glitch, drawn by PreviewController; the real guess never changes). Between spikes the outline
--              keeps a faint pulsing cyan tint. The authored Game.Lagging frame is shown via Sabotage.Active.
--   FogBank    fog that keeps thickening until, near the end, nothing can be seen (never blocks input)
--   Wobble     the camera slowly rolls a full 360 degrees over the whole effect
local Sabotage = {}
Sabotage.__index = Sabotage

local FADE_IN, FADE_OUT, RELEASE_SECONDS = 0.35, 0.6, 0.4
local FOG_BANKS = 10
local FOG_COLOR = Color3.fromRGB(228, 234, 242)
-- Lag spikes: how often the model jumps to a new size/colour, how far (log scale), and the glitch colours.
local GLITCH_STEP = 0.07
local GLITCH_SHRINK, GLITCH_GROW = -0.5, 0.42
local GLITCH_CYAN = Color3.fromRGB(60, 235, 255)
local GLITCH_COLORS = {
	Color3.fromRGB(255, 60, 220),
	GLITCH_CYAN,
	Color3.fromRGB(120, 255, 130),
	Color3.fromRGB(255, 255, 255),
}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- kind: the one effect this instance draws (several run together, one instance each); nil draws any non-ink effect.
function Sabotage.new(deps: any, kind: string?)
	return setmetatable({ D = deps, Parts = {}, Only = kind }, Sabotage)
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

local function root(self: any): Frame
	local gui, parent = holder(self.D, "ScaleSabotage", -49)
	local frame = Instance.new("Frame")
	frame.Name, frame.Size, frame.BackgroundTransparency, frame.BorderSizePixel, frame.Active =
		"Effect", UDim2.fromScale(1, 1), 1, 0, false
	frame.ClipsDescendants = true
	frame.Parent = gui
	gui.Parent = parent
	self.Gui = gui
	return frame
end

-- Builds the effect's pooled pieces once from the event seed, so every player sees the same attack without creating
-- instances every frame. Game.Lagging and the HUD panel throw remain driven by Sabotage.Active.
function Sabotage.Build(self: any, kind: string, seed: number, duration: number?)
	local random = Random.new(seed)
	self.Root, self.Kind, self.Parts, self.Duration = nil, kind, {}, duration or 9
	self.Freezes = {}
	local frame = root(self)
	self.Root = frame
	local banner = Instance.new("TextLabel")
	banner.Name, banner.AnchorPoint, banner.BackgroundTransparency, banner.BorderSizePixel, banner.Active =
		"TrollBanner", Vector2.new(0.5, 0.5), 1, 0, false
	banner.Position, banner.Size = UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.8, 0.18)
	banner.Font, banner.TextScaled = Enum.Font.GothamBlack, true
	banner.ZIndex = 10
	banner.Text = if kind == "Lag" then "LAG ATTACK!" elseif kind == "FogBank" then "LOST IN THE FOG!" else "WHEEE!"
	banner.TextColor3, banner.TextStrokeColor3, banner.TextStrokeTransparency = Color3.new(1, 1, 1), Color3.new(0, 0, 0), 0
	banner.Parent = frame
	table.insert(self.Parts, { Kind = "Banner", Node = banner, Tilt = random:NextNumber(-5, 5) })
	if kind == "Lag" then
		-- The spike schedule comes from the seed, so every player's lag spikes at the same moments: long enough to
		-- see the model glitch, with breathing room between them so the player can still work.
		local cursor = random:NextNumber(0.5, 0.9)
		while cursor < self.Duration - 0.8 do
			local length = random:NextNumber(0.55, 1.05)
			table.insert(self.Freezes, { cursor, math.min(cursor + length, self.Duration - 0.3) })
			cursor += length + random:NextNumber(0.75, 1.45)
		end
		local tint = Instance.new("Frame")
		tint.Name, tint.Size, tint.BackgroundColor3, tint.BackgroundTransparency, tint.BorderSizePixel, tint.Active =
			"DigitalTint", UDim2.fromScale(1, 1), Color3.fromRGB(15, 230, 255), 1, 0, false
		tint.ZIndex = 1
		tint.Parent = frame
		table.insert(self.Parts, { Kind = "LagTint", Node = tint })
		for index = 1, 12 do
			local line = Instance.new("Frame")
			line.Name, line.BorderSizePixel, line.Active = "Scanline", 0, false
			line.ZIndex = 2
			line.BackgroundColor3, line.BackgroundTransparency = if index % 2 == 0 then GLITCH_CYAN else GLITCH_COLORS[1], 1
			line.Parent = frame
			table.insert(self.Parts, { Kind = "Scanline", Node = line, Y = random:NextNumber(), Speed = random:NextNumber(0.04, 0.13) })
		end
		for index = 1, 10 do
			local block = Instance.new("Frame")
			block.Name, block.BorderSizePixel, block.Active, block.Visible = "PixelTear", 0, false, false
			block.ZIndex = 3
			block.BackgroundColor3 = GLITCH_COLORS[index % #GLITCH_COLORS + 1]
			block.Parent = frame
			table.insert(self.Parts, {
				Kind = "PixelTear",
				Node = block,
				X = random:NextNumber(0.05, 0.9),
				Y = random:NextNumber(0.08, 0.92),
				Width = random:NextNumber(0.06, 0.24),
			})
		end
	elseif kind == "FogBank" then
		-- A screen-wide blanket that thickens to nearly solid, under the drifting banks.
		local blanket = Instance.new("Frame")
		blanket.Name, blanket.Size, blanket.BackgroundColor3, blanket.BorderSizePixel, blanket.Active =
			"Blanket", UDim2.fromScale(1, 1), FOG_COLOR, 0, false
		blanket.BackgroundTransparency = 1
		blanket.ZIndex = 1
		blanket.Parent = frame
		table.insert(self.Parts, { Kind = "Blanket", Node = blanket })
		for index = 1, FOG_BANKS do
			local bank = Instance.new("Frame")
			bank.Name, bank.AnchorPoint, bank.BackgroundColor3, bank.BorderSizePixel, bank.Active =
				"Fog", Vector2.new(0.5, 0.5), FOG_COLOR, 0, false
			bank.ZIndex = 2
			bank.Parent = frame
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = bank
			-- Soft edges: the fog is thickest in the middle and thins out to nothing.
			local soft = Instance.new("UIGradient")
			soft.Name = "Soft"
			soft.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.42),
				NumberSequenceKeypoint.new(1, 1),
			})
			soft.Parent = bank
			table.insert(self.Parts, {
				Kind = "Fog",
				Node = bank,
				Y = random:NextNumber(0.12, 0.88),
				Speed = random:NextNumber(0.03, 0.07) * (if index % 2 == 0 then 1 else -1),
				Start = random:NextNumber(0.2, 0.8),
				Height = random:NextNumber(0.35, 0.55),
				Width = random:NextNumber(1.1, 1.5),
			})
		end
		for index = 1, 4 do
			local question = Instance.new("TextLabel")
			question.Name, question.BackgroundTransparency, question.BorderSizePixel, question.Active = "FogQuestion", 1, 0, false
			question.Font, question.Text, question.TextScaled = Enum.Font.GothamBlack, "?", true
			question.ZIndex = 3
			question.TextColor3, question.TextStrokeColor3, question.TextStrokeTransparency = Color3.new(1, 1, 1), Color3.fromRGB(120, 130, 145), 0.25
			question.Parent = frame
			table.insert(self.Parts, {
				Kind = "FogQuestion",
				Node = question,
				X = random:NextNumber(0.12, 0.88),
				Y = random:NextNumber(0.15, 0.82),
				Phase = random:NextNumber(0, math.pi * 2),
			})
		end
	elseif kind == "Wobble" then
		for index = 1, 16 do
			local star = Instance.new("TextLabel")
			star.Name, star.AnchorPoint, star.BackgroundTransparency, star.BorderSizePixel, star.Active =
				"SpinStar", Vector2.new(0.5, 0.5), 1, 0, false
			-- GothamBlack lacks the Unicode star glyphs on some Roblox platforms, which displayed them as squares.
			star.Font, star.Text, star.TextScaled = Enum.Font.GothamBlack, if index % 2 == 0 then "*" else "+", true
			star.ZIndex = 3
			star.TextColor3 = if index % 3 == 0 then Color3.fromRGB(255, 225, 70) elseif index % 3 == 1 then Color3.fromRGB(255, 105, 210) else GLITCH_CYAN
			star.Parent = frame
			table.insert(self.Parts, {
				Kind = "SpinStar",
				Node = star,
				Phase = random:NextNumber(0, math.pi * 2),
				Radius = random:NextNumber(0.34, 0.56),
				Size = random:NextNumber(0.035, 0.075),
			})
		end
	end
end

-- Lays the effect out for the current viewport, event age and fade (1 = fully shown).
function Sabotage.Layout(self: any, age: number, fade: number, viewport: Vector2)
	local u = math.min(viewport.X, viewport.Y)
	local progress = clamp01(age / math.max(0.1, self.Duration))
	local frozen, episode = self:FrozenAt(age)
	for _, part in self.Parts do
		local node = part.Node
		if part.Kind == "Banner" then
			local life = 1 - clamp01((age - 1.05) / 0.4)
			local pop = 1 + math.sin(clamp01(age / 0.3) * math.pi) * 0.18
			node.Visible = life > 0
			node.Size = UDim2.fromScale(0.8 * pop, 0.18 * pop)
			node.Rotation = part.Tilt + math.sin(age * 16) * 3 * life
			node.TextTransparency, node.TextStrokeTransparency = 1 - fade * life, 1 - fade * life
		elseif part.Kind == "LagTint" then
			node.BackgroundTransparency = 1 - fade * (if frozen then 0.2 else 0.035)
		elseif part.Kind == "Scanline" then
			node.Size = UDim2.fromOffset(viewport.X, math.max(2, u * (if frozen then 0.012 else 0.004)))
			node.Position = UDim2.fromOffset(0, ((part.Y + age * part.Speed) % 1) * viewport.Y)
			node.BackgroundTransparency = 1 - fade * (if frozen then 0.5 else 0.12)
		elseif part.Kind == "PixelTear" then
			local pulse = frozen and (math.floor((age + part.X) / GLITCH_STEP) % 3 ~= 0)
			node.Visible = pulse
			node.Size = UDim2.fromOffset(part.Width * viewport.X, math.max(5, u * 0.018))
			node.Position = UDim2.fromScale((part.X + episode * 0.037) % 0.94, part.Y)
			node.BackgroundTransparency = 1 - fade * 0.72
		elseif part.Kind == "SpinStar" then
			local angle = part.Phase + progress * math.pi * 6
			local radius = part.Radius * (0.75 + 0.25 * math.sin(progress * math.pi))
			node.Size = UDim2.fromOffset(part.Size * u, part.Size * u)
			node.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius, 0.5 + math.sin(angle) * radius * 0.72)
			node.Rotation = math.deg(angle) * 1.5
			node.TextTransparency, node.TextStrokeTransparency = 1 - fade * 0.9, 1 - fade * 0.9
		end
	end
	if self.Kind == "FogBank" then
		-- The fog builds slowly (density = progress squared) until, near the end, the view is almost completely lost.
		local density = progress * progress
		for _, bank in self.Parts do
			local node = bank.Node
			if bank.Kind == "Blanket" then
				node.BackgroundTransparency = 1 - math.min(0.97, density * 1.05) * fade
			elseif bank.Kind == "Fog" then
				local drift = ((bank.Start + bank.Speed * age) % 1.4) - 0.2
				local grow = 1 + density * 1.2
				node.Size = UDim2.fromOffset(bank.Width * viewport.X * grow, bank.Height * viewport.Y * grow)
				node.Position = UDim2.fromOffset(drift * viewport.X, bank.Y * viewport.Y)
				node.BackgroundTransparency = 1 - (0.25 + 0.7 * density) * fade
			elseif bank.Kind == "FogQuestion" then
				local bob = math.sin(age * 1.8 + bank.Phase)
				node.Size = UDim2.fromOffset(u * (0.08 + density * 0.08), u * (0.1 + density * 0.1))
				node.Position = UDim2.fromScale(bank.X, bank.Y + bob * 0.025)
				node.Rotation = bob * 12
				node.TextTransparency = 1 - density * fade * 0.72
				node.TextStrokeTransparency = 1 - density * fade * 0.65
			end
		end
	end
end

-- Whether the picture is frozen at this event age, plus the number and start age of that freeze.
function Sabotage.FrozenAt(self: any, age: number): (boolean, number, number)
	for index, window in self.Freezes do
		if age >= window[1] and age < window[2] then
			return true, index, window[1]
		end
	end
	return false, 0, 0
end

-- How the mystery model looks during Lag at this moment, or nil when no Lag runs. Inside a spike: Spike=true,
-- Episode (which spike), Frame (which jump inside it), Factor (visual size multiplier, 1 on the first frame and
-- now and then a still frame), Color and Fill (the outline/fill colour and fill transparency). Between spikes:
-- Spike=false with a softly pulsing cyan outline and no fill. Seeded, so every player sees the same glitch.
function Sabotage.Glitch(self: any, now: number): any?
	local event = self.Event
	if not event or self.Kind ~= "Lag" or self.ReleasedAt then
		return nil
	end
	local age = now - event.StartedAt
	local frozen, index, start = self:FrozenAt(age)
	if not frozen then
		local pulse = 0.5 + 0.5 * math.sin(age * 7)
		return {
			Spike = false,
			Factor = 1,
			Color = Color3.new(1, 1, 1):Lerp(GLITCH_CYAN, (0.35 + 0.45 * pulse) * (self.Fade or 1)),
			Fill = 1,
		}
	end
	local frame = math.floor((age - start) / GLITCH_STEP)
	local random = Random.new((event.Seed or 0) + index * 7919 + frame * 131)
	local still = frame == 0 or random:NextNumber(0, 1) < 0.2
	return {
		Spike = true,
		Episode = index,
		Frame = frame,
		Factor = if still then 1 else math.exp(random:NextNumber(GLITCH_SHRINK, GLITCH_GROW)),
		Color = GLITCH_COLORS[random:NextInteger(1, #GLITCH_COLORS)],
		Fill = random:NextNumber(0.35, 0.75),
	}
end

-- A small HUD stutter offset (scale) for exactly the same Lag freeze bursts the camera holds on: one fixed offset
-- per burst (not re-rolled every frame), and zero the rest of the time, so GameHUDMotion's slow drift reads as the
-- UI going briefly sluggish and stepping slightly, in sync with the freeze, then easing cleanly back -- not a
-- constant scatter across the screen.
function Sabotage.StutterOffset(self: any, now: number): (number, number)
	local event = self.Event
	if not event or self.Kind ~= "Lag" or self.ReleasedAt then
		return 0, 0
	end
	local frozen, index = self:FrozenAt(now - event.StartedAt)
	if not frozen then
		return 0, 0
	end
	local random = Random.new((event.Seed or 0) + index * 97)
	return random:NextNumber(-1, 1) * 0.025, random:NextNumber(-1, 1) * 0.025
end

function Sabotage.Clear(self: any)
	if self.Gui then
		self.Gui:Destroy()
	end
	self.Gui, self.Root, self.Kind, self.Id, self.ReleasedAt, self.Event = nil, nil, nil, nil, nil, nil
	self.Parts = {}
end

local function envelope(event: any, now: number): number
	return math.min(clamp01((now - event.StartedAt) / FADE_IN), clamp01((event.ExpiresAt - now) / FADE_OUT))
end

-- The live troll event for this snapshot (not ink), or nil.
local function liveEvent(snapshot: any, now: number, only: string?): any?
	if not snapshot then
		return nil
	end
	for _, event in snapshot.InkSplats or { snapshot.InkSplat } do
		if
			event.Kind
			and event.Kind ~= "Ink"
			and (only == nil or event.Kind == only)
			and snapshot.MatchId ~= nil
			and snapshot.State == "GUESSING"
			and now >= event.StartedAt
			and now < event.ExpiresAt
		then
			return event
		end
	end
	return nil
end

-- snapshot: the local player's match snapshot (nil outside a match). now: shared server time.
function Sabotage.Step(self: any, snapshot: any, now: number)
	local event = liveEvent(snapshot, now, self.Only)
	self.Fade = 0
	self.SwayEvent = nil
	if event then
		local id = tostring(snapshot.MatchId) .. ":" .. tostring(event.Id)
		if self.Id ~= id then
			self:Clear()
			self.Id = id
			self:Build(event.Kind, event.Seed, event.ExpiresAt - event.StartedAt)
		end
		self.ReleasedAt, self.Event = nil, event
		self.Fade = envelope(event, now)
		self.SwayEvent = if event.Kind == "Wobble" then event else nil
		if self.Gui then
			self:Layout(now - event.StartedAt, self.Fade, self.D.Viewport())
		end
		return
	end
	if not self.Event then
		return
	end
	-- The effect ended (turn locked or expired): fade out quickly, then remove.
	self.ReleasedAt = self.ReleasedAt or now
	local fade = 1 - clamp01((now - self.ReleasedAt) / RELEASE_SECONDS)
	if fade <= 0 then
		self:Clear()
		return
	end
	self.Fade = math.min(fade, clamp01((self.Event.ExpiresAt - self.ReleasedAt) / FADE_OUT))
	if self.Kind == "Wobble" then
		self.SwayEvent = self.Event
	end
	if self.Gui then
		self:Layout(math.max(0, self.ReleasedAt - self.Event.StartedAt), self.Fade, self.D.Viewport())
	end
end

-- Camera roll in radians for Wobble (0 otherwise): one smooth, complete 360 degree turn over the whole effect
-- (slow start, slow finish, so it ends exactly upright). An early end eases the roll back out instead of snapping.
function Sabotage.Sway(self: any, now: number): number
	local event = self.SwayEvent
	if not event then
		return 0
	end
	local total = math.max(0.1, event.ExpiresAt - event.StartedAt)
	local at = math.min(now, self.ReleasedAt or now)
	local progress = clamp01((at - event.StartedAt) / total)
	local eased = progress * progress * (3 - 2 * progress)
	local angle = math.pi * 2 * eased + math.sin(progress * math.pi) * math.sin(progress * math.pi * 8) * math.rad(11)
	if self.ReleasedAt and progress < 1 then
		angle *= self.Fade
	end
	return angle
end

-- True while a Lag effect holds the picture: CameraController stops updating the camera during these bursts.
function Sabotage.Frozen(self: any, now: number): boolean
	local event = self.Event
	if not event or self.Kind ~= "Lag" or self.ReleasedAt then
		return false
	end
	return (self:FrozenAt(now - event.StartedAt))
end

-- The live Lag event (including its ThrowerUserId), from the moment it starts until its release fade fully clears,
-- or nil. Drives Game.Lagging's visibility/text and the HUD panel throw in GameFrameUI/GameHUDMotion, which own
-- the actual presentation.
function Sabotage.ActiveEvent(self: any): any?
	if self.Kind == "Lag" and self.Event then
		return self.Event
	end
	return nil
end
function Sabotage.Active(self: any): boolean
	return self:ActiveEvent() ~= nil
end

function Sabotage.Destroy(self: any)
	self:Clear()
end

return Sabotage

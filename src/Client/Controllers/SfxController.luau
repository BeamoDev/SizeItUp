--!strict
-- Sound effects from SoundService.SFX and the ambience playlist from SoundService.Music.
--   SFX: Click (mouse-over and press on every button), Purchase, TickUp / TickDown (models growing or shrinking, and
--        the results counting up), YouWin / YouLose (match result), Error, Notification, InkSplash (an enemy's ink
--        hits you), SpinStart (an egg or lucky block starts spinning) / EggOpen (it opens), LoadingIntro. GameWon is the fallback for YouWin.
--   Music: every sound in the folder (Ambience, Ambience2, ... Ambience5) plays in order and then starts over, forever.
--   Everything is played through Style.Play(name) (see UIStyle) or this controller's Play; UIEffects (ReplicatedStorage.
--   Shared.UIEffects) plays its button sound through the same player.
-- Effects are cloned per play so they overlap, and each one has a small cooldown so nothing machine-guns. Volumes are
-- whatever each sound is authored at: nothing here changes a Volume.
local SfxController = {}
SfxController.__index = SfxController

local COOLDOWNS = { HeartLost = 0.5, Safe = 0.5, Click = 0.04, Hover = 0.05, TickUp = 0.04, TickDown = 0.04, Notification = 0.3, Error = 0.2, InkSplash = 0.15, Purchase = 0.1, Reward = 0.2, MaxMinSet = 0.25, Whoosh = 0.15, SpinStart = 0.3, EggOpen = 0.1, Landmark = 0.15 }
-- Other spellings a sound may carry in Studio (the down tick is currently named TickDowm), and stand-ins for missing ones.
-- Landmark (crossing a round size like 1m, 10m or the reference height while dragging) has no dedicated sound yet, so it
-- borrows TickUp at a higher pitch until one is authored.
-- HeartLost (a player loses a life in the table cutscene) and Safe (they keep it, or get one back) use their own
-- sounds when SFX has them, otherwise Error and Reward stand in.
local ALIASES = {
	TickDown = { "TickDowm" },
	YouWin = { "GameWon" },
	Landmark = { "TickUp" },
	HeartLost = { "LoseHeart", "LostHeart", "Error" },
	Safe = { "StaySafe", "Reward" },
}
local STEP_SECONDS = 1
local HOVER_GAP = 0.1 -- a button never plays Hover twice inside this many seconds (a growing button can re-fire at its edge)
local LOAD_GRACE_SECONDS = 15 -- an ambience track that never loads is skipped after this long

function SfxController.new(deps: any)
	local self: any = setmetatable({
		Folder = deps.Folder, Container = deps.Container or deps.Folder, Player = deps.Player, PlayerGui = deps.PlayerGui, Input = deps.Input,
		Clock = deps.Clock or os.clock, Gate = deps.Gate, UIEffects = deps.UIEffects,
		Music = deps.Music, LastPlayed = {}, Bound = setmetatable({}, { __mode = "k" }), Connections = {}, Ambience = { List = {}, Index = 0 },
		StepAt = 0,
	}, SfxController)
	-- UIEffects plays its own hover / click / pop sounds through this controller.
	if self.UIEffects and self.UIEffects.SetSoundPlayer then
		self.UIEffects.SetSoundPlayer(function(name: string) self:Play(name) end)
		-- Buttons this controller voices are silent in UIEffects, so nothing plays twice.
		self.UIEffects.SetVoicedCheck(function(button: Instance) return self.Bound[button] ~= nil end)
	end
	-- Buttons already in PlayerGui, and any that appear later (cloned cards, runtime panels).
	if self.PlayerGui then
		for _, descendant in self.PlayerGui:GetDescendants() do self:BindButton(descendant) end
		pcall(function()
			table.insert(self.Connections, self.PlayerGui.DescendantAdded:Connect(function(node: Instance) self:BindButton(node) end))
			table.insert(self.Connections, self.PlayerGui.DescendantRemoving:Connect(function(node: Instance) self:UnbindButton(node) end))
		end)
	end
	if deps.RunService then table.insert(self.Connections, deps.RunService.Heartbeat:Connect(function() self:Step() end)) end
	self:LoadPlaylist()
	return self
end

function SfxController.UnbindButton(self: any, node: Instance)
	local connections = self.Bound[node]
	if not connections then return end
	self.Bound[node] = nil
	for _, connection in connections do
		connection:Disconnect()
	end
end

-- The Music folder's sounds in natural order (Ambience, Ambience2, ..., Ambience10).
function SfxController.LoadPlaylist(self: any)
	local list = {}
	if self.Music then
		for _, child in self.Music:GetChildren() do
			if child:IsA("Sound") then table.insert(list, child) end
		end
	end
	local function key(sound: any): (string, number)
		local base, number = string.match(sound.Name, "^(%D*)(%d*)$")
		return base or sound.Name, tonumber(number) or 0
	end
	table.sort(list, function(a: any, b: any)
		local nameA, numberA = key(a)
		local nameB, numberB = key(b)
		if nameA ~= nameB then return nameA < nameB end
		return numberA < numberB
	end)
	self.Ambience.List = list
	-- A track authored with Playing (or Looped) on would start by itself, all at once: silence them all now; only the
	-- playlist starts a track, one at a time.
	for _, track in list do
		track.Looped = false
		if track.IsPlaying then track:Stop() end
	end
end

-- Plays one effect (overlapping any still playing). options.Pitch (a PlaybackSpeed multiplier) is used by the "snap and
-- juice" resize ticks so the pitch rises with size; every other caller leaves it out and gets the sound's authored speed.
-- Returns whether it played.
function SfxController.Play(self: any, name: string, options: any?): boolean
	local sound = self.Folder:FindFirstChild(name)
	if not sound then
		for _, alias in ALIASES[name] or {} do
			sound = self.Folder:FindFirstChild(alias)
			if sound then break end
		end
	end
	if not sound or not sound:IsA("Sound") then return false end
	local now = self.Clock()
	if now - (self.LastPlayed[name] or -math.huge) < (COOLDOWNS[name] or 0) then return false end
	self.LastPlayed[name] = now
	local copy = sound:Clone()
	copy.Looped = false
	if options and type(options.Pitch) == "number" and options.Pitch > 0 then copy.PlaybackSpeed = options.Pitch end
	copy.Parent = self.Container
	copy:Play()
	local function cleanup() if copy.Parent then copy:Destroy() end end
	copy.Ended:Connect(cleanup)
	task.delay(math.max(copy.TimeLength, 2) + 1, cleanup)
	return true
end

local function touchOnly(self: any): boolean
	if not self.Input then return false end
	local ok, last = pcall(function() return self.Input:GetLastInputType() end)
	return ok and last == Enum.UserInputType.Touch
end

-- Hover on mouse-over and mouse-leave, Click on press. Buttons UIEffects already handles are left to it.
function SfxController.BindButton(self: any, node: Instance)
	if not node:IsA("GuiButton") or self.Bound[node] then return end
	if node:GetAttribute("NoSound") == true then return end
	if self.UIEffects and self.UIEffects.IsVoiced and self.UIEffects.IsVoiced(node) then return end
	local connections = {}
	self.Bound[node] = connections
	-- Hover plays when the pointer enters the button and again when it leaves; Click plays when it is pressed.
	local lastHover = -math.huge
	local function hover()
		local now = self.Clock()
		if now - lastHover < HOVER_GAP or node.Active == false or touchOnly(self) then return end
		lastHover = now
		self:Play((node:GetAttribute("HoverSound") :: string?) or "Hover")
	end
	table.insert(connections, node.MouseEnter:Connect(hover))
	table.insert(connections, node.MouseLeave:Connect(hover))
	table.insert(connections, node.Activated:Connect(function()
		-- Buttons that make their own sound (the +/- scale buttons tick) set NoClick.
		if node:GetAttribute("NoClick") == true then return end
		self:Play((node:GetAttribute("ClickSound") :: string?) or "Click")
	end))
end

-- The playlist in order, then again from the start, forever.
function SfxController.NextAmbience(self: any)
	local ambience = self.Ambience
	if #ambience.List == 0 then return end
	if ambience.Ended then ambience.Ended:Disconnect();ambience.Ended = nil end
	ambience.Index = ambience.Index % #ambience.List + 1
	local sound = ambience.List[ambience.Index]
	sound.Looped = false -- a looping track never ends, so the next one could not start
	ambience.Current, ambience.StartedAt = sound, self.Clock()
	-- Only this track may sound: stop any other that is playing before starting it.
	for _, other in ambience.List do
		if other ~= sound and other.IsPlaying then other:Stop() end
	end
	sound:Play()
	ambience.Ended = sound.Ended:Connect(function() self:NextAmbience() end)
end

function SfxController.StartAmbience(self: any)
	if self.Ambience.Started or #self.Ambience.List == 0 then return end
	self.Ambience.Started = true
	self:NextAmbience()
end

-- Starts the ambience once loading is over, and keeps it moving if a track stalls or fails to load.
function SfxController.Step(self: any)
	local now = self.Clock()
	if now < self.StepAt then return end
	self.StepAt = now + STEP_SECONDS
	local ambience = self.Ambience
	-- Anything but the current track that is somehow playing (an autoplaying Studio setting, a late change) is silenced.
	for _, track in ambience.List do
		if track ~= ambience.Current and track.IsPlaying then track:Stop() end
	end
	if not ambience.Started then
		if not self.Gate or self.Gate() then self:StartAmbience() end
		return
	end
	local current = ambience.Current
	if current and not current.IsPlaying then
		local waited = now - ambience.StartedAt
		if (current.IsLoaded and waited >= 1.5) or waited >= LOAD_GRACE_SECONDS then self:NextAmbience() end
	end
end

function SfxController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	for _, connections in self.Bound do
		for _, connection in connections do connection:Disconnect() end
	end
	table.clear(self.Bound)
	local ambience = self.Ambience
	if ambience.Ended then ambience.Ended:Disconnect();ambience.Ended = nil end
	if ambience.Current then ambience.Current:Stop() end
	ambience.Started = false
	if self.UIEffects and self.UIEffects.SetSoundPlayer then
		self.UIEffects.SetSoundPlayer(nil)
		self.UIEffects.SetVoicedCheck(nil)
	end
end

return SfxController

--!strict
local MatchController = {}
local HintWobble = require(script.Parent.HintWobble)
MatchController.__index = MatchController
local TICK_PITCHES = { 0.97, 1.02, 0.99, 1.04, 0.96, 1.01 }
function MatchController.PlayScaleTick(self: any, name: string)
	if not self.D.Sfx then
		return
	end
	self.ScaleTickIndex = (self.ScaleTickIndex or 0) % #TICK_PITCHES + 1
	self.D.Sfx:Play(name, { Pitch = TICK_PITCHES[self.ScaleTickIndex] })
end
function MatchController.new(dependencies: any)
	local d = dependencies
	local self: any = setmetatable({
		D = d,
		Revision = 0,
		Snapshot = nil,
		Connections = {},
		TickValues = {},
		LandmarkValues = {},
		LastSend = -math.huge,
		Dirty = false,
		PreviewRound = nil,
		SuppressedMatch = nil,
		RevealAnimation = nil,
	}, MatchController)
	local overlay = {
		Config = d.Config.SabotageVisuals,
		PlayerGui = d.Player:WaitForChild("PlayerGui"),
		Effects = d.Effects,
		Viewport = function()
			local camera = d.World.CurrentCamera
			return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		end,
	}
	if d.InkSplatController then
		self.Ink = d.InkSplatController.new(overlay)
	end
	if d.SabotageController then
		-- The troll effects run together, so each kind has its own drawer; one handle answers for all of them.
		local drawers = {}
		for _, kind in { "Lag", "FogBank", "Wobble" } do
			table.insert(drawers, d.SabotageController.new(overlay, kind))
		end
		self.Sabotage = {
			Clear = function()
				for _, drawer in drawers do
					drawer:Clear()
				end
			end,
			Step = function(_, snapshot, now)
				for _, drawer in drawers do
					drawer:Step(snapshot, now)
				end
			end,
			Sway = function(_, now)
				local total = 0
				for _, drawer in drawers do
					total += drawer:Sway(now)
				end
				return total
			end,
			Frozen = function(_, now)
				for _, drawer in drawers do
					if drawer:Frozen(now) then
						return true
					end
				end
				return false
			end,
			Active = function(_)
				for _, drawer in drawers do
					if drawer:Active() then
						return true
					end
				end
				return false
			end,
			ActiveEvent = function(_)
				for _, drawer in drawers do
					local event = drawer:ActiveEvent()
					if event then
						return event
					end
				end
				return nil
			end,
			Glitch = function(_, now)
				for _, drawer in drawers do
					local glitch = drawer:Glitch(now)
					if glitch then
						return glitch
					end
				end
				return nil
			end,
			StutterOffset = function(_, now)
				local dx, dy = 0, 0
				for _, drawer in drawers do
					local a, b = drawer:StutterOffset(now)
					dx, dy = dx + a, dy + b
				end
				return dx, dy
			end,
			Destroy = function()
				for _, drawer in drawers do
					drawer:Destroy()
				end
			end,
		}
	end
	self.UI = d.UIController.new(d.Player:WaitForChild("PlayerGui"), d.Config, d.StarterGui)
	if d.ModeVoteView then
		self.ModeVote = d.ModeVoteView.new(d.Player:WaitForChild("PlayerGui"), d.Config, function(voteId, mode)
			d.ModeVote:FireServer(voteId, mode)
		end, d.Storage)
	end
	self.Transition = d.TransitionController.new(d.Player:WaitForChild("PlayerGui"), d.Config, function()
		return if self.UI.Gui
				and self.UI.StatusGui
				and self.UI.StatusGui.Parent == self.UI.Gui
			then { self.UI.Gui }
			else { self.UI.Gui, self.UI.StatusGui }
	end)
	self.Preview = d.PreviewController.new(d.Storage, d.World, d.Config, d.Math)
	self.Camera = d.CameraController.new(d.World, d.Player, d.Input, d.Config, function()
		self:Interrupt()
	end)
	self.Reaction = d.ReactionController.new(d.World, d.Players, d.Config, d.Player:WaitForChild("PlayerGui"))
	self.Scale = d.ScaleController.new(d.Input, d.GuiService, self.UI.Track, d.Config, d.Math, function(value, alpha)
		self.UI:SetGuess(value, alpha)
		-- Ticks while you drag or press +/-; jumps from a new turn or a reset rebase silently.
		if self.Scale.Drag or self.Scale.ButtonPending then
			self:TickModel(value, "own")
		else
			self.TickValues["own"] = value
		end
		-- Input already moves at a bounded speed. Render that exact selected size
		-- so Lock In cannot submit an unseen destination ahead of the model.
		self.Preview:Set(value, true)
		self.Dirty = true
	end)
	self.Scale.OnLimit = function(side)
		if self.D.Sfx then
			self.D.Sfx:Play("MaxMinSet")
		end
		if self.UI.PulseScaleLimit then
			self.UI:PulseScaleLimit(side)
		end
	end
	-- The knob travels from Y 0.9 (minimum) to Y 0.1 (maximum), so a full drag uses that same inner 80%.
	self.Scale.TrackFraction = 0.8
	table.insert(
		self.Connections,
		d.Input.InputBegan:Connect(function(input, processed)
			if input.UserInputType == Enum.UserInputType.Touch then
				self:ClearObjectHover()
			end
			if processed or not self:CanGuess() or self.Scale.Drag then
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			if self.UI:BlocksObjectDrag(input.Position) then
				return
			end
			if self.Preview:HitMystery(input.Position, input.UserInputType == Enum.UserInputType.Touch) then
				self.Scale:BeginDrag(input)
			end
		end)
	)
	if self.UI.Plus then
		table.insert(
			self.Connections,
			self.UI.Plus.Activated:Connect(function()
				if self:CanGuess() then
					self:PlayScaleTick("TickUp")
					self.SuppressOwnTicksUntil = self.D.World:GetServerTimeNow() + 0.35
					self.Scale:Nudge(1)
				end
			end)
		)
	end
	if self.UI.Minus then
		table.insert(
			self.Connections,
			self.UI.Minus.Activated:Connect(function()
				if self:CanGuess() then
					self:PlayScaleTick("TickDown")
					self.SuppressOwnTicksUntil = self.D.World:GetServerTimeNow() + 0.35
					self.Scale:Nudge(-1)
				end
			end)
		)
	end
	if self.UI.Knob then
		table.insert(
			self.Connections,
			self.UI.Knob.InputBegan:Connect(function(input)
				if self:CanGuess() then
					self.Scale:BeginDrag(input)
				end
			end)
		)
	end
	-- A lost heart's "+" works throughout the live match, including while watching another turn or a result.
	if self.UI.HeartLabels and d.Heart then
		for heartIndex = 1, 3 do
			local label = self.UI.HeartLabels[heartIndex]
			if not label then
				continue
			end
			table.insert(
				self.Connections,
				label.InputBegan:Connect(function(input)
					if
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					then
						return
					end
					local snapshot = self.Snapshot
					if
						not snapshot
						or snapshot.MatchId == nil
						or snapshot.State == "IDLE"
						or snapshot.State == "MATCH_END"
						or not label.Visible
						or (snapshot.YourHearts or 0)
							>= (snapshot.Mode == "SuddenDeath" and 1 or d.Config.StartingHearts)
					then
						return
					end
					local now = d.World:GetServerTimeNow()
					if self.HeartAt and now - self.HeartAt < 0.25 then
						return
					end
					self.HeartAt = now
					d.Heart:FireServer(snapshot.MatchId, snapshot.RoundId, snapshot.TurnId)
				end)
			)
		end
	end
	table.insert(
		self.Connections,
		self.UI.LockIn.Activated:Connect(function()
			if not self:CanGuess() then
				return
			end
			local snapshot = self.Snapshot
			self.PendingLock, self.LockSentAt = snapshot.TurnId, self.D.World:GetServerTimeNow()
			self.Dirty = false
			self.Scale:Enable(false)
			self:ClearObjectHover()
			self.UI:EnableLock(false)
			self.D.Lock:FireServer(snapshot.MatchId, snapshot.RoundId, snapshot.TurnId, self.Scale.Value)
		end)
	)
	if self.UI.ResetButton then
		table.insert(
			self.Connections,
			self.UI.ResetButton.Activated:Connect(function()
				if self:CanGuess() then
					if self.TurnStartGuess then
						self.Scale:ResetGuess(self.TurnStartGuess)
					end
				end
			end)
		)
	end
	-- Every troll button (ink, and Lag / FogBank / Wobble when the layout has them) sends its own kind.
	local sabotage = self.UI.SabotageButtons
		or (if self.UI.InkSplatButton then { Ink = self.UI.InkSplatButton } else {})
	self.SabotageCues, self.CueRandom = {}, Random.new()
	for _, button in sabotage do table.insert(self.SabotageCues, HintWobble.new(button)) end
	if d.LeaveSpectator then
		local function leave()
			local s = self.Snapshot
			if not s or not s.CanLeaveSpectating or not s.MatchId or d.Input:GetFocusedTextBox() then return end
			local now = d.World:GetServerTimeNow()
			if now - (self.LastSpectatorExit or -math.huge) < 0.25 then return end
			self.LastSpectatorExit = now
			d.LeaveSpectator:FireServer(s.MatchId)
		end
		table.insert(self.Connections, d.Input.JumpRequest:Connect(leave))
		-- Bind an existing authored exit control when supplied; never generate a replacement button.
		local bound = {}
		for _, name in { "Exit", "ExitButton", "Leave", "LeaveButton" } do
			local node = self.UI.Gui and self.UI.Gui:FindFirstChild(name, true)
			local button = node and (if node:IsA("GuiButton") then node else node:FindFirstChildWhichIsA("GuiButton", true))
			if button and not bound[button] then
				bound[button] = true
				table.insert(self.Connections, button.Activated:Connect(leave))
			end
		end
	end
	if d.InkSplat then
		for kind, button in sabotage do
			table.insert(
				self.Connections,
				button.Activated:Connect(function()
					local s = self.Snapshot
					if not self:CanInkSplat() then
						return
					end
					self.PendingInk = self.D.World:GetServerTimeNow()
					-- Effects already running do not confirm this click; only a new one does.
					self.PendingKnown = {}
					for _, event in s.InkSplats or { s.InkSplat } do
						self.PendingKnown[event.Id] = true
					end
					self.UI:EnableInkSplat(false)
					d.InkSplat:FireServer(s.MatchId, s.RoundId, s.TurnId, kind)
					if self.UI.InkSent then
						self.UI:InkSent(s.TurnId)
					end
				end)
			)
		end
	end
	if self.UI.HintButton and d.Hint then
		table.insert(
			self.Connections,
			self.UI.HintButton.Activated:Connect(function()
				if not self:CanGuess() or self.PendingHint or not self.Snapshot.CanBuyHint then
					return
				end
				self.PendingHint = d.World:GetServerTimeNow()
				self.HintWasFree = self.Snapshot.FreeHint == true
				self.UI:EnableHint(false)
				d.Hint:FireServer(self.Snapshot.MatchId, self.Snapshot.RoundId, self.Snapshot.TurnId)
			end)
		)
	end
	table.insert(
		self.Connections,
		d.State.OnClientEvent:Connect(function(snapshot)
			local ok, err = xpcall(function()
				self:Receive(snapshot)
			end, debug.traceback)
			if not ok then
				self:Fail(err)
			end
		end)
	)
	table.insert(
		self.Connections,
		d.Player.CharacterRemoving:Connect(function()
			self:Interrupt()
		end)
	)
	table.insert(
		self.Connections,
		d.Player.CharacterAdded:Connect(function(character)
			self:BindCharacter(character)
			d.Ready:FireServer()
		end)
	)
	if d.Player.Character then
		self:BindCharacter(d.Player.Character)
	end
	table.insert(
		self.Connections,
		d.RunService.RenderStepped:Connect(function(dt)
			local ok, err = xpcall(function()
				self:Step(dt)
			end, debug.traceback)
			if not ok then
				self:Fail(err)
			end
		end)
	)
	table.insert(
		self.Connections,
		d.GuiService.MenuOpened:Connect(function()
			self.Scale:Enable(false)
			self:ClearObjectHover()
		end)
	)
	table.insert(
		self.Connections,
		d.Input.WindowFocusReleased:Connect(function()
			self.PointerInactive = true
			self:ClearObjectHover()
		end)
	)
	table.insert(
		self.Connections,
		d.Input.WindowFocused:Connect(function()
			self.PointerInactive = false
		end)
	)
	d.Ready:FireServer()
	return self
end
function MatchController.CanInkSplat(self: any): boolean
	local s = self.Snapshot
	return s ~= nil
		and s.State == "GUESSING"
		and s.CanUseInkSplat == true
		and not self.PendingInk
		and s.MatchId ~= self.SuppressedMatch
		and s.ActivePlayerUserId ~= s.YourUserId
		and not self.Transition:IsActive()
		and self.D.World:GetServerTimeNow() < s.Deadline
		and not self.D.GuiService.MenuIsOpen
		and not self.D.Input:GetFocusedTextBox()
end
function MatchController.CanGuess(self: any): boolean
	local s = self.Snapshot
	return s ~= nil
		and s.MatchId ~= self.SuppressedMatch
		and s.State == "GUESSING"
		and s.CanGuess == true
		and not self.PendingLock
		and not self.Transition:IsActive()
		and self.D.World:GetServerTimeNow() < s.Deadline
		and not self.D.GuiService.MenuIsOpen
		and not self.D.Input:GetFocusedTextBox()
end
function MatchController.ClearObjectHover(self: any)
	self.Preview:SetObjectHovered(false)
	self.UI:SetObjectHover(nil)
end
function MatchController.UpdateObjectHover(self: any)
	local input = self.D.Input
	if
		not self:CanGuess()
		or self.PointerInactive
		or not input.MouseEnabled
		or (self.Scale.Drag and self.Scale.Drag.UserInputType == Enum.UserInputType.Touch)
	then
		self:ClearObjectHover()
		return
	end
	local last = input:GetLastInputType()
	if last == Enum.UserInputType.Touch or last.Name:find("Gamepad", 1, true) then
		self:ClearObjectHover()
		return
	end
	-- GetMouseLocation uses viewport pixels; model picking uses screen pixels.
	local viewport = input:GetMouseLocation()
	local inset = self.D.GuiService:GetGuiInset()
	local point = viewport - inset
	local position = Vector3.new(point.X, point.Y, 0)
	if self.UI:BlocksObjectDrag(position) or not self.Preview:HitMystery(position) then
		self:ClearObjectHover()
		return
	end
	self.Preview:SetObjectHovered(true)
	self.UI:SetObjectHover(point, viewport)
end
function MatchController.BindCharacter(self: any, character: Model)
	if self.DeathConnection then
		self.DeathConnection:Disconnect()
		self.DeathConnection = nil
	end
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
		self.CharacterConnection = nil
	end
	local function bindHumanoid(humanoid: Instance)
		if humanoid:IsA("Humanoid") and not self.DeathConnection then
			self.DeathConnection = humanoid.Died:Connect(function()
				self:Interrupt()
			end)
		end
	end
	for _, child in character:GetChildren() do
		bindHumanoid(child)
	end
	self.CharacterConnection = character.ChildAdded:Connect(bindHumanoid)
end
-- The Player for a UserId, or a bot's NPC (tagged ScaleBot with its ScaleBotUserId). A bot is wrapped once and the
-- same table is reused, so the table camera sees one steady target instead of a new one (and a restarted ease)
-- every frame.
function MatchController.TablePlayer(self: any, userId: number?): any
	if not userId then
		return nil
	end
	local player = self.D.Players:GetPlayerByUserId(userId)
	if player then
		return player
	end
	local function isWorldBot(character: Instance?): boolean
		return character ~= nil and character:IsA("Model") and character:IsDescendantOf(self.D.World)
			and character:FindFirstAncestorWhichIsA("WorldModel") == nil
			and character:GetAttribute("ScaleBotUserId") == userId
	end
	self.BotTargets = self.BotTargets or {}
	local cached = self.BotTargets[userId]
	if cached and isWorldBot(cached.Character) then
		return cached
	end
	self.BotTargets[userId] = nil
	local ok, tagged = pcall(function()
		return (self.D.CollectionService or game:GetService("CollectionService")):GetTagged("ScaleBot")
	end)
	for _, character in if ok then tagged else {} do
		if isWorldBot(character) then
			self.BotTargets[userId] = { Character = character }
			return self.BotTargets[userId]
		end
	end
	return nil
end

function MatchController.IsInGame(self: any): boolean
	local snapshot = self.Snapshot
	return snapshot ~= nil
		and snapshot.MatchId ~= nil
		and snapshot.State ~= "IDLE"
		and snapshot.MatchId ~= self.SuppressedMatch
end

function MatchController.ClearView(self: any)
	if self.Ink then
		self.Ink:Clear()
	end
	if self.Sabotage then
		self.Sabotage:Clear()
		self.Camera.Sway = 0
		self.Camera.Frozen = false
		if self.UI.SetLagging then
			self.UI:SetLagging(false, 0)
		end
	end
	self.PendingInk = nil
	self:ClearObjectHover()
	self.Reaction:Clear()
	self.Scale:Enable(false)
	self.RevealAnimation, self.PreviewRound, self.Dirty = nil, nil, false
	self.RevealKey = nil
	self.PreviewTurn, self.PendingLock = nil, nil
	self.PendingHint = nil
	self.Camera:Stop()
	self.Preview:Clear()
end
-- The camera the 2D overlays project with: the real one, or its un-rolled twin while a Wobble tilts the view.
function MatchController.OverlayCamera(self: any): any
	local camera = self.D.World.CurrentCamera
	if self.Camera.Steady then
		return self.Camera:Steady(camera)
	end
	return camera
end
function MatchController.Interrupt(self: any)
	if self.ModeVote then
		self.ModeVote:Hide()
	end
	self.Transition:Cancel()
	self.Scene, self.VisualSnapshot = nil, nil
	self.SuppressedMatch = self.Snapshot and self.Snapshot.MatchId
	self:ClearView()
	self.UI:Hide()
end
function MatchController.Fail(self: any, err: any)
	warn("Scale It Up! client: " .. tostring(err))
	self:Interrupt()
	self.UI:ShowStatus("Comparison view unavailable.")
end
function MatchController.PreparePreview(self: any, snapshot: any)
	if self.PreviewRound == snapshot.RoundId then
		return
	end
	self.Preview:Start(snapshot)
	self.PreviewRound = snapshot.RoundId
	self.Camera:Start(snapshot.Arena)
	local minimum, maximum =
		snapshot.GuessMinimum or self.D.Config.MinimumGuessMeters,
		snapshot.GuessMaximum or self.D.Config.MaximumGuessMeters
	self.Scale:SetRange(minimum, maximum)
	-- Snap-and-juice landmarks (1m, 10m, the reference height, ...) for this round's band; pure feedback, never sent
	-- anywhere and never changes the guess.
	self.Landmarks = self.D.Math.Landmarks(minimum, maximum, snapshot.ReferenceMeters)
	self.Scale:Set(snapshot.Guess, true)
	self.Dirty = false
end
local function scene(snapshot: any, ui: any): string
	if snapshot.State == "TABLE_RETURN" or snapshot.State == "TABLE_REACTION" then
		return "TABLE:" .. snapshot.MatchId
	end
	-- The end screen plays at the table; the wipe back to the lobby only comes after the seat is left.
	if snapshot.State == "MATCH_END" and ui.HasEnd and ui:HasEnd(snapshot) then
		return "TABLE:" .. snapshot.MatchId
	end
	if
		snapshot.State == "ROUND_INTRO"
		or snapshot.State == "GUESSING"
		or snapshot.State == "TURN_LOCKED"
		or snapshot.State == "ROUND_REVEAL"
	then
		-- Each player's turn is its own scene, so passing the turn runs the black wipe (the reveal keeps the last turn's).
		return "ARENA:" .. snapshot.RoundId .. ":" .. tostring(snapshot.TurnId)
	end
	return "LOBBY"
end
-- Private notices (a pet helped, someone splatted ink on you) become alerts with a chime; an enemy's ink splashes.
function MatchController.PlaySnapshotSounds(self: any, snapshot: any)
	local sfx = self.D.Sfx
	self.SeenNotices = self.SeenNotices or {}
	if self.NoticeMatch ~= snapshot.MatchId then
		self.NoticeMatch = snapshot.MatchId
		table.clear(self.SeenNotices)
	end
	if snapshot.Notices then
		for _, notice in snapshot.Notices do
			if notice.Id and not self.SeenNotices[notice.Id] then
				self.SeenNotices[notice.Id] = true
				if self.D.Alerts then
					self.D.Alerts:Show(notice.Text, notice.Kind)
				end
				if sfx then
					sfx:Play("Notification")
				end
			end
		end
	end
	if not sfx then
		return
	end
	if self.EffectSoundMatch ~= snapshot.MatchId then
		self.EffectSoundMatch, self.EffectSoundIds = snapshot.MatchId, {}
	end
	self.EffectSoundIds = self.EffectSoundIds or {}
	local effects = snapshot.InkSplats
	local count = if effects then #effects elseif snapshot.InkSplat then 1 else 0
	for index = 1, count do
		local effect = if effects then effects[index] else snapshot.InkSplat
		if effect and effect.Id and not self.EffectSoundIds[effect.Id] then
			self.EffectSoundIds[effect.Id] = true
			local sound = if effect.Kind == "Lag"
				then "Error"
				elseif effect.Kind == "FogBank"
				then "Whoosh"
				elseif effect.Kind == "Wobble"
				then "SpinStart"
				else "InkSplash"
			sfx:Play(sound)
		end
	end
end
-- A tick each time the model has grown or shrunk by about 2%. A tiny repeating pitch pattern keeps long drags from
-- sounding mechanical while remaining close to each sound's authored tone.
local TICK_STEP = 0.02
function MatchController.TickModel(self: any, value: number, key: string)
	if type(value) ~= "number" or value <= 0 then
		return
	end
	local own = key == "own"
	-- Landmark crossings (1m, 10m, the reference height, ...): checked every call against the raw previous value, so a
	-- crossing between two frames is never missed by the coarser 2% tick below. Pure feedback -- Value never snaps.
	self.LandmarkValues = self.LandmarkValues or {}
	local previous = self.LandmarkValues[key]
	self.LandmarkValues[key] = value
	if previous and self.Landmarks then
		local low, high = math.min(previous, value), math.max(previous, value)
		for _, landmark in self.Landmarks do
			if landmark > low and landmark <= high then
				-- A controller pulse only: no extra, higher-pitched tick, so the tick sounds stay the same throughout.
				if own and self.D.Haptic then
					self.D.Haptic:Pulse(0.6)
				end
				break
			end
		end
	end
	local last = self.TickValues[key]
	if not last then
		self.TickValues[key] = value
		return
	end
	local delta = math.log(value / last)
	if own and self.SuppressOwnTicksUntil and self.D.World:GetServerTimeNow() < self.SuppressOwnTicksUntil then
		self.TickValues[key] = value
		return
	end
	if math.abs(delta) >= TICK_STEP then
		self.TickValues[key] = value
		self:PlayScaleTick(if delta > 0 then "TickUp" else "TickDown")
		if own and self.D.Haptic then
			self.D.Haptic:Pulse(0.25)
		end
	end
end
-- The prize amount on the table flickers as it is picked; each change ticks (up when it rises, down when it falls).
function MatchController.TickPrizeRoll(self: any, snapshot: any, now: number)
	local roll, sfx = self.D.PrizeRoll, self.D.Sfx
	if not (roll and sfx) then
		return
	end
	if
		snapshot.State ~= "PRIZE_ROLL"
		or not snapshot.Prize
		or not snapshot.RollStarted
		or not snapshot.RollDuration
	then
		self.RollLast = nil
		return
	end
	local elapsed = now - snapshot.RollStarted
	-- Same timeline as the tabletop: a beat with no amount, then the flicker settling on the real prize.
	local intro = math.min(1, snapshot.RollDuration * 0.25)
	if elapsed < intro then
		self.RollLast = nil
		return
	end
	local amount =
		roll.Amount(snapshot.Prize, elapsed - intro, snapshot.RollDuration - intro, self.D.Config.PrizeHoldSeconds)
	if self.RollLast and amount ~= self.RollLast then
		sfx:Play(if amount > self.RollLast then "TickUp" else "TickDown")
	end
	self.RollLast = amount
end
function MatchController.Receive(self: any, snapshot: any)
	if type(snapshot) ~= "table" or type(snapshot.Revision) ~= "number" or snapshot.Revision <= self.Revision then
		return
	end
	self.Revision = snapshot.Revision
	self.Snapshot = snapshot
	if snapshot.State == "IDLE" and not snapshot.Completion then
		-- A spectator exit is immediate even during a reveal or black-wipe transition.
		self:Interrupt()
		self:ApplySnapshot(snapshot)
		return
	end
	self:PlaySnapshotSounds(snapshot)
	if self.ModeVote then
		self.ModeVote:Show(snapshot, self.D.World:GetServerTimeNow())
	end
	if snapshot.MatchId and snapshot.MatchId == self.SuppressedMatch then
		return
	end
	local nextScene = scene(snapshot, self.UI)
	if (self.Scene and self.Scene ~= nextScene) or self.Transition.Phase == "OUT" then
		self.Scale:Enable(false)
		self.Transition:Run(function()
			local latest = self.Snapshot
			self:ApplySnapshot(latest)
			self.Scene = scene(latest, self.UI)
			self.Camera:Snap(self.Preview:Points())
		end)
	else
		self:ApplySnapshot(snapshot)
		self.Scene = nextScene
	end
end
function MatchController.ApplySnapshot(self: any, snapshot: any)
	if snapshot.State ~= "GUESSING" or not snapshot.CanGuess then
		self:ClearObjectHover()
	end
	self.VisualSnapshot = snapshot
	local state = snapshot.State
	if state == "MATCH_END" then
		if self.UI.HasEnd and self.UI:HasEnd(snapshot) then
			-- Keep the table view for the end screen; arriving from anywhere else, restore the normal camera first.
			if not (self.Scene and string.sub(self.Scene, 1, 6) == "TABLE:") then
				self:ClearView()
			end
			self.Scale:Enable(false)
			self.UI:Show(snapshot)
			return
		end
		self:ClearView()
		self.UI:Show(snapshot)
		return
	end
	local atTable = state == "TABLE_RETURN" or state == "TABLE_REACTION"
	if
		state ~= "ROUND_INTRO"
		and state ~= "GUESSING"
		and state ~= "TURN_LOCKED"
		and state ~= "ROUND_REVEAL"
		and not atTable
	then
		self:ClearView()
		self.SuppressedMatch = nil
		self.UI:Show(snapshot)
		return
	end
	if snapshot.MatchId == self.SuppressedMatch then
		return
	end
	if atTable then
		self.Scale:Enable(false)
		self.Dirty, self.RevealAnimation, self.PreviewRound = false, nil, nil
		self.Preview:Clear()
		-- The camera heads for the reaction's first player while it returns to the table, so the cutscene's first
		-- slot starts already framed on them (the Step loop then follows each slot's player).
		local target
		if self.D.ReactionCycle and self.D.ReactionCycle.Lineup then
			local lineup = self.D.ReactionCycle.Lineup(
				snapshot.Participants,
				snapshot.YourUserId,
				snapshot.HeartChanges,
				snapshot.LoserUserId
			)
			if lineup[1] then
				target = self:TablePlayer(lineup[1].UserId)
			end
		end
		if not target then
			target = self:TablePlayer(snapshot.TableFocusUserId or snapshot.LoserUserId or snapshot.OpponentUserId)
		end
		self.Camera:StartTable(snapshot.TableView, target)
		self.UI:Show(snapshot)
		return
	end
	self.Reaction:Clear()
	self:PreparePreview(snapshot)
	local newTurn = self.PreviewTurn ~= snapshot.TurnId
	if newTurn then
		self.PreviewTurn, self.PendingLock = snapshot.TurnId, nil
		table.clear(self.TickValues)
		table.clear(self.LandmarkValues)
		self.PendingHint = nil
		-- Watching changes the preview without changing our input value. Always
		-- reapply the active turn's guess, even when the slider value is unchanged.
		if snapshot.CanGuess then
			self.TurnStartGuess = snapshot.Guess
			self.Scale:Set(snapshot.Guess, true)
		end
		self.Dirty = false
	end
	if (state == "TURN_LOCKED" or (state == "GUESSING" and not snapshot.CanGuess)) and snapshot.WatchedGuess then
		-- Watching someone scale ticks too.
		if state == "GUESSING" and not newTurn then
			self:TickModel(snapshot.WatchedGuess, "watch")
		else
			self.TickValues["watch"] = snapshot.WatchedGuess
		end
		self.Preview:Set(snapshot.WatchedGuess, newTurn or state == "TURN_LOCKED")
		self.Dirty = false
	end
	if state == "TURN_LOCKED" then
		self.PendingLock = nil
	end
	if snapshot.Hint then
		self.PendingHint = nil
		-- A new exact-size highlight confirms itself: paid hints as a purchase, a pet's free hint as news.
		if self.HintAlertId ~= snapshot.Hint.Id then
			self.HintAlertId = snapshot.Hint.Id
			if self.D.Alerts and snapshot.CanGuess then
				if self.HintWasFree then
					self.D.Alerts:Show("Free hint!", "Notice")
				else
					self.D.Alerts:Show("Hint bought!", "Good")
					if self.D.Sfx then
						self.D.Sfx:Play("Purchase")
					end
				end
			end
		end
	end
	if self.Preview.SetHint then
		self.Preview:SetHint(
			if state == "GUESSING" and snapshot.CanGuess then snapshot.Hint else nil,
			self.D.World:GetServerTimeNow()
		)
	end
	self.UI:Show(snapshot)
	self.Scale:Enable(self:CanGuess())
	self.UI:EnableLock(self:CanGuess())
	if state == "ROUND_REVEAL" then
		-- Reveal uses the server's accepted guess; never score the optimistic visual.
		local key = snapshot.MatchId .. ":" .. snapshot.RoundId
		if self.RevealKey ~= key then
			self.RevealKey = key
			if self.Camera.BeginResultSettle then
				self.Camera:BeginResultSettle(key)
			end
			self.Preview:ShowResults(snapshot, self.D.World:GetServerTimeNow())
			self.RevealAnimation = nil
		end
		self.Dirty = false
	else
		self.RevealAnimation, self.RevealKey = nil, nil
	end
end
function MatchController.StepSabotageCue(self: any, dt: number)
	local cues = self.SabotageCues or {}
	if not self:CanInkSplat() or self.Transition:IsActive() then
		for _, cue in cues do cue:SetEnabled(false) end
		self.ActiveCue, self.CueDelay = nil, nil
		return
	end
	if self.ActiveCue then
		if self.ActiveCue:Step(dt) then
			self.ActiveCue:SetEnabled(false)
			self.ActiveCue = nil
			self.CueDelay = self.D.Config.SabotageVisuals.CuePauseSeconds
		end
		return
	end
	self.CueDelay = (self.CueDelay or 0) - dt
	if self.CueDelay > 0 or #cues == 0 then return end
	local choices = {}
	for _, cue in cues do
		if cue.Target.Visible and (#cues == 1 or cue ~= self.LastCue) then table.insert(choices, cue) end
	end
	if #choices == 0 then return end
	self.ActiveCue = choices[self.CueRandom:NextInteger(1, #choices)]
	self.LastCue = self.ActiveCue
	self.ActiveCue:Play()
end

function MatchController.Step(self: any, dt: number)
	local now = self.D.World:GetServerTimeNow()
	if self.ModeVote then
		self.ModeVote:Step(dt, now)
	end
	self.Transition:Step(dt)
	self.UI:Step(dt)
	self:StepSabotageCue(dt)
	local snapshot = self.Snapshot
	if self.PendingInk then
		local confirmed = false
		if snapshot then
			local events = snapshot.InkSplats
			if events then
				for _, event in events do
					if not (self.PendingKnown and self.PendingKnown[event.Id]) then confirmed = true end
				end
			elseif snapshot.InkSplat and not (self.PendingKnown and self.PendingKnown[snapshot.InkSplat.Id]) then
				confirmed = true
			end
		end
		if confirmed then
			self.PendingInk = nil
		elseif now - self.PendingInk > 2 then
			self.PendingInk = nil
			if self.UI.InkFailed then
				self.UI:InkFailed()
			end
			self.D.Ready:FireServer()
		end
	end
	if self.UI.EnableInkSplat then
		self.UI:EnableInkSplat(self:CanInkSplat())
	end
	if self.Ink then
		self.Ink:Step(if snapshot and snapshot.MatchId ~= self.SuppressedMatch then snapshot else nil, now)
	end
	if self.Sabotage then
		self.Sabotage:Step(if snapshot and snapshot.MatchId ~= self.SuppressedMatch then snapshot else nil, now)
		self.Camera.Sway = self.Sabotage:Sway(now)
		self.Camera.Frozen = self.Sabotage:Frozen(now)
		if self.UI.SetLagging then
			local lagEvent = self.Sabotage:ActiveEvent()
			local throwerName
			if lagEvent and snapshot then
				for _, participant in snapshot.Participants or {} do
					if participant.UserId == lagEvent.ThrowerUserId then
						throwerName = participant.Name
						break
					end
				end
			end
			local stutterX, stutterY = self.Sabotage:StutterOffset(now)
			self.UI:SetLagging(lagEvent ~= nil, now, throwerName, stutterX, stutterY)
		end
		-- Lag spikes glitch the mystery model itself (size jumps and a flickering outline, see
		-- SabotageEffectController.Glitch). Purely visual: the real guess, the slider and what is sent never change.
		local glitch = self.Sabotage:Glitch(now)
		self.Preview:SetGlitch(glitch)
		if glitch and glitch.Spike and glitch.Factor ~= 1 and self.D.Sfx then
			local key = tostring(glitch.Episode) .. ":" .. tostring(glitch.Frame)
			if self.GlitchSoundKey ~= key then
				self.GlitchSoundKey = key
				self.D.Sfx:Play(if glitch.Factor > 1 then "TickUp" else "TickDown")
			end
		end
	end
	if snapshot then
		self:TickPrizeRoll(snapshot, now)
	end
	local presentation = self.UI:Tick(self.VisualSnapshot, now)
	if not snapshot or snapshot.MatchId == self.SuppressedMatch then
		self:ClearObjectHover()
		return
	end
	-- A missed server transition must never strand the local scriptable camera. This is recoverable: do not leave the
	-- same match suppressed forever, and throttle Ready retries while waiting for an authoritative fresh snapshot.
	if snapshot.Deadline and snapshot.MatchId and now > snapshot.Deadline + 15 then
		if now - (self.RecoveryAt or 0) >= 2 then
			self:Interrupt()
			self.SuppressedMatch = nil
			self.RecoveryAt = now
			self.UI:ShowStatus("Connection lost. Restoring...")
			self.D.Ready:FireServer()
		end
		self:ClearObjectHover()
		return
	end
	if self.PendingLock and now - self.LockSentAt > 2 then
		self.PendingLock = nil
		self.D.Ready:FireServer()
	end
	local guessing = self:CanGuess()
	if self.PendingHint and now - self.PendingHint > 2 then
		self.PendingHint = nil
		self.D.Ready:FireServer()
	end
	if self.UI.EnableHint then
		self.UI:EnableHint(guessing and snapshot.CanBuyHint == true and not self.PendingHint)
	end
	self.Scale:Enable(guessing == true)
	-- Lay out against the authored CameraPart axis before input changes the geometry.
	self.Preview:SetViewBasis(if self.Camera.Mode == "ARENA" then self.Camera.ViewBasis else nil)
	self.Scale:Step(dt)
	self.UI:EnableLock(guessing == true)
	if guessing and self.Dirty and now - self.LastSend >= self.D.Config.ClientSendInterval then
		self.LastSend, self.Dirty = now, false
		self.D.Guess:FireServer(snapshot.MatchId, snapshot.RoundId, self.Scale.Value)
	end
	self.Preview:Step(dt)
	if self.Preview.StepHint then
		self.Preview:StepHint(now)
	end
	self.Preview:Present(presentation)
	-- During TABLE_REACTION the camera cycles to whoever ReactionCycle is currently showing (every participant in
	-- turn, ending on you); at every other table state it stays on the server's single TableFocusUserId.
	local reactionEntry, reactionCharacter
	if self.D.ReactionCycle and snapshot.State == "TABLE_REACTION" and snapshot.HeartAppliedAt then
		reactionEntry = self.D.ReactionCycle.Evaluate(
			snapshot.Participants,
			snapshot.YourUserId,
			snapshot.HeartChanges,
			snapshot.LoserUserId,
			snapshot.HeartAppliedAt,
			now,
			self.D.Config.TableReactionSlotSeconds
		)
		if reactionEntry then
			local focused = self:TablePlayer(reactionEntry.UserId)
			-- A bot's NPC is handed to the reaction effects directly; real players are looked up there by UserId.
			reactionCharacter = if type(focused) == "table" then focused.Character else nil
			-- Missing/streamed-out characters use the server table view, never the previous slot's cached avatar.
			if self.Camera.FocusTablePlayer then
				self.Camera:FocusTablePlayer(focused)
			else
				self.Camera.TargetPlayer = focused
			end
		end
	end
	self.Camera:Step(dt, self.Preview:Points())
	self:UpdateObjectHover()
	-- Project after the eased camera update so the ruler never trails a view turn.
	if self.UI.DrawReferenceMeasurement and self.Preview.ReferenceMeasurement then
		if self.Transition:IsActive() then
			self.UI:DrawReferenceMeasurement(nil)
		else
			self.UI:DrawReferenceMeasurement(self:OverlayCamera(), self.Preview:ReferenceMeasurement())
		end
	end
	if self.UI.DrawMysteryMeasurement and self.Preview.MysteryMeasurement then
		if self.Transition:IsActive() then
			self.UI:DrawMysteryMeasurement(nil)
		else
			local bounds, size, revealedMeters, revealedUserId, revealedColor = self.Preview:MysteryMeasurement()
			-- Keep the mystery caption unknown throughout play, even with a hint.
			-- Results measure the visible answer/guess, including reveal growth.
			local meters = if snapshot.State == "ROUND_REVEAL" then revealedMeters else nil
			local userId = if snapshot.State == "ROUND_REVEAL" then revealedUserId else nil
			local color = if snapshot.State == "ROUND_REVEAL" then revealedColor else nil
			self.UI:DrawMysteryMeasurement(self:OverlayCamera(), bounds, size, meters, userId, color)
		end
	end
	self.Reaction:Step(reactionEntry, reactionCharacter)
end
function MatchController.Destroy(self: any)
	for _, cue in self.SabotageCues or {} do cue:Destroy() end
	if self.ModeVote then
		self.ModeVote:Destroy()
	end
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	if self.DeathConnection then
		self.DeathConnection:Disconnect()
	end
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
	end
	self:ClearView()
	self.Transition:Destroy()
	self.Camera:Destroy()
	self.Scale:Destroy()
	self.UI:Destroy()
end
return MatchController

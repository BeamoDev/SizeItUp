--!strict
-- The authored Game frame split into states (used instead of GameFrameUI's flat layout when Game.AdjustingSize exists):
--   AdjustingSize        your turn: Left.Players (P1 is always you; P2-P4 are opponents), Lower (Submit, TimeLeft),
--                        Right.Container (Track/Minus/Plus) and Upper (Header with Title/Sub and P1-P4Points, Hint).
--                        Header alone carries every
--                        status, lock and result message.
--   OtherPlayerGuessing  another player's turn: Upper (Profile.Container.Mugshot, Username, Status, TimeLeft.Close.Label)
--                        and Lower.LightsOut (the ink splat button).
--   DamageFlash          pulses red while your own turn is running out of time (and on a lost heart, as before).
--   RevealWinner         (3-4 players: results stay on TargetSize.Container.Players.3v3/4v4, P1-P4 = mugshot + ???/metres) the reveal: TargetSize (its TargetSize label ticks up to the real height while the arena shows
--                        the target at real size) exits, then Scores enters: Enemy / Yourself (Meters = the guess, Frame.Mugshot),
--                        TheirScore.Score / YourScore.Score (X/100) tick up with the meters, and Actual shows the real size.
--                        EndMatch (Loser / Winner) and Points play in the MATCH_END state, after the last table reaction: the
--                        banner grows from nothing with a slight rotation, holds and shrinks away, then Points.Points slides
--                        from 0,0 to its place showing the XP earned. The table then ejects the players and the wipe back to
--                        the lobby begins. Lower stays hidden until it is set up. Without the reveal nodes the header
--                        carries the reveal text as before.
-- Player-card heart i is white while held and black when lost (its TextLabel then offers a refill on P1); Sudden Death
-- has one heart. BestOfFive is the points mode: Hearts hide and the Header shows one slot per seated player --
-- P1Points is always you, P2Points/P3Points/P4Points the other seats in order (P2 for a 1v1, P3 from 1v1v1, P4 at a
-- full 1v1v1v1); each slot's TextLabel reads "<username> Points" and its Points label "★ N". The older
-- YourPoints/TheirPoints/TheirPoints1/TheirPoints2 names still bind when the P-slots are not authored.
-- Every message, timer and request path is inherited from GameFrameUI; only the nodes and the state switching differ.
local Style = require(script.Parent.UIStyle)
local Base = require(script.Parent.GameFrameUI)
local Reveal = require(script.Parent.RevealPresentation)
local Motion = require(script.Parent.GameHUDMotion)
local HintWobble = require(script.Parent.HintWobble)
local MeasurementUI = require(script.Parent.MeasurementUI)
local Cycle = require(script.Parent.ReactionCycle)
local BotPortrait = require(script.Parent.BotPortrait)
local States = setmetatable({}, { __index = Base })
States.__index = States
local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local LOW_SECONDS = 5
local END_TILT = -14
-- How long each dot of the watched player's "Is Guessing." / ".." / "..." shows.
local GUESSING_DOT_SECONDS = 0.4
-- Left.Players card layout by mode: points modes (Best of Five) put the points label lower and the hearts at the
-- bottom; heart modes put the points label up top and the hearts in the middle.
local POINTS_POSITION_POINTS, POINTS_POSITION_HEARTS = UDim2.fromScale(0.606, 0.535), UDim2.fromScale(0.606, 0.335)
local HEARTS_POSITION_POINTS, HEARTS_POSITION_HEARTS = UDim2.fromScale(0.563, 0.881), UDim2.fromScale(0.563, 0.5)
-- The reaction verdict's colour fades in over this long (timing itself comes from ReactionCycle.Beats).
local REACTION_TINT_SECONDS = 0.3
local RED, GREEN = Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 230, 120)
local PRAISE_SECONDS = 1.35
local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c = 1.70158
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function scaled(size: UDim2, factor: number): UDim2
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

-- An authored tile may be a button itself or an image holding one; clicks use the button, motion the tile.
local function clickable(node: Instance): GuiButton?
	if node:IsA("GuiButton") then
		return node
	end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end
local function points(value: any): string
	return "★ " .. string.format("%d", math.floor((if type(value) == "number" then value else 0) + 0.5))
end
local function meters(value: number): string
	return string.format("%.2fm", value)
end
local function avatarId(entry: any): number
	return entry.AvatarUserId or entry.UserId
end

local function snapshotAvatar(s: any, userId: number): number
	if s.ActivePlayerUserId == userId and s.ActivePlayerAvatarUserId then return s.ActivePlayerAvatarUserId end
	for _, participant in s.Participants or {} do
		if participant.UserId == userId then return avatarId(participant) end
	end
	return userId
end

function States.new(playerGui: PlayerGui, config: any, starterGui: any, measurementMethods: any?)
	local player = playerGui.Parent
	local localUserId = if player and player:IsA("Player") then player.UserId else nil
	local authored = Style.Authoring
	local need = authored.Need
	local game = authored.Game
	local adjusting, other = need(game, "AdjustingSize", "GuiObject"), need(game, "OtherPlayerGuessing", "GuiObject")
	local left, lower, right, upper =
		need(adjusting, "Left"), need(adjusting, "Lower"), need(adjusting, "Right"), need(adjusting, "Upper")
	local header = need(upper, "Header")
	-- The reaction profile is optional, but every live stat now comes from Left.Players.P1-P4.
	local profile = left:FindFirstChild("Profile", true)
	local otherUpper, otherLower = need(other, "Upper"), need(other, "Lower")
	-- The watched player's nodes may sit directly in Upper or inside its Container/Profile frames.
	local function deep(name: string, class: string): any
		local node = otherUpper:FindFirstChild(name, true)
		assert(
			node and node:IsA(class),
			"Missing authored UI: " .. otherUpper:GetFullName() .. "." .. name .. " (" .. class .. ")"
		)
		return node
	end
	local watchButton = deep("TimeLeft", "GuiObject")
	local holders = {}
	-- The sabotage buttons live in Lower.Frame (Ink, Fog, Lag, Wobble); a bare Lower still works.
	local sabotageRoot = otherLower:FindFirstChild("Frame") or otherLower
	local SABOTAGE_NAMES = {
		Ink = { "Ink", "InkSplat", "LightsOut" },
		Lag = { "Lag" },
		FogBank = { "Fog", "FogBank" },
		Wobble = { "Wobble" },
	}
	local function sabotageName(kind: string): string?
		for _, name in SABOTAGE_NAMES[kind] do
			if sabotageRoot:FindFirstChild(name) then
				return name
			end
		end
		return nil
	end
	local function tile(parent: Instance, name: string): GuiButton
		local holder = need(parent, name, "GuiObject")
		local button = clickable(holder)
		assert(button, "Missing authored UI: " .. holder:GetFullName() .. " (a button, or a child button)")
		holders[button] = holder
		return button
	end
	local scaleContainer = need(right, "Container", "GuiObject")
	local scaleTrack = need(scaleContainer, "Track", "GuiObject")
	scaleTrack.Active = true
	local scaleKnob = scaleTrack:FindFirstChild("Knob", true)
	if scaleKnob and not scaleKnob:IsA("GuiObject") then
		scaleKnob = nil
	end
	local plusButton = tile(scaleContainer, "Plus")
	local minusButton = tile(scaleContainer, "Minus")
	local self: any = setmetatable({
		Gui = game,
		StatusGui = adjusting,
		Header = header,
		Title = need(header, "Title"),
		Paragraph = need(header, "Sub"),
		Adjusting = adjusting,
		Other = other,
		Left = left,
		Lower = lower,
		Right = right,
		Upper = upper,
		Timer = need(lower, "TimeLeft", "GuiObject"),
		Time = lower:FindFirstChild("TimeLeft"),
		CurrentPlayerName = "Player",
		Holders = holders,
		Slider = scaleContainer,
		Track = scaleTrack,
		Knob = scaleKnob,
		Plus = plusButton,
		Minus = minusButton,
		LockIn = tile(lower, "Submit"),
		HintButton = tile(upper, "Hint"),
		InkSplatButton = tile(sabotageRoot, sabotageName("Ink") or "Ink"),
		Flash = need(game, "DamageFlash"),
		PlayerGui = playerGui,
		LocalUserId = localUserId,
		Config = config,
		StarterGui = starterGui,
		HiddenGuis = {},
		HiddenCore = {},
		HeartImages = {},
		HeartLabels = {},
		HeartsFrame = nil,
		PointsLabel = nil,
		ProfileFrame = profile,
		ProfileImage = profile and need(profile, "ImageLabel", "ImageLabel"),
		ProfileName = profile and need(profile, "TextLabel", "TextLabel"),
		OtherUpper = otherUpper,
		OtherMugshot = deep("Mugshot", "ImageLabel"),
		OtherStatus = deep("Status", "TextLabel"),
		OtherName = deep("Username", "TextLabel"),
		OtherClock = need(need(watchButton, "Close", "GuiObject"), "Label", "TextLabel"),
	}, States)
	self:BindReveal(game)
	-- The table cutscene's header and red flash belong to PaintReaction/ReactionFlash (on ReactionCycle.Beats), so
	-- GameFrameUI's generic table message and heart flash stay out of the way instead of being overwritten.
	self.OwnsTable = true
	-- Optional header points slots, you first: P1Points-P4Points, else the older names (both may be absent now that
	-- Left.Players shows every player's points).
	local slotNames = if header:FindFirstChild("P1Points")
		then { "P1Points", "P2Points", "P3Points", "P4Points" }
		else { "YourPoints", "TheirPoints", "TheirPoints1", "TheirPoints2" }
	self.PointSlots = {}
	for index, name in slotNames do
		local frame = header:FindFirstChild(name)
		if frame then
			local label = frame:FindFirstChild("TextLabel")
			self.PointSlots[index] = {
				Frame = frame,
				Points = need(frame, "Points", "TextLabel"),
				Name = if label and label:IsA("TextLabel") then label else nil,
			}
		end
	end
	-- Left.Players: P1 is always the local player; P2-P4 are the other players in seat order. Each card:
	-- Frame.Frame.ImageLabel (mugshot), Frame.Frame.TextLabel (username), Frame.Hearts.1-3 and Frame.TextLabel (points).
	self.PlayerCards = {}
	local playersRoot = need(left, "Players", "GuiObject")
	for index = 1, 4 do
		local root = need(playersRoot, "P" .. index, "GuiObject")
		local body = need(root, "Frame", "GuiObject")
		local face = need(body, "Frame", "GuiObject")
		local heartsFrame = need(body, "Hearts", "GuiObject")
		local card = {
			Root = root,
			Mugshot = need(face, "ImageLabel", "ImageLabel"),
			Name = need(face, "TextLabel", "TextLabel"),
			HeartsFrame = heartsFrame,
			Hearts = {},
			Points = need(body, "TextLabel", "TextLabel"),
		}
		for i = 1, 3 do
			card.Hearts[i] = need(heartsFrame, tostring(i), "GuiObject")
		end
		self.PlayerCards[index] = card
		root.Visible = false
	end
	local ownCard = self.PlayerCards[1]
	self.HeartsFrame, self.PointsLabel = ownCard.HeartsFrame, ownCard.Points
	for i = 1, 3 do
		local heart = ownCard.Hearts[i]
		self.HeartImages[i] = heart
		local plus = heart:FindFirstChild("TextLabel")
		if plus and plus:IsA("TextLabel") then
			plus.Active = true
			plus.Visible = false
			self.HeartLabels[i] = plus
		end
	end
	-- A transient, deterministic results celebration. It is runtime presentation layered over the authored reveal,
	-- not a replacement screen, and is destroyed with the HUD clone.
	local praise = Instance.new("Frame")
	praise.Name, praise.AnchorPoint, praise.Position = "ScorePraiseEffect", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52)
	praise.Size, praise.BackgroundTransparency, praise.Visible, praise.ZIndex = UDim2.fromScale(0.62, 0.15), 1, false, 90
	praise.Parent = game
	local praiseText = Instance.new("TextLabel")
	praiseText.Name, praiseText.Size, praiseText.BackgroundTransparency, praiseText.ZIndex = "Text", UDim2.fromScale(1, 1), 1, 91
	praiseText.TextScaled, praiseText.TextColor3 = true, Color3.new(1, 1, 1)
	praiseText.Parent = praise
	local praiseStroke = MeasurementUI.StyleLabel(praiseText,"PraiseGradient",4)
	local praiseScale = Instance.new("UIScale")
	praiseScale.Name, praiseScale.Scale, praiseScale.Parent = "PraiseScale", 1, praise
	local sparkles = {}
	for i = 1, 8 do
		local sparkle = Instance.new("Frame")
		sparkle.Name, sparkle.AnchorPoint, sparkle.Size = "Sparkle" .. i, Vector2.new(0.5, 0.5), UDim2.fromOffset(12, 12)
		sparkle.BorderSizePixel, sparkle.Rotation, sparkle.ZIndex, sparkle.Parent = 0, 45, 90, praise
		local corner = Instance.new("UICorner")
		corner.CornerRadius, corner.Parent = UDim.new(0.2, 0), sparkle
		sparkles[i] = sparkle
	end
	self.PraiseRoot, self.PraiseText, self.PraiseStroke, self.PraiseScale, self.PraiseSparkles = praise, praiseText, praiseStroke, praiseScale, sparkles
	-- Bigger / smaller tick the model instead of clicking.
	self.Plus:SetAttribute("NoClick", true)
	self.Minus:SetAttribute("NoClick", true)
	-- The watched player's timer button is decoration only.
	if watchButton:IsA("GuiButton") then
		watchButton.Active = false
		watchButton.Selectable = false
	end
	-- The structural frames only group content; they never block dragging the object.
	self.Structural = { game, adjusting, other, lower, right, upper, otherLower }
	if measurementMethods then
		authored.Measurements(self, measurementMethods, true)
	end
	Style.Caption(holders[self.HintButton], "Hint")
	self.Motion = Motion.new()
	self.HintWobble = HintWobble.new(self.HintButton)
	-- Leaf panels animate; the frames that group them stay visible while any leaf is showing (see Step).
	self.AdjustingPanels = {
		{ left, "Left" },
		{ scaleContainer, "Right" },
		{ holders[self.LockIn], "Down" },
		{ self.Timer, "Down" },
		{ header, "Up" },
		{ holders[self.HintButton], "Up" },
	}
	-- The ink button sits in a UIListLayout, which would ignore any position tween: its whole Lower frame slides down
	-- and off screen instead (and the button itself just stays visible inside it).
	holders[self.InkSplatButton] = otherLower
	self.InkSplatButton.Visible = true
	-- The other troll buttons (Lag, FogBank, Wobble) sit beside it in the same Lower frame when authored.
	self.SabotageButtons = { Ink = self.InkSplatButton }
	for _, kind in { "Lag", "FogBank", "Wobble" } do
		local name = sabotageName(kind)
		local holder = if name then sabotageRoot:FindFirstChild(name) else nil
		local button = if holder and holder:IsA("GuiObject") then clickable(holder) else nil
		if button then
			self.SabotageButtons[kind] = button
			holders[button] = otherLower;
			(holder :: GuiObject).Visible = true
		end
	end
	self.OtherPanels = { { otherUpper, "Up" }, { otherLower, "Down" } }
	self.Panels = {}
	for _, group in { self.AdjustingPanels, self.OtherPanels } do
		for _, entry in group do
			self.Motion:Add(entry[1], entry[2])
			table.insert(self.Panels, entry[1])
		end
	end
	self.Containers =
		{ { Node = adjusting, Panels = self.AdjustingPanels }, { Node = other, Panels = self.OtherPanels } }
	if self.RevealBound then
		self.RevealPanels = { { self.TargetRoot } }
		if self.ScoresRoot then
			table.insert(self.RevealPanels, { self.ScoresRoot })
		end
		for _, entry in self.RevealPanels do
			self.Motion:Add(entry[1])
			table.insert(self.Panels, entry[1])
		end
		table.insert(self.Containers, { Node = self.RevealRoot, Panels = self.RevealPanels })
	end
	for _, frame in { lower, right, upper } do
		frame.Visible = true
	end
	for _, binding in
		{ { "MeasurementRoot", "DrawReferenceMeasurement" }, { "MysteryMeasurementRoot", "DrawMysteryMeasurement" } }
	do
		local root = self[binding[1]]
		if root then
			self.Motion:AddOverlay(root)
			table.insert(self.Panels, root)
			local draw = self[binding[2]]
			self[binding[2]] = function(owner, ...)
				draw(owner, ...)
				owner.Motion:Set(root, root.Visible and not owner.Closing)
				owner.Motion:ApplyOverlay(root)
			end
		end
	end
	-- Small, controller-owned juice on the real authored controls. Submit compresses while held; the matching size
	-- button pulses once when the smooth scaler first reaches its boundary.
	self.PolishConnections = {}
	self.SubmitPressValue, self.SubmitPressVelocity, self.SubmitPressed = 1, 0, false
	self.SubmitMotionItem = self.Motion.Items[holders[self.LockIn]]
	local function pointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	table.insert(self.PolishConnections, self.LockIn.InputBegan:Connect(function(input)
		if pointer(input) and self.LockIn.Active then
			self.SubmitPressed = true
		end
	end))
	table.insert(self.PolishConnections, self.LockIn.InputEnded:Connect(function(input)
		if pointer(input) then
			self.SubmitPressed = false
		end
	end))
	table.insert(self.PolishConnections, self.LockIn.Activated:Connect(function()
		self.SubmitPressed = false
	end))
	self.LimitScales = {}
	for side, button in { Minimum = self.Minus, Maximum = self.Plus } do
		local scale = button:FindFirstChild("LimitPulseScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name, scale.Parent = "LimitPulseScale", button
		end
		self.LimitScales[side] = scale
	end
	self:Hide(true)
	return self
end

-- Optional: binds RevealWinner when every node the reveal needs exists, otherwise reports what is missing.
function States.BindReveal(self: any, game: Instance)
	local root = game:FindFirstChild("RevealWinner")
	if not root then
		return
	end
	local missing = {}
	local function deep(within: Instance?, name: string, class: string): any
		if within then
			for _, node in within:GetDescendants() do
				if node.Name == name and node:IsA(class) then
					return node
				end
			end
		end
		table.insert(
			missing,
			(if within then within:GetFullName() else root:GetFullName()) .. ".." .. name .. " (" .. class .. ")"
		)
		return nil
	end
	local target = root:FindFirstChild("TargetSize")
	local scores = root:FindFirstChild("Scores")
	if not target then
		table.insert(missing, root:GetFullName() .. ".TargetSize")
	end
	local reveal: any = { Enemy = {}, Yourself = {} }
	-- The real height label is optional (TargetSize.TargetSize, or the Title beside the Container).
	local heightLabel = nil
	if target then
		for _, node in target:GetDescendants() do
			if node.Name == "TargetSize" and node:IsA("TextLabel") then
				heightLabel = node
				break
			end
		end
		heightLabel = heightLabel or target:FindFirstChild("Title")
	end
	reveal.Height = if heightLabel and heightLabel:IsA("TextLabel") then heightLabel else nil
	-- 3 or 4 players: results stay on TargetSize.Container.Players.3v3 / 4v4 (Frame.ImageLabel mugshot, TextLabel).
	local playersRoot = target and target:FindFirstChild("Players", true)
	if playersRoot then
		reveal.Players = {}
		for _, key in { "3v3", "4v4" } do
			local group = playersRoot:FindFirstChild(key)
			if not group then
				continue
			end
			local slots = {}
			for i = 1, (if key == "4v4" then 4 else 3) do
				local slot = group:FindFirstChild("P" .. i)
				local face = slot
					and slot:FindFirstChild("Frame")
					and slot.Frame:FindFirstChildWhichIsA("ImageLabel", true)
				local label = slot and slot:FindFirstChild("TextLabel")
				if slot and face and label and label:IsA("TextLabel") then
					slots[i] = { Root = slot, Face = face, Label = label }
				else
					table.insert(missing, group:GetFullName() .. ".P" .. i .. " (Frame.ImageLabel, TextLabel)")
				end
			end
			reveal.Players[key] = { Root = group, Slots = slots }
			group.Visible = false
		end
	end
	-- Two players still use the Scores frame (Enemy / Yourself).
	if scores then
		reveal.Actual = deep(scores, "Actual", "TextLabel")
		local theirScore, yourScore = deep(scores, "TheirScore", "GuiObject"), deep(scores, "YourScore", "GuiObject")
		reveal.Enemy.Score, reveal.Yourself.Score =
			deep(theirScore, "Score", "TextLabel"), deep(yourScore, "Score", "TextLabel")
		reveal.Enemy.ScoreFrame, reveal.Yourself.ScoreFrame = theirScore, yourScore
		for key, name in { Enemy = "Enemy", Yourself = "Yourself" } do
			local frame = deep(scores, name, "GuiObject")
			reveal[key].Frame = frame
			reveal[key].Meters = deep(frame, "Meters", "TextLabel")
			reveal[key].Mugshot = deep(frame, "Mugshot", "ImageLabel")
		end
	elseif not reveal.Players then
		table.insert(missing, root:GetFullName() .. ".Scores or TargetSize.Container.Players")
	end
	if #missing > 0 then
		warn(
			"RevealWinner is not fully authored; the header shows the reveal instead. Missing: "
				.. table.concat(missing, ", ")
		)
		return
	end
	self.RevealBound, self.RevealRoot, self.TargetRoot, self.ScoresRoot, self.RevealUI =
		true, root, target, scores, reveal
	-- Optional end-of-match banner and points; Lower is not driven yet, so it stays hidden.
	local endRoot = root:FindFirstChild("EndMatch") or root:FindFirstChild("End match")
	local pointsRoot = root:FindFirstChild("Points")
	if endRoot and pointsRoot then
		local function find(within: Instance, name: string): any
			for _, node in within:GetDescendants() do
				if node.Name == name and node:IsA("TextLabel") then
					return node
				end
			end
			return nil
		end
		local loser, winner, pointsLabel = find(endRoot, "Loser"), find(endRoot, "Winner"), find(pointsRoot, "Points")
		if loser and winner and pointsLabel then
			self.EndUI =
				{ Root = endRoot, Loser = loser, Winner = winner, PointsRoot = pointsRoot, Points = pointsLabel }
			for _, node in { loser, winner, pointsLabel } do
				Style.Authoring.Remember(node)
			end
		else
			warn(
				"RevealWinner end screen is not fully authored (needs EndMatch.Loser, EndMatch.Winner, Points.Points); it will not show."
			)
		end
	end
	for _, name in { "EndMatch", "End match", "Lower", "Points" } do
		local part = root:FindFirstChild(name)
		if part and part:IsA("GuiObject") then
			part.Visible = false
		end
	end
	if self.EndUI then
		for _, node in { self.EndUI.Loser, self.EndUI.Winner, self.EndUI.Points } do
			node.Visible = false
		end
	end
end
function States.ClearEnd(self: any)
	self.EndActive, self.EndKey, self.EndStart = false, nil, nil
	local ui = self.EndUI
	if not ui then
		return
	end
	ui.Root.Visible, ui.PointsRoot.Visible = false, false
	for _, node in { ui.Loser, ui.Winner, ui.Points } do
		node.Visible = false
	end
end
-- Whether a MATCH_END snapshot gets the end screen (cancelled matches, and layouts without it, do not).
function States.HasEnd(self: any, s: any): boolean
	return self.EndUI ~= nil and type(s.Result) == "string" and not string.find(s.Result, "CANCEL", 1, true)
end
-- The end screen: banner pops, holds and shrinks, then Points slide in and hold; the table ejects everyone when it is done.
function States.PaintEnd(self: any, s: any, now: number?)
	local ui = self.EndUI
	if s.State ~= "MATCH_END" or not self:HasEnd(s) then
		self:ClearEnd()
		return
	end
	if not now then
		return
	end
	local config = self.Config
	local pop, hold, shrink = config.EndBannerPopSeconds, config.EndBannerHoldSeconds, config.EndBannerShrinkSeconds
	local result = if s.Result == "YOU WIN!" then "WON" elseif s.Result == "YOU LOST!" then "LOST" else "DRAW"
	-- Server-relative, so a late snapshot joins mid-way instead of restarting.
	local age = now - ((s.Deadline or now) - config.EndSeconds)
	if age < 0 then
		ui.Root.Visible, ui.PointsRoot.Visible = false, false
		self.EndActive = false
		return
	end
	self.EndActive = true
	ui.Root.Visible = true
	local banner = if result == "WON" then ui.Winner elseif result == "LOST" then ui.Loser else nil
	for _, node in { ui.Loser, ui.Winner } do
		node.Visible = node == banner and age < pop + hold + shrink
	end
	if banner and banner.Visible then
		local pose = Style.Authoring.Pose(banner)
		local factor = if age < pop
			then backOut(age / pop)
			elseif age < pop + hold then 1
			else 1 - ((age - pop - hold) / shrink) ^ 2
		banner.Size = scaled(pose.Size, math.max(0, factor))
		banner.Rotation = pose.Rotation + END_TILT * (1 - math.clamp(age / pop, 0, 1)) ^ 2
	end
	-- Points come after the banner has gone.
	local pointsAge = age - (pop + hold + shrink)
	ui.PointsRoot.Visible = pointsAge >= 0 and s.MatchXP ~= nil
	if ui.PointsRoot.Visible then
		local pose = Style.Authoring.Pose(ui.Points)
		local e = 1 - (1 - math.clamp(pointsAge / config.EndPointsSeconds, 0, 1)) ^ 3
		ui.Points.Visible = true
		ui.Points.Text = "+" .. s.MatchXP .. " XP"
		ui.Points.Position = UDim2.new(
			e * pose.Position.X.Scale,
			e * pose.Position.X.Offset,
			e * pose.Position.Y.Scale,
			e * pose.Position.Y.Offset
		)
	end
end
function States.Hide(self: any, immediate: boolean?)
	Base.Hide(self, immediate)
	self.SubmitPressed = false
	for _, scale in self.LimitScales or {} do
		scale.Scale = 1
	end
	self.LimitPulseAge, self.LimitPulseSide = nil, nil
	self.PraiseRoot.Visible = false
	self:ClearEnd()
end

-- Clicks use the button; motion, captions and visibility use the tile that holds it.
function States.Panel(self: any, node: GuiObject?, on: boolean)
	if node then
		self.Motion:Set(self.Holders[node] or node, on)
	end
end
local function enable(button: GuiButton, on: boolean)
	button.Active, button.Selectable, button.AutoButtonColor = on, on, on
end
function States.EnableInkSplat(self: any, on: boolean)
	for _, button in self.SabotageButtons do
		enable(button, on)
	end
end
function States.EnableLock(self: any, on: boolean)
	enable(self.LockIn, on)
	enable(self.Plus, on)
	enable(self.Minus, on)
	Style.Caption(self.Holders[self.LockIn], if on then "Submit" else "Locked")
	if not on then
		self.SubmitPressed = false
	end
end
function States.PulseScaleLimit(self: any, side: string)
	if self.LimitScales and self.LimitScales[side] then
		self.LimitPulseSide, self.LimitPulseAge = side, 0
	end
end
function States.SetGuess(self: any, meters: number, alpha: number)
	self.SelectedGuessMeters = meters
	if self.Knob then
		local pose = Style.Authoring.Pose(self.Knob)
		self.Knob.Position = UDim2.new(
			pose.Position.X.Scale,
			pose.Position.X.Offset,
			0.9 - 0.8 * math.clamp(alpha, 0, 1),
			pose.Position.Y.Offset
		)
	end
end
function States.BlocksObjectDrag(self: any, position: Vector3): boolean
	for _, node in self.PlayerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if
			node == Style.Authoring.HUD
			or node == Style.Authoring.Overlays
			or node == self.Flash
			or table.find(self.Structural, node)
		then
			continue
		end
		if
			node:IsA("GuiButton")
			or node:IsA("TextBox")
			or node:IsA("ScrollingFrame")
			or node.Active
			or node.BackgroundTransparency < 1
		then
			return true
		end
	end
	return false
end

function States.Step(self: any, dt: number)
	Base.Step(self, dt)
	-- Critically damped press/release: quick on contact, softer on release, without spawning tweens or connections.
	local target = if self.SubmitPressed then 0.91 else 1
	local omega = if self.SubmitPressed then 32 else 18
	local error = self.SubmitPressValue - target
	local step = math.max(0, dt)
	local temp = (self.SubmitPressVelocity + omega * error) * step
	local decay = math.exp(-omega * step)
	self.SubmitPressValue = target + (error + temp) * decay
	self.SubmitPressVelocity = (self.SubmitPressVelocity - omega * temp) * decay
	if self.SubmitMotionItem and self.SubmitMotionItem.Scale then
		self.SubmitMotionItem.Scale.Scale *= self.SubmitPressValue
	end
	if self.LimitPulseAge then
		self.LimitPulseAge += step
		local duration = 0.52
		local progress = math.clamp(self.LimitPulseAge / duration, 0, 1)
		local pulse = 1 + 0.11 * math.sin(progress * math.pi * 2) * (1 - progress)
		for side, scale in self.LimitScales do
			scale.Scale = if side == self.LimitPulseSide then pulse else 1
		end
		if progress >= 1 then
			self.LimitPulseAge, self.LimitPulseSide = nil, nil
		end
	end
	for _, group in self.Containers do
		local any = false
		for _, entry in group.Panels do
			if entry[1].Visible then
				any = true
				break
			end
		end
		group.Node.Visible = any or (group.Node == self.RevealRoot and self.EndActive == true)
	end
end

local function only(self: any, adjusting: { any }, other: { any })
	for _, entry in self.AdjustingPanels do
		self.Motion:Set(entry[1], table.find(adjusting, entry[1]) ~= nil)
	end
	for _, entry in self.OtherPanels do
		self.Motion:Set(entry[1], table.find(other, entry[1]) ~= nil)
	end
end
-- Messages only (waiting, intro, locked, table, reveal, completion) use the header.
function States.ShowStatus(self: any, message: string)
	Base.ShowStatus(self, message)
	only(self, { self.Header }, {})
	if self.RevealBound then
		for _, entry in self.RevealPanels do
			self.Motion:Set(entry[1], false)
		end
	end
end
function States.Show(self: any, s: any)
	if s.State == "MATCH_END" and self:HasEnd(s) then
		self:ShowEnd(s)
		return
	end
	if s.State ~= "MATCH_END" then
		self:ClearEnd()
	end
	Base.Show(self, s)
	if self.StatusOnly or not Style.IsEnabled(self.Gui) or self.Closing then
		return
	end
	local state = s.State
	local watching = state == "GUESSING"
		and not s.CanGuess
		and s.ActivePlayerUserId ~= nil
		and s.ActivePlayerUserId ~= s.YourUserId
	local guessing = state == "GUESSING" and s.CanGuess == true
	local keep = { self.Header }
	-- The header stays away while the camera returns to the table; it slides in with the first player's name.
	if (state == "ROUND_REVEAL" and self.RevealBound) or state == "TABLE_RETURN" then
		keep = {}
	end
	self:UpdateReacting(s)
	if guessing then
		for _, node in
			{
				self.Slider,
				self.Holders[self.LockIn],
				self.Holders[self.HintButton],
				self.Timer,
			}
		do
			table.insert(keep, node)
		end
	end
	-- Only the header is left once you submit; the timer and size controls slide off screen.
	if watching then
		keep = {}
	end
	-- The Left panel (your hearts and every player's card) stays on screen for the whole match.
	table.insert(keep, self.Left)
	only(self, keep, if watching then { self.OtherUpper, self.Holders[self.InkSplatButton] } else {})
	if self.RevealBound and state ~= "ROUND_REVEAL" then
		for _, entry in self.RevealPanels do
			self.Motion:Set(entry[1], false)
		end
	end
	-- The ink button is offered only while watching, once per turn (GameFrameUI's rule).
	self:Panel(self.InkSplatButton, watching)
	self:PaintStates(s, nil)
end

-- MATCH_END: only the end screen; the rest of the HUD has already gone.
function States.ShowEnd(self: any, s: any)
	self.Snapshot, self.StatusOnly = s, false
	-- The match result: a win or a loss has its own sound (a draw has none).
	if self.WonKey ~= s.MatchId then
		if s.Result == "YOU WIN!" then
			self.WonKey = s.MatchId
			Style.Play("YouWin")
		elseif s.Result == "YOU LOST!" then
			self.WonKey = s.MatchId
			Style.Play("YouLose")
		end
	end
	self:HideMeasurements()
	self:EndResults()
	self:Open()
	only(self, {}, {})
	if self.RevealBound then
		for _, entry in self.RevealPanels do
			self.Motion:Set(entry[1], false)
		end
	end
	self:EnableLock(false)
	self:EnableHint(false)
	self:EnableInkSplat(false)
	self.Flash.BackgroundTransparency = 1
	self:PaintEnd(s, self.LastPaintNow)
end

-- The Left panel's profile: the picture only reloads when the player changes.
function States.SetLeftProfile(self: any, userId: number?, name: string, portraitUserId: number?)
	if not self.ProfileImage then
		return
	end
	local portrait = portraitUserId or userId
	if userId and portrait and (self.LeftId ~= userId or self.LeftPortraitId ~= portrait) then
		self.LeftId, self.LeftPortraitId = userId, portrait
		BotPortrait.Set(self.ProfileImage, userId, portrait, self.Config)
	end
	self.ProfileName.Text = name
end
-- Paints one player card's Frame.Hearts: `before` lit hearts turning into
-- `after` as `change` goes 0 to 1 (the changed heart pops), `lives` shown at all.
local function paintHearts(images: { any }, lives: number, before: number, after: number, change: number)
	for i, heart in images do
		local pop = heart:FindFirstChild("HeartPop") :: UIScale?
		if not pop then
			pop = Instance.new("UIScale")
			pop.Name, pop.Parent = "HeartPop", heart
		end
		heart.Visible = i <= lives
		local had, has = i <= before, i <= after
		local t = if had == has then 1 else change
		local lit = (if had then 1 else 0) + ((if has then 1 else 0) - (if had then 1 else 0)) * t
		heart.ImageColor3 = black:Lerp(white, lit)
		heart.ImageTransparency = 0.5 * (1 - lit)
		;(pop :: UIScale).Scale = if had == has then 1 else 1 + 0.4 * math.sin(math.pi * change)
	end
end

-- P1 is always the local player. Offer only the next missing heart, so one click always maps to the label the
-- player expects: heart 2 while they have one heart, then heart 3 while they have two.
function States.PaintHeartPurchase(self: any, s: any, now: number?)
	local lives = if s.Mode == "SuddenDeath" then 1 else self.Config.StartingHearts
	local have = math.clamp(math.floor(s.YourHearts or 0), 0, lives)
	local liveMatch = s.MatchId ~= nil
		and s.State ~= "IDLE"
		and s.State ~= "MATCH_END"
		and s.Mode ~= "BestOfFive"
	local reactionFinished = true
	if liveMatch and s.State == "TABLE_REACTION" and s.HeartAppliedAt then
		local changes = Cycle.Deltas(s.HeartChanges, s.LoserUserId)
		if (changes[s.YourUserId] or 0) < 0 then
			reactionFinished = false
			local lineup = Cycle.Lineup(s.Participants, s.YourUserId, s.HeartChanges, s.LoserUserId)
			for slot, participant in lineup do
				if participant.UserId == s.YourUserId then
					local elapsed = math.max(0, (now or self.LastPaintNow or s.HeartAppliedAt) - s.HeartAppliedAt)
					local completedAt = (slot - 1) * self.Config.TableReactionSlotSeconds
						+ Cycle.Beats.Heart
						+ Cycle.Beats.HeartSeconds
					reactionFinished = elapsed >= completedAt
					break
				end
			end
		end
	end
	local nextHeart = if liveMatch and reactionFinished and have < lives then have + 1 else nil
	for index, label in self.HeartLabels do
		label.Visible = index == nextHeart
	end
end
-- P1 is always you: heart modes show its Hearts row and points modes show its Points label.
function States.PaintOwnStat(self: any, s: any)
	local pointsMode = s.Mode == "BestOfFive"
	self.HeartsFrame.Visible = not pointsMode
	if self.PointsLabel then
		self.PointsLabel.Visible = pointsMode
		if pointsMode then
			local total = s.TotalAccuracy
			for _, participant in s.Participants or {} do
				if participant.UserId == s.YourUserId and total == nil then
					total = participant.Points
				end
			end
			self.PointsLabel.Text = points(total)
		end
	end
end
-- Hearts to show for one player right now: during the table cutscene a player's change happens in their own slot
-- (before it the old count, after it the new one); at any other time simply their current hearts.
function States.HeartsFor(self: any, s: any, participant: any): (number, number, number)
	local now = participant.Hearts or 0
	local cycle = self.Cycle
	if not cycle then
		return now, now, 1
	end
	local delta = Cycle.Deltas(s.HeartChanges, s.LoserUserId)[participant.UserId] or 0
	local slot
	for index, entry in cycle.Order do
		if entry.UserId == participant.UserId then
			slot = index
		end
	end
	if not slot or delta == 0 or slot < cycle.Index then
		return now, now, 1
	end
	local before = math.max(0, now - delta)
	if slot > cycle.Index then
		return before, before, 1
	end
	local beats = Cycle.Beats
	return before, now, math.clamp((cycle.SlotAge - beats.Heart) / beats.HeartSeconds, 0, 1)
end
-- The Left.Players cards use local-first ordering: P1 is you and P2-P4 are the other seats.
-- Mugshot and username always; a points mode
-- (Best of Five) shows only "★ points", a heart mode only the hearts, each at its mode's position.
function States.PaintPlayers(self: any, s: any)
	if not next(self.PlayerCards) then
		return
	end
	local pointsMode = s.Mode == "BestOfFive"
	local lives = if s.Mode == "SuddenDeath" then 1 else self.Config.StartingHearts
	local ordered = {}
	for _, participant in s.Participants or {} do
		if participant.UserId == s.YourUserId then table.insert(ordered, 1, participant) else table.insert(ordered, participant) end
	end
	for index, card in self.PlayerCards do
		local participant = ordered[index]
		card.Root.Visible = participant ~= nil
		if participant then
			local portrait = avatarId(participant)
			if card.UserId ~= participant.UserId or card.PortraitUserId ~= portrait then
				card.UserId, card.PortraitUserId = participant.UserId, portrait
				BotPortrait.Set(card.Mugshot, participant.UserId, portrait, self.Config)
			end
			card.Name.Text = if index == 1 then "YOU" else participant.Username or participant.Name or "Player"
			local value = if participant.UserId == s.YourUserId then (s.TotalAccuracy or participant.Points) else participant.Points
			card.Points.Text = points(value)
			card.Points.Position = if pointsMode then POINTS_POSITION_POINTS else POINTS_POSITION_HEARTS
			card.HeartsFrame.Position = if pointsMode then HEARTS_POSITION_POINTS else HEARTS_POSITION_HEARTS
			card.Points.Visible, card.HeartsFrame.Visible = pointsMode, not pointsMode
			local before, after, change = self:HeartsFor(s, participant)
			paintHearts(card.Hearts, lives, before, after, change)
		end
	end
end
-- The table cutscene cycles through every player who played the round, in order starting after you and ending on
-- yourself (see ReactionCycle), every round and in every mode. One slot per player, all on ReactionCycle.Beats:
-- the title shows their username as the camera arrives, the subtitle says whether they are safe or lost a life (the
-- avatar highlight and icon land at the same moment, see ReactionController), then the Left panel slides in, the
-- heart changes, and the panel slides out before the camera moves on. Only PaintReaction writes the header here.
function States.UpdateReacting(self: any, s: any, now: number?)
	self.Cycle = if s.State == "TABLE_REACTION" and s.HeartAppliedAt
		then Cycle.Evaluate(
			s.Participants,
			s.YourUserId,
			s.HeartChanges,
			s.LoserUserId,
			s.HeartAppliedAt,
			now or self.LastPaintNow or 0,
			self.Config.TableReactionSlotSeconds
		)
		else nil
	self.Reacting = self.Cycle ~= nil
end
-- Subtitle and colour for the slot's outcome.
local function verdict(cycle: any): (string, Color3)
	if cycle.Eliminated then
		return if cycle.IsYou then "You're out!" else "Is out!", RED
	elseif cycle.Delta < 0 then
		return if cycle.IsYou then "You lost a life!" else "Lost a life!", RED
	elseif cycle.Delta > 0 then
		return if cycle.IsYou then "You got a life back!" else "Got a life back!", GREEN
	end
	return if cycle.IsYou then "You are safe!" else "Is safe!", GREEN
end
function States.PaintReaction(self: any, s: any, now: number?)
	now = now or self.LastPaintNow
	local cycle = self.Cycle
	if not cycle or not now then
		return
	end
	local beats = Cycle.Beats
	local age = cycle.SlotAge
	self.Motion:Set(self.Header, true)
	self.Motion:Set(self.Left, true)
	local name = cycle.Username or cycle.Name or "Player"
	self:SetLeftProfile(cycle.UserId, if cycle.IsYou then "YOU" else name, snapshotAvatar(s, cycle.UserId))
	-- Every card's hearts change in that player's own slot. P1 remains the local player throughout the cutscene.
	self:PaintOwnStat(s)
	self:PaintPlayers(s)
	-- Header: the username from the first frame of the slot; the verdict joins it once the camera has arrived.
	self.Title.Text = name
	if age < beats.Verdict then
		self.Paragraph.Text, self.Title.TextColor3 = "", white
	else
		local text, color = verdict(cycle)
		self.Paragraph.Text = text
		-- One sound per player, landing with the verdict: HeartLost for a lost life, Safe otherwise. A snapshot
		-- joining late in the slot stays silent rather than playing it out of sync.
		local key = tostring(cycle.UserId) .. "@" .. tostring(cycle.Index) .. "@" .. tostring(s.HeartAppliedAt)
		if self.ReactionSoundKey ~= key and age < beats.Verdict + 0.5 then
			self.ReactionSoundKey = key
			Style.Play(if cycle.Delta < 0 then "HeartLost" else "Safe")
		end
		self.Title.TextColor3 = white:Lerp(color, math.clamp((age - beats.Verdict) / REACTION_TINT_SECONDS, 0, 1))
	end
end
-- The red screen flash for your own lost heart, landing with your verdict (never during someone else's slot).
function States.ReactionFlash(self: any): number
	local cycle = self.Cycle
	if not cycle or not cycle.IsYou or cycle.Delta >= 0 then
		return 1
	end
	local age = cycle.SlotAge - Cycle.Beats.Verdict
	local seconds = self.Config.HeartFlashSeconds
	return if age >= 0 and age < seconds then 1 - 0.28 * (1 - age / seconds) else 1
end
function States.PaintStates(self: any, s: any, now: number?)
	local pointsMode = s.Mode == "BestOfFive"
	local have = s.YourHearts or 0
	-- Buying a heart back is a purchase (losing one is silent).
	if s.YourHearts ~= nil then
		if self.HeartMatch ~= s.MatchId then
			self.HeartMatch, self.LastHearts = s.MatchId, have
		elseif have > (self.LastHearts or have) and s.State == "GUESSING" then
			Style.Play("Purchase")
			Style.Alert("Heart bought!", "Good")
			self.LastHearts = have
		else
			self.LastHearts = have
		end
	end
	if not self.Reacting then
		self:PaintOwnStat(s)
		self:PaintPlayers(s)
	end
	self:PaintHeartPurchase(s, now)
	-- One points slot per seated player: P1 is you, then the other seats in order (the reveal's local-first order),
	-- each coloured like that player's results (Config.ResultColor). A slot shows only when the table has that
	-- many players.
	local order = {}
	for _, participant in s.Participants or {} do
		if participant.UserId == s.YourUserId then
			table.insert(order, 1, participant)
		else
			table.insert(order, participant)
		end
	end
	local seats = #order
	for slot, ui in self.PointSlots do
		local participant = order[slot]
		ui.Frame.Visible = pointsMode and participant ~= nil
		if pointsMode and participant then
			local mine = participant.UserId == s.YourUserId
			ui.Points.Text = points(if mine then s.TotalAccuracy or participant.Points else participant.Points)
			ui.Points.TextColor3 = Color3.fromRGB(table.unpack(self.Config.ResultColor(slot, seats)))
			if ui.Name then
				ui.Name.Text = (participant.Username or participant.Name or "Player") .. " Points"
			end
		end
	end
	if not self.Reacting then
		self:SetLeftProfile(s.YourUserId, "YOU", s.YourAvatarUserId)
	end
	local watchedPortrait = s.ActivePlayerAvatarUserId or s.ActivePlayerUserId
	if s.ActivePlayerUserId and (self.WatchedId ~= s.ActivePlayerUserId or self.WatchedPortraitId ~= watchedPortrait) then
		self.WatchedId, self.WatchedPortraitId = s.ActivePlayerUserId, watchedPortrait
		BotPortrait.Set(self.OtherMugshot, s.ActivePlayerUserId, watchedPortrait, self.Config)
	end
	now = now or self.LastPaintNow
	-- The dots cycle "." / ".." / "..." on the shared clock while you watch.
	local dots = 3
	if now then
		dots = math.floor(now / GUESSING_DOT_SECONDS) % 3 + 1
	end
	self.OtherStatus.Text = "Is Guessing" .. string.rep(".", dots)
	self.OtherName.Text = s.ActivePlayerUsername or s.ActivePlayerName or ""
	if now and s.Deadline then
		self.OtherClock.Text = math.max(0, math.ceil(s.Deadline - now)) .. "s Left"
	end
end
local PRAISE_LINES = {
	Perfect = { "PERFECT!", "NAILED IT!", "SPOT ON!", "BULLSEYE!", "SIZE MASTER!", "UNREAL!" },
	Amazing = { "AMAZING!", "SO CLOSE!", "INCREDIBLE!", "CRUSHED IT!", "WHAT A GUESS!", "WOW!" },
	Great = { "GREAT GUESS!", "SHARP EYE!", "AWESOME!", "SUPER CLOSE!", "NICE ONE!", "GREAT WORK!" },
	Good = { "GOOD JOB!", "WELL PLAYED!", "SOLID GUESS!", "LOOKING GOOD!", "NICE WORK!", "YOU GOT THIS!" },
}
local function praiseFor(accuracy: number): ({ string }?, Color3?, boolean)
	if accuracy >= 99 and accuracy <= 100 then
		return PRAISE_LINES.Perfect, Color3.fromRGB(255, 218, 65), true
	elseif accuracy >= 95 then
		return PRAISE_LINES.Amazing, Color3.fromRGB(255, 102, 221), true
	elseif accuracy >= 88 then
		return PRAISE_LINES.Great, Color3.fromRGB(82, 226, 255), true
	elseif accuracy >= 75 then
		return PRAISE_LINES.Good, Color3.fromRGB(100, 244, 137), false
	end
	return nil, nil, false
end
-- A quick upward score pop begins when the visible guess finishes growing. Everything is derived from the server
-- reveal clock, so repeated snapshots retain the same animation rather than restarting it.
function States.PaintPraise(self: any, view: any, entry: any?, s: any)
	local root = self.PraiseRoot
	local age = view.Sequence.SlotAge - self.Config.ResultAnnounceSeconds - self.Config.ResultGrowSeconds
	local accuracy = if entry then math.clamp(entry.Accuracy or 0, 0, 100) else 0
	local lines, color, burst = praiseFor(accuracy)
	-- Praise is personal feedback. Opponents still get their normal score reveal, without a local celebration over it.
	local ownUserId = self.LocalUserId or s.YourUserId
	if not entry or entry.UserId ~= ownUserId or not lines or age < 0 or age >= PRAISE_SECONDS then
		root.Visible = false
		return
	end
	local key = tostring(s.MatchId) .. ":" .. tostring(s.RoundId) .. ":" .. tostring(entry.UserId)
	if self.PraisePhraseKey ~= key then
		local hash = math.floor(accuracy * 100 + 0.5)
		for index = 1, #key do
			hash = (hash * 33 + string.byte(key, index)) % 2147483647
		end
		local choice = hash % #lines + 1
		if #lines > 1 and lines[choice] == self.LastPraiseText then
			choice = choice % #lines + 1
		end
		self.PraisePhraseKey = key
		self.PraisePhrase = lines[choice]
		self.LastPraiseText = self.PraisePhrase
	end
	local message = self.PraisePhrase
	local enter = backOut(math.clamp(age / 0.24, 0, 1))
	local fade = math.clamp((PRAISE_SECONDS - age) / 0.35, 0, 1)
	local travel = math.clamp(age / PRAISE_SECONDS, 0, 1)
	root.Visible = true
	root.Position = UDim2.fromScale(0.5, 0.52 - 0.12 * travel)
	root.Rotation = 3 * math.sin(age * 13) * (1 - travel)
	self.PraiseScale.Scale = 0.58 + 0.48 * enter
	self.PraiseText.Text, self.PraiseText.TextColor3 = message, Color3.new(1,1,1)
	self.PraiseText.TextTransparency, self.PraiseStroke.Transparency = 1 - fade, 1 - fade
	if self.PraiseKey ~= key then
		self.PraiseKey = key
		Style.Play(if accuracy >= 95 then "Safe" else "TickUp")
	end
	for i, sparkle in self.PraiseSparkles do
		local angle = (i - 1) * math.pi / 4
		local strength = math.clamp((accuracy - 75) / 25, 0, 1)
		local distance = (0.18 + 0.18 * strength) * math.clamp(age / 0.55, 0, 1)
		local size = 7 + 8 * strength
		sparkle.Visible = burst or strength >= 0.45
		sparkle.Size = UDim2.fromOffset(size, size)
		sparkle.BackgroundColor3 = if i % 2 == 0 then color else Color3.new(1, 1, 1)
		sparkle.BackgroundTransparency = 1 - fade
		sparkle.Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance * 1.8)
		sparkle.Rotation = 45 + age * 180 * (if i % 2 == 0 then 1 else -1)
	end
end
-- TargetSize ticks up to the real height while the target is shown at real size, then leaves as Scores arrive; each
-- guess's Meters and X/100 tick up together as its slot grows and stay at their final values afterwards.
function States.PaintReveal(self: any, view: any, s: any)
	local ui, config = self.RevealUI, self.Config
	local frozen = self.RevealSnapshot or s
	local scored = frozen.Reveal
	if not scored then
		return
	end
	local age, intro = view.Age, config.RevealIntroSeconds()
	-- With three or four players the results stay on TargetSize (Players.3v3 / 4v4); two players move on to Scores.
	local count = #scored.Results
	local usePlayers = ui.Players ~= nil and count >= 3 and ui.Players[if count >= 4 then "4v4" else "3v3"] ~= nil
	local showTarget = age >= config.ResultReferenceSeconds and (usePlayers or age < intro)
	local showScores = age >= intro and not usePlayers and self.ScoresRoot ~= nil
	self.Motion:Set(self.TargetRoot, showTarget)
	if self.ScoresRoot then
		self.Motion:Set(self.ScoresRoot, showScores)
	end
	local actual = scored.Actual or 0
	local tick = math.clamp(
		(age - config.ResultReferenceSeconds) / (config.ResultActualAppearSeconds + config.ResultActualHoldSeconds),
		0,
		1
	)
	if ui.Height then
		ui.Height.Text = meters(actual * (1 - math.cos(tick * math.pi)) * 0.5)
	end
	-- The height counting up, and each guess's meters and score counting up, tick.
	local tickKey = nil
	if showTarget and tick > 0 and tick < 1 then
		tickKey = "target:" .. math.floor(tick * 24)
	end
	if ui.Actual then
		ui.Actual.Text = meters(actual)
	end
	local ordered = Reveal.Order(scored.Results, frozen.YourUserId)
	local current = view.Sequence.Index
	local growth = (1 - math.cos(view.Sequence.Growth * math.pi)) * 0.5
	local mine, others = nil, {}
	for index, entry in ordered do
		if entry.UserId == frozen.YourUserId then
			mine = index
		else
			table.insert(others, index)
		end
	end
	-- The Enemy card follows whichever opponent is being announced (the first one before their turn comes).
	local shown = others[1]
	for _, index in others do
		if current and index <= current then
			shown = index
		end
	end
	local function fill(card: any, index: number?)
		card.Frame.Visible = index ~= nil
		card.ScoreFrame.Visible = index ~= nil
		if not index then
			return
		end
		local entry = ordered[index]
		local progress = if not current or index > current then 0 elseif index < current then 1 else growth
		local resultColor = Color3.fromRGB(table.unpack(config.ResultColor(index, count)))
		card.Meters.Text = meters((entry.Guess or 0) * progress)
		card.Score.Text = string.format(
			"%d/100",
			math.floor(
				math.clamp(entry.Accuracy or 0, 0, 100) * progress + (if scored.Mode == "Endless" then 1e-7 else 0.5)
			)
		)
		-- Measurements stay white; only the accuracy score uses the player's reveal colour.
		card.Meters.TextColor3 = white
		card.Score.TextColor3 = white:Lerp(resultColor, progress)
		local portrait = avatarId(entry)
		if card.UserId ~= entry.UserId or card.PortraitUserId ~= portrait then
			card.UserId, card.PortraitUserId = entry.UserId, portrait
			BotPortrait.Set(card.Mugshot, entry.UserId, portrait, config)
			-- The mugshot's background is that player's result colour from your point of view (you blue in a duel).
			card.Mugshot.BackgroundColor3 = resultColor
			card.Mugshot.BackgroundTransparency = 0
		end
	end
	if usePlayers then
		-- Each guesser's slot reads ??? until their result is announced, then their guess grows to its size in metres.
		local active = if count >= 4 then "4v4" else "3v3"
		for key, group in ui.Players do
			group.Root.Visible = key == active
			if key ~= active then
				continue
			end
			for i, slot in group.Slots do
				local entry = ordered[i]
				slot.Root.Visible = entry ~= nil
				if not entry then
					continue
				end
				local portrait = avatarId(entry)
				if slot.UserId ~= entry.UserId or slot.PortraitUserId ~= portrait then
					slot.UserId, slot.PortraitUserId = entry.UserId, portrait
					BotPortrait.Set(slot.Face, entry.UserId, portrait, config)
					slot.Face.BackgroundColor3 = Color3.fromRGB(table.unpack(config.ResultColor(i, count)))
					slot.Face.BackgroundTransparency = 0
				end
				local progress = if not current or i > current then nil elseif i < current then 1 else growth
				slot.Label.Text = if progress then meters((entry.Guess or 0) * progress) else "???"
				slot.Label.TextColor3 = white
			end
		end
	else
		if ui.Players then
			for _, group in ui.Players do
				group.Root.Visible = false
			end
		end
		if ui.Yourself.Frame then
			fill(ui.Yourself, mine)
			fill(ui.Enemy, shown)
		end
	end
	if (showScores or usePlayers) and current and growth > 0 and growth < 1 then
		tickKey = "guess" .. current .. ":" .. math.floor(growth * 21)
	end
	if tickKey and tickKey ~= self.TickKey then
		Style.Play("TickUp")
	end
	self.TickKey = tickKey or self.TickKey
end
function States.Paint(self: any, s: any, now: number?)
	local view = Base.Paint(self, s, now)
	self:UpdateReacting(s)
	-- The table scenes are this layout's alone (OwnsTable): blank while the camera returns, then PaintReaction.
	if (s.State == "TABLE_RETURN" or s.State == "TABLE_REACTION") and not self.Reacting then
		self.Title.Text, self.Paragraph.Text, self.Title.TextColor3 = "", "", white
	end
	self:PaintStates(s, now)
	if self.Reacting then
		self:PaintReaction(s, now)
	end
	if view and s.State == "ROUND_REVEAL" and s.Reveal then
		local ordered = Reveal.Order(s.Reveal.Results, s.YourUserId)
		local current = view.Sequence.Index
		local entry = if current then ordered[current] else nil
		local ownUserId = self.LocalUserId or s.YourUserId
		self:PaintPraise(view, if entry and entry.UserId == ownUserId then entry else nil, s)
		if self.RevealBound then
			self:PaintReveal(view, s)
		end
	else
		self.PraiseRoot.Visible = false
	end
	if self.EndUI then
		self:PaintEnd(s, now or self.LastPaintNow)
	end
	return view
end
-- The screen also pulses red as your own turn runs out.
function States.Tick(self: any, s: any, now: number)
	local result = Base.Tick(self, s, now)
	if not s or self.StatusOnly or not Style.IsEnabled(self.Gui) or (s.State == "IDLE" and s.Completion) then
		return result
	end
	-- This layout owns the flash (OwnsTable): your own lost heart flashes with your reaction verdict.
	self.Flash.BackgroundTransparency = if self.Reacting then self:ReactionFlash() else 1
	if s.State == "GUESSING" and s.CanGuess and s.Deadline then
		local left = s.Deadline - now
		if left >= 0 and left <= LOW_SECONDS then
			-- One slow, smooth breath every two seconds, fading in over the first second and growing a little stronger.
			local urgency = 1 - left / LOW_SECONDS
			local ramp = math.clamp((LOW_SECONDS - left) / 1, 0, 1)
			local breath = (1 - math.cos(now * math.pi)) * 0.5
			self.Flash.BackgroundTransparency = 1 - (0.16 + 0.14 * urgency) * ramp * breath
		end
	end
	return result
end
function States.Destroy(self: any)
	self:Hide(true)
	for _, connection in self.PolishConnections or {} do
		connection:Disconnect()
	end
	if self.HintWobble then
		self.HintWobble:Destroy()
	end
	if self.PraiseRoot then
		self.PraiseRoot:Destroy()
	end
end
return States

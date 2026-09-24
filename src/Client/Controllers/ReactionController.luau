--!strict
-- The reaction cutscene's world/screen effects for whoever ReactionCycle is showing: a coloured Highlight on their
-- avatar (pulsing red for a lost heart, deep red for an elimination, green when safe or healed) and a matching screen
-- icon (a heart that pops in and goes dark when the heart is lost, a shield when safe). Everything follows
-- ReactionCycle.Beats (carried on each entry): it appears at Verdict with the header's subtitle, the heart icon darkens at Heart together
-- with the Left panel's heart, and it all fades out at PanelOut before the next player's slot. Purely visual; hearts
-- already settled on the server.
local ReactionController = {}
ReactionController.__index = ReactionController

local SAFE_ICON = "rbxassetid://116722997037295"
local HEART_ICON = "rbxassetid://136166313004613"
local GROW_SECONDS = 0.45
local RISE_SCALE = 0.16 -- how far up the icon drifts, as a fraction of screen height
local BASE_SCALE = 0.16
local ELIMINATED_EXTRA_SCALE = 0.5 -- an eliminated player's icon swells this much larger, easing back down
local ELIMINATED_SETTLE_SECONDS = 0.7
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local DEEP_RED = Color3.fromRGB(180, 0, 10)

function ReactionController.new(world: Workspace, players: Players, config: any, playerGui: PlayerGui?)
	return setmetatable({ World = world, Players = players, Config = config, PlayerGui = playerGui }, ReactionController)
end

local function ensureIcon(self: any): ImageLabel
	if self.Icon then
		return self.Icon
	end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled =
		"ScaleReactionEffect", false, true, 40, true
	local label = Instance.new("ImageLabel")
	label.Name, label.BackgroundTransparency, label.BorderSizePixel, label.Active, label.Selectable =
		"ReactionIcon", 1, 0, false, false
	label.AnchorPoint, label.Position, label.Size, label.ScaleType =
		Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(), Enum.ScaleType.Fit
	label.Parent = gui
	if self.PlayerGui then
		gui.Parent = self.PlayerGui
	end
	self.Gui, self.Icon = gui, label
	return label
end

function ReactionController.Clear(self: any)
	if self.Highlight then
		self.Highlight:Destroy()
		self.Highlight = nil
	end
	if self.Gui then
		self.Gui:Destroy()
		self.Gui, self.Icon = nil, nil
	end
	self.Key = nil
end

-- entry: the current ReactionCycle result (nil while not reacting). character: that player's avatar (a bot's NPC
-- too); when omitted it is looked up from Players.
function ReactionController.Step(self: any, entry: any?, character: Model?)
	if not entry then
		self:Clear()
		return
	end
	if not character then
		local player = self.Players:GetPlayerByUserId(entry.UserId)
		character = player and player.Character
	end
	if character and (not character:IsDescendantOf(self.World) or character:FindFirstAncestorWhichIsA("WorldModel")) then
		character = nil
	end
	local key = tostring(entry.UserId) .. "@" .. tostring(entry.Index)
	if key ~= self.Key then
		self:Clear()
		self.Key = key
		local label = ensureIcon(self)
		label.Image = if entry.Delta ~= 0 then HEART_ICON else SAFE_ICON
		label.Size = UDim2.new()
	end
	-- A live rig may replicate after this reaction slot starts. Rebind the visual without restarting its timeline.
	if self.Highlight and self.Highlight.Adornee ~= character then
		self.Highlight:Destroy()
		self.Highlight = nil
	end
	if character and not self.Highlight then
		local highlight = Instance.new("Highlight")
		highlight.Name, highlight.Adornee = "ScaleReactionFlash", character
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency, highlight.OutlineTransparency = 1, 1
		highlight.Parent = character
		self.Highlight = highlight
	end
	local beats = entry.Beats
	local age = entry.SlotAge
	local lost, healed = entry.Delta < 0, entry.Delta > 0
	-- 0 before the verdict, 1 once it has landed, back to 0 as the slot hands over to the next player.
	local since = math.max(0, age - beats.Verdict)
	local grow = if age < beats.Verdict then 0 else 1 - (1 - math.clamp(since / GROW_SECONDS, 0, 1)) ^ 3
	local out = 1 - math.clamp((age - beats.PanelOut) / beats.FadeSeconds, 0, 1)
	local shown = grow * out
	-- The heart changes with the Left panel's heart, over the same beat.
	local change = math.clamp((age - beats.Heart) / beats.HeartSeconds, 0, 1)
	local label = self.Icon
	if label then
		local scale = BASE_SCALE * grow
		if entry.Eliminated then
			local settle = math.clamp((since - GROW_SECONDS) / ELIMINATED_SETTLE_SECONDS, 0, 1)
			scale *= 1 + ELIMINATED_EXTRA_SCALE * (1 - settle) ^ 2
		end
		label.Size = UDim2.fromScale(scale, scale)
		label.Position = UDim2.fromScale(0.5, 0.5 - RISE_SCALE * grow)
		local tint, fade = WHITE, 0
		if lost then
			tint, fade = WHITE:Lerp(if entry.Eliminated then DEEP_RED else BLACK, change), 0.5 * change
		elseif healed then
			tint, fade = BLACK:Lerp(WHITE, change), 0.5 * (1 - change)
		end
		label.ImageColor3 = tint
		label.ImageTransparency = 1 - (1 - fade) * shown
	end
	local highlight = self.Highlight
	if highlight then
		local fill, outline
		if entry.Eliminated then
			highlight.FillColor, highlight.OutlineColor = DEEP_RED, Color3.fromRGB(255, 40, 40)
			fill, outline = 0.5, 0
		elseif lost then
			-- A lost heart pulses red on the avatar.
			highlight.FillColor, highlight.OutlineColor = Color3.fromRGB(255, 55, 65), Color3.fromRGB(255, 100, 105)
			fill, outline = 0.45 + 0.2 * math.sin(since * 7), 0
		else
			highlight.FillColor, highlight.OutlineColor = Color3.fromRGB(60, 255, 110), Color3.fromRGB(140, 255, 160)
			fill, outline = 0.8, 0.15
		end
		highlight.FillTransparency = 1 - (1 - fill) * shown
		highlight.OutlineTransparency = 1 - (1 - outline) * shown
	end
end

return ReactionController

--!strict
-- Alerts are cloned from the authored HUD.Alerts.Template (a Frame with a Sub TextLabel and its OuterUIStroke); nothing
-- is built in code. Each alert is made visible, given its message, coloured with a text colour or a UIGradient, and
-- faded in (background to 0.95 transparency, text and stroke to their authored look), held, then faded out and removed.
-- HUD.Alerts' own UIListLayout stacks them. Anything can raise one with Style.Alert(message, kind[, options]).
--   kinds: Info (white), Good (green), Bad (red), Help (green-cyan gradient), Sabotage (red-purple gradient),
--          Notice (gold gradient). options: Color (Color3), Gradient (ColorSequence), Seconds (how long it holds).
local AlertController = {}
AlertController.__index = AlertController

local FADE_IN, FADE_OUT = 0.25, 0.45
local BACKGROUND = 0.95 -- the alert's resting BackgroundTransparency
local MAX_VISIBLE = 5
local GREEN_WHITE_GREEN=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(74,255,116)),ColorSequenceKeypoint.new(0.5,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,Color3.fromRGB(74,255,116))})

local KINDS: {[string]: any} = {
	Info = { Color = Color3.new(1, 1, 1) },
	Good = { Gradient = GREEN_WHITE_GREEN },
	Bad = { Color = Color3.fromRGB(255, 95, 95) },
	Help = { Gradient = ColorSequence.new(Color3.fromRGB(120, 255, 140), Color3.fromRGB(90, 230, 255)) },
	Sabotage = { Gradient = ColorSequence.new(Color3.fromRGB(255, 90, 90), Color3.fromRGB(190, 90, 255)) },
	Notice = { Gradient = ColorSequence.new(Color3.fromRGB(255, 240, 130), Color3.fromRGB(255, 170, 60)) },
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function AlertController.new(hud: any, runService: any?, clock: (() -> number)?)
	local container = hud and hud:FindFirstChild("Alerts")
	local template = container and container:FindFirstChild("Template")
	local sub = template and template:FindFirstChild("Sub")
	local self: any = setmetatable({ Container = container, Template = template, Alerts = {}, Connections = {}, Clock = clock or os.clock }, AlertController)
	if not (template and sub and sub:IsA("TextLabel")) then
		warn("Missing authored UI: HUD.Alerts.Template.Sub (TextLabel); alerts will not show")
		self.Disabled = true
		return self
	end
	template.Visible = false
	-- What the template looks like when an alert is fully shown.
	local stroke = sub:FindFirstChildWhichIsA("UIStroke")
	self.TextTarget = sub.TextTransparency
	self.StrokeTarget = if stroke then stroke.Transparency else nil
	if runService then table.insert(self.Connections, runService.RenderStepped:Connect(function(dt: number) self:Step(dt) end)) end
	return self
end

-- Shows a message. The same message already on screen is kept alive instead of stacking a copy.
function AlertController.Show(self: any, message: string, kind: string?, options: any?)
	if self.Disabled or type(message) ~= "string" or message == "" then return end
	local seconds = (options and options.Seconds) or math.clamp(2.5 + #message * 0.035, 2.5, 8)
	for _, alert in self.Alerts do
		if alert.Message == message and alert.Age < alert.HoldUntil then
			alert.Age = math.min(alert.Age, FADE_IN)
			alert.HoldUntil = alert.Age + seconds
			return
		end
	end
	local node = self.Template:Clone()
	node.Name, node.Visible = "Alert", true
	local sub = node:FindFirstChild("Sub") :: TextLabel
	sub.Text = message
	local fontOk=pcall(function() sub.FontFace=Font.fromName("Montserrat",Enum.FontWeight.Heavy) end)
	if not fontOk then sub.Font=Enum.Font.GothamBlack end
	local look = KINDS[kind or "Info"] or KINDS.Info
	local color = (options and options.Color) or look.Color
	local gradient = (options and options.Gradient) or look.Gradient
	for _, existing in sub:GetChildren() do
		if existing:IsA("UIGradient") and existing.Name == "AlertGradient" then existing:Destroy() end
	end
	if gradient then
		-- A gradient multiplies the text colour, so the text is white underneath it.
		sub.TextColor3 = Color3.new(1, 1, 1)
		local ui = Instance.new("UIGradient")
		ui.Name, ui.Color, ui.Parent = "AlertGradient", gradient, sub
		ui.Rotation = if (kind or "Info") == "Good" then 90 else 0
	elseif color then
		sub.TextColor3 = color
	end
	for _,existing in sub:GetChildren() do
		if existing:IsA("UIGradient") then existing.Enabled=existing.Name=="AlertGradient" end
	end
	local stroke = sub:FindFirstChildWhichIsA("UIStroke")
	if stroke then stroke.Color=Color3.new() end
	local alert = { Node = node, Sub = sub, Stroke = stroke, Message = message, Age = 0, HoldUntil = FADE_IN + seconds, Leaving = false }
	-- Everything starts invisible and fades in.
	node.BackgroundTransparency, sub.TextTransparency = 1, 1
	if stroke then stroke.Transparency = 1 end
	node.Parent = self.Container
	table.insert(self.Alerts, alert)
	-- Only the newest few stay; the oldest start leaving early.
	local live = 0
	for _, other in self.Alerts do if not other.Leaving then live += 1 end end
	for _, other in self.Alerts do
		if live <= MAX_VISIBLE then break end
		if not other.Leaving then other.Leaving, other.Age, live = true, other.HoldUntil, live - 1 end
	end
end

function AlertController.Step(self: any, dt: number)
	for index = #self.Alerts, 1, -1 do
		local alert = self.Alerts[index]
		alert.Age += dt
		local shown: number
		if alert.Age < alert.HoldUntil then shown = smooth(alert.Age / FADE_IN)
		else shown = 1 - smooth((alert.Age - alert.HoldUntil) / FADE_OUT) end
		if not alert.Node.Parent or alert.Age >= alert.HoldUntil + FADE_OUT then
			alert.Node:Destroy()
			table.remove(self.Alerts, index)
		else
			alert.Node.BackgroundTransparency = 1 - (1 - BACKGROUND) * shown
			alert.Sub.TextTransparency = 1 - (1 - self.TextTarget) * shown
			if alert.Stroke and self.StrokeTarget then alert.Stroke.Transparency = 1 - (1 - self.StrokeTarget) * shown end
		end
	end
end

function AlertController.Clear(self: any)
	for _, alert in self.Alerts do alert.Node:Destroy() end
	table.clear(self.Alerts)
end

function AlertController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	self:Clear()
	if self.Template then self.Template.Visible = false end
end

return AlertController

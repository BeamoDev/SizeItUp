--!strict
-- Slowly cycles a rainbow through the text of authored world labels (the Lucky Blocks sign). Each target gets a
-- UIGradient named ColorCycle whose colours drift around the colour wheel; the label's text is set to white so the
-- gradient shows true colours. Purely cosmetic and local; it only touches that gradient (and the text colour).
local LabelGradientController = {}
LabelGradientController.__index = LabelGradientController

-- Workspace path of each label to animate.
LabelGradientController.Targets = {
	{ "Map", "Deco", "Model", "Title", "SurfaceGui", "Container", "Label" },
}
local CYCLE_SECONDS = 24 -- one full trip around the colour wheel
local SPREAD = 0.55 -- how much of the wheel is visible across the text at once
local STOPS = 6
local UPDATES_PER_SECOND = 20
local SEARCH_SECONDS = 1

local function resolve(world: any, path: {string}): Instance?
	local node: any = world
	for _, name in path do
		node = node and node:FindFirstChild(name)
		if not node then return nil end
	end
	return if node and node:IsA("TextLabel") then node else nil
end

function LabelGradientController.Colors(phase: number): ColorSequence
	local keypoints = {}
	for index = 0, STOPS - 1 do
		local alpha = index / (STOPS - 1)
		keypoints[index + 1] = ColorSequenceKeypoint.new(alpha, Color3.fromHSV((phase + alpha * SPREAD) % 1, 0.85, 1))
	end
	return ColorSequence.new(keypoints)
end

function LabelGradientController.new(world: any, runService: any, clock: (() -> number)?)
	local self: any = setmetatable({ World = world, Clock = clock or os.clock, Bound = {}, SearchAt = 0, UpdateAt = 0, Connections = {} }, LabelGradientController)
	table.insert(self.Connections, runService.RenderStepped:Connect(function() self:Step() end))
	self:Step()
	return self
end

function LabelGradientController.Bind(self: any, label: TextLabel)
	local gradient = label:FindFirstChild("ColorCycle") :: UIGradient?
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "ColorCycle"
		gradient.Parent = label
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	self.Bound[label] = gradient
end

function LabelGradientController.Step(self: any)
	local now = self.Clock()
	-- Streamed-in or late labels are found by a slow search rather than on every frame.
	if now >= self.SearchAt then
		self.SearchAt = now + SEARCH_SECONDS
		for _, path in LabelGradientController.Targets do
			local label = resolve(self.World, path)
			if label and not self.Bound[label] then self:Bind(label :: TextLabel) end
		end
	end
	if now < self.UpdateAt then return end
	self.UpdateAt = now + 1 / UPDATES_PER_SECOND
	local phase = (now / CYCLE_SECONDS) % 1
	for label, gradient in self.Bound do
		if label.Parent and gradient.Parent == label then gradient.Color = LabelGradientController.Colors(phase) else self.Bound[label] = nil end
	end
end

function LabelGradientController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	table.clear(self.Connections)
	for label, gradient in self.Bound do
		if gradient.Parent == label then gradient:Destroy() end
	end
	table.clear(self.Bound)
end

return LabelGradientController

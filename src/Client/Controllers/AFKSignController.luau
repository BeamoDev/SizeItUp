--!strict
-- The AFK portal's sign (Workspace.Game.Triggers.AFK.Part.Billboard1): its ImageLabels rock between 16 and -16 degrees, each on
-- its own (faster, eye-catching) speed and starting point, so they swing at different times. Driven by the shared
-- server clock, so every player sees the same sway. Purely visual: it only sets Rotation on those labels and puts them
-- back on teardown.
local AFKSignController = {}
AFKSignController.__index = AFKSignController

local DEGREES = 16
-- Each label has its own speed (radians per second) and starting phase; extra labels reuse the pattern.
local SPEEDS, PHASES = { 1, 1.45, 1.9, 1.25 }, { 0, 2.1, 4.3, 5.4 }
local SEARCH_SECONDS = 2

function AFKSignController.new(world: any, runService: any, clock: (() -> number)?)
	local self: any = setmetatable({ World = world, Clock = clock or function() return world:GetServerTimeNow() end, Labels = {}, Rest = {}, Timer = 0 }, AFKSignController)
	self.Connection = runService.RenderStepped:Connect(function(dt: number) self:Step(dt) end)
	return self
end

-- Looks for the sign's billboard (it may stream in later) and collects its ImageLabels in name order.
function AFKSignController.Find(self: any)
	local game = self.World:FindFirstChild("Game")
	local triggers = game and game:FindFirstChild("Triggers")
	local afk = (triggers and triggers:FindFirstChild("AFK")) or (game and game:FindFirstChild("AFK"))
	local part = afk and afk:FindFirstChild("Part")
	local board = part and part:FindFirstChild("Billboard1")
	if not board then return end
	local found = {}
	for _, child in board:GetChildren() do
		if child:IsA("ImageLabel") then table.insert(found, child) end
	end
	table.sort(found, function(a, b) return a.Name < b.Name end)
	for _, label in found do self.Rest[label] = label.Rotation end
	self.Labels = found
end

function AFKSignController.Step(self: any, dt: number)
	if #self.Labels == 0 then
		self.Timer -= dt
		if self.Timer <= 0 then self.Timer = SEARCH_SECONDS;self:Find() end
		return
	end
	local time = self.Clock()
	for index, label in self.Labels do
		local slot = (index - 1) % #SPEEDS + 1
		if label.Parent then label.Rotation = DEGREES * math.sin(time * SPEEDS[slot] + PHASES[slot]) end
	end
end

function AFKSignController.Destroy(self: any)
	self.Connection:Disconnect()
	for label, rest in self.Rest do
		if label.Parent then label.Rotation = rest end
	end
	self.Labels, self.Rest = {}, {}
end

return AFKSignController

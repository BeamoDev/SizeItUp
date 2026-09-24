--!strict
-- Eases every title's UIGradient back and forth so names shimmer. The server only
-- marks gradients (Shimmer speed, ShimmerPhase); all motion is local and cosmetic.
local TitleGradientController = {}
TitleGradientController.__index = TitleGradientController

function TitleGradientController.new(world: any, runService: any, clock: (() -> number)?)
	local self: any = setmetatable({ Tracked = {}, Connections = {}, Clock = clock or os.clock }, TitleGradientController)
	local function track(instance: any)
		if instance:IsA("UIGradient") and type(instance:GetAttribute("Shimmer")) == "number" then self.Tracked[instance] = true end
	end
	local function attach(root: any)
		self.Attached = true
		for _, descendant in root:GetDescendants() do track(descendant) end
		table.insert(self.Connections, root.DescendantAdded:Connect(track))
		table.insert(self.Connections, root.DescendantRemoving:Connect(function(descendant: any) self.Tracked[descendant] = nil end))
	end
	local runtime = world:FindFirstChild("Runtime")
	local other = runtime and runtime:FindFirstChild("Other")
	local root = if other then other:FindFirstChild("ScaleCosmeticDisplays") else nil
	if root then attach(root)
	else
		table.insert(self.Connections, world.DescendantAdded:Connect(function(child: any)
			if child.Name == "ScaleCosmeticDisplays"
				and child.Parent and child.Parent.Name == "Other"
				and child.Parent.Parent and child.Parent.Parent.Name == "Runtime"
				and child.Parent.Parent.Parent == world
				and not self.Attached then
				attach(child)
			end
		end))
	end
	table.insert(self.Connections, runService.RenderStepped:Connect(function() self:Step() end))
	return self
end

function TitleGradientController.Step(self: any)
	local now = self.Clock()
	for gradient in self.Tracked do
		if not gradient.Parent then self.Tracked[gradient] = nil;continue end
		local speed, phase = gradient:GetAttribute("Shimmer"), gradient:GetAttribute("ShimmerPhase") or 0
		-- Sine ping-pong: the light band glides across and eases to a stop at each end.
		gradient.Offset = Vector2.new(math.sin(now * speed + phase), 0)
		if gradient:GetAttribute("GoldPulse") == true and gradient.Parent:IsA("TextLabel") then
			local pulse = (math.sin(now * 2.4 + phase) + 1) * 0.5
			local brightness = 0.82 + 0.18 * pulse
			gradient.Parent.TextColor3 = Color3.new(brightness, brightness, brightness)
			gradient.Parent.TextStrokeTransparency = 0.35 + 0.4 * (1 - pulse)
		end
	end
end

function TitleGradientController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	for gradient in self.Tracked do
		if gradient.Parent and gradient:GetAttribute("GoldPulse") == true and gradient.Parent:IsA("TextLabel") then
			gradient.Parent.TextColor3 = Color3.new(1,1,1)
			gradient.Parent.TextStrokeTransparency = 0.55
			gradient.Offset = Vector2.zero
		end
	end
	table.clear(self.Connections);table.clear(self.Tracked)
end

return TitleGradientController

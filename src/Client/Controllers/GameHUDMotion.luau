--!strict
-- One render-driven motion per authored panel. Reversals retain their velocity.
local Style=require(script.Parent.UIStyle)
local Motion={}
Motion.__index=Motion
local JITTER_OMEGA = 1/0.35 -- a slow, sluggish drift toward the target -- the lag "feel" -- not a snap
-- Panels, controls and ruler overlays all use this same curve after their reversible spring has advanced.
local function ease(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end
function Motion.new()
	return setmetatable({Items={},JitterTarget=UDim2.new(),JitterValue=UDim2.new()},Motion)
end
-- Sets where every tracked panel should drift to (offset, in scale, from its authored resting pose) while lagging;
-- nil/zero drifts it back to its normal position. Motion.Step eases toward this target slowly rather than
-- snapping, so a burst reads as the UI going sluggish and stepping slightly, not teleporting around the screen.
function Motion.SetJitter(self: any,offset: UDim2?)
	-- Lag should affect input timing, not the HUD layout itself. Keep the UI anchored to its authored pose.
	self.JitterTarget=UDim2.new()
end
function Motion.Add(self: any,node: GuiObject,direction: string?)
	if self.Items[node] then return end
	local pose=Style.Authoring.Pose(node)
	local scale=node:FindFirstChild("GameMotionScale")
	if not scale then scale=Instance.new("UIScale");scale.Name="GameMotionScale";scale.Parent=node end
	local position=pose.Position
	local off
	if direction=="Down" then off=UDim2.new(position.X.Scale,position.X.Offset,2,pose.Size.Y.Offset)
	elseif direction=="Up" then off=UDim2.new(position.X.Scale,position.X.Offset,-1,-pose.Size.Y.Offset)
	elseif direction=="Left" then off=UDim2.new(-1,-pose.Size.X.Offset,position.Y.Scale,position.Y.Offset)
	elseif direction=="Right" then off=UDim2.new(2,pose.Size.X.Offset,position.Y.Scale,position.Y.Offset)
	elseif position.X.Scale<0.22 then off=UDim2.new(-1,-pose.Size.X.Offset,position.Y.Scale,position.Y.Offset)
	elseif position.X.Scale>0.7 then off=UDim2.new(2,pose.Size.X.Offset,position.Y.Scale,position.Y.Offset)
	elseif position.Y.Scale<0.35 then off=UDim2.new(position.X.Scale,position.X.Offset,-1,-pose.Size.Y.Offset)
	else off=UDim2.new(position.X.Scale,position.X.Offset,2,pose.Size.Y.Offset) end
	-- Copied running UI retains its resting pose, not the interrupted animation.
	node:SetAttribute("RestPositionScale",Vector2.new(position.X.Scale,position.Y.Scale))
	node:SetAttribute("RestPositionOffset",Vector2.new(position.X.Offset,position.Y.Offset))
	node:SetAttribute("GameHUDMotion",true)
	self.Items[node]={Node=node,Position=position,Off=off,Scale=scale,Value=0,Velocity=0,Target=false}
	node.Position,node.Visible,scale.Scale=position,false,1
end
function Motion.AddOverlay(self: any,node: GuiObject)
	local fades={}
	local scale=node:FindFirstChild("GameMotionScale")
	if not scale then scale=Instance.new("UIScale");scale.Name="GameMotionScale";scale.Parent=node end
	for _,child in node:GetDescendants() do
		if child:IsA("GuiObject") then table.insert(fades,{Node=child,Property="BackgroundTransparency",Base=child.BackgroundTransparency}) end
		if child:IsA("TextLabel") then
			table.insert(fades,{Node=child,Property="TextTransparency",Base=child.TextTransparency})
			table.insert(fades,{Node=child,Property="TextStrokeTransparency",Base=child.TextStrokeTransparency})
		end
		-- Ruler dots and caps use UIStroke for their black border. Fade it with the white marker so an outline does
		-- not linger for a frame after the marker fill has disappeared.
		if child:IsA("UIStroke") then table.insert(fades,{Node=child,Property="Transparency",Base=child.Transparency}) end
	end
	self.Items[node]={Node=node,Fades=fades,Scale=scale,Value=0,Velocity=0,Target=false}
	node:SetAttribute("GameHUDMotion",true)
end
function Motion.ApplyOverlay(self: any,node: GuiObject)
	local item=self.Items[node]
	node.Visible=item.Target or item.Value>0
	local value=ease(item.Value)
	for _,fade in item.Fades do fade.Node[fade.Property]=1-(1-fade.Base)*value end
	item.Scale.Scale=0.94+0.06*value
end
function Motion.Set(self: any,node: GuiObject,on: boolean)
	local item=self.Items[node]
	if not item or item.Target==on then return end
	item.Target=on
	if on then
		node.Visible=true
		if item.Value==0 and not item.Fades then node.Position=item.Off;item.Scale.Scale=0.72 end
	end
end
function Motion.Step(self: any,dt: number): boolean
	local visible=false
	self.JitterValue=self.JitterValue:Lerp(self.JitterTarget,1-math.exp(-JITTER_OMEGA*math.max(0,dt)))
	for _,item in self.Items do
		if not item.Node.Parent then continue end
		local goal=if item.Target then 1 else 0
		local omega=8/(if item.Target then Style.Pacing.GameEnterSeconds else Style.Pacing.GameExitSeconds)
		local error=item.Value-goal
		local temp=(item.Velocity+omega*error)*math.max(0,dt)
		local decay=math.exp(-omega*math.max(0,dt))
		item.Value=math.clamp(goal+(error+temp)*decay,0,1)
		item.Velocity=(item.Velocity-omega*temp)*decay
		if math.abs(item.Value-goal)<0.001 and math.abs(item.Velocity)<0.01 then item.Value=goal;item.Velocity=0 end
		item.Node.Visible=item.Target or item.Value>0
		visible=visible or item.Node.Visible
		if item.Fades then self:ApplyOverlay(item.Node);continue end
		local value=ease(item.Value)
		local settled=if item.Node.Visible then item.Off:Lerp(item.Position,value) else item.Position
		item.Node.Position=settled
		item.Scale.Scale=if item.Node.Visible then 0.72+0.28*value else 1
	end
	return visible
end
function Motion.Reset(self: any)
	for _,item in self.Items do
		item.Value,item.Velocity,item.Target=0,0,false
		item.Node.Visible=false
		if item.Fades then
			for _,fade in item.Fades do fade.Node[fade.Property]=fade.Base end
			item.Scale.Scale=1
		else item.Node.Position=item.Position;item.Scale.Scale=1 end
	end
end
return Motion

--!strict
local ScaleController = {}
ScaleController.__index = ScaleController
-- True while the player types in a real TextBox. The slider's own Track/Knob may be TextBoxes (they take focus when
-- clicked), and that must never block or cancel a drag.
function ScaleController.Typing(self: any): boolean
	local box = self.Input:GetFocusedTextBox()
	if not box then return false end
	local track = self.Track
	if not track then return true end
	if box == track then return false end
	local ok, inside = pcall(function() return (box :: any):IsDescendantOf(track) end)
	return not (ok and inside)
end
function ScaleController.new(inputService: UserInputService, guiService: GuiService, track: GuiObject?, config: any, mathUtil: any, changed: (number, number) -> ())
	local self: any = setmetatable({ Input = inputService, GuiService = guiService, Track = track, Config = config, Math = mathUtil, Changed = changed, Enabled = false, Drag = nil, Connections = {}, Value = 1,
		Minimum = config.MinimumGuessMeters, Maximum = config.MaximumGuessMeters }, ScaleController)
	local function at(position: Vector3)
		-- Relative motion prevents a click/touch from jumping to a track position.
		if track and math.abs(track.AbsoluteSize.Y*(self.TrackFraction or 1)-self.DragHeight)>0.5 then self:Cancel();return end
		local delta = self.DragY - position.Y
		if math.abs(delta) < 2 and not self.DragMoved then return end
		if delta==0 then return end
		self.DragMoved = true
		local direction=math.sign(delta)
		if self.DragDirection and direction~=self.DragDirection then
			self.TargetValue,self.Velocity=self.Value,0
		end
		-- Rebase each sample at the clamped destination. There is no invisible
		-- overshoot to drag back through at either end of the slider.
		local alpha = mathUtil.ToAlpha(self.TargetValue or self.Value,self.Minimum,self.Maximum)+delta/self.DragHeight
		self.DragY,self.DragDirection=position.Y,direction
		self:Aim(mathUtil.FromAlpha(alpha, self.Minimum, self.Maximum))
	end
	if track then
		table.insert(self.Connections, track.InputBegan:Connect(function(input)
			self:BeginDrag(input)
		end))
	end
	table.insert(self.Connections, inputService.InputChanged:Connect(function(input)
		if not self.Enabled or not self.Drag then return end
		if self:Typing() then self:Cancel(); return end
		if input == self.Drag or (self.Drag.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then at(input.Position) end
	end))
	table.insert(self.Connections, inputService.InputEnded:Connect(function(input)
		if self.Drag == input or (self.Drag and self.Drag.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then self:Cancel() end
	end))
	table.insert(self.Connections, inputService.WindowFocusReleased:Connect(function() self:Cancel() end))
	table.insert(self.Connections, guiService.MenuOpened:Connect(function() self:Cancel() end))
	return self
end
-- Slider and model presses share capture, sensitivity, smoothing and teardown.
-- Capture persists outside the hit area until this same pointer is released.
function ScaleController.BeginDrag(self: any,input: InputObject): boolean
	if not self.Enabled or self.Drag or self.GuiService.MenuIsOpen or self:Typing() then return false end
	if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return false end
	self:Cancel()
	self.Drag=input
	-- TrackFraction is the part of the track the knob travels (0.1 to 0.9 of it is 0.8).
	local camera = workspace.CurrentCamera
	local fallbackHeight = if camera then camera.ViewportSize.Y * 0.8 else 600
	self.DragY,self.DragHeight=input.Position.Y,math.max(1,if self.Track then self.Track.AbsoluteSize.Y*(self.TrackFraction or 1) else fallbackHeight)
	return true
end
function ScaleController.Nudge(self: any, direction: number)
	if not self.Enabled or self:Typing() or not self.Math.IsFinite(direction) or direction==0 then return end
	self:Cancel()
	-- One explicit button click requests one small step, with no queued backlog.
	self.TargetValue=math.clamp(self.Value * 1.1 ^ math.sign(direction),self.Minimum,self.Maximum)
	self.ButtonPending=true
end
function ScaleController.Aim(self: any,meters: number)
	if not self.Enabled or not self.Drag or not self.Math.IsFinite(meters) then return end
	self.TargetValue=math.clamp(meters,self.Minimum,self.Maximum)
end
function ScaleController.ResetGuess(self: any,meters: number)
	if not self.Enabled or self.GuiService.MenuIsOpen or self:Typing() or not self.Math.IsFinite(meters) then return end
	self:Cancel()
	self.TargetValue=math.clamp(meters,self.Minimum,self.Maximum)
	self.ButtonPending=true
end
function ScaleController.Cancel(self: any)
	self.Drag,self.TargetValue=nil,self.Value
	self.DragMoved,self.ButtonPending=nil,nil
	self.Velocity,self.DragDirection,self.DragHeight=0,nil,nil
end
function ScaleController.Step(self: any,dt: number)
	if not self.Enabled or (not self.Drag and not self.ButtonPending) then return end
	if self:Typing() then self:Cancel();return end
	local value,velocity=self.Math.SmoothApproach(self.Value,self.TargetValue or self.Value,self.Velocity,dt,self.Config)
	self.Velocity=velocity
	if value~=self.Value then
		-- Reaching the smallest or largest allowed size (not merely sitting there) calls OnLimit once.
		local atLimit=value<=self.Minimum or value>=self.Maximum
		local wasAtLimit=self.Value<=self.Minimum or self.Value>=self.Maximum
		if atLimit and not wasAtLimit and self.OnLimit then
			self.OnLimit(if value <= self.Minimum then "Minimum" else "Maximum")
		end
		self.Value,self.Initialized=value,true
		self.Changed(value,self.Math.ToAlpha(value,self.Minimum,self.Maximum))
	end
	if self.Value==self.TargetValue then self.ButtonPending=nil end
end
function ScaleController.SetRange(self: any,minimum: number,maximum: number)
	assert(self.Math.IsFinite(minimum) and self.Math.IsFinite(maximum) and minimum>0 and maximum>minimum,"Invalid slider range")
	self.Minimum,self.Maximum=minimum,maximum
	self:Cancel()
end
function ScaleController.Set(self: any, meters: number, force: boolean?)
	if type(meters)~="number" or meters~=meters or math.abs(meters)==math.huge then return end
	self:Cancel()
	local value=math.clamp(meters, self.Minimum, self.Maximum)
	self.TargetValue=value
	if self.Initialized and value==self.Value and not force then return end
	self.Value,self.Initialized = value,true
	self.Changed(self.Value, self.Math.ToAlpha(self.Value, self.Minimum, self.Maximum))
end
function ScaleController.Enable(self: any, enabled: boolean)
	self.Enabled = enabled
	if not enabled then self:Cancel() end
end
function ScaleController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	self.Connections = {}
	self:Enable(false)
end
return ScaleController

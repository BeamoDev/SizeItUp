--!strict
-- Opaque black wipe: left -> center (swap) -> right, with staggered UI motion.
-- Render-driven ownership avoids delayed callbacks reopening an obsolete round.
local Style = require(script.Parent.UIStyle)
local Transition = {}
Transition.__index = Transition
local function sine(t: number): number return (1-math.cos(math.pi*t))*0.5 end
local function back(t: number): number local x=t-1;return 1+2.70158*x*x*x+1.70158*x*x end
function Transition.new(playerGui: PlayerGui, config: any, roots: () -> {ScreenGui})
	if Style.Authoring then
		local cover=Style.Authoring.Need(Style.Authoring.HUD,"BlackWipe","GuiObject")
		Style.SetEnabled(cover,false)
		return setmetatable({Gui=cover,Cover=cover,Config=config,Roots=roots,Motion={},Elapsed=0},Transition)
	end
	local gui=Style.Node(playerGui,"ScaleSceneTransition","ScreenGui");gui.Name="ScaleSceneTransition";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=1000;Style.SetEnabled(gui,false);gui.Parent=playerGui
	local cover=Style.Node(gui,"BlackWipe","Frame");cover.Name="BlackWipe";cover.Size=UDim2.fromScale(1,1);cover.Position=UDim2.fromScale(-1,0);cover.BackgroundColor3=Color3.new(0,0,0);cover.BackgroundTransparency=0;cover.BorderSizePixel=0;cover.Active=true;cover.Parent=gui
	return setmetatable({Gui=gui,Cover=cover,Config=config,Roots=roots,Motion={},Elapsed=0},Transition)
end
function Transition.Restore(self: any)
	for _,item in self.Motion do
		if item.Node.Parent then item.Node.Position=item.Position;if item.Scale then item.Scale.Scale=item.BaseScale end;Style.RestorePose(item.Node) end
		if item.Created then item.Scale:Destroy() end
	end
	table.clear(self.Motion)
end
function Transition.Capture(self: any, incoming: boolean)
	for _,root in self.Roots() do
		if not Style.IsEnabled(root) then continue end
		for _,node in root:GetChildren() do
			if not node:IsA("GuiObject") or not node.Visible or node.Name=="DamageFlash" or node:GetAttribute("GameHUDMotion") then continue end
			local position=node.Position
			Style.SavePose(node)
			local off
			if position.X.Scale<0.22 then off=UDim2.new(-1,-node.Size.X.Offset,position.Y.Scale,position.Y.Offset)
			elseif position.X.Scale>0.7 then off=UDim2.new(1.15,0,position.Y.Scale,position.Y.Offset)
			elseif position.Y.Scale<0.35 then off=UDim2.new(position.X.Scale,position.X.Offset,-1,-node.Size.Y.Offset)
			else off=UDim2.new(position.X.Scale,position.X.Offset,1.2,0) end
			local scale=node:FindFirstChildOfClass("UIScale");local created=scale==nil
			if not scale and not Style.Authoring then scale=Instance.new("UIScale");scale.Name="SceneMotionScale";scale.Parent=node end
			local item={Node=node,Position=position,Off=off,Scale=scale,BaseScale=if scale then scale.Scale else 1,Created=created and scale~=nil,Delay=(#self.Motion%5)*0.01}
			table.insert(self.Motion,item)
			if incoming then node.Position=off;if scale then scale.Scale=item.BaseScale*0.75 end end
		end
	end
end
function Transition.Animate(self: any, incoming: boolean)
	for _,item in self.Motion do
		if not item.Node.Parent then continue end
		local duration=if incoming then self.Config.TransitionRevealSeconds else self.Config.TransitionCoverSeconds
		local p=math.clamp((self.Elapsed-item.Delay)/math.max(0.05,duration-0.05),0,1)
		if incoming then
			item.Node.Position=item.Off:Lerp(item.Position,1-(1-p)^5)
			if item.Scale then item.Scale.Scale=item.BaseScale*(0.75+0.25*back(p)) end
		else
			item.Node.Position=item.Position:Lerp(item.Off,p^5)
			if item.Scale then item.Scale.Scale=item.BaseScale*(1-0.25*p*p) end
		end
	end
end
function Transition.Run(self: any, covered: () -> ())
	self.Pending=covered
	if self.Phase then return end -- Finish rightward travel; queued requests start a fresh left wipe.
	self:Restore();self:Capture(false)
	self.Phase,self.Elapsed="OUT",0
	Style.Play("Whoosh")
	self.Cover.Position=UDim2.fromScale(-1,0)
	self.Gui:SetAttribute("Phase","OUT")
	Style.SetEnabled(self.Gui,true)
end
function Transition.IsActive(self: any): boolean return self.Phase~=nil end
function Transition.Step(self: any, dt: number)
	local remaining=math.max(0,dt)
	while self.Phase and remaining>0 do
		local outgoing=self.Phase=="OUT"
		local duration=if outgoing then self.Config.TransitionCoverSeconds else self.Config.TransitionRevealSeconds
		local advance=math.min(remaining,math.max(0,duration-self.Elapsed));remaining-=advance;self.Elapsed+=advance
		if duration-self.Elapsed<1e-9 then self.Elapsed=duration end
		local p=math.clamp(self.Elapsed/duration,0,1)
		self.Cover.Position=UDim2.fromScale(if outgoing then -1+sine(p) else sine(p),0)
		self:Animate(not outgoing)
		if p<1 then break end
		self:Restore()
		if outgoing then
			local callback=self.Pending;self.Pending=nil
			self.Phase,self.Elapsed="IN",0
			self.Gui:SetAttribute("Phase","IN")
			if callback then
				local ok,err=pcall(callback)
				if not ok then self:Cancel();error(err) end
			end
			if self.Phase then self:Capture(true) end
		else
			local queued=self.Pending
			self:Cancel()
			if queued then self:Run(queued) end
		end
	end
end
function Transition.Cancel(self: any)
	self.Pending,self.Phase=nil,nil;self:Restore();self.Cover.Position=UDim2.fromScale(-1,0);Style.SetEnabled(self.Gui,false);self.Gui:SetAttribute("Phase",nil)
end
function Transition.Destroy(self: any) self:Cancel();Style.Dispose(self.Gui) end
return Transition

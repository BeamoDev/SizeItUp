--!strict
-- One startup overlay. Own only this blur/GUI; restore the HUD and CoreGui on exit.
local Style=require(script.Parent.UIStyle)
local Loading={};Loading.__index=Loading
-- The player cannot walk or jump while the loading screen is up: their controls are disabled and their character is anchored
-- (including a character that spawns during loading), then both are released when the screen fades (or is destroyed).
-- Applied through one function so the latest wish always wins.
local function applyControls(self: any)
	local spawn = if task then task.spawn else nil
	local function hold(character: any)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then root.Anchored = not self.WantControls end
	end
	local function apply()
		pcall(function()
			local player = self.D.PlayerGui.Parent
			hold(player.Character)
			-- A character that spawns while loading is anchored as soon as its root exists.
			if not self.WantControls and not self.CharacterHook then
				self.CharacterHook = player.CharacterAdded:Connect(function(character: any)
					local root = character:WaitForChild("HumanoidRootPart", 5)
					if root and not self.WantControls then root.Anchored = true end
				end)
			elseif self.WantControls and self.CharacterHook then
				self.CharacterHook:Disconnect();self.CharacterHook = nil
			end
			local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5))
			local controls = module:GetControls()
			if self.WantControls then controls:Enable() else controls:Disable() end
			hold(player.Character)
		end)
	end
	if spawn then spawn(apply) else apply() end
end
-- Hide authored world signs, replicated player CashTag/HeadTag billboards and the local PlayerDetails prompt while
-- loading. Billboards created during loading are covered too, then restored to their requested Enabled state.
local BILLBOARD_FOLDERS={{"Triggers","AFK"},{"Interactables","Eggs"},{"Interactables","Chairs"}}
local function hideBillboards(self: any)
	local world=self.D.World
	local gameRoot=world and world:FindFirstChild("Game")
	-- Game may stream in after the loading controller; the descendant hook below also covers that case.
	self.Billboards=self.Billboards or {}
	local function hide(node: Instance)
		if node:IsA("BillboardGui") and self.Billboards[node]==nil then
			local state={Enabled=node.Enabled,Forcing=false}
			self.Billboards[node]=state
			state.Forcing=true
			node.Enabled=false
			state.Forcing=false
			table.insert(self.HideConnections,node:GetPropertyChangedSignal("Enabled"):Connect(function()
				if state.Forcing or self.Revealed or self.Destroyed then return end
				state.Enabled=node.Enabled
				if node.Enabled then state.Forcing=true;node.Enabled=false;state.Forcing=false end
			end))
		end
	end
	local function worldBillboard(node: Instance): boolean
		if not node:IsA("BillboardGui") then return false end
		gameRoot=(world and world:FindFirstChild("Game")) or gameRoot
		if gameRoot then
			for _,path in BILLBOARD_FOLDERS do
				local section=gameRoot:FindFirstChild(path[1])
				local folder=(section and section:FindFirstChild(path[2])) or gameRoot:FindFirstChild(path[2])
				if folder and node:IsDescendantOf(folder) then return true end
			end
		end
		local runtime=world and world:FindFirstChild("Runtime")
		local other=runtime and runtime:FindFirstChild("Other")
		local displays=other and other:FindFirstChild("ScaleCosmeticDisplays")
		return displays~=nil and node:IsDescendantOf(displays)
	end
	if world then
		for _,node in world:GetDescendants() do if worldBillboard(node) then hide(node) end end
		table.insert(self.HideConnections,world.DescendantAdded:Connect(function(node)
			if worldBillboard(node) then hide(node) end
		end))
	end
	local playerGui=self.D.PlayerGui
	local function playerBillboard(node: Instance)
		if node:IsA("BillboardGui") and node.Name=="PlayerDetails" then hide(node) end
	end
	for _,node in playerGui:GetDescendants() do playerBillboard(node) end
	table.insert(self.HideConnections,playerGui.DescendantAdded:Connect(playerBillboard))
end
local function restoreBillboards(self: any)
	for node,state in self.Billboards or {} do
		if node.Parent then node.Enabled=state.Enabled end
	end
	self.Billboards=nil
end
local MINIMUM_SECONDS=5 -- The loading screen always plays this long, even when everything is ready sooner.
local FADE_SECONDS=1.2
local DOT_SIZE,DOT_SPACING,DOT_WAVE=42,96,30 -- the waving dots, three times their original size
local INTRO_SECONDS,INTRO_STAGGER,INTRO_MAX_DELAY,INTRO_DISTANCE,INTRO_START_SCALE=0.7,0.05,0.4,0.3,0.8
local function quintOut(t: number): number return 1-(1-t)^5 end
local function backOut(t: number): number
	local c1=1.70158;local c3=c1+1
	return 1+c3*(t-1)^3+c1*(t-1)^2
end
-- Top-level panels that should tween in; full-screen containers are looked through, not animated.
local function collect(root: any,out: {any},depth: number)
	for _,child in root:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child:GetAttribute("NoLoadMotion")~=true then
			local big=child.Size.X.Scale>=0.95 and child.Size.Y.Scale>=0.95
			if big and depth<2 then collect(child,out,depth+1) else table.insert(out,child) end
		end
	end
end
function Loading.new(d: any)
	if Style.Authoring then return Loading.FromHUD(d) end
	local self: any=setmetatable({D=d,Age=0,Connections={},HideConnections={},Hidden={},Core={},Dots={},Destroyed=false},Loading)
	local gui=Style.Node(d.PlayerGui,"ScaleStartupLoading","ScreenGui")
	gui.Enabled=true
	gui.Name,gui.ResetOnSpawn,gui.IgnoreGuiInset,gui.DisplayOrder="ScaleStartupLoading",false,true,10000
	self.Gui=gui
	local backdrop=Style.Node(gui,"Backdrop","Frame")
	backdrop.Name,backdrop.Size,backdrop.BackgroundColor3,backdrop.BackgroundTransparency,backdrop.BorderSizePixel,backdrop.Active="Backdrop",UDim2.fromScale(1,1),Color3.new(0,0,0),0.92,0,true
	backdrop.Parent=gui;self.Backdrop=backdrop
	for index=1,3 do
		local dot=Style.Node(backdrop,"Dot"..index,"Frame")
		dot.Name,dot.AnchorPoint,dot.Size,dot.Position="Dot"..index,Vector2.new(0.5,0.5),UDim2.fromOffset(DOT_SIZE,DOT_SIZE),UDim2.new(0.5,(index-2)*DOT_SPACING,0.5,0)
		dot.BackgroundColor3,dot.BorderSizePixel,dot.ZIndex,dot.Parent=Color3.new(1,1,1),0,2,backdrop
		local corner=Style.Node(dot,"Corners","UICorner");corner.CornerRadius,corner.Parent=UDim.new(1,0),dot
		table.insert(self.Dots,dot)
	end
	local blur=Instance.new("BlurEffect");blur.Name,blur.Size,blur.Parent="ScaleStartupBlur",56,d.Lighting;self.Blur=blur
	gui.Parent=d.PlayerGui
	local function hide(other: Instance)
		if not other:IsA("ScreenGui") or other==gui or self.Hidden[other] then return end
		local state={Enabled=other.Enabled};self.Hidden[other]=state
		other.Enabled=false
		table.insert(self.HideConnections,other:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not self.Destroyed and other.Enabled then state.Enabled=true;other.Enabled=false end
		end))
	end
	for _,other in d.PlayerGui:GetChildren() do hide(other) end
	table.insert(self.HideConnections,d.PlayerGui.ChildAdded:Connect(hide))
	for _,kind in {Enum.CoreGuiType.Backpack,Enum.CoreGuiType.PlayerList,Enum.CoreGuiType.Health} do
		pcall(function() self.Core[kind]=d.StarterGui:GetCoreGuiEnabled(kind);d.StarterGui:SetCoreGuiEnabled(kind,false) end)
	end
	hideBillboards(self)
	self.WantControls=false;applyControls(self)
	table.insert(self.Connections,d.RunService.RenderStepped:Connect(function(dt) self:Step(dt) end))
	-- Never leave the input blocker/blur behind after a GUI teardown.
	table.insert(self.Connections,gui.Destroying:Connect(function() self:Destroy(true) end))
	return self
end
function Loading.FromHUD(d: any)
	local authored=Style.Authoring
	local gui=authored.Overlays:FindFirstChild("Loading") or authored.HUD:FindFirstChild("Loading") or d.PlayerGui:FindFirstChild("LoadingScreen")
	-- The authored StarterGui.LoadingScreen is the home of the loading UI (its balls, or the dots this controller adds).
	if not gui and d.StarterGui then
		local template=d.StarterGui:FindFirstChild("LoadingScreen")
		if template and template:IsA("ScreenGui") then gui=template:Clone();gui.Parent=d.PlayerGui end
	end
	if gui and gui:IsA("ScreenGui") then
		gui.ResetOnSpawn,gui.DisplayOrder=false,math.max(gui.DisplayOrder,10000)
	end
	local self:any=setmetatable({D=d,Gui=gui,Age=0,Connections={},HideConnections={},Hidden={},Core={},Dots={},DotPoses={},DotScales={},DotFade={},Destroyed=false},Loading)
	if gui then
		self.Backdrop=gui:FindFirstChild("Backdrop")
		-- The waving balls are any GuiObjects in the overlay named like a dot, ball or circle.
		local found={}
		for _,node in gui:GetDescendants() do
			local name=string.lower(node.Name)
			if node:IsA("GuiObject") and (name:find("dot",1,true) or name:find("ball",1,true) or name:find("circle",1,true)) then table.insert(found,node) end
		end
		table.sort(found,function(a,b) return a.Name<b.Name end)
		for _,dot in found do
			table.insert(self.Dots,dot);self.DotPoses[dot]=dot.Position
			self.DotFade[dot]=if dot:IsA("GuiObject") and dot.ClassName:find("Image") then dot.ImageTransparency else dot.BackgroundTransparency
			-- A list or grid layout ignores Position, so those balls wave by pulsing their size instead.
			local parent=dot.Parent
			if parent and (parent:FindFirstChildOfClass("UIListLayout") or parent:FindFirstChildOfClass("UIGridLayout")) then
				local scale=Instance.new("UIScale");scale.Name="WaveScale";scale.Parent=dot;self.DotScales[dot]=scale
			end
		end
		Style.SetEnabled(gui,true)
	end
	-- No authored balls to wave: the startup screen still shows the three white dots, inside LoadingScreen when it exists.
	if #self.Dots==0 then
		local hosted=gui~=nil and gui:IsA("ScreenGui")
		local host:any=gui
		if not hosted then
			host=Instance.new("ScreenGui")
			host.Name,host.ResetOnSpawn,host.IgnoreGuiInset,host.DisplayOrder="ScaleStartupLoading",false,true,10000
		elseif not self.Backdrop then
			local backdrop=Instance.new("Frame")
			backdrop.Name,backdrop.Size,backdrop.BackgroundColor3,backdrop.BackgroundTransparency,backdrop.BorderSizePixel,backdrop.Active="Backdrop",UDim2.fromScale(1,1),Color3.new(0,0,0),0.92,0,true
			backdrop.Parent=host;self.Backdrop=backdrop
		end
		local parent=if hosted then self.Backdrop else host
		for index=1,3 do
			local dot=Instance.new("Frame")
			dot.Name,dot.AnchorPoint,dot.Size,dot.Position="Dot"..index,Vector2.new(0.5,0.5),UDim2.fromOffset(DOT_SIZE,DOT_SIZE),UDim2.new(0.5,(index-2)*DOT_SPACING,0.5,0)
			dot.BackgroundColor3,dot.BorderSizePixel,dot.Parent=Color3.new(1,1,1),0,parent
			local corner=Instance.new("UICorner");corner.CornerRadius,corner.Parent=UDim.new(1,0),dot
			table.insert(self.Dots,dot);self.DotPoses[dot]=dot.Position;self.DotFade[dot]=0
		end
		if not hosted then host.Parent=d.PlayerGui;self.Fallback=host end
	end
	local blur=Instance.new("BlurEffect");blur.Name,blur.Size,blur.Parent="ScaleStartupBlur",56,d.Lighting;self.Blur=blur
	local function hide(other)
		if other==authored.HUD or other==gui or other==self.Fallback or self.Hidden[other] or not (other:IsA("ScreenGui") or other:IsA("GuiObject")) then return end
		local state={Enabled=Style.IsEnabled(other)};self.Hidden[other]=state;Style.SetVisible(other,false)
		local property=if other:IsA("GuiObject") then "Visible" else "Enabled"
		table.insert(self.HideConnections,other:GetPropertyChangedSignal(property):Connect(function()
			if not self.Destroyed and Style.IsEnabled(other) then state.Enabled=true;Style.SetVisible(other,false) end
		end))
	end
	for _,other in Style.Roots(d.PlayerGui) do hide(other) end
	table.insert(self.HideConnections,d.PlayerGui.ChildAdded:Connect(hide))
	for _,kind in {Enum.CoreGuiType.Backpack,Enum.CoreGuiType.PlayerList,Enum.CoreGuiType.Health} do
		pcall(function()self.Core[kind]=d.StarterGui:GetCoreGuiEnabled(kind);d.StarterGui:SetCoreGuiEnabled(kind,false) end)
	end
	hideBillboards(self)
	self.WantControls=false;applyControls(self)
	table.insert(self.Connections,d.RunService.RenderStepped:Connect(function(dt)self:Step(dt) end))
	table.insert(self.Connections,(gui or authored.HUD).Destroying:Connect(function()self:Destroy(true) end))
	return self
end
function Loading.Step(self: any,dt: number)
	if self.Destroyed then return end
	self.Age+=math.max(0,dt)
	if not self.ExitAge then
		local ok,ready=pcall(self.D.Ready,self.Age)
		local minimum=self.D.MinimumSeconds or MINIMUM_SECONDS
		if not ok or (ready and self.Age>=minimum) or self.Age>=60 then
			self.ExitAge=0
			-- The fade and the HUD entrance start together.
			self:Reveal(true)
		end
	end
	local opacity=1
	if self.ExitAge then
		self.ExitAge+=math.max(0,dt)
		local t=math.clamp(self.ExitAge/FADE_SECONDS,0,1)
		opacity=1-t*t*(3-2*t)
	end
	self:StepIntro(dt)
	for index,dot in self.Dots do
		local offset=-math.sin(self.Age*math.pi*2/1.8-(index-1)*0.65)*DOT_WAVE
		if self.DotPoses then
			local scale=self.DotScales and self.DotScales[dot]
			if scale then scale.Scale=1+0.4*(-offset/DOT_WAVE*0.5+0.5) else dot.Position=self.DotPoses[dot]+UDim2.fromOffset(0,offset) end
			-- Authored balls keep their own look until the fade at the end.
			if self.ExitAge then
				local base=self.DotFade[dot] or 0
				local value=base+(1-base)*(1-opacity)
				if dot.ClassName:find("Image") then dot.ImageTransparency=value else dot.BackgroundTransparency=value end
			end
		else
			dot.Position=UDim2.new(0.5,(index-2)*DOT_SPACING,0.5,offset)
			dot.BackgroundTransparency=1-opacity
		end
	end
	self.Blur.Size=56*opacity
	if self.Backdrop then self.Backdrop.BackgroundTransparency=1-0.08*opacity end
	if opacity==0 then self:Destroy() end
end
-- Returns the hidden UI and CoreGui. When animate is set, each top-level panel slides in from its
-- nearest screen edge while scaling up, staggered, instead of popping in.
function Loading.Reveal(self: any,animate: boolean)
	if self.Revealed then return end
	self.Revealed=true
	for _,connection in self.HideConnections do connection:Disconnect() end
	table.clear(self.HideConnections)
	local targets={}
	for gui,state in self.Hidden do
		if gui.Parent then
			local requested=gui:GetAttribute("RuntimeEnabled")
			local enabled=if requested~=nil then requested else state.Enabled
			Style.SetVisible(gui,enabled)
			if enabled and animate then
				if gui:IsA("GuiObject") and not (gui.Size.X.Scale>=0.95 and gui.Size.Y.Scale>=0.95) then table.insert(targets,gui)
				else collect(gui,targets,0) end
			end
		end
	end
	for kind,enabled in self.Core do pcall(function() self.D.StarterGui:SetCoreGuiEnabled(kind,enabled) end) end
	restoreBillboards(self)
	self.WantControls=true;applyControls(self)
	table.clear(self.Hidden);table.clear(self.Core)
	if self.Backdrop then self.Backdrop.Active=false end
	self.Intro,self.IntroAge={},0
	for index,node in targets do
		local rest=node.Position
		local anchor=node.AnchorPoint
		local cx=rest.X.Scale+(0.5-anchor.X)*node.Size.X.Scale
		local cy=rest.Y.Scale+(0.5-anchor.Y)*node.Size.Y.Scale
		local edges={{cx,-1,0},{1-cx,1,0},{cy,0,-1},{1-cy,0,1}}
		table.sort(edges,function(a,b) return a[1]<b[1] end)
		local scale=Instance.new("UIScale");scale.Name="LoadInScale";scale.Scale=INTRO_START_SCALE;scale.Parent=node
		local from=rest+UDim2.fromScale(edges[1][2]*INTRO_DISTANCE,edges[1][3]*INTRO_DISTANCE)
		node.Position=from
		table.insert(self.Intro,{Node=node,Rest=rest,From=from,Scale=scale,Delay=math.min((index-1)*INTRO_STAGGER,INTRO_MAX_DELAY)})
	end
end
function Loading.StepIntro(self: any,dt: number)
	local intro=self.Intro
	if not intro or #intro==0 then return end
	self.IntroAge+=math.max(0,dt)
	local remaining={}
	for _,entry in intro do
		local node=entry.Node
		if not node.Parent then
			if entry.Scale.Parent then entry.Scale:Destroy() end
			continue
		end
		local t=math.clamp((self.IntroAge-entry.Delay)/INTRO_SECONDS,0,1)
		if t>=1 then self:FinishEntry(entry)
		else
			node.Position=entry.From:Lerp(entry.Rest,quintOut(t))
			entry.Scale.Scale=INTRO_START_SCALE+(1-INTRO_START_SCALE)*backOut(t)
			table.insert(remaining,entry)
		end
	end
	self.Intro=remaining
end
function Loading.FinishEntry(_self: any,entry: any)
	if entry.Node.Parent then entry.Node.Position=entry.Rest end
	if entry.Scale.Parent then entry.Scale:Destroy() end
end
function Loading.Destroy(self: any,guiDestroying: boolean?)
	if self.Destroyed then return end
	self.Destroyed=true
	for _,connection in self.Connections do connection:Disconnect() end
	self:Reveal(false)
	for _,entry in self.Intro or {} do self:FinishEntry(entry) end
	self.Intro=nil
	self.Blur:Destroy();if not guiDestroying and self.Gui then Style.Dispose(self.Gui) end
	if self.Fallback then self.Fallback:Destroy();self.Fallback=nil end
end
return Loading

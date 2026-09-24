--!strict
local HintWobble=require(script.Parent.HintWobble)
local Style = require(script.Parent.UIStyle)
local RevealPresentation = require(script.Parent.RevealPresentation)
local MeasurementUI=require(script.Parent.MeasurementUI)
local styleRulerFont=MeasurementUI.StyleFont
local BotPortrait=require(script.Parent.BotPortrait)
local UIController = {}
UIController.__index = UIController
local PERFECT_ACCURACY=99
local PERFECT_SECONDS=1.4
local function screen(parent: Instance, name: string): ScreenGui
 local hud=if name=="ScaleItUpHUD" then parent:FindFirstChild("HUD") else nil
 local gui=Style.Node(parent,if hud and hud:IsA("ScreenGui") then "HUD" else name,"ScreenGui");gui.Name,gui.ResetOnSpawn,gui.DisplayOrder,gui.Enabled,gui.Parent=gui.Name,false,30,false,parent;Style.SetEnabled(gui,false);return gui
end
local function card(parent: Instance,name: string,position: UDim2,size: UDim2): Frame
 return Style.Frame(parent,name,size,position,Color3.fromRGB(24,27,39),0.55)
end
local function hearts(parent: Instance,prefix: string,count: number)
 local icons={}
 for i=1,count do local icon=Style.Text(parent,prefix..i,"♥",UDim2.fromScale(0.85/count,0.7),UDim2.fromScale((i-1)*0.95/count,0.26),45);icon.TextColor3=Color3.fromRGB(255,49,72);table.insert(icons,icon) end
 return icons
end
function UIController.new(playerGui: PlayerGui,config: any,starterGui: StarterGui?)
 if Style.Authoring then return Style.Authoring.Match(UIController,playerGui,config,starterGui) end
 local gui=screen(playerGui,"ScaleItUpHUD");local statusGui=screen(playerGui,"ScaleItUpStatus")
 local header=card(gui,"Header",UDim2.fromScale(0.29,0.015),UDim2.fromScale(0.42,0.12))
 local round=Style.Text(header,"Round","",UDim2.fromScale(0.9,0.38),UDim2.fromScale(0.05,0.05),24)
 local time=Style.Text(header,"Time","",UDim2.fromScale(0.9,0.52),UDim2.fromScale(0.05,0.42),38)
 local yourPanel=Style.Node(gui,"Hearts","Frame");yourPanel.Name,yourPanel.Size,yourPanel.Position,yourPanel.BackgroundTransparency,yourPanel.Parent="Hearts",UDim2.fromScale(0.2,0.115),UDim2.fromScale(0.02,0.85),1,gui
 Style.Text(yourPanel,"Name","YOUR HEARTS",UDim2.fromScale(0.9,0.26),UDim2.new(),18)
 local yourHearts=hearts(yourPanel,"YourHeart",config.StartingHearts)
 local opponentPanel=Style.Node(gui,"OpponentHearts","Frame");opponentPanel.Size,opponentPanel.Position,opponentPanel.BackgroundTransparency,opponentPanel.Parent=UDim2.fromScale(0.19,0.1),UDim2.fromScale(0.79,0.02),1,gui
 local opponentHearts=hearts(opponentPanel,"OpponentHeart",config.StartingHearts)
 local scoreboard=Style.Text(gui,"Players","",UDim2.fromScale(0.26,0.16),UDim2.fromScale(0.72,0.025),20)
 local ref=card(gui,"Reference",UDim2.fromScale(0.04,0.15),UDim2.fromScale(0.31,0.095))
 local target=card(gui,"Target",UDim2.fromScale(0.52,0.15),UDim2.fromScale(0.31,0.095))
 local reference=Style.Text(ref,"Text","",UDim2.fromScale(0.94,0.9),UDim2.fromScale(0.03,0.05),24)
 local targetText=Style.Text(target,"Text","",UDim2.fromScale(0.94,0.9),UDim2.fromScale(0.03,0.05),24)
 local bottom=card(gui,"Estimate",UDim2.fromScale(0.29,0.83),UDim2.fromScale(0.43,0.115))
 local guess=Style.Text(bottom,"Guess","Your size",UDim2.fromScale(0.94,0.8),UDim2.fromScale(0.03,0.06),32)
 local lockIn=Style.Button(gui,"LockIn","LOCK IN!",UDim2.fromScale(0.16,0.085),UDim2.fromScale(0.74,0.845),Color3.fromRGB(35,225,72))
 lockIn.Visible=false
 local locked=card(gui,"LockAnnouncement",UDim2.fromScale(0.5,0.34),UDim2.fromScale(0.62,0.14));locked.AnchorPoint=Vector2.new(0.5,0.5);locked.Visible=false
 local lockedScale=Style.Node(locked,"LockMotionScale","UIScale");lockedScale.Parent=locked
 local lockedTitle=Style.Text(locked,"Title","",UDim2.fromScale(0.92,0.49),UDim2.fromScale(0.04,0.09),34)
 local lockedHint=Style.Text(locked,"Hint","",UDim2.fromScale(0.92,0.26),UDim2.fromScale(0.04,0.64),19)
 local lockedLine=Style.Node(locked,"Sweep","Frame");lockedLine.Name,lockedLine.BorderSizePixel,lockedLine.BackgroundColor3,lockedLine.Size,lockedLine.Position,lockedLine.Parent="Sweep",0,Color3.fromRGB(65,255,113),UDim2.fromScale(0,0.035),UDim2.fromScale(0.05,0.94),locked
 local results=Style.Node(gui,"Results","Frame");results.Name,results.Size,results.Position,results.BackgroundTransparency,results.Visible,results.Parent="Results",UDim2.fromScale(0.86,0.24),UDim2.fromScale(0.07,0.41),1,false,gui
 local pulse=Style.Node(guess,"AccuracyPulse","UIScale");pulse.Name="AccuracyPulse";pulse.Parent=guess
 local accuracyTrack=Style.Frame(bottom,"AccuracyTrack",UDim2.fromScale(0.9,0.04),UDim2.fromScale(0.05,0.92),Color3.fromRGB(70,80,95),0.7)
 local accuracyFill=Style.Node(accuracyTrack,"Fill","Frame");accuracyFill.Name,accuracyFill.Size,accuracyFill.BackgroundColor3,accuracyFill.BorderSizePixel,accuracyFill.Parent="Fill",UDim2.fromScale(0,1),Color3.fromRGB(80,225,255),0,accuracyTrack
 local help=Style.Text(bottom,"Help","Drag object: ↑ bigger / ↓ smaller",UDim2.fromScale(0.94,0.3),UDim2.fromScale(0.03,0.64),17)
 help.Visible=false
 local slider=Style.Node(gui,"ScaleSlider","Frame");slider.Size,slider.Position,slider.BackgroundTransparency,slider.Parent=UDim2.fromScale(0.065,0.55),UDim2.fromScale(0.91,0.32),1,gui
 local bounds=Style.Node(slider,"SliderSizeLimit","UISizeConstraint");bounds.MinSize,bounds.MaxSize,bounds.Parent=Vector2.new(48,0),Vector2.new(72,800),slider
 local plus=Style.Button(slider,"Plus","+",UDim2.fromScale(1,0.15),UDim2.new())
 local minus=Style.Button(slider,"Minus","−",UDim2.fromScale(1,0.15),UDim2.fromScale(0,0.85))
 local track=Style.Node(slider,"Track","TextButton");track.Name,track.Size,track.Position,track.BackgroundTransparency,track.Text,track.Parent="Track",UDim2.fromScale(1,0.66),UDim2.fromScale(0,0.17),1,"",slider
 local line=Style.Frame(track,"Line",UDim2.fromScale(0.14,1),UDim2.fromScale(0.43,0),Color3.fromRGB(80,218,255),0.15)
 local knob=Style.Frame(track,"Knob",UDim2.fromScale(0.7,0.085),UDim2.fromScale(0.15,0.5),Color3.new(1,1,1),0);knob.AnchorPoint=Vector2.new(0,0.5)
 local statusPanel=card(statusGui,"Status",UDim2.fromScale(0.27,0.35),UDim2.fromScale(0.46,0.24))
 local status=Style.Text(statusPanel,"Text","",UDim2.fromScale(0.94,0.9),UDim2.fromScale(0.03,0.05),40)
 local flash=Style.Node(gui,"DamageFlash","Frame");flash.Name,flash.Size,flash.BackgroundColor3,flash.BackgroundTransparency,flash.BorderSizePixel,flash.ZIndex,flash.Parent="DamageFlash",UDim2.fromScale(1,1),Color3.fromRGB(255,20,50),1,0,20,gui
 local self=setmetatable({Gui=gui,StatusGui=statusGui,Config=config,Round=round,Time=time,YourHearts=yourHearts,OpponentHearts=opponentHearts,OpponentPanel=opponentPanel,Scoreboard=scoreboard,Reference=reference,Target=targetText,Bottom=bottom,Guess=guess,Help=help,Slider=slider,Track=track,Knob=knob,Plus=plus,Minus=minus,Status=status,Flash=flash,AccuracyTrack=accuracyTrack,AccuracyFill=accuracyFill,Pulse=pulse,BottomStroke=bottom:FindFirstChildOfClass("UIStroke")},UIController)
 self.LockIn,self.Results,self.ResultCards=lockIn,results,{}
 self.ChainStatus=Style.Text(gui,"ChainProgress","",UDim2.fromScale(0.24,0.065),UDim2.fromScale(0.01,0.78),18)
 self.ChainStatus.Visible=false
 self.HintButton=Style.Button(gui,"BuySizeHint",(if (config.HintCash or 0)>0 then "Hint / "..Style.Money(config.HintCash) else "Hint"),UDim2.fromScale(0.19,0.075),UDim2.fromScale(0.03,0.7),Style.Purple)
 self.PetNotice=Style.Text(gui,"PetAbilityNotice","",UDim2.fromScale(0.7,0.055),UDim2.fromScale(0.15,0.255),22)
	self.HintButton.Visible,self.PetNotice.Visible=false,false
	self.HintWobble=HintWobble.new(self.HintButton)
 self.HintPanel=card(gui,"SizeHintAnnouncement",UDim2.fromScale(0.29,0.255),UDim2.fromScale(0.42,0.115))
 self.HintPanel.Visible=false;self.HintPanel.BackgroundColor3=Color3.fromRGB(57,39,13)
 self.HintTitle=Style.Text(self.HintPanel,"Title","SIZE HINT",UDim2.fromScale(0.92,0.3),UDim2.fromScale(0.04,0.04),20)
 self.HintGuidance=Style.Text(self.HintPanel,"Guidance",config.HintMessage.Title,UDim2.fromScale(0.92,0.44),UDim2.fromScale(0.04,0.34),26)
 self.HintProgress=Style.Frame(self.HintPanel,"TimeRemaining",UDim2.fromScale(0.92,0.045),UDim2.fromScale(0.04,0.9),Color3.fromRGB(255,222,80),0)
 self.HintMotion=Style.Node(self.HintPanel,"HintMotionScale","UIScale");self.HintMotion.Parent=self.HintPanel
 self.PlayerGui,self.StarterGui,self.HiddenGuis,self.HiddenCore=playerGui,starterGui,{},{}
 self:CreateResultSlots()
 self.LockAnnouncement,self.LockedTitle,self.LockedHint,self.LockedScale,self.LockedLine=locked,lockedTitle,lockedHint,lockedScale,lockedLine
 self:CreateReferenceMeasurement()
 self:CreateObjectResizeIndicator()
 return self
end
function UIController.CreateObjectResizeIndicator(self: any)
 local root=Style.Frame(self.Gui,"ObjectResizeIndicator",UDim2.fromOffset(126,40),UDim2.new(),Color3.fromRGB(24,27,39),0.25)
 root.Visible,root.Active,root.ZIndex=false,false,80
 local arrows=Style.Text(root,"ResizeArrows","↕",UDim2.fromOffset(32,34),UDim2.fromOffset(5,3),30)
 local label=Style.Text(root,"Action","Resize",UDim2.fromOffset(80,30),UDim2.fromOffset(39,5),23)
 arrows.ZIndex,label.ZIndex=81,81;arrows.Active,label.Active=false,false
 self.ObjectResizeIndicator=root
end
function UIController.SetObjectHover(self: any,position: Vector2?,viewportPosition: Vector2?)
 local root=self.ObjectResizeIndicator
 root.Visible=false
 if not position or not Style.IsEnabled(self.Gui) then return end
 local point=if Style.IgnoreInset(self.Gui) then viewportPosition or position else position
 local viewport=self.MeasurementRoot.AbsoluteSize
 if viewport.X<150 or viewport.Y<64 then return end
 local x,y=point.X+18,point.Y+18
 if x+126>viewport.X-8 then x=point.X-144 end
 if y+40>viewport.Y-8 then y=point.Y-58 end
 root.Position=UDim2.fromOffset(math.clamp(x,8,viewport.X-134),math.clamp(y,8,viewport.Y-48))
 root.Visible=true
end
local function createMeasurement(self: any,name: string,labelName: string)
 local root=Style.Node(self.Gui,name,"Frame")
 root.Size,root.Position,root.BackgroundTransparency,root.BorderSizePixel=UDim2.fromScale(1,1),UDim2.new(),1,0
 root.Visible,root.Active,root.ZIndex=false,false,0
 local dots={}
 local label=Style.Text(root,labelName,"",UDim2.fromOffset(160,56),UDim2.new(),44)
 label.ZIndex=0
 label.TextColor3=Color3.new(1,1,1)
 label.TextScaled,label.TextWrapped=false,false
 local objectName=Style.Text(root,"ObjectName","",UDim2.fromOffset(160,28),UDim2.new(),22)
 objectName.ZIndex=0
 objectName.TextScaled,objectName.TextWrapped,objectName.Active=true,true,false
 objectName:FindFirstChild("TextSizeLimit").MinTextSize=16
 MeasurementUI.StyleLabel(label)
 MeasurementUI.StyleLabel(objectName)
 local function marker(markerName: string): Frame
  local mark=Style.Node(root,markerName,"Frame")
  mark.AnchorPoint,mark.BackgroundColor3,mark.BackgroundTransparency=Vector2.new(0.5,0.5),Color3.new(1,1,1),0
  mark.BorderSizePixel,mark.ZIndex,mark.Active,mark.Visible=0,0,false,false
  MeasurementUI.StyleMarker(mark,true)
  return mark
 end
 marker("TopCap");marker("BottomCap")
 -- Reuse a bounded pool; no instances or connections are created per render.
 for i=1,64 do
  local dot=marker("HeightDot"..i)
  dot.Size=UDim2.fromOffset(8,12)
  dot.Visible=false;dots[i]=dot
 end
 return root,dots,label,objectName
end
function UIController.CreateReferenceMeasurement(self: any)
 self.MeasurementRoot,self.MeasurementDots,self.MeasurementText,self.ReferenceObjectName=createMeasurement(self,"ReferenceMeasurement","RealHeight")
 self.MysteryMeasurementRoot,self.MysteryMeasurementDots,self.MysteryMeasurementText,self.MysteryObjectName=createMeasurement(self,"MysteryMeasurement","UnknownHeight")
 self.EstimatedHeight=Style.Text(self.MysteryMeasurementRoot,"EstimatedHeight","",UDim2.fromOffset(160,56),UDim2.new(),44)
 self.EstimatedHeight.ZIndex=0
 self.EstimatedHeight.TextScaled,self.EstimatedHeight.TextWrapped,self.EstimatedHeight.Visible=false,false,false
 MeasurementUI.StyleLabel(self.EstimatedHeight)
 -- Results only: a small round headshot above the caption stack, showing whose attempt is growing.
 local mugshot=Style.Node(self.MysteryMeasurementRoot,"PlayerMugshot","ImageLabel")
 mugshot.BackgroundTransparency,mugshot.BorderSizePixel,mugshot.ZIndex=1,0,0
 mugshot.ScaleType,mugshot.Visible,mugshot.Active=Enum.ScaleType.Fit,false,false
 -- UIAspectRatio is not a class Lune's test polyfill knows; the manual square offset size below already
 -- keeps this a 1:1 circle either way, so a failure here is harmless in tests.
 pcall(function() Style.Node(mugshot,"MugshotAspect","UIAspectRatio").AspectRatio=1 end)
 Style.Node(mugshot,"MugshotCorner","UICorner").CornerRadius=UDim.new(1,0)
 local mugshotStroke=Style.Node(mugshot,"ProfileOutline","UIStroke")
 mugshotStroke.Color,mugshotStroke.Transparency,mugshotStroke.Thickness=Color3.new(),0,2
 self.MysteryPlayerMugshot=mugshot
end
local function drawMeasurement(self: any,root: Frame,dots: {Frame},label: TextLabel,camera: Camera?,bounds: CFrame?,size: Vector3?,text: string,direction: number,objectName: TextLabel,avoid: any?,profileBelow: boolean?)
 root.Visible=false
 local topCap,bottomCap=root:FindFirstChild("TopCap"),root:FindFirstChild("BottomCap")
 if topCap and topCap:IsA("GuiObject") then topCap.Visible=false end
 if bottomCap and bottomCap:IsA("GuiObject") then bottomCap.Visible=false end
 if not Style.IsEnabled(self.Gui) or not camera or not bounds or not size then return end
 local project=if Style.IgnoreInset(self.Gui) then camera.WorldToViewportPoint else camera.WorldToScreenPoint
 local left,edge,low,high=math.huge,-math.huge,math.huge,-math.huge
 for _,x in {-0.5,0.5} do for _,y in {-0.5,0.5} do for _,z in {-0.5,0.5} do
  local point=bounds:PointToWorldSpace(size*Vector3.new(x,y,z))
  local pixel=project(camera,point)
  if pixel.Z<=0 then return end
  left=math.min(left,pixel.X);edge=math.max(edge,pixel.X);low=math.min(low,point.Y);high=math.max(high,point.Y)
 end end end
 local horizontal=camera.CFrame.RightVector*Vector3.new(1,0,1)
 local right=if horizontal.Magnitude>0.001 then horizontal.Unit else Vector3.xAxis
 local halfWidth=(math.abs(right:Dot(bounds.RightVector))*size.X+math.abs(right:Dot(bounds.UpVector))*size.Y+math.abs(right:Dot(bounds.LookVector))*size.Z)*0.5
 local side=bounds.Position+right*halfWidth*direction
 local top=project(camera,Vector3.new(side.X,high,side.Z))
 local bottom=project(camera,Vector3.new(side.X,low,side.Z))
 local viewport=root.AbsoluteSize
 if viewport.X<=0 or viewport.Y<=0 then viewport=camera.ViewportSize end
 local compact=viewport.X<700 or viewport.Y<520
 local sideGap=if compact then 10 else 18
 local height=bottom.Y-top.Y;local lineX=if direction<0 then left-sideGap else edge+sideGap
 -- Hide an off-screen/behind-camera ruler instead of showing a false clamped height.
 if height<2 or lineX<3 or lineX>viewport.X-3 or top.Y<2 or bottom.Y>viewport.Y-2 then return end
 root.Visible=true
 -- Match the bold reference art: horizontal end caps and separated white vertical blocks, all with a black outline.
 local capWidth,capHeight=if compact then 24 else 32,if compact then 7 else 9
 local segmentWidth,segmentHeight=if compact then 7 else 9,if compact then 10 else 13
 local segmentGap=if compact then 4 else 5
 if topCap and topCap:IsA("GuiObject") then
  topCap.Size,topCap.Position,topCap.Visible=UDim2.fromOffset(capWidth,capHeight),UDim2.fromOffset(lineX,top.Y),true
 end
 if bottomCap and bottomCap:IsA("GuiObject") then
  bottomCap.Size,bottomCap.Position,bottomCap.Visible=UDim2.fromOffset(capWidth,capHeight),UDim2.fromOffset(lineX,bottom.Y),true
 end
 local segmentTop=top.Y+capHeight*0.5+segmentGap
 local segmentBottom=bottom.Y-capHeight*0.5-segmentGap
 local segmentSpan=math.max(0,segmentBottom-segmentTop)
 local count=math.clamp(math.floor((segmentSpan+segmentGap)/(segmentHeight+segmentGap)),1,#dots)
 for i,dot in dots do
  dot.Visible=i<=count
  if i<=count then
   dot.Size=UDim2.fromOffset(segmentWidth,math.min(segmentHeight,math.max(3,segmentSpan/count-segmentGap)))
   dot.Position=UDim2.fromOffset(lineX,if count==1 then (segmentTop+segmentBottom)*0.5 else segmentTop+(i-1)/(count-1)*segmentSpan)
  end
 end
 label.Text=text
 -- Keep runtime-rebound captions on the same Montserrat Black face.
 styleRulerFont(label);styleRulerFont(objectName)
 -- Use both axes so landscape phones stay compact instead of inheriting desktop-sized text from their width.
 local scaleBasis=math.min(viewport.X,viewport.Y*1.25)
 local fontSize=math.floor(math.clamp(scaleBasis*0.055,22,44)+0.5)
 local nameFont=math.floor(math.clamp(scaleBasis*0.028,12,22)+0.5)
 local nameWidth=#objectName.Text*nameFont*0.65
 local minimumWidth=if compact then 68 else 90
 local maximumNameWidth=if compact then 180 else 240
 local width=math.min(viewport.X-12,math.max(minimumWidth,#text*fontSize*0.65,math.min(maximumNameWidth,nameWidth)))
 local nameHeight=if objectName.Text=="" then 0 elseif nameWidth>width then nameFont*2+4 else nameFont+6
 local measurementHeight=fontSize+10
 local blockHeight=nameHeight+measurementHeight
 local profileExtent=if profileBelow then (if compact then 34 else 46) else 0
 local profileGap=if profileBelow then 6 else 0
 local totalBlockHeight=blockHeight+profileGap+profileExtent
 -- Always cap the ruler with its name/measurement stack, at every screen width.
 -- Horizontal edge clamping never changes this into a side or midpoint label.
 local edgePadding=if compact then 5 else 8
 local textX=math.clamp(lineX-width*0.5,edgePadding,math.max(edgePadding,viewport.X-width-edgePadding))
 local textY=math.max(edgePadding,top.Y-totalBlockHeight-(if compact then 4 else 8))
 -- HUD overlap is intentional: rulers use ZIndex 0 and sit behind every authored panel. Only separate the two
 -- ruler caption stacks from each other, since neither is an interactive HUD control.
 local regions={}
 if avoid then table.insert(regions,avoid) end
 local function overlapsRegion(region: any): boolean
  return textX<region.X+region.Width+6 and textX+width>region.X-6 and textY<region.Y+region.Height+6 and textY+totalBlockHeight>region.Y-6
 end
 for _=1,#regions do
  local moved=false
  for _,region in regions do
   if overlapsRegion(region) then
    local pushed=region.Y-totalBlockHeight-6
    if pushed<textY then textY=pushed;moved=true end
   end
  end
  if not moved then break end
 end
 textY=math.max(edgePadding,textY)
 objectName.Visible=nameHeight>0
 objectName:FindFirstChild("TextSizeLimit").MaxTextSize=nameFont
 objectName.Size,objectName.Position=UDim2.fromOffset(width,nameHeight),UDim2.fromOffset(textX,textY)
 label.TextSize=fontSize
 local labelLimit=label:FindFirstChild("TextSizeLimit")
 if labelLimit then labelLimit.MaxTextSize=fontSize end
 label.Size,label.Position=UDim2.fromOffset(width,measurementHeight),UDim2.fromOffset(textX,textY+nameHeight)
 return {X=textX,Y=textY,Width=width,Height=totalBlockHeight,TextHeight=blockHeight,ProfileY=textY+blockHeight+profileGap,ProfileExtent=profileExtent,Compact=compact}
end
function UIController.DrawReferenceMeasurement(self: any,camera: Camera?,bounds: CFrame?,size: Vector3?,meters: number?)
 self.ReferenceLabelBounds=nil
 if not meters or meters<=0 then self.MeasurementRoot.Visible=false;return end
 local text=string.format("%.2fm",meters)
 self.ReferenceLabelBounds=drawMeasurement(self,self.MeasurementRoot,self.MeasurementDots,self.MeasurementText,camera,bounds,size,text,-1,self.ReferenceObjectName)
end
function UIController.DrawMysteryMeasurement(self: any,camera: Camera?,bounds: CFrame?,size: Vector3?,estimate: number?,userId: number?,playerColor: Color3?)
 -- Optional metres come only from the owner's visible selection, never the answer.
 local hasEstimate=estimate~=nil and estimate==estimate and estimate>0 and estimate<math.huge
 self.EstimatedHeight.Visible=hasEstimate
 self.MysteryMeasurementText.Visible=not hasEstimate
 local label=if hasEstimate then self.EstimatedHeight else self.MysteryMeasurementText
 local text=if hasEstimate then string.format("%.2fm",estimate :: number) else "???m"
 local labelBounds=drawMeasurement(self,self.MysteryMeasurementRoot,self.MysteryMeasurementDots,label,camera,bounds,size,text,1,self.MysteryObjectName,if self.MeasurementRoot and self.MeasurementRoot.Visible then self.ReferenceLabelBounds else nil,userId~=nil)
 -- Results only: the player's round headshot sits below the object name/metres and above the ruler cap.
 local mugshot=self.MysteryPlayerMugshot
 if mugshot then
  local show=labelBounds~=nil and userId~=nil
  mugshot.Visible=show
  if show then
   local extent=labelBounds.ProfileExtent
   BotPortrait.Set(mugshot,userId,userId,self.Config)
   mugshot.Size=UDim2.fromOffset(extent,extent)
   mugshot.Position=UDim2.fromOffset(labelBounds.X+labelBounds.Width/2-extent/2,labelBounds.ProfileY)
   -- The circle's fill is that player's own reveal colour, showing through behind the headshot.
   mugshot.BackgroundColor3=playerColor or Color3.new(1,1,1)
   mugshot.BackgroundTransparency=0
  end
 end
end
function UIController.EnableLock(self: any,enabled: boolean)
 self.LockIn.Active,self.LockIn.Selectable,self.LockIn.AutoButtonColor=enabled,enabled,enabled
 Style.Caption(self.LockIn,if enabled then "LOCK IN!" else "LOCKED")
 self.LockIn.BackgroundTransparency=if enabled then 0 else 0.4
end
function UIController.BlocksObjectDrag(self: any,position: Vector3): boolean
	for _,node in self.PlayerGui:GetGuiObjectsAtPosition(position.X,position.Y) do
		if node==self.ObjectResizeIndicator or node:IsDescendantOf(self.ObjectResizeIndicator) then continue end
		if node:IsA("GuiButton") or node:IsA("TextBox") or node:IsA("ScrollingFrame") or node.Active or node.BackgroundTransparency<1 then return true end
	end
	return false
end
function UIController.EnableHint(self: any,enabled: boolean)
 self.HintButton.Active,self.HintButton.Selectable=enabled,enabled
 self.HintButton.BackgroundTransparency=if enabled then 0 else 0.45
 self.HintWobble:SetEnabled(enabled)
end
-- Four permanent slots are available to copy before a match starts.
function UIController.CreateResultSlots(self: any)
 self.Results.Size,self.Results.Position=UDim2.fromScale(1,1),UDim2.new()
 self.Results.ZIndex=50
 self.Results.BackgroundColor3=Color3.fromRGB(16,19,30)
 self.Results.BorderSizePixel=0
 self.ResultSlots={}
 self.ActualSize=Style.Text(self.Results,"ActualSize","",UDim2.fromScale(0.88,0.14),UDim2.fromScale(0.06,0.06),46)
 self.ActualSize.ZIndex=52;self.ActualSize.Visible=false
 self.ResultAnnouncement=Style.Text(self.Results,"GuessAnnouncement","",UDim2.fromScale(0.88,0.065),UDim2.fromScale(0.06,0.135),36)
 self.ResultAnnouncement.ZIndex=53
 self.AnnouncementScale=Style.Node(self.ResultAnnouncement,"AnnouncementScale","UIScale")
 for index=1,4 do
  local panel=Style.Frame(self.Results,"PlayerResult"..index,UDim2.fromScale(0.4,0.7),UDim2.new(),Color3.fromRGB(24,27,39),1)
  panel.BackgroundTransparency=1;panel.ZIndex=51;panel.Visible=false
  panel:FindFirstChildOfClass("UIStroke").Transparency=1
  local scale=Style.Node(panel,"ResultMotionScale","UIScale")
  local portrait=Style.Node(panel,"Mugshot","ImageLabel")
  portrait.AnchorPoint,portrait.Size,portrait.Position=Vector2.new(0.5,0),UDim2.fromScale(0.72,0.43),UDim2.fromScale(0.5,0)
  portrait.BackgroundTransparency,portrait.ScaleType,portrait.ZIndex=1,Enum.ScaleType.Fit,52
  local name=Style.Text(panel,"PlayerName","Player",UDim2.fromScale(1,0.1),UDim2.fromScale(0,0.45),30)
  local caption=Style.Text(panel,"AccuracyCaption","ACCURACY",UDim2.fromScale(1,0.07),UDim2.fromScale(0,0.57),20)
  local percent=Style.Text(panel,"AccuracyPercent","0 / 100",UDim2.fromScale(1,0.23),UDim2.fromScale(0,0.64),100)
	local guess=Style.Text(panel,"AcceptedGuess","",UDim2.fromScale(1,0.1),UDim2.fromScale(0,0.52),22)
  local verdict=Style.Text(panel,"Verdict","",UDim2.fromScale(1,0.1),UDim2.fromScale(0,0.89),28)
  for _,label in {name,caption,percent,verdict,guess} do label.ZIndex=52 end
  local perfect=Style.Node(panel,"PerfectEffect","Frame")
  perfect.AnchorPoint,perfect.Position,perfect.Size=Vector2.new(0.5,0.5),UDim2.fromScale(0.61,0.15),UDim2.fromScale(0.68,0.26)
  perfect.BackgroundTransparency,perfect.Visible,perfect.Active,perfect.ZIndex=1,false,false,54
  local perfectScale=Style.Node(perfect,"PerfectPopScale","UIScale");perfectScale.Scale=1
  local perfectText=Style.Text(perfect,"PerfectText","PERFECT!",UDim2.fromScale(1,1),UDim2.new(),34)
  perfectText.TextColor3,perfectText.ZIndex=Style.Gold,56
  local sparks={}
  for sparkIndex=1,8 do
   local spark=Style.Node(perfect,"Sparkle"..sparkIndex,"Frame")
   spark.AnchorPoint,spark.Size,spark.BorderSizePixel=Vector2.new(0.5,0.5),UDim2.fromOffset(5,5),0
   spark.BackgroundColor3=if sparkIndex%2==0 then Color3.new(1,1,1) else Style.Gold
   spark.ZIndex,spark.Active,spark.Rotation=55,false,45
   sparks[sparkIndex]=spark
  end
  table.insert(self.ResultSlots,{Panel=panel,Scale=scale,Portrait=portrait,Name=name,Percent=percent,Verdict=verdict,Guess=guess,Caption=caption,Index=index,Perfect=perfect,PerfectScale=perfectScale,PerfectText=perfectText,PerfectSparks=sparks})
 end
end
function UIController.FocusResults(self: any)
 for _,gui in Style.Roots(self.PlayerGui) do
  if (gui:IsA("ScreenGui") or gui:IsA("BillboardGui") or gui:IsA("GuiObject")) and gui~=self.Gui and gui.Name~="ScaleSceneTransition" and gui.Name~="ScaleStartupLoading" then
   local known=false
   for _,entry in self.HiddenGuis do if entry.Gui==gui then known=true;break end end
   if not known then table.insert(self.HiddenGuis,{Gui=gui,Enabled=Style.IsEnabled(gui)}) end
   if Style.IsEnabled(gui) then Style.SetVisible(gui,false) end
  end
 end
 if not self.CoreHidden and self.StarterGui then
  self.CoreHidden=true
  -- Keep Roblox chat usable during the legacy results presentation too.
  for _,kind in {Enum.CoreGuiType.Backpack,Enum.CoreGuiType.PlayerList,Enum.CoreGuiType.Health} do
   pcall(function() self.HiddenCore[kind]=self.StarterGui:GetCoreGuiEnabled(kind);self.StarterGui:SetCoreGuiEnabled(kind,false) end)
  end
 end
end
function UIController.EndResults(self: any)
 for _,item in self.ResultSlots do item.Perfect.Visible=false;item.Name.Visible=true end
 for _,entry in self.HiddenGuis do
  if entry.Gui.Parent then
   local requested=entry.Gui:GetAttribute("RuntimeEnabled")
   Style.SetVisible(entry.Gui,if requested~=nil then requested else entry.Enabled)
  end
 end
 table.clear(self.HiddenGuis)
 for kind,enabled in self.HiddenCore do pcall(function() self.StarterGui:SetCoreGuiEnabled(kind,enabled) end) end
 table.clear(self.HiddenCore);self.CoreHidden=false
 for _,item in self.ResultExit or {} do if item.Node.Parent then item.Node.Position=item.Position;item.Node.Visible=item.Visible;Style.RestorePose(item.Node) end end
 self.ResultExit=nil;self.Results.Visible=false
end
function UIController.BuildResults(self: any,s: any)
 self.Results.Visible=s.State=="ROUND_REVEAL" and s.Reveal~=nil and s.Reveal.Results~=nil
 if not self.Results.Visible then return end
 if not self.ResultExit then
  self.ResultExit={}
  for _,node in self.Gui:GetChildren() do
   if node:IsA("GuiObject") and node~=self.Results and node~=self.MeasurementRoot and node~=self.MysteryMeasurementRoot then
    Style.SavePose(node)
    table.insert(self.ResultExit,{Node=node,Position=node.Position,Visible=node.Visible})
   end
  end
 end
 self:FocusResults()
 local key=s.MatchId..":"..s.RoundId
 if self.ResultsKey==key then return end
 self.ResultsKey=key;self.ResultCards={};self.ResultOwnUserId=s.YourUserId
 local entries=table.clone(s.Reveal.Results)
 -- The local participant is leftmost. Eliminated spectators retain seat order.
 for index,entry in entries do if entry.UserId==s.YourUserId then table.remove(entries,index);table.insert(entries,1,entry);break end end
 for index,item in self.ResultSlots do
  item.Perfect.Visible=false;item.Name.Visible=true
  local entry=entries[index];item.Panel.Visible=entry~=nil
  if not entry then continue end
  item.Entry=entry;item.Name.Text=entry.Name
	item.Color=Color3.fromRGB(table.unpack(self.Config.ResultColor(index,#entries)))
	item.Guess.Text=string.format("Guess: %.2f m",entry.Guess)
  local portraitUserId=entry.AvatarUserId or entry.UserId
  BotPortrait.Set(item.Portrait,entry.UserId,portraitUserId,self.Config)
  item.Percent.Text,item.Verdict.Text="0 / 100",""
  table.insert(self.ResultCards,item)
 end
 self.ActualSize.Text=RevealPresentation.SizeCaption(s.Target.DisplayName,s.Reveal.Actual)
 self.ActualResultText=self.ActualSize.Text
 self.ReferenceResultText=string.format("%s / %.2fm",s.Reference.DisplayName,s.ReferenceMeters)
 self.ActualSize.TextColor3=Color3.fromRGB(185,193,205)
 self.ActualSize.Visible=true
end
function UIController.PaintResults(self: any,view: any)
 if not self.Results.Visible then return end
 self:FocusResults()
 local exit=math.clamp(view.Age/self.Config.ResultHudExitSeconds,0,1)
 for _,item in self.ResultExit or {} do
  item.Node.Visible=item.Visible and exit<1
  local pos=item.Position
  item.Node.Position=pos:Lerp(UDim2.new(pos.X.Scale,pos.X.Offset,if pos.Y.Scale<0.5 then -1 else 1.5,pos.Y.Offset),1-(1-exit)^5)
 end
 self.Results.BackgroundTransparency=1
 self.ActualSize.Visible=true
	if not Style.Authoring then self.ActualSize.Size,self.ActualSize.Position=UDim2.fromScale(0.88,0.075),UDim2.fromScale(0.06,0.04) end
 -- Keep the announced roster aligned with the already-created model sequence
 -- if a departure produces another snapshot during this reveal.
 local sequence=RevealPresentation.Sequence(view.Age,self.Config,#self.ResultCards)
 self.ActualSize.Text=if sequence.Phase=="REFERENCE" then self.ReferenceResultText else self.ActualResultText
 local announcement=math.clamp(sequence.SlotAge/self.Config.ResultAnnounceSeconds,0,1)
 self.AnnouncementScale.Scale=if sequence.Index then 0.86+0.14*(1-(1-announcement)^3) else 1
 local active=sequence.Index and self.ResultCards[sequence.Index]
 self.ResultAnnouncement.Text=if active then (if active.Entry.UserId==self.ResultOwnUserId then "YOUR GUESS" else string.upper(active.Entry.Name).."'S GUESS") elseif sequence.Phase=="REFERENCE" then "Compare with this!" else self.ActualResultText
 self.ResultAnnouncement.TextColor3=if active then active.Color else Color3.new(1,1,1)
 local count=#self.ResultCards
 local compact=self.Results.AbsoluteSize.X>0 and self.Results.AbsoluteSize.X<650
 local columns=if compact and count>2 then 2 else math.max(1,count)
 local rows=math.ceil(count/columns)
 local width=0.9/columns
 local height=if rows==2 then 0.16 else 0.22
 for index,item in self.ResultCards do
  local start=self.Config.RevealIntroSeconds()+(index-1)*self.Config.RevealSlotSeconds()+self.Config.ResultAnnounceSeconds
  local progress=math.clamp((view.Age-start)/self.Config.ResultGrowSeconds,0,1)
  local entry=item.Entry
  local accuracy=math.clamp(math.floor(entry.Accuracy+(if entry.Passed~=nil then 1e-7 else 0.5)),0,100)
  local amount=if progress>=1 then accuracy else math.min(math.floor(accuracy*(1-(1-progress)^2)),math.max(0,accuracy-1))
  local tie=view.Outcome=="TIE"
  local color=if progress<1 then Color3.new(1,1,1) elseif tie then Color3.fromRGB(255,221,70) elseif entry.Loser then Color3.fromRGB(255,65,85) elseif entry.Passed or entry.Closest then Color3.fromRGB(65,255,113) else Color3.new(1,1,1)
  item.Panel.Visible=sequence.Index~=nil and index<=sequence.Index
	item.Panel.BackgroundTransparency=0.28
	local border=item.Panel:FindFirstChildOfClass("UIStroke");border.Color=item.Color;border.Transparency=0.1
	item.Portrait.ImageColor3=Color3.new(1,1,1)
	item.Portrait.Size,item.Portrait.Position=UDim2.fromScale(0.18,0.3),UDim2.fromScale(0.12,0.05)
	item.Name.Size,item.Name.Position=UDim2.fromScale(0.72,0.18),UDim2.fromScale(0.25,0.06)
	item.Name.TextColor3=item.Color
	item.Guess.Size,item.Guess.Position=UDim2.fromScale(0.92,0.15),UDim2.fromScale(0.04,0.3)
	item.Guess.TextColor3=item.Color
	item.Caption.Visible=false
	item.Percent.Size,item.Percent.Position=UDim2.fromScale(0.92,0.32),UDim2.fromScale(0.04,0.46)
	item.Verdict.Size,item.Verdict.Position=UDim2.fromScale(0.92,0.16),UDim2.fromScale(0.04,0.81)
  item.Percent.Text=tostring(amount).." / 100";item.Percent.TextColor3=item.Color
  item.Verdict.Text=if progress<1 then "" elseif tie then "TIE" elseif entry.Loser then "KEEP PRACTISING!" elseif entry.Closest then "CLOSEST!" else "NICE TRY!"
  if progress>=1 and entry.Passed~=nil then
   item.Verdict.Text=if not entry.Passed then "BELOW TARGET" elseif (entry.HeartDelta or 0)>0 then "GREAT GUESS STREAK!" else "TARGET REACHED!"
  end
  item.Verdict.TextColor3=color
  local enter=math.clamp((view.Age-start+self.Config.ResultAnnounceSeconds)/self.Config.ResultCardEnterSeconds,0,1)
  local x=(index-1)%columns;local row=math.floor((index-1)/columns)
  item.Panel.Size=UDim2.fromScale(width-0.02,height)
  item.Panel.Position=UDim2.fromScale(0.06+x*width,(if rows==2 then 0.63 else 0.74)+row*0.18+0.12*(1-enter)^5)
  if Style.Authoring then
   for _,node in {item.Panel,item.Portrait,item.Name,item.Guess,item.Percent,item.Verdict} do
    local pose=Style.Authoring.Pose(node);node.Size,node.Position,node.AnchorPoint=pose.Size,pose.Position,pose.AnchorPoint
   end
   item.Panel.Position+=UDim2.fromScale(0,0.12*(1-enter)^5)
  end
  item.Scale.Scale=0.85+0.15*(1-(1-enter)^3)
  -- Celebrate the authoritative, unrounded score only once its final number lands.
  -- Server-relative age keeps duplicate/late snapshots from restarting the burst.
  local perfectAge=view.Age-start-self.Config.ResultGrowSeconds
  local perfect=item.Panel.Visible and entry.Accuracy>=PERFECT_ACCURACY and entry.Accuracy<=100 and perfectAge>=0 and perfectAge<PERFECT_SECONDS
  item.Perfect.Visible=perfect;item.Name.Visible=not perfect
  if perfect then
   local pop=math.clamp(perfectAge/0.3,0,1);local p=pop-1
   local opacity=math.min(1,perfectAge/0.08)*(1-math.clamp((perfectAge-1.0)/0.4,0,1))
   item.PerfectScale.Scale=0.75+0.25*(1+2.70158*p*p*p+1.70158*p*p)
   item.PerfectText.TextTransparency=1-opacity
   item.PerfectText.TextStrokeTransparency=1-opacity
   local travel=1-(1-math.clamp(perfectAge/0.8,0,1))^3
   for sparkIndex,spark in item.PerfectSparks do
    local angle=(sparkIndex-1)*math.pi/4
    spark.Position=UDim2.fromScale(0.5+math.cos(angle)*(0.3+0.2*travel),0.5+math.sin(angle)*(0.2+0.35*travel))
    spark.Rotation=45+travel*100
    spark.BackgroundTransparency=1-opacity*(1-math.clamp(perfectAge/1.0,0,1))
   end
  end
 end
end
function UIController.Hide(self: any) self:EndResults();self.HintWobble:SetEnabled(false);Style.SetEnabled(self.Gui,false);Style.SetEnabled(self.StatusGui,false);self.LockAnnouncement.Visible=false;self.HintPanel.Visible=false;self.MeasurementRoot.Visible=false;self.MysteryMeasurementRoot.Visible=false;self:SetObjectHover(nil) end
function UIController.SetGuess(self: any,_meters: number,alpha: number)
 self.SelectedGuessMeters=_meters
 self.DesiredAlpha,self.DisplayAlpha=alpha,alpha
 self.Knob.Position=UDim2.fromScale(0.15,0.9-0.8*math.clamp(alpha,0,1))
end
function UIController.Step(self: any,dt: number)
 if self.DesiredAlpha then self.DisplayAlpha+=(self.DesiredAlpha-self.DisplayAlpha)*(1-math.exp(-self.Config.ScaleSmoothSpeed*dt));self.Knob.Position=UDim2.fromScale(0.15,0.9-0.8*math.clamp(self.DisplayAlpha,0,1)) end
 self.HintWobble:Step(dt)
end
function UIController.ShowStatus(self: any,text: string)
 self:EndResults()
 if Style.Authoring then
  if not self.StatusHidden then
   self.StatusHidden={}
   for _,node in self.Gui:GetChildren() do if node:IsA("GuiObject") and node~=self.StatusGui then self.StatusHidden[node]=node.Visible;node.Visible=false end end
  end
  Style.SetEnabled(self.Gui,true)
 else Style.SetEnabled(self.Gui,false) end
 Style.SetEnabled(self.StatusGui,true);self.Status.Text=text;self:SetObjectHover(nil)
end
function UIController.Show(self: any,s: any)
 if self.StatusHidden then for node,visible in self.StatusHidden do if node.Parent then node.Visible=visible end end;self.StatusHidden=nil end
 local state=s.State
 self.ReferenceObjectName.Text=Style.MeasurementName(if s.Reference then s.Reference.DisplayName else nil)
 self.MysteryObjectName.Text=Style.MeasurementName(if s.Target then s.Target.DisplayName else nil)
 if state~="GUESSING" or not s.CanGuess then self:SetObjectHover(nil) end
 self.MeasurementRoot.Visible=false
 self.MysteryMeasurementRoot.Visible=false
 self.Help.Visible=state=="GUESSING" and s.CanGuess==true
 if not Style.Authoring then self.Guess.Size=UDim2.fromScale(0.94,if self.Help.Visible then 0.5 else 0.8) end
 self.HintPanel.Visible=false
 self.HintButton.Visible=state=="GUESSING" and s.CanGuess==true
 self.PetNotice.Visible=self.HintButton.Visible and s.PetNotice~=nil and s.PetNotice~=""
 self.PetNotice.Text=s.PetNotice or ""
 self:EnableHint(s.CanBuyHint==true)
 Style.Caption(self.HintButton,"Hint")
 if state~="ROUND_REVEAL" then self:EndResults() end
 self.ChainStatus.Visible=s.Mode=="Endless" and state~="MATCH_END"
 if self.ChainStatus.Visible then self.ChainStatus.Text="3 x 90% = +1 HEART / "..(s.AccuracyStreak or 0).."/3\nNEXT REWARD: ROUND "..(s.NextMilestone or 5) end
 if state=="IDLE" and s.Completion then
  local result=s.Completion
  local heading=if result.Cancelled then "MATCH CANCELLED" else "GAME OVER\nMATCH COMPLETE"
  self:ShowStatus(heading..(if result.Cancelled then "\n"..(result.Message or "") else "\n"..result.Result)..(if (result.Reward or 0)>0 then "\n+$"..result.Reward else ""))
  return
 end
 if state=="IDLE" or state=="EMPTY" or state=="RESETTING" then self:Hide();return end
 if state=="WAITING_FOR_PLAYER" then self:ShowStatus(s.Message or "Waiting for players...");return end
 if state=="VOTING" or state=="PRIZE_ROLL" or state=="COUNTDOWN" or state=="GO" then self:Hide();return end
 if state=="MATCH_END" then self:Hide();return end
 Style.SetEnabled(self.Gui,true);Style.SetEnabled(self.StatusGui,false);self.Round.Parent.Visible=true;self.YourHearts[1].Parent.Visible=s.Mode~="BestOfFive";self.Round.Text="ROUND "..s.Round
 if state=="GUESSING" then self.Round.Text=if s.CanGuess then "YOUR TURN  /  "..(s.TurnIndex or 1).." OF "..(s.TurnCount or 2) else (s.ActivePlayerName or "Player").." is guessing" end
 if s.Mode=="Endless" then self.Round.Text="CHAIN "..s.Round.." / NEED "..s.RequiredAccuracy.."%" end
 for i,icon in self.YourHearts do icon.Visible=i<=s.YourHearts end
 for i,icon in self.OpponentHearts do icon.Visible=i<=s.OpponentHearts end
 self.OpponentPanel.Visible=not s.Participants and s.Mode~="BestOfFive";self.Scoreboard.Visible=s.Participants~=nil and s.Mode~="BestOfFive"
 if s.Participants then local lines={};for _,p in s.Participants do table.insert(lines,p.Name.."  "..string.rep("♥",p.Hearts)) end;self.Scoreboard.Text=table.concat(lines,"\n") end
 local atTable=state=="TABLE_RETURN" or state=="TABLE_REACTION"
 self.Reference.Parent.Visible,self.Target.Parent.Visible=not atTable,not atTable
 self.Bottom.Visible,self.Slider.Visible=true,state=="GUESSING" and s.CanGuess==true
 self.LockIn.Visible=state=="GUESSING" and s.CanGuess==true
 Style.Caption(self.Plus,if s.GuessMaximum then string.format("+\n%.3g m",s.GuessMaximum) else "+")
 Style.Caption(self.Minus,if s.GuessMinimum then string.format("−\n%.3g m",s.GuessMinimum) else "−")
 self.LockAnnouncement.Visible=state=="TURN_LOCKED"
 if state=="TURN_LOCKED" then
  self.LockedTitle.Text=(s.ActivePlayerName or "Player").." locked in!"
  self.LockedHint.Text=(if s.LockedAutomatically then "Time's up / " else "")..(if s.NextPlayerName then "Up next: "..s.NextPlayerName else "All guesses locked / Results next")
 end
 self:BuildResults(s)
 self.AccuracyTrack.Visible=false
 if atTable then
  self.Time.Text="RESULT"
  self:PaintReveal(RevealPresentation.Evaluate(s,(s.Reveal.StartedAt or 0)+self.Config.RevealSeconds,self.Config),0)
  return
 end
 self.Reference.Text=string.format("%s / %.2fm",s.Reference.DisplayName,s.ReferenceMeters)
 self.Target.Text=s.Target.DisplayName.." / ???"
 if s.Reveal and state~="ROUND_REVEAL" then self.Target.Text=string.format("%s / %.2fm",s.Target.DisplayName,s.Reveal.Actual)
 else
  self.Guess.Text=if state=="TURN_LOCKED" then "Guess locked" elseif state=="GUESSING" and not s.CanGuess then (s.ActivePlayerName or "Player").."'s size" else "Your size";self.Guess.TextColor3=Color3.new(1,1,1);self.Bottom.BackgroundColor3=Color3.fromRGB(24,27,39);self.Bottom.BackgroundTransparency=0.55
  self.BottomStroke.Color=Color3.fromRGB(28,22,32);self.Pulse.Scale=1;self.LastPercent,self.LastPhase=nil,nil
 end
end
function UIController.PaintReveal(self: any,view: any,now: number)
 if not view then return end
 local outcomeColor=if view.Outcome=="WON" or view.Outcome=="SAFE" or view.Outcome=="HEALED" then Color3.fromRGB(65,255,113) elseif view.Outcome=="LOST" then Color3.fromRGB(255,65,85) else Color3.fromRGB(255,221,70)
 local color=if view.Phase=="COUNT" then Color3.fromRGB(100,232,255) else outcomeColor
 if self.LastPercent~=view.Percent or self.LastPhase~=view.Phase then self.PulseAt=now end
 self.LastPercent,self.LastPhase=view.Percent,view.Phase
 self.Guess.Text=view.Text;self.Guess.TextColor3=if view.Phase=="COUNT" then Color3.new(1,1,1) else color
 self.BottomStroke.Color=color;self.AccuracyFill.BackgroundColor3=color
 self.AccuracyFill.Size=UDim2.fromScale(view.Percent/100,1)
 self.AccuracyTrack.Visible=view.Phase=="COUNT"
 self.Bottom.BackgroundColor3=Color3.fromRGB(24,27,39):Lerp(color,if view.Phase=="RESULT" then 0.2 else 0.05)
 self.Bottom.BackgroundTransparency=if view.Phase=="RESULT" then 0.28 else 0.5
 local age=math.max(0,now-(self.PulseAt or now))
 self.Pulse.Scale=1+(if view.Phase=="RESULT" then 0.16 else 0.035)*math.exp(-5*age)
end
function UIController.TickHint(self: any,s: any,now: number)
 local hint=s and s.State=="GUESSING" and s.CanGuess and s.Hint
 local active=hint and now<hint.ExpiresAt and now<s.Deadline
 self.HintPanel.Visible=active==true
 if not active then return end
 self.PetNotice.Visible=false
 local remaining=math.max(0,hint.ExpiresAt-now)
 local age=math.max(0,now-(hint.StartedAt or hint.ExpiresAt-(self.Config.HintSeconds or 10)))
 local opacity=math.min(1,age/0.7,remaining/0.8)
 local color=Color3.fromRGB(table.unpack(self.Config.HintColor))
 self.HintTitle.Text=string.format("SIZE HINT / %.1fs",remaining)
 self.HintGuidance.Text=self.Config.HintMessage.Title
 self.HintGuidance.TextColor3=color;self.HintProgress.BackgroundColor3=color
 self.HintProgress.Size=UDim2.fromScale(0.92*math.clamp(remaining/(self.Config.HintSeconds or 10),0,1),0.045)
 self.HintProgress.BackgroundTransparency=1-opacity
 self.HintMotion.Scale=0.88+0.12*(1-(1-math.clamp(age/0.8,0,1))^3)
 self.HintPanel.BackgroundTransparency=1-0.72*opacity
 for _,label in {self.HintTitle,self.HintGuidance} do label.TextTransparency,label.TextStrokeTransparency=1-opacity,1-opacity end
 local stroke=self.HintPanel:FindFirstChildOfClass("UIStroke");if stroke then stroke.Color=color;stroke.Transparency=1-opacity end
end
function UIController.Tick(self: any,s: any,now: number)
 self:TickHint(s,now)
 Style.Caption(self.HintButton,"Hint")
 if not s or not s.Deadline then return end
 if s.State=="IDLE" and s.Completion then
  if now>=s.Deadline then self:Hide() end
  return
 end
 local seconds=math.max(0,math.ceil(s.Deadline-now))
 if s.State=="GUESSING" then self.Time.Text=seconds.."s"
 elseif s.State=="TURN_LOCKED" then
  self.Time.Text="LOCKED IN"
  local age=math.max(0,now-(s.LockedAt or s.Deadline-self.Config.LockInSeconds))
  local enter=math.clamp(age/self.Config.LockEnterSeconds,0,1);local x=enter-1
  local exit=math.clamp((s.Deadline-now)/self.Config.LockExitSeconds,0,1)
  local opacity=math.min(1,age/(self.Config.LockEnterSeconds*0.5))*exit
  self.LockedScale.Scale=0.85+0.15*(1+2.70158*x*x*x+1.70158*x*x)
  self.LockAnnouncement.Position=(if Style.Authoring then Style.Authoring.Pose(self.LockAnnouncement).Position else UDim2.fromScale(0.5,0.34))+UDim2.fromScale(0,0.035*(1-enter)^3-0.015*(1-exit))
  self.LockAnnouncement.BackgroundTransparency=1-0.78*opacity
  local stroke=self.LockAnnouncement:FindFirstChildOfClass("UIStroke");stroke.Color=Color3.fromRGB(65,255,113);stroke.Transparency=1-opacity
  for _,label in {self.LockedTitle,self.LockedHint} do label.TextTransparency,label.TextStrokeTransparency=1-opacity,1-opacity end
  self.LockedLine.Size=UDim2.fromScale(0.9*math.clamp(age/self.Config.LockInSeconds,0,1),0.035);self.LockedLine.BackgroundTransparency=1-opacity
 elseif s.State=="ROUND_INTRO" then self.Time.Text="GET READY"
 elseif s.State=="ROUND_REVEAL" then self.Time.Text="THE RESULTS" end
 local hit=s.State=="TABLE_REACTION" and s.Reveal and s.Reveal.Result=="ROUND LOST!" and s.HeartAppliedAt
 local age=if hit then now-s.HeartAppliedAt else 10
 self.Flash.BackgroundTransparency=if age>=0 and age<self.Config.HeartFlashSeconds then 1-0.28*(1-age/self.Config.HeartFlashSeconds)*(0.6+0.4*math.abs(math.cos(age/self.Config.HeartFlashSeconds*math.pi*2))) else 1
 if s.Reveal then
  local view=RevealPresentation.Evaluate(s,now,self.Config)
  self:PaintReveal(view,now)
  self:PaintResults(view)
  return view
 end
end
function UIController.Destroy(self: any) self:EndResults();self.HintWobble:Destroy();Style.Dispose(self.Gui);Style.Dispose(self.StatusGui) end
return UIController

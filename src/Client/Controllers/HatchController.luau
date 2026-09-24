--!strict
local Style = require(script.Parent.UIStyle)
local HatchController = {}
HatchController.__index = HatchController
local SPIN_SECONDS = 2.4
local SPIN_TURNS = 3
local POP_SECONDS = 0.7
local DOT_SECONDS = 0.4 -- how long each dot of "Hatching..." shows
local OPENED_SECONDS = 1.3 -- OPENED! shows this long before the item name
local VIEWPORT_GROW = 0.14 -- the reward viewport frame slowly grows this much while spinning, then snaps back on reveal
local VIEWPORT_SNAP_SECONDS = 0.2
local PET_MODEL_EXTENT = 2.5 * 1.5 -- the revealed pet model is shown at 1.5x its previous display size
local SPIN_RATE = 0.35 * 2 -- the revealed pet spins at 2x its previous speed
local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function backOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2
end
local function backIn(t: number): number
	t = math.clamp(t, 0, 1)
	return 2.70158 * t ^ 3 - 1.70158 * t ^ 2
end
function HatchController.SetupViewport(viewport: ViewportFrame): Part
	local existing=viewport:FindFirstChild("RewardCamera")
	local camera=Style.Node(viewport,"RewardCamera","Camera")
	if not existing then camera.CFrame,camera.FieldOfView=CFrame.new(0,0,7),40 end
	viewport.CurrentCamera=camera
	local egg=Style.Node(viewport,"RewardModel","Part")
	egg.Anchored,egg.Material=true,Enum.Material.SmoothPlastic
	egg.CanCollide,egg.CanTouch,egg.CanQuery=false,false,false
	egg.Transparency=0
	local stale=viewport:FindFirstChild("PetModel");if stale then stale:Destroy() end
	return egg
end
function HatchController.new(playerGui: PlayerGui, starterGui: StarterGui, catalog: any, shop: any, equip: any)
	if Style.Authoring then
		-- The grid layout (HatchContainer.Template) opens one or ten items; the older single-item layout keeps its binder.
		local Grid=require(script.Parent.HatchGridController)
		if Grid.Matches(Style.Authoring.Overlays:FindFirstChild("HatchReveal")) then return Grid.new(playerGui,starterGui,catalog,shop,equip) end
		return Style.Authoring.Hatch(HatchController,playerGui,starterGui,catalog,shop,equip)
	end
	local self: any = setmetatable({ PlayerGui = playerGui, StarterGui = starterGui, Catalog = catalog, Shop = shop, Equip = equip, Hidden = {}, Core = {}, Confetti = {} }, HatchController)
	local gui = Style.Node(playerGui,"ScaleHatchReveal","ScreenGui");gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder, gui.Enabled, gui.Parent = "ScaleHatchReveal", false, true, 100, false, playerGui;Style.SetEnabled(gui,false);self.Gui = gui
	local dim = Style.Node(gui,"Backdrop","Frame");dim.Size, dim.BackgroundColor3, dim.BackgroundTransparency, dim.Parent = UDim2.fromScale(1,1), Color3.fromRGB(12,8,30), 0.35, gui
	local viewport = Style.Node(gui,"RewardViewport","ViewportFrame");viewport.Size, viewport.Position, viewport.BackgroundTransparency, viewport.Parent = UDim2.fromScale(0.8,0.74), UDim2.fromScale(0.1,0.05), 1, gui
	viewport.Ambient, viewport.LightColor = Color3.new(0.7,0.7,0.7), Color3.new(1,1,1)
	self.Egg=HatchController.SetupViewport(viewport)
	-- A cool touch while it spins: the whole viewport frame slowly grows, then snaps back the instant it opens.
	self.ViewportScale=Style.Node(viewport,"RewardViewportScale","UIScale")
	self.Title=Style.Text(gui,"Title","Hatching...",UDim2.fromScale(0.9,0.12),UDim2.fromScale(0.05,0.06),62)
	self.Rarity=Style.Text(gui,"Rarity","",UDim2.fromScale(0.9,0.09),UDim2.fromScale(0.05,0.72),36)
	self.Continue=Style.Button(gui,"Continue","Continue",UDim2.fromScale(0.25,0.09),UDim2.fromScale(0.53,0.86))
	self.EquipButton=Style.Button(gui,"Equip","Equip pet",UDim2.fromScale(0.25,0.09),UDim2.fromScale(0.22,0.86),Style.Purple)
	for _,child in gui:GetChildren() do if child.Name:match("^Confetti%d+$") then child:Destroy() end end
	self.Continue.Visible,self.EquipButton.Visible=false,false
	self.Connections={self.Continue.Activated:Connect(function() if self.Revealed then self:Stop() end end),self.EquipButton.Activated:Connect(function() if self.Revealed then local id=self.Reward.PetId;self:Stop();self.Equip(id) end end)}
	return self
end
function HatchController.Start(self: any, reward: any,progress: any?)
	self:Stop();self.Reward,self.Age,self.Revealed=reward,0,false
	Style.Play("SpinStart")
	self.PetProgress=progress or {}
	self.Hidden={};self.Core={}
	for _,gui in Style.Roots(self.PlayerGui) do if (gui:IsA("ScreenGui") or gui:IsA("GuiObject")) and gui~=self.Gui then self.Hidden[gui]=Style.IsEnabled(gui);Style.SetVisible(gui,false) end end
	for _, kind in {Enum.CoreGuiType.Backpack,Enum.CoreGuiType.PlayerList,Enum.CoreGuiType.Health} do
		pcall(function() self.Core[kind]=self.StarterGui:GetCoreGuiEnabled(kind);self.StarterGui:SetCoreGuiEnabled(kind,false) end)
	end
	local container=self.Shop.Containers[reward.Container or "Egg"]
	self.Egg.Shape=if container.Shape=="Egg" then Enum.PartType.Ball else Enum.PartType.Block
	self.Egg.Size=if container.Shape=="Egg" then Vector3.new(2.4,3,2.4) else Vector3.one*2.5
	self.BaseSize=self.Egg.Size;self.Egg.Color=if container.Shape=="Egg" then Color3.fromRGB(255,236,174) else Style.Purple
	-- Mystery blocks show their real lucky block design in the viewport instead of the plain cube.
	local design=container.Shape=="Block" and self.Shop.BlockPreviewModels and self.Shop.BlockPreviewModels[reward.Container or ""]
	local assets=design and Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local pack=assets and assets:FindFirstChild("LuckyBlocks")
	local source=pack and pack:FindFirstChild(design)
	if source and Style.BlockVisual then
		self.BoxModel=Style.BlockVisual.Create(source,self.Egg.Parent)
		if self.BoxModel then self.Egg.Transparency=1;self.BoxScale=self.BoxModel:GetScale() end
	end
	if self.ViewportScale then self.ViewportScale.Scale=1 end
	self.Title.Text,self.Rarity.Text="Hatching.",""
	for _,label in {self.Title,self.Rarity} do
		local gradient=label:FindFirstChild("RarityGradient");if gradient then if Style.Authoring then gradient.Enabled=false else gradient:Destroy() end end
		label.TextColor3=Color3.new(1,1,1)
	end
	-- The reward viewport's outline only appears once the item is revealed.
	if self.RewardStroke then self.RewardStroke.Enabled=false end
	self.Continue.Visible,self.EquipButton.Visible=false,false;Style.SetEnabled(self.Gui,true)
end
function HatchController.Step(self: any, dt: number)
	if not self.Reward then return end
	self.Age+=dt;local age=self.Age
	if age<Style.Pacing.HatchSeconds then
		-- "Hatching." "Hatching.." "Hatching..." while the box spins.
		self.Title.Text="Hatching"..string.rep(".",math.floor(age/DOT_SECONDS)%3+1)
		-- Three full turns that start and end slowly, then the box shrinks away.
		local angle=smooth(age/SPIN_SECONDS)*SPIN_TURNS*math.pi*2
		local scale=backOut(age/0.35)
		if age>SPIN_SECONDS then scale*=1-backIn((age-SPIN_SECONDS)/(Style.Pacing.HatchSeconds-SPIN_SECONDS)) end
		scale=math.max(scale,0.001)
		if self.BoxModel then
			self.BoxModel:ScaleTo(self.BoxScale*scale);self.BoxModel:PivotTo(CFrame.Angles(0,angle,0))
		else
			self.Egg.Size=self.BaseSize*scale;self.Egg.CFrame=CFrame.Angles(0,angle,0)
		end
		-- The viewport frame itself slowly grows while it spins.
		if self.ViewportScale then self.ViewportScale.Scale=1+VIEWPORT_GROW*math.clamp(age/Style.Pacing.HatchSeconds,0,1) end
	else
		if not self.Revealed then
			self.Revealed=true
			Style.Play("EggOpen")
			if self.BoxModel then self.BoxModel:Destroy();self.BoxModel=nil end
			local item=self.Catalog.Items.Pets[self.Reward.PetId]
			self.Egg.Shape,self.Egg.Color=Enum.PartType.Block,Color3.fromRGB(table.unpack(item.Color))
			if Style.PetVisual then
				self.PetModel=Style.PetVisual.Create(Style.PetModels,self.Reward.PetId,self.Egg.Parent,PET_MODEL_EXTENT,item)
				if self.PetModel then self.Egg.Transparency=1;self.PetScale=self.PetModel:GetScale() end
			end
			-- The rarity reads like the inventory info card (its gradient takes the rarity's colours) and the reward
			-- viewport's outline lights up with only that rarity's gradient.
			Style.RarityLabel(self.Rarity,item.Rarity,self.Catalog.PetRarityStyles)
			if self.RewardStroke then Style.SelectRarityGradients(self.RewardStroke,item.Rarity);self.RewardStroke.Enabled=true end
			Style.PetRarity(self.Title,item)
			self.Continue.Visible,self.EquipButton.Visible=true,true
			for i=1,28 do
				if Style.Authoring and not self.Gui:FindFirstChild("Confetti"..i) then continue end
				local spark=Style.Text(self.Gui,"Confetti"..i,"★",UDim2.fromOffset(24,24),UDim2.fromScale(0.5,0.5),24)
				spark.Visible=true
				spark.TextColor3=Color3.fromHSV(i/28,0.75,1);table.insert(self.Confetti,{Gui=spark,Angle=i/28*math.pi*2,Speed=0.25+(i%5)*0.05})
			end
		end
		local t=age-Style.Pacing.HatchSeconds
		-- OPENED! first, then just the pet's own name (no "Lvl N" prefix, unlike PetDisplayName elsewhere).
		if t>=OPENED_SECONDS then
			local item=self.Catalog.Items.Pets[self.Reward.PetId]
			local name: string=item.Name
			self.Title.Text=(name:gsub("^Evolved%s+",""))
		else
			self.Title.Text="OPENED!"
		end
		if self.ViewportScale then self.ViewportScale.Scale=1+VIEWPORT_GROW*(1-math.clamp(t/VIEWPORT_SNAP_SECONDS,0,1)) end
		local pop=math.max(backOut(t/POP_SECONDS),0.001)
		self.Egg.Size=Vector3.one*2.5*pop;self.Egg.CFrame=CFrame.Angles(0,t*SPIN_RATE,0)
		if self.PetModel then self.PetModel:ScaleTo(self.PetScale*pop);self.PetModel:PivotTo(self.Egg.CFrame) end
		if Style.PetVisual and Style.PetVisual.Step then
			if self.PetModel then Style.PetVisual.Step(self.PetModel,t,true) end
			Style.PetVisual.StepLabel(self.Title,t);Style.PetVisual.StepLabel(self.Rarity,t)
		end
		for _,spark in self.Confetti do
			spark.Gui.Position=UDim2.fromScale(0.5+math.cos(spark.Angle)*spark.Speed*t,0.48+math.sin(spark.Angle)*spark.Speed*t+t*t*0.05)
			spark.Gui.Rotation=t*180;spark.Gui.TextTransparency=math.clamp(t/2,0,1);spark.Gui.TextStrokeTransparency=spark.Gui.TextTransparency
		end
	end
end
function HatchController.Stop(self: any)
	if self.PetModel then self.PetModel:Destroy();self.PetModel=nil end
	if self.BoxModel then self.BoxModel:Destroy();self.BoxModel=nil end
	self.Egg.Transparency=0
	if self.RewardStroke then self.RewardStroke.Enabled=false end
	self.Reward,self.Revealed=nil,false;Style.SetEnabled(self.Gui,false)
	for gui,enabled in self.Hidden do
		if gui.Parent then
			local requested=gui:GetAttribute("RuntimeEnabled")
			Style.SetVisible(gui,if requested~=nil then requested else enabled)
		end
	end;table.clear(self.Hidden)
	for kind,enabled in self.Core do pcall(function() self.StarterGui:SetCoreGuiEnabled(kind,enabled) end) end;table.clear(self.Core)
	for _,spark in self.Confetti do if Style.Authoring then spark.Gui.Visible=false else spark.Gui:Destroy() end end;table.clear(self.Confetti)
end
function HatchController.Destroy(self: any) self:Stop();for _,connection in self.Connections do connection:Disconnect() end;Style.Dispose(self.Gui) end
return HatchController

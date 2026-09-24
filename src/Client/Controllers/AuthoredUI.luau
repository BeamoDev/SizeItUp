--!strict
-- Runtime binding for the owner's single StarterGui.HUD. Never build a replacement.
local Style=require(script.Parent.UIStyle)
local MeasurementUI=require(script.Parent.MeasurementUI)
local BlockCards=require(script.Parent.AuthoredBlockCards)
local LobbyView=require(script.Parent.LobbyHUDView)
local UI={}
local poses={}
local nextPose=0
local parked={}
local function need(parent: Instance,name: string,class: string?): any
	local node=parent:FindFirstChild(name)
	assert(node and (not class or node:IsA(class)),"Missing authored UI: "..parent:GetFullName().."."..name..(if class then " ("..class..")" else ""))
	return node
end
UI.Need=need
function UI.CanFill(parent: Instance): boolean
	if not Style.BindingContent then return false end
	local panel=UI.Lobby and UI.Lobby:FindFirstChild("Panel")
	if panel then for _,name in {"Body","Tabs","InventoryTools"} do
		local root=panel:FindFirstChild(name)
		if root and (parent==root or parent:IsDescendantOf(root)) then return true end
	end end
	local blocks=UI.Overlays and UI.Overlays:FindFirstChild("BlockPreview")
	local odds=blocks and blocks:FindFirstChild("PetOdds",true)
	return odds~=nil and (parent==odds or parent:IsDescendantOf(odds))
end
function UI.Slots(parent: Instance,signature: string): {Instance}
	local slots={}
	for _,card in parent:GetChildren() do if card:IsA("GuiObject") and card:FindFirstChild(signature) and card:FindFirstChild("Preview") then table.insert(slots,card) end end
	table.sort(slots,function(a,b)
		if a.LayoutOrder~=b.LayoutOrder then return a.LayoutOrder<b.LayoutOrder end
		for _,axis in {"Y","X"} do for _,unit in {"Scale","Offset"} do if a.Position[axis][unit]~=b.Position[axis][unit] then return a.Position[axis][unit]<b.Position[axis][unit] end end end
		return a.Name<b.Name
	end)
	return slots
end
function UI.CloneTemplate(parent: Instance,name: string,className: string): Instance?
	-- Repeated data cards may clone supplied assets; never manufacture their layout.
	if not Style.BindingContent then return nil end
	if parked[parent] and parked[parent][name] then local node=parked[parent][name];parked[parent][name]=nil;node.Parent=parent;return node end
	if className~="Frame" and className~="TextButton" and className~="ImageButton" then return nil end
	local templates=parent:FindFirstChild("Templates")
	local key=parent:GetAttribute("UITemplate")
	local template=(templates and (templates:FindFirstChild(name) or templates:FindFirstChild(if type(key)=="string" then key else className.."Template")))
		or parent:FindFirstChild(name.."Template")
	if not template and (className=="Frame" or className=="TextButton") then
		local signatures=if className=="TextButton" and UI.ContentKind and UI.ContentKind:sub(1,8)=="PetShop:" then {"RarityRim","SelectedMarker","Preview"}
			elseif parent.Name=="PetOdds" then {"PetName","Chance","Preview"}
			elseif parent.Name=="Potions" then {"PotionName","PotionDuration","BuyPotion"}
			elseif parent.Name=="Cash" or parent.Name=="Keys" then {"Name","Icon","Buy"}
			elseif UI.ContentKind=="Inventory:Pets" then {"Level","XPBar","Preview"}
			elseif UI.ContentKind=="Inventory:Chairs" then {"Name","Equip","Preview"}
			elseif UI.ContentKind=="Inventory:Titles" then {"Name","Equip","TitlePreview"} else nil
		if signatures then for _,candidate in parent:GetChildren() do
			local match=candidate:IsA(className)
			for _,childName in signatures do if not candidate:FindFirstChild(childName) then match=false;break end end
			if match then template=candidate;break end
		end end
	end
	if not template or not template:IsA(className) then return nil end
	local copy=template:Clone();copy.Name=name;copy:SetAttribute("RuntimeCard",true);copy.Parent=parent
	UI.Remember(copy);for _,node in copy:GetDescendants() do UI.Remember(node) end
	return copy
end
function UI.ClearChildren(parent: Instance)
	for _,node in parent:GetChildren() do
		if node:IsA("GuiObject") then node.Visible=false
		elseif node:IsA("UIGridStyleLayout") then
			parked[parent]=parked[parent] or {};parked[parent][node.Name]=node;node.Parent=nil
		end
	end
end
function UI.RestoreParked(root: Instance)
	for parent,nodes in parked do if parent==root or parent:IsDescendantOf(root) then
		for name,node in nodes do node.Parent=parent;nodes[name]=nil end
	end end
end
function UI.Attach(playerGui: PlayerGui,starterGui: any?)
	table.clear(poses);table.clear(parked)
	local hud=playerGui:WaitForChild("HUD",15)
	-- PlayerGui only receives StarterGui once the character spawns, which can take a while on a slow connection:
	-- if HUD has still not arrived, copy it from StarterGui ourselves and discard the engine's later duplicate.
	if not hud and starterGui then
		local template=starterGui:FindFirstChild("HUD")
		if template and template:IsA("ScreenGui") then
			hud=template:Clone();hud.Parent=playerGui
			local owned=hud
			pcall(function() playerGui.ChildAdded:Connect(function(child) if child.Name=="HUD" and child~=owned then child:Destroy() end end) end)
		end
	end
	assert(hud and hud:IsA("ScreenGui"),"StarterGui.HUD must contain the authored interface"..(if hud then " (found a "..hud.ClassName..", not a ScreenGui)" else " (no HUD reached PlayerGui or StarterGui)"))
	UI.HUD=hud;UI.Game=need(hud,"Game","GuiObject");UI.Lobby=need(hud,"Lobby","GuiObject");-- The overlay frames (HatchReveal, Inventory, LuckyBlocks, Profile, Rewards, Voting...) live in HUD.Frames (older HUDs: HUD.Frame).
	local overlays=hud:FindFirstChild("Frames") or hud:FindFirstChild("Frame")
	assert(overlays and overlays:IsA("GuiObject"),"Missing authored UI: "..hud:GetFullName()..".Frames (GuiObject)")
	UI.Overlays=overlays
	need(hud,"BlackWipe","GuiObject")
	-- The old multi-step tutorial was removed; discard its obsolete local HUD clone if the place still contains it.
	local tutorial=hud:FindFirstChild("Tutorial")
	if tutorial then tutorial:Destroy() end
	Style.Authoring=UI
	for _,node in hud:GetDescendants() do UI.Remember(node) end
	hud.ResetOnSpawn=false;hud.Enabled=true
	-- Clicking a button must never draw Roblox's white selection outline around it (covers cloned cards too).
	for _,node in hud:GetDescendants() do if node:IsA("GuiButton") then node.Selectable=false end end
	pcall(function() hud.DescendantAdded:Connect(function(node) if node:IsA("GuiButton") then node.Selectable=false end end) end)
	UI.Overlays.Visible=true
	-- The friend alert moved to Lobby.Upper.InviteFrame; keep the unused old frame out of the way.
	local oldAlert=overlays:FindFirstChild("OnlineFriendAlert")
	if oldAlert and oldAlert:IsA("GuiObject") then oldAlert.Visible=false end
end
function UI.Remember(node: Instance)
	if not node:IsA("GuiObject") then return end
	local existing=poses[node:GetAttribute("RuntimePoseId")]
	if existing and existing.Node==node then return end
	local position=node.Position
	local savedScale,savedOffset=node:GetAttribute("RestPositionScale"),node:GetAttribute("RestPositionOffset")
	if savedScale and savedOffset then position=UDim2.new(savedScale.X,savedOffset.X,savedScale.Y,savedOffset.Y) end
	nextPose+=1;node:SetAttribute("RuntimePoseId",nextPose)
	poses[nextPose]={Node=node,Layout={Position=position,Size=node.Size,AnchorPoint=node.AnchorPoint,Rotation=node.Rotation}}
end
function UI.Pose(node: GuiObject): any UI.Remember(node);return poses[node:GetAttribute("RuntimePoseId")].Layout end
function UI.RestoreLayout(root: Instance)
	local function restore(node)
		local pose=poses[node:GetAttribute("RuntimePoseId")];if pose and pose.Node==node and not node:GetAttribute("FilledUI") then for key,value in pose.Layout do if not (node.Name=="XPFill" and key=="Size") then node[key]=value end end end
	end
	restore(root);for _,node in root:GetDescendants() do restore(node) end
end
function UI.Roots(playerGui: PlayerGui): {Instance}
	local result={UI.Game,UI.Lobby}
	for _,node in UI.Overlays:GetChildren() do if node:IsA("GuiObject") then table.insert(result,node) end end
	for _,node in playerGui:GetChildren() do if node:IsA("ScreenGui") and node~=UI.HUD then table.insert(result,node) end end
	return result
end
function UI.Measurements(self: any,class: any,optional: boolean)
	-- The rulers live in the authored Game.ReferenceSizes frame when the HUD has one.
	local sizes=UI.Game:FindFirstChild("ReferenceSizes")
	local g=if sizes and sizes:IsA("GuiObject") then sizes else UI.Game
	-- Rulers may cross authored panels, but their dedicated layer always renders beneath the interactive HUD.
	if g~=UI.Game then g.ZIndex=0;g.Active=false end
	for _,prefix in {"Reference","Mystery"} do
		local root=MeasurementUI.Ensure(g,prefix);local dots={}
		for i=1,64 do dots[i]=need(root,"HeightDot"..i) end
		if prefix=="Reference" then self.MeasurementRoot,self.MeasurementDots,self.MeasurementText,self.ReferenceObjectName=root,dots,need(root,"RealHeight"),need(root,"ObjectName")
		else self.MysteryMeasurementRoot,self.MysteryMeasurementDots,self.MysteryMeasurementText,self.MysteryObjectName=root,dots,need(root,"UnknownHeight"),need(root,"ObjectName");self.EstimatedHeight=need(root,"EstimatedHeight");self.MysteryPlayerMugshot=need(root,"PlayerMugshot") end
		root.Visible=false
		self["Draw"..prefix.."Measurement"]=class["Draw"..prefix.."Measurement"]
	end
end
function UI.Match(class: any,playerGui: PlayerGui,config: any,starterGui: any)
	local g=UI.Game
	-- The state-based Game frame (AdjustingSize / OtherPlayerGuessing) replaces the flat compact layout.
	if g:FindFirstChild("AdjustingSize") then return require(script.Parent.GameStatesUI).new(playerGui,config,starterGui,class) end
	local header=g:FindFirstChild("Header")
	-- The compact HUD uses Header for its timer; TimeLeft may have been removed.
	if g:FindFirstChild("Profile") or (header and (header:FindFirstChild("Title") or header:FindFirstChild("Paragraph"))) then
		return require(script.Parent.GameFrameUI).new(playerGui,config,starterGui,class)
	end
	local self:any=setmetatable({Gui=g,StatusGui=need(g,"Status"),PlayerGui=playerGui,StarterGui=starterGui,Config=config,HiddenGuis={},HiddenCore={},ResultCards={}},class)
	local fields={Round={"Header","Round"},Time={"Header","Time"},Reference={"Reference","Text"},Target={"Target","Text"},Bottom={"Estimate"},Guess={"Estimate","Guess"},Help={"Estimate","Help"},Pulse={"Estimate","Guess","AccuracyPulse"},AccuracyTrack={"Estimate","AccuracyTrack"},AccuracyFill={"Estimate","AccuracyTrack","Fill"},Slider={"ScaleSlider"},Track={"ScaleSlider","Track"},Knob={"ScaleSlider","Track","Knob"},Plus={"ScaleSlider","Plus"},Minus={"ScaleSlider","Minus"},LockIn={"LockIn"},Flash={"DamageFlash"},OpponentPanel={"OpponentHearts"},Scoreboard={"Players"},ChainStatus={"ChainProgress"},HintButton={"BuySizeHint"},PetNotice={"PetAbilityNotice"},HintPanel={"SizeHintAnnouncement"},HintTitle={"SizeHintAnnouncement","Title"},HintGuidance={"SizeHintAnnouncement","Guidance"},HintProgress={"SizeHintAnnouncement","TimeRemaining"},HintMotion={"SizeHintAnnouncement","HintMotionScale"},LockAnnouncement={"LockAnnouncement"},LockedTitle={"LockAnnouncement","Title"},LockedHint={"LockAnnouncement","Hint"},LockedScale={"LockAnnouncement","LockMotionScale"},LockedLine={"LockAnnouncement","Sweep"},Results={"Results"},ObjectResizeIndicator={"ObjectResizeIndicator"}}
	for field,path in fields do local node=g;for _,name in path do node=need(node,name) end;self[field]=node end
	self.Status=need(self.StatusGui,"Text");self.BottomStroke=self.Bottom:FindFirstChildOfClass("UIStroke")
	self.YourHearts,self.OpponentHearts={},{}
	for i=1,config.StartingHearts do self.YourHearts[i]=need(need(g,"Hearts"),"YourHeart"..i);self.OpponentHearts[i]=need(self.OpponentPanel,"OpponentHeart"..i) end
	local retiredViews=g:FindFirstChild("ViewControls");if retiredViews and retiredViews:IsA("GuiObject") then retiredViews.Visible=false end
	UI.Measurements(self,class,false)
	self.ActualSize,self.ResultAnnouncement=need(self.Results,"ActualSize"),need(self.Results,"GuessAnnouncement")
	self.AnnouncementScale=need(self.ResultAnnouncement,"AnnouncementScale");self.ResultSlots={}
	for i=1,4 do
		local panel=need(self.Results,"PlayerResult"..i);local perfect=need(panel,"PerfectEffect");local sparks={}
		for n=1,8 do sparks[n]=need(perfect,"Sparkle"..n) end
		table.insert(self.ResultSlots,{Panel=panel,Scale=need(panel,"ResultMotionScale"),Portrait=need(panel,"Mugshot"),Name=need(panel,"PlayerName"),Percent=need(panel,"AccuracyPercent"),Verdict=need(panel,"Verdict"),Guess=need(panel,"AcceptedGuess"),Caption=need(panel,"AccuracyCaption"),Index=i,Perfect=perfect,PerfectScale=need(perfect,"PerfectPopScale"),PerfectText=need(perfect,"PerfectText"),PerfectSparks=sparks})
	end
	self:Hide()
	return self
end
function UI.Inventory(class: any,playerGui: PlayerGui,catalog: any,shop: any,rewards: any,blocks: any)
	local g=UI.Lobby
	local self:any=setmetatable({Gui=g,Catalog=catalog,ShopCatalog=shop,RewardCatalog=rewards,Actions={},DockWanted=true,CurrencyWanted=true},class)
	-- The lobby's buttons and balances are the authored layout (CurrencyDisplay, Lower, left, right, Upper).
	self.Lobby=LobbyView.new(g);self.Buttons=self.Lobby.Buttons
	-- Where a message would go (there is no menu shell any more): controllers write Text, alerts show the news.
	self.Message={Text=""}
	self.Blocks=blocks.new(playerGui,catalog,shop);Style.SetEnabled(g,true)
	return self
end
function UI.BlockCards(odds: GuiObject) return BlockCards.Bind(odds,UI) end
function UI.Blocks(class: any,catalog: any,shop: any)
	local g=need(UI.Overlays,"BlockPreview");local room=g:FindFirstChild("Showroom") or g
	local self:any=setmetatable({Gui=g,Room=room,Catalog=catalog,Shop=shop,Age=0,Slide=0,PetPreviews={}},class)
	local fields={Heading="Heading",Close="BackToLobby",Balance="Balance",Hero="BlockShowcase",RewardsHeading="RewardsHeading",Viewport="BlockViewport",Surface="SwipeSurface",Name="BlockName",Previous="PreviousBlock",Next="NextBlock",Counter="BlockCounter",BrowseHint="BrowseHint",Odds="PetOdds",Cash="BuyWithCash",Keys="BuyWithKeys",Message="PurchaseMessage"}
	for field,name in fields do self[field]=need(room,name) end
	self:SetupViewport()
	self.OddsSlots=UI.Slots(self.Odds,"Chance")
	self.Viewport.CurrentCamera=self.Camera;self.Cash.Active,self.Keys.Active=false,false;self.Cash.Visible,self.Keys.Visible=false,false
	Style.SetEnabled(g,false);return self
end
function UI.Hatch(class: any,playerGui: PlayerGui,starterGui: any,catalog: any,shop: any,equip: any)
	local g=need(UI.Overlays,"HatchReveal");local viewport=need(g,"RewardViewport")
	-- Shown at 1.5x its authored size, constant; ViewportScale (below) adds the "grows while spinning" touch on top.
	local base=viewport:FindFirstChild("RewardViewportBaseScale") or Instance.new("UIScale")
	base.Name,base.Scale,base.Parent="RewardViewportBaseScale",1.5,viewport
	local viewportScale=viewport:FindFirstChild("RewardViewportScale") or Instance.new("UIScale")
	viewportScale.Name,viewportScale.Parent="RewardViewportScale",viewport
	local self:any=setmetatable({Gui=g,PlayerGui=playerGui,StarterGui=starterGui,Catalog=catalog,Shop=shop,Equip=equip,Hidden={},Core={},Confetti={},Egg=class.SetupViewport(viewport),Title=need(g,"Title"),Rarity=need(g,"Rarity"),Continue=need(g,"Continue"),EquipButton=need(g,"Equip"),RewardStroke=viewport:FindFirstChild("OuterUIStroke"),ViewportScale=viewportScale},class)
	Style.SetEnabled(g,false);self.Continue.Visible,self.EquipButton.Visible=false,false
	self.Connections={self.Continue.Activated:Connect(function()if self.Revealed then self:Stop() end end),self.EquipButton.Activated:Connect(function()if self.Revealed then local id=self.Reward.PetId;self:Stop();self.Equip(id) end end)}
	return self
end
return UI

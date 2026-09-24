--!strict
-- The owner's compact, authored Game frame. All messages share Header.
local Style=require(script.Parent.UIStyle)
local Reveal=require(script.Parent.RevealPresentation)
local Motion=require(script.Parent.GameHUDMotion)
local HintWobble=require(script.Parent.HintWobble)
local UI={}
UI.__index=UI
local white=Color3.new(1,1,1)
-- How long each dot of "<Name> made you lag..." shows, same cadence as the hatch "Hatching..." text.
local LAG_DOT_SECONDS=0.4
function UI.new(playerGui: PlayerGui,config: any,starterGui: any,measurementMethods: any?)
	local authored=Style.Authoring
	local need=authored.Need
	local game=authored.Game
	local header,timer,profile=need(game,"Header"),game:FindFirstChild("TimeLeft"),game:FindFirstChild("Profile")
	if profile then profile.Visible=false end
	local slider=need(game,"ScaleSlider")
	local track=need(slider,"Track")
	track.Active=true
	local retiredView=game:FindFirstChild("View")
	if retiredView and retiredView:IsA("GuiObject") then retiredView.Visible=false end
	local lagging=game:FindFirstChild("Lagging")
	if lagging then lagging.Visible=false end
	local self:any=setmetatable({Gui=game,StatusGui=header,Header=header,Title=need(header,"Title"),Paragraph=need(header,"Paragraph"),
		Timer=timer,TimeTitle=timer and timer:FindFirstChild("Title"),Time=timer and timer:FindFirstChild("Paragraph"),Profile=profile,CurrentPlayerName="Player",
		Slider=slider,Track=track,Knob=need(track,"Knob"),Plus=need(slider,"Plus"),Minus=need(slider,"Minus"),
		LockIn=need(game,"Submit","GuiButton"),HintButton=need(game,"Hint","GuiButton"),ResetButton=need(game,"Reset","GuiButton"),
		InkSplatButton=need(game,if game:FindFirstChild("InkSplat") then "InkSplat" else "LightsOut","GuiButton"),Flash=need(game,"DamageFlash"),
		Lagging=lagging,LaggingTitle=lagging and lagging:FindFirstChild("Title"),
		PlayerGui=playerGui,Config=config,StarterGui=starterGui,HiddenGuis={},HiddenCore={}},UI)
	if measurementMethods then authored.Measurements(self,measurementMethods,true) end
	-- Bigger / smaller tick the model instead of clicking.
	self.Plus:SetAttribute("NoClick",true);self.Minus:SetAttribute("NoClick",true)
	if self.TimeTitle then self.TimeTitle.Text="Time Left" end;Style.Caption(self.HintButton,"Hint")
	self.Motion=Motion.new()
	self.HintWobble=HintWobble.new(self.HintButton)
	self.Panels={self.Header,self.Slider,self.LockIn,self.HintButton,self.ResetButton,self.InkSplatButton}
	if self.Timer then table.insert(self.Panels,self.Timer) end
	-- Once used, the ink button always drops off the bottom of the screen.
	for _,node in self.Panels do self.Motion:Add(node,if node==self.InkSplatButton then "Down" else nil) end
	for _,binding in {{"MeasurementRoot","DrawReferenceMeasurement"},{"MysteryMeasurementRoot","DrawMysteryMeasurement"}} do
		local root=self[binding[1]]
		if root then
			self.Motion:AddOverlay(root);table.insert(self.Panels,root)
			local draw=self[binding[2]]
			self[binding[2]]=function(owner,...)
				draw(owner,...)
				owner.Motion:Set(root,root.Visible and not owner.Closing)
				owner.Motion:ApplyOverlay(root)
			end
		end
	end
	self:Hide(true)
	return self
end
function UI.Message(self: any,title: string,paragraph: string,color: Color3?)
	self.Title.Text,self.Paragraph.Text=title,paragraph
	self.Title.TextColor3=color or white
end
function UI.SetProfile(self: any,s: any,id: number?,fallback: string?)
	id=id or s.YourUserId
	local name=fallback or "Player"
	for _,p in s.Participants or {} do if p.UserId==id then name=p.Username or p.Name or name;break end end
	self.CurrentPlayerName=if id==s.YourUserId then "YOU" else name
end
local function enable(button: GuiButton,on: boolean)
	button.Active,button.Selectable,button.AutoButtonColor=on,on,on
end
function UI.EnableLock(self: any,on: boolean)
	enable(self.LockIn,on);enable(self.ResetButton,on);enable(self.Plus,on);enable(self.Minus,on)
	Style.Caption(self.LockIn,if on then "Submit" else "Locked")
end
function UI.EnableHint(self: any,on: boolean)
	enable(self.HintButton,on)
	if self.HintWobble then self.HintWobble:SetEnabled(on) end
end
function UI.SetGuess(self: any,meters: number,alpha: number)
	self.SelectedGuessMeters=meters
	local pose=Style.Authoring.Pose(self.Knob)
	self.Knob.Position=UDim2.new(pose.Position.X.Scale,pose.Position.X.Offset,0.9-0.8*math.clamp(alpha,0,1),pose.Position.Y.Offset)
end
function UI.Step(self: any,dt: number)
	local visible=self.Motion:Step(dt)
	if self.HintWobble then self.HintWobble:Step(dt) end
	if self.Closing and not visible then Style.SetVisible(self.Gui,false) end
end
-- Lag sabotage: all the other funny effects (camera freeze bursts, ink, etc.) keep running elsewhere; this just
-- makes Game.Lagging visible with its Title cycling "<Name> made you lag." / ".." / "..." on repeat, and drifts
-- every authored panel toward stutterX/stutterY (Sabotage's small, synced-to-the-freeze offset -- zero between
-- bursts) with GameHUDMotion's own slow easing, so the HUD reads as briefly going sluggish and stepping slightly
-- in place, then cleanly settling back, instead of scattering across the screen.
function UI.SetLagging(self: any,active: boolean,now: number,throwerName: string?,stutterX: number?,stutterY: number?)
	if self.Lagging then
		self.Lagging.Visible=active
		if active and self.LaggingTitle then
			if not self.LagStartAt then self.LagStartAt=now end
			local dots=string.rep(".",math.floor((now-self.LagStartAt)/LAG_DOT_SECONDS)%3+1)
			self.LaggingTitle.Text=(throwerName or "Someone").." made you lag"..dots
		else
			self.LagStartAt=nil
		end
	end
	self.Motion:SetJitter(if active then UDim2.fromScale(stutterX or 0,stutterY or 0) else nil)
end
function UI.Panel(self: any,node: GuiObject?,on: boolean) if node then self.Motion:Set(node,on) end end
function UI.Open(self: any)
	self.Closing=false;Style.SetEnabled(self.Gui,true)
end
function UI.EnableInkSplat(self: any,on: boolean) enable(self.InkSplatButton,on) end
-- Called the moment the button is pressed, so it leaves at once instead of waiting for the server.
-- The sabotage buttons stay on screen after a use (dimmed while an effect runs); nothing to hide or restore.
function UI.InkSent(_self: any,_turnId: any) end
function UI.InkFailed(_self: any) end
-- Model hover still uses the existing world highlight; the deleted badge is not rebuilt.
function UI.SetObjectHover(_self: any,_point: any,_viewport: any?) end
function UI.BlocksObjectDrag(self: any,position: Vector3): boolean
	for _,node in self.PlayerGui:GetGuiObjectsAtPosition(position.X,position.Y) do
		-- Full-screen structural frames must not swallow direct object dragging.
		if node==self.Gui or node==Style.Authoring.HUD or node==Style.Authoring.Overlays or node==self.Flash then continue end
		if node:IsA("GuiButton") or node:IsA("TextBox") or node:IsA("ScrollingFrame") or node.Active or node.BackgroundTransparency<1 then return true end
	end
	return false
end
function UI.FocusResults(self: any)
	for _,root in Style.Roots(self.PlayerGui) do
		if root==self.Gui then continue end
		local known=false
		for _,entry in self.HiddenGuis do if entry.Gui==root then known=true;break end end
		if not known then table.insert(self.HiddenGuis,{Gui=root,Enabled=Style.IsEnabled(root)}) end
		Style.SetVisible(root,false)
	end
	if not self.CoreHidden then
		self.CoreHidden=true
		-- Chat stays available throughout gameplay and results; only non-chat CoreGui is cleared for the reveal.
		for _,kind in {Enum.CoreGuiType.Backpack,Enum.CoreGuiType.PlayerList,Enum.CoreGuiType.Health} do
			pcall(function() self.HiddenCore[kind]=self.StarterGui:GetCoreGuiEnabled(kind);self.StarterGui:SetCoreGuiEnabled(kind,false) end)
		end
	end
end
function UI.EndResults(self: any)
	for _,entry in self.HiddenGuis do if entry.Gui.Parent then
		local desired=entry.Gui:GetAttribute("RuntimeEnabled")
		Style.SetVisible(entry.Gui,if desired~=nil then desired else entry.Enabled)
	end end
	table.clear(self.HiddenGuis)
	for kind,on in self.HiddenCore do pcall(function()self.StarterGui:SetCoreGuiEnabled(kind,on)end) end
	table.clear(self.HiddenCore);self.CoreHidden=false
end
function UI.HideMeasurements(self: any)
	if self.MeasurementRoot then self:Panel(self.MeasurementRoot,false) end
	if self.MysteryMeasurementRoot then self:Panel(self.MysteryMeasurementRoot,false) end
end
function UI.Hide(self: any,immediate: boolean?)
	self.HeaderTurnKey,self.HeaderTurnStartedAt,self.LastPaintNow=nil,nil,nil
	self:HideMeasurements()
	self.StatusOnly=false
	self:EndResults();self.Closing=true;self.Gui:SetAttribute("RuntimeEnabled",false)
	for _,node in self.Panels do self:Panel(node,false) end
	self:EnableInkSplat(false)
	self:SetLagging(false,0)
	if immediate then self.Motion:Reset();Style.SetVisible(self.Gui,false) end
	self:EnableLock(false);self:EnableHint(false)
	self.Flash.BackgroundTransparency=1
end
function UI.ShowStatus(self: any,message: string)
	self:HideMeasurements()
	self.StatusOnly=true
	self:EndResults();self:Open()
	self:Panel(self.Timer,false)
	for _,node in {self.Slider,self.LockIn,self.HintButton,self.ResetButton,self.InkSplatButton} do self:Panel(node,false) end
	self:Panel(self.Header,true);self.Flash.BackgroundTransparency=1
	self:EnableInkSplat(false)
	local title,paragraph=message:match("^([^\n]+)\n(.*)$")
	self:Message(title or message,paragraph or "")
	self:EnableLock(false);self:EnableHint(false)
end
function UI.Show(self: any,s: any)
	self.Snapshot=s
	if self.Profile then self.Profile.Visible=false end
	self:HideMeasurements()
	if self.ReferenceObjectName then self.ReferenceObjectName.Text=Style.MeasurementName(s.Reference and s.Reference.DisplayName) end
	if self.MysteryObjectName then self.MysteryObjectName.Text=Style.MeasurementName(s.Target and s.Target.DisplayName) end
	local state=s.State
	if state~="ROUND_REVEAL" then self:EndResults() end
	if state=="IDLE" and s.Completion then
		local c=s.Completion
		-- Just "GAME OVER" and how it went; no "match complete" line and no reward text.
		if c.Cancelled then self:ShowStatus("MATCH CANCELLED\n"..(c.Result or c.Message or ""));return end
		local result=string.upper(c.Result or c.Message or "")
		local outcome=if string.find(result,"WIN",1,true) then "YOU WON" elseif string.find(result,"LOST",1,true) then "YOU LOST" elseif string.find(result,"DRAW",1,true) then "IT'S A DRAW" else result
		self:ShowStatus("GAME OVER\n"..outcome);return
	end
	-- Sitting down shows nothing here: the table's own sign says "Waiting for players (1/2)".
	if state=="WAITING_FOR_PLAYER" then self:Hide();return end
	local arena=state=="ROUND_INTRO" or state=="GUESSING" or state=="TURN_LOCKED" or state=="ROUND_REVEAL"
	local tableView=state=="TABLE_RETURN" or state=="TABLE_REACTION"
	if not arena and not tableView then self:Hide();return end
	self.StatusOnly=false
	self:Open();self:Panel(self.Header,true);self:Panel(self.Timer,arena and state~="ROUND_REVEAL" and state~="GUESSING")
	local guessing=state=="GUESSING" and s.CanGuess==true
	for _,node in {self.Slider,self.LockIn,self.HintButton,self.ResetButton} do self:Panel(node,guessing) end
	self:Panel(self.InkSplatButton,state=="GUESSING" and not s.CanGuess and s.ActivePlayerUserId~=nil and s.ActivePlayerUserId~=s.YourUserId)
	self:EnableInkSplat(s.CanUseInkSplat==true)
	self:EnableLock(guessing);self:EnableHint(guessing and s.CanBuyHint==true)
	self:SetProfile(s,if tableView then s.YourUserId else s.ActivePlayerUserId or s.YourUserId,s.ActivePlayerUsername or s.ActivePlayerName)
	if state=="ROUND_REVEAL" and s.Reveal then
		local key=tostring(s.MatchId)..":"..tostring(s.RoundId)
		if self.RevealKey~=key then
			self.RevealKey=key;self.RevealSnapshot=table.clone(s);self.RevealSnapshot.Reveal=table.clone(s.Reveal)
			local entries={};for _,entry in s.Reveal.Results or {} do table.insert(entries,table.clone(entry)) end
			self.RevealSnapshot.Reveal.Results=entries
		end
		self:FocusResults()
	end
	self:Paint(s,nil)
end
function UI.Paint(self: any,s: any,now: number?)
	now=now or self.LastPaintNow
	if now then self.LastPaintNow=now end
	local state=s.State
	if state~="GUESSING" then self.HeaderTurnKey,self.HeaderTurnStartedAt=nil,nil end
	local seconds=if now and s.Deadline then math.max(0,math.ceil(s.Deadline-now)) else nil
	if self.TimeTitle then self.TimeTitle.Text="Time Left" end
	-- "Time left 20s" on a single timer label; a layout with its own "Time Left" title (TimeTitle) shows just "20s".
	if self.Time then self.Time.Text=if seconds then (if self.TimeTitle then "" else "Time left ")..seconds.."s" else "" end
	local instruction="Try to make the "..string.lower(s.Target and s.Target.DisplayName or "mystery object").." its real life size!"
	local targetMessage=if s.RequiredAccuracy then "Get "..s.RequiredAccuracy.."/100 to keep "..(if s.CanGuess then "your" else "a").." heart!" else nil
	if state=="ROUND_INTRO" then
		self:Message("ROUND "..(s.Round or 1),instruction)
	elseif state=="GUESSING" then
		local key=tostring(s.MatchId)..":"..tostring(s.RoundId)..":"..tostring(s.TurnId)..":"..tostring(s.ActivePlayerUserId)
		if self.HeaderTurnKey~=key then self.HeaderTurnKey,self.HeaderTurnStartedAt=key,nil end
		if now and not self.HeaderTurnStartedAt then self.HeaderTurnStartedAt=now end
		local messageUntil=(self.HeaderTurnStartedAt or math.huge)+Style.HeaderMessageSeconds
		local targetUntil=messageUntil
		self:Message(if s.CanGuess then "YOUR TURN" else self.CurrentPlayerName.." IS GUESSING",targetMessage or (if s.CanGuess then instruction else "Watch them try to find the size!"))
		local hint=s.CanGuess and s.Hint
		local activeHint=false
		if hint and now and now<hint.ExpiresAt and now<(s.Deadline or math.huge) then
			local clue=self.Config.HintMessages[hint.Guidance] or self.Config.HintMessages.Close
			self:Message(clue.Title,clue.Body,Color3.fromRGB(255,222,80))
			messageUntil=(hint.StartedAt or now)+Style.HeaderMessageSeconds
			activeHint=true
		end
		-- A hint bought or earned at the start of the turn must remain visible. Previously the opening
		-- Endless target message replaced its explanation, which made a working free hint look inert.
		if targetMessage and not activeHint and (not now or now<targetUntil) then self.Paragraph.Text=targetMessage;messageUntil=targetUntil end
		if now and seconds and (now>=messageUntil or seconds<=5) then self.Paragraph.Text="Time left: "..seconds.." s" end
		Style.Caption(self.HintButton,"Hint")
	elseif state=="TURN_LOCKED" then
		self:Message((if s.ActivePlayerUserId==s.YourUserId then "YOU" else self.CurrentPlayerName).." LOCKED IN",(if s.LockedAutomatically then "Time is up. " else "Guess ready! ")..(if s.NextPlayerName then "Up next: "..s.NextPlayerName else "Let's see how you did!"))
	elseif (state=="TABLE_RETURN" or state=="TABLE_REACTION") and not self.OwnsTable then
		local view=Reveal.Evaluate(s,now or s.Deadline or 0,self.Config)
		self:Message("You scored:",string.format("%d/100 Accuracy",if view then view.Accuracy else 0))
		if s.Mode=="BestOfFive" and state=="TABLE_REACTION" then self:Message("ROUND "..s.Round.." OF "..s.RoundLimit,string.format("Your total: %.1f points",s.TotalAccuracy or 0)) end
	elseif state=="ROUND_REVEAL" and s.Reveal then
		local frozen=self.RevealSnapshot or s
		local view=Reveal.Evaluate(frozen,now or s.Reveal.StartedAt or 0,self.Config)
		local sequence=view.Sequence
		local entry=sequence.Index and Reveal.Order(frozen.Reveal.Results,frozen.YourUserId)[sequence.Index]
		self:FocusResults()
		if entry then
			local progress=(1-math.cos(sequence.Growth*math.pi))*0.5
			local score=math.floor(math.clamp(entry.Accuracy,0,100)*progress+(if s.Mode=="Endless" then 1e-7 else 0.5))
			self:SetProfile(frozen,entry.UserId,entry.Username or entry.Name)
			local perfect=entry.Accuracy>=99 and entry.Accuracy<=100 and sequence.SlotAge>=self.Config.ResultAnnounceSeconds+self.Config.ResultGrowSeconds and sequence.SlotAge<self.Config.ResultAnnounceSeconds+self.Config.ResultGrowSeconds+1.4
			local finalColor=if entry.Loser then Color3.fromRGB(255,65,85) else Color3.fromRGB(65,255,113)
			local color=if perfect then Color3.fromRGB(255,215,55) else white:Lerp(finalColor,progress)
			self:Message(if entry.UserId==s.YourUserId then "You scored:" else self.CurrentPlayerName.." scored:",string.format("%d/100 Accuracy",score),color)
		else
			self:SetProfile(s,s.YourUserId)
			self:Message(sequence.Caption,if sequence.Phase=="REFERENCE" then (s.Reference.DisplayName or "") else "")
		end
		return view
	end
	if state=="GUESSING" and s.RoundLimit then self.Title.Text=self.Title.Text.."  ("..s.Round.."/"..s.RoundLimit..")" end
end
function UI.Tick(self: any,s: any,now: number)
	if not s then return end
	if s.State=="IDLE" and s.Completion then if s.Deadline and now>=s.Deadline then self:Hide() end;return end
	if self.StatusOnly or not Style.IsEnabled(self.Gui) then return end
	-- A layout that owns the table cutscene (GameStatesUI) times its own flash.
	if self.OwnsTable then return self:Paint(s,now) end
	local hit=s.State=="TABLE_REACTION" and s.Reveal and s.Reveal.Result=="ROUND LOST!" and s.HeartAppliedAt
	local age=if hit then now-s.HeartAppliedAt else math.huge
	self.Flash.BackgroundTransparency=if age>=0 and age<self.Config.HeartFlashSeconds then 1-0.28*(1-age/self.Config.HeartFlashSeconds) else 1
	return self:Paint(s,now)
end
function UI.Destroy(self: any)
	self:Hide(true)
	if self.HintWobble then self.HintWobble:Destroy() end
end
return UI

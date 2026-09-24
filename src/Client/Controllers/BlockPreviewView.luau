--!strict
local Style = require(script.Parent.UIStyle)
local BlockPreviewView = {}
BlockPreviewView.__index = BlockPreviewView
local rarityColors={Common=Color3.fromRGB(225,235,245),Uncommon=Color3.fromRGB(90,245,130),Rare=Color3.fromRGB(40,210,255),Epic=Color3.fromRGB(236,85,255),Legendary=Color3.fromRGB(255,204,45),Mythic=Color3.fromRGB(255,85,130)}
local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local existing=parent:FindFirstChild(name)
	local object = Style.Node(parent, name, "Part")
	if existing and Style.Authoring then return object end
	object.Size, object.CFrame, object.Color = size, CFrame.new(position), color
	object.Anchored, object.CanCollide, object.CanTouch, object.CanQuery = true, false, false, false
	object.Material = Enum.Material.SmoothPlastic
	return object
end
function BlockPreviewView.SetupViewport(self: any)
	local viewport=self.Viewport
	local existingCamera=viewport:FindFirstChild("ShowroomCamera")
	local camera = Style.Node(viewport, "ShowroomCamera", "Camera")
	if not existingCamera then camera.CFrame, camera.FieldOfView = CFrame.lookAt(Vector3.new(0, 2, 7.8), Vector3.new(0, -0.4, 0)), 42 end
	viewport.CurrentCamera = camera;self.Camera, self.Viewport = camera, viewport
	local world = Style.Node(viewport, "PreviewStage", "WorldModel")
	local oldFloor=world:FindFirstChild("StageFloor");if oldFloor and not Style.Authoring then oldFloor:Destroy() end
	part(world, "DisplayPlinth", Vector3.new(4.2, 0.45, 4.2), Vector3.new(0, -2.05, 0), Style.Purple)
	part(world, "PlinthTrim", Vector3.new(4.4, 0.12, 4.4), Vector3.new(0, -1.78, 0), Style.Gold)
	self.World=world
	local previous=world:FindFirstChild("SelectedBlock")
	-- Remove the old generated cube (or a copied runtime clone), never the source pack/scenery.
	if previous and previous~=self.Model then previous:Destroy() end
	if self.Model and self.Model.Parent~=world then self.Model=nil;self.ModelSource=nil end

end
function BlockPreviewView.RefreshModel(self: any)
	local name=self.Selected and self.Shop.BlockPreviewModels and self.Shop.BlockPreviewModels[self.Selected]
	local assets=Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local pack=assets and assets:FindFirstChild("LuckyBlocks")
	local source=name and pack and pack:FindFirstChild(name)
	if source==self.ModelSource and self.Model and self.Model.Parent==self.World then return end
	if self.Model then self.Model:Destroy();self.Model=nil end
	self.ModelSource=nil
	if source and Style.BlockVisual then
		self.Model=Style.BlockVisual.Create(source,self.World)
		if self.Model then self.ModelSource=source end
	end
end
function BlockPreviewView.new(playerGui: PlayerGui, catalog: any, shop: any)
 if Style.Authoring then return Style.Authoring.Blocks(BlockPreviewView,catalog,shop) end
	local self: any = setmetatable({ Catalog = catalog, Shop = shop, Age = 0, Slide = 0, PetPreviews={} }, BlockPreviewView)
	local gui = Style.Node(playerGui, "ScaleBlockPreview", "ScreenGui")
	gui.ResetOnSpawn, gui.DisplayOrder, gui.ZIndexBehavior = false, 60, Enum.ZIndexBehavior.Sibling
	Style.SetEnabled(gui, false);self.Gui = gui
	local oldRoom=gui:FindFirstChild("Showroom")
	local oldCapture=oldRoom and oldRoom:FindFirstChild("InputBlocker")
	if oldCapture then oldCapture.Parent=gui end
	local capture = Style.Node(gui, "InputBlocker", "TextButton")
	capture.Size, capture.BackgroundTransparency, capture.Text, capture.Modal, capture.AutoButtonColor = UDim2.fromScale(1, 1), 1, "", true, false
	capture.BackgroundColor3,capture.BackgroundTransparency,capture.ZIndex=Color3.fromRGB(15,8,35),0.2,1
	local room = Style.Frame(gui, "Showroom", UDim2.fromScale(0.94,0.92),UDim2.fromScale(0.03,0.04),Style.Gold,0)
	self.Room=room;room.ZIndex=2;room.Corners.CornerRadius=UDim.new(0,26);room.Border.Thickness=5
	room.Size,room.Position,room.BackgroundColor3,room.BackgroundTransparency=UDim2.fromScale(0.94,0.92),UDim2.fromScale(0.03,0.04),Style.Gold,0
	Style.Gradient(room, Color3.fromRGB(255,244,45), Color3.fromRGB(255,146,35))
	self.Heading=Style.Text(room, "Heading", "LUCKY BLOCKS", UDim2.fromScale(0.76, 0.09), UDim2.fromScale(0.04, 0.015), 48)
	self.Heading.TextXAlignment=Enum.TextXAlignment.Left
	self.Close = Style.Button(room, "BackToLobby", "X", UDim2.fromScale(0.065, 0.085), UDim2.fromScale(0.905, 0.02), Color3.fromRGB(245, 61, 91))
	self.Close.Corners.CornerRadius=UDim.new(1,0)
	self.Balance = Style.Text(room, "Balance", "", UDim2.fromScale(0.88, 0.045), UDim2.fromScale(0.04, 0.108), 22)
	self.Balance.TextXAlignment=Enum.TextXAlignment.Left
	self.Hero=Style.Frame(room,"BlockShowcase",UDim2.fromScale(0.38,0.68),UDim2.fromScale(0.03,0.17),Color3.fromRGB(59,23,112),0)
	self.Hero.Corners.CornerRadius=UDim.new(0,22);self.Hero.Border.Thickness=4
	self.Hero.ZIndex=1
	Style.Gradient(self.Hero,Color3.fromRGB(99,40,170),Color3.fromRGB(32,16,70))
	self.RewardsHeading=Style.Text(room,"RewardsHeading","POSSIBLE PETS",UDim2.fromScale(0.51,0.065),UDim2.fromScale(0.45,0.17),32)
	self.RewardsHeading.TextXAlignment=Enum.TextXAlignment.Left
	local viewport = Style.Node(room, "BlockViewport", "ViewportFrame")
	viewport.Size, viewport.Position, viewport.BackgroundTransparency = UDim2.fromScale(0.88, 0.45), UDim2.fromScale(0.06, 0.19), 1
	viewport.Ambient, viewport.LightColor, viewport.LightDirection = Color3.new(0.8, 0.8, 0.8), Color3.new(1, 1, 1), Vector3.new(-1, -1, -1)
	self.Viewport=viewport;self:SetupViewport()
	viewport.ZIndex=2
	self.Surface = Style.Node(room, "SwipeSurface", "TextButton")
	self.Surface.Size, self.Surface.Position, self.Surface.BackgroundTransparency, self.Surface.Text, self.Surface.AutoButtonColor = viewport.Size, viewport.Position, 1, "", false
	self.Surface.ZIndex=3
	self.Name = Style.Text(room, "BlockName", "", UDim2.fromScale(0.64, 0.075), UDim2.fromScale(0.18, 0.15), 38)
	self.Previous = Style.Button(room, "PreviousBlock", "<", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.025, 0.37), Style.Orange)
	self.Next = Style.Button(room, "NextBlock", ">", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.875, 0.37), Style.Orange)
	for _,node in {self.Name,self.Previous,self.Next} do node.ZIndex=4 end
	self.Counter = Style.Text(room, "BlockCounter", "", UDim2.fromScale(0.8, 0.04), UDim2.fromScale(0.1, 0.61), 22)
	self.BrowseHint=Style.Text(room, "BrowseHint", "Swipe to explore", UDim2.fromScale(0.9, 0.035), UDim2.fromScale(0.05, 0.65), 18)
	self.Odds = Style.Node(room, "PetOdds", "Frame");self.Odds.BackgroundTransparency = 1
	self.Odds.Size, self.Odds.Position = UDim2.fromScale(0.94, 0.12), UDim2.fromScale(0.03, 0.7)
	self.Cash = Style.Button(room, "BuyWithCash", "", UDim2.fromScale(0.44, 0.08), UDim2.fromScale(0.04, 0.85), Style.Green)
	self.Keys = Style.Button(room, "BuyWithKeys", "", UDim2.fromScale(0.44, 0.08), UDim2.fromScale(0.52, 0.85), Style.Green)
	self.Message = Style.Text(room, "PurchaseMessage", "", UDim2.fromScale(0.92, 0.055), UDim2.fromScale(0.04, 0.94), 20)
	-- Copied runtime content must never offer stale prices or actions before readiness.
	self.Cash.Active, self.Keys.Active = false, false
	self.Cash.Visible, self.Keys.Visible = false, false
	Style.ClearChildren(self.Odds)
	self:Layout(false)
	return self
end
function BlockPreviewView.Layout(self: any, compact: boolean)
	if Style.Authoring then self.Compact=compact;return end
	self.Compact=compact
	local function place(node,x,y,w,h) node.Position,node.Size=UDim2.fromScale(x,y),UDim2.fromScale(w,h) end
	place(self.Heading,0.04,0.015,0.76,0.09)
	place(self.Close,0.88,0.02,0.09,0.085)
	place(self.Balance,0.04,0.108,0.88,0.045)
	place(self.Hero,0.03,0.17,if compact then 0.94 else 0.38,if compact then 0.30 else 0.68)
	place(self.Name,if compact then 0.12 else 0.05,if compact then 0.185 else 0.19,if compact then 0.76 else 0.34,if compact then 0.055 else 0.11)
	place(self.Viewport,if compact then 0.20 else 0.065,if compact then 0.235 else 0.30,if compact then 0.60 else 0.31,if compact then 0.20 else 0.40)
	self.Surface.Size,self.Surface.Position=self.Viewport.Size,self.Viewport.Position
	place(self.Previous,0.045,if compact then 0.30 else 0.47,if compact then 0.11 else 0.065,0.085)
	place(self.Next,if compact then 0.845 else 0.33,if compact then 0.30 else 0.47,if compact then 0.11 else 0.065,0.085)
	place(self.Counter,if compact then 0.40 else 0.10,if compact then 0.427 else 0.735,if compact then 0.20 else 0.24,0.035)
	place(self.BrowseHint,0.065,0.79,0.31,0.03);self.BrowseHint.Visible=not compact
	place(self.RewardsHeading,if compact then 0.04 else 0.45,if compact then 0.48 else 0.17,if compact then 0.92 else 0.51,if compact then 0.04 else 0.065)
	place(self.Odds,if compact then 0.04 else 0.45,if compact then 0.53 else 0.255,if compact then 0.92 else 0.51,if compact then 0.31 else 0.59)
	for _,button in {self.Cash,self.Keys} do place(button,0.12,0.87,0.76,0.065) end
	place(self.Message,0.04,0.947,0.92,0.037)
end
function BlockPreviewView.Show(self: any, visible: boolean)
	self.Open = visible;self.Drag = nil
	Style.SetEnabled(self.Gui, visible)
	if not visible then self.Selected = nil end
end
function BlockPreviewView.Render(self: any, state: any, selected: string, actions: any)
	if Style.Authoring and not self.BindingData then
		self.BindingData=true;local previous=Style.BindingContent;Style.BindingContent=true
		local ok,message=pcall(function() self:Render(state,selected,actions) end)
		self.BindingData=nil;Style.BindingContent=previous;Style.Authoring.RestoreLayout(self.Room)
		if not ok then self.CardsFor=nil;error(message,0) end
		return
	end
	local index = table.find(self.Shop.BlockOrder, selected) or 1
	selected = self.Shop.BlockOrder[index]
	local item = self.Shop.Containers[selected]
	if self.Selected ~= selected then self.Slide, self.Age,self.PreviewRetryAt = 5, 0,0 end
	self.Selected = selected
	self:RefreshModel()
	self.Name.Text, self.Counter.Text = item.Name, tostring(index).." / "..#self.Shop.BlockOrder
	self.Balance.Text = Style.Money(state.Cash).."   /   "..state.Keys.." Gems"
	local pets, total = {}, 0
	local available=true
	for _, id in item.PetOrder or self.Catalog.Order.Pets do
		if (item.Weights[id] or 0)>0 then
			table.insert(pets,id);total+=item.Weights[id]
			if state.AvailablePets and not state.AvailablePets[id] then available=false end
		end
	end
	if self.CardsFor~=selected then
	if Style.Authoring then
		self.AuthoredCards=self.AuthoredCards or Style.Authoring.BlockCards(self.Odds)
	else Style.ClearChildren(self.Odds) end
	self.PetPreviews,self.PendingPreviews,self.PetNameLabels={},{},{};self.CardsFor=selected
	for order, id in pets do
		local pet = self.Catalog.Items.Pets[id]
		local tint=if pet.Presentation then Color3.fromRGB(table.unpack(pet.Presentation.Tint)) else rarityColors[pet.Rarity] or Style.Purple
		if Style.Authoring then
			local binding=self.AuthoredCards[order]
			local card=binding.Card;card.Visible=true
			card.BackgroundColor3=tint
			binding.Name.Text=pet.Name;binding.Chance.Text=string.format("%g%%",item.Weights[id]/total*100)
			self.PetNameLabels[id]=binding.Name
			Style.PetRarity(binding.Name,pet)
			if binding.Rarity then binding.Rarity.Text=string.upper(pet.Rarity);Style.PetRarity(binding.Rarity,pet) end
			local preview=Style.Preview(card,pet,"Pets",binding.Preview)
			table.insert(self.PetPreviews,preview)
			if pet.AssetId and not preview:FindFirstChild("PetModel") then self.PendingPreviews[preview]=pet.AssetId end
			continue
		end
		local card = Style.Frame(self.Odds, if self.OddsSlots and self.OddsSlots[order] then self.OddsSlots[order].Name else id, UDim2.fromScale(0.48, 0.48), UDim2.fromScale((order-1)%2*0.52, math.floor((order-1)/2)*0.52),tint,0)
		card.Corners.CornerRadius=UDim.new(0,18);card.Border.Thickness=3
		Style.Gradient(card,tint:Lerp(Color3.new(1,1,1),0.16),tint:Lerp(Color3.fromRGB(40,12,72),0.7))
		local preview=Style.Preview(card,pet,"Pets")
		preview.Size,preview.Position=UDim2.fromScale(0.94,0.74),UDim2.fromScale(0.03,0.015)
		table.insert(self.PetPreviews,preview)
		if pet.AssetId and not preview:FindFirstChild("PetModel") then self.PendingPreviews[preview]=pet.AssetId end
		local badge=Style.Frame(card,"ChanceBadge",UDim2.fromScale(0.34,0.19),UDim2.fromScale(0.63,0.035),Color3.fromRGB(32,18,52),0.12)
		badge.Border.Thickness=2
		local chance=Style.Text(card, "Chance", string.format("%g%%", item.Weights[id]/total*100),badge.Size,badge.Position,24)
		chance.ZIndex=3
		local name=Style.Text(card, "PetName", pet.Name, UDim2.fromScale(0.94, 0.19), UDim2.fromScale(0.03, 0.70), 23);name.ZIndex=3
		self.PetNameLabels[id]=name
		Style.PetRarity(name,pet)
		local rarity=Style.Text(card,"Rarity",string.upper(pet.Rarity),UDim2.fromScale(0.94,0.11),UDim2.fromScale(0.03,0.885),15)
		Style.PetRarity(rarity,pet);rarity.ZIndex=3
	end
	end
	self:UpdatePetProgress(state.PetProgress or {})
	Style.Caption(self.Cash, "Buy & Open / "..Style.Money(item.Cash))
	Style.Caption(self.Keys, "Buy & Open / "..item.Keys..(if item.Keys==1 then " Gem" else " Gems"))
	self.Cash.Visible,self.Keys.Visible=item.Currency=="Cash",item.Currency=="Keys"
	self.Cash.Active = self.Cash.Visible and available and state.AllowedRandom == true and item.Cash>0 and state.Cash >= item.Cash
	self.Keys.Active = self.Keys.Visible and available and state.AllowedRandom == true and item.Keys > 0 and state.Keys >= item.Keys
	for _, button in { self.Cash, self.Keys } do button.Selectable = button.Active;button.BackgroundColor3 = if button.Active then Style.Green else Color3.fromRGB(114, 116, 136) end
	if state.AllowedRandom ~= true then self.Message.Text = "Not available for you."
	elseif not available then self.Message.Text="Block unavailable."
	elseif not self.Cash.Active and not self.Keys.Active then self.Message.Text = "Earn more "..(if item.Currency=="Keys" then "Gems" else "Cash").." to open this block."
	else self.Message.Text = "Each block opens immediately and gives one pet." end
	table.insert(actions, { Button = if item.Currency=="Keys" then self.Keys else self.Cash, Action = "Hatch", Payload = { Container = selected, Payment = item.Currency, Token = state.Token } })
end
function BlockPreviewView.UpdatePetProgress(self: any,progress: any)
	for id,label in self.PetNameLabels or {} do
		local info=progress[id]
		label.Text=self.Catalog.PetDisplayName(id,info and info.Level)
	end
end
function BlockPreviewView.BeginSwipe(self: any, input: any)
	if not self.Open or self.Drag then return end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		self.Drag = { Input = input, Kind = input.UserInputType, Start = input.Position }
	end
end
function BlockPreviewView.EndSwipe(self: any, input: any): number
	local drag = self.Drag
	if not drag or input.UserInputType ~= drag.Kind or (drag.Kind == Enum.UserInputType.Touch and input ~= drag.Input) then return 0 end
	self.Drag = nil
	if not self.Open or input.UserInputState == Enum.UserInputState.Cancel then return 0 end
	local delta = input.Position - drag.Start
	if math.abs(delta.X) < math.max(35, self.Surface.AbsoluteSize.X*0.08) or math.abs(delta.X) <= math.abs(delta.Y)*1.3 then return 0 end
	return if delta.X < 0 then 1 else -1
end
function BlockPreviewView.Step(self: any, dt: number)
	if not self.Open then return end
	local roomSize=self.Room.AbsoluteSize
	local compact=roomSize.X>0 and roomSize.X<680 and roomSize.Y>roomSize.X
	if compact~=self.Compact then self:Layout(compact) end
	self.Age += dt;self.Slide *= math.exp(-Style.Pacing.BlockSpeed*dt)
	if self.Model then self.Model:PivotTo(CFrame.new(self.Slide*0.3, math.sin(self.Age*1.8)*0.12, 0)*CFrame.Angles(0, self.Age*0.6, 0)) end
	for _,preview in self.PetPreviews do Style.RotatePetPreview(preview,self.Age) end
	if self.Age>=(self.PreviewRetryAt or 0) then
		self.PreviewRetryAt=self.Age+1
		self:RefreshModel()
		for preview,id in self.PendingPreviews or {} do
			if Style.PetVisual and Style.PetModels and Style.PetModels:FindFirstChild(id) then
				local model=Style.PetVisual.Create(Style.PetModels,id,preview,2.3,self.Catalog.Items.Pets[id])
				if model then
					for _,child in preview:GetChildren() do if child:IsA("BasePart") then child:Destroy() end end
					self.PendingPreviews[preview]=nil
				end
			end
		end
	end
	local size = self.Viewport.AbsoluteSize
	local aspect = if size.Y>0 then size.X/size.Y else 1.5
	self.Camera.FieldOfView = math.clamp(42/math.min(1, math.max(0.35, aspect)), 42, 80)
end
function BlockPreviewView.Destroy(self: any)
	self:Show(false)
	if self.Model then self.Model:Destroy();self.Model=nil end
	self.ModelSource=nil;Style.Dispose(self.Gui)
end
return BlockPreviewView

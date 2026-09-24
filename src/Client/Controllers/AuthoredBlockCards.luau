--!strict
-- Bind repeated authored cards, including nested controls and arbitrary template names.
local Cards={}
local Style=require(script.Parent.UIStyle)
local function text(root: Instance,names: {string}): TextLabel?
	for _,name in names do
		local item=root:FindFirstChild(name,true)
		if item and item:IsA("TextLabel") then return item end
	end
	return nil
end
local function candidates(root: Instance): {GuiObject}
	local found={}
	for _,item in root:GetDescendants() do
		if item:IsA("GuiObject") and not item:IsA("ViewportFrame")
			and item:FindFirstChildWhichIsA("ViewportFrame",true)
			and item:FindFirstChildWhichIsA("TextLabel",true) then table.insert(found,item) end
	end
	local result={}
	for _,item in found do
		local wrapper=false
		for _,other in found do if other~=item and other:IsDescendantOf(item) then wrapper=true;break end end
		if not wrapper then table.insert(result,item) end
	end
	table.sort(result,function(a,b)
		if a.LayoutOrder~=b.LayoutOrder then return a.LayoutOrder<b.LayoutOrder end
		if a.Position.Y~=b.Position.Y then
			if a.Position.Y.Scale~=b.Position.Y.Scale then return a.Position.Y.Scale<b.Position.Y.Scale end
			return a.Position.Y.Offset<b.Position.Y.Offset
		end
		if a.Position.X.Scale~=b.Position.X.Scale then return a.Position.X.Scale<b.Position.X.Scale end
		if a.Position.X.Offset~=b.Position.X.Offset then return a.Position.X.Offset<b.Position.X.Offset end
		return a.Name<b.Name
	end)
	return result
end
function Cards.Bind(odds: GuiObject,authored: any): {any}
	local slots,templates={},{}
	for _,card in candidates(odds) do
		local ancestor: Instance?=card
		local template=card.Name:lower():find("template",1,true)~=nil
		while ancestor and ancestor~=odds do
			if ancestor.Name=="Templates" then template=true end
			ancestor=ancestor.Parent
		end
		table.insert(if template then templates else slots,card)
	end
	local source=templates[1] or slots[1]
	-- Empty odds grids can reuse a saved inventory/pet-shop card from the same HUD.
	if not source then
		for _,card in candidates(authored.Lobby) do
			if card:FindFirstChild("Level",true) or card:FindFirstChild("Rarity",true) or card:GetAttribute("PetName") then source=card;break end
		end
	end
	if not source then
		source=Style.Frame(odds,"PetReward1",UDim2.fromScale(0.48,0.48),UDim2.new(),Color3.fromRGB(30,25,45),0)
		source:SetAttribute("RuntimeCard",true);source.LayoutOrder=1
		Style.Text(source,"PetName","",UDim2.fromScale(0.94,0.16),UDim2.fromScale(0.03,0.64),22)
		Style.Text(source,"Rarity","",UDim2.fromScale(0.94,0.12),UDim2.fromScale(0.03,0.52),17)
		Style.Text(source,"Chance","",UDim2.fromScale(0.94,0.16),UDim2.fromScale(0.03,0.82),24)
		local preview=Style.Node(source,"Preview","ViewportFrame")
		preview.Size,preview.Position,preview.BackgroundTransparency=UDim2.fromScale(0.92,0.5),UDim2.fromScale(0.04,0.02),1
		table.insert(slots,source)
	end
	while #slots<4 do
		local index=#slots+1
		local card=source:Clone();card.Name="PetReward"..index
		card:SetAttribute("RuntimeCard",true)
		card.AnchorPoint=Vector2.zero
		card.Size=UDim2.fromScale(0.48,0.48)
		card.Position=UDim2.fromScale((index-1)%2*0.52,math.floor((index-1)/2)*0.52)
		card.LayoutOrder=index;card.Parent=odds
		table.insert(slots,card)
		-- Inventory buttons/XP are not actions in a reward preview.
		for _,child in card:GetDescendants() do
			if child:IsA("GuiButton") then child.Active=false;child.Selectable=false;child.Visible=false end
			if child:IsA("GuiObject") and (child.Name=="XPBar" or child.Name=="Level" or child.Name=="CopyCount" or child.Name=="Copies" or child.Name=="EquippedBadge") then child.Visible=false end
		end
	end
	local result={}
	for index,card in slots do
		card.Visible=index<=4
		if index>4 then continue end
		local function label(name: string,aliases: {string},y: number): TextLabel
			local found=text(card,aliases)
			if found then return found end
			-- Clone the card's own authored label, keeping its font/outline styling.
			local seed=card:FindFirstChildWhichIsA("TextLabel",true)
			assert(seed,"Pet reward card needs an authored TextLabel")
			local copy=seed:Clone();copy.Name=name;copy.AnchorPoint=Vector2.zero
			copy.Size,copy.Position=UDim2.fromScale(0.94,0.16),UDim2.fromScale(0.03,y)
			copy.BackgroundTransparency,copy.ZIndex,copy.Visible=1,5,true
			copy.Parent=card
			return copy
		end
		local name=label("PetName",{"PetName","Name"},0.64)
		local chance=label("Chance",{"Chance","Odds","Percentage"},0.82)
		local rarity=text(card,{"Rarity","PetRarity"})
		if card:GetAttribute("RuntimeCard") and rarity then
			rarity.Size,rarity.Position=UDim2.fromScale(0.94,0.12),UDim2.fromScale(0.03,0.52)
		end
		local preview=card:FindFirstChildWhichIsA("ViewportFrame",true)
		local function show(node: Instance)
			local ancestor: Instance?=node
			while ancestor and ancestor~=odds do
				if ancestor:IsA("GuiObject") then ancestor.Visible=true end
				ancestor=ancestor.Parent
			end
		end
		show(name);show(chance);show(preview)
		if rarity then show(rarity) end
		authored.Remember(card);for _,child in card:GetDescendants() do authored.Remember(child) end
		table.insert(result,{Card=card,Name=name,Chance=chance,Rarity=rarity,Preview=preview})
	end
	return result
end
return Cards

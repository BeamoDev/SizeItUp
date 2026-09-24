--!strict
local ChairShop = {}
-- Binds the authored chairs in Workspace.Game.Interactables.Chairs.Chairs. Each chair's inner Model PrimaryPart holds a Custom-style
-- ProximityPrompt (created here when missing); the chair, inner model and part get the ChairShopId attribute
-- the server handler and client prompt text key off. The optional
-- ChairId attribute overrides the name lookup (Basic -> Classic, ElectricChair -> Electric via the catalog).
function ChairShop.Bind(root: Instance, catalog: any, warn: (string) -> ()): {any}
	local bound, seen = {}, {}
	for _, model in root:GetChildren() do
		if not model:IsA("Model") then continue end
		local id = model:GetAttribute("ChairId") or catalog.ChairModelIds[model.Name] or model.Name
		local item = type(id) == "string" and catalog.Items.Chairs[id]
		if not item or not table.find(catalog.ChairShopOrder, id) then
			warn("Chair model '" .. model.Name .. "' is not one of the sold chairs and was ignored.")
		elseif seen[id] then warn("Chair '" .. id .. "' appears twice; ignoring " .. model.Name .. ".")
		else
			seen[id] = true
			-- The prompt sits on the PrimaryPart of the chair's inner Model (set to its first part when unset).
			local inner = model:FindFirstChild("Model")
			inner = if inner and inner:IsA("Model") then inner else model
			local anchor = inner.PrimaryPart or inner:FindFirstChildWhichIsA("BasePart", true)
			if anchor and not inner.PrimaryPart then inner.PrimaryPart = anchor end
			local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "ProximityPrompt"
				prompt.RequiresLineOfSight = false
			end
			prompt.Parent = anchor or inner
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt.MaxActivationDistance, prompt.HoldDuration = 15, 1
			model:SetAttribute("ChairShopId", id)
			-- Display chairs are for looking at: no part of them blocks a player.
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then part.CanCollide = false end
			end
			if model:IsA("BasePart") then model.CanCollide = false end
			inner:SetAttribute("ChairShopId", id)
			if prompt.Parent ~= model and prompt.Parent ~= inner then prompt.Parent:SetAttribute("ChairShopId", id) end
			prompt.ObjectText = item.Name
			prompt.ActionText = if item.Price == 0 then "Equip" else "Buy"
			prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
			-- Default tag text; each player's client swaps the price for "Owned" and styles the name.
			local tag = model:FindFirstChild("Tag")
			local nameLabel, priceLabel = tag and tag:FindFirstChild("ChairName", true), tag and tag:FindFirstChild("Price", true)
			if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = item.Name .. " Chair" end
			if priceLabel and priceLabel:IsA("TextLabel") then
				local reversed = string.reverse(tostring(item.Price))
				-- Keep gsub's second (replacement-count) return out of string.reverse.
				local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
				grouped = string.gsub(string.reverse(grouped), "^,", "")
				priceLabel.Text = if item.Price == 0 then "Owned" else "$" .. grouped
			end
			table.insert(bound, { Model = model, Prompt = prompt, Id = id })
		end
	end
	for _, id in catalog.ChairShopOrder do
		if not seen[id] then warn("No authored chair model found for '" .. id .. "'.") end
	end
	return bound
end
local rarityColors = {Common=Color3.fromRGB(150,215,255),Uncommon=Color3.fromRGB(90,245,110),Rare=Color3.fromRGB(210,100,255),Legendary=Color3.fromRGB(255,200,35),Mythic=Color3.fromRGB(150,90,255)}
function ChairShop.Ensure(lobby: Instance, catalog: any, visual: any)
	if lobby:FindFirstChild("ChairShop") then return end
	local courtyard = lobby:FindFirstChild("Courtyard")
	if not courtyard or not courtyard:IsA("BasePart") then return end
	-- Back edge of the courtyard, beyond both table rows and their exits.
	local frame = courtyard.CFrame*CFrame.new(0,courtyard.Size.Y/2,-35)
	local root = Instance.new("Model"); root.Name="ChairShop"
	local function part(parent: Instance,name: string,size: Vector3,cf: CFrame,color: Color3): Part
		local p=Instance.new("Part");p.Name,p.Size,p.CFrame,p.Color=name,size,cf,color
		p.Anchored,p.TopSurface,p.BottomSurface=true,Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
		p.Parent=parent;return p
	end
	part(root,"ShowroomPath",Vector3.new(116,0.12,13),frame*CFrame.new(0,0.06,2),Color3.fromRGB(232,213,149))
	for index,id in catalog.ChairShopOrder do
		local item = catalog.Items.Chairs[id]
		local cf = frame*CFrame.new((index-(#catalog.ChairShopOrder+1)/2)*11,0,0)
		local stand=Instance.new("Model");stand.Name=id.."Stand";stand:SetAttribute("ChairShopId",id);stand.Parent=root
		local rim=part(stand,"DisplayPad",Vector3.new(6,0.35,6),cf*CFrame.new(0,0.235,0),rarityColors[item.Rarity])
		rim:SetAttribute("ChairShopId",id)
		part(stand,"DisplayTop",Vector3.new(5.5,0.12,5.5),cf*CFrame.new(0,0.47,0),Color3.fromRGB(245,248,255))
		visual.Build(stand,item,cf*CFrame.new(0,0.53,0))
		local billboard=Instance.new("BillboardGui");billboard.Name="ChairSign";billboard.Adornee=rim
		billboard.Size,billboard.StudsOffsetWorldSpace,billboard.MaxDistance=UDim2.fromScale(7,2.5),Vector3.new(0,6.4,0),95
		billboard.AlwaysOnTop=false;billboard.Parent=rim
		for row,data in {{"ChairName",item.Name,Color3.new(1,1,1)},{"Rarity",string.upper(item.Rarity),rarityColors[item.Rarity]},{"Price",if item.Price==0 then "STARTER" else "$"..item.Price,Color3.fromRGB(30,255,45)}} do
			local label=Instance.new("TextLabel");label.Name,label.Text=data[1],data[2]
			label.Size,label.Position=UDim2.fromScale(1,1/3),UDim2.fromScale(0,(row-1)/3)
			label.BackgroundTransparency,label.TextScaled,label.Font=1,true,Enum.Font.FredokaOne
			label.TextColor3,label.TextStrokeColor3,label.TextStrokeTransparency=data[3],Color3.new(0,0,0),0
			label.Parent=billboard
		end
		local prompt=Instance.new("ProximityPrompt");prompt.Name="PurchaseChair"
		prompt.ObjectText,prompt.ActionText=item.Name,if item.Price==0 then "Equip" else "Buy / Equip"
		prompt.KeyboardKeyCode,prompt.GamepadKeyCode=Enum.KeyCode.E,Enum.KeyCode.ButtonX
		prompt.HoldDuration,prompt.MaxActivationDistance,prompt.RequiresLineOfSight=0.45,8,false
		prompt.Parent=rim
	end
	root.Parent=lobby
	return root
end
return ChairShop

--!strict
local Style = {}
Style.HeaderMessageSeconds = 3.5
-- Presentation only: never change reward clocks, purchase guards or input rates.
Style.Pacing = table.freeze({
	GameEnterSeconds = 0.9,
	GameExitSeconds = 0.65,
	MenuSpeed = 5,
	LobbySpeed = 5,
	InviteEnterSeconds = 1,
	HatchSeconds = 3,
	BlockSpeed = 5,
})
Style.Gold = Color3.fromRGB(255, 214, 35)
Style.Orange = Color3.fromRGB(255, 142, 30)
Style.Green = Color3.fromRGB(53, 237, 65)
Style.Purple = Color3.fromRGB(159, 44, 245)
Style.Blue = Color3.fromRGB(65, 140, 255)
Style.Pink = Color3.fromRGB(255, 105, 170)
Style.Red = Color3.fromRGB(255, 70, 75)
-- Lobby.InfoCard is optional and holds only a TextLabel: hovering a potion (a Store tier button or an active one in the
-- lobby list) shows its name there ("2x Cash"); leaving hides the card. Nothing is created if the card is missing.
function Style.PotionInfoCard(): any?
	local lobby = Style.Authoring and Style.Authoring.Lobby
	return lobby and lobby:FindFirstChild("InfoCard")
end
function Style.ShowPotionInfo(title: string)
	local card = Style.PotionInfoCard()
	if not card then
		return
	end
	local titleLabel = card:FindFirstChild("TextLabel")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = title
	end
	if card:IsA("GuiObject") then
		card.Visible = true
	else
		Style.SetVisible(card, true)
	end
end
function Style.HidePotionInfo()
	local card = Style.PotionInfoCard()
	if card then
		if card:IsA("GuiObject") then
			card.Visible = false
		else
			Style.SetVisible(card, false)
		end
	end
end
-- Wires hover (MouseEnter/MouseLeave) on any GuiObject -- a Store tier's PurchaseButton or a Lobby.Potions clone -- to
-- show/hide the InfoCard with this potion's name ("2x Cash"). A missing InfoCard makes this a no-op.
function Style.BindPotionHover(node: GuiObject, title: string)
	if not Style.PotionInfoCard() then
		return
	end
	node.MouseEnter:Connect(function()
		Style.ShowPotionInfo(title)
	end)
	node.MouseLeave:Connect(function()
		Style.HidePotionInfo()
	end)
end
function Style.MeasurementName(displayName: string?): string
	local name = (displayName or ""):match("^%s*(.-)%s*$") or ""
	-- Runtime duplicates use '(2)'; catalog variants also use names like 'Car 2'.
	name = name:gsub("%s*%(%d+%)$", ""):gsub("%s+%d+$", "")
	return string.upper(name)
end
function Style.SavePose(node: GuiObject)
	node:SetAttribute("RestPositionScale", Vector2.new(node.Position.X.Scale, node.Position.Y.Scale))
	node:SetAttribute("RestPositionOffset", Vector2.new(node.Position.X.Offset, node.Position.Y.Offset))
	node:SetAttribute("RestVisible", node.Visible)
end
function Style.RestorePose(node: Instance)
	local scale, offset = node:GetAttribute("RestPositionScale"), node:GetAttribute("RestPositionOffset")
	if node:IsA("GuiObject") and scale and offset then
		(node :: GuiObject).Position = UDim2.new(scale.X, offset.X, scale.Y, offset.Y)
		local visible = node:GetAttribute("RestVisible")
		if visible ~= nil then
			(node :: GuiObject).Visible = visible
		end
		node:SetAttribute("RestPositionScale", nil)
		node:SetAttribute("RestPositionOffset", nil)
		node:SetAttribute("RestVisible", nil)
	end
end
function Style.RestoreTree(root: Instance)
	Style.RestorePose(root)
	for _, child in root:GetChildren() do
		if child.Name == "SceneMotionScale" and child:IsA("UIScale") then
			child:Destroy()
		else
			Style.RestoreTree(child)
		end
	end
end
-- Named children are the binding contract for UI copied into StarterGui.
-- Reuse the actual instances so existing layouts and button connections agree.
function Style.Node(parent: Instance, name: string, className: string): any
	local object = parent:FindFirstChild(name)
	if
		not object
		and Style.Authoring
		and (
			className:find("Gui")
			or className:find("Frame")
			or className:find("Label")
			or className:find("Button")
			or className:sub(1, 2) == "UI"
		)
	then
		object = Style.Authoring.CloneTemplate(parent, name, className)
		if not object and Style.Authoring.CanFill and Style.Authoring.CanFill(parent) then
			object = Instance.new(className)
			object.Name, object.Parent = name, parent
			object:SetAttribute("FilledUI", true)
			object:SetAttribute("FillStylePending", true)
		end
		assert(
			object,
			"Missing authored UI: "
				.. parent:GetFullName()
				.. "."
				.. name
				.. " ("
				.. className
				.. "). This control is outside the menu content containers."
		)
	end
	if object then
		assert(object:IsA(className), name .. " must be a " .. className)
		Style.RestorePose(object)
		if className == "ScreenGui" then
			Style.RestoreTree(object)
		end
		if Style.BindingContent and object:IsA("GuiObject") then
			object.Visible = true
		end
		return object
	end
	object = Instance.new(className)
	if className == "ScreenGui" then
		object.Enabled = false
	end
	object.Name, object.Parent = name, parent
	return object
end
-- Startup may temporarily force Enabled=false. Retain the controller's desired
-- state even when assigning false would not emit a property-change event.
function Style.SetEnabled(gui: Instance, enabled: boolean)
	gui:SetAttribute("RuntimeEnabled", enabled)
	Style.SetVisible(gui, enabled)
end
function Style.SetVisible(gui: any, enabled: boolean)
	if gui:IsA("GuiObject") then
		gui.Visible = enabled
	else
		gui.Enabled = enabled
	end
end
function Style.IgnoreInset(gui: Instance): boolean
	local screen = if gui:IsA("ScreenGui") then gui else gui:FindFirstAncestorWhichIsA("ScreenGui")
	return screen ~= nil and (screen :: ScreenGui).IgnoreGuiInset
end
function Style.IsEnabled(gui: any): boolean
	return if gui:IsA("GuiObject") then gui.Visible else gui.Enabled
end
function Style.Roots(playerGui: PlayerGui): { Instance }
	return if Style.Authoring then Style.Authoring.Roots(playerGui) else playerGui:GetChildren()
end
function Style.ClearChildren(parent: Instance)
	if Style.Authoring then
		Style.Authoring.ClearChildren(parent)
		return
	end
	for _, node in parent:GetChildren() do
		if Style.Authoring then
			if node:IsA("GuiObject") then
				node.Visible = false
			end
		else
			node:Destroy()
		end
	end
end
function Style.Dispose(gui: Instance)
	if Style.Authoring then
		Style.Authoring.RestoreParked(gui)
		Style.SetEnabled(gui, false)
	else
		gui:Destroy()
	end
end
function Style.Text(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	maximum: number?
): TextLabel
	if Style.Authoring then
		local label = Style.Node(parent, name, "TextLabel")
		label.Text = text
		if label:GetAttribute("FillStylePending") then
			label.Size, label.Position, label.BackgroundTransparency, label.BorderSizePixel = size, position, 1, 0
			label.Font, label.TextColor3, label.TextStrokeColor3, label.TextStrokeTransparency =
				Enum.Font.FredokaOne, Color3.new(1, 1, 1), Color3.new(), 0
			label.TextScaled, label.TextWrapped = true, true
			local limit = Style.Node(label, "TextSizeLimit", "UITextSizeConstraint")
			limit.MaxTextSize, limit.MinTextSize = maximum or 28, 8
			label:SetAttribute("FillStylePending", nil)
		end
		return label
	end
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("TextLabel"), name .. " must be a TextLabel")
		Style.RestorePose(existing)
		existing.Text = text
		return existing :: TextLabel
	end
	local label = Instance.new("TextLabel")
	label.Name, label.Text, label.Size, label.Position = name, text, size, position
	label.BackgroundTransparency, label.BorderSizePixel, label.Font = 1, 0, Enum.Font.FredokaOne
	label.TextColor3, label.TextStrokeColor3, label.TextStrokeTransparency = Color3.new(1, 1, 1), Color3.new(), 0
	label.TextScaled, label.TextWrapped = true, true
	local limit = Instance.new("UITextSizeConstraint")
	limit.Name = "TextSizeLimit"
	limit.MaxTextSize, limit.MinTextSize, limit.Parent = maximum or 28, 8, label
	label.Parent = parent
	return label
end
function Style.Round(object: Instance, radius: number?, thickness: number?)
	if Style.Authoring and not object:GetAttribute("FilledUI") then
		return
	end
	if not object:FindFirstChild("Corners") then
		local corner = Style.Node(object, "Corners", "UICorner")
		corner.CornerRadius = UDim.new(0, radius or 12)
	end
	if not object:FindFirstChild("Border") then
		local stroke = Style.Node(object, "Border", "UIStroke")
		stroke.ApplyStrokeMode, stroke.Color, stroke.Thickness =
			Enum.ApplyStrokeMode.Border, Color3.fromRGB(28, 22, 32), thickness or 3
	end
end
function Style.Frame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3?,
	transparency: number?
): Frame
	if Style.Authoring then
		local frame = Style.Node(parent, name, "Frame")
		if frame:GetAttribute("FillStylePending") then
			frame.Size, frame.Position, frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel =
				size, position, color or Style.Gold, transparency or 0.08, 0
			Style.Round(frame)
			frame:SetAttribute("FillStylePending", nil)
		end
		return frame
	end
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Frame"), name .. " must be a Frame")
		Style.RestorePose(existing)
		Style.Round(existing)
		return existing :: Frame
	end
	local frame = Instance.new("Frame")
	frame.Name, frame.Size, frame.Position = name, size, position
	frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel =
		color or Style.Gold, transparency or 0.08, 0
	frame.Parent = parent
	Style.Round(frame)
	return frame
end
function Style.Gradient(frame: Instance, top: Color3?, bottom: Color3?)
	if Style.Authoring and not frame:GetAttribute("FilledUI") then
		return
	end
	local gradient = Style.Node(frame, "BackgroundGradient", "UIGradient")
	gradient.Color = ColorSequence.new(top or Style.Gold, bottom or Style.Orange)
	gradient.Rotation = 90
end
function Style.Button(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3?
): TextButton
	if Style.Authoring then
		local button = parent:FindFirstChild(name)
		if button and button:IsA("GuiButton") then
			if Style.BindingContent then
				button.Visible = true
			end
			Style.Caption(button, text)
			return button
		end
		button = Style.Node(parent, name, "TextButton")
		if button:GetAttribute("FillStylePending") then
			button.Size, button.Position, button.Text = size, position, ""
			button.BackgroundColor3, button.BackgroundTransparency, button.BorderSizePixel, button.AutoButtonColor =
				color or Style.Green, 0.03, 0, true
			Style.Round(button)
			Style.Text(button, "Caption", text, UDim2.fromScale(0.92, 0.86), UDim2.fromScale(0.04, 0.07), 25)
			button:SetAttribute("FillStylePending", nil)
		end
		Style.Caption(button, text)
		return button
	end
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("TextButton"), name .. " must be a TextButton")
		Style.RestorePose(existing)
		Style.Round(existing)
		Style.Text(existing, "Caption", text, UDim2.fromScale(0.92, 0.86), UDim2.fromScale(0.04, 0.07), 25)
		return existing :: TextButton
	end
	local button = Instance.new("TextButton")
	button.Name, button.Size, button.Position, button.Text = name, size, position, ""
	button.BackgroundColor3, button.BackgroundTransparency, button.BorderSizePixel, button.AutoButtonColor =
		color or Style.Green, 0.03, 0, true
	button.Parent = parent
	Style.Round(button)
	Style.Text(button, "Caption", text, UDim2.fromScale(0.92, 0.86), UDim2.fromScale(0.04, 0.07), 25)
	return button
end
-- Shows a fading alert (HUD.Alerts.Template clone): kind is Info, Good, Bad, Help, Sabotage or Notice. AlertController sets
-- Style.Alerts; without it this does nothing.
-- Money with thousands separators: 80000 -> "$80,000".
function Style.Money(amount: number): string
	local text = tostring(math.floor(math.abs(amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (if amount < 0 then "-$" else "$") .. string.gsub(string.reverse(grouped), "^,", "")
end
function Style.Alert(message: string, kind: string?, options: any?)
	local alerts = Style.Alerts
	if alerts then
		alerts:Show(message, kind, options)
	end
end
-- Plays a sound effect by name (Click, Swoosh, Pop, ...). SfxController sets Style.Sfx; without it this does nothing.
function Style.Play(name: string, options: any?)
	local sfx = Style.Sfx
	if sfx then
		sfx:Play(name, options)
	end
end
function Style.Caption(button: TextButton, text: string)
	local label = button:FindFirstChild("Caption") or button:FindFirstChildWhichIsA("TextLabel")
	if label then
		(label :: TextLabel).Text = text
	elseif button:IsA("TextButton") then
		button.Text = text
	end
end
-- The stroke gradients authored per rarity are named Common, UnCommon, Rare, Epic, Gold (Legendary) and Mythic.
local RARITY_GRADIENTS =
	{ Common = "Common", Uncommon = "UnCommon", Rare = "Rare", Epic = "Epic", Legendary = "Gold", Mythic = "Mythic" }
-- Enables only the gradient under `container` (e.g. an OuterUIStroke) that matches the rarity; the others go off.
function Style.SelectRarityGradients(container: Instance, rarity: string?)
	local wanted = RARITY_GRADIENTS[rarity or "Common"] or "Common"
	for _, child in container:GetChildren() do
		if child:IsA("UIGradient") then
			child.Enabled = child.Name == wanted
		end
	end
end
-- Shows the rarity as text with its gradient: the label's UIGradient takes the rarity's colours (a rainbow for Mythic).
function Style.RarityLabel(label: TextLabel, rarity: string, styles: any?)
	label.Text = rarity
	label.TextColor3 = Color3.new(1, 1, 1)
	styles = styles or {}
	local look = styles[rarity] or styles.Common or { Tint = { 255, 255, 255 }, Accent = { 255, 255, 255 } }
	local gradient = label:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "RarityGradient"
		gradient.Parent = label
	end
	gradient.Enabled = true
	gradient.Color = if look.Rainbow
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 230, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
		})
		else ColorSequence.new(Color3.fromRGB(table.unpack(look.Tint)), Color3.fromRGB(table.unpack(look.Accent)))
end
function Style.PetRarity(label: TextLabel, item: any)
	if Style.Authoring and not label:GetAttribute("FilledUI") then
		local gradient = label:FindFirstChild("RarityGradient")
		if gradient then
			gradient.Enabled = item.Rarity == "Mythic"
		end
		if item.Presentation then
			label.TextColor3 = Color3.fromRGB(table.unpack(item.Presentation.Tint))
		end
		return
	end
	if Style.PetVisual and Style.PetVisual.StyleLabel then
		Style.PetVisual.StyleLabel(label, item)
	elseif item.Presentation then
		label.TextColor3 = Color3.fromRGB(table.unpack(item.Presentation.Tint))
	end
end
-- The authored chair model (ReplicatedStorage.Assets.Chairs.<Name>.Model; Electric is "ElectricChair"), if there is one.
function Style.ChairAsset(item: any): Instance?
	local assets = Style.AssetStorage and Style.AssetStorage:FindFirstChild("Assets")
	local chairs = assets and assets:FindFirstChild("Chairs")
	if not chairs or not item or not item.Name then
		return nil
	end
	local holder = chairs:FindFirstChild(item.Name) or chairs:FindFirstChild(item.Name .. "Chair")
	if not holder then
		return nil
	end
	local model = holder:FindFirstChild("Model")
	if model then
		return model
	end
	return if holder:IsA("Model") or holder:IsA("BasePart") then holder else nil
end
function Style.Preview(parent: Instance, item: any, kind: string, boundFrame: ViewportFrame?): ViewportFrame
	local frame = boundFrame or Style.Node(parent, "Preview", "ViewportFrame")
	if not boundFrame then
		frame.Name, frame.Size, frame.Position, frame.BackgroundTransparency =
			"Preview", UDim2.fromScale(0.84, 0.53), UDim2.fromScale(0.08, 0.22), 1
		frame.Parent = parent
	end
	frame.Ambient, frame.LightColor = Color3.new(0.7, 0.7, 0.7), Color3.new(1, 1, 1)
	frame:SetAttribute("RotatingPet", kind == "Pets" and item.Name ~= nil)
	local camera = Style.Node(frame, "PreviewCamera", "Camera")
	camera.CFrame, camera.FieldOfView, camera.Parent = CFrame.lookAt(Vector3.new(3, 2, 5), Vector3.zero), 38, frame
	frame.CurrentCamera = camera
	for _, child in frame:GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") then
			child:Destroy()
		end
	end
	if kind == "Chairs" and Style.BlockVisual then
		-- The real chair model, centred and sized for the viewport; chairs without one fall back to the built-in shape.
		local source = Style.ChairAsset(item)
		local model = source and Style.BlockVisual.Create(source, frame)
		if model then
			frame:SetAttribute("RotatingPet", true)
			camera.CFrame = CFrame.lookAt(Vector3.new(4, 2.4, 5.5), Vector3.zero)
			return frame
		end
	end
	if kind == "Chairs" and item.Visual and Style.ChairVisual then
		Style.ChairVisual.Build(frame, item, CFrame.new(0, -1.8, 0), 0.8)
		camera.CFrame = CFrame.lookAt(Vector3.new(4, 2, 7), Vector3.zero)
		return frame
	end
	local tint = Color3.fromRGB(table.unpack(item.Color or { 255, 225, 80 }))
	if kind == "Pets" and item.AssetId and Style.PetVisual and Style.PetModels:FindFirstChild(item.AssetId) then
		Style.PetVisual.Create(Style.PetModels, item.AssetId, frame, 2.3, item)
		return frame
	end
	local pieceIndex = 0
	local function piece(size: Vector3, position: Vector3)
		pieceIndex += 1
		local part = Style.Node(frame, "PreviewPart" .. pieceIndex, "Part")
		part.Size, part.CFrame, part.Color, part.Anchored, part.Parent = size, CFrame.new(position), tint, true, frame
	end
	if kind == "Chairs" then
		piece(Vector3.new(2, 0.25, 2), Vector3.new(0, -0.2, 0))
		piece(Vector3.new(2, 1.8, 0.25), Vector3.new(0, 0.6, 0.9))
		for _, x in { -0.8, 0.8 } do
			for _, z in { -0.8, 0.8 } do
				piece(Vector3.new(0.2, 1.3, 0.2), Vector3.new(x, -0.9, z))
			end
		end
	else
		piece(Vector3.one * 1.8, Vector3.zero)
	end
	return frame
end
function Style.RotatePetPreview(frame: ViewportFrame, seconds: number)
	if Style.PetVisual and Style.PetVisual.Step then
		local model = frame:FindFirstChild("PetModel")
		if model then
			Style.PetVisual.Step(model, seconds, true)
		end
		-- Direct named labels only; no per-frame scan of the full menu tree.
		for _, parent in { frame.Parent, frame.Parent and frame.Parent.Parent } do
			for _, name in { "PetName", "Rarity" } do
				Style.PetVisual.StepLabel(parent:FindFirstChild(name), seconds)
			end
		end
	end
	local camera = frame:FindFirstChild("PreviewCamera")
	if camera and frame:GetAttribute("RotatingPet") then
		local angle = seconds * math.rad(24) + math.rad(25);
		(camera :: Camera).CFrame =
			CFrame.lookAt(Vector3.new(math.sin(angle) * 4.1, 1.5, math.cos(angle) * 4.1), Vector3.zero)
	end
end
return Style

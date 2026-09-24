--!strict
-- The two requested rulers are runtime overlays; all other HUD controls stay authored.
-- Reference and target rulers use plain white text/markers with a black outline. Result praise can opt into the
-- green-white-green treatment without leaking that styling back onto the rulers.
local GREEN_WHITE_GREEN = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(74,255,116)),
	ColorSequenceKeypoint.new(0.5, Color3.new(1,1,1)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(74,255,116)),
})
local function styleRulerFont(label: any)
	local ok = pcall(function() label.FontFace = Font.fromName("Montserrat", Enum.FontWeight.Heavy) end)
	if not ok then label.Font = Enum.Font.GothamBlack end
end
local MeasurementUI = {}
MeasurementUI.StyleFont = styleRulerFont
local RULER_Z = 0
local function node(parent: Instance, name: string, className: string): any
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA(className), name.." must be a "..className)
		return existing
	end
	local item = Instance.new(className)
	item.Name, item.Parent = name, parent
	return item
end
local function styleMarker(marker: Frame, rounded: boolean)
	marker.BackgroundColor3, marker.BackgroundTransparency, marker.BorderSizePixel = Color3.new(1,1,1), 0, 0
	marker.AnchorPoint, marker.ZIndex, marker.Active = Vector2.new(0.5,0.5), RULER_Z, false
	local corner = node(marker,"RoundDot","UICorner")
	corner.CornerRadius = if rounded then UDim.new(0.35,0) else UDim.new(1,0)
	local stroke = node(marker,"BlackOutline","UIStroke")
	stroke.Color, stroke.Transparency, stroke.Thickness = Color3.new(), 0, 2
	for _,child in marker:GetChildren() do if child:IsA("UIGradient") then child.Enabled=false end end
end
function MeasurementUI.StyleLabel(label: TextLabel,gradientName: string?,thickness: number?): UIStroke
	styleRulerFont(label)
	label.TextColor3=Color3.new(1,1,1)
	label.TextStrokeTransparency=1
	local stroke=node(label,"BlackOutline","UIStroke")
	stroke.Color,stroke.Transparency,stroke.Thickness=Color3.new(),0,thickness or 2.5
	local gradient = if gradientName then node(label,gradientName,"UIGradient") else nil
	if gradient then gradient.Color,gradient.Rotation=GREEN_WHITE_GREEN,90 end
	for _,child in label:GetChildren() do if child:IsA("UIGradient") then child.Enabled=child==gradient end end
	return stroke
end
MeasurementUI.StyleMarker=styleMarker
function MeasurementUI.Ensure(parent: Instance, prefix: string): Frame
	local root = node(parent, prefix.."Measurement", "Frame")
	root.Size, root.Position, root.AnchorPoint = UDim2.fromScale(1,1), UDim2.new(), Vector2.zero
	root.BackgroundTransparency, root.BorderSizePixel, root.ZIndex = 1, 0, RULER_Z
	root.Visible, root.Active, root.ClipsDescendants = false, false, false
	-- Authored labels keep their layout identity, while ruler-owned typography and depth stay responsive/behind the HUD.
	local function label(name: string, isName: boolean)
		local text = node(root, name, "TextLabel")
		text.BackgroundTransparency, text.BorderSizePixel, text.ZIndex = 1, 0, RULER_Z
		MeasurementUI.StyleLabel(text)
		text.TextStrokeColor3, text.TextTransparency = Color3.new(), 0
		text.TextScaled, text.TextWrapped, text.Active = isName, isName, false
		text.AnchorPoint = Vector2.zero
		text.Visible = name~="EstimatedHeight"
		text.TextSize = if isName then 20 else 40
		local limit = node(text, "TextSizeLimit", "UITextSizeConstraint")
		limit.MinTextSize, limit.MaxTextSize = if isName then 12 else 20, if isName then 22 else 44
	end
	label("ObjectName", true)
	label(if prefix=="Reference" then "RealHeight" else "UnknownHeight", false)
	if prefix=="Mystery" then
		label("EstimatedHeight", false)
		-- Results only: a small round headshot above the caption stack, showing whose attempt is growing.
		local mugshot = node(root, "PlayerMugshot", "ImageLabel")
		mugshot.BackgroundTransparency, mugshot.BorderSizePixel, mugshot.ZIndex = 0, 0, RULER_Z
		mugshot.ScaleType, mugshot.Visible, mugshot.Active = Enum.ScaleType.Fit, false, false
		-- UIAspectRatio is not a class Lune's test polyfill knows; the manual square offset size below
		-- already keeps this a 1:1 circle either way, so a failure here is harmless in tests.
		pcall(function() node(mugshot, "MugshotAspect", "UIAspectRatio").AspectRatio = 1 end)
		node(mugshot, "MugshotCorner", "UICorner").CornerRadius = UDim.new(1, 0)
		local stroke = node(mugshot, "ProfileOutline", "UIStroke")
		stroke.Color, stroke.Transparency, stroke.Thickness = Color3.new(), 0, 2
	end
	for _, name in {"TopCap","BottomCap"} do
		local cap = node(root,name,"Frame")
		cap.Visible = false
		styleMarker(cap,true)
	end
	for i=1,64 do
		local dot = node(root, "HeightDot"..i, "Frame")
		dot.Size, dot.Visible = UDim2.fromOffset(8,12), false
		styleMarker(dot,true)
	end
	return root
end
return MeasurementUI

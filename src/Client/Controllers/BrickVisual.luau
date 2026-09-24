--!strict
-- Temporary owner-requested art. Colors are sampled by the server once per pair.
local BrickVisual = {}
function BrickVisual.Create(definition: any, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = definition.ModelName
	local brick = Instance.new("Part")
	brick.Name, brick.Size = "Brick", Vector3.new(2, 4, 2)
	brick.Anchored, brick.CanCollide, brick.CanTouch, brick.CanQuery = true, false, false, false
	brick.Material = Enum.Material.SmoothPlastic
	brick.Color = Color3.fromHSV(definition.Hue or 0.5, 0.65, 0.95)
	brick.Parent = model
	local board = Instance.new("BillboardGui")
	board.Name, board.Adornee, board.AlwaysOnTop = "ObjectLabel", brick, true
	board.Size, board.StudsOffsetWorldSpace = UDim2.fromScale(4, 0.9), Vector3.new(0, 2.8, 0)
	board.Parent = brick
	local text = Instance.new("TextLabel")
	text.Name, text.Text = "ObjectName", definition.DisplayName
	text.Size, text.BackgroundTransparency, text.BorderSizePixel = UDim2.fromScale(1, 1), 1, 0
	text.BackgroundColor3, text.TextColor3 = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
	text.Font, text.TextSize, text.TextWrapped = Enum.Font.FredokaOne, 20, true
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Parent = board
	local corner = Instance.new("UICorner");corner.Name="Corners"
	corner.CornerRadius, corner.Parent = UDim.new(0, 8), text
	model.Parent = parent
	return model
end
return BrickVisual

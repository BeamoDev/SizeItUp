--!strict
-- Procedural cosmetic chairs shared by world stock, inventory and equipped displays.
-- Never create Seat instances: display chairs must not enter the match queue.
local ChairVisual = {}
function ChairVisual.Build(parent: Instance, item: any, frame: CFrame, scale: number?): Model
	local sizeScale = scale or 1
	local model = Instance.new("Model")
	model.Name = "ChairModel"
	local tint = Color3.fromRGB(table.unpack(item.Color))
	local style = item.Visual or item.Name
	local material = if style == "Wooden" or style == "Moon"
		then Enum.Material.Wood
		elseif style == "Glass" then Enum.Material.Glass
		elseif style == "RGB" or style == "Electric" then Enum.Material.Neon
		else Enum.Material.SmoothPlastic
	local function piece(
		name: string,
		size: Vector3,
		position: Vector3,
		color: Color3?,
		shape: Enum.PartType?
	): BasePart
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color =
			name, size * sizeScale, frame * CFrame.new(position * sizeScale), color or tint
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Material, p.TopSurface, p.BottomSurface = material, Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if style == "Glass" then
			p.Transparency = 0.45
		end
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	local seat = piece("SeatCushion", Vector3.new(2.4, 0.35, 2.4), Vector3.new(0, 1.5, 0))
	model.PrimaryPart = seat
	if style == "Moon" then
		for _, x in { -1.65, 1.65 } do
			piece(if x < 0 then "LeftPost" else "RightPost", Vector3.new(0.3, 4.6, 0.3), Vector3.new(x, 2.3, 0))
		end
		piece("TopBeam", Vector3.new(3.65, 0.3, 0.3), Vector3.new(0, 4.6, 0))
		for i, x in { -1, 1 } do
			piece("Rope" .. i, Vector3.new(0.09, 2.9, 0.09), Vector3.new(x, 3, 0), Color3.fromRGB(235, 225, 185))
		end
	elseif style == "Goop" or style == "Slime" then
		piece("Puddle", Vector3.new(3.2, 0.5, 3), Vector3.new(0, 0.25, 0), nil, Enum.PartType.Ball)
		piece("BlobBody", Vector3.new(2, 2, 2), Vector3.new(0, 1.1, 0), nil, Enum.PartType.Ball)
		piece("BlobBack", Vector3.new(2.4, 2.6, 0.9), Vector3.new(0, 2.35, 0.9), nil, Enum.PartType.Ball)
		for i, x in { -0.45, 0.45 } do
			piece("Eye" .. i, Vector3.new(0.25, 0.35, 0.1), Vector3.new(x, 2.55, 0.41), Color3.new(0, 0, 0))
		end
	else
		local legIndex = 0
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				legIndex += 1
				piece("Leg" .. legIndex, Vector3.new(0.24, 1.4, 0.24), Vector3.new(x, 0.7, z))
			end
		end
		if style == "Flower" then
			piece("Stem", Vector3.new(0.25, 2.4, 0.25), Vector3.new(0, 2.4, 1), Color3.fromRGB(65, 190, 60))
			for i = 1, 6 do
				local angle = i * math.pi / 3
				piece(
					"Petal" .. i,
					Vector3.new(1.1, 1.1, 0.35),
					Vector3.new(math.cos(angle) * 0.8, 3 + math.sin(angle) * 0.8, 1),
					nil,
					Enum.PartType.Ball
				)
			end
			piece(
				"FlowerCenter",
				Vector3.new(0.9, 0.9, 0.4),
				Vector3.new(0, 3, 0.8),
				Color3.fromRGB(255, 145, 35),
				Enum.PartType.Ball
			)
		else
			local tall = style == "Throne"
			piece(
				"Backrest",
				Vector3.new(2.4, if tall then 3.2 else 1.9, 0.25),
				Vector3.new(0, if tall then 3 else 2.55, 1.1)
			)
			if tall then
				piece("Velvet", Vector3.new(1.8, 2.5, 0.15), Vector3.new(0, 2.9, 0.9), Color3.fromRGB(200, 35, 70))
				for i, x in { -0.8, 0, 0.8 } do
					piece("Crown" .. i, Vector3.new(0.35, 0.6, 0.35), Vector3.new(x, 4.7, 1.1), nil, Enum.PartType.Ball)
				end
			end
		end
		if style == "RGB" or style == "Electric" or style == "Throne" then
			for i, x in { -1.15, 1.15 } do
				piece(
					"Arm" .. i,
					Vector3.new(0.25, 0.25, 2.2),
					Vector3.new(x, 2.25, 0),
					if style == "RGB" then Color3.fromRGB(20, 255, 155) else nil
				)
			end
		end
	end
	model.Parent = parent
	return model
end
return ChairVisual

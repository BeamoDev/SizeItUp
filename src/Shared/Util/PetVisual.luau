--!strict
local PetVisual = {}
local function tint(rgb)
	return Color3.fromRGB(table.unpack(rgb))
end
local function spectrum()
	local keys = {}
	for index = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 0.75, 1)))
	end
	return ColorSequence.new(keys)
end
function PetVisual.StyleLabel(label, item)
	local look = item.Presentation
	if not look then
		return
	end
	local gradient = label:FindFirstChild("RarityGradient")
	label.TextColor3 = if look.Rainbow then Color3.new(1, 1, 1) else tint(look.Tint)
	if look.Rainbow then
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "RarityGradient"
			gradient.Parent = label
		end
		gradient.Color = spectrum()
		gradient.Enabled = true
	elseif gradient then
		gradient:Destroy()
	end
end
function PetVisual.StepLabel(label, seconds)
	local gradient = label and label:FindFirstChild("RarityGradient")
	if gradient then
		gradient.Rotation = seconds * 24 % 360
	end
end
function PetVisual.Decorate(model, item, extent)
	local look = item and item.Presentation
	if not look or look.Orbits == 0 then
		return
	end
	local aura = Instance.new("Folder")
	aura.Name = "PetAura"
	aura.Parent = model
	aura:SetAttribute("Extent", extent)
	aura:SetAttribute("BaseScale", model:GetScale())
	aura:SetAttribute("Rainbow", look.Rainbow == true)
	aura:SetAttribute("Tint", tint(look.EffectTint or look.Tint))
	for index = 1, look.Orbits do
		local orb = Instance.new("Part")
		orb.Name = "OrbitLight" .. index
		orb.Shape = Enum.PartType.Ball
		orb.Anchored, orb.CanCollide, orb.CanTouch, orb.CanQuery, orb.CastShadow = true, false, false, false, false
		orb.Material = Enum.Material.Neon
		orb.Color = tint(look.EffectTint or look.Tint)
		orb.Size = Vector3.one * (extent * 0.07)
		orb.CFrame = model:GetPivot()
		orb.Parent = aura
	end
	if look.Orbits >= 2 then
		local glow = Instance.new("Highlight")
		glow.Name = "PetAuraOutline"
		glow.Adornee, glow.DepthMode, glow.FillTransparency = model, Enum.HighlightDepthMode.Occluded, 1
		glow.OutlineColor, glow.OutlineTransparency = tint(look.EffectTint or look.Tint), 0.65
		glow.Parent = model
	end
	PetVisual.Step(model, 0, true)
end
function PetVisual.Step(model, seconds, visible)
	local aura = model:FindFirstChild("PetAura")
	if not aura then
		return
	end
	local parts = aura:GetChildren()
	local frame = model:GetPivot()
	local extent = aura:GetAttribute("Extent") * model:GetScale() / aura:GetAttribute("BaseScale")
	local rainbow = aura:GetAttribute("Rainbow")
	local color = if rainbow then Color3.fromHSV(seconds * 0.12 % 1, 0.7, 1) else aura:GetAttribute("Tint")
	for index, orb in parts do
		orb.Transparency = if visible == false then 1 else 0.1 + 0.15 * (0.5 + 0.5 * math.sin(seconds * 3 + index))
		if visible == false then
			continue
		end
		local angle = seconds * 1.6 + index / #parts * math.pi * 2
		orb.Size = Vector3.one * extent * 0.07
		orb.CFrame = frame
			* CFrame.new(
				math.cos(angle) * extent * 0.6,
				math.sin(angle * 1.5) * extent * 0.28,
				math.sin(angle) * extent * 0.6
			)
		orb.Color = if rainbow then Color3.fromHSV((seconds * 0.12 + index / #parts) % 1, 0.7, 1) else color
	end
	local glow = model:FindFirstChild("PetAuraOutline")
	if glow then
		glow.Enabled = visible ~= false
		glow.OutlineColor = color
		glow.OutlineTransparency = 0.6 + 0.15 * math.sin(seconds * 2) ^ 2
	end
end
function PetVisual.Trail(anchor, item, extent)
	local look = item.Presentation
	if not look or not look.Trail then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "PetTrailLeft"
	a.Position = Vector3.new(-extent * 0.18, 0, extent * 0.2)
	a.Parent = anchor
	local b = Instance.new("Attachment")
	b.Name = "PetTrailRight"
	b.Position = Vector3.new(extent * 0.18, 0, extent * 0.2)
	b.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Name = "PetRarityTrail"
	trail.Attachment0, trail.Attachment1 = a, b
	trail.Color = if look.Rainbow
		then spectrum()
		else ColorSequence.new(tint(look.EffectTint or look.Tint), tint(look.Accent))
	trail.Lifetime, trail.MinLength, trail.MaxLength, trail.FaceCamera, trail.LightEmission = 0.45, 0.08, 7, true, 0.8
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = anchor
	return trail
end
function PetVisual.Create(models, id, parent, extent, item)
	local source = models and models:FindFirstChild(id)
	if not source then
		return nil
	end
	local model = source:Clone()
	model.Name = "PetModel"
	local bounds, size = model:GetBoundingBox()
	-- Bake the pack's 180-degree facing correction into local geometry before
	-- scaling. Followers and hatch animations can then PivotTo normally without
	-- undoing it. Shared templates and authored ServerStorage.Pets assets stay untouched.
	model.WorldPivot = CFrame.new(bounds.Position)
	model:PivotTo(CFrame.Angles(0, math.pi, 0))
	model.WorldPivot = CFrame.new()
	model:ScaleTo(model:GetScale() * (extent or 2.3) / math.max(size.X, size.Y, size.Z, 0.001))
	model.Parent = parent
	PetVisual.Decorate(model, item, extent or 2.3)
	return model
end
return PetVisual

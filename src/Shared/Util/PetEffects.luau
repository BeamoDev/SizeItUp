--!strict
-- Themed particle/light effects for world followers. Purely cosmetic: it never
-- touches odds, abilities, saves or the authored pet meshes. ParticleEmitters do
-- not render in ViewportFrames, so menus/hatches keep using PetVisual's geometry.
local PetEffects = {}

PetEffects.Themes = {
	Fire = { "Phoenix", "UniversalPhoenix", "SunFlare", "EvolvedSolis", "SunFox", "SunBunny", "Dragon", "Kitsune", "Tiger", "SunCat", "SunDoubull" },
	Water = { "WaterDragon", "OceanicBunny", "OceanicFox", "OceanicDiamond", "EvolvedOceanicDiamond", "Slime", "OceanicKitty", "OceanicStar", "OceanicWingedLord", "EvolvedOceanicTrio" },
	Nature = { "Bee", "Deer", "Bear", "Panda", "Fairy", "Lizard", "GlowingBear", "Fox", "Frog" },
	Shadow = { "DarkDragon", "DarkFairy", "Spider", "AbyssalHydra", "EvolvedAbyssalHydra", "Hydra", "Owl", "AbyssDemon", "AbyssalCerberus" },
	Holy = { "Unicorn", "Celestial", "WingedFairy", "Griffin", "Spirit", "Helios" },
	Cosmic = { "Infinity", "Alien", "UniversalHybrid", "UniversalLeviathan", "EvolvedUniversalYatagarasu", "GalacticQueen", "UniversalMegalodon" },
	Earth = { "Golem", "Bull" },
	Fluff = { "Bunny", "Cat", "Dog", "Rabbit", "IceCreamKitty" },
	Tech = { "Ruler", "Stopwatch", "Tape", "MagnifyingGlass", "Compass", "MeasuringMug", "Microscope", "Scale" },
}
PetEffects.RarityRate = { Common = 0.4, Uncommon = 0.7, Rare = 1, Epic = 1.4, Legendary = 1.9, Mythic = 2.6 }
PetEffects.LightRarities = { Legendary = 1.2, Mythic = 2 }

local SPARK, FIRE, SMOKE = "rbxasset://textures/particles/sparkles_main.dds", "rbxasset://textures/particles/fire_main.dds", "rbxasset://textures/particles/smoke_main.dds"
-- Layer: At = attachment (Body/Top/Feet), Size/Speed/Accel are per 2.3 studs of pet extent.
local Specs: {[string]: any} = {
	Fire = { Light = {255,150,50}, Layers = {
		{ At="Body", Tex=FIRE, From={255,210,70}, To={255,60,20}, Size=0.34, Life={0.7,1.2}, Rate=14, Speed={0.8,2}, Spread=80, Accel={0,3,0}, Glow=0.9 },
		{ At="Top", Tex=SPARK, From={255,240,150}, To={255,110,30}, Size=0.18, Life={0.6,1.4}, Rate=9, Speed={2,5}, Spread=50, Accel={0,-1,0}, Glow=1 },
	}},
	Water = { Light = {80,200,255}, Layers = {
		{ At="Feet", Tex=SPARK, From={190,245,255}, To={60,170,255}, Size=0.2, Life={1.4,2.4}, Rate=8, Speed={0.6,1.6}, Spread=60, Accel={0,1.6,0}, Glow=0.6, Rot=90 },
		{ At="Body", Tex=SMOKE, From={170,225,255}, To={90,170,255}, Size=0.6, Life={1.2,1.8}, Rate=3, Speed={0.3,0.8}, Spread=180, Accel={0,0.6,0}, Glow=0.3, Fade={0.75,1} },
	}},
	Nature = { Light = {120,255,140}, Layers = {
		{ At="Top", Tex=SPARK, From={150,255,120}, To={255,240,110}, Size=0.22, Life={1.4,2.2}, Rate=7, Speed={0.4,1.2}, Spread=180, Accel={0,-0.8,0}, Glow=0.5, Rot=120 },
		{ At="Body", Tex=SPARK, From={255,175,215}, To={255,235,240}, Size=0.14, Life={1.2,2}, Rate=4, Speed={0.3,1}, Spread=180, Accel={0,0.4,0}, Glow=0.7 },
	}},
	Shadow = { Light = {170,60,255}, Layers = {
		{ At="Feet", Tex=SMOKE, From={90,20,140}, To={15,0,30}, Size=0.7, Life={1.2,2}, Rate=6, Speed={0.4,1.2}, Spread=180, Accel={0,0.9,0}, Glow=0, Fade={0.55,1} },
		{ At="Body", Tex=SPARK, From={255,90,230}, To={140,40,255}, Size=0.16, Life={0.8,1.6}, Rate=6, Speed={0.8,2.2}, Spread=180, Accel={0,0.6,0}, Glow=1 },
	}},
	Holy = { Light = {255,235,160}, Layers = {
		{ At="Body", Tex=SPARK, From={255,255,230}, To={255,220,110}, Size=0.28, Life={1.2,2}, Rate=9, Speed={0.6,1.6}, Spread=150, Accel={0,1.4,0}, Glow=1, Rot=60 },
		{ At="Top", Tex=SPARK, From={255,255,255}, To={255,235,150}, Size=0.42, Life={0.8,1.2}, Rate=2.5, Speed={0.1,0.4}, Spread=30, Accel={0,0.5,0}, Glow=1 },
	}},
	Cosmic = { Light = {140,140,255}, Layers = {
		{ At="Body", Tex=SPARK, From={100,240,255}, To={255,90,230}, Size=0.24, Life={1.2,2.2}, Rate=12, Speed={1,3}, Spread=180, Accel={0,0,0}, Glow=1, Rot=240 },
		{ At="Top", Tex=SPARK, From={255,225,120}, To={140,110,255}, Size=0.14, Life={1.6,2.6}, Rate=8, Speed={0.3,0.9}, Spread=180, Accel={0,0.5,0}, Glow=1 },
	}},
	-- The object pets: bright sparks that look like little glints off metal and glass.
	Tech = { Light = {120,225,255}, Layers = {
		{ At="Top", Tex=SPARK, From={255,255,255}, To={110,215,255}, Size=0.2, Life={0.7,1.3}, Rate=7, Speed={0.5,1.4}, Spread=120, Accel={0,0.8,0}, Glow=1, Rot=180 },
		{ At="Body", Tex=SPARK, From={255,235,130}, To={255,255,255}, Size=0.12, Life={1,1.8}, Rate=4, Speed={0.3,0.9}, Spread=180, Accel={0,0.3,0}, Glow=1 },
	}},
	Earth = { Light = {200,160,100}, Layers = {
		{ At="Feet", Tex=SMOKE, From={190,160,110}, To={110,90,60}, Size=0.45, Life={0.8,1.4}, Rate=5, Speed={0.3,1}, Spread=180, Accel={0,0.3,0}, Glow=0, Fade={0.6,1} },
		{ At="Feet", Tex=SPARK, From={230,200,140}, To={160,130,80}, Size=0.1, Life={0.6,1.1}, Rate=4, Speed={1,2.4}, Spread=90, Accel={0,-5,0}, Glow=0.2 },
	}},
	Fluff = { Light = {255,230,240}, Layers = {
		{ At="Body", Tex=SPARK, From={255,255,255}, To={255,215,235}, Size=0.16, Life={1,1.8}, Rate=4, Speed={0.3,0.9}, Spread=180, Accel={0,0.5,0}, Glow=0.6 },
	}},
}

local themeById: {[string]: string} = {}
for theme, ids in PetEffects.Themes do for _, id in ids do themeById[id] = theme end end
function PetEffects.ThemeOf(id: string): string? return themeById[id] end

local function color(rgb: {number}): Color3 return Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end
local function spectrum(): ColorSequence
	local keys = {}
	for index = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6, 0.7, 1))) end
	return ColorSequence.new(keys)
end

-- Builds emitters (and a soft light for Legendary+) under `anchor`; they follow it automatically
-- and are destroyed with it. `weight` scales density (use less for other players' pets).
function PetEffects.Attach(anchor: any, item: any, id: string, extent: number, weight: number?): any?
	local spec = Specs[themeById[id] or ""]
	if not spec then return nil end
	local rarity = item.Rarity or "Common"
	local rainbow = item.Presentation and item.Presentation.Rainbow == true
	local density = (PetEffects.RarityRate[rarity] or 1) * (weight or 1)
	local unit = extent / 2.3
	local attachments = {}
	for name, height in { Body = 0, Top = extent * 0.45, Feet = -extent * 0.4 } do
		local attachment = Instance.new("Attachment");attachment.Name = "PetFx" .. name
		attachment.Position = Vector3.new(0, height, 0);attachment.Parent = anchor;attachments[name] = attachment
	end
	local fx: any = { Emitters = {}, Rainbow = rainbow, Visible = true, NextPulse = 4, Weight = density }
	for index, layer in spec.Layers do
		local emitter = Instance.new("ParticleEmitter");emitter.Name = "PetFx" .. index
		emitter.Texture = layer.Tex
		emitter.Color = if rainbow then spectrum() else ColorSequence.new(color(layer.From), color(layer.To))
		local size = extent * layer.Size
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(0.35, size), NumberSequenceKeypoint.new(1, 0) })
		local fade = layer.Fade or { 0.1, 1 }
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, fade[1]), NumberSequenceKeypoint.new(1, fade[2]) })
		emitter.Lifetime = NumberRange.new(layer.Life[1], layer.Life[2])
		emitter.Rate = layer.Rate * density
		emitter.Speed = NumberRange.new(layer.Speed[1] * unit, layer.Speed[2] * unit)
		emitter.SpreadAngle = Vector2.new(layer.Spread, layer.Spread)
		emitter.Acceleration = Vector3.new(layer.Accel[1], layer.Accel[2], layer.Accel[3]) * unit
		emitter.LightEmission, emitter.LightInfluence, emitter.Drag = layer.Glow, 0, 0.5
		emitter.Rotation, emitter.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-(layer.Rot or 0), layer.Rot or 0)
		emitter.Parent = attachments[layer.At]
		table.insert(fx.Emitters, emitter)
	end
	local lightPower = PetEffects.LightRarities[rarity]
	if lightPower then
		local light = Instance.new("PointLight");light.Name = "PetFxLight"
		light.Color, light.Range, light.Brightness, light.Shadows = color(spec.Light), extent * 3.2, lightPower, false
		light.Parent = attachments.Body;fx.Light = light;fx.LightPower = lightPower;fx.LightColor = color(spec.Light)
	end
	return fx
end

-- One-shot flourish (equip, big pulses).
function PetEffects.Burst(fx: any, scale: number?)
	if not fx or not fx.Visible then return end
	for _, emitter in fx.Emitters do emitter:Emit(math.max(1, math.floor(emitter.Rate * 0.9 * (scale or 1)))) end
end

-- Per-frame: distance gating, light pulse, rainbow light, and periodic pulses for Epic+.
function PetEffects.Step(fx: any, seconds: number, visible: boolean, teleported: boolean?)
	if not fx then return end
	if fx.Visible ~= visible then
		fx.Visible = visible
		for _, emitter in fx.Emitters do emitter.Enabled = visible end
	end
	if teleported then for _, emitter in fx.Emitters do emitter:Clear() end end
	if fx.Light then
		fx.Light.Enabled = visible
		fx.Light.Brightness = fx.LightPower * (0.75 + 0.25 * math.sin(seconds * 2.4))
		if fx.Rainbow then fx.Light.Color = Color3.fromHSV(seconds * 0.12 % 1, 0.6, 1) end
	end
	if visible and fx.LightPower and seconds >= fx.NextPulse then
		fx.NextPulse = seconds + 5 + fx.LightPower * 0.5
		PetEffects.Burst(fx, 0.6)
	end
end

return PetEffects

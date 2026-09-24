--!strict
-- Equipped pets float close behind their owner in a slight arc, in up to two rows:
--   1-3 pets   one row at normal height
--   4 pets     three on top, one bottom in the middle
--   5 pets     two on top (between the bottom ones), three on the bottom
--   6 pets     three on top, three on the bottom
-- They follow on a soft spring (a little overshoot), turn smoothly, bob, hop and spin now and then, spin and grow when
-- their level goes up, and shed a few basic sparkles. Everything is local and cosmetic.
local PetFollowerController = {}
PetFollowerController.__index = PetFollowerController

local TOP, BOTTOM = "Top", "Bottom"
local MAX_PETS = 8
-- How many of `count` pets go on the top row vs. the bottom row. 1-3 are a single (bottom) row; 4 and 5 keep their
-- established asymmetric look (three-top-one-bottom, two-top-three-bottom); 6 and up split into even top/bottom
-- rows (6 = 3+3, 7 = 4+3, 8 = 4+4), each row centered and evenly spaced.
local function rowCounts(count: number): (number, number)
	if count <= 3 then return 0, count end
	if count == 4 then return 3, 1 end
	if count == 5 then return 2, 3 end
	local top = math.ceil(count / 2)
	return top, count - top
end
-- n evenly spaced, centered step-offsets, e.g. 3 -> {-1, 0, 1}, 4 -> {-1.5, -0.5, 0.5, 1.5}.
local function evenSpots(n: number): { number }
	local spots = {}
	for i = 1, n do table.insert(spots, i - (n + 1) / 2) end
	return spots
end
-- factor: position in the row, in steps either side of the middle. Built once for every pet count the follower
-- system supports (up to MAX_PETS), so each count gets rows that are centered and evenly spaced without any
-- per-count entry going stale as the pet cap changes.
local LAYOUTS = {}
for count = 1, MAX_PETS do
	local top, bottom = rowCounts(count)
	local layout = {}
	for _, x in evenSpots(top) do table.insert(layout, { TOP, x }) end
	for _, x in evenSpots(bottom) do table.insert(layout, { BOTTOM, x }) end
	LAYOUTS[count] = layout
end
local SPRING, DAMPING = 70, 13 -- slightly underdamped: a gentle, floaty follow
local TURN_SPEED = 7
local CELEBRATE_SECONDS, IDLE_SECONDS = 1.5, 0.9
local TELEPORT_STUDS = 40
local TAG_TEXT_SECONDS = 0.1 -- the pulsing level text is rebuilt this often
-- The "Lvl. N" colour by level bracket (it pulses toward white): blue, green, purple, orange, and gold at the top.
local LEVEL_COLORS = { { 10, { 95, 170, 255 } }, { 25, { 90, 235, 140 } }, { 50, { 190, 110, 255 } }, { 100, { 255, 150, 60 } } }
local LEVEL_MAX_COLOR = { 255, 205, 45 }

local function levelColor(level: number, now: number, slot: number): string
	local base = LEVEL_MAX_COLOR
	for _, tier in LEVEL_COLORS do
		if level < tier[1] then base = tier[2];break end
	end
	local pulse = 0.5 + 0.5 * math.sin(now * 3 + slot)
	local function channel(value: number): number return math.floor(value + (255 - value) * 0.35 * pulse + 0.5) end
	return string.format("#%02X%02X%02X", channel(base[1]), channel(base[2]), channel(base[3]))
end

-- Where a pet sits relative to the owner's root: x sideways, y lift above the bottom row, z behind (+z).
function PetFollowerController.Offset(index: number, count: number, extent: number): Vector3
	local layout = LAYOUTS[math.clamp(count, 1, #LAYOUTS)]
	local spot = layout[index] or { TOP, 0 }
	local radius = math.max(4.4, extent * 1.05 + 2.4)
	local step = math.max(math.rad(30), 2 * math.asin(math.min(1, (extent + 0.7) / (2 * radius))))
	local top = spot[1] == TOP
	local ring = radius + (if top then 0.6 else 0)
	local angle = spot[2] * step
	return Vector3.new(math.sin(angle) * ring, if top then extent * 0.85 + 2.8 else 0, math.cos(angle) * ring)
end

local function easeOut(t: number): number return 1 - (1 - math.clamp(t, 0, 1)) ^ 3 end

-- storage: ReplicatedStorage (holds Assets.UI.PetTag, the authored tag with LevelBar.FillBar, Label and Rarity).
function PetFollowerController.new(players: Players, world: Workspace, runService: RunService, catalog: any, models: any?, visual: any?, effects: any?, storage: any?)
	-- Followers live in Workspace.Runtime.Pets (Workspace itself when that folder does not exist).
	local runtime = world:FindFirstChild("Runtime")
	local root = Instance.new("Folder");root.Name, root.Parent = "ScaleLocalPets", (runtime and runtime:FindFirstChild("Pets")) or world
	local collection = game:GetService("CollectionService")
	local self: any = setmetatable({ Players = players, World = world, Root = root, Catalog = catalog, Views = {}, BotPlayers = {}, Population = {}, CollectionService = collection,Models=models,Visual=visual,Effects=effects,Storage=storage,Connections={},Retained={},EquippedIds={},EquippedItems={} }, PetFollowerController)
	for _, character in collection:GetTagged("ScalePopulationNPC") do self.Population[character] = true end
	table.insert(self.Connections, collection:GetInstanceAddedSignal("ScalePopulationNPC"):Connect(function(character) self.Population[character] = true end))
	table.insert(self.Connections, collection:GetInstanceRemovedSignal("ScalePopulationNPC"):Connect(function(character) self.Population[character] = nil end))
	table.insert(self.Connections, runService.RenderStepped:Connect(function(dt) self:Step(dt) end))
	return self
end
function PetFollowerController.Clear(self: any, player: any)
	local view = self.Views[player];if view then for _, entry in view do entry.Part:Destroy() end end;self.Views[player] = nil
end

-- A few soft sparkles for every pet (the themed rarity effects come from PetEffects on top of these).
local function sparkles(pet: any, item: any, weight: number): any?
	local ok, emitter = pcall(function()
		local made = Instance.new("ParticleEmitter")
		made.Name = "PetFxBasic"
		made.Rate = 3 * weight
		made.Lifetime = NumberRange.new(0.8, 1.5)
		made.Speed = NumberRange.new(0.3, 1)
		made.SpreadAngle = Vector2.new(180, 180)
		made.Acceleration = Vector3.new(0, 0.6, 0)
		made.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.16), NumberSequenceKeypoint.new(1, 0) })
		made.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(1, 1) })
		local tint = item.Presentation and item.Presentation.Tint or item.Color
		made.Color = ColorSequence.new(Color3.fromRGB(tint[1], tint[2], tint[3]), Color3.new(1, 1, 1))
		made.LightEmission, made.LockedToPart = 0.6, false
		made.Parent = pet
		return made
	end)
	return if ok then emitter else nil
end

-- Clones the authored Assets.UI.PetTag onto a follower, or returns nil when the tag (or a part of it) is missing.
function PetFollowerController.BuildTag(self: any, pet: BasePart, extent: number): any?
	local assets = self.Storage and self.Storage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("PetTag")
	if not (template and template:IsA("BillboardGui")) then return nil end
	local bar = template:FindFirstChild("LevelBar")
	local fill = bar and bar:FindFirstChild("FillBar")
	local label, rarity = template:FindFirstChild("Label"), template:FindFirstChild("Rarity")
	if not (fill and fill:IsA("GuiObject") and label and label:IsA("TextLabel") and rarity and rarity:IsA("TextLabel")) then return nil end
	local gui = template:Clone()
	gui.Name = "PetTag"
	-- No size or offset is touched: the authored template's own custom Size/StudsOffset/etc. are kept exactly, just
	-- adorned to and parented onto this pet.
	gui.Adornee = pet
	if gui.MaxDistance <= 0 or gui.MaxDistance == math.huge then gui.MaxDistance = 60 end
	gui.Parent = pet
	local cloneFill = gui.LevelBar.FillBar
	cloneFill.Size = UDim2.new(0, 0, cloneFill.Size.Y.Scale, cloneFill.Size.Y.Offset)
	gui.Label.RichText = true
	return { Gui = gui, Label = gui.Label, Rarity = gui.Rarity, Fill = cloneFill, FillValue = 0 }
end

function PetFollowerController.Step(self: any, dt: number)
	local retained = self.Retained;table.clear(retained);local now = self.World:GetServerTimeNow()
	local step = math.min(dt, 0.05)
	local participants: { any } = self.Players:GetPlayers()
	-- Population NPCs are Models rather than Players. Stable proxies let the existing follower renderer use the
	-- character's replicated Pet1-8/PetLevel/PetFill attributes exactly like it does for real players.
	for character in self.Population do
		if not character:IsA("Model") or not character:IsDescendantOf(self.World) then continue end
		local proxy = self.BotPlayers[character]
		if not proxy then
			proxy = { Character = character, Source = character, Name = character.Name }
			function proxy:GetAttribute(name: string) return self.Source:GetAttribute(name) end
			self.BotPlayers[character] = proxy
		else
			proxy.Character, proxy.Source, proxy.Name = character, character, character.Name
		end
		table.insert(participants, proxy)
	end
	for _, player in participants do
		local character = player.Character;local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then self:Clear(player);continue end
		retained[player] = true;local view = self.Views[player] or {};self.Views[player] = view
		local count,largest,index=0,1.8,0
		-- These arrays are consumed before moving to the next participant, so one pair can serve the whole frame.
		local equippedIds, equippedItems = self.EquippedIds, self.EquippedItems
		table.clear(equippedIds);table.clear(equippedItems)
		for slot=1,8 do
			local id=player:GetAttribute("Pet"..slot);local item=id and self.Catalog.Items.Pets[id]
			equippedIds[slot], equippedItems[slot] = id, item
			if item then count+=1;largest=math.max(largest,if item.Presentation then item.Presentation.Extent else 1.8) end
		end
		for slot = 1, 8 do
			local id, item = equippedIds[slot], equippedItems[slot]
			local entry = view[slot]
			if entry and (not item or entry.Id ~= id or entry.Character ~= character) then entry.Part:Destroy();view[slot] = nil;entry = nil end
			if not item then continue end
			local look=item.Presentation
			local extent=if look then look.Extent else 1.8
			index+=1
			local offset=PetFollowerController.Offset(index,count,largest)
			local bob=math.sin(now*(if look then look.Speed else 3)+slot)*(if look then look.Bob else 0.22)
			local hover=(if look then look.Hover else -1.4)+bob+offset.Y
			-- An occasional little hop and half-turn keeps idle pets lively; a level-up is a full spin and a grow.
			local spin,hop,pulse=0,0,1
			if entry then
				if now>=(entry.NextIdle or math.huge) then entry.IdleAt,entry.NextIdle=now,now+14+(slot*5)%9 end
				local idle=if entry.IdleAt then (now-entry.IdleAt)/IDLE_SECONDS else 2
				if idle>=0 and idle<1 then spin+=math.pi*easeOut(idle);hop+=0.7*math.sin(math.pi*idle) end
				local celebrate=if entry.CelebrateAt then (now-entry.CelebrateAt)/CELEBRATE_SECONDS else 2
				if celebrate>=0 and celebrate<1 then
					spin+=math.pi*2*easeOut(celebrate);hop+=0.9*math.sin(math.pi*celebrate)
					pulse=1+0.55*math.sin(math.pi*celebrate)
				end
			end
			local goal = root.CFrame * CFrame.new(offset.X, hover+hop, offset.Z) * CFrame.Angles(0,spin,0)
			if look and look.Hover>0 then goal*=CFrame.Angles(math.sin(now*1.7+slot)*0.035,0,math.sin(now*1.3+slot)*0.04) end
			if not entry then
				local pet = Instance.new("Part");pet.Name, pet.Size, pet.Color, pet.CFrame = player.Name .. "_" .. slot, Vector3.one * 1.4, Color3.fromRGB(table.unpack(item.Color)), goal
				pet.Anchored, pet.CanCollide, pet.CanTouch, pet.CanQuery, pet.CastShadow = true, false, false, false, false;pet.Parent = self.Root
				local tag = self:BuildTag(pet, extent)
				local label: any, rarity: any
				if not tag then
				local gui = Instance.new("BillboardGui");gui.Name="PetNameplate";gui.Size, gui.Adornee, gui.StudsOffsetWorldSpace, gui.MaxDistance, gui.Parent = UDim2.fromScale(3.6, 1), pet, Vector3.new(0,extent*0.5+0.7,0), 60, pet
				label = Instance.new("TextLabel");label.Name="PetName";label.Size, label.BackgroundTransparency, label.Font = UDim2.fromScale(1, 1), 1, Enum.Font.FredokaOne
				label.Text, label.TextColor3, label.TextScaled, label.TextStrokeTransparency, label.Parent = item.Name, Color3.new(1, 1, 1), true, 0, gui
				label.Size=UDim2.fromScale(1,0.56)
				rarity=Instance.new("TextLabel");rarity.Name="PetRarity";rarity.Text=string.upper(item.Rarity);rarity.Size,rarity.Position=UDim2.fromScale(1,0.38),UDim2.fromScale(0,0.6)
				rarity.BackgroundTransparency,rarity.Font,rarity.TextScaled,rarity.TextStrokeTransparency,rarity.Parent=1,Enum.Font.FredokaOne,true,0,gui
				if self.Visual and self.Visual.StyleLabel then self.Visual.StyleLabel(label,item);self.Visual.StyleLabel(rarity,item) end
				end
				if tag then
					-- The authored tag: the rarity reads as its own label with the rarity effect; the name is built each update.
					tag.Rarity.Text = string.upper(item.Rarity)
					if self.Visual and self.Visual.StyleLabel then self.Visual.StyleLabel(tag.Rarity, item) end
				end
				entry = { Id = id, Part = pet, Character = character, NameLabel=if tag then tag.Label else label, RarityLabel=if tag then tag.Rarity else rarity, Tag = tag, Velocity = Vector3.zero, NextIdle = now + 6 + slot * 3 };view[slot] = entry
				entry.Sparkles = sparkles(pet, item, if player==self.Players.LocalPlayer then 1 else 0.5)
				if self.Visual then
					entry.Model=self.Visual.Create(self.Models,id,pet,extent,item)
					if entry.Model then pcall(function() entry.BaseScale=entry.Model:GetScale() end) end
					if self.Visual.Trail then entry.Trail=self.Visual.Trail(pet,item,extent) end
					entry.RetryAt=now+1
					if entry.Model then pet.Transparency=1 end
				end
				if self.Effects then
					entry.Fx=self.Effects.Attach(pet,item,id,extent,if player==self.Players.LocalPlayer then 1 else 0.5)
					self.Effects.Burst(entry.Fx,1.5)
				end
			end
			local level=player:GetAttribute("PetLevel"..slot) or 1
			if entry.Level~=level then
				-- Levelling up (not the first time it is seen) starts the spin-and-grow celebration with a burst of sparkles.
				if entry.Level and level>entry.Level then
					entry.CelebrateAt=now
					if entry.Sparkles and entry.Sparkles.Emit then pcall(function() entry.Sparkles:Emit(28) end) end
					if entry.Fx and self.Effects then self.Effects.Burst(entry.Fx,3) end
				end
				entry.Level=level
				if not entry.Tag then entry.NameLabel.Text=self.Catalog.PetDisplayName(id,level) else entry.TagTextAt=nil end
			end
			local tag=entry.Tag
			if tag then
				-- Level bar: how far through the current level the pet is (the server's PetFill attribute, 0-1).
				local target=player:GetAttribute("PetFill"..slot);if type(target)~="number" then target=0 end
				target=math.clamp(target,0,1)
				-- A level-up wraps the bar back to empty: jump instead of sliding backwards.
				if target<tag.FillValue-0.5 then tag.FillValue=0 end
				tag.FillValue+=(target-tag.FillValue)*math.min(1,step*8)
				if math.abs(target-tag.FillValue)<0.002 then tag.FillValue=target end
				local size=tag.Fill.Size;tag.Fill.Size=UDim2.new(tag.FillValue,0,size.Y.Scale,size.Y.Offset)
				-- "Lvl. N" in a pulsing colour for its level bracket, then the pet's name in its rarity colour.
				if not entry.TagTextAt or now-entry.TagTextAt>=TAG_TEXT_SECONDS then
					entry.TagTextAt=now
					local tint=if look then look.Tint else {255,255,255}
					tag.Label.Text=string.format('<font color="%s">Lvl. %d</font> <font color="#%02X%02X%02X">%s</font>',levelColor(level,now,slot),level,tint[1],tint[2],tint[3],item.Name)
				end
			end
			-- The preview folder can replicate before its models. Upgrade a temporary
			-- fallback once content arrives, without recreating the follower each frame.
			if self.Visual and not entry.Model and now>=(entry.RetryAt or 0) then
				entry.RetryAt=now+1;entry.Model=self.Visual.Create(self.Models,id,entry.Part,extent,item)
				if entry.Model then entry.Part.Transparency=1;pcall(function() entry.BaseScale=entry.Model:GetScale() end) end
			end
			-- Follow on a soft spring and turn smoothly toward the goal facing.
			local teleported=(entry.Part.Position-goal.Position).Magnitude>TELEPORT_STUDS
			local placed
			if teleported then
				entry.Velocity=Vector3.zero;placed=goal
			else
				local position=entry.Part.Position
				local velocity=entry.Velocity+((goal.Position-position)*SPRING-entry.Velocity*DAMPING)*step
				entry.Velocity=velocity
				local turned=entry.Part.CFrame.Rotation:Lerp(goal.Rotation,1-math.exp(-TURN_SPEED*step))
				placed=CFrame.new(position+velocity*step)*turned
			end
			entry.Part.CFrame = placed
			if entry.Model then
				entry.Model:PivotTo(entry.Part.CFrame)
				if entry.BaseScale and pulse~=entry.Pulse then
					entry.Pulse=pulse
					pcall(function() entry.Model:ScaleTo(entry.BaseScale*pulse) end)
				end
			end
			local camera=self.World.CurrentCamera
			local effectsVisible=not camera or (camera.CFrame.Position-entry.Part.Position).Magnitude<90
			if entry.Sparkles then entry.Sparkles.Enabled=effectsVisible end
			if entry.Trail then entry.Trail.Enabled=effectsVisible;if teleported or not effectsVisible then entry.Trail:Clear() end end
			if entry.Fx then self.Effects.Step(entry.Fx,now,effectsVisible,teleported) end
			if self.Visual and self.Visual.Step then
				if entry.Model then self.Visual.Step(entry.Model,now+slot*0.3,effectsVisible) end
				self.Visual.StepLabel(entry.NameLabel,now);self.Visual.StepLabel(entry.RarityLabel,now)
			end
		end
	end
	for player in self.Views do if not retained[player] then self:Clear(player) end end
	for character, proxy in self.BotPlayers do
		if not character.Parent then self:Clear(proxy);self.BotPlayers[character] = nil end
	end
end
function PetFollowerController.Destroy(self: any)
	for _, connection in self.Connections do connection:Disconnect() end
	self.Root:Destroy();table.clear(self.Views);table.clear(self.BotPlayers);table.clear(self.Population)
	table.clear(self.Retained);table.clear(self.EquippedIds);table.clear(self.EquippedItems)
end
return PetFollowerController

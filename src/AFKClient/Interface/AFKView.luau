--!strict
-- Binds the authored HUD.AFK (StarterGui.HUD.AFK). Nothing is built on it except a UIGradient on a reward label that
-- has none, a Camera inside a card's ViewportFrame, and (only for a card with no authored ViewportFrame) a fallback
-- ViewportFrame. Every card's ViewportFrame shows the real reward model, slowly turning, for Pet / Chair / Block
-- rewards: pets from ReplicatedStorage.AFKPreviews.Pets (published by the server from ServerStorage.Pets.Active), chairs
-- from ReplicatedStorage.Assets.Chairs and Lucky Blocks from ReplicatedStorage.Assets.LuckyBlocks. Until a model has
-- replicated the card shows a simple placeholder shape and retries. Cash always reads "$X" ("$1,500").
--   Left.RewardsEarnt.1-15     the last 15 rewards, 1 the newest and 15 the oldest, each ImageLabel (icon) + TextLabel ("$100")
--   Lower.Frame.ProgressBar    grows from 0 to full width between rewards
--   Lower.RewardNext           "Rewards in 25s"
--   Lower.Return               back to the main game
--   Right.Container.Reward1-N  as many of config.Rewards (Cash x3, Boost, Gems, Pet, Chair, Block) as have an authored
--                              Reward# slot: ImageLabel icon (or the item's ViewportFrame), TextLabel amount, Chance ("79%")
--   Upper.UpperTitle (+ .LowerTitle)  the title, slowly rocking between 3 and -3 degrees forever
local View = {}
View.__index = View

local ROCK_DEGREES, ROCK_SPEED = 3, 0.9
-- Returning to the game: the AFK UI slides off the bottom of the screen and a loading screen (blur, dim backdrop and
-- three waving white dots, like the main game's) fades in until the teleport happens; if it fails it all comes back.
local TRAVEL_SPEED, TRAVEL_DROP = 3, 1.3
local DOT_SIZE, DOT_SPACING, DOT_WAVE = 42, 96, 30
local PREVIEW_SPIN_DEGREES_PER_SECOND = 24
local PREVIEW_COLORS =
	{ Pet = Color3.fromRGB(255, 205, 60), Chair = Color3.fromRGB(130, 235, 160), Block = Color3.fromRGB(190, 110, 255) }
local MODEL_KINDS = { Pet = true, Chair = true, Block = true, Egg = true }
local RETRY_SECONDS = 1

-- A chance as shown on a card: one decimal, without a trailing ".0" ("84.4%", "14%").
local function chanceText(chance: number): string
	return (string.gsub(string.format("%.1f", chance), "%.0$", "")) .. "%"
end
local function comma(amount: number): string
	local text = tostring(math.floor(math.max(0, amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(grouped), "^,", ""))
end

local function need(parent: Instance, name: string, class: string?): any
	local node = parent:FindFirstChild(name)
	assert(node and (not class or node:IsA(class)), "Missing authored UI: " .. parent:GetFullName() .. "." .. name .. (if class then " (" .. class .. ")" else ""))
	return node
end

local function gradientFor(config: any, kind: string): ColorSequence
	local stops = config.Gradients[kind] or config.Gradients.Boost
	local keys = {}
	for _, stop in stops do
		local rgb = stop[2]
		table.insert(keys, ColorSequenceKeypoint.new(stop[1], Color3.fromRGB(rgb[1], rgb[2], rgb[3])))
	end
	return ColorSequence.new(keys)
end

-- The card's authored ViewportFrame (anywhere inside it), else a fallback one over the ImageLabel; either way with a
-- PreviewCamera the view owns.
local function ensurePreview(card: any): ViewportFrame
	if card.Preview then
		return card.Preview
	end
	local view = card.Frame:FindFirstChildWhichIsA("ViewportFrame", true)
	if not view then
		view = Instance.new("ViewportFrame")
		view.Name, view.Size, view.BackgroundTransparency = "Preview", UDim2.fromScale(1, 1), 1
		view.Ambient, view.LightColor = Color3.new(0.7, 0.7, 0.7), Color3.new(1, 1, 1)
		view.Parent = card.Image.Parent
	end
	local camera = view:FindFirstChild("PreviewCamera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Name, camera.FieldOfView = "PreviewCamera", 38
		camera.Parent = view
	end
	view.CurrentCamera = camera
	card.Preview, card.PreviewCamera, card.PreviewDistance = view, camera, 4.1
	return view
end
local function clearModels(view: ViewportFrame)
	for _, child in view:GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") then
			child:Destroy()
		end
	end
end
-- A stand-in shape (gold ball for a pet, green chair, purple cube for a block) while the real model is not available.
local function buildPlaceholder(view: ViewportFrame, kind: string)
	clearModels(view)
	local color = PREVIEW_COLORS[kind] or Color3.new(1, 1, 1)
	if kind == "Pet" then
		local ball = Instance.new("Part")
		ball.Name, ball.Shape, ball.Material, ball.Color = "PreviewShape", Enum.PartType.Ball, Enum.Material.Neon, color
		ball.Size, ball.Anchored, ball.CanCollide, ball.CanTouch, ball.CanQuery = Vector3.one * 1.6, true, false, false, false
		ball.CFrame = CFrame.new()
		ball.Parent = view
	elseif kind == "Chair" then
		local model = Instance.new("Model")
		model.Name = "PreviewShape"
		local function block(size: Vector3, position: Vector3)
			local part = Instance.new("Part")
			part.Material, part.Color, part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery =
				Enum.Material.SmoothPlastic, color, true, false, false, false
			part.Size, part.CFrame = size, CFrame.new(position)
			part.Parent = model
		end
		block(Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, -0.5, 0))
		block(Vector3.new(1.6, 1.3, 0.25), Vector3.new(0, 0.3, 0.65))
		model.Parent = view
	elseif kind == "Block" or kind == "Egg" then
		local cube = Instance.new("Part")
		cube.Name, cube.Material, cube.Color = "PreviewShape", Enum.Material.Neon, color
		cube.Size, cube.Anchored, cube.CanCollide, cube.CanTouch, cube.CanQuery = Vector3.one * 1.8, true, false, false, false
		cube.CFrame = CFrame.new()
		cube.Parent = view
	end
end

-- The replicated source model for a Pet / Chair / Block reward, or nil while it is not (yet) available.
function View.Source(self: any, reward: any): Instance?
	local storage = self.Storage
	if not storage then
		return nil
	end
	local info = self.ById[reward.Id] or reward
	if reward.Kind == "Pet" then
		local previews = storage:FindFirstChild("AFKPreviews")
		local pets = previews and previews:FindFirstChild("Pets")
		return pets and info.PetId and pets:FindFirstChild(info.PetId)
	end
	local assets = storage:FindFirstChild("Assets")
	if reward.Kind == "Chair" and info.ChairId then
		-- Assets.Chairs uses model names (Basic, ElectricChair); CosmeticCatalog.ChairModelIds maps them to IDs.
		local name = info.ChairId
		for modelName, id in (self.Catalog and self.Catalog.ChairModelIds) or {} do
			if id == info.ChairId then
				name = modelName
			end
		end
		local chairs = assets and assets:FindFirstChild("Chairs")
		return chairs and chairs:FindFirstChild(name)
	elseif reward.Kind == "Block" then
		local block = self.Config.Blocks and info.BlockId and self.Config.Blocks[info.BlockId]
		local design = info.Design or (block and block.Design)
		local blocks = assets and assets:FindFirstChild("LuckyBlocks")
		return blocks and design and blocks:FindFirstChild(design)
	elseif reward.Kind == "Egg" then
		-- ReplicatedStorage.Assets.Eggs, by the first model name AFKConfig.Eggs lists that exists.
		local egg = self.Config.Eggs and info.EggId and self.Config.Eggs[info.EggId]
		local eggs = assets and assets:FindFirstChild("Eggs")
		for _, name in (egg and egg.Models) or { info.EggId } do
			local model = eggs and eggs:FindFirstChild(name)
			if model then return model end
		end
		return nil
	end
	return nil
end

-- Puts a sanitized copy of the reward's real model in the card's viewport, centred, with the camera distance set
-- from its size. Returns false (leaving the placeholder) when the model is not available yet.
function View.ShowModel(self: any, card: any, reward: any): boolean
	local source = self:Source(reward)
	if not source then
		return false
	end
	local view = ensurePreview(card)
	local copy = source:Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	else
		model = Instance.new("Model")
		copy.Parent = model
	end
	-- Strip behaviour and measure the visible parts' box (from each part's position and size, so it works on any
	-- model), then move every part so that box is centred on the viewport's origin.
	local parts, low, high = {}, nil, nil
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ProximityPrompt") or item:IsA("ClickDetector") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			local ok, position = pcall(function()
				return item.CFrame.Position
			end)
			if not ok then
				continue
			end
			table.insert(parts, item)
			local a, b = position - item.Size * 0.5, position + item.Size * 0.5
			low = if low then Vector3.new(math.min(low.X, a.X), math.min(low.Y, a.Y), math.min(low.Z, a.Z)) else a
			high = if high then Vector3.new(math.max(high.X, b.X), math.max(high.Y, b.Y), math.max(high.Z, b.Z)) else b
		end
	end
	if not low or not high then
		model:Destroy()
		return false
	end
	local centre, size = (low + high) * 0.5, high - low
	for _, part in parts do
		part.CFrame = part.CFrame - centre
	end
	clearModels(view)
	model.Name = "PreviewModel"
	model.Parent = view
	card.PreviewDistance = math.max(1, size.Magnitude * 0.9)
	return true
end
-- What a reward card says: Cash is always "$X", everything else its configured label.
function View.Label(self: any, reward: any): string
	if reward.Kind == "Cash" then
		return "$" .. comma(reward.Amount or 0)
	end
	local info = self.ById[reward.Id]
	return (info and info.Label) or reward.Label or tostring(reward.Amount)
end

-- Icon, amount text and text gradient for one reward on one of the authored cards. A Pet / Chair / Block reward
-- shows its real model in the card's ViewportFrame (rebuilt only when the item changes) and is left to turn (Step).
function View.Fill(self: any, card: any, reward: any)
	if MODEL_KINDS[reward.Kind] then
		local view = ensurePreview(card)
		if card.PreviewKey ~= reward.Id then
			card.PreviewKey = reward.Id
			card.PreviewDistance = 4.1
			if self:ShowModel(card, reward) then
				card.Retry = nil
			else
				buildPlaceholder(view, reward.Kind)
				card.Retry = reward
			end
		end
		view.Visible, card.Image.Visible = true, false
	else
		card.PreviewKey, card.Retry = nil, nil
		local authored = card.Preview or card.Frame:FindFirstChildWhichIsA("ViewportFrame", true)
		if authored then
			authored.Visible = false
		end
		local icon = self.Config.Icons[reward.Kind] or ""
		card.Image.Image, card.Image.Visible = icon, icon ~= ""
	end
	card.Text.Text = self:Label(reward)
	local gradient = card.Text:FindFirstChildWhichIsA("UIGradient")
	if not gradient then
		card.Text.TextColor3 = Color3.new(1, 1, 1)
		gradient = Instance.new("UIGradient")
		gradient.Name = "RewardGradient"
		gradient.Parent = card.Text
	end
	gradient.Color = gradientFor(self.Config, reward.Kind)
end

local function card(frame: Instance, textName: string): any
	return { Frame = frame, Image = need(frame, "ImageLabel", "ImageLabel"), Text = need(frame, textName, "TextLabel") }
end

-- Binds the same StarterGui.HUD the engine already copies into every PlayerGui; never clones or builds one.
-- storage (ReplicatedStorage) and catalog (CosmeticCatalog) supply the reward models; without them cards keep the
-- placeholder shapes.
function View.new(playerGui: PlayerGui, config: any, storage: Instance?, catalog: any?)
	local hud = playerGui:FindFirstChild("HUD") or playerGui:WaitForChild("HUD", 15)
	assert(hud and hud:IsA("ScreenGui"), "StarterGui.HUD must contain the authored AFK interface")
	local afk = need(hud, "AFK", "GuiObject")
	local self: any = setmetatable({
		Config = config,
		Gui = hud,
		Afk = afk,
		Sequence = -1,
		Slots = {},
		Possible = {},
		Time = 0,
		RetryAt = 0,
		Storage = storage,
		Catalog = catalog,
		ById = {},
	}, View)
	for _, reward in config.Rewards do
		self.ById[reward.Id] = reward
	end
	local earnt = need(need(afk, "Left"), "RewardsEarnt")
	for index = 1, config.RecentSlots do
		local frame = need(earnt, tostring(index), "GuiObject")
		frame.Visible = false
		self.Slots[index] = card(frame, "TextLabel")
	end
	local lower = need(afk, "Lower")
	self.Bar = need(need(lower, "Frame"), "ProgressBar", "GuiObject")
	self.BarHeight = self.Bar.Size.Y
	self.Bar.Size = UDim2.new(0, 0, self.BarHeight.Scale, self.BarHeight.Offset)
	self.Next = need(lower, "RewardNext", "TextLabel")
	self.Return = need(lower, "Return", "GuiButton")
	local container = need(need(afk, "Right"), "Container")
	-- Optional beyond however many Reward# slots are actually authored: the possible-rewards strip just shows as
	-- many as it has room for, so adding a new reward kind to the config never crashes the whole AFK screen while
	-- waiting on a matching slot to be authored.
	for index, reward in config.Rewards do
		local frame = container:FindFirstChild("Reward" .. index)
		if frame and frame:IsA("GuiObject") then
			local entry = card(frame, "TextLabel")
			entry.Chance = need(entry.Frame, "Chance", "TextLabel")
			entry.Chance.Text = chanceText(reward.Chance)
			self:Fill(entry, reward)
			self.Possible[index] = entry
		end
	end
	local upper = need(afk, "Upper")
	self.Title = need(upper, "UpperTitle", "TextLabel")
	self.Subtitle = need(self.Title, "LowerTitle", "TextLabel")
	self.AfkRest, self.TravelOut = afk.Position, 0
	afk.Visible, hud.Enabled = true, true
	return self
end

function View.Receive(self: any, packet: any)
	if packet.Ready then
		self.State = packet
		-- The server draws a new random offer for every reward: refill the possible-reward cards when it changes.
		if type(packet.Offer) == "table" then
			local parts = {}
			for _, reward in packet.Offer do table.insert(parts, tostring(reward.Id) .. "=" .. tostring(reward.Chance)) end
			local key = table.concat(parts, ",")
			if key ~= self.OfferKey then
				self.OfferKey = key
				for index, entry in self.Possible do
					local reward = packet.Offer[index]
					entry.Frame.Visible = reward ~= nil
					if reward then
						entry.Chance.Text = chanceText(reward.Chance)
						self:Fill(entry, reward)
					end
				end
			end
		end
		-- The 15 most recent rewards, newest first; slots that have no reward yet stay hidden.
		if self.Sequence ~= packet.Sequence then
			self.Sequence = packet.Sequence
			for index, slot in self.Slots do
				local reward = packet.History[index]
				slot.Frame.Visible = reward ~= nil
				if reward then self:Fill(slot, reward) end
			end
		end
	end
	self.Traveling = packet.Traveling
	self.Return.Active = not self.Traveling
end

-- The travel loading screen, built on first use and removed once it has faded out again.
function View.TravelOverlay(self: any, alpha: number)
	if alpha <= 0 then
		if self.TravelGui then
			self.TravelGui:Destroy()
			self.TravelGui, self.TravelDots = nil, nil
		end
		if self.TravelBlur then
			self.TravelBlur:Destroy()
			self.TravelBlur = nil
		end
		return
	end
	if not self.TravelGui then
		local gui = Instance.new("ScreenGui")
		gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "AFKTravelLoading", false, true, 10000
		local backdrop = Instance.new("Frame")
		backdrop.Name, backdrop.Size, backdrop.BackgroundColor3, backdrop.BorderSizePixel, backdrop.Active =
			"Backdrop", UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0, true
		backdrop.Parent = gui
		self.TravelDots = {}
		for index = 1, 3 do
			local dot = Instance.new("Frame")
			dot.Name, dot.AnchorPoint, dot.Size = "Dot" .. index, Vector2.new(0.5, 0.5), UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
			dot.BackgroundColor3, dot.BorderSizePixel = Color3.new(1, 1, 1), 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius, corner.Parent = UDim.new(1, 0), dot
			dot.Parent = backdrop
			self.TravelDots[index] = dot
		end
		gui.Parent = self.Gui.Parent
		self.TravelGui, self.TravelBackdrop = gui, backdrop
		if self.Lighting then
			local blur = Instance.new("BlurEffect")
			blur.Name, blur.Size, blur.Parent = "AFKTravelBlur", 0, self.Lighting
			self.TravelBlur = blur
		end
	end
	self.TravelBackdrop.BackgroundTransparency = 1 - 0.08 * alpha
	for index, dot in self.TravelDots do
		local offset = -math.sin(self.Time * math.pi * 2 / 1.8 - (index - 1) * 0.65) * DOT_WAVE
		dot.Position = UDim2.new(0.5, (index - 2) * DOT_SPACING, 0.5, offset)
		dot.BackgroundTransparency = 1 - alpha
	end
	if self.TravelBlur then
		self.TravelBlur.Size = 56 * alpha
	end
end

function View.Step(self: any, now: number, dt: number?)
	self.Time += dt or 0
	-- Travel: slide the AFK UI away and fade the loading screen in (or back out after a failed teleport).
	local goal = if self.Traveling then 1 else 0
	local step = (dt or 0) * TRAVEL_SPEED
	self.TravelOut = if self.TravelOut < goal then math.min(goal, self.TravelOut + step) else math.max(goal, self.TravelOut - step)
	local eased = self.TravelOut * self.TravelOut * (3 - 2 * self.TravelOut)
	self.Afk.Position = self.AfkRest + UDim2.fromScale(0, TRAVEL_DROP * eased)
	self:TravelOverlay(eased)
	-- The title and its subtitle rock gently between 3 and -3 degrees, out of step with each other, at the same
	-- speed. LowerTitle is a child of UpperTitle, and Roblox composes a GuiObject's Rotation with its parent's, so
	-- the subtitle's own Rotation must subtract the title's to land on the same independent wave on screen instead
	-- of the two summing into a different-looking amplitude/phase.
	self.Title.Rotation = ROCK_DEGREES * math.sin(self.Time * ROCK_SPEED)
	self.Subtitle.Rotation = ROCK_DEGREES * math.sin(self.Time * ROCK_SPEED + 1.6) - self.Title.Rotation
	if self.Traveling then
		self.Next.Text = "Returning to game..."
	elseif self.State then
		local remaining = math.max(0, self.State.NextReward - now)
		self.Next.Text = "Rewards in " .. math.ceil(remaining) .. "s"
		local progress = math.clamp(1 - remaining / self.State.Interval, 0, 1)
		self.Bar.Size = UDim2.new(progress, 0, self.BarHeight.Scale, self.BarHeight.Offset)
	end
	-- Every shown reward model keeps turning slowly; cards still on a placeholder retry their real model each second.
	local angle = math.rad(self.Time * PREVIEW_SPIN_DEGREES_PER_SECOND)
	local retry = self.Time >= self.RetryAt
	if retry then
		self.RetryAt = self.Time + RETRY_SECONDS
	end
	for _, list in { self.Slots, self.Possible } do
		for _, card in list do
			if retry and card.Retry and self:ShowModel(card, card.Retry) then
				card.Retry = nil
			end
			if card.Preview and card.Preview.Visible then
				local distance = card.PreviewDistance or 4.1
				local eye = Vector3.new(math.sin(angle) * distance, distance * 0.36, math.cos(angle) * distance)
				card.PreviewCamera.CFrame = CFrame.lookAt(eye, Vector3.zero)
			end
		end
	end
end

function View.Destroy(self: any)
	self.Traveling = false
	self:TravelOverlay(0)
	self.Afk.Position = self.AfkRest
	self.Afk.Visible = false
end
return View

--!strict
-- Replaces a bot's flat thumbnail with a local clone of its replicated character. Every caller supplies the logical
-- participant UserId (negative for bots), so ambient NPCs cannot be mistaken for the real account whose AvatarUserId
-- they borrow. One tagged-instance listener completes portraits whose character replicated just after the UI packet.
local CollectionService = game:GetService("CollectionService")

local BotPortrait = {}
local pending = setmetatable({}, { __mode = "k" })
local VIEWPORT_NAME = "BotPortraitViewport"

local function isBot(userId: number?): boolean
	return type(userId) == "number" and userId < 0
end

local function sourceFor(userId: number): Model?
	for _, instance in CollectionService:GetTagged("ScaleBot") do
		if
			instance:IsA("Model")
			and instance:IsDescendantOf(workspace)
			and instance:GetAttribute("ScaleBotUserId") == userId
		then
			return instance
		end
	end
	return nil
end

local function viewportFor(image: GuiObject): ViewportFrame
	local existing = image:FindFirstChild(VIEWPORT_NAME)
	if existing and existing:IsA("ViewportFrame") then
		return existing
	end
	if existing then existing:Destroy() end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = VIEWPORT_NAME
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(185, 185, 185)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -0.5, -1)
	viewport.ZIndex = image.ZIndex + 1
	viewport.Parent = image
	local sourceCorner = image:FindFirstChildWhichIsA("UICorner")
	if sourceCorner then
		local corner = Instance.new("UICorner")
		corner.Name, corner.CornerRadius, corner.Parent = "PortraitCorner", sourceCorner.CornerRadius, viewport
	end
	return viewport
end

local function clearViewport(viewport: ViewportFrame)
	viewport.CurrentCamera = nil
	for _, child in viewport:GetChildren() do
		if child:IsA("Camera") or child:IsA("WorldModel") then child:Destroy() end
	end
	viewport:SetAttribute("PortraitUserId", nil)
end

local function render(image: GuiObject, userId: number, source: Model): boolean
	if not image.Parent or image:GetAttribute("BotPortraitUserId") ~= userId then return false end
	local viewport = viewportFor(image)
	if viewport:GetAttribute("PortraitUserId") == userId and viewport.CurrentCamera then
		if image:IsA("ImageLabel") or image:IsA("ImageButton") then image.ImageTransparency = 1 end
		viewport.Visible = true
		return true
	end
	clearViewport(viewport)
	local wasArchivable = source.Archivable
	source.Archivable = true
	local ok, character = pcall(function() return source:Clone() end)
	source.Archivable = wasArchivable
	if not ok or not character then return false end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide, descendant.CanTouch, descendant.CanQuery = false, false, false
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant:Destroy()
		end
	end
	local world = Instance.new("WorldModel")
	world.Name, world.Parent = "PortraitWorld", viewport
	character.Name, character.Parent = "NPC", world
	character:PivotTo(CFrame.new())
	local head = character:FindFirstChild("Head", true)
	local root = character:FindFirstChild("HumanoidRootPart", true)
	if not (head and head:IsA("BasePart")) then
		world:Destroy()
		return false
	end
	local forward = if root and root:IsA("BasePart") then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	-- Keep the face dominant in the small circular player card. A small downward bias retains the top of the
	-- shoulders without letting the torso consume most of the portrait.
	local focus = head.Position - Vector3.yAxis * (head.Size.Y * 0.04)
	local distance = math.max(2.8, head.Size.Magnitude * 1.35)
	local camera = Instance.new("Camera")
	camera.Name, camera.FieldOfView = "PortraitCamera", 24
	camera.CFrame = CFrame.lookAt(focus + forward * distance, focus, Vector3.yAxis)
	camera.Parent, viewport.CurrentCamera = viewport, camera
	viewport:SetAttribute("PortraitUserId", userId)
	if image:IsA("ImageLabel") or image:IsA("ImageButton") then image.ImageTransparency = 1 end
	viewport.Visible = true
	return true
end

-- image may be an ImageLabel or ImageButton. Real users retain their Roblox headshot; bots show the matching 3D rig.
function BotPortrait.Set(image: GuiObject?, userId: number?, avatarUserId: number?, config: any?)
	if not image then return end
	pending[image] = nil
	local viewport = image:FindFirstChild(VIEWPORT_NAME)
	if not isBot(userId) then
		image:SetAttribute("BotPortraitUserId", nil)
		if viewport and viewport:IsA("ViewportFrame") then
			clearViewport(viewport)
			viewport.Visible = false
		end
		if image:IsA("ImageLabel") or image:IsA("ImageButton") then
			local portraitId = avatarUserId or userId
			image.Image = if portraitId then "rbxthumb://type=AvatarHeadShot&id=" .. portraitId .. "&w=420&h=420" else ""
			image.ImageTransparency = 0
		end
		return
	end
	local botId = userId :: number
	image:SetAttribute("BotPortraitUserId", botId)
	if image:IsA("ImageLabel") or image:IsA("ImageButton") then
		image.Image = (config and config.BotMugshotImage) or ""
		-- Keep the old picture underneath until the replicated character is available; a completed viewport hides it.
		image.ImageTransparency = 0
	end
	viewport = viewportFor(image)
	viewport.Visible = true
	local source = sourceFor(botId)
	if source and render(image, botId, source) then return end
	pending[image] = botId
end

CollectionService:GetInstanceAddedSignal("ScaleBot"):Connect(function(instance)
	if not instance:IsA("Model") then return end
	local userId = instance:GetAttribute("ScaleBotUserId")
	if type(userId) ~= "number" then return end
	for image, wanted in pending do
		if wanted == userId then
			if render(image, userId, instance) then pending[image] = nil end
		end
	end
end)

return BotPortrait

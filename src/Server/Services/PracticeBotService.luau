--!strict
-- Creates the obvious, short-lived "Bot" used by the Play Bot button and tutorial.
-- These opponents are deliberately separate from the ambient population: they have no
-- player-like identity, avatar mugshot, cosmetics, roaming state, or population lifecycle.
local PracticeBotService = {}
PracticeBotService.__index = PracticeBotService

local function profile(): any
	local owned = { Pets = {}, Chairs = {}, Titles = {} }
	local equipped = { Pets = {} }
	local data = {
		VIP = false,
		Streak = 0,
		Wins = 0,
		Matches = 0,
		HighestStreak = 0,
		Cash = 0,
		Owned = owned,
		Equipped = equipped,
		PetAbilityProgress = {},
	}
	return { Owned = owned, Equipped = equipped, Data = data, Token = "PRACTICE_BOT", HatchAt = math.huge }
end

local function sitAnimation(character: Model, humanoid: Humanoid): (AnimationTrack?, RBXScriptConnection?)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = character:FindFirstChild("SitAnim", true)
	local ownedAnimation = false
	if not (animation and animation:IsA("Animation")) then
		animation = Instance.new("Animation")
		animation.Name = "PracticeBotSit"
		animation.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R15
			then "rbxassetid://2506281703"
			else "rbxassetid://178130996"
		ownedAnimation = true
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation :: Animation)
	end)
	if ownedAnimation then
		animation:Destroy()
	end
	if not ok or not track then
		return nil, nil
	end
	track.Looped, track.Priority = true, Enum.AnimationPriority.Action
	local connection = humanoid.Seated:Connect(function(active)
		if active and not track.IsPlaying then
			track:Play(0.15)
		elseif not active and track.IsPlaying then
			track:Stop(0.15)
		end
	end)
	return track, connection
end

function PracticeBotService.new(d: any)
	local runtime = d.World:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = d.World
	end
	local root = runtime:FindFirstChild("NPC")
	if not root then
		root = Instance.new("Folder")
		root.Name = "NPC"
		root.Parent = runtime
	end
	return setmetatable({
		D = d,
		Root = root,
		NextId = d.BotUserIdCeiling - 1000000,
		Bots = {},
		Reservations = {},
		MissingTemplateWarned = false,
	}, PracticeBotService)
end

function PracticeBotService.Template(self: any): Model?
	-- Play Bot is deliberately recognizable as the legacy practice opponent. Ambient
	-- population appearances live under ServerStorage.Characters.NPC and must never enter this path.
	local characters = self.D.ServerStorage:FindFirstChild("Characters")
	local template = characters and characters:FindFirstChild("Bot")
	if
		template
		and template:IsA("Model")
		and template:FindFirstChildOfClass("Humanoid")
		and template:FindFirstChild("HumanoidRootPart")
	then
		self.MissingTemplateWarned = false
		return template
	end
	if not self.MissingTemplateWarned then
		self.MissingTemplateWarned = true
		warn("Scale It Up: Play Bot requires ServerStorage.Characters.Bot with a Humanoid and HumanoidRootPart")
	end
	return nil
end

function PracticeBotService.Spawn(self: any, record: any): any?
	local seat = nil
	for _, candidate in self.D.Bindings:Seats(record) or {} do
		if not candidate.Occupant and not candidate:FindFirstChild("SeatWeld") and not self.Reservations[candidate] then
			seat = candidate
			break
		end
	end
	local template = self:Template()
	if not seat or not template then
		return nil
	end

	local character = template:Clone()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not (root and root:IsA("BasePart")) then
		character:Destroy()
		return nil
	end

	self.NextId -= 1
	local name = "Bot"
	character.Name = name
	character:SetAttribute("ScaleBotUserId", self.NextId)
	character:SetAttribute("ScalePracticeBot", true)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanTouch, descendant.CanQuery = false, false
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		elseif descendant:IsA("BaseScript") and descendant.Name == "Move" then
			descendant.Disabled = true
		end
	end
	root.CanTouch = true
	humanoid.DisplayName = name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	-- Position the disconnected clone before parenting, so touching a seat cannot weld it during this move.
	local rootTarget = seat.CFrame * CFrame.new(0, seat.Size.Y * 0.5 + humanoid.HipHeight + root.Size.Y * 0.5, 0)
	character:PivotTo(rootTarget * root.CFrame:Inverse() * character:GetPivot())
	character.Parent = self.Root
	if self.D.AttachBotTag then self.D.AttachBotTag(character) end
	pcall(function()
		(root :: BasePart):SetNetworkOwner(nil)
	end)

	local botProfile = profile()
	local bot = {
		IsBot = true,
		ManagedPopulation = false,
		PracticeBot = true,
		UserId = self.NextId,
		AvatarUserId = self.NextId,
		Name = name,
		DisplayName = name,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Profile = botProfile,
		ReservedSeat = seat,
	}
	bot.SitTrack, bot.SeatedConnection = sitAnimation(character, humanoid)
	self.Bots[bot] = true
	self.D.CharacterBots[character] = bot
	self.D.Profiles[bot] = botProfile
	self.Reservations[seat] = bot
	self.D.CollectionService:AddTag(character, "ScaleBot")

	seat.Disabled = false
	if not seat.Occupant and not seat:FindFirstChild("SeatWeld") and not self.D.Bindings:SeatAttachment(character) then
		seat:Sit(humanoid)
	end
	task.spawn(function()
		for attempt = 1, 4 do
			task.wait(0.15)
			if not self.Bots[bot] or not humanoid.Parent or not seat:IsDescendantOf(self.D.World) then
				return
			end
			if seat.Occupant == humanoid and humanoid.SeatPart == seat then
				self.Reservations[seat], bot.ReservedSeat = nil, nil
				if bot.SitTrack and not bot.SitTrack.IsPlaying then
					bot.SitTrack:Play(0.15)
				end
				return
			end
			if seat.Occupant and seat.Occupant ~= humanoid then
				break
			end
			if attempt < 4 and not seat:FindFirstChild("SeatWeld") and not self.D.Bindings:SeatAttachment(character) then
				seat:Sit(humanoid)
			end
		end
		self:Remove(bot)
	end)
	return bot
end

function PracticeBotService.Remove(self: any, bot: any)
	if not self.Bots[bot] then
		return
	end
	self.Bots[bot] = nil
	if bot.ReservedSeat and self.Reservations[bot.ReservedSeat] == bot then
		self.Reservations[bot.ReservedSeat] = nil
	end
	if bot.SeatedConnection then
		bot.SeatedConnection:Disconnect()
	end
	if bot.SitTrack then
		bot.SitTrack:Stop(0)
	end
	self.D.Profiles[bot] = nil
	if self.D.CharacterBots[bot.Character] == bot then
		self.D.CharacterBots[bot.Character] = nil
	end
	if bot.Character and bot.Character.Parent then
		bot.Character:Destroy()
	end
end

function PracticeBotService.Destroy(self: any)
	local bots = {}
	for bot in self.Bots do
		table.insert(bots, bot)
	end
	for _, bot in bots do
		self:Remove(bot)
	end
end

return PracticeBotService

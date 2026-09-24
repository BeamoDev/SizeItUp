--!strict
-- Own only additive visuals; never change an authored chair or avatar.
local CosmeticDisplay = {}
CosmeticDisplay.__index = CosmeticDisplay
local function color(item: any): Color3 return Color3.fromRGB(table.unpack(item.Color)) end
local function part(parent: Instance, name: string, size: Vector3, tint: Color3): Part
	local result = Instance.new("Part")
	result.Name, result.Size, result.Color = name, size, tint
	result.Anchored, result.CanCollide, result.CanQuery, result.CanTouch = true, false, false, false
	result.Material, result.CastShadow = Enum.Material.SmoothPlastic, false
	result.Parent = parent
	return result
end
local function find(root: Instance, name: string): any return root:FindFirstChild(name, true) end
local function formatCash(cash: number): string
	local reversed = string.reverse(tostring(math.floor(cash)))
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	grouped = string.gsub(string.reverse(grouped), "^,", "")
	return "$" .. grouped
end
-- Dark -> light -> dark of the title's own colour, so a sliding gradient reads as a clean shimmer.
local function titleGradient(base: Color3): ColorSequence
	local dark, light = base:Lerp(Color3.new(0, 0, 0), 0.35), base:Lerp(Color3.new(1, 1, 1), 0.65)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, dark), ColorSequenceKeypoint.new(0.5, light), ColorSequenceKeypoint.new(1, dark) })
end
function CosmeticDisplay.new(world: Instance, catalog: any, chairVisual: any?, storage: Instance?)
	local runtime = world:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = world
	end
	local other = runtime:FindFirstChild("Other")
	if not other then
		other = Instance.new("Folder")
		other.Name = "Other"
		other.Parent = runtime
	end
	local root = Instance.new("Folder")
	root.Name, root.Parent = "ScaleCosmeticDisplays", other
	return setmetatable({ World = world, Root = root, Catalog = catalog, ChairVisual = chairVisual, Storage = storage, Views = {} }, CosmeticDisplay)
end
-- Authored BillboardGui templates live in ReplicatedStorage.Assets.UI (HeadTag, CashTag).
function CosmeticDisplay.Asset(self: any, name: string): any
	local assets = self.Storage and self.Storage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild(name)
	if template and template:IsA("BillboardGui") then return template end
	return nil
end
-- Both tags attach to the HumanoidRootPart, the point their authored offsets are measured from.
function CosmeticDisplay.BuildHeadTag(_self: any, template: any, parent: Instance, anchor: BasePart, player: any, definition: any?): any
	local tag = template:Clone()
	tag.Name, tag.Adornee = "HeadTag", anchor
	local username, title = find(tag, "Username"), find(tag, "Title")
	if username and username:IsA("TextLabel") then username.Text = player.Name end
	if title and title:IsA("TextLabel") then
		title.Visible = definition ~= nil
		if definition then
			title.Text = definition.Name
			title.TextColor3 = Color3.new(1, 1, 1)
			local gradient = title:FindFirstChildOfClass("UIGradient")
			if not gradient then gradient = Instance.new("UIGradient");gradient.Name = "TitleGradient";gradient.Parent = title end
			gradient.Color = titleGradient(color(definition))
			-- The client eases Offset with a per-player phase; the server only describes the motion.
			gradient:SetAttribute("Shimmer", 1.4)
			gradient:SetAttribute("ShimmerPhase", (player.UserId % 7) * 0.9)
		end
	end
	tag.Parent = parent
	return tag
end
function CosmeticDisplay.Remove(self: any, player: any)
	local view = self.Views[player]
	if view then view.Root:Destroy(); self.Views[player] = nil end
end
function CosmeticDisplay.Update(self: any, player: any, profile: any, now: number, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not root:IsDescendantOf(self.World) or not humanoid or humanoid.Health <= 0 then self:Remove(player); return end
	local equipped = profile.Equipped
	local view = self.Views[player]
	if view and (view.Character ~= character or view.Anchor ~= root or view.ChairId ~= equipped.Chairs or view.TitleId ~= equipped.Titles) then
		self:Remove(player); view = nil
	end
	if not view then
		local folder = Instance.new("Folder")
		folder.Name, folder.Parent = tostring(player.UserId), self.Root
		view = { Root = folder, Character = character, Anchor = root, ChairId = equipped.Chairs, TitleId = equipped.Titles }
		self.Views[player] = view
		local definition = equipped.Titles and self.Catalog.Items.Titles[equipped.Titles]
		local headTemplate = self:Asset("HeadTag")
		if headTemplate then
			do
				view.HeadTag = self:BuildHeadTag(headTemplate, folder, root, player, definition)
				view.VIPBadge = find(view.HeadTag, "VIP")
				view.Username = find(view.HeadTag, "Username")
				view.StreakFrame = find(view.HeadTag, "Streak")
				view.StreakLabel = view.StreakFrame and find(view.StreakFrame, "Label")
			end
		end
	end
	local vip = player.UserId == 1790165114 or (if profile.Data then profile.Data.VIP == true else player:GetAttribute("VIP") == true)
	if view.LastVIP ~= vip then
		view.LastVIP = vip
		local badge, username = view.VIPBadge, view.Username
		if badge and badge:IsA("GuiObject") then badge.Visible = vip end
		if view.StreakFrame and view.StreakFrame:IsA("GuiObject") then
			view.StreakFrame.Position = UDim2.new(if badge and badge:IsA("GuiObject") and badge.Visible then 0.65 else 0.5, 0, -0.2, 0)
		end
		if username and username:IsA("TextLabel") then
			if vip then
				view.UsernameStyle = { Color = username.TextColor3, Stroke = username.TextStrokeColor3, Transparency = username.TextStrokeTransparency, Gradients = {} }
				for _, child in username:GetChildren() do
					if child:IsA("UIGradient") then view.UsernameStyle.Gradients[child] = child.Enabled;child.Enabled = false end
				end
				username.TextColor3, username.TextStrokeColor3, username.TextStrokeTransparency = Color3.new(1,1,1), Color3.fromRGB(255,190,45), 0.55
				local gradient = Instance.new("UIGradient")
				gradient.Name = "VIPUsernameGradient"
				gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255,175,25)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,245,175)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255,175,25)) })
				gradient:SetAttribute("Shimmer", 1.6)
				gradient:SetAttribute("ShimmerPhase", (player.UserId % 7) * 0.9)
				gradient:SetAttribute("GoldPulse", true)
				gradient.Parent = username
				view.VIPGradient = gradient
			elseif view.UsernameStyle then
				if view.VIPGradient then view.VIPGradient:Destroy();view.VIPGradient = nil end
				local saved = view.UsernameStyle
				username.TextColor3, username.TextStrokeColor3, username.TextStrokeTransparency = saved.Color, saved.Stroke, saved.Transparency
				for gradient, enabled in saved.Gradients do if gradient.Parent then gradient.Enabled = enabled end end
				view.UsernameStyle = nil
			end
		end
	end
	if view.StreakFrame and view.StreakFrame:IsA("GuiObject") then
		-- HeadTag.Streak appears from a streak of 1 and Streak.Label shows the value.
		local streak = math.max(0, math.floor(if profile.Data then profile.Data.Streak or 0 else player:GetAttribute("Streak") or 0))
		if view.LastStreak ~= streak then
			view.LastStreak = streak
			view.StreakFrame.Visible = streak >= 1
			if view.StreakLabel and view.StreakLabel:IsA("TextLabel") then view.StreakLabel.Text = tostring(streak) end
		end
	end
	-- A VIP with no streak has the badge alone: centre it (X scale 0.5). With a streak it keeps its authored spot.
	local vipBadge = view.VIPBadge
	if vipBadge and vipBadge:IsA("GuiObject") then
		view.BadgeRest = view.BadgeRest or vipBadge.Position
		local rest = view.BadgeRest
		local wanted = if vip and (view.LastStreak or 0) < 1 then UDim2.new(0.5, rest.X.Offset, rest.Y.Scale, rest.Y.Offset) else rest
		if vipBadge.Position ~= wanted then vipBadge.Position = wanted end
	end
	local cash = if profile.Data then profile.Data.Cash else player:GetAttribute("Cash") or 0
	local cashTemplate = self:Asset("CashTag")
	local templateLabel = cashTemplate and find(cashTemplate, "Label")
	if cashTemplate and templateLabel and templateLabel:IsA("TextLabel") then
		-- Authored CashTag, used exactly as authored (no code-set offsets): Label shows $1,000-style cash and the tag hides at zero.
		do
			if not view.CashTag then
				view.CashTag = cashTemplate:Clone()
				view.CashTag.Name, view.CashTag.Adornee = "CashTag", root
				view.CashTag.Parent = view.Root
				view.CashLabel = find(view.CashTag, "Label")
			end
			if view.LastCash ~= cash then
				view.CashLabel.Text, view.CashLabel.Visible, view.CashTag.Enabled = formatCash(cash), cash > 0, cash > 0
				view.CashTag:SetAttribute("CashShown", cash > 0)
				view.LastCash = cash
			end
		end
	end
	local seat = humanoid.SeatPart
	-- Seat ancestry and chair assets are stable while a humanoid remains seated. Cache that lookup instead of walking
	-- the table hierarchy and searching ReplicatedStorage for every player on every 20 Hz display tick.
	if view.CachedSeat ~= seat then
		view.CachedSeat = seat
		view.AuthoredChair = false
		local ancestor = seat
		while ancestor and ancestor ~= self.World do
			if ancestor:GetAttribute("PreserveAuthoredChairs") then
				view.AuthoredChair = true
				break
			end
			ancestor = ancestor.Parent
		end
	end
	local authoredChair = view.AuthoredChair
	-- Authored table furniture always remains exactly as built; equipped-chair visuals are suppressed there.
	if not authoredChair and equipped.Chairs and seat and seat:IsA("Seat") and seat.Parent and seat:IsDescendantOf(self.World) then
		if not view.Chair then
			local definition = self.Catalog.Items.Chairs[equipped.Chairs]
			if definition.Visual and self.ChairVisual then
				view.Chair = self.ChairVisual.Build(view.Root,definition,CFrame.new())
			else view.Chair = part(view.Root, "ChairBack", Vector3.new(seat.Size.X + 0.3, 3.3, 0.3), color(definition)) end
		end
		if view.Chair:IsA("Model") then
			if view.ChairFrame~=seat.CFrame then view.Chair:PivotTo(seat.CFrame);view.ChairFrame=seat.CFrame end
		else
			if view.Seat ~= seat then view.Chair.Size = Vector3.new(seat.Size.X + 0.3, 3.3, 0.3); view.Seat = seat end
			view.Chair.CFrame = seat.CFrame * CFrame.new(0, 1.45, seat.Size.Z * 0.5 + 0.25)
		end
	elseif view.Chair then view.Chair:Destroy(); view.Chair,view.ChairFrame = nil,nil end
end
function CosmeticDisplay.Tick(self: any, profiles: any, now: number, dt: number)
	for player in self.Views do if not profiles[player] then self:Remove(player) end end
	for player, profile in profiles do self:Update(player, profile, now, dt) end
end
function CosmeticDisplay.Destroy(self: any)
	self.Root:Destroy(); table.clear(self.Views)
end
return CosmeticDisplay

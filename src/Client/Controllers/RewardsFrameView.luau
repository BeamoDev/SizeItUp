--!strict
-- Binds the authored HUD.Frame.Rewards overlay and presents Play Time, Daily and Group rewards. It builds no UI;
-- the only things it creates are ReadyMark clones of Playtime["!"] and a Viewport's ViewportFrame when missing.
--   Frame.Frame.Timed / Daily / Group   tab buttons; Header.ActiveStroke is enabled on the open tab
--   Frame.DiffRewards.Playtime / Daily / Group   the three pages, one visible at a time
--   Frame.Header.Close                  closes (InventoryController wires it and the tab buttons)
--   Playtime.RewardN, Daily.Frame.DayN  Claimed, PurchaseButton.Frame.TextLabel (claim / countdown), sunburst
--   Playtime["!"]                       cloned into the PurchaseButton of every claimable playtime reward
--   Group.Frame.Reward1-3 + Group.Verify  cash, boost and chair (shown in Reward3.Viewport); Verify claims once
-- The server still owns every claim; this only shows state and sends the same ClaimReward requests.
local Style = require(script.Parent.UIStyle)
local FrameSlide = require(script.Parent.FrameSlide)
local RewardsFrameView = {}
RewardsFrameView.__index = RewardsFrameView

local SUNBURST_DEGREES_PER_SECOND = 12
-- The chair fills 1.5x as much of its viewport (the camera orbits 1.5x closer), lit in soft blue.
local CHAIR_ORBIT_RADIUS, CHAIR_ORBIT_HEIGHT = 8 / 1.5, 2 / 1.5
local CHAIR_AMBIENT, CHAIR_LIGHT = Color3.fromRGB(105, 145, 255), Color3.fromRGB(175, 210, 255)
local TAB_PAGES = { Timed = "Playtime", Daily = "Daily", Group = "Group" }
local TAB_ORDER = { "Timed", "Daily", "Group" }

local function timeText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 86400 then return string.format("%dd %02dh", seconds // 86400, seconds % 86400 // 3600) end
	if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60) end
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

-- The authored tile may be a button itself or an image holding one (e.g. a nested "B"): clicks and Active use that button.
local function clickable(node: Instance?): GuiButton?
	if not node then return nil end
	if node:IsA("GuiButton") then return node end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end

local function needClickable(node: Instance): GuiButton
	local button = clickable(node)
	assert(button, "Missing authored UI: " .. node:GetFullName() .. " (a button, or a child button)")
	return button
end

-- "$200", "1 Gem", "10m 2x Time", "Electric chair": what the tile gives, shown in NonInteractives.Frame.TextLabel.
local function rewardName(reward: any, catalog: any): string
	local parts = {}
	if reward.Cash then table.insert(parts, Style.Money(reward.Cash)) end
	if reward.Keys then table.insert(parts, reward.Keys .. (if reward.Keys == 1 then " Gem" else " Gems")) end
	if reward.BoostSeconds then table.insert(parts, math.floor(reward.BoostSeconds / 60) .. "m 2x Time") end
	local chair = reward.Chair and catalog.Items.Chairs[reward.Chair]
	if chair then table.insert(parts, chair.Name .. " chair") end
	local pet = reward.Pet and catalog.Items.Pets[reward.Pet]
	if pet then table.insert(parts, pet.Name) end
	return table.concat(parts, " + ")
end

local function bindItem(node: Instance): any
	local button = node:FindFirstChild("PurchaseButton", true)
	local plain = node:FindFirstChild("NonInteractives", true)
	return {
		Node = node,
		NameLabel = if plain then plain:FindFirstChild("TextLabel", true) else nil,
		Button = button,
		Click = clickable(button),
		Label = if button then button:FindFirstChild("TextLabel", true) else nil,
		Claimed = node:FindFirstChild("Claimed", true),
	}
end

local function showItem(item: any, claimed: boolean, ready: boolean, text: string)
	if item.Claimed then item.Claimed.Visible = claimed end
	if item.Button then
		item.Button.Visible = not claimed
		if item.Click then item.Click.Active = ready end
	end
	if item.Label then item.Label.Text = text end
	if item.Mark then item.Mark.Visible = ready end
end

function RewardsFrameView.new(catalog: any, rewards: any)
	local UI = Style.Authoring
	local need = UI.Need
	local root = need(UI.Overlays, "Rewards", "GuiObject")
	local frame = need(root, "Frame", "GuiObject")
	local pages = need(frame, "DiffRewards")
	local tabBar = need(frame, "Frame", "GuiObject")
	local headerNode = frame:FindFirstChild("Header")
	local self: any = setmetatable({
		Catalog = catalog, Config = rewards, Gui = root, Titles = headerNode and headerNode:FindFirstChild("Titles"), Close = needClickable(need(need(frame, "Header", "GuiObject"), "Close", "GuiObject")),
		Tabs = {}, Pages = {}, Daily = {}, Timed = {}, Suns = {}, Age = 0, Elapsed = 0,
	}, RewardsFrameView)

	for _, tab in TAB_ORDER do
		local tile = need(tabBar, tab, "GuiObject")
		self.Tabs[tab] = { Button = needClickable(tile), Stroke = need(need(tile, "Header", "GuiObject"), "ActiveStroke", "UIStroke") }
		self.Pages[tab] = need(pages, TAB_PAGES[tab], "GuiObject")
	end

	local dailyList = need(self.Pages.Daily, "Frame", "GuiObject")
	for index in rewards.Daily do
		-- The last day may sit beside the grid (Daily.Day7) instead of inside it (Daily.Frame.Day7).
		local day = dailyList:FindFirstChild("Day" .. index) or self.Pages.Daily:FindFirstChild("Day" .. index)
		assert(day and day:IsA("GuiObject"), "Missing authored UI: " .. dailyList:GetFullName() .. ".Day" .. index .. " (GuiObject)")
		-- The day titles (DAY 1, DAY 2 ...) are authored and never overwritten.
		local item = bindItem(day)
		table.insert(self.Daily, item)
	end

	-- The authored playtime list may hold fewer slots than the catalog: report it and hide any extras.
	local mark = self.Pages.Timed:FindFirstChild("!")
	if mark then mark.Visible = false end
	for index in rewards.Timed do
		local node = self.Pages.Timed:FindFirstChild("Reward" .. index)
		if node then
			local item = bindItem(node)
			if mark and item.Button then
				local clone = mark:Clone()
				clone.Name = "ReadyMark"
				clone.Visible = false
				clone.Parent = item.Button
				item.Mark = clone
			end
			if item.NameLabel then item.NameLabel.Text = rewardName(rewards.Timed[index], catalog) end
			self.Timed[index] = item
		else
			warn("Missing authored UI: " .. self.Pages.Timed:GetFullName() .. ".Reward" .. index .. " (playtime reward " .. rewards.Timed[index].Id .. ")")
		end
	end
	local index = #rewards.Timed + 1
	while true do
		local extra = self.Pages.Timed:FindFirstChild("Reward" .. index)
		if not extra then break end
		if extra:IsA("GuiObject") then extra.Visible = false end
		index += 1
	end

	local groupList = need(self.Pages.Group, "Frame", "GuiObject")
	self.Group = bindItem(self.Pages.Group)
	self.Group.Claimed = self.Pages.Group:FindFirstChild("Claimed", true)
	self.Verify = needClickable(need(self.Pages.Group, "Verify", "GuiObject"))
	self:BindGroup(groupList)

	for _, descendant in root:GetDescendants() do
		if descendant.Name == "sunburst" and descendant:IsA("GuiObject") then table.insert(self.Suns, descendant) end
	end
	self.Slide = FrameSlide.new(root)
	Style.SetEnabled(root, false)
	return self
end

-- Reward3 shows the chair in its Viewport. Every label on the group page is authored and left untouched.
function RewardsFrameView.BindGroup(self: any, list: Instance)
	local reward = self.Config.Group
	local slot = list:FindFirstChild("Reward3")
	local chair = reward.Chair and self.Catalog.Items.Chairs[reward.Chair]
	if not (slot and chair) then return end
	local holder = slot:FindFirstChild("Viewport")
	if not holder then return end
	local viewport = if holder:IsA("ViewportFrame") then holder else holder:FindFirstChildWhichIsA("ViewportFrame", true)
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name, viewport.Size, viewport.BackgroundTransparency = "ChairViewport", UDim2.fromScale(1, 1), 1
		viewport.Parent = holder
	end
	local ok, message = pcall(Style.Preview, holder, chair, "Chairs", viewport)
	if not ok then warn("Group chair preview failed: " .. tostring(message)) return end
	-- Better, bluer lighting than the shared preview default.
	pcall(function()
		viewport.Ambient, viewport.LightColor = CHAIR_AMBIENT, CHAIR_LIGHT
		viewport.LightDirection = Vector3.new(-0.6, -1, -0.8)
	end)
	self.ChairCamera = viewport:FindFirstChild("PreviewCamera")
end

-- Which of Header.Titles' labels belongs to each tab (matched by a word in its name).
local TITLE_WORDS = { Timed = "play", Daily = "daily", Group = "group" }

function RewardsFrameView.SetTab(self: any, tab: string)
	self.Tab = tab
	-- Header.Titles holds one label per page ("Daily Rewards", "Group Rewards", "PlayTime Rewards"): show the open one.
	local titles = self.Titles
	if titles then
		for _, label in titles:GetChildren() do
			if label:IsA("GuiObject") then label.Visible = string.find(string.lower(label.Name), TITLE_WORDS[tab], 1, true) ~= nil end
		end
	end
	for name, page in self.Pages do
		page.Visible = name == tab
		self.Tabs[name].Stroke.Enabled = name == tab
	end
end

function RewardsFrameView.Show(self: any, visible: boolean)
	if visible == (self.Open == true) then return end
	self.Open = visible
	if visible then self:SetTab("Timed");self.Slide:Show() else self.Slide:Hide() end
end

-- Adds a claim request for every reward button; the controller connects them on each render.
function RewardsFrameView.Render(self: any, state: any, actions: any)
	local snapshot = state.Rewards
	if not snapshot then return end
	self.Snapshot, self.Elapsed = snapshot, 0
	local function claim(item: any, category: string, id: string)
		if item and item.Click then table.insert(actions, { Button = item.Click, Action = "ClaimReward", Payload = { Category = category, Id = id } }) end
	end
	for index, reward in self.Config.Daily do claim(self.Daily[index], "Daily", reward.Id) end
	for index, reward in self.Config.Timed do claim(self.Timed[index], "Play Time", reward.Id) end
	table.insert(actions, { Button = self.Verify, Action = "ClaimReward", Payload = { Category = "Group", Id = self.Config.Group.Id } })
	self:Update()
end

function RewardsFrameView.SetElapsed(self: any, elapsed: number)
	self.Elapsed = elapsed
	self:Update()
end

function RewardsFrameView.Update(self: any)
	local s = self.Snapshot
	if not s then return end
	local elapsed = self.Elapsed
	local now = s.Now + elapsed
	local timed = s.TimedSeconds + elapsed + math.clamp(s.BoostUntil - s.Now, 0, elapsed)

	local daily = self.Config.Daily
	local completed = if s.DailyCompleted == #daily and now >= s.DailyReadyAt then 0 else s.DailyCompleted
	local untilNext = math.max(0, s.DailyReadyAt - now)
	for index, item in self.Daily do
		local claimed = index <= completed
		local ready = index == s.DailyNext and untilNext == 0 and not claimed
		-- Every unclaimed day counts down to its own unlock: the next one now, later ones a day apart.
		local wait = untilNext + math.max(0, index - s.DailyNext) * self.Config.DailySeconds
		showItem(item, claimed, ready, if ready then "Claim" else timeText(wait))
	end

	for index, item in self.Timed do
		local reward = self.Config.Timed[index]
		local claimed = s.TimedClaims[reward.Id] == true
		local remaining = math.max(0, reward.Seconds - timed)
		local ready = not claimed and remaining == 0
		showItem(item, claimed, ready, if ready then "Claim" else timeText(remaining))
	end

	-- Verify only acts while the reward is unclaimed; once claimed a click does nothing.
	local groupClaimed = s.GroupClaimed == true
	-- Verify stays clickable so an already-claimed player is told so; the server never grants it twice.
	self.Verify.Active = s.GroupId > 0
	if self.Group.Claimed then self.Group.Claimed.Visible = groupClaimed end
end

function RewardsFrameView.Step(self: any, dt: number)
	self.Slide:Step(dt)
	if not self.Open then return end
	self.Age += dt
	self.Elapsed += dt
	self:Update()
	local spin = (self.Age * SUNBURST_DEGREES_PER_SECOND) % 360
	for _, sun in self.Suns do sun.Rotation = spin end
	local camera = self.ChairCamera
	if camera and camera.Parent then
		local angle = self.Age * 0.5
		camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(angle) * CHAIR_ORBIT_RADIUS, CHAIR_ORBIT_HEIGHT, math.cos(angle) * CHAIR_ORBIT_RADIUS), Vector3.zero)
	end
end

function RewardsFrameView.Destroy(self: any)
	for _, item in self.Timed do
		if item.Mark then item.Mark:Destroy();item.Mark = nil end
	end
	self.Open = false
	self.Slide:Reset()
end

return RewardsFrameView

--!strict
-- Binds the authored lobby HUD (HUD.Lobby). Nothing here creates UI; every control is looked up by name:
--   CurrencyDisplay.Cash.Amount / CurrencyDisplay.Gems.Amount   the balances (the A icons stay as authored)
--   Lower.Chairs / Lower.Pets / Lower.Titles                    inventory shortcuts
--   left.Store / left.Free / left.Profile                       Shop, Rewards and Profile menus
--   right.LuckyBlocks                                           the lucky block showroom
--   Upper.InviteFrame                                           the friend alert (see FriendInviteView)
--   <button>.Close                                              the optional badge frame on each button; only the "!" inside
--                                                               it is shown while there is something new or claimable and
--                                                               hidden once the button is used (Close itself is never changed)
--   The balances count up or down (with a tick sound) whenever they change, in the lobby and during a match.
-- Groups slide off their own screen edge while a match, a hatch or a menu takes over, and slide back in.
local Style = require(script.Parent.UIStyle)
local Lobby = {}
Lobby.__index = Lobby

-- Which page each button opens, and which way each group leaves the screen.
local BUTTONS = {
	{ Group = "Lower", Name = "Chairs", Page = "Chairs" },
	{ Group = "Lower", Name = "Pets", Page = "Pets" },
	{ Group = "Lower", Name = "Titles", Page = "Titles" },
	{ Group = "left", Name = "Store", Page = "Shop" },
	{ Group = "left", Name = "Free", Page = "Rewards" },
	{ Group = "left", Name = "Profile", Page = "Profile" },
	{ Group = "right", Name = "LuckyBlocks", Page = "Blocks" },
}
local EXITS = {
	CurrencyDisplay = Vector2.new(0, -0.3), Upper = Vector2.new(0, -0.3),
	Lower = Vector2.new(0, 0.3), left = Vector2.new(-0.3, 0), right = Vector2.new(0.3, 0),
}
local CURRENCY_GROUPS = { CurrencyDisplay = true }
local ROLL_SPEED = 9 -- how fast a balance chases its new value
local TICK_GAP = 0.05

local function need(parent: Instance, name: string, class: string?): any
	local node = parent:FindFirstChild(name)
	assert(node and (not class or node:IsA(class)), "Missing authored UI: " .. parent:GetFullName() .. "." .. name .. (if class then " (" .. class .. ")" else ""))
	return node
end

-- The "!" inside a badge frame: a TextLabel reading "!", else the frame's first GuiObject child.
local function findMark(holder: Instance): Instance?
	for _, child in holder:GetDescendants() do
		if child:IsA("TextLabel") and child.Text == "!" then return child end
	end
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then return child end
	end
	return nil
end

-- 12345 -> "12,345"
function Lobby.Format(amount: number): string
	local text = tostring(math.floor(math.max(0, amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(grouped), "^,", ""))
end

function Lobby.new(root: Instance)
	local self: any = setmetatable({ Root = root, Buttons = {}, Groups = {}, Amounts = {}, Wanted = { Dock = true, Currency = true } }, Lobby)
	-- Optional: only present once the owner authors it. Shown while seated alone at an empty 1v1 table.
	self.PlayBot = root:FindFirstChild("PlayBot")
	local currency = need(root, "CurrencyDisplay")
	self.Cash = need(need(currency, "Cash"), "Amount", "TextLabel")
	self.Gems = need(need(currency, "Gems"), "Amount", "TextLabel")
	self.Badges, self.Shown, self.Targets, self.RollTick = {}, {}, {}, 0
	for _, entry in BUTTONS do
		local button = need(need(root, entry.Group), entry.Name, "GuiButton")
		self.Buttons[entry.Page] = button
		-- Only the "!" inside Close is shown or hidden; the Close frame itself is never touched.
		local holder = button:FindFirstChild("Close")
		local mark = holder and (holder:FindFirstChild("!", true) or findMark(holder))
		if mark and mark:IsA("GuiObject") then
			self.Badges[entry.Page] = { Node = mark, Wanted = false, Value = 0, Seen = 0 }
			mark.Visible = false
		end
	end
	for name in EXITS do
		local group = root:FindFirstChild(name)
		if group and group:IsA("GuiObject") then
			-- This view alone moves these groups; the load-in intro and the scene wipe must not fight it for their position
			-- (a wipe or intro that captured a mid-slide pose could leave the buttons off screen).
			group:SetAttribute("NoLoadMotion", true)
			group:SetAttribute("GameHUDMotion", true)
			group.Visible = true
			table.insert(self.Groups, { Node = group, Name = name, Amount = 1 })
		end
	end
	return self
end

-- The first call shows the balances at once; later changes roll toward the new value (see Step).
function Lobby.SetCurrency(self: any, cash: number, gems: number)
	if not self.Targets.Cash then
		self.Shown.Cash, self.Shown.Gems = cash, gems
		self.Cash.Text, self.Gems.Text = Lobby.Format(cash), Lobby.Format(gems)
	end
	self.Targets.Cash, self.Targets.Gems = cash, gems
end

-- value: how many new or claimable things the button stands for. The badge shows while that is more than what the
-- player already acknowledged by using the button, and a bigger value later shows it again.
function Lobby.SetBadge(self: any, page: string, value: number)
	local badge = self.Badges[page]
	if not badge then return end
	badge.Value = value
	badge.Seen = math.min(badge.Seen, value)
	badge.Wanted = value > badge.Seen
end

function Lobby.Acknowledge(self: any, page: string)
	local badge = self.Badges[page]
	if not badge then return end
	badge.Seen = badge.Value
	badge.Wanted = false
end

-- dock: the button groups and the friend alert; currency: the balances (which stay put while the lucky blocks open).
function Lobby.SetVisible(self: any, dock: boolean, currency: boolean)
	self.Wanted.Dock, self.Wanted.Currency = dock, currency
end

function Lobby.SetPlayBotVisible(self: any, visible: boolean)
	if self.PlayBot then self.PlayBot.Visible = visible end
end

local function stepBadges(self: any)
	for _, badge in self.Badges do
		if badge.Node.Visible ~= badge.Wanted then badge.Node.Visible = badge.Wanted end
	end
end

local function stepBalances(self: any, dt: number)
	if not self.Targets.Cash then return end
	local moved, direction = false, 0
	local blend = 1 - math.exp(-ROLL_SPEED * dt)
	for _, key in { "Cash", "Gems" } do
		local shown, goal = self.Shown[key], self.Targets[key]
		if shown ~= goal then
			local before = math.floor(shown + 0.5)
			shown += (goal - shown) * blend
			if math.abs(goal - shown) < 0.5 then shown = goal end
			self.Shown[key] = shown
			local after = math.floor(shown + 0.5)
			if after ~= before then moved, direction = true, if after > before then 1 else -1 end
			local label = if key == "Cash" then self.Cash else self.Gems
			label.Text = Lobby.Format(shown)
		end
	end
	self.RollTick -= dt
	local sfx = Style.Sfx
	if moved and self.RollTick <= 0 and sfx then
		self.RollTick = TICK_GAP
		sfx:Play(if direction > 0 then "TickUp" else "TickDown")
	end
end

function Lobby.Step(self: any, dt: number)
	stepBadges(self)
	stepBalances(self, dt)
	local alpha = 1 - math.exp(-Style.Pacing.LobbySpeed * dt)
	for _, group in self.Groups do
		local wanted = if CURRENCY_GROUPS[group.Name] then self.Wanted.Currency else self.Wanted.Dock
		group.Amount += ((if wanted then 1 else 0) - group.Amount) * alpha
		local hidden = not wanted and group.Amount < 0.002
		group.Node.Visible = not hidden
		local away = EXITS[group.Name] * (1 - group.Amount)
		local pose = Style.Authoring.Pose(group.Node).Position
		group.Node.Position = pose + UDim2.fromScale(away.X, away.Y)
	end
end

-- Puts every group back exactly where it was authored.
function Lobby.Destroy(self: any)
	for _, group in self.Groups do
		group.Node.Position = Style.Authoring.Pose(group.Node).Position
	end
	for _, badge in self.Badges do
		badge.Node.Visible = false
	end
	self.Groups, self.Badges = {}, {}
end

return Lobby

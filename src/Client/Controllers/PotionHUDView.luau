--!strict
-- The lobby's active-potion list: HUD.Lobby.Potions.Template is cloned once for every 2x potion that is running, showing
-- the potion's own fixed icon and the time left in its TextLabel. Only Template.Icon's Image changes -- never its Size or
-- any other property. Hovering a clone shows Lobby.InfoCard (title + what it does); nothing else is created. Clones go
-- away when their potion runs out. The template itself stays hidden.
local Style = require(script.Parent.UIStyle)
local Potions = {}
Potions.__index = Potions

local ORDER = { "Cash", "Streak", "Wins" }
local ICON_IMAGES = { Cash = "rbxassetid://123245550387872", Streak = "rbxassetid://116701584881975", Wins = "rbxassetid://88736776300074" }

local function timeText(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 86400 then return string.format("%dd %02dh", seconds // 86400, seconds % 86400 // 3600) end
	if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60) end
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end
Potions.TimeText = timeText

-- Returns nil when the HUD has no Lobby.Potions.Template.
function Potions.new(): any?
	local lobby = Style.Authoring and Style.Authoring.Lobby
	local holder = lobby and lobby:FindFirstChild("Potions")
	local template = holder and holder:FindFirstChild("Template")
	if not (holder and template and template:IsA("GuiObject")) then return nil end
	template.Visible = false
	return setmetatable({ Holder = holder, Template = template, Entries = {}, Snapshot = nil, Elapsed = 0 }, Potions)
end

-- snapshot: state.Potions (Now, Cash, Streak, Wins expiry times); elapsed: seconds since it was received.
function Potions.Set(self: any, snapshot: any, elapsed: number)
	self.Snapshot, self.Elapsed = snapshot, elapsed
	self:Update()
end

function Potions.Step(self: any, dt: number)
	self.Elapsed += math.max(0, dt)
	self:Update()
end

function Potions.Update(self: any)
	local snapshot = self.Snapshot
	for index, boost in ORDER do
		local remaining = if snapshot then (snapshot[boost] or 0) - (snapshot.Now + self.Elapsed) else 0
		local entry = self.Entries[boost]
		if remaining > 0 then
			if not entry then
				local clone = self.Template:Clone()
				clone.Name = "Potion" .. boost
				clone.Visible = true
				if clone:IsA("GuiObject") then clone.LayoutOrder = index end
				entry = { Node = clone, Label = clone:FindFirstChild("TextLabel") }
				-- Only the icon's Image changes; its authored Size (and everything else) is left exactly alone.
				local icon = clone:FindFirstChild("Icon")
				if icon and icon:IsA("ImageLabel") then icon.Image = ICON_IMAGES[boost] end
				Style.BindPotionHover(clone, "2x " .. boost)
				clone.Parent = self.Holder
				self.Entries[boost] = entry
			end
			if entry.Label and entry.Label:IsA("TextLabel") then entry.Label.Text = timeText(remaining) end
		elseif entry then
			entry.Node:Destroy()
			self.Entries[boost] = nil
		end
	end
end

-- Hidden while the Game frame is showing (a match) and while the Store page itself is open (its own tiles already show
-- each potion's running state); visible the rest of the time in the lobby.
function Potions.SetVisible(self: any, visible: boolean)
	self.Holder.Visible = visible
end

function Potions.Destroy(self: any)
	for boost, entry in self.Entries do entry.Node:Destroy();self.Entries[boost] = nil end
end

return Potions

--!strict
-- Binds the authored HUD.Frame.Profile overlay for your own profile and for other players' profiles. It builds no UI;
-- it may create pet preview frames and the shared local 3D portrait viewport used for bots.
--   Mugshot.ImageLabel / Mugshot.LevelLabel   their headshot and "Lvl. N"
--   TextInfo.Username / AtUsername / VipStatu  display name, "@name" and "Vip: Yes/No"
--   Header.Close                               closes (InventoryController wires it)
--   Stats.Container.Wins / WinRate / HighestStreak / LoginStreak / Playtime   each shows its value in Frame.TextLabel
--   PetLoadout.Block1-8                        the player's equipped pets in order, for you and for anyone you view.
--                                              Without VIP blocks 4 and 8 stay empty; on your own profile their ImageButton
--                                              is visible and opens the Shop (where the VIP bundle is). With VIP that
--                                              button hides and all eight blocks hold pets.
local Style = require(script.Parent.UIStyle)
local FrameSlide = require(script.Parent.FrameSlide)
local BotPortrait = require(script.Parent.BotPortrait)
local ProfileFrameView = {}
ProfileFrameView.__index = ProfileFrameView

local BLOCKS = 8
local LOCKED_BLOCKS = { [4] = true, [8] = true }
local STATS = { "Wins", "WinRate", "HighestStreak", "LoginStreak", "Playtime" }

local function commas(value: number): string
	local text = string.format("%d", math.floor(value))
	local reversed = string.reverse(text)
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(grouped), "^,", ""))
end

-- "5H 30M", or just "30M" under an hour.
local function playtime(seconds: number): string
	local minutes = math.floor(math.max(0, seconds) / 60)
	if minutes >= 60 then return string.format("%dH %dM", minutes // 60, minutes % 60) end
	return minutes .. "M"
end

local function deep(within: Instance, name: string, class: string, missing: {string}): any
	for _, node in within:GetDescendants() do
		if node.Name == name and node:IsA(class) then return node end
	end
	table.insert(missing, within:GetFullName() .. ".." .. name .. " (" .. class .. ")")
	return nil
end

local function clickable(node: Instance?): GuiButton?
	if not node then return nil end
	if node:IsA("GuiButton") then return node end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end

function ProfileFrameView.new(catalog: any, ownUserId: number)
	local UI = Style.Authoring
	local root = UI.Need(UI.Overlays, "Profile", "GuiObject")
	local missing: {string} = {}
	local mugshot = deep(root, "Mugshot", "GuiObject", missing)
	local info = deep(root, "TextInfo", "GuiObject", missing)
	local header = deep(root, "Header", "GuiObject", missing)
	local loadout = deep(root, "PetLoadout", "GuiObject", missing)
	local stats = deep(root, "Stats", "GuiObject", missing)
	local self: any = setmetatable({
		Catalog = catalog, OwnUserId = ownUserId, Gui = root, Age = 0, Previews = {}, Blocks = {}, Stats = {},
	}, ProfileFrameView)
	if mugshot then
		self.Icon = deep(mugshot, "ImageLabel", "ImageLabel", missing)
		self.Level = deep(mugshot, "LevelLabel", "TextLabel", missing)
	end
	if info then
		self.Username = deep(info, "Username", "TextLabel", missing)
		self.AtUsername = deep(info, "AtUsername", "TextLabel", missing)
		-- "VipStatu" is the authored spelling; VipStatus is accepted too.
		local before = #missing
		self.Vip = deep(info, "VipStatu", "TextLabel", missing)
		if not self.Vip then
			while #missing > before do table.remove(missing) end
			self.Vip = deep(info, "VipStatus", "TextLabel", missing)
		end
	end
	if header then
		local close = deep(header, "Close", "GuiObject", missing)
		self.Close = clickable(close)
		if close and not self.Close then table.insert(missing, close:GetFullName() .. " (a button, or a child button)") end
	end
	if stats then
		for _, name in STATS do
			local stat = deep(stats, name, "GuiObject", missing)
			if stat then self.Stats[name] = deep(stat, "TextLabel", "TextLabel", missing) end
		end
	end
	self.Loadout = loadout
	if loadout then
		for index = 1, BLOCKS do
			local block = loadout:FindFirstChild("Block" .. index)
			if not (block and block:IsA("GuiObject")) then table.insert(missing, loadout:GetFullName() .. ".Block" .. index .. " (GuiObject)")
			else
				local button = block:FindFirstChild("ImageButton", true)
				self.Blocks[index] = { Node = block, Button = clickable(button), Holder = button }
			end
		end
	end
	assert(#missing == 0, "Missing authored UI: " .. table.concat(missing, ", "))
	self.Slide = FrameSlide.new(root)
	Style.SetEnabled(root, false)
	return self
end

-- The block's pet viewport, made only if the block has none.
function ProfileFrameView.Viewport(self: any, block: any): ViewportFrame
	if block.Viewport and block.Viewport.Parent then return block.Viewport end
	local found = block.Node:FindFirstChildWhichIsA("ViewportFrame", true)
	if not found then
		found = Instance.new("ViewportFrame")
		found.Name, found.Size, found.BackgroundTransparency = "PetViewport", UDim2.fromScale(1, 1), 1
		found.Parent = block.Node
	end
	block.Viewport = found
	return found :: ViewportFrame
end

function ProfileFrameView.Show(self: any, visible: boolean)
	self.Wanted = visible
	if not visible then
		self.Slide:Hide()
		table.clear(self.Previews)
	end
end

-- Fills the frame from a public profile; it appears once the profile has arrived. Returns nothing to bind: the only
-- action is the locked-block button, which opens the Shop.
function ProfileFrameView.Render(self: any, profile: any?, actions: any)
	if not self.Wanted or not profile then return end
	local own = profile.UserId == self.OwnUserId
	BotPortrait.Set(self.Icon, profile.UserId, profile.AvatarUserId)
	self.Level.Text = "Lvl. " .. (profile.Level or 1)
	self.Username.Text = profile.DisplayName or profile.Username or ""
	self.AtUsername.Text = "@" .. (profile.Username or "")
	self.Vip.Text = "Vip: " .. (if profile.VIP then "Yes" else "No")
	local matches = profile.Matches or 0
	local values = {
		Wins = commas(profile.Wins or 0),
		WinRate = (if matches > 0 then math.floor((profile.Wins or 0) / matches * 100 + 0.5) else 0) .. "%",
		HighestStreak = commas(profile.HighestStreak or 0),
		LoginStreak = commas(profile.LoginStreak or 0),
		Playtime = playtime(profile.TimePlayed or 0),
	}
	for name, label in self.Stats do label.Text = values[name] end
	-- Everyone's loadout shows, yours and other players': the same blocks, filled from their equipped pets.
	self.Loadout.Visible = true
	table.clear(self.Previews)
	do
		local vip = profile.VIP == true
		local pets = profile.Equipped and profile.Equipped.Pets or {}
		local next = 0
		for index = 1, BLOCKS do
			local block = self.Blocks[index]
			local locked = not vip and LOCKED_BLOCKS[index] == true
			local id = nil
			if not locked then next += 1;id = pets[next] end
			local viewport = self:Viewport(block)
			local item = id and self.Catalog.Items.Pets[id]
			viewport.Visible = item ~= nil
			-- Only rebuild a block when its pet changes, so state pushes never restart the rotation.
			if block.PetId ~= (id or false) then
				block.PetId = id or false
				if item then Style.Preview(block.Node, item, "Pets", viewport)
				else
					for _, child in viewport:GetChildren() do if child:IsA("BasePart") or child:IsA("Model") then child:Destroy() end end
				end
			end
			if item then table.insert(self.Previews, viewport) end
			-- On your own profile locked blocks show a button that opens the Shop (the VIP bundle is at its top).
			if block.Holder then block.Holder.Visible = locked and own end
			if locked and own and block.Button then
				table.insert(actions, { Button = block.Button, Action = "OpenPage", Payload = { Page = "Shop" } })
			end
		end
	end
	self.Slide:Show()
end

function ProfileFrameView.Step(self: any, dt: number)
	self.Slide:Step(dt)
	if not self.Wanted then return end
	self.Age += dt
	for _, preview in self.Previews do Style.RotatePetPreview(preview, self.Age) end
end

function ProfileFrameView.Destroy(self: any)
	self.Wanted = false
	table.clear(self.Previews)
	self.Slide:Reset()
end

return ProfileFrameView

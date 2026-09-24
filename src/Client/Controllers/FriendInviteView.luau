--!strict
-- The friend alert is the authored HUD.Lobby.Upper.InviteFrame: OnlineMessage says "<Name> is online!", Frame.Mugshot
-- shows the friend's portrait, Icon is the reward icon (already authored to the cash icon -- its Image is never
-- touched), InviteButton sends the invite, Close dismisses it and Amount shows the invite reward (the older lowercase
-- "reward" name is still accepted for an InviteFrame authored before this hierarchy). Nothing is created except a
-- UIScale for the pop-in.
local Style = require(script.Parent.UIStyle)
local BotPortrait = require(script.Parent.BotPortrait)
local View = {}
View.__index = View

local function need(parent: Instance, name: string, class: string?): any
	local node = parent:FindFirstChild(name)
	assert(node and (not class or node:IsA(class)), "Missing authored UI: " .. parent:GetFullName() .. "." .. name .. (if class then " (" .. class .. ")" else ""))
	return node
end

function View.new(_playerGui: PlayerGui?)
	local authoring = assert(Style.Authoring, "The authored HUD must be attached before the friend alert")
	local upper = need(authoring.Lobby, "Upper")
	local panel = need(upper, "InviteFrame", "GuiObject")
	-- Frame.Mugshot is the friend's portrait; Frame itself may hold other decoration.
	local portraitHolder = panel:FindFirstChild("Frame")
	local portrait = portraitHolder and (portraitHolder:FindFirstChild("Mugshot") or portraitHolder:FindFirstChildWhichIsA("ImageLabel", true))
	local amount = panel:FindFirstChild("Amount")
	local rewardLabel = if amount and amount:IsA("TextLabel") then amount else nil
	if not rewardLabel then
		local reward = panel:FindFirstChild("reward")
		rewardLabel = if reward then reward:FindFirstChildWhichIsA("TextLabel", true) else nil
	end
	local motion = panel:FindFirstChild("AlertMotionScale") or Instance.new("UIScale")
	motion.Name, motion.Parent = "AlertMotionScale", panel
	local self: any = setmetatable({
		Gui = panel, Panel = panel, Mugshot = portrait, Reward = rewardLabel, Message = need(panel, "OnlineMessage", "TextLabel"),
		Invite = need(panel, "InviteButton", "GuiButton"), Close = need(panel, "Close", "GuiButton"), Motion = motion, Age = 0,
	}, View)
	Style.SetEnabled(panel, false)
	return self
end

function View.Show(self: any, friend: any)
	local cash = if friend.RewardCash == nil then 250 else friend.RewardCash
	self.Message.Text = friend.Name .. " is online!"
	if self.Mugshot and self.Mugshot:IsA("ImageLabel") then BotPortrait.Set(self.Mugshot, friend.Id, friend.Id) end
	if self.Reward then
		self.Reward.Text = if cash > 0 then "+" .. Style.Money(cash) else "Claimed"
	end
	self.Age = 0
	Style.Play("Notification")
	self:SetEnabled(true)
	self:Step(0)
	Style.SetEnabled(self.Gui, true)
end

function View.SetEnabled(self: any, enabled: boolean)
	self.Invite.Active, self.Invite.Selectable, self.Invite.AutoButtonColor = enabled, false, enabled
end

-- A springy pop-in; the frame's own position stays wherever it was authored.
function View.Step(self: any, dt: number)
	self.Age += math.max(0, dt)
	local alpha = math.clamp(self.Age / Style.Pacing.InviteEnterSeconds, 0, 1)
	local x = alpha - 1
	self.Motion.Scale = 0.6 + 0.4 * (1 + 2.70158 * x * x * x + 1.70158 * x * x)
end

function View.Hide(self: any) Style.SetEnabled(self.Gui, false) end
function View.Destroy(self: any) Style.SetEnabled(self.Gui, false) end
function View.IsVisible(self: any): boolean return Style.IsEnabled(self.Gui) end
return View

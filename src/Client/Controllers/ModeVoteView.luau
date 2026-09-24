--!strict
-- The authored HUD.Frame.Voting overlay: Frame.Header.TextLabel is the timer ("Ending in 10s..."), Frame.Container holds
-- the mode buttons 1-4 (in GameConfig.ModeOrder: Classic, Endless, Best of Five, Sudden Death). Each button has ModeName,
-- ModeInfo and a VotingList that receives one clone of ReplicatedStorage.Assets.UI.VoteTemplate per player who voted for
-- it (the template's PlayerVote is that player's mugshot). A plain click votes: no highlights, notices or animation.
-- Bot entries add the shared local 3D portrait viewport inside PlayerVote.
local Style = require(script.Parent.UIStyle)
local BotPortrait = require(script.Parent.BotPortrait)
local View = {}
View.__index = View

local function need(parent: Instance, name: string, class: string?): any
	local node = parent:FindFirstChild(name)
	assert(
		node and (not class or node:IsA(class)),
		"Missing authored UI: " .. parent:GetFullName() .. "." .. name .. (if class then " (" .. class .. ")" else "")
	)
	return node
end

-- storage: ReplicatedStorage (holds Assets.UI.VoteTemplate).
function View.new(_playerGui: PlayerGui?, config: any, cast: (string, string) -> (), storage: any?)
	local authoring = Style.Authoring
	if not authoring or not authoring.Overlays then
		return setmetatable({
			Root = nil,
			Config = config,
			Cast = cast,
			Storage = storage,
			Timer = nil,
			Cards = {},
			Connections = {},
			Open = false,
		}, View)
	end
	local root = need(authoring.Overlays, "Voting", "GuiObject")
	local frame = need(root, "Frame")
	local self: any = setmetatable({
		Root = root,
		Config = config,
		Cast = cast,
		Storage = storage,
		Timer = need(need(frame, "Header"), "TextLabel", "TextLabel"),
		Cards = {},
		Connections = {},
	}, View)
	local container = need(frame, "Container")
	for index, id in config.ModeOrder do
		local button = need(container, tostring(index), "GuiButton")
		local mode = config.Modes[id]
		local name, info = need(button, "ModeName", "TextLabel"), need(button, "ModeInfo", "TextLabel")
		name.Text, info.Text = mode.Name, mode.Description
		self.Cards[id] = { Button = button, List = need(button, "VotingList"), Faces = {} }
		table.insert(
			self.Connections,
			button.Activated:Connect(function()
				if self.Open and self.VoteId and self.Remaining and self.Remaining > 0 then
					self.Cast(self.VoteId, id)
				end
			end)
		)
	end
	Style.SetEnabled(root, false)
	return self
end

local function template(self: any): Instance?
	local assets = self.Storage and self.Storage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	return ui and ui:FindFirstChild("VoteTemplate")
end

local function portrait(entry: Instance): Instance?
	local face = entry:FindFirstChild("PlayerVote", true)
	if face and (face:IsA("ImageLabel") or face:IsA("ImageButton")) then
		return face
	end
	return entry:FindFirstChildWhichIsA("ImageLabel", true)
end

-- One VoteTemplate clone per voter, kept in seat order; clones are reused between snapshots.
function View.SetVoters(self: any, id: string, userIds: { number }, avatars: any?)
	if not self.Root or not self.Cards or not self.Cards[id] then
		return
	end
	local card = self.Cards[id]
	local wanted = {}
	for order, userId in userIds do
		wanted[tostring(userId)] = order
	end
	for key, entry in card.Faces do
		if not wanted[key] then
			entry:Destroy()
			card.Faces[key] = nil
		end
	end
	local source = template(self)
	if not source then
		return
	end
	for order, userId in userIds do
		local key = tostring(userId)
		local entry = card.Faces[key]
		if not entry then
			entry = source:Clone()
			entry.Name = "Voter" .. key
			local face = portrait(entry)
			if face then
				local portraitId = (avatars and avatars[key]) or userId
				BotPortrait.Set(face :: any, userId, portraitId, self.Config)
			end
			entry.Parent = card.List
			card.Faces[key] = entry
		end
		if entry:IsA("GuiObject") then
			entry.LayoutOrder = order
		end
	end
end

function View.Show(self: any, snapshot: any, now: number)
	if not self.Root or not snapshot or snapshot.State ~= "VOTING" then
		if self.Root then
			self:Hide()
		end
		return
	end
	self.Open, self.VoteId, self.Deadline = true, snapshot.VoteId, snapshot.Deadline
	Style.SetEnabled(self.Root, true)
	for id in self.Cards do
		self:SetVoters(id, (snapshot.Voters or {})[id] or {}, snapshot.VoterAvatars)
	end
	self:Step(0, now)
end

function View.Step(self: any, dt: number, now: number)
	if not self.Root or not self.Open then
		return
	end
	self.Remaining = math.max(0, (self.Deadline or now) - now)
	if self.Timer then
		self.Timer.Text = if self.Remaining > 0
			then "Ending in " .. math.ceil(self.Remaining) .. "s..."
			else "Choosing the mode..."
	end
	for _, card in self.Cards do
		card.Button.Active = self.Remaining > 0
		card.Button.Selectable = false
	end
end

function View.Hide(self: any)
	self.Open, self.VoteId, self.Deadline, self.Remaining = false, nil, nil, 0
	if not self.Root then
		return
	end
	for id in self.Cards do
		self:SetVoters(id, {})
	end
	Style.SetEnabled(self.Root, false)
end

function View.Destroy(self: any)
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
	if self.Root then
		self:Hide()
	end
end
return View

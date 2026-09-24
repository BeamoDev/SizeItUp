--!strict
-- Global top-10 boards in Workspace.Game.Interactables.Leaderboards, ported from Kingdom Wars.
-- Board layout: Leaderboards.<Name>.Body.Gui.List (+ UIListLayout); rows clone
-- ReplicatedStorage.Assets.UI.LeaderboardTemp (Mugshot, Rank, PlrName, Score).
local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

local PLAYER_SYNC_INTERVAL_SECONDS = 60
local BOARD_REFRESH_INTERVAL_SECONDS = 120
local MAX_ENTRIES = 10

-- "Streak" ranks each player's best win streak; the live streak resets on every loss.
LeaderboardService.Boards = {
	{ Name = "Wins", Stat = "Wins", Store = "ScaleItUp_LB_Wins_v1", Icon = "🏆" },
	{ Name = "Streak", Stat = "HighestStreak", Store = "ScaleItUp_LB_Streak_v1", Icon = "🔥" },
}

local function formatNumber(value: any): string
	local digits = tostring(math.max(0, math.floor(tonumber(value) or 0)))
	local prefix, suffix = digits, ""
	while #prefix > 3 do
		suffix = "," .. string.sub(prefix, -3) .. suffix
		prefix = string.sub(prefix, 1, #prefix - 3)
	end
	return prefix .. suffix
end
local function isText(instance: any): boolean
	return instance ~= nil and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end
local function isImage(instance: any): boolean
	return instance ~= nil and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
end
local function findByNames(root: any, names: {string}): any
	for _, name in names do
		if root.Name == name then return root end
		local match = root:FindFirstChild(name, true)
		if match then return match end
	end
	return nil
end

function LeaderboardService.new(deps: any)
	local self: any = setmetatable({ D = deps }, LeaderboardService)
	self.Stores, self.Memory, self.Synced, self.InFlight, self.NextWriteAt = {}, {}, {}, {}, {}
	self.NameCache, self.ThumbnailCache, self.Pending = {}, {}, {}
	for _, board in LeaderboardService.Boards do
		self.Memory[board.Stat], self.Synced[board.Stat], self.InFlight[board.Stat], self.NextWriteAt[board.Stat] = {}, {}, {}, {}
		-- Studio keeps a session-only board so playtests never touch live ordered stores.
		if not deps.IsStudio then
			local ok, store = pcall(function() return deps.DataStore:GetOrderedDataStore(board.Store) end)
			if ok then self.Stores[board.Stat] = store else deps.Warn("[Leaderboards] store unavailable for " .. board.Name .. ": " .. tostring(store)) end
		end
	end
	return self
end

function LeaderboardService.HasBudget(self: any, requestType: any): boolean
	local ok, budget = pcall(function() return self.D.DataStore:GetRequestBudgetForRequestType(requestType) end)
	return ok and (tonumber(budget) or 0) >= 1
end

-- Values only ever grow (wins, best streak), so the stored score is a max and a late
-- write from an older server can never lower it.
function LeaderboardService.WriteValue(self: any, stat: string, userId: number, value: any): boolean
	local id, amount = math.max(0, math.floor(tonumber(userId) or 0)), math.max(0, math.floor(tonumber(value) or 0))
	if id <= 0 then return false end
	self.Memory[stat][id] = math.max(amount, self.Memory[stat][id] or 0)
	amount = self.Memory[stat][id]
	local store = self.Stores[stat]
	if not store then self.Synced[stat][id] = amount;return true end
	if (self.Synced[stat][id] or -1) >= amount then return true end
	if self.InFlight[stat][id] or self.D.Clock() < (self.NextWriteAt[stat][id] or 0) then return false end
	if not self:HasBudget(self.D.Enum.DataStoreRequestType.UpdateAsync) then return false end
	self.InFlight[stat][id] = true
	self.NextWriteAt[stat][id] = self.D.Clock() + PLAYER_SYNC_INTERVAL_SECONDS
	local ok, result = pcall(function()
		return store:UpdateAsync(tostring(id), function(previous: any) return math.max(math.floor(tonumber(previous) or 0), amount) end)
	end)
	self.InFlight[stat][id] = nil
	if not ok then self.D.Warn(string.format("[Leaderboards] failed to save %s for %d: %s", stat, id, tostring(result))) return false end
	self.Synced[stat][id] = math.max(math.floor(tonumber(result) or 0), amount)
	return true
end

function LeaderboardService.SyncPlayer(self: any, player: any)
	for _, board in LeaderboardService.Boards do
		local value = self.D.GetStat(player, board.Stat)
		if value ~= nil then self:WriteValue(board.Stat, player.UserId, value) end
	end
end

-- Record the latest values immediately (the profile may be released right after), then write off-thread.
function LeaderboardService.QueuePlayerSync(self: any, player: any)
	if not player then return end
	for _, board in LeaderboardService.Boards do
		local value = self.D.GetStat(player, board.Stat)
		if value ~= nil then self.Memory[board.Stat][player.UserId] = math.max(value, self.Memory[board.Stat][player.UserId] or 0) end
	end
	if self.Pending[player] then return end
	self.Pending[player] = true
	self.D.Spawn(function()
		local ok, failure = pcall(function()
			for _, board in LeaderboardService.Boards do
				local remembered = self.Memory[board.Stat][player.UserId]
				if remembered ~= nil then self:WriteValue(board.Stat, player.UserId, remembered) end
			end
		end)
		self.Pending[player] = nil
		if not ok then self.D.Warn("[Leaderboards] player sync failed: " .. tostring(failure)) end
	end)
end

function LeaderboardService.SyncOnlinePlayers(self: any)
	for _, player in self.D.Players:GetPlayers() do
		self:SyncPlayer(player)
		self.D.Wait(0.05)
	end
	-- Retry committed scores for departed players; equal scores and cooldowns skip the write.
	for stat, values in self.Memory do for userId, value in values do self:WriteValue(stat, userId, value) end end
end

function LeaderboardService.TopFromMemory(self: any, stat: string, limit: number): {any}
	local entries = {}
	for userId, value in self.Memory[stat] do table.insert(entries, { UserId = userId, Value = value }) end
	table.sort(entries, function(a: any, b: any) if a.Value == b.Value then return a.UserId < b.UserId end return a.Value > b.Value end)
	while #entries > limit do table.remove(entries) end
	return entries
end

function LeaderboardService.TopEntries(self: any, stat: string, limit: number): {any}
	local store = self.Stores[stat]
	if not store or not self:HasBudget(self.D.Enum.DataStoreRequestType.GetSortedAsync) then return self:TopFromMemory(stat, limit) end
	local ok, pages = pcall(function() return store:GetSortedAsync(false, limit) end)
	if not ok then
		self.D.Warn("[Leaderboards] failed to read " .. stat .. ": " .. tostring(pages))
		return self:TopFromMemory(stat, limit)
	end
	local entries = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = math.max(0, math.floor(tonumber(entry.key) or 0))
		if userId > 0 then table.insert(entries, { UserId = userId, Value = math.max(0, math.floor(tonumber(entry.value) or 0)) }) end
	end
	return entries
end

function LeaderboardService.PlayerName(self: any, userId: number): string
	local cached = self.NameCache[userId]
	if cached then return cached end
	local online = self.D.Players:GetPlayerByUserId(userId)
	if online then self.NameCache[userId] = online.Name;return online.Name end
	local ok, name = pcall(function() return self.D.Players:GetNameFromUserIdAsync(userId) end)
	local resolved = if ok and type(name) == "string" and name ~= "" then name else string.format("User %d", userId)
	self.NameCache[userId] = resolved
	return resolved
end

function LeaderboardService.Thumbnail(self: any, userId: number): string?
	local cached = self.ThumbnailCache[userId]
	if cached then return cached end
	local ok, image = pcall(function()
		return self.D.Players:GetUserThumbnailAsync(userId, self.D.Enum.ThumbnailType.HeadShot, self.D.Enum.ThumbnailSize.Size100x100)
	end)
	if ok and type(image) == "string" and image ~= "" then self.ThumbnailCache[userId] = image;return image end
	return nil
end

function LeaderboardService.ResolveList(self: any, boardName: string): any
	-- Boards live in Workspace.Game.Interactables.Leaderboards.
	local gameRoot = self.D.Workspace:FindFirstChild("Game")
	local interactables = gameRoot and gameRoot:FindFirstChild("Interactables")
	local boards = (interactables and interactables:FindFirstChild("Leaderboards"))
		or (gameRoot and gameRoot:FindFirstChild("Leaderboards"))
		or self.D.Workspace:FindFirstChild("Leaderboards")
	local board = boards and boards:FindFirstChild(boardName)
	local body = board and board:FindFirstChild("Body")
	local gui = body and (body:FindFirstChild("Gui") or body:FindFirstChildWhichIsA("SurfaceGui", true))
	local list = gui and findByNames(gui, { "List", "Entries", "Content", "ScrollingFrame" })
	if list and list:IsA("GuiObject") then return list end
	return nil
end

function LeaderboardService.Template(self: any): any
	local assets = self.D.Storage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("LeaderboardTemp")
	if template and template:IsA("GuiObject") then return template end
	return nil
end

function LeaderboardService.ApplyRow(self: any, row: any, rank: number, name: string, value: number, userId: number?, icon: string?)
	row:SetAttribute("LeaderboardEntry", true)
	row.Name, row.Visible, row.LayoutOrder = string.format("Entry_%02d", rank), true, rank
	local rankLabel = findByNames(row, { "Rank", "Place", "Number", "Index" })
	local nameLabel = findByNames(row, { "PlrName", "Player", "Name", "Username", "User", "Title" })
	local valueLabel = findByNames(row, { "Score", "Value", "Stat", "Count", "Amount" })
	local mugshot = findByNames(row, { "Mugshot", "Avatar", "Portrait", "Thumbnail", "Icon" })
	if isText(rankLabel) then rankLabel.Text = string.format("#%d", rank) end
	if isText(nameLabel) then nameLabel.Text = name end
	if isText(valueLabel) then valueLabel.Text = (if icon then icon .. " " else "") .. formatNumber(value) end
	if isImage(mugshot) then
		local image = if userId then self:Thumbnail(userId) else nil
		if image then mugshot.Image, mugshot.Visible = image, true
		elseif not userId then mugshot.Visible = false end
	end
end

function LeaderboardService.RenderBoard(self: any, board: any)
	local list, template = self:ResolveList(board.Name), self:Template()
	if not (list and template) then return end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("LeaderboardEntry") == true then child:Destroy() end
	end
	local entries = self:TopEntries(board.Stat, MAX_ENTRIES)
	if #entries == 0 then
		local placeholder = template:Clone()
		self:ApplyRow(placeholder, 1, "No data yet", 0, nil)
		placeholder.Parent = list
	else
		for rank, entry in entries do
			local row = template:Clone()
			self:ApplyRow(row, rank, self:PlayerName(entry.UserId), entry.Value, entry.UserId, board.Icon)
			row.Parent = list
		end
	end
	local layout = list:FindFirstChildWhichIsA("UIListLayout")
	if list:IsA("ScrollingFrame") and layout then list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y) end
end

function LeaderboardService.RefreshBoards(self: any)
	for _, board in LeaderboardService.Boards do
		local ok, failure = pcall(function() self:RenderBoard(board) end)
		if not ok then self.D.Warn("[Leaderboards] render failed for " .. board.Name .. ": " .. tostring(failure)) end
	end
end

function LeaderboardService.Start(self: any)
	if self.Started then return end
	self.Started = true
	local nextRefreshAt = 0
	local function step()
		if self.Stopped then return end
		self:SyncOnlinePlayers()
		if self.D.Clock() >= nextRefreshAt then
			self:RefreshBoards()
			nextRefreshAt = self.D.Clock() + BOARD_REFRESH_INTERVAL_SECONDS
		end
		if not self.Stopped then self.D.Delay(PLAYER_SYNC_INTERVAL_SECONDS, step) end
	end
	self.D.Spawn(step)
end

function LeaderboardService.Stop(self: any) self.Stopped = true end

return LeaderboardService

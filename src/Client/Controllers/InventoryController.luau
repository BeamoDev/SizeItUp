--!strict
local InventoryController = {}
InventoryController.__index = InventoryController
local FAILURE_WORDS = {
	"not enough",
	"wait a moment",
	"invalid",
	"could not",
	"cannot",
	"can't",
	"already",
	"not ready",
	"unavailable",
	"finish your match",
	"between matches",
	"try again",
	"refresh",
	"unknown",
	"join the group",
	"no cash",
	"not available",
	"coming soon",
	"full",
}
local lobbyStates =
	{ IDLE = true, WAITING_FOR_PLAYER = true, VOTING = true, COUNTDOWN = true, PRIZE_ROLL = true, GO = true }
function InventoryController.new(d: any)
	local self: any = setmetatable({
		D = d,
		Connections = {},
		Actions = {},
		ChairPrompts = {},
		Revision = 0,
		Busy = false,
		InGame = false,
		Tab = "Pets",
	}, InventoryController)
	self.View = d.View.new(d.Player:WaitForChild("PlayerGui"), d.Catalog, d.Shop, d.Rewards, d.Input, d.GuiService)
	self.Hatch = d.HatchController.new(d.Player:WaitForChild("PlayerGui"), d.StarterGui, d.Catalog, d.Shop, function(id)
		self:Request("Equip", { Category = "Pets", Id = id })
	end)
	self.Details = d.DetailsController.new(d, function(action, payload)
		if action == "Profile" then
			self.Page, self.Profile = "Profile", nil
			self.View:Show("Profile")
			self:Render()
		end
		if action == "Steal" then
			payload.Token = self.State and self.State.Token
		end
		self:Request(action, payload)
	end)
	local function connect(signal, callback)
		table.insert(self.Connections, signal:Connect(callback))
	end
	if d.Prompts then
		connect(d.Prompts.PromptShown, function(prompt)
			if prompt.Parent and prompt.Parent:GetAttribute("ChairShopId") then
				self.ChairPrompts[prompt] = true
				self:UpdateChairPrompt(prompt)
			end
		end)
		connect(d.Prompts.PromptHidden, function(prompt)
			self.ChairPrompts[prompt] = nil
		end)
	end
	for page, button in self.View.Buttons do
		connect(button.Activated, function()
			self:Open(page)
		end)
	end
	if self.View.Lobby and self.View.Lobby.PlayBot then
		connect(self.View.Lobby.PlayBot.Activated, function()
			d.PlayBot:FireServer()
		end)
	end
	if self.View.Blocks then
		local blocks = self.View.Blocks
		connect(blocks.Close.Activated, function()
			self:Close()
		end)
		connect(blocks.Previous.Activated, function()
			self:BrowseBlock(-1)
		end)
		connect(blocks.Next.Activated, function()
			self:BrowseBlock(1)
		end)
		connect(blocks.Surface.InputBegan, function(input)
			if self.Page == "Blocks" and not self.Pending then
				blocks:BeginSwipe(input)
			end
		end)
		connect(d.Input.InputEnded, function(input)
			local direction = blocks:EndSwipe(input)
			if direction ~= 0 then
				self:BrowseBlock(direction)
			end
		end)
	end
	if self.View.ProfileFrame then
		connect(self.View.ProfileFrame.Close.Activated, function()
			self:Close()
		end)
	end
	if self.View.StoreFrame then
		local store = self.View.StoreFrame
		connect(store.Close.Activated, function()
			self:Close()
		end)
		-- Codes: Verify sends whatever was typed; the server validates it and each code works once per player.
		if store.Verify then
			connect(store.Verify.Activated, function()
				if self.Page ~= "Shop" or self.Busy or self.Hatch.Reward then
					return
				end
				self:Request("Code", { Code = string.sub(store:CodeText(), 1, 32) })
				store:ClearCode()
			end)
		end
	end
	if self.View.EggShop and self.View.EggShop.Close then
		connect(self.View.EggShop.Close.Activated, function()
			self:Close()
		end)
	end
	if self.View.InventoryFrame then
		local frame = self.View.InventoryFrame
		connect(frame.Close.Activated, function()
			self:Close()
		end)
		for tab, entry in frame.Tabs do
			connect(entry.Button.Activated, function()
				if self.Page == "Inventory" then
					self.MenuEpoch = (self.MenuEpoch or 0) + 1
					self.Tab = tab
					self:Render()
				end
			end)
		end
	end
	if self.View.RewardsFrame then
		local rewards = self.View.RewardsFrame
		connect(rewards.Close.Activated, function()
			self:Close()
		end)
		for tab, entry in rewards.Tabs do
			connect(entry.Button.Activated, function()
				rewards:SetTab(tab)
			end)
		end
	end
	connect(d.Remote.OnClientEvent, function(packet)
		self:Receive(packet)
	end)
	-- Whatever the outcome, the Roblox purchase prompt closing always clears the overlay too.
	if d.Marketplace and self.D.PurchaseOverlay then
		connect(d.Marketplace.PromptProductPurchaseFinished, function()
			self.D.PurchaseOverlay:Hide()
		end)
	end
	connect(d.MatchState.OnClientEvent, function(snapshot)
		if (snapshot.Revision or 0) <= self.Revision then
			return
		end
		self.Revision, self.Busy = snapshot.Revision, snapshot.State ~= "IDLE"
		self.InGame = not lobbyStates[snapshot.State]
		if self.Busy then
			self.Hatch:Stop()
		end
		if self.InGame or snapshot.State == "VOTING" then
			self:Close()
		end
		-- Alone at any empty table (1v1, 2v2/3v3, or 4v4), with nobody else seated yet: offer to fill every
		-- other seat with bots instead of waiting.
		local showPlayBot = snapshot.State == "WAITING_FOR_PLAYER" and snapshot.SeatedCount == 1
		if showPlayBot ~= self.ShowingPlayBot then
			self.ShowingPlayBot = showPlayBot
			if self.View.SetPlayBotVisible then
				self.View:SetPlayBotVisible(showPlayBot)
			end
		end
	end)
	connect(d.Player.CharacterRemoving, function()
		self.Hatch:Stop()
		self:Close()
	end)
	connect(d.Input.InputBegan, function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:Close()
		elseif self.Page == "Blocks" then
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft then
				self:BrowseBlock(-1)
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.DPadRight then
				self:BrowseBlock(1)
			end
		end
	end)
	connect(d.RunService.RenderStepped, function(dt)
		self:Step(dt)
	end)
	if d.Player.GetAttributeChangedSignal then
		for _, name in { "Cash", "Keys" } do
			connect(d.Player:GetAttributeChangedSignal(name), function()
				self.View:SetCurrency(d.Player:GetAttribute("Cash") or 0, d.Player:GetAttribute("Keys") or 0)
			end)
		end
	end
	self:Request("Refresh", {})
	return self
end
function InventoryController.Request(self: any, action: string, payload: any)
	if
		self.Destroyed
		or self.Joining
		or self.Pending
		or (self.Busy and action ~= "Refresh" and action ~= "Profile")
	then
		return
	end
	self.Pending = self.D.World:GetServerTimeNow()
	self.View.Message.Text = ""
	self.PendingGroupClaim = if action == "ClaimReward" and payload.Category == "Group"
		then { Id = payload.Id, Retry = payload.GroupRetry == true, Epoch = self.MenuEpoch }
		else nil
	if self.Page == "Blocks" then
		self.View.Blocks.Message.Text = ""
	end
	self.D.Remote:FireServer(action, payload)
end
function InventoryController.Open(self: any, page: string)
	-- The menu stays openable while seated and waiting (WAITING_FOR_PLAYER/VOTING/COUNTDOWN/PRIZE_ROLL/GO are all
	-- "lobby" states, not InGame); it force-closes the moment InGame actually starts (see the snapshot handler).
	if self.InGame or self.Hatch.Reward then
		return
	end
	-- A region where paid random items are restricted never gets the Lucky Blocks frame: fail closed (unknown
	-- eligibility blocks it too), just a short alert instead. The server's own OpenLuckyBlocks gates the world
	-- trigger and HUD button the same way; this covers this client's own direct Blocks open.
	if page == "Blocks" and (not self.State or self.State.AllowedRandom ~= true) then
		if self.D.Alerts then
			self.D.Alerts:Show("Not allowed in your region.", "Info")
		end
		return
	end
	local category = if page == "Chairs"
			or page == "Pets"
			or page == "Titles"
		then page
		elseif page == "Inventory" then "Chairs"
		else nil
	if category then
		page = "Inventory"
	end
	if self.View.CanOpen and not self.View:CanOpen(page) then
		if self.D.Alerts then
			self.D.Alerts:Show("That menu isn't ready yet.", "Info")
		end
		return
	end
	if self.Page == page and (not category or self.Tab == category) then
		self:Close()
		return
	end
	self.MenuEpoch = (self.MenuEpoch or 0) + 1
	self.Page = page
	if self.View.Acknowledge then
		self.View:Acknowledge(category or (if page == "Inventory" then "Chairs" else page))
	end
	self.Tab = category
		or (
			if page == "PetShop"
				then self.D.Catalog.PetShopOrder[1]
				elseif page == "Blocks" then self.D.Shop.BlockOrder[1]
				elseif page == "Eggs" then "Egg"
				elseif page == "Rewards" then "Play Time"
				else "Cash"
		)
	self:Sfx("Whoosh")
	self.Profile = nil
	self.View:Show(page)
	self:Render()
	self:Request(if page == "Profile" then "Profile" else "Refresh", {})
end
-- The "!" badges on the lobby buttons: something to claim (Free), an unclaimed bundle (Store), a level-up (Profile) or items
-- gained since the game was joined (Chairs / Pets / Titles). Using a button acknowledges its badge.
function InventoryController.UpdateBadges(self: any)
	local view, state = self.View, self.State
	if not (view.SetBadge and state and state.Owned) then
		return
	end
	local function counts(category: string): any
		local result = {}
		for id, count in state.Owned[category] or {} do
			result[id] = count
		end
		return result
	end
	if not self.Baseline then
		self.Baseline = {
			Chairs = counts("Chairs"),
			Pets = counts("Pets"),
			Titles = counts("Titles"),
			Level = state.PlayerLevel and state.PlayerLevel.Level or 1,
		}
	end
	for _, category in { "Chairs", "Pets", "Titles" } do
		local gained, base = 0, self.Baseline[category]
		for id, count in counts(category) do
			gained += math.max(0, count - (base[id] or 0))
		end
		view:SetBadge(category, gained)
	end
	view:SetBadge("Profile", math.max(0, (state.PlayerLevel and state.PlayerLevel.Level or 1) - self.Baseline.Level))
	view:SetBadge("Shop", if state.VIP ~= true and state.FreeShop == true then 1 else 0)
	local rewards, catalog, claimable = state.Rewards, self.D.Rewards, 0
	if rewards and catalog then
		local elapsed = math.max(0, self.D.World:GetServerTimeNow() - (self.StateReceivedAt or 0))
		if rewards.DailyReadyAt and rewards.Now and rewards.Now + elapsed >= rewards.DailyReadyAt then
			claimable += 1
		end
		for _, item in catalog.Timed or {} do
			if not (rewards.TimedClaims or {})[item.Id] and (rewards.TimedSeconds or 0) + elapsed >= item.Seconds then
				claimable += 1
			end
		end
		if rewards.GroupClaimed ~= true and (rewards.GroupId or 0) > 0 then
			claimable += 1
		end
	end
	view:SetBadge("Rewards", claimable)
end
function InventoryController.Close(self: any)
	self.MenuEpoch = (self.MenuEpoch or 0) + 1
	self.PendingGroupClaim = nil
	self.Page = nil
	self.View:Show(nil)
	self:Render()
end
function InventoryController.BrowseBlock(self: any, direction: number)
	if self.Page ~= "Blocks" or self.Busy or self.Pending or self.Hatch.Reward then
		return
	end
	local order = self.D.Shop.BlockOrder
	local index = table.find(order, self.Tab) or 1
	self.Tab = order[(index - 1 + direction) % #order + 1]
	self:Render()
end
function InventoryController.UpdateChairPrompt(self: any, prompt: ProximityPrompt)
	local stand = prompt.Parent
	local id = stand and stand:GetAttribute("ChairShopId")
	local item = id and self.D.Catalog.Items.Chairs[id]
	if not item or not self.State then
		return
	end
	local owned = self.State.Owned.Chairs[id] ~= nil
	-- Each player sees their own state: the price until bought, then Equip / Unequip.
	-- The prompt never shows a price: just Buy, Equip or Unequip.
	prompt.ActionText = if self.State.Equipped.Chairs == id then "Unequip" elseif owned then "Equip" else "Buy"
	local sign = stand:FindFirstChild("ChairSign")
	local price = sign and sign:FindFirstChild("Price")
	if price then
		price.Text = if owned then "Owned" else (require(script.Parent.UIStyle)).Money(item.Price)
	end
end
function InventoryController.Render(self: any)
	for _, connection in self.Actions do
		connection:Disconnect()
	end
	table.clear(self.Actions)
	if not self.State then
		return
	end
	for prompt in self.ChairPrompts do
		if prompt.Parent then
			self:UpdateChairPrompt(prompt)
		end
	end
	self.View:SetCurrency(self.State.Cash, self.State.Keys)
	if self.View.SetPotions and self.State.Potions then
		self.View:SetPotions(
			self.State.Potions,
			math.max(0, self.D.World:GetServerTimeNow() - (self.StateReceivedAt or self.D.World:GetServerTimeNow()))
		)
	end
	-- The lobby potion bar stays visible while in the lobby, but hides during matches and whenever the Lucky Blocks
	-- showroom or an in-game Store menu is the active page. This keeps it off the gameplay HUD and away from the
	-- block showcase screen.
	local potionsVisible = not self.InGame
		and self.Page ~= "Shop"
		and self.Page ~= "Blocks"
		and self.Page ~= "PetShop"
		and not self.Hatch.Reward
	if self.View.SetPotionsVisible then
		self.View:SetPotionsVisible(potionsVisible)
	end
	if not self.Page then
		return
	end
	for _, entry in self.View:Render(self.State, self.Page, self.Tab, self.Profile) do
		table.insert(
			self.Actions,
			entry.Button.Activated:Connect(function()
				if entry.Button.Active == false or not self.Page or self.Busy or self.Hatch.Reward then
					return
				end
				if entry.Action == "Tab" then
					self.MenuEpoch = (self.MenuEpoch or 0) + 1
					self.Tab = entry.Payload.Name
					self:Render()
				elseif entry.Action == "SelectPet" then
					self.View.SelectedShopPet = entry.Payload.Id
					self:Render()
				elseif entry.Action == "OpenPage" then
					self:Open(entry.Payload.Page)
				elseif entry.Action == "Scroll" then
					if self.View.StoreFrame then
						self.View.StoreFrame:ScrollTo(entry.Payload.Section)
					end
				elseif entry.Action == "Alert" then
					self:Alert(entry.Payload.Message, "Info")
				elseif entry.Action == "JoinGroup" then
					self:JoinGroup(entry.Payload.GroupId)
				else
					if entry.Action == "Product" and self.D.PurchaseOverlay then
						self.D.PurchaseOverlay:Show()
					end
					self:Request(entry.Action, entry.Payload)
				end
			end)
		)
	end
	if self.Page == "Rewards" and self.View.UpdateRewardClock then
		self.View:UpdateRewardClock(
			math.max(0, self.D.World:GetServerTimeNow() - (self.StateReceivedAt or self.D.World:GetServerTimeNow()))
		)
	end
	if self.Page == "Shop" then
		self.View.PotionElapsed =
			math.max(0, self.D.World:GetServerTimeNow() - (self.StateReceivedAt or self.D.World:GetServerTimeNow()))
	end
end
function InventoryController.JoinGroup(self: any, id: number, claim: any?)
	if
		self.Destroyed
		or self.Joining
		or self.Busy
		or self.Pending
		or type(id) ~= "number"
		or id <= 0
		or id % 1 ~= 0
	then
		return
	end
	self.Joining = true
	local epoch = self.MenuEpoch
	local ok, status = pcall(function()
		return self.D.GroupService:PromptJoinAsync(id)
	end)
	self.Joining = false
	if self.Destroyed or self.Busy or self.Hatch.Reward or self.Page ~= "Rewards" or self.MenuEpoch ~= epoch then
		return
	end
	if not ok then
		self.View.Message.Text = "Join the group on Roblox!"
		return
	end
	local name = status and status.Name
	if name == "Joined" or name == "AlreadyMember" then
		self:Request(
			"ClaimReward",
			{ Category = "Group", Id = if claim then claim.Id else self.D.Rewards.Group.Id, GroupRetry = true }
		)
	elseif name == "JoinRequestPending" then
		self.View.Message.Text = "Request sent. Claim later!"
	elseif claim then
		self.View.Message.Text = "Join the group first!"
	else
		self:Request("Refresh", {})
	end
end
function InventoryController.Alert(self: any, message: string, kind: string)
	local alerts = self.D.Alerts
	if alerts then
		alerts:Show(message, kind)
	end
end
function InventoryController.Sfx(self: any, name: string)
	local sfx = self.D.Sfx
	if sfx then
		sfx:Play(name)
	end
end
function InventoryController.OpenShopForFunds(self: any, message: string)
	if not message then
		return false
	end
	local lower = string.lower(message)
	local section
	if string.find(lower, "gem", 1, true) or string.find(lower, "key", 1, true) then
		section = "Gems"
	elseif string.find(lower, "cash", 1, true) then
		section = "CashPacks1"
	else
		section = nil
	end
	if not section then
		return false
	end
	self.Page, self.Tab = "Shop", section
	self.View:Show("Shop")
	self:Render()
	if self.View.StoreFrame then
		self.View.StoreFrame:ScrollTo(section)
	end
	self:Sfx("Error")
	return true
end
function InventoryController.Receive(self: any, packet: any)
	if packet.PetProgress then
		self.Hatch.PetProgress = packet.PetProgress
		if self.State then
			self.State.PetProgress = packet.PetProgress
		end
		if self.View.UpdatePetProgress then
			self.View:UpdatePetProgress(packet.PetProgress)
		end
		return
	end
	local groupClaim = self.PendingGroupClaim
	if not packet.Passive then
		self.Pending = nil
		self.PendingGroupClaim = nil
	end
	if packet.State then
		self.State = packet.State
		self.StateReceivedAt = self.D.World:GetServerTimeNow()
		if self.View.SetPotions and self.State.Potions then
			self.View:SetPotions(self.State.Potions, 0)
		end
		self:UpdateBadges()
	end
	self.View.Message.Text = packet.Message or ""
	-- Every message becomes an alert. Purchases ring, failed actions buzz, passive news (a new title, a steal) chimes.
	if packet.Purchased then
		self:Sfx("Purchase")
		if self.D.PurchaseOverlay then
			self.D.PurchaseOverlay:Hide()
		end
	end
	if packet.RewardClaimed then
		self:Sfx("Reward")
	end
	if packet.Message and packet.Message ~= "" then
		local kind = if packet.Purchased or packet.RewardClaimed
			then "Good"
			elseif packet.CashStolen then "Bad"
			elseif packet.Passive then "Notice"
			else "Info"
		if packet.Passive or packet.CashStolen then
			self:Sfx("Notification")
		else
			local lower = string.lower(packet.Message)
			local isInsufficientFunds = string.find(lower, "not enough", 1, true)
				and (
					string.find(lower, "cash", 1, true)
					or string.find(lower, "gem", 1, true)
					or string.find(lower, "key", 1, true)
				)
			if isInsufficientFunds then
				self:OpenShopForFunds(packet.Message)
				kind = "Bad"
			else
				for _, word in FAILURE_WORDS do
					if string.find(lower, word, 1, true) then
						self:Sfx("Error")
						kind = "Bad"
						break
					end
				end
			end
		end
		self:Alert(packet.Message, kind)
	elseif packet.Purchased then
		-- A purchase with nothing more to say (a lucky block opening) still confirms itself.
		self:Alert("Purchased!", "Good")
	end
	if packet.Profile then
		self.Profile = packet.Profile
	end
	if
		packet.OpenPetShop
		and self.D.Catalog.PetShops[packet.OpenPetShop]
		and not self.Busy
		and not self.Hatch.Reward
	then
		self.Page, self.Tab = "PetShop", packet.OpenPetShop
		self.View:Show("PetShop")
	end
	-- A purchase (chair in the world, pet from a shop) opens the inventory on that tab.
	if
		(packet.OpenInventory == "Chairs" or packet.OpenInventory == "Pets")
		and self.View.InventoryFrame
		and not self.Busy
		and not self.Hatch.Reward
	then
		self.Page, self.Tab = "Inventory", packet.OpenInventory
		self.View:Show("Inventory")
	end
	if
		packet.OpenContainer
		and self.D.Shop.Containers[packet.OpenContainer]
		and not self.Busy
		and not self.Hatch.Reward
	then
		self.Page, self.Tab =
			if table.find(self.D.Shop.BlockOrder, packet.OpenContainer)
				then "Blocks"
				elseif self.D.Catalog.PetShops[packet.OpenContainer] then "PetShop"
				else "Eggs",
			packet.OpenContainer
		self.View:Show(self.Page)
	end
	if packet.Hatch and not self.Busy then
		self:Close()
		self.Hatch:Start(packet.Hatch, self.State and self.State.PetProgress)
	end
	self:Render()
	if self.Page == "Blocks" and packet.Message and packet.Message ~= "" then
		self.View.Blocks.Message.Text = packet.Message
	end
	if
		packet.JoinGroupId
		and not packet.Passive
		and groupClaim
		and groupClaim.Epoch == self.MenuEpoch
		and self.Page == "Rewards"
		and (self.Tab == "Group" or self.View.RewardsFrame)
		and not self.Busy
		and not self.Hatch.Reward
	then
		if groupClaim.Retry then
			self.View.Message.Text = "Membership updating. Try again."
		else
			self:JoinGroup(packet.JoinGroupId, groupClaim)
		end
	end
end
function InventoryController.Step(self: any, dt: number)
	local now = self.D.World:GetServerTimeNow()
	if self.Page == "Rewards" and not self.Pending and now - (self.StateReceivedAt or 0) >= 15 then
		self:Request("Refresh", {})
	end
	local gui = self.View.Gui
	local transition = gui
		and gui.Parent
		and (gui.Parent:FindFirstChild("BlackWipe") or gui.Parent:FindFirstChild("ScaleSceneTransition"))
	local transitioning = transition
		and (if transition.Name == "BlackWipe" then transition.Visible else transition.Enabled)
	local exiting = transitioning and transition:GetAttribute("Phase") == "OUT"
	local blocksOpen = self.Page == "Blocks"

	-- Nudges: after a minute in the lobby a new player is shown the group rewards; after five minutes, a reminder to favourite.
	self.SessionAge = (self.SessionAge or 0) + dt
	local idle = not self.InGame and not self.Busy and self.Page == nil and not self.Hatch.Reward and self.State ~= nil
	if
		idle
		and not self.GroupPrompted
		and self.SessionAge >= 60
		and self.State.Rewards
		and self.State.Rewards.GroupClaimed ~= true
		and self.View.RewardsFrame
	then
		self.GroupPrompted = true
		self:Open("Rewards")
		self.View.RewardsFrame:SetTab("Group")
	end
	if idle and not self.FavouritePrompted and self.SessionAge >= 300 then
		self.FavouritePrompted = true
		self:Alert("Like the game!", "Notice")
	end
	-- Teleporting (to or from the AFK world): menus close and the whole lobby HUD slides off screen while the loading
	-- screen shows; if the teleport fails the server clears Traveling and everything slides back.
	local readTravel, travelValue = pcall(function()
		return self.D.Player:GetAttribute("Traveling")
	end)
	local traveling = readTravel and travelValue == true
	if traveling and self.Page ~= nil then
		self:Close()
	end
	-- The dock steps aside during a match; the currency display now hides too, restoring once back in the lobby.
	self.View:SetLobbyVisible(
		not self.InGame and not self.Hatch.Reward and not exiting and not blocksOpen and not traveling,
		not self.InGame and not exiting and not traveling
	)
	if self.State and self.State.Potions and self.View.SetPotions then
		self.View:SetPotions(self.State.Potions, math.max(0, now - (self.StateReceivedAt or now)))
	end
	self.BadgeClock = (self.BadgeClock or 0) + dt
	if self.BadgeClock >= 0.5 then
		self.BadgeClock = 0
		self:UpdateBadges()
	end
	self.View:Step(dt)
	self.Hatch:Step(dt)
	if self.D.PurchaseOverlay then
		self.D.PurchaseOverlay:Step(dt)
	end
	self.Details:Step(dt, self.Busy or self.Page ~= nil or self.Hatch.Reward ~= nil or transitioning == true)
	if self.Pending and now - self.Pending > 8 then
		self.Pending = nil
		self.PendingGroupClaim = nil
		self.View.Message.Text = "Couldn't confirm. Try again."
		if self.Page == "Blocks" then
			self.View.Blocks.Message.Text = self.View.Message.Text
		end
	end
end
function InventoryController.Destroy(self: any)
	self.Destroyed = true
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	for _, connection in self.Actions do
		connection:Disconnect()
	end
	table.clear(self.ChairPrompts)
	self.Hatch:Destroy()
	self.Details:Destroy()
	self.View:Destroy()
	if self.D.PurchaseOverlay then
		self.D.PurchaseOverlay:Destroy()
	end
end
return InventoryController

--!strict
-- The lobby menus. Every menu is an authored frame in HUD.Frames (Inventory, Rewards, Profile, LuckyBlocks) or the
-- authored egg shop; the lobby buttons themselves are bound by LobbyHUDView. This class only routes a page name to its
-- view and collects the actions (Button, Action, Payload) that view wants wired. The old sliding Lobby.Panel shell, its
-- generated shop/inventory/reward/potion pages and their fixtures are gone.
local Style = require(script.Parent.UIStyle)
local RewardsFrameView = require(script.Parent.RewardsFrameView)
local ProfileFrameView = require(script.Parent.ProfileFrameView)
local InventoryFrameView = require(script.Parent.InventoryFrameView)
local BlockPreviewView = require(script.Parent.BlockPreviewView)
local LuckyBlockView = require(script.Parent.LuckyBlockView)
local EggShopView = require(script.Parent.EggShopView)
local StoreFrameView = require(script.Parent.StoreFrameView)
local PotionHUDView = require(script.Parent.PotionHUDView)
local InventoryView = {}
InventoryView.__index = InventoryView

function InventoryView.new(playerGui: PlayerGui, catalog: any, shop: any, rewards: any, input: UserInputService?, guiService: GuiService?)
	local authoring = assert(Style.Authoring, "The authored HUD must be attached before the menus")
	local lobbyFrames = authoring.Overlays
	local blocks = if lobbyFrames:FindFirstChild("LuckyBlocks") then LuckyBlockView else BlockPreviewView
	local view = authoring.Inventory(InventoryView, playerGui, catalog, shop, rewards, blocks)
	-- The egg shop (opened by the E prompt on an egg stand) is the authored HUD.Frames.Eggs.
	if lobbyFrames:FindFirstChild("Eggs") then view.EggShop = EggShopView.new(catalog) end
	if lobbyFrames:FindFirstChild("Rewards") then view.RewardsFrame = RewardsFrameView.new(catalog, rewards) end
	if lobbyFrames:FindFirstChild("Inventory") then view.InventoryFrame = InventoryFrameView.new(catalog, input, guiService) end
	if lobbyFrames:FindFirstChild("Store") then
		local ok, marketplace = pcall(function() return game:GetService("MarketplaceService") end)
		view.StoreFrame = StoreFrameView.new(shop, if ok then marketplace else nil)
	end
	-- Lobby.Potions.Template lists the running 2x potions (with the icons drawn on the Store tiles).
	view.PotionHUD = PotionHUDView.new()
	if lobbyFrames:FindFirstChild("Profile") then
		local owner = playerGui.Parent
		view.ProfileFrame = ProfileFrameView.new(catalog, if owner and (owner :: any).UserId then (owner :: any).UserId else 0)
	end
	return view
end

function InventoryView.Clear(self: any)
	self.Actions = {}
end
function InventoryView.Action(self: any, button: any, action: string, payload: any) table.insert(self.Actions, { Button = button, Action = action, Payload = payload }) end

-- Which pages have a frame to open. Pages without one are refused instead of failing.
function InventoryView.CanOpen(self: any, page: string): boolean
	if page == "Blocks" then return true end
	if page == "PetShop" then return self.EggShop ~= nil end
	if page == "Rewards" then return self.RewardsFrame ~= nil end
	if page == "Shop" then return self.StoreFrame ~= nil end
	if page == "Profile" then return self.ProfileFrame ~= nil end
	if page == "Inventory" then return self.InventoryFrame ~= nil end
	return false
end

function InventoryView.Show(self: any, page: string?)
	self.Blocks:Show(page == "Blocks")
	if self.RewardsFrame then self.RewardsFrame:Show(page == "Rewards") end
	if self.ProfileFrame then self.ProfileFrame:Show(page == "Profile") end
	if self.InventoryFrame then self.InventoryFrame:Show(page == "Inventory") end
	if self.EggShop then self.EggShop:Show(page == "PetShop") end
	if self.StoreFrame then self.StoreFrame:Show(page == "Shop") end
end

function InventoryView.SetLobbyVisible(self: any, dock: boolean, currency: boolean)
	self.DockWanted, self.CurrencyWanted = dock, currency
	if self.Lobby then self.Lobby:SetVisible(dock, currency) end
end
function InventoryView.SetPlayBotVisible(self: any, visible: boolean)
	if self.Lobby then self.Lobby:SetPlayBotVisible(visible) end
end
function InventoryView.SetBadge(self: any, page: string, value: number)
	if self.Lobby then self.Lobby:SetBadge(page, value) end
end
function InventoryView.Acknowledge(self: any, page: string)
	if self.Lobby then self.Lobby:Acknowledge(page) end
end
function InventoryView.SetCurrency(self: any, cash: number, gems: number)
	if self.Lobby then self.Lobby:SetCurrency(cash, gems) end
	if self.StoreFrame then self.StoreFrame:SetCurrency(cash, gems) end
end
-- The running potions (state.Potions) and how long ago that snapshot arrived.
function InventoryView.SetPotions(self: any, snapshot: any, elapsed: number)
	if self.PotionHUD then self.PotionHUD:Set(snapshot, elapsed) end
end
-- Hidden during the Game frame (a match) and while the Store page is open.
function InventoryView.SetPotionsVisible(self: any, visible: boolean)
	if self.PotionHUD then self.PotionHUD:SetVisible(visible) end
end

function InventoryView.UpdateRewardClock(self: any, elapsed: number)
	if self.RewardsFrame then self.RewardsFrame:SetElapsed(elapsed) end
end
function InventoryView.UpdatePetProgress(self: any, progress: any)
	self.Blocks:UpdatePetProgress(progress)
	if self.InventoryFrame then self.InventoryFrame:UpdatePetProgress(progress) end
end

function InventoryView.Step(self: any, dt: number)
	if self.RewardsFrame then self.RewardsFrame:Step(dt) end
	if self.ProfileFrame then self.ProfileFrame:Step(dt) end
	if self.InventoryFrame then self.InventoryFrame:Step(dt) end
	if self.EggShop then self.EggShop:Step(dt) end
	if self.StoreFrame then self.StoreFrame:Step(dt) end
	if self.PotionHUD then self.PotionHUD:Step(dt) end
	self.Blocks:Step(dt)
	self.Lobby:Step(dt)
end

-- Renders the page's frame and returns its actions.
function InventoryView.Render(self: any, state: any, page: string, tab: string, profile: any?)
	self:Clear()
	if not state then return self.Actions end
	self:SetCurrency(state.Cash, state.Keys)
	if page == "Inventory" then
		if self.InventoryFrame then self.InventoryFrame:Render(state, tab, self.Actions) end
	elseif page == "PetShop" then
		if self.EggShop then self.EggShop:Render(state, tab, self.SelectedShopPet, self.Actions) end
	elseif page == "Blocks" then self.Blocks:Render(state, tab, self.Actions)
	elseif page == "Rewards" then
		if self.RewardsFrame then self.RewardsFrame:Render(state, self.Actions) end
	elseif page == "Shop" then
		if self.StoreFrame then self.StoreFrame:Render(state, self.Actions) end
	elseif page == "Profile" and profile then
		if self.ProfileFrame then self.ProfileFrame:Render(profile, self.Actions) end
	end
	return self.Actions
end

function InventoryView.Destroy(self: any)
	if self.EggShop then self.EggShop:Destroy() end
	if self.Lobby then self.Lobby:Destroy() end
	self.Blocks:Destroy()
	if self.RewardsFrame then self.RewardsFrame:Destroy() end
	if self.StoreFrame then self.StoreFrame:Destroy() end
	if self.PotionHUD then self.PotionHUD:Destroy() end
	if self.ProfileFrame then self.ProfileFrame:Destroy() end
	if self.InventoryFrame then self.InventoryFrame:Destroy() end
end

return InventoryView

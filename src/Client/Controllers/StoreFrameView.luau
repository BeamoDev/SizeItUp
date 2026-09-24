--!strict
-- Binds the authored HUD.Frames.Store overlay. It builds no UI; every control is looked up by name:
--   Frame.Shortcuts.Cash / Boosts / Deals    plain buttons that scroll to that section (no effects)
--   Frame.Header.Close                       closes (InventoryController wires it)
--   Frame.Header.Frame.Cash / Gems           the player's balances (every TextLabel inside is set)
--   Frame.ScrollingFrame.Frame:
--     Large.GoldenDeal / Large.VIP           one PurchaseButton each (GoldenDeal is not for sale yet)
--     Large.Gems.1gem / 2gem / 3gem          the three Gem packs
--     Medium.CashBoost / StreakBoost / WinsBoost .1Boost / 2Boost / 3Boost   2x potions for an hour / a day / a week
--     CashPacks1.1Cash / 2Cash / 3Cash, CashPack2.1Cash / 2Cash              Cash packs
--     Codes.Verify + the TextBox in Codes.Codes.InputZone                       code redemption
-- Every PurchaseButton's Frame.TextLabel shows the live Robux price once a product ID is configured ("Free" while the
-- temporary free shop is on, "Soon" while there is no product yet). The server still owns every purchase: a click only
-- sends the same Product request as before (a Robux prompt, or the free claim), and the potion is applied by the server.
local Style = require(script.Parent.UIStyle)
local FrameSlide = require(script.Parent.FrameSlide)
local Store = {}
Store.__index = Store

-- Cash jumps to the Cash packs, Boosts to the 2x potions (Medium), Deals to VIP/Golden Deal/Gems (Large).
local SHORTCUTS = { Cash = "CashPacks1", Boosts = "CashBoost", Deals = "GoldenDeal" }
-- section -> button name -> product ID (ShopCatalog.Products)
local PACKS = {
	{ Section = "Gems", Items = { ["1gem"] = "Key1", ["2gem"] = "Key10", ["3gem"] = "Key50" } },
	{ Section = "CashPacks1", Items = { ["1Cash"] = "Cash800", ["2Cash"] = "Cash2000", ["3Cash"] = "Cash5000" } },
	{ Section = "CashPack2", Items = { ["1Cash"] = "Cash15000", ["2Cash"] = "Cash40000" } },
}
local BOOSTS = { CashBoost = "Cash", StreakBoost = "Streak", WinsBoost = "Wins" }
local BOOST_TIERS = { { "1Boost", "Hour" }, { "2Boost", "Day" }, { "3Boost", "Week" } }
local PRICE_REFRESH_SECONDS = 120

local function clickable(node: Instance?): GuiButton?
	if not node then return nil end
	if node:IsA("GuiButton") then return node end
	return node:FindFirstChildWhichIsA("GuiButton", true) :: GuiButton?
end

local function comma(amount: number): string
	local text = tostring(math.floor(math.max(0, amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(grouped), "^,", ""))
end

function Store.new(shop: any, marketplace: any?)
	local UI = Style.Authoring
	local need = UI.Need
	local root = need(UI.Overlays, "Store", "GuiObject")
	local frame = need(root, "Frame", "GuiObject")
	local header = need(frame, "Header", "GuiObject")
	local scroll = need(frame, "ScrollingFrame", "ScrollingFrame")
	local self: any = setmetatable({
		Shop = shop, Marketplace = marketplace, Gui = root, Scroll = scroll, Items = {}, Prices = {}, PriceAt = -math.huge,
		Close = clickable(need(header, "Close", "GuiObject")),
	}, Store)
	assert(self.Close, "Missing authored UI: " .. header:GetFullName() .. ".Close (a button)")

	local balances = need(header, "Frame", "GuiObject")
	self.CashLabels = {}
	self.GemLabels = {}
	for _, entry in { { "Cash", self.CashLabels }, { "Gems", self.GemLabels } } do
		local holder = need(balances, entry[1], "GuiObject")
		for _, label in holder:GetDescendants() do
			if label:IsA("TextLabel") then table.insert(entry[2], label) end
		end
	end

	local function find(parent: Instance, name: string): Instance?
		return parent:FindFirstChild(name, true)
	end
	local function bind(node: Instance?, product: string, path: string, kind: string?): GuiButton?
		if not node then warn("Missing authored UI: Store " .. path);return nil end
		local button = clickable(node:FindFirstChild("PurchaseButton", true))
		if not button then warn("Missing authored UI: " .. node:GetFullName() .. ".PurchaseButton");return nil end
		table.insert(self.Items, { Button = button, Label = button:FindFirstChild("TextLabel", true), Product = product, Kind = kind })
		return button
	end

	for _, pack in PACKS do
		local section = find(scroll, pack.Section)
		for name, product in pack.Items do
			bind(section and section:FindFirstChild(name), product, pack.Section .. "." .. name)
		end
	end
	for boostName, boost in BOOSTS do
		local section = find(scroll, boostName)
		for _, entry in BOOST_TIERS do
			local tier, duration = entry[1], entry[2]
			local node = section and section:FindFirstChild(tier)
			local button = bind(node, "Potion" .. boost .. duration, boostName .. "." .. tier)
			-- Store tile art is untouched; only the Lobby.Potions active-potion list gets the new image IDs (PotionHUDView).
			if button then Style.BindPotionHover(button, "2x " .. boost) end
		end
	end
	-- The VIP bundle and the Golden Deal are both claimed through the same Product request.
	bind(find(scroll, "VIP"), "VIP", "VIP", "Pass")
	local goldenDeal = find(scroll, "GoldenDeal")
	bind(goldenDeal, "GoldenDeal", "GoldenDeal")
	-- GoldenDeal.NonInteractives.stars: each star breathes up/down 10-20% from its resting size, on its own
	-- random speed and phase so they twinkle independently instead of pulsing in sync.
	self.Stars, self.StarClock = {}, 0
	local starsFolder = goldenDeal and goldenDeal:FindFirstChild("NonInteractives", true)
	starsFolder = starsFolder and starsFolder:FindFirstChild("stars", true)
	if starsFolder then
		for _, star in starsFolder:GetChildren() do
			if star:IsA("ImageLabel") then
				local scale = star:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
				scale.Parent = star
				table.insert(self.Stars, {
					Scale = scale,
					Amplitude = 0.10 + math.random() * 0.10,
					Speed = 0.6 + math.random() * 0.9,
					Phase = math.random() * math.pi * 2,
				})
			end
		end
	end
	-- Frame.Passes.1Pass/2Pass/3Pass: the other three gamepasses (VIP has its own Large.VIP tile above).
	local passes = find(frame, "Passes")
	for name, product in { ["1Pass"] = "StarterPack", ["2Pass"] = "Open10", ["3Pass"] = "TwoXCash" } do
		bind(passes and passes:FindFirstChild(name), product, "Passes." .. name, "Pass")
	end

	-- Codes: a TextBox (its own placeholder stays) and the Verify button.
	local codes = find(scroll, "Codes")
	local box = codes and codes:FindFirstChildWhichIsA("TextBox", true)
	self.CodeBox = box
	self.Verify = codes and clickable(codes:FindFirstChild("Verify", true))
	if not (box and self.Verify) then warn("Missing authored UI: Store Codes (Verify button and a TextBox in Codes.InputZone)") end

	-- Shortcuts only move the scroll position (a Scroll action, no effects).
	local shortcuts = need(frame, "Shortcuts", "GuiObject")
	self.Shortcuts = {}
	for name, section in SHORTCUTS do
		local button = clickable(shortcuts:FindFirstChild(name))
		if button then table.insert(self.Shortcuts, { Button = button, Section = section })
		else warn("Missing authored UI: " .. shortcuts:GetFullName() .. "." .. name .. " (a button)") end
	end

	self.Slide = FrameSlide.new(root)
	Style.SetEnabled(root, false)
	return self
end

-- Jumps the scroll so the named section sits at the top.
function Store.ScrollTo(self: any, section: string)
	local target = self.Scroll:FindFirstChild(section, true)
	if not (target and target:IsA("GuiObject")) then return end
	local scroll = self.Scroll
	local top = target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
	local furthest = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	scroll.CanvasPosition = Vector2.new(scroll.CanvasPosition.X, math.clamp(top, 0, furthest))
end

function Store.SetCurrency(self: any, cash: number, gems: number)
	for _, label in self.CashLabels do label.Text = comma(cash) end
	for _, label in self.GemLabels do label.Text = comma(gems) end
end

function Store.CodeText(self: any): string
	return if self.CodeBox then self.CodeBox.Text else ""
end

function Store.ClearCode(self: any)
	if self.CodeBox then self.CodeBox.Text = "" end
end

-- The Robux price of a developer product (or game pass), fetched a few at a time and remembered.
function Store.FetchPrices(self: any)
	local service = self.Marketplace
	if not service or os.clock() - self.PriceAt < PRICE_REFRESH_SECONDS then return end
	self.PriceAt = os.clock()
	local shop = self.Shop
	for _, item in self.Items do
		local id, info = 0, Enum.InfoType.Product
		if item.Kind == "Pass" then id, info = (shop.Passes[item.Product] or { PassId = 0 }).PassId, Enum.InfoType.GamePass
		elseif item.Kind ~= "Soon" then id = (shop.Products[item.Product] or { ProductId = 0 }).ProductId end
		if id > 0 then
			task.spawn(function()
				local ok, result = pcall(function() return service:GetProductInfo(id, info) end)
				if ok and type(result) == "table" and type(result.PriceInRobux) == "number" then
					self.Prices[item] = result.PriceInRobux
					self:UpdatePrices()
				end
			end)
		end
	end
end

-- Roblox draws the private-use character U+E002 as its Robux icon in any font, so a price reads "\u{E002} 100" (the
-- icon, a space, then the amount with thousands separators). No RichText needed.
local ROBUX_ICON = "\u{E002}"
function Store.UpdatePrices(self: any)
	local free = self.Shop.FreeShop == true
	for _, item in self.Items do
		local label = item.Label
		if label and label:IsA("TextLabel") then
			local price = self.Prices[item]
			label.Text = if item.Kind == "Soon" then "Soon"
				elseif free then "Free"
				elseif price then ROBUX_ICON .. " " .. comma(price)
				else (if self:ProductId(item) > 0 then "..." else "Soon")
		end
	end
end

function Store.ProductId(self: any, item: any): number
	if item.Kind == "Pass" then return (self.Shop.Passes[item.Product] or { PassId = 0 }).PassId end
	local product = self.Shop.Products[item.Product]
	return if product then product.ProductId else 0
end

function Store.Show(self: any, visible: boolean)
	if visible == (self.Open == true) then return end
	self.Open = visible
	if visible then
		self.Scroll.CanvasPosition = Vector2.zero
		self.Slide:Show()
		self:FetchPrices()
	else self.Slide:Hide() end
end

-- One request per purchase button; the controller connects them on each render.
function Store.Render(self: any, state: any, actions: any)
	for _, shortcut in self.Shortcuts do
		table.insert(actions, { Button = shortcut.Button, Action = "Scroll", Payload = { Section = shortcut.Section } })
	end
	for _, item in self.Items do
		if item.Kind == "Soon" then
			table.insert(actions, { Button = item.Button, Action = "Alert", Payload = { Message = "Coming soon!" } })
		else
			table.insert(actions, { Button = item.Button, Action = "Product", Payload = { Id = item.Product, Token = state.ShopToken } })
		end
	end
	self:UpdatePrices()
end

function Store.Step(self: any, dt: number)
	self.Slide:Step(dt)
	self.StarClock += dt
	for _, star in self.Stars do
		star.Scale.Scale = 1 + math.sin(self.StarClock * star.Speed + star.Phase) * star.Amplitude
	end
end

function Store.Destroy(self: any)
	self.Open = false
	self.Slide:Reset()
end

return Store

--!strict
-- Production inventory references its leased profile document.
-- No yielding between debit, grant, and token rotation.
local InventoryService = {}
InventoryService.__index = InventoryService
function InventoryService.new(catalog: any, currency: any, adapters: any)
	return setmetatable({ Catalog = catalog, Currency = currency, Adapters = adapters, Profiles = {} }, InventoryService)
end
function InventoryService.AddPlayer(self: any, player: any)
	local data = self.Adapters.Data and self.Adapters.Data(player)
	-- Teleport failure reacquires a new profile document. Rebind ownership and
	-- rotate the token instead of retaining tables from the released lease.
	if self.Profiles[player] and self.Profiles[player].Data == data then return end
	local owned = { Pets = {}, Chairs = {}, Titles = {} }
	for _, category in { "Chairs", "Titles" } do
		for _, id in self.Catalog.Order[category] do
			local item = self.Catalog.Items[category][id]
			if not item.RewardOnly and not item.PurchaseOnly then owned[category][id] = 1 end
		end
	end
	self.Profiles[player] = { Owned = if data then data.Owned else owned, Equipped = if data then data.Equipped else { Pets = {} }, Data = data, Token = self.Adapters.NewId(), HatchAt = -math.huge }
end
-- Six equipped pets, eight for VIP owners.
local function petCap(profile: any): number
	return if profile.Data and profile.Data.VIP == true then 8 else 6
end
function InventoryService.RemovePlayer(self: any, player: any) self.Profiles[player] = nil end
function InventoryService.Snapshot(self: any, player: any)
	local profile = self.Profiles[player]
	if not profile then return nil end
	local owned = {}
	for category, items in profile.Owned do owned[category] = table.clone(items) end
	local equipped = table.clone(profile.Equipped)
	equipped.Pets = table.clone(equipped.Pets or {})
	return { Owned = owned, Equipped = equipped, Token = profile.Token, Cash = self.Currency:GetBalance(player), MaxPets = petCap(profile), AvailablePets = self.Adapters.AvailablePets and table.clone(self.Adapters.AvailablePets),
		-- Unopened Lucky Blocks (block ID -> count), e.g. won in the AFK world.
		OwnedBlocks = if profile.Data and profile.Data.OwnedBlocks then table.clone(profile.Data.OwnedBlocks) else {} }
end
-- What opening `count` blocks costs: one is the block's price, the bulk count gets the catalog's discount.
function InventoryService.BulkPrice(self: any, price: number, count: number): number
	local bulk = self.Adapters.Shop and self.Adapters.Shop.BulkHatch
	if count == 1 or not bulk then return price end
	return math.floor(price * count * (1 - bulk.Discount))
end
function InventoryService.Buy(self: any, player: any, token: any, containerId: string?, payment: string?, count: any?)
	local profile = self.Profiles[player]
	if not profile then return false, "Inventory is not ready." end
	if type(token) ~= "string" or token ~= profile.Token then return false, "That changed. Try again." end
	if self.Adapters.Busy(player) then return false, "Finish your match first." end
	local bulk = self.Adapters.Shop and self.Adapters.Shop.BulkHatch
	if count == nil then count = 1 end
	if count ~= 1 then
		if not (bulk and count == bulk.Count) then return false, "Invalid amount." end
		if self.Adapters.OwnsOpen10 and not self.Adapters.OwnsOpen10(player) then return false, "Buy the Open 10 pass first." end
	end
	local container = self.Adapters.Shop and self.Adapters.Shop.Containers[containerId or "Egg"]
	if self.Adapters.Shop and not container then return false, "Unknown container." end
	if container and container.Retired then return false,"Pick an egg or block." end
	-- Owned (unopened) blocks of this kind open first, free: no Cash or Gems, and no paid-random-item check since
	-- nothing is bought. Opening ten this way needs ten owned (and the Open 10 pass, as above).
	local stock = if container and profile.Data and profile.Data.OwnedBlocks then profile.Data.OwnedBlocks[containerId] or 0 else 0
	local fromStock = stock >= count
	if not fromStock and self.Adapters.Allowed and not self.Adapters.Allowed(player) then return false, "Not available for you." end
	local cost = self:BulkPrice(if container then container.Cash else self.Catalog.Egg.Price, count)
	local keyCost = if container then self:BulkPrice(container.Keys, count) else 0
	local keys = payment == "Keys"
	if payment and payment ~= "Cash" and payment ~= "Keys" then return false, "Invalid payment." end
	if not fromStock then
		if container and (payment or "Cash")~=container.Currency then return false,"This block can only be bought with "..tostring(container.Currency).."." end
		if container and (container[container.Currency] or 0)<=0 then return false,"This block is unavailable." end
		if keys and (not container or container.Keys <= 0 or not profile.Data or profile.Data.Keys < keyCost) then return false, "Not enough Gems." end
	end
	local now = self.Adapters.Now()
	if now < profile.HatchAt then return false, "Your egg is still hatching." end
	if not fromStock and not keys and self.Currency:GetBalance(player) < cost then return false, "Not enough Cash!" end
	local total = 0
	local order=container and container.PetOrder or self.Catalog.Order.Pets
	for _, id in order do
		local weight=if container then container.Weights[id] or 0 else self.Catalog.Items.Pets[id].Weight
		if weight>0 and (not self.Catalog.Items.Pets[id] or (self.Adapters.AvailablePets and not self.Adapters.AvailablePets[id])) then return false,"Block unavailable." end
		total+=weight
	end
	if total<=0 then return false,"No pets available." end
	-- Every opening rolls on its own; the pets are only granted once the payment has gone through.
	local picks = {}
	for _ = 1, count do
		local roll = self.Adapters.Random:NextInteger(1, total)
		local chosen = order[#order]
		for _, id in order do
			roll -= if container then container.Weights[id] or 0 else self.Catalog.Items.Pets[id].Weight
			if roll <= 0 then chosen = id; break end
		end
		table.insert(picks, chosen)
	end
	local nextToken = self.Adapters.NewId()
	if fromStock then
		profile.Data.OwnedBlocks[containerId] = if stock > count then stock - count else nil
	elseif keys then profile.Data.Keys -= keyCost
	elseif not self.Currency:Spend(player, cost) then return false, "Not enough Cash." end
	local duplicate = false
	for _, chosen in picks do
		if profile.Owned.Pets[chosen] ~= nil then duplicate = true end
		profile.Owned.Pets[chosen] = (profile.Owned.Pets[chosen] or 0) + 1
	end
	profile.Token, profile.HatchAt = nextToken, now + self.Catalog.Egg.HatchSeconds
	if profile.Data then profile.Data.Hatches += count end
	return true, { PetId = picks[1], Duplicate = duplicate, Container = containerId or "Egg", Count = if count > 1 then count else nil, Pets = if count > 1 then picks else nil, FromStock = fromStock or nil }
end
function InventoryService.Equip(self: any, player: any, category: any, id: any)
	local profile = self.Profiles[player]
	if not profile or type(category) ~= "string" or not self.Catalog.Items[category] or type(id) ~= "string" then
		return false, "Invalid item."
	end
	if self.Adapters.Busy(player) then return false, "Change gear between matches." end
	if id ~= "" and (not self.Catalog.Items[category][id] or not profile.Owned[category][id]) then
		return false, "You do not own that item."
	end
	if category == "Pets" then
		local pets = profile.Equipped.Pets
		if id == "" then table.clear(pets); return true, "Pets unequipped." end
		if #pets >= petCap(profile) then return false, "Pet slots full. Remove one." end
		local count = 0; for _, equippedId in pets do if equippedId == id then count += 1 end end
		if count >= profile.Owned.Pets[id] then return false, "All copies are equipped." end
		table.insert(pets, id); return true, "Pet equipped."
	end
	profile.Equipped[category] = if id == "" then nil else id
	return true, if id == "" then "Unequipped." else "Equipped."
end
function InventoryService.BuyPet(self: any, player: any, token: any, shopId: any, id: any)
	local profile=self.Profiles[player]
	if not profile or token~=profile.Token then return false,"That changed. Try again." end
	if self.Adapters.Busy(player) then return false,"Buy pets between matches." end
	local shop=self.Catalog.PetShops[shopId]
	local pet=self.Catalog.Items.Pets[id]
	if not shop or not pet or not table.find(shop.Pets,id) then return false,"Unknown pet." end
	if self.Adapters.AvailablePets and not self.Adapters.AvailablePets[id] then return false,"This pet is unavailable." end
	if (profile.Owned.Pets[id] or 0)>0 then return false,"You own this pet. Equip it!" end
	local now=self.Adapters.Now()
	if now<(profile.PetBuyAt or 0) then return false,"Wait before buying again." end
	local nextToken=self.Adapters.NewId()
	-- Most shops spend Cash; a shop marked Currency="Keys" (the Exquisite egg) spends Gems instead.
	if shop.Currency=="Keys" then
		if not profile.Data or profile.Data.Keys<pet.Price then return false,"Not enough Gems!" end
		profile.Data.Keys-=pet.Price
	elseif not self.Currency:Spend(player,pet.Price) then return false,"Not enough Cash!" end
	profile.Owned.Pets[id]=1;profile.Token=nextToken;profile.PetBuyAt=now+1
	return true,pet.Name.." purchased! Equip it to use its ability."
end
-- Called only by a server-bound, distance-validated world prompt. Ownership is
-- the permanent duplicate guard: an owned chair can be equipped without debit.
function InventoryService.BuyChair(self: any, player: any, id: any)
	local profile = self.Profiles[player]
	if not profile then return false, "Your inventory is not ready." end
	if self.Adapters.Busy(player) then return false, "Buy chairs between matches." end
	local item = type(id) == "string" and self.Catalog.Items.Chairs[id]
	if not item or not table.find(self.Catalog.ChairShopOrder,id) or item.RewardOnly then return false, "Unknown chair." end
	local now = self.Adapters.Now()
	if now < (profile.ChairBuyAt or -math.huge) then return false, "Wait before using a chair." end
	profile.ChairBuyAt = now + 1
	if profile.Owned.Chairs[id] then
		if profile.Equipped.Chairs == id then
			profile.Equipped.Chairs = nil
			return true, item.Name .. " unequipped."
		end
		profile.Equipped.Chairs = id
		return true, item.Name .. " equipped."
	end
	if not self.Currency:Spend(player,item.Price) then return false, "Not enough Cash for " .. item.Name .. "." end
	profile.Owned.Chairs[id], profile.Equipped.Chairs = 1, id
	return true, item.Name .. " purchased and equipped!"
end
function InventoryService.UnequipPet(self: any, player: any, slot: any)
	local profile = self.Profiles[player]
	if not profile or self.Adapters.Busy(player) or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > #profile.Equipped.Pets then return false, "Invalid pet slot." end
	table.remove(profile.Equipped.Pets, slot)
	return true, "Pet unequipped."
end
return InventoryService

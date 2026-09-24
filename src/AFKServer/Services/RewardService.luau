--!strict
-- One server-owned timer per visit. No offline accumulation or client claims.
-- Every reward cycle draws a fresh random offer from AFKConfig.Offer (one rarity tier per slot: a random option,
-- amount or item, and a random chance, the chances scaled to exactly 100%); the next reward is rolled on that offer.
local Rewards = {}
Rewards.__index = Rewards

local function comma(amount: number): string
	local text = tostring(math.floor(math.max(0, amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(grouped), "^,", ""))
end

-- wealth (optional, AFKShared/Util/WealthScale): Cash and Gem prizes grow with the Cash the player already holds.
function Rewards.new(config: any, random: any, catalog: any?, wealth: any?)
	local total = 0
	for _, reward in config.Rewards do total += reward.Chance end
	assert(math.abs(total - 100) < 0.0001, "AFK odds must sum to 100")
	return setmetatable({ Config = config, Random = random, Catalog = catalog, Wealth = wealth, Sessions = {} }, Rewards)
end

-- A random pick from a list, a random number in [low, high], and a weighted pick (entries carry Weight, default 1).
local function pick(self: any, list: { any }): any
	return list[math.clamp(math.floor(self.Random:NextNumber() * #list) + 1, 1, #list)]
end
local function between(self: any, low: number, high: number): number
	return low + (high - low) * self.Random:NextNumber()
end
local function weighted(self: any, list: { any }, weightOf: (any) -> number): any
	local total = 0
	for _, entry in list do total += weightOf(entry) end
	local roll = self.Random:NextNumber() * total
	for _, entry in list do
		roll -= weightOf(entry)
		if roll < 0 then return entry end
	end
	return list[#list]
end

-- One prize from one tier option: its amount or item, label and a stable Id. Cash and Gem amounts are scaled to the
-- Cash the player holds (`held`) so they stay worth having for rich players.
function Rewards.Prize(self: any, option: any, slot: number, held: number?): any
	local reward: any = { Kind = option.Kind, Amount = 1 }
	if option.Amount then
		local low, high, step = option.Amount[1], option.Amount[2], option.Amount[3] or 1
		local steps = math.floor((high - low) / step)
		reward.Amount = low + step * math.clamp(math.floor(self.Random:NextNumber() * (steps + 1)), 0, steps)
		if self.Wealth and option.Kind == "Cash" then
			reward.Amount = self.Wealth.Cash(reward.Amount, held, "AFK")
		elseif self.Wealth and option.Kind == "Keys" then
			reward.Amount = self.Wealth.Gems(reward.Amount, held, "AFK")
		end
	end
	local catalog, config = self.Catalog, self.Config
	local item
	if option.Kind == "Cash" then
		reward.Label = "$" .. comma(reward.Amount)
	elseif option.Kind == "Keys" then
		reward.Label = reward.Amount .. (if reward.Amount == 1 then " Gem" else " Gems")
	elseif option.Kind == "Pet" then
		item = pick(self, option.Pool)
		reward.PetId = item
		local pet = catalog and catalog.Items.Pets[item]
		reward.Label = if pet then pet.Name else item
	elseif option.Kind == "Chair" then
		item = pick(self, option.Pool)
		reward.ChairId = item
		local chair = catalog and catalog.Items.Chairs[item]
		reward.Label = (if chair then chair.Name else item) .. " Chair"
	elseif option.Kind == "Block" then
		item = pick(self, option.Pool)
		reward.BlockId = item
		local block = config.Blocks and config.Blocks[item]
		reward.Design = block and block.Design
		reward.Label = if block then block.Name else item .. " Block"
	elseif option.Kind == "Egg" then
		item = pick(self, option.Pool)
		reward.EggId = item
		local shop = catalog and catalog.PetShops and catalog.PetShops[item]
		reward.Label = if shop then shop.Name else item .. " Egg"
	end
	reward.Id = option.Kind .. ":" .. tostring(item or reward.Amount) .. ":" .. slot
	return reward
end

-- A fresh offer: one prize per AFKConfig.Offer tier with a random chance, the chances rounded to one decimal and
-- adding up to exactly 100. Falls back to the fixed Rewards list without Offer. data: the player's profile (its Cash
-- scales the Cash and Gem prizes).
function Rewards.Draw(self: any, data: any?): { any }
	local config = self.Config
	if not config.Offer then
		local fixed = {}
		for index, reward in config.Rewards do fixed[index] = table.clone(reward) end
		return fixed
	end
	local offer, weights, total = {}, {}, 0
	for slot, tier in config.Offer do
		local option = weighted(self, tier.Options, function(entry) return entry.Weight or 1 end)
		offer[slot] = self:Prize(option, slot, data and data.Cash)
		weights[slot] = between(self, tier.Weight[1], tier.Weight[2])
		total += weights[slot]
	end
	local rest = 0
	for slot = 2, #offer do
		offer[slot].Chance = math.max(0.1, math.floor(weights[slot] / total * 1000 + 0.5) / 10)
		rest += offer[slot].Chance
	end
	offer[1].Chance = math.floor((100 - rest) * 10 + 0.5) / 10
	return offer
end

function Rewards.Interval(self: any, data: any, wallTime: number): number
	-- A new random wait between RewardMinSeconds and RewardMaxSeconds (30-60s) before every reward. Old saved clock
	-- boosts no longer shorten it.
	return self.Config.RewardMinSeconds + (self.Config.RewardMaxSeconds - self.Config.RewardMinSeconds) * self.Random:NextNumber()
end
function Rewards.Add(self: any, id: number, data: any, now: number, wallTime: number)
	local interval = self:Interval(data, wallTime)
	self.Sessions[id] = { Next = now + interval, Interval = interval, Earned = 0, History = {}, Sequence = 0, Offer = self:Draw(data) }
end

-- Grants one prize; returns what the history shows (an egg becomes the pet it hatched, an owned chair its Cash).
function Rewards.Grant(self: any, session: any, data: any, selected: any): any
	local shown: any = { Id = selected.Id, Kind = selected.Kind, Amount = selected.Amount, Label = selected.Label,
		PetId = selected.PetId, ChairId = selected.ChairId, BlockId = selected.BlockId, Design = selected.Design }
	local function cash(amount: number)
		data.Cash += amount;data.TotalEarned += amount
		session.Earned += amount
	end
	if selected.Kind == "Cash" then
		cash(selected.Amount)
	elseif selected.Kind == "Keys" then
		data.Keys += selected.Amount
	elseif selected.Kind == "Chair" then
		if data.Owned.Chairs[selected.ChairId] then
			-- Already owned: a share of its price in Cash instead of a useless duplicate.
			local chair = self.Catalog and self.Catalog.Items.Chairs[selected.ChairId]
			local amount = math.max(25, math.floor((chair and chair.Price or 100) * (self.Config.OwnedChairCash or 0.25) / 25 + 0.5) * 25)
			cash(amount)
			shown = { Id = "Cash:" .. amount .. ":chair", Kind = "Cash", Amount = amount, Label = "$" .. comma(amount) }
		else
			data.Owned.Chairs[selected.ChairId] = 1
		end
	elseif selected.Kind == "Pet" then
		data.Owned.Pets[selected.PetId] = (data.Owned.Pets[selected.PetId] or 0) + 1
	elseif selected.Kind == "Block" then
		-- Saved unopened (stacking); the main game's Lucky Blocks screen opens it free.
		data.OwnedBlocks = data.OwnedBlocks or {}
		data.OwnedBlocks[selected.BlockId] = (data.OwnedBlocks[selected.BlockId] or 0) + 1
	elseif selected.Kind == "Egg" then
		-- Hatch one pet from that egg's shop, cheaper pets likelier (chance proportional to 1 / price).
		local shop = self.Catalog and self.Catalog.PetShops and self.Catalog.PetShops[selected.EggId]
		local pets = shop and shop.Pets or {}
		if #pets > 0 then
			local pet = weighted(self, pets, function(id)
				local item = self.Catalog.Items.Pets[id]
				return 1 / math.max(1, item and item.Price or 1)
			end)
			data.Owned.Pets[pet] = (data.Owned.Pets[pet] or 0) + 1
			local item = self.Catalog.Items.Pets[pet]
			shown = { Id = "Pet:" .. pet .. ":egg", Kind = "Pet", Amount = 1, PetId = pet,
				Label = (if item then item.Name else pet) }
		end
	end
	return shown
end

function Rewards.Tick(self: any, id: number, data: any, now: number, wallTime: number)
	local session = self.Sessions[id]
	if not session or now < session.Next then return nil end
	local offer = session.Offer or self:Draw(data)
	local roll, accumulated = self.Random:NextNumber() * 100, 0
	local selected = offer[#offer]
	for _, reward in offer do
		accumulated += reward.Chance
		if roll < accumulated then selected = reward;break end
	end
	local shown = self:Grant(session, data, selected)
	data.AFKRewards = (data.AFKRewards or 0) + 1
	session.Sequence += 1
	shown.Sequence = session.Sequence
	table.insert(session.History, 1, shown)
	if #session.History > self.Config.HistoryLimit then table.remove(session.History) end
	session.Interval = self:Interval(data, wallTime)
	session.Next = now + session.Interval
	-- A new random offer (items, amounts and chances) for the next reward.
	session.Offer = self:Draw(data)
	return selected
end
function Rewards.Remove(self: any, id: number) self.Sessions[id] = nil end
return Rewards

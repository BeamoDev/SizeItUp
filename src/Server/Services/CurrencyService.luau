--!strict
-- Wallet adapter. Production uses the leased profile supplied by GetData;
-- an isolated in-memory balance remains available to pure gameplay tests.
local CurrencyService = {}
CurrencyService.__index = CurrencyService
function CurrencyService.new(changed: (any, number) -> (), getData: any?, rewardMultiplier: any?)
	return setmetatable({ Balances = {}, Receipts = setmetatable({}, { __mode = "k" }), Changed = changed, GetData = getData, RewardMultiplier = rewardMultiplier }, CurrencyService)
end
function CurrencyService.AddPlayer(self: any, player: any)
	if self.Balances[player] == nil then self.Balances[player] = 0 end
	self.Changed(player, self.Balances[player])
end
function CurrencyService.RemovePlayer(self: any, player: any)
	self.Balances[player] = nil
end
function CurrencyService.GetBalance(self: any, player: any): number
	if self.GetData then local data = self.GetData(player); return if data then data.Cash else 0 end
	return self.Balances[player] or 0
end
function CurrencyService.Spend(self: any, player: any, amount: number): boolean
	if type(amount) ~= "number" or amount < 0 or amount % 1 ~= 0 or amount >= math.huge then return false end
	local data = self.GetData and self.GetData(player)
	if self.GetData and not data then return false end
	local balance = if data then data.Cash else self.Balances[player]
	if balance == nil or balance < amount then return false end
	self.Balances[player] = balance - amount
	if data then data.Cash = balance - amount end
	self.Changed(player, self.Balances[player])
	return true
end
function CurrencyService.Award(self: any, settlement: any, player: any, amount: number): number
	local data = self.GetData and self.GetData(player)
	if self.Receipts[settlement] or (self.GetData and not data) or (not self.GetData and self.Balances[player] == nil) then return 0 end
	assert(type(amount) == "number" and amount == amount and amount >= 0 and amount % 1 == 0 and amount < math.huge, "Invalid cash reward")
	-- A combo/potion multiplier can make this fractional; Cash always stays a whole number.
	if self.RewardMultiplier then amount = math.floor(amount * self.RewardMultiplier(player, settlement)) end
	self.Receipts[settlement] = true
	self.Balances[player] = self:GetBalance(player) + amount
	if data then data.Cash = self.Balances[player]; data.TotalEarned += amount end
	self.Changed(player, self.Balances[player])
	return amount
end
return CurrencyService

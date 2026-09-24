--!strict
local Schema = {}
function Schema.Copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value do
		result[key] = Schema.Copy(item)
	end
	return result
end
local function integer(value: any): number
	return if type(value) == "number"
			and value == value
			and value < math.huge
		then math.clamp(math.floor(value), 0, 1e12)
		else 0
end
function Schema.Reconcile(source: any, catalog: any)
	local data = if type(source) == "table" then Schema.Copy(source) else {}
	assert(not data.Version or data.Version <= 1, "Profile version is newer than this server")
	data.Version = 1
	local invites = {}
	if type(data.InviteRewards) == "table" then
		for id, claimed in data.InviteRewards do
			local numberId = if type(id) == "string" then tonumber(id) else nil
			if numberId and numberId > 0 and numberId < 2 ^ 53 and numberId % 1 == 0 and claimed == true then
				invites[tostring(numberId)] = true
			end
		end
	end
	data.InviteRewards = invites
	-- Codes this player has redeemed (upper-case keys).
	local redeemed, redeemedCount = {}, 0
	if type(data.RedeemedCodes) == "table" then
		for id, used in data.RedeemedCodes do
			if type(id) == "string" and #id > 0 and #id <= 32 and used == true and redeemedCount < 500 then
				redeemed[id] = true
				redeemedCount += 1
			end
		end
	end
	data.RedeemedCodes = redeemed
	local badges = {}
	if type(data.Badges) == "table" then
		for id, awarded in data.Badges do
			if type(id) == "string" and awarded == true then
				badges[id] = true
			end
		end
	end
	data.Badges = badges
	-- Every non-VIP gamepass (VIP keeps its own long-standing data.VIP flag): granted once, from either
	-- PromptGamePassPurchaseFinished or the join-time UserOwnsGamePassAsync fallback.
	local ownedPasses = {}
	if type(data.OwnedPasses) == "table" then
		for id, owned in data.OwnedPasses do
			if type(id) == "string" and owned == true then
				ownedPasses[id] = true
			end
		end
	end
	data.OwnedPasses = ownedPasses
	local pending = data.PendingReferral
	data.PendingReferral = if type(pending) == "number"
			and pending > 0
			and pending < 2 ^ 53
			and pending % 1 == 0
		then pending
		else nil
	local potions = if type(data.Potions) == "table" then data.Potions else {}
	data.Potions = {}
	for _, boost in { "Cash", "Streak", "Wins" } do
		data.Potions[boost] = integer(potions[boost])
	end
	data.Rewards = if type(data.Rewards) == "table" then data.Rewards else {}
	-- TimedDay is retained for old saves only. TimedClaims are now permanent.
	for _, field in { "DailyAt", "DailyDay", "TimedDay", "TimedSeconds", "BoostUntil" } do
		data.Rewards[field] = integer(data.Rewards[field])
	end
	data.Rewards.DailyDay = math.min(7, data.Rewards.DailyDay)
	data.Rewards.GroupClaimed = data.Rewards.GroupClaimed == true
	local claims = {}
	if type(data.Rewards.TimedClaims) == "table" then
		for id, claimed in data.Rewards.TimedClaims do
			if type(id) == "string" and #id <= 32 and claimed == true then
				claims[id] = true
			end
		end
	end
	data.Rewards.TimedClaims = claims
	for _, field in
		{
			"Cash",
			"Keys",
			"Wins",
			"Streak",
			"HighestStreak",
			"Matches",
			"TimePlayed",
			"Hatches",
			"StealCredits",
			"HeartCredits",
			"SabotageCredits",
			"HintCredits",
			"TotalEarned",
			"AFKBoostUntil",
			"AFKRewards",
			"AFKTimePlayed",
			"BestChainRound",
			"BestTeamChainRound",
			"PlayerXP",
			"LoginStreak",
			"LoginDay",
		}
	do
		data[field] = integer(data[field])
	end
	-- Retire the removed tutorial fields from old profile documents.
	data.TutorialCompleted, data.TutorialSkipped = nil, nil
	data.Owned = if type(data.Owned) == "table" then data.Owned else {}
	data.Equipped = if type(data.Equipped) == "table" then data.Equipped else {}
	-- The BlackHole chair was renamed Void: carry saved ownership and the equipped choice over.
	if type(data.Owned.Chairs) == "table" and data.Owned.Chairs.BlackHole ~= nil then
		data.Owned.Chairs.Void = data.Owned.Chairs.Void or data.Owned.Chairs.BlackHole
		data.Owned.Chairs.BlackHole = nil
	end
	if data.Equipped.Chairs == "BlackHole" then
		data.Equipped.Chairs = "Void"
	end
	for _, category in { "Pets", "Chairs", "Titles" } do
		local items = if type(data.Owned[category]) == "table" then data.Owned[category] else {}
		local cleaned = {}
		for id in catalog.Items[category] do
			local item = catalog.Items[category][id]
			local count = if category == "Pets"
					or item.RewardOnly
					or item.PurchaseOnly
				then integer(items[id])
				else math.max(1, integer(items[id]))
			if count > 0 then
				cleaned[id] = count
			end
		end
		data.Owned[category] = cleaned
	end
	local pets = if type(data.Equipped.Pets) == "table"
		then data.Equipped.Pets
		elseif type(data.Equipped.Pets) == "string" then { data.Equipped.Pets }
		else {}
	local savedXP = if type(data.PetXP) == "table" then data.PetXP else {}
	data.PetXP = {}
	local levels = catalog.PetLevels
	local maxXP = (levels.MaxLevel - 1) * levels.BaseXP
		+ levels.StepXP * (levels.MaxLevel - 2) * (levels.MaxLevel - 1) / 2
	for id in data.Owned.Pets do
		data.PetXP[id] = math.min(maxXP, integer(savedXP[id]))
	end
	local savedAbilities = if type(data.PetAbilityProgress) == "table" then data.PetAbilityProgress else {}
	data.PetAbilityProgress = {}
	for id in data.Owned.Pets do
		local ability = catalog.Items.Pets[id].Ability
		if ability then
			data.PetAbilityProgress[id] = math.min(ability.Every - 1, integer(savedAbilities[id]))
		end
	end
	-- VIP owners equip eight pets, everyone else six.
	data.VIP = data.VIP == true
	local selected, counts = {}, {}
	for index = 1, (if data.VIP then 8 else 6) do
		local id = pets[index]
		if type(id) == "string" and data.Owned.Pets[id] and (counts[id] or 0) < data.Owned.Pets[id] then
			table.insert(selected, id)
			counts[id] = (counts[id] or 0) + 1
		end
	end
	data.Equipped.Pets = selected
	for _, category in { "Chairs", "Titles" } do
		local id = data.Equipped[category]
		if type(id) ~= "string" or not data.Owned[category][id] then
			data.Equipped[category] = nil
		end
	end
	-- Unopened Lucky Blocks (block ID -> count), e.g. won in the AFK world; the Lucky Blocks screen opens them free.
	local blocks = {}
	if type(data.OwnedBlocks) == "table" then
		for id, count in data.OwnedBlocks do
			if type(id) == "string" and #id > 0 and #id <= 32 and integer(count) > 0 then
				blocks[id] = math.min(1e6, integer(count))
			end
		end
	end
	data.OwnedBlocks = blocks
	data.Showcase = if type(data.Showcase) == "table" then data.Showcase else {}
	for _, field in { "Receipts", "TransfersOut", "TransfersIn" } do
		data[field] = if type(data[field]) == "table" then data[field] else {}
	end
	return data
end
return Schema

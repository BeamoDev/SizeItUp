--!strict
-- Mutate the same leased profile as currency/inventory, before any transport yields.
local Progress = {}
function Progress.Apply(match: any, config: any, getData: (any) -> any)
	if match.Mode ~= "Endless" or not match.HeartAppliedAt or not match.Reveal then return {} end
	match.ChainRecorded = match.ChainRecorded or {}
	local team = true
	for index in match.Players do if match.Hearts[index] <= 0 or match.Departed[index] then team = false end end
	local updated = {}
	for index, player in match.Players do
		local outcome = match.Reveal.Outcomes[index]
		if outcome and match.Hearts[index] > 0 and not match.Departed[index] and (match.ChainRecorded[index] or 0) < match.CurrentRound then
			local data = getData(player)
			if data then
				match.ChainRecorded[index] = match.CurrentRound
				data.BestChainRound = math.max(data.BestChainRound or 0, match.CurrentRound)
				if team then data.BestTeamChainRound = math.max(data.BestTeamChainRound or 0, match.CurrentRound) end
				local milestone = match.CurrentRound % config.ChainMilestoneRounds == 0
				if milestone then
					data.Cash += config.ChainMilestoneCash
					data.Keys += config.ChainMilestoneKeys
					data.TotalEarned += config.ChainMilestoneCash
				end
				table.insert(updated, {Player = player, Milestone = milestone})
			end
		end
	end
	return updated
end
return Progress

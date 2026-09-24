--!strict
-- Saved player XP (Profile.PlayerXP) is one lifetime total; the level is always derived from it, so retuning
-- LevelConfig never leaves a stale level behind. Invalid amounts are ignored and the total stops at max level.
local Levels = {}
function Levels.Maximum(config: any): number
	return (config.MaxLevel-1)*config.BaseXP + config.StepXP*(config.MaxLevel-2)*(config.MaxLevel-1)/2
end
function Levels.Info(saved: any, config: any)
	local safe = if type(saved)=="number" and saved==saved then saved else 0
	local xp = math.clamp(math.floor(safe),0,Levels.Maximum(config))
	local total = xp
	local level, required = 1, config.BaseXP
	while level < config.MaxLevel and xp >= required do
		xp -= required;level += 1;required = config.BaseXP + (level-1)*config.StepXP
	end
	local max = level == config.MaxLevel
	return {Level=level,XP=if max then 0 else xp,Required=if max then 0 else required,Max=max,Total=total}
end
-- Adds XP to a profile and returns how many levels were gained (0 when nothing changed).
function Levels.Award(data: any, config: any, amount: any): number
	if type(amount)~="number" or amount~=amount or amount<=0 or amount==math.huge then return 0 end
	local before = Levels.Info(data.PlayerXP,config)
	data.PlayerXP = math.min(Levels.Maximum(config),before.Total+math.floor(amount))
	return Levels.Info(data.PlayerXP,config).Level-before.Level
end
-- Grants every title whose level has been reached (idempotent); returns the names of the newly unlocked ones.
function Levels.UnlockTitles(data: any, catalog: any, config: any): {string}
	local unlocked = {}
	local level = Levels.Info(data.PlayerXP, config).Level
	data.Owned = data.Owned or {}
	data.Owned.Titles = data.Owned.Titles or {}
	for _, id in catalog.Order.Titles do
		local item = catalog.Items.Titles[id]
		if item and item.Level <= level and (data.Owned.Titles[id] or 0) == 0 then
			data.Owned.Titles[id] = 1
			table.insert(unlocked, item.Name)
		end
	end
	return unlocked
end
function Levels.MatchFinished(data: any, config: any, won: boolean): number
	return Levels.Award(data,config,config.MatchPlayedXP+(if won then config.MatchWonXP else 0))
end
-- Call after TimePlayed has advanced by elapsed seconds; pays each PlaytimeSeconds boundary crossed once.
function Levels.Tick(data: any, config: any, elapsed: number): number
	if type(elapsed)~="number" or elapsed~=elapsed or elapsed<=0 or elapsed==math.huge then return 0 end
	local crossed = math.floor(data.TimePlayed/config.PlaytimeSeconds)-math.floor((data.TimePlayed-elapsed)/config.PlaytimeSeconds)
	return Levels.Award(data,config,math.max(0,crossed)*config.PlaytimeXP)
end
return Levels

--!strict
-- Saved XP belongs to an owned pet type. Duplicate equipped copies never stack.
local Progression = {}
function Progression.Maximum(config: any): number
	return (config.MaxLevel-1)*config.BaseXP + config.StepXP*(config.MaxLevel-2)*(config.MaxLevel-1)/2
end
function Progression.Info(total: number, config: any)
	local xp = math.clamp(math.floor(total),0,Progression.Maximum(config))
	local level, required = 1,config.BaseXP
	while level < config.MaxLevel and xp >= required do
		xp -= required;level += 1;required = config.BaseXP + (level-1)*config.StepXP
	end
	return {Level=level,XP=if level==config.MaxLevel then 0 else xp,Required=if level==config.MaxLevel then 0 else required,Max=level==config.MaxLevel}
end
function Progression.Tick(data: any, config: any, seconds: number): boolean
	if type(seconds)~="number" or seconds~=seconds or seconds<=0 or seconds==math.huge then return false end
	local amount = math.floor(seconds*config.XPPerSecond)
	if amount<=0 then return false end
	data.PetXP = data.PetXP or {}
	local seen,changed = {},false
	for _,id in data.Equipped.Pets do
		if not seen[id] and (data.Owned.Pets[id] or 0)>0 then
			seen[id] = true
			local before = data.PetXP[id] or 0
			data.PetXP[id] = math.min(Progression.Maximum(config),before+amount)
			changed = changed or data.PetXP[id]~=before
		end
	end
	return changed
end
function Progression.Snapshot(data: any, config: any)
	local result = {}
	for id in data.Owned.Pets do result[id] = Progression.Info((data.PetXP and data.PetXP[id]) or 0,config) end
	return result
end
return Progression

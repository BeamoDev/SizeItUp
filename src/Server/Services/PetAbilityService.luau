--!strict
-- Saved per-pet progress; the equipped roster stays frozen for each match.
-- Turn-based abilities (Heal, Hint, Shield) advance a saved per-pet counter once per living owner turn.
-- Every other ability is passive or once per game and is summarised by Effects(): duplicate copies never
-- stack, and when several different pets share a kind only the strongest counts.
local PetAbilityService = {}

local TURN_KINDS = { Heal = true, Hint = true, Shield = true }
-- Kinds summarised by Effects(), with a hard cap on their combined strength.
local PASSIVE_CAPS = {
	SecondChance = 10, LowerBar = 12, ExtraTime = 10, InkRefill = 2, LongInk = 6,
	CashBonus = 50, KeyFinder = 60, StreakSaver = 60, SharpEye = 50, Revive = 1,
}

function PetAbilityService.Capture(data: any, catalog: any)
	local result, seen = {}, {}
	if not data then return result end
	data.PetAbilityProgress=data.PetAbilityProgress or {}
	for _, id in data.Equipped.Pets do
		local pet = catalog.Items.Pets[id]
		if not seen[id] and pet and pet.Ability and (data.Owned.Pets[id] or 0)>0 then
			seen[id]=true
			table.insert(result, { Id=id, Name=pet.Name, Kind=pet.Ability.Kind, Every=pet.Ability.Every, Power=pet.Ability.Power, Unit=pet.Ability.Unit, Progress=data.PetAbilityProgress })
		end
	end
	return result
end

-- Strongest pet of each passive kind: { LowerBar = { Power = 4, Name = "Bull" }, Revive = { Power = 1, Name = "..." }, ... }.
-- Shield is included when any Shield pet is equipped so the match knows the ability exists.
function PetAbilityService.Effects(roster: any): any
	local effects: any = {}
	for _, ability in roster or {} do
		local cap = PASSIVE_CAPS[ability.Kind]
		if cap then
			local power = math.min(ability.Power or 1, cap)
			local best = effects[ability.Kind]
			if not best or power > best.Power then effects[ability.Kind] = { Power = power, Name = ability.Name } end
		elseif ability.Kind == "Shield" and not effects.Shield then
			effects.Shield = { Power = 1, Name = ability.Name }
		end
	end
	return effects
end

-- Returns hearts after healing, whether a free hint was earned, the kid-friendly messages for whatever fired,
-- and whether a Shield charge was earned this turn.
function PetAbilityService.Turn(abilities: any, turn: number, _round: number, hearts: number, maximum: number)
	local healed, hint, shield, messages = 0, false, false, {}
	if hearts<=0 then return hearts, false, messages, false end
	for _, ability in abilities do
		if not TURN_KINDS[ability.Kind] then continue end
		-- Each living owner has one turn per round. Watching/AFK and duplicate
		-- equipped copies do not advance these saved counters.
		if ability.LastTurn and turn<=ability.LastTurn then continue end
		ability.LastTurn=turn
		local count=(ability.Progress[ability.Id] or 0)+1
		ability.Progress[ability.Id]=count%ability.Every
		if count>=ability.Every then
			if ability.Kind=="Heal" then
				local gain=math.min(1,maximum-hearts-healed)
				if gain>0 then healed+=gain;table.insert(messages,"Healed: +1 heart!") end
			elseif ability.Kind=="Hint" and not hint then hint=true;table.insert(messages,"Free hint! Tap Hint.")
			elseif ability.Kind=="Shield" and not shield then shield=true;table.insert(messages,"Shield ready!") end
		end
	end
	return hearts+healed, hint, messages, shield
end
return PetAbilityService

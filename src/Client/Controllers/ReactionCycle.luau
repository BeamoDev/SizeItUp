--!strict
-- The end-of-round "who survived" cutscene: every player who played the round gets one full slot, in seat order
-- starting with the player after you and ending on yourself (a duel shows the other player, then you). Players
-- already out before this round are skipped; the server gives the reaction exactly one slot per shown player.
-- Runs every round, in every mode, even when nobody lost a heart (they simply get a "safe" slot).
--
-- Beats is the ONE timeline for a slot, read by every piece of the cutscene (camera, header, Left panel, hearts,
-- avatar highlight, icon, red screen flash) so nothing is timed twice or rewritten by another system:
--   0          the camera starts easing onto the player; the header title shows their username
--   Verdict    the subtitle says safe / lost a life; the avatar highlight (red or green) and the icon appear
--   PanelIn    the Left panel (profile and hearts) slides in
--   Heart      over HeartSeconds the lost heart goes dark (or a healed one comes back) inside that panel
--   PanelOut   the panel slides away and the highlight/icon fade over FadeSeconds, before the next player's slot
-- Pure data/time math; no Instances, no side effects.
local ReactionCycle = {}

ReactionCycle.Beats = table.freeze({
	Verdict = 0.9,
	PanelIn = 1.4,
	Heart = 2.2,
	HeartSeconds = 0.9,
	PanelOut = 4.1,
	FadeSeconds = 0.5,
})

-- participants: the snapshot's own Participants array (UserId, Name, Username, Hearts), already in seat order.
function ReactionCycle.Order(participants: { any }, yourUserId: number): { any }
	local mine
	for i, p in participants do
		if p.UserId == yourUserId then
			mine = i
		end
	end
	if not mine then
		return participants
	end
	local count = #participants
	local order = {}
	for offset = 1, count do
		table.insert(order, participants[(mine + offset - 1) % count + 1])
	end
	return order
end

-- heartChanges: the snapshot's HeartChanges list (only present for modes that report every change, e.g. Endless).
-- loserUserId: the snapshot's single-loser fallback (Classic/SuddenDeath, which never send HeartChanges).
local function deltas(heartChanges: { any }?, loserUserId: number?): { [number]: number }
	local map = {}
	for _, change in heartChanges or {} do
		map[change.UserId] = change.HeartDelta
	end
	if not next(map) and loserUserId then
		map[loserUserId] = -1
	end
	return map
end

-- UserId -> heart change this round (the same map Evaluate uses), for painting each player's hearts in their slot.
ReactionCycle.Deltas = deltas

-- The players the cutscene shows, in order: everyone still in (hearts left) or who lost a heart this round. Works
-- before and after hearts settle, so the table camera can go to the first player already during TABLE_RETURN.
function ReactionCycle.Lineup(participants: { any }?, yourUserId: number?, heartChanges: { any }?, loserUserId: number?): { any }
	if not participants or not yourUserId then
		return {}
	end
	local changes = deltas(heartChanges, loserUserId)
	local lineup = {}
	for _, participant in ReactionCycle.Order(participants, yourUserId) do
		if (participant.Hearts or 0) > 0 or (changes[participant.UserId] or 0) < 0 then
			table.insert(lineup, participant)
		end
	end
	return lineup
end

-- slotSeconds: time to show one player. Returns nil outside a reaction, else one entry: Order, Index, Count,
-- SlotSeconds, SlotAge (all in seconds), UserId, Name, Username, HeartsAfter, Delta (0 for a safe/unaffected
-- player), Eliminated, IsYou, IsLast, Beats.
function ReactionCycle.Evaluate(
	participants: { any }?,
	yourUserId: number?,
	heartChanges: { any }?,
	loserUserId: number?,
	heartAppliedAt: number?,
	now: number,
	slotSeconds: number
): any?
	if not heartAppliedAt then
		return nil
	end
	local order = ReactionCycle.Lineup(participants, yourUserId, heartChanges, loserUserId)
	local count = #order
	if count == 0 then
		return nil
	end
	local changes = deltas(heartChanges, loserUserId)
	local slot = math.max(0.01, slotSeconds)
	local age = math.max(0, now - heartAppliedAt)
	local index = math.clamp(math.floor(age / slot) + 1, 1, count)
	local participant = order[index]
	local delta = changes[participant.UserId] or 0
	return {
		Order = order,
		Index = index,
		Count = count,
		SlotSeconds = slot,
		SlotAge = age - (index - 1) * slot,
		UserId = participant.UserId,
		Name = participant.Name,
		Username = participant.Username,
		HeartsAfter = participant.Hearts,
		Delta = delta,
		Eliminated = delta < 0 and (participant.Hearts or 0) <= 0,
		IsYou = participant.UserId == yourUserId,
		IsLast = index == count,
		Beats = ReactionCycle.Beats,
	}
end

-- Whether the Left panel is on screen at this point of the slot (Show and Paint both ask, so they always agree).
function ReactionCycle.PanelShown(entry: any?): boolean
	local beats = ReactionCycle.Beats
	return entry ~= nil and entry.SlotAge >= beats.PanelIn and entry.SlotAge < beats.PanelOut
end

return ReactionCycle

--!strict
-- Roblox funnel analytics: the "Onboarding V2" funnel follows a player from joining all the way through their
-- first real engagement and monetization moments. Each step is logged once per player per visit, through
-- AnalyticsService:LogFunnelStepEvent. Analytics can never affect gameplay: every call is protected and a
-- missing or failing service is ignored. (V2 replaces the shallower four-step V1 funnel; V1 never shipped to
-- real players, so there is no historical data to preserve continuity with.)
--   1  Joined game        the player arrives
--   2  Sat at table       they take a seat at any table
--   3  Started game       a match starts with them in it
--   4  Locked a guess     they submit their first ever guess
--   5  Saw a reveal       their first round reaches the reveal
--   6  Finished a game    a match they played ends with a result (cancelled matches do not count)
--   7  Won a match        they win their first match
--   8  Made a purchase    their first real Robux purchase (a developer product or gamepass) completes
--   9  Leveled up         they reach player level 2
--   10 Hatched a pet      they open their first egg/lucky block and receive a pet
local AnalyticsFunnel = {}
AnalyticsFunnel.__index = AnalyticsFunnel

AnalyticsFunnel.Name = "Onboarding V2"
AnalyticsFunnel.Steps = {
	"Joined game",
	"Sat at table",
	"Started game",
	"Locked a guess",
	"Saw a reveal",
	"Finished a game",
	"Won a match",
	"Made a purchase",
	"Leveled up",
	"Hatched a pet",
}
AnalyticsFunnel.Joined, AnalyticsFunnel.Seated, AnalyticsFunnel.Started = 1, 2, 3
AnalyticsFunnel.LockedGuess, AnalyticsFunnel.SawReveal, AnalyticsFunnel.Finished = 4, 5, 6
AnalyticsFunnel.Won, AnalyticsFunnel.Purchased, AnalyticsFunnel.LeveledUp, AnalyticsFunnel.HatchedPet = 7, 8, 9, 10

-- service: AnalyticsService (or nil); newId: returns a fresh unique string (the funnel session id).
function AnalyticsFunnel.new(service: any?, newId: () -> string)
	return setmetatable({ Service = service, NewId = newId, Players = {} }, AnalyticsFunnel)
end

-- Logs `step` (1-4) for the player once; later calls for the same step are ignored. Returns whether it was sent.
function AnalyticsFunnel.Log(self: any, player: any, step: number): boolean
	local name = AnalyticsFunnel.Steps[step]
	if not name or not player then return false end
	local session = self.Players[player]
	if not session then
		session = { Id = self.NewId(), Logged = {} }
		self.Players[player] = session
	end
	if session.Logged[step] then return false end
	session.Logged[step] = true
	if not self.Service then return false end
	local ok = pcall(function()
		self.Service:LogFunnelStepEvent(player, AnalyticsFunnel.Name, session.Id, step, name)
	end)
	return ok
end

function AnalyticsFunnel.Remove(self: any, player: any)
	self.Players[player] = nil
end

return AnalyticsFunnel

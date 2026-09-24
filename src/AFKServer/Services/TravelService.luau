--!strict
-- Release the profile before teleporting; reacquire it if initialization fails.
local Travel = {}
Travel.__index = Travel
function Travel.new(d: any)
	return setmetatable({ D = d, Pending = {} }, Travel)
end
function Travel.Recover(self: any, player: any, destination: number)
	local pending = self.Pending[player]
	if not pending or pending.PlaceId ~= destination or pending.Recovering then return end
	pending.Recovering = true
	if self.D.Present(player) then
		local success, recovered = pcall(self.D.Recover,player)
		if self.D.Present(player) and self.Pending[player]==pending then
			if not success or not recovered then self.D.Kick(player, "Your save could not reopen after travel failed. Please rejoin.")
			else
				self.D.SetTraveling(player, false)
				self.D.Message(player, "Teleport failed. Try again.")
			end
		end
	end
	if self.Pending[player]==pending then self.Pending[player] = nil end
end
function Travel.Start(self: any, player: any, destination: any): boolean
	if self.Pending[player] then return false end
	if self.D.IsStudio() then self.D.Message(player, "Teleport works in-game only.");return false end
	if type(destination) ~= "number" or destination % 1 ~= 0 or destination <= 0 or destination == self.D.PlaceId then
		self.D.Message(player, "Destination not set yet.");return false
	end
	if not self.D.CanTravel(player) then self.D.Message(player, "Finish your match first.");return false end
	self.Pending[player] = { PlaceId = destination }
	self.D.SetTraveling(player, true)
	self.D.Message(player, "Saving and teleporting...")
	local released,saved=pcall(self.D.Release,player)
	if not released or not saved then
		self.Pending[player] = nil
		self.D.Kick(player, "Your save could not finish. Please rejoin; no teleport was started.")
		return false
	end
	if not self.D.Present(player) then self.Pending[player] = nil;return false end
	local ok = pcall(self.D.Teleport, destination, player)
	if not ok then self:Recover(player, destination) end
	return ok
end
function Travel.Remove(self: any, player: any) self.Pending[player] = nil end
return Travel

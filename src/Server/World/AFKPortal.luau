--!strict
-- The authored AFK portal: the BasePart named Hitbox under Workspace.Game.Triggers.AFK. Running into it sends a living, unseated
-- player to the AFK place (the server's normal save-releasing TravelService trip). There is no ProximityPrompt any more;
-- an old one left on the model is switched off so it never shows. Nothing else about the model is touched.
local AFKPortal = {}

local COOLDOWN_SECONDS = 3 -- per player, so standing in the hitbox doesn't restart the trip every frame

-- Finds the Hitbox part under `root` (Workspace.Game.Triggers.AFK), or nil.
function AFKPortal.Find(root: Instance?): BasePart?
	if not root then return nil end
	local hitbox = root:FindFirstChild("Hitbox", true)
	if hitbox and hitbox:IsA("BasePart") then return hitbox end
	return nil
end

-- go(player): starts the trip (validates the profile, match state and saving); returns whether it was accepted.
-- players: the Players service (used to turn a touching character into its player).
function AFKPortal.Bind(root: Instance?, go: (Player) -> boolean, warn: (string) -> (), players: any, clock: (() -> number)?): any?
	if not root then return nil end -- no portal in this map
	local part = AFKPortal.Find(root)
	if not part then
		warn("No Workspace.Game.Triggers.AFK.Hitbox part found; the AFK portal is off.")
		return nil
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then descendant.Enabled = false end
	end
	part.CanTouch = true
	local now = clock or os.clock
	local last: { [Player]: number } = {}
	local connection = part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and players:GetPlayerFromCharacter(character)
		if not player then return end
		local body = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not (body and humanoid and humanoid.Health > 0 and not humanoid.SeatPart) then return end
		local time = now()
		if last[player] and time - last[player] < COOLDOWN_SECONDS then return end
		last[player] = time
		go(player)
	end)
	local leaving = players.PlayerRemoving:Connect(function(player: Player) last[player] = nil end)
	return {
		Part = part,
		Connection = connection,
		Leaving = leaving,
	}
end

return AFKPortal

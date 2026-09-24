--!strict
-- You never see your own cash counter, and players sharing a match do not see each
-- other's either (it clutters the heart-loss camera). Everyone else's stays visible,
-- so lobby players can still see and steal. Purely local: the server still replicates
-- every tag and the steal flow uses the replicated Cash attribute.
local CashPrivacyController = {}
CashPrivacyController.__index = CashPrivacyController
local TAG_NAMES = { "CashTag", "CashBillboard" }

function CashPrivacyController.new(player: any, world: any, getSnapshot: () -> any, runService: any)
	local self: any = setmetatable(
		{
			Player = player,
			World = world,
			GetSnapshot = getSnapshot,
			Hidden = {},
			OpponentIds = {},
			Seen = {},
			Timer = 0,
		},
		CashPrivacyController
	)
	self.Connection = runService.Heartbeat:Connect(function(dt: number)
		self:Step(dt)
	end)
	return self
end

function CashPrivacyController.Opponents(self: any): { [number]: boolean }
	local snapshot = self.GetSnapshot()
	local ids = self.OpponentIds
	table.clear(ids)
	if snapshot and snapshot.MatchId and snapshot.State ~= "IDLE" and type(snapshot.Participants) == "table" then
		for _, participant in snapshot.Participants do
			if participant.UserId ~= self.Player.UserId then
				ids[participant.UserId] = true
			end
		end
	end
	return ids
end

function CashPrivacyController.Step(self: any, dt: number)
	self.Timer += dt
	if self.Timer < 0.1 then
		return
	end
	self.Timer = 0
	local hiddenIds = self:Opponents()
	hiddenIds[self.Player.UserId] = true
	local runtime = self.World:FindFirstChild("Runtime")
	local other = runtime and runtime:FindFirstChild("Other")
	local root = if other then other:FindFirstChild("ScaleCosmeticDisplays") else nil
	local seen = self.Seen
	table.clear(seen)
	if root then
		for _, folder in root:GetChildren() do
			local userId = tonumber(folder.Name)
			for _, name in TAG_NAMES do
				local tag = folder:FindFirstChild(name)
				if tag then
					seen[tag] = true
					local hideTag = userId == self.Player.UserId or (userId and hiddenIds[userId])
					if hideTag then
						self.Hidden[tag] = true
						-- The server re-enables the tag whenever cash changes; keep it off for the local player and hidden opponents.
						if tag.Enabled then
							tag.Enabled = false
						end
						if tag:IsA("BillboardGui") then
							local label = tag:FindFirstChild("Label")
							if label and label:IsA("TextLabel") then
								label.Visible = false
							end
						end
					elseif self.Hidden[tag] then
						self:Restore(tag)
					end
				end
			end
		end
	end
	for tag in self.Hidden do
		if not seen[tag] or not tag.Parent then
			self.Hidden[tag] = nil
		end
	end
end

-- The server marks zero-cash tags CashShown=false; never turn those on.
function CashPrivacyController.Restore(self: any, tag: any)
	self.Hidden[tag] = nil
	if tag.Parent then
		tag.Enabled = tag:GetAttribute("CashShown") ~= false
	end
end

function CashPrivacyController.Destroy(self: any)
	self.Connection:Disconnect()
	for tag in self.Hidden do
		self:Restore(tag)
	end
end

return CashPrivacyController

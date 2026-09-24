--!strict
-- Server-created spectator visuals. Never serialize private match records or
-- use the secret target size / either live guess for the guessing miniatures.
-- Money is always shown with thousands separators: 80000 -> "$80,000".
local function money(amount: number): string
	local text = tostring(math.floor(math.abs(amount)))
	local grouped = string.gsub(string.reverse(text), "(%d%d%d)", "%1,")
	return (if amount < 0 then "-$" else "$") .. string.gsub(string.reverse(grouped), "^,", "")
end
local TableDisplay = {}
TableDisplay.__index = TableDisplay
local heartColor = Color3.fromRGB(235, 45, 60)
local function setText(label: TextLabel?, value: string)
	if label and label.Text ~= value then
		label.Text = value
	end
end
local function text(parent: Instance, name: string, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name, label.Size = name, size
	label.BackgroundColor3, label.BackgroundTransparency, label.BorderSizePixel = Color3.new(0, 0, 0), 1, 0
	label.TextColor3, label.Font, label.TextSize = Color3.fromRGB(246, 248, 255), Enum.Font.FredokaOne, 16
	label.TextStrokeTransparency = 0
	label.TextWrapped, label.RichText, label.Text = true, false, ""
	label.TextScaled = true
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.Name = "Corners"
	corner.CornerRadius, corner.Parent = UDim.new(0, 8), label
	return label
end
local function board(
	parent: Instance,
	name: string,
	adornee: BasePart,
	size: Vector2,
	offset: Vector3?,
	distance: number
)
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.Adornee, gui.Size = name, adornee, UDim2.fromScale(size.X, size.Y)
	if offset then
		gui.StudsOffsetWorldSpace = offset
	end
	gui.MaxDistance, gui.AlwaysOnTop = distance, false
	gui.Parent = parent
	return gui, text(gui, "Text", UDim2.fromScale(1, 1))
end
local function gui(instance: Instance?): any
	return if instance and (instance:IsA("BillboardGui") or instance:IsA("SurfaceGui")) then instance else nil
end
local function label(parent: any): any
	local found = parent and parent:FindFirstChild("Label")
	return if found and found:IsA("TextLabel") then found else nil
end
function TableDisplay.new(config: any, catalog: any, prizeRoll: any?, models: any?, visual: any?, worldBindings: any?)
	return setmetatable({
		Config = config,
		Catalog = catalog,
		Views = {},
		PrizeRoll = prizeRoll,
		Models = models,
		Visual = visual,
		WorldBindings = worldBindings,
	}, TableDisplay)
end
function TableDisplay.Placement(_self: any, model: Model): CFrame?
	local marker = model:FindFirstChild("SpectatorDisplay")
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	local top = model:FindFirstChild("Tabletop", true) or model:FindFirstChild("TableTop", true)
	if top and top:IsA("BasePart") then
		return top.CFrame * CFrame.new(0, top.Size.Y * 0.5 + 0.03, 0)
	end
	local a, b = model:FindFirstChild("Seat1"), model:FindFirstChild("Seat2")
	if a and b and a:IsA("Seat") and b:IsA("Seat") then
		return CFrame.new((a.CFrame.Position + b.CFrame.Position) * 0.5 + Vector3.new(0, 1.3, 0))
	end
	return CFrame.new(0, 3, 0)
end
function TableDisplay.Add(self: any, record: any)
	if self.Views[record] then
		return self.Views[record]
	end
	local root = record.Key and record.Key:FindFirstChild("TableDisplay")
	local ownedRoot = false
	if not root then
		root = Instance.new("Model")
		root.Name = "TableDisplay"
		root.Parent = record.Key
		ownedRoot = true
	end
	local anchor = root:FindFirstChild("Anchor") or Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = root
	anchor.CFrame = self:Placement(record.Key) or CFrame.new(0, 3, 0)
	local reference = root:FindFirstChild("Reference") or Instance.new("Part")
	reference.Name = "Reference"
	reference.Size = Vector3.new(0.5, 0.5, 0.5)
	reference.Transparency = 1
	reference.Anchored = true
	reference.CanCollide = false
	reference.CanTouch = false
	reference.CanQuery = false
	reference:SetAttribute("TableMiniature", true)
	reference.Parent = root
	local target = root:FindFirstChild("Target") or Instance.new("Part")
	target.Name = "Target"
	target.Size = Vector3.new(0.5, 0.5, 0.5)
	target.Transparency = 1
	target.Anchored = true
	target.CanCollide = false
	target.CanTouch = false
	target.CanQuery = false
	target:SetAttribute("TableMiniature", true)
	target.Parent = root
	local status = root:FindFirstChild("Status") or Instance.new("BillboardGui")
	status.Name = "Status"
	status.Size = UDim2.fromOffset(260, 42)
	status.AlwaysOnTop = true
	status.MaxDistance = 80
	status.Parent = root
	status.Adornee = anchor
	local statusText = status:FindFirstChild("StatusText") or text(status, "StatusText", UDim2.fromScale(1, 1))
	statusText.TextScaled = true
	statusText.BackgroundTransparency = 1
	statusText.Font = Enum.Font.FredokaOne
	statusText.TextColor3 = Color3.fromRGB(246, 248, 255)
	statusText.Text = "Sit to play"
	statusText.Parent = status
	local names = root:FindFirstChild("Names") or Instance.new("BillboardGui")
	names.Name = "Names"
	names.Size = UDim2.fromOffset(300, 80)
	names.AlwaysOnTop = true
	names.MaxDistance = 60
	names.Parent = root
	names.Adornee = anchor
	local namesText = names:FindFirstChild("NamesText") or text(names, "NamesText", UDim2.fromScale(1, 1))
	namesText.Text = ""
	namesText.TextScaled = true
	namesText.BackgroundTransparency = 1
	names.Enabled = false
	local prizePad = root:FindFirstChild("PrizePad") or Instance.new("Part")
	prizePad.Name = "PrizePad"
	prizePad.Size = Vector3.new(1.5, 0.2, 1.5)
	prizePad.Color = Color3.fromRGB(70, 255, 125)
	prizePad.Transparency = 1
	prizePad.Anchored = true
	prizePad.CanCollide = false
	prizePad.CanTouch = false
	prizePad.CanQuery = false
	prizePad.CFrame = CFrame.lookAt(Vector3.new(0, 1.4, 0), Vector3.new(-1, 0, 0))
	prizePad.Parent = root
	local prizeSurface = prizePad:FindFirstChild("PrizeSurface") or Instance.new("SurfaceGui")
	prizeSurface.Name = "PrizeSurface"
	prizeSurface.Face = Enum.NormalId.Top
	prizeSurface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	prizeSurface.Adornee = prizePad
	prizeSurface.Enabled = false
	prizeSurface.Parent = prizePad
	local prizeLabel1 = prizeSurface:FindFirstChild("PrizeLabel1")
		or text(prizeSurface, "PrizeLabel1", UDim2.fromScale(1, 0.5))
	prizeLabel1.Position = UDim2.new(0, 0, 0, 0)
	prizeLabel1.Rotation = 180
	prizeLabel1.TextSize = 24
	local prizeLabel2 = prizeSurface:FindFirstChild("PrizeLabel2")
		or text(prizeSurface, "PrizeLabel2", UDim2.fromScale(1, 0.5))
	prizeLabel2.Position = UDim2.new(0, 0, 0.5, 0)
	prizeLabel2.Rotation = 0
	prizeLabel2.TextSize = 24
	local view = {
		Root = root,
		OwnedRoot = ownedRoot,
		Anchor = anchor,
		Reference = reference,
		Target = target,
		ReferencePart = reference,
		TargetPart = target,
		Status = status,
		StatusText = statusText,
		Names = names,
		NamesText = namesText,
		PrizePad = prizePad,
		PrizeSurface = prizeSurface,
		PrizeLabels = { prizeLabel1, prizeLabel2 },
		Hearts = {},
		Authored = nil,
		MiniatureKey = nil,
	}
	self.Views[record] = view
	return view
end
function TableDisplay.StatusText(self: any, record: any, now: number): string
	local match = record.Match
	if not match then
		local seatedCount = record.SeatedCount or #record.Players
		if record.State == "VOTING" then
			return "Vote for a mode! " .. math.max(0, math.ceil(record.Deadline - now)) .. "s"
		end
		if record.State == "PRIZE_ROLL" then
			return "Picking the prize..."
		end
		if record.State == "COUNTDOWN" then
			return "Starting in " .. math.max(0, math.ceil(record.Deadline - now)) .. "..."
		end
		if record.State == "GO" then
			return "GO!"
		end
		if record.State == "RESETTING" then
			return "Getting ready for the next match..."
		end
		if record.State == "WAITING_FOR_PLAYER" then
			if seatedCount == (record.Capacity or 2) then
				return record.Message or "Preparing match..."
			end
			return "Waiting for players (" .. seatedCount .. "/" .. (record.Capacity or 2) .. ")"
		end
		return "Sit to play (" .. seatedCount .. "/" .. (record.Capacity or 2) .. ")"
	end
	if match.Mode and match.RoundState ~= "MATCH_END" then
		return tostring(match.Mode) .. " in progress"
	end
	if match.RoundState == "MATCH_END" then
		if match.Winner then
			return tostring(match.Players[match.Winner].DisplayName) .. " wins!"
		end
		return if match.Completed then "Match complete / Draw!" else "Match cancelled"
	end
	return "Match in progress"
end
function TableDisplay.ResolveAuthored(_self: any, record: any, view: any, now: number): any
	local cached = view.Authored
	if cached then
		local valid = true
		for _, instance in cached.Parts do
			if not instance:IsDescendantOf(record.Key) then
				valid = false
				break
			end
		end
		if valid and (#cached.Parts > 0 or now < (view.AuthoredRetryAt or 0)) then
			return cached
		end
	elseif now < (view.AuthoredRetryAt or 0) then
		return nil
	end
	view.AuthoredRetryAt = now + 2
	local status = gui(record.Key:FindFirstChild("TableStatus", true))
	local board = gui(record.Key:FindFirstChild("CashBillboard", true))
	local cash = record.Key:FindFirstChild("Cash", true)
	local decor, parts = {}, {}
	if cash then
		for _, child in cash:GetDescendants() do
			if child.Name == "Decor" and child:IsA("BasePart") then
				table.insert(decor, child)
				table.insert(parts, child)
			end
		end
	end
	local result = {
		Status = status,
		StatusLabel = label(status),
		Board = board,
		BoardLabel = label(board),
		Decor = decor,
		Parts = parts,
		CashSpot = if cash and cash:IsA("PVInstance") then cash else nil,
	}
	if result.CashSpot then
		table.insert(parts, result.CashSpot)
	end
	for _, instance in { result.StatusLabel, result.BoardLabel } do
		if instance then
			table.insert(parts, instance)
		end
	end
	view.Authored = result
	return result
end
function TableDisplay.ApplyAuthored(self: any, record: any, view: any, authored: any, statusText: string, now: number)
	local rolling = record.State == "PRIZE_ROLL" and record.Prize ~= nil and record.RollStarted ~= nil
	if authored.StatusLabel then
		authored.Status.Enabled = not rolling
		setText(authored.StatusLabel, statusText)
	end
	if view.Status then
		view.Status.Enabled = false
	end
	local transparency = if rolling then 0 else 1
	for _, decor in authored.Decor do
		if decor.Transparency ~= transparency then
			decor.Transparency = transparency
		end
	end
	if authored.BoardLabel then
		local elapsed = if rolling then now - record.RollStarted else 0
		local intro = if rolling then math.min(1, record.RollDuration * 0.25) else 0
		local flicker = rolling and elapsed >= intro
		authored.Board.Enabled = flicker
		if flicker then
			local cash = if self.PrizeRoll
				then self.PrizeRoll.Amount(
					record.Prize,
					elapsed - intro,
					record.RollDuration - intro,
					self.Config.PrizeHoldSeconds
				)
				else record.Prize
			setText(authored.BoardLabel, money(cash))
		end
	end
end
local function miniaturePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary and primary:IsA("BasePart") then
			return primary
		end
		for _, child in instance:GetDescendants() do
			if child:IsA("BasePart") then
				return child
			end
		end
	end
	return nil
end
-- A miniature is a whole cloned Model (most real objects are more than one part), not just the single
-- representative BasePart miniaturePart() finds for colour-tinting: this reaches every part of it so hiding
-- one at match end (or when there is no pair at all) cannot leave any of its other parts stuck visible.
local function setMiniatureVisible(instance: Instance?, visible: boolean)
	if not instance then
		return
	end
	local transparency, collide = if visible then 0 else 1, visible
	if instance:IsA("BasePart") then
		instance.Transparency, instance.CanCollide = transparency, collide
	elseif instance:IsA("Model") then
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency, part.CanCollide = transparency, collide
			end
		end
	end
end

function TableDisplay.SetMiniature(self: any, view: any, pair: any, tableKey: Instance?, kind: string)
	if not self.Visual or not self.Visual.MiniatureFit or not pair then
		return
	end
	local display = tableKey and tableKey:FindFirstChild("TableDisplay")
	if not display then
		return
	end
	local box = display:FindFirstChild(kind .. "Miniature")
	if not box or not box:IsA("BasePart") then
		return
	end
	local prior = view[kind]
	if prior and prior.Parent == display and prior ~= display:FindFirstChild(kind) then
		prior:Destroy()
	end
	local id = if kind == "Reference" then pair.ReferenceId else pair.TargetId
	local model = self.Models and self.Models:FindFirstChild(id)
	if not model then
		return
	end
	local clone = self.Visual.MiniatureFit(model, display, box.CFrame, box.Size)
	-- Tagged (the model and every one of its real parts, since most objects are more than a single part) so
	-- SpectatorDisplayController (client-only) can hide the whole thing from the seated players at this
	-- table, while everyone else in the server still sees it normally; view[kind] keeps the whole model too,
	-- so hiding it later (match end, no pair) never leaves part of a multi-part object stuck visible.
	clone:SetAttribute("TableMiniature", true)
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("TableMiniature", true)
		end
	end
	view[kind] = clone
	view[kind .. "Part"] = miniaturePart(clone)
end
function TableDisplay.UpdateMiniatures(self: any, view: any, pair: any, frame: CFrame?, tableKey: Instance?)
	if not pair then
		return
	end
	local key = pair.ReferenceId .. ":" .. pair.TargetId
	if view.MiniatureKey == key then
		return
	end
	view.MiniatureKey = key
	if self.Visual and self.Visual.MiniatureFit then
		self:SetMiniature(view, pair, tableKey, "Reference")
		self:SetMiniature(view, pair, tableKey, "Target")
	end
end
function TableDisplay.UpdateHearts(self: any, view: any, record: any)
	-- This runs for every table at 20 Hz. Reuse the per-view set instead of producing one garbage table per update.
	local retained = view.RetainedHearts or {}
	view.RetainedHearts = retained
	table.clear(retained)
	for index, player in record.Players do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if
			head
			and head:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and seat
			and seat:IsDescendantOf(record.Key)
		then
			retained[player] = true
			local entry = view.Hearts[player]
			if not entry then
				local gui = Instance.new("BillboardGui")
				gui.Name = "Hearts_" .. tostring(player.UserId)
				gui.Adornee = head
				gui.Size = UDim2.fromOffset(180, 48)
				gui.MaxDistance = 55
				gui.Parent = view.Root
				local label = text(gui, "Text", UDim2.fromScale(1, 1))
				label.AnchorPoint = Vector2.new(0.5, 1)
				local name = text(label, "PlayerName", UDim2.fromScale(0.9, 0.45))
				name.Position = UDim2.fromScale(0.05, 0.08)
				name.TextSize = 13
				local hearts = {}
				for i = 1, 3 do
					local icon = text(label, "Heart" .. i, UDim2.fromScale(0.15, 0.45))
					icon.Position = UDim2.fromScale((i - 1) * 0.2 + 0.1, 0.5)
					icon.Text = "♥"
					icon.TextColor3 = heartColor
					icon.TextSize = 21
					table.insert(hearts, icon)
				end
				entry = { Gui = gui, Text = label, Name = name, Hearts = hearts, Head = head }
				view.Hearts[player] = entry
			end
			local count = if record.Match then record.Match.Hearts and record.Match.Hearts[index] or 0 else 3
			local cup = record.Match and record.Match.Mode == "BestOfFive"
			setText(
				entry.Name,
				player.DisplayName .. (if cup then " / " .. tostring(record.Match.Scores[index]) else "")
			)
			for i, icon in entry.Hearts do
				icon.Visible = not cup and i <= count
			end
		end
	end
	for player, entry in view.Hearts do
		if not retained[player] then
			entry.Gui:Destroy()
			view.Hearts[player] = nil
		end
	end
end
function TableDisplay.Update(self: any, record: any, now: number)
	local view = self:Add(record)
	if not view or not view.Root then
		return nil
	end
	local statusText = self:StatusText(record, now)
	view.StatusText.Text = statusText
	view.StatusText.BackgroundTransparency = 1
	view.StatusText.Font = Enum.Font.FredokaOne
	local match = record.Match
	if match and match.CurrentObjectPair then
		local pair = match.CurrentObjectPair
		view.Names.Enabled = true
		local actualText = if match.RoundState == "ROUND_REVEAL" and pair.Actual ~= nil
			then string.format("%.2f", pair.Actual) .. "m"
			else "???"
		view.NamesText.Text = tostring(pair.ReferenceId)
			.. " / "
			.. tostring(pair.TargetId)
			.. " ("
			.. actualText
			.. ")"
		local referencePart = view.ReferencePart
		local targetPart = view.TargetPart
		if pair.ReferenceHue and referencePart then
			referencePart.Color = Color3.fromHSV(pair.ReferenceHue, 0.65, 0.95)
		end
		if pair.TargetHue and targetPart then
			targetPart.Color = Color3.fromHSV(pair.TargetHue, 0.65, 0.95)
		end
		if match.RoundState == "MATCH_END" then
			-- The match is over (finished or cancelled early): hide and de-collide immediately, not just at
			-- cleanup -- the whole miniature (every part of it), not only the one part used for its colour.
			if view.MiniaturesVisible ~= false then
				setMiniatureVisible(view.Reference, false)
				setMiniatureVisible(view.Target, false)
				view.MiniaturesVisible = false
			end
			view.Names.Enabled = false
		else
			if view.MiniaturesVisible ~= true then
				setMiniatureVisible(view.Reference, true)
				setMiniatureVisible(view.Target, true)
				view.MiniaturesVisible = true
			end
		end
		self:UpdateMiniatures(view, pair, nil, record.Key)
	else
		if view.MiniaturesVisible ~= false then
			setMiniatureVisible(view.Reference, false)
			setMiniatureVisible(view.Target, false)
			view.MiniaturesVisible = false
		end
		view.Names.Enabled = false
		view.NamesText.Text = ""
		view.MiniatureKey = nil
	end
	if record.State == "COUNTDOWN" or record.State == "PRIZE_ROLL" or record.State == "GO" then
		view.PrizePad.Transparency = 0
		view.PrizeSurface.Enabled = true
		if record.State == "COUNTDOWN" then
			local value = "Starting in " .. math.max(0, math.ceil(record.Deadline - now)) .. "..."
			for _, label in view.PrizeLabels do
				setText(label, value)
			end
		elseif record.State == "PRIZE_ROLL" and record.Prize ~= nil then
			local elapsed = now - record.RollStarted
			local intro = math.min(1, record.RollDuration * 0.25)
			local value = if elapsed >= intro
				then money(
					if self.PrizeRoll
						then self.PrizeRoll.Amount(
							record.Prize,
							elapsed - intro,
							record.RollDuration - intro,
							self.Config.PrizeHoldSeconds
						)
						else record.Prize
				)
				else "Picking the prize..."
			for _, label in view.PrizeLabels do
				setText(label, value)
			end
		elseif record.State == "GO" then
			for _, label in view.PrizeLabels do
				setText(label, "GO!")
			end
		end
	else
		view.PrizePad.Transparency = 1
		view.PrizeSurface.Enabled = false
	end
	local authored = self:ResolveAuthored(record, view, now)
	if authored then
		self:ApplyAuthored(record, view, authored, statusText, now)
	end
	self:UpdateHearts(view, record)
	return view
end
function TableDisplay.Remove(self: any, record: any)
	local view = self.Views[record]
	if view then
		for _, entry in view.Hearts do
			if entry.Gui then
				entry.Gui:Destroy()
			end
		end
		-- Runtime display roots and miniature clones must not survive an unbound/removed table. Authored roots stay in
		-- place, but are returned to an inert state so removing a ScaleTable tag cannot leave stale signs or collisions.
		if view.OwnedRoot then
			if view.Root.Parent then view.Root:Destroy() end
		elseif view.Root.Parent then
			for _, key in { "Reference", "Target" } do
				local miniature = view[key]
				local authored = view.Root:FindFirstChild(key)
				if miniature and miniature ~= authored and miniature.Parent then miniature:Destroy() end
			end
			if view.Status then view.Status.Enabled = false end
			if view.Names then view.Names.Enabled = false end
			if view.PrizeSurface then view.PrizeSurface.Enabled = false end
			if view.PrizePad then view.PrizePad.Transparency = 1 end
		end
		self.Views[record] = nil
	end
end
function TableDisplay.Tick(self: any, records: any, now: number)
	for record in self.Views do
		if records[record.Key] ~= record or record.Removed then
			self:Remove(record)
		end
	end
	for _, record in records do
		if record.Removed then
			continue
		end
		local ok, err = pcall(function()
			self:Update(record, now)
		end)
		if not ok then
			local view = self.Views[record]
			if not view or not view.Warned then
				warn("Scale It Up table display: " .. tostring(err))
				if view then
					view.Warned = true
				end
			end
		end
	end
end
function TableDisplay.Destroy(self: any)
	for record in self.Views do
		self:Remove(record)
	end
end
return TableDisplay

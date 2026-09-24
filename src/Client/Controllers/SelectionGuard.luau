--!strict
-- Roblox draws a white selection outline around whichever button becomes GuiService.SelectedObject, and a click can
-- select it. This game has no gamepad menu navigation, so a selection is cleared the instant it happens.
local SelectionGuard = {}
SelectionGuard.__index = SelectionGuard

-- Nothing in the HUD can be selected, and any selection border that would be drawn is an invisible image.
local blank: Frame? = nil
local function quiet(item: Instance)
	if item:IsA("GuiObject") then
		item.Selectable = false
		if blank then item.SelectionImageObject = blank end
	end
end

function SelectionGuard.new(guiService: GuiService, playerGui: Instance?, input: any?)
	local self: any = setmetatable({ Service = guiService, Connection = nil, Added = nil, Clicks = nil }, SelectionGuard)
	-- Whatever a click or touch selects is un-selected the same frame, so no selection border can ever be drawn.
	if input then
		self.Clicks = { input.InputBegan:Connect(function() if guiService.SelectedObject ~= nil then guiService.SelectedObject = nil end end),
			input.InputEnded:Connect(function() if guiService.SelectedObject ~= nil then guiService.SelectedObject = nil end end) }
	end
	if playerGui then
		pcall(function()
			local hidden = Instance.new("Frame")
			hidden.Name, hidden.BackgroundTransparency, hidden.BorderSizePixel = "NoSelection", 1, 0
			blank = hidden
			for _, item in playerGui:GetDescendants() do quiet(item) end
			self.Added = playerGui.DescendantAdded:Connect(quiet)
		end)
	end
	local ok, signal = pcall(function() return guiService:GetPropertyChangedSignal("SelectedObject") end)
	if ok and signal then
		self.Connection = signal:Connect(function()
			if guiService.SelectedObject ~= nil then guiService.SelectedObject = nil end
		end)
	end
	if guiService.SelectedObject ~= nil then guiService.SelectedObject = nil end
	return self
end

function SelectionGuard.Destroy(self: any)
	if self.Connection then self.Connection:Disconnect();self.Connection = nil end
	if self.Added then self.Added:Disconnect();self.Added = nil end
	for _, connection in self.Clicks or {} do connection:Disconnect() end
	self.Clicks = nil
end

return SelectionGuard

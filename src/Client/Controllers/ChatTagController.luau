--!strict
-- Puts a gold [VIP] in front of VIP players' and the owner's chat messages, and
-- keeps our server announcements at the ordinary chat-message text size.
-- Saved VIP comes from the server attribute; the owner also has an automatic cosmetic tag.
local ChatTagController = {}

local TAG = '<font color="#FFC800">[VIP]</font> '
local OWNER_USER_ID = 1790165114
local SERVER_MESSAGE_METADATA = "ScaleItUpServerMessage"

local function normalSize(configuration: any): number
	local ok, size = pcall(function()
		return configuration.TextSize
	end)
	return if ok and type(size) == "number" then math.max(1, math.round(size)) else 18
end

function ChatTagController.new(textChat: any, players: any)
	local self = { Destroyed = false }
	-- Decorate the final chat-window prefix after channel formatting. Callback members are write-only.
	local configuration = textChat.ChatWindowConfiguration
	textChat.OnChatWindowAdded = function(message: any)
		local properties = configuration:DeriveNewMessageProperties()
		if message.Metadata == SERVER_MESSAGE_METADATA and message.Text ~= "" then
			properties.Text = string.format('<font size="%d">%s</font>', normalSize(configuration), message.Text)
		end
		local source = message.TextSource
		local sender = source and players:GetPlayerByUserId(source.UserId)
		local hasTag = source and (source.UserId == OWNER_USER_ID or (sender and sender:GetAttribute("VIP") == true))
		if hasTag and message.PrefixText ~= "" and not string.find(message.PrefixText, TAG, 1, true) then
			properties.PrefixText = TAG .. message.PrefixText
		end
		return properties
	end
	function self.Destroy()
		if self.Destroyed then
			return
		end
		self.Destroyed = true
		textChat.OnChatWindowAdded = nil
	end
	return self
end

return ChatTagController

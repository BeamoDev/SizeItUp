--!strict
-- Shows server chat news (beat announcements, win and streak milestones) as system messages in the chat.
local ChatNewsController = {}

-- ChatTagController uses this metadata to give local server announcements the same
-- text size as an ordinary player message instead of Roblox's smaller system style.
ChatNewsController.Metadata = "ScaleItUpServerMessage"

function ChatNewsController.new(remote: any, textChat: any, format: (any) -> string?)
	local self = { Destroyed = false }
	local connection = remote.OnClientEvent:Connect(function(packet: any)
		local text = format(packet)
		local channels = textChat:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild("RBXSystem")
		if text and channel then
			pcall(function()
				channel:DisplaySystemMessage(text, ChatNewsController.Metadata)
			end)
		end
	end)
	function self.Destroy()
		if self.Destroyed then
			return
		end
		self.Destroyed = true
		connection:Disconnect()
	end
	return self
end

return ChatNewsController

--!strict
-- Milestone announcements for the chat: which moments are worth a message, and how one is worded.
-- The server decides and sends a small packet; the client turns it into text with Format.
local ChatNews = {}

ChatNews.WinMilestones = table.freeze({ 10, 25, 50, 100, 250, 500, 1000, 2500, 5000 })
ChatNews.StreakMilestones = table.freeze({ 5, 10, 25, 50, 100 })
-- "X just beat Y" only shows for a beaten player with a real record, so routine matches stay quiet.
ChatNews.BeatMinimumWins = 10
ChatNews.BeatMinimumStreak = 3

-- The highest milestone passed when a counter goes from before to after (potions can skip values).
function ChatNews.Crossed(milestones: {number}, before: number, after: number): number?
	local found: number? = nil
	for _, milestone in milestones do
		if before < milestone and after >= milestone then found = milestone end
	end
	return found
end

-- Whether beating this player deserves an announcement, using their record before the match settled.
function ChatNews.BeatWorthy(loserWins: number, loserStreak: number): boolean
	return loserWins >= ChatNews.BeatMinimumWins or loserStreak >= ChatNews.BeatMinimumStreak
end

local function clean(name: any): string
	return (tostring(name):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }))
end
local function gold(text: string): string return '<font color="#FFC800">' .. text .. "</font>" end
local rarityColors = {
	Common = "#D5D5DF", Uncommon = "#6FE28C", Rare = "#62D7FF", Epic = "#C184FF",
	Legendary = "#FFC83D", Mythic = "#FF69D4",
}
local function reward(text: string, rarity: any): string
	local color = rarityColors[rarity] or "#FFC800"
	return '<font color="' .. color .. '">' .. clean(text) .. "</font>"
end

local function comma(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then break end
	end
	return text
end

-- Text for a packet, or nil when the packet is malformed. Names are escaped; Beat may carry the beaten player's Streak.
function ChatNews.Format(packet: any): string?
	if type(packet) ~= "table" or type(packet.Name) ~= "string" then return nil end
	local name = gold(clean(packet.Name))
	if packet.Kind == "Beat" and type(packet.Other) == "string" then
		local streak = packet.Streak
		if type(streak) == "number" and streak >= ChatNews.BeatMinimumStreak then
			return name .. " just beat " .. clean(packet.Other) .. " and ended their " .. comma(streak) .. " win streak!"
		end
		return name .. " just beat " .. clean(packet.Other) .. "!"
	elseif packet.Kind == "Wins" and type(packet.Count) == "number" then
		return name .. " reached " .. gold(comma(packet.Count) .. " wins") .. "!"
	elseif packet.Kind == "Streak" and type(packet.Count) == "number" then
		return name .. " is on a " .. gold(comma(packet.Count) .. " win streak") .. "!"
	elseif packet.Kind == "BotPet" and type(packet.Item) == "string" then
		return name .. " just rolled a " .. reward(packet.Item, packet.Rarity) .. " pet!"
	elseif packet.Kind == "BotChair" and type(packet.Item) == "string" then
		return name .. " just bought the " .. reward(packet.Item, packet.Rarity) .. " chair!"
	elseif packet.Kind == "BotWin" then
		if type(packet.Count) == "number" and packet.Count >= 3 then
			return name .. " just won a match and reached a " .. gold(comma(packet.Count) .. " win streak") .. "!"
		end
		return name .. " just won a match!"
	end
	return nil
end

return ChatNews

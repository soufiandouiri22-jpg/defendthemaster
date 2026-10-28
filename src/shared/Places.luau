-- Which part of the experience runs here (Config.Places): the lobby with the menu, where every player comes in after
-- the loading screen, or a match. Both carry the same code. In Studio Play opens the lobby too, as for a player; the
-- Workspace attribute "Match" opens the arena instead, to test a match straight away.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local Places = {}

function Places.isLobby(): boolean
	if RunService:IsStudio() then
		return Workspace:GetAttribute("Match") ~= true
	end
	local lobby, match = Config.Places.Lobby, Config.Places.Match
	if lobby ~= match then
		return game.PlaceId == lobby
	end
	-- One place for both: its matches run in reserved servers (QueueService), its public and VIP servers are the lobby.
	return not (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)
end

-- Whether players can be sent between the lobby and the matches: only in the published game.
function Places.canTeleport(): boolean
	return not RunService:IsStudio() and Config.Places.Lobby ~= nil and Config.Places.Match ~= nil
end

return Places

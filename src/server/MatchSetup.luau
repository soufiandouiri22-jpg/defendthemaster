-- Who plays this match. A match from the queue runs on a reserved server (QueueService), whose record in the
-- MemoryStore hash map "Matches" (keyed by the server's PrivateServerId) holds its mode and teams: only its players
-- are let in, each on his team (the "Team" attribute), and the match waits up to Config.Draft.Arrive seconds for them;
-- whoever did not come is played by a bot. Without a record (Studio, or the match place before the lobby exists) it is
-- a match of whoever comes in, all on Blue, in Quick Play (in Studio the Workspace attribute "Mode" may say "Ranked").
-- Someone who comes into the match place on his own once the lobby exists is sent there.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)
local ProfileService = require(script.Parent.ProfileService)

local MatchSetup = {}

export type Record = {
	mode: string,
	teams: { [string]: { number } },
	parties: { { number } }?,
}

export type Slot = {
	key: string,
	team: string,
	index: number,
	player: Player?,
	userId: number,
	name: string,
}

local record: Record? = nil
local teamOf: { [number]: string } = {}
local mode = "QuickPlay"

local function readRecord(id: string): Record?
	local map = MemoryStoreService:GetHashMap("Matches")
	for _ = 1, 6 do
		local ok, value = pcall(map.GetAsync, map, id)
		if ok and value then
			return value
		end
		task.wait(1.5)
	end
	return nil
end

local function admit(player: Player)
	if record then
		local team = teamOf[player.UserId]
		if not team then
			player:Kick("This match is not yours.")
			return
		end
		player:SetAttribute("Team", team)
	elseif Places.canTeleport() then
		pcall(TeleportService.TeleportAsync, TeleportService, Config.Places.Lobby :: number, { player })
	else
		player:SetAttribute("Team", "Blue")
	end
end

-- "QuickPlay" or "Ranked".
function MatchSetup.mode(): string
	return mode
end

-- Whether this match came from the queue.
function MatchSetup.queued(): boolean
	return record ~= nil
end

-- The party `userId` came with (all its members' ids), or just him.
function MatchSetup.partyOf(userId: number): { number }
	for _, party in record and record.parties or {} do
		if table.find(party, userId) then
			return party
		end
	end
	return { userId }
end

function MatchSetup.start()
	if game.PrivateServerId ~= "" then
		record = readRecord(game.PrivateServerId)
	end
	if record then
		mode = record.mode
		for team, ids in record.teams do
			for _, id in ids do
				teamOf[id] = team
			end
		end
	elseif RunService:IsStudio() and Workspace:GetAttribute("Mode") == "Ranked" then
		mode = "Ranked"
	end
	Workspace:SetAttribute("Mode", mode)
	Workspace:SetAttribute("Phase", "Waiting")
	Players.PlayerAdded:Connect(admit)
	for _, player in Players:GetPlayers() do
		task.spawn(admit, player)
	end
end

-- Waits for the match's players (and their data): all of them, or as many as come within Config.Draft.Arrive seconds;
-- without a record, for the first player.
function MatchSetup.awaitPlayers()
	local deadline = os.clock() + (if record then Config.Draft.Arrive else Config.Match.WaitForPlayer)
	while os.clock() < deadline do
		local present = 0
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Team") and ProfileService.get(player) then
				present += 1
			end
		end
		local expected = 0
		for _ in teamOf do
			expected += 1
		end
		if (record and present >= expected) or (not record and present > 0) then
			break
		end
		task.wait(0.25)
	end
end

-- The draft's eight places in Config.Draft.Order's names: each team's players first, then its bots.
function MatchSetup.slots(): { Slot }
	local byTeam: { [string]: { Player } } = {}
	for _, team in Config.TeamOrder do
		byTeam[team] = {}
	end
	for _, player in Players:GetPlayers() do
		local team = player:GetAttribute("Team")
		if team and byTeam[team] and #byTeam[team] < Config.HeroesPerTeam then
			table.insert(byTeam[team], player)
		end
	end
	local slots = {}
	for _, key in Config.Draft.Order do
		local team, index = string.match(key, "^(%a+)(%d+)$")
		local n = tonumber(index) :: number
		local player = byTeam[team :: string][n]
		table.insert(slots, {
			key = key,
			team = team :: string,
			index = n,
			player = player,
			userId = if player then player.UserId else 0,
			name = if player then player.DisplayName else "Bot",
		})
	end
	return slots
end

return MatchSetup

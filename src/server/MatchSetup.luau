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
local Remote = require(script.Parent.Remote)
local TraceService = require(script.Parent.TraceService)

local MatchSetup = {}

export type Record = {
	mode: string,
	teams: { [string]: { number } },
	parties: { { number } }?,
	seed: number?,
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
local ownSeed = Random.new():NextInteger(1, 2 ^ 30)

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
			TraceService.mark("match.kick", nil, player)
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

-- What shuffles the bots' heroes (Shared.Lineup.botOrder): the lobby's from the record, else this server's own.
function MatchSetup.seed(): number
	return record and record.seed or ownSeed
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
		local reading = os.clock()
		record = readRecord(game.PrivateServerId)
		TraceService.mark("match.record", {
			found = record ~= nil,
			mode = if record then record.mode else nil,
			took = math.floor((os.clock() - reading) * 100) / 100,
		})
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
	Remote.event("ClientReady", 1, function(player)
		player:SetAttribute("Loaded", 1)
		player:SetAttribute("ClientReady", true)
	end)
	-- How far a player's loading screen is (0 to 1), for everyone's cards (VersusView).
	Remote.event("LoadProgress", 8, function(player, share)
		if typeof(share) == "number" and share == share and not player:GetAttribute("ClientReady") then
			player:SetAttribute("Loaded", math.clamp(math.floor(share * 100 + 0.5) / 100, 0, 1))
		end
	end)
	Players.PlayerAdded:Connect(admit)
	for _, player in Players:GetPlayers() do
		task.spawn(admit, player)
	end
end

-- The moment the waiting for the match's players ends, shared by MatchSetup.awaitArrivals and awaitPlayers:
-- Config.Draft.Arrive seconds after the first wait began, without a record Config.Match.WaitForPlayer.
local deadline: number? = nil

-- Waits until every one of the match's players is in with his data and `ready` says so of him, or until the deadline;
-- without a record, for the first player.
local function await(ready: (Player) -> boolean)
	deadline = deadline or os.clock() + (if record then Config.Draft.Arrive else Config.Match.WaitForPlayer)
	while os.clock() < (deadline :: number) do
		local present = 0
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Team") and ProfileService.get(player) and ready(player) then
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

-- Waits for the match's players to be in with their data, so who plays and with which hero is known (the cards while
-- the match loads show it while they are still loading).
function MatchSetup.awaitArrivals()
	await(function()
		return true
	end)
end

-- Waits for the match's players, their data and their clients, which say so once they have everything in under the
-- loading screen ("ClientReady"): all of them, or as many as are ready within Config.Draft.Arrive seconds; without a
-- record, for the first player. So the draft and its clock start when everyone can see it.
function MatchSetup.awaitPlayers()
	await(function(player)
		return player:GetAttribute("ClientReady") == true
	end)
end

-- The draft's eight places in Config.Draft.Order's names: each team's players first, in the record's order (as the
-- lobby showed their cards, Shared.Lineup), then its bots.
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
	if record then
		for team, list in byTeam do
			local order = record.teams[team] or {}
			table.sort(list, function(a, b)
				return (table.find(order, a.UserId) or math.huge) < (table.find(order, b.UserId) or math.huge)
			end)
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

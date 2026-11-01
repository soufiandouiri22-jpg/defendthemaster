-- The queue (Net.Queue, Config.Queue): a party's leader puts it in for Quick Play or Ranked, and it waits for a match.
-- Every lobby server keeps its waiting parties in the MemoryStore sorted map "Queue_<mode>" (by when they came in,
-- with the party's ids and average hidden rating); one lobby at a time holds the matchmaker's lock and makes matches
-- out of all of them: from the party that waited longest, parties within its window of rating (Window, Grow more for
-- every second it waited), on two teams of Config.HeroesPerTeam, a party always together. When both teams are full,
-- or the longest waited FillAfter seconds (in Ranked only once both teams have RankedHumans players), it reserves a
-- server of the match place, writes the match's record (MatchSetup reads it there) and every player's assignment, and
-- takes the parties out of the queue. Each lobby sends its own players to their match as soon as it sees their
-- assignment, after their clients have shown the match's cards ("Lineup", from the cards every party brought into the
-- queue) and sent them along as their teleport's screen (VersusView.travel). In Studio (no teleports) the queue runs in
-- this server alone and only shows the cards and says a match was found.
-- It runs in a match as well (owner, 2026-11-01): Play Again on the end screen queues the party from there (MatchEnd),
-- its cards come over the end screen and it goes straight to the next match, without the lobby in between. Who is in
-- a party comes from the lobby's PartyService there, from MatchEnd here; a match server only matchmakes while some
-- of its players search, a lobby always.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lineup = require(ReplicatedStorage.Shared.Lineup)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local Places = require(ReplicatedStorage.Shared.Places)
local Profile = require(ReplicatedStorage.Shared.Profile)
local ProfileService = require(script.Parent.ProfileService)
local Remote = require(script.Parent.Remote)
local TraceService = require(script.Parent.TraceService)

local QueueService = {}

-- Who searches together: the party `player` is in, as its leader's id (the one who queues it) and its members in this
-- server; and, where parties can change while they search, a way to hear of it.
export type Parties = {
	partyOf: (player: Player) -> (number, { Player }),
	onChanged: ((callback: (leader: number) -> ()) -> ())?,
}
local partyInfo: Parties

local SETTINGS = Config.Queue
local TEAM = Config.HeroesPerTeam
-- How long a queue entry and an assignment live in the MemoryStore without being renewed, and how often they are.
local ENTRY_LIFE, RENEW = 90, 20
local MATCH_LIFE = 3600
local LOCK_LIFE = 12
local MATCHMAKE_EVERY, ASSIGNMENT_EVERY = 3, 1.5
local TELEPORT_TRIES = 3
-- How long a found match waits for its players' clients to show its cards and send them along as their teleport's
-- screen (VersusView.travel, "Prepared") before it teleports them anyway.
local PREPARE = 5

-- A party in the queue: its players' ids, average hidden rating, since when, its lobby server, and its players' cards
-- (Shared.Lineup, by their ids as strings) for the lineup every player of the match sees before his teleport.
type Entry = { ids: { number }, rating: number, at: number, job: string, cards: { [string]: Lineup.Card }? }
type Search = { mode: string, since: number, ids: { number }, renewed: number, found: boolean }

-- The parties of this server that wait, by their leader's id.
local searching: { [number]: Search } = {}
local localQueue: { [string]: { [string]: Entry } } = { QuickPlay = {}, Ranked = {} }
local rng = Random.new()
-- The players whose client has shown the found match's cards and sent them along ("Prepared").
local prepared: { [number]: boolean } = {}
local event: RemoteEvent

local online = Places.canTeleport()

local function playerOf(id: number): Player?
	return Players:GetPlayerByUserId(id)
end

local function send(leader: number, kind: string, payload: any, bad: boolean?)
	local player = playerOf(leader)
	if not player then
		return
	end
	local _, members = partyInfo.partyOf(player)
	for _, member in members do
		event:FireClient(member, kind, payload, bad)
	end
end

local function stateOf(leader: number): any
	local s = searching[leader]
	if not s then
		return { state = "Idle" }
	end
	return { state = if s.found then "Found" else "Searching", mode = s.mode, since = s.since }
end

-- Whether the party `leader` queued is "Idle", "Searching" or "Found" (being sent to its match).
function QueueService.state(leader: number): string
	return stateOf(leader).state
end

local function tell(leader: number)
	if playerOf(leader) then
		send(leader, "State", stateOf(leader))
	end
end

local function queueMap(mode: string): MemoryStoreSortedMap
	return MemoryStoreService:GetSortedMap("Queue_" .. mode)
end

local function retry<T>(fn: () -> T, tries: number?): (boolean, T?)
	for attempt = 1, tries or 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn("[QueueService]", result)
		task.wait(0.5 * attempt)
	end
	return false, nil
end

local function put(leader: number, s: Search)
	local entry: Entry = { ids = s.ids, rating = 0, at = s.since, job = game.JobId, cards = {} }
	local total = 0
	for _, id in s.ids do
		local p = playerOf(id)
		local data = p and ProfileService.get(p)
		total += if data then data.Rank.Rating else Config.Ranked.StartRating
		if p then
			(entry.cards :: any)[tostring(id)] = Lineup.card(p)
		end
	end
	entry.rating = total / math.max(1, #s.ids)
	if online then
		local map = queueMap(s.mode)
		retry(function()
			map:SetAsync(tostring(leader), entry, ENTRY_LIFE, s.since)
		end)
	else
		localQueue[s.mode][tostring(leader)] = entry
	end
	s.renewed = os.clock()
end

local function remove(leader: number, mode: string)
	if online then
		local map = queueMap(mode)
		retry(function()
			map:RemoveAsync(tostring(leader))
		end)
	else
		localQueue[mode][tostring(leader)] = nil
	end
end

-- Takes `leader`'s party out of the queue.
function QueueService.cancel(leader: number, why: string?)
	local s = searching[leader]
	if not s or s.found then
		return
	end
	searching[leader] = nil
	task.spawn(remove, leader, s.mode)
	tell(leader)
	if why then
		send(leader, "Notice", why, true)
	end
end

-- Puts `player`'s party in the queue for `mode`, when he leads it.
function QueueService.join(player: Player, mode: any)
	if typeof(mode) ~= "string" or not table.find(SETTINGS.Modes, mode) then
		return
	end
	local leader, members = partyInfo.partyOf(player)
	if leader ~= player.UserId then
		event:FireClient(player, "Notice", "Only the party's leader can start the queue.", true)
		return
	end
	if searching[leader] then
		return
	end
	local ids = {}
	local heroes = {}
	for _, member in members do
		local data = ProfileService.get(member)
		if not data then
			event:FireClient(player, "Notice", member.DisplayName .. "'s data is still loading.", true)
			return
		end
		table.insert(heroes, Profile.showcase(data))
		if mode == "Ranked" then
			local open, why = Ranks.unlocked(data)
			if not open then
				local who = if member == player then "" else member.DisplayName .. ": "
				event:FireClient(player, "Notice", who .. (why :: string), true)
				return
			end
		end
		table.insert(ids, member.UserId)
	end
	local clash = Lineup.clash(heroes)
	if clash then
		send(leader, "Notice", clash .. " twice in the party: pick different heroes.", true)
		return
	end
	local s: Search = { mode = mode, since = Workspace:GetServerTimeNow(), ids = ids, renewed = 0, found = false }
	searching[leader] = s
	tell(leader)
	task.spawn(put, leader, s)
end

-- The matchmaker: the match it makes out of `entries` (oldest first) at `now`, as the parties' keys and the teams,
-- or nil when none is ready.
local function makeMatch(
	mode: string,
	entries: { { key: string, value: Entry } },
	now: number
): ({ string }?, { [string]: { number } }?, { { number } }?)
	if #entries == 0 then
		return nil
	end
	local anchor = entries[1].value
	local waited = now - anchor.at
	local window = SETTINGS.Window + SETTINGS.Grow * waited
	if mode == "QuickPlay" then
		window *= 3
	end
	local teams = { Blue = {}, Red = {} }
	local keys, parties = {}, {}
	for _, entry in entries do
		local e = entry.value
		if math.abs(e.rating - anchor.rating) <= window and #e.ids <= TEAM then
			local into = if #teams.Blue <= #teams.Red then "Blue" else "Red"
			if #teams[into] + #e.ids > TEAM then
				into = if into == "Blue" then "Red" else "Blue"
			end
			if #teams[into] + #e.ids <= TEAM then
				for _, id in e.ids do
					table.insert(teams[into], id)
				end
				table.insert(keys, entry.key)
				table.insert(parties, e.ids)
				if #teams.Blue == TEAM and #teams.Red == TEAM then
					break
				end
			end
		end
	end
	local full = #teams.Blue == TEAM and #teams.Red == TEAM
	if not full then
		if waited < SETTINGS.FillAfter then
			return nil
		end
		if mode == "Ranked" and (#teams.Blue < SETTINGS.RankedHumans or #teams.Red < SETTINGS.RankedHumans) then
			return nil
		end
	end
	return keys, teams, parties
end

-- The cards of the parties `keys` among `entries`.
local function cardsOf(entries: { { key: string, value: Entry } }, keys: { string }): { [string]: Lineup.Card }
	local cards = {}
	for _, entry in entries do
		if table.find(keys, entry.key) then
			for id, card in entry.value.cards or {} do
				cards[id] = card
			end
		end
	end
	return cards
end

-- The lineup the match's players see before their teleport (VersusView.travel), with the `seed` of its bots' heroes.
local function lineupOf(
	mode: string,
	teams: { [string]: { number } },
	cards: { [string]: Lineup.Card },
	seed: number
): any
	return { mode = mode, teams = teams, cards = cards, seed = seed }
end

-- Reserves the match's server and hands out the assignments, with the lineup.
local function startMatch(
	mode: string,
	keys: { string },
	teams: { [string]: { number } },
	parties: { { number } },
	cards: { [string]: Lineup.Card }
)
	local ok, code, privateId = pcall(TeleportService.ReserveServer, TeleportService, Config.Places.Match :: number)
	if not ok or not code then
		warn("[QueueService] ReserveServer failed:", code)
		return
	end
	local seed = rng:NextInteger(1, 2 ^ 30)
	local record = { mode = mode, teams = teams, parties = parties, seed = seed }
	local matches = MemoryStoreService:GetHashMap("Matches")
	local written = retry(function()
		matches:SetAsync(privateId, record, MATCH_LIFE)
	end)
	if not written then
		return
	end
	local assignments = MemoryStoreService:GetHashMap("Assignments")
	local assignment = {
		code = code,
		mode = mode,
		id = HttpService:GenerateGUID(false),
		at = Workspace:GetServerTimeNow(),
		lineup = lineupOf(mode, teams, cards, seed),
	}
	for _, ids in teams do
		for _, id in ids do
			retry(function()
				assignments:SetAsync(tostring(id), assignment, ENTRY_LIFE)
			end)
		end
	end
	local map = queueMap(mode)
	for _, key in keys do
		retry(function()
			map:RemoveAsync(key)
		end)
	end
end

local function holdLock(mode: string): boolean
	local locks = MemoryStoreService:GetHashMap("QueueLock")
	local now = os.time()
	local ok, held = pcall(locks.UpdateAsync, locks, mode, function(old)
		if old and old.job ~= game.JobId and old.untilAt > now then
			return nil
		end
		return { job = game.JobId, untilAt = now + LOCK_LIFE - 2 }
	end, LOCK_LIFE)
	return ok and held ~= nil and held.job == game.JobId
end

local function matchmakeOnline(mode: string)
	if not holdLock(mode) then
		return
	end
	local map = queueMap(mode)
	local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 100)
	if not ok or not items then
		return
	end
	local entries = {}
	for _, item in items do
		table.insert(entries, { key = item.key, value = item.value })
	end
	local now = Workspace:GetServerTimeNow()
	for _ = 1, 5 do
		local keys, teams, parties = makeMatch(mode, entries, now)
		if not keys then
			break
		end
		startMatch(mode, keys, teams :: any, parties :: any, cardsOf(entries, keys))
		local rest = {}
		for _, entry in entries do
			if not table.find(keys, entry.key) then
				table.insert(rest, entry)
			end
		end
		entries = rest
	end
end

-- How far each of this server's parties searching for `mode` is, told to its players ("Filled": found of a match's
-- players, for the end screen's line, owner 2026-11-01): the players of the queue (`entries`, its own among them) within
-- its window of rating as makeMatch's grows with how long it waited, at most a match's.
local function report(mode: string)
	local mine = false
	for _, s in searching do
		mine = mine or (not s.found and s.mode == mode)
	end
	if not mine then
		return
	end
	local entries: { { key: string, value: Entry } } = {}
	if online then
		local map = queueMap(mode)
		local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 100)
		if not ok or not items then
			return
		end
		for _, item in items do
			table.insert(entries, { key = item.key, value = item.value })
		end
	else
		for key, value in localQueue[mode] do
			table.insert(entries, { key = key, value = value })
		end
	end
	local now = Workspace:GetServerTimeNow()
	for leader, s in searching do
		if not s.found and s.mode == mode then
			local own: Entry? = nil
			for _, entry in entries do
				if entry.key == tostring(leader) then
					own = entry.value
				end
			end
			local found = #s.ids
			if own then
				local window = SETTINGS.Window + SETTINGS.Grow * (now - own.at)
				if mode == "QuickPlay" then
					window *= 3
				end
				found = 0
				for _, entry in entries do
					if math.abs(entry.value.rating - own.rating) <= window then
						found += #entry.value.ids
					end
				end
			end
			send(leader, "Filled", { found = math.min(found, 2 * TEAM), of = 2 * TEAM })
		end
	end
end

-- In Studio: the match is only announced, since a reserved server cannot be reached from here.
local function matchmakeLocal(mode: string)
	local entries = {}
	for key, value in localQueue[mode] do
		table.insert(entries, { key = key, value = value })
	end
	table.sort(entries, function(a, b)
		return a.value.at < b.value.at
	end)
	local keys, teams = makeMatch(mode, entries, Workspace:GetServerTimeNow())
	local lineup = if keys and teams
		then lineupOf(mode, teams, cardsOf(entries, keys), rng:NextInteger(1, 2 ^ 30))
		else nil
	for _, key in keys or {} do
		local leader = tonumber(key) :: number
		localQueue[mode][key] = nil
		local s = searching[leader]
		if s then
			s.found = true
			tell(leader)
			-- Its cards show as they will before the teleport, for a look at them.
			send(leader, "Lineup", lineup)
			send(
				leader,
				"Notice",
				"Match found! Teleporting only works in the published game: in Studio, play the match place itself.",
				false
			)
			task.delay(4, function()
				searching[leader] = nil
				tell(leader)
			end)
		end
	end
end

local function teleport(leader: number, s: Search, assignment: any)
	local player = playerOf(leader)
	if not player then
		return
	end
	s.found = true
	tell(leader)
	local _, members = partyInfo.partyOf(player)
	local assignments = MemoryStoreService:GetHashMap("Assignments")
	for _, id in s.ids do
		pcall(assignments.RemoveAsync, assignments, tostring(id))
	end
	-- The cards first: each client shows them and sends them along as his teleport's screen, so the players see them
	-- from here until the fight.
	if assignment.lineup then
		for _, member in members do
			prepared[member.UserId] = nil
			event:FireClient(member, "Lineup", assignment.lineup)
		end
		local deadline = os.clock() + PREPARE
		while os.clock() < deadline do
			local all = true
			for _, member in members do
				if member.Parent and not prepared[member.UserId] then
					all = false
				end
			end
			if all then
				break
			end
			task.wait(0.1)
		end
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.code
	options:SetTeleportData({ mode = assignment.mode, party = leader, members = s.ids })
	for attempt = 1, TELEPORT_TRIES do
		local ok, err =
			pcall(TeleportService.TeleportAsync, TeleportService, Config.Places.Match :: number, members, options)
		if ok then
			TraceService.mark("queue.teleport", { mode = assignment.mode, players = #members, attempt = attempt })
			return
		end
		warn("[QueueService] teleport failed:", err)
		task.wait(attempt * 2)
	end
	searching[leader] = nil
	tell(leader)
	send(leader, "Notice", "Could not join the match. Try again.", true)
end

local function checkAssignments()
	local assignments = MemoryStoreService:GetHashMap("Assignments")
	for leader, s in searching do
		if not s.found then
			local ok, assignment = pcall(assignments.GetAsync, assignments, tostring(leader))
			if ok and assignment and (assignment.at or 0) >= s.since - 1 then
				task.spawn(teleport, leader, s, assignment)
			elseif os.clock() - s.renewed > RENEW then
				task.spawn(put, leader, s)
			end
		end
	end
end

function QueueService.start(given: Parties)
	partyInfo = given
	local lobby = Places.isLobby()
	event = Remote.event("Queue", 4, function(player, action, mode)
		if action == "Hello" then
			local leader = partyInfo.partyOf(player)
			event:FireClient(player, "State", stateOf(leader))
		elseif action == "Prepared" then
			prepared[player.UserId] = true
		elseif not lobby then
			-- In a match the end screen's buttons queue and cancel, through MatchEnd.
			return
		elseif action == "Join" then
			QueueService.join(player, mode)
		elseif action == "Cancel" then
			local leader = partyInfo.partyOf(player)
			if leader == player.UserId then
				QueueService.cancel(leader)
			end
		end
	end)
	if partyInfo.onChanged then
		partyInfo.onChanged(function(leader)
			QueueService.cancel(leader, "The party changed: the search stopped.")
		end)
	end
	-- A member who switches to a hero another member plays while they search stops the search.
	ProfileService.onChanged(function(player)
		local leader, members = partyInfo.partyOf(player)
		if not searching[leader] then
			return
		end
		local heroes = {}
		for _, member in members do
			local data = ProfileService.get(member)
			if data then
				table.insert(heroes, Profile.showcase(data))
			end
		end
		local clash = Lineup.clash(heroes)
		if clash then
			QueueService.cancel(leader, clash .. " twice in the party: the search stopped.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		prepared[player.UserId] = nil
		QueueService.cancel(player.UserId)
	end)
	TeleportService.TeleportInitFailed:Connect(function(player)
		local leader = partyInfo.partyOf(player)
		local s = searching[leader]
		if s and s.found then
			searching[leader] = nil
			tell(leader)
			event:FireClient(player, "Notice", "Could not join the match. Try again.", true)
		end
	end)
	local function anySearching(): boolean
		for _, s in searching do
			if not s.found then
				return true
			end
		end
		return false
	end
	task.spawn(function()
		while true do
			if lobby or anySearching() then
				for _, mode in SETTINGS.Modes do
					if online then
						matchmakeOnline(mode)
					else
						matchmakeLocal(mode)
					end
					report(mode)
				end
			end
			task.wait(MATCHMAKE_EVERY)
		end
	end)
	if online then
		task.spawn(function()
			while true do
				task.wait(ASSIGNMENT_EVERY)
				checkAssignments()
			end
		end)
	end
end

return QueueService

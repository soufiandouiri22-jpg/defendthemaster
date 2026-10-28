-- The ranked ladder (design 15): every ranked player's score (Shared.Ranks) in an OrderedDataStore of the season, and
-- its top 100 read every REFRESH seconds with the players' names, from which a Legend shows as Sunborn or Master
-- (Ranks.shown). The Friends tab reads the scores of a player's friends, at most FRIENDS of them, kept for a while.
-- Without DataStore access (Studio) the ladder holds only the scores written on this server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)

local Ladder = {}

local REFRESH = 120
local TOP = 100
local FRIENDS = 30
local FRIENDS_KEEP = 300

export type Entry = { userId: number, name: string, score: number, position: number? }

local store: OrderedDataStore? = nil
local local_: { [number]: number } = {}
local top: { Entry } = {}
local positions: { [number]: number } = {}
local names: { [number]: string } = {}
local friendCache: { [number]: { at: number, list: { Entry } } } = {}
local refreshed: { () -> () } = {}

-- Runs `callback` whenever the top was read again.
function Ladder.onRefreshed(callback: () -> ())
	table.insert(refreshed, callback)
end

local function storeOf(): OrderedDataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("Ladder_S" .. Config.Season.Number)
	end)
	store = if ok then result else nil
	return store
end

local function lookUpNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
	for _, id in missing do
		if not names[id] then
			local player = Players:GetPlayerByUserId(id)
			names[id] = if player then player.DisplayName else "Player"
		end
	end
end

local function rebuild(entries: { { userId: number, score: number } })
	table.sort(entries, function(a, b)
		return a.score > b.score
	end)
	local ids = {}
	for i = 1, math.min(TOP, #entries) do
		table.insert(ids, entries[i].userId)
	end
	lookUpNames(ids)
	local list, at = {}, {}
	for i, id in ids do
		table.insert(list, { userId = id, name = names[id], score = entries[i].score, position = i })
		at[id] = i
	end
	top, positions = list, at
	for _, callback in refreshed do
		task.spawn(callback)
	end
end

local function refresh()
	local ordered = storeOf()
	local entries = {}
	local ok = ordered ~= nil
		and pcall(function()
			local pages = (ordered :: OrderedDataStore):GetSortedAsync(false, TOP)
			for _, item in pages:GetCurrentPage() do
				table.insert(entries, { userId = tonumber(item.key) :: number, score = item.value })
			end
		end)
	if not ok then
		entries = {}
		for id, score in local_ do
			table.insert(entries, { userId = id, score = score })
		end
	end
	rebuild(entries)
end

-- Writes `player`'s ladder score from his rank.
function Ladder.submit(player: Player, rank: Ranks.Rank)
	if not Ranks.placed(rank) then
		return
	end
	local score = Ranks.score(rank)
	local_[player.UserId] = score
	names[player.UserId] = player.DisplayName
	local ordered = storeOf()
	if ordered then
		task.spawn(function()
			local ok, err = pcall(ordered.SetAsync, ordered, tostring(player.UserId), score)
			if not ok then
				warn("[Ladder] could not save", player.UserId, err)
			end
		end)
	end
end

-- The top of the ladder.
function Ladder.top(): { Entry }
	return top
end

-- `userId`'s place in the top, if he is in it.
function Ladder.position(userId: number): number?
	return positions[userId]
end

-- `player`'s friends on the ladder, best first, with his own score among them.
function Ladder.friends(player: Player): { Entry }
	local cached = friendCache[player.UserId]
	if cached and os.clock() - cached.at < FRIENDS_KEEP then
		return cached.list
	end
	local ids = { player.UserId }
	pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		while #ids <= FRIENDS do
			for _, friend in pages:GetCurrentPage() do
				if #ids <= FRIENDS then
					table.insert(ids, friend.Id)
				end
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	local ordered = storeOf()
	local list = {}
	for _, id in ids do
		local score = local_[id]
		if score == nil and ordered then
			local ok, value = pcall(ordered.GetAsync, ordered, tostring(id))
			score = if ok then value else nil
		end
		if score then
			table.insert(list, { userId = id, name = "", score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	local idList = {}
	for _, entry in list do
		table.insert(idList, entry.userId)
	end
	lookUpNames(idList)
	for i, entry in list do
		entry.name = names[entry.userId]
		entry.position = i
	end
	friendCache[player.UserId] = { at = os.clock(), list = list }
	return list
end

function Ladder.start()
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

-- Reads the ladder again at once (after a match changed it on this server).
function Ladder.refreshSoon()
	task.spawn(refresh)
end

return Ladder

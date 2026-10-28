-- Parties in the lobby (Net.Party, design 10): up to Config.Queue.PartySize players who queue and play together, on one
-- team. A player alone is a party of one. The leader invites a player in this lobby; an invite lasts INVITE_TIME
-- seconds and only one of his own party's places. Roblox friends come in through Roblox's invite with the leader's id
-- and server in its LaunchData ("<userId>:<jobId>"): in the leader's server they join him at once, elsewhere they are
-- sent to it first. After a match the party comes back together (its ids in the TeleportData, MatchEnd): the first
-- lobby server one of them comes into is the party's home (the MemoryStore hash map "PartyHome") and whoever comes into
-- another is sent there. When the leader leaves, the longest member leads. Any change takes the party out of the queue (QueueService).

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)
local Remote = require(script.Parent.Parent.Remote)

local PartyService = {}

local INVITE_TIME = 30
-- How long a party's home server is kept for its members coming back from a match.
local HOME_LIFE = 180

-- Each party by its leader's id, its members' ids in the order they came (the leader first).
local parties: { [number]: { number } } = {}
local leaderOf: { [number]: number } = {}
-- invites[target][from] = when it runs out.
local invites: { [number]: { [number]: number } } = {}
local changed: { (leader: number) -> () } = {}
local event: RemoteEvent

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- The party `player` is in, as its leader's id and its members (players in this server).
function PartyService.partyOf(player: Player): (number, { Player })
	local leader = leaderOf[player.UserId] or player.UserId
	local list = {}
	for _, id in parties[leader] or { player.UserId } do
		local member = playerOf(id)
		if member then
			table.insert(list, member)
		end
	end
	return leader, list
end

function PartyService.isLeader(player: Player): boolean
	local leader = leaderOf[player.UserId]
	return leader == nil or leader == player.UserId
end

-- Runs `callback` with a party's leader id whenever that party changes.
function PartyService.onChanged(callback: (leader: number) -> ())
	table.insert(changed, callback)
end

local function describe(leader: number): any
	local members = {}
	for _, id in parties[leader] or { leader } do
		local p = playerOf(id)
		table.insert(members, {
			userId = id,
			name = if p then p.DisplayName else "?",
			level = p and p:GetAttribute("AccountLevel"),
			shown = p and p:GetAttribute("RankShown"),
			division = p and p:GetAttribute("RankDivision"),
		})
	end
	return { leader = if parties[leader] then leader else 0, members = members }
end

local function broadcast(leader: number)
	local state = describe(leader)
	for _, id in parties[leader] or { leader } do
		local p = playerOf(id)
		if p then
			event:FireClient(p, "State", state)
		end
	end
	for _, callback in changed do
		task.spawn(callback, leader)
	end
end

local function notice(player: Player?, text: string, bad: boolean?)
	if player then
		event:FireClient(player, "Notice", text, bad)
	end
end

-- Takes `userId` out of his party; the party carries on under its next member, and dissolves at one.
local function leave(userId: number)
	local leader = leaderOf[userId]
	if not leader then
		return
	end
	local members = parties[leader]
	leaderOf[userId] = nil
	local index = table.find(members, userId)
	if index then
		table.remove(members, index)
	end
	parties[leader] = nil
	if #members <= 1 then
		for _, id in members do
			leaderOf[id] = nil
			local p = playerOf(id)
			if p then
				event:FireClient(p, "State", describe(id))
			end
		end
		for _, callback in changed do
			task.spawn(callback, leader)
		end
	else
		local newLeader = members[1]
		parties[newLeader] = members
		for _, id in members do
			leaderOf[id] = newLeader
		end
		broadcast(newLeader)
		if newLeader ~= leader then
			for _, callback in changed do
				task.spawn(callback, leader)
			end
		end
	end
	local p = playerOf(userId)
	if p and p.Parent then
		event:FireClient(p, "State", describe(userId))
	end
end

-- Puts `userId` in the party of `leader`; false when it is full.
local function join(userId: number, leader: number): boolean
	if leaderOf[userId] == leader then
		return true
	end
	local members = parties[leader] or { leader }
	if #members >= Config.Queue.PartySize then
		return false
	end
	leave(userId)
	parties[leader] = members
	leaderOf[leader] = leader
	table.insert(members, userId)
	leaderOf[userId] = leader
	broadcast(leader)
	return true
end

local function invite(from: Player, targetId: any)
	if typeof(targetId) ~= "number" then
		return
	end
	local target = playerOf(targetId)
	if not target or target == from then
		return
	end
	if not PartyService.isLeader(from) then
		notice(from, "Only the party's leader can invite.", true)
		return
	end
	local _, members = PartyService.partyOf(from)
	if #members >= Config.Queue.PartySize then
		notice(from, "Your party is full.", true)
		return
	end
	invites[targetId] = invites[targetId] or {}
	invites[targetId][from.UserId] = os.clock() + INVITE_TIME
	event:FireClient(target, "Invited", { from = from.UserId, name = from.DisplayName })
	notice(from, "Invite sent to " .. target.DisplayName .. ".", false)
end

local function accept(player: Player, fromId: any)
	local pending = invites[player.UserId]
	local expires = typeof(fromId) == "number" and pending and pending[fromId]
	if not expires or os.clock() > expires then
		notice(player, "That invite has run out.", true)
		return
	end
	pending[fromId] = nil
	local from = playerOf(fromId)
	if not from then
		notice(player, "That player has left.", true)
		return
	end
	local leader = leaderOf[fromId] or fromId
	if not join(player.UserId, leader) then
		notice(player, "That party is full.", true)
		return
	end
	notice(from, player.DisplayName .. " joined your party.", false)
end

local function decline(player: Player, fromId: any)
	local pending = invites[player.UserId]
	if typeof(fromId) == "number" and pending and pending[fromId] then
		pending[fromId] = nil
		notice(playerOf(fromId), player.DisplayName .. " declined your invite.", true)
	end
end

local function kick(player: Player, targetId: any)
	if typeof(targetId) ~= "number" or targetId == player.UserId then
		return
	end
	if leaderOf[player.UserId] == player.UserId and leaderOf[targetId] == player.UserId then
		leave(targetId)
		notice(playerOf(targetId), "You were removed from the party.", true)
	end
end

-- The server party `key` comes home to: this one unless another took it first.
local function home(key: number): string
	local map = MemoryStoreService:GetHashMap("PartyHome")
	local ok, job = pcall(map.UpdateAsync, map, tostring(key), function(old)
		return old or game.JobId
	end, HOME_LIFE)
	return if ok and typeof(job) == "string" then job else game.JobId
end

-- Sends `player` to the lobby server `job` with `teleport` as his TeleportData.
local function forward(player: Player, job: string, teleport: { [string]: any })
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = job
	teleport.forwarded = true
	options:SetTeleportData(teleport)
	pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
end

-- A player who came in from a friend's invite or back from a match finds his party again.
local function arrived(player: Player)
	local data = player:GetJoinData()
	local teleport = data and data.TeleportData
	if typeof(teleport) == "table" and typeof(teleport.party) == "number" then
		local leader = teleport.party
		if not teleport.forwarded and teleport.members and Places.canTeleport() then
			local job = home(leader)
			if job ~= game.JobId then
				forward(player, job, teleport)
				return
			end
		end
		-- Whoever of the party is here first leads it until its leader comes.
		if playerOf(leader) and leader ~= player.UserId then
			join(player.UserId, leaderOf[leader] or leader)
		else
			for _, id in teleport.members or {} do
				if typeof(id) == "number" and id ~= player.UserId and playerOf(id) and (leaderOf[id] or id) == id then
					join(id, player.UserId)
				end
			end
		end
		return
	end
	local launch = data and data.LaunchData
	if typeof(launch) ~= "string" or launch == "" then
		return
	end
	local leaderText, job = string.match(launch, "^(%d+):?(.*)$")
	local leader = tonumber(leaderText)
	if not leader or leader == player.UserId then
		return
	end
	if playerOf(leader) then
		if not join(player.UserId, leaderOf[leader] or leader) then
			notice(player, "That party is full.", true)
		end
	elseif job and job ~= "" and job ~= game.JobId and Places.canTeleport() then
		forward(player, job, { party = leader })
	end
end

function PartyService.start()
	event = Remote.event("Party", 6, function(player, action, value)
		if action == "Hello" then
			event:FireClient(player, "State", describe(leaderOf[player.UserId] or player.UserId))
		elseif action == "Invite" then
			invite(player, value)
		elseif action == "Accept" then
			accept(player, value)
		elseif action == "Decline" then
			decline(player, value)
		elseif action == "Leave" then
			leave(player.UserId)
		elseif action == "Kick" then
			kick(player, value)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.defer(arrived, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player.UserId)
		invites[player.UserId] = nil
	end)
	-- A member's rank or level changes (his profile loads): his party sees it.
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("ProfileLoaded"):Connect(function()
			local leader = leaderOf[player.UserId]
			if leader then
				broadcast(leader)
			end
		end)
	end)
end

return PartyService

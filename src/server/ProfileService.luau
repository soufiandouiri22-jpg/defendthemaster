-- Every player's saved data (Shared.Profile) in a ProfileStore (Lib/ProfileStore, Docs/Third_Party.md), in the lobby
-- and in a match alike: the store keeps one session per player, so his data is never open on two servers when he is
-- sent from one place to the other. Without DataStore access (Studio without API access) ProfileStore keeps it in
-- memory for the session. Only the server changes it (ProfileService.update), and every change goes to the player's
-- client (Net.Profile). What other players see of him (his level and rank) he carries as attributes.
-- A new season (Config.Season) pays the rank's season reward, lowers his rank and starts a new pass when he comes in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Account = require(ReplicatedStorage.Shared.Account)
local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.Profile)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local Ladder = require(script.Parent.Ladder)
local ProfileStore = require(script.Parent.ProfileStore)
local Remote = require(script.Parent.Remote)

local ProfileService = {}

local STORE = "Players_v1"

local store = ProfileStore.New(STORE, Profile.template())
local sessions: { [Player]: any } = {}
local waiting: { [Player]: { thread } } = {}
local leaving: { (player: Player, data: Profile.Data) -> () } = {}
local changed: { (player: Player, data: Profile.Data) -> () } = {}
local push: RemoteEvent

-- The tier others see on `player`, nil while he plays his placements (unranked).
local function shown(player: Player, rank: any): number?
	if not Ranks.placed(rank) then
		return nil
	end
	return Ranks.shown(rank, Ladder.position(player.UserId))
end

local function publish(player: Player, data: Profile.Data)
	player:SetAttribute("AccountLevel", (Account.level(data.Xp)))
	player:SetAttribute("RankTier", data.Rank.Tier)
	player:SetAttribute("RankDivision", data.Rank.Division)
	player:SetAttribute("RankLp", data.Rank.Lp)
	player:SetAttribute("RankShown", shown(player, data.Rank))
	player:SetAttribute("RankPlacements", data.Rank.Placements)
	player:SetAttribute("RankPosition", Ladder.position(player.UserId))
	push:FireClient(player, data)
	for _, callback in changed do
		task.spawn(callback, player, data)
	end
end

-- Pays the season reward of the best tier `data` reached, lowers its rank and starts the new season's pass.
local function newSeason(data: Profile.Data)
	local season = Config.Season.Number
	local rank = data.Rank
	if rank.Season < season then
		local coins = 0
		for _, reward in Config.Ranked.SeasonRewards do
			if rank.Peak >= reward.Tier then
				coins = reward.Coins
			end
		end
		data.Coins += coins
		Ranks.reset(rank)
		rank.Season = season
	end
	if data.Pass.Season < season then
		data.Pass = { Season = season, Xp = 0, Claimed = {}, BoostUntil = data.Pass.BoostUntil }
	end
end

local function load(player: Player)
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		if player.Parent == Players then
			player:Kick("Your data could not be loaded. Please rejoin.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		sessions[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	newSeason(profile.Data)
	sessions[player] = profile
	player:SetAttribute("ProfileLoaded", true)
	publish(player, profile.Data)
	for _, thread in waiting[player] or {} do
		task.spawn(thread)
	end
	waiting[player] = nil
end

-- `player`'s data, or nil while it loads.
function ProfileService.get(player: Player): Profile.Data?
	local profile = sessions[player]
	return profile and profile.Data
end

-- `player`'s data, waiting up to `timeout` seconds for it to load.
function ProfileService.await(player: Player, timeout: number?): Profile.Data?
	local data = ProfileService.get(player)
	if data or player.Parent ~= Players then
		return data
	end
	local thread = coroutine.running()
	waiting[player] = waiting[player] or {}
	table.insert(waiting[player], thread)
	task.delay(timeout or 30, function()
		local list = waiting[player]
		local index = list and table.find(list, thread)
		if index then
			table.remove(list :: { thread }, index)
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	return ProfileService.get(player)
end

-- Changes `player`'s data by `change` and tells his client; returns what `change` returns, or nil without data.
function ProfileService.update<T>(player: Player, change: (data: Profile.Data) -> T): T?
	local profile = sessions[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local result = change(profile.Data)
	publish(player, profile.Data)
	return result
end

-- Runs `callback` with a player's data as he leaves, before it is saved and let go.
function ProfileService.onLeaving(callback: (player: Player, data: Profile.Data) -> ())
	table.insert(leaving, callback)
end

-- Runs `callback` whenever a player's data changed.
function ProfileService.onChanged(callback: (player: Player, data: Profile.Data) -> ())
	table.insert(changed, callback)
end

function ProfileService.start()
	push = Remote.event("Profile", 4, function(player)
		local data = ProfileService.get(player)
		if data then
			push:FireClient(player, data)
		end
	end)
	Ladder.onRefreshed(function()
		for player, profile in sessions do
			local rank = profile.Data.Rank
			player:SetAttribute("RankShown", shown(player, rank))
			player:SetAttribute("RankPosition", Ladder.position(player.UserId))
		end
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = sessions[player]
		if not profile then
			return
		end
		for _, callback in leaving do
			local ok, err = pcall(callback, player, profile.Data)
			if not ok then
				warn("[ProfileService] leaving:", err)
			end
		end
		sessions[player] = nil
		profile:EndSession()
	end)
end

return ProfileService

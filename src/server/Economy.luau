-- Coins. Each player's coins are the server's attribute "Coins" on the Player, which the client only reads; every hero
-- starts with Config.Economy.StartCoins and, once the buy phase is over, earns Config.Economy.Passive every second,
-- also while dead.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Actors = require(script.Parent.Actors)
local MatchService = require(script.Parent.MatchService)

local Economy = {}

function Economy.coins(player: Instance): number
	return player:GetAttribute("Coins") or 0
end

-- Gives `amount` coins to `player`; `reason` is for the log.
function Economy.give(player: Instance, amount: number, reason: string)
	player:SetAttribute("Coins", Economy.coins(player) + amount)
	if player:IsA("Player") then
		print(string.format("[Economy] %s +%d coins (%s), now %d", player.Name, amount, reason, Economy.coins(player)))
	end
end

-- A new player or bot (Actors) starts with Config.Economy.StartCoins.
function Economy.join(player: Instance)
	if player:GetAttribute("Coins") == nil then
		player:SetAttribute("Coins", Config.Economy.StartCoins)
	end
end

function Economy.start()
	Players.PlayerAdded:Connect(Economy.join)
	for _, player in Players:GetPlayers() do
		Economy.join(player)
	end
	task.spawn(function()
		MatchService.awaitFight()
		while true do
			task.wait(1)
			for _, actor in Actors.all() do
				actor:SetAttribute("Coins", Economy.coins(actor) + Config.Economy.Passive)
			end
		end
	end)
end

return Economy

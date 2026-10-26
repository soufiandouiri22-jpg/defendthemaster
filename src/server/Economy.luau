-- Coins. Each player's coins are the server's attribute "Coins" on the Player, which the client only reads; every hero
-- starts with Config.Economy.StartCoins.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Economy = {}

function Economy.coins(player: Player): number
	return player:GetAttribute("Coins") or 0
end

-- Gives `amount` coins to `player`; `reason` is for the log.
function Economy.give(player: Player, amount: number, reason: string)
	player:SetAttribute("Coins", Economy.coins(player) + amount)
	print(string.format("[Economy] %s +%d coins (%s), now %d", player.Name, amount, reason, Economy.coins(player)))
end

function Economy.start()
	local function join(player: Player)
		if player:GetAttribute("Coins") == nil then
			player:SetAttribute("Coins", Config.Economy.StartCoins)
		end
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
end

return Economy

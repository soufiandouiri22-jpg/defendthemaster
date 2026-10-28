-- The menu's remotes in ReplicatedStorage.Net, each with a limit on how often one player may call it: a bucket of
-- `rate` calls a second that holds twice that, so a burst of clicks passes but a flood is dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remote = {}

local function net(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Net")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Net"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

local function limiter(rate: number): (player: Player) -> boolean
	local buckets: { [Player]: { tokens: number, at: number } } = {}
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
	return function(player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player] or { tokens = rate * 2, at = now }
		bucket.tokens = math.min(rate * 2, bucket.tokens + (now - bucket.at) * rate)
		bucket.at = now
		buckets[player] = bucket
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end
end

-- A RemoteEvent `name` whose calls from a client run `handler`, at most `rate` a second per player.
function Remote.event(name: string, rate: number, handler: ((player: Player, ...any) -> ())?): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = net()
	if handler then
		local allowed = limiter(rate)
		event.OnServerEvent:Connect(function(player, ...)
			if allowed(player) then
				handler(player, ...)
			end
		end)
	end
	return event
end

-- A RemoteFunction `name` answered by `handler`, at most `rate` calls a second per player; beyond that it answers
-- { ok = false, error = "Busy" }.
function Remote.func(name: string, rate: number, handler: (player: Player, ...any) -> any): RemoteFunction
	local func = Instance.new("RemoteFunction")
	func.Name = name
	func.Parent = net()
	local allowed = limiter(rate)
	func.OnServerInvoke = function(player, ...)
		if not allowed(player) then
			return { ok = false, error = "Busy" }
		end
		return handler(player, ...)
	end
	return func
end

return Remote

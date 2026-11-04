-- The game's log, to see from outside how a published game goes (owner, 2026-11-01): this server's marks
-- (TraceService.mark: who joins and leaves, phases, teleports, heroes), its errors and warnings, every STATS seconds
-- what its memory is spent on and every other time what its world holds (Memory), and what every
-- player's client marks (ReplicatedFirst.Trace, over Net.Trace), each with the server's clock. Every FLUSH seconds,
-- and as the server closes, what came in since goes as one entry into the DataStore STORE, keyed by the time, the
-- server and a count ("20261101-012345_1a2b3c4d_007"), which Tools/trace.py reads through Open Cloud and lays out
-- as one timeline. Not in Studio (no DataStores there): with the Workspace attribute "TracePrint" it prints instead.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Memory = require(ReplicatedFirst:WaitForChild("Memory"))
local Places = require(ReplicatedStorage.Shared.Places)
local Remote = require(script.Parent.Remote)

local TraceService = {}

local STORE = "Trace_v1"
local FLUSH = 60
-- How often the server's memory is marked.
local STATS = 30
-- How many entries wait at most (the oldest go first), how many one player may send in all, and how many warnings
-- this server marks.
local MOST, PER_PLAYER, WARNINGS = 6000, 3000, 300
-- What a client's entry may carry: this many fields, each name and text this long.
local FIELDS, NAME, TEXT = 12, 24, 300

local studio = RunService:IsStudio()
local server = if game.JobId ~= "" then string.sub(game.JobId, 1, 8) else "studio"
local entries: { any } = {}
local dropped = 0
local count = 0
local sent: { [Player]: number } = {}

local function add(entry: any)
	if #entries >= MOST then
		table.remove(entries, 1)
		dropped += 1
	end
	table.insert(entries, entry)
	if studio and Workspace:GetAttribute("TracePrint") == true then
		print("[Trace]", entry.p or "server", entry.k, if entry.d then HttpService:JSONEncode(entry.d) else "")
	end
end

-- Marks `kind` (a short dotted name, "hero.spawn") with `data` (a flat table) at this moment, for `player` if it
-- concerns one.
function TraceService.mark(kind: string, data: { [string]: any }?, player: Player?)
	add({ t = Workspace:GetServerTimeNow(), p = if player then player.UserId else nil, k = kind, d = data })
end

-- A client's entry, if it is one, with only what may go into the log.
local function clean(raw: any): any?
	if typeof(raw) ~= "table" or typeof(raw.k) ~= "string" or typeof(raw.t) ~= "number" or raw.t ~= raw.t then
		return nil
	end
	local data = nil
	if typeof(raw.d) == "table" then
		data = {}
		local fields = 0
		for key, value in raw.d do
			if typeof(key) ~= "string" or fields >= FIELDS then
				continue
			end
			local kind = typeof(value)
			if (kind == "number" and value == value) or kind == "boolean" then
				data[string.sub(key, 1, NAME)] = value
			elseif kind == "string" then
				data[string.sub(key, 1, NAME)] = string.sub(value, 1, TEXT)
			else
				continue
			end
			fields += 1
		end
	end
	return {
		t = raw.t,
		c = if typeof(raw.c) == "number" and raw.c == raw.c then raw.c else nil,
		k = string.sub(raw.k, 1, 40),
		d = data,
	}
end

local function flush()
	if #entries == 0 and dropped == 0 then
		return
	end
	local batch = entries
	entries = {}
	if dropped > 0 then
		table.insert(batch, { t = Workspace:GetServerTimeNow(), k = "trace.dropped", d = { count = dropped } })
		dropped = 0
	end
	if studio then
		return
	end
	count += 1
	local key = `{os.date("!%Y%m%d-%H%M%S")}_{server}_{string.format("%03d", count)}`
	local value = {
		server = game.JobId,
		role = Workspace:GetAttribute("Role"),
		mode = Workspace:GetAttribute("Mode"),
		place = game.PlaceVersion,
		entries = batch,
	}
	local ok, problem = pcall(function()
		DataStoreService:GetDataStore(STORE):SetAsync(key, value)
	end)
	if not ok then
		warn("[TraceService] the log could not be written:", problem)
	end
end

function TraceService.start()
	Remote.event("Trace", 4, function(player, batch)
		if typeof(batch) ~= "table" then
			return
		end
		for _, raw in batch do
			if (sent[player] or 0) >= PER_PLAYER then
				return
			end
			local entry = clean(raw)
			if entry then
				sent[player] = (sent[player] or 0) + 1
				entry.p = player.UserId
				add(entry)
			end
		end
	end)

	TraceService.mark("server.start", {
		lobby = Places.isLobby(),
		private = game.PrivateServerId ~= "",
		place = game.PlaceVersion,
	})
	ScriptContext.Error:Connect(function(message, stack, origin)
		TraceService.mark("error", {
			message = string.sub(message, 1, TEXT),
			stack = string.sub(stack, 1, TEXT),
			script = if origin then origin:GetFullName() else nil,
		})
	end)
	local warnings = 0
	LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageWarning and warnings < WARNINGS then
			warnings += 1
			TraceService.mark("warning", { message = string.sub(message, 1, TEXT) })
		end
	end)

	local function joined(player: Player)
		local data = player:GetJoinData()
		TraceService.mark("player.join", {
			name = player.Name,
			from = data.SourcePlaceId,
			teleported = data.TeleportData ~= nil,
		}, player)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		TraceService.mark("player.leave", nil, player)
		sent[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		TraceService.mark("teleport.failed", { result = result.Name, message = string.sub(message, 1, TEXT) }, player)
	end)
	for _, attribute in { "Phase", "Role", "Mode", "VersusUntil" } do
		Workspace:GetAttributeChangedSignal(attribute):Connect(function()
			local value = Workspace:GetAttribute(attribute)
			TraceService.mark("world." .. string.lower(attribute), { to = if value ~= nil then value else "nil" })
		end)
	end

	task.spawn(function()
		while true do
			task.wait(FLUSH)
			flush()
		end
	end)
	task.spawn(function()
		local round = 0
		while true do
			task.wait(STATS)
			local sample = Memory.sample()
			sample.players = #Players:GetPlayers()
			TraceService.mark("server.memory", sample)
			round += 1
			if round % 2 == 0 then
				TraceService.mark("server.objects", Memory.objects(Workspace))
			end
		end
	end)
	game:BindToClose(function()
		TraceService.mark("server.close")
		flush()
	end)
end

return TraceService

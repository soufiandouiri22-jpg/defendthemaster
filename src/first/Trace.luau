-- This client's part of the game's log (TraceService, read with Tools/trace.py): what happened when, from the first
-- frame on. It lives in ReplicatedFirst so the loading screen can log too; what it marks waits here until the server's
-- Net.Trace is there and then goes over every SEND seconds, stamped with the server's clock. On its own it marks the
-- client's errors and warnings, the screen and device, every click on a free mouse (where it went), the mouse's
-- behaviour as it changes, and every STATS seconds the frame rate, ping and memory.

local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Trace = {}

-- How often the marks go to the server, how many at once, and how many this client may mark in all.
local SEND, BATCH, MOST = 1, 40, 3000
-- How often the frame rate, ping and memory are marked, and how many warnings and clicks are marked at most.
local STATS, WARNINGS, CLICKS = 30, 200, 400

local START = os.clock()
local queue: { any } = {}
local marked = 0
local started = false

local function now(): number
	local ok, time = pcall(Workspace.GetServerTimeNow, Workspace)
	return if ok and time > 0 then time else DateTime.now().UnixTimestampMillis / 1000
end

-- Marks `kind` (a short dotted name, "loading.stage") with `data` (a flat table of numbers, booleans and short
-- strings) at this moment.
function Trace.mark(kind: string, data: { [string]: any }?)
	if marked >= MOST then
		return
	end
	marked += 1
	table.insert(queue, { t = now(), c = math.floor((os.clock() - START) * 1000) / 1000, k = kind, d = data })
end

-- The path of `item` from its ScreenGui down, for the log.
local function path(item: Instance): string
	local names = {}
	local at: Instance? = item
	while at and not at:IsA("PlayerGui") and #names < 6 do
		table.insert(names, 1, at.Name)
		at = at.Parent
	end
	return table.concat(names, ".")
end

-- Starts marking on its own and sending; once only.
function Trace.start()
	if started then
		return
	end
	started = true
	local camera = Workspace.CurrentCamera
	Trace.mark("client.start", {
		screen = if camera then `{camera.ViewportSize.X}x{camera.ViewportSize.Y}` else nil,
		mouse = UserInputService.MouseEnabled,
		touch = UserInputService.TouchEnabled,
		pad = UserInputService.GamepadEnabled,
		place = game.PlaceVersion,
	})

	ScriptContext.Error:Connect(function(message, stack, origin)
		Trace.mark("error", {
			message = string.sub(message, 1, 300),
			stack = string.sub(stack, 1, 300),
			script = if origin then origin:GetFullName() else nil,
		})
	end)
	local warnings = 0
	LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageWarning and warnings < WARNINGS then
			warnings += 1
			Trace.mark("warning", { message = string.sub(message, 1, 300) })
		end
	end)

	local clicks = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			or clicks >= CLICKS
		then
			return
		end
		clicks += 1
		local at = UserInputService:GetMouseLocation()
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
		local inset = GuiService:GetGuiInset()
		local under = if playerGui then playerGui:GetGuiObjectsAtPosition(at.X - inset.X, at.Y - inset.Y) else {}
		-- What lies under the mouse's own picture (Loading.pointer's gauntlet).
		local top = nil
		for _, item in under do
			local gui = item:FindFirstAncestorWhichIsA("LayerCollector")
			if not gui or gui.Name ~= "Pointer" then
				top = item
				break
			end
		end
		Trace.mark("click", {
			x = math.floor(at.X),
			y = math.floor(at.Y),
			processed = processed,
			top = if top then path(top) else nil,
		})
	end)
	TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		Trace.mark("teleport.failed", { result = result.Name, message = string.sub(message, 1, 300) })
	end)
	UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
		Trace.mark("mouse.behavior", { to = UserInputService.MouseBehavior.Name })
	end)

	task.spawn(function()
		local frames = 0
		local since = os.clock()
		RunService.RenderStepped:Connect(function()
			frames += 1
		end)
		while true do
			task.wait(STATS)
			local fps = frames / (os.clock() - since)
			frames, since = 0, os.clock()
			Trace.mark("client.stats", {
				fps = math.floor(fps + 0.5),
				ping = math.floor(Players.LocalPlayer:GetNetworkPing() * 1000),
				memory = math.floor(Stats:GetTotalMemoryUsageMb()),
			})
		end
	end)

	task.spawn(function()
		local net = ReplicatedStorage:WaitForChild("Net", math.huge)
		local remote = net:WaitForChild("Trace", math.huge) :: RemoteEvent
		while true do
			if #queue > 0 then
				local batch = table.move(queue, 1, math.min(#queue, BATCH), 1, {})
				queue = table.move(queue, #batch + 1, #queue, 1, {})
				remote:FireServer(batch)
			end
			task.wait(SEND)
		end
	end)
end

return Trace

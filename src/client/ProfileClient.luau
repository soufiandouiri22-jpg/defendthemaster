-- The player's own saved data (Shared.Profile) as the server last sent it (Net.Profile, server ProfileService), and the
-- menu's requests to the server (Net.Menu, server MenuService). The client never changes the data itself: it asks,
-- and the server's answer and new data come back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(ReplicatedStorage.Shared.Profile)

local ProfileClient = {}

local data: Profile.Data? = nil
local changed = Instance.new("BindableEvent")

-- The data, or nil until it has come.
function ProfileClient.get(): Profile.Data?
	return data
end

-- Waits for the data.
function ProfileClient.await(): Profile.Data
	while not data do
		changed.Event:Wait()
	end
	return data :: Profile.Data
end

-- Runs `callback` with the data now (once it has come) and after every change.
function ProfileClient.watch(callback: (data: Profile.Data) -> ()): RBXScriptConnection
	if data then
		task.spawn(callback, data)
	end
	return changed.Event:Connect(callback)
end

export type Answer = { ok: boolean, error: string?, [string]: any }

-- Asks the server `action` (MenuService's ACTIONS) with `...`; the answer, or a failed one when the server is not
-- reached.
function ProfileClient.ask(action: string, ...: any): Answer
	local net = ReplicatedStorage:WaitForChild("Net", 10)
	local menu = net and net:WaitForChild("Menu", 10)
	if not menu then
		return { ok = false, error = "The server is not ready yet." }
	end
	local ok, answer = pcall((menu :: RemoteFunction).InvokeServer, menu, action, ...)
	if not ok or typeof(answer) ~= "table" then
		return { ok = false, error = "No answer from the server. Try again." }
	end
	return answer
end

function ProfileClient.start()
	local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Profile") :: RemoteEvent
	event.OnClientEvent:Connect(function(new)
		data = new
		changed:Fire(new)
	end)
	event:FireServer()
end

return ProfileClient

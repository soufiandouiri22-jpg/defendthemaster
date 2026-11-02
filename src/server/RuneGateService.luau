-- The Rune Gates (Config.RuneGates; Map.Features.RuneGates, ColosseumBuilder, each with its "Gate" name), flat gold
-- rune circles in two pairs across the centre. Every frame the server looks who stands on one: a living hero, player
-- or bot, within Middle studs of a gate's middle goes through after Channel seconds there, coming out on the gate it
-- leads to facing the way he faced; then for Again seconds no gate takes him. Stepping off before stops it. A gate
-- carries since when the first of those on it has stood there ("ChannelAt", server time, for the clients' light), and
-- each jump is told to the clients (Net.RuneGateJump: from, to, the hero) for its light and sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Actors = require(script.Parent.Actors)

local RuneGateService = {}

local SETTINGS = Config.RuneGates
-- A hero's root stands this high over his feet; who is higher over a gate is jumping over it.
local ROOT_HEIGHT, ABOVE = 3, 5

type Channel = { gate: string, since: number, serverSince: number }

local gates: { [string]: Model } = {}
local channels: { [Model]: Channel } = {}
local resting: { [Model]: number } = {}
local jumpEvent: RemoteEvent

-- The gate whose middle the hero's `root` stands over, if any.
local function standingOn(root: BasePart): string?
	for name, spot in SETTINGS.Spots do
		local offset = root.Position - spot.At
		if offset.Y <= ABOVE and Vector2.new(offset.X, offset.Z).Magnitude <= SETTINGS.Middle then
			return name
		end
	end
	return nil
end

local function jump(character: Model, root: BasePart, from: string)
	local to = SETTINGS.Spots[from].To
	local at = SETTINGS.Spots[to].At + Vector3.new(0, ROOT_HEIGHT + 0.2, 0)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	channels[character] = nil
	character:PivotTo(CFrame.lookAt(at, at + look))
	resting[character] = os.clock() + SETTINGS.Again
	jumpEvent:FireAllClients(from, to, character)
end

local function step()
	local now = os.clock()
	local seen = {}
	for _, actor in Actors.all() do
		local character = Actors.character(actor)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		seen[character] = true
		local gate = if (resting[character] or 0) > now then nil else standingOn(root)
		local channel = channels[character]
		if not gate then
			channels[character] = nil
		elseif not channel or channel.gate ~= gate then
			channels[character] = { gate = gate, since = now, serverSince = Workspace:GetServerTimeNow() }
		elseif now - channel.since >= SETTINGS.Channel then
			jump(character, root, gate)
		end
	end
	for character in channels do
		if not seen[character] then
			channels[character] = nil
		end
	end
	for character in resting do
		if not seen[character] then
			resting[character] = nil
		end
	end
	local first: { [string]: number } = {}
	for _, channel in channels do
		first[channel.gate] = math.min(first[channel.gate] or math.huge, channel.serverSince)
	end
	for name, gate in gates do
		if gate:GetAttribute("ChannelAt") ~= first[name] then
			gate:SetAttribute("ChannelAt", first[name])
		end
	end
end

export type Layout = {
	map: Folder,
}

function RuneGateService.start(layout: Layout)
	if not SETTINGS.Enabled then
		return
	end
	local features = layout.map:FindFirstChild("Features")
	local folder = features and features:FindFirstChild("RuneGates")
	for _, gate in if folder then folder:GetChildren() else {} do
		local name = gate:GetAttribute("Gate")
		if gate:IsA("Model") and type(name) == "string" then
			gates[name] = gate
		end
	end
	jumpEvent = Instance.new("RemoteEvent")
	jumpEvent.Name = "RuneGateJump"
	jumpEvent.Parent = ReplicatedStorage:WaitForChild("Net")
	RunService.Heartbeat:Connect(step)
end

return RuneGateService

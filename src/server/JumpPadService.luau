-- The jump pads on the server (Config.JumpPads). The flight itself is the player's client's, as all his movement
-- (JumpPadView, HeroControls.launch); his client tells the server when his hero leaves a pad (Net.JumpPad: the pad's
-- number in Config.JumpPads.Spots) and when he is down or an attack took over ("Land"). In between his hero carries
-- until when he flies ("Flying", server time), by which every other client's HeroAnimator holds him in the jump's
-- flight rather than looking for the ground under him. A pad he does not stand on is not believed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local JumpPadService = {}

local SETTINGS = Config.JumpPads
-- How far from a pad's middle a hero may be when his client says he left it: its edge, and the way his client's
-- position takes to arrive.
local SLACK = 6

function JumpPadService.start()
	if not SETTINGS.Enabled then
		return
	end
	local event = Instance.new("RemoteEvent")
	event.Name = "JumpPad"
	event.OnServerEvent:Connect(function(player: Player, what: unknown)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root then
			return
		end
		if what == "Land" then
			character:SetAttribute("Flying", nil)
			return
		end
		local spot = type(what) == "number" and SETTINGS.Spots[what]
		if not spot or humanoid.Health <= 0 then
			return
		end
		local offset = (root.Position - spot.At) * Vector3.new(1, 0, 1)
		if offset.Magnitude > SETTINGS.Width / 2 + SLACK then
			return
		end
		local length =
			math.max(SETTINGS.Flight, ((spot.To - spot.At) * Vector3.new(1, 0, 1)).Magnitude / SETTINGS.Speed)
		character:SetAttribute("Flying", Workspace:GetServerTimeNow() + length)
	end)
	event.Parent = ReplicatedStorage:WaitForChild("Net")
end

return JumpPadService

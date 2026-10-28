-- While the player's hero is dead the world turns grey and the middle of the screen counts down to his return (the
-- hero's "RespawnAt" attribute, in server time, from ProgressService.heroDied). While the player's own kill banner
-- shows there (KillFeed sets PlayerGui's "KillBanner") the count fades out of its way and keeps running underneath.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UiStyle = require(script.Parent.UiStyle)

local RespawnTimer = {}

local C = UiStyle.Colors
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GREY = -0.85
-- How fast the count fades out of the kill banner's way and back (its full fade per second).
local MAKE_WAY = 5

function RespawnTimer.start()
	local player = Players.LocalPlayer
	local gui = UiStyle.screen("Respawn", player:WaitForChild("PlayerGui"), 5)
	gui.Enabled = false
	local box = UiStyle.frame(gui, UDim2.fromOffset(520, 200), UDim2.fromScale(0.5, 0.3), Vector2.new(0.5, 0.5))
	box.BackgroundTransparency = 1
	local title = UiStyle.text(box, "RESPAWN IN", 44, C.Cream, C.Edge)
	title.Size = UDim2.new(1, 0, 0, 56)
	local count = UiStyle.text(box, "", 120, Color3.new(1, 1, 1), C.Edge)
	count.Size = UDim2.new(1, 0, 0, 130)
	count.Position = UDim2.fromOffset(0, 58)

	local grey = Instance.new("ColorCorrectionEffect")
	grey.Name = "Dead"
	grey.Saturation = 0
	grey.Parent = Lighting

	local character: Model? = nil
	local dead = false

	local function setDead(on: boolean)
		if dead == on then
			return
		end
		dead = on
		gui.Enabled = on
		TweenService:Create(grey, FADE, { Saturation = if on then GREY else 0, Brightness = if on then -0.05 else 0 })
			:Play()
	end

	local function watch(model: Model)
		character = model
		setDead(false)
		local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid and character == model then
			humanoid.Died:Connect(function()
				if character == model then
					setDead(true)
				end
			end)
		end
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end

	local shown = 1
	local texts = { title, count }
	RunService.RenderStepped:Connect(function(dt)
		if not dead or not character then
			return
		end
		local target = if player.PlayerGui:GetAttribute("KillBanner") then 0 else 1
		shown = if target > shown
			then math.min(target, shown + MAKE_WAY * dt)
			else math.max(target, shown - MAKE_WAY * dt)
		for _, label in texts do
			label.TextTransparency = 1 - shown;
			(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Transparency = 1 - shown
		end
		local at = character:GetAttribute("RespawnAt")
		count.Text = if at then tostring(math.max(1, math.ceil(at - Workspace:GetServerTimeNow()))) else ""
	end)
end

return RespawnTimer

-- The player's own hero getting hurt, at the screen's edges: they flash red on every hit, stronger the more it took
-- (as League's "screen flash on damage"), and below LOW of his health they glow red and pulse slowly, deeper the lower
-- he is.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DamageView = {}

local RED = Color3.fromRGB(200, 16, 16)
-- A hit's flash: its least and most strength, how much a hit of a full health bar would add, and how fast it fades
-- (strength per second).
local HIT_MIN, HIT_MAX, HIT_PER_HEALTH, HIT_FADE = 0.35, 0.85, 3, 2.4
-- The glow below this share of health: its strength at the edge of LOW and at none left, and its pulse.
local LOW, LOW_FROM, LOW_TO, PULSE, PULSE_SPEED = 0.25, 0.15, 0.5, 0.15, 4
-- How far in from each edge the red reaches, as a share of the screen.
local DEPTH_X, DEPTH_Y = 0.16, 0.22

local function edge(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2, rotation: number): Frame
	local f = Instance.new("Frame")
	f.Visible = false
	f.BorderSizePixel = 0
	f.BackgroundColor3 = RED
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor
	f.Parent = parent
	local fade = Instance.new("UIGradient")
	fade.Rotation = rotation
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.45, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = f
	return f
end

function DamageView.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DamageView"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	-- Each edge fades on its own: a CanvasGroup's GroupTransparency of 1 still draws its contents as a red haze.
	local edges = {
		edge(gui, UDim2.fromScale(1, DEPTH_Y), UDim2.fromScale(0, 0), Vector2.zero, 90),
		edge(gui, UDim2.fromScale(1, DEPTH_Y), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90),
		edge(gui, UDim2.fromScale(DEPTH_X, 1), UDim2.fromScale(0, 0), Vector2.zero, 0),
		edge(gui, UDim2.fromScale(DEPTH_X, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180),
	}

	local hit = 0
	local humanoid: Humanoid? = nil
	local function watch(character: Model)
		local h = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not h then
			return
		end
		humanoid = h
		local last = h.Health
		h.HealthChanged:Connect(function(health)
			local lost = last - health
			last = health
			if lost > 0.5 and h.MaxHealth > 0 and health > 0 then
				hit = math.max(hit, math.clamp(HIT_MIN + lost / h.MaxHealth * HIT_PER_HEALTH, HIT_MIN, HIT_MAX))
			end
		end)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end

	RunService.RenderStepped:Connect(function(dt)
		hit = math.max(0, hit - HIT_FADE * dt)
		local low = 0
		local h = humanoid
		if h and h.Parent and h.Health > 0 and h.MaxHealth > 0 then
			local share = h.Health / h.MaxHealth
			if share < LOW then
				local depth = 1 - share / LOW
				local pulse = (math.sin(os.clock() * PULSE_SPEED) + 1) / 2
				low = LOW_FROM + (LOW_TO - LOW_FROM) * depth + PULSE * pulse
			end
		end
		local strength = math.clamp(math.max(hit, low), 0, 1)
		for _, f in edges do
			f.Visible = strength > 0.01
			f.BackgroundTransparency = 1 - strength
		end
	end)
end

return DamageView

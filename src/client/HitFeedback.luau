-- Shows every hit a hero lands (Net.HeroHit from the server: the target, the damage, where, and who struck): the target
-- flashes white for a moment, and the striker sees the damage jump up from it, gold and larger the harder the hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MinionView = require(script.Parent.MinionView)

local HitFeedback = {}

local GOLD = Color3.fromRGB(255, 214, 102)
local OUTLINE = Color3.fromRGB(60, 34, 8)
local FLASH_TIME = 0.18
local NUMBER_TIME = 0.75

local player = Players.LocalPlayer
local flashing: { [Instance]: Highlight } = {}

local function flash(target: Instance)
	local model = if target:IsA("BasePart") then MinionView.modelOf(target) else target
	if not model then
		return
	end
	local highlight = flashing[model]
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.OutlineTransparency = 1
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.Adornee = model
		highlight.Parent = model
		flashing[model] = highlight
	end
	local h = highlight :: Highlight
	h.FillTransparency = 0.25
	TweenService:Create(h, TweenInfo.new(FLASH_TIME), { FillTransparency = 1 }):Play()
	task.delay(FLASH_TIME + 0.05, function()
		if flashing[model] == h and h.FillTransparency >= 0.99 then
			flashing[model] = nil
			h:Destroy()
		end
	end)
end

local function number(at: Vector3, amount: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = at + Vector3.new(math.random(-10, 10) / 10, 3.5, math.random(-10, 10) / 10)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(math.round(amount))
	label.TextColor3 = GOLD
	label.TextSize = math.clamp(18 + amount / 6, 20, 40)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2
	stroke.Parent = label
	gui.Parent = anchor
	anchor.Parent = Workspace:FindFirstChild("Effects") or Workspace
	local info = TweenInfo.new(NUMBER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { Position = anchor.Position + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(NUMBER_TIME, function()
		anchor:Destroy()
	end)
end

function HitFeedback.start()
	local net = ReplicatedStorage:WaitForChild("Net")
	local event = net:WaitForChild("HeroHit") :: RemoteEvent
	event.OnClientEvent:Connect(function(target: Instance, amount: number, at: Vector3, striker: Player?)
		if target and target.Parent then
			flash(target)
		end
		if striker == player then
			number(at, amount)
		end
	end)
end

return HitFeedback

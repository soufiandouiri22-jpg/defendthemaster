-- The task of the tip that is on in the first matches (Tips), in the middle under the score board: a dark plate in a
-- gold rim with an empty check circle, the task, how many of it are done, and its keys (Tips.Prompts) under it. Done,
-- the circle fills green with a tick, the plate flashes gold with a chime, and it rises away for the next.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Prompts = require(script.Parent.Prompts)
local Shop = require(script.Parent.Parent.Shop)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)

local Objective = {}

local C = UiStyle.Colors
-- Its top in the middle, in the HUD's 1080-high pixels: well clear of the score board's clock (owner, 2026-11-11);
-- under the buy phase's banner while that shows, and under the respawn count while the hero is dead (RespawnTimer).
local TOP, BANNER_TOP, DEAD_TOP = 190, 300, 450
-- How fast it moves to another of those heights (a share of the way per second).
local GLIDE = 8
local WIDTH = 900
local HEIGHT = 58
local TEXT = 28
local KEY = 60
local CHECK = 38
local DONE_GREEN = Color3.fromRGB(96, 200, 64)

type Shown = { frame: Frame, check: Frame, tick: TextLabel, count: TextLabel, label: TextLabel, plate: Frame }

local gui: Frame
local current: Shown? = nil
local currentKey: string? = nil
local counted = ""

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad), goal)
	t:Play()
	return t
end

local function make(goal: string, keys: { string }?): Shown
	local home = UDim2.new(0.5, 0, 0, TOP)
	local frame = UiStyle.frame(gui, UDim2.fromOffset(WIDTH, HEIGHT + KEY + 14), home)
	frame.Name = "Objective"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1
	local plate = UiStyle.frame(frame, UDim2.fromOffset(0, HEIGHT), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	plate.AutomaticSize = Enum.AutomaticSize.X
	UiStyle.corner(plate, HEIGHT // 2)
	UiStyle.gradient(plate, Color3.fromRGB(96, 62, 36), Color3.fromRGB(52, 32, 18))
	UiStyle.stroke(plate, C.Gold, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 26)
	padding.Parent = plate
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = plate
	local check = UiStyle.frame(plate, UDim2.fromOffset(CHECK, CHECK))
	check.BackgroundColor3 = Color3.fromRGB(40, 26, 14)
	check.LayoutOrder = 1
	UiStyle.corner(check, UDim.new(0.5, 0))
	UiStyle.stroke(check, C.Gold, 3)
	local tick = UiStyle.text(check, "✓", 30, C.Cream, C.Edge)
	tick.Size = UDim2.fromScale(1, 1)
	tick.TextTransparency = 1
	local label = UiStyle.text(plate, string.upper(goal), TEXT, C.Cream, C.Edge)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, HEIGHT)
	label.LayoutOrder = 2
	local count = UiStyle.text(plate, counted, TEXT, Color3.fromRGB(255, 214, 90), C.Edge)
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromOffset(0, HEIGHT)
	count.LayoutOrder = 3
	if keys and #keys > 0 then
		local row = Prompts.row(frame, keys, KEY)
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.Position = UDim2.new(0.5, 0, 0, HEIGHT + 10)
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	frame.Position = home + UDim2.fromOffset(0, 30)
	tween(frame, 0.35, { Position = home }, Enum.EasingStyle.Back)
	return { frame = frame, check = check, tick = tick, count = count, label = label, plate = plate }
end

local function away(shown: Shown, done: boolean)
	local delay = 0
	if done then
		UiSound.play("StepDone")
		shown.check.BackgroundColor3 = DONE_GREEN
		shown.tick.TextTransparency = 0
		local pop = Instance.new("UIScale")
		pop.Scale = 1.5
		pop.Parent = shown.check
		tween(pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		local gradient = shown.plate:FindFirstChildOfClass("UIGradient") :: UIGradient
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(214, 140, 30))
		shown.label.TextColor3 = C.Cream
		delay = 0.9
	end
	task.delay(delay, function()
		tween(shown.frame, 0.35, { Position = shown.frame.Position - UDim2.fromOffset(0, 50) })
		for _, d in shown.frame:GetDescendants() do
			if d:IsA("TextLabel") then
				tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("ImageLabel") then
				tween(d, 0.3, { ImageTransparency = 1 })
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				tween(d, 0.3, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.36)
		shown.frame:Destroy()
	end)
end

function Objective.build(parent: ScreenGui)
	-- Away while the armory is open, whose cards it would cover (the gold frames lead there), and while the player's own
	-- kill banner takes the middle (KillFeed).
	local holder = UiStyle.frame(parent, UDim2.fromScale(1, 1))
	holder.Name = "Objectives"
	holder.BackgroundTransparency = 1
	gui = holder
	local playerGui = parent.Parent :: Instance
	local offset = 0
	RunService.Heartbeat:Connect(function(dt)
		holder.Visible = not Shop.isOpen() and not playerGui:GetAttribute("KillBanner")
		local banner = playerGui:FindFirstChild("BuyPhase") :: ScreenGui?
		local respawn = playerGui:FindFirstChild("Respawn") :: ScreenGui?
		local top = if respawn and respawn.Enabled
			then DEAD_TOP
			elseif banner and banner.Enabled then BANNER_TOP
			else TOP
		offset += (top - TOP - offset) * math.min(1, GLIDE * dt)
		holder.Position = UDim2.fromOffset(0, math.round(offset))
	end)
end

-- Shows the task `goal` (nil for none) with `keys`, under the name `key` (the same key keeps what is shown); `done`
-- says the one before was done rather than left.
function Objective.set(key: string?, goal: string?, keys: { string }?, done: boolean)
	if key == currentKey then
		return
	end
	currentKey = key
	counted = ""
	if current then
		away(current, done)
		current = nil
	end
	if goal then
		local shownKey = key
		task.delay(if done then 1.1 else 0, function()
			if currentKey == shownKey and not current then
				current = make(goal, keys)
			end
		end)
	end
end

-- How many of `need` are done.
function Objective.count(done: number, need: number?)
	counted = if need and need > 1 then done .. " / " .. need else ""
	if current then
		current.count.Text = counted
	end
end

return Objective

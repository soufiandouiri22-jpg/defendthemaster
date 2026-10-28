-- The buy phase at the start of a match (Config.Match, the server's "FightAt" on Workspace): "PURCHASE YOUR ITEMS!"
-- slams onto the screen in gold with an orchestral sting and a burst of coins, then sits small under the score board
-- counting down while the heroes walk to their armory stalls; with the armory open (Shop) its own countdown shows
-- instead. The last three seconds count big in the middle, and "FIGHT!" opens the match with a deep boom.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Preferences = require(script.Parent.Preferences)
local Shop = require(script.Parent.Shop)
local UiStyle = require(script.Parent.UiStyle)

local BuyPhase = {}

local C = UiStyle.Colors
-- With less than this many seconds left when the player comes in, the big entrance is skipped.
local INTRO = 4
-- How long the big banner stands before it moves up under the score board.
local HOLD = 2.6
-- Where the banner stands, as a share of the screen's height, and where it shrinks to (pixels from the top).
local MIDDLE = 0.36
local TOP = 205
local COINS = 16
local GOLD = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(236, 150, 34))
local FIRE = ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(226, 60, 34))

local function tween(
	object: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	after: number?
)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, after or 0)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.SoundGroup = Preferences.group("Effects")
	s.Parent = SoundService
	return s
end

-- Big lettering filling its frame (TextSize stops at 100), with a gradient fill and a thick dark edge.
local function lettering(parent: Instance, value: string, fill: ColorSequence, edge: number): TextLabel
	local label = UiStyle.text(parent, value, 100, Color3.new(1, 1, 1), C.Edge)
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = edge
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local gradient = Instance.new("UIGradient")
	gradient.Color = fill
	gradient.Rotation = 90
	gradient.Parent = label
	return label
end

-- A white glint that sweeps once across `label`'s letters.
local function glint(label: TextLabel, seconds: number)
	local shine = label:Clone()
	shine:ClearAllChildren()
	shine.Parent = label
	shine.Position = UDim2.new()
	shine.ZIndex = label.ZIndex + 1
	local band = Instance.new("UIGradient")
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.05),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Rotation = 20
	band.Offset = Vector2.new(-1, 0)
	band.Parent = shine
	tween(band, seconds, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine).Completed:Connect(function()
		shine:Destroy()
	end)
end

local function fade(label: TextLabel, to: number, seconds: number, after: number?)
	tween(label, seconds, { TextTransparency = to }, nil, after)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		tween(stroke, seconds, { Transparency = to }, nil, after)
	end
end

local function setAlpha(label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

-- An empty frame of `size` round `position`, with a UIScale to grow or shrink it from its middle.
local function holder(parent: Instance, size: UDim2, position: UDim2): (Frame, UIScale)
	local frame = UiStyle.frame(parent, size, position, Vector2.new(0.5, 0.5))
	frame.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	return frame, scale
end

function BuyPhase.start()
	local gui = UiStyle.screen("BuyPhase", Players.LocalPlayer:WaitForChild("PlayerGui"), 8)
	gui.Enabled = false

	local flash = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20

	-- A dark band behind the banner, fading out to its top and bottom.
	local band = UiStyle.frame(gui, UDim2.fromScale(1, 0), UDim2.fromScale(0.5, MIDDLE), Vector2.new(0.5, 0.5))
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	local bandFade = Instance.new("UIGradient")
	bandFade.Rotation = 90
	bandFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	bandFade.Parent = band

	-- The banner and its countdown pill, moved and scaled as one.
	local group = UiStyle.frame(gui, UDim2.fromOffset(1500, 250), UDim2.fromScale(0.5, MIDDLE), Vector2.new(0.5, 0.3))
	group.BackgroundTransparency = 1
	group.ZIndex = 5
	local groupScale = Instance.new("UIScale")
	groupScale.Parent = group
	local banner = UiStyle.frame(group, UDim2.new(1, 0, 0, 130))
	banner.BackgroundTransparency = 1
	local title = lettering(banner, "PURCHASE YOUR ITEMS!", GOLD, 8)
	local pillOuter, pill =
		UiStyle.panel(group, UDim2.fromOffset(440, 72), UDim2.new(0.5, 0, 0, 150), Vector2.new(0.5, 0), 36, 5)
	UiStyle.corner(pill, 31)
	local pillText = UiStyle.text(pill, "", 40, C.Ink)
	pillText.Size = UDim2.fromScale(1, 1)
	local pillScale = Instance.new("UIScale")
	pillScale.Parent = pillOuter

	local bigFrame, bigScale = holder(gui, UDim2.fromOffset(400, 260), UDim2.fromScale(0.5, 0.42))
	local big = lettering(bigFrame, "", GOLD, 10)
	local fightHome = UDim2.fromScale(0.5, 0.4)
	local fightFrame, fightScale = holder(gui, UDim2.fromOffset(900, 260), fightHome)
	local fight = lettering(fightFrame, "FIGHT!", FIRE, 11)

	local sting = sound(Assets.BuySting, 0.45)
	local tick = sound(Assets.CountTick, 0.5)
	local boom = sound(Assets.FightBoom, 0.6)
	local function burst(at: UDim2, count: number)
		for _ = 1, count do
			local coin = Instance.new("ImageLabel")
			coin.BackgroundTransparency = 1
			coin.Image = Assets.HudCoin
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			local size = math.random(38, 64)
			coin.Size = UDim2.fromOffset(size, size)
			coin.Position = at
			coin.ZIndex = 4
			coin.Parent = gui
			local angle = math.random() * math.pi * 2
			local reach = math.random(320, 700)
			local goal = at + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach * 0.6)
			tween(coin, 1.1, { Position = goal, Rotation = math.random(-540, 540) }, Enum.EasingStyle.Quart)
			tween(coin, 0.5, { ImageTransparency = 1 }, nil, 0.6).Completed:Connect(function()
				coin:Destroy()
			end)
		end
	end

	local function flashScreen(strength: number)
		flash.BackgroundTransparency = 1 - strength
		tween(flash, 0.4, { BackgroundTransparency = 1 })
	end

	local function shake(frame: GuiObject, home: UDim2)
		task.spawn(function()
			for i = 6, 1, -1 do
				frame.Position = home + UDim2.fromOffset(math.random(-i, i) * 2, math.random(-i, i) * 2)
				task.wait(0.03)
			end
			frame.Position = home
		end)
	end

	local function setPill(seconds: number)
		pillText.Text = string.format("FIGHT IN  %d", seconds)
	end

	-- The big entrance: the band opens, the title slams in, coins fly, the announcer speaks.
	local function entrance()
		local home = UDim2.fromScale(0.5, MIDDLE)
		group.Position = home
		groupScale.Scale = 3
		group.Rotation = -7
		setAlpha(title, 1)
		pillOuter.Visible = false
		band.Size = UDim2.fromScale(1, 0)
		band.BackgroundTransparency = 0
		tween(band, 0.3, { Size = UDim2.new(1, 0, 0, 330) })
		sting:Play()
		fade(title, 0, 0.18)
		tween(groupScale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(group, 0.38, { Rotation = 0 }, Enum.EasingStyle.Back)
		task.wait(0.3)
		flashScreen(0.45)
		shake(group, home)
		burst(UDim2.fromScale(0.5, MIDDLE), COINS)
		glint(title, 0.7)
		task.wait(0.35)
		pillOuter.Visible = true
		pillScale.Scale = 0.2
		tween(pillScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(HOLD)
		tween(band, 0.45, { BackgroundTransparency = 1 })
		tween(group, 0.5, { Position = UDim2.new(0.5, 0, 0, TOP) }, Enum.EasingStyle.Quint)
		tween(groupScale, 0.5, { Scale = 0.5 }, Enum.EasingStyle.Quint)
		task.wait(0.5)
		glint(title, 0.6)
	end

	local function compact()
		band.BackgroundTransparency = 1
		group.Position = UDim2.new(0.5, 0, 0, TOP)
		group.Rotation = 0
		groupScale.Scale = 0.5
		setAlpha(title, 0)
		pillOuter.Visible = true
		pillScale.Scale = 1
	end

	local function count(n: number)
		big.Text = tostring(n)
		setAlpha(big, 0)
		bigScale.Scale = 1.9
		tween(bigScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		fade(big, 1, 0.25, 0.7)
		tick.TimePosition = 0
		tick:Play()
		task.delay(0.8, function()
			tick:Stop()
		end)
	end

	local function fightNow()
		boom:Play()
		fightFrame.Visible = true
		fade(fight, 0, 0.1)
		fightScale.Scale = 3.2
		tween(fightScale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(0.25)
		flashScreen(0.55)
		shake(fightFrame, fightHome)
		glint(fight, 0.6)
		task.wait(1.3)
		tween(fightScale, 0.5, { Scale = 1.25 })
		fade(fight, 1, 0.5)
		task.wait(0.5)
		fightFrame.Visible = false
	end

	local running = false
	local function run()
		local fightAt = Workspace:GetAttribute("FightAt")
		local function left(): number
			return fightAt - Workspace:GetServerTimeNow()
		end
		if running or not fightAt or left() <= 0 then
			return
		end
		running = true
		gui.Enabled = true
		setAlpha(big, 1)
		setAlpha(fight, 1)
		fightFrame.Visible = false
		setPill(math.ceil(left()))
		if left() > INTRO then
			entrance()
		else
			compact()
		end
		local shown = math.huge
		while left() > 0 do
			local n = math.ceil(left())
			setPill(n)
			if n <= 3 and n < shown then
				if shown == math.huge or shown > 3 then
					fade(title, 1, 0.3)
					tween(pillOuter, 0.3, { Position = pillOuter.Position - UDim2.fromOffset(0, 20) })
					task.delay(0.3, function()
						pillOuter.Visible = false
					end)
				end
				shown = n
				count(n)
			end
			task.wait(0.05)
		end
		fightNow()
		gui.Enabled = false
		running = false
	end

	-- The armory shows its own countdown, so the banner and its band give way while it is open.
	RunService.RenderStepped:Connect(function()
		local open = Shop.isOpen()
		group.Visible = not open
		band.Visible = not open
	end)

	Workspace:GetAttributeChangedSignal("FightAt"):Connect(function()
		task.spawn(run)
	end)
	task.spawn(run)
end

return BuyPhase

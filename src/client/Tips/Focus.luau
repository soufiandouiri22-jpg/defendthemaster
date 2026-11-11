-- What of the HUD a tip of the first matches is about (Tips): a gold frame pulsing round it with a gold arrow bobbing
-- over it, laid on the screen in its own pixels over everything but the draft and the end of the match. "Shop": the
-- chosen card and the buy button while the armory is open. A rank to raise needs none: its pill already pulses
-- (AbilityBar).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Shop = require(script.Parent.Parent.Shop)
local UiStyle = require(script.Parent.Parent.UiStyle)

local Focus = {}

local C = UiStyle.Colors
local PAD = 8
local ARROW = 54
local MOST = 3

local player = Players.LocalPlayer
local focus: string? = nil

type Mark = { frame: Frame, stroke: UIStroke, arrow: ImageLabel }

local function targets(): { GuiObject }
	return if focus == "Shop" then Shop.targets() else {}
end

function Focus.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TipsFocus"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	gui.DisplayOrder = 19
	local marks: { Mark } = {}
	for _ = 1, MOST do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Color3.fromRGB(255, 214, 80)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = gui
		UiStyle.corner(frame, 14)
		local stroke = UiStyle.stroke(frame, Color3.fromRGB(255, 226, 110), 4)
		local arrow = Instance.new("ImageLabel")
		arrow.BackgroundTransparency = 1
		arrow.Image = Assets.TutorialEdgeArrow
		arrow.Rotation = 180
		arrow.Size = UDim2.fromOffset(ARROW, ARROW)
		arrow.AnchorPoint = Vector2.new(0.5, 1)
		arrow.Parent = frame
		table.insert(marks, { frame = frame, stroke = stroke, arrow = arrow })
	end
	RunService.RenderStepped:Connect(function()
		local list = if focus then targets() else {}
		local now = os.clock()
		local pulse = (math.sin(now * 2 * math.pi * 1.3) + 1) / 2
		local scale = gui.AbsoluteSize.Y / 1080
		for i, mark in marks do
			local target = list[i]
			local shown = target ~= nil and target.Visible and target.AbsoluteSize.X > 0
			mark.frame.Visible = shown
			if target and shown then
				local pad = PAD * math.max(scale, 0.6)
				-- Absolute positions count from under Roblox's top bar; this screen starts above it.
				local at = target.AbsolutePosition - gui.AbsolutePosition
				mark.frame.Position = UDim2.fromOffset(at.X - pad, at.Y - pad)
				mark.frame.Size = UDim2.fromOffset(target.AbsoluteSize.X + 2 * pad, target.AbsoluteSize.Y + 2 * pad)
				mark.frame.BackgroundTransparency = 0.88 - 0.1 * pulse
				mark.stroke.Thickness = 3 + 3 * pulse
				mark.stroke.Color = C.Gold:Lerp(Color3.fromRGB(255, 250, 220), pulse)
				local size = ARROW * math.max(scale, 0.6)
				mark.arrow.Size = UDim2.fromOffset(size, size)
				mark.arrow.Position = UDim2.new(0.5, 0, 0, -6 - 10 * math.abs(math.sin(now * 4)))
			end
		end
	end)
end

-- Lights up `what` (nil for nothing).
function Focus.set(what: string?)
	focus = what
end

return Focus

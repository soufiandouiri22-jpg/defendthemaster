-- The key prompts of the tips (Tips, Lobby.Hints), and the mouse buttons wherever the HUD names them: an ivory
-- keycap with its letter on top, a wide one for Shift and Space, and the mouse with its left ("M1") or right ("M2")
-- button lit gold (Assets.KeyCap, KeyWide, MouseLeft, MouseRight). A row of them now and then presses itself down to
-- show what to do, and a key flashes gold as the player really presses it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local UiStyle = require(script.Parent.Parent.UiStyle)

local Prompts = {}

local C = UiStyle.Colors
-- The keycap's top in its picture, as a share of its height: where the letter sits, and how big it is.
local FACE_Y, LETTER = 0.42, 0.42
-- How much wider than high the wide keys are drawn.
local WIDE = { Shift = 2, Space = 3 }
-- How often a row shows itself pressed, and how deep a press goes.
local HINT_EVERY, PRESS = 1.8, 0.86
local LIT = Color3.fromRGB(255, 222, 120)

local INPUTS: { [string]: { Enum.KeyCode | Enum.UserInputType } } = {
	M1 = { Enum.UserInputType.MouseButton1 },
	M2 = { Enum.UserInputType.MouseButton2 },
	Shift = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	Space = { Enum.KeyCode.Space },
	["1"] = { Enum.KeyCode.One },
	["2"] = { Enum.KeyCode.Two },
	["3"] = { Enum.KeyCode.Three },
}

local function inputsOf(name: string): { Enum.KeyCode | Enum.UserInputType }
	local known = INPUTS[name]
	if known then
		return known
	end
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok and code then { code } else {}
end

-- The width of `name`'s prompt at `height`.
function Prompts.width(name: string, height: number): number
	if name == "M1" or name == "M2" then
		return math.floor(height * 0.66)
	end
	return math.floor(height * (WIDE[name] or 1))
end

export type Key = { frame: Frame, press: () -> (), lit: () -> () }

-- One prompt for `name` ("W", "1", "Shift", "M1"...), `height` pixels high.
function Prompts.key(parent: Instance, name: string, height: number): Key
	local width = Prompts.width(name, height)
	local frame = UiStyle.frame(parent, UDim2.fromOffset(width, height))
	frame.Name = "Key" .. name
	frame.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = frame
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1, 1)
	glow.ImageTransparency = 1
	glow.ImageColor3 = LIT
	glow.ZIndex = 2
	glow.Parent = frame
	if name == "M1" or name == "M2" then
		image.Image = if name == "M1" then Assets.MouseLeft else Assets.MouseRight
		image.ScaleType = Enum.ScaleType.Fit
		glow.Image = image.Image
		glow.ScaleType = Enum.ScaleType.Fit
	else
		local wide = WIDE[name] ~= nil
		image.Image = if wide then Assets.KeyWide else Assets.KeyCap
		glow.Image = image.Image
		if wide then
			for _, picture in { image, glow } do
				picture.ScaleType = Enum.ScaleType.Slice
				picture.SliceCenter = Assets.KeyWideSlice
				picture.SliceScale = height / 256
			end
		end
		local letter = UiStyle.text(frame, string.upper(name), math.floor(height * LETTER), C.Ink)
		letter.Size = UDim2.fromScale(1, LETTER + 0.06)
		letter.Position = UDim2.fromScale(0.5, FACE_Y)
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.TextScaled = #name > 1
		letter.ZIndex = 3
		if #name > 1 then
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = math.floor(height * 0.3)
			limit.Parent = letter
		end
	end
	local function press()
		scale.Scale = PRESS
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	local function lit()
		press()
		glow.ImageTransparency = 0.25
		TweenService:Create(glow, TweenInfo.new(0.45), { ImageTransparency = 1 }):Play()
	end
	return { frame = frame, press = press, lit = lit }
end

-- A row of prompts for `names`, `height` high and `gap` apart, that hints itself pressed now and then and lights up
-- each key the player presses; nothing once the row is gone.
function Prompts.row(parent: Instance, names: { string }, height: number, gap: number?): Frame
	local spacing = gap or math.floor(height * 0.12)
	local width = 0
	for i, name in names do
		width += Prompts.width(name, height) + (if i > 1 then spacing else 0)
	end
	local row = UiStyle.frame(parent, UDim2.fromOffset(width, height))
	row.Name = "Keys"
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row
	local keys: { Key } = {}
	local byInput: { [any]: Key } = {}
	for i, name in names do
		local key = Prompts.key(row, name, height)
		key.frame.LayoutOrder = i
		table.insert(keys, key)
		for _, input in inputsOf(name) do
			byInput[input] = key
		end
	end
	local pressed = UserInputService.InputBegan:Connect(function(input)
		local key = byInput[input.KeyCode] or byInput[input.UserInputType]
		if key then
			key.lit()
		end
	end)
	row.Destroying:Connect(function()
		pressed:Disconnect()
	end)
	task.spawn(function()
		while row.Parent do
			task.wait(HINT_EVERY)
			for _, key in keys do
				if not row.Parent then
					return
				end
				key.press()
				task.wait(0.16)
			end
		end
	end)
	return row
end

return Prompts

-- The mouse pointer: the game's gold gauntlet (Assets.Pointer), drawn as a picture that follows the hidden system
-- mouse every frame. Roblox's own MouseIcon falls back to its arrow over every button and on every click, so the
-- system mouse stays off for good. The gauntlet shows once the loading screen is gone, never while the camera holds
-- the mouse in the middle (HeroCamera's crosshair) and only where there is a mouse.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Loading = require(ReplicatedFirst:WaitForChild("Loading"))

local Assets = require(ReplicatedStorage.Shared.Assets)

local Pointer = {}

-- The gauntlet's height on the screen in pixels, the picture's size, and its fingertip (where it clicks) in it.
local HIGH = 54
local PICTURE = Vector2.new(211, 238)
local TIP = Vector2.new(7, 11)
-- Above every other screen of the game, the loading screen (1000) included.
local ORDER = 2000

function Pointer.start(playerGui: Instance)
	UserInputService.MouseIconEnabled = false
	local gui = Instance.new("ScreenGui")
	gui.Name = "Pointer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	-- After parenting: a ScreenGui created at runtime can ignore DisplayOrder set before it has a parent.
	gui.DisplayOrder = ORDER
	local image = Instance.new("ImageLabel")
	image.Name = "Gauntlet"
	image.BackgroundTransparency = 1
	image.Image = Assets.Pointer
	image.Size = UDim2.fromOffset(math.round(HIGH * PICTURE.X / PICTURE.Y), HIGH)
	image.AnchorPoint = TIP / PICTURE
	image.Active = false
	image.Visible = false
	image.Parent = gui

	local loaded = false
	task.spawn(function()
		Loading.waitGone()
		loaded = true
	end)
	RunService:BindToRenderStep("Pointer", Enum.RenderPriority.Last.Value, function()
		UserInputService.MouseIconEnabled = false
		-- The draft and the end screen switch every other screen off while they are up.
		gui.Enabled = true
		local at = UserInputService:GetMouseLocation()
		image.Position = UDim2.fromOffset(at.X, at.Y)
		image.Visible = loaded
			and UserInputService.MouseEnabled
			and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	end)
end

return Pointer

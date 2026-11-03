-- The emotes in a match (Config.Emotes): holding G opens the wheel of the player's emotes (EmoteWheel) with the mouse
-- free to point at one, and letting go asks the server to dance it (Net.Emote, EmoteService), which every client then
-- plays (HeroAnimator). Only while his hero is alive and no menu has the mouse (the shop, the end of the match).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Profile = require(ReplicatedStorage.Shared.Profile)
local EmoteWheel = require(script.Parent.EmoteWheel)
local HeroCamera = require(script.Parent.HeroCamera)
local ProfileClient = require(script.Parent.ProfileClient)

local EmoteControls = {}

local KEY = Enum.KeyCode.G
-- The wheel's size against the menu's, small enough to keep the fight round it in sight.
local SIZE = 0.65

function EmoteControls.start()
	local event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Emote") :: RemoteEvent
	local wheel = EmoteWheel.new(SIZE)
	local function alive(): boolean
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil and humanoid.Health > 0
	end
	local function finish(): string?
		if not wheel.isOpen() then
			return nil
		end
		local id = wheel.release()
		HeroCamera.setEnabled(true)
		return id
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= KEY or wheel.isOpen() then
			return
		end
		local data = ProfileClient.get()
		if not data or not alive() or not HeroCamera.isEnabled() then
			return
		end
		HeroCamera.setEnabled(false)
		wheel.hold(Profile.wheel(data))
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode ~= KEY then
			return
		end
		local id = finish()
		if id and alive() then
			event:FireServer(id)
		end
	end)
	-- Dying with the wheel open closes it.
	task.spawn(function()
		while true do
			task.wait(0.2)
			if wheel.isOpen() and not alive() then
				finish()
			end
		end
	end)
end

return EmoteControls

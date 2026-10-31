-- The mouse pointer: the game's gold gauntlet (Assets.Pointer), drawn by the loading screen from its first frame on
-- (Loading.pointer, in ReplicatedFirst so it is there before anything else and goes along from the menu without a
-- gap); this hands it the picture from Assets.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Loading = require(ReplicatedFirst:WaitForChild("Loading"))

local Pointer = {}

function Pointer.start(_playerGui: Instance)
	Loading.pointer(Assets.Pointer)
end

return Pointer

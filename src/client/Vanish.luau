-- A vanished hero (his "Hidden" attribute, from a kit of Kind "Vanish" on the server): gone for his enemies, his health
-- bar with him, and faint to himself and his team, till he shows again or dies.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Vanish = {}

-- How see-through a vanished hero is to himself and his team; to his enemies he is gone.
local FAINT = 0.7

local player = Players.LocalPlayer
local faded: { [Model]: boolean } = {}

local function fade(model: Model, amount: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = amount
		end
	end
	local bar = model:FindFirstChild("HeroBar")
	if bar and bar:IsA("BillboardGui") then
		bar.Enabled = amount < 1
	end
end

local function hidden(model: Model): boolean
	return model:GetAttribute("Hidden") == true and CollectionService:HasTag(model, "Combatant")
end

-- Every frame, so his weapons and what else comes onto him stay faded with him; last of all, as Roblox's camera
-- scripts set the local hero's fade back each frame.
function Vanish.start()
	RunService:BindToRenderStep("Vanish", Enum.RenderPriority.Last.Value, function()
		for model in faded do
			if not model.Parent or not hidden(model) then
				fade(model, 0)
				faded[model] = nil
			end
		end
		local own = player.Character
		local team = own and own:GetAttribute("Team")
		for _, model in CollectionService:GetTagged("Combatant") do
			if model:IsA("Model") and hidden(model) then
				fade(model, if model == own or model:GetAttribute("Team") == team then FAINT else 1)
				faded[model] = true
			end
		end
	end)
end

-- Whether `model` is a hero the local player cannot see: vanished, and of the other team.
function Vanish.unseen(model: Model): boolean
	local own = player.Character
	return hidden(model) and model ~= own and model:GetAttribute("Team") ~= (own and own:GetAttribute("Team"))
end

return Vanish

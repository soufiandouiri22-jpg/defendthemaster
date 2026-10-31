-- The heroes for the menu: one model of every hero (HeroLook) in ReplicatedStorage.Showcase, standing still with its
-- root anchored. Each client puts its own showcase hero (Shared.Profile.showcase) on the hall's podium and plays his
-- showcase pose with his aura there (Lobby.Showcase); the heroes page, the shop and the leaderboard show copies in
-- their portraits. Every player in the lobby also gets his own Roblox avatar in ReplicatedStorage.Showcase.Avatars
-- (named by his UserId), in the heroes' proportions, which stands on his podium until he has chosen a hero and is
-- what turns into that hero (Lobby.Welcome).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)
local HeroLook = require(script.Parent.HeroLook)

local ShowcaseService = {}

local function still(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
		model.PrimaryPart = root
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	-- How many pieces it has, so a client copies it only once all of them have come over (Lobby.Showcase).
	model:SetAttribute("Parts", #model:GetDescendants())
end

local function build(hero: string): Model?
	local ok, model =
		pcall(Players.CreateHumanoidModelFromDescription, Players, HeroLook.description(hero), Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("[ShowcaseService] could not build", hero, model)
		return nil
	end
	model.Name = hero
	HeroLook.dress(model, hero)
	still(model)
	return model
end

-- The idles Roblox gives an avatar without an animation pack.
local STANDARD_IDLES = {
	["http://www.roblox.com/asset/?id=507766388"] = true,
	["http://www.roblox.com/asset/?id=507766666"] = true,
}

-- The idle of the animation pack `model` was built with (the heaviest of its Animate script's idles), nil without one.
local function idle(model: Model): string?
	local animate = model:FindFirstChild("Animate")
	local idles = animate and animate:FindFirstChild("idle")
	local best, weight = nil, -1
	for _, animation in if idles then idles:GetChildren() else {} do
		local value = animation:FindFirstChild("Weight")
		local w = if value and value:IsA("NumberValue") then value.Value else 1
		if animation:IsA("Animation") and animation.AnimationId ~= "" and w > weight then
			best, weight = animation.AnimationId, w
		end
	end
	if best and STANDARD_IDLES[best] then
		return nil
	end
	return best
end

-- `player`'s own avatar, its clothes, hair, face and accessories as he wears them, in the proportions of the heroes'
-- rigs so it stands on the podium as tall as they do.
local function avatar(player: Player): Model?
	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, math.max(1, player.UserId))
	if not ok or not description then
		warn("[ShowcaseService] no avatar for", player.Name, description)
		return nil
	end
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	local built, model =
		pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not built or not model then
		warn("[ShowcaseService] could not build the avatar of", player.Name, model)
		return nil
	end
	model.Name = tostring(player.UserId)
	model:SetAttribute("Idle", idle(model))
	still(model)
	return model
end

function ShowcaseService.start()
	local folder = Instance.new("Folder")
	folder.Name = "Showcase"
	local avatars = Instance.new("Folder")
	avatars.Name = "Avatars"
	avatars.Parent = folder
	for hero in Config.Heroes do
		local model = build(hero)
		if model then
			model.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
	if not Places.isLobby() then
		return
	end
	local function add(player: Player)
		local model = avatar(player)
		if model and player.Parent then
			model.Parent = avatars
		end
	end
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		task.spawn(add, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local model = avatars:FindFirstChild(tostring(player.UserId))
		if model then
			model:Destroy()
		end
	end)
end

return ShowcaseService

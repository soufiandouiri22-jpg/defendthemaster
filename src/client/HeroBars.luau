-- The bar over every other hero's head (design 05): his health in his team's colour on this screen (Side: allies blue,
-- enemies red), the only thing that tells the teams apart, with his level in the round knob at its left end. A hero's bar goes when he dies (the "Combatant" tag
-- goes with his life). A boost's carrier (his "Boost" attribute, BoostService) has his bar raised over the boost
-- that turns over his head (BoostView).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local BoostView = require(script.Parent.BoostView)
local Side = require(script.Parent.Side)
local UiStyle = require(script.Parent.UiStyle)

local HeroBars = {}

local C = UiStyle.Colors
local WIDTH, HEIGHT, KNOB = 132, 16, 28
-- The name over the bar (owner, 2026-11-02: friend and foe, so you see whom you kill); a bot goes by his hero, as on
-- the scoreboard.
local NAME = 18
-- The bar floats this many studs over the hero's root; while he carries a boost, `BOOSTED` over the top of the boost
-- (counted from the top of his head).
local OVER, BOOSTED = 4.4, 4.2

local bars: { [Model]: BillboardGui } = {}

local function levelOf(model: Model): number
	local owner = Players:GetPlayerFromCharacter(model)
	return (if owner then owner:GetAttribute("Level") else model:GetAttribute("Level")) or 1
end

local function build(model: Model)
	-- While the game loads, a hero's tag can arrive before its parts.
	local humanoid = model:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if
		bars[model]
		or not humanoid
		or not root
		or not CollectionService:HasTag(model, "Combatant")
		or model == Players.LocalPlayer.Character
	then
		return
	end
	local team = Side.shown(model:GetAttribute("Team"))
	local colour = C[team]

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroBar"
	gui.Size = UDim2.fromOffset(WIDTH + KNOB / 2, KNOB + NAME)
	-- The bar stays where it was before the name came over it.
	gui.SizeOffset = Vector2.new(0, NAME / 2 / (KNOB + NAME))
	gui.LightInfluence = 0
	-- Only the heroes near enough to matter: further bars would crowd the screen.
	gui.MaxDistance = 75
	gui.Adornee = root

	local bar = UiStyle.bar(
		gui,
		UDim2.fromOffset(WIDTH, HEIGHT),
		UDim2.new(0, KNOB / 2, 1, -KNOB / 2),
		colour:Lerp(Color3.new(1, 1, 1), 0.2),
		colour:Lerp(C[team .. "Dark"], 0.4),
		Vector2.new(0, 0.5),
		nil,
		C.Trail
	);
	(bar.frame:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 2
	local knob = UiStyle.frame(gui, UDim2.fromOffset(KNOB, KNOB))
	knob.Position = UDim2.new(0, 0, 1, -KNOB)
	knob.BackgroundColor3 = colour
	knob.ZIndex = 2
	UiStyle.corner(knob, UDim.new(0.5, 0))
	UiStyle.gradient(knob, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	UiStyle.stroke(knob, C.Edge, 2)
	local level = UiStyle.text(knob, "1", 17, C.Cream, C.Edge)
	level.Size = UDim2.fromScale(1, 1)
	level.ZIndex = 3

	local owner = Players:GetPlayerFromCharacter(model)
	local name =
		UiStyle.text(gui, if owner then owner.DisplayName else model:GetAttribute("Hero") or "", 16, C.Cream, C.Edge)
	name.Size = UDim2.new(1, 0, 0, NAME)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local function update()
		bar:set(if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0)
		level.Text = tostring(levelOf(model))
		local boost = if model:GetAttribute("Boost") == true then Boosts.current() else nil
		gui.StudsOffsetWorldSpace = Vector3.new(0, if boost then BOOSTED + BoostView.wornTop(boost) else OVER, 0)
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	model:GetAttributeChangedSignal("Boost"):Connect(update)
	if owner then
		owner:GetAttributeChangedSignal("Level"):Connect(update)
	else
		model:GetAttributeChangedSignal("Level"):Connect(update)
	end
	update()
	gui.Parent = model
	bars[model] = gui
end

local function add(instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Hero") and instance ~= Players.LocalPlayer.Character then
		task.spawn(build, instance)
	end
end

local function remove(instance: Instance)
	local gui = bars[instance :: Model]
	if gui then
		gui:Destroy()
		bars[instance :: Model] = nil
	end
end

function HeroBars.start()
	CollectionService:GetInstanceAddedSignal("Combatant"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Combatant"):Connect(remove)
	for _, instance in CollectionService:GetTagged("Combatant") do
		add(instance)
	end
end

return HeroBars

-- The hero's items in the HUD, right of the ability bar: the six slots of his bag in two rows of three on a parchment
-- panel (Shared.Items), a potion with how many he carries and the Q that drinks one (Net.Shop "Drink"); while a potion
-- heals, its slot fills with green from the top for the time it has left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local UiStyle = require(script.Parent.UiStyle)

local ItemBar = {}

local C = UiStyle.Colors
local SLOT = 72
local GAP = 8
local COLUMNS = 3
-- The ability bar's half width and its gap to this panel, in the bottom blocks' drawn pixels.
local BESIDE = 307 + 16
local SLOT_TOP = Color3.fromRGB(250, 238, 206)
local SLOT_BOTTOM = Color3.fromRGB(222, 196, 146)
local EMPTY_TOP, EMPTY_BOTTOM = Color3.fromRGB(150, 118, 80), Color3.fromRGB(118, 90, 60)

type Slot = {
	frame: Frame,
	gradient: UIGradient,
	icon: ImageLabel,
	badge: Frame,
	count: TextLabel,
	key: Frame,
	heal: Frame,
}

local player = Players.LocalPlayer
local slots: { Slot } = {}
local shopEvent: RemoteEvent? = nil

local function drink()
	if shopEvent and Items.count(player, "HealthPotion") > 0 then
		shopEvent:FireServer("Drink")
		for i, held in Items.bag(player) do
			if Config.Items[held.id].Potion then
				local frame = slots[i].frame
				local scale = frame:FindFirstChildOfClass("UIScale") :: UIScale
				scale.Scale = 0.85
				TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end
end

local function show()
	local bag = Items.bag(player)
	for i, s in slots do
		local held = bag[i]
		local item = held and Config.Items[held.id]
		s.icon.Image = if item then item.Icon else ""
		s.gradient.Color = if item
			then ColorSequence.new(SLOT_TOP, SLOT_BOTTOM)
			else ColorSequence.new(EMPTY_TOP, EMPTY_BOTTOM)
		local potion = item ~= nil and item.Potion == true
		s.badge.Visible = held ~= nil and (held.count > 1 or potion)
		s.count.Text = if held then tostring(held.count) else ""
		s.key.Visible = potion
	end
end

local function slot(parent: Instance, index: number): Slot
	local column, row = (index - 1) % COLUMNS, (index - 1) // COLUMNS
	local frame = UiStyle.frame(
		parent,
		UDim2.fromOffset(SLOT, SLOT),
		UDim2.fromOffset(GAP + column * (SLOT + GAP) + SLOT / 2, GAP + row * (SLOT + GAP) + SLOT / 2),
		Vector2.one / 2
	)
	frame.ClipsDescendants = true
	UiStyle.corner(frame, 9)
	local gradient = UiStyle.gradient(frame, EMPTY_TOP, EMPTY_BOTTOM)
	UiStyle.stroke(frame, C.GoldDark, 2.5)
	Instance.new("UIScale").Parent = frame
	local heal = UiStyle.frame(frame, UDim2.fromScale(1, 0))
	heal.BackgroundColor3 = Color3.fromRGB(96, 220, 80)
	heal.BackgroundTransparency = 0.45
	heal.ZIndex = 3
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.fromOffset(4, 4)
	icon.ZIndex = 2
	icon.Parent = frame
	local badge = UiStyle.frame(frame, UDim2.fromOffset(24, 22), UDim2.new(1, -3, 1, -3), Vector2.one)
	badge.BackgroundColor3 = Color3.fromRGB(44, 30, 20)
	badge.ZIndex = 4
	UiStyle.corner(badge, 6)
	local count = UiStyle.text(badge, "", 17, C.Cream)
	count.Size = UDim2.fromScale(1, 1)
	count.ZIndex = 5
	local key = UiStyle.frame(frame, UDim2.fromOffset(22, 22), UDim2.fromOffset(3, 3))
	key.BackgroundColor3 = C.Cream
	key.ZIndex = 4
	UiStyle.corner(key, 5)
	UiStyle.stroke(key, C.Edge, 1.5)
	local keyLabel = UiStyle.text(key, "Q", 16, C.Ink)
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.ZIndex = 5
	return {
		frame = frame,
		gradient = gradient,
		icon = icon,
		badge = badge,
		count = count,
		key = key,
		heal = heal,
	}
end

function ItemBar.start()
	local gui = UiStyle.screen("ItemBar", player:WaitForChild("PlayerGui"))
	local rows = math.ceil(Config.Shop.Slots / COLUMNS)
	local width = COLUMNS * (SLOT + GAP) + GAP
	local height = rows * (SLOT + GAP) + GAP
	local outer, inner = UiStyle.panel(
		gui,
		UDim2.fromOffset(width + 10, height + 10),
		UDim2.new(0.5, BESIDE * UiStyle.BottomScale, 1, -18),
		Vector2.new(0, 1),
		14,
		5
	)
	UiStyle.shrink(outer, UiStyle.BottomScale)
	inner.Name = "Bag"
	for i = 1, Config.Shop.Slots do
		slots[i] = slot(inner, i)
	end

	task.spawn(function()
		shopEvent = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Shop") :: RemoteEvent
	end)
	player.AttributeChanged:Connect(function(name)
		if name:match("^Item") or name:match("^Count") then
			show()
		end
	end)
	show()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Q then
			drink()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local left = (player:GetAttribute("PotionUntil") or 0) - Workspace:GetServerTimeNow()
		local time = Config.Shop.Potion.Time
		-- The potion healing now: what is left of it, past the ones queued behind it.
		local current = if left > 0 then left - time * (math.ceil(left / time) - 1) else 0
		local bag = Items.bag(player)
		for i, s in slots do
			local held = bag[i]
			local potion = held ~= nil and Config.Items[held.id].Potion == true
			s.heal.Size = UDim2.fromScale(1, if potion then current / time else 0)
		end
	end)
end

return ItemBar

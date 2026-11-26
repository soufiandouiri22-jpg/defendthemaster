-- While the player's hero is dead, one line under the respawn count says who killed him (owner, 2026-11-25: as
-- Fortnite's "ELIMINATED <name>", in the HUD's look, not a card full of information): "KILLED BY" in cream and the
-- killer's name in his team's colour: the player's own name, never his hero's, and "Bot" for a bot (owner,
-- 2026-11-25); the Master, the minions, or a warden. A death nobody is credited with shows none. It comes in after the death's banner has slammed in (KillFeed) and goes when the hero is back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Side = require(script.Parent.Side)
local UiStyle = require(script.Parent.UiStyle)

local KilledBy = {}

local C = UiStyle.Colors
local player = Players.LocalPlayer

-- Where the line sits (in the HUD's 1080-high units: under the hero, clear of the crosshair in the middle), how big
-- its words are, and the room between them.
local TOP, WORDS, NAME, GAP = 660, 42, 50, 14
-- How long after the death it comes in (the death's banner slams in first), and how long it takes to come and go.
local DELAY, IN, OUT = 0.5, 0.3, 0.3

function KilledBy.start()
	local gui = UiStyle.screen("KilledBy", player:WaitForChild("PlayerGui"), 5)

	local line = Instance.new("CanvasGroup")
	line.BackgroundTransparency = 1
	line.AutomaticSize = Enum.AutomaticSize.X
	line.Size = UDim2.fromOffset(0, NAME + 16)
	line.Position = UDim2.new(0.5, 0, 0, TOP)
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Visible = false
	line.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = line
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = line

	local words = UiStyle.text(line, "KILLED BY", WORDS, C.Cream, C.Edge)
	words.AutomaticSize = Enum.AutomaticSize.X
	words.Size = UDim2.fromOffset(0, NAME + 16)
	words.LayoutOrder = 1
	local name = UiStyle.text(line, "", NAME, C.Red, C.Edge)
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Size = UDim2.fromOffset(0, NAME + 16)
	name.LayoutOrder = 2

	local serial = 0
	local shown = false

	local function hide()
		serial += 1
		if not shown then
			return
		end
		shown = false
		local mine = serial
		TweenService:Create(line, TweenInfo.new(OUT), { GroupTransparency = 1 }):Play()
		task.delay(OUT, function()
			if mine == serial then
				line.Visible = false
			end
		end)
	end

	local function show(kill: { [string]: any })
		serial += 1
		local mine = serial
		local killer = kill.killer
		if kill.killerHero == "Master" then
			name.Text = "The Master"
		elseif kill.killerHero == "Minion" then
			name.Text = "Minions"
		elseif kill.killerHero == "Warden" then
			name.Text = "The Warden"
		elseif typeof(killer) == "Instance" and killer:IsA("Player") then
			name.Text = killer.DisplayName
		else
			name.Text = "Bot"
		end
		name.TextColor3 = Config.Teams[Side.shown(kill.killerTeam)].Color

		task.delay(DELAY, function()
			if mine ~= serial then
				return
			end
			shown = true
			line.Visible = true
			line.GroupTransparency = 1
			scale.Scale = 1.4
			TweenService:Create(line, TweenInfo.new(IN * 0.6), { GroupTransparency = 0 }):Play()
			TweenService
				:Create(scale, TweenInfo.new(IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end)
	end

	local net = ReplicatedStorage:WaitForChild("Net")
	local event = net:WaitForChild("Kill") :: RemoteEvent
	event.OnClientEvent:Connect(function(kill)
		if typeof(kill) == "table" and kill.victim == player and kill.killerHero ~= nil then
			show(kill)
		end
	end)
	player.CharacterAdded:Connect(hide)
end

return KilledBy

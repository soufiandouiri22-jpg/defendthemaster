-- Every hero's death on screen (Net.Kill from ProgressService, its call from Config.Kills):
-- * A banner under the score board, the player's own in the middle and the others' on the right: the killer's portrait in his team's ring, crossed swords and the victim's
--   portrait greyed and struck out, over the call in big lettering. The bigger the call (Config.Kills.Tiers), the
--   bigger and hotter the lettering: rays turn behind it from tier 3, and on the player's own kills the screen flashes,
--   the camera kicks and coins burst. Kills by others show smaller, in the killer's team colour; the player's own death
--   reads "YOU HAVE BEEN SLAIN". Only the player's own kills and death sound (a sting per tier); no voices.
-- * The bounty: coins burst from where the victim fell and fly into the coin counter (Hud's "Coins", whose "Held"
--   attribute keeps them off the count until they land), with "+300" rising from the spot and a clink per coin.
--   A kill that leaves a whole team down is followed on the same banner by WIPEOUT.
-- * The feed over the minimap: the last kills as small rows of both portraits, edged in the killer's team colour.
-- A hero felled by a Master shows that Master's portrait, his team's (Config.Master.Portraits), as his killer's, and
-- one felled by a minion its team's minion portrait (Config.Minions.Portraits).
-- When a hero takes the Sun Crown (CrownService), the middle banner shows his portrait with the crown on it over
-- Config.Crown.Texts: gold for the player's team, with its sting, and the enemy's colour for theirs, with a dark bell.
-- When it fades, the banner shows the crown alone, fading out with a falling shimmer.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HeroCamera = require(script.Parent.HeroCamera)
local UiSound = require(script.Parent.UiSound)
local UiStyle = require(script.Parent.UiStyle)

local KillFeed = {}

local C = UiStyle.Colors
local SETTINGS = Config.Kills
local player = Players.LocalPlayer

-- The two banners: the player's own kills and death big in the middle, everyone else's small on the right. While the
-- player's own shows, PlayerGui's "KillBanner" attribute is set, and the middle's other texts (the respawn timer) step
-- aside until it is gone. Where they stand (in the HUD's 1080-high units: from the top, and the right one from the
-- screen's side), how wide they are, and how long they hold.
local BANNER_TOP, BANNER_SIDE, MIDDLE_WIDTH, SIDE_WIDTH = 200, 60, 1100, 600
local HOLD = 2.2
-- When a kill leaves a whole team down, WIPEOUT takes over its banner this long after it.
local WIPE_AFTER = 1.3
-- The lettering's height per tier, and the scale of a banner for someone else's kill.
local TEXT_HEIGHT = { 64, 86, 108, 134 }
local OTHERS_SCALE = 0.62
local PORTRAIT = 112
-- The Sun Crown on its banner (Assets.SunCrown, 484 by 275): worn on the taker's portrait, or alone as it fades.
local CROWN_WORN = UDim2.fromOffset(PORTRAIT * 0.95, PORTRAIT * 0.95 * 275 / 484)
local CROWN_ALONE = UDim2.fromOffset(PORTRAIT * 1.5, PORTRAIT * 1.5 * 275 / 484)
-- The feed: its rows, how many show at once, how long each stays, and where its foot sits (over the minimap).
local ROW_WIDTH, ROW_HEIGHT, ROWS, ROW_LIFE = 210, 52, 5, 8
local FEED_RIGHT, FEED_BOTTOM = 30, 96 + 270 + 22
-- Coins: one per this much bounty (at most COINS_MAX), how long they burst out and how long they take to fly home.
local COIN_WORTH, COINS_MAX, BURST, FLIGHT = 25, 14, 0.35, 0.55

local FILLS = {
	ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 220, 232)),
	ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(236, 150, 34)),
	ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(226, 60, 34)),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 170)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 24, 70)),
	}),
}
local DEATH_FILL = ColorSequence.new(Color3.fromRGB(255, 140, 130), Color3.fromRGB(160, 20, 30))
-- The sting under the player's own kill, per tier (UiSound).
local STINGS = { "KillSlain", "KillBig", "KillHuge", "KillLegend" }
-- How loud the stings and the own death's sound play.
local STING_VOLUME = 1.5

type Kill = {
	kind: string,
	crown: boolean?,
	fades: boolean?,
	wipe: boolean?,
	killer: Player?,
	killerName: string?,
	killerHero: string?,
	killerTeam: string,
	victim: Player?,
	victimName: string?,
	victimHero: string?,
	victimTeam: string,
	coins: number,
	at: Vector3,
}

local function tween(
	object: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	after: number?
)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, after or 0)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

local function teamColour(team: string?): Color3
	return (Config.Teams[team or "Blue"] or Config.Teams.Blue).Color
end

-- Big lettering filling its frame, with a gradient fill and a thick dark edge (as BuyPhase's).
local function lettering(parent: Instance, edge: number): (TextLabel, UIGradient)
	local label = UiStyle.text(parent, "", 100, Color3.new(1, 1, 1), C.Edge)
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = edge
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = label
	return label, gradient
end

-- A round portrait of `hero` in a ring of `ring`'s colour; returns the frame and the picture.
local function portrait(parent: Instance, size: number, position: UDim2, anchor: Vector2?): (Frame, ImageLabel)
	local ring = UiStyle.frame(parent, UDim2.fromOffset(size, size), position, anchor)
	UiStyle.corner(ring, UDim.new(0.5, 0))
	UiStyle.stroke(ring, C.Edge, math.max(2, size / 28))
	local inset = math.max(3, math.round(size * 0.07))
	local back = UiStyle.frame(ring, UDim2.new(1, -2 * inset, 1, -2 * inset), UDim2.fromOffset(inset, inset))
	back.ClipsDescendants = true
	UiStyle.corner(back, UDim.new(0.5, 0))
	UiStyle.gradient(back, Color3.fromRGB(246, 214, 160), Color3.fromRGB(200, 150, 96))
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Crop
	image.Parent = back
	UiStyle.corner(image, UDim.new(0.5, 0))
	return ring, image
end

-- The portrait of `hero`, or of `team`'s Master when he is "Master" and of its minions when he is "Minion".
local function faceOf(hero: string?, team: string?): { Image: string, Face: { number } }?
	if hero == "Master" then
		return Config.Master.Portraits[team or "Blue"]
	elseif hero == "Minion" then
		return Config.Minions.Portraits[team or "Blue"]
	end
	return hero and Config.Heroes[hero] and Config.Heroes[hero].Portrait
end

local function showHero(ring: Frame, image: ImageLabel, hero: string?, team: string?, dead: boolean)
	ring.BackgroundColor3 = teamColour(team)
	local face = faceOf(hero, team)
	image.Visible = face ~= nil
	if face then
		local x, y, size = table.unpack(face.Face)
		image.Image = face.Image
		image.ImageRectOffset = Vector2.new(x, y)
		image.ImageRectSize = Vector2.new(size, size)
	end
	image.ImageColor3 = if dead then Color3.fromRGB(120, 112, 108) else Color3.new(1, 1, 1)
end

-- Two bars crossed over `parent`'s middle: the swords between the portraits, or the cross over a fallen one.
local function cross(parent: Instance, length: number, width: number, colour: Color3, edge: Color3): { Frame }
	local bars = {}
	for _, angle in { 45, -45 } do
		local bar =
			UiStyle.frame(parent, UDim2.fromOffset(width, length), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		bar.Rotation = angle
		bar.BackgroundColor3 = colour
		bar.ZIndex = 3
		UiStyle.corner(bar, math.floor(width / 2))
		UiStyle.stroke(bar, edge, 2)
		table.insert(bars, bar)
	end
	return bars
end

-- The counter's middle on screen, in `gui`'s units.
local function counterAt(gui: ScreenGui, scale: number): Vector2?
	local hud = player.PlayerGui:FindFirstChild("Hud")
	local pill = hud and hud:FindFirstChild("Coins", true)
	if not pill or not pill:IsA("GuiObject") then
		return nil
	end
	local middle = pill.AbsolutePosition + pill.AbsoluteSize / 2 - gui.AbsolutePosition
	return middle / scale
end

function KillFeed.start()
	-- Under the armory (18), so a kill's banner and WIPEOUT sit behind the board, not across it.
	local gui = UiStyle.screen("KillFeed", player:WaitForChild("PlayerGui"), 4)
	local scale = gui:FindFirstChildOfClass("UIScale") :: UIScale

	local flash = UiStyle.frame(gui, UDim2.fromScale(1, 1))
	flash.BackgroundTransparency = 1
	flash.ZIndex = 20

	-- A banner at `home` (its top middle) shown at `size`: a holder that grows from its middle, the row of portraits,
	-- and the lettering under it, `width` wide. With `claims` it sets PlayerGui's "KillBanner" while it shows.
	local function makeBanner(home: UDim2, width: number, size: number, claims: boolean)
		local group =
			UiStyle.frame(gui, UDim2.fromOffset(width, PORTRAIT + 12 + TEXT_HEIGHT[4]), home, Vector2.new(0.5, 0))
		group.BackgroundTransparency = 1
		group.Visible = false
		local groupScale = Instance.new("UIScale")
		groupScale.Parent = group

		local rays = UiStyle.frame(
			group,
			UDim2.fromOffset(10, 10),
			UDim2.new(0.5, 0, 0, PORTRAIT + 12 + 60),
			Vector2.new(0.5, 0.5)
		)
		rays.BackgroundTransparency = 1
		for i = 1, 12 do
			local ray = UiStyle.frame(rays, UDim2.fromOffset(46, 900), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
			ray.Rotation = i * 15
			ray.BackgroundColor3 = Color3.fromRGB(255, 214, 110)
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = ray
		end

		local row = UiStyle.frame(
			group,
			UDim2.fromOffset(PORTRAIT * 2 + 150, PORTRAIT),
			UDim2.fromScale(0.5, 0),
			Vector2.new(0.5, 0)
		)
		row.BackgroundTransparency = 1
		-- Behind the crown's taker, a halo of short gold rays.
		local halo =
			UiStyle.frame(row, UDim2.fromOffset(10, 10), UDim2.new(0.5, 0, 0, PORTRAIT / 2), Vector2.new(0.5, 0.5))
		halo.BackgroundTransparency = 1
		halo.ZIndex = 0
		halo.Visible = false
		for i = 1, 8 do
			local ray = UiStyle.frame(
				halo,
				UDim2.fromOffset(18, PORTRAIT * 2.2),
				UDim2.fromScale(0.5, 0.5),
				Vector2.new(0.5, 0.5)
			)
			ray.Rotation = i * 22.5
			ray.BackgroundColor3 = Color3.fromRGB(255, 214, 110)
			ray.ZIndex = 0
			UiStyle.corner(ray, UDim.new(0.5, 0))
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = ray
		end
		local killerRing, killerImage = portrait(row, PORTRAIT, UDim2.fromScale(0, 0))
		local victimRing, victimImage = portrait(row, PORTRAIT, UDim2.fromScale(1, 0), Vector2.new(1, 0))
		local swords = UiStyle.frame(row, UDim2.fromOffset(80, 80), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		swords.BackgroundTransparency = 1
		cross(swords, 86, 14, C.Gold, C.Edge)
		local struck = cross(victimRing, PORTRAIT * 0.9, 12, Color3.fromRGB(214, 40, 40), Color3.fromRGB(70, 10, 10))
		-- The crown worn on the portrait: its rim over the ring's top, as on a head.
		local crown = Instance.new("ImageLabel")
		crown.BackgroundTransparency = 1
		crown.Image = Assets.SunCrown
		crown.AnchorPoint = Vector2.new(0.5, 1)
		-- Loaded now, so the crown shows with the portrait the first time it is taken.
		task.spawn(ContentProvider.PreloadAsync, ContentProvider, { crown })
		local crownFade: Tween? = nil
		crown.Position = UDim2.new(0.5, 0, 0, PORTRAIT * 0.3)
		crown.ZIndex = 4
		crown.Visible = false
		crown.Parent = row

		local textFrame = UiStyle.frame(
			group,
			UDim2.fromOffset(width, TEXT_HEIGHT[4]),
			UDim2.new(0.5, 0, 0, PORTRAIT + 12),
			Vector2.new(0.5, 0)
		)
		textFrame.BackgroundTransparency = 1
		local text, fill = lettering(textFrame, 9)
		local textScale = Instance.new("UIScale")
		textScale.Parent = textFrame

		local serial = 0

		local function setAlpha(transparency: number)
			text.TextTransparency = transparency;
			(text:FindFirstChildOfClass("UIStroke") :: UIStroke).Transparency = transparency
		end

		local function burstCoins(at: UDim2, count: number)
			for _ = 1, count do
				local coin = Instance.new("ImageLabel")
				coin.BackgroundTransparency = 1
				coin.Image = Assets.HudCoin
				coin.AnchorPoint = Vector2.new(0.5, 0.5)
				local across = math.random(30, 52)
				coin.Size = UDim2.fromOffset(across, across)
				coin.Position = at
				coin.ZIndex = 4
				coin.Parent = gui
				local angle = math.random() * math.pi * 2
				local reach = math.random(260, 560)
				tween(coin, 1, {
					Position = at + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach * 0.6),
					Rotation = math.random(-540, 540),
				}, Enum.EasingStyle.Quart)
				tween(coin, 0.45, { ImageTransparency = 1 }, nil, 0.55).Completed:Connect(function()
					coin:Destroy()
				end)
			end
		end

		local function banner(kill: Kill, kind: string, own: boolean, death: boolean)
			serial += 1
			local mine = serial
			if claims then
				player.PlayerGui:SetAttribute("KillBanner", true)
			end
			-- The crown's banner: the taker's portrait alone in the middle, the crown on it, `kind` its text. As the
			-- crown fades it stands alone, bigger, and fades with the banner.
			local crowned = kill.crown == true
			local fading = crowned and kill.fades == true
			local tier = if crowned then 2 else SETTINGS.Tiers[kind] or 1
			showHero(killerRing, killerImage, kill.killerHero, kill.killerTeam, false)
			showHero(victimRing, victimImage, kill.victimHero, kill.victimTeam, true)
			killerRing.Position = UDim2.fromScale(if crowned then 0.5 else 0, 0)
			killerRing.AnchorPoint = Vector2.new(if crowned then 0.5 else 0, 0)
			killerRing.Visible = kill.killerHero ~= nil
			victimRing.Visible = not crowned
			swords.Visible = kill.killerHero ~= nil and not crowned
			crown.Visible = crowned
			crown.Size = if fading then CROWN_ALONE else CROWN_WORN
			crown.Position = UDim2.new(0.5, 0, 0, if fading then PORTRAIT * 0.85 else PORTRAIT * 0.3)
			if crownFade then
				crownFade:Cancel()
			end
			crown.ImageTransparency = 0
			crownFade = if fading then tween(crown, HOLD, { ImageTransparency = 0.75 }, Enum.EasingStyle.Sine) else nil
			halo.Visible = crowned and not fading
			halo.Rotation = 0
			tween(halo, HOLD + 0.4, { Rotation = 30 }, Enum.EasingStyle.Linear)
			for _, bar in struck do
				bar.Visible = false
			end
			text.Text = if crowned then kind else SETTINGS.Texts[kind] or kind
			if death then
				fill.Color = DEATH_FILL
			elseif fading then
				fill.Color = FILLS[1]
			elseif own then
				fill.Color = FILLS[tier]
			else
				local colour = teamColour(kill.killerTeam)
				fill.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.55), colour)
			end
			textFrame.Size = UDim2.fromOffset(width, TEXT_HEIGHT[if own then tier else 1])
			rays.Visible = own and tier >= 3
			rays.Rotation = 0
			tween(rays, HOLD + 0.4, { Rotation = 40 }, Enum.EasingStyle.Linear)

			group.Visible = true
			group.Position = home
			groupScale.Scale = size * 2.4
			group.Rotation = -6
			setAlpha(1)
			textScale.Scale = 1
			tween(groupScale, 0.34, { Scale = size }, Enum.EasingStyle.Back)
			tween(group, 0.34, { Rotation = 0 }, Enum.EasingStyle.Back)
			tween(text, 0.16, { TextTransparency = 0 })
			tween(text:FindFirstChildOfClass("UIStroke") :: UIStroke, 0.16, { Transparency = 0 })

			-- The player's own kills and death go before every other sound (UiSound.announce); the crown's calls wait
			-- their turn and are left out while one plays.
			if crowned then
				if not UiSound.announcing() then
					UiSound.play(
						if own then STINGS[tier] elseif fading then "CrownFades" else "CrownEnemy",
						if own then STING_VOLUME else nil
					)
				end
			elseif own then
				UiSound.announce(STINGS[tier] or STINGS[1], STING_VOLUME)
			elseif death then
				UiSound.announce("Death", STING_VOLUME)
			end

			task.delay(0.26, function()
				if mine ~= serial then
					return
				end
				for _, bar in struck do
					bar.Visible = true
					bar.Size = UDim2.fromOffset(12, 0)
					tween(bar, 0.14, { Size = UDim2.fromOffset(12, PORTRAIT * 0.9) })
				end
				if own and (not crowned or kill.killer == player) then
					flash.BackgroundColor3 = Color3.new(1, 1, 1)
					flash.BackgroundTransparency = 1 - 0.12 * tier
					tween(flash, 0.35, { BackgroundTransparency = 1 })
					HeroCamera.shake(0.12 + 0.08 * tier, 0.25)
					if tier >= 2 and not crowned then
						burstCoins(home + UDim2.fromOffset(0, PORTRAIT + 12 + 50), 6 * tier)
					end
					task.spawn(function()
						for i = 5, 1, -1 do
							if mine ~= serial then
								return
							end
							group.Position = home + UDim2.fromOffset(math.random(-i, i) * 2, math.random(-i, i) * 2)
							task.wait(0.03)
						end
						group.Position = home
					end)
				elseif death then
					flash.BackgroundColor3 = Color3.fromRGB(90, 0, 0)
					flash.BackgroundTransparency = 0.6
					tween(flash, 0.8, { BackgroundTransparency = 1 })
				end
			end)

			task.delay(HOLD, function()
				if mine ~= serial then
					return
				end
				tween(groupScale, 0.4, { Scale = size * 0.85 })
				tween(text, 0.4, { TextTransparency = 1 })
				tween(text:FindFirstChildOfClass("UIStroke") :: UIStroke, 0.4, { Transparency = 1 })
				tween(group, 0.4, { Position = home - UDim2.fromOffset(0, 30) })
				task.delay(0.4, function()
					if mine == serial then
						group.Visible = false
						if claims then
							player.PlayerGui:SetAttribute("KillBanner", false)
						end
					end
				end)
			end)
		end
		return banner
	end

	local mine = makeBanner(UDim2.new(0.5, 0, 0, BANNER_TOP), MIDDLE_WIDTH, 1, true)
	local others = makeBanner(
		UDim2.new(1, -(BANNER_SIDE + SIDE_WIDTH * OTHERS_SCALE / 2), 0, BANNER_TOP),
		SIDE_WIDTH,
		OTHERS_SCALE,
		false
	)

	-- The bounty flying home.
	local function bounty(kill: Kill)
		local camera = Workspace.CurrentCamera
		local hud = player.PlayerGui:FindFirstChild("Hud")
		local pill = hud and hud:FindFirstChild("Coins", true)
		if not camera or kill.coins <= 0 then
			return
		end
		local point, visible = camera:WorldToViewportPoint(kill.at + Vector3.new(0, 2, 0))
		local from = if visible
			then (Vector2.new(point.X, point.Y) - gui.AbsolutePosition) / scale.Scale
			else gui.AbsoluteSize / 2 / scale.Scale
		local count = math.clamp(math.round(kill.coins / COIN_WORTH), 4, COINS_MAX)
		local each = kill.coins / count
		if pill then
			pill:SetAttribute("Held", (pill:GetAttribute("Held") or 0) + kill.coins)
		end

		local plus = UiStyle.text(gui, "+" .. UiStyle.thousands(kill.coins), 44, C.Xp, C.Edge)
		plus.Size = UDim2.fromOffset(240, 50)
		plus.AnchorPoint = Vector2.new(0.5, 0.5)
		plus.Position = UDim2.fromOffset(from.X, from.Y - 30)
		plus.ZIndex = 6
		local plusScale = Instance.new("UIScale")
		plusScale.Scale = 0.3
		plusScale.Parent = plus
		tween(plusScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(plus, 1.1, { Position = plus.Position - UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Quad, 0.2)
		tween(plus, 0.4, { TextTransparency = 1 }, nil, 0.9)
		tween(plus:FindFirstChildOfClass("UIStroke") :: UIStroke, 0.4, { Transparency = 1 }, nil, 0.9).Completed:Connect(
			function()
				plus:Destroy()
			end
		)

		for i = 1, count do
			local coin = Instance.new("ImageLabel")
			coin.BackgroundTransparency = 1
			coin.Image = Assets.HudCoin
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Size = UDim2.fromOffset(40, 40)
			coin.Position = UDim2.fromOffset(from.X, from.Y)
			coin.ZIndex = 5
			coin.Parent = gui
			local angle = math.random() * math.pi * 2
			local out = from + Vector2.new(math.cos(angle), math.sin(angle) * 0.7) * math.random(50, 130)
			tween(
				coin,
				BURST,
				{ Position = UDim2.fromOffset(out.X, out.Y), Rotation = math.random(-200, 200) },
				Enum.EasingStyle.Quad
			)
			task.delay(BURST + i * 0.04, function()
				local counter = counterAt(gui, scale.Scale) or from
				tween(
					coin,
					FLIGHT,
					{ Position = UDim2.fromOffset(counter.X, counter.Y), Size = UDim2.fromOffset(26, 26) },
					Enum.EasingStyle.Quad
				).Completed:Connect(function()
					coin:Destroy()
					UiSound.play("Coin", nil, 0.92 + math.random() * 0.2)
					if pill then
						pill:SetAttribute("Held", math.max(0, (pill:GetAttribute("Held") or 0) - each))
						local bump = pill:FindFirstChild("Bump") :: UIScale?
						if not bump then
							local made = Instance.new("UIScale")
							made.Name = "Bump"
							made.Parent = pill
							bump = made
						end
						(bump :: UIScale).Scale = 1.12
						tween(bump :: UIScale, 0.18, { Scale = 1 })
					end
				end)
			end)
		end
	end

	-- The feed over the minimap, newest at the foot.
	local feed = UiStyle.frame(
		gui,
		UDim2.fromOffset(ROW_WIDTH, ROWS * (ROW_HEIGHT + 8)),
		UDim2.new(1, -FEED_RIGHT, 1, -FEED_BOTTOM),
		Vector2.new(1, 1)
	)
	feed.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout")
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = feed
	local order = 0

	local function addRow(kill: Kill)
		order += 1
		local outer, inner = UiStyle.panel(feed, UDim2.fromOffset(ROW_WIDTH, ROW_HEIGHT), nil, nil, 12, 4)
		outer.LayoutOrder = order
		local colour = teamColour(kill.killerTeam);
		(outer:FindFirstChildOfClass("UIGradient") :: UIGradient).Color =
			ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.25), colour);
		(inner:FindFirstChildOfClass("UIGradient") :: UIGradient).Color =
			ColorSequence.new(Color3.fromRGB(60, 46, 36), Color3.fromRGB(34, 26, 20))
		local size = ROW_HEIGHT - 12
		if kill.killerHero then
			local ring, image = portrait(inner, size, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
			showHero(ring, image, kill.killerHero, kill.killerTeam, false)
			local mark =
				UiStyle.frame(inner, UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
			mark.BackgroundTransparency = 1
			cross(mark, 30, 6, C.Gold, C.Edge)
		else
			local died = UiStyle.text(inner, "SLAIN", 22, C.Cream, C.Edge)
			died.Size = UDim2.new(1, -size - 12, 1, 0)
		end
		local ring, image = portrait(inner, size, UDim2.new(1, -6, 0.5, 0), Vector2.new(1, 0.5))
		showHero(ring, image, kill.victimHero, kill.victimTeam, true)
		local rows = {}
		for _, child in feed:GetChildren() do
			if child:IsA("Frame") then
				table.insert(rows, child)
			end
		end
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #rows - ROWS do
			rows[i]:Destroy()
		end
		local rowScale = Instance.new("UIScale")
		rowScale.Scale = 0.4
		rowScale.Parent = outer
		tween(rowScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(ROW_LIFE, function()
			if outer.Parent then
				tween(rowScale, 0.3, { Scale = 0 }).Completed:Connect(function()
					outer:Destroy()
				end)
			end
		end)
	end

	local net = ReplicatedStorage:WaitForChild("Net")
	local event = net:WaitForChild("Kill") :: RemoteEvent
	event.OnClientEvent:Connect(function(kill: Kill)
		if typeof(kill) ~= "table" then
			return
		end
		local own = kill.killer == player
		local death = kill.victim == player
		addRow(kill)
		local where = if own or death then mine else others
		if death then
			mine(kill, "Own", false, true)
		elseif own then
			mine(kill, kill.kind, true, false)
		elseif kill.kind ~= "Died" then
			others(kill, kill.kind, false, false)
		end
		if kill.wipe then
			task.delay(if death or own or kill.kind ~= "Died" then WIPE_AFTER else 0, function()
				where(kill, "Wipeout", own, false)
			end)
		end
		if own then
			bounty(kill)
		end
	end)

	-- The player's team, kept while he waits to respawn without a character.
	local myTeam: string? = nil
	local crownWas = Workspace:GetAttribute("Crown")
	Workspace:GetAttributeChangedSignal("Crown"):Connect(function()
		local state = Workspace:GetAttribute("Crown")
		local was = crownWas
		crownWas = state
		if state == "Waiting" and (was == "Carried" or was == "Dropped") then
			mine({
				kind = Config.Crown.Texts.Fades,
				crown = true,
				fades = true,
				killerTeam = "Blue",
				victimTeam = "Blue",
				coins = 0,
				at = Vector3.zero,
			}, Config.Crown.Texts.Fades, false, false)
			return
		end
		if state ~= "Carried" then
			return
		end
		-- The taker's own attribute can arrive a moment after the crown's state.
		local carrier: Model? = nil
		for _ = 1, 10 do
			for _, model in CollectionService:GetTagged("Combatant") do
				if model:IsA("Model") and model:GetAttribute("Crown") == true then
					carrier = model
				end
			end
			if carrier then
				break
			end
			task.wait(0.1)
		end
		local team = Workspace:GetAttribute("CrownTeam") or "Blue"
		local taker = if carrier then Players:GetPlayerFromCharacter(carrier) else nil
		myTeam = player.Character and player.Character:GetAttribute("Team") or myTeam
		local ally = myTeam == team
		local texts = Config.Crown.Texts
		local text = if taker == player then texts.Own elseif ally then texts.Ally else texts.Enemy
		mine({
			kind = text,
			crown = true,
			killer = taker,
			killerHero = carrier and carrier:GetAttribute("Hero"),
			killerTeam = team,
			victimTeam = team,
			coins = 0,
			at = Vector3.zero,
		}, text, ally, false)
	end)
end

return KillFeed

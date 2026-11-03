-- The party (design 10, Net.Party, server PartyService): the panel on the Play page with its leader (a crown), its
-- members and the empty places, where "+" invites. An invite goes to a player in this lobby, picked from a list, or
-- to a Roblox friend through Roblox's own invite (SocialService, which brings him into the party when he comes in).
-- An invite that comes in shows as a card to accept or decline. The leader starts the queue and may remove members;
-- a member may leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranks = require(ReplicatedStorage.Shared.Ranks)
local UiSound = require(script.Parent.Parent.UiSound)
local UiStyle = require(script.Parent.Parent.UiStyle)
local Widgets = require(script.Parent.Parent.Widgets)

local Party = {}

local C = UiStyle.Colors
local W = Widgets.Colors
local ROW = 124

export type Member = { userId: number, name: string, level: number?, shown: number?, division: number? }
export type State = { leader: number, members: { Member } }

local state: State = { leader = 0, members = {} }
local changed = Instance.new("BindableEvent")
local event: RemoteEvent

function Party.state(): State
	return state
end

function Party.isLeader(): boolean
	return state.leader == 0 or state.leader == Players.LocalPlayer.UserId
end

function Party.onChanged(callback: () -> ()): RBXScriptConnection
	return changed.Event:Connect(callback)
end

-- The list of players in this lobby to invite.
local function invitePicker(gui: ScreenGui, api: any)
	local holder = Widgets.popup(gui, "Invite")
	local veil = Widgets.veil(holder)
	local outer, _, body = Widgets.panel(
		holder,
		UDim2.fromOffset(560, 640),
		UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5),
		"INVITE",
		32
	)
	local close =
		Widgets.button(outer, "X", "Gold", UDim2.fromOffset(54, 54), UDim2.new(1, 14, 0, -14), Vector2.new(1, 0), 30)
	Widgets.paint(close, "Cream")
	local friends = Widgets.button(
		body,
		"INVITE FRIENDS",
		"Blue",
		UDim2.fromOffset(460, 70),
		UDim2.new(0.5, 0, 0, 10),
		Vector2.new(0.5, 0),
		32
	)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, -30, 1, -110)
	scroll.Position = UDim2.fromOffset(15, 96)
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = C.GoldDark
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	Widgets.list(scroll, "Vertical", 8)

	local function done()
		holder:Destroy()
	end
	close.Activated:Connect(done)
	veil.Activated:Connect(done)
	friends.Activated:Connect(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = "Join my party in Defend The Master!"
		-- The leader and his server: a friend who comes in elsewhere is sent there (server PartyService).
		options.LaunchData = Players.LocalPlayer.UserId .. ":" .. game.JobId
		local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, Players.LocalPlayer)
		if ok and can then
			pcall(SocialService.PromptGameInvite, SocialService, Players.LocalPlayer, options)
		else
			api.notice("Inviting friends is not possible here.", true)
		end
	end)

	local inParty = {}
	for _, m in state.members do
		inParty[m.userId] = true
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer and not inParty[other.UserId] then
			count += 1
			local row = UiStyle.frame(scroll, UDim2.new(1, -12, 0, 76))
			row.BackgroundColor3 = W.Stripe
			row.LayoutOrder = count
			UiStyle.corner(row, 10)
			Widgets.avatar(row, other.UserId, 60, UDim2.fromOffset(8, 8))
			local name = Widgets.label(row, other.DisplayName, 28, C.Ink, "Left")
			name.Size = UDim2.new(1, -250, 1, 0)
			name.Position = UDim2.fromOffset(80, 0)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local invite, inviteText = Widgets.button(
				row,
				"INVITE",
				"Gold",
				UDim2.fromOffset(140, 54),
				UDim2.new(1, -10, 0.5, 0),
				Vector2.new(1, 0.5),
				26
			)
			invite.Activated:Connect(function()
				event:FireServer("Invite", other.UserId)
				inviteText.Text = "SENT"
				Widgets.enable(invite, false, "Gold")
			end)
		end
	end
	if count == 0 then
		local none = Widgets.label(scroll, "Nobody else is in this lobby. Invite your friends!", 24, W.Muted)
		none.Size = UDim2.new(1, 0, 0, 80)
		none.TextWrapped = true
	end
end

-- The card of an invite that came in.
local function invitation(gui: ScreenGui, from: number, name: string)
	local holder = Widgets.popup(gui, "Invitation")
	-- Tall enough that the buttons stand clear under the portrait.
	local card = UiStyle.frame(holder, UDim2.fromOffset(520, 214), UDim2.new(0.5, 0, 0, 130), Vector2.new(0.5, 0))
	card.BackgroundTransparency = 1
	card.Destroying:Connect(function()
		holder:Destroy()
	end)
	local _, inner = UiStyle.panel(card, UDim2.fromScale(1, 1))
	Widgets.avatar(inner, from, 90, UDim2.fromOffset(16, 16))
	local text = Widgets.label(inner, name .. " invites you to his party", 28, C.Ink, "Left")
	text.Size = UDim2.new(1, -130, 0, 90)
	text.Position = UDim2.fromOffset(120, 12)
	text.TextWrapped = true
	local accept = Widgets.button(
		inner,
		"JOIN",
		"Green",
		UDim2.fromOffset(200, 58),
		UDim2.new(0.5, -10, 1, -14),
		Vector2.new(1, 1),
		30
	)
	local decline = Widgets.button(
		inner,
		"NO THANKS",
		"Cream",
		UDim2.fromOffset(200, 58),
		UDim2.new(0.5, 10, 1, -14),
		Vector2.new(0, 1),
		26
	)
	UiSound.play("Pick")
	accept.Activated:Connect(function()
		event:FireServer("Accept", from)
		card:Destroy()
	end)
	decline.Activated:Connect(function()
		event:FireServer("Decline", from)
		card:Destroy()
	end)
	task.delay(30, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

function Party.build(page: Frame, api: any)
	-- `page` is the Play page's column (PlayPage), the player's card above.
	local _, inner, body = Widgets.panel(page, UDim2.fromOffset(380, 590), UDim2.fromOffset(40, 314), nil, "PARTY", 32)
	local rows = UiStyle.frame(body, UDim2.new(1, -24, 1, -12), UDim2.fromOffset(12, 0))
	rows.BackgroundTransparency = 1
	Widgets.list(rows, "Vertical", 8)
	local leave = Widgets.button(
		inner,
		"LEAVE",
		"Cream",
		UDim2.fromOffset(84, 34),
		UDim2.new(1, -10, 0, 7),
		Vector2.new(1, 0),
		18
	)
	leave.Visible = false
	leave.Activated:Connect(function()
		event:FireServer("Leave")
	end)

	local function draw()
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local members = state.members
		if #members == 0 then
			local me = Players.LocalPlayer
			members = { { userId = me.UserId, name = me.DisplayName } }
		end
		local leaderId = if state.leader ~= 0 then state.leader else Players.LocalPlayer.UserId
		for i = 1, Config.Queue.PartySize do
			local member = members[i]
			local row = UiStyle.frame(rows, UDim2.new(1, 0, 0, ROW))
			row.LayoutOrder = i
			row.BackgroundColor3 = W.Stripe
			row.BackgroundTransparency = if i % 2 == 0 then 0.6 else 1
			UiStyle.corner(row, 8)
			if member then
				Widgets.avatar(row, member.userId, 96, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
				local name = Widgets.label(row, member.name, 28, C.Ink, "Left")
				name.Size = UDim2.new(1, -124, 0, 34)
				name.Position = UDim2.fromOffset(116, 24)
				name.TextTruncate = Enum.TextTruncate.AtEnd
				local isLeader = member.userId == leaderId
				local tag = if isLeader
					then "LEADER"
					else (if member.shown then string.upper(Ranks.label(member.shown, member.division)) else "")
				local sub = Widgets.label(row, tag, 22, if isLeader then C.GoldDark else W.Muted, "Left")
				sub.Size = UDim2.new(1, -124, 0, 28)
				sub.Position = UDim2.fromOffset(116, 62)
				if
					Party.isLeader()
					and not isLeader
					and member.userId ~= Players.LocalPlayer.UserId
					and state.leader ~= 0
				then
					local kick = Widgets.button(
						row,
						"X",
						"Cream",
						UDim2.fromOffset(40, 40),
						UDim2.new(1, -6, 0, 6),
						Vector2.new(1, 0),
						22
					)
					kick.Activated:Connect(function()
						event:FireServer("Kick", member.userId)
					end)
				end
			else
				local plus = Widgets.button(
					row,
					"+",
					"Dark",
					UDim2.fromOffset(96, 96),
					UDim2.new(0, 8, 0.5, 0),
					Vector2.new(0, 0.5),
					54
				)
				local text = Widgets.label(row, "INVITE", 30, C.Ink, "Left")
				text.Size = UDim2.new(1, -130, 1, 0)
				text.Position = UDim2.fromOffset(130, 0)
				local enabled = Party.isLeader()
				Widgets.enable(plus, enabled, "Dark")
				plus.Activated:Connect(function()
					if plus.Active then
						invitePicker(api.gui, api)
					end
				end)
			end
		end
		leave.Visible = state.leader ~= 0 and #state.members > 1
	end

	event = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Party") :: RemoteEvent
	event.OnClientEvent:Connect(function(kind: string, payload: any, bad: boolean?)
		if kind == "State" then
			state = payload
			draw()
			changed:Fire()
		elseif kind == "Invited" then
			invitation(api.gui, payload.from, payload.name)
		elseif kind == "Notice" then
			api.notice(payload, bad)
		end
	end)
	event:FireServer("Hello")
	draw()
end

return Party

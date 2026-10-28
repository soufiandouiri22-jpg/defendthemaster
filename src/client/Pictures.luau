-- Every picture the menu's pages and the HUD can show: each "rbxassetid://" in Config and Assets, without Assets'
-- sounds. The loading screen loads them all, so a page shows complete the first time it opens instead of filling in
-- picture by picture (owner, 2026-10-28). A sound missing from SOUNDS only costs one failed request while loading.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local SOUNDS = {
	Music = true,
	MenuMusic = true,
	BuySting = true,
	CountTick = true,
	FightBoom = true,
	DrumSting = true,
	VictorySting = true,
	DefeatSting = true,
	UiHover = true,
	UiSelect = true,
	UiSwipe = true,
	UiBack = true,
	ClothSwing = true,
	PaperHandling = true,
	ChainMail = true,
	CoinJingle = true,
	CoinBounce = true,
	WoodThud = true,
	MagicTwirl = true,
	MagicGlow = true,
	MagicExit = true,
	FallingShimmer = true,
	PowerClunk = true,
	CorkPull = true,
	SwordDraw = true,
	EvilBell = true,
	CrownDrop = true,
	FireWhoosh = true,
	FireBurst = true,
	RockKnock = true,
	RockBreak = true,
	GlassShards = true,
	DeepThud = true,
}

local Pictures = {}

-- The pictures' content ids, each once.
function Pictures.all(): { string }
	local found: { [string]: boolean } = {}
	local seen: { [any]: boolean } = {}
	local function walk(value: any)
		if type(value) == "string" then
			if string.sub(value, 1, 13) == "rbxassetid://" then
				found[value] = true
			end
		elseif type(value) == "table" and not seen[value] then
			seen[value] = true
			for _, inner in value do
				walk(inner)
			end
		end
	end
	walk(Config)
	for name, value in Assets :: { [string]: any } do
		if not SOUNDS[name] then
			walk(value)
		end
	end
	local list = {}
	for id in found do
		table.insert(list, id)
	end
	return list
end

return Pictures

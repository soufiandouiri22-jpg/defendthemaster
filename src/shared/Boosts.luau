-- The boost in play (Config.Boosts, BoostService), read from its attributes on Workspace: "Boost" ("Waiting", "Ready"
-- on the plateau, "Carried" or "Dropped"), "BoostKind" (the boost in play, or the next one while waiting), "BoostAt"
-- (the server time it appears while waiting), "BoostSpot" (where it floats while ready or dropped), "BoostEnds" (the
-- server time it fades, once taken) and "BoostTeam" (the carrier's team). The carrier's player or bot and his hero
-- both have the attribute "Boost". Shared, so the server and the player's client reckon speed and cooldowns alike.

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local Boosts = {}

export type Boost = {
	Name: string,
	Effect: string,
	Carrier: number,
	Team: number,
	Short: string,
	Own: string,
	Ally: string,
	Enemy: string,
	Color: Color3,
	Model: string,
	Worn: number,
	Image: string?,
	ImageSize: Vector2?,
	ImageScale: number?,
	FadeScale: number?,
}

-- The boost in play or coming next, and its id.
function Boosts.current(): (Boost?, string?)
	local kind = Workspace:GetAttribute("BoostKind")
	local boost = if typeof(kind) == "string" then Config.Boosts.List[kind] else nil
	return boost, if boost then kind else nil
end

-- The share `effect` gives the hero of `actor` (a player or bot) now: the carrier's or his team's while his team
-- carries a boost with that effect, else 0.
function Boosts.bonus(actor: Instance, effect: string): number
	if Workspace:GetAttribute("Boost") ~= "Carried" then
		return 0
	end
	local boost = Boosts.current()
	if not boost or boost.Effect ~= effect or actor:GetAttribute("Team") ~= Workspace:GetAttribute("BoostTeam") then
		return 0
	end
	return if actor:GetAttribute("Boost") == true then boost.Carrier else boost.Team
end

local function percent(share: number): string
	local value = share * 100
	return if value == math.floor(value) then string.format("%d%%", value) else string.format("%.1f%%", value)
end

-- The line under the boost's banner for `who` ("Own", "Ally" or "Enemy"), its shares filled in.
function Boosts.line(boost: Boost, who: string): string
	local line = (boost :: any)[who] :: string
	line = string.gsub(line, "{carrier}", function()
		return percent(boost.Carrier)
	end)
	line = string.gsub(line, "{team}", function()
		return percent(boost.Team)
	end)
	return line
end

return Boosts

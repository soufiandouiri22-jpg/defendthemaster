-- When the arena's traps strike (Config.Spikes, Config.FireGrates): from the server's clock, so HazardService and
-- HazardView keep the same beat without telling each other.

local Hazards = {}

export type Phase = "Warn" | "Strike" | "Rest"

export type Settings = {
	Every: number,
	Warn: number,
	Offset: number?,
	-- How long it strikes: a spike tile's spikes stand up, a grate burns.
	Up: number?,
	Burn: number?,
}

-- Where the trap is in its round at server time `now`: warning, striking or resting, and the seconds since that
-- began.
function Hazards.phase(settings: Settings, now: number): (Phase, number)
	local t = (now - (settings.Offset or 0)) % settings.Every
	if t < settings.Warn then
		return "Warn", t
	end
	t -= settings.Warn
	local strike = settings.Up or settings.Burn or 0
	if t < strike then
		return "Strike", t
	end
	return "Rest", t - strike
end

return Hazards

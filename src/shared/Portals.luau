-- The portals' shape (Config.Portals): where each ring stands, the middle and radius of its opening, its stones and
-- its pad's two steps, in studs, measured from the kit's portal_ring (Art/Models/Portal/portal_ring.glb, 1.844 tall in
-- its own size). Shared by PortalService (who goes through, the stones' collision) and PortalView (the vortex).

local Config = require(script.Parent.Config)

local Portals = {}

local SETTINGS = Config.Portals
-- In the model's own size: the opening's middle above its foot and its radius, how far out the stones reach and how
-- deep they are either side of the middle, and the pad's steps (radius, top).
local HOLE_UP, HOLE_RADIUS = 0.9, 0.64
local STONES_OUT, STONES_DEPTH = 0.945, 0.185
local STEPS = { { 0.95, 0.12 }, { 0.75, 0.2375 } }

export type Step = {
	radius: number,
	top: number,
}

export type Portal = {
	name: string,
	-- On the sand under the ring's middle, its front (-Z) towards its team's nearest spawn pad.
	frame: CFrame,
	-- The opening's middle, in the frame.
	hole: Vector3,
	holeRadius: number,
	stonesOut: number,
	stonesDepth: number,
	steps: { Step },
	-- The top of the pad.
	top: number,
}

function Portals.all(): { [string]: Portal }
	local scale = SETTINGS.Scale
	local all = {}
	for name, spot in SETTINGS.Spots do
		local steps = {}
		for _, step in STEPS do
			table.insert(steps, { radius = step[1] * scale, top = step[2] * scale })
		end
		all[name] = {
			name = name,
			frame = CFrame.lookAt(spot.At, spot.Faces),
			hole = Vector3.new(0, HOLE_UP * scale, 0),
			holeRadius = HOLE_RADIUS * scale,
			stonesOut = STONES_OUT * scale,
			stonesDepth = STONES_DEPTH * scale,
			steps = steps,
			top = steps[#steps].top,
		}
	end
	return all
end

-- The portal `name` leads to.
function Portals.other(name: string): string
	return SETTINGS.Spots[name].To
end

return Portals

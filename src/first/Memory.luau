-- What the memory is spent on and what the world holds, for the log (Trace on the client, TraceService on the server),
-- so a leak shows as the one number that keeps rising (owner, 2026-11-04). Each sample is a flat table of at most 12
-- numbers, all a log entry may carry.

local Stats = game:GetService("Stats")

local Memory = {}

-- The engine's own groups (megabytes), by the short name they carry in the log.
local TAGS = {
	lua = Enum.DeveloperMemoryTag.LuaHeap,
	instances = Enum.DeveloperMemoryTag.Instances,
	signals = Enum.DeveloperMemoryTag.Signals,
	texture = Enum.DeveloperMemoryTag.GraphicsTexture,
	character = Enum.DeveloperMemoryTag.GraphicsTextureCharacter,
	meshes = Enum.DeveloperMemoryTag.GraphicsMeshParts,
	animation = Enum.DeveloperMemoryTag.Animation,
	sounds = Enum.DeveloperMemoryTag.Sounds,
	gui = Enum.DeveloperMemoryTag.Gui,
	parts = Enum.DeveloperMemoryTag.BaseParts,
}

-- The kinds of object counted under a root, by their name in the log; the first class that fits an object counts it.
local KINDS = {
	{ "highlights", "Highlight" },
	{ "sounds", "Sound" },
	{ "emitters", "ParticleEmitter" },
	{ "trails", "Trail" },
	{ "beams", "Beam" },
	{ "joints", "JointInstance" },
	{ "constraints", "Constraint" },
	{ "attachments", "Attachment" },
	{ "parts", "BasePart" },
	{ "models", "Model" },
}

-- The whole memory (megabytes), the number of objects there are, and each group's megabytes.
function Memory.sample(): { [string]: number }
	local sample = {
		total = math.floor(Stats:GetTotalMemoryUsageMb()),
		count = Stats.InstanceCount,
	}
	for name, tag in TAGS do
		sample[name] = math.floor(Stats:GetMemoryUsageMbForTag(tag) * 10) / 10
	end
	return sample
end

-- How many objects are counted before the count waits a frame, so a large world does not hitch.
local STEP = 4000

-- How many of each kind of object lie under `root`, and all of them together; it yields.
function Memory.objects(root: Instance): { [string]: number }
	local counts: { [string]: number } = { all = 0 }
	for _, kind in KINDS do
		counts[kind[1]] = 0
	end
	for i, item in root:GetDescendants() do
		if i % STEP == 0 then
			task.wait()
		end
		counts.all += 1
		for _, kind in KINDS do
			if item:IsA(kind[2]) then
				counts[kind[1]] += 1
				break
			end
		end
	end
	return counts
end

return Memory

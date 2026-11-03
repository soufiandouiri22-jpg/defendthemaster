-- The first thing the client runs: its part of the game's log (Trace), then the loading screen (Loading) until the
-- game and the client are ready.
local Trace = require(script.Parent:WaitForChild("Trace"))
local Loading = require(script.Parent:WaitForChild("Loading"))

Trace.start()
Loading.show()
-- An error in its own waiting must not leave the player behind a black screen for good.
local ok, problem = pcall(Loading.finish)
if not ok then
	Trace.mark("loading.failed", { error = tostring(problem) })
	Loading.abandon()
end

-- Server entry point of Defend The Master.
local ColosseumBuilder = require(script.ColosseumBuilder)
local Economy = require(script.Economy)
local MinionModel = require(script.MinionModel)
local MinionService = require(script.MinionService)

local layout = ColosseumBuilder.build()
Economy.start()
MinionModel.publish()
MinionService.start(layout)
print("[DefendTheMaster] server started")

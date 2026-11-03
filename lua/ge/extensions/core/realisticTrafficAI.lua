local M = {}

M.dependencies = {
  "gameplay_traffic",
}

local manager = require('/lua/ge/extensions/realisticTrafficAI/manager')

M.start = manager.start
M.stop = manager.stop
M.toggle = manager.toggle
M.getStatus = manager.getStatus

function M.onExtensionLoaded()
  manager.onExtensionLoaded()
end

function M.onExtensionUnloaded()
  manager.onExtensionUnloaded()
end

function M.onUpdate(dtReal, dtSim)
  manager.onUpdate(dtReal, dtSim)
end

function M.onClientStartMission()
  manager.onClientStartMission()
end

function M.onClientEndMission()
  manager.onClientEndMission()
end

return M

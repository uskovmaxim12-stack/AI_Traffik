local config = require('/lua/ge/extensions/realisticTrafficAI/config')

local M = {}
local state = {
  lastCheck = -999,
  lastSpawn = -999,
}

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

function M.estimateTarget()
  if not config.population.auto then
    return clamp(config.population.targetActive, config.population.minimum, config.population.maximum)
  end

  local cores = 8
  pcall(function()
    cores = (Engine.Platform.getCPUInfo().coresLogical or 8)
  end)

  -- Rough physics-oriented scaling. We intentionally cap the result so the
  -- mod does not blindly spawn hundreds of full physics vehicles on every PC.
  local estimate = math.floor(cores * 4.5 + 0.5)
  return clamp(estimate, config.population.minimum, config.population.maximum)
end

function M.getCurrentCount()
  local list = nil
  local ok = pcall(function()
    list = extensions.gameplay_traffic.getTrafficList()
  end)

  if not ok or type(list) ~= "table" then
    return 0
  end

  local n = 0
  for _ in pairs(list) do n = n + 1 end
  return n
end

function M.configure()
  local target = M.estimateTarget()

  pcall(function()
    extensions.gameplay_traffic.setTrafficVars({
      aiMode = "traffic",
      aiAware = "auto",
      baseAggression = 0.30,
      spawnValue = 1.10,
      enableRandomEvents = true,
    })
  end)

  pcall(function()
    if extensions.gameplay_traffic.setActiveAmount then
      extensions.gameplay_traffic.setActiveAmount(target)
    end
  end)

  return target
end

function M.ensure(target, now)
  local current = M.getCurrentCount()
  if current >= target then
    return current, 0
  end

  if now - state.lastSpawn < config.general.populationCheckInterval then
    return current, 0
  end

  local missing = math.min(target - current, config.population.spawnBatch)
  if missing <= 0 then
    return current, 0
  end

  local spawned = false

  -- BeamNG's traffic API can create a new traffic group without deleting
  -- already spawned traffic when ignoreDelete=true. allMods/allConfigs keeps
  -- third-party traffic-capable vehicles eligible.
  pcall(function()
    local fn = extensions.gameplay_traffic.setupTraffic
    if type(fn) == "function" then
      local result = fn(
        missing,
        0,
        {
          ignoreDelete = true,
          autoAdjustAmount = false,
          allMods = config.population.useAllMods,
          allConfigs = config.population.useAllConfigs,
          simpleVehs = config.population.simpleVehicles,
          activeAmount = target,
        }
      )
      spawned = result ~= false
    end
  end)

  if spawned then
    state.lastSpawn = now
  end

  return current, missing
end

function M.reset()
  state.lastCheck = -999
  state.lastSpawn = -999
end

return M

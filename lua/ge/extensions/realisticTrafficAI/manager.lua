local config = require('/lua/ge/extensions/realisticTrafficAI/config')
local personality = require('/lua/ge/extensions/realisticTrafficAI/personality')
local commands = require('/lua/ge/extensions/realisticTrafficAI/commands')
local perception = require('/lua/ge/extensions/realisticTrafficAI/perception')
local decision = require('/lua/ge/extensions/realisticTrafficAI/decision')
local population = require('/lua/ge/extensions/realisticTrafficAI/population')

local M = {}

local runtime = {
  enabled = false,
  started = false,
  accumulator = 0,
  populationAccumulator = 0,
  startCountdown = 0,
  now = 0,
  targetPopulation = 0,
  controlled = 0,
  lastVehicleCount = 0,
}

local function message(text)
  if not config.general.showMessages then return end
  pcall(function()
    guihooks.trigger("Message", {
      ttl = 3,
      msg = text,
      category = "realisticTrafficAI",
      icon = "traffic",
    })
  end)
end

local function isFreeroam()
  local state = nil
  pcall(function()
    state = core_gamestate and core_gamestate.state and core_gamestate.state.state
  end)
  return state == "freeroam"
end

local function getTrafficIds()
  local list = nil
  local ok = pcall(function()
    list = extensions.gameplay_traffic.getTrafficList()
  end)
  if not ok or type(list) ~= "table" then
    return {}
  end

  local ids = {}
  for id in pairs(list) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

local function getPlayerId()
  local id = 0
  pcall(function() id = be:getPlayerVehicleID(0) or 0 end)
  return id
end

local function setEnabled(value)
  runtime.enabled = value == true

  if runtime.enabled then
    runtime.targetPopulation = population.configure()
    message("Realistic Traffic AI: ON")
  else
    message("Realistic Traffic AI: OFF")
  end
end

local function initializeIfNeeded()
  if runtime.started then return end
  runtime.started = true
  runtime.targetPopulation = population.configure()

  if config.general.showMessages then
    message("Realistic Traffic AI: loaded (" .. config.version .. ")")
  end
end

local function controlVehicle(ego, world, dt, now, playerId)
  local profile = personality.get(ego.id)
  profile.lastSeen = now

  commands.ensureBase(ego.obj, profile, now)

  local includePlayer = config.behavior.enablePlayerInteraction
  local perceptionResult = perception.findLead(world, ego, includePlayer)

  local result = decision.evaluate(profile, ego, perceptionResult, dt, now)

  profile.state = result.state
  profile.desiredGap = result.desiredGap

  commands.setFollowDistance(ego.obj, result.desiredGap, now)

  if result.passIntent and config.behavior.enableNativeLaneChanges then
    if not profile.nativeAggressionBoosted then
      profile.nativeAggressionBoosted = true
    end
  else
    profile.nativeAggressionBoosted = false
  end

  -- Make the personality update effective immediately after pass-intent changes.
  commands.ensureBase(ego.obj, profile, now)

  if result.emergency then
    commands.setSpeedLimit(ego.obj, profile, 0, dt, now, true)
  elseif result.targetSpeedKmh ~= nil and config.behavior.enablePredictiveFollowing then
    commands.setSpeedLimit(ego.obj, profile, result.targetSpeedKmh, dt, now, false)
  else
    commands.releaseSpeedLimit(ego.obj, now)
  end

  -- Rare human hesitation: deliberately tiny and heavily rate-limited.
  if profile.hesitationLeft <= 0
      and result.state == "CRUISE"
      and ego.speedKmh > 10
      and math.random() < (profile.hesitationChance * dt) then
    profile.hesitationLeft = profile.hesitationDuration
  end

  if profile.hesitationLeft > 0 then
    profile.hesitationLeft = profile.hesitationLeft - dt
    if result.state == "CRUISE" then
      commands.setSpeedLimit(
        ego.obj,
        profile,
        math.max(5, ego.speedKmh - 4.0),
        dt,
        now,
        false
      )
    end
  end

  runtime.controlled = runtime.controlled + 1
end

function M.start()
  initializeIfNeeded()
  setEnabled(true)
end

function M.stop()
  setEnabled(false)
end

function M.toggle()
  initializeIfNeeded()
  setEnabled(not runtime.enabled)
end

function M.isEnabled()
  return runtime.enabled
end

function M.getStatus()
  return {
    enabled = runtime.enabled,
    targetPopulation = runtime.targetPopulation,
    currentPopulation = runtime.lastVehicleCount,
    controlled = runtime.controlled,
    profiles = personality.count(),
  }
end

function M.onUpdate(dtReal, dtSim)
  runtime.now = runtime.now + (dtReal or 0)
  initializeIfNeeded()

  if not isFreeroam() then
    return
  end

  if not runtime.enabled then
    if config.general.autoStart then
      runtime.startCountdown = runtime.startCountdown + (dtReal or 0)
      if runtime.startCountdown >= 2.0 then
        runtime.startCountdown = 0
        setEnabled(true)
      end
    end
    return
  end

  runtime.accumulator = runtime.accumulator + (dtReal or 0)
  runtime.populationAccumulator = runtime.populationAccumulator + (dtReal or 0)

  if runtime.populationAccumulator >= config.general.populationCheckInterval then
    runtime.populationAccumulator = 0
    runtime.targetPopulation = population.estimateTarget()

    local current = population.getCurrentCount()
    runtime.lastVehicleCount = current

    -- Keep the desired active amount high while letting vanilla traffic
    -- pooling manage vehicles outside the active window.
    pcall(function()
      if extensions.gameplay_traffic.setActiveAmount then
        extensions.gameplay_traffic.setActiveAmount(runtime.targetPopulation)
      end
    end)

    population.ensure(runtime.targetPopulation, runtime.now)
  end

  if runtime.accumulator < config.general.updateInterval then
    return
  end

  local dt = runtime.accumulator
  runtime.accumulator = 0
  runtime.controlled = 0

  local ids = getTrafficIds()
  runtime.lastVehicleCount = #ids

  if #ids == 0 then
    return
  end

  local playerId = getPlayerId()
  local world = perception.snapshot(ids, playerId)

  local playerPos = nil
  if playerId ~= 0 then
    local playerObj = getObjectByID(playerId)
    if playerObj and playerObj.getPosition then
      local ok, p = pcall(function() return playerObj:getPosition() end)
      if ok and p then playerPos = p end
    end
  end

  local maxVehicles = math.min(
    #world.items,
    config.performance.maxControlledVehiclesPerTick
  )

  -- Prioritize the first N sorted traffic vehicles. The stock AI continues
  -- driving all vehicles; our controller is an enhancement pass.
  local handled = 0
  for i = 1, #world.items do
    if handled >= maxVehicles then break end
    local ego = world.items[i]
    if not ego.isPlayer then
      local distanceToPlayer = math.huge
      if playerPos then
        distanceToPlayer = (ego.pos - playerPos):length()
      end

      if not config.performance.reduceFarVehicleWork
          or distanceToPlayer <= config.performance.farVehicleDistance then
        controlVehicle(ego, world, dt, runtime.now, playerId)
        handled = handled + 1
      end
    end
  end
end

function M.onClientStartMission()
  runtime.startCountdown = 0
  runtime.started = false
  runtime.accumulator = 0
  runtime.populationAccumulator = 0
  runtime.targetPopulation = 0
  runtime.lastVehicleCount = 0
  runtime.controlled = 0
  population.reset()
  personality.clear()
  commands.clear()
end

function M.onClientEndMission()
  runtime.enabled = false
  runtime.started = false
  runtime.startCountdown = 0
  runtime.accumulator = 0
  runtime.populationAccumulator = 0
  personality.clear()
  commands.clear()
end

function M.onExtensionLoaded()
  initializeIfNeeded()
end

function M.onExtensionUnloaded()
  runtime.enabled = false
  personality.clear()
  commands.clear()
end

return M

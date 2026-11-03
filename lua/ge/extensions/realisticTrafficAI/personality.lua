local config = require('/lua/ge/extensions/realisticTrafficAI/config')

local M = {}
local profiles = {}

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function hash(n)
  n = tonumber(n) or 1
  n = (n * 1103515245 + 12345) % 2147483647
  if n < 0 then n = -n end
  return n
end

local function rand01(seed)
  local h = hash(seed)
  return (h % 1000000) / 1000000
end

local function range(seed, a, b)
  return a + (b - a) * rand01(seed)
end

local function sign(seed)
  return rand01(seed) < 0.5 and -1 or 1
end

local function build(id)
  local seed = tonumber(id) or 1

  local p = {
    id = id,

    -- Continuous human variation
    speedFactor = range(seed + 11, config.driver.speedFactorMin, config.driver.speedFactorMax),
    aggression = range(seed + 23, config.driver.aggressionMin, config.driver.aggressionMax),
    reactionTime = range(seed + 37, config.driver.reactionMin, config.driver.reactionMax),
    headway = range(seed + 41, config.driver.headwayMin, config.driver.headwayMax),

    comfortBrake = range(seed + 53, config.driver.comfortBrakeMin, config.driver.comfortBrakeMax),

    hesitationChance = config.driver.hesitationChance * range(seed + 61, 0.55, 1.35),
    hesitationDuration = range(seed + 71, config.driver.hesitationMin, config.driver.hesitationMax),

    preferredPassSide = sign(seed + 83),

    -- Runtime state
    state = "CRUISE",
    hesitationLeft = 0,
    nativeAggressionBoosted = false,
    lastSeen = 0,
    lastCommandAt = 0,
    targetSpeedKmh = nil,
    sentSpeedKmh = nil,
    desiredGap = nil,
    sentFollowDistance = nil,
    sentAggression = nil,
    sentAvoid = false,
    releaseSpeedAt = 0,
  }

  return p
end

function M.get(id)
  if not id then return nil end
  if not profiles[id] then
    profiles[id] = build(id)
  end
  return profiles[id]
end

function M.remove(id)
  profiles[id] = nil
end

function M.clear()
  profiles = {}
end

function M.count()
  local n = 0
  for _ in pairs(profiles) do n = n + 1 end
  return n
end

function M.clampAggression(v)
  return clamp(v, 0.15, 0.95)
end

return M

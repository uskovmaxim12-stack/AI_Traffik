local config = require('/lua/ge/extensions/realisticTrafficAI/config')

local M = {}
local state = {}

local function get(id)
  state[id] = state[id] or {
    speed = {sent = nil, smoothed = nil, time = -999},
    follow = {sent = nil, time = -999},
    aggression = {sent = nil, time = -999},
    avoid = {sent = nil, time = -999},
    mode = {sent = nil, time = -999},
  }
  return state[id]
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function canSend(bucket, now, interval)
  return now - (bucket.time or -999) >= interval
end

local function queue(obj, command)
  if not obj or not obj.queueLuaCommand then return false end
  local ok = pcall(function()
    obj:queueLuaCommand(command)
  end)
  return ok
end

local function lerpRate(current, target, factor, dt)
  if current == nil then return target end
  local a = 1.0 - math.pow(factor, math.max(dt, 0.001) * 10.0)
  return current + (target - current) * a
end

function M.ensureBase(obj, profile, now)
  if not obj or not profile then return end
  local id = obj:getId()
  local s = get(id)

  if s.mode.sent ~= "traffic" and canSend(s.mode, now, 1.0) then
    queue(obj, 'ai.setMode("traffic")')
    s.mode.sent = "traffic"
    s.mode.time = now
  end

  local aggr = profile.aggression
  if profile.nativeAggressionBoosted then
    aggr = aggr + config.behavior.nativePassAggressionBoost
  end
  aggr = clamp(aggr, 0.15, 0.95)

  if (s.aggression.sent == nil or math.abs(s.aggression.sent - aggr) >= 0.04)
      and canSend(s.aggression, now, 2.5) then
    queue(obj, string.format('ai.setAggression(%.3f)', aggr))
    s.aggression.sent = aggr
    s.aggression.time = now
  end

  if not s.avoid.sent and canSend(s.avoid, now, 1.0) then
    queue(obj, 'ai.setAvoidCars("on")')
    s.avoid.sent = true
    s.avoid.time = now
  end
end

function M.setFollowDistance(obj, meters, now)
  if not obj then return end
  meters = clamp(tonumber(meters) or 12, 5, config.following.maximumComfortGap)
  local id = obj:getId()
  local s = get(id).follow

  if (s.sent == nil or math.abs(s.sent - meters) >= 1.0)
      and canSend(s, now, 0.9) then
    queue(obj, string.format('ai.setFollowDistance(%.1f)', meters))
    s.sent = meters
    s.time = now
  end
end

function M.setSpeedLimit(obj, profile, targetKmh, dt, now, emergency)
  if not obj or not profile then return end
  local id = obj:getId()
  local b = get(id).speed

  if emergency then
    if canSend(b, now, 0.20) then
      queue(obj, 'ai.setSpeedMode("limit"); ai.setSpeed(0)')
      b.sent = 0
      b.smoothed = 0
      b.time = now
    end
    return
  end

  local minDrop = config.following.maxTargetDropPerSecond * math.max(dt, 0)
  local maxRise = config.following.maxTargetRisePerSecond * math.max(dt, 0)

  if b.smoothed == nil then
    b.smoothed = targetKmh
  else
    local delta = targetKmh - b.smoothed
    if delta < -minDrop then delta = -minDrop end
    if delta > maxRise then delta = maxRise end
    local limitedTarget = b.smoothed + delta
    b.smoothed = lerpRate(b.smoothed, limitedTarget, config.following.speedSmoothing, dt)
  end

  local wanted = math.max(0, b.smoothed)
  local sent = b.sent

  if sent == nil or math.abs(sent - wanted) >= config.following.speedCommandThreshold then
    if canSend(b, now, config.following.speedControllerInterval) then
      queue(obj, string.format('ai.setSpeedMode("limit"); ai.setSpeed(%.2f)', wanted / 3.6))
      b.sent = wanted
      b.time = now
    end
  end
end

function M.releaseSpeedLimit(obj, now)
  if not obj then return end
  local id = obj:getId()
  local b = get(id).speed

  if canSend(b, now, 0.8) then
    queue(obj, 'ai.setSpeed(nil)')
    b.sent = nil
    b.smoothed = nil
    b.time = now
  end
end

function M.resetVehicle(obj, profile, now)
  if not obj or not profile then return end
  local id = obj:getId()
  state[id] = nil
  M.ensureBase(obj, profile, now)
end

function M.remove(id)
  state[id] = nil
end

function M.clear()
  state = {}
end

return M

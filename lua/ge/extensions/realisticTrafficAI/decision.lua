local config = require('/lua/ge/extensions/realisticTrafficAI/config')

local M = {}

local clamp = math.min
local max = math.max

local function bound(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.evaluate(profile, ego, perception, dt, now)
  local result = {
    state = "CRUISE",
    targetSpeedKmh = nil,
    desiredGap = nil,
    emergency = false,
    caution = false,
    queue = false,
    passIntent = false,
  }

  if not profile or not ego then
    return result
  end

  local speed = ego.speedKmh
  local speedMps = ego.speedMps
  local comfortableGap = bound(
    config.following.minimumGap + speedMps * profile.headway,
    config.following.minimumGap,
    config.following.maximumComfortGap
  )

  result.desiredGap = comfortableGap

  if not perception then
    -- Free-flow: return the native AI to its own road-aware target.
    result.state = "CRUISE"
    return result
  end

  local lead = perception.vehicle
  local leadSpeed = lead.speedKmh
  local gap = perception.gap
  local closing = perception.closingMps
  local ttc = perception.ttc

  result.desiredGap = comfortableGap

  -- Severe conflict: let the native AI perform the hard stop.
  if gap <= config.following.minimumGap
      or ttc <= config.following.emergencyTTC then
    result.state = "EMERGENCY_BRAKE"
    result.emergency = true
    result.targetSpeedKmh = 0
    return result
  end

  if ttc <= config.following.hardBrakeTTC then
    result.state = "HARD_FOLLOW"
    result.caution = true
  elseif ttc <= config.following.cautionTTC then
    result.state = "CAUTION"
    result.caution = true
  elseif gap <= comfortableGap * 0.82 then
    result.state = "FOLLOW"
  elseif gap <= comfortableGap * 1.35 then
    result.state = "FOLLOW"
  else
    result.state = "FOLLOW"
  end

  if lead.speedKmh <= config.following.stoppedVehicleSpeed and gap < 35 then
    result.state = "QUEUE"
    result.queue = true
  end

  -- Desired speed is intentionally conservative. The command is a ceiling,
  -- not a direct throttle value; BeamNG's AI retains control of steering,
  -- traction and the final throttle/brake actuation.
  local speedError = gap - comfortableGap

  local gapCorrection = bound(speedError * 0.65, -16, 10)
  local target = leadSpeed + gapCorrection

  -- Closing quickly: target the lead vehicle and then let the native adaptive
  -- controller settle the acceleration/braking.
  if closing > 0.5 then
    target = math.min(target, leadSpeed + 2.5)
  end

  if result.queue then
    target = math.min(target, math.max(0, leadSpeed + 1.0))
  end

  if result.caution then
    target = math.min(target, math.max(0, leadSpeed + 1.5))
  end

  result.targetSpeedKmh = bound(target, 0, 180)

  -- Passing is intentionally delegated to BeamNG's native traffic AI. A slow
  -- leader + an aggressive personality raises the AI aggression briefly.
  if leadSpeed + 12 < speed
      and gap < comfortableGap * 1.25
      and profile.aggression >= config.driver.overtakeThreshold then
    result.passIntent = true
  end

  return result
end

return M

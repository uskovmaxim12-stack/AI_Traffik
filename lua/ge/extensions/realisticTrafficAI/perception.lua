local config = require('/lua/ge/extensions/realisticTrafficAI/config')

local M = {}

local function safePosition(obj)
  if not obj or not obj.getPosition then return nil end
  local ok, p = pcall(function() return obj:getPosition() end)
  return ok and p or nil
end

local function safeVelocity(obj)
  if not obj or not obj.getVelocity then return nil end
  local ok, v = pcall(function() return obj:getVelocity() end)
  return ok and v or nil
end

local function safeDirection(obj, velocity)
  if obj and obj.getDirectionVector then
    local ok, d = pcall(function() return obj:getDirectionVector() end)
    if ok and d and d:length() > 0.1 then
      return d:normalized()
    end
  end
  if velocity and velocity:length() > 0.1 then
    return velocity:normalized()
  end
  return vec3(0, 1, 0)
end

local function speedKmh(v)
  return v and v:length() * 3.6 or 0
end

local function addCell(grid, pos, item, cellSize)
  local cx = math.floor(pos.x / cellSize)
  local cy = math.floor(pos.y / cellSize)
  local key = cx .. ":" .. cy
  grid[key] = grid[key] or {}
  grid[key][#grid[key] + 1] = item
  item.cellX = cx
  item.cellY = cy
end

local function getNeighborCells(grid, item, radiusCells)
  local out = {}
  local cx = item.cellX
  local cy = item.cellY
  for dx = -radiusCells, radiusCells do
    for dy = -radiusCells, radiusCells do
      local bucket = grid[(cx + dx) .. ":" .. (cy + dy)]
      if bucket then
        for i = 1, #bucket do
          out[#out + 1] = bucket[i]
        end
      end
    end
  end
  return out
end

function M.snapshot(ids, playerId)
  local items = {}
  local grid = {}
  local cellSize = config.performance.spatialCellSize

  local function append(id, obj, isPlayer)
    if not obj then return end

    local active = true
    if config.performance.activeOnly and be and be.getObjectActive then
      local ok, value = pcall(function() return be:getObjectActive(id) end)
      active = not ok or value
    end
    if not active then return end

    local p = safePosition(obj)
    local v = safeVelocity(obj)
    if not p or not v then return end

    local d = safeDirection(obj, v)
    local speed = speedKmh(v)

    local item = {
      id = id,
      obj = obj,
      pos = p,
      vel = v,
      dir = d,
      speedKmh = speed,
      speedMps = v:length(),
      isPlayer = isPlayer == true,
    }

    items[#items + 1] = item
    addCell(grid, p, item, cellSize)
  end

  for i = 1, #(ids or {}) do
    local id = ids[i]
    local obj = getObjectByID(id)
    append(id, obj, false)
  end

  if playerId and playerId ~= 0 then
    local playerObj = getObjectByID(playerId)
    append(playerId, playerObj, true)
  end

  return {
    items = items,
    grid = grid,
    cellSize = cellSize,
  }
end

function M.findLead(world, ego, includePlayer)
  if not world or not ego then return nil end

  local best = nil
  local bestLong = config.following.lookAhead + 1

  local candidates = getNeighborCells(world.grid, ego, math.ceil(config.following.lookAhead / world.cellSize))

  local forward = ego.dir
  local right = vec3(-forward.y, forward.x, 0)
  if right:length() < 0.1 then
    right = vec3(1, 0, 0)
  else
    right = right:normalized()
  end

  for i = 1, #candidates do
    local other = candidates[i]

    if other.id ~= ego.id and (includePlayer or not other.isPlayer) then
      local rel = other.pos - ego.pos
      local longitudinal = rel:dot(forward)
      if longitudinal > 0.5 and longitudinal <= config.following.lookAhead then
        local lateral = math.abs(rel:dot(right))
        if lateral <= config.following.laneHalfWidth then
          if longitudinal < bestLong then
            best = other
            bestLong = longitudinal
          end
        end
      end
    end
  end

  if not best then return nil end

  local closing = ego.speedMps - best.speedMps
  local ttc = math.huge
  if closing > 0.1 then
    ttc = bestLong / closing
  end

  return {
    vehicle = best,
    gap = bestLong,
    closingMps = closing,
    ttc = ttc,
    stopped = best.speedKmh <= config.following.stoppedVehicleSpeed,
    lateral = math.abs((best.pos - ego.pos):dot(right)),
  }
end

function M.hasRearOrSideVehicle(world, ego)
  if not world or not ego then return false end

  local candidates = getNeighborCells(world.grid, ego, 1)
  local forward = ego.dir
  local right = vec3(-forward.y, forward.x, 0)
  if right:length() < 0.1 then
    right = vec3(1, 0, 0)
  else
    right = right:normalized()
  end

  for i = 1, #candidates do
    local other = candidates[i]
    if other.id ~= ego.id and not other.isPlayer then
      local rel = other.pos - ego.pos
      local longitudinal = rel:dot(forward)
      local lateral = math.abs(rel:dot(right))
      if math.abs(longitudinal) < 22 and lateral > 2.1 and lateral < 7.5 then
        return true, other
      end
    end
  end

  return false, nil
end

return M

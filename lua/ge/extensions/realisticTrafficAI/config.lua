local M = {}

M.version = "0.1.0"

M.general = {
  autoStart = true,
  updateInterval = 0.20,        -- AI decision cadence; not every frame
  populationCheckInterval = 8.0,
  showMessages = true,
  debug = false,
}

M.population = {
  auto = true,
  targetActive = 90,
  minimum = 50,
  maximum = 120,
  spawnBatch = 18,
  spawnGap = 20,
  useAllMods = true,
  useAllConfigs = true,
  simpleVehicles = false,
  activeAmountMultiplier = 1.0,
}

-- Driver model. Values are sampled per vehicle, producing a continuous
-- distribution rather than a few rigid "driver types".
M.driver = {
  speedFactorMin = 0.90,
  speedFactorMax = 1.07,

  aggressionMin = 0.20,
  aggressionMax = 0.68,

  reactionMin = 0.75,
  reactionMax = 1.55,

  headwayMin = 1.20,             -- seconds
  headwayMax = 2.15,             -- seconds

  comfortBrakeMin = 2.0,         -- m/s²
  comfortBrakeMax = 4.5,         -- m/s²

  hesitationChance = 0.035,
  hesitationMin = 0.7,
  hesitationMax = 1.8,

  overtakeThreshold = 0.48,
}

M.following = {
  laneHalfWidth = 3.8,
  lookAhead = 90.0,
  lookBehind = 35.0,
  minimumGap = 5.0,
  maximumComfortGap = 42.0,

  emergencyTTC = 0.85,
  hardBrakeTTC = 1.45,
  cautionTTC = 2.75,

  speedControllerInterval = 0.20,
  speedCommandThreshold = 0.8,
  speedSmoothing = 0.58,

  maxTargetDropPerSecond = 7.0,  -- km/h target-speed reduction
  maxTargetRisePerSecond = 4.0,  -- km/h target-speed increase

  stoppedVehicleSpeed = 2.0,
  congestionSpeed = 18.0,
}

M.behavior = {
  enablePredictiveFollowing = true,
  enableChainReactions = true,
  enableDriverVariation = true,
  enablePlayerInteraction = true,
  enableNativeLaneChanges = true,
  enableNativeIntersections = true,
  enableNativeAvoidance = true,

  -- Passing is delegated to BeamNG's native traffic AI.
  -- We only vary aggression and headway; we never force an unsafe offset
  -- into another lane.
  nativePassAggressionBoost = 0.12,
}

M.performance = {
  spatialCellSize = 30.0,
  activeOnly = true,
  maxControlledVehiclesPerTick = 140,
  farVehicleDistance = 180.0,
  reduceFarVehicleWork = true,
}

return M

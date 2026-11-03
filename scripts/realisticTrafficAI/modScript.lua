-- Realistic Traffic AI
-- BeamNG.drive 0.39.x
--
-- Loads the game-engine extension. The extension is intentionally kept separate
-- from the stock gameplay_traffic module so the mod can add behavior without
-- replacing BeamNG's traffic implementation.

load('core/realisticTrafficAI')
setExtensionUnloadMode('core/realisticTrafficAI', 'manual')

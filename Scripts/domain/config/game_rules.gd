class_name GameRules

# Pure game-rule constants. No engine concerns here — collision layers, masks,
# and physics tick rate live in Constants.gd (engine-facing autoload).
#
# This is a class_name const class, not an autoload — no registration needed.
# Access anywhere as `GameRules.BLUE_LINE_Z`.

# ── Game Flow Timings ─────────────────────────────────────────────────────────
const GOAL_PAUSE_DURATION: float   = 2.0
const FACEOFF_PREP_DURATION: float = 0.5
const FACEOFF_TIMEOUT: float       = 10.0
const PERIOD_DURATION: float       = 4.0 * 60.0   # 240 s per period
const NUM_PERIODS: int             = 3
const END_OF_PERIOD_PAUSE: float   = 3.0           # pause before next-period faceoff prep

# ── Rink Geometry ─────────────────────────────────────────────────────────────
const GOAL_LINE_Z: float = 26.6  # rink_length / 2 - distance_from_end (30 - 3.4)
const BLUE_LINE_Z: float = 7.62  # 25 ft from center ice (NHL standard)

# ── Puck ──────────────────────────────────────────────────────────────────────
const PUCK_START_POS: Vector3 = Vector3(0, 0.05, 0)
const ICE_FRICTION: float = 0.01

# ── Infractions ───────────────────────────────────────────────────────────────
const ICING_GHOST_DURATION: float = 3.0  # seconds team stays ghosted after icing

# ── Players ───────────────────────────────────────────────────────────────────
const MAX_PLAYERS: int = 6  # 3v3

# ── Faceoff Positions ─────────────────────────────────────────────────────────
# Indexed by slot. Even slots are Team 0 (+Z side), odd slots are Team 1 (-Z side).
const CENTER_FACEOFF_POSITIONS: Array[Vector3] = [
	Vector3( 0.0, 1.0,  1.5),  # slot 0 — Team 0 center
	Vector3( 0.0, 1.0, -1.5),  # slot 1 — Team 1 center
	Vector3(-5.0, 1.0,  3.0),  # slot 2 — Team 0 left wing
	Vector3(-5.0, 1.0, -3.0),  # slot 3 — Team 1 left wing
	Vector3( 5.0, 1.0,  3.0),  # slot 4 — Team 0 right wing
	Vector3( 5.0, 1.0, -3.0),  # slot 5 — Team 1 right wing
]

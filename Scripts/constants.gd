extends Node

# Collision Layers (bit values used in collision_layer / collision_mask)
# Layer 1  (bit 0, value  1) — walls, ice, goalie bodies
# Layer 2  (bit 1, value  2) — skater blade Area3Ds
# Layer 4  (bit 3, value  8) — puck body (goal sensors use mask 8 to detect it)
# Layer 5  (bit 4, value 16) — skater CharacterBody3D bodies
const LAYER_WALLS: int          = 1
const LAYER_BLADE_AREAS: int    = 2
const LAYER_PUCK: int           = 8
const LAYER_SKATER_BODIES: int  = 16

# Composed masks
const MASK_PUCK: int   = LAYER_WALLS                         # bounces off boards + goalie bodies
const MASK_SKATER: int = LAYER_WALLS | LAYER_SKATER_BODIES   # blocked by boards + other skaters

# Network
const PORT: int = 7777
const MAX_PLAYERS: int = 6
const INPUT_RATE: int = 60
const STATE_RATE: int = 20
const ICE_FRICTION: float = 0.01

# Physics
const PHYSICS_TICK: int = 240

# Game
const PUCK_START_POS: Vector3 = Vector3(0, 0.05, 0)
const GOAL_LINE_Z: float = 26.6  # rink_length / 2 - distance_from_end (30 - 3.4)

# Game flow
const GOAL_PAUSE_DURATION: float   = 2.0
const FACEOFF_PREP_DURATION: float = 0.5
const FACEOFF_TIMEOUT: float       = 10.0

# Center ice faceoff positions, indexed by slot.
# Even slots (0, 2, 4) are Team 0 — positive-Z side.
# Odd slots (1, 3, 5) are Team 1 — negative-Z side.
const CENTER_FACEOFF_POSITIONS: Array[Vector3] = [
	Vector3( 0.0, 1.0,  1.5),   # slot 0 — Team 0 center
	Vector3( 0.0, 1.0, -1.5),   # slot 1 — Team 1 center
	Vector3(-5.0, 1.0,  3.0),   # slot 2 — Team 0 left wing
	Vector3(-5.0, 1.0, -3.0),   # slot 3 — Team 1 left wing
	Vector3( 5.0, 1.0,  3.0),   # slot 4 — Team 0 right wing
	Vector3( 5.0, 1.0, -3.0),   # slot 5 — Team 1 right wing
]

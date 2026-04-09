extends Node

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

const SKATER_START_POSITIONS: Array[Vector3] = [
	Vector3(-3, 1, 8),    # local player / host
	Vector3(3, 1, -12),   # second player
	Vector3(-5, 1, 6),    # third
	Vector3(5, 1, -10),   # fourth
	Vector3(-7, 1, 4),    # fifth
	Vector3(7, 1, -8),    # sixth
]

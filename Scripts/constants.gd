extends Node

# Network
const PORT: int = 7777
const MAX_PLAYERS: int = 6
const DEFAULT_IP: String = "127.0.0.1"
const INPUT_RATE: int = 60
const STATE_RATE: int = 20

# Physics
const PHYSICS_TICK: int = 240

# Game
const PUCK_START_POS: Vector3 = Vector3(0, 0.05, 0)
const SKATER_START_POS: Vector3 = Vector3(0, 1, 10)
const TOP_GOALIE_POS: Vector3 = Vector3(0, 0, -24)
const BOTTOM_GOALIE_POS: Vector3 = Vector3(0, 0, 24)

const SKATER_START_POSITIONS: Array[Vector3] = [
	Vector3(-3, 1, 8),    # local player / host
	Vector3(3, 1, -12),   # second player
	Vector3(-5, 1, 6),    # third
	Vector3(5, 1, -10),   # fourth
	Vector3(-7, 1, 4),    # fifth
	Vector3(7, 1, -8),    # sixth
]

class_name FrozenPuckRules
extends RefCounted

# A puck trapped on the boards under a man held there (BoardWallRules' squeeze):
# loose at his feet or still on his stick, nobody gets it out, so play stops
# (NHL, a faceoff at the nearest dot) or the puck squirts free (ARCADE). The
# count runs only while the trap holds — puck slow and at the wall, a held
# skater on it — and restarts whenever the puck moves off its anchor.

const BOARD_MARGIN_M: float = 0.6
const SPEED_MAX_M_S: float = 1.0
# Body edge to puck: the held skater's skates and a stick held in to his body.
const REACH_M: float = 0.9
# Bodies this far apart, edge to edge, are still leaning on each other.
const HELD_GAP_M: float = 0.1
const SLOP_M: float = 0.3
const FROZEN_S: float = 2.0
const SQUIRT_SPEED_M_S: float = 4.0


class State:
	var anchor: Vector3 = Vector3.INF
	var elapsed: float = 0.0

	func clear() -> void:
		anchor = Vector3.INF
		elapsed = 0.0


static func near_boards(puck_pos: Vector3) -> bool:
	return BoardWallRules.wall_normal(puck_pos, 0.0, BOARD_MARGIN_M) != Vector2.ZERO


# Whether the body at `pos` is held on the boards by an opponent at `other_pos`:
# against the wall, leaned on, and him engaged (the check button) on the open-ice
# side, square enough to the wall to be pressing into it.
static func held_on_boards(pos: Vector3, radius: float, other_pos: Vector3,
		other_radius: float, other_engaged: bool) -> bool:
	if not other_engaged:
		return false
	var wall_out: Vector2 = BoardWallRules.wall_normal(pos, radius,
			BoardWallRules.SQUEEZE_MARGIN_M)
	if wall_out == Vector2.ZERO:
		return false
	var d := Vector2(pos.x - other_pos.x, pos.z - other_pos.z)
	var dist: float = d.length()
	if dist < 1e-4 or dist - radius - other_radius > HELD_GAP_M:
		return false
	return (d / dist).dot(wall_out) >= BoardWallRules.BACKSTOP_MIN_INTO_WALL


# Advances the count; true on the tick it reaches FROZEN_S (and clears it).
static func step(state: State, puck_pos: Vector3, trapped: bool, delta: float) -> bool:
	if not trapped:
		state.clear()
		return false
	if not state.anchor.is_finite() or puck_pos.distance_to(state.anchor) > SLOP_M:
		state.anchor = puck_pos
		state.elapsed = 0.0
	state.elapsed += delta
	if state.elapsed < FROZEN_S:
		return false
	state.clear()
	return true


# Along the boards, away from the held body.
static func squirt_velocity(puck_pos: Vector3, pinned_pos: Vector3) -> Vector3:
	var out: Vector2 = BoardWallRules.wall_normal(puck_pos, 0.0, BOARD_MARGIN_M)
	if out == Vector2.ZERO:
		return Vector3.ZERO
	var along := Vector2(-out.y, out.x)
	var away := Vector2(puck_pos.x - pinned_pos.x, puck_pos.z - pinned_pos.z)
	if along.dot(away) < 0.0:
		along = -along
	return Vector3(along.x, 0.0, along.y) * SQUIRT_SPEED_M_S

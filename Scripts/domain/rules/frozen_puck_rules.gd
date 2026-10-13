class_name FrozenPuckRules
extends RefCounted

# A puck trapped on the boards by a pinned body: nobody can play it, so play
# stops (NHL, a faceoff at the nearest dot) or the puck squirts free (ARCADE).
# The count runs only while the trap holds — puck slow and at the wall, a pinned
# skater on it — and restarts whenever the puck moves off its anchor.

const BOARD_MARGIN_M: float = 0.6
const SPEED_MAX_M_S: float = 1.0
# Body edge to puck: the pinned skater's skates and a stick held in to his body.
const REACH_M: float = 0.9
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
	return BoardPinRules.wall_normal(puck_pos, 0.0, BOARD_MARGIN_M) != Vector2.ZERO


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


# Along the boards, away from the pinned body.
static func squirt_velocity(puck_pos: Vector3, pinned_pos: Vector3) -> Vector3:
	var out: Vector2 = BoardPinRules.wall_normal(puck_pos, 0.0, BOARD_MARGIN_M)
	if out == Vector2.ZERO:
		return Vector3.ZERO
	var along := Vector2(-out.y, out.x)
	var away := Vector2(puck_pos.x - pinned_pos.x, puck_pos.z - pinned_pos.z)
	if along.dot(away) < 0.0:
		along = -along
	return Vector3(along.x, 0.0, along.y) * SQUIRT_SPEED_M_S

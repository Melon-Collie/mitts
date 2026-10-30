extends GutTest

# Rebound control in a match (KeeperSave's face turns): the live keeper and the
# real puck's tick, shots straight on from the slot at his blocker and along
# the ice at his stick. What comes off him goes more toward the near corner
# than off the same save made with the face never turned, and stays out.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SLOT := Vector3(0.0, 0.05, -8.0)
const SHOTS: Array[Vector2] = [Vector2(0.55, 0.8), Vector2(0.0, 0.02)]
const SPEED_M_S: float = 25.0


class Unsteered extends KeeperSave:
	func _steer(_l: int, _side: float, _h: int) -> float:
		return 0.0


var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _touched: bool = false


func before_each() -> void:
	_goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_keeper)
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [_goalie])
	_keeper.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	_puck.puck_touched_goalie.connect(func(_g: Goalie) -> void: _touched = true)
	_puck._physics_process(DT)


func test_off_his_blocker_and_his_stick_it_goes_more_toward_the_corner() -> void:
	for to: Vector2 in SHOTS:
		var steered: Array = _shoot(to, true)
		var plain: Array = _shoot(to, false)
		assert_false(is_nan(steered[0]) or is_nan(plain[0]), "%s: met" % to)
		assert_gt(steered[0], plain[0], "%s: more toward the corner" % to)
		assert_false(steered[1], "%s: stays out" % to)


# A shot from the slot arriving at `to` on the goal line, the save steered or
# not: the share of the first rebound's pace across the ice heading out toward
# the corner on the side of his net it met him (either way out from the
# middle), and whether the puck was in his net a second later.
func _shoot(to: Vector2, steer: bool) -> Array:
	_keeper.reset_to_crease()
	if not steer:
		_keeper.save = Unsteered.new()
		_keeper._tier()
	_puck.clear_carrier()
	var lying: Vector3 = _keeper._net * Vector3(SLOT.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, SLOT.z)
	for _i: int in 150:
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._physics_process(DT)
	var start: Vector3 = _keeper._net * SLOT
	var at_line: Vector3 = _keeper._net * Vector3(to.x, to.y, 0.0)
	var flight: float = start.distance_to(at_line) / SPEED_M_S
	var v: Vector3 = (at_line - start) / flight
	if to.y > KeeperShotRead.ON_ICE_Y:
		v.y += 0.5 * GameRules.GRAVITY_M_S2 * flight
	_puck.global_position = start
	_puck.set_puck_velocity(v)
	_puck.puck_released.emit()
	_touched = false
	for _i: int in int(2.0 / DT):
		_tick()
		if _touched:
			var hit_x: float = (_keeper._net.affine_inverse() * _puck.global_position).x
			var w: Vector3 = _keeper._net.basis.inverse() * _puck.get_puck_velocity()
			var across := Vector2(w.x, w.z)
			var out: float = absf(w.x) if absf(hit_x) < KeeperSave.MIDDLE_M else w.x * signf(hit_x)
			for _j: int in int(1.0 / DT):
				_tick()
			var end: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
			return [out / maxf(across.length(), 1e-4), end.z > 0.0 and absf(end.x) < GameRules.NET_HALF_WIDTH]
	return [NAN, true]


func _tick() -> void:
	_keeper._physics_process(DT)
	_goalie._part_velocity_frame = Engine.get_physics_frames() - 1
	_goalie.get_collision_part_velocities()
	_puck._physics_process(DT)
	_puck.drain_contact_events()

extends GutTest

# Says how far rebound control steers what comes off him (KeeperSave's face
# turns): the live keeper and the real puck's tick, shots from the slot, both
# circles and both dots at his blocker high and mid and along the ice at his
# stick, each made steered and with the face never turned. Per shot, the share
# of the first rebound's pace across the ice heading out toward the corner on
# the side of his net it met him (1 along the goal line that way, 0 straight
# back out, below 0 back across his mouth), the hand, the turn and the
# rebound's pace; then the means and the goals each way.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const FROM: Array[Vector3] = [Vector3(0.0, 0.05, -8.0), Vector3(-3.0, 0.05, -7.0), Vector3(3.0, 0.05, -7.0),
		Vector3(-6.0, 0.05, -4.0), Vector3(6.0, 0.05, -4.0)]
const TO: Array[Vector2] = [Vector2(0.55, 0.8), Vector2(0.6, 0.4), Vector2(0.2, 0.02), Vector2(-0.2, 0.02),
		Vector2(0.0, 0.02), Vector2(-0.5, 0.02), Vector2(0.5, 0.02)]
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


func test_report_rebound_control() -> void:
	var lines: PackedStringArray = []
	var sums: Array[float] = [0.0, 0.0]
	var met: Array[int] = [0, 0]
	var goals: Array[int] = [0, 0]
	for from: Vector3 in FROM:
		for to: Vector2 in TO:
			var row: String = "from %s to %s:" % [Vector2(from.x, from.z), to]
			for k: int in 2:
				var r: Array = _shoot(from, to, k == 0)
				row += "  [%s] corner %+.2f hand %d turn %+.0f° pace %.1f%s" % ["steered" if k == 0 else "plain  ",
						r[0], r[2], r[3], r[4], " GOAL" if r[1] else ""]
				if not is_nan(r[0]):
					sums[k] += r[0]
					met[k] += 1
				if r[1]:
					goals[k] += 1
			lines.append(row)
	lines.append("mean toward the corner: steered %+.2f (%d met), plain %+.2f (%d met); goals steered %d, plain %d"
			% [sums[0] / maxi(met[0], 1), met[0], sums[1] / maxi(met[1], 1), met[1], goals[0], goals[1]])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


# [toward the corner, in his net, the hand, its turn in degrees, the rebound's
# pace]; NAN for one that met nothing of him.
func _shoot(from: Vector3, to: Vector2, steer: bool) -> Array:
	_keeper.reset_to_crease()
	if not steer:
		_keeper.save = Unsteered.new()
		_keeper._tier()
	_puck.clear_carrier()
	var lying: Vector3 = _keeper._net * Vector3(from.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, from.z)
	for _i: int in 150:
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._physics_process(DT)
	var start: Vector3 = _keeper._net * from
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
		var at: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		if _touched:
			var hand: int = _keeper.save.hand
			var turn: float = rad_to_deg(_keeper.save.face_turn)
			var w: Vector3 = _keeper._net.basis.inverse() * _puck.get_puck_velocity()
			var across := Vector2(w.x, w.z)
			var out: float = absf(w.x) if absf(at.x) < KeeperSave.MIDDLE_M else w.x * signf(at.x)
			for _j: int in int(1.0 / DT):
				_tick()
			var end: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
			return [out / maxf(across.length(), 1e-4), end.z > 0.0 and absf(end.x) < GameRules.NET_HALF_WIDTH,
					hand, turn, across.length()]
		if at.z > 0.0:
			return [NAN, absf(at.x) < GameRules.NET_HALF_WIDTH, -1, 0.0, 0.0]
	return [NAN, false, -1, 0.0, 0.0]


func _tick() -> void:
	_keeper._physics_process(DT)
	_goalie._part_velocity_frame = Engine.get_physics_frames() - 1
	_goalie.get_collision_part_velocities()
	_puck._physics_process(DT)
	_puck.drain_contact_events()

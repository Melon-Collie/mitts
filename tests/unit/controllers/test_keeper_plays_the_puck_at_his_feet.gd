extends GutTest

# A dead puck at his feet he plays where he is (KeeperController,
# KeeperCover.at_feet): set square on a puck out front, the live keeper and the
# real puck's tick (his gear's boxes moving as he moves) stepped as the game
# steps them, a puck laid dead beside him, behind him either side, or a step
# ahead past his glove's reach. He covers every one, and nothing of his knocks
# it on the way: it is where it was laid when the glove comes down on it.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 2.5
# Where the puck he is set on lies, net frame: out front.
const SET_ON := Vector2(0.0, -6.0)
# From where he stands, his own frame: across (− his glove side), and ahead (+).
const SPOTS: Array[Vector2] = [Vector2(-0.7, 0.1), Vector2(0.7, 0.1), Vector2(-0.45, -0.3), Vector2(0.4, -0.35),
		Vector2(0.0, -0.6), Vector2(0.0, 1.0)]
# How far a puck may have moved under him before the glove is on it: less than
# a puck's width, a nudge at most.
const NUDGE_M: float = 0.05

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _covered: bool = false


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
	_keeper.puck_covered.connect(func(_team: int) -> void: _covered = true)
	# A new puck's first tick stages it for the opening faceoff.
	_puck._physics_process(DT)


func test_a_dead_puck_round_his_feet_he_covers_where_it_lies() -> void:
	for spot: Vector2 in SPOTS:
		var what: String = "a puck %s from him" % spot
		var laid: Vector3 = _lay(spot)
		var moved: float = 0.0
		var t: float = 0.0
		while t < SECONDS and not _covered:
			_keeper._physics_process(DT)
			_tick_puck()
			t += DT
			if not _covered:
				moved = maxf(moved, (_puck.global_position - laid).length())
		assert_true(_covered, what + ": covered")
		assert_lt(moved, NUDGE_M, what + ": not knocked first")


# Starting him over from his crease leaves nothing of what he did before: set
# on a puck at the near post, he solves to the same gear whether or not he had
# covered a puck by his feet first.
func test_a_reset_leaves_nothing_of_what_came_before() -> void:
	_lay(Vector2(-0.45, -0.3))
	for _i: int in 180:
		_keeper._physics_process(DT)
		_tick_puck()
	var after: Array[Transform3D] = _boxes_set_at(Vector2(-3.0, -1.2))
	before_each()
	var fresh: Array[Transform3D] = _boxes_set_at(Vector2(-3.0, -1.2))
	for i: int in fresh.size():
		assert_true(after[i].is_equal_approx(fresh[i]), "box %d" % i)


# From a full reset, set on the puck out front, then the puck laid dead at
# `spot` from him in his own frame; where it was laid.
func _lay(spot: Vector2) -> Vector3:
	_settle(SET_ON)
	_covered = false
	var mine := Vector3(spot.x, 0.0, -spot.y)
	var at: Vector3 = Basis(Vector3.UP, _keeper.motor.yaw) * mine + Vector3(_keeper.motor.x, 0.0, _keeper.motor.z)
	at.y = GameRules.PUCK_COLLISION_HALF_HEIGHT
	_puck.global_position = _keeper._net * at
	_puck.set_puck_velocity(Vector3.ZERO)
	_goalie._part_velocity_frame = -10
	_goalie.get_collision_part_velocities()
	return _puck.global_position


func _settle(on: Vector2) -> void:
	_keeper.reset_to_crease()
	_puck.clear_carrier()
	_puck.motion_pinned = false
	_puck.pickup_locked = false
	var lying: Vector3 = _keeper._net * Vector3(on.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, on.y)
	for _i: int in 120:
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._physics_process(DT)


func _boxes_set_at(on: Vector2) -> Array[Transform3D]:
	_settle(on)
	var out: Array[Transform3D] = []
	for cs: CollisionShape3D in _goalie.get_collision_parts():
		out.append(cs.global_transform)
	return out


# The puck's tick, his gear's velocities sampled from where his boxes were a
# tick ago: stepped by hand inside one engine frame, Goalie's once-a-frame
# cache would otherwise hold them at zero.
func _tick_puck() -> void:
	_goalie._part_velocity_frame = Engine.get_physics_frames() - 1
	_goalie.get_collision_part_velocities()
	_puck._physics_process(DT)
	_puck.drain_contact_events()

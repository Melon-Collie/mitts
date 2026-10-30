extends GutTest

# A slow loose puck at his feet never ends up in his net through something he
# does: set on the near post and sealed below the goal line, the live keeper
# (KeeperController) and the real puck's tick (Puck._host_tick, his gear's
# boxes moving as he moves) stepped as the game steps them, a puck laid dead
# or drifting at the spots where his pads once walked it in. A puck that slides
# in on its own is not his doing and is not asked about here
# (tests/instruments/keeper/test_loose_puck_at_his_feet.gd sweeps it all).
# Nor does one he catches there and, with no whistle for it, plays out.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 1.5
# Where the puck he is set on lies, net frame: a sharp angle (the near post),
# below the goal line (the RVH).
const SET_ON: Array[Vector2] = [Vector2(-3.0, -1.2), Vector2(2.4, 0.6)]
# From where he stands, net frame: across, and in front (−).
const SPOTS: Array[Vector2] = [Vector2(0.0, -0.25), Vector2(0.3, -0.25), Vector2(0.6, -0.25),
		Vector2(0.9, -0.25), Vector2(0.3, -0.5), Vector2(-0.3, -0.25)]

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


func test_a_slow_puck_at_his_feet_he_never_walks_in() -> void:
	for set_on: Vector2 in SET_ON:
		for spot: Vector2 in SPOTS:
			for velocity: Vector2 in [Vector2.ZERO, Vector2(0.0, 0.6), Vector2(0.6, 0.0), Vector2(-0.6, 0.0)]:
				var what: String = "set on %s, puck %s from him at %s" % [set_on, spot, velocity]
				assert_false(_walked_in(set_on, spot, velocity), what)


# Whether the puck, laid at `spot` from him moving at `velocity` (net frame),
# ends up in his net having touched him.
func _walked_in(set_on: Vector2, spot: Vector2, velocity: Vector2) -> bool:
	_keeper.reset_to_crease()
	_puck.clear_carrier()
	_puck.motion_pinned = false
	_puck.pickup_locked = false
	var lying: Vector3 = _keeper._net * Vector3(set_on.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, set_on.y)
	for _i: int in 120:
		_puck.global_position = lying
		_puck.set_puck_velocity(Vector3.ZERO)
		_keeper._physics_process(DT)
	var at := Vector3(_keeper.motor.x + spot.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, _keeper.motor.z + spot.y)
	if at.z >= -GameRules.PUCK_COLLISION_RADIUS:
		return false
	_puck.global_position = _keeper._net * at
	_puck.set_puck_velocity(_keeper._net.basis * Vector3(velocity.x, 0.0, velocity.y))
	_touched = false
	var t: float = 0.0
	while t < SECONDS:
		_keeper._physics_process(DT)
		var was: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		_puck._physics_process(DT)
		_puck.drain_contact_events()
		t += DT
		var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
		if p.z >= 0.0 and was.z < 0.0 and absf(p.x) < GameRules.NET_HALF_WIDTH:
			return _touched
	return false


func test_a_puck_he_holds_at_the_post_he_never_plays_out_into_his_net() -> void:
	for set_on: Vector2 in SET_ON:
		for mirrored: bool in [false, true]:
			_keeper.reset_to_crease()
			_keeper._keeper.skeleton.mirrored = mirrored
			var lying: Vector3 = _keeper._net * Vector3(set_on.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, set_on.y)
			for _i: int in 120:
				_puck.global_position = lying
				_puck.set_puck_velocity(Vector3.ZERO)
				_keeper._physics_process(DT)
			_puck.puck_caught_by_goalie.emit(_goalie)
			var what: String = "set on %s, catching %s" % [set_on, "right" if mirrored else "left"]
			var t: float = 0.0
			while _puck.motion_pinned and t < KeeperController.CATCH_HOLD_S + 0.5:
				_keeper._physics_process(DT)
				t += DT
			assert_false(_puck.motion_pinned, "played out, " + what)
			var down: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
			assert_lt(down.z, -GameRules.PUCK_COLLISION_RADIUS, "set down in front of his line, " + what)
			var went_in: bool = false
			t = 0.0
			while t < SECONDS and not went_in:
				var was: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
				_puck._physics_process(DT)
				_puck.drain_contact_events()
				_keeper._physics_process(DT)
				t += DT
				var p: Vector3 = _keeper._net.affine_inverse() * _puck.global_position
				went_in = p.z >= 0.0 and was.z < 0.0 and absf(p.x) < GameRules.NET_HALF_WIDTH
			assert_false(went_in, "never into his net, " + what)

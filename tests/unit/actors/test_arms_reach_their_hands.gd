extends GutTest

# An arm is drawn no longer than it is. The rig poses each arm bone between two
# points and scales it to fit, so a hand placed past the arm's reach shows as a
# rubber forearm rather than failing anywhere; this measures the drawn bones
# directly, through the poses that used to stretch them (cross-body reach, the
# tight turn's exit, the knockdown, the block). The bottom hand slides up the
# shaft and the shoulder girdle gives to keep them within reach
# (BottomHandIK.reachable_grip, TwoBoneIK.reach_root).

const DT: float = 1.0 / 120.0
const UpperBone = SkaterMeshBuilder.UpperBone
const _ARM_BONES: Array[int] = [UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM,
		UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM]

# [name, puck, knockdown impulse, steps]; a step is [ticks, aim, move, flags].
const _POSES: Array = [
	["rest", false, Vector3.ZERO, [[40, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, ""]]],
	["carry", true, Vector3.ZERO, [[40, Vector3(0.6, 0.0, -2.2), Vector2.ZERO, ""]]],
	["cross_body_reach", true, Vector3.ZERO, [
		[20, Vector3(0.4, 0.0, -2.0), Vector2.ZERO, ""],
		[50, Vector3(-2.6, 0.0, -0.4), Vector2.ZERO, ""]]],
	["wide_forehand", true, Vector3.ZERO, [[50, Vector3(2.6, 0.0, -0.4), Vector2.ZERO, ""]]],
	["wrister_aim", true, Vector3.ZERO, [
		[10, Vector3(0.4, 0.0, -2.0), Vector2.ZERO, ""],
		[45, Vector3(1.4, 0.0, -3.0), Vector2.ZERO, "shoot"]]],
	["slapper_coil", true, Vector3.ZERO, [
		[10, Vector3(0.4, 0.0, -2.0), Vector2.ZERO, ""],
		[58, Vector3(0.8, 0.0, -3.2), Vector2.ZERO, "slap"]]],
	["turn_tight_exit", false, Vector3.ZERO, [
		[240, Vector3(0.0, 0.0, -3.0), Vector2(0.0, -1.0), ""],
		[70, Vector3(3.0, 0.0, -0.5), Vector2(1.0, 0.0), "brake"]]],
	["wiggle_aim", false, Vector3.ZERO, [
		[240, Vector3(0.0, 0.0, -3.0), Vector2(0.0, -1.0), ""],
		[40, Vector3(2.5, 0.0, -1.5), Vector2(0.0, -1.0), ""],
		[40, Vector3(-2.5, 0.0, -1.5), Vector2(0.0, -1.0), ""]]],
	["shot_block", false, Vector3.ZERO, [[30, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, "block"]]],
	["hit_commit_deep", false, Vector3.ZERO, [
		[60, Vector3(1.6, 0.0, 2.4), Vector2(0.84, -0.55), "hit"]]],
	["knockdown_side", false, Vector3(3.0, 0.0, 0.0), [[100, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, ""]]],
	["knockdown_back", false, Vector3(0.0, 0.0, 3.0), [[100, Vector3(0.0, 0.0, -3.0), Vector2.ZERO, ""]]],
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func _rig() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)


# The drawn length of the longest arm bone, as a fraction of the length it has.
func _worst_stretch() -> float:
	var body: Skeleton3D = _skater._arms._skeleton
	var worst: float = 0.0
	for bone: int in _ARM_BONES:
		var drawn: float = body.get_bone_pose(bone).basis.get_scale().z
		var length: float = _skater.upper_arm_length \
				if bone == UpperBone.TOP_UPPER_ARM or bone == UpperBone.BOTTOM_UPPER_ARM \
				else _skater.forearm_length
		worst = maxf(worst, drawn / length)
	return worst


func _worst_through(pose: Array) -> float:
	_rig()
	if bool(pose[1]):
		_puck.set_carrier(_skater)
		_controller.on_puck_picked_up_network()
	if pose[2] != Vector3.ZERO:
		_controller._on_body_check_received(pose[2] as Vector3)
	var input := InputState.new()
	var worst: float = 0.0
	for step: Array in pose[3]:
		var flags: String = step[3]
		for t: int in int(step[0]):
			input.delta = DT
			input.host_timestamp += DT
			input.move_vector = step[2]
			input.mouse_world_pos = _skater.global_position + (step[1] as Vector3)
			input.brake = flags == "brake"
			input.block_held = flags == "block"
			input.hit_held = flags == "hit"
			input.shoot_held = flags == "shoot"
			input.shoot_pressed = flags == "shoot" and t == 0
			input.slap_held = flags == "slap"
			input.slap_pressed = flags == "slap" and t == 0
			_controller._process_input(input, DT)
			_skater._physics_process(DT)
			_skater._process(DT)
			worst = maxf(worst, _worst_stretch())
	return worst


func test_no_arm_is_drawn_longer_than_it_is() -> void:
	for pose: Array in _POSES:
		var worst: float = _worst_through(pose)
		gut.p("%s: longest arm bone drawn at %.3f of its length" % [pose[0], worst])
		assert_lt(worst, 1.001, "%s draws an arm bone stretched" % pose[0])


# The hand slides up the shaft before it lets go: in an ordinary carry it is
# still on the stick, between the top hand and the blade.
func test_the_bottom_hand_holds_the_stick_in_a_carry() -> void:
	_worst_through(_POSES[1])
	var top: Vector3 = _skater.get_top_hand_position()
	var blade: Vector3 = _skater.get_blade_position()
	var bottom: Vector3 = _skater.bottom_hand.position
	var shaft: Vector3 = blade - top
	var g: float = (bottom - top).dot(shaft) / shaft.length_squared()
	assert_between(g, 0.0, 1.0, "the grip is on the shaft")
	assert_lt((top + shaft * g).distance_to(bottom), 0.01, "and the hand is on it")

extends GutTest

# A standing skater posed by the real controller and render pass, and how far
# each arm, drawn as a capsule of the sleeve's radius from its shoulder (past
# the pad) through the elbow to the hand, goes into the jersey's trunk. Shared
# by the clearance instrument and its gate.
#
# ARM_CLEARANCE_TUNE=<pivot forward>,<pivot inward>,<hand_y_max> overrides those
# three on the rigged controller, for trying values without editing them.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const _UPPER_ARMS: Array[int] = [UpperBone.TOP_UPPER_ARM, UpperBone.BOTTOM_UPPER_ARM]
const _FOREARMS: Array[int] = [UpperBone.TOP_FOREARM, UpperBone.BOTTOM_FOREARM]
# Arm nearer the shoulder than this is the pad and the armhole's seam, which sit
# on the trunk by design.
const PAST_PAD_M: float = 0.12
const SLEEVE_R: float = SkaterMeshBuilder.SLEEVE_RADIUS_M
const _TICKS: int = 60
const _CAPSULE_SAMPLES: int = 10


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func before_all() -> void:
	SkaterCameraCull.enabled = false


func after_all() -> void:
	SkaterCameraCull.enabled = true


func _rig(attrs: PlayerAttributes) -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.set_physics_process(false)
	_puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	_skater.apply_appearance(attrs)
	_controller.apply_attributes(attrs)
	var tune: PackedStringArray = OS.get_environment("ARM_CLEARANCE_TUNE").split(",")
	if tune.size() == 3:
		_controller.hand_pivot_forward = tune[0].to_float()
		_controller.hand_pivot_inward = tune[1].to_float()
		_controller.hand_y_max = tune[2].to_float()
		_controller._ik.invalidate_configs()


# The blade side's sign the solve uses: -1 for a lefty, whose blade is on -X.
func _side() -> float:
	return -1.0 if _skater.is_left_handed else 1.0


# Holds the cursor `r` off the top shoulder at forehand-signed `deg`, a skater
# facing -Z. `mode`: "rest" (no puck near), "reach" (a loose puck under the
# cursor), "carry".
func _hold(deg: float, r: float, mode: String) -> void:
	if mode == "carry" and _puck.get_carrier() != _skater:
		_puck.set_carrier(_skater)
		_controller.on_puck_picked_up_network()
	var a: float = deg_to_rad(deg) * _side()
	var s: Vector3 = _skater.shoulder.position
	for t: int in _TICKS:
		_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
		var input := InputState.new()
		input.delta = DT
		input.host_timestamp = float(t) * DT
		var cursor := Vector3(s.x + sin(a) * r, 0.0, s.z - cos(a) * r)
		input.mouse_world_pos = cursor
		if mode == "reach":
			_puck.global_position = cursor
		elif mode == "rest":
			_puck.global_position = Vector3(30.0, 0.0, 30.0)
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)


# The blade's (forehand-signed degrees, metres) off the top shoulder.
func _blade_polar() -> Vector2:
	var s: Vector3 = _controller._ik.arm_shoulder()
	var b: Vector3 = _skater.get_blade_position()
	var d := Vector2(b.x - s.x, b.z - s.z)
	return Vector2(rad_to_deg(atan2(d.x, -d.y) * _side()), d.length())


# How far `p` (the jersey's own frame, SkaterConnectedMesh.jersey_stations') is
# inside the jersey's section at its height; negative outside, NAN off the
# trunk's span.
static func _depth(p: Vector3, stations: Array[Vector3]) -> float:
	for i: int in stations.size() - 1:
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i + 1]
		if p.y <= a.x and p.y >= b.x:
			var t: float = (a.x - p.y) / maxf(a.x - b.x, 0.0001)
			var r: float = lerpf(a.y, b.y, t)
			var sway: float = lerpf(a.z, b.z, t)
			var ax: float = r * SkaterMeshBuilder.PELVIS_XZ_SCALE.x
			var az: float = r * SkaterMeshBuilder.PELVIS_XZ_SCALE.y
			var q := Vector2(p.x, p.z - sway)
			var e: float = Vector2(q.x / ax, q.y / az).length()
			if e < 0.001:
				return minf(ax, az)
			return q.length() * (1.0 - e) / e
	return NAN


# A capsule arm's deepest intrusion: its surface's, the sleeve's radius past the
# axis.
static func _capsule_depth(sh: Vector3, el: Vector3, hand: Vector3,
		stations: Array[Vector3]) -> float:
	var worst: float = -1.0
	for i: int in _CAPSULE_SAMPLES + 1:
		var t: float = float(i) / float(_CAPSULE_SAMPLES)
		var p: Vector3 = sh.lerp(el, t)
		if p.distance_to(sh) >= PAST_PAD_M:
			var d: float = _depth(p, stations)
			if not is_nan(d):
				worst = maxf(worst, d + SLEEVE_R)
		var e: float = _depth(el.lerp(hand, t), stations)
		if not is_nan(e):
			worst = maxf(worst, e + SLEEVE_R)
	return worst


# Per arm, top first: (depth with the elbow as drawn, the least depth any elbow
# the two bones allow could have).
func _arm_depths() -> Array[Vector2]:
	var body: Skeleton3D = _skater._arms._skeleton
	var skin: Skin = SkaterConnectedMesh.shared_skin()
	# The trunk's bind (the first) back to the jersey's own frame.
	var to_jersey: Transform3D = (body.get_bone_global_pose(skin.get_bind_bone(0))
			* skin.get_bind_pose(0)).affine_inverse()
	var lift: Vector3 = SkaterConnectedMesh.bind_rests()[0].origin
	var stations: Array[Vector3] = SkaterConnectedMesh.jersey_stations()
	var out: Array[Vector2] = []
	for i: int in 2:
		var up: Transform3D = body.get_bone_global_pose(_UPPER_ARMS[i])
		var fo: Transform3D = body.get_bone_global_pose(_FOREARMS[i])
		var sh: Vector3 = to_jersey * (up * Vector3(0.0, 0.0, 0.5)) - lift
		var el: Vector3 = to_jersey * (up * Vector3(0.0, 0.0, -0.5)) - lift
		var hand: Vector3 = to_jersey * (fo * Vector3(0.0, 0.0, -0.5)) - lift
		var drawn: float = _capsule_depth(sh, el, hand, stations)
		var axis: Vector3 = (hand - sh).normalized()
		var foot: Vector3 = sh + axis * (el - sh).dot(axis)
		var radial: Vector3 = el - foot
		var best: float = INF
		for k: int in 36:
			var e: Vector3 = foot + radial.rotated(axis, TAU * float(k) / 36.0)
			best = minf(best, _capsule_depth(sh, e, hand, stations))
		out.append(Vector2(drawn, best))
	return out

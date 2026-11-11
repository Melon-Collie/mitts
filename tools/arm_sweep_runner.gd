extends Node

# The body of tools/arm_sweep.gd. Each scenario gets a fresh skater, driven by
# hand at a fixed DT as tools/gait_strip_runner.gd drives one. The cursor sits
# `r` metres out at an angle from up-ice (+ toward the forehand: the default
# skater shoots left, so facing up-ice his forehand is world −X) that turns at
# `rate` °/s once the skater has settled, and walks out from it at `dr` m/s;
# `swing` degrees either side of it at `swing_hz`, a dangle.
#
# `hold` pins the facing up-ice every tick, so the sweep walks the blade round
# the body instead of the body round the cursor: the arms' whole range at one
# facing. `skate` strides up-ice throughout, starting far enough down the rink
# to finish before the end boards.
#
# Views per frame, top to bottom: the chest, his left, his right (all turning
# with the body), and overhead from behind where he started.

const DT: float = 1.0 / 120.0
const VIEWS: int = 4
const SHEET_COLS: int = 12
const OUT_DIR: String = "user://arm_sweep"
const BUILD_HEIGHT_IN: int = 73
const BUILD_WEIGHT_LB: int = 201
const SETTLE_TICKS: int = 60
const SKATE_SETTLE_TICKS: int = 180
const SKATE_START_Z: float = 26.0
# The armhole's own seam: the sleeve's first stretch below the shoulder is
# skinned into the torso by design, so it is not measured.
const ARMHOLE_M: float = 0.12

const SCENARIOS: Array[Dictionary] = [
	# The blade walked from behind the backhand, across the front, round the
	# forehand to behind it: carried at a stick's reach, and pulled in tight.
	{"name": "carry_sweep", "r": 1.6, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": true, "hold": true},
	{"name": "tight_sweep", "r": 0.75, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": true, "hold": true},
	# The same at his skates, standing and skating.
	{"name": "feet_sweep", "r": 0.45, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": true, "hold": true},
	{"name": "skate_feet", "r": 0.5, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": true, "hold": true, "skate": true},
	# The cursor walked out from his skates, ahead, round the forehand and the
	# backhand: where the arms come out of the body.
	{"name": "radial_ahead", "r": 0.3, "dr": 0.1, "a0": 0.0, "rate": 0.0, "frames": 14, "step": 120,
		"puck": true, "hold": true},
	{"name": "radial_forehand", "r": 0.3, "dr": 0.1, "a0": 60.0, "rate": 0.0, "frames": 14, "step": 120,
		"puck": true, "hold": true},
	{"name": "radial_backhand", "r": 0.3, "dr": 0.1, "a0": -45.0, "rate": 0.0, "frames": 14, "step": 120,
		"puck": true, "hold": true},
	# The forehand arc where the two-hand stop lets the blade go, tick by tick.
	{"name": "forehand_trace", "r": 1.6, "a0": 40.0, "rate": 20.0, "frames": 1, "step": 1,
		"puck": true, "hold": true, "trace": true, "trace_ticks": 540},
	{"name": "front_trace", "r": 1.26, "a0": -30.0, "rate": 20.0, "frames": 1, "step": 1,
		"puck": true, "hold": true, "trace": true, "trace_ticks": 360},
	{"name": "stance_sweep", "r": 1.6, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": true, "hold": true, "stance": true},
	{"name": "empty_sweep", "r": 1.6, "a0": -150.0, "rate": 60.0, "frames": 24, "step": 25,
		"puck": false, "hold": true},
	# The body following the cursor round: standing, and skating up-ice with the
	# puck swept round the forehand and the backhand.
	{"name": "stand_spin", "r": 1.5, "a0": 0.0, "rate": 120.0, "frames": 12, "step": 30,
		"puck": true, "trace": true},
	{"name": "skate_forehand", "r": 2.0, "a0": 0.0, "rate": 45.0, "frames": 12, "step": 40,
		"puck": true, "skate": true, "trace": true},
	{"name": "skate_backhand", "r": 2.0, "a0": 0.0, "rate": -45.0, "frames": 12, "step": 40,
		"puck": true, "skate": true, "trace": true},
	# Held where tests/instruments/actors/test_carry_clipping.gd finds the shaft
	# in the body: skating with the puck behind on the forehand and in close on
	# the backhand, and pulled in tight standing.
	{"name": "clip_skate_forehand_behind", "r": 1.1, "a0": 140.0, "rate": 0.0, "frames": 4,
		"step": 40, "puck": true, "skate": true},
	{"name": "clip_skate_backhand_close", "r": 0.8, "a0": -90.0, "rate": 0.0, "frames": 4,
		"step": 40, "puck": true, "skate": true},
	{"name": "clip_stand_tight", "r": 0.5, "a0": -150.0, "rate": 60.0, "frames": 6, "step": 75,
		"puck": true, "hold": true},
	# A dangle across his front, a frame every 1/30 s over a stroke and a half:
	# standing, in tight, and skating.
	{"name": "dangle", "r": 1.25, "a0": 5.0, "rate": 0.0, "swing": 28.0, "swing_hz": 1.8,
		"frames": 24, "step": 4, "puck": true, "hold": true},
	{"name": "dangle_tight", "r": 0.9, "a0": 5.0, "rate": 0.0, "swing": 40.0, "swing_hz": 1.8,
		"frames": 24, "step": 4, "puck": true, "hold": true},
	{"name": "skate_dangle", "r": 1.6, "a0": 5.0, "rate": 0.0, "swing": 22.0, "swing_hz": 1.8,
		"frames": 24, "step": 4, "puck": true, "skate": true},
]


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return false


# Each view's size in pixels, square (tools/arm_sweep.gd's --tile).
var tile: int = 256

var _scenarios: Array[Dictionary] = []
var _index: int = -1
var _camera: Camera3D = null
var _state: StubGameState = null
var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null
var _input := InputState.new()
var _tick: int = 0
var _frame: int = 0
var _view: int = 0
var _grab: bool = false
var _images: Array[Image] = []
var _start := Vector3.ZERO


func begin(only: String, list: bool) -> void:
	if list:
		for s: Dictionary in SCENARIOS:
			print(String(s["name"]))
		get_tree().quit()
		return
	for s: Dictionary in SCENARIOS:
		if only == "" or only.split(",").has(String(s["name"])):
			_scenarios.append(s)
	if _scenarios.is_empty():
		push_error("no scenario matches --only=%s" % only)
		get_tree().quit()
		return
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	SkaterCameraCull.enabled = false
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	_state = StubGameState.new()
	add_child(_state)
	_build_stage()
	_next_scenario()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	env.environment = e
	add_child(env)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 40.0
	add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ice.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.60, 0.66)
	ice.material_override = mat
	add_child(ice)


func _scenario() -> Dictionary:
	return _scenarios[_index]


func _settle_ticks() -> int:
	return SKATE_SETTLE_TICKS if bool(_scenario().get("skate", false)) else SETTLE_TICKS


func _next_scenario() -> void:
	if _skater != null:
		_save_sheet()
		_controller.queue_free()
		_skater.queue_free()
		_puck.queue_free()
		_skater = null
	_index += 1
	if _index >= _scenarios.size():
		get_tree().quit()
		return
	_build_actor()
	_input = InputState.new()
	_tick = 0
	_frame = 0
	_view = 0
	_images.clear()
	print("── %s" % String(_scenario()["name"]))
	_drive(_settle_ticks())


func _build_actor() -> void:
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	add_child(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_skater)
	var start_z: float = SKATE_START_Z if bool(_scenario().get("skate", false)) else 0.0
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, start_z)
	_start = _skater.global_position
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var attrs := PlayerAttributes.new(BUILD_HEIGHT_IN, BUILD_WEIGHT_LB, 1, 1, 1, 1)
	_skater.set_uniform(TeamColorRegistry.get_colors(5, 0))
	_skater.set_jersey_info("ARMS", 8)
	_skater.apply_appearance(attrs)
	_skater.set_world_hud_hidden(true)
	_controller = SkaterController.new()
	add_child(_controller)
	_controller.setup(_skater, _puck, _state)
	_controller.apply_attributes(attrs)
	if bool(_scenario()["puck"]):
		_puck.set_carrier(_skater)
		_controller.on_puck_picked_up_network()
	else:
		_puck.visible = false
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


func _cursor_angle() -> float:
	var s: Dictionary = _scenario()
	var t: float = maxf(float(_tick - _settle_ticks()), 0.0) * DT
	return deg_to_rad(float(s["a0"]) + float(s["rate"]) * t
			+ float(s.get("swing", 0.0)) * sin(TAU * float(s.get("swing_hz", 0.0)) * t))


func _cursor() -> Vector3:
	var a: float = _cursor_angle()
	var t: float = maxf(float(_tick - _settle_ticks()), 0.0) * DT
	var r: float = float(_scenario()["r"]) + float(_scenario().get("dr", 0.0)) * t
	return _skater.global_position + Vector3(-sin(a), 0.0, -cos(a)) * r


func _drive(ticks: int) -> void:
	var s: Dictionary = _scenario()
	for _t: int in ticks:
		_input.move_vector = Vector2(0.0, -1.0) if bool(s.get("skate", false)) else Vector2.ZERO
		_input.stance_held = bool(s.get("stance", false))
		if bool(s.get("hold", false)):
			_controller._pose.facing = Vector2(0.0, -1.0)
			_skater.set_facing(Vector2(0.0, -1.0))
		_input.mouse_world_pos = _cursor()
		_input.mouse_world_pos.y = 0.0
		_input.delta = DT
		_input.host_timestamp += DT
		_controller._process_input(_input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)
		if bool(s["puck"]):
			_puck.global_position = _skater.get_carry_target_global()
		_tick += 1
		if bool(s.get("trace", false)) and _tick > _settle_ticks() and _tick % 6 == 0:
			_trace()


# Degrees off the facing, + toward the forehand.
func _off_facing(world: Vector3) -> float:
	var local: Vector3 = _skater.global_transform.basis.inverse() * (world - _skater.global_position)
	return rad_to_deg(atan2(-local.x, -local.z)) * (1.0 if _skater.is_left_handed else -1.0)


func _trace() -> void:
	var blade: Vector3 = _skater.upper_body_to_global(_skater.blade.position)
	var cursor: float = _off_facing(_cursor())
	var to_blade: Vector3 = blade - _skater.global_position
	print("    t%4d cursor %+5.0f° blade %+5.0f° (lag %+4.0f°) %.2f m out | facing %+5.0f° hips %+4.0f° twist %+4.0f° | %.1f m/s" % [
			_tick, cursor, _off_facing(blade), wrapf(cursor - _off_facing(blade), -180.0, 180.0),
			Vector2(to_blade.x, to_blade.z).length(), _skater.rotation_degrees.y,
			_skater.lower_body.rotation_degrees.y, _skater.upper_body.rotation_degrees.y,
			Vector2(_skater.velocity.x, _skater.velocity.z).length()])


# The arm's closest approach to the torso (m, negative inside) and where along
# it: 0 the shoulder, 1 the elbow, 2 the hand.
func _arm_clearance(upper: int, forearm: int, hand: int) -> Vector2:
	var body: Skeleton3D = _skater._arms._skeleton
	var worst := Vector2(INF, 0.0)
	for seg: int in 2:
		var pose: Transform3D = body.get_bone_global_pose(upper if seg == 0 else forearm)
		# A segment's +Z runs from its far joint back to its near one.
		var length: float = pose.basis.z.length()
		for k: int in 9:
			var along: float = float(k) / 8.0
			if seg == 0 and along * length < ARMHOLE_M:
				continue
			var p: Vector3 = pose.origin + pose.basis.z * (0.5 - along)
			var c: float = _skater._arms.torso_clearance(p) - SkaterMeshBuilder.SLEEVE_RADIUS_M
			if c < worst.x:
				worst = Vector2(c, float(seg) + along)
	var fist: float = _skater._arms.torso_clearance(body.get_bone_global_pose(hand).origin) \
			- _skater.hand_sphere_radius
	if fist < worst.x:
		worst = Vector2(fist, 2.0)
	return worst


# The forearm's angle to the shaft toward the blade, and how far the shaft sits
# off the hand's grip (SkaterArmPoses.glove_basis) — where the wrist ran out of
# range — degrees.
func _grip(forearm: int, hand: int, hand_local: Vector3, grip_deg: float) -> Vector2:
	var body: Skeleton3D = _skater._arms._skeleton
	var shaft: Vector3 = (_skater.drawn_upper_body().basis
			* _skater.stick_grip_axis(hand_local)).normalized()
	var fist: Transform3D = body.get_bone_global_pose(hand)
	var along: Vector3 = (fist.origin - body.get_bone_global_pose(forearm).origin).normalized()
	if shaft == Vector3.ZERO:
		return Vector2.ZERO
	return Vector2(rad_to_deg(along.angle_to(shaft)),
			absf(rad_to_deg((-fist.basis.y).angle_to(shaft)) - grip_deg))


func _report() -> void:
	var top: Vector2 = _arm_clearance(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM,
			SkaterMeshBuilder.UpperBone.TOP_FOREARM, SkaterMeshBuilder.UpperBone.TOP_HAND)
	var bottom: Vector2 = _arm_clearance(SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM, SkaterMeshBuilder.UpperBone.BOTTOM_HAND)
	var top_grip: Vector2 = _grip(SkaterMeshBuilder.UpperBone.TOP_FOREARM,
			SkaterMeshBuilder.UpperBone.TOP_HAND, _skater.drawn_top_hand(),
			_skater.top_grip_angle_deg)
	var bottom_grip: Vector2 = _grip(SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND, _skater.bottom_hand.position,
			_skater.bottom_grip_angle_deg)
	var to_blade: Vector3 = _skater.upper_body_to_global(_skater.blade.position) - _skater.global_position
	var hand_off: Vector3 = _skater.top_hand.position - _skater.shoulder.position
	print("  f%02d blade %.2f m out, top hand %.2f m ahead of its shoulder, %.2f below | trunk pitch %+3.0f°" % [
			_frame, Vector2(to_blade.x, to_blade.z).length(), -hand_off.z, -hand_off.y,
			_skater.upper_body.rotation_degrees.x])
	print("  f%02d cursor %+5.0f° | twist %+4.0f° hips %+4.0f° | clearance top %+.3f m @%.1f bottom %+.3f m @%.1f | top: forearm∠shaft %3.0f° off grip %2.0f° | bottom: %3.0f° %2.0f°" % [
			_frame, _off_facing(_cursor()), _skater.upper_body.rotation_degrees.y,
			_skater.lower_body.rotation_degrees.y, top.x, top.y, bottom.x, bottom.y,
			top_grip.x, top_grip.y, bottom_grip.x, bottom_grip.y])
	var ub_inv: Basis = _skater.drawn_upper_body().basis.inverse()
	var body: Skeleton3D = _skater._arms._skeleton
	_report_hold()
	var top_back: Vector3 = ub_inv * body.get_bone_global_pose(
			SkaterMeshBuilder.UpperBone.TOP_HAND).basis.z.normalized()
	var bottom_back: Vector3 = ub_inv * body.get_bone_global_pose(
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND).basis.z.normalized()
	var drawn_off: Vector3 = _skater.drawn_top_hand() - _skater.top_hand.position
	var clear_off: Vector3 = _controller._ik._clear_offset
	print("  f%02d   of it, the shaft's clearance %+.2f up %+.2f ahead" % [
			_frame, clear_off.y, -clear_off.z])
	print("  f%02d top hand drawn %+.2f m up %+.2f m ahead of its marker | elbow ahead of its hand: top %+.2f m bottom %+.2f m | back of glove (fwd, out, up): top %+.1f %+.1f %+.1f bottom %+.1f %+.1f %+.1f" % [
			_frame, drawn_off.y, -drawn_off.z, _elbow_ahead(SkaterMeshBuilder.UpperBone.TOP_FOREARM,
					SkaterMeshBuilder.UpperBone.TOP_HAND),
			_elbow_ahead(SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
					SkaterMeshBuilder.UpperBone.BOTTOM_HAND),
			-top_back.z, top_back.x * signf(_skater.shoulder.position.x), top_back.y,
			-bottom_back.z, bottom_back.x * signf(_skater.bottom_shoulder.position.x),
			bottom_back.y])


# The stick as held: how high each drawn hand and the shoulder over the top one
# ride off the ice, where the top hand and its elbow sit off that shoulder
# across the chest, how far apart the hands are, how steeply the shaft stands,
# and how bent each elbow is (0° a straight arm).
func _report_hold() -> void:
	var body: Skeleton3D = _skater._arms._skeleton
	var to_world: Transform3D = body.global_transform
	var top: Vector3 = to_world * body.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_HAND).origin
	var bottom: Vector3 = to_world * body.get_bone_global_pose(
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND).origin
	var upper: Transform3D = body.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM)
	var shoulder: Vector3 = to_world * (upper.origin + upper.basis.z * 0.5)
	var hips: Vector3 = to_world * body.get_bone_global_pose(SkaterBodySkeleton.HIPS_BONE).origin
	var chest: Basis = Basis(Vector3.UP, _skater.global_rotation.y + _skater.upper_body.rotation.y)
	var off: Vector3 = chest.inverse() * (top - shoulder)
	var blade: Vector3 = _skater.upper_body_to_global(_skater.drawn_blade().origin)
	var shaft: Vector3 = top - blade
	var elbow: Vector3 = chest.inverse() * (to_world * (upper.origin - upper.basis.z * 0.5) - shoulder)
	print("  f%02d top elbow %.2f m below its shoulder, %+.2f out %+.2f behind | blade's face leans %+3.0f° over the puck, drawn %+3.0f° round off the marker's" % [
			_frame, -elbow.y, elbow.x * signf(_skater.shoulder.position.x), elbow.z,
			_face_lean(), _blade_yaw_off_marker()])
	print("  f%02d hold: top hand %.2f m up, %+.2f ahead %+.2f out of its shoulder (%.2f up, hips %.2f) | hands %.2f apart, bottom %.2f up | shaft %2.0f° | elbows bent top %3.0f° bottom %3.0f°" % [
			_frame, top.y, -off.z, off.x * signf(_skater.shoulder.position.x), shoulder.y, hips.y,
			top.distance_to(bottom), bottom.y,
			rad_to_deg(asin(clampf(shaft.y / maxf(shaft.length(), 0.001), -1.0, 1.0))),
			_elbow_bend(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM,
					SkaterMeshBuilder.UpperBone.TOP_FOREARM),
			_elbow_bend(SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM,
					SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM)])


# How far the drawn blade's top edge leans toward the carried puck off
# upright (degrees, negative away from it): the cup a stroke's wrist roll lays
# over it.
func _face_lean() -> float:
	var mesh: MeshInstance3D = _skater._blade_mesh_instance
	if mesh == null or not bool(_scenario()["puck"]):
		return 0.0
	var xf: Transform3D = mesh.global_transform
	var to_puck: Vector3 = _puck.global_position - xf * Vector3(0.0, 0.0, -_skater.blade_length * 0.5)
	to_puck.y = 0.0
	if to_puck.length() < 0.001:
		return 0.0
	var top: Vector3 = xf.basis.y.normalized()
	return rad_to_deg(asin(clampf(top.dot(to_puck.normalized()), -1.0, 1.0)))


# How far round (degrees, about up) the drawn blade's heel→toe line lies off
# the Blade marker's, which the hold's drawn hand turns it by.
func _blade_yaw_off_marker() -> float:
	var mesh: MeshInstance3D = _skater._blade_mesh_instance
	if mesh == null:
		return 0.0
	var drawn: Vector3 = -mesh.global_transform.basis.z
	var marker: Vector3 = -_skater.blade.global_transform.basis.z
	return rad_to_deg(Vector2(marker.x, marker.z).angle_to(Vector2(drawn.x, drawn.z)))


func _elbow_bend(upper: int, forearm: int) -> float:
	var body: Skeleton3D = _skater._arms._skeleton
	return rad_to_deg(body.get_bone_global_pose(upper).basis.z.angle_to(
			body.get_bone_global_pose(forearm).basis.z))


# How far the elbow sits ahead of its hand along the chest's facing (m,
# UpperBody's frame as drawn).
func _elbow_ahead(forearm: int, hand: int) -> float:
	var body: Skeleton3D = _skater._arms._skeleton
	var ub_inv: Transform3D = _skater.drawn_upper_body().affine_inverse()
	var fore: Transform3D = body.get_bone_global_pose(forearm)
	var elbow: Vector3 = ub_inv * (fore.origin + fore.basis.z * 0.5)
	var fist: Vector3 = ub_inv * body.get_bone_global_pose(hand).origin
	return fist.z - elbow.z


func _place_camera(view: int) -> void:
	var fwd: Vector3 = -_skater.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left: Vector3 = Vector3.UP.cross(fwd)
	var aim: Vector3 = _skater.global_position + Vector3(0.0, -0.05, 0.0)
	var offset: Vector3
	match view:
		0:
			offset = fwd * 3.0 + Vector3(0.0, 0.5, 0.0)
		1:
			offset = left * 3.0 + fwd * 0.8 + Vector3(0.0, 0.5, 0.0)
		2:
			offset = -left * 3.0 + fwd * 0.8 + Vector3(0.0, 0.5, 0.0)
		_:
			aim = _skater.global_position + Vector3(0.0, -0.6, 0.0)
			offset = Vector3(0.0, 3.4, 1.4) if not bool(_scenario().get("skate", false)) \
					else -fwd * 1.4 + Vector3(0.0, 3.4, 0.0)
	_camera.global_position = aim + offset
	_camera.look_at(aim, Vector3.UP)


# One frame is VIEWS rendered images. get_texture() returns the LAST PRESENTED
# frame, so each grab happens on the frame after its camera move.
func _process(_delta: float) -> void:
	if _index >= _scenarios.size():
		return
	if _grab:
		_grab = false
		_images.append(get_viewport().get_texture().get_image())
	if _view == 0:
		if _frame >= int(_scenario()["frames"]):
			_next_scenario()
			return
		if _frame == 0 and _scenario().has("trace_ticks"):
			_drive(int(_scenario()["trace_ticks"]))
		if _frame > 0:
			_drive(int(_scenario()["step"]))
		_report()
		_frame += 1
	_place_camera(_view)
	_view = (_view + 1) % VIEWS
	_grab = true


func _save_sheet() -> void:
	var frames: int = _images.size() / VIEWS
	var cols: int = mini(frames, SHEET_COLS)
	var rows: int = ceili(float(frames) / float(cols))
	var sheet := Image.create(tile * cols, tile * VIEWS * rows, false, Image.FORMAT_RGBA8)
	for i: int in _images.size():
		var img: Image = _images[i]
		img.convert(Image.FORMAT_RGBA8)
		var f: int = i / VIEWS
		sheet.blit_rect(img, Rect2i(0, 0, tile, tile),
				Vector2i((f % cols) * tile, ((f / cols) * VIEWS + i % VIEWS) * tile))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = "%s/%s.png" % [OUT_DIR, String(_scenario()["name"])]
	sheet.save_png(path)
	print("  saved %s" % ProjectSettings.globalize_path(path))

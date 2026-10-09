extends Node

# The body of tools/gait_strip.gd — see that file for what a strip is for.
#
# Each scenario gets a fresh skater and controller, driven by hand at a fixed DT
# through the same calls a live tick makes (as tools/pose_capture_runner.gd
# does, for the same determinism), facing up-ice as a spawn leaves it. It skates
# WARM ticks to settle into the scenario, then FRAMES captures STEP ticks apart;
# each capture is three tiles — behind, beside (the travel's right) and ahead —
# so the strip is FRAMES columns by three rows.

const DT: float = 1.0 / 120.0
const TILE: int = 320
const FRAMES: int = 8
const VIEWS: int = 3
const OUT_DIR: String = "user://gait_strip"
# Ticks of straight skating before a turning scenario turns.
const TURN_AT: int = 180
# One build for every strip, as the pose capture does.
const BUILD_HEIGHT_IN: int = 73
const BUILD_WEIGHT_LB: int = 201

# name: the stick it holds (see _steer), how long it settles, and the spacing of
# its captures. A stride cycle at cruise is ~1 s, so 8 captures 12 ticks apart
# cover one.
const SCENARIOS: Array[Dictionary] = [
	{"name": "stride", "warm": 240, "step": 12},
	{"name": "stance", "warm": 240, "step": 12},
	# The stick held 45° off travel: a driven arc, the crossover's case.
	{"name": "turn45", "warm": 200, "step": 10},
	# The stick held across travel: the edges turn the skater with no thrust.
	{"name": "turn90", "warm": 200, "step": 10},
	# Keyboard: D alone, then W+D, from straight up-ice.
	{"name": "keyD", "warm": 200, "step": 10},
	{"name": "keyWD", "warm": 200, "step": 10},
	# Steering taps either side every quarter second.
	{"name": "tap", "warm": 200, "step": 10},
	{"name": "glide", "warm": 300, "step": 12},
	{"name": "stop", "warm": 200, "step": 6},
]


class StubGameState extends Node:
	var faceoff_prep: bool = false

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return faceoff_prep


var _scenarios: Array[Dictionary] = []
var _index: int = -1
var _camera: Camera3D = null
var _state: StubGameState = null
var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null
var _tick: int = 0
var _frame: int = 0
var _view: int = 0
var _grab: bool = false
var _images: Array[Image] = []


func begin(only: String) -> void:
	for s: Dictionary in SCENARIOS:
		if only == "" or only.split(",").has(String(s["name"])):
			_scenarios.append(s)
	if _scenarios.is_empty():
		push_error("no scenario matches --only=%s" % only)
		get_tree().quit()
		return
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
	# Big enough that a long turn never skates off it.
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ice.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.60, 0.66)
	ice.material_override = mat
	add_child(ice)


func _next_scenario() -> void:
	if _skater != null:
		_save_strip()
		_controller.queue_free()
		_skater.queue_free()
		_puck.queue_free()
		_skater = null
	_index += 1
	if _index >= _scenarios.size():
		get_tree().quit()
		return
	_build_actor()
	_tick = 0
	_frame = 0
	_view = 0
	_images.clear()
	print("── %s" % String(_scenarios[_index]["name"]))
	_skate(int(_scenarios[_index]["warm"]))


func _build_actor() -> void:
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	add_child(_puck)
	_puck.visible = false
	_puck.set_physics_process(false)
	_puck.set_process(false)
	_skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var attrs := PlayerAttributes.new(BUILD_HEIGHT_IN, BUILD_WEIGHT_LB, 1, 1, 1, 1)
	_skater.set_uniform(TeamColorRegistry.get_colors(5, 0))
	_skater.set_jersey_info("POSE", 8)
	_skater.apply_appearance(attrs)
	_skater.set_world_hud_hidden(true)
	_controller = SkaterController.new()
	add_child(_controller)
	_controller.setup(_skater, _puck, _state)
	_controller.apply_attributes(attrs)
	# Facing up-ice, as a spawn leaves it. From the default facing the cursor
	# ahead sits in the wedge behind the body that freezes facing, and the
	# skater would skate the whole strip backward.
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


# The stick and cursor for this tick, from the scenario and the current travel.
# The cursor leads along travel, so facing follows the skate.
func _steer(input: InputState) -> void:
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	var travel: Vector2 = v.normalized() if v.length() > 0.5 else Vector2(0.0, -1.0)
	var right := Vector2(-travel.y, travel.x)
	var up_ice := Vector2(0.0, -1.0)
	var turning: bool = _tick > TURN_AT
	var move: Vector2 = up_ice
	input.stance_held = false
	input.brake = false
	match String(_scenarios[_index]["name"]):
		"stance":
			input.stance_held = true
		"turn45":
			if turning:
				move = (travel + right).normalized()
		"turn90":
			if turning:
				move = right
		"keyD":
			if turning:
				move = Vector2(1.0, 0.0)
		"keyWD":
			if turning:
				move = Vector2(0.7071, -0.7071)
		"tap":
			if turning:
				var side: float = 1.0 if (_tick / 30) % 2 == 0 else -1.0
				move = Vector2(0.7071 * side, -0.7071)
		"glide":
			if turning:
				move = Vector2.ZERO
		"stop":
			if turning:
				move = Vector2.ZERO
				input.brake = true
	input.move_vector = move
	input.mouse_world_pos = _skater.global_position + Vector3(travel.x, 0.0, travel.y) * 4.0
	input.mouse_world_pos.y = 0.0
	input.delta = DT
	input.host_timestamp += DT


func _skate(ticks: int) -> void:
	var input := InputState.new()
	for _t: int in ticks:
		_steer(input)
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)
		_tick += 1


func _place_camera(view: int) -> void:
	var v := Vector3(_skater.velocity.x, 0.0, _skater.velocity.z)
	var travel: Vector3 = v.normalized() if v.length() > 0.5 else Vector3(0.0, 0.0, -1.0)
	var aim: Vector3 = _skater.global_position + Vector3(0.0, -0.35, 0.0)
	var offset: Vector3
	match view:
		0:
			offset = -travel * 3.6 + Vector3(0.0, 0.4, 0.0)
		1:
			offset = travel.cross(Vector3.UP) * 3.6 + Vector3(0.0, 0.3, 0.0)
		_:
			offset = travel * 3.6 + Vector3(0.0, 0.4, 0.0)
	_camera.global_position = aim + offset
	_camera.look_at(aim, Vector3.UP)


func _report() -> void:
	var m: LocomotionRules.Mix = _controller._skating.locomotion_mix()
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	print("  f%d t%d %.2f m/s %4.0f° | glide %.2f stride %.2f cross %.2f carve %.2f back %.2f shuffle %.2f skid %.2f tight %.2f stop %.2f | lean %.1f°" % [
			_frame, _tick, v.length(), rad_to_deg(atan2(v.x, -v.y)), m.glide, m.stride,
			m.crossover, m.carve, m.backward, m.shuffle, m.skid, m.tight, m.stop,
			rad_to_deg(_skater.balance_tilt().length())])


# One capture is three rendered frames, one per view. get_texture() returns the
# LAST PRESENTED frame, so each grab happens on the frame after its camera move.
func _process(_delta: float) -> void:
	if _index >= _scenarios.size():
		return
	if _grab:
		_grab = false
		_images.append(get_viewport().get_texture().get_image())
	if _view == 0:
		if _frame >= FRAMES:
			_next_scenario()
			return
		if _frame > 0:
			_skate(int(_scenarios[_index]["step"]))
		_report()
		_frame += 1
	_place_camera(_view)
	_view = (_view + 1) % VIEWS
	_grab = true


func _save_strip() -> void:
	var sheet := Image.create(TILE * FRAMES, TILE * VIEWS, false, Image.FORMAT_RGBA8)
	for i: int in _images.size():
		var img: Image = _images[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, TILE, TILE),
				Vector2i((i / VIEWS) * TILE, (i % VIEWS) * TILE))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = "%s/%s.png" % [OUT_DIR, String(_scenarios[_index]["name"])]
	sheet.save_png(path)
	print("  saved %s" % ProjectSettings.globalize_path(path))

extends Node

# The body of tools/puck_strip.gd — see that file for what a strip is for.
#
# Each scenario gets a fresh Puck in host mode, ticked by hand at a fixed DT
# through its own _physics_process (the analytic drive, then the spin rig), so
# every run draws the same frames. It ticks WARM ticks to reach the moment that
# matters, then captures FRAMES frames STEP ticks apart from a camera beside
# and a little above the puck, following it. The puck and its mesh are opted
# out of physics interpolation, so a capture is the tick's own attitude.

const DT: float = 1.0 / 120.0
const TILE_W: int = 320
const TILE_H: int = 240
const FRAMES: int = 16
const COLS: int = 8
const DEFAULT_OUT: String = "user://puck_strip"
const OUT_ENV: String = "PUCK_STRIP_OUT"
const ICE_Y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
# The side boards' face, where the analytic carom turns the puck's centre.
const BOARD_X: float = GameRules.INNER_HALF_WIDTH + GameRules.PUCK_COLLISION_RADIUS
# Camera offset from the puck: beside its travel and a little above, close
# enough that the 7.6 cm disc fills a fair share of the tile.
const CAMERA_OFFSET: Vector3 = Vector3(-0.05, 0.12, -0.42)

# pos / vel: the loose puck's start. carry: ticks a blade carries it at `vel`
# before `shot` releases it. kick_at / kick: the tick a contact the drive does
# not model (a stick in the air) sets the velocity to `kick`.
const SCENARIOS: Array[Dictionary] = [
	# Glancing off the side boards at 10 m/s along them: spin from the rim's
	# drag, and the wobble the hit starts, which the spin slows.
	{"name": "board", "pos": Vector3(9.0, ICE_Y, 0.0), "vel": Vector3(6.0, 0.0, 10.0),
			"warm": 70, "step": 3},
	# Square into the boards: nothing for the rim to drag along, so a wobble
	# with almost no spin to hold it up — it settles quickly.
	{"name": "square", "pos": Vector3(9.0, ICE_Y, 0.0), "vel": Vector3(9.0, 0.0, 0.0),
			"warm": 45, "step": 3},
	# A lofted puck landing while it slides: the leading edge catches.
	{"name": "landing", "pos": Vector3(0.0, 0.6, 0.0), "vel": Vector3(6.0, 1.5, 0.0),
			"warm": 50, "step": 3},
	# The faceoff drop: straight down onto the dot, and the rattle flat.
	{"name": "drop", "pos": Vector3(0.0, 1.0, 0.0), "vel": Vector3(0.0, -2.0, 0.0),
			"warm": 30, "step": 3},
	# Hit in the air with no spin: it tumbles end over end.
	{"name": "deflect", "pos": Vector3(0.0, 0.8, 0.0), "vel": Vector3(14.0, 2.5, 0.0),
			"warm": 6, "step": 4, "kick_at": 8, "kick": Vector3(11.0, 3.5, 6.0)},
	# A saucer pass off the blade: rolled heel to toe, it flies flat.
	{"name": "saucer", "pos": Vector3(0.0, ICE_Y, 0.0), "vel": Vector3(4.0, 0.0, 0.0),
			"carry": 30, "shot": Vector3(12.0, 2.5, 3.0), "warm": 36, "step": 4},
	# The same pass tipped in the air: its spin slows the tumble the tip
	# starts, against the spinless deflect.
	{"name": "tip", "pos": Vector3(0.0, ICE_Y, 0.0), "vel": Vector3(4.0, 0.0, 0.0),
			"carry": 30, "shot": Vector3(12.0, 2.5, 3.0), "kick_at": 44,
			"kick": Vector3(9.0, 3.0, 7.0), "warm": 40, "step": 4},
]

var _scenarios: Array[Dictionary] = []
var _index: int = -1
var _puck: Puck = null
var _carrier: Node3D = null
var _carrying: bool = false
var _camera: Camera3D = null
var _tick: int = 0
var _frame: int = 0
var _grab: bool = false
var _images: Array[Image] = []
var _rows: PackedStringArray = []
var _out_dir: String = DEFAULT_OUT


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
	var env_out: String = OS.get_environment(OUT_ENV)
	if env_out != "":
		_out_dir = env_out
	_build_stage()
	_next_scenario()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.50, 0.55, 0.60)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.60, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 30.0
	add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	key.light_energy = 1.4
	add_child(key)
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	ice.mesh = plane
	ice.material_override = _flat(Color(0.85, 0.88, 0.92))
	add_child(ice)
	var boards := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, GameRules.BOARD_TOP_HEIGHT, 200.0)
	boards.mesh = box
	boards.position = Vector3(BOARD_X + 0.05, GameRules.BOARD_TOP_HEIGHT * 0.5, 0.0)
	boards.material_override = _flat(Color(0.95, 0.95, 0.90))
	add_child(boards)
	_carrier = Node3D.new()
	add_child(_carrier)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _next_scenario() -> void:
	if _puck != null:
		_save_strip()
		_puck.queue_free()
		_puck = null
	_index += 1
	if _index >= _scenarios.size():
		get_tree().quit()
		return
	var s: Dictionary = _scenarios[_index]
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	_puck.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_puck)
	_puck.set_physics_process(false)
	_puck.set_process(false)
	# The trail and bursts are particles the Compatibility renderer half-supports.
	var vfx: Node = _puck.get_node_or_null("VFX")
	if vfx != null:
		vfx.free()
	_puck.set_server_mode(true)
	_puck.set_goalie_provider(func() -> Array: return [])
	_puck.set_carrier_view(_carrier_view)
	_puck.set_puck_position(s["pos"])
	_puck.set_puck_velocity(s["vel"])
	_carrying = s.has("carry")
	_tick = 0
	_frame = 0
	_images.clear()
	_rows.clear()
	_run(int(s["warm"]))


# The blade is a stand-in: a node a stick's length behind and to the side of
# the puck, which is all the rig asks of a carrier.
func _carrier_view() -> Node3D:
	return _carrier if _carrying else null


func _run(ticks: int) -> void:
	var s: Dictionary = _scenarios[_index]
	for i: int in ticks:
		_tick += 1
		if _carrying:
			if _tick > int(s["carry"]):
				_carrying = false
				_puck.set_puck_velocity(s["shot"])
			else:
				_puck.set_puck_velocity(s["vel"])
				_carrier.global_position = _puck.global_position + Vector3(-0.4, 0.0, -1.2)
		if s.has("kick_at") and _tick == int(s["kick_at"]):
			_puck.set_puck_velocity(s["kick"])
		_puck._physics_process(DT)


func _report() -> void:
	var rig: PuckSpinRig = _puck._spin
	var mesh: Node3D = _puck.get_node("MeshInstance3D") as Node3D
	_rows.append("  t%3d  y %.3f  spin %+6.1f  tilt %.3f  az %4.2f  tumble %5.1f  lift %.4f%s" % [
			_tick, _puck.global_position.y, rig.spin, rig.tilt, rig.tilt_azimuth,
			rig.tumble_rate, mesh.position.y, "  carried" if _carrying else ""])


# get_texture() returns the LAST PRESENTED frame, so each grab happens on the
# frame after its camera move, before the next ticks.
func _process(_delta: float) -> void:
	if _puck == null:
		return
	if _grab:
		_grab = false
		_images.append(get_viewport().get_texture().get_image())
	if _frame >= FRAMES:
		_next_scenario()
		return
	if _frame > 0:
		_run(int(_scenarios[_index]["step"]))
	_report()
	var p: Vector3 = _puck.global_position
	_camera.global_position = p + CAMERA_OFFSET
	_camera.look_at(p, Vector3.UP)
	_frame += 1
	_grab = true


func _save_strip() -> void:
	var rows: int = ceili(float(FRAMES) / COLS)
	var sheet := Image.create(TILE_W * COLS, TILE_H * rows, false, Image.FORMAT_RGBA8)
	for i: int in _images.size():
		var img: Image = _images[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, TILE_W, TILE_H),
				Vector2i((i % COLS) * TILE_W, (i / COLS) * TILE_H))
	var dir: String = ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("%s.png" % String(_scenarios[_index]["name"]))
	sheet.save_png(path)
	print("── %s -> %s" % [String(_scenarios[_index]["name"]), path])
	for row: String in _rows:
		print(row)

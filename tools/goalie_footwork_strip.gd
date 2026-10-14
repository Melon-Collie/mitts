extends SceneTree

# Dev visualizer for the upright goalie's footwork (GoalieFootwork): skates the
# real pose builder and footwork through scripted lateral moves — a shuffle, a
# T-push that brakes onto its spot, back the other way — and captures a frame
# every few ticks from the shooter's side and from high on his glove side. Each scenario saves one
# contact strip, so a stroke reads left to right. The goalie faces −Z; the moves
# use the same push-and-stop kinematics the live mover does
# (GoaliePushRules.push_progress).
#
#   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path . \
#       --rendering-driver opengl3 --rendering-method gl_compatibility \
#       --audio-driver Dummy -s res://tools/goalie_footwork_strip.gd
#
# PNGs to user://footwork_<scenario>_<view>.png (paths print on save).

const DT: float = 1.0 / 120.0
const SHUFFLE_SPEED: float = 2.0
const T_PUSH_SPEED: float = GameRules.DEFAULT_GOALIE_T_PUSH_SPEED_M_S
const ACCEL: float = GameRules.DEFAULT_GOALIE_LATERAL_ACCEL_M_S2
const FRAME_EVERY: int = 6
const TILE := Vector2i(256, 320)
# name, lateral distance (signed, + his right), top speed, T-push.
const SCENARIOS: Array = [
	["shuffle", 0.9, SHUFFLE_SPEED, false],
	["t_push", 1.6, T_PUSH_SPEED, true],
	["t_push_back", -1.6, T_PUSH_SPEED, true],
]
# view name, camera offset from the goalie, look-at height.
const VIEWS: Array = [
	["front", Vector3(0.0, 1.1, -3.4), 0.6],
	["high", Vector3(-1.8, 2.4, -2.2), 0.3],
]

var _goalie: Goalie
var _camera: Camera3D
var _builder := GoalieBodyConfigBuilder.new()
var _inputs := GoalieBodyConfigBuilder.Inputs.new()
var _footwork := GoalieFootwork.new()
var _frames: int = 0
var _scenario: int = 0
var _view: int = 0
var _tick: int = 0
var _x: float = 0.0
var _x0: float = 0.0
var _prev_speed: float = 0.0
var _total_ticks: int = 0
var _tiles: Array[Image] = []


func _init() -> void:
	DisplayServer.window_set_size(TILE)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment = e
	root.add_child(env)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	root.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	root.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.66, 0.72)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	_inputs.state = GoalieStateMachine.State.READY
	_inputs.direction_sign = 1
	_inputs.footwork = _footwork
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		_goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate()
		root.add_child(_goalie)
		_goalie.apply_uniform(TeamColorRegistry.get_colors(1, 0))
		_begin()
		return
	if _frames < 2:
		return
	_step()


func _begin() -> void:
	_footwork.reset()
	_tick = 0
	_x0 = 0.0
	_x = 0.0
	_prev_speed = 0.0
	_tiles.clear()
	var s: Array = _scenario_row()
	var settle: float = 0.3
	_total_ticks = int((GoaliePushRules.time_to_set(absf(s[1]), s[2], ACCEL) + settle) / DT)
	_goalie.set_goalie_position(0.0, 0.0)
	_goalie.apply_body_config(_builder.build(_inputs), 1.0)


func _scenario_row() -> Array:
	return SCENARIOS[_scenario]


# One tick of the scripted move, then a frame every FRAME_EVERY ticks.
func _step() -> void:
	var s: Array = _scenario_row()
	var dist: float = absf(s[1])
	var t: float = float(_tick) * DT
	var x: float = _x0 + signf(s[1]) * GoaliePushRules.push_progress(dist, s[2], ACCEL, t)
	var v: float = (x - _x) / DT
	_x = x
	var braking: bool = absf(v) < _prev_speed - 1e-4
	_prev_speed = absf(v)
	_footwork.advance(DT, v, s[3], braking, SHUFFLE_SPEED)
	_goalie.set_goalie_position(_x, 0.0)
	_goalie.apply_body_config(_builder.build(_inputs), 6.0 * DT)
	var view: Array = VIEWS[_view]
	_camera.position = Vector3(_x, 0.0, 0.0) + view[1]
	_camera.look_at(Vector3(_x, view[2], 0.0),
			Vector3.UP)
	# The frame on screen is last tick's, so the first capture waits a tick.
	if _tick > 0 and _tick % FRAME_EVERY == 0:
		_tiles.append(root.get_texture().get_image())
	_tick += 1
	if _tick > _total_ticks:
		_save_strip("footwork_%s_%s.png" % [s[0], view[0]])
		_view += 1
		if _view >= VIEWS.size():
			_view = 0
			_scenario += 1
		if _scenario >= SCENARIOS.size():
			quit()
			return
		_begin()


func _save_strip(fname: String) -> void:
	var w: int = _tiles[0].get_width()
	var h: int = _tiles[0].get_height()
	var strip := Image.create(w * _tiles.size(), h, false, _tiles[0].get_format())
	for i: int in _tiles.size():
		strip.blit_rect(_tiles[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	var path: String = "user://" + fname
	strip.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

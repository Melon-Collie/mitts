extends SceneTree

# Dev visualizer: close-ups of the goalie's blocker arm — elbow, board and
# stick — in the ready, standing and butterfly stances, each from the front,
# the shooter's blocker-side 3/4, the side and above. goalie_capture.gd frames
# the whole body; this frames the arm, where a winged elbow or a board laid
# along a flat forearm is easy to miss at full-body scale.
#
#   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path . \
#       --rendering-driver opengl3 --rendering-method gl_compatibility \
#       --audio-driver Dummy -s res://tools/goalie_blocker_capture.gd
#
# PNGs to user://blocker_<stance>_<angle>.png (paths print on save).

var _frames: int = 0
var _camera: Camera3D = null
var _goalie: Node3D = null
var _builder: GoalieBodyConfigBuilder = null
var _inputs: GoalieBodyConfigBuilder.Inputs = null
var _shots: Array = []
var _shot_i: int = 0

const _STANCES: Array = [
	["ready", GoalieStateMachine.State.READY, 0.75],
	["standing", GoalieStateMachine.State.STANDING, 0.85],
	["butterfly", GoalieStateMachine.State.BUTTERFLY, 0.45],
]
# name, camera offset from the look point (goalie faces -Z; blocker is +X).
const _ANGLES: Array = [
	["front", Vector3(0.0, 0.25, -2.4)],
	["shooter_right", Vector3(1.3, 0.25, -2.0)],
	["side", Vector3(2.4, 0.15, -0.1)],
	["top", Vector3(0.05, 2.4, -0.25)],
]


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(512, 640))
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
	light.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	light.light_energy = 1.2
	root.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.6
	root.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.60, 0.66)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	for st: Array in _STANCES:
		for an: Array in _ANGLES:
			_shots.append([st[0] + "_" + an[0], st[1], Vector3(0.12, st[2], -0.2), an[1]])
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		var scene: PackedScene = load("res://Scenes/Goalie.tscn")
		_goalie = scene.instantiate()
		root.add_child(_goalie)
		_goalie.call("apply_uniform", TeamColorRegistry.get_colors(1, 0))
		_builder = GoalieBodyConfigBuilder.new()
		_inputs = GoalieBodyConfigBuilder.Inputs.new()
		_inputs.state = GoalieStateMachine.State.READY
		_inputs.direction_sign = 1
		_aim()
		return
	if _frames < 2:
		return
	_goalie.call("apply_body_config", _builder.build(_inputs), 1.0)
	if _frames % 10 == 0:
		_save("blocker_%s.png" % _shots[_shot_i][0])
		_shot_i += 1
		if _shot_i >= _shots.size():
			quit()
			return
		_aim()


func _aim() -> void:
	var s: Array = _shots[_shot_i]
	_inputs.state = s[1]
	var at: Vector3 = s[2]
	_camera.position = at + s[3]
	_camera.look_at(at, Vector3.UP if absf((s[3] as Vector3).normalized().y) < 0.95 else Vector3.FORWARD)


func _save(fname: String) -> void:
	var img: Image = root.get_texture().get_image()
	var path: String = "user://" + fname
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

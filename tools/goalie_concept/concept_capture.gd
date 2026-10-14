extends SceneTree

# Renders the current goalie and the concept skin side by side: the same
# GoalieBodyConfigBuilder pose, the same camera, one PNG each, for every shot
# below. Needs a real (software) renderer, not --headless:
#
#   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path . \
#       --rendering-driver opengl3 --rendering-method gl_compatibility \
#       --audio-driver Dummy -s res://tools/goalie_concept/concept_capture.gd
#
# Writes user://goalie_concept/<shot>_old.png and <shot>_new.png.

const ConceptSkin := preload("res://tools/goalie_concept/concept_skin.gd")
const _SETTLE_FRAMES: int = 6
const _TEAM_SLOT: int = 1
const _TEAM_ID: int = 0

const S := GoalieStateMachine.State
# [name, state, camera position, look target, blocking seal, pose tweak]
const _SHOTS: Array = [
	["ready_front", S.READY, Vector3(0.0, 1.0, -3.0), Vector3(0.0, 0.75, 0.0), false],
	["ready_34", S.READY, Vector3(-2.6, 1.1, -1.6), Vector3(0.0, 0.72, 0.0), false],
	["ready_side", S.READY, Vector3(-3.0, 0.9, -0.1), Vector3(0.0, 0.72, -0.1), false],
	["ready_back", S.READY, Vector3(1.9, 1.5, 2.3), Vector3(0.0, 0.7, 0.0), false],
	["standing_front", S.STANDING, Vector3(0.0, 1.1, -3.2), Vector3(0.0, 0.9, 0.0), false],
	["butterfly_front", S.BUTTERFLY, Vector3(0.0, 1.0, -3.0), Vector3(0.0, 0.5, 0.0), false],
	["butterfly_34", S.BUTTERFLY, Vector3(-2.3, 1.2, -1.9), Vector3(0.0, 0.45, 0.0), false],
	["butterfly_back", S.BUTTERFLY, Vector3(1.4, 1.6, 2.2), Vector3(0.0, 0.4, 0.0), false],
	["blocking_front", S.BUTTERFLY, Vector3(0.0, 1.0, -3.0), Vector3(0.0, 0.5, 0.0), true],
	["half_butterfly_34", S.HALF_BUTTERFLY_RIGHT, Vector3(-2.3, 1.1, -2.0), Vector3(0.0, 0.55, 0.0), false],
	["rvh_left_34", S.RVH_LEFT, Vector3(-2.0, 1.1, -2.2), Vector3(0.0, 0.5, 0.0), false],
	["vh_left_34", S.VH_LEFT, Vector3(-2.0, 1.1, -2.2), Vector3(0.0, 0.6, 0.0), false],
	["covering_34", S.COVERING, Vector3(-2.0, 1.2, -2.2), Vector3(0.0, 0.4, 0.0), false],
	["catching_34", S.CATCHING, Vector3(-2.0, 1.2, -2.2), Vector3(0.0, 0.7, 0.0), false],
	["game_front", S.READY, Vector3(0.0, 7.5, -2.4), Vector3(0.0, 0.5, 0.0), false],
	["game_butterfly", S.BUTTERFLY, Vector3(0.0, 7.5, -2.4), Vector3(0.0, 0.3, 0.0), false],
	["game_back", S.READY, Vector3(0.0, 7.5, 2.4), Vector3(0.0, 0.5, 0.0), false],
	["stance_front", S.READY, Vector3(0.0, 1.0, -3.0), Vector3(0.0, 0.75, 0.0), false, "stance"],
	["stance_34", S.READY, Vector3(-2.6, 1.1, -1.6), Vector3(0.0, 0.72, 0.0), false, "stance"],
	["stance_side", S.READY, Vector3(-3.0, 0.9, -0.1), Vector3(0.0, 0.72, -0.1), false, "stance"],
]
# The proposed ready stance: shins lean forward over the skates, so the knees
# come out in front and the trunk folds less to get as low.
const _STANCE_SHIN_LEAN_DEG: float = 22.0
const _STANCE_BODY_PITCH_DEG: float = -20.0
const _PAD_HALF_H: float = 0.42
const _GAME_FOV: float = 22.0

var _frames: int = 0
var _camera: Camera3D
var _old: Node3D
var _new: Node3D
var _skin: Node
var _builder: GoalieBodyConfigBuilder
var _inputs: GoalieBodyConfigBuilder.Inputs
var _shot: int = -1
var _phase_start: int = 0
var _out_dir: String = "user://goalie_concept/"


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(480, 600))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.45
	env.environment = e
	root.add_child(env)
	# Nothing here runs on the physics tick, so interpolation would only lag
	# every camera cut and pose snap.
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, 200.0, 0.0)
	key.light_energy = 0.95
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 30.0, 0.0)
	fill.light_energy = 0.45
	root.add_child(fill)
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ice.mesh = plane
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.93, 0.95, 0.97)  # HockeyRink.ice_color
	im.roughness = 0.35
	ice.material_override = im
	root.add_child(ice)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		_old = _spawn()
		_new = _spawn()
		_skin = ConceptSkin.new()
		_new.add_child(_skin)
		_skin.dress(TeamColorRegistry.get_colors(_TEAM_SLOT, _TEAM_ID))
		_builder = GoalieBodyConfigBuilder.new()
		_inputs = GoalieBodyConfigBuilder.Inputs.new()
		_inputs.puck_position = Vector3(0.0, 0.0, -0.5)
		_next_shot()
		return
	if _frames < 2 or _shot >= _SHOTS.size():
		return
	var cfg: GoalieBodyConfig = _builder.build(_inputs)
	var shot: Array = _SHOTS[_shot]
	if shot.size() > 5 and shot[5] == "stance":
		_tweak_stance(cfg)
	_old.call("apply_body_config", cfg, 1.0)
	_new.call("apply_body_config", cfg, 1.0)
	var age: int = _frames - _phase_start
	if age == _SETTLE_FRAMES:
		_save(_SHOTS[_shot][0] + "_old.png")
		_old.visible = false
		_new.visible = true
	elif age == _SETTLE_FRAMES * 2:
		_save(_SHOTS[_shot][0] + "_new.png")
		print("  thighs ", _skin.thigh_length(0), " ", _skin.thigh_length(1))
		_next_shot()


func _tweak_stance(cfg: GoalieBodyConfig) -> void:
	var lp: Array = _lean_pad(cfg.left_pad_pos, cfg.left_pad_rot)
	cfg.left_pad_pos = lp[0]
	cfg.left_pad_rot = lp[1]
	var rp: Array = _lean_pad(cfg.right_pad_pos, cfg.right_pad_rot)
	cfg.right_pad_pos = rp[0]
	cfg.right_pad_rot = rp[1]
	var neck: Vector3 = _euler(cfg.body_rot).inverse() * (cfg.head_pos - cfg.body_pos)
	cfg.body_rot.x = _STANCE_BODY_PITCH_DEG
	cfg.head_pos = cfg.body_pos + _euler(cfg.body_rot) * neck


# Pivots a pad about its bottom so it leans forward with the shin.
func _lean_pad(pos: Vector3, rot: Vector3) -> Array:
	var bottom: Vector3 = pos - _euler(rot).y * _PAD_HALF_H
	var leaned := Vector3(-_STANCE_SHIN_LEAN_DEG, rot.y, rot.z)
	return [bottom + _euler(leaned).y * _PAD_HALF_H, leaned]


static func _euler(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))


func _spawn() -> Node3D:
	var g: Node3D = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate()
	g.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(g)
	g.call("apply_uniform", TeamColorRegistry.get_colors(_TEAM_SLOT, _TEAM_ID))
	g.call("apply_jersey_info", "MELON", 31)
	return g


func _next_shot() -> void:
	_shot += 1
	if _shot >= _SHOTS.size():
		quit()
		return
	var s: Array = _SHOTS[_shot]
	_inputs.state = s[1]
	_inputs.blocking_seal = s[4]
	var game: bool = (s[0] as String).begins_with("game_")
	_camera.fov = _GAME_FOV if game else 50.0
	_camera.position = s[2]
	_camera.look_at(s[3])
	_old.visible = true
	_new.visible = false
	_phase_start = _frames


func _save(fname: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(_out_dir + fname)
	print("saved ", ProjectSettings.globalize_path(_out_dir + fname))

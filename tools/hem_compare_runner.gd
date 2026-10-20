extends Node

# The body of tools/hem_compare.gd. One skater per hem sim (HemSimMode), in
# lanes far enough apart that none is in another's shot, all fed the same
# scripted input through a real SkaterController — skated, crouched on the move,
# stopped hard, crouched still, then turned — while the engine runs its own loop
# at a fixed 60 fps (render-hem.sh), so the soft body's physics steps as in a
# match and the spring solver runs in its modifier pass as it would.
#
# Out: one sheet per view (rows are the moments in CAPTURES, columns the modes
# in MODES order) and a table of how far each mode's tail went inside the thighs
# and pants (SkaterHemColliders.depth) over the run, per phase — the number the
# picture is checked against.

const DT: float = 1.0 / 120.0
const TILE: int = 320
const LANE_M: float = 8.0
const MODES: Array[int] = [HemSimMode.SWAY, HemSimMode.FLAPS, HemSimMode.SPRINGS,
		HemSimMode.SOFT_BODY]
const OUT_DIR: String = "user://hem_compare"
const BACKGROUND: Color = Color(0.10, 0.11, 0.14)
# Penetration below this is the fabric margin and render noise, not a clip.
const CLIP_EPS_M: float = 0.003

# [ticks, input spec, phase] — spec keys as pose_capture_runner's: move, aim
# (relative to the skater), stance, brake.
const SCENARIO: Array = [
	[60, {"aim": Vector3(0.0, 0.0, -3.0)}, "rest"],
	[200, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}, "skate"],
	[40, {"move": Vector2(0.0, -1.0), "stance": true, "aim": Vector3(0.0, 0.0, -3.0)},
			"skate_crouch"],
	[80, {"brake": true, "aim": Vector3(0.0, 0.0, -3.0)}, "stop"],
	[80, {"stance": true, "aim": Vector3(0.0, 0.0, -3.0)}, "crouch"],
	[120, {"move": Vector2(1.0, -0.2), "aim": Vector3(3.0, 0.0, 0.5)}, "turn"],
]
# Ticks at which every view of every mode is captured.
const CAPTURES: Array[int] = [55, 130, 250, 290, 315, 350, 440, 520, 575]
# Camera offsets from the skater, world space, and the point looked at.
const VIEWS: Array[Dictionary] = [
	{"name": "side", "cam": Vector3(2.3, 0.05, 0.3)},
	{"name": "rear", "cam": Vector3(0.9, 0.35, 2.1)},
	{"name": "front", "cam": Vector3(-0.9, 0.2, -2.1)},
]
const LOOK_AT: Vector3 = Vector3(0.0, -0.2, 0.0)


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func is_faceoff_prep() -> bool:
		return false


var _skaters: Array[Skater] = []
var _controllers: Array[SkaterController] = []
var _inputs: Array[InputState] = []
var _probes: Array[SkaterHemColliders] = []
# The loose tail's rest drape, for measuring the swung mode, which has no sim.
var _sway_rest: SkaterHemSim = null
var _viewports: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []
var _sheets: Array[Image] = []
var _tick: int = 0
var _segment: int = 0
var _segment_tick: int = 0
var _capture_row: int = -1
var _read_pending: bool = false
var _done: bool = false
# Per mode, per phase: [samples, clipped, depth sum, worst].
var _stats: Array[Dictionary] = []


func begin() -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	SkaterCameraCull.enabled = false
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	process_physics_priority = -10
	_build_stage()
	var state := StubGameState.new()
	add_child(state)
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	var puck_scene: PackedScene = load("res://Scenes/Puck.tscn")
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	for i: int in MODES.size():
		var puck: Puck = puck_scene.instantiate() as Puck
		add_child(puck)
		puck.visible = false
		puck.set_physics_process(false)
		puck.set_process(false)
		var skater: Skater = skater_scene.instantiate() as Skater
		skater.hem_sim_mode = MODES[i]
		skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(skater)
		skater.global_position = Vector3((i - 1.5) * LANE_M, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		skater.set_physics_process(false)
		skater.set_uniform(TeamColorRegistry.get_colors(5, 0))
		skater.set_jersey_info("HEM", 8)
		skater.apply_appearance(attrs)
		skater.set_world_hud_hidden(true)
		var controller := SkaterController.new()
		add_child(controller)
		controller.setup(skater, puck, state)
		controller.apply_attributes(attrs)
		_skaters.append(skater)
		_controllers.append(controller)
		_inputs.append(InputState.new())
		_probes.append(SkaterHemColliders.new())
		_stats.append({})
	_sway_rest = SkaterHemSim.new()
	_sway_rest.setup(_skaters[0], _rig(0), GearModelRegistry.TUCK_NONE)
	for v: int in VIEWS.size():
		_sheets.append(Image.create(TILE * MODES.size(), TILE * CAPTURES.size(), false,
				Image.FORMAT_RGBA8))
		for i: int in MODES.size():
			var vp := SubViewport.new()
			vp.size = Vector2i(TILE, TILE)
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(vp)
			var cam := Camera3D.new()
			cam.fov = 40.0
			cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			vp.add_child(cam)
			cam.current = true
			_viewports.append(vp)
			_cameras.append(cam)
	_frame(0)
	_read_pending = false


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.60, 0.66)
	floor_mesh.material_override = fm
	add_child(floor_mesh)


func _rig(i: int) -> Skeleton3D:
	return _skaters[i].mesh_root.get_node("BodyRig") as Skeleton3D


func _physics_process(_delta: float) -> void:
	if _done or _skaters.is_empty():
		return
	if _segment >= SCENARIO.size():
		_finish()
		return
	var step: Array = SCENARIO[_segment]
	var spec: Dictionary = step[1]
	var phase: String = step[2]
	for i: int in _skaters.size():
		_fill(_inputs[i], spec, _skaters[i])
		_controllers[i]._process_input(_inputs[i], DT)
		_skaters[i]._physics_process(DT)
		_measure(i, phase)
	_tick += 1
	_segment_tick += 1
	if _segment_tick >= int(step[0]):
		_segment += 1
		_segment_tick = 0
	var row: int = CAPTURES.find(_tick)
	if row >= 0 and not _read_pending:
		_frame(row)


func _process(_delta: float) -> void:
	if not _read_pending:
		return
	_read_pending = false
	for v: int in VIEWS.size():
		for i: int in MODES.size():
			var img: Image = _viewports[v * MODES.size() + i].get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			_sheets[v].blit_rect(img, Rect2i(0, 0, TILE, TILE),
					Vector2i(i * TILE, _capture_row * TILE))


func _frame(row: int) -> void:
	_capture_row = row
	for v: int in VIEWS.size():
		for i: int in MODES.size():
			var cam: Camera3D = _cameras[v * MODES.size() + i]
			var at: Vector3 = _skaters[i].global_position
			cam.global_position = at + (VIEWS[v]["cam"] as Vector3)
			cam.look_at(at + LOOK_AT, Vector3.UP)
			_viewports[v * MODES.size() + i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_read_pending = true


func _fill(input: InputState, spec: Dictionary, skater: Skater) -> void:
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = spec.get("move", Vector2.ZERO)
	input.mouse_world_pos = skater.global_position + (spec.get("aim", Vector3(0.0, 0.0, -3.0)) as Vector3)
	input.stance_held = spec.get("stance", false)
	input.brake = spec.get("brake", false)


# Every sample on the drawn tail, against the thighs and pants as posed now.
func _measure(i: int, phase: String) -> void:
	var rig: Skeleton3D = _rig(i)
	var probe: SkaterHemColliders = _probes[i]
	probe.update(rig)
	var points: PackedVector3Array = _swung_points(rig) if MODES[i] == HemSimMode.SWAY \
			else _skaters[i]._arms._hem_sim.hem_points()
	var row: Array = _stats[i].get_or_add(phase, [0, 0, 0.0, 0.0])
	for p: Vector3 in points:
		var d: float = probe.depth(p)
		row[0] += 1
		if d > CLIP_EPS_M:
			row[1] += 1
			row[2] += d
			row[3] = maxf(float(row[3]), d)


# Where the swung tail's bend and hem points are drawn: its weights
# (SkaterJerseyHem.append_torso), below the belt, through this frame's bones.
func _swung_points(rig: Skeleton3D) -> PackedVector3Array:
	var hem: Transform3D = rig.get_bone_global_pose(SkaterBodySkeleton.HEM_BONE)
	var tail: Transform3D = rig.get_bone_global_pose(SkaterBodySkeleton.TAIL_BONE)
	var tail_hem: Transform3D = rig.get_bone_global_pose(SkaterBodySkeleton.TAIL_HEM_BONE)
	var drawn := PackedVector3Array()
	for k: int in _sway_rest.columns:
		var hips: float = _sway_rest.hips_share[k]
		var t: float = _sway_rest.tuck_share[k]
		var at := PackedVector3Array()
		for station: int in [0, SkaterHemSim.BEND, SkaterHemSim.HEM]:
			var v: Vector3 = _sway_rest.rest[station][k]
			at.append((hem * v) * (1.0 - hips) + ((tail * v) * t + (tail_hem * v) * (1.0 - t)) * hips)
		drawn.append(at[1])
		drawn.append(at[2])
		drawn.append((at[0] + at[1]) * 0.5)
		drawn.append((at[1] + at[2]) * 0.5)
	return drawn


func _finish() -> void:
	_done = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for v: int in VIEWS.size():
		var path: String = "%s/sheet_%s.png" % [OUT_DIR, VIEWS[v]["name"]]
		_sheets[v].save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
	print("columns: ", ", ".join(PackedStringArray(
			MODES.map(func(m: int) -> String: return HemSimMode.NAMES[m]))))
	print("rows (tick): ", CAPTURES)
	print("\n── Tail inside the thighs / pants (clip > %.0f mm) ──" % (CLIP_EPS_M * 1000.0))
	print("%-10s %-13s %8s %10s %10s" % ["mode", "phase", "clipped", "mean mm", "worst mm"])
	for i: int in MODES.size():
		var total: Array = [0, 0, 0.0, 0.0]
		for step: Array in SCENARIO:
			var row: Array = _stats[i].get(step[2], [0, 0, 0.0, 0.0])
			print("%-10s %-13s %7.1f%% %10.1f %10.1f" % [HemSimMode.NAMES[MODES[i]], step[2],
					100.0 * row[1] / maxf(row[0], 1.0), 1000.0 * row[2] / maxf(row[1], 1.0),
					1000.0 * row[3]])
			for j: int in 3:
				total[j] += row[j]
			total[3] = maxf(total[3], row[3])
		print("%-10s %-13s %7.1f%% %10.1f %10.1f" % [HemSimMode.NAMES[MODES[i]], "ALL",
				100.0 * total[1] / maxf(total[0], 1.0), 1000.0 * total[2] / maxf(total[1], 1.0),
				1000.0 * total[3]])
	_time_flaps()
	get_tree().quit()


# The flaps are the one sim whose whole cost is script: one step, timed — with
# its bone writes, each of which the next step's pose reads pay to re-solve the
# skeleton for (as a frame does once), and without (the solver alone).
func _time_flaps() -> void:
	var sim: SkaterHemSim = _skaters[MODES.find(HemSimMode.FLAPS)]._arms._hem_sim
	for on_camera: bool in [true, false]:
		var t0: int = Time.get_ticks_usec()
		for n: int in 200:
			sim.update(1.0 / 60.0, on_camera)
		print("flaps step%s: %.0f µs (GDScript)" % [" + bone writes" if on_camera else "",
				(Time.get_ticks_usec() - t0) / 200.0])

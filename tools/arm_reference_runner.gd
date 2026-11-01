extends Node

# Draws what the arm anatomy model makes of each reference carry
# (tests/harness/arm_reference_carries.gd): the jersey's rings as the trunk
# holds them, both arms (green inside their ranges, red past one), the hands,
# the stick from its knob to its blade, the reference's puck, from the front,
# the top hand's side, above and three quarters. One sheet a carry, with what
# binds printed. tools/arm_reference_capture.gd boots it; the hook is
# .claude/hooks/render-references.sh.

const Carries := preload("res://tests/harness/arm_reference_carries.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const OUT_ENV: String = "ARM_REFERENCE_OUT"
const DEFAULT_OUT: String = "user://arm_reference"
const TILE := Vector2i(360, 360)
# Off the body's middle, looking at its chest (the body faces -Z).
const VIEWS: Array[Dictionary] = [
	{"name": "front", "eye": Vector3(0.0, 1.1, -4.2), "at": Vector3(0.0, 0.6, -0.5)},
	{"name": "side", "eye": Vector3(4.2, 1.0, -0.6), "at": Vector3(0.0, 0.6, -0.6)},
	{"name": "above", "eye": Vector3(0.0, 4.6, -0.6), "at": Vector3(0.0, 0.0, -0.6)},
	{"name": "three_quarter", "eye": Vector3(3.0, 2.0, -3.4), "at": Vector3(0.0, 0.6, -0.5)},
]
const ARM_RADIUS: float = 0.05
const SHAFT_RADIUS: float = 0.015

var _carries: Array[Dictionary] = []
var _index: int = -1
var _view: int = 0
var _wait: int = 0
var _images: Array[Image] = []
var _figure: Node3D = null
var _camera: Camera3D
var _body: ArmAnatomyBody
var _trunk: ArmAnatomySearch.TrunkState
var _pivot_m: float = 0.0
var _blade_m: float = 0.0
var _search: ArmAnatomySearch
var _out_dir: String = DEFAULT_OUT
var _lines: PackedStringArray = []


func begin(only: String, list: bool) -> void:
	if list:
		for c: Dictionary in Carries.CARRIES:
			print(String(c["name"]))
		get_tree().quit()
		return
	for c: Dictionary in Carries.CARRIES:
		if only == "" or only.split(",").has(String(c["name"])):
			_carries.append(c)
	if OS.get_environment(OUT_ENV) != "":
		_out_dir = OS.get_environment(OUT_ENV)
	_build_model()
	_build_stage()
	_next_carry()


# A neutral skater standing at rest, read into the model.
func _build_model() -> void:
	var skater: Skater = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	add_child(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	add_child(puck)
	puck.set_physics_process(false)
	var stub := _GameStateStub.new()
	add_child(stub)
	var c := SkaterController.new()
	add_child(c)
	c.setup(skater, puck, stub)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	_body = SkaterAnatomyCapture.capture(c)
	_trunk = SkaterAnatomyCapture.trunk_state(skater, _body)
	_trunk.crouch_max = 1.0
	_pivot_m = SkaterAnatomyCapture.pivot_height(skater)
	_blade_m = c.blade_height
	_search = ArmAnatomySearch.new(_body)
	_search.technique = true
	skater.visible = false
	puck.visible = false


class _GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(key)
	var ice := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ice.mesh = plane
	ice.material_override = _flat(Color(0.88, 0.9, 0.94))
	add_child(ice)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)


func _next_carry() -> void:
	if _figure != null:
		_save_sheet()
		_figure.queue_free()
		_figure = null
	_index += 1
	if _index >= _carries.size():
		_write_report()
		get_tree().quit()
		return
	var carry: Dictionary = _carries[_index]
	var s: Dictionary = Carries.setup(carry, _body, _pivot_m, _blade_m)
	var pose := ArmAnatomySearch.Pose.new()
	_search.hold(_trunk, s["heel"], s["twist"], s["lie"], s["heading"], s["spacing"], pose,
			s["lean"], s["crouch"])
	_figure = _draw_pose(pose, s)
	add_child(_figure)
	_report(carry, pose, s)
	_view = 0
	_images.clear()


# get_texture() returns the last PRESENTED frame, so a view is grabbed two
# frames after its camera moved: one to draw it, one to present it.
func _process(_delta: float) -> void:
	if _figure == null:
		return
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_images.append(get_viewport().get_texture().get_image())
			_view += 1
		return
	if _view >= VIEWS.size():
		_next_carry()
		return
	_camera.global_position = VIEWS[_view]["eye"]
	_camera.look_at(VIEWS[_view]["at"], Vector3.UP if _view != 2 else Vector3.FORWARD)
	_wait = 2


# The pose in the world: the hips frame's origin at the trunk's pivot over the
# body's middle, sunk by the crouch.
func _draw_pose(pose: ArmAnatomySearch.Pose, s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.0, _pivot_m - pose.crouch, 0.0)
	var spine := Transform3D(ArmAnatomySearch.spine_basis(_trunk, pose.twist, pose.lean),
			Vector3.ZERO)
	var torso: Transform3D = spine * _body.torso_in_spine
	for i: int in _body.torso_profile.size():
		var ring: Vector2 = _body.torso_profile[i]
		var pts := PackedVector3Array()
		for k: int in 25:
			var t: float = TAU * float(k) / 24.0
			pts.append(torso * Vector3(cos(t) * ring.y * _body.torso_xz_scale.x, ring.x,
					sin(t) * ring.y * _body.torso_xz_scale.y + _body.torso_sway[i]))
		_strip(root, pts, Color(0.2, 0.25, 0.6))
	for arm: ArmAnatomy.ArmPose in [pose.top, pose.bottom]:
		var color := Color(0.2, 0.75, 0.3) if arm.feasible() else Color(0.85, 0.2, 0.2)
		_segment(root, arm.root, arm.elbow, ARM_RADIUS, color)
		_segment(root, arm.elbow, arm.hand, ARM_RADIUS * 0.8, color)
		_ball(root, arm.root, ARM_RADIUS * 1.3, Color(0.3, 0.3, 0.35))
		_ball(root, arm.hand, ARM_RADIUS * 1.1, Color(0.1, 0.1, 0.1))
	var shaft: Vector3 = (pose.top.hand - pose.bottom.hand).normalized() * -1.0
	var heel: Vector3 = Vector3(s["heel"]) + Vector3.UP * pose.crouch
	var knob: Vector3 = pose.top.hand - shaft * _body.knob_extend
	_segment(root, knob, heel, SHAFT_RADIUS, Color(0.9, 0.75, 0.3))
	var blade_dir: Vector3 = Vector3(shaft.x, 0.0, shaft.z).normalized()
	_segment(root, heel, heel + blade_dir * _body.blade_length, SHAFT_RADIUS * 2.0,
			Color(0.1, 0.1, 0.1))
	_ball(root, Vector3(s["puck"]) + Vector3.UP * pose.crouch, 0.04, Color(0.05, 0.05, 0.05))
	# The hips, and a plumb line to the ice for scale.
	_ball(root, Vector3.ZERO, 0.06, Color(0.4, 0.4, 0.4))
	_segment(root, Vector3.ZERO, Vector3(0.0, -_pivot_m + pose.crouch, 0.0), 0.01,
			Color(0.4, 0.4, 0.4))
	return root


func _segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var length: float = a.distance_to(b)
	if length < 0.001:
		return
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	m.mesh = cyl
	m.material_override = _flat(color)
	var up: Vector3 = (b - a) / length
	var side: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	m.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	parent.add_child(m)


func _ball(parent: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	m.mesh = sphere
	m.material_override = _flat(color)
	m.position = at
	parent.add_child(m)


func _strip(parent: Node3D, pts: PackedVector3Array, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: Vector3 in pts:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := _flat(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	parent.add_child(m)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _report(carry: Dictionary, pose: ArmAnatomySearch.Pose, s: Dictionary) -> void:
	var why: String = "held"
	if not pose.feasible():
		if pose.binding_arm >= 0:
			why = "%s arm: %s +%.0f°" % ["top" if pose.binding_arm == 0 else "bottom",
					ArmAnatomy.Limit.keys()[pose.arm_binding], rad_to_deg(pose.violation)]
		elif pose.trunk_binding == ArmAnatomySearch.Limit.TECHNIQUE:
			why = "technique: %s +%.2f m" % [ArmTechnique.Limit.keys()[pose.technique.binding],
					pose.technique.violation / ArmAnatomy.METRE_AS_RADIANS]
		else:
			why = "%s +%.0f°" % [ArmAnatomySearch.Limit.keys()[pose.trunk_binding],
					rad_to_deg(pose.violation)]
	var off: float = Vector2(Vector3(s["heel"]).x - Vector3(s["puck"]).x,
			Vector3(s["heel"]).z - Vector3(s["puck"]).z).length()
	_lines.append("%s: %s (blade %.2f m off the reference's puck; lie %.0f°)" % [carry["name"], why,
			off, rad_to_deg(float(s["lie"]))])
	for arm_name: String in ["top", "bottom"]:
		var a: ArmAnatomy.ArmPose = pose.top if arm_name == "top" else pose.bottom
		_lines.append("    %s: shoulder raised %.0f° (plane %.0f°) turned %+.0f°, elbow %.0f°, forearm %+.0f°, wrist %+.0f°/%+.0f°, in the jersey %.0f cm%s" % [
				arm_name, rad_to_deg(a.elevation), rad_to_deg(a.plane), rad_to_deg(a.axial),
				rad_to_deg(a.elbow_flexion), rad_to_deg(a.pronation), rad_to_deg(a.wrist_flexion),
				rad_to_deg(a.wrist_deviation), maxf(a.torso_depth, 0.0) * 100.0,
				"" if a.feasible() else "  <- " + ArmAnatomy.Limit.keys()[a.binding]])
	print(_lines[_lines.size() - 3])
	print(_lines[_lines.size() - 2])
	print(_lines[_lines.size() - 1])


func _save_sheet() -> void:
	var sheet := Image.create(TILE.x * VIEWS.size(), TILE.y, false, Image.FORMAT_RGBA8)
	for i: int in _images.size():
		var img: Image = _images[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(TILE.x, TILE.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(i * TILE.x, 0))
	var dir: String = ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("%s.png" % String(_carries[_index]["name"]))
	sheet.save_png(path)
	print("── %s -> %s" % [_carries[_index]["name"], path])


func _write_report() -> void:
	var dir: String = ProjectSettings.globalize_path(_out_dir)
	var f: FileAccess = FileAccess.open(dir.path_join("report.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()

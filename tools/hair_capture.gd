extends SceneTree

# Dev visualizer: renders every pickable hair style against every facial-hair
# style — one head per pair, scalp styles down the rows and facial styles
# across the columns — and saves a PNG per shot (front three-quarter, side,
# back three-quarter, from below in front and behind, from above), so a hair
# edit can be SEEN without launching the game. Each head is the rink's own
# helmet assembly wearing the rink's own hair shells and material, so what the
# sheet shows is what the ice shows.
#
#   .claude/hooks/render-hair.sh                      # helmeted, into .preview/hair
#   HAIR_PREVIEW_BARE=1 .claude/hooks/render-hair.sh  # the helmet shell left off
#
# HAIR_PREVIEW_OUT (default user://hair_preview), HAIR_PREVIEW_SHOTS (comma
# list of shot names), HAIR_PREVIEW_FACIALS (comma list of FACIAL_* indices,
# default all), HAIR_PREVIEW_ZOOM (pixels per head, a multiple, default 1). MITTS_FACE (a GearModelRegistry FACE_* index, default bare),
# MITTS_SKIN (a SkinToneRegistry index) and MITTS_HAIR_COLOR (a
# HairStyleRegistry colour) dress every head the same, so one run answers one
# question — does the beard clear the cage, does blonde read on the lightest
# skin.

const _SPACING_M: float = 0.40
const _ROW_M: float = 0.42
const _ORTHO_MARGIN_M: float = 0.40
const _LABEL_DROP_M: float = 0.20
# One head's share of the window: the ortho camera fits the columns to its
# width, so this keeps _ROW_M of height per row at that scale.
const _CELL_PX := Vector2i(300, 315)
# Each shot's (yaw off facing the camera, pitch toward it), degrees: a negative
# pitch tips the chin toward the camera, which then looks up from below.
const _SHOTS: Dictionary[String, Vector2] = {
	"front": Vector2(30.0, 0.0),
	"side": Vector2(90.0, 0.0),
	"back": Vector2(150.0, 0.0),
	"below_front": Vector2(25.0, -30.0),
	"below_back": Vector2(155.0, -30.0),
	"above": Vector2(40.0, 40.0),
}
const _HELMET_COLOR := Color(0.12, 0.20, 0.45)

var _frames: int = 0
var _shot: int = 0
var _shot_names: Array[String] = []
var _holders: Array[Node3D] = []
var _face: int = GearModelRegistry.FACE_NONE
var _skin: int = SkinToneRegistry.DEFAULT_INDEX
var _hair_color: int = 0
var _bare: bool = false
var _out_dir: String = "user://hair_preview"
var _hair_rows: Array[int] = HairStyleRegistry.pickable_hair()
var _facial_cols: Array[int] = []


func _init() -> void:
	_face = _env_int("MITTS_FACE", GearModelRegistry.FACE_NONE)
	_skin = _env_int("MITTS_SKIN", SkinToneRegistry.DEFAULT_INDEX)
	_hair_color = _env_int("MITTS_HAIR_COLOR", 0)
	_bare = OS.get_environment("HAIR_PREVIEW_BARE") == "1"
	if OS.get_environment("HAIR_PREVIEW_OUT") != "":
		_out_dir = OS.get_environment("HAIR_PREVIEW_OUT")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for raw: String in OS.get_environment("HAIR_PREVIEW_FACIALS").split(",", false):
		if raw.is_valid_int() and HairStyleRegistry.is_valid_facial(int(raw)):
			_facial_cols.append(int(raw))
	if _facial_cols.is_empty():
		for style: int in HairStyleRegistry.facial_count():
			_facial_cols.append(style)
	for raw: String in OS.get_environment("HAIR_PREVIEW_SHOTS").split(",", false):
		if _SHOTS.has(raw):
			_shot_names.append(raw)
	if _shot_names.is_empty():
		_shot_names.assign(_SHOTS.keys())

	var cols: int = _facial_cols.size()
	var rows: int = _hair_rows.size()
	var zoom: int = maxi(_env_int("HAIR_PREVIEW_ZOOM", 1), 1)
	DisplayServer.window_set_size(Vector2i(_CELL_PX.x * maxi(cols, 2), _CELL_PX.y * rows + 40) * zoom)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.52)
	env.environment = e
	root.add_child(env)

	var span: float = _SPACING_M * float(maxi(cols, 2) - 1)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = span + _ORTHO_MARGIN_M
	camera.position = Vector3(0.0, -_ROW_M * float(rows - 1) * 0.5, 2.0)
	root.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	light.light_energy = 1.2
	root.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -150.0, 0.0)
	fill.light_energy = 0.5
	root.add_child(fill)

	var x0: float = -_SPACING_M * float(cols - 1) * 0.5
	for row: int in rows:
		for col: int in cols:
			_place(Vector3(x0 + _SPACING_M * float(col), -_ROW_M * float(row), 0.0),
					_hair_rows[row], _facial_cols[col])
	process_frame.connect(_on_frame)


func _place(at: Vector3, hair: int, facial: int) -> void:
	var holder := Node3D.new()
	holder.position = at
	root.add_child(holder)
	_holders.append(holder)

	# The mesh faces −Z; turned to face the camera, each head is then turned per
	# shot by its holder.
	var head := Node3D.new()
	head.basis = Basis(Vector3.UP, PI)
	holder.add_child(head)

	var helmet := MeshInstance3D.new()
	helmet.mesh = SkaterMeshBuilder.shared_helmet_assembly()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = _HELMET_COLOR
	shell.roughness = 0.28
	if _bare:
		shell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shell.albedo_color.a = 0.0
	helmet.set_surface_override_material(SkaterMeshBuilder.HELMET_SURF_SHELL, shell)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SkinToneRegistry.color_for(_skin)
	skin.roughness = 0.85
	skin.vertex_color_use_as_albedo = true
	helmet.set_surface_override_material(SkaterMeshBuilder.HELMET_SURF_SKIN, skin)
	head.add_child(helmet)

	_add_piece(head, SkaterHairMesh.shared_hair(hair),
			SkaterHairMesh.make_material(_hair_color, SkaterHairMesh.is_scalp_translucent(hair)))
	_add_piece(head, SkaterHairMesh.shared_brows(),
			SkaterHairMesh.make_material(_hair_color, false))
	_add_piece(head, SkaterHairMesh.shared_facial_hair(facial, _face),
			SkaterHairMesh.make_material(_hair_color, SkaterHairMesh.is_translucent(facial)))
	_add_piece(head, SkaterMeshBuilder.shared_face_gear(_face),
			SkaterMeshBuilder.make_face_gear_material(_face))

	var label := Label3D.new()
	label.text = "%s / %s" % [tr(HairStyleRegistry.HAIR_NAME_KEYS[hair]),
			tr(HairStyleRegistry.FACIAL_NAME_KEYS[facial])]
	label.pixel_size = 0.0009
	label.font_size = 48
	label.position = at + Vector3(0.0, -_LABEL_DROP_M, 0.3)
	root.add_child(label)


func _add_piece(parent: Node3D, mesh: ArrayMesh, mat: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)


func _env_int(key: String, fallback: int) -> int:
	var raw: String = OS.get_environment(key)
	return int(raw) if raw.is_valid_int() else fallback


func _on_frame() -> void:
	_frames += 1
	if _frames == 2:
		_turn(_SHOTS[_shot_names[_shot]])
	elif _frames == 12:
		_save("hair_%s%s.png" % ["bare_" if _bare else "", _shot_names[_shot]])
		_shot += 1
		if _shot >= _shot_names.size():
			quit()
			return
		_frames = 1


# Pitched about the camera's own horizontal, after the yaw, so a shot from
# below stays below whichever side of the head it shows.
func _turn(shot: Vector2) -> void:
	var basis := Basis(Vector3.RIGHT, deg_to_rad(shot.y)) * Basis(Vector3.UP, deg_to_rad(shot.x))
	for holder: Node3D in _holders:
		holder.basis = basis


func _save(fname: String) -> void:
	var img: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(fname)
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

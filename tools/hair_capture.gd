extends SceneTree

# Dev visualizer: renders every pickable hair style against every facial-hair
# style — one helmeted head per pair, scalp styles down the rows and facial
# styles across the columns — and saves PNGs from three angles (front three-quarter,
# side, back three-quarter), so a hair edit can be SEEN without launching the
# game. Each head is the rink's own helmet assembly wearing the rink's own hair
# shells and material, so what the sheet shows is what the ice shows.
#
# Needs a real (software) renderer, not --headless. On the web container:
#
#   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a godot --path . \
#       --rendering-driver opengl3 --audio-driver Dummy \
#       -s res://tools/hair_capture.gd
#
# Locally any GPU works: drop the env var and xvfb-run. Output paths print on
# save (user:// — never the repo tree, so captures can't be committed).
#
# MITTS_FACE (a GearModelRegistry FACE_* index, default bare), MITTS_SKIN (a
# SkinToneRegistry index) and MITTS_HAIR_COLOR (a HairStyleRegistry colour)
# dress every head the same, so one run answers one question — does the beard
# clear the cage, does blonde read on the lightest skin.

const _SPACING_M: float = 0.40
const _ROW_M: float = 0.42
const _ORTHO_MARGIN_M: float = 0.40
const _LABEL_DROP_M: float = 0.20
# One head's share of the window: the ortho camera fits the columns to its
# width, so this keeps _ROW_M of height per row at that scale.
const _CELL_PX := Vector2i(300, 315)
# Each shot's yaw off facing the camera, degrees.
const _SHOT_YAWS: Array[float] = [30.0, 90.0, 150.0]
const _SHOT_NAMES: Array[String] = ["front", "side", "back"]
const _HELMET_COLOR := Color(0.12, 0.20, 0.45)

var _frames: int = 0
var _shot: int = 0
var _holders: Array[Node3D] = []
var _face: int = GearModelRegistry.FACE_NONE
var _skin: int = SkinToneRegistry.DEFAULT_INDEX
var _hair_color: int = 0
var _hair_rows: Array[int] = HairStyleRegistry.pickable_hair()


func _init() -> void:
	var cols: int = HairStyleRegistry.facial_count()
	var rows: int = _hair_rows.size()
	DisplayServer.window_set_size(Vector2i(_CELL_PX.x * cols, _CELL_PX.y * rows + 40))
	_face = _env_int("MITTS_FACE", GearModelRegistry.FACE_NONE)
	_skin = _env_int("MITTS_SKIN", SkinToneRegistry.DEFAULT_INDEX)
	_hair_color = _env_int("MITTS_HAIR_COLOR", 0)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.52)
	env.environment = e
	root.add_child(env)

	var span: float = _SPACING_M * float(cols - 1)
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

	for row: int in rows:
		for col: int in cols:
			_place(Vector3(-span * 0.5 + _SPACING_M * float(col), -_ROW_M * float(row), 0.0),
					_hair_rows[row], col)
	process_frame.connect(_on_frame)


func _place(at: Vector3, hair: int, facial: int) -> void:
	var holder := Node3D.new()
	holder.position = at
	root.add_child(holder)
	_holders.append(holder)

	# The mesh faces −Z; turned to face the camera, each head is then yawed per
	# shot by its holder.
	var head := Node3D.new()
	head.basis = Basis(Vector3.UP, PI)
	holder.add_child(head)

	var helmet := MeshInstance3D.new()
	helmet.mesh = SkaterMeshBuilder.shared_helmet_assembly()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = _HELMET_COLOR
	shell.roughness = 0.28
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
		_turn(_SHOT_YAWS[_shot])
	elif _frames == 12:
		_save("hair_%s.png" % _SHOT_NAMES[_shot])
		_shot += 1
		if _shot >= _SHOT_YAWS.size():
			quit()
			return
		_frames = 1


func _turn(deg: float) -> void:
	for holder: Node3D in _holders:
		holder.rotation_degrees = Vector3(0.0, deg, 0.0)


func _save(fname: String) -> void:
	var img: Image = root.get_texture().get_image()
	var path: String = "user://" + fname
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))

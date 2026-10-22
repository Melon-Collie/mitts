class_name BodyZonePaint
extends RefCounted

# One material for a whole player body (Shaders/body_zones.gdshaderinc). Each
# zone — a surface of the body as it was authored, numbered in UV2.x by
# BodyZoneMesh — is painted from a StandardMaterial3D RECORD: the material the
# part would have worn on its own surface. A record is a description, never
# drawn; set_zone compiles it into the shader's per-zone arrays. Whoever edits a
# record in place hands it back through set_zone.

const MAX_ZONES: int = 48
const MAX_TEXTURES: int = 8
const GHOST_ALPHA: float = 0.3

const _SHADER: Shader = preload("res://Shaders/body_zones.gdshader")
const _GHOST_SHADER: Shader = preload("res://Shaders/body_zones_ghost.gdshader")
const _TEX_PARAMS: Array[StringName] = [
	&"tex0", &"tex1", &"tex2", &"tex3", &"tex4", &"tex5", &"tex6", &"tex7",
]

var material := ShaderMaterial.new()

var _records: Array[StandardMaterial3D] = []
var _textures: Array[Texture2D] = []
var _albedo := PackedVector4Array()
var _pbr := PackedVector4Array()
var _tex := PackedVector4Array()
var _ghost: bool = false


func _init(count: int) -> void:
	assert(count <= MAX_ZONES, "BodyZonePaint: %d zones, the shader holds %d" % [
			count, MAX_ZONES])
	material.shader = _SHADER
	_records.resize(count)
	_textures.resize(MAX_TEXTURES)
	_albedo.resize(MAX_ZONES)
	_pbr.resize(MAX_ZONES)
	_tex.resize(MAX_ZONES)
	_tex.fill(Vector4(-1.0, 0.0, 0.0, 0.0))
	for z: int in count:
		_records[z] = StandardMaterial3D.new()
		_compile(z)
	_push()


# The record a zone is painted from. Read it freely; after editing it in place,
# hand it back through set_zone.
func zone(z: int) -> StandardMaterial3D:
	return _records[z]


func set_zone(z: int, mat: StandardMaterial3D) -> void:
	_records[z] = mat
	_compile(z)
	_push()


# Records for `count` zones from `first_zone` on, copied from the shared default
# each surface of `mesh` ships with (a fresh material where it has none) — what
# an unpainted body wears.
func seed_from_mesh(mesh: ArrayMesh, first_zone: int) -> void:
	for s: int in mesh.get_surface_count():
		var shared: StandardMaterial3D = mesh.surface_get_material(s) as StandardMaterial3D
		_records[first_zone + s] = shared.duplicate() as StandardMaterial3D if shared != null \
				else StandardMaterial3D.new()
		_compile(first_zone + s)
	_push()


func set_ghost(ghost: bool) -> void:
	if ghost == _ghost:
		return
	_ghost = ghost
	material.shader = _GHOST_SHADER if ghost else _SHADER
	if ghost:
		material.set_shader_parameter(&"ghost_alpha", GHOST_ALPHA)
	_push()
	for slot: int in MAX_TEXTURES:
		material.set_shader_parameter(_TEX_PARAMS[slot], _textures[slot])


func is_ghost() -> bool:
	return _ghost


# The slot a texture is bound to, or -1. Exposed for tests.
func texture_slot(tex: Texture2D) -> int:
	return _textures.find(tex) if tex != null else -1


func _compile(z: int) -> void:
	var mat: StandardMaterial3D = _records[z]
	# As authored (sRGB); the shader converts it the way the renderer converts a
	# source_color albedo. A Vector4, never a Color: the server would convert a
	# Color array itself, and on one renderer only.
	var c: Color = mat.albedo_color
	_albedo[z] = Vector4(c.r, c.g, c.b, c.a)
	var rim: float = mat.rim if mat.rim_enabled else 0.0
	_pbr[z] = Vector4(mat.roughness, mat.metallic, rim, mat.rim_tint)
	var slot: int = _bind(mat.albedo_texture)
	_tex[z] = Vector4(float(slot), mat.uv1_offset.x,
			1.0 if mat.vertex_color_use_as_albedo else 0.0, 0.0)


# The slot `tex` is drawn from, binding it to a free one if it is new. A slot is
# free when no record wears its texture any more.
func _bind(tex: Texture2D) -> int:
	if tex == null:
		return -1
	var slot: int = _textures.find(tex)
	if slot >= 0:
		return slot
	for s: int in MAX_TEXTURES:
		if _textures[s] == null or not _worn(_textures[s]):
			_textures[s] = tex
			material.set_shader_parameter(_TEX_PARAMS[s], tex)
			return s
	push_error("BodyZonePaint: more than %d textures on one body; %s drawn untextured" % [
			MAX_TEXTURES, tex])
	return -1


func _worn(tex: Texture2D) -> bool:
	for mat: StandardMaterial3D in _records:
		if mat != null and mat.albedo_texture == tex:
			return true
	return false


func _push() -> void:
	material.set_shader_parameter(&"zone_albedo", _albedo)
	material.set_shader_parameter(&"zone_pbr", _pbr)
	material.set_shader_parameter(&"zone_tex", _tex)

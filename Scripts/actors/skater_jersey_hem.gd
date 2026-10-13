class_name SkaterJerseyHem
extends RefCounted

# The jersey's lower body, hung loose: the torso rings below PIVOT_Y_M blend onto
# a HEM bone (SkaterBodySkeleton.HEM_BONE, a child of the torso), which
# SkaterArmRig swings on an underdamped lag of the balance lean
# (ClothSwayRules) — a start kicks the hem back, a stop throws it forward, an
# arc swings it out, and each settles with an overshoot.
#
# The one place in the skater rig where a vertex has two bones. Everywhere else a
# pose write is exactly the node transform it replaced; here the blend is the
# point, and it only reaches the jersey, whose swing nothing else agrees with.

# Torso-local heights: where the hem starts to hang free, and the hem itself
# (the torso lathe's last station).
const PIVOT_Y_M: float = -0.06
const HEM_Y_M: float = -0.275

# Share of the balance lean the hem swings by, and the swing's ceiling — small,
# because the pelvis sits a few centimetres inside the hem's front.
var gain: float = 0.35
var cap_rad: float = deg_to_rad(6.0)
var omega: float = TAU * 2.0
var zeta: float = 0.35

var _x: Vector2 = Vector2.ZERO
var _v: Vector2 = Vector2.ZERO

const _REST_EPS: float = 1e-8


# How much of a torso vertex at torso-local `y` rides the hem bone.
static func weight(y: float) -> float:
	var t: float = clampf((PIVOT_Y_M - y) / (PIVOT_Y_M - HEM_Y_M), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# Appends the torso to `target` blended between its own bone and the hem bone by
# height — _append_skinned_surface with two influences instead of one.
static func append_torso(target: ArrayMesh, torso: ArrayMesh, torso_bind: int,
		hem_bind: int) -> void:
	var arrays: Array = torso.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	bones.resize(verts.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(verts.size() * 4)
	for i: int in verts.size():
		var w: float = weight(verts[i].y)
		bones[i * 4] = torso_bind
		bones[i * 4 + 1] = hem_bind
		weights[i * 4] = 1.0 - w
		weights[i * 4 + 1] = w
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# Steps the swing toward the lean `tilt` (world XZ, already in the torso's frame)
# and says whether it is anywhere but at rest.
func advance(dt: float, tilt: Vector2) -> bool:
	var target: Vector2 = ClothSwayRules.rest_swing(tilt, gain, cap_rad)
	if _x.length_squared() < _REST_EPS and _v.length_squared() < _REST_EPS \
			and target.length_squared() < _REST_EPS:
		_x = Vector2.ZERO
		_v = Vector2.ZERO
		return false
	var s: Vector4 = ClothSwayRules.step(_x, _v, target, omega, zeta, dt)
	_x = Vector2(s.x, s.y)
	_v = Vector2(s.z, s.w)
	return true


func swing() -> Vector2:
	return _x


# The hem bone's pose in the torso's frame: turned about the pivot so the hem's
# bottom moves along the swing.
func pose() -> Transform3D:
	var angle: float = _x.length()
	if angle < 1e-6:
		return Transform3D.IDENTITY
	var toward := Vector3(_x.x, 0.0, _x.y) / angle
	var turn := Basis(Vector3.DOWN.cross(toward).normalized(), angle)
	var pivot := Vector3(0.0, PIVOT_Y_M, 0.0)
	return Transform3D(turn, pivot - turn * pivot)

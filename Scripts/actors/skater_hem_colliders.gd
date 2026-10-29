class_name SkaterHemColliders
extends HemColliders

# What the jersey's tail drapes over, in skeleton space, as of the bones' poses
# this frame: each thigh as a capsule from its hip pivot (the dome is the
# capsule's top) down to the leg hem, and the pants as a lathe on the PELVIS
# bone — the rig's own (SkaterMeshBuilder.pelvis_stations), or another body's
# pants given as stations of the same form with its thigh's girth. Read by the hem sims that
# collide on their own (SkaterHemFlaps) and by the comparison's clipping measure;
# the engine-backed sims build node colliders from the same numbers.

const _LEGS: Array[int] = [SkaterMeshBuilder.LegBone.LEG_L, SkaterMeshBuilder.LegBone.LEG_R]
const _THIGHS: Array[int] = [
	SkaterMeshBuilder.LegBone.THIGH_L, SkaterMeshBuilder.LegBone.THIGH_R]

var thigh_top: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var thigh_bottom: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var thigh_radius: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var pelvis := Transform3D.IDENTITY
var _pelvis_inv := Transform3D.IDENTITY
# The pants' lathe, (y, radius, rear sway) per station top down, waist-space,
# scaled by PELVIS_XZ_SCALE; and the thigh capsule's radius.
var _stations: PackedFloat64Array
var _thigh_radius_m: float


func _init(stations := PackedFloat64Array(),
		thigh_radius_m: float = SkaterMeshBuilder.THIGH_CAPSULE_RADIUS_M) -> void:
	_stations = stations if not stations.is_empty() else SkaterMeshBuilder.pelvis_stations()
	_thigh_radius_m = thigh_radius_m


func update(skeleton: Skeleton3D) -> void:
	for i: int in 2:
		var leg: Transform3D = skeleton.get_bone_global_pose(
				SkaterBodySkeleton.LEG_BONE_OFFSET + _LEGS[i])
		var thigh: Basis = skeleton.get_bone_global_pose(
				SkaterBodySkeleton.LEG_BONE_OFFSET + _THIGHS[i]).basis
		thigh_top[i] = leg.origin
		thigh_bottom[i] = leg * Vector3(0.0, -SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M, 0.0)
		thigh_radius[i] = _thigh_radius_m * thigh.x.length()
	pelvis = skeleton.get_bone_global_pose(SkaterMeshBuilder.UpperBone.PELVIS)
	_pelvis_inv = pelvis.affine_inverse()


func configure_native(native: RefCounted) -> void:
	var legs: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	native.call("collide_skater", PackedInt32Array([SkaterMeshBuilder.UpperBone.PELVIS,
			legs + _LEGS[0], legs + _LEGS[1], legs + _THIGHS[0], legs + _THIGHS[1]]),
			_stations,
			PackedFloat64Array([SkaterMeshBuilder.THIGH_CAPSULE_LENGTH_M, _thigh_radius_m,
					SkaterMeshBuilder.PELVIS_XZ_SCALE.x, SkaterMeshBuilder.PELVIS_XZ_SCALE.y]))


func push_out(p: Vector3, margin: float) -> Vector3:
	for i: int in 2:
		var c: Vector3 = _closest_on_thigh(i, p)
		var d: Vector3 = p - c
		var reach: float = thigh_radius[i] + margin
		if d.length_squared() < reach * reach:
			var dist: float = d.length()
			p = c + (d / dist if dist > 1e-6 else Vector3.FORWARD) * reach
	var q: Vector3 = _pelvis_inv * p
	var ring: Vector2 = _ring(q.y)
	if ring.x > 0.0:
		var xs: float = SkaterMeshBuilder.PELVIS_XZ_SCALE.x
		var zs: float = SkaterMeshBuilder.PELVIS_XZ_SCALE.y
		var r: float = ring.x + margin
		var e: float = pow(q.x / (r * xs), 2.0) + pow((q.z - ring.y) / (r * zs), 2.0)
		if e < 1.0 and e > 1e-8:
			var f: float = 1.0 / sqrt(e)
			p = pelvis * Vector3(q.x * f, q.y, ring.y + (q.z - ring.y) * f)
	return p


# How far `p` is inside the deepest collider holding it, metres; 0 outside all.
func depth(p: Vector3) -> float:
	var deepest: float = 0.0
	for i: int in 2:
		deepest = maxf(deepest, thigh_radius[i] - p.distance_to(_closest_on_thigh(i, p)))
	var q: Vector3 = _pelvis_inv * p
	var ring: Vector2 = _ring(q.y)
	if ring.x > 0.0:
		var e: float = pow(q.x / (ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.x), 2.0) \
				+ pow((q.z - ring.y) / (ring.x * SkaterMeshBuilder.PELVIS_XZ_SCALE.y), 2.0)
		if e < 1.0:
			deepest = maxf(deepest, (1.0 - sqrt(e)) * ring.x * pelvis.basis.x.length())
	return deepest


# The pants at waist-space height `y`: (radius, rear sway), radius < 0 outside
# their span.
func _ring(y: float) -> Vector2:
	for i: int in range(0, _stations.size() - 3, 3):
		var hi_y: float = _stations[i]
		var lo_y: float = _stations[i + 3]
		if y <= hi_y and y >= lo_y:
			var t: float = (hi_y - y) / maxf(hi_y - lo_y, 1e-6)
			return Vector2(lerpf(_stations[i + 1], _stations[i + 4], t),
					lerpf(_stations[i + 2], _stations[i + 5], t))
	return Vector2(-1.0, 0.0)


func _closest_on_thigh(i: int, p: Vector3) -> Vector3:
	var a: Vector3 = thigh_top[i]
	var ab: Vector3 = thigh_bottom[i] - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
	return a + ab * t

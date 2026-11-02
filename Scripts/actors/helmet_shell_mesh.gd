class_name HelmetShellMesh
extends RefCounted

# The helmet's shell as the body wears it (SkaterRigidParts): the plain shell
# (SkaterMeshBuilder) shaped into a hockey helmet, a lip round its rim, and a
# UV the number decal (HelmetDecal) is painted through. Every shape term only
# raises the plain shell, so the hair and face gear fitted under it still fit.
# Helmet-local: the face toward −Z, azimuth θ = atan2(x, z), 0 the back.

const LON: int = 24
const LAT: int = 8

# The shell drawn toward a rounded box (a superellipsoid, which only raises a
# sphere): its plan squared by the first power and its upper half's profile by
# the second, so the brow and the sides stand up and the top flattens.
const _PLAN_POWER: float = 2.4
const _PROFILE_POWER: float = 2.6
# A ridge down the crown's centre line and a rib either side of it (m proud;
# half widths, and the ribs' place, as fractions of the radius off the centre
# plane), running out down the back toward the nape and at the front above the
# number on the brow; the step across the back where the rear shell laps the
# front one; and the whole shell drawn out front to back, as a helmet is longer
# than wide.
const _RIDGE_M: float = 0.010
const _RIDGE_HALF_WIDTH: float = 0.22
const _RIB_M: float = 0.007
const _RIB_ACROSS: float = 0.55
const _RIB_HALF_WIDTH: float = 0.08
const _CREST_BACK_FADE := Vector2(-0.35, 0.1)
const _CREST_FRONT_FADE := Vector2(0.62, 0.85)
const _STEP_M: float = 0.008
const _STEP_HEIGHT: float = 0.05
const _STEP_HALF_HEIGHT: float = 0.09
const _LENGTH: float = 1.07

# The lip round the rim, as (arc up the shell its top leaves from, arc up the
# shell its outer face's top is level with, how far it stands out, how far its
# outer face drops below the rim), m: across the brow a brim the visor tucks
# under, standing straight out; round the rest a rolled edge that gives the
# shell its thickness, standing out along the shell, so it does not flare.
const _BRIM_LIP := Vector4(0.020, 0.011, 0.014, 0.004)
const _EDGE_LIP := Vector4(0.008, 0.005, 0.0045, 0.001)
# Radians off dead front: the brim full inside the first, gone past the second.
const _BRIM_ARC := Vector2(0.55, 1.2)

# U runs once round the shell with θ (the front at 0.5, the seam down the back);
# V runs down from UV_TOP_Y_M, a unit every UV_SPAN_Y_M.
const UV_TOP_Y_M: float = 0.21
const UV_SPAN_Y_M: float = 0.36

static var _arrays: Array = []


# The shell's arrays: VERTEX, NORMAL (each face's own) and TEX_UV, unindexed.
static func shared() -> Array:
	if _arrays.is_empty():
		_arrays = _build()
	return _arrays


# Where the plain shell's point `p` lands on this one.
static func shape(p: Vector3) -> Vector3:
	var d: Vector3 = p.normalized()
	var plan: float = pow(pow(absf(d.x), _PLAN_POWER) + pow(absf(d.z), _PLAN_POWER),
			1.0 / _PLAN_POWER)
	var profile: float = _PROFILE_POWER if d.y > 0.0 else 2.0
	var squared: Vector3 = p / pow(pow(plan, profile) + pow(absf(d.y), profile), 1.0 / profile)
	var front: float = smoothstep(-0.2, 0.2, -d.z)
	var fade: float = lerpf(smoothstep(_CREST_BACK_FADE.x, _CREST_BACK_FADE.y, d.y),
			smoothstep(_CREST_FRONT_FADE.x, _CREST_FRONT_FADE.y, d.y), front)
	var raise: float = (_RIDGE_M * exp(-(d.x / _RIDGE_HALF_WIDTH) ** 2) \
			+ _RIB_M * exp(-((absf(d.x) - _RIB_ACROSS) / _RIB_HALF_WIDTH) ** 2)) * fade
	raise += _STEP_M * smoothstep(0.2, 0.5, d.z) \
			* exp(-((d.y - _STEP_HEIGHT) / _STEP_HALF_HEIGHT) ** 2)
	var out: Vector3 = squared + d * raise
	out.z *= _LENGTH
	return out


# The shell's metres per unit of U and of V at azimuth θ, height `y`: what a
# decal drawn there is stretched by.
static func metres_per_uv(theta: float, y: float) -> Vector2:
	var v: float = acos(clampf(y / _radius(), -1.0, 1.0)) / PI
	var e: float = 0.002
	var across: float = (_shell(theta + e, v) - _shell(theta - e, v)).length() / (2.0 * e)
	var up: Vector3 = _shell(theta, v - e)
	var down: Vector3 = _shell(theta, v + e)
	return Vector2(across * TAU, (up - down).length() / absf(up.y - down.y) * UV_SPAN_Y_M)


static func uv_of(theta: float, y: float) -> Vector2:
	return Vector2(fposmod(theta, TAU) / TAU, (UV_TOP_Y_M - y) / UV_SPAN_Y_M)


static func _build() -> Array:
	var plain: Array = SkaterMeshBuilder.shared_helmet_shell(LON, LAT).surface_get_arrays(0)
	var src: PackedVector3Array = plain[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array()
	if plain[Mesh.ARRAY_INDEX] != null and not (plain[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		for i: int in plain[Mesh.ARRAY_INDEX] as PackedInt32Array:
			verts.append(shape(src[i]))
	else:
		for p: Vector3 in src:
			verts.append(shape(p))
	_append_lip(verts)
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for t: int in range(0, verts.size(), 3):
		var a: Vector3 = verts[t]
		var n: Vector3 = (verts[t + 2] - a).cross(verts[t + 1] - a).normalized()
		normals.append_array([n, n, n])
		uvs.append_array(_face_uvs(a, verts[t + 1], verts[t + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays


# The lip as a strip of four rings round the rim, from where its top leaves the
# shell, out and down its outer face, and back in under it to the rim — wound as
# the shell's own bands are, top ring first.
static func _append_lip(verts: PackedVector3Array) -> void:
	var rings: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(),
			PackedVector3Array(), PackedVector3Array()]
	for k: int in LON + 1:
		var theta: float = TAU * float(k) / float(LON)
		var cut: float = SkaterMeshBuilder.helmet_cut_v(theta)
		var brim: float = _brim_share(theta)
		var lip: Vector4 = _EDGE_LIP.lerp(_BRIM_LIP, brim)
		var rim: Vector3 = _shell(theta, cut)
		var out: Vector3 = rim.normalized().lerp(Vector3(rim.x, 0.0, rim.z).normalized(),
				brim).normalized() * lip.z
		rings[0].append(lip_top(theta))
		rings[1].append(_shell(theta, cut - lip.y / (PI * _radius())) + out)
		rings[2].append(rim + out + Vector3.DOWN * lip.w)
		rings[3].append(rim)
	for j: int in rings.size() - 1:
		for k: int in LON:
			var a: Vector3 = rings[j][k]
			var b: Vector3 = rings[j][k + 1]
			var c: Vector3 = rings[j + 1][k + 1]
			var d: Vector3 = rings[j + 1][k]
			verts.append_array([a, b, d, b, c, d])


# Where the lip's top leaves the shell at azimuth θ: the lowest the shell is
# clear to paint on.
static func lip_top(theta: float) -> Vector3:
	var lip: Vector4 = _EDGE_LIP.lerp(_BRIM_LIP, _brim_share(theta))
	return _shell(theta, SkaterMeshBuilder.helmet_cut_v(theta) - lip.x / (PI * _radius()))


static func _brim_share(theta: float) -> float:
	return 1.0 - smoothstep(_BRIM_ARC.x, _BRIM_ARC.y, absf(wrapf(theta - PI, -PI, PI)))


# A face's three UVs, unwrapped across the seam so none spans the texture; a
# point on the axis (the crown) takes the others' U.
static func _face_uvs(a: Vector3, b: Vector3, c: Vector3) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	var on_axis: Array[bool] = []
	var first_u: float = NAN
	var u_sum: float = 0.0
	var u_count: int = 0
	for p: Vector3 in [a, b, c]:
		var uv: Vector2 = uv_of(atan2(p.x, p.z), p.y)
		var axis: bool = Vector2(p.x, p.z).length() < 1e-4
		if not axis:
			if is_nan(first_u):
				first_u = uv.x
			else:
				uv.x += roundf(first_u - uv.x)
			u_sum += uv.x
			u_count += 1
		on_axis.append(axis)
		uvs.append(uv)
	for i: int in 3:
		if on_axis[i]:
			uvs[i].x = u_sum / float(maxi(u_count, 1))
	return uvs


static func _shell(theta: float, v: float) -> Vector3:
	return shape(SkaterMeshBuilder.helmet_shell_point(theta, v))


static func _radius() -> float:
	return SkaterMeshBuilder.helmet_shell_point(0.0, 0.0).y

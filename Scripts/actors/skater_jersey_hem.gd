class_name SkaterJerseyHem
extends RefCounted

# The jersey's tail: the torso rings below PIVOT_Y_M hang loose, and partly off
# the hips rather than the chest. The hips' share rides TAIL
# (SkaterBodySkeleton.TAIL_BONE: the torso's own placement, hung from the WAIST,
# so it takes the hips' fold and twist and not the chest's). By BELT_Y_M the
# FRONT is the hips' entirely — the thighs and the pants push it, so a deep fold
# bunches it over them instead of driving the hem into them — while the back
# keeps CARRY_BACK of it and mostly rides up with the chest, as a bent-over
# sweater does over the seat. Both shares swing: the chest's on HEM (under the
# torso), the hips' on TAIL_HEM (under TAIL), which SkaterArmRig pose alike on
# an underdamped lag of the balance lean (ClothSwayRules) — a start kicks the
# hem back, a stop throws it forward, an arc swings it out, and each settles
# with an overshoot.
#
# A tuck (GearModelRegistry.TUCK_*) pulls the tail in under the pants'
# waistband wherever it is tucked — a front corner, or all the way round — and
# weights it to TAIL itself, where the belt holds it still; the ring above it bunches
# out over the belt. In between, the tail is lifted part of the way, which is
# the diagonal drape from a tucked corner round to the loose back.
#
# The one place in the skater rig where a vertex has more than one bone.
# Everywhere else a pose write is exactly the node transform it replaced; here
# the blend is the point, and it only reaches the jersey, whose drape nothing
# else agrees with.

# Torso-local heights: where the tail starts to leave the chest, the ring that
# bunches over a tuck, the waistband line the tuck goes in at (just under the
# pants' top, SkaterMeshBuilder._PELVIS_PROFILE[0]), and the hem itself (the
# torso lathe's last station). The lathe has a ring at each of the last three.
const PIVOT_Y_M: float = -0.06
const BLOUSE_Y_M: float = -0.125
const BELT_Y_M: float = -0.15
const HEM_Y_M: float = -0.350

# Share of the tail the hips carry at the back; it rises to all of it at the
# front.
const CARRY_BACK: float = 0.3

# Profile radii (before the lathe's x/z scale) of a tucked ring: the belt ring
# just inside the pants' rim, the tail below it well inside the pants, and what
# a full tuck's fabric adds to the ring that bunches over the belt.
const BELT_IN_RADIUS_M: float = 0.176
const TUCKED_RADIUS_M: float = 0.165
const BLOUSE_M: float = 0.012
# Share of the tail's length below the belt that a tuck keeps — the rest is
# taken up inside the pants — and where the tucked tail centres: on the pants'
# own rear sway there, which is less than the hanging jersey's.
const TUCKED_LENGTH_SHARE: float = 0.5
const TUCKED_REAR_SWAY_M: float = 0.010

# A corner tuck, by azimuth on the lathe (0 at the +Z back, toward +X, the
# wearer's right): centred on the front of that hip, fully in within INNER of
# it, loose past OUTER.
const CORNER_AZIMUTH_RAD: float = deg_to_rad(144.0)
const CORNER_INNER_RAD: float = deg_to_rad(20.0)
const CORNER_OUTER_RAD: float = deg_to_rad(70.0)

# Share of the balance lean the hem swings by, and the swing's ceiling — what
# the room between the hem and the seat it hangs over allows.
var gain: float = 0.35
var cap_rad: float = deg_to_rad(8.0)
var omega: float = TAU * 2.0
var zeta: float = 0.35

var _x: Vector2 = Vector2.ZERO
var _v: Vector2 = Vector2.ZERO

const _REST_EPS: float = 1e-8


# How the torso surface carries the tail below the belt, by HemSimMode: swung
# whole on the hem bones, ridden by per-column bones, or cut away for a soft
# body to stand in for (collapsed onto the belt ring, so its faces have no area).
const TAIL_SWUNG: int = 0
const TAIL_COLUMNS: int = 1
const TAIL_CUT: int = 2


static func tail_kind(hem_sim: int) -> int:
	if HemSimMode.uses_columns(hem_sim):
		return TAIL_COLUMNS
	return TAIL_CUT if hem_sim == HemSimMode.SOFT_BODY else TAIL_SWUNG


# How much of a torso vertex at rest height `y` hangs below the chest.
static func hang(y: float) -> float:
	return _smooth((PIVOT_Y_M - y) / (PIVOT_Y_M - BELT_Y_M))


# How much of what hangs at `azimuth` the hips carry when it is loose.
static func carry(azimuth: float) -> float:
	return lerpf(CARRY_BACK, 1.0, (1.0 - cos(azimuth)) * 0.5)


# How tucked the jersey is at `azimuth` (the lathe's angle, see
# CORNER_AZIMUTH_RAD) under a GearModelRegistry TUCK_* option.
static func tuck_share(tuck: int, azimuth: float) -> float:
	match tuck:
		GearModelRegistry.TUCK_FULL:
			return 1.0
		GearModelRegistry.TUCK_RIGHT:
			return _corner(azimuth, CORNER_AZIMUTH_RAD)
		GearModelRegistry.TUCK_LEFT:
			return _corner(azimuth, -CORNER_AZIMUTH_RAD)
	return 0.0


static func _corner(azimuth: float, centre: float) -> float:
	var off: float = absf(angle_difference(azimuth, centre))
	return _smooth((CORNER_OUTER_RAD - off) / (CORNER_OUTER_RAD - CORNER_INNER_RAD))


static func _smooth(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


# A torso ring at rest height `y`, tucked: each point is moved about the ring's
# own centre (`z_off` behind the axis) to the radius and height the tuck gives it
# at its azimuth. `ring` is the lathe's — sides + 1 points from `phase`, the
# last repeating the first — at profile radius `radius` scaled by `xs` / `zs`.
static func tuck_ring(ring: PackedVector3Array, y: float, radius: float, z_off: float,
		tuck: int, phase: float, xs: float, zs: float) -> PackedVector3Array:
	if tuck == GearModelRegistry.TUCK_NONE or y > BLOUSE_Y_M + 1e-5:
		return ring
	var sides: int = ring.size() - 1
	var out := PackedVector3Array(ring)
	for k: int in ring.size():
		var theta: float = TAU * float(k) / float(sides) + phase
		var t: float = tuck_share(tuck, theta)
		var r: float = radius
		var ty: float = y
		var tz: float = z_off
		if y > BELT_Y_M + 1e-5:
			r += BLOUSE_M * t
		else:
			var inside: float = BELT_IN_RADIUS_M if y > BELT_Y_M - 1e-5 else TUCKED_RADIUS_M
			r = lerpf(radius, inside, t)
			ty = lerpf(y, BELT_Y_M + (y - BELT_Y_M) * TUCKED_LENGTH_SHARE, t)
			tz = lerpf(z_off, TUCKED_REAR_SWAY_M, t)
		out[k] = Vector3(sin(theta) * r * xs, ty, tz + cos(theta) * r * zs)
	return out


# Appends the torso to `target`, posed as `posed` (the rest torso or a tucked
# copy of it, vertex for vertex), weighted from the rest torso `rest`: rigid on
# its own bone above the pivot; below it, swinging on HEM as far as the chest
# carries it and on TAIL_HEM as far as the hips do (all of it where it is
# tucked), but for the tucked share, held still on TAIL.
# Azimuths come off the UVs, which no tuck moves: a side vertex's U is its
# angle, a bottom-cap vertex's offset from the cap's UV centre is.
#
# A `tail` other than TAIL_SWUNG re-carries everything from the belt ring down:
# TAIL_COLUMNS puts each vertex rigidly on its facet column's bone — the upper
# segment above `bend_y`, the lower from it down (`column_bind_base` + 2·column
# + segment) — and TAIL_CUT collapses it onto `belt_ring`'s point for its column.
# Of the `sides` columns, the bottom cap's centre belongs to none and keeps its
# weights.
static func append_torso(target: ArrayMesh, rest: ArrayMesh, posed: ArrayMesh, tuck: int,
		phase: float, torso_bind: int, hem_bind: int, tail_bind: int,
		tail_hem_bind: int, tail: int = TAIL_SWUNG, sides: int = 10,
		column_bind_base: int = 0, belt_ring: PackedVector3Array = PackedVector3Array(),
		bend_y: float = 0.0) -> void:
	var rest_arrays: Array = rest.surface_get_arrays(0)
	var verts: PackedVector3Array = rest_arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = rest_arrays[Mesh.ARRAY_TEX_UV]
	var mean_tuck: float = 0.0
	for k: int in 36:
		mean_tuck += tuck_share(tuck, TAU * float(k) / 36.0) / 36.0
	var bones := PackedInt32Array()
	bones.resize(verts.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(verts.size() * 4)
	for i: int in verts.size():
		var uv: Vector2 = uvs[i]
		var side: bool = uv.y <= UniformPaint.CYLINDER_SIDE_V_FRACTION + 1e-4
		var h: float = hang(verts[i].y) if side or uv.x > 0.5 else 0.0
		# The bottom cap's centre has no azimuth: it takes the ring's means.
		var c: float = (1.0 + CARRY_BACK) * 0.5
		var t: float = mean_tuck
		var off: Vector2 = uv - _BOTTOM_CAP_UV
		if side or off.length() > 1e-4:
			var azimuth: float = (TAU * uv.x if side else atan2(off.x, off.y)) + phase
			c = carry(azimuth)
			t = tuck_share(tuck, azimuth)
		t *= clampf((BLOUSE_Y_M - verts[i].y) / (BLOUSE_Y_M - BELT_Y_M), 0.0, 1.0)
		var hips: float = h * lerpf(c, 1.0, t)
		bones[i * 4] = torso_bind
		bones[i * 4 + 1] = hem_bind
		bones[i * 4 + 2] = tail_bind
		bones[i * 4 + 3] = tail_hem_bind
		weights[i * 4] = 1.0 - h
		weights[i * 4 + 1] = h - hips
		weights[i * 4 + 2] = hips * t
		weights[i * 4 + 3] = hips * (1.0 - t)
	var arrays: Array = posed.surface_get_arrays(0)
	if tail != TAIL_SWUNG:
		var posed_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var belt_centre := Vector3.ZERO
		for k: int in sides:
			belt_centre += belt_ring[k] / float(sides) if tail == TAIL_CUT else Vector3.ZERO
		for i: int in verts.size():
			if verts[i].y > BELT_Y_M + 1e-5:
				continue
			var column: int = _column(uvs[i], sides)
			if tail == TAIL_CUT:
				posed_verts[i] = belt_centre if column < 0 else belt_ring[column]
				continue
			if column < 0:
				continue
			var lower: int = 1 if verts[i].y <= bend_y + 1e-5 else 0
			for j: int in 4:
				bones[i * 4 + j] = column_bind_base + column * 2 + lower if j == 0 else 0
				weights[i * 4 + j] = 1.0 if j == 0 else 0.0
		arrays[Mesh.ARRAY_VERTEX] = posed_verts
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# The facet column a torso vertex sits on, off its UV (the side's U, or a bottom
# cap vertex's angle about the cap's UV centre); -1 for the top cap and the
# bottom cap's centre.
static func _column(uv: Vector2, sides: int) -> int:
	if uv.y <= UniformPaint.CYLINDER_SIDE_V_FRACTION + 1e-4:
		return posmod(roundi(uv.x * sides), sides)
	var off: Vector2 = uv - _BOTTOM_CAP_UV
	if uv.x < 0.5 or off.length() < 1e-4:
		return -1
	return posmod(roundi(atan2(off.x, off.y) / TAU * sides), sides)


# The lathe's bottom-cap UV centre (SkaterMeshBuilder._build_lathe).
const _BOTTOM_CAP_UV := Vector2(0.75, 0.75)


# Steps the swing toward the lean `tilt` (world XZ, already in the trunk's frame)
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


# Both hem bones' pose, in their parent's frame (the torso's or the tail's,
# which agree at rest): turned about the pivot so the hem's bottom moves along
# the swing.
func pose() -> Transform3D:
	var angle: float = _x.length()
	if angle < 1e-6:
		return Transform3D.IDENTITY
	var toward := Vector3(_x.x, 0.0, _x.y) / angle
	var turn := Basis(Vector3.DOWN.cross(toward).normalized(), angle)
	var pivot := Vector3(0.0, PIVOT_Y_M, 0.0)
	return Transform3D(turn, pivot - turn * pivot)

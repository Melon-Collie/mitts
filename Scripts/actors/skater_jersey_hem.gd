class_name SkaterJerseyHem
extends RefCounted

# The jersey's tail, as the torso surface carries it. The torso rings below
# PIVOT_Y_M hang partly off the hips rather than the chest: the hips' share
# rides TAIL (SkaterBodySkeleton.TAIL_BONE: the torso's own placement, hung from
# the WAIST, so it takes the hips' fold and twist and not the chest's). By
# BELT_Y_M the FRONT is the hips' entirely — the thighs and the pants push it —
# while the back keeps CARRY_BACK of it and mostly rides up with the chest, as a
# bent-over sweater does over the seat. From the belt ring down the tail hangs
# free, and SkaterHemFlaps drapes it: each vertex rides its facet column's bone.
#
# A tuck (GearModelRegistry.TUCK_*) pulls the tail in under the pants'
# waistband wherever it is tucked — a corner, or all the way round — and the
# flaps hold it there. There the pants' padded top stands up proud of the
# jersey (pad_ring), the ring at its height goes in under it, and the ring
# above that bunches out over it. Beside a tucked corner the tail stays outside
# the pants, lifted toward the belt: the diagonal hem from the corner round to
# the loose front and back. A column is in or out, never between — between is
# inside the pants' wall.
#
# The one place in the skater rig where a vertex has more than one bone.
# Everywhere else a pose write is exactly the node transform it replaced; here
# the blend is the point, and it only reaches the jersey, whose drape nothing
# else agrees with.

# Torso-local heights: where the tail starts to leave the chest, the ring that
# bunches over a tuck's pad, the ring that goes in under the pad, the waistband
# line the tuck goes in at (just under the pants' waistband,
# SkaterMeshBuilder._PELVIS_PROFILE[1]), and the hem itself (the torso lathe's
# last station). The lathe has a ring at each of the last four.
const PIVOT_Y_M: float = -0.06
const BUNCH_Y_M: float = -0.07
const PAD_Y_M: float = -0.125
const BELT_Y_M: float = -0.15
const HEM_Y_M: float = -0.350

# Share of the tail the hips carry at the back; it rises to all of it at the
# front.
const CARRY_BACK: float = 0.3

# Profile radii (before the lathe's x/z scale) of a tucked ring: the ring under
# the pad, the belt ring just inside the pants' rim, the tail below it well
# inside the pants, and what a full tuck's fabric adds to the ring that bunches
# over the pad.
const UNDER_PAD_RADIUS_M: float = 0.192
const BELT_IN_RADIUS_M: float = 0.176
const TUCKED_RADIUS_M: float = 0.165
const BLOUSE_M: float = 0.012
# How far a tuck's pad stands the pants' lip up, the share of that the
# waistband under it rises, and how far the waistband flares out — the lip
# stays in against the jersey, so the pad's top rolls in to meet it rather than
# standing open off it.
const PAD_RISE_M: float = 0.035
const PAD_BULGE_SHARE: float = 0.5
const PAD_FLARE_M: float = 0.022
# Share of the tail's length below the belt that a tuck keeps — the rest is
# taken up inside the pants — and where the tucked tail centres: on the pants'
# own rear sway there, which is less than the hanging jersey's.
const TUCKED_LENGTH_SHARE: float = 0.5
const TUCKED_REAR_SWAY_M: float = 0.010
# Share of the tail's length below the belt that a fully lifted column (one
# just short of tucked in) is taken up by.
const LIFT_MAX: float = 0.8

# A corner tuck, by azimuth on the lathe (0 at the +Z back, toward +X, the
# wearer's right): centred just in front of that hip's side, tucked in within
# INNER of it, lifted less and less out to OUTER, loose past it.
const CORNER_AZIMUTH_RAD: float = deg_to_rad(104.0)
const CORNER_INNER_RAD: float = deg_to_rad(30.0)
const CORNER_OUTER_RAD: float = deg_to_rad(85.0)

# The lathe's bottom-cap UV centre (SkaterMeshBuilder._build_lathe).
const _BOTTOM_CAP_UV := Vector2(0.75, 0.75)


# How much of a torso vertex at rest height `y` hangs below the chest.
static func hang(y: float) -> float:
	return _smooth((PIVOT_Y_M - y) / (PIVOT_Y_M - BELT_Y_M))


# How much of what hangs at `azimuth` the hips carry when it is loose.
static func carry(azimuth: float) -> float:
	return lerpf(CARRY_BACK, 1.0, (1.0 - cos(azimuth)) * 0.5)


# How tucked the jersey is at `azimuth` (the lathe's angle, see
# CORNER_AZIMUTH_RAD) under a GearModelRegistry TUCK_* option: 1 tucked in,
# short of it how far the hem is lifted.
static func tuck_share(tuck: int, azimuth: float) -> float:
	match tuck:
		GearModelRegistry.TUCK_FULL:
			return 1.0
		GearModelRegistry.TUCK_RIGHT:
			return _corner(azimuth, CORNER_AZIMUTH_RAD)
		GearModelRegistry.TUCK_LEFT:
			return _corner(azimuth, -CORNER_AZIMUTH_RAD)
	return 0.0


# 1 where the jersey at `azimuth` is tucked in under the waistband, else 0.
static func tucked_in(tuck: int, azimuth: float) -> float:
	return 1.0 if tuck_share(tuck, azimuth) >= 1.0 else 0.0


static func _corner(azimuth: float, centre: float) -> float:
	var off: float = absf(angle_difference(azimuth, centre))
	return _smooth((CORNER_OUTER_RAD - off) / (CORNER_OUTER_RAD - CORNER_INNER_RAD))


static func _smooth(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


# A torso ring at rest height `y`, tucked: each point is moved about the ring's
# own centre (`z_off` behind the axis) to the radius and height the tuck gives it
# at its azimuth. `ring` is the lathe's — sides + 1 points from `phase`, the
# last repeating the first — at profile radius `radius` scaled by `xs` / `zs`;
# `blouse` is what the ring bunching over the pad stands out by.
static func tuck_ring(ring: PackedVector3Array, y: float, radius: float, z_off: float,
		tuck: int, phase: float, xs: float, zs: float,
		blouse: float = BLOUSE_M) -> PackedVector3Array:
	if tuck == GearModelRegistry.TUCK_NONE or y > BUNCH_Y_M + 1e-5:
		return ring
	var sides: int = ring.size() - 1
	var out := PackedVector3Array(ring)
	for k: int in ring.size():
		var theta: float = TAU * float(k) / float(sides) + phase
		var r: float = radius
		var ty: float = y
		var tz: float = z_off
		if tucked_in(tuck, theta) == 0.0:
			if y < BELT_Y_M - 1e-5:
				ty = BELT_Y_M + (y - BELT_Y_M) * (1.0 - LIFT_MAX * tuck_share(tuck, theta))
		elif y > PAD_Y_M + 1e-5:
			r += blouse
		elif y > BELT_Y_M + 1e-5:
			r = UNDER_PAD_RADIUS_M
			tz = TUCKED_REAR_SWAY_M
		else:
			r = BELT_IN_RADIUS_M if y > BELT_Y_M - 1e-5 else TUCKED_RADIUS_M
			ty = BELT_Y_M + (y - BELT_Y_M) * TUCKED_LENGTH_SHARE
			tz = TUCKED_REAR_SWAY_M
		out[k] = Vector3(sin(theta) * r * xs, ty, tz + cos(theta) * r * zs)
	return out


# A pants ring at its top (waist-space height `y`, profile radius `radius`,
# `sides` + 1 points from azimuth 0, behind the axis by `z_off`) as `tuck`
# stands the pad up: raised by `rise` and flared by `flare` where the jersey is
# tucked in on both sides of the point (the torso's facet columns sit half a
# facet either side of it), so the pad never stands up under a jersey still
# hanging outside.
static func pad_ring(ring: PackedVector3Array, y: float, radius: float, z_off: float,
		tuck: int, xs: float, zs: float, rise: float, flare: float) -> PackedVector3Array:
	if tuck == GearModelRegistry.TUCK_NONE:
		return ring
	var sides: int = ring.size() - 1
	var half: float = PI / float(sides)
	var out := PackedVector3Array(ring)
	for k: int in ring.size():
		var theta: float = TAU * float(k) / float(sides)
		var t: float = minf(tucked_in(tuck, theta - half), tucked_in(tuck, theta + half))
		var r: float = radius + flare * t
		out[k] = Vector3(sin(theta) * r * xs, y + rise * t, z_off + cos(theta) * r * zs)
	return out


# Appends the torso to `target`, posed as `posed` (the rest torso or a tucked
# copy of it, vertex for vertex), weighted from the rest torso `rest`: rigid on
# its own bone above the pivot, then onto TAIL as far as the hips carry it (all
# of it where it is tucked). From the belt ring down, each vertex rides its
# facet column's bone (`column_bind_base` + 2·column + segment) — the upper
# segment above `bend_y`, the lower from it down. The bottom cap's centre
# belongs to no column of the `sides` and keeps the blend.
# Azimuths come off the UVs, which no tuck moves: a side vertex's U is its
# angle, a bottom-cap vertex's offset from the cap's UV centre is.
static func append_torso(target: ArrayMesh, rest: ArrayMesh, posed: ArrayMesh, tuck: int,
		phase: float, torso_bind: int, tail_bind: int, sides: int, column_bind_base: int,
		bend_y: float) -> void:
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
		var column: int = _column(uv, sides)
		if column >= 0 and verts[i].y <= BELT_Y_M + 1e-5:
			var lower: int = 1 if verts[i].y <= bend_y + 1e-5 else 0
			bones[i * 4] = column_bind_base + column * 2 + lower
			weights[i * 4] = 1.0
			continue
		var side: bool = uv.y <= UniformPaint.CYLINDER_SIDE_V_FRACTION + 1e-4
		var h: float = hang(verts[i].y) if side or uv.x > 0.5 else 0.0
		# The bottom cap's centre has no azimuth: it takes the ring's means.
		var c: float = (1.0 + CARRY_BACK) * 0.5
		var t: float = mean_tuck
		if column >= 0:
			var azimuth: float = TAU * float(column) / float(sides) + phase
			c = carry(azimuth)
			t = tuck_share(tuck, azimuth)
		t *= clampf((BUNCH_Y_M - verts[i].y) / (BUNCH_Y_M - PAD_Y_M), 0.0, 1.0)
		var hips: float = h * lerpf(c, 1.0, t)
		bones[i * 4] = torso_bind
		bones[i * 4 + 1] = tail_bind
		weights[i * 4] = 1.0 - hips
		weights[i * 4 + 1] = hips
	var arrays: Array = posed.surface_get_arrays(0)
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

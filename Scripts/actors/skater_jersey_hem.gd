class_name SkaterJerseyHem
extends RefCounted

# The jersey's tail, as the torso carries it (SkaterConnectedMesh). The torso
# rings below PIVOT_Y_M hang partly off the hips rather than the chest: the hips'
# share rides TAIL (SkaterBodySkeleton.TAIL_BONE: the torso's own placement, hung
# from the WAIST, so it takes the hips' fold and twist and not the chest's). By
# BELT_Y_M the FRONT is the hips' entirely — the thighs and the pants push it —
# while the back keeps CARRY_BACK of it and mostly rides up with the chest, as a
# bent-over sweater does over the seat. From the belt ring down the tail hangs
# free, and SkaterHemFlaps drapes it: each vertex rides its column's bone.
#
# A tuck (GearModelRegistry.TUCK_*) pulls the tail in under the pants'
# waistband wherever it is tucked — a corner, or all the way round — and the
# flaps hold it there. There the pants' padded top stands proud of the jersey
# going in behind it (SkaterConnectedPants), and the cloth above sags out over
# it. Beside a tucked corner the tail stays outside the pants, lifted toward
# the belt: the diagonal hem from the corner round to the loose front and back.

# Torso-local heights: where the tail starts to leave the chest, where a tuck's
# sag starts, the ring that sags widest just over the pants' rim, the waistband
# line the tuck goes in at (under the rim, SkaterConnectedPants), and the hem
# itself (the torso's last station). The torso has a ring at each of the last
# four.
const PIVOT_Y_M: float = -0.06
const BUNCH_Y_M: float = -0.07
const PAD_Y_M: float = -0.125
const BELT_Y_M: float = -0.15
const HEM_Y_M: float = -0.350

# Share of the tail the hips carry at the back; it rises to all of it at the
# front.
const CARRY_BACK: float = 0.3
# Where the jersey is tucked in, the waistband holds it: the hips carry all of it
# from where the sag starts down, the chest taking it back by this
# height (the waist). The trunk folds about the hip joints, well under the
# waistband, so cloth above a rim it does not ride swings through the rim — at
# the centre's address over the dot, by the most.
const TUCK_PIVOT_Y_M: float = 0.0

# Profile radii (before the lathe's x/z scale) of a tucked ring: the belt ring
# just inside the pants' rim, and the tail below it well inside the pants.
const BELT_IN_RADIUS_M: float = 0.198
const TUCKED_RADIUS_M: float = 0.165
# Share of the tail's length below the belt that a tuck keeps — the rest is
# taken up inside the pants — and where the tucked tail centres: on the pants'
# own rear sway there, which is less than the hanging jersey's.
const TUCKED_LENGTH_SHARE: float = 0.5
const TUCKED_REAR_SWAY_M: float = 0.010

# A corner tuck, by azimuth on the lathe (0 at the +Z back, toward +X, the
# wearer's right): a front corner pushed in at the front of that hip, tucked in
# within INNER of it, and the hem either side lifted toward it, out to FRONT
# round the belly and REAR round the side, loose past them. The back hangs
# loose: the corner pulls the front panel it belongs to, and the side seam
# takes up most of the pull before it reaches the back.
const CORNER_AZIMUTH_RAD: float = deg_to_rad(125.0)
const CORNER_INNER_RAD: float = deg_to_rad(18.0)
const CORNER_FRONT_RAD: float = deg_to_rad(70.0)
const CORNER_REAR_RAD: float = deg_to_rad(55.0)


# How much of a torso vertex at rest height `y` hangs below the chest.
static func hang(y: float) -> float:
	return _smooth((PIVOT_Y_M - y) / (PIVOT_Y_M - BELT_Y_M))


# How much of a torso vertex at rest height `y` the hips carry where the jersey
# is tucked in.
static func tucked_hang(y: float) -> float:
	return _smooth((TUCK_PIVOT_Y_M - y) / (TUCK_PIVOT_Y_M - BUNCH_Y_M))


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


# How far a tucked ring at rest height `y` stands out of the full blouse: none
# at BUNCH_Y_M, all of it at PAD_Y_M, the ring just over the pants' rim, so the
# cloth sags over the rim as a bag does rather than standing out as a shelf.
static func _sag(y: float) -> float:
	var t: float = clampf((BUNCH_Y_M - y) / (BUNCH_Y_M - PAD_Y_M), 0.0, 1.0)
	return t * t


# The hem pulled taut from the corner runs straight up to it, so the lift is
# linear in angle there, and eases onto the loose hem at the far end.
static func _corner(azimuth: float, centre: float) -> float:
	var toward_front: float = angle_difference(centre, azimuth) * signf(centre)
	var outer: float = CORNER_FRONT_RAD if toward_front > 0.0 else CORNER_REAR_RAD
	var t: float = clampf((outer - absf(toward_front)) / (outer - CORNER_INNER_RAD), 0.0, 1.0)
	return t * t * (2.0 - t)


static func _smooth(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


# A torso ring at rest height `y`, tucked: each point tucked in is moved about
# the ring's own centre (`z_off` behind the axis) to the radius and height the
# tuck gives it; the rest are left (a lifted tail is SkaterConnectedMesh's). `ring` is the lathe's — sides + 1 points from `phase`, the
# last repeating the first — at profile radius `radius` scaled by `xs` / `zs`;
# `blouse` is what the ring sagging over the rim stands out by.
static func tuck_ring(ring: PackedVector3Array, y: float, radius: float, z_off: float,
		tuck: int, phase: float, xs: float, zs: float, blouse: float) -> PackedVector3Array:
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
			continue
		if y > BELT_Y_M + 1e-5:
			var sag: float = _sag(y)
			r += blouse * sag
			tz = lerpf(z_off, TUCKED_REAR_SWAY_M, sag)
		else:
			r = BELT_IN_RADIUS_M if y > BELT_Y_M - 1e-5 else TUCKED_RADIUS_M
			ty = BELT_Y_M + (y - BELT_Y_M) * TUCKED_LENGTH_SHARE
			tz = TUCKED_REAR_SWAY_M
		out[k] = Vector3(sin(theta) * r * xs, ty, tz + cos(theta) * r * zs)
	return out

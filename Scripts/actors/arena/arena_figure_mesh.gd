class_name ArenaFigureMesh

# The human figure this arena is populated with — its geometry, its
# anthropometry, and the arithmetic that stands one up.
#
# One file because the crowd and the rinkside staff are the same population in
# two postures, and the bridge between them (`SITTING_HEIGHT_FRACTION`) only
# works if both read it from the same place. `ArenaCrowd` takes the seated
# spectator at the bottom of this file, `ArenaRinkside` the box figure, sitting
# or standing; neither depends on the other.

# The staff's figure: two stacked boxes. Its height is also the crowd figure's
# (FIGURE_HEIGHT), so both populations share one anthropometry.
const BODY_SIZE: Vector3 = Vector3(0.28, 0.45, 0.28)
const HEAD_SIZE: Vector3 = Vector3(0.22, 0.22, 0.22)
# Tiny lift to keep the body bottom face off the tread without a visible gap.
# Without it the two co-planar surfaces z-fight; without keeping the bottom
# face at all, back-row spectators look hollow when the camera ends up below
# their row (upper-bowl rows reach ~6 m, well above typical camera height).
const BODY_Y_LIFT: float = 0.002
# Neck gap between the body box's top face and the head box's bottom.
const NECK_GAP: float = 0.02

# ── Stature ──────────────────────────────────────────────────────────────────
# One unscaled figure stands 0.692 m from the tread to the crown of its head.
# That is not a person: these spectators sit with their base ON the tread rather
# than on a raised pan, so their whole height IS sitting height, and a real adult
# sitting height runs about 0.79 m to 0.97 m.
#
# Every stature below is divided by this to get a scale factor, so the figures
# are sized by anthropometry in one place instead of by eye in several.
const FIGURE_HEIGHT: float = BODY_Y_LIFT + BODY_SIZE.y + NECK_GAP + HEAD_SIZE.y
# Roughly 5th-percentile female to 95th-percentile male. Rolled per spectator, so
# a row is a mix of statures rather than a line of identical boxes — which reads
# as a crowd of people at a glance, where a uniform one reads as a texture.
const SEATED_STATURE_MIN: float = 0.80
const SEATED_STATURE_MAX: float = 0.96
const CROWD_SCALE_MAX: float = SEATED_STATURE_MAX / FIGURE_HEIGHT
# The rinkside staff are the same population on their feet — the same percentiles
# read off the standing column of the same tables.
const STANDING_STATURE_MIN: float = 1.52
const STANDING_STATURE_MAX: float = 1.88
# Sitting height is about 52% of stature in adults, and that ratio is the entire
# bridge between the two populations. Standing widens nobody — it unfolds legs the
# seated figure has no geometry for — so a staffer is sized ACROSS by the seated
# scale of a person their height (`stature * this / FIGURE_HEIGHT`) and lifted by
# the remaining 48%, which is their hip height. Scaling the whole figure uniformly
# to standing stature instead is what makes a coach read as a giant beside the
# crowd: at 1.75 m the body box comes out 0.71 m across under a half-metre head,
# both about double a spectator's, because a box that is a seated torso ends up
# standing in for torso AND legs.
const SITTING_HEIGHT_FRACTION: float = 0.52

# Skin tones + hat colors for the head box. Independent of body color (no team
# correlation) so the bowl reads as a sea of people, not a wall of identical
# avatars — and shared with the rinkside staff, who are the same population.
const HEAD_PALETTE: Array[Color] = [
	Color(0.94, 0.82, 0.70),  # light skin
	Color(0.85, 0.69, 0.55),  # medium-light skin
	Color(0.72, 0.55, 0.42),  # medium skin
	Color(0.55, 0.40, 0.30),  # tan
	Color(0.40, 0.28, 0.22),  # dark skin
	Color(0.12, 0.10, 0.10),  # black hair / dark cap
	Color(0.32, 0.22, 0.16),  # brown hair
	Color(0.78, 0.74, 0.68),  # grey hair / pale cap
]
# The leading HEAD_PALETTE entries that are bare skin; the rest are hair or a cap.
const BARE_HEAD_TONES: int = 5


# Body box, origin at the figure's base. Lifted 2 mm off the floor so the bottom
# face doesn't z-fight with it.
static func body_mesh() -> ArrayMesh:
	return _box_mesh(Vector3(0.0, BODY_Y_LIFT + BODY_SIZE.y * 0.5, 0.0), BODY_SIZE)


# Head box, positioned above the body so it lines up when applied with the same
# transform as the body. Lifted with the body.
static func head_mesh() -> ArrayMesh:
	return _box_mesh(Vector3(0.0, head_center_y(), 0.0), HEAD_SIZE)


static func head_center_y() -> float:
	return BODY_Y_LIFT + BODY_SIZE.y + NECK_GAP + HEAD_SIZE.y * 0.5


static func _box_mesh(center: Vector3, size: Vector3) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	ArenaMeshEmit.box(st, center, size)
	st.generate_normals()
	return st.commit()


# Uniform scale for a seated figure of `stature`. The head rides the body on one
# transform, so heads vary a little with stature — not how people are built, but
# invisible at this level of stylization.
static func seated_scale(stature: float) -> float:
	return stature / FIGURE_HEIGHT


# What the crowd's scale would be for a spectator of this standing stature.
static func girth_scale(stature: float) -> float:
	return stature * SITTING_HEIGHT_FRACTION / FIGURE_HEIGHT


# Everything standing adds over sitting: the hips a seated figure folds away.
static func hip_height(stature: float) -> float:
	return stature * (1.0 - SITTING_HEIGHT_FRACTION)


# The body box is the only part of a figure that changes with posture: standing,
# it stands in for legs as well as torso, so it is stretched in Y by `lift` until
# its top lands at the neck. Across, it stays at `girth` either way — shoulders
# are shoulders, sitting or standing — and a seated figure (lift 0) comes out as
# exactly the spectator this geometry was drawn for.
static func body_transform(post: Vector3, yaw: float, girth: float,
		lift: float) -> Transform3D:
	var y_scale: float = girth + lift / (BODY_Y_LIFT + BODY_SIZE.y)
	return Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3(girth, y_scale, girth)), post)


# The head is that same figure's head untouched, carried up by whatever the body
# box grew — so the crown lands at full stature and the neck gap survives.
static func head_transform(post: Vector3, yaw: float, girth: float,
		lift: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * girth),
			post + Vector3.UP * lift)


# ── The seated spectator ─────────────────────────────────────────────────────
# Flat-shaded and chamfered like the skater: a torso and a head lofted through
# octagons, arms resting hands-on-lap, and thighs out over the tread's edge. No
# shins: on 0.6 m treads they would hang into the riser or the seat back of the
# row below, which hides that space anyway. Built in the unscaled frame the
# stature scale multiplies (crown at FIGURE_HEIGHT, local -Z toward the rink),
# with every part tagged in UV.x for crowd.gdshader, which raises the arms.

const PART_BODY: float = 0.0
const PART_UPPER_ARM: float = 1.0
const PART_FOREARM: float = 2.0
const PART_LEG: float = 3.0

# Right-hand joints; the left mirror them in X. The shoulder and elbow are also
# the pivots crowd.gdshader raises the arm about.
const SHOULDER: Vector3 = Vector3(0.150, 0.415, 0.005)
const ELBOW: Vector3 = Vector3(0.160, 0.225, 0.020)
const HAND: Vector3 = Vector3(0.088, 0.170, -0.150)
const HIP: Vector3 = Vector3(0.058, 0.085, 0.030)
# Far enough forward to clear the tread's edge on the smallest roll, short of the
# row below's seat back on the largest (test_arena_figures.gd).
const KNEE: Vector3 = Vector3(0.064, 0.090, -0.180)
const UPPER_ARM_THICKNESS: float = 0.056
const FOREARM_THICKNESS: float = 0.050
const THIGH_THICKNESS: float = 0.088

# Torso and head stations, bottom up: [y, z centre, half width, half depth].
# The torso's back stays inside the seat back's clearance at the largest roll.
const _TORSO: Array[Vector4] = [
	Vector4(0.040, 0.025, 0.112, 0.100),
	Vector4(0.340, 0.012, 0.132, 0.112),
	Vector4(0.425, 0.010, 0.118, 0.092),
	Vector4(BODY_Y_LIFT + BODY_SIZE.y, 0.006, 0.062, 0.056),
]
const _HEAD: Array[Vector4] = [
	Vector4(BODY_Y_LIFT + BODY_SIZE.y + NECK_GAP * 0.8, -0.004, 0.072, 0.078),
	Vector4(0.640, -0.004, 0.096, 0.102),
	Vector4(FIGURE_HEIGHT, -0.004, 0.062, 0.066),
]
# Share of each half-extent an octagon's corners cut away.
const _CHAMFER: float = 0.38

static var _pose_bounds: AABB = AABB()


# Torso, arms and thighs: everything that takes the shirt's colour.
static func crowd_body_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	# Sits on the seat pan, so no bottom; the top shows from above.
	ArenaMeshEmit.loft(st, _rings(_TORSO), PART_BODY, false, true)
	for side: float in [1.0, -1.0]:
		var m := Vector3(side, 1.0, 1.0)
		# Each limb's root end is buried in what it hangs from.
		ArenaMeshEmit.beam(st, SHOULDER * m, ELBOW * m, UPPER_ARM_THICKNESS,
				UPPER_ARM_THICKNESS, Vector3.RIGHT, PART_UPPER_ARM, false, true)
		ArenaMeshEmit.beam(st, ELBOW * m, HAND * m, FOREARM_THICKNESS,
				FOREARM_THICKNESS, Vector3.UP, PART_FOREARM, false, true)
		ArenaMeshEmit.beam(st, HIP * m, KNEE * m, THIGH_THICKNESS,
				THIGH_THICKNESS, Vector3.RIGHT, PART_LEG, false, true)
	if surface_material != null:
		st.set_material(surface_material)
	return st.commit()


static func crowd_head_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	ArenaMeshEmit.loft(st, _rings(_HEAD), PART_BODY, true, true)
	if surface_material != null:
		st.set_material(surface_material)
	return st.commit()


# The rotation about X at the elbow that lines the forearm up with the upper
# arm: how far crowd.gdshader unbends it as the arm goes up.
static func elbow_unbend() -> float:
	var upper: Vector3 = ELBOW - SHOULDER
	var fore: Vector3 = HAND - ELBOW
	return wrapf(atan2(upper.z, upper.y) - atan2(fore.z, fore.y), -PI, PI)


# Every place the figure can reach, in its unscaled frame, before sway and hop.
# The arms only turn about the shoulder and the elbow, so wherever they are
# posed, an arm vertex stays within its rest distance of the shoulder — through
# the elbow, for the forearm — and a sphere that wide holds every raise.
static func crowd_pose_bounds() -> AABB:
	if _pose_bounds.has_volume():
		return _pose_bounds
	var bounds: AABB = crowd_head_mesh().get_aabb()
	var arrays: Array = crowd_body_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var reach: float = 0.0
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		var m := Vector3(signf(v.x), 1.0, 1.0)
		match uvs[i].x:
			PART_UPPER_ARM:
				reach = maxf(reach, v.distance_to(SHOULDER * m))
			PART_FOREARM:
				reach = maxf(reach, SHOULDER.distance_to(ELBOW) + v.distance_to(ELBOW * m))
			_:
				bounds = bounds.expand(v)
	for side: float in [1.0, -1.0]:
		var shoulder: Vector3 = SHOULDER * Vector3(side, 1.0, 1.0)
		bounds = bounds.merge(AABB(shoulder - Vector3.ONE * reach, Vector3.ONE * reach * 2.0))
	_pose_bounds = bounds
	return bounds


static func _rings(stations: Array[Vector4]) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	var k: float = 1.0 - _CHAMFER
	for s: Vector4 in stations:
		var y: float = s.x
		var z: float = s.y
		var w: float = s.z
		var d: float = s.w
		rings.append(PackedVector3Array([
			Vector3(w, y, z - d * k), Vector3(w, y, z + d * k),
			Vector3(w * k, y, z + d), Vector3(-w * k, y, z + d),
			Vector3(-w, y, z + d * k), Vector3(-w, y, z - d * k),
			Vector3(-w * k, y, z - d), Vector3(w * k, y, z - d),
		]))
	return rings

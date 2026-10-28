class_name ArenaFigureMesh

# The human figure this arena is populated with — its geometry, its
# anthropometry, and the arithmetic that stands one up.
#
# One file because the crowd and the rinkside staff are the same population in
# two postures, and the bridge between them (`SITTING_HEIGHT_FRACTION`) only
# works if both read it from the same place. `ArenaCrowd` takes the seated
# figure, and the cheaper one for far rows; `ArenaRinkside` takes the seated
# one and the standing one. Neither depends on the other.
#
# Flat-shaded and chamfered like the skater: a torso and a head lofted through
# octagons, arms bent with the hands in front, and legs. Built in the unscaled
# frame the stature scale multiplies (crown at FIGURE_HEIGHT, local -Z facing
# out), with every part tagged in UV.x for crowd.gdshader, which paints them and
# raises the crowd's arms.

const SHADER_PATH: String = "res://Shaders/crowd.gdshader"

const PART_BODY: float = 0.0
const PART_UPPER_ARM: float = 1.0
const PART_FOREARM: float = 2.0
const PART_LEG: float = 3.0
const PART_SHOE: float = 4.0
const PART_HEAD: float = 5.0

# Where the torso ends and, a neck's gap above it, the head begins.
const BODY_TOP_Y: float = 0.452
const NECK_GAP: float = 0.02
const HEAD_HEIGHT: float = 0.22

# ── Stature ──────────────────────────────────────────────────────────────────
# One unscaled figure stands 0.692 m from the tread to the crown of its head.
# That is not a person: these spectators sit with their base ON the tread rather
# than on a raised pan, so their whole height IS sitting height, and a real adult
# sitting height runs about 0.79 m to 0.97 m.
#
# Every stature below is divided by this to get a scale factor, so the figures
# are sized by anthropometry in one place instead of by eye in several.
const FIGURE_HEIGHT: float = BODY_TOP_Y + NECK_GAP + HEAD_HEIGHT
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
# bridge between the two populations. Standing widens nobody — it unfolds the
# legs — so a staffer is sized ACROSS by the seated scale of a person their
# height (`stature * this / FIGURE_HEIGHT`) and lifted by the remaining 48%,
# which is their hip height. Scaling the whole figure uniformly to standing
# stature instead makes a coach a giant beside the crowd, about double a
# spectator's width.
const SITTING_HEIGHT_FRACTION: float = 0.52
# How far the standing figure's upper body sits above the seated one's, in the
# unscaled frame. Hip height and girth both scale with stature, so this is the
# same for every staffer: `girth_scale(s) * STANDING_LIFT == hip_height(s)`.
const STANDING_LIFT: float = FIGURE_HEIGHT * (1.0 - SITTING_HEIGHT_FRACTION) \
		/ SITTING_HEIGHT_FRACTION

# Skin tones + hat colors for the head. Independent of body color (no team
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


# A figure's body at `post`, scaled by `girth` alone: a standing body carries
# its own legs (standing_body_mesh), so nothing stretches.
static func figure_transform(post: Vector3, yaw: float, girth: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * girth), post)


# The head is the seated figure's, carried up by `lift` (hip_height for a
# standing staffer), so the crown lands at full stature.
static func head_transform(post: Vector3, yaw: float, girth: float,
		lift: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * girth),
			post + Vector3.UP * lift)


# A material for figures, with the figure's own pivots and palette written in.
# Its `excitement` stays 0 until someone writes it, so figures on a material
# nobody excites — and with no sway or hop rolled in INSTANCE_CUSTOM — hold still.
static func new_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("excitement", 0.0)
	mat.set_shader_parameter("body_top_y", BODY_TOP_Y)
	mat.set_shader_parameter("shoulder", SHOULDER)
	mat.set_shader_parameter("elbow", ELBOW)
	mat.set_shader_parameter("elbow_unbend", elbow_unbend())
	var skin: PackedVector3Array = PackedVector3Array()
	for i: int in BARE_HEAD_TONES:
		var c: Color = HEAD_PALETTE[i]
		skin.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("skin_tones", skin)
	return mat


# A head colour from HEAD_PALETTE, alpha 0 on bare skin: crowd.gdshader paints
# hair over those, and skin under everything else.
static func roll_head(rng: RandomNumberGenerator) -> Color:
	var tone: int = rng.randi() % HEAD_PALETTE.size()
	var head: Color = HEAD_PALETTE[tone]
	if tone < BARE_HEAD_TONES:
		head.a = 0.0
	return head


# ── Geometry ─────────────────────────────────────────────────────────────────

# Right-hand joints of the seated figure; the left mirror them in X. The
# shoulder and elbow are also the pivots crowd.gdshader raises the arm about.
const SHOULDER: Vector3 = Vector3(0.150, 0.415, 0.005)
const ELBOW: Vector3 = Vector3(0.160, 0.225, 0.020)
const HAND: Vector3 = Vector3(0.088, 0.170, -0.150)
const HIP: Vector3 = Vector3(0.058, 0.085, 0.030)
# Far enough forward to clear the tread's edge on the smallest roll, short of the
# row below's seat back on the largest (test_arena_figures.gd). The seated
# figure has no shins: on 0.6 m treads they would hang into the riser or that
# seat back, which hides the space anyway.
const KNEE: Vector3 = Vector3(0.064, 0.090, -0.180)
# A standing figure's leg, from the floor up: ankle, then the knee midway to
# the hip it shares with the seated figure.
const ANKLE: Vector3 = Vector3(0.066, 0.060, 0.020)
const SHOE_LENGTH: float = 0.135
const SHOE_HEIGHT: float = 0.050
const UPPER_ARM_THICKNESS: float = 0.056
const FOREARM_THICKNESS: float = 0.050
const THIGH_THICKNESS: float = 0.088
const SHIN_THICKNESS: float = 0.070

# Torso and head stations, bottom up: [y, z centre, half width, half depth].
# The torso's back stays inside the seat back's clearance at the largest roll.
const _TORSO: Array[Vector4] = [
	Vector4(0.040, 0.025, 0.112, 0.100),
	Vector4(0.340, 0.012, 0.132, 0.112),
	Vector4(0.425, 0.010, 0.118, 0.092),
	Vector4(BODY_TOP_Y, 0.006, 0.062, 0.056),
]
const _HEAD: Array[Vector4] = [
	Vector4(BODY_TOP_Y + NECK_GAP * 0.8, -0.004, 0.072, 0.078),
	Vector4(0.640, -0.004, 0.096, 0.102),
	Vector4(FIGURE_HEIGHT, -0.004, 0.062, 0.066),
]
# The far figure's, through hexagons: the same silhouette from across the bowl,
# with half the stations.
const _FAR_TORSO: Array[Vector4] = [
	Vector4(0.040, 0.020, 0.115, 0.104),
	Vector4(0.425, 0.010, 0.128, 0.100),
]
const _FAR_HEAD: Array[Vector4] = [
	Vector4(BODY_TOP_Y + NECK_GAP * 0.8, -0.004, 0.078, 0.084),
	Vector4(FIGURE_HEIGHT, -0.004, 0.090, 0.096),
]
# Share of each half-extent an octagon's corners cut away.
const _CHAMFER: float = 0.38
# What a right-hand joint is multiplied by for each side.
const _SIDES: Array[Vector3] = [Vector3(1.0, 1.0, 1.0), Vector3(-1.0, 1.0, 1.0)]

static var _pose_bounds: AABB = AABB()


# Seated: torso, arms and thighs, everything that takes the shirt's colour.
# `surface_material` is embedded; a caller with a material_override passes none.
static func seated_body_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := _begin()
	_upper_body(st, Vector3.ZERO)
	for m: Vector3 in _SIDES:
		ArenaMeshEmit.beam(st, HIP * m, KNEE * m, THIGH_THICKNESS,
				THIGH_THICKNESS, Vector3.RIGHT, PART_LEG, false, true)
	return _commit(st, surface_material)


# Standing: the seated upper body raised by STANDING_LIFT onto straight legs
# and shoes, so it scales by girth alone (figure_transform).
static func standing_body_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := _begin()
	var lift := Vector3.UP * STANDING_LIFT
	_upper_body(st, lift)
	for m: Vector3 in _SIDES:
		var hip: Vector3 = HIP * m + lift
		var ankle: Vector3 = ANKLE * m
		var knee: Vector3 = (hip + ankle) * 0.5
		ArenaMeshEmit.beam(st, hip, knee, THIGH_THICKNESS, THIGH_THICKNESS,
				Vector3.RIGHT, PART_LEG, false, true)
		ArenaMeshEmit.beam(st, knee, ankle, SHIN_THICKNESS, SHIN_THICKNESS,
				Vector3.RIGHT, PART_LEG, false, false)
		var heel := Vector3(ankle.x, SHOE_HEIGHT * 0.5, ankle.z + SHIN_THICKNESS * 0.5)
		ArenaMeshEmit.beam(st, heel, heel + Vector3.FORWARD * SHOE_LENGTH,
				SHIN_THICKNESS, SHOE_HEIGHT, Vector3.RIGHT, PART_SHOE, true, true)
	return _commit(st, surface_material)


static func head_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := _begin()
	ArenaMeshEmit.loft(st, _octagons(_HEAD), PART_HEAD, true, true)
	return _commit(st, surface_material)


# The seated figure for the far rows, at under half the triangles: hexagons,
# a straight arm from shoulder to hand (raised whole about the shoulder), and
# one block for the lap.
static func far_body_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := _begin()
	ArenaMeshEmit.loft(st, _hexagons(_FAR_TORSO), PART_BODY, false, true)
	for m: Vector3 in _SIDES:
		ArenaMeshEmit.beam(st, SHOULDER * m, HAND * m, UPPER_ARM_THICKNESS,
				UPPER_ARM_THICKNESS, Vector3.UP, PART_UPPER_ARM, false, true)
	ArenaMeshEmit.beam(st, Vector3(0.0, HIP.y, HIP.z), Vector3(0.0, KNEE.y, KNEE.z),
			(KNEE.x + THIGH_THICKNESS * 0.5) * 2.0, THIGH_THICKNESS, Vector3.RIGHT,
			PART_LEG, false, true)
	return _commit(st, surface_material)


static func far_head_mesh(surface_material: Material = null) -> ArrayMesh:
	var st := _begin()
	ArenaMeshEmit.loft(st, _hexagons(_FAR_HEAD), PART_HEAD, true, true)
	return _commit(st, surface_material)


# The rotation about X at the elbow that lines the forearm up with the upper
# arm: how far crowd.gdshader unbends it as the arm goes up.
static func elbow_unbend() -> float:
	var upper: Vector3 = ELBOW - SHOULDER
	var fore: Vector3 = HAND - ELBOW
	return wrapf(atan2(upper.z, upper.y) - atan2(fore.z, fore.y), -PI, PI)


# Every place a crowd figure (seated or far) can reach, in the unscaled frame,
# before sway and hop. The arms only turn about the shoulder and the elbow, so
# wherever they are posed, an arm vertex stays within its rest distance of the
# shoulder — through the elbow, for the forearm — and a sphere that wide holds
# every raise.
static func crowd_pose_bounds() -> AABB:
	if _pose_bounds.has_volume():
		return _pose_bounds
	var bounds: AABB = head_mesh().get_aabb().merge(far_head_mesh().get_aabb())
	var reach: float = 0.0
	for mesh: ArrayMesh in [seated_body_mesh(), far_body_mesh()]:
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i: int in verts.size():
			var v: Vector3 = verts[i]
			var m := Vector3(signf(v.x), 1.0, 1.0)
			match uvs[i].x:
				PART_UPPER_ARM:
					reach = maxf(reach, v.distance_to(SHOULDER * m))
				PART_FOREARM:
					reach = maxf(reach,
							SHOULDER.distance_to(ELBOW) + v.distance_to(ELBOW * m))
				_:
					bounds = bounds.expand(v)
	for m: Vector3 in _SIDES:
		var shoulder: Vector3 = SHOULDER * m
		bounds = bounds.merge(AABB(shoulder - Vector3.ONE * reach, Vector3.ONE * reach * 2.0))
	_pose_bounds = bounds
	return bounds


# Torso and both arms, raised by `lift`. Each limb's root end is buried in what
# it hangs from, so only its far end is capped; the torso sits on its seat or
# hips, so only its top is.
static func _upper_body(st: SurfaceTool, lift: Vector3) -> void:
	ArenaMeshEmit.loft(st, _octagons(_TORSO, lift.y), PART_BODY, false, true)
	for m: Vector3 in _SIDES:
		ArenaMeshEmit.beam(st, SHOULDER * m + lift, ELBOW * m + lift,
				UPPER_ARM_THICKNESS, UPPER_ARM_THICKNESS, Vector3.RIGHT,
				PART_UPPER_ARM, false, true)
		ArenaMeshEmit.beam(st, ELBOW * m + lift, HAND * m + lift, FOREARM_THICKNESS,
				FOREARM_THICKNESS, Vector3.UP, PART_FOREARM, false, true)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PrimitiveType.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool, surface_material: Material) -> ArrayMesh:
	if surface_material != null:
		st.set_material(surface_material)
	return st.commit()


static func _octagons(stations: Array[Vector4], lift: float = 0.0) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	var k: float = 1.0 - _CHAMFER
	for s: Vector4 in stations:
		var y: float = s.x + lift
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


static func _hexagons(stations: Array[Vector4]) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	for s: Vector4 in stations:
		var y: float = s.x
		var z: float = s.y
		var w: float = s.z
		var d: float = s.w
		rings.append(PackedVector3Array([
			Vector3(w, y, z), Vector3(w * 0.5, y, z + d), Vector3(-w * 0.5, y, z + d),
			Vector3(-w, y, z), Vector3(-w * 0.5, y, z - d), Vector3(w * 0.5, y, z - d),
		]))
	return rings

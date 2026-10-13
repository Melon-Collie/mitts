class_name GoalieMeshBuilder
extends SkaterMeshBuilder

# Low-poly faceted replacements for the goalie's primitive part meshes:
# chest-protector body, mask, leg pads with roll ridges, catch glove (rim +
# pocket + detail ball), blocker board and hand, plus the unit tube the hip
# connectors stretch. Extends SkaterMeshBuilder for its emission toolbox
# (lathe / ball / loop sweep / caps) and the shared mesh cache — same flat-
# shaded style, so both "players" read as one art set.
#
# Visual-only: every part stays inside the envelope of the primitive it
# replaces. The sibling COLLIDERS in Goalie.tscn are untouched — saves,
# rebounds, and skater bumps are byte-identical.
#
# The body must keep three goalie_jersey.gdshader contracts: a flat +Z back
# region (normal.z > 0.9 gates the nameplate projection), a flat top face
# (normal.y > 0.9 gates the yoke), and the box's full ±0.36 object-Y span
# (stripes map over it). The sweep below tapers WIDTH only — depth stays
# constant so every back facet keeps its exact +Z normal.

# Body cross-section (replaces the 0.52 × 0.72 × 0.28 BoxMesh): flat back,
# chamfered front. The block is torso THROUGH hips — standing, its bottom
# (body y 1.22 − 0.36 = 0.86) sits exactly at pad-top level — so the one
# solid is styled as BOTH garments: chest, a waist pinch, then a hip flare
# back out to the full box for the pants bulk. The jersey shader paints the
# band below the hip line as the kit's pants color (goalie_jersey.gdshader
# pants_start), splitting the garments by color where the silhouette splits
# them by shape. Stations are (y, width multiplier); depth is fixed.
const _BODY_HALF_W: float = 0.26
const _BODY_HALF_D: float = 0.14
const _BODY_STATIONS: Array[Vector2] = [
	Vector2(0.36, 1.0),     # shoulder line — chest-protector caps carry the widest read
	Vector2(0.18, 0.98),    # chest
	Vector2(-0.02, 0.93),   # waist pinch
	Vector2(-0.16, 1.0),    # hip crest — pants bulk back out to the yoke's width
	Vector2(-0.36, 0.97),
]

# Leg pad (replaces the 0.28 × 0.84 × 0.2 BoxMesh), sculpted inside that box: a
# tapered thigh rise, the knee stack standing proud of the face, a shin face
# creased into three vertical panels, the boot at the bottom, an outer roll
# down both edges, and the leg channel recessed into the back. Symmetric in X,
# since both pads share one mesh. The front is −Z, toward the shooter in every
# stance (the butterfly rolls the pad about Z).
const _PAD_HALF_W: float = 0.14
const _PAD_HALF_D: float = 0.10
# Stations top→bottom: (y, width multiplier, front reach, back reach), reaches
# in metres from the pad's centre plane. The knee stack alone reaches the full
# front depth, so it is the part of the face a shot reads first.
const _PAD_STATIONS: Array[Vector4] = [
	Vector4(0.42, 0.80, 0.055, 0.070),    # thigh rise top
	Vector4(0.30, 0.90, 0.075, 0.085),
	Vector4(0.25, 0.88, 0.066, 0.090),    # break above the knee
	Vector4(0.235, 0.97, 0.098, 0.095),   # knee stack
	Vector4(0.06, 1.00, 0.100, 0.100),
	Vector4(0.045, 0.92, 0.068, 0.100),   # break below the knee
	Vector4(0.03, 1.00, 0.086, 0.100),    # shin
	Vector4(-0.28, 1.00, 0.086, 0.100),
	Vector4(-0.295, 0.93, 0.070, 0.095),  # boot break
	Vector4(-0.31, 0.96, 0.092, 0.092),   # boot
	Vector4(-0.42, 0.86, 0.078, 0.070),   # toe
]
# Cross-section, as fractions of the station's half-width: the creases between
# the shin face's panels, the edge where the face turns into the outer roll,
# and the leg channel's half-width.
const _PAD_PANEL_X: float = 0.30
const _PAD_FACE_X: float = 0.72
const _PAD_CHANNEL_X: float = 0.45
const _PAD_CHANNEL_DEPTH: float = 0.022
# Creases are COLOR as well as shape, like the mask's cage: a groove's facets
# bake a dark vertex tint under the pad paint, because a 1 cm step in a
# flat-shaded solid barely changes its shading from the top-down camera.
const _PAD_BREAK_YS: Array[float] = [0.25, 0.045, -0.295]
const _PAD_BREAK_HALF: float = 0.012
const _PAD_CREASE_TINT := Color(0.62, 0.62, 0.64)
const _PAD_CHANNEL_TINT := Color(0.45, 0.45, 0.47)

# Mask, shaped as a goalie's rather than as the head sphere it replaces: taller
# than it is wide, with a domed cranium, a brow standing proud over the face
# opening, cheeks that narrow toward a chin running well below where a skater's
# helmet stops and jutting forward, and the back tucking in to the neck. From
# the side that is the mask's S-profile; from the front, a long shield. It
# overruns the 0.26 m head collider by the chin, which the save geometry
# does not need to follow.
# Front/back asymmetric, so it's a loop sweep rather than a lathe. The goalie
# faces −Z, so "front" is the −Z half; the head node's own rotation carries
# the mask's facing. Stations are (y, lateral rx, back +Z reach, front −Z
# reach).
const _MASK_STATIONS: Array[Vector4] = [
	Vector4(0.145, 0.040, 0.050, 0.040),    # crown
	Vector4(0.125, 0.085, 0.100, 0.090),
	Vector4(0.085, 0.110, 0.130, 0.125),    # cranium
	Vector4(0.035, 0.118, 0.140, 0.142),    # brow, proud over the opening
	Vector4(0.000, 0.120, 0.140, 0.128),    # eye line, set back under the brow
	Vector4(-0.050, 0.114, 0.124, 0.134),   # cheeks
	Vector4(-0.100, 0.098, 0.094, 0.138),   # jaw: the back tucks, the chin holds
	Vector4(-0.145, 0.072, 0.050, 0.132),   # chin
	Vector4(-0.178, 0.040, 0.020, 0.112),   # chin point
]
const _MASK_SEGS: int = 12

# The face opening is COLOR: front facets between brow and chin bake a dark
# vertex tint under the kit's helmet paint, and the cage's bars (a separate,
# fixed-colour mesh) stand in front of it. Whole facets tint at once —
# centroid tests, so the opening's edge lands on facet edges and stays crisp
# under flat shading.
const _CAGE_TINT := Color(0.22, 0.22, 0.24)
# Opening = facets whose centroid lies within this half-angle of the −Z front
# axis (the θ grid is station-independent, so the same facet columns tint at
# every height — 36° keeps the middle two of the six front columns). Vertical
# span: under the brow to above the chin.
const _CAGE_HALF_ANGLE_DEG: float = 36.0
const _CAGE_TOP_Y: float = 0.030
const _CAGE_BOT_Y: float = -0.125
# The cage: bars standing proud of the opening, light against its dark, so the
# face reads as a goalie's cage from the broadcast angles. Vertical bars at
# these x, horizontal bars at these y, all at _CAGE_PROUD in front of the
# mask's front reach at their height. Mask-local metres.
const _CAGE_BAR_XS: Array[float] = [-0.042, -0.014, 0.014, 0.042]
const _CAGE_BAR_YS: Array[float] = [0.018, -0.030, -0.078]
const _CAGE_HALF_X: float = 0.066
const _CAGE_PROUD: float = 0.012
const _CAGE_BAR_HALF: float = 0.004
const _CAGE_COLOR := Color(0.86, 0.86, 0.88)
# The backplate: a real mask is two shells, the painted front and a plate
# strapped over the back of the head. Tinting the rear facets darker draws the
# seam between them, and from the top-down camera it is what says which way
# the keeper is looking — the crown reads light in front, dark behind. Facets
# whose centroid lies within this half-angle of the +Z back axis.
const _BACKPLATE_HALF_ANGLE_DEG: float = 62.0
const _BACKPLATE_TINT := Color(0.66, 0.66, 0.68)
# Throat guard ("dangler"): a plate hanging from the chin in front of the neck
# guard, which otherwise reads as a bare stick under the mask from the front.
# Stations top→bottom in the mask's frame: (y, half-width, front −Z reach of
# the plate's face). It tucks up behind the chin rim and hangs a touch forward.
const _DANGLER_STATIONS: Array[Vector3] = [
	Vector3(-0.150, 0.034, 0.100),
	Vector3(-0.235, 0.032, 0.112),
	Vector3(-0.255, 0.020, 0.112),
]
const _DANGLER_HALF_T: float = 0.006

# NECK guard tube — a fixed-color child of the BODY mesh (created once by
# apply_goalie; the uniform coordinator repaints only the meshes it owns),
# so it tilts with the trunk's per-stance pitch/lean instead of hanging
# plumb under a head that never pitches. The body's local +Y axis passes
# within a few centimetres of the head center in every stance (STANDING
# 1.79/1.22 @ −4°, READY 1.62/1.06 @ −14°, BUTTERFLY 0.97/0.40 @ −10°), so
# one fixed body-local tube runs shoulders → mask chin everywhere. Set back
# of the spine line so the mask front overhangs it — the neck sits BEHIND a
# real mask, never flush with its face.
const _NECK_TOP_Y: float = 0.50    # body-local; buries into the mask chin
const _NECK_BOT_Y: float = 0.30    # below the body top (0.36) — no visible seam
const _NECK_RADIUS_TOP: float = 0.070
const _NECK_RADIUS_BOT: float = 0.080  # flares toward the shoulders
const _NECK_BACK_OFFSET: float = 0.025  # body-local +Z (rearward)
const _NECK_COLOR := Color(0.10, 0.10, 0.11)

# Catch glove: a trapper's hand, built as its silhouette rather than as the
# hoop and disc of the primitives it replaces. The drawn forearm is the wrist
# and cuff, so this starts at its end: seen by the shooter, a mitt rising from
# a rounded heel at the wrist, the thumb up the side toward the body, the
# T-web's notch between thumb and fingers, and the finger stall arching over
# the top and down the outside, around a deep pocket. In the Glove body's
# frame, which every stance leaves unrotated: −Z is toward the shooter, the
# glove hangs on the goalie's −X side so +X is its inner (body) side, and the
# origin is the wrist the drawn forearm meets.
const _TRAPPER_OUTLINE: Array[Vector2] = [
	Vector2(-0.015, -0.070),   # heel, over the forearm's end
	Vector2(0.060, -0.050),
	Vector2(0.100, -0.010),    # thumb base
	Vector2(0.115, 0.060),
	Vector2(0.100, 0.120),     # thumb tip
	Vector2(0.065, 0.145),
	Vector2(0.045, 0.125),     # the T-web's notch
	Vector2(0.025, 0.180),
	Vector2(-0.020, 0.215),    # top of the finger stall
	Vector2(-0.070, 0.205),
	Vector2(-0.110, 0.155),
	Vector2(-0.125, 0.075),    # the stall down the outside
	Vector2(-0.120, -0.005),
	Vector2(-0.090, -0.050),
]
# Every layer is the outline shrunk toward this point.
const _TRAPPER_POCKET_CENTER := Vector2(-0.005, 0.070)
# Layers back to front: (z, outline scale) — the rounded back, the full-width
# side, the rim's front edge and lip, then down into the pocket.
const _TRAPPER_LAYERS: Array[Vector2] = [
	Vector2(0.060, 0.84),
	Vector2(0.025, 1.00),
	Vector2(-0.045, 1.00),
	Vector2(-0.060, 0.82),     # rim lip
	Vector2(-0.040, 0.64),     # pocket wall
	Vector2(0.000, 0.62),      # pocket floor
]
const _TRAPPER_RIM_LIP_LAYER: int = 3
# One material paints the whole glove, so the pocket is told apart from the
# rim by baked tint: a deep shade, which is what makes the face read as open.
const _GLOVE_POCKET_TINT := Color(0.58, 0.58, 0.60)

# Blocker: the board (the 0.2 × 0.39 × 0.05 collider box, NHL Rule 11.6's
# 8 × 16 in at near its limit) strapped to the back of a padded glove whose fist
# wraps the shaft. The board's face is −Z, toward the shooter; local +X is its
# outer edge, away from the body. Cross-section features, as fractions of the
# half-width: the face panel recessed between a narrow inner border and the
# raised sidewall that runs the outer edge, and the finger-protection section
# across the top, split from the face by a break.
const _BLOCKER_HALF_W: float = 0.10
const _BLOCKER_HALF_D: float = 0.025
const _BLOCKER_HALF_H: float = 0.195
const _BLOCKER_PANEL_INNER_X: float = 0.78
const _BLOCKER_PANEL_OUTER_X: float = 0.55
const _BLOCKER_PANEL_RECESS: float = 0.008
# Stations top→bottom: (y, width multiplier, depth multiplier).
const _BLOCKER_STATIONS: Array[Vector3] = [
	Vector3(0.195, 0.90, 0.70),    # finger protection, rolled back at the top
	Vector3(0.175, 1.00, 1.00),
	Vector3(0.112, 1.00, 1.00),
	Vector3(0.100, 0.97, 0.80),    # the break below the finger section
	Vector3(0.088, 1.00, 1.00),
	Vector3(-0.175, 1.00, 1.00),
	Vector3(-0.195, 0.92, 0.80),
]
const _BLOCKER_BREAK_Y: float = 0.100
const _BLOCKER_PANEL_TINT := Color(0.84, 0.84, 0.86)
const _BLOCKER_BREAK_TINT := Color(0.60, 0.60, 0.62)
# The glove behind the board, in the BlockArm frame the hand ball sat in (origin
# at the wrist, where the shaft is gripped): a fist block round the shaft, its
# back flush with the board's and its palm leather a shade darker than the
# board so the two pieces read apart.
const _BLOCKER_FIST_HALF := Vector3(0.050, 0.060, 0.040)
const _BLOCKER_FIST_TINT := Color(0.78, 0.78, 0.80)

# Hip connector tube radius — baked into the shared connector mesh; the
# per-frame stretch in Goalie._point_connector scales the basis Y column only.
const HIP_CONNECTOR_RADIUS: float = 0.08


# Swaps every scene-primitive goalie part for its cached low-poly build.
# Idempotent; the uniform coordinator's material_override painting and the
# jersey ShaderMaterial ride mesh identity unchanged. (Named apart from the
# inherited SkaterMeshBuilder.apply — GDScript forbids overriding with a
# different signature.)
static func apply_goalie(goalie: Goalie) -> void:
	_swap_instance(goalie.body_mesh, "goalie_body", _build_body)
	_swap_instance(goalie.head_mesh, "goalie_mask", _build_mask)
	_ensure_extras(goalie)
	_swap_instance(goalie.left_pad_mesh, "goalie_pad", _build_pad)
	_swap_instance(goalie.right_pad_mesh, "goalie_pad", _build_pad)
	_merge_glove(goalie)
	_merge_stick(goalie)
	_merge_blocker(goalie)


# ── Rigid merges ─────────────────────────────────────────────────────────────
# The goalie does NOT get the skater's skinned-rig treatment, and the reason is
# worth stating where someone would otherwise try it: its moving parts are
# StaticBody3Ds carrying real colliders (the puck bounces off the pads, the
# glove and the stick, and the poke geometry reads the blade collider's world
# position). apply_body_config moves six of them per tick, and their meshes are
# children that ride along for free. Bones would not replace those writes — the
# bodies still have to move for collision — they would ADD one per mesh.
#
# What DOES apply is the merge the boot and helmet already use: several meshes
# that never move relative to each other, and here also share one material, do
# not need to be separate nodes. Each group collapses to one node, one mesh and
# one draw call.
#
# The absorbed nodes are resolved by path rather than kept as Goalie fields:
# they are freed here, so a field would be left dangling for anyone who reached
# for it later. A part that must stay addressable therefore has to stay OUT of
# its merge — see _merge_stick and the blade.
#
# The part transforms are read off the scene and BAKED into a mesh that every
# goalie shares. That is safe because every goalie is the same scene, but it
# does mean the first goalie built decides the cached geometry — moving one of
# these nodes in the editor changes every goalie, which is what you want, and
# changing it at runtime would not take, which nothing does.
static func _merge_glove(goalie: Goalie) -> void:
	var ring: MeshInstance3D = goalie.get_node("Glove/Ring") as MeshInstance3D
	var detail: MeshInstance3D = goalie.get_node("Glove/MeshInstance3D2") as MeshInstance3D
	_merge_rigid(goalie.glove_main_mesh, "goalie_trapper", [
		[_shared("goalie_trapper_part", _build_trapper), Transform3D.IDENTITY],
	])
	ring.free()
	detail.free()


# THE BLADE IS NOT IN THIS MERGE, and that is the whole reason the merge stops at
# two parts. Merging bakes a part's placement into vertices, and the blade's is
# not the authored one: Goalie._seat_blade re-hangs it from the heel with the
# stick's lie and curve on it, and it is a different mesh entirely from the box
# the scene carries. Baking the authored box in would freeze the visible blade at
# an angle and a shape the collider making the save does not have.
static func _merge_stick(goalie: Goalie) -> void:
	var paddle: MeshInstance3D = goalie.get_node(
			"BlockArm/Stick/StickPaddleMesh") as MeshInstance3D
	# The stick's boxes are the only goalie parts still rendering the scene's own
	# primitives — there is no low-poly build to swap in, so the merge bakes what
	# the nodes are already carrying.
	_merge_rigid(goalie.stick_shaft_mesh, "goalie_stick_shaft_paddle", [
		[goalie.stick_shaft_mesh.mesh, goalie.stick_shaft_mesh.transform],
		[paddle.mesh, paddle.transform],
	])
	paddle.free()


# The hand is a sibling of the blocker BODY, not of its mesh, so its transform
# is re-expressed in that body's frame before baking.
static func _merge_blocker(goalie: Goalie) -> void:
	var hand: MeshInstance3D = goalie.get_node("BlockArm/BlockerHand") as MeshInstance3D
	var body: Node3D = goalie.blocker_mesh.get_parent() as Node3D
	_merge_rigid(goalie.blocker_mesh, "goalie_blocker_assembly", [
		[_shared("goalie_blocker", _build_blocker), goalie.blocker_mesh.transform],
		[_shared("goalie_blocker_hand", _build_blocker_hand),
				body.transform.affine_inverse() * hand.transform],
	])
	hand.free()


# Bakes several meshes into one and hands it to `survivor`, whose own transform
# is cleared because the parts' placements now live in the vertices. `parts`
# entries are [source mesh, transform in the survivor's PARENT frame].
static func _merge_rigid(survivor: MeshInstance3D, key: String, parts: Array) -> void:
	var built: ArrayMesh = _cache.get(key)
	if built == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: Array in parts:
			st.append_from(part[0] as Mesh, 0, part[1] as Transform3D)
		built = st.commit()
		_cache[key] = built
	survivor.mesh = built
	survivor.transform = Transform3D.IDENTITY


# Unit-radius, unit-height straight tube for the hip connectors (the arm
# bones use the tapered shared_arm_bone instead). Cylinder-convention UVs —
# the connectors are painted with the pants stripe texture.
static func shared_connector_tube() -> ArrayMesh:
	return _shared("goalie_connector", func() -> ArrayMesh:
		var profile: Array[Vector2] = [
			Vector2(0.5, HIP_CONNECTOR_RADIUS), Vector2(-0.5, HIP_CONNECTOR_RADIUS)]
		return _build_lathe(profile, 8, 1.0, 1.0))


# The blade the keeper actually carries, and the same builder the skaters use —
# a bowed centerline, a heel-to-toe height and thickness taper, a rounded toe and
# a hosel up the paddle line, in place of the box that was there. A box cannot be
# flush with the paddle through a rotation and cannot bow, and both showed.
#
# Sized off NHL Rule 10.2 (see GoalieStickRules): 0.38 m heel to toe against the
# 0.394 limit, 0.108 m tall at the heel tapering to the 0.089 standard, and the
# full 0.019 m of permitted curve — a goalie blade is much taller and much
# straighter than the player blade this builder defaults to.
#
# HEEL-ORIGIN, which is the point. Goalie._seat_blade hangs it from the joint so
# the lie and the curve pivot there instead of about the blade's middle.
static func shared_goalie_blade() -> ArrayMesh:
	return _shared("goalie_blade", func() -> ArrayMesh:
		var p := StickBladeMeshBuilder.Params.new()
		p.length = GoalieStickRules.BLADE_WIDTH_M
		p.height = GoalieStickRules.BLADE_HEEL_HEIGHT_M
		p.height_toe_frac = GoalieStickRules.BLADE_HEIGHT_M \
				/ GoalieStickRules.BLADE_HEEL_HEIGHT_M
		p.thickness_heel = GoalieStickRules.BLADE_THICKNESS_M
		p.thickness_toe = GoalieStickRules.BLADE_THICKNESS_M * 0.75
		p.curve_depth = GoalieStickRules.BLADE_CURVE_DEPTH_M
		# Late and shallow: a keeper's blade holds straight through the contact
		# zone and turns near the toe, where a player's heel curve would lift the
		# middle of it off the ice.
		p.curve_power = 3.0
		p.toe_round_m = 0.018
		p.toe_kick_m = 0.002
		p.toe_kick_start_frac = 0.82
		# The blade's own twist stays at zero: blade_curve_face_deg() already turns
		# the whole blade, and doing it twice would double the steer.
		p.face_open_deg = 0.0
		# NO HOSEL. The builder's taper is sized to hide inside a player's 0.05 m
		# shaft, and a goalie paddle is 0.03 m thick — it stood proud of the very
		# joint it exists to close. The paddle's own box meets the heel instead.
		p.hosel_length = 0.0
		return StickBladeMeshBuilder.build(p))


# ── Part builders ─────────────────────────────────────────────────────────────


static func _build_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for s: Vector2 in _BODY_STATIONS:
		loops.append(_body_loop(s.x, s.y))
	_sweep_loops(st, loops)
	_loop_cap(st, loops[0], Vector3(0.0, _BODY_STATIONS[0].x, 0.0), true)     # top (yoke)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(0.0, _BODY_STATIONS[_BODY_STATIONS.size() - 1].x, 0.0), false)
	st.generate_normals()
	return st.commit()


# 8-point chest cross-section, CCW seen from +Y (the sweep-loop contract):
# generous flat back segment at +Z for the nameplate, wide chamfers rounding
# the front. Width multiplier scales x only — see the class doc block.
static func _body_loop(y: float, w_mult: float) -> PackedVector3Array:
	var hw: float = _BODY_HALF_W * w_mult
	var hd: float = _BODY_HALF_D
	var pts := PackedVector3Array()
	pts.resize(8)
	pts[0] = Vector3(-0.13 * w_mult, y, -hd)   # front-left
	pts[1] = Vector3(-hw, y, -0.05)
	pts[2] = Vector3(-hw, y, 0.08)
	pts[3] = Vector3(-0.21 * w_mult, y, hd)    # back-left
	pts[4] = Vector3(0.21 * w_mult, y, hd)     # back-right
	pts[5] = Vector3(hw, y, 0.08)
	pts[6] = Vector3(hw, y, -0.05)
	pts[7] = Vector3(0.13 * w_mult, y, -hd)    # front-right
	return pts


static func _build_pad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for s: Vector4 in _PAD_STATIONS:
		loops.append(_pad_loop(s.x, _PAD_HALF_W * s.y, s.z, s.w))
	_sweep_loops(st, loops)
	_loop_cap(st, loops[0], Vector3(0.0, _PAD_STATIONS[0].x, 0.0), true)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(0.0, _PAD_STATIONS[_PAD_STATIONS.size() - 1].x, 0.0), false)
	st.generate_normals()
	return _bake_facet_tint(st.commit(), _pad_tint)


# 14-point pad cross-section, CCW seen from +Y (the sweep-loop contract), in the
# _octagon_loop order: front centre, out along the face to the roll, round the
# side to the back, across the back with the leg channel cut into it, and back
# along the other half. The shin face's outer panels angle back from the centre
# one, so the crease between them is a facet edge.
static func _pad_loop(y: float, hw: float, front: float, back: float) -> PackedVector3Array:
	var gx: float = hw * _PAD_PANEL_X
	var fx: float = hw * _PAD_FACE_X
	var cx: float = hw * _PAD_CHANNEL_X
	var channel: float = back - _PAD_CHANNEL_DEPTH
	var pts := PackedVector3Array()
	pts.resize(14)
	pts[0] = Vector3(-gx, y, -front)
	pts[1] = Vector3(-fx, y, -front * 0.93)
	pts[2] = Vector3(-hw, y, -front * 0.45)
	pts[3] = Vector3(-hw, y, back * 0.45)
	pts[4] = Vector3(-fx, y, back)
	pts[5] = Vector3(-cx, y, back)
	pts[6] = Vector3(-cx * 0.75, y, channel)
	pts[7] = Vector3(cx * 0.75, y, channel)
	pts[8] = Vector3(cx, y, back)
	pts[9] = Vector3(fx, y, back)
	pts[10] = Vector3(hw, y, back * 0.45)
	pts[11] = Vector3(hw, y, -front * 0.45)
	pts[12] = Vector3(fx, y, -front * 0.93)
	pts[13] = Vector3(gx, y, -front)
	return pts


static func _pad_tint(centroid: Vector3, _normal: Vector3) -> Color:
	if centroid.z > _PAD_HALF_D * 0.5 \
			and absf(centroid.x) < _PAD_HALF_W * _PAD_CHANNEL_X * 0.9:
		return _PAD_CHANNEL_TINT
	for y: float in _PAD_BREAK_YS:
		if absf(centroid.y - y) < _PAD_BREAK_HALF:
			return _PAD_CREASE_TINT
	return Color.WHITE


static func _build_blocker() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for s: Vector3 in _BLOCKER_STATIONS:
		loops.append(_blocker_loop(s.x, _BLOCKER_HALF_W * s.y, _BLOCKER_HALF_D * s.z))
	_sweep_loops(st, loops)
	_loop_cap(st, loops[0], Vector3(0.0, _BLOCKER_STATIONS[0].x, 0.0), true)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(0.0, _BLOCKER_STATIONS[_BLOCKER_STATIONS.size() - 1].x, 0.0), false)
	st.generate_normals()
	return _bake_facet_tint(st.commit(), _blocker_tint)


# 10-point board cross-section, CCW seen from +Y, in the _octagon_loop order:
# the inner (−X) bevel, the flat back, the full-depth rounded sidewall on +X,
# then back across the face with the panel stepped in between the borders.
static func _blocker_loop(y: float, hw: float, hd: float) -> PackedVector3Array:
	var px_in: float = -hw * _BLOCKER_PANEL_INNER_X
	var px_out: float = hw * _BLOCKER_PANEL_OUTER_X
	var panel_z: float = -hd + _BLOCKER_PANEL_RECESS * hd / _BLOCKER_HALF_D
	var pts := PackedVector3Array()
	pts.resize(10)
	pts[0] = Vector3(-hw * 0.88, y, -hd * 0.7)
	pts[1] = Vector3(-hw, y, -hd * 0.1)
	pts[2] = Vector3(-hw * 0.92, y, hd)
	pts[3] = Vector3(hw * 0.85, y, hd)
	pts[4] = Vector3(hw, y, hd * 0.3)
	pts[5] = Vector3(hw, y, -hd * 0.6)
	pts[6] = Vector3(hw * 0.78, y, -hd)
	pts[7] = Vector3(px_out, y, panel_z)
	pts[8] = Vector3(px_in + hw * 0.06, y, panel_z)
	pts[9] = Vector3(px_in, y, -hd * 0.85)
	return pts


static func _blocker_tint(centroid: Vector3, normal: Vector3) -> Color:
	if absf(centroid.y - _BLOCKER_BREAK_Y) < 0.010:
		return _BLOCKER_BREAK_TINT
	if normal.z < -0.9 and centroid.x > -_BLOCKER_HALF_W * _BLOCKER_PANEL_INNER_X \
			and centroid.x < _BLOCKER_HALF_W * _BLOCKER_PANEL_OUTER_X:
		return _BLOCKER_PANEL_TINT
	return Color.WHITE


static func _ensure_extras(goalie: Goalie) -> void:
	var head: MeshInstance3D = goalie.head_mesh
	if head != null and head.get_node_or_null("Dangler") == null:
		var dangler := MeshInstance3D.new()
		dangler.name = "Dangler"
		dangler.mesh = _shared("goalie_dangler", _build_dangler)
		head.add_child(dangler)
	if head != null and head.get_node_or_null("Cage") == null:
		var cage := MeshInstance3D.new()
		cage.name = "Cage"
		cage.mesh = _shared("goalie_cage", _build_cage)
		var cage_mat := StandardMaterial3D.new()
		cage_mat.albedo_color = _CAGE_COLOR
		cage_mat.metallic = 0.6
		cage_mat.roughness = 0.35
		cage.material_override = cage_mat
		cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(cage)
	var body: MeshInstance3D = goalie.body_mesh
	if body == null or body.get_node_or_null("Neck") != null:
		return
	var neck := MeshInstance3D.new()
	neck.name = "Neck"
	neck.mesh = _shared("goalie_neck", func() -> ArrayMesh:
		var profile: Array[Vector2] = [
			Vector2(_NECK_TOP_Y, _NECK_RADIUS_TOP),
			Vector2(_NECK_BOT_Y, _NECK_RADIUS_BOT)]
		return _build_lathe(profile, 8, 1.0, 1.0))
	neck.position = Vector3(0.0, 0.0, _NECK_BACK_OFFSET)
	var neck_mat := StandardMaterial3D.new()
	neck_mat.albedo_color = _NECK_COLOR
	neck_mat.roughness = 0.9
	BodyRim.apply(neck_mat)
	neck.material_override = neck_mat
	body.add_child(neck)


static func _build_mask() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for s: Vector4 in _MASK_STATIONS:
		loops.append(_mask_loop(s.x, s.y, s.z, s.w))
	_sweep_loops(st, loops)
	_loop_cap(st, loops[0], Vector3(0.0, _MASK_STATIONS[0].x, 0.0), true)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(0.0, _MASK_STATIONS[_MASK_STATIONS.size() - 1].x, 0.0), false)
	st.generate_normals()
	return _bake_facet_tint(st.commit(), _mask_tint)


# Cage facets: between brow and chin, within the cage's half-angle of the −Z
# front axis. Backplate facets: within its half-angle of the +Z back axis.
static func _mask_tint(centroid: Vector3, _normal: Vector3) -> Color:
	var flat: float = Vector2(centroid.x, centroid.z).length()
	if flat < 0.001:
		return Color.WHITE
	if centroid.z / flat > cos(deg_to_rad(_BACKPLATE_HALF_ANGLE_DEG)):
		return _BACKPLATE_TINT
	var in_cage: bool = centroid.y < _CAGE_TOP_Y and centroid.y > _CAGE_BOT_Y \
			and -centroid.z / flat > cos(deg_to_rad(_CAGE_HALF_ANGLE_DEG))
	return _CAGE_TINT if in_cage else Color.WHITE


static func _tinted(mesh: ArrayMesh, color: Color) -> ArrayMesh:
	return _bake_facet_tint(mesh, func(_c: Vector3, _n: Vector3) -> Color: return color)


# Rebuilds the committed surface with per-facet vertex colors from
# `tint_of(centroid, normal) -> Color`, white being pure paint. Flat shading
# keeps vertices un-shared across facets, so a whole-triangle color never
# bleeds. The part's material must enable vertex_color_use_as_albedo, or the
# tint is silently dropped (test_goalie_paint_reads_the_baked_tints).
static func _bake_facet_tint(mesh: ArrayMesh, tint_of: Callable) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var c: Vector3 = (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var col: Color = tint_of.call(c, normals[i])
		colors[i] = col
		colors[i + 1] = col
		colors[i + 2] = col
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# The cage's bars as box segments between their crossings, each set _CAGE_PROUD
# in front of the mask's surface at its ends, so the grid follows the face's
# curve both ways rather than standing off it as a flat plate.
static func _build_cage() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var ys: Array[float] = [_CAGE_TOP_Y]
	ys.append_array(_CAGE_BAR_YS)
	ys.append(_CAGE_BOT_Y + 0.015)
	var xs: Array[float] = [-_CAGE_HALF_X]
	xs.append_array(_CAGE_BAR_XS)
	xs.append(_CAGE_HALF_X)
	var t: float = _CAGE_BAR_HALF
	for x: float in _CAGE_BAR_XS:
		for i in ys.size() - 1:
			var z: float = minf(_mask_front_z(x, ys[i]), _mask_front_z(x, ys[i + 1])) - _CAGE_PROUD
			_box(st, Vector3(x - t, ys[i + 1], z - t), Vector3(x + t, ys[i], z + t))
	for y: float in _CAGE_BAR_YS:
		for i in xs.size() - 1:
			var z: float = minf(_mask_front_z(xs[i], y), _mask_front_z(xs[i + 1], y)) - _CAGE_PROUD
			_box(st, Vector3(xs[i], y - t, z - t), Vector3(xs[i + 1], y + t, z + t))
	st.generate_normals()
	return st.commit()


# The mask's front surface z at (x, y): its front reach at that height,
# interpolated between stations, set back elliptically toward the sides.
static func _mask_front_z(x: float, y: float) -> float:
	for i in _MASK_STATIONS.size() - 1:
		var a: Vector4 = _MASK_STATIONS[i]
		var b: Vector4 = _MASK_STATIONS[i + 1]
		if y <= a.x and y >= b.x:
			var f: float = inverse_lerp(a.x, b.x, y)
			var rx: float = lerpf(a.y, b.y, f)
			var front: float = lerpf(a.w, b.w, f)
			return -front * sqrt(maxf(1.0 - (x / rx) * (x / rx), 0.0))
	return 0.0


# Painted with the mask (GoalieUniformCoordinator), so it bakes plain white
# vertex colour for the mask material's vertex-colour albedo.
static func _build_dangler() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for s: Vector3 in _DANGLER_STATIONS:
		var loop: PackedVector3Array = _octagon_loop(s.x, s.y, _DANGLER_HALF_T, 0.7, 0.5)
		for k in loop.size():
			loop[k] += Vector3(0.0, 0.0, _DANGLER_HALF_T - s.z)
		loops.append(loop)
	_sweep_loops(st, loops)
	var top: Vector3 = _DANGLER_STATIONS[0]
	var bottom: Vector3 = _DANGLER_STATIONS[_DANGLER_STATIONS.size() - 1]
	_loop_cap(st, loops[0], Vector3(0.0, top.x, -(top.z - _DANGLER_HALF_T)), true)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(0.0, bottom.x, -(bottom.z - _DANGLER_HALF_T)), false)
	st.generate_normals()
	return _tinted(st.commit(), Color.WHITE)


# Egg-shaped cross-section: _ring's trig (θ = 0 at +Z, CCW from +Y — same
# winding) with the Z reach split per half so the front can differ from the
# back.
static func _mask_loop(y: float, rx: float, back_z: float, front_z: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(_MASK_SEGS)
	for k in _MASK_SEGS:
		var theta: float = TAU * float(k) / float(_MASK_SEGS)
		var cz: float = cos(theta)
		var rz: float = back_z if cz >= 0.0 else front_z
		pts[k] = Vector3(sin(theta) * rx, y, cz * rz)
	return pts


static func _build_blocker_hand() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var h: Vector3 = _BLOCKER_FIST_HALF
	var loops: Array[PackedVector3Array] = [
		_octagon_loop(h.y, h.x * 0.85, h.z * 0.85, 0.6, 0.5),
		_octagon_loop(h.y * 0.6, h.x, h.z, 0.6, 0.5),
		_octagon_loop(-h.y * 0.6, h.x, h.z, 0.6, 0.5),
		_octagon_loop(-h.y, h.x * 0.85, h.z * 0.85, 0.6, 0.5),
	]
	_sweep_loops(st, loops)
	_loop_cap(st, loops[0], Vector3(0.0, h.y, 0.0), true)
	_loop_cap(st, loops[loops.size() - 1], Vector3(0.0, -h.y, 0.0), false)
	st.generate_normals()
	return _tinted(st.commit(), _BLOCKER_FIST_TINT)


# The trapper as a sweep of its outline, back to front: each layer the outline
# shrunk toward the pocket centre and stepped in z, the last closing the pocket
# floor.
static func _build_trapper() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat shading — see SkaterMeshBuilder doc block
	var loops: Array[PackedVector3Array] = []
	for layer: Vector2 in _TRAPPER_LAYERS:
		var loop := PackedVector3Array()
		for p: Vector2 in _TRAPPER_OUTLINE:
			var q: Vector2 = _TRAPPER_POCKET_CENTER + (p - _TRAPPER_POCKET_CENTER) * layer.y
			loop.append(Vector3(q.x, q.y, layer.x))
		loops.append(loop)
	_sweep_loops(st, loops)
	var c: Vector2 = _TRAPPER_POCKET_CENTER
	_loop_cap(st, loops[0], Vector3(c.x, c.y, _TRAPPER_LAYERS[0].x), true)
	_loop_cap(st, loops[loops.size() - 1],
			Vector3(c.x, c.y, _TRAPPER_LAYERS[_TRAPPER_LAYERS.size() - 1].x), false)
	st.generate_normals()
	return _bake_facet_tint(st.commit(), _trapper_tint)


# Pocket: the facets behind the rim lip, inside it.
static func _trapper_tint(centroid: Vector3, _normal: Vector3) -> Color:
	if centroid.z > _TRAPPER_LAYERS[_TRAPPER_RIM_LIP_LAYER].x + 0.002 \
			and centroid.z < _TRAPPER_LAYERS[1].x \
			and _inside_rim_lip(centroid):
		return _GLOVE_POCKET_TINT
	return Color.WHITE


# Whether a point lies inside the rim lip's outline in plan: no farther from
# the pocket centre than the lip is along the same direction (the outline is
# star-shaped about that centre, which the caps' fans need anyway).
static func _inside_rim_lip(p: Vector3) -> bool:
	var d := Vector2(p.x, p.y) - _TRAPPER_POCKET_CENTER
	var scale: float = _TRAPPER_LAYERS[_TRAPPER_RIM_LIP_LAYER].y
	var n: int = _TRAPPER_OUTLINE.size()
	for i in n:
		var a: Vector2 = (_TRAPPER_OUTLINE[i] - _TRAPPER_POCKET_CENTER) * scale
		var b: Vector2 = (_TRAPPER_OUTLINE[(i + 1) % n] - _TRAPPER_POCKET_CENTER) * scale
		# d within the wedge a..b, and on the centre's side of the a-b edge.
		if a.cross(d) * a.cross(b) >= 0.0 and d.cross(b) * a.cross(b) >= 0.0:
			return (b - a).cross(d - a) * (b - a).cross(-a) >= 0.0
	return false


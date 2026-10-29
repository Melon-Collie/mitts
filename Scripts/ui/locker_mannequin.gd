class_name LockerMannequin
extends Node3D

# A full kit-dressed skater (FigureKit) holding the picked stick in both hands:
# the player screen's display figure, standing in its case (PlayerCase), and —
# `seated` — a player on the lobby's bench. Every piece the player screen edits
# is worn HERE — skates on the feet, gloves gripping the shaft, face gear and
# hair on the head — so a pick is judged in the place it will actually be seen.
#
# It is the rink's own body on the rink's own skeleton, posed by writing its
# bones as the rigs would (no gait, no IK rig: the pose is solved here). The
# jersey's tail is the rink's cloth: settled on each pose, and on a standing
# figure stepped on every frame, carried through the case's turn so it swings
# as the figure does (_process).
#
# Frame: the rest positions below are Scenes/Skater.tscn's, in MeshRoot-local
# coordinates, so the figure is laid out in the rig's own numbers and faces −Z
# like the rig does. `_rig` is then seated so the blade contact lands on THIS
# node's origin — y = 0 is the ice, whatever the build's height. Seated, the
# underside of the thighs lands there instead: y = 0 is the bench.
#
# Body dials scale the rig about that ice plane, mirroring
# SkaterAppearanceCoordinator's rule: every Y offset rides the height
# multiplier, each part's lateral scale rides its own bulk multiplier, and the
# helmet scales uniformly by its own mild table rather than stretching with
# height.
#
# The stick hangs at rest — no flex pulse. Both fists are pinned to the shaft,
# and a bow that leaves the hands behind reads as broken rather than as flex.
# The FLEX row carries the fitted stiffness number instead.

# The camera framings the player screen's case dollies between, plus the wide shot nothing is
# focused. The stick takes THREE of them because one shot cannot serve its eight
# rows: it is nearly as long as the player is tall, so a framing that contains
# all of it is barely a zoom at all. LENGTH and FLEX want the whole stick, CURVE
# and the blade tape want the blade, the knob and the wrap want the butt end.
enum Focus { FULL, STICK, BLADE, GRIP, SKATES, GLOVES, HELMET }

# ── Rig rest pose (Scenes/Skater.tscn, MeshRoot-local) ───────────────────────
# Leg offsets are relative to the LEG pivot so the chain reads as the scene's
# parenting does (Leg → Shin → Sock/Skate/Foot) without the intermediate nodes.
const _TORSO_Y: float = 0.195
const _HELMET_Y: float = 0.65
const _SHOULDER_X: float = 0.22
const _SHOULDER_Y: float = 0.40
const _LEG_X: float = 0.13
const _LEG_Y: float = -0.13
const _SOCK_DY: float = -0.50
const _COLLAR_DY: float = -0.72
const _BOOT_DY: float = -0.76
const _BOOT_DZ: float = -0.10
const _THIGH_DY: float = -0.13
const _KNEE_DY: float = -0.31
# Boot frame, straight off FootL/R's scene basis: local −Y is the toe and local
# +Z is down, so this lands the toe on −Z (the way the rig faces) sole-down.
const _BOOT_ROT := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
const _UpperBone = SkaterMeshBuilder.UpperBone
const _LegBone = SkaterMeshBuilder.LegBone
# Each arm's bones, TOP hand first, then BOTTOM — the grip order on the shaft,
# not left/right, because that is what the pose is built from: the upper arm,
# the forearm, the elbow, the hand and the cuff.
const _ARM_BONES: Array[Array] = [
	[_UpperBone.TOP_UPPER_ARM, _UpperBone.TOP_FOREARM, _UpperBone.TOP_ELBOW,
			_UpperBone.TOP_HAND, _UpperBone.TOP_CUFF],
	[_UpperBone.BOTTOM_UPPER_ARM, _UpperBone.BOTTOM_FOREARM, _UpperBone.BOTTOM_ELBOW,
			_UpperBone.BOTTOM_HAND, _UpperBone.BOTTOM_CUFF],
]
# The runner bottoms out this far below the boot origin.
const _BLADE_ICE_M: float = SkaterMeshBuilder.BLADE_ICE_Z
# The ice plane in rig-local coordinates. Everything scales about it.
const _ICE_Y: float = _LEG_Y + _BOOT_DY - _BLADE_ICE_M

# Part radii, all the live rig's own defaults (Skater.arm_mesh_thickness and
# its kin), and all scaled by girth together as the rig's are.
const _ARM_RADIUS: float = SkaterMeshBuilder.SLEEVE_RADIUS_M
const _ELBOW_RADIUS: float = SkaterMeshBuilder.ELBOW_PAD_RADIUS_M
const _HAND_RADIUS: float = SkaterMeshBuilder.GLOVE_FIST_RADIUS_M
const _CUFF_RADIUS: float = SkaterMeshBuilder.SLEEVE_RADIUS_M * 1.2
# Skater.cuff_wrist_offset and wrist_break_max_deg at their defaults.
const _CUFF_WRIST_OFFSET_M: float = SkaterMeshBuilder.GLOVE_CUFF_BACK_M \
		- SkaterMeshBuilder.CUFF_HEIGHT_M * 0.5
const _WRIST_BREAK_MAX_DEG: float = 25.0
# Seated, the underside of the thighs is this far under the hip pivot (the
# pants leg's half depth), times the build's girth: what rests on the bench.
const _SEAT_UNDER_HIP_M: float = 0.14
# Arm segments at the rig's own lengths (Skater.upper_arm_length /
# forearm_length), NOT derived from how far the grip happens to be: the two
# hands sit at very different distances from their shoulders, so a
# reach-proportional segment builds one long arm and one short one.
const _UPPER_ARM_M: float = 0.33
const _FOREARM_M: float = 0.33
# Grips are solved onto the shaft within this fraction of the arm's full span,
# so the elbow always has a bend left in it and the fists never float off the
# hand they belong to.
const _GRIP_REACH_FRAC: float = 0.88
# Elbow pole hint, the rig's own (Skater.arm_pole_local) — mirrored per side so
# each elbow swings out and back rather than folding into the ribs.
const _ARM_POLE := Vector3(0.55, -1.0, 0.1)

# ── Stick pose ───────────────────────────────────────────────────────────────
# The display LIE — steeper than the rink's 42°, which is a skating-crouch
# number. A standing player's stick is near-upright, and the hosel is built at
# this same angle so the blade still sits flat on the ice instead of up on an
# edge. Steep also keeps the silhouette portrait-shaped: at 68° the blade is
# only ~0.5 m ahead of the butt instead of ~0.8 m.
const _SHAFT_LEAN_DEG: float = 68.0
# Yaw of the whole stick about the heel — the shaft leans back across the body
# rather than straight out, which is what puts the blade in profile.
const _STICK_YAW_DEG: float = 30.0
# Blade heel on the ice: out to the shooting side and ahead of the toes.
# Deliberately not scaled by height — where a player plants the blade is a
# stance, not a limb length.
const _HEEL_OUT_M: float = 0.14
const _HEEL_FWD_M: float = -0.67
# The heel point rides this far above the floor, which rests the blade —
# tilted with the shaft's lie — with its sole just clear of it (~7 mm).
const _HEEL_LIFT_M: float = 0.042
# Seated, the blade rests on the bench floor this far ahead of the knees, the
# shaft standing up between them.
const _SEATED_HEEL_FWD_M: float = -0.22
# Where the grips WANT to sit — the top hand just under the knob, the bottom
# hand high on the shaft. Both are only hints: the arm pass slides each one
# along the shaft until its own shoulder can actually reach it. They sit high
# because a stick standing on the ice in front of a player genuinely is held
# near its top; the shoulders are only ~1.4 m above a blade planted 0.7 m out.
const _TOP_HAND_DROP_M: float = 0.13
const _BOTTOM_HAND_FRAC: float = 0.70
# A grip never rides onto the hosel, and never past the knob.
const _GRIP_MIN_S_M: float = 0.25
const _GRIP_END_MARGIN_M: float = 0.06
const _HOSEL_LEN_M: float = 0.085

# ── Camera framings, indexed by Focus ────────────────────────────────────────
# The yaw the figure turns to present the piece (mirrored by shooting side, so
# the gear you are looking at faces the glass) and the camera's elevation:
# above for the head, well below for boots on the floor, and down onto the
# blade, which lies on the ice.
const _FOCUS_YAW_DEG: Array[float] = [22.0, 40.0, 52.0, 30.0, 26.0, 34.0, 18.0]
const _FOCUS_PITCH_DEG: Array[float] = [-3.0, 4.0, 26.0, -2.0, 24.0, 5.0, -8.0]
# Half-extent of each subject (width, height) in metres — the caller turns
# these into a distance with its own lens, so "how big is the thing" lives here
# and "how wide does the case see" lives there. The four fixed-size subjects
# are constants; FULL, STICK and GLOVES are measured per build in _pose,
# because a stick's length and a figure's height genuinely change what has to
# fit in frame.
const _FOCUS_EXTENT: Array[Vector2] = [
	Vector2(0.55, 0.95),   # FULL   — measured
	Vector2(0.45, 0.75),   # STICK  — measured
	Vector2(0.22, 0.13),   # BLADE
	Vector2(0.15, 0.17),   # GRIP
	# SKATES — the PAIR, so width binds: the boots sit ±0.13 apart and each is
	# ~0.30 front-to-back, which the presentation yaw turns partly into width.
	Vector2(0.24, 0.16),
	Vector2(0.16, 0.22),   # GLOVES — measured
	Vector2(0.19, 0.19),   # HELMET
]

var _rig: Node3D = null
var _skeleton: Skeleton3D = null

var _stick_root: Node3D = null
var _shaft: MeshInstance3D = null
var _blade: MeshInstance3D = null
var _tape_mesh: MeshInstance3D = null
var _knob: MeshInstance3D = null

# The skeleton and the stick are the kit's, aliased for the pose; the kit builds
# and dresses them.
var _kit := FigureKit.new()
var _player_name: String = ""
var _jersey_number: int = 0

# Focus anchors, in THIS node's space — recomputed by every apply() because the
# pieces move with the build's height and the picked stick length.
var _anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
# Seeded from _FOCUS_EXTENT; the measured framings overwrite their own entry.
var _extents: Array[Vector2] = _FOCUS_EXTENT.duplicate()
# The posed shaft line, in rig space. Written by the stick pass and read by the
# arm pass right after it — the grips are solved onto this line.
var _shaft_heel: Vector3 = Vector3.ZERO
var _shaft_up: Vector3 = Vector3.UP
var _shaft_len: float = 1.0
# +1 when the blade sits on the rig's +X side (a right-handed shot), −1 for a
# lefty. The top hand is always on the other side — see Skater._position_hand_markers.
var _blade_side: float = 1.0

# Set before the first apply(): sit on a bench rather than stand on the ice.
var seated: bool = false
# The figure's yaw as its hem last saw it, and the frame's step before this
# one (the cloth's verlet reads the ratio of the two).
var _hem_yaw: float = 0.0
var _hem_dt: float = 0.0


func _ready() -> void:
	_build()


# The standing figure's jersey tail, stepped as the case turns it: a turn is
# the world going round the other way in the skeleton's frame, so the cloth's
# points are carried back through it before the step, and the hem lags and
# swings. A seated figure's tail stays as it settled.
func _process(delta: float) -> void:
	if seated or _skeleton == null or not is_visible_in_tree():
		return
	var yaw: float = global_basis.get_euler().y
	var turn: float = angle_difference(yaw, _hem_yaw)
	_hem_yaw = yaw
	if absf(turn) > 1e-6 and _hem_dt > 0.0:
		var back := Basis(Vector3.UP, -turn)
		var state: PackedVector3Array = _kit.hem.get_state()
		for i: int in state.size():
			state[i] = back * state[i]
		_kit.hem.set_state(state, _hem_dt)
	_kit.hem.update(delta, true)
	_hem_dt = delta


# ── Construction ─────────────────────────────────────────────────────────────

func _build() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_kit.build(_rig, self)
	_skeleton = _kit.skeleton
	_stick_root = _kit.stick_root
	_shaft = _kit.shaft
	_blade = _kit.blade
	_tape_mesh = _kit.tape_mesh
	_knob = _kit.knob


# ── Host API ─────────────────────────────────────────────────────────────────

# Dress and pose the figure from one pending build. `team_colors` is the
# pending team's TeamColorRegistry.get_colors dict — the kit the mannequin
# wears AND the slots a gear model's TEAM / ACCENT / LIGHT zones resolve
# against, so the figure previews the design on the sweater you are buying it
# for.
func apply(attrs: PlayerAttributes, gear: GearStyleConfig, tape: StickTapeConfig,
		team_colors: Dictionary, skin_tone: int, is_left_handed: bool) -> void:
	_blade_side = -1.0 if is_left_handed else 1.0
	_pose(attrs, tape, is_left_handed)
	_kit.dress(team_colors, gear, tape, skin_tone, _player_name, _jersey_number)
	_kit.hem.settle()
	_hem_yaw = global_basis.get_euler().y if is_inside_tree() else 0.0
	_hem_dt = 0.0


# The name and number the sweater is lettered with. Painted by the next apply().
func set_jersey_info(player_name: String, jersey_number: int) -> void:
	_player_name = player_name
	_jersey_number = jersey_number


# Where the camera looks for one framing, in this node's space.
func focus_anchor(focus: int) -> Vector3:
	return _anchors[clampi(focus, 0, _anchors.size() - 1)]


# Half-extent (width, height) of what this framing has to contain, in metres.
# The caller owns the lens, so it converts this into a distance.
func focus_extent(focus: int) -> Vector2:
	return _extents[clampi(focus, 0, _extents.size() - 1)]


# The yaw the figure turns to, mirrored so the piece under inspection swings
# toward the glass on either shooting side.
func focus_yaw(focus: int) -> float:
	return deg_to_rad(_FOCUS_YAW_DEG[clampi(focus, 0, _FOCUS_YAW_DEG.size() - 1)]) \
			* _blade_side


func focus_pitch(focus: int) -> float:
	return deg_to_rad(_FOCUS_PITCH_DEG[clampi(focus, 0, _FOCUS_PITCH_DEG.size() - 1)])


# ── Pose ─────────────────────────────────────────────────────────────────────

# Scale a rig-local height about the ice plane — the appearance rig's rule, so
# a tall build grows legs and torso together and the skates stay planted.
static func _lift(y: float, m_height: float) -> float:
	return _ICE_Y + (y - _ICE_Y) * m_height


func _pose(attrs: PlayerAttributes, tape: StickTapeConfig,
		is_left_handed: bool) -> void:
	var m_height: float = attrs.height_mult()
	var m_girth: float = attrs.girth_mult()
	var m_head: float = attrs.head_bulk_mult()
	var bulk := Basis.from_scale(Vector3(m_girth, m_height, m_girth))

	# The trunk bones under HIPS, WAIST, SPINE and NECK, all at identity: each
	# bone's pose is its place in the rig's own frame. The jersey's tail hangs
	# from the torso as the hips hold it (TAIL), which a still figure's are not.
	var torso := Transform3D(bulk, Vector3(0.0, _lift(_TORSO_Y, m_height), 0.0))
	_skeleton.set_bone_pose(_UpperBone.TORSO, torso)
	_skeleton.set_bone_pose(SkaterBodySkeleton.TAIL_BONE, torso)
	# The pants are authored in the hips' own space, whose origin is the rig's
	# y 0 — so they need no station of their own.
	_skeleton.set_bone_pose(_UpperBone.PELVIS,
			Transform3D(bulk, Vector3(0.0, _lift(0.0, m_height), 0.0)))
	# The helmet takes its own mild multiplier on all three axes and never
	# stretches with height: adult heads are near-constant across statures, and
	# that constancy is what sells a tall build as big rather than zoomed.
	var helmet := Transform3D(Basis.from_scale(Vector3.ONE * m_head),
			Vector3(0.0, _lift(_HELMET_Y, m_height), 0.0))
	_skeleton.set_bone_pose(_UpperBone.HELMET, helmet)

	var shoulder_y: float = _lift(_SHOULDER_Y, m_height)
	# The shoulders ride girth laterally: the arm roots on the chest wall, so
	# the torso's width pushes it out.
	var shoulder_x: float = _SHOULDER_X * m_girth
	# Seated, the thigh swings forward about the hip to lie flat and the shin
	# turns back under it, so the leg below the knee hangs straight down.
	var hip_y: float = _lift(_LEG_Y, m_height)
	var thigh_swing := Basis(Vector3.RIGHT, PI * 0.5) if seated else Basis.IDENTITY
	var knee_dy: float = _KNEE_DY * m_height
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var leg: int = SkaterBodySkeleton.LEG_BONE_OFFSET \
				+ (_LegBone.LEG_L if i == 0 else _LegBone.LEG_R)
		_skeleton.set_bone_pose(leg, Transform3D(thigh_swing,
				Vector3(side * _LEG_X * m_girth, hip_y, 0.0)))
		_skeleton.set_bone_pose(leg + 1, Transform3D(bulk, Vector3(0.0, _THIGH_DY * m_height, 0.0)))
		_skeleton.set_bone_pose(leg + 2, Transform3D(bulk, Vector3(0.0, knee_dy, 0.0)))
		_skeleton.set_bone_pose(leg + 3, Transform3D(thigh_swing.inverse(),
				Vector3(0.0, knee_dy, 0.0)))
		_skeleton.set_bone_pose(leg + 4, Transform3D(bulk,
				Vector3(0.0, (_SOCK_DY - _KNEE_DY) * m_height, 0.0)))
		_skeleton.set_bone_pose(leg + 5, Transform3D(bulk,
				Vector3(0.0, (_COLLAR_DY - _KNEE_DY) * m_height, 0.0)))
		# The boot itself never scales — a big frame gets a longer leg, not a
		# longer foot — but its seat rides the lengthened shin like the rig's.
		_skeleton.set_bone_pose(leg + 6, Transform3D(_BOOT_ROT,
				Vector3(0.0, (_BOOT_DY - _KNEE_DY) * m_height, _BOOT_DZ)))
	var boot: Vector3 = _skeleton.get_bone_global_pose(
			SkaterBodySkeleton.LEG_BONE_OFFSET + _LegBone.FOOT_L).origin

	# The heel stands on whatever the skates do: the ice, or the bench floor
	# in front of the knees.
	var floor_y: float = boot.y - _BLADE_ICE_M if seated else _ICE_Y
	var heel_fwd: float = boot.z - _BOOT_DZ + _SEATED_HEEL_FWD_M if seated else _HEEL_FWD_M
	_pose_stick(attrs, tape, Vector3(_blade_side * _HEEL_OUT_M, floor_y + _HEEL_LIFT_M,
			heel_fwd))
	_pose_arms(is_left_handed, shoulder_x, shoulder_y, m_girth, m_height)

	# Anchors so far are rig-local (the stick and arm passes wrote theirs the
	# same way); the two body framings join them here.
	_anchors[Focus.SKATES] = Vector3(0.0, boot.y, boot.z)
	_anchors[Focus.HELMET] = helmet.origin
	# The wide shot holds the whole standing figure, so it grows with the build.
	# Crown comes off the posed helmet's own bounds rather than a copy of the
	# builder's radius, which would drift the first time the shell changed. The
	# anchor sits at the midpoint of ice-to-crown so the extent below actually
	# centres what it measures.
	var crown: float = (helmet * SkaterMeshBuilder.shared_helmet_assembly().get_aabb()).end.y
	_anchors[Focus.FULL] = Vector3(0.0, (_ICE_Y + crown) * 0.5, 0.0)
	_extents[Focus.FULL] = Vector2(
			maxf(_FOCUS_EXTENT[Focus.FULL].x, _extents[Focus.STICK].x),
			(crown - _ICE_Y) * 0.5 + 0.06)
	_extents[Focus.HELMET] = _FOCUS_EXTENT[Focus.HELMET] * m_head

	# Seat the whole rig so the runner's contact lands on this node's origin.
	# The boot is the one unscaled part, so its contact does not follow the
	# height scaling on its own — deriving the seat here is what keeps every
	# build standing ON the case floor rather than sunk into it or hovering.
	# Seated, what rests on the origin is the underside of the thighs.
	var contact_y: float = hip_y - _SEAT_UNDER_HIP_M * m_girth if seated \
			else boot.y - _BLADE_ICE_M
	_rig.position.y = -contact_y
	# Publish the anchors in THIS node's space, so a caller framing a piece does
	# not have to know how the rig was seated.
	for i: int in _anchors.size():
		_anchors[i].y -= contact_y


# The stick, then the grips derived from it. Placing the assembly first is what
# lets the hands sit ON the shaft instead of near it.
func _pose_stick(attrs: PlayerAttributes, tape: StickTapeConfig, heel: Vector3) -> void:
	var curve: int = attrs.curve
	var p := StickBladeMeshBuilder.Params.new()
	p.length = GameRules.DEFAULT_BLADE_LENGTH_M
	p.curve_depth = Skater.BLADE_PATTERN_DEPTH[curve]
	p.curve_power = Skater.BLADE_PATTERN_POWER[curve]
	p.face_open_deg = Skater.BLADE_PATTERN_FACE_DEG[curve]
	p.toe_round_m = Skater.BLADE_PATTERN_TOE_ROUND[curve]
	# The blade's curve is baked per hand, and the mannequin's blade side is
	# already the same flag, so the two can never disagree.
	p.curve_sign = -_blade_side
	p.hosel_length = _HOSEL_LEN_M
	p.hosel_angle_deg = _SHAFT_LEAN_DEG
	_blade.mesh = StickBladeMeshBuilder.build(p)
	_blade.transform = Transform3D.IDENTITY

	var tape_p := StickBladeMeshBuilder.Params.new()
	tape_p.length = p.length
	tape_p.curve_depth = p.curve_depth
	tape_p.curve_power = p.curve_power
	tape_p.face_open_deg = p.face_open_deg
	tape_p.toe_round_m = p.toe_round_m
	tape_p.curve_sign = p.curve_sign
	_tape_mesh.mesh = StickBladeMeshBuilder.build_tape(tape_p, tape.span_range()) \
			if tape.has_blade_tape() else null

	var stick_len: float = GameRules.DEFAULT_STICK_LENGTH_M * attrs.stick_len_mult() \
			+ SkaterStickRig.SHAFT_BUTT_EXTEND_M
	var lean: float = deg_to_rad(_SHAFT_LEAN_DEG)
	var axis := Vector3(0.0, sin(lean), cos(lean))
	_shaft.transform = Transform3D(
			Basis.looking_at(-axis, Vector3.UP)
					* Basis.from_scale(Vector3(1.0, 1.0, stick_len)),
			axis * (stick_len * 0.5))
	# Same composition as Skater._update_stick_knob: the cylinder's long axis
	# onto the shaft line, taper toward the blade, capping the butt slightly proud.
	_knob.transform = Transform3D(
			Basis.looking_at(axis, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
			axis * (stick_len - FigureKit.KNOB_HEIGHT_M * 0.5 + 0.01))

	# Seat the assembly: heel on the floor out to the shooting side, yawed so the
	# shaft leans back across the body rather than straight out in front.
	var yaw: float = deg_to_rad(-_blade_side * _STICK_YAW_DEG)
	_stick_root.transform = Transform3D(Basis(Vector3.UP, yaw), heel)

	# Cached for the arm pass, which solves the grips onto this line.
	_shaft_heel = heel
	_shaft_up = _stick_root.basis * axis
	_shaft_len = stick_len

	# Three shots down the stick. The blade lies flat on the ice half a blade
	# ahead of the heel; the grip sits at the butt, where the knob and the top
	# of the wrap are; the whole-stick shot splits the difference.
	var blade_len: float = GameRules.DEFAULT_BLADE_LENGTH_M
	_anchors[Focus.BLADE] = heel \
			+ _stick_root.basis * Vector3(0.0, 0.0, -blade_len * 0.5)
	_anchors[Focus.GRIP] = heel + _shaft_up * (stick_len - FigureKit.KNOB_HEIGHT_M)
	_anchors[Focus.STICK] = (_anchors[Focus.BLADE] + _anchors[Focus.GRIP]) * 0.5
	# What the whole-stick shot has to contain. Measuring it rather than fixing
	# it is what keeps a LONG cut on a tall build from hanging out of frame:
	# the blade runs forward and the shaft climbs, so the two axes are set by
	# different pieces.
	var span: Vector3 = _anchors[Focus.GRIP] - _anchors[Focus.BLADE]
	_extents[Focus.STICK] = Vector2(
			maxf(absf(span.x), blade_len) * 0.5 + 0.10,
			absf(span.y) * 0.5 + 0.10)


# Both arms, shoulder → elbow → fist. The top hand belongs to the shoulder AWAY
# from the blade (a lefty's right hand tops the stick), which is the same rule
# the rig's hand markers use.
#
# The grips are SOLVED onto the shaft rather than fixed on it: the shoulders sit
# ~1.4 m above a blade planted out in front, so the two hands are at very
# different distances from their own shoulders, and pinning both would put one
# hand outside its arm's reach. Sliding each grip to where its arm can hold it
# is what keeps both arms the rig's own length.
func _pose_arms(is_left_handed: bool, shoulder_x: float, shoulder_y: float,
		m_girth: float, m_height: float) -> void:
	var top_side: float = 1.0 if is_left_handed else -1.0
	var upper: float = _UPPER_ARM_M * m_height
	var fore: float = _FOREARM_M * m_height
	var reach_limit: float = (upper + fore) * _GRIP_REACH_FRAC
	var wanted: Array[float] = [
		_shaft_len - _TOP_HAND_DROP_M, _shaft_len * _BOTTOM_HAND_FRAC]
	var grips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var arm_r: float = _ARM_RADIUS * m_girth
	for i: int in 2:
		var bones: Array = _ARM_BONES[i]
		var side: float = top_side if i == 0 else -top_side
		var shoulder := Vector3(side * shoulder_x, shoulder_y, 0.0)
		var hand: Vector3 = _shaft_heel + _shaft_up \
				* _grip_along_shaft(shoulder, wanted[i], reach_limit)
		grips[i] = hand
		var pole := Vector3(_ARM_POLE.x * side, _ARM_POLE.y, _ARM_POLE.z)
		var elbow: Vector3 = _solve_elbow(shoulder, hand, pole, upper, fore)
		var arm := Vector3(arm_r, arm_r, 1.0)
		_skeleton.set_bone_pose(bones[0], SkaterArmPoses.segment_pose(shoulder, elbow, arm))
		_skeleton.set_bone_pose(bones[1], SkaterArmPoses.segment_pose(elbow, hand, arm))
		_skeleton.set_bone_pose(bones[2], SkaterArmPoses.elbow_pose(shoulder, elbow, hand, pole,
				Vector3.ONE * _ELBOW_RADIUS * m_girth))
		_skeleton.set_bone_pose(bones[3], SkaterArmPoses.glove_pose(elbow, hand, _shaft_up,
				deg_to_rad(_WRIST_BREAK_MAX_DEG), Vector3.ONE * _HAND_RADIUS * m_girth))
		var cuff_r: float = _CUFF_RADIUS * m_girth
		_skeleton.set_bone_pose(bones[4], SkaterArmPoses.cuff_pose(elbow, hand,
				Vector3(cuff_r, 1.0, cuff_r), _CUFF_WRIST_OFFSET_M))
	_kit.pose_skin(0 if top_side < 0.0 else 1)

	_anchors[Focus.GLOVES] = (grips[0] + grips[1]) * 0.5
	# Both fists plus the shaft between them — how far apart they sit is solved,
	# not fixed, so the shot that holds them has to be measured too.
	var spread: float = grips[0].distance_to(grips[1]) * 0.5 + _HAND_RADIUS * 2.0
	_extents[Focus.GLOVES] = Vector2(maxf(spread * 0.6, 0.14), spread)


# How far along the shaft a hand can grip: the points within `reach` of the
# shoulder are an interval on the shaft line, so take the one nearest where the
# grip wanted to be. A shaft that never comes within reach falls back to the
# closest it gets, which is the best that arm can do.
func _grip_along_shaft(shoulder: Vector3, wanted: float, reach: float) -> float:
	var to_heel: Vector3 = _shaft_heel - shoulder
	var b: float = _shaft_up.dot(to_heel)
	var disc: float = b * b - to_heel.length_squared() + reach * reach
	var s: float = -b
	if disc > 0.0:
		var root: float = sqrt(disc)
		s = clampf(wanted, -b - root, -b + root)
	return clampf(s, _GRIP_MIN_S_M, _shaft_len - _GRIP_END_MARGIN_M)


# Elbow on the circle of poses that reach `hand` with the given segments,
# picked by a pole hint — the hint is what stops the solver bending into the
# ribs. Segments are the rig's fixed lengths, so both arms come out the same
# length whatever their grip ended up being.
func _solve_elbow(shoulder: Vector3, hand: Vector3, pole: Vector3,
		upper: float, fore: float) -> Vector3:
	var to_hand: Vector3 = hand - shoulder
	var reach: float = to_hand.length()
	if reach < 0.001:
		return shoulder + Vector3.DOWN * upper
	var dir: Vector3 = to_hand / reach
	# Cosine rule: how far along the shoulder→hand line the elbow projects.
	var along: float = clampf(
			(reach * reach + upper * upper - fore * fore) / (2.0 * reach), -upper, upper)
	var offset: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var perp: Vector3 = pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-8:
		perp = Vector3.DOWN - dir * dir.dot(Vector3.DOWN)
	return shoulder + dir * along + perp.normalized() * offset

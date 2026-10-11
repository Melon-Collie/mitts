class_name GaitPose
extends RefCounted

# The legs and trunk one gait pass composes: the locomotion stroke on the stance
# crouch, then every GaitLayer in priority order. Scratch — the coordinator owns
# one and refills it each pass. Leg angles are hip-frame radians; knee values
# are the total fold, negative folding the shin back under the body.
#
# The stroke's pose (solve_stance, seed_legs, seed_trunk) is mirrored by
# NativeSkaterGait.solve; test_native_gait_parity.gd fails if the two drift.

# MESH-NATIVE leg segment spans from Scenes/Skater.tscn — hip pivot to knee
# pivot (LegL → ShinL) and knee pivot to skate sole (ShinL → FootL). The knee
# solve reads only their RATIO, so it is build-independent; every vertical
# length rides `leg_scale`.
const THIGH_LEN: float = 0.31
const SHIN_LEN: float = 0.45
# Forward offset from the shin's end to the FOOT pivot (ShinL → FootL local −Z):
# the boot's centre sits ahead of the ankle, not under it. Folding the shin
# swings this offset from horizontal toward straight DOWN, so any solve that
# holds the boot LEVEL owes the height it costs, or it buries that skate in the
# ice. A boot left to tilt with its shin keeps its sole planted, which is the
# model the stance crouch solves.
const FOOT_FWD: float = 0.10
# Each leg's hip pivot out from the body's centre line, and below the hips'
# origin (LegL / LegR in the scene), metres; the build lengthens the drop, not
# the width.
const HIP_HALF_WIDTH: float = 0.13
const HIP_DROP: float = 0.13
# Stroke engagement over which the feet hand from the ice to the stroke: below
# it the stance is two-footed (rest, glide, the held poses), above it the
# stroke's push and recovery put the feet. A smoothstep band rather than a
# step, so the handoff never pops a leg, and so the stroke's exponential
# release reaches a full plant rather than lingering just short of it.
const PLANT_STROKE_BAND: float = 0.2
# The share of the leg's length an authored offset may carry a leg to: a target
# past it is brought in toward the hip at its own height, so a skate on the ice
# stays on it and the knee keeps a little bend rather than locking. Never below
# what the joint strokes themselves reached.
const REACH_MAX: float = 0.99
# How far short of that limit, metres at leg_scale 1, the target starts easing
# in. Near straight the knee turns fast per centimetre of reach, so a hard stop
# would halt it mid-swing; eased, it slows into the limit instead.
const REACH_EASE_M: float = 0.06
# The depth eases over this band into this much short of the whole reach, so a
# target too deep to stand on keeps room to reach out from under the hip
# (√(2·reach·spare), ~0.12 m).
const DEPTH_EASE_M: float = 0.02
const DEPTH_SPARE_M: float = 0.01

# This build's leg height multiplier (SkaterController.apply_attributes).
var leg_scale: float = 1.0
# +1 when the stick is on the right (+X) side, −1 for a left-handed skater.
var stick_side: float = 1.0

var stance_hip: float = 0.0
var stance_knee: float = 0.0
var stance_shin: float = 0.0
# Whole-body crouch drop, metres, and the share of it the gameplay frame takes
# (0..1): the held-pose layers raise it to their weight, everything else leaves
# it at 0 (Skater.set_skating_crouch_drop).
var drop: float = 0.0
var frame_share: float = 0.0
# Share of the blade contact seat the visible body takes (Skater
# .set_skating_crouch_drop): whole on skates, none for a body on the ice.
var plant: float = 1.0
# How much each foot is held on the ice (Skater.set_leg_contact): fully in the
# two-footed stances, none while the stroke puts the feet (plant_share).
var plant_l: float = 1.0
var plant_r: float = 1.0

var l_pitch: float = 0.0
var l_roll: float = 0.0
var l_knee: float = 0.0
var l_yaw: float = 0.0
var r_pitch: float = 0.0
var r_roll: float = 0.0
var r_knee: float = 0.0
var r_yaw: float = 0.0
# Straightening applied to each knee after its solve, radians toward straight.
var knee_extend_l: float = 0.0
var knee_extend_r: float = 0.0
# How much of each leg's splay and fold its ankle gives back (SkaterLegRig
# .set_ankle_flatten).
var foot_flat_l: float = 0.0
var foot_flat_r: float = 0.0
# How much each blade is laid flat along its length on its edge (the same seam):
# the states authored as where the skates go (SkaterLocomotion.authored) keep
# their blades on the ice.
var foot_level_l: float = 0.0
var foot_level_r: float = 0.0
# Per-blade edge load for the ice VFX, 0..1.
var edge_l: float = 0.0
var edge_r: float = 0.0
# The hips' frame against the ice under them, turned to the hips' heading:
# `lean` the balance lean alone, which turns them about the ice, and `ice` all of
# it, with the lower body's own pitch (SkaterSkatingCoordinator.tilt_hips). The
# states authored as where the skates go are authored on the ice, and the hips
# tip over them.
var lean := Basis.IDENTITY
var ice := Basis.IDENTITY
# Of this pass's authored share, the part whose skates grip the ice (seed_legs).
var _gripping: float = 1.0
# Where the locomotion puts each ankle, and the joints the leg solve reaches it
# with (LegIK, metres from the hip pivot).
var leg_l := LegIK.Leg.new()
var leg_r := LegIK.Leg.new()

# Trunk texture, radians; the coordinator's inertia filter smooths it.
var trunk_pitch: float = 0.0
var trunk_roll: float = 0.0
# Added after that filter: a shake the filter would blunt.
var wobble_pitch: float = 0.0
var wobble_roll: float = 0.0


func leg_length() -> float:
	return leg_scale * (THIGH_LEN + SHIN_LEN)


# The crouch from the hip flex alone: the knee flex that keeps the skate under
# the hip (knee = hip + asin(thigh/shin · sin(hip))) and the bent leg's vertical
# deficit, paid as a whole-body drop so the skates stay on the ice.
func solve_stance(hip: float) -> void:
	stance_hip = hip
	stance_knee = hip + asin(clampf(THIGH_LEN / SHIN_LEN * sin(hip), -1.0, 1.0))
	stance_shin = stance_knee - hip
	drop = leg_scale * (THIGH_LEN * (1.0 - cos(hip)) + SHIN_LEN * (1.0 - cos(stance_shin)))


# The stroke on the solved stance, before any layer shapes the legs: where it
# puts each ankle, and the leg solve that reaches it. The ankle is placed from
# the stance flex both knees carry and the glide's joint-space texture (its sway
# and its light inside knee, the thigh counter-pitched by the small-angle FK
# term Δpitch = −Δknee · L_shin / L_leg so a tucked knee lifts the foot without
# dragging it fore-aft); the authored states lay their offsets on that, and both
# skates go `width` further out from under their hips (GaitLayer.stance_width).
func seed_legs(loco: SkaterLocomotion, yaw_l: float, yaw_r: float, width: float = 0.0) -> void:
	var knee_l: float = -(stance_knee + loco.l_tuck)
	var knee_r: float = -(stance_knee + loco.r_tuck)
	_place(leg_l, stance_hip - (knee_l + stance_knee) * _shin_frac(), yaw_l, loco.l_roll, knee_l)
	_place(leg_r, stance_hip - (knee_r + stance_knee) * _shin_frac(), yaw_r, loco.r_roll, knee_r)
	# Below the shared blend floor a share is a residue of an ease, not a pose.
	var authored: float = loco.authored if loco.authored > 0.001 else 0.0
	foot_level_l = authored
	foot_level_r = authored
	# Of the authored share, the part whose skates grip the ice the body goes
	# over, against the part that scrapes along with it.
	_gripping = clampf(1.0 - loco.sliding / authored, 0.0, 1.0) if authored > 0.0 else 1.0
	_reach(leg_l, loco.l_dx - width, loco.l_dy, loco.l_dz, yaw_l + loco.l_yaw, foot_level_l, -1.0)
	_reach(leg_r, loco.r_dx + width, loco.r_dy, loco.r_dz, yaw_r + loco.r_yaw, foot_level_r, 1.0)
	l_pitch = leg_l.pitch
	l_roll = leg_l.roll
	l_knee = leg_l.knee
	l_yaw = leg_l.yaw
	r_pitch = leg_r.pitch
	r_roll = leg_r.roll
	r_knee = leg_r.knee
	r_yaw = leg_r.yaw
	frame_share = 0.0
	plant = 1.0
	plant_l = plant_share(loco.intensity, loco.edge_floor)
	plant_r = plant_l
	knee_extend_l = 0.0
	knee_extend_r = 0.0
	foot_flat_l = 0.0
	foot_flat_r = 0.0


# What solve_stance and seed_legs set, from the pose NativeSkaterGait.solve
# settled on. The leg solve's own state (leg_l, leg_r) stays in the port.
func load_native_legs(native: RefCounted) -> void:
	var stance: Vector4 = native.get_stance()
	var left: Vector4 = native.get_leg_l()
	var right: Vector4 = native.get_leg_r()
	var seed: Vector4 = native.get_seed()
	stance_hip = stance.x
	stance_knee = stance.y
	stance_shin = stance.z
	drop = stance.w
	l_pitch = left.x
	l_roll = left.y
	l_knee = left.z
	l_yaw = left.w
	r_pitch = right.x
	r_roll = right.y
	r_knee = right.z
	r_yaw = right.w
	foot_level_l = seed.x
	foot_level_r = seed.x
	plant_l = seed.y
	plant_r = seed.y
	frame_share = 0.0
	plant = 1.0
	knee_extend_l = 0.0
	knee_extend_r = 0.0
	foot_flat_l = 0.0
	foot_flat_r = 0.0


# What seed_trunk sets, from the same pose.
func load_native_trunk(native: RefCounted) -> void:
	var trunk: Vector4 = native.get_trunk()
	var seed: Vector4 = native.get_seed()
	drop += trunk.x
	trunk_pitch = trunk.y
	trunk_roll = trunk.z
	wobble_pitch = 0.0
	wobble_roll = 0.0
	edge_l = seed.z
	edge_r = seed.w


# The ankle the stroke's joints put the leg at.
func _place(leg: LegIK.Leg, pitch: float, yaw: float, roll: float, knee: float) -> void:
	leg.pitch = pitch
	leg.yaw = yaw
	leg.roll = roll
	leg.knee = knee
	LegIK.place(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN)


# The authored states' offset on that ankle, then the joints that reach it,
# turned to `yaw`. `level` is the share of the leg authored as where its skate
# goes. That share is on the ice rather than on the hips: its target is turned
# through the hips' tilt against the ice (`ice`). A skate that grips the ice
# also takes the lean's turn about the ice under the body, so it stays where it
# was put while the body goes over it; one that scrapes along with the body (the
# stop) keeps its place under the hips, and the lean only lays it level. Its blade lies flat along its length (foot_level_*), so what it aims
# at the ice is the runner: the ankle comes down by whatever height the edge the
# leg rolls the blade onto takes off the boot, and the leg is solved again —
# until it settles, since the ankle's height moves the edge. `side` is −1 for the left leg.
func _reach(leg: LegIK.Leg, dx: float, dy: float, dz: float, yaw: float, level: float,
		side: float) -> void:
	leg.yaw = yaw
	if level <= 0.0:
		# The joints' own ankle: reachable by construction, so solved as it is.
		leg.x += dx * leg_scale
		leg.y += dy * leg_scale
		leg.z += dz * leg_scale
		LegIK.solve(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN)
		return
	# The reach is limited against the ice, by the authored share.
	var frame: Basis = Basis.IDENTITY.slerp(ice, level)
	var reach: float = _reach_for(frame * Vector3(leg.x, leg.y, leg.z))
	var depth: float = _runner_depth(leg, ice)
	# The hips' origin above the ice: the pivot hangs HIP_DROP below it, the
	# stance ankle below that and the runner below the ankle.
	var above: float = depth - leg.y + HIP_DROP * leg_scale
	var pivot := Vector3(side * HIP_HALF_WIDTH, -HIP_DROP * leg_scale, 0.0)
	var shift: Vector3 = (lean * Vector3(0.0, above, 0.0) - Vector3(0.0, above, 0.0)) * _gripping
	var aim := Vector3(leg.x + dx * leg_scale, leg.y + dy * leg_scale, leg.z + dz * leg_scale)
	var lift: float = 0.0
	for _pass: int in 3:
		var on_ice: Vector3 = aim + Vector3(0.0, lift, 0.0)
		var target: Vector3 = on_ice.lerp(ice.inverse() * (pivot + on_ice - shift) - pivot, level)
		target = frame.inverse() * _within(frame * target, reach)
		leg.x = target.x
		leg.y = target.y
		leg.z = target.z
		LegIK.solve(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN)
		lift = (_runner_depth(leg, ice) - depth) * level


# The reach a leg's targets ease into, from its joints' own ankle `ankle`: never
# so short that ankle sits in the easing, so with no offset the limit moves
# nothing.
func _reach_for(ankle: Vector3) -> float:
	return maxf(REACH_MAX * leg_length(), maxf(
			-ankle.y + (DEPTH_SPARE_M + DEPTH_EASE_M) * leg_scale,
			Vector2(Vector2(ankle.x, ankle.z).length() + REACH_EASE_M * leg_scale, ankle.y).length()))


# A target brought within `reach`, its depth and its distance out from under the
# hip measured against the ice. The depth eases in first, short of the whole
# reach, so a target below what the leg can stand on never takes all of it; then
# its distance out eases into what that depth leaves. Each eases exponentially,
# continuous in value and slope where it starts, so the knee slows into the
# limit rather than halting there, and a target past it lands the skate a little
# short rather than standing the leg straight under the hip.
func _within(target: Vector3, reach: float) -> Vector3:
	var y: float = -_ease_into(-target.y, reach - DEPTH_SPARE_M * leg_scale,
			DEPTH_EASE_M * leg_scale)
	var out: float = Vector2(target.x, target.z).length()
	var keep: float = 1.0
	if out > 0.0:
		keep = _ease_into(out, sqrt(maxf(reach * reach - y * y, 0.0)), REACH_EASE_M * leg_scale) / out
	return Vector3(target.x * keep, y, target.z * keep)


# `value` eased into `limit` over the last `band` before it.
static func _ease_into(value: float, limit: float, band: float) -> float:
	if value <= limit - band:
		return value
	return limit - band * exp((limit - band - value) / band)


# How far the runner's edge hangs below the ankle, measured on the ice (`ice`
# is the hips' frame against it), with the blade laid flat along the leg's
# heading (SkaterLegRig's level give-back): the boot's pivot rides FOOT_FWD
# ahead of the ankle on the shin, and the runner BLADE_ICE_Z below that pivot on
# the boot's own down. Laying the blade flat drops down's share along the
# heading and keeps the rest: its share square to the heading (the edge) and
# its vertical, renormalized.
static func _runner_depth(leg: LegIK.Leg, ice: Basis) -> float:
	var posed: Basis = ice * Basis.from_euler(Vector3(leg.pitch, leg.yaw, leg.roll)) \
			* Basis(Vector3.RIGHT, leg.knee)
	var along: Vector3 = posed * Vector3.FORWARD
	var down: Vector3 = posed * Vector3.DOWN
	var heading: Vector3 = ice * Basis(Vector3.UP, leg.yaw) * Vector3.FORWARD
	var flat: float = sqrt(heading.x * heading.x + heading.z * heading.z)
	var edge: float = 0.0
	if flat > 1e-6:
		edge = (down.x * heading.z - down.z * heading.x) / flat
	var upright: float = -down.y / maxf(sqrt(edge * edge + down.y * down.y), 1e-6)
	return -along.y * FOOT_FWD + upright * SkaterMeshBuilder.BLADE_ICE_Z


# The hip flex whose stance (solve_stance) lets a leg reach `out` metres from
# under the hip at the stance ankle's depth before the reach starts easing in
# (_solve_within), leg_scale 1. The ankle hangs T·cos h + √(S² − T²·sin² h)
# below the hip; set equal to the depth that leaves that reach, that is a
# quadratic in cos h.
static func reach_hip(out: float) -> float:
	var leg: float = REACH_MAX * (THIGH_LEN + SHIN_LEN)
	var depth: float = sqrt(maxf(leg * leg - (out + REACH_EASE_M) * (out + REACH_EASE_M), 1e-6))
	return acos(clampf((depth * depth - SHIN_LEN * SHIN_LEN + THIGH_LEN * THIGH_LEN)
			/ (2.0 * depth * THIGH_LEN), -1.0, 1.0))


# Any layer's straightening, never past straight, with the thigh counter-pitched
# as the stroke's own knee is.
func extend_knees() -> void:
	if knee_extend_l > 0.0:
		var k: float = minf(l_knee + knee_extend_l, 0.0)
		l_pitch -= (k - l_knee) * _shin_frac()
		l_knee = k
	if knee_extend_r > 0.0:
		var k: float = minf(r_knee + knee_extend_r, 0.0)
		r_pitch -= (k - r_knee) * _shin_frac()
		r_knee = k


static func _shin_frac() -> float:
	return SHIN_LEN / (THIGH_LEN + SHIN_LEN)


# The stroke's bob, trunk texture and edge loads, before the trunk layers. The
# edge load is each skate's push scaled by stroke engagement, floored by the
# dug edges of the stop, the tight turn and the carve.
func seed_trunk(loco: SkaterLocomotion) -> void:
	drop += loco.bob
	trunk_pitch = loco.trunk_pitch
	trunk_roll = loco.trunk_roll
	wobble_pitch = 0.0
	wobble_roll = 0.0
	edge_l = clampf(maxf(loco.l_push * loco.intensity, loco.edge_floor), 0.0, 1.0)
	edge_r = clampf(maxf(loco.r_push * loco.intensity, loco.edge_floor), 0.0, 1.0)


# Both feet on the ice while the stroke is idle, and through the dug-edge
# states (the stop and the tight turn, `edge_floor`) however hard it was
# working going in.
static func plant_share(intensity: float, edge_floor: float) -> float:
	return maxf(smoothstep(0.0, 1.0, 1.0 - intensity / PLANT_STROKE_BAND),
			clampf(edge_floor, 0.0, 1.0))


func frame_drop() -> float:
	return drop * frame_share


# `delta` is the render time this pose covers: the plant eases over it.
func publish_legs(skater: Skater, delta: float) -> void:
	skater.set_leg_swing(l_pitch, l_roll, l_knee, r_pitch, r_roll, r_knee, l_yaw, r_yaw)
	skater.set_edge_loads(edge_l, edge_r)
	skater.set_ankle_flatten(foot_flat_l, foot_flat_r, foot_level_l, foot_level_r, ice)
	skater.set_leg_contact(plant_l, plant_r, delta)
	skater.set_skating_crouch_drop(drop, frame_drop(), plant)

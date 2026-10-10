class_name GaitPose
extends RefCounted

# The legs and trunk one gait pass composes: the locomotion stroke on the stance
# crouch, then every GaitLayer in priority order. Scratch — the coordinator owns
# one and refills it each pass. Leg angles are hip-frame radians; knee values
# are the total fold, negative folding the shin back under the body.

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
# puts each ankle, and the leg solve that reaches it.
#
# Knee flex — three layers that read as one leg working. (1) The stance flex,
# the seated base both knees carry. (2) Push extension: the loaded leg
# straightens as it extends back (`release` of the stance flex gone at full
# extension and full stroke intensity) — the power stroke. (3) The locomotion
# state's own folds: recovery tuck, crossover clearance, the glide's inside
# tuck.
#
# Then the fore-aft compensation. The dynamic knee layers exist for LIFT and
# leg-length texture, but each also drags the FOOT fore-aft: uncompensated,
# unfolding mid-push shoves the skate forward against the thigh's backward
# sweep, so measured AT THE SKATE the stride's fast phase comes out FORWARD —
# the inverse of a real push (test_gait_stroke_profile pins the corrected
# profile). The thigh counter-pitches by the small-angle FK term
# (Δpitch = −Δknee · L_shin / L_leg), so the foot tracks the thigh's curve —
# slow recovery, fast push — while the knee keeps its full range.
func seed_legs(loco: SkaterLocomotion, yaw_l: float, yaw_r: float, release: float) -> void:
	var r: float = release * loco.intensity
	var knee_l: float = -(stance_knee * (1.0 - r * loco.l_ext) + loco.l_tuck)
	var knee_r: float = -(stance_knee * (1.0 - r * loco.r_ext) + loco.r_tuck)
	_place(leg_l, stance_hip + loco.l_pitch - (knee_l + stance_knee) * _shin_frac(),
			yaw_l, loco.l_roll, knee_l)
	_place(leg_r, stance_hip + loco.r_pitch - (knee_r + stance_knee) * _shin_frac(),
			yaw_r, loco.r_roll, knee_r)
	# Below the shared blend floor a share is a residue of an ease, not a pose.
	var authored: float = loco.authored if loco.authored > 0.001 else 0.0
	foot_level_l = authored
	foot_level_r = authored
	_reach(leg_l, loco.l_dx, loco.l_dy, loco.l_dz, yaw_l + loco.l_yaw, foot_level_l, -1.0)
	_reach(leg_r, loco.r_dx, loco.r_dy, loco.r_dz, yaw_r + loco.r_yaw, foot_level_r, 1.0)
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
# through the hips' tilt against the ice (`ice`), with the lean's turn about the
# ice under the body, so the skate stays where it was put while the body goes
# over it. Its blade lies flat along its length (foot_level_*), so what it aims
# at the ice is the runner: the ankle comes down by whatever height the edge the
# leg rolls the blade onto takes off the boot, and the leg is solved again —
# twice, since the ankle's height moves the edge. `side` is −1 for the left leg.
func _reach(leg: LegIK.Leg, dx: float, dy: float, dz: float, yaw: float, level: float,
		side: float) -> void:
	var reach: float = maxf(REACH_MAX * leg_length(),
			sqrt(leg.x * leg.x + leg.y * leg.y + leg.z * leg.z))
	leg.yaw = yaw
	if level <= 0.0:
		# The joints' own ankle: reachable by construction, so solved as it is.
		leg.x += dx * leg_scale
		leg.y += dy * leg_scale
		leg.z += dz * leg_scale
		LegIK.solve(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN)
		return
	var depth: float = _runner_depth(leg, ice)
	# The hips' origin above the ice: the pivot hangs HIP_DROP below it, the
	# stance ankle below that and the runner below the ankle.
	var above: float = depth - leg.y + HIP_DROP * leg_scale
	var pivot := Vector3(side * HIP_HALF_WIDTH, -HIP_DROP * leg_scale, 0.0)
	var shift: Vector3 = lean * Vector3(0.0, above, 0.0) - Vector3(0.0, above, 0.0)
	var aim := Vector3(leg.x + dx * leg_scale, leg.y + dy * leg_scale, leg.z + dz * leg_scale)
	var lift: float = 0.0
	for _pass: int in 2:
		var on_ice: Vector3 = aim + Vector3(0.0, lift, 0.0)
		var target: Vector3 = on_ice.lerp(ice.inverse() * (pivot + on_ice - shift) - pivot, level)
		leg.x = target.x
		leg.y = target.y
		leg.z = target.z
		_solve_within(leg, reach, level)
		lift = (_runner_depth(leg, ice) - depth) * level


# The target brought within `reach`. Its depth eases in first, short of the
# whole reach, so a target below what the leg can stand on never takes all of
# it; then its distance out from under the hip eases into what that depth
# leaves. Each eases exponentially, continuous in value and slope where it
# starts, so the knee slows into the limit rather than halting there, and a
# target past it lands the skate a little short rather than standing the leg
# straight under the hip. The easing moves the target by `level`, the authored
# share, so it fades in with that share rather than switching on.
func _solve_within(leg: LegIK.Leg, reach: float, level: float) -> void:
	var y: float = -_ease_into(-leg.y, reach - DEPTH_SPARE_M * leg_scale, DEPTH_EASE_M * leg_scale)
	var keep: float = 1.0
	var out: float = sqrt(leg.x * leg.x + leg.z * leg.z)
	if out > 0.0:
		keep = _ease_into(out, sqrt(maxf(reach * reach - y * y, 0.0)),
				REACH_EASE_M * leg_scale) / out
	leg.y = lerpf(leg.y, y, level)
	leg.x *= lerpf(1.0, keep, level)
	leg.z *= lerpf(1.0, keep, level)
	LegIK.solve(leg, leg_scale * THIGH_LEN, leg_scale * SHIN_LEN)


# `value` eased into `limit` over the last `band` before it.
static func _ease_into(value: float, limit: float, band: float) -> float:
	if value <= limit - band:
		return value
	return limit - band * exp((limit - band - value) / band)


# How far the runner's edge hangs below the ankle, measured on the ice (`ice`
# is the hips' frame against it), with the blade laid flat along its length
# (SkaterLegRig's level give-back): the boot's pivot rides FOOT_FWD ahead of the
# ankle on the shin, and the runner BLADE_ICE_Z below that pivot on the boot's
# own down. Laying the blade flat turns the boot about the level line square to
# its heading, which keeps down's share along that line (the edge) and stands
# the rest of it vertical.
static func _runner_depth(leg: LegIK.Leg, ice: Basis) -> float:
	var posed: Basis = ice * Basis.from_euler(Vector3(leg.pitch, leg.yaw, leg.roll)) \
			* Basis(Vector3.RIGHT, leg.knee)
	var along: Vector3 = posed * Vector3.FORWARD
	var down: Vector3 = posed * Vector3.DOWN
	var heading: float = sqrt(along.x * along.x + along.z * along.z)
	var edge: float = 0.0
	if heading > 1e-6:
		edge = (down.x * along.z - down.z * along.x) / heading
	return -along.y * FOOT_FWD + sqrt(maxf(1.0 - edge * edge, 0.0)) * SkaterMeshBuilder.BLADE_ICE_Z


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
# edge load is the push half-wave (which already carries the crossover
# under-stroke) scaled by stroke engagement, floored by the dug edges of the
# stop and the tight turn.
func seed_trunk(loco: SkaterLocomotion) -> void:
	drop += loco.bob
	trunk_pitch = loco.trunk_pitch
	trunk_roll = loco.trunk_roll
	wobble_pitch = 0.0
	wobble_roll = 0.0
	edge_l = clampf(maxf(maxf(loco.l_ext, loco.l_push) * loco.intensity, loco.edge_floor), 0.0, 1.0)
	edge_r = clampf(maxf(maxf(loco.r_ext, loco.r_push) * loco.intensity, loco.edge_floor), 0.0, 1.0)


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

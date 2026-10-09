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
# Stroke engagement over which the feet hand from the ice to the stroke: below
# it the stance is two-footed (rest, glide, the held poses), above it the
# stroke's push and recovery put the feet. A smoothstep band rather than a
# step, so the handoff never pops a leg, and so the stroke's exponential
# release reaches a full plant rather than lingering just short of it.
const PLANT_STROKE_BAND: float = 0.2

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
# Per-blade edge load for the ice VFX, 0..1.
var edge_l: float = 0.0
var edge_r: float = 0.0

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


# The stroke on the solved stance, before any layer shapes the legs.
func seed_legs(loco: SkaterLocomotion, yaw_l: float, yaw_r: float) -> void:
	l_pitch = stance_hip + loco.l_pitch
	l_roll = loco.l_roll
	r_pitch = stance_hip + loco.r_pitch
	r_roll = loco.r_roll
	l_yaw = yaw_l
	r_yaw = yaw_r
	frame_share = 0.0
	plant = 1.0
	plant_l = 1.0
	plant_r = 1.0
	knee_extend_l = 0.0
	knee_extend_r = 0.0
	foot_flat_l = 0.0
	foot_flat_r = 0.0


# Knee flex — three layers that read as one leg working. (1) The stance flex,
# the seated base both knees carry. (2) Push extension: the loaded leg
# straightens as it extends back (`release` of the stance flex gone at full
# extension and full stroke intensity) — the power stroke. (3) The locomotion
# state's own folds: recovery tuck, crossover clearance, the glide's inside
# tuck. Then any layer's straightening, never past straight.
#
# Then the fore-aft compensation. The dynamic knee layers exist for LIFT and
# leg-length texture, but each also drags the FOOT fore-aft: uncompensated,
# unfolding mid-push shoves the skate forward against the thigh's backward
# sweep, so measured AT THE SKATE the stride's fast phase comes out FORWARD —
# the inverse of a real push (test_gait_stroke_profile pins the corrected
# profile). The thigh counter-pitches by the small-angle FK term
# (Δpitch = −Δknee · L_shin / L_leg), so the foot tracks the thigh's curve —
# slow recovery, fast push — while the knee keeps its full range.
func solve_knees(loco: SkaterLocomotion, release: float) -> void:
	var r: float = release * loco.intensity
	l_knee = -(stance_knee * (1.0 - r * loco.l_ext) + loco.l_tuck)
	r_knee = -(stance_knee * (1.0 - r * loco.r_ext) + loco.r_tuck)
	if knee_extend_l > 0.0:
		l_knee = minf(l_knee + knee_extend_l, 0.0)
	if knee_extend_r > 0.0:
		r_knee = minf(r_knee + knee_extend_r, 0.0)
	var shin_frac: float = SHIN_LEN / (THIGH_LEN + SHIN_LEN)
	l_pitch += -(l_knee + stance_knee) * shin_frac
	r_pitch += -(r_knee + stance_knee) * shin_frac
	plant_l = plant_share(loco.intensity, loco.edge_floor)
	plant_r = plant_l


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
	edge_l = clampf(maxf(loco.l_ext * loco.intensity, loco.edge_floor), 0.0, 1.0)
	edge_r = clampf(maxf(loco.r_ext * loco.intensity, loco.edge_floor), 0.0, 1.0)


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
	skater.set_ankle_flatten(foot_flat_l, foot_flat_r)
	skater.set_leg_contact(plant_l, plant_r, delta)
	skater.set_skating_crouch_drop(drop, frame_drop(), plant)

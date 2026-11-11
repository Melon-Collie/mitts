class_name PredictedState
extends RefCounted

# Per-input snapshot of what the client predicted for the moment immediately
# after applying an input. Keyed by the input's host_timestamp, so when the
# server confirms `last_processed_host_timestamp = T` the client can look up
# its own prediction at T and compare position/velocity directly — true
# divergence, with prediction lead subtracted out.
#
# Mirrors the subset of SkaterNetworkState that the server broadcasts and that
# the client can validate against. Stored in a ring buffer on LocalController.

var host_timestamp: float
var position: Vector3
var velocity: Vector3
var facing: Vector2
var shot_state: int
# True when this entry was RE-RECORDED by a reconcile replay (its values come
# from the replay's manual integration) rather than the live post-move capture.
# Attribution flag for reconcile telemetry: a reconcile whose matched
# prediction was re-recorded fires against the replay's approximations (no
# goalie-body sliding, snapshot-approximated body checks), so a high
# replayed-entry share of reconciles points at replay fidelity, while a high
# live-entry share points at genuine live prediction divergence.
var was_replay_rerecorded: bool = false
# The upper-body frame's yaw (radians), follow-through whip included: the same
# quantity the host broadcasts as `upper_body_rotation_y`, so the threshold
# compares like with like.
var upper_body_rotation_y: float
# What rebuilds the twist state under an adopted frame yaw (see
# SkaterPoseCoordinator.adopt_wire_twist): the whip the follow spring adds over
# the tracked angle, and the spring itself.
var twist_whip: float
var twist_follow: float
var twist_follow_vel: float
# Skater.step_tick_state's state after this input: the replay adopts the ack's
# and steps it forward rather than reading the live, end-of-window values.
var forced_lift_s: float
var stick_check_cooldown_s: float
var blade_lift_blend: float
var commit_lift_blend: float
var check_lead: float
# The carry contact's two reads as this live tick left them (Skater.carry_read_*).
# Recorded live only: the replay plays them back rather than re-deriving them.
var carry_side_smoothed: float
var carry_hop: float
# The hold's fold and grip as this live tick left them (SkaterHoldEase.state),
# played back the same way.
var hold_ease: Vector2
# The blade smoother's dangle velocity after this input: the reconcile seeds the
# smoother from the host's blade at the ack moving at this, since the wire
# carries the blade's place but not its motion.
var blade_dangle_vel: Vector3


func record_tick_state(skater: Skater) -> void:
	forced_lift_s = skater.forced_lift_remaining()
	stick_check_cooldown_s = skater.stick_check_cooldown_remaining()
	blade_lift_blend = skater.get_blade_lift_blend()
	commit_lift_blend = skater.get_commit_lift_blend()
	check_lead = skater.get_check_lead()


func adopt_tick_state(skater: Skater) -> void:
	skater.adopt_tick_state(forced_lift_s, stick_check_cooldown_s,
			blade_lift_blend, commit_lift_blend, check_lead)


# Binary search for the snapshot at exactly target_ts. Returns null when the
# timestamp is outside the buffered range (cap overflow, cleared after teleport,
# session-boundary effects). The history must be append-ordered (chronological
# by host_timestamp). Mirrors StateBufferManager._find_bracket — same shape,
# applied to a client-side history instead of the host's ring buffer.
#
# Epsilon must exceed the wire round-trip error of host_timestamp.
# last_processed_host_timestamp rides the wire as u32 in 0.1ms units
# (Constants.TIME_WIRE_SCALE), so the worst-case round-trip error against the
# f64 the local history stores is 0.05ms — constant regardless of session
# length, which an f32 encoding would not be (its ULP grows with host uptime).
# 1ms is comfortably
# above that and well below the gap between adjacent tick-stamped inputs
# (11.1 ms at 90 Hz), so no risk of off-by-one matches.
const TS_MATCH_EPSILON: float = 1e-3

static func find_at(history: Array[PredictedState], target_ts: float) -> PredictedState:
	if history.is_empty():
		return null
	var lo: int = 0
	var hi: int = history.size() - 1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		var mid_ts: float = history[mid].host_timestamp
		if absf(mid_ts - target_ts) < TS_MATCH_EPSILON:
			return history[mid]
		if mid_ts < target_ts:
			lo = mid + 1
		else:
			hi = mid - 1
	return null

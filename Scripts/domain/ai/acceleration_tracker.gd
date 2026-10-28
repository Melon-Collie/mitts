class_name AIAccelerationTracker
extends RefCounted

# Per-skater smoothed XZ acceleration and heading turn rate for the bot AI.
# Both are global quantities, identical for every bot that reads them, so the
# host computes them once per physics frame and shares them by reference through
# WorldSnapshot.accel_by_peer / heading_omega_by_peer (CLAUDE.md → hot-path
# discipline, "memoize at the seam").

# Low-pass on the raw per-frame velocity diff. The raw diff is noisy at
# the tick rate (a one-tick velocity blip reads as a huge accel); the lerp
# folds it toward the running estimate: a half-life of ln(0.5)/ln(1 − ALPHA)
# ≈ 3 ticks, well inside a 400-600 ms pass window.
const SMOOTH_ALPHA: float = 0.2
# Ceiling on the smoothed magnitude so a collision / reconcile snap can't
# register as a multi-hundred-m/s² spike that poisons receiver lead. It sits
# above a striding turn's centripetal accel (turn_accel × grip), so a hard turn
# still reads in full.
const CLAMP_M_S2: float = 14.0

# Heading turn rate (rad/s): the passer's read of how committed a receiver is
# to a direction (AIPuckLane.receiver_heading_uncertainty_m). Filtered a
# little slower than the accel so it builds and decays over a beat. Below
# OMEGA_MIN_SPEED_M_S the travel direction is noise, so the raw rate reads 0 —
# a near-stationary receiver needs no lead, which is "settled". The clamp stops
# a one-frame velocity flip (collision / reconcile snap) reading as a spin.
const OMEGA_SMOOTH_ALPHA: float = 0.15
const OMEGA_CLAMP_RAD_S: float = 8.0
const OMEGA_MIN_SPEED_M_S: float = 1.0

# peer_id -> smoothed accel (XZ; y always 0).
var accel_by_peer: Dictionary[int, Vector3] = {}

# peer_id -> smoothed heading turn rate (rad/s; the pass EV reads its
# magnitude). Smoothed SIGNED so straight-line direction noise cancels around
# zero while a sustained turn's consistent sign accumulates.
var heading_omega_by_peer: Dictionary[int, float] = {}

var _prev_velocity_by_peer: Dictionary[int, Vector3] = {}
# Reused scratch so the per-frame update allocates nothing: a set of the
# peers seen this frame, and the list of stale peers to prune.
var _seen: Dictionary[int, bool] = {}
var _stale: Array[int] = []


# Advance one physics frame; called once per host frame, never per bot.
# First-sight peers seed prev_velocity from the current value and contribute
# zero accel, so a spawn / rejoin doesn't register as a thrust spike.
func update(skater_states: Dictionary, delta: float) -> void:
	if delta <= 0.0:
		return
	var inv_delta: float = 1.0 / delta
	_seen.clear()
	for peer_id: int in skater_states:
		_seen[peer_id] = true
		var s: SkaterNetworkState = skater_states[peer_id]
		var curr_v: Vector3 = s.velocity
		var prev_v: Vector3 = _prev_velocity_by_peer.get(peer_id, curr_v)
		_prev_velocity_by_peer[peer_id] = curr_v
		var raw_a: Vector3 = (curr_v - prev_v) * inv_delta
		raw_a.y = 0.0
		var smoothed: Vector3 = accel_by_peer.get(peer_id, Vector3.ZERO)
		smoothed = smoothed.lerp(raw_a, SMOOTH_ALPHA)
		var mag: float = sqrt(smoothed.x * smoothed.x + smoothed.z * smoothed.z)
		if mag > CLAMP_M_S2:
			var scale: float = CLAMP_M_S2 / mag
			smoothed.x *= scale
			smoothed.z *= scale
		accel_by_peer[peer_id] = smoothed
		# Signed XZ angle swept prev→curr per second; atan2(cross, dot) covers the
		# full range and sign.
		var raw_omega: float = 0.0
		var prev_speed: float = sqrt(prev_v.x * prev_v.x + prev_v.z * prev_v.z)
		var curr_speed: float = sqrt(curr_v.x * curr_v.x + curr_v.z * curr_v.z)
		if prev_speed > OMEGA_MIN_SPEED_M_S and curr_speed > OMEGA_MIN_SPEED_M_S:
			var dot: float = prev_v.x * curr_v.x + prev_v.z * curr_v.z
			var cross: float = prev_v.x * curr_v.z - prev_v.z * curr_v.x
			raw_omega = atan2(cross, dot) * inv_delta
		var omega: float = lerpf(heading_omega_by_peer.get(peer_id, 0.0),
				raw_omega, OMEGA_SMOOTH_ALPHA)
		omega = clampf(omega, -OMEGA_CLAMP_RAD_S, OMEGA_CLAMP_RAD_S)
		heading_omega_by_peer[peer_id] = omega
	# Prune peers that left the snapshot (rare — swap / disconnect) so the
	# dicts don't grow over a long match. Collect into reused scratch first;
	# erasing during dict iteration is unsafe.
	_stale.clear()
	for peer_id: int in _prev_velocity_by_peer:
		if not _seen.has(peer_id):
			_stale.append(peer_id)
	for peer_id: int in _stale:
		_prev_velocity_by_peer.erase(peer_id)
		accel_by_peer.erase(peer_id)
		heading_omega_by_peer.erase(peer_id)

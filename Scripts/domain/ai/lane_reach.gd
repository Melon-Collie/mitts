class_name AILaneReach

# A defender's stick on a fired puck's path: the one-chance read the carry's
# keep odds use (AIStripOdds.chance_at — set on a point AIStripOdds.SET_S before
# the puck, on the shared momentum-honest arrival clock, graded across its error),
# along the puck's lane, the read AIPuckLane.lane_clear prices a pass the carrier
# fires with and AIRimPass a rim's path along the boards. Unlike a carrier, a pass
# cannot react to him: a stick set on its path stops it. Measured against a
# worst-case interceptor (tests/instruments/ai/test_pass_truth.gd). A leaf —
# GameRules, AIArrival, AIBotMechanics, AISkaterCaps and AIStripOdds only — that
# AIPuckLane and AIRimPass call and never the other way.

# Lane points the reach read samples, evenly along the stretch it reads.
const SAMPLES: int = 8


# One defender's block on an accurate lane (AIPuckLane.lane_clear) and where he makes
# it: his best chance on the lane — a point his stick can be set on before the puck
# passes it, within `reach` (his lane reach, defender_reach, when negative: the
# reach the loose-puck chase plays a pass with) — from where his momentum carries
# him through his read. Returns (block, lane arc-coord of the pick).
#
# The stretch read runs from arc `u0`, which the puck reaches at `t0`, to
# `line_len` at `eff_speed` — a saucer's flight and landed run are stretches of
# it. `read_delay` is when he starts skating to it, from the release
# (AIPuckLane.LANE_WINDUP_READ_DELAY_S: on the windup, before it). He skates and
# reaches on his build `caps` (null: the league build).
static func block(fx: float, fz: float, dirx: float, dirz: float,
		line_len: float, eff_speed: float, px: float, pz: float,
		vx: float, vz: float, caps: AISkaterCaps,
		read_delay: float, u0: float = 0.0, t0: float = 0.0, reach: float = -1.0) -> Vector2:
	if reach < 0.0:
		reach = defender_reach(caps)
	var vmax: float = caps.max_speed if caps != null else GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var span: float = line_len - u0
	if span <= 0.0:
		return Vector2.ZERO
	var t_end: float = t0 + span / eff_speed
	# Out of reach of the whole stretch at any pace he could hold: no read.
	var rx: float = px - fx
	var rz: float = pz - fz
	var along: float = clampf(rx * dirx + rz * dirz, u0, line_len)
	var gx: float = rx - dirx * along
	var gz: float = rz - dirz * along
	var reachable: float = reach + (sqrt(vx * vx + vz * vz) + vmax) * t_end
	if gx * gx + gz * gz > reachable * reachable:
		return Vector2.ZERO
	# Where his momentum has him when he starts to skate to it: (px, pz) is his
	# spot at the release, so a read before it is back along his momentum.
	var from := Vector3(px + vx * read_delay, 0.0, pz + vz * read_delay)
	var vel := Vector3(vx, 0.0, vz)
	# His own crossing first, so a tie is picked where he stands.
	var foot: float = clampf((from.x - fx) * dirx + (from.z - fz) * dirz, u0, line_len)
	var best := Vector2(_block_at(fx, fz, dirx, dirz, foot,
			t0 + (foot - u0) / eff_speed, from, vel, reach, caps, read_delay), foot)
	for k: int in SAMPLES:
		if best.x >= 1.0:
			break
		var u: float = u0 + span * float(k + 1) / float(SAMPLES)
		var at_u: float = _block_at(fx, fz, dirx, dirz, u,
				t0 + (u - u0) / eff_speed, from, vel, reach, caps, read_delay)
		if at_u > best.x:
			best = Vector2(at_u, u)
	return best


# block's read of one lane point `u`, which the puck reaches at `t_puck` from the
# release: his chance at it from `from` (where his read finds him), the time since
# his read being his window.
static func _block_at(fx: float, fz: float, dirx: float, dirz: float,
		u: float, t_puck: float, from: Vector3, vel: Vector3, reach: float,
		caps: AISkaterCaps, read_delay: float) -> float:
	return AIStripOdds.chance_at(from, vel, caps, Vector3(fx + dirx * u, 0.0, fz + dirz * u),
			t_puck - read_delay, AIStripOdds.SET_S, reach)


# One defender's chance at a puck walking `path` (a point every `step_dt` from the
# release) up to `t_end`: his best chance on it, read from `pos` moving `vel`
# `read_delay` from the release (on the windup, before it), within his lane reach.
static func path_block(path: Array[Vector3], step_dt: float, t_end: float, pos: Vector3,
		vel: Vector3, caps: AISkaterCaps, read_delay: float) -> float:
	var reach: float = defender_reach(caps)
	var from: Vector3 = pos + vel * read_delay
	var best: float = 0.0
	for i: int in path.size():
		var t: float = float(i + 1) * step_dt
		if t > t_end:
			break
		best = maxf(best, AIStripOdds.chance_at(from, vel, caps, path[i], t - read_delay,
				AIStripOdds.SET_S, reach))
		if best >= 1.0:
			break
	return best


# A defender's reach for the accurate lane read: his blade span and the outward
# buffer, the same "within a blade" the loose-puck chase plays a puck at.
static func defender_reach(caps: AISkaterCaps) -> float:
	return caps.blade_span + AIBotMechanics.BLADE_REACH_BUFFER_M if caps != null \
			else AIBotMechanics.BLADE_REACH_M

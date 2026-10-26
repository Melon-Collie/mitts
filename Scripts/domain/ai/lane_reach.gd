class_name AILaneReach

# A defender's body on a fired puck's lane, read on the shared momentum-honest
# arrival clock (AIArrival): the accurate lane read AIPuckLane.lane_clear prices
# a pass the carrier fires with. A leaf — GameRules, AIArrival, AIBotMechanics
# and AISkaterCaps only — that AIPuckLane calls and never the other way.

# Lane points the reach read samples, evenly along the stretch it reads.
const SAMPLES: int = 8


# One defender's block on an accurate lane (AIPuckLane.lane_clear) and where he makes
# it: the best lane point his BODY can get within a blade of before the puck
# passes it, on the shared momentum-honest arrival clock (AIArrival.time_to_arrive)
# from where his momentum carries him through his read. The same reach the
# loose-puck chase plays a pass with (AILoosePuckChase.reach_meet_time, stick out),
# so a lane the passer reads open is one the defender cannot take.
#
# Graded by the clock's own calibrated error (AIArrival.ERROR_FRAC, ERROR_FLOOR_S):
# arriving exactly as the puck does is even odds, a full error band early is a
# certain block, a band late none. Returns (block, lane arc-coord of the pick).
#
# The stretch read runs from arc `u0`, which the puck reaches at `t0`, to
# `line_len` at `eff_speed` — a saucer's landed run is the stretch after its
# touch-down. `read_delay` is when he starts skating to it, from the release
# (AIPuckLane.LANE_WINDUP_READ_DELAY_S: on the windup, before it). He skates and
# reaches on his build `caps` (null: the league build).
static func block(fx: float, fz: float, dirx: float, dirz: float,
		line_len: float, eff_speed: float, px: float, pz: float,
		vx: float, vz: float, caps: AISkaterCaps,
		read_delay: float, u0: float = 0.0, t0: float = 0.0) -> Vector2:
	var reach: float = defender_reach(caps)
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
			t0 + (foot - u0) / eff_speed, px, pz, from, vel, reach, caps, read_delay), foot)
	for k: int in SAMPLES:
		if best.x >= 1.0:
			break
		var u: float = u0 + span * float(k + 1) / float(SAMPLES)
		var at_u: float = _block_at(fx, fz, dirx, dirz, u,
				t0 + (u - u0) / eff_speed, px, pz, from, vel, reach, caps, read_delay)
		if at_u > best.x:
			best = Vector2(at_u, u)
	return best


# block's read of one lane point `u`, which the puck reaches at
# `t_puck`. A stick already within a blade of it is in the path whatever the
# timing; otherwise he skates to it from `from` (where his read finds him).
static func _block_at(fx: float, fz: float, dirx: float, dirz: float,
		u: float, t_puck: float, px: float, pz: float, from: Vector3, vel: Vector3,
		reach: float, caps: AISkaterCaps, read_delay: float) -> float:
	var lx: float = fx + dirx * u
	var lz: float = fz + dirz * u
	var window: float = t_puck - read_delay
	if window <= 0.0:
		var nx: float = px - lx
		var nz: float = pz - lz
		return 1.0 if nx * nx + nz * nz <= reach * reach else 0.0
	var ox: float = from.x - lx
	var oz: float = from.z - lz
	var off: float = sqrt(ox * ox + oz * oz)
	if off <= reach:
		return 1.0
	var t_arrive: float = AIArrival.time_to_arrive_caps(from,
			Vector3(lx + ox / off * reach, 0.0, lz + oz / off * reach), vel, caps)
	var err: float = maxf(AIArrival.ERROR_FRAC * t_arrive, AIArrival.ERROR_FLOOR_S)
	return clampf(0.5 + (window - t_arrive) / (2.0 * err), 0.0, 1.0)


# A defender's reach for the accurate lane read: his blade span and the outward
# buffer, the same "within a blade" the loose-puck chase plays a puck at.
static func defender_reach(caps: AISkaterCaps) -> float:
	return caps.blade_span + AIBotMechanics.BLADE_REACH_BUFFER_M if caps != null \
			else AIBotMechanics.BLADE_REACH_M

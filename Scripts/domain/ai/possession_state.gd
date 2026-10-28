class_name AIPossessionState

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# Pure-function team possession state, from puck zone × possession. Roles are
# driven by this state rather than by closest-to-puck.
#
# State table (per team) — symmetric in puck zone × possession; a slow loose
# puck outside our DZ is NEUTRAL, and any loose puck in our DZ is DZONE:
#                  we possess        opp possesses
#   their DZ       OZONE             FORECHECK
#   neutral zone   TRANS_OFFENSE          TRANS_DEFENSE
#   our DZ         BREAKOUT          DZONE
#
# Both splits exist because possession alone doesn't name the job — puck
# position decides it, and collapsing either pair inverts the behavior:
#
#   FORECHECK vs TRANS_DEFENSE — both are "opp possesses, not in our DZ". Deep in
#     their end the job is to forecheck (pin them, force a turnover); once the
#     puck reaches the NZ it's a retreat (TRANS_DEFENSE's Sprinting-Through
#     backcheck). One bucket for both retreats from a sloppy opponent deep in
#     his own zone — the exact opposite of a forecheck.
#   BREAKOUT vs TRANS_OFFENSE — both are "we possess, not in their DZ". Deep in our
#     own end the job is to break out safely (supports present strong-side-wall
#     + weak-side-reverse outlets); in the NZ it's a rush, where TRANS_OFFENSE's
#     stretch OUTLET at the far blue line makes sense. One bucket for both fires
#     that OUTLET from deep in our own zone.
#
# There is deliberately no RETRIEVAL state for a loose puck in our DZ we have
# clearly won: it gates no breakout the team does not already make straight from
# DZONE, and it churns the shape. Read docs/breakout-plan.md Phase A before
# adding one.
#
# Loose-puck handling: possession is sticky. `prev_carrier_team` carries
# over until a new carrier sets it. The 6 Hz brain tick smooths sub-tick
# oscillation (e.g., stick-on-stick contact during a strip) naturally —
# we sample at the brain tick, not every physics tick.

enum State { DZONE, OZONE, TRANS_OFFENSE, TRANS_DEFENSE, NEUTRAL, BREAKOUT, FORECHECK }

# ── Coverage readiness (docs/transition-defense-plan.md §9) ──────────────────
# Scripts/domain/ai/CLAUDE.md → "DZONE is a shape, not a location". A SET
# structure leaves coverage once the readiness read has been false for this many
# consecutive brain ticks (~50 ms; the brain ticks with physics); entering needs
# only one ready tick. There must be NO time-floor fallback beside it.
const COVERAGE_HOLD_TICKS: int = (_PhysicsConstants.PHYSICS_TICK + 10) / 20


# True when the team should be running D-zone COVERAGE rather than the rush /
# recovery shape. `ready` is AIRushRead.coverage_ready (the backcheck is home);
# `unready_ticks` counts consecutive brain ticks it has been FALSE; `was_set` is
# last tick's answer.
static func coverage_read(ready: bool, unready_ticks: int,
		was_set: bool) -> bool:
	if was_set:
		return unready_ticks < COVERAGE_HOLD_TICKS
	return ready


class Result:
	var state: int           # AIPossessionState.State enum value
	var carrier_team: int    # -1 if no carrier ever seen

	static func make(s: int, ct: int) -> Result:
		var r := Result.new()
		r.state = s
		r.carrier_team = ct
		return r

# Below this puck speed, carrier-less puck is treated as NEUTRAL (a
# fresh faceoff drop, basically). High-speed loose pucks (passes in
# flight, stripped-puck contact) keep the prior possession state.
const NEUTRAL_PUCK_SPEED_M_S: float = 1.0


# `own_goal_z` is the z-coordinate of this team's defended net (+ for team 0,
# − for team 1). `team_id_by_peer` maps peer_id -> team_id; unknown peers
# resolve to -1. `prev_carrier_team` is the last-known team in possession, for
# sticky loose-puck handling; -1 if unknown.
static func compute(
		snapshot: WorldSnapshot,
		team_id: int,
		own_goal_z: float,
		team_id_by_peer: Dictionary,
		prev_carrier_team: int) -> Result:
	if snapshot == null or snapshot.puck_state == null:
		return Result.make(State.NEUTRAL, prev_carrier_team)

	var carrier: int = snapshot.puck_state.carrier_peer_id
	var carrier_team: int = prev_carrier_team
	if carrier != -1:
		carrier_team = team_id_by_peer.get(carrier, -1)

	var own_goal_dir: float = signf(own_goal_z)
	var puck_z: float = snapshot.puck_state.position.z
	var in_our_dz: bool = own_goal_dir * puck_z > GameRules.BLUE_LINE_Z
	var in_their_dz: bool = -own_goal_dir * puck_z > GameRules.BLUE_LINE_Z

	# A loose puck in our DZ is ALWAYS defensive priority (strips, dump-ins,
	# faceoff drops). Checked BEFORE the slow-puck NEUTRAL test so a slow loose
	# puck in our DZ still resolves as DZONE.
	if carrier == -1 and in_our_dz:
		return Result.make(State.DZONE, carrier_team)

	if carrier == -1:
		var v: Vector3 = snapshot.puck_state.velocity
		var speed: float = sqrt(v.x * v.x + v.z * v.z)
		if speed < NEUTRAL_PUCK_SPEED_M_S:
			return Result.make(State.NEUTRAL, carrier_team)

	var our_possession: bool = (carrier_team == team_id)

	var state: State
	if our_possession:
		if in_their_dz:
			state = State.OZONE
		elif in_our_dz:
			state = State.BREAKOUT
		else:
			state = State.TRANS_OFFENSE
	else:
		if in_our_dz:
			state = State.DZONE
		elif in_their_dz:
			state = State.FORECHECK
		else:
			state = State.TRANS_DEFENSE

	return Result.make(state, carrier_team)

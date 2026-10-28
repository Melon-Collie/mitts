class_name AIFeedReception

# A feed as its receiver takes it: how hard it arrives in his frame, and what
# that costs him — the settle of a catch, or a bobble he has to win back. A leaf
# (GameRules, the puck rules and AISkaterCaps only).


# The receiver's settle (PuckReceptionRules.settle_time) priced at the any-angle
# catch ceiling, the one every catch gets: bot catches rarely arrive square
# (in the duel harness's reception sweep the blade's mean alignment at the
# catch is 0.2–0.4), and a human's blade is his own. test_bot_mirrors.gd holds
# the three to Puck.
const RECEIVE_ANY_ANGLE_CEILING_M_S: float = 22.0
const SETTLE_CLEAN_LOAD: float = 0.30
const SETTLE_MAX_S: float = 0.40


# Past the bobble line (PuckReceptionRules.bobble_load_at) a catch bobbles
# instead; at the toe or heel the line is lower. test_bot_mirrors.gd holds the
# two to Puck. Measured on bot catches in the duel harness's reception sweep:
# the share whose path meets the blade end-on or past its end (the rest cross
# near the middle, where the blade parks on the line).
const BOBBLE_LOAD: float = 0.67
const BOBBLE_EDGE_SHARE: float = 0.4
const RECEIVE_EDGE_CONTACT_SHARE: float = 0.35
# The bobble's exit off the face (Puck.apply_reception_bobble, through
# PuckCollisionRules.bobble_velocity): Puck's deflect restitution and the
# bobble's two retains. test_bot_mirrors.gd holds the five to Puck.
const DEFLECT_NORMAL_RESTITUTION: float = 0.6
const DEFLECT_NORMAL_RESTITUTION_MIN: float = 0.15
const DEFLECT_SPEED_REF_M_S: float = 30.0
const BOBBLE_TANGENTIAL_RETAIN: float = 0.35
const BOBBLE_PACE_RETAIN: float = 0.45


# Seconds a receiver settles a catch closing at `closing` m/s in his frame.
static func receiver_settle_s(closing: float) -> float:
	var ratio: float = closing / RECEIVE_ANY_ANGLE_CEILING_M_S
	return PuckReceptionRules.settle_time(ratio * ratio, SETTLE_CLEAN_LOAD, SETTLE_MAX_S)


# Odds a catch closing at `closing` m/s bobbles: a middle contact past the bobble
# line, or an edge one past its lower line.
static func receiver_bobble_prob(closing: float) -> float:
	return spill_prob(closing, RECEIVE_EDGE_CONTACT_SHARE)


# Odds a blade meeting a puck closing at `closing` m/s in its frame spills it —
# bobbles it off the face, or past the catch ceiling deflects it — rather than
# holding it: always past the bobble line, and past the edge's lower line for the
# `edge_share` of contacts that meet the blade end-on or past its end.
static func spill_prob(closing: float, edge_share: float) -> float:
	var ratio: float = closing / RECEIVE_ANY_ANGLE_CEILING_M_S
	var catch_load: float = ratio * ratio
	if catch_load >= BOBBLE_LOAD:
		return 1.0
	if catch_load >= PuckReceptionRules.bobble_load_at(1.0, BOBBLE_LOAD, BOBBLE_EDGE_SHARE):
		return edge_share
	return 0.0


# Speed (m/s, his frame) a feed closing at `closing` bobbles off his blade at,
# priced square on: a bot receiver sets up on the line.
static func bobble_exit_speed(closing: float) -> float:
	return PuckCollisionRules.bobble_velocity(Vector3(0.0, 0.0, -closing),
			Vector3(0.0, 0.0, 1.0), DEFLECT_NORMAL_RESTITUTION,
			DEFLECT_NORMAL_RESTITUTION_MIN, DEFLECT_SPEED_REF_M_S,
			BOBBLE_TANGENTIAL_RETAIN, BOBBLE_PACE_RETAIN).length()


# Seconds until a bobbler has a feed closing at `closing` back on his stick: his
# hands are blown open for the full settle, the puck sliding off the face all
# the while, then his blade chases it down at the league blade speed net of the
# puck's own. Until then it is loose, anyone's.
static func bobble_regather_s(closing: float) -> float:
	var exit: float = bobble_exit_speed(closing)
	var gap: float = exit * SETTLE_MAX_S
	return SETTLE_MAX_S + gap / maxf(AISkaterCaps.LEAGUE_BLADE_SPEED_M_S - exit, 0.001)


# Seconds a receiver is tied up taking a feed closing at `closing` m/s, before he
# can act or protect it: the settle of a catch, or the regather of a bobble, by
# the odds of each.
static func reception_hold_s(closing: float) -> float:
	var p_bobble: float = receiver_bobble_prob(closing)
	var settle_s: float = receiver_settle_s(closing)
	if p_bobble <= 0.0:
		return settle_s
	return (1.0 - p_bobble) * settle_s + p_bobble * bobble_regather_s(closing)


# Receiver-frame closing speed of a pass launched at `launch` from `origin` and
# met at `meet` by a receiver moving at `receiver_vel`: the puck's arrival
# velocity after ice friction over the distance, less his.
static func arrival_closing_speed(origin: Vector3, meet: Vector3, launch: float,
		receiver_vel: Vector3) -> float:
	var d := Vector3(meet.x - origin.x, 0.0, meet.z - origin.z)
	var dist: float = d.length()
	if dist < 0.001:
		return 0.0
	var arrival: float = sqrt(maxf(0.0,
			launch * launch - 2.0 * GameRules.PUCK_ICE_DECEL_M_S2 * dist))
	var rel: Vector3 = d * (arrival / dist) - Vector3(receiver_vel.x, 0.0, receiver_vel.z)
	return rel.length()

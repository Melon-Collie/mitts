class_name AIFeedReception

# A feed as its receiver takes it: how hard it arrives in his frame, and what
# that costs him — the settle of a catch, or a bobble he has to win back. A leaf
# (GameRules, the puck rules and AISkaterCaps only).


# The catch ceiling's two terms (PuckReceptionRules.reception_load), the settle
# and the bobble line: Puck's, held there by test_bot_mirrors.gd.
const RECEIVE_DEFLECT_MIN_M_S: float = 22.0
const RECEIVE_ALIGNMENT_BONUS_M_S: float = 8.0
const SETTLE_CLEAN_LOAD: float = 0.30
const SETTLE_MAX_S: float = 0.40
const BOBBLE_LOAD: float = 0.67
const BOBBLE_EDGE_SHARE: float = 0.4
# The catch ceiling of a blade on the feed's line, where a receiver parks it,
# and the pace under which it holds the catch there rather than bobbling it.
const RECEIVE_ON_LINE_CEILING_M_S: float = RECEIVE_DEFLECT_MIN_M_S + RECEIVE_ALIGNMENT_BONUS_M_S
const RECEIVE_HOLD_CEILING_M_S: float = RECEIVE_ON_LINE_CEILING_M_S * sqrt(BOBBLE_LOAD)

# Where a receiver's blade sits against a feed's path when it arrives
# (PuckReceptionRules.path_offset), measured on 107 bot receptions at feed pace
# across the duel harness's reception, rush and odd-man scenarios: 93.5% on the
# line (offset 0), the rest off it at a mean offset of 0.38. A catch is priced
# as one of those two contacts by their shares. A human's blade is his own; it
# is priced as a bot's.
const RECEIVE_OFF_LINE_SHARE: float = 0.065
const RECEIVE_OFF_LINE_OFFSET: float = 0.38

# The bobble's exit off the face (Puck.apply_reception_bobble, through
# PuckCollisionRules.bobble_velocity): Puck's deflect restitution and the
# bobble's two retains. test_bot_mirrors.gd holds the five to Puck.
const DEFLECT_NORMAL_RESTITUTION: float = 0.6
const DEFLECT_NORMAL_RESTITUTION_MIN: float = 0.15
const DEFLECT_SPEED_REF_M_S: float = 30.0
const BOBBLE_TANGENTIAL_RETAIN: float = 0.35
const BOBBLE_PACE_RETAIN: float = 0.45


# The reception load of a catch closing at `closing` m/s with the blade at
# `offset` off the feed's path.
static func _catch_load(closing: float, offset: float) -> float:
	return PuckReceptionRules.reception_load(Vector3(closing, 0.0, 0.0), Vector3.ZERO,
			offset, RECEIVE_DEFLECT_MIN_M_S, RECEIVE_ALIGNMENT_BONUS_M_S)


# Seconds a receiver settles a catch closing at `closing` m/s in his frame: the
# settle of each contact by its share.
static func receiver_settle_s(closing: float) -> float:
	var on_line: float = PuckReceptionRules.settle_time(_catch_load(closing, 0.0),
			SETTLE_CLEAN_LOAD, SETTLE_MAX_S)
	var off_line: float = PuckReceptionRules.settle_time(
			_catch_load(closing, RECEIVE_OFF_LINE_OFFSET), SETTLE_CLEAN_LOAD, SETTLE_MAX_S)
	return (1.0 - RECEIVE_OFF_LINE_SHARE) * on_line + RECEIVE_OFF_LINE_SHARE * off_line


# Odds a catch closing at `closing` m/s bobbles: the share of contacts whose load
# is past their own bobble line.
static func receiver_bobble_prob(closing: float) -> float:
	var p: float = 0.0
	if _catch_load(closing, 0.0) >= PuckReceptionRules.bobble_load_at(
			0.0, BOBBLE_LOAD, BOBBLE_EDGE_SHARE):
		p += 1.0 - RECEIVE_OFF_LINE_SHARE
	if _catch_load(closing, RECEIVE_OFF_LINE_OFFSET) >= PuckReceptionRules.bobble_load_at(
			RECEIVE_OFF_LINE_OFFSET, BOBBLE_LOAD, BOBBLE_EDGE_SHARE):
		p += RECEIVE_OFF_LINE_SHARE
	return p


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

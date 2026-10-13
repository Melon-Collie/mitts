class_name AIPinThreatRead
extends RefCounted

# A carrier on the boards with a committed checker coming square: get out of his
# line before he arrives, and brace only when that can't be done — bracing costs
# the stride and the edges, so it is the last resort, as coached. Read off the
# bot's perceived snapshot, so a drive is seen late by the tier's delay: a fast
# square drive catches it still thinking it has time, and a slow one never does.

enum Answer { ESCAPE, BRACE }

# Bodies touch at two of the bots' body radius (GameRules.OFFSIDE_LINE_SLACK, the
# skater collision radius) plus the pin's contact slack.
const TOUCHING_M: float = 2.0 * GameRules.OFFSIDE_LINE_SLACK + BoardPinRules.PIN_CONTACT_SLACK_M


# Along-wall offset from the checker at contact past which his hit is no longer
# square into the boards (BoardPinRules.BACKSTOP_MIN_INTO_WALL), so no pin.
static func escape_along_m() -> float:
	var c: float = BoardPinRules.BACKSTOP_MIN_INTO_WALL
	return TOUCHING_M * sqrt(1.0 - c * c)


# Seconds until the bodies touch, from the gap and the closing speed along the
# line between them; 0 in contact, INF when he isn't closing.
static func time_to_contact(me_pos: Vector3, me_vel: Vector3, opp_pos: Vector3,
		opp_vel: Vector3) -> float:
	var d := Vector2(me_pos.x - opp_pos.x, me_pos.z - opp_pos.z)
	var dist: float = d.length()
	if dist <= TOUCHING_M:
		return 0.0
	var closing: float = Vector2(opp_vel.x - me_vel.x, opp_vel.z - me_vel.z).dot(d / dist)
	if closing <= 1e-3:
		return INF
	return (dist - TOUCHING_M) / closing


# Which way along the wall to get out: the way we are already going, else the
# side we are already off his line, else +1.
static func escape_sign(offset: float, along_vel: float) -> float:
	if absf(along_vel) > 0.1:
		return signf(along_vel)
	if absf(offset) > 1e-3:
		return signf(offset)
	return 1.0


# Seconds to put escape_along_m() between us and him along the wall, going `dir_sign`
# from our along-wall `offset` (signed, us from him) at `along_vel`, accelerating
# at `accel`. His own steering to stay square is not modelled: following the
# escape is the checker's skill.
static func escape_time(offset: float, along_vel: float, accel: float, dir_sign: float) -> float:
	var need: float = escape_along_m() - offset * dir_sign
	if need <= 0.0:
		return 0.0
	var v: float = along_vel * dir_sign
	if accel <= 0.0:
		return need / v if v > 1e-3 else INF
	return (-v + sqrt(maxf(v * v + 2.0 * accel * need, 0.0))) / accel


# Escape when we get out of his line before he arrives, brace when we don't.
static func answer(time_to_contact_s: float, escape_s: float) -> int:
	return Answer.ESCAPE if escape_s < time_to_contact_s else Answer.BRACE

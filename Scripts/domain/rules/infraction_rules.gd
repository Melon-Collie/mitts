class_name InfractionRules

# Pure rules for hockey infractions that trigger ghost mode.
# Offside: skater in attacking zone before the puck.
# Icing: puck shot from own half past the opponent's goal line, then the hybrid
# race to the end-zone dots (IcingRace runs it).
#
# Team 0 attacks toward -Z (defends +Z goal at z = +GoalLineZ).
# Team 1 attacks toward +Z (defends -Z goal at z = -GoalLineZ).

# Whether the puck is in `team_id`'s attacking zone, given whether it was last
# tick (`was_in`). The blue line belongs to the zone the puck is in (NHL 83.1):
# it enters once wholly past the line's zone-side edge, and stays in while any
# part of it still touches the line. PuckZoneTracker holds `was_in`.
static func puck_in_attacking_zone(puck_z: float, team_id: int, was_in: bool) -> bool:
	var attack_dir: float = -1.0 if team_id == 0 else 1.0
	var depth: float = puck_z * attack_dir
	if was_in:
		return depth + GameRules.PUCK_COLLISION_RADIUS >= GameRules.BLUE_LINE_NEUTRAL_EDGE_Z
	return depth - GameRules.PUCK_COLLISION_RADIUS > GameRules.BLUE_LINE_ZONE_EDGE_Z


# Whether this skater is offside: wholly past the blue line's zone-side edge
# while the puck is not in the zone. The body's trailing edge stands in for the
# trailing skate. Carriers are never offside.
static func is_offside(
		skater_z: float,
		skater_team_id: int,
		puck_in_zone: bool,
		is_carrier: bool) -> bool:
	if is_carrier or puck_in_zone:
		return false
	return not has_tagged_up(skater_z, skater_team_id)

enum IcingCall { NONE, ICING, WAVED_OFF }

# Seconds until a skater's body reaches the end-zone dot line of the end
# `offender_team_id` iced toward; 0 once on or past it. Straight-line along the
# rink's length from the skater's current speed toward that end, at the league
# default thrust and top speed — lateral motion and the skater's own build are
# not modelled.
static func time_to_icing_dot_line(skater_z: float, skater_vz: float, offender_team_id: int) -> float:
	var end_sign: float = -1.0 if offender_team_id == 0 else 1.0
	var remaining: float = GameRules.ICING_FACEOFF_DOT_Z - skater_z * end_sign
	if remaining <= 0.0:
		return 0.0
	var v_max: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	var a: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
	var v: float = minf(skater_vz * end_sign, v_max)
	var t_top: float = (v_max - v) / a
	var d_top: float = (v_max * v_max - v * v) / (2.0 * a)
	if remaining <= d_top:
		return (sqrt(v * v + 2.0 * a * remaining) - v) / a
	return t_top + (remaining - d_top) / v_max


# Whether an icing-team skater is in the race: at the dots already, or skating
# at the end hard enough to be going for the puck.
static func is_racing_icing(skater_z: float, skater_vz: float, offender_team_id: int) -> bool:
	var end_sign: float = -1.0 if offender_team_id == 0 else 1.0
	return skater_z * end_sign >= GameRules.ICING_FACEOFF_DOT_Z \
			or skater_vz * end_sign >= GameRules.ICING_RACE_PURSUIT_SPEED_M_S


# Hybrid icing: the race is decided the instant the first skater reaches the
# end-zone dots (each team's best `time_to_icing_dot_line`). A defender there
# first, or level, is icing; an attacker there first waves it off only if he
# leads by ICING_RACE_CLEAR_MARGIN_S — too close to call is icing. NONE while
# nobody has reached the dots.
static func judge_icing_race(icing_eta: float, defending_eta: float) -> IcingCall:
	if defending_eta <= 0.0:
		return IcingCall.ICING
	if icing_eta > 0.0:
		return IcingCall.NONE
	if defending_eta >= GameRules.ICING_RACE_CLEAR_MARGIN_S:
		return IcingCall.WAVED_OFF
	return IcingCall.ICING

# Whether the skater is onside of their attacking blue line: some part of the
# body still touching the line's zone-side edge, or behind it. Clears a served
# offside (the skate back on the line, NHL 83.3).
static func has_tagged_up(skater_z: float, team_id: int) -> bool:
	var attack_dir: float = -1.0 if team_id == 0 else 1.0
	return skater_z * attack_dir - GameRules.OFFSIDE_LINE_SLACK <= GameRules.BLUE_LINE_ZONE_EDGE_Z

# Whether a puck at `puck_z` sits wholly behind the red line for a team
# attacking toward `attack_dir` (-1 = team 0, +1 = team 1) — the only spot an
# icing can be released from. Touching the paint has gained the line.
static func behind_red_line(puck_z: float, attack_dir: float) -> bool:
	return puck_z * attack_dir < -(GameRules.THICK_LINE_WIDTH_M * 0.5
			+ GameRules.PUCK_COLLISION_RADIUS)


# Detects a potential icing crossing. Returns the offending team id (0 or 1),
# or -1 if no icing condition is present. `last_touch_z` is the PUCK's Z where
# that team last touched it (behind_red_line), and the puck must be wholly past
# the goal line. The caller runs the hybrid race to confirm or wave off.
static func check_icing(
		last_touch_team_id: int,
		last_touch_z: float,
		puck_z: float) -> int:
	if last_touch_team_id != 0 and last_touch_team_id != 1:
		return -1
	var attack_dir: float = -1.0 if last_touch_team_id == 0 else 1.0
	if not behind_red_line(last_touch_z, attack_dir):
		return -1
	if puck_z * attack_dir > GameRules.GOAL_LINE_Z + GameRules.GOAL_LINE_WIDTH_M * 0.5 \
			+ GameRules.PUCK_COLLISION_RADIUS:
		return last_touch_team_id
	return -1

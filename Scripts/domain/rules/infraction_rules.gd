class_name InfractionRules

# Pure rules for hockey infractions that trigger ghost mode.
# Offside: skater in attacking zone before the puck.
# Icing: puck shot from own half past the opponent's goal line, then the hybrid
# race to the end-zone dots (IcingRace runs it).
#
# Team 0 attacks toward -Z (defends +Z goal at z = +GoalLineZ).
# Team 1 attacks toward +Z (defends -Z goal at z = -GoalLineZ).

# Returns true if this skater is offside given their position, team, and the
# puck's position. Carriers are never offside.
static func is_offside(
		skater_z: float,
		skater_team_id: int,
		puck_z: float,
		is_carrier: bool) -> bool:
	if is_carrier:
		return false
	# Skater line is slacked a skate-length past the blue line (OFFSIDE_LINE_SLACK)
	# so a toe over the line isn't offside; the puck line stays at the true blue
	# line — the puck physically crossing it is what clears the zone.
	var line: float = GameRules.BLUE_LINE_Z + GameRules.OFFSIDE_LINE_SLACK
	if skater_team_id == 0:
		# Team 0 attacking zone: z < -BlueLineZ
		return skater_z < -line and puck_z >= -GameRules.BLUE_LINE_Z
	else:
		# Team 1 attacking zone: z > BlueLineZ
		return skater_z > line and puck_z <= GameRules.BLUE_LINE_Z

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

# Returns true when a player who was serving an offside has crossed back into
# the neutral zone or their own zone — i.e. they have "tagged up" at the line.
static func has_tagged_up(skater_z: float, team_id: int) -> bool:
	# Mirrors the slacked entry line so the player tags up as soon as their skate
	# reaches the line — they need only get back to the same edge that ruled them
	# offside, not drag their whole body across. The shared line keeps a dead-band
	# with is_offside so a just-tagged skater isn't instantly re-ghosted.
	var line: float = GameRules.BLUE_LINE_Z + GameRules.OFFSIDE_LINE_SLACK
	if team_id == 0:
		return skater_z >= -line
	else:
		return skater_z <= line

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
	if puck_z * attack_dir > GameRules.GOAL_LINE_Z + GameRules.PUCK_COLLISION_RADIUS:
		return last_touch_team_id
	return -1

extends GutTest

# ── A feed to a man standing near their blue line: does the puck stay in? ──
# The pass search keeps every O-zone feed's catch point
# AICarrierField.OZ_RECEIVE_LINE_BUFFER_M inside the line, on the reasoning that
# a catch gives with the puck and can carry it out. This measures it: a bot
# point man standing still at a depth inside the line, a teammate's feed to him
# (released as a pass, so he reads it as one) from low in the zone, from the
# half-wall, and along the line, at a ladder of paces and aimed at him or off
# him by a little, nobody of theirs near. Through the duel harness's real
# reception (catches, settles, bobbles), each feed is read for whether the puck
# crossed the line within WATCH_S and whether he kept it.
#
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/ai -gselect=test_line_reception

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const PASSER: int = 1
const POINT: int = 2
const FAR_OPP: int = 10
const WATCH_S: float = 1.5
const FEED_M: float = 12.0
# Team 0 attacks -Z: their blue line is at z = -BLUE_LINE_Z, the zone below it.
const LINE_Z: float = -GameRules.BLUE_LINE_Z
const POINT_X: float = -6.0
const DEPTHS_M: Array[float] = [0.5, 1.0, 1.5, 2.0, 2.5]
# Degrees the feed travels off straight out toward the line: 0 from low, 45 off
# the half-wall, 90 along the line.
const ANGLES_DEG: Array[float] = [0.0, 45.0, 90.0]
const PACES_M_S: Array[float] = [10.0, 14.0, 18.0, 22.0]
# Aimed at his body, and off it toward the zone's side and the line's.
const AIM_OFF_M: Array[float] = [0.0, -0.5, 0.5]


# One feed. Returns [crossed the line, kept by him at the end].
func _feed(depth: float, angle_deg: float, pace: float, aim_off: float) -> Array[bool]:
	var at := Vector3(POINT_X, 0.0, LINE_Z - depth)
	var a: float = deg_to_rad(angle_deg)
	# The direction the puck travels: +z is out of the zone, toward the line.
	var travel := Vector3(sin(a), 0.0, cos(a))
	var from: Vector3 = at - travel * FEED_M
	var duel: Object = Duel.new()
	duel.team_size = 3
	var hard: BotSkillProfile = BotSkillProfile.hard()
	duel.add_skater(PASSER, 0, from, hard)
	duel.add_skater(POINT, 0, at, hard)
	duel.add_skater(FAR_OPP, 1, Vector3(8.0, 0.0, LINE_Z - 20.0), hard)
	duel.start(-1, from + travel * 0.6)
	duel._skater(POINT).facing = Vector2(-travel.x, -travel.z)
	var side := Vector3(travel.z, 0.0, -travel.x)
	var aim: Vector3 = at + side * aim_off - (from + travel * 0.6)
	duel.puck_vel = aim.normalized() * pace
	duel.loose_released_by = PASSER
	var crossed: bool = false
	for _i: int in int(WATCH_S / Duel.DT):
		duel.step()
		crossed = crossed or duel.puck_pos.z > LINE_Z
	return [crossed, duel.carrier_id == POINT] as Array[bool]


func test_feeds_to_a_man_at_the_line() -> void:
	gut.p("depth  angle  pace  | out of zone (of %d aims) | kept" % AIM_OFF_M.size())
	for depth: float in DEPTHS_M:
		for angle: float in ANGLES_DEG:
			var row: String = "%4.1f m  %3.0f°  " % [depth, angle]
			for pace: float in PACES_M_S:
				var out: int = 0
				var kept: int = 0
				for off: float in AIM_OFF_M:
					var r: Array[bool] = _feed(depth, angle, pace, off)
					out += 1 if r[0] else 0
					kept += 1 if r[1] else 0
				row += "  %2.0f m/s: out %d kept %d" % [pace, out, kept]
			gut.p(row)
	assert_true(true)

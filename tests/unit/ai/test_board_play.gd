extends GutTest

# Play along the boards, measured on the whole stack (duel harness): does a
# clear fired up the wall out of THEIR zone get kept in at the line? A single
# dispatch can say where a D wants to stand; only a run says whether the body
# gets there before the puck does.
#
# Team 0 attacks -z. Their clear starts low on the +x wall and is fired up it,
# loose, with our forecheck in its 1-2-2 (or 3v3 1-1-1) shape and their
# skaters too deep to collect it first — so the line is the only place it can
# be stopped.
#
# On Hard the chase election alone gets there: the line man is the soonest
# interceptor and reacts in 50 ms. The slower tiers are where the station read
# (AIRoleDefenseman.wall_rim_keepin) earns its keep — their chase reaction
# delay holds the elected chaser still while the rim runs, and only a body
# already moving to the crossing makes it.

const Harness := preload("res://tests/unit/ai/duel_harness.gd")

const RUN_S: float = 2.5
const CLEAR_FROM := Vector3(11.8, 0.0, -22.0)
const CLEAR_VEL := Vector3(0.0, 0.0, 11.0)


class Outcome:
	var kept_in: bool = false      # one of ours collected it inside their zone
	var escaped: bool = false      # it crossed their blue line uncollected
	var collector: int = -1


func _run_clear(h) -> Outcome:
	h.start(-1, CLEAR_FROM)
	h.puck_vel = CLEAR_VEL
	var o := Outcome.new()
	for _i: int in int(RUN_S / Harness.DT):
		h.step()
		var c: int = h.carrier()
		if c != -1 and h.team_map[c] == 0 and h.puck_pos.z < -GameRules.BLUE_LINE_Z:
			o.kept_in = true
			o.collector = c
			return o
		if c == -1 and h.puck_pos.z > -GameRules.BLUE_LINE_Z:
			o.escaped = true
			return o
		if c != -1 and h.team_map[c] == 1:
			return o
	return o


func _run_5v5(profile: BotSkillProfile) -> Outcome:
	var h = Harness.new()
	h.team_size = 5
	h.positions = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 11: 0, 12: 1, 13: 2, 14: 3, 15: 4}
	h.add_skater(1, 0, Vector3(-2.0, 0.0, -21.0), profile)     # F1, on their D
	h.add_skater(2, 0, Vector3(-8.0, 0.0, -14.0), profile)     # LW
	h.add_skater(3, 0, Vector3(1.0, 0.0, -11.0), profile)      # RW, high middle
	h.add_skater(4, 0, Vector3(-5.0, 0.0, -8.29), profile)     # LD on the line
	h.add_skater(5, 0, Vector3(6.7, 0.0, -8.29), profile)      # RD on the line
	h.add_skater(11, 1, Vector3(-4.0, 0.0, -25.0))
	h.add_skater(12, 1, Vector3(-9.0, 0.0, -20.0))
	h.add_skater(13, 1, Vector3(0.0, 0.0, -18.0))
	h.add_skater(14, 1, Vector3(-2.0, 0.0, -26.0))
	h.add_skater(15, 1, Vector3(3.0, 0.0, -25.5))
	var o: Outcome = _run_clear(h)
	gut.p("  5v5: kept in %s by %d | escaped %s" % [o.kept_in, o.collector, o.escaped])
	return o


func _run_3v3(profile: BotSkillProfile) -> Outcome:
	var h = Harness.new()
	h.add_skater(1, 0, Vector3(-2.0, 0.0, -21.0), profile)     # F1, on their D
	h.add_skater(2, 0, Vector3(-3.0, 0.0, -17.0), profile)     # F2, mid read
	h.add_skater(3, 0, Vector3(9.0, 0.0, -7.6), profile)       # F3, his line stand
	h.add_skater(11, 1, Vector3(-4.0, 0.0, -25.0))
	h.add_skater(12, 1, Vector3(-9.0, 0.0, -20.0))
	h.add_skater(13, 1, Vector3(0.0, 0.0, -24.0))
	var o: Outcome = _run_clear(h)
	gut.p("  3v3: kept in %s by %d | escaped %s" % [o.kept_in, o.collector, o.escaped])
	return o


func test_5v5_line_pair_keeps_a_wall_clear_in_hard() -> void:
	assert_true(_run_5v5(BotSkillProfile.hard()).kept_in)


func test_5v5_line_pair_keeps_a_wall_clear_in_normal() -> void:
	assert_true(_run_5v5(BotSkillProfile.normal()).kept_in)


func test_5v5_line_pair_keeps_a_wall_clear_in_easy() -> void:
	assert_true(_run_5v5(BotSkillProfile.easy()).kept_in)


func test_3v3_high_forward_keeps_a_wall_clear_in_hard() -> void:
	assert_true(_run_3v3(BotSkillProfile.hard()).kept_in)


func test_3v3_high_forward_keeps_a_wall_clear_in_normal() -> void:
	assert_true(_run_3v3(BotSkillProfile.normal()).kept_in)


func test_3v3_high_forward_keeps_a_wall_clear_in_easy() -> void:
	assert_true(_run_3v3(BotSkillProfile.easy()).kept_in)


# ── The pinch and the rotation behind it (5v5) ───────────────────────────────
# Their winger holds the puck on the +x half-wall a few metres inside their
# line, going nowhere — the bottled carrier a strong-side D pinches on. The
# whole exchange should happen: the RD steps down the wall onto him, a forward
# rotates up to the RD's point, and the LD slides to the middle of the line.
# The pinch waits on its cover (a forward able to take the point in time), and
# F2_WEAK starts on the weak-side breakout lane, so the exchange runs ~4 s: the
# point is covered at ~4.0 s.
func test_5v5_strong_d_pinches_and_the_rotation_covers_him() -> void:
	var h = Harness.new()
	h.team_size = 5
	h.positions = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 11: 0, 12: 1, 13: 2, 14: 3, 15: 4}
	h.add_skater(1, 0, Vector3(4.0, 0.0, -20.0))      # C, forechecking low
	h.add_skater(2, 0, Vector3(-6.0, 0.0, -15.0))     # LW
	h.add_skater(3, 0, Vector3(1.0, 0.0, -11.0))      # RW, middle lane
	h.add_skater(4, 0, Vector3(-5.0, 0.0, -8.29))     # LD
	h.add_skater(5, 0, Vector3(6.7, 0.0, -8.29))      # RD
	var spot := Vector3(11.5, 0.0, -12.5)
	var hold: Array[Vector3] = [spot, spot + Vector3(0.0, 0.0, -0.3)]
	h.add_scripted_attacker(11, 1, hold, 0.3)
	h.add_skater(12, 1, Vector3(-9.0, 0.0, -20.0))
	h.add_skater(13, 1, Vector3(0.0, 0.0, -22.0))
	h.add_skater(14, 1, Vector3(-3.0, 0.0, -25.0))
	h.add_skater(15, 1, Vector3(4.0, 0.0, -25.5))
	h.start(11)
	var rd_deepest: float = 0.0
	var point_covered: bool = false
	var ld_middle: bool = false
	var strong_point := Vector3(AIRoleDefenseman.DP_STRONG_LANE_X_M, 0.0,
			-(GameRules.BLUE_LINE_Z + AIRoleDefenseman.DP_LINE_INSET_M))
	for _i: int in int(4.5 / Harness.DT):
		h.step()
		var rd_depth: float = -h.skater_pos(5).z - GameRules.BLUE_LINE_Z
		rd_deepest = maxf(rd_deepest, rd_depth)
		if rd_depth > 3.0:
			for f: int in [1, 2, 3]:
				if h.skater_pos(f).distance_to(strong_point) < 2.0:
					point_covered = true
			if absf(h.skater_pos(4).x) < 2.0 \
					and h.skater_pos(4).z > -(GameRules.BLUE_LINE_Z + 3.0):
				ld_middle = true
	gut.p("  RD deepest %.1f m inside | point covered %s | LD middle %s"
			% [rd_deepest, point_covered, ld_middle])
	assert_gt(rd_deepest, 3.0, "the strong-side D pinches down the wall")
	assert_true(point_covered, "a forward rotates up to his point")
	assert_true(ld_middle, "the weak D slides to the middle of the line")

extends GutTest

# BodyBalanceRules — whether a hit knocks a man off his skates. Properties hold
# the pendulum's shape whatever the tuning; the closing-speed grid (what a
# committed check needs to floor him, by how he stands and where it comes from)
# is a snapshot, so a tuning change is a reviewed table diff.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/body_balance.txt"
const FACING := Vector2(0.0, 1.0)
const HEAVY_W: float = 1.28
const LIGHT_W: float = 0.79
const TRANSFER: float = 0.65
const P := BodyBalanceRules.Posture

var _cfg: BodyBalanceRules.Config


func before_each() -> void:
	_cfg = BodyBalanceRules.Config.new()


# The unit Δv driving him away from a hitter `deg` off his facing (0 = in front).
func _from(deg: float) -> Vector2:
	var to_hitter: Vector2 = FACING.rotated(deg_to_rad(deg))
	return -to_hitter


func test_along_the_blades_only_a_share_tips_him_and_across_all_of_it() -> void:
	assert_almost_eq(BodyBalanceRules.tip_dv(_from(0.0) * 2.0, FACING, _cfg), 2.0 * _cfg.along_share, 1e-5)
	assert_almost_eq(BodyBalanceRules.tip_dv(_from(180.0) * 2.0, FACING, _cfg), 2.0 * _cfg.along_share, 1e-5)
	assert_almost_eq(BodyBalanceRules.tip_dv(_from(90.0) * 2.0, FACING, _cfg), 2.0, 1e-5)


func test_the_tip_grows_as_the_hit_swings_across_his_blades() -> void:
	var prev: float = 0.0
	for deg: int in range(0, 91, 5):
		var tip: float = BodyBalanceRules.tip_dv(_from(deg), FACING, _cfg)
		assert_gte(tip, prev - 1e-6, "%d°" % deg)
		prev = tip


func test_he_rides_a_hit_he_sees_best() -> void:
	assert_almost_eq(BodyBalanceRules.sight(_from(0.0), FACING, _cfg), 1.0, 1e-5)
	assert_almost_eq(BodyBalanceRules.sight(_from(180.0), FACING, _cfg), _cfg.sight_behind, 1e-5)
	var prev: float = INF
	for deg: int in range(0, 181, 10):
		var s: float = BodyBalanceRules.sight(_from(deg), FACING, _cfg)
		assert_lte(s, prev + 1e-6, "%d°" % deg)
		prev = s


func test_the_stance_holds_more_and_a_shot_less() -> void:
	var dv: Vector2 = _from(90.0)
	var upright: float = BodyBalanceRules.budget(dv, FACING, P.UPRIGHT, 1.0, _cfg)
	assert_gt(BodyBalanceRules.budget(dv, FACING, P.STANCE, 1.0, _cfg), upright)
	assert_lt(BodyBalanceRules.budget(dv, FACING, P.VULNERABLE, 1.0, _cfg), upright)


func test_a_taller_man_tips_sooner() -> void:
	var dv: Vector2 = _from(90.0)
	assert_lt(BodyBalanceRules.budget(dv, FACING, P.UPRIGHT, 1.1, _cfg),
			BodyBalanceRules.budget(dv, FACING, P.UPRIGHT, 1.0, _cfg))


func test_the_overshoot_scales_with_the_hit() -> void:
	var one: float = BodyBalanceRules.overshoot(_from(45.0), FACING, P.UPRIGHT, 1.0, _cfg)
	var three: float = BodyBalanceRules.overshoot(_from(45.0) * 3.0, FACING, P.UPRIGHT, 1.0, _cfg)
	assert_almost_eq(three, 3.0 * one, 1e-5)


func test_a_vulnerable_posture_wins_over_the_stance() -> void:
	assert_eq(BodyBalanceRules.posture_of(true, true), P.VULNERABLE)
	assert_eq(BodyBalanceRules.posture_of(true, false), P.STANCE)
	assert_eq(BodyBalanceRules.posture_of(false, false), P.UPRIGHT)


# Closing speed (m/s) a timed check (CheckDriveRules) needs to knock him down:
# where the closing share and the drive's kick together reach his balance. Both
# rise with the closing speed, so it is bisected.
func _knockdown_closing(posture: P, deg: float, checker_w: float, victim_w: float) -> float:
	var per_unit: float = BodyBalanceRules.overshoot(_from(deg), FACING, posture, 1.0, _cfg)
	var dv_needed: float = 1.0 / per_unit
	var kick: float = CheckDriveRules.kick_dv(GameRules.DEFAULT_SKATER_THRUST_M_S2,
			checker_w, victim_w)
	var lo: float = 0.0
	var hi: float = 100.0
	for _i: int in 40:
		var mid: float = 0.5 * (lo + hi)
		var dv: float = SkaterCollisionRules.victim_kick(mid, checker_w, victim_w, TRANSFER) \
				+ kick * CheckDriveRules.impact_share(mid)
		if dv < dv_needed:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


func test_the_knockdown_grid() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	var postures: Dictionary = {"upright": P.UPRIGHT, "stance": P.STANCE, "vulnerable": P.VULNERABLE}
	var angles: Dictionary = {"front": 0.0, "45": 45.0, "side": 90.0, "behind": 180.0}
	var builds: Dictionary = {"equal": [1.0, 1.0], "heavy_on_light": [HEAVY_W, LIGHT_W],
			"light_on_heavy": [LIGHT_W, HEAVY_W]}
	for posture: String in postures:
		for angle: String in angles:
			for build: String in builds:
				var w: Array = builds[build]
				snap.record("%s %s %s" % [posture, angle, build], _knockdown_closing(
						postures[posture], angles[angle], w[0], w[1]))
	snap.verify(self)


# The doctrine's read of the grid: a square, upright man rides any one-sided
# check below top speed; a side hit floors him well inside it.
func test_square_and_upright_he_rides_a_full_speed_check() -> void:
	var top: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
	assert_gt(_knockdown_closing(P.UPRIGHT, 0.0, 1.0, 1.0), top)
	assert_lt(_knockdown_closing(P.UPRIGHT, 90.0, 1.0, 1.0), top)


func test_a_checker_leans_into_what_drives_him_back_only() -> void:
	var back: Vector2 = -FACING * 3.0
	assert_almost_eq(BodyBalanceRules.leaned_into(back, FACING, 0.0, _cfg).length(),
			3.0 * _cfg.checker_front_share, 1e-5)
	var side := Vector2(3.0, 0.0)
	assert_eq(BodyBalanceRules.leaned_into(side, FACING, 0.0, _cfg), side, "across him, all of it")
	var forward: Vector2 = FACING * 3.0
	assert_eq(BodyBalanceRules.leaned_into(forward, FACING, 0.0, _cfg), forward)


func test_the_faster_he_arrives_the_more_of_his_own_hit_he_takes() -> void:
	var back: Vector2 = -FACING * 3.0
	var prev: float = 0.0
	for i: int in 25:
		var felt: float = BodyBalanceRules.leaned_into(back, FACING, 0.5 * i, _cfg).length()
		assert_gte(felt, prev, "never less for arriving faster")
		assert_lte(felt, 3.0 + 1e-6, "never more than it was")
		prev = felt
	assert_almost_eq(BodyBalanceRules.leaned_into(back, FACING, _cfg.checker_control_speed,
			_cfg).length(), 3.0 * _cfg.checker_front_share, 1e-5, "under control, the lean")
	assert_almost_eq(BodyBalanceRules.leaned_into(back, FACING, _cfg.checker_wild_speed,
			_cfg).length(), 3.0, 1e-5, "at full pace, all of it")


func test_the_approach_is_his_own_speed_into_the_hit() -> void:
	var dv := Vector2(0.0, -2.0)
	assert_almost_eq(BodyBalanceRules.approach_speed(Vector2(0.0, 4.0), dv), 6.0, 1e-5,
			"skating 6 into it, knocked back to 4")
	assert_almost_eq(BodyBalanceRules.approach_speed(dv, dv), 0.0, 1e-5, "set, then driven back")
	assert_eq(BodyBalanceRules.approach_speed(Vector2(0.0, -5.0), dv), 0.0, "backing away from it")


# The checker's own reading of his hit, square on (docs/hit-outcomes-plan.md,
# Phases 3 and 5): the closing speed, how much of it is his own, both builds.
func test_the_checkers_table() -> void:
	var snap := Snapshot.new("res://tests/unit/rules/snapshots/checker_share.txt")
	var rows: Dictionary = {"full speed on a stationary equal man": [10.0, 10.0, 1.0, 1.0],
			"controlled 4 m/s on a stationary equal man": [4.0, 4.0, 1.0, 1.0],
			"stand-up 8 m/s equal": [8.0, 0.0, 1.0, 1.0],
			"light checker into heavy, full speed": [10.0, 10.0, LIGHT_W, HEAVY_W],
			"two checkers head-on 16 m/s": [16.0, 8.0, 1.0, 1.0]}
	for row: String in rows:
		var r: Array = rows[row]
		var kick_on_checker: float = SkaterCollisionRules.victim_kick(r[0], r[3], r[2], TRANSFER)
		snap.record(row, BodyBalanceRules.leaned_into(-FACING * kick_on_checker, FACING,
				r[1], _cfg).length())
	snap.verify(self)

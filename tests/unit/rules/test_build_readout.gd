extends GutTest

# The player screen's stat panel reads these numbers, so they have to say what
# the attribute model does: neutral reads 1.0 everywhere, each stat points the
# way its name says, and each dial is credited with exactly the stats it moves.

const S := BuildReadout.Stat
const D := BuildReadout.Dial


func _gear(profile: int, curve: int, flex: int, length: int) -> PlayerAttributes:
	return PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, 0, profile, curve, flex, length)


func test_tables_cover_every_stat() -> void:
	assert_eq(BuildReadout.NAME_KEYS.size(), BuildReadout.STAT_COUNT)
	assert_eq(BuildReadout.GROUP_OF.size(), BuildReadout.STAT_COUNT)
	assert_eq(S.size(), BuildReadout.STAT_COUNT)


func test_neutral_reads_one_everywhere() -> void:
	var n := PlayerAttributes.neutral()
	for s: int in BuildReadout.STAT_COUNT:
		assert_almost_eq(BuildReadout.ratio(n, s), 1.0, 0.0001, str(BuildReadout.NAME_KEYS[s]))


func test_each_stat_points_the_way_its_name_says() -> void:
	var b := PlayerAttributes.GEAR_BALANCED
	assert_gt(BuildReadout.ratio(_gear(2, b, b, b), S.TOP_SPEED), 1.0, "power skates are faster")
	assert_gt(BuildReadout.ratio(_gear(2, b, b, b), S.COAST), 1.0, "power skates coast further")
	assert_lt(BuildReadout.ratio(_gear(2, b, b, b), S.BACKWARD), 1.0, "power skates go back worse")
	assert_gt(BuildReadout.ratio(_gear(0, b, b, b), S.AGILITY), 1.0, "shifty skates turn sharper")
	assert_gt(BuildReadout.ratio(_gear(b, b, 2, b), S.SLAPSHOT), 1.0, "a stiff stick hits harder")
	assert_lt(BuildReadout.ratio(_gear(b, b, 2, b), S.SLAPPER_RELEASE), 1.0,
			"and loads slower — release is the inverse of wind-up")
	assert_gt(BuildReadout.ratio(_gear(b, 0, b, b), S.BACKHAND), 1.0, "M88 is the backhand blade")
	assert_gt(BuildReadout.ratio(_gear(b, 0, b, b), S.PASS_CATCH), 1.0)
	assert_gt(BuildReadout.ratio(_gear(b, b, b, 2), S.REACH), 1.0, "a long stick reaches")
	var heavy := PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM,
			PlayerAttributes.weight_max(PlayerAttributes.HEIGHT_MEDIUM))
	assert_gt(BuildReadout.ratio(heavy, S.MASS), 1.0)
	assert_lt(BuildReadout.ratio(heavy, S.AGILITY), 1.0, "heavy turns wide")


func test_each_gear_dial_is_credited_with_exactly_what_it_moves() -> void:
	assert_eq(BuildReadout.moved_by([D.PROFILE]), [S.TOP_SPEED, S.FIRST_STEP, S.AGILITY,
			S.CROSSOVER, S.BACKWARD, S.COAST])
	assert_eq(BuildReadout.moved_by([D.CURVE]), [S.SLAPSHOT, S.BACKHAND, S.PASS_CATCH])
	assert_eq(BuildReadout.moved_by([D.FLEX]), [S.SLAPSHOT, S.SLAPPER_RELEASE])
	assert_eq(BuildReadout.moved_by([D.LENGTH]), [S.REACH])


# Size never buys top speed (Scripts/domain/state/CLAUDE.md): neither body dial
# may light up the top-speed row.
func test_the_body_never_moves_top_speed() -> void:
	var body: Array[int] = BuildReadout.moved_by([D.HEIGHT, D.WEIGHT])
	assert_false(body.has(S.TOP_SPEED))
	assert_true(body.has(S.MASS))
	assert_true(body.has(S.FIRST_STEP))
	assert_true(body.has(S.WRIST_SHOT), "height carries the shot ceiling")

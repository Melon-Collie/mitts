extends GutTest

# Reachable-set (pursuit-evasion) possession safety. Whether a defender threatens
# the puck is "can he get a stick to it given his momentum + reaction," not raw
# proximity. These pin the behaviours the old proximity model couldn't express:
# a hard charger is evadable (he overshoots), a contained/jockeying defender can't
# strip a careful carrier, a stick on the puck is a real threat, and handling
# (how far the carrier holds the puck off his body) threads tighter seams. The
# safety values the current calibration gives at the reference looks are the
# snapshot, test_reach_safety_calibration_snapshot.

const Snapshot := preload("res://tests/snapshot.gd")
const SNAPSHOT_PATH := "res://tests/unit/rules/snapshots/reach_safety.txt"
const HANDLE: float = 0.9   # base puck-protect reach (Hands scales this)
# Float noise in a quantity that should be flat.
const SLACK: float = 1e-4


# Carrier's evadability [0,1]: safety at the best seam in his handling envelope.
func _evade(car: Vector3, car_v: Vector3, opps: Array[Vector3],
		vels: Array[Vector3], handle: float = HANDLE) -> float:
	var seam: Vector3 = AICarrySpace.best_evade_point(car, car_v, opps, vels, handle)
	var clear: float = AICarrySpace.reach_clearance(
			seam, AICarrySpace.EVADE_HORIZON_S, opps, vels)
	return AICarrySpace.clearance_to_safety(clear)


func test_no_defenders_is_fully_safe() -> void:
	assert_eq(_evade(Vector3.ZERO, Vector3(5, 0, 0), [], []), 1.0)


func _caps(max_accel: float, blade_span: float) -> AISkaterCaps:
	var c := AISkaterCaps.new()
	c.max_accel = max_accel
	c.blade_span = blade_span
	return c


func test_bigger_more_agile_defender_covers_more() -> void:
	# Same defender geometry, but its real build sets its reach: Agility (max_accel)
	# is how far it can lunge off its line, Size (blade_span) how far its stick
	# touches. A big, agile defender reaches further → LESS clearance for the same
	# puck point; a small, sluggish one reaches less → more room. Empty caps sits
	# between them at the league default.
	var opps: Array[Vector3] = [Vector3(2.0, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var t: float = AICarrySpace.EVADE_HORIZON_S
	var league: float = AICarrySpace.reach_clearance(Vector3.ZERO, t, opps, vels)
	var vs_big: float = AICarrySpace.reach_clearance(
			Vector3.ZERO, t, opps, vels, [_caps(16.0, 2.0)])
	var vs_small: float = AICarrySpace.reach_clearance(
			Vector3.ZERO, t, opps, vels, [_caps(6.0, 1.2)])
	assert_lt(vs_big, league, "a bigger, more agile defender reaches further → less clearance")
	assert_gt(vs_small, league, "a smaller, slower defender reaches less → more room")


# A defender charging at the carrier's lane at `speed` from `start`.
func _charge(start: Vector3, speed: float) -> float:
	var opps: Array[Vector3] = [start]
	var vels: Array[Vector3] = [(Vector3(1.0, 0, 0) - start).normalized() * speed]
	return _evade(Vector3.ZERO, Vector3(5, 0, 0), opps, vels)


func test_momentum_overshoot_raises_evadability() -> void:
	# Over charge speed, evadability is a valley: closing first brings his reach
	# onto the puck, then his momentum carries it past where the carrier was. Past
	# the worst speed more pace only takes him further past, and the full charge
	# reads more evadable than the worst one.
	for start: Vector3 in [Vector3(3, 0, 0), Vector3(3, 0, 1)]:
		var row: Array[float] = []
		for k: int in range(25):
			row.append(_charge(start, 0.5 * k))
		var worst: int = row.find(row.min())
		for i: int in range(1, worst + 1):
			assert_lte(row[i], row[i - 1] + SLACK,
					"closing from %s: evadability rises before the worst speed" % start)
		for i: int in range(worst + 1, row.size()):
			assert_gte(row[i], row[i - 1] - SLACK,
					"charging from %s at %.1f m/s: more pace never reads harder to evade"
					% [start, 0.5 * i])
		assert_gt(row[row.size() - 1], row[worst],
				"the committed charger from %s overshoots" % start)


func test_approach_lowers_evadability_for_a_standing_carrier() -> void:
	# No momentum on either side: the nearer a stationary defender's stick, the
	# less room the seam has.
	var prev: float = INF
	for gap: float in [3.0, 2.5, 2.0, 1.6, 1.2, 1.0, 0.8, 0.6, 0.4]:
		var opps: Array[Vector3] = [Vector3(gap, 0, 0.3)]
		var vels: Array[Vector3] = [Vector3.ZERO]
		var safety: float = _evade(Vector3.ZERO, Vector3.ZERO, opps, vels)
		assert_lte(safety, prev + SLACK, "a defender %.1f m off never leaves more room" % gap)
		prev = safety
	assert_lt(prev, 1.0, "a stick at the puck takes room away")


func test_stick_on_the_puck_is_a_real_threat() -> void:
	# Defender's stick right on the puck, no momentum — the carrier can't just
	# skate out of it in one cut.
	var opps: Array[Vector3] = [Vector3(0.8, 0, 0.3)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	assert_lt(_evade(Vector3.ZERO, Vector3(3, 0, 0), opps, vels), 0.35,
			"a stick on the puck is genuine pressure")


func test_stationary_wall_ahead_is_tight() -> void:
	var opps: Array[Vector3] = [Vector3(1.5, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	assert_lt(_evade(Vector3.ZERO, Vector3(5, 0, 0), opps, vels), 0.35,
			"skating into a stationary defender 1.5 m ahead is tight")


# A defender 2.2 m ahead of a 5 m/s carrier, skating with him at `pace`.
func _jockey(pace: float) -> float:
	var opps: Array[Vector3] = [Vector3(2.2, 0, 0.2)]
	var vels: Array[Vector3] = [Vector3(pace, 0, 0)]
	return _evade(Vector3.ZERO, Vector3(5, 0, 0), opps, vels)


func test_jockey_cannot_strip_a_careful_carrier() -> void:
	# A gap-control defender pacing the carrier CONTAINS (caps progress) but his
	# disk does not close on the puck the way a standing one the carrier skates
	# into does — containment is the offense model's problem, not a safety one.
	var prev: float = -INF
	for pace: float in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		var safety: float = _jockey(pace)
		assert_gte(safety, prev - SLACK, "matching more of the carrier's pace never closes him in")
		prev = safety
	assert_gt(_jockey(5.0), _jockey(0.0),
			"the pacer is safer to carry against than the same man standing still")


# An 8 m/s carry along +X for a second, a man `gap` ahead of it skating `pace`
# along it.
func _carry_at(start: Vector3, pace: float, apply_escape: bool = true) -> float:
	var opps: Array[Vector3] = [start]
	var vels: Array[Vector3] = [Vector3(pace, 0, 0)]
	return AICarrySpace.carry_safety(Vector3.ZERO, Vector3(8.0, 0, 0), 1.0, opps, vels,
			[], apply_escape)


func test_a_man_retreating_in_the_lane_can_stop_on_the_carry() -> void:
	# The carry is coming to him, so braking commits him to no spot: he stops from
	# his read rather than coasting to the commit window. Backing off at the
	# carrier's own pace, he is as much a wall as a man standing there.
	for gap: float in [3.0, 5.0]:
		for pace: float in [0.0, 4.0, 8.0]:
			assert_eq(_carry_at(Vector3(gap, 0, 0.2), pace), 0.0,
					"%.0f m ahead backing off at %.0f m/s" % [gap, pace])


func test_stopping_spares_a_chaser_his_escape_gate() -> void:
	# Braking only loses him ground on a carry running away from him, so a chaser
	# pacing it keeps the gate's credit.
	var behind := Vector3(-2.0, 0, 0.2)
	assert_gt(_carry_at(behind, 8.0), _carry_at(behind, 8.0, false))


func test_a_chaser_out_pacing_the_carry_is_on_it_where_it_ends() -> void:
	# A backchecker a stride behind a carrier slowing into the crease, skating his
	# way: chasing the carry, he is after the carrier, not coasting to a spot, and
	# runs it down where it ends. Read as coasting until a last lunge, his momentum
	# carried him past the crease and it read clear.
	var opps: Array[Vector3] = [Vector3(-0.55, 0, -18.77)]
	var vels: Array[Vector3] = [Vector3(3.86, 0, -7.81)]
	var from := Vector3(-2.6, 0, -21.5)
	var end := Vector3(-1.13, 0, -24.08)
	var carry: Vector3 = end - from
	var dir := Vector2(carry.x, carry.z).normalized()
	var speed: float = carry.length()
	var at: Vector3 = end + carry * 0.25
	var window: float = AICarrySpace.CARRY_LUNGE_WINDOW_S
	assert_lt(AICarrySpace.reach_clearance(at, 1.25, opps, vels, [], window, dir, speed,
			-INF, from), 0.0, "on the carry where it ends")
	assert_gt(AICarrySpace.reach_clearance(at, 1.25, opps, vels, [], window, dir, speed),
			0.0, "where coasting would have left him clear of it")


func test_handling_threads_a_tighter_seam() -> void:
	# In a tight spot (stationary wall), a better handler holds the puck further
	# off his body and finds room a plodder can't. Skill expression, grounded in
	# the handling envelope — not a magic deke chance.
	var opps: Array[Vector3] = [Vector3(1.5, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var low: float = _evade(Vector3.ZERO, Vector3(5, 0, 0), opps, vels, 0.6)
	var high: float = _evade(Vector3.ZERO, Vector3(5, 0, 0), opps, vels, 1.4)
	assert_gt(high, low, "better hands thread a tighter seam")


func test_seam_points_into_open_space() -> void:
	# The seam is a usable carry target: with a defender to the left, it resolves
	# to the right of the carrier's line.
	var opps: Array[Vector3] = [Vector3(1.0, 0, 2.0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var seam: Vector3 = AICarrySpace.best_evade_point(
			Vector3.ZERO, Vector3(4, 0, 0), opps, vels, HANDLE)
	assert_lt(seam.z, 0.5, "seam leans away from the defender on the +Z side")


# ─── carry_strip_point: WHERE a carry gets stripped ──────────────────────────

func test_strip_point_is_the_tight_midroute_not_the_safe_destination() -> void:
	# Carry from (0,0) to a clear destination (0,10), but a defender sits right on
	# the mid-route point (0,5). The strip, if it happens, is mid-route — the cost
	# must localize there, not at the open destination.
	var from := Vector3(0, 0, 0)
	var to := Vector3(0, 0, 10)
	var opps: Array[Vector3] = [Vector3(0, 0, 5)]     # parked on the midpoint
	var vels: Array[Vector3] = [Vector3.ZERO]
	var strip: Vector3 = AICarrySpace.carry_strip_point(from, to, 1.4, opps, vels)
	assert_almost_eq(strip.z, 5.0, 0.01, "strip localizes to the tight mid-route point")


func test_strip_point_is_destination_when_that_is_the_tight_end() -> void:
	# Clear mid-route, but a defender waiting AT the destination. The strip is there.
	var from := Vector3(0, 0, 0)
	var to := Vector3(0, 0, 10)
	var opps: Array[Vector3] = [Vector3(0, 0, 10)]    # waiting at the destination
	var vels: Array[Vector3] = [Vector3.ZERO]
	var strip: Vector3 = AICarrySpace.carry_strip_point(from, to, 1.4, opps, vels)
	assert_almost_eq(strip.z, 10.0, 0.01, "strip localizes to the covered destination")


func test_covered_only_carry_reaches_its_destination_when_nothing_covers_it() -> void:
	# A defender well off the route covers neither sample. As a strip LOCATION the
	# tighter sample still answers (the default); as how far the carry GETS, it
	# gets all the way.
	var from := Vector3(0, 0, 0)
	var to := Vector3(0, 0, 10)
	var opps: Array[Vector3] = [Vector3(5, 0, 5)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	assert_almost_eq(AICarrySpace.carry_safety(from, to, 1.4, opps, vels), 1.0, 0.001,
			"precondition: the route is clear")
	assert_almost_eq(AICarrySpace.carry_strip_point(from, to, 1.4, opps, vels).z, 5.0, 0.01,
			"the strip location is still the tighter sample")
	assert_almost_eq(AICarrySpace.carry_strip_point(
			from, to, 1.4, opps, vels, [], false, true).z, 10.0, 0.01,
			"a clear carry reaches its destination")

	# A defender ON the route still stops it there.
	var on_route: Array[Vector3] = [Vector3(0, 0, 5)]
	assert_almost_eq(AICarrySpace.carry_strip_point(
			from, to, 1.4, on_route, vels, [], false, true).z, 5.0, 0.01,
			"a covered mid-route still ends the carry mid-route")


func test_strip_point_of_a_stand_is_the_spot_itself() -> void:
	var spot := Vector3(3, 0, 7)
	var opps: Array[Vector3] = [Vector3(4, 0, 7)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var strip: Vector3 = AICarrySpace.carry_strip_point(spot, spot, 0.4, opps, vels)
	assert_eq(strip, spot, "a stand's strip is where it stands")


# ─── boards bound the seam search (the wall-pincer read) ─────────────────────

func test_evade_seam_never_leaves_the_playing_surface() -> void:
	# Carrier tight on the side wall, defender sealing from mid-ice: the naive
	# "away from the threat" seam sits THROUGH the boards. The handling envelope
	# is intersected with the rink, so the seam resolves along the wall instead.
	var carrier := Vector3(GameRules.INNER_HALF_WIDTH - 0.4, 0, 0)
	var opps: Array[Vector3] = [carrier + Vector3(-2.0, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var seam: Vector3 = AICarrySpace.best_evade_point(
			carrier, Vector3.ZERO, opps, vels, HANDLE)
	assert_lte(seam.x, GameRules.INNER_HALF_WIDTH, "seam stays on the playing surface")
	assert_gt(absf(seam.z), 0.5, "with the wall at the back, the escape runs along the boards")


func test_wall_alone_is_harmless_without_a_defender() -> void:
	# Nobody to pin against: a carrier parked on the boards with no defender in
	# the picture is fully safe (the n == 0 early return).
	assert_eq(_evade(Vector3(GameRules.INNER_HALF_WIDTH - 0.3, 0, 0),
			Vector3.ZERO, [], []), 1.0)


# The same defender gap with the carrier pinned against the side wall (the
# outside half of his handling envelope is off the ice) and in open ice.
func _pinned_and_open(gap: float) -> Array[float]:
	var pinned_pos := Vector3(GameRules.INNER_HALF_WIDTH - 0.4, 0, 0)
	var opps_wall: Array[Vector3] = [pinned_pos + Vector3(-gap, 0, 0)]
	var opps_open: Array[Vector3] = [Vector3(-gap, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	return [_evade(pinned_pos, Vector3.ZERO, opps_wall, vels),
			_evade(Vector3.ZERO, Vector3.ZERO, opps_open, vels)]


func test_wall_pinned_carrier_reads_less_safe_than_open_ice() -> void:
	# The wall pincer: losing half the envelope never adds room at any gap, and
	# with the defender 1.5 m off it costs room.
	for gap: float in [1.0, 1.5, 2.0, 2.5, 3.0]:
		var both: Array[float] = _pinned_and_open(gap)
		assert_lte(both[0], both[1] + SLACK, "the wall never adds room at %.1f m" % gap)
	var at_1_5: Array[float] = _pinned_and_open(1.5)
	assert_lt(at_1_5[0], at_1_5[1], "pinned at 1.5 m reads less safe than open ice")


# ─── best_handle_protect_point: shield the puck with the body ─────────────────

func test_protect_point_pulls_the_puck_away_from_a_frontal_stick() -> void:
	# Stick threat dead ahead of a stationary carrier: the safest holdable spot
	# is on the FAR side of the body — pull the puck back, body becomes the
	# shield. Offset is body-relative.
	var opps: Array[Vector3] = [Vector3(0, 0, -1.2)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var offset: Vector3 = AICarrySpace.best_handle_protect_point(
			Vector3.ZERO, Vector3.ZERO, opps, vels, HANDLE)
	assert_gt(offset.z, 0.5, "puck pulls to the protected side, away from the threat")


func test_protect_point_stays_inside_the_handling_envelope() -> void:
	var opps: Array[Vector3] = [Vector3(0.9, 0, 0.7)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var offset: Vector3 = AICarrySpace.best_handle_protect_point(
			Vector3.ZERO, Vector3.ZERO, opps, vels, HANDLE)
	assert_lte(offset.length(), HANDLE + 0.001,
			"the blade can only hold the puck within its handling reach")


func test_protect_point_never_shields_into_the_wall() -> void:
	# Carrier tight on the side wall, defender attacking from mid-ice: the naive
	# "away from the threat" side is INTO the wall. The board cap makes the seam
	# resolve along the wall instead — never outside the rink.
	var carrier := Vector3(GameRules.INNER_HALF_WIDTH - 0.4, 0, 0)
	var opps: Array[Vector3] = [carrier + Vector3(-1.2, 0, 0)]
	var vels: Array[Vector3] = [Vector3.ZERO]
	var offset: Vector3 = AICarrySpace.best_handle_protect_point(
			carrier, Vector3.ZERO, opps, vels, HANDLE)
	assert_lte(carrier.x + offset.x, GameRules.INNER_HALF_WIDTH,
			"the protected spot stays on the playing surface")
	assert_gt(absf(offset.z), 0.3, "with the wall behind, the escape runs ALONG the boards")


func test_reach_safety_calibration_snapshot() -> void:
	var snap := Snapshot.new(SNAPSHOT_PATH)
	snap.record("straight-on charger 3 m ahead at 8 m/s", _charge(Vector3(3, 0, 0), 8.0))
	snap.record("straight-on charger 3 m ahead at 2 m/s", _charge(Vector3(3, 0, 0), 2.0))
	snap.record("angled charger from (3, 1) at 3 m/s", _charge(Vector3(3, 0, 1), 3.0))
	snap.record("angled charger from (3, 1) at 8 m/s", _charge(Vector3(3, 0, 1), 8.0))
	snap.record("jockey pacing a 5 m/s carrier 2.2 m ahead", _jockey(5.0))
	snap.record("same defender standing still", _jockey(0.0))
	var wall: Array[float] = _pinned_and_open(1.5)
	snap.record("wall-pinned carrier, defender 1.5 m off", wall[0])
	snap.record("open-ice carrier, defender 1.5 m off", wall[1])
	snap.verify(self)

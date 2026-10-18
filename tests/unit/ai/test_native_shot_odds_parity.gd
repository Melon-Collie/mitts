extends GutTest

# Parity fuzz: NativeShotOdds (C++ GDExtension, native/src/) against the GDScript
# reference AIShotOdds — every query kind, from random releases over both ends,
# against random keepers in every stance, the field the same for both. The
# weights are rounded the same way on both sides, so the two agree to the bit.
# Goes pending when the extension isn't built.

const FUZZ_ITERATIONS: int = 600
const SEED: int = 0x4F444453  # "ODDS"

var _rng := RandomNumberGenerator.new()
var _was: Callable
var _reference := AIShotOdds.Query.new()
var _ported := AIShotOdds.Query.new()


func before_each() -> void:
	_rng.seed = SEED
	_was = AIShotOdds.native_factory
	AIShotOdds.native_factory = NativeShotOddsFactory.make
	AIShotOdds.attach_native()
	_reference = AIShotOdds.Query.new()
	_reference.use_native = false
	_ported = AIShotOdds.Query.new()


func after_each() -> void:
	AIShotOdds.native_factory = _was
	AIShotOdds.attach_native()


func _native_missing() -> bool:
	if ClassDB.class_exists(&"NativeShotOdds"):
		return false
	NativeParityGuard.report_missing(self, "NativeShotOdds")
	return true


func _goal() -> Vector3:
	return Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z * (1.0 if _rng.randf() < 0.5 else -1.0))


# A release in front of `goal`, from the doorstep to the blue line and beyond,
# sometimes off the measured grid.
func _release(goal: Vector3) -> Vector3:
	var out: float = _rng.randf_range(0.05, 22.0)
	return Vector3(_rng.randf_range(-12.0, 12.0), 0.0, goal.z - signf(goal.z) * out)


func _keeper(goal: Vector3) -> Vector3:
	var depth: float = _rng.randf_range(-0.3, 3.0)
	return Vector3(_rng.randf_range(-1.6, 1.6), 0.0, goal.z - signf(goal.z) * depth)


# Runs `query` (taking the Query to read through) on the GDScript reference, then
# on the kernel, and returns both answers with the matched cells and weights each
# left.
func _both(query: Callable) -> Array:
	var ref_value: Variant = query.call(_reference)
	var nat_value: Variant = query.call(_ported)
	AIShotOdds._sync_cells(_ported)
	return [ref_value, nat_value, _reference.cells.duplicate(), _ported.cells.duplicate(),
			_reference.weights.duplicate(), _ported.weights.duplicate()]


func _check(r: Array, what: String) -> void:
	assert_eq(r[1], r[0], "%s: the odds" % what)
	assert_eq(r[3], r[2], "%s: the matched cells" % what)
	assert_eq(r[5], r[4], "%s: their weights" % what)


func test_every_query_weighs_as_the_gdscript_does() -> void:
	if _native_missing():
		return
	AIShotOdds.shot_set(Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z),
			_ported)
	assert_not_null(_ported.native, "the field loaded into the kernel")
	var stances: Array[int] = [AIShotOdds.Stance.UPRIGHT, AIShotOdds.Stance.DOWN,
			AIShotOdds.Stance.POST_SEAL]
	var matched: int = 0
	for i: int in FUZZ_ITERATIONS:
		var goal: Vector3 = _goal()
		var release: Vector3 = _release(goal)
		var keeper: Vector3 = _keeper(goal)
		var vel_x: float = _rng.randf_range(-3.0, 3.0)
		var stance: int = stances[_rng.randi_range(0, 2)]
		var yaw: float = NAN if _rng.randf() < 0.3 else _rng.randf_range(-PI, PI)
		var now: Array = _both(func(q: AIShotOdds.Query) -> float:
			return AIShotOdds.shot_now(release, goal, keeper, vel_x, stance, yaw, q))
		_check(now, "shot_now %d" % i)
		if not (now[2] as PackedInt32Array).is_empty():
			matched += 1
		_check(_both(func(q: AIShotOdds.Query) -> float:
			return AIShotOdds.shot_set(release, goal, q)),
				"shot_set %d" % i)
		var passer: Vector3 = release + Vector3(_rng.randf_range(-12.0, 12.0), 0.0,
				_rng.randf_range(-8.0, 8.0))
		var speed: float = _rng.randf_range(8.0, 24.0)
		var one_timer: bool = _rng.randf() < 0.5
		_check(_both(func(q: AIShotOdds.Query) -> float:
			return AIShotOdds.feed(passer, release, speed, goal, keeper, one_timer, q)),
				"feed %d" % i)
		_check(_both(func(q: AIShotOdds.Query) -> float:
			return AIShotOdds.feed_unaimed(passer, release, speed, goal, keeper, q)),
				"feed_unaimed %d" % i)
		var spread: float = _rng.randf_range(0.01, 0.12)
		_check(_both(func(q: AIShotOdds.Query) -> float:
			return AIShotOdds.shot_now_at_spread(release, goal, keeper, vel_x, stance,
					spread, yaw, q)),
				"shot_now_at_spread %d" % i)
		var pick := AIShotOdds.Pick.new()
		var picks: Array = _both(func(q: AIShotOdds.Query) -> Array:
			AIShotOdds.pick_shot_now(release, goal, keeper, vel_x, stance, pick, yaw, q)
			return [pick.odds, pick.aim, pick.loft])
		_check(picks, "pick_shot_now %d" % i)
	assert_gt(matched, FUZZ_ITERATIONS / 4, "a good share of the queries land on measured cells")

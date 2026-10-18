extends GutTest

# Parity fuzz: NativeShotOdds (C++ GDExtension, native/src/) against the GDScript
# reference AIShotOdds — every query kind, from random releases over both ends,
# against random keepers in every stance, the field the same for both. The
# weights are rounded the same way on both sides, so the two agree to the bit.
# Goes pending when the extension isn't built.

const FUZZ_ITERATIONS: int = 600
const SEED: int = 0x4F444453  # "ODDS"

var _rng := RandomNumberGenerator.new()
var _native: RefCounted = null
var _was: RefCounted = null


func before_each() -> void:
	_rng.seed = SEED
	AIShotOdds.shot_set(Vector3(0.0, 0.0, -20.0), Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z))
	_was = AIShotOdds._native
	_native = NativeShotOddsFactory.make()
	if _native != null:
		var factory: Callable = AIShotOdds.native_factory
		AIShotOdds.native_factory = NativeShotOddsFactory.make
		AIShotOdds.attach_native()
		_native = AIShotOdds._native
		AIShotOdds.native_factory = factory


func after_each() -> void:
	AIShotOdds._native = _was
	AIShotOdds._q_synced = true


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


# Runs `query` with the kernel detached, then attached, and returns both answers
# with the matched cells and weights each left.
func _both(query: Callable) -> Array:
	AIShotOdds._native = null
	var ref_value: Variant = query.call()
	var ref_cells: PackedInt32Array = AIShotOdds._q_cells.duplicate()
	var ref_weights: PackedFloat32Array = AIShotOdds._q_weights.duplicate()
	AIShotOdds._native = _native
	var nat_value: Variant = query.call()
	AIShotOdds._sync_cells()
	return [ref_value, nat_value, ref_cells, AIShotOdds._q_cells.duplicate(), ref_weights,
			AIShotOdds._q_weights.duplicate()]


func _check(r: Array, what: String) -> void:
	assert_eq(r[1], r[0], "%s: the odds" % what)
	assert_eq(r[3], r[2], "%s: the matched cells" % what)
	assert_eq(r[5], r[4], "%s: their weights" % what)


func test_every_query_weighs_as_the_gdscript_does() -> void:
	if _native_missing():
		return
	assert_not_null(_native, "the field loaded into the kernel")
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
		var now: Array = _both(func() -> float:
			return AIShotOdds.shot_now(release, goal, keeper, vel_x, stance, yaw))
		_check(now, "shot_now %d" % i)
		if not (now[2] as PackedInt32Array).is_empty():
			matched += 1
		_check(_both(func() -> float: return AIShotOdds.shot_set(release, goal)),
				"shot_set %d" % i)
		var passer: Vector3 = release + Vector3(_rng.randf_range(-12.0, 12.0), 0.0,
				_rng.randf_range(-8.0, 8.0))
		var speed: float = _rng.randf_range(8.0, 24.0)
		var one_timer: bool = _rng.randf() < 0.5
		_check(_both(func() -> float:
			return AIShotOdds.feed(passer, release, speed, goal, keeper, one_timer)),
				"feed %d" % i)
		_check(_both(func() -> float:
			return AIShotOdds.feed_unaimed(passer, release, speed, goal, keeper)),
				"feed_unaimed %d" % i)
		var spread: float = _rng.randf_range(0.01, 0.12)
		_check(_both(func() -> float:
			return AIShotOdds.shot_now_at_spread(release, goal, keeper, vel_x, stance,
					spread, yaw)),
				"shot_now_at_spread %d" % i)
		var pick := AIShotOdds.Pick.new()
		var picks: Array = _both(func() -> Array:
			AIShotOdds.pick_shot_now(release, goal, keeper, vel_x, stance, pick, yaw)
			return [pick.odds, pick.aim, pick.loft])
		_check(picks, "pick_shot_now %d" % i)
	assert_gt(matched, FUZZ_ITERATIONS / 4, "a good share of the queries land on measured cells")

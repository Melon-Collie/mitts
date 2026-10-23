extends GutTest

# WristerPocket — where to hold the puck so a release toward an aim carries the
# most it can. World XZ; "ahead" is −Z, a lefty's stick side is −X (left).

const AHEAD := Vector2(0.0, -1.0)
const LEFT := Vector2(-1.0, 0.0)
const RIGHT := Vector2(1.0, 0.0)
const LEFTY: bool = true
const RIGHTY: bool = false
const UNLOADED: float = 0.6
const BACKHAND: float = 0.75

var _load_cfg := WristerLoad.Config.new()
var _facing_cfg := FacingRules.Config.new()
var _out := WristerPocket.Result.new()
var _facing := FacingRules.Result.new()
var _load := WristerLoad.Result.new()


func _solve(aim: Vector2, velocity: Vector2, left_handed: bool,
		facing: Vector2 = AHEAD) -> WristerPocket.Result:
	WristerPocket.solve(_out, aim, velocity, facing, left_handed, _load_cfg, _facing_cfg,
			0.6, 0.75, _facing, _load)
	return _out


func _off(dir: Vector2) -> float:
	return rad_to_deg(absf(_out.dir.angle_to(dir)))


func test_skating_a_shot_ahead_is_held_beside_the_stick_hip() -> void:
	_solve(AHEAD, AHEAD * 6.0, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)
	assert_lt(_off(LEFT), 46.0, "a lefty's pocket is out on the left")


func test_skating_a_shot_across_to_the_off_side_sweeps_across_the_front() -> void:
	_solve(RIGHT, AHEAD * 6.0, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)


func test_skating_a_shot_to_the_stick_side_takes_the_best_it_can() -> void:
	# A forehand to the stick side would need the puck behind the body; the
	# backhand sweeping the puck across from in front is the loaded release.
	_solve(LEFT, AHEAD * 6.0, LEFTY)
	assert_gt(_out.power_share, 0.74)


func test_standing_turns_side_on_with_the_puck_in_front() -> void:
	# At rest the body faces the cursor, so the pocket off to the stick side
	# becomes "puck in front, aim off to the side": a full forehand.
	_solve(AHEAD, Vector2.ZERO, LEFTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)


func test_right_handed_mirrors() -> void:
	_solve(AHEAD, AHEAD * 6.0, RIGHTY)
	assert_false(_out.is_backhand)
	assert_almost_eq(_out.power_share, 1.0, 0.001)
	assert_lt(_off(RIGHT), 46.0, "a righty's pocket is out on the right")


func test_a_skating_carrier_never_pockets_past_its_backhand_stop() -> void:
	# With the puck the blade stops on the backhand (SkaterController's
	# bh_release_angle_deg), and a cursor past it pivots the hips onto the other
	# line instead: a pocket there is a turn round, not a hold.
	var carry := FacingRules.Config.new()
	carry.backhand_edge_rad = deg_to_rad(67.0)
	var fr := FacingRules.Result.new()
	for deg: int in range(-180, 180, 15):
		var aim: Vector2 = AHEAD.rotated(deg_to_rad(deg))
		for left: bool in [LEFTY, RIGHTY]:
			WristerPocket.solve(_out, aim, AHEAD * 8.0, AHEAD, left, _load_cfg, carry,
					UNLOADED, BACKHAND, _facing, _load)
			FacingRules.solve(fr, AHEAD, _out.dir, AHEAD * 8.0, false, false, left, carry)
			assert_false(fr.pivoting, "aim %d°, %s" % [deg, "lefty" if left else "righty"])


func test_no_aim_leaves_everything_alone() -> void:
	_solve(Vector2.ZERO, AHEAD * 6.0, LEFTY)
	assert_almost_eq(_out.power_share, 1.0, 0.001)


# ── The bearing path matches the local-frame solve ───────────────────────────
# The pocket reads the load straight from bearings; this is the long way round
# it replaced (each vector rotated into the body's frame, WristerLoad.solve on
# those), held against it on seeded random builds and situations.

func _local(world: Vector2, body: Vector2) -> Vector3:
	return Vector3(world.x, 0.0, world.y).rotated(Vector3.UP, -atan2(-body.x, -body.y))


func _ref_share(puck: Vector2, aim: Vector2, body: Vector2, left: bool,
		lr: WristerLoad.Result) -> float:
	WristerLoad.solve(lr, _local(puck, body), _local(aim, body), left, _load_cfg)
	return WristerLoad.power_share(lr.load_share, lr.is_backhand, UNLOADED, BACKHAND)


func test_the_bearing_path_matches_the_local_frame_solve() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x90C7E7
	var lr := WristerLoad.Result.new()
	var fr := FacingRules.Result.new()
	var worst_share: float = 0.0
	var worst_pocket: float = 0.0
	var worst_dir: float = 0.0
	for _i: int in 2000:
		var aim := Vector2.from_angle(rng.randf_range(-PI, PI))
		var vel := Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.0, 9.0)
		var facing := Vector2.from_angle(rng.randf_range(-PI, PI))
		var left: bool = rng.randf() < 0.5
		var puck := Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.1, 1.3)
		worst_share = maxf(worst_share, absf(WristerPocket.share_at(puck, aim, facing, left,
				_load_cfg, UNLOADED, BACKHAND, _load) - _ref_share(puck, aim, facing, left, lr)))
		WristerPocket.solve(_out, aim, vel, facing, left, _load_cfg, _facing_cfg,
				UNLOADED, BACKHAND, _facing, _load)
		var best: float = -1.0
		var second: float = -1.0
		var best_dir := Vector2.ZERO
		for offset: float in WristerPocket._CANDIDATES:
			var pocket: Vector2 = aim.rotated(offset)
			FacingRules.solve(fr, facing, pocket, vel, false, false, left, _facing_cfg)
			if fr.pivoting:
				continue
			var s: float = _ref_share(pocket, aim, fr.target, left, lr)
			if s > best:
				second = best
				best = s
				best_dir = pocket
			elif s > second:
				second = s
		worst_pocket = maxf(worst_pocket, absf(_out.power_share - best))
		if best - second > 1e-4:
			worst_dir = maxf(worst_dir, _out.dir.distance_to(best_dir))
	assert_lt(worst_share, 1e-5, "share_at")
	assert_lt(worst_pocket, 1e-5, "the pocket's share")
	assert_lt(worst_dir, 1e-5, "the pocket's bearing")

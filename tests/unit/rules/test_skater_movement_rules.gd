extends GutTest

# SkaterMovementRules — stride, glide, skid, turn, stop, postures, and the speed caps.

const DT: float = 1.0 / 120.0


func _default_cfg() -> SkaterMovementRules.MovementConfig:
	var cfg := SkaterMovementRules.MovementConfig.new()
	cfg.thrust = 20.0
	cfg.power_knee_speed = 100.0  # no power fade unless a test opts in
	cfg.friction = 5.0
	cfg.max_speed = 10.0
	cfg.move_deadzone = 0.1
	cfg.stop_decel = 25.0
	cfg.reverse_skid_fraction = 0.75
	cfg.turn_accel = 9.0
	cfg.max_turn_rate = 6.0
	cfg.puck_carry_speed_multiplier = 0.88
	cfg.backward_thrust_multiplier = 0.7
	cfg.crossover_thrust_multiplier = 0.85
	return cfg


# A frictionless config, so a test reads one mechanism's effect exactly.
func _clean_cfg() -> SkaterMovementRules.MovementConfig:
	var cfg := _default_cfg()
	cfg.friction = 0.0
	cfg.max_speed = 30.0
	return cfg


func _speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func test_no_input_applies_friction() -> void:
	var result: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(5, 0, 0), Vector2.ZERO, 0.0, false, false, 0.1, _default_cfg())
	var speed: float = Vector2(result.x, result.z).length()
	assert_lt(speed, 5.0, "friction should slow the skater")

func test_brake_slows_faster_than_friction() -> void:
	var no_brake: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(5, 0, 0), Vector2.ZERO, 0.0, false, false, 0.1, _default_cfg())
	var with_brake: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(5, 0, 0), Vector2.ZERO, 0.0, false, true, 0.1, _default_cfg())
	assert_lt(with_brake.length(), no_brake.length(), "braking removes more speed than idle friction")

func test_input_applies_thrust() -> void:
	var result: Vector3 = SkaterMovementRules.apply_movement(
		Vector3.ZERO, Vector2(1, 0), 0.0, false, false, 0.1, _default_cfg())
	assert_gt(result.x, 0.0, "thrust in +X direction should increase X velocity")

func test_deadzone_input_treated_as_no_input() -> void:
	var cfg := _default_cfg()
	# Input below the 0.1 deadzone should apply only friction, no thrust
	var result: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(5, 0, 0), Vector2(0.01, 0), 0.0, false, false, 0.1, cfg)
	assert_lt(Vector2(result.x, result.z).length(), 5.0)

func test_puck_carry_reduces_max_speed() -> void:
	# Accelerate for a long time to hit the cap
	var cfg := _default_cfg()
	var v_free := Vector3.ZERO
	var v_carry := Vector3.ZERO
	for i in range(1000):
		v_free = SkaterMovementRules.apply_movement(v_free, Vector2(1, 0), 0.0, false, false, 0.01, cfg)
		v_carry = SkaterMovementRules.apply_movement(v_carry, Vector2(1, 0), 0.0, true, false, 0.01, cfg)
	var free_speed: float = Vector2(v_free.x, v_free.z).length()
	var carry_speed: float = Vector2(v_carry.x, v_carry.z).length()
	assert_lt(carry_speed, free_speed, "carrying the puck caps speed lower than free skating")
	assert_lt(carry_speed, cfg.max_speed, "carry speed should be below full max_speed")

# ── Postures ─────────────────────────────────────────────────────────────────

func _top_speed(cfg: SkaterMovementRules.MovementConfig, posture: SkaterMovementRules.Posture,
		has_puck: bool = false) -> float:
	var v := Vector3.ZERO
	for _i in 2000:
		v = SkaterMovementRules.apply_movement(v, Vector2(1, 0), -PI / 2.0, has_puck, false, 0.01,
				cfg, posture)
	return _speed(v)


func _stance_cfg() -> SkaterMovementRules.MovementConfig:
	var cfg := _clean_cfg()
	cfg.stance_grip_mult = 2.0
	cfg.stance_scrape = 1.0 / 3.0
	cfg.stance_stride_mult = 0.6
	cfg.stance_max_speed_mult = 0.85
	cfg.stance_shuffle_mult = 1.2
	cfg.commit_grip_mult = 0.6
	cfg.commit_stride_mult = 0.5
	return cfg


func test_omitted_posture_is_upright() -> void:
	var cfg := _stance_cfg()
	var omitted: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(3, 0, 0), Vector2(1, 1), 0.0, false, false, 0.01, cfg)
	var upright: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(3, 0, 0), Vector2(1, 1), 0.0, false, false, 0.01, cfg,
		SkaterMovementRules.Posture.UPRIGHT)
	assert_eq(omitted, upright)


func test_the_stance_stride_stops_adding_lower() -> void:
	var cfg := _default_cfg()
	cfg.stance_max_speed_mult = 0.85
	cfg.stance_stride_mult = 0.6
	assert_almost_eq(_top_speed(cfg, SkaterMovementRules.Posture.STANCE), cfg.max_speed * 0.85, 0.2,
		"the stance tops out at its own cap")
	assert_almost_eq(_top_speed(cfg, SkaterMovementRules.Posture.UPRIGHT), cfg.max_speed, 0.2)


func test_the_stance_strides_choppier() -> void:
	var cfg := _stance_cfg()
	var upright: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(2, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg)) - 2.0
	var stance: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(2, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)) - 2.0
	assert_almost_eq(stance, upright * cfg.stance_stride_mult, 1e-5)


func test_dropping_into_the_stance_above_its_cap_keeps_the_speed() -> void:
	var cfg := _stance_cfg()
	cfg.max_speed = 10.0
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(9.5, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(_speed(v), 9.5, 1e-5, "the stride stops adding; nothing clamps down")


func test_the_stance_digs_a_tighter_turn() -> void:
	var cfg := _stance_cfg()
	var upright: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg)
	var stance: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(atan2(stance.z, stance.x), atan2(upright.z, upright.x) * cfg.stance_grip_mult, 1e-5)


# The anchor the default stance_scrape is chosen from: at ×2 grip the excess on a
# full-lock cut is the upright capacity, turn_accel × grip.
func test_a_full_lock_stance_cut_bleeds_scrape_times_the_excess() -> void:
	var cfg := _stance_cfg()
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(_speed(v), 8.0 - cfg.stance_scrape * cfg.turn_accel * DT, 1e-4)


func test_a_stance_turn_inside_upright_grip_costs_nothing() -> void:
	var cfg := _stance_cfg()
	# The upright edges reach a stick this close in one tick, so the stance digs
	# no harder than a clean carve.
	var stick := Vector2(cos(0.005), sin(0.005))
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), stick, -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(atan2(v.z, v.x), 0.005, 1e-5, "lands on the stick")
	assert_gt(_speed(v), 8.0, "no scrape — the stride still adds")


func test_a_stance_cut_ends_in_a_glide_not_a_stop() -> void:
	var cfg := _stance_cfg()
	var v := Vector3(8, 0, 0)
	for _i in 120:
		v = SkaterMovementRules.apply_movement(v, Vector2(0, 1), -PI / 2.0, false, false, DT, cfg,
			SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(atan2(v.z, v.x), PI / 2.0, 1e-4, "lined up with the stick")
	assert_gt(_speed(v), 5.0, "and still skating")


func test_the_stance_shuffles_harder_sideways() -> void:
	var cfg := _stance_cfg()
	var upright: Vector3 = SkaterMovementRules.apply_movement(
		Vector3.ZERO, Vector2(1, 0), 0.0, false, false, DT, cfg)
	var stance: Vector3 = SkaterMovementRules.apply_movement(
		Vector3.ZERO, Vector2(1, 0), 0.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.STANCE)
	assert_almost_eq(stance.x, upright.x * cfg.stance_shuffle_mult, 1e-5,
		"a pure side-step from a standstill pushes at the shuffle scale")


func test_a_committed_check_loses_grip_and_stride() -> void:
	var cfg := _stance_cfg()
	var upright: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg)
	var commit: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.COMMIT)
	assert_almost_eq(atan2(commit.z, commit.x), atan2(upright.z, upright.x) * cfg.commit_grip_mult, 1e-5)
	var push_up: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(2, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg)) - 2.0
	var push_commit: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(2, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.COMMIT)) - 2.0
	assert_almost_eq(push_commit, push_up * cfg.commit_stride_mult, 1e-5)


func test_grip_scale_multiplies_the_turn() -> void:
	var cfg := _stance_cfg()
	var full: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg)
	var rattled: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg,
		SkaterMovementRules.Posture.UPRIGHT, 0.6)
	assert_almost_eq(atan2(rattled.z, rattled.x), atan2(full.z, full.x) * 0.6, 1e-5)


func test_posture_of_lets_the_commit_win() -> void:
	assert_eq(SkaterMovementRules.posture_of(false, false), SkaterMovementRules.Posture.UPRIGHT)
	assert_eq(SkaterMovementRules.posture_of(true, false), SkaterMovementRules.Posture.STANCE)
	assert_eq(SkaterMovementRules.posture_of(false, true), SkaterMovementRules.Posture.COMMIT)
	assert_eq(SkaterMovementRules.posture_of(true, true), SkaterMovementRules.Posture.COMMIT)


func test_over_max_preserved_when_no_thrust() -> void:
	# Skater blasted by a body check to speed 20 — without new thrust input, the
	# clamp shouldn't yank them back to max_speed. Only friction erodes it.
	var cfg := _default_cfg()
	var boosted := Vector3(20, 0, 0)
	var result: Vector3 = SkaterMovementRules.apply_movement(
		boosted, Vector2.ZERO, 0.0, false, false, 0.01, cfg)
	# A single small step of friction should barely reduce 20
	assert_gt(Vector2(result.x, result.z).length(), cfg.max_speed,
		"over-max speed from external source should survive a single friction tick")

func test_backward_thrust_scaled_down() -> void:
	# Facing +Z means facing_dir is (-sin(0), -cos(0)) = (0, -1), so moving
	# in (0, 1) is aligned with facing — move_dot = -1 is backward.
	# Moving in (0, -1) is backward from facing. (0, 1) is forward. Let's test
	# that moving "behind" the skater applies reduced thrust.
	var cfg := _default_cfg()
	# With rotation_y = 0, forward is -Z direction; so move (0, 1) is backward
	var forward: Vector3 = SkaterMovementRules.apply_movement(
		Vector3.ZERO, Vector2(0, -1), 0.0, false, false, 0.1, cfg)
	var backward: Vector3 = SkaterMovementRules.apply_movement(
		Vector3.ZERO, Vector2(0, 1), 0.0, false, false, 0.1, cfg)
	# Forward thrust full; backward thrust scaled by backward_thrust_multiplier (0.7)
	assert_gt(forward.length(), backward.length(), "backward thrust should be weaker than forward")


# ── integrate_forward (stage-3 remote forward-prediction primitive) ────────────

func test_integrate_forward_zero_ticks_is_identity() -> void:
	var r := SkaterMovementRules.ForwardResult.new()
	var pos := Vector3(3, 0, 4)
	var vel := Vector3(5, 0, 0)
	SkaterMovementRules.integrate_forward(pos, vel, Vector2(1, 0), 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 0.01, 0, 0, r)
	assert_eq(r.position, pos, "0 ticks leaves position unchanged")
	assert_eq(r.velocity, vel, "0 ticks leaves velocity unchanged")


func test_integrate_forward_negative_ticks_clamped() -> void:
	var r := SkaterMovementRules.ForwardResult.new()
	var pos := Vector3(3, 0, 4)
	var vel := Vector3(5, 0, 0)
	SkaterMovementRules.integrate_forward(pos, vel, Vector2(1, 0), 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 0.01, -5, 0, r)
	assert_eq(r.position, pos, "negative ticks treated as zero — no integration")


func test_integrate_forward_matches_sequential_apply_movement() -> void:
	# The whole point: with NO decay the primitive must equal N hand-rolled
	# apply_movement steps with position accumulation — the client render and host
	# rewind both call it, so its equivalence to the live per-tick math is what keeps
	# them aligned. (intent_decay_ticks = 0 -> full intent every tick.)
	var cfg := _default_cfg()
	var pos := Vector3(0, 0, 0)
	var vel := Vector3(2, 0, 1)
	var mv := Vector2(1, 0)
	var expect_pos := pos
	var expect_vel := vel
	for _i in 9:
		expect_vel = SkaterMovementRules.apply_movement(expect_vel, mv, 0.0, false, false, 0.0083, cfg)
		expect_pos += expect_vel * 0.0083
	var r := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(pos, vel, mv, 0.0, false, false, SkaterMovementRules.Posture.UPRIGHT, cfg, 0.0083, 9, 0, r)
	assert_almost_eq(r.velocity.x, expect_vel.x, 1e-6)
	assert_almost_eq(r.velocity.z, expect_vel.z, 1e-6)
	assert_almost_eq(r.position.x, expect_pos.x, 1e-6)
	assert_almost_eq(r.position.z, expect_pos.z, 1e-6)


func test_integrate_forward_is_deterministic() -> void:
	# render == rewind rests on this: identical inputs (incl. the decay) must give
	# identical output, so the host's rewind reconstruction lands exactly where the
	# client rendered.
	var cfg := _default_cfg()
	var a := SkaterMovementRules.ForwardResult.new()
	var b := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(Vector3(1, 0, 2), Vector3(4, 0, -3),
		Vector2(0, 1), 1.2, true, false, SkaterMovementRules.Posture.STANCE, cfg, 0.0083, 9, 5, a)
	SkaterMovementRules.integrate_forward(Vector3(1, 0, 2), Vector3(4, 0, -3),
		Vector2(0, 1), 1.2, true, false, SkaterMovementRules.Posture.STANCE, cfg, 0.0083, 9, 5, b)
	assert_eq(a.position, b.position, "same inputs -> same predicted position")
	assert_eq(a.velocity, b.velocity, "same inputs -> same predicted velocity")


func test_integrate_forward_coasts_to_a_stop_with_no_input() -> void:
	var cfg := _default_cfg()
	var r := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(Vector3(6, 0, 0), Vector3(6, 0, 0),
		Vector2.ZERO, 0.0, false, false, SkaterMovementRules.Posture.UPRIGHT, cfg, 0.0083, 9, 0, r)
	assert_lt(Vector2(r.velocity.x, r.velocity.z).length(), 6.0,
		"no input -> friction bleeds speed over the prediction window")
	assert_gt(r.position.x, 6.0, "still drifts forward while decelerating")


func test_integrate_forward_intent_decay_reduces_thrust_travel() -> void:
	# RL-style decay: fading the assumed intent to 0 over the window applies less
	# thrust than holding it full, so a thrusting skater travels LESS far — the
	# mechanism that tames overshoot when the real player cuts. From rest so the
	# only forward motion is the (decayed vs full) thrust.
	var cfg := _default_cfg()
	var full := SkaterMovementRules.ForwardResult.new()
	var decayed := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, Vector2(1, 0),
		0.0, false, false, SkaterMovementRules.Posture.UPRIGHT, cfg, 0.0083, 9, 0, full)   # no decay
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, Vector2(1, 0),
		0.0, false, false, SkaterMovementRules.Posture.UPRIGHT, cfg, 0.0083, 9, 5, decayed)  # decay over 5 ticks
	assert_lt(decayed.position.x, full.position.x, "decayed intent applies less thrust -> less travel")
	assert_lt(decayed.velocity.x, full.velocity.x, "decayed intent -> lower end speed")
	assert_gt(decayed.position.x, 0.0, "but still moves forward (near ticks apply near-full intent)")


func test_integrate_forward_stagger_reduces_thrust_travel() -> void:
	# A staggered victim (thrust penalized by BodyCheckRules.thrust_mult) must
	# predict LESS forward travel than a healthy one — right after checks is
	# exactly when follow-up contests cluster, so both sides apply the penalty.
	var bc_cfg := BodyCheckRules.Config.new()
	bc_cfg.max_stagger_seconds = 1.0
	bc_cfg.max_thrust_penalty = 0.6
	var healthy := SkaterMovementRules.ForwardResult.new()
	var staggered := SkaterMovementRules.ForwardResult.new()
	var mv := Vector2(1, 0)
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, mv, 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 1.0 / 120.0, 9, 0, healthy)
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, mv, 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 1.0 / 120.0, 9, 0, staggered, 0.8, bc_cfg)
	assert_lt(staggered.position.length(), healthy.position.length(),
		"stagger thrust penalty must reduce predicted travel")
	assert_gt(staggered.position.length(), 0.0, "penalized, not frozen")


func test_integrate_forward_restores_cfg_thrust() -> void:
	# The primitive transiently scales cfg.thrust (callers pass a shared cached
	# config) — it must ALWAYS restore the base afterward, or the render path's
	# next tick inherits a stale stagger penalty.
	var cfg := _default_cfg()
	var base: float = cfg.thrust
	var bc_cfg := BodyCheckRules.Config.new()
	bc_cfg.max_stagger_seconds = 1.0
	bc_cfg.max_thrust_penalty = 0.6
	var r := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, Vector2(1, 0), 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, cfg, 1.0 / 120.0, 9, 0, r, 0.8, bc_cfg)
	assert_eq(cfg.thrust, base, "cfg.thrust restored after integration")


func test_integrate_forward_zero_stagger_matches_unstaggered() -> void:
	# stagger 0 / null cfg are exact no-ops — the default path is unchanged.
	var bc_cfg := BodyCheckRules.Config.new()
	bc_cfg.max_stagger_seconds = 1.0
	bc_cfg.max_thrust_penalty = 0.6
	var plain := SkaterMovementRules.ForwardResult.new()
	var zeroed := SkaterMovementRules.ForwardResult.new()
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, Vector2(1, 0), 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 1.0 / 120.0, 9, 0, plain)
	SkaterMovementRules.integrate_forward(Vector3.ZERO, Vector3.ZERO, Vector2(1, 0), 0.0,
		false, false, SkaterMovementRules.Posture.UPRIGHT, _default_cfg(), 1.0 / 120.0, 9, 0, zeroed, 0.0, bc_cfg)
	assert_eq(zeroed.position, plain.position, "zero stagger is a no-op")

# ── Stride power ─────────────────────────────────────────────────────────────

func test_stride_fades_above_the_power_knee() -> void:
	var cfg := _clean_cfg()
	cfg.power_knee_speed = 3.0
	var slow_gain: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(2, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg)) - 2.0
	var fast_gain: float = _speed(SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(1, 0), -PI / 2.0, false, false, DT, cfg)) - 8.0
	assert_almost_eq(slow_gain, cfg.thrust * DT, 1e-4, "below the knee the push is full thrust")
	assert_almost_eq(fast_gain, cfg.thrust * 3.0 / 8.0 * DT, 1e-4, "above it the push is thrust·knee/speed")


# ── Reversing: skid first, then push ─────────────────────────────────────────

func test_opposing_stick_skids_instead_of_pushing_back() -> void:
	var cfg := _clean_cfg()
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(-1, 0), -PI / 2.0, false, false, DT, cfg)
	assert_almost_eq(v.x, 8.0 - cfg.stop_decel * cfg.reverse_skid_fraction * DT, 1e-4,
		"an opposing stick decelerates at the skid rate, not at thrust")
	assert_almost_eq(v.z, 0.0, 1e-5, "dead-opposite stick doesn't turn")


func test_brake_stops_faster_than_the_opposing_stick() -> void:
	var cfg := _default_cfg()
	var skid := Vector3(8, 0, 0)
	var brake := Vector3(8, 0, 0)
	for _i in 10:
		skid = SkaterMovementRules.apply_movement(skid, Vector2(-1, 0), -PI / 2.0, false, false, DT, cfg)
		brake = SkaterMovementRules.apply_movement(brake, Vector2.ZERO, -PI / 2.0, false, true, DT, cfg)
	assert_lt(brake.x, skid.x, "the dedicated stop is the better stop")


func test_opposing_stick_eventually_reverses() -> void:
	var cfg := _default_cfg()
	var v := Vector3(8, 0, 0)
	for _i in 240:
		v = SkaterMovementRules.apply_movement(v, Vector2(-1, 0), -PI / 2.0, false, false, DT, cfg)
	assert_lt(v.x, 0.0, "once stopped, the push takes over in the new direction")


# ── Turning ──────────────────────────────────────────────────────────────────

func test_side_stick_turns_without_adding_speed() -> void:
	var cfg := _clean_cfg()
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg)
	assert_gt(v.z, 0.0, "turns toward the stick")
	assert_almost_eq(_speed(v), 8.0, 1e-4, "a pure turn redirects momentum without adding to it")
	var expected_angle: float = cfg.turn_accel / 8.0 * DT
	assert_almost_eq(atan2(v.z, v.x), expected_angle, 1e-5, "turn rate is turn_accel / speed")


func test_turn_never_overshoots_the_stick() -> void:
	var cfg := _clean_cfg()
	cfg.max_turn_rate = 1000.0
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(1, 0, 0), Vector2(1, 0.01), -PI / 2.0, false, false, 0.5, cfg)
	assert_almost_eq(atan2(v.z, v.x), atan2(0.01, 1.0), 1e-4, "lands on the stick, not past it")


func test_turn_rate_capped_at_low_speed() -> void:
	var cfg := _clean_cfg()
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(1, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg)
	assert_almost_eq(atan2(v.z, v.x), cfg.max_turn_rate * DT, 1e-5, "max_turn_rate binds at low speed")


func test_grip_scales_the_turn() -> void:
	var cfg := _clean_cfg()
	var grippy := _clean_cfg()
	grippy.lateral_grip = 1.1
	var loose := _clean_cfg()
	loose.lateral_grip = 0.9
	var a_neutral: float = atan2(SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, cfg).z, 8.0)
	var a_grippy: float = atan2(SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, grippy).z, 8.0)
	var a_loose: float = atan2(SkaterMovementRules.apply_movement(
		Vector3(8, 0, 0), Vector2(0, 1), -PI / 2.0, false, false, DT, loose).z, 8.0)
	assert_gt(a_grippy, a_neutral, "better edges turn tighter")
	assert_lt(a_loose, a_neutral, "worse edges turn wider")


func test_grip_does_not_touch_straight_drive_or_stops() -> void:
	var cfg := _clean_cfg()
	var loose := _clean_cfg()
	loose.lateral_grip = 0.85
	for brake: bool in [false, true]:
		var a: Vector3 = SkaterMovementRules.apply_movement(
			Vector3(5, 0, 0), Vector2(1, 0), -PI / 2.0, false, brake, DT, cfg)
		var b: Vector3 = SkaterMovementRules.apply_movement(
			Vector3(5, 0, 0), Vector2(1, 0), -PI / 2.0, false, brake, DT, loose)
		assert_eq(a, b, "grip only governs turning (brake=%s)" % brake)


func test_standing_start_pushes_freely_in_any_direction() -> void:
	var cfg := _clean_cfg()
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(0.2, 0, 0), Vector2(0, 1), 0.0, false, false, DT, cfg)
	assert_gt(v.z, 0.0, "below GRIP_MIN_SPEED the push goes where the stick says")
	assert_almost_eq(v.x, 0.2, 1e-5, "with no turn law at a standstill")


# ── Brake: the hockey stop ───────────────────────────────────────────────────

func test_brake_is_a_stop_whatever_the_stick_says() -> void:
	var cfg := _clean_cfg()
	for stick: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1).normalized(),
			Vector2(0, 1), Vector2(-1, -1).normalized()]:
		for posture: SkaterMovementRules.Posture in [SkaterMovementRules.Posture.UPRIGHT,
				SkaterMovementRules.Posture.STANCE]:
			var v: Vector3 = SkaterMovementRules.apply_movement(
				Vector3(8, 0, 0), stick, -PI / 2.0, false, true, DT, cfg, posture)
			var ctx := "stick %s posture %d" % [stick, posture]
			assert_almost_eq(v.x, 8.0 - cfg.stop_decel * DT, 1e-4, ctx)
			assert_almost_eq(v.z, 0.0, 1e-6, "the brake never turns — " + ctx)


# ── Backward skating ─────────────────────────────────────────────────────────

func test_backward_top_speed_is_capped() -> void:
	var cfg := _default_cfg()
	cfg.backward_max_speed_multiplier = 0.7
	var v := Vector3.ZERO
	# Facing -Z (rotation 0), skating +Z: travel runs against facing.
	for _i in 1200:
		v = SkaterMovementRules.apply_movement(v, Vector2(0, 1), 0.0, false, false, DT, cfg)
	assert_almost_eq(_speed(v), cfg.max_speed * 0.7, 0.2, "backward skating tops out lower")


func test_turning_around_at_speed_glides_rather_than_clamps() -> void:
	# Swinging facing around at full speed doesn't yank speed down to the
	# backward cap — the stride just stops adding; glide does the rest.
	var cfg := _default_cfg()
	cfg.backward_max_speed_multiplier = 0.7
	var v: Vector3 = SkaterMovementRules.apply_movement(
		Vector3(0, 0, 9.5), Vector2(0, 1), 0.0, false, false, DT, cfg)
	assert_gt(_speed(v), cfg.max_speed * 0.7, "speed above the backward cap survives the tick")
	assert_lt(_speed(v), 9.5, "but the stride can't add to it")

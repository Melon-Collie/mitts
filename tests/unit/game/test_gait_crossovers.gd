extends GutTest

# The gait's rotations and the sizing seam's positions live on the leg rig's
# bones now, not on Node3Ds — see Skater.leg_bone_euler / leg_bone_position.
const _LEG_L: int = SkaterMeshBuilder.LegBone.LEG_L
const _LEG_R: int = SkaterMeshBuilder.LegBone.LEG_R

# Crossover gait — four behaviors pinned:
#  1. Cadence follows the ARC through a driven turn: stride frequency during a real
#     turn is crossover_phase_per_turn × turn rate, not the straight-line
#     speed law — a tight turn quickens the feet, a wide arc glides.
#  2. Backward turning is gated out: a defender curling backward keeps C-cuts
#     on the speed law (forward crossover roles mirror wrong through the flip).
#  3. Two-beat rhythm: the outside push and the inside under-push ride OPPOSITE
#     halves of the stride cycle (push-push around the corner).
#  4. It crosses: the outside skate passes the inside one every step.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 120.0
const WARMUP_TICKS: int = 300
const MEASURE_TICKS: int = 240
const SPEED: float = 5.0
const TURN_RATE: float = 1.6  # rad/s — at SPEED, ~0.9 of the edge's lateral grip


class Rig:
	var skater: Skater
	var controller: SkaterController
	var coord: SkaterSkatingCoordinator
	var travel: Vector2  # unit travel direction, rotated per tick when turning
	var backward: bool = false


func _make_rig(backward: bool) -> Rig:
	var rig := Rig.new()
	rig.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(rig.skater)
	rig.skater.set_physics_process(false)
	rig.skater.set_process(false)
	rig.controller = SkaterController.new()
	autofree(rig.controller)
	var sm := SkaterStateMachine.new()
	rig.coord = SkaterSkatingCoordinator.new()
	rig.coord.setup(rig.skater, sm, rig.controller)
	rig.travel = Vector2(0.0, -1.0)
	rig.backward = backward
	return rig


# One tick of steady circular (or straight, turn = 0) travel. Positive turn
# rotates travel toward +X — the skater's right when facing along travel — so
# the left leg crosses over and the right leg under-pushes. The stick is held
# 45° into the turn: the physics turns at the full edge rate for any stick off
# travel and drives by its cosine, so this is a driven arc — a crossover. Held
# straight across, it would coast round on the edges (a carve).
func _tick(rig: Rig, turn: float, stick_off: float = PI * 0.25) -> void:
	rig.travel = rig.travel.rotated(turn * DT)
	var facing: Vector2 = -rig.travel if rig.backward else rig.travel
	rig.skater.set_facing(facing)
	rig.skater.velocity = Vector3(rig.travel.x, 0.0, rig.travel.y) * SPEED
	rig.skater.move_intent = rig.travel.rotated(signf(turn) * stick_off) \
			if turn != 0.0 else rig.travel
	rig.coord.apply(DT)


# Mean stride-phase advance rate (rad/s) over MEASURE_TICKS of steady motion.
func _phase_rate(rig: Rig, turn: float) -> float:
	for _i: int in WARMUP_TICKS:
		_tick(rig, turn)
	var prev: float = rig.coord.stride_phase
	var advanced: float = 0.0
	for _i: int in MEASURE_TICKS:
		_tick(rig, turn)
		advanced += wrapf(rig.coord.stride_phase - prev, -PI, PI)
		prev = rig.coord.stride_phase
	return advanced / (MEASURE_TICKS * DT)


func test_crossover_cadence_follows_turn_rate() -> void:
	var straight_rig: Rig = _make_rig(false)
	var straight: float = _phase_rate(straight_rig, 0.0)
	var crossing: float = _phase_rate(_make_rig(false), TURN_RATE)
	var turn_law: float = TURN_RATE * straight_rig.controller.crossover_phase_per_turn
	gut.p("phase rate — straight %.2f, crossover arc %.2f (turn law %.2f) rad/s"
			% [straight, crossing, turn_law])
	assert_lt(straight, 6.5, "straight cruise must stay on the speed law")
	assert_gt(crossing, 9.0, "a driven arc must re-time the feet to the arc")
	assert_almost_eq(crossing, turn_law, 1.5,
			"crossover cadence should approximate crossover_phase_per_turn × turn rate")


func test_backward_turning_keeps_speed_law() -> void:
	var back_turning: float = _phase_rate(_make_rig(true), TURN_RATE)
	gut.p("backward-turn phase rate %.2f rad/s" % back_turning)
	assert_lt(back_turning, 6.5,
			"backward turning must not adopt the crossover cadence (forward gate)")


# Where a skate is drawn, in the skeleton's frame (the body's heading).
func _skate(rig: Rig, left: bool) -> Vector3:
	var sk: Skeleton3D = rig.skater._legs._skeleton
	return sk.get_bone_global_pose(SkaterLegRig._OFFSET
			+ (SkaterMeshBuilder.LegBone.FOOT_L if left else SkaterMeshBuilder.LegBone.FOOT_R)).origin


func test_crossover_strokes_alternate() -> void:
	# A driven right arc, push-push around the corner: the outside (left)
	# skate's push reaches furthest out on one half of the cycle, the inside
	# (right) skate's under-push furthest under the body on the other.
	var rig: Rig = _make_rig(false)
	for _i: int in WARMUP_TICKS:
		_tick(rig, TURN_RATE)
	var out: float = INF
	var out_phase: float = 0.0
	var under: float = INF
	var under_phase: float = 0.0
	for _i: int in MEASURE_TICKS:
		_tick(rig, TURN_RATE)
		var outside: Vector3 = _skate(rig, true)
		var inside: Vector3 = _skate(rig, false)
		if outside.x < out:
			out = outside.x
			out_phase = rig.coord.stride_phase
		if inside.x < under:
			under = inside.x
			under_phase = rig.coord.stride_phase
	var separation: float = absf(wrapf(out_phase - under_phase, -PI, PI))
	gut.p("outside push deepest at phase %.2f, under-push deepest at %.2f — separation %.2f rad"
			% [out_phase, under_phase, separation])
	assert_gt(separation, 2.5, "the two pushes ride opposite halves of the stride cycle")


# The crossover crosses: through a held arc the outside skate passes over to the
# inside of the inside skate on every step, and it is the outside one that does,
# whichever way the turn goes.
func test_the_outside_skate_crosses_over_every_step() -> void:
	for turn: float in [TURN_RATE, -TURN_RATE]:
		var rig: Rig = _make_rig(false)
		for _i: int in WARMUP_TICKS:
			_tick(rig, turn)
		var inside_sign: float = signf(turn)
		var crossings: int = 0
		var crossed: bool = false
		var deepest: float = -INF
		var phase_start: float = rig.coord.stride_phase
		var advanced: float = 0.0
		var prev_phase: float = phase_start
		for _i: int in MEASURE_TICKS:
			_tick(rig, turn)
			advanced += wrapf(rig.coord.stride_phase - prev_phase, -PI, PI)
			prev_phase = rig.coord.stride_phase
			var outside: Vector3 = _skate(rig, turn > 0.0)
			var inside: Vector3 = _skate(rig, turn < 0.0)
			# How far the outside skate is past the inside one, toward the inside.
			var past: float = (outside.x - inside.x) * inside_sign
			deepest = maxf(deepest, past)
			if past > 0.0 and not crossed:
				crossings += 1
			crossed = past > 0.0
		var cycles: float = advanced / TAU
		gut.p("turn %+.1f: %d crossings over %.1f cycles, crossed up to %.2f m"
				% [turn, crossings, cycles, deepest])
		assert_gte(crossings, floori(cycles), "the outside skate crosses on every step")
		assert_gt(deepest, 0.08, "and crosses well past")


# A coasting turn (the stick straight across travel, so no thrust) is carved:
# both skates down, the inside one leading the outside one.
func test_a_carve_leads_with_the_inside_skate() -> void:
	for turn: float in [TURN_RATE, -TURN_RATE]:
		var rig: Rig = _make_rig(false)
		for _i: int in WARMUP_TICKS:
			_tick(rig, turn, PI * 0.5)
		var lead: float = 0.0
		for _i: int in MEASURE_TICKS:
			_tick(rig, turn, PI * 0.5)
			var inside: Vector3 = _skate(rig, turn < 0.0)
			var outside: Vector3 = _skate(rig, turn > 0.0)
			lead += (outside.z - inside.z) / MEASURE_TICKS
		gut.p("turn %+.1f: carve %.2f, inside skate leads by %.2f m"
				% [turn, rig.coord.locomotion_mix().carve, lead])
		assert_gt(rig.coord.locomotion_mix().carve, 0.6, "a coasting turn is carved")
		assert_gt(lead, 0.12, "the inside skate leads")

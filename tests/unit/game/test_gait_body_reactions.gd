extends GutTest

# The gait's rotations and the sizing seam's positions live on the leg rig's
# bones now, not on Node3Ds — see Skater.leg_bone_euler / leg_bone_position.
const _SHIN_L: int = SkaterMeshBuilder.LegBone.SHIN_L

# Reactive body language in the gait (SkaterSkatingCoordinator): the
# check-delivery drive (hitter finishing through a landed hit, armed by the
# host-authoritative broadcast via start_check_drive), the stick-lift working
# posture (keyed off the replicated blade_up), and the celly's legs (reading the
# controller's celebration timer, which the controllers age at physics rate via
# tick_celebration — the gait only reads it, at render rate).

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 120.0

var _skater: Skater = null
var _controller: SkaterController = null
var _coord: SkaterSkatingCoordinator = null


func before_each() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_physics_process(false)
	_skater.set_process(false)
	_controller = SkaterController.new()
	autofree(_controller)
	var sm := SkaterStateMachine.new()
	_coord = SkaterSkatingCoordinator.new()
	_coord.setup(_skater, sm, _controller)
	_skater.set_facing(Vector2(0.0, -1.0))
	_skater.velocity = Vector3.ZERO
	_skater.move_intent = Vector2.ZERO


func _tick(count: int) -> void:
	for _i: int in count:
		# The controllers age the celebration timer at physics rate; the gait
		# (render rate) only reads it. Mirror both here so the coordinator sees the
		# countdown advance.
		_controller.tick_celebration(DT)
		_coord.apply(DT)


func test_check_drive_leans_into_hit_and_settles() -> void:
	# A full-hardness hit straight ahead (world −Z is this body's forward).
	_coord.start_check_drive(Vector3(0.0, 0.0, -1.0), 1.0)
	var min_pitch: float = INF
	var min_shin: float = INF
	for _i: int in 54:  # 0.45 s = check_drive_time
		_coord.apply(DT)
		min_pitch = minf(min_pitch, _coord.trunk_pitch_add)
		min_shin = minf(min_shin, _skater.leg_bone_euler(_SHIN_L).x)
	assert_lt(min_pitch, -0.1,
			"the trunk should drive INTO the hit (peak pitch add %.3f rad)" % min_pitch)
	assert_lt(min_shin, -0.1, "the legs should drive under the finishing shoulder")
	_tick(30)
	assert_almost_eq(_coord.trunk_pitch_add, 0.0, 0.01,
			"the drive should settle out after check_drive_time")


func test_check_drive_refire_hardens_without_restarting() -> void:
	_coord.start_check_drive(Vector3(0.0, 0.0, -1.0), 0.4)
	_tick(20)  # mid-envelope
	_coord.start_check_drive(Vector3(1.0, 0.0, 0.0), 1.0)  # grind re-fire
	# The clock must not restart: the drive finishes on the original timer,
	# plus the trunk inertia filter's ~0.2 s settle tail
	# (trunk_texture_smooth_rate) before the pitch reads as square again.
	_tick(64)  # 20 + 64 ticks = 0.7 s > check_drive_time + settle tail
	assert_almost_eq(_coord.trunk_pitch_add, 0.0, 0.01,
			"a sustained-contact re-fire must not extend the drive forever")


func test_stick_lift_pops_chest_and_releases() -> void:
	_skater.blade_up = true
	_tick(90)
	assert_gt(_coord.trunk_pitch_add, 0.03,
			"the lift should tip the chest up (pitch add %.3f)" % _coord.trunk_pitch_add)
	assert_lt(_skater.leg_bone_euler(_SHIN_L).x, -0.05, "the lift should carry a light working coil")
	_skater.blade_up = false
	_tick(120)
	assert_almost_eq(_coord.trunk_pitch_add, 0.0, 0.01, "the lift read should release")


func test_knee_slide_kneels_with_the_frame_and_timer_ages() -> void:
	_tick(60)
	var standing: float = _coord.crouch_drop
	_controller.start_celebration(1.5, CellyRegistry.KNEE_SLIDE)
	_tick(90)  # mid-window, past the ease
	assert_gt(_coord.crouch_drop, standing + 0.3,
			"the knee slide should put the body down on a knee (drop %.3f, standing %.3f)"
			% [_coord.crouch_drop, standing])
	assert_almost_eq(_coord.frame_drop, _coord.crouch_drop, 0.01,
			"the arms are posed in a frame that goes down with the body")
	# The controllers age the timer at physics rate, on every path including
	# wire-fed remotes. A few grace ticks absorb the float-summation residue.
	_tick(96)
	assert_false(_controller.is_celebrating(), "the timer should have aged out")
	assert_almost_eq(_coord.crouch_drop, standing, 0.02, "and the skater stands back up")


func test_raised_stick_stays_on_its_skates() -> void:
	_tick(60)
	var standing: float = _coord.crouch_drop
	_controller.start_celebration(1.5, CellyRegistry.RAISED_STICK)
	var deepest: float = 0.0
	for _i: int in 180:
		_tick(1)
		deepest = maxf(deepest, _coord.crouch_drop)
	assert_lt(deepest, standing + 0.1, "a bob, never a squat (deepest %.3f)" % deepest)

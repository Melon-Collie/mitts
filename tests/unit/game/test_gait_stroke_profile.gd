extends GutTest

# The stride measured where the eye reads it, at the skates. A skating push is
# explosive and goes out and back; the recovery is slower and comes back in under
# the hips. So, on the skate bones in the lower body's frame:
#  - the push (backward) is the fast phase, not the forward recovery;
#  - the stride covers ground fore and aft;
#  - the pushing skate goes out from the body's midline, wider the harder the
#    skater drives, and comes back in under the hips between pushes.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const LegBone = SkaterMeshBuilder.LegBone
const DT: float = 1.0 / 120.0
const WARMUP_TICKS: int = 240  # let intensity/effort envelopes settle
const MEASURE_TICKS: int = 480 # 4 s — several full cycles at steady state


class Stroke:
	# Per tick, per skate: fore-aft (−Z forward) and lateral distance from the
	# midline, metres.
	var fwd: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var out: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]


# Straight up-ice at `speed`, the stick held; `accel` m/s² of forward
# acceleration fed to the gait's effort read (0 = steady cruise).
func _run(speed: float, accel: float) -> Stroke:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var controller: SkaterController = SkaterController.new()
	autofree(controller)
	var sm := SkaterStateMachine.new()
	var coord := SkaterSkatingCoordinator.new()
	coord.setup(skater, sm, controller)
	skater.set_facing(Vector2(0.0, -1.0))
	skater.move_intent = Vector2(0.0, -1.0)
	var stroke := Stroke.new()
	for i: int in WARMUP_TICKS + MEASURE_TICKS:
		# Past top speed the gait's speed share saturates, so a speed that keeps
		# rising reads as driving at full stride.
		skater.velocity = Vector3(0.0, 0.0, -(speed + accel * DT * float(i)))
		coord.apply(DT)
		skater._process(DT)
		if i < WARMUP_TICKS:
			continue
		var sk: Skeleton3D = skater._legs._skeleton
		for side: int in 2:
			var bone: int = LegBone.SKATE_L if side == 0 else LegBone.SKATE_R
			var p: Vector3 = sk.get_bone_global_pose(SkaterLegRig._OFFSET + bone).origin
			stroke.fwd[side].append(-p.z)
			stroke.out[side].append(absf(p.x))
	return stroke


func test_foot_push_is_faster_than_recovery() -> void:
	var stroke := _run(6.0, 0.0)
	var peak_fwd: float = 0.0   # fastest forward skate speed (recovery)
	var peak_back: float = 0.0  # fastest backward skate speed (the push)
	var swing_min: float = INF
	var swing_max: float = -INF
	for side: int in 2:
		var f: PackedFloat32Array = stroke.fwd[side]
		for i: int in range(1, f.size()):
			var v: float = (f[i] - f[i - 1]) / DT
			peak_fwd = maxf(peak_fwd, v)
			peak_back = maxf(peak_back, -v)
			swing_min = minf(swing_min, f[i])
			swing_max = maxf(swing_max, f[i])
	gut.p("skate: fwd peak %.3f m/s, back peak %.3f m/s, ratio back/fwd %.2f, swing %.0f cm"
			% [peak_fwd, peak_back, peak_back / maxf(peak_fwd, 0.001), (swing_max - swing_min) * 100.0])
	assert_gt(peak_back, peak_fwd, "the push is the fast phase")
	assert_gt(swing_max - swing_min, 0.14, "the stride covers ground fore and aft")


# The width the stride pushes to, against the hip width it lands at.
func _width(stroke: Stroke) -> Vector2:
	var widest: float = 0.0
	var narrowest: float = INF
	for side: int in 2:
		for o: float in stroke.out[side]:
			widest = maxf(widest, o)
			narrowest = minf(narrowest, o)
	return Vector2(narrowest, widest)


func test_the_push_goes_out_and_comes_back_under_the_hips() -> void:
	var cruise: Vector2 = _width(_run(6.0, 0.0))
	var driving: Vector2 = _width(_run(9.5, 9.0))
	gut.p("from the midline: cruising at 6 m/s %.2f..%.2f m, driving at 9.5 m/s %.2f..%.2f m"
			% [cruise.x, cruise.y, driving.x, driving.y])
	assert_lt(cruise.x, 0.2, "lands back under the hips")
	assert_gt(cruise.y, 0.28, "a cruising push goes out past hip width")
	assert_gt(driving.y, 0.42, "a hard push goes wide")
	assert_gt(driving.y, cruise.y + 0.08, "harder drive, wider push")

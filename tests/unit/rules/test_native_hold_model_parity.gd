extends GutTest

# Parity fuzz: the C++ hold model (NativeHoldModel, native/src/) against its
# GDScript reference (SkaterHoldModel.evaluate and project). Seeded RNG over a
# live carrier's body (SkaterIKCoordinator.fill_hold_body), moved, turned and
# rescaled: hands in and out of reach, inside the jersey and over the collar,
# the bottom grip pinned at its floor, the height rule on and off, and anchors
# the projection walks far. Every limit and the held hand must agree.
#
# Pending without the extension (fresh clone, CI without a native build) — run
# native/build.sh.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# Both paths run the same float ops and measure exactly equal here; the room is
# the arm rig's (each elbow is the bottom of a cost, SkaterArmPoses.swivel_bend,
# defined only as well as the cost is flat there), for another compiler.
const TOLERANCE: float = 0.001
# The projection walks that elbow's sleeve and reach for up to PROJECT_STEPS
# steps, so the elbow's float noise can carry into the hand it settles on. A
# slip in the port is centimetres.
const PROJECT_TOLERANCE: float = 0.002
const CASES: int = 400
const SEED: int = 0x484F4C44  # "HOLD" — fixed so failures reproduce.
const _LIMITS: Array[String] = ["fist", "fold", "high", "knob", "shaft", "top reach",
		"top sleeve", "bottom reach", "bottom sleeve", "bottom grip", "total"]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _rng := RandomNumberGenerator.new()


func _v(spread: float) -> Vector3:
	return Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread),
			_rng.randf_range(-spread, spread))


func _carrier_body() -> SkaterHoldModel.Body:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var controller := SkaterController.new()
	add_child_autofree(controller)
	controller.setup(skater, puck, gs)
	controller.apply_attributes(PlayerAttributes.neutral())
	controller.set_process(false)
	controller.set_physics_process(false)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	puck.set_carrier(skater)
	controller.on_puck_picked_up_network()
	var input := InputState.new()
	for _i: int in 30:
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = skater.global_position + Vector3(0.4, 0.0, -1.1)
		input.mouse_world_pos.y = 0.0
		skater.capture_prev_blade_contact()
		controller._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)
	var body := SkaterHoldModel.Body.new()
	controller._ik.fill_hold_body(body)
	return body


# `base` moved, turned and rescaled into `out`, as other builds and trunks have it.
func _perturb(base: SkaterHoldModel.Body, out: SkaterHoldModel.Body) -> void:
	var turn := Basis.from_euler(_v(0.35))
	var scale: float = _rng.randf_range(0.85, 1.15)
	var shift: Vector3 = _v(0.05)
	for arm: int in 2:
		out.shoulders[arm] = turn * base.shoulders[arm] * scale + shift + _v(0.03)
		out.rest_poles[arm] = (turn * base.rest_poles[arm]).normalized()
		out.outward[arm] = (turn * base.outward[arm]).normalized()
		out.wrists[arm] = base.wrists[arm] + _v(0.1)
	out.back = (turn * base.back).normalized()
	out.torso = Transform3D(turn * base.torso.basis.scaled(Vector3.ONE * scale),
			turn * base.torso.origin * scale + shift)
	out.upper_len = base.upper_len * scale
	out.forearm_len = base.forearm_len * scale
	out.reach = base.reach * scale
	out.slack = base.slack * scale
	out.elbow_flex_max = base.elbow_flex_max
	out.fist_radius = base.fist_radius * scale
	out.knob_extend = base.knob_extend
	out.knob_radius = base.knob_radius
	out.spacing = base.spacing * scale
	out.grip = _rng.randf_range(0.15, 0.4)
	out.hand_below_shoulder = SkaterHoldModel.HAND_BELOW_SHOULDER_M if _rng.randf() < 0.6 else INF


func _report_array(r: SkaterHoldModel.Report) -> PackedFloat64Array:
	return PackedFloat64Array([r.fist, r.fold, r.high, r.knob, r.shaft, r.top.reach_past,
			r.top.sleeve, r.bottom.reach_past, r.bottom.sleeve, r.bottom_grip, r.total()])


func test_the_native_hold_model_matches_the_gdscript() -> void:
	var native: RefCounted = SkaterHoldModel.native()
	if native == null:
		NativeParityGuard.report_missing(self, "NativeHoldModel")
		return
	_rng.seed = SEED
	var base: SkaterHoldModel.Body = _carrier_body()
	var body := SkaterHoldModel.Body.new()
	var report := SkaterHoldModel.Report.new()
	var vectors := PackedVector3Array()
	vectors.resize(SkaterHoldModel.PACKED_VECTORS)
	var scalars := PackedFloat64Array()
	scalars.resize(SkaterHoldModel.PACKED_SCALARS)
	var worst_eval: float = 0.0
	var worst_eval_at: String = ""
	var worst_project: float = 0.0
	var walked: float = 0.0
	var unheld: int = 0
	for i: int in CASES:
		_perturb(base, body)
		SkaterHoldModel.pack(body, vectors, scalars)
		var top: Vector3 = body.shoulders[0]
		# A hand round the top shoulder, and a blade a stick's length off it on the ice.
		var hand: Vector3 = top + Vector3(_rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-0.7, 0.15), _rng.randf_range(-0.7, 0.3))
		var flat := Vector2.from_angle(_rng.randf_range(-PI, PI)) * _rng.randf_range(0.3, 1.3)
		var blade := Vector3(hand.x + flat.x, top.y - _rng.randf_range(1.0, 1.5), hand.z + flat.y)
		SkaterHoldModel.evaluate(body, hand, blade, report)
		var want: PackedFloat64Array = _report_array(report)
		var got: PackedFloat64Array = native.evaluate(vectors, body.torso, scalars, hand, blade)
		if report.total() > 0.0:
			unheld += 1
		for k: int in want.size():
			var gap: float = absf(want[k] - got[k])
			if not is_finite(gap):
				gap = 0.0 if want[k] == got[k] else INF
			if gap > worst_eval:
				worst_eval = gap
				worst_eval_at = "case %d %s: %.6f vs %.6f" % [i, _LIMITS[k], want[k], got[k]]
		var lie: float = deg_to_rad(_rng.randf_range(35.0, 55.0))
		var held_gd: Vector3 = SkaterHoldModel.project(body, hand, blade, lie, report)
		var held_cc: Vector3 = native.project(vectors, body.torso, scalars, hand, blade, lie)
		worst_project = maxf(worst_project, held_gd.distance_to(held_cc))
		walked = maxf(walked, held_gd.distance_to(hand))
	gut.p("evaluate worst %.7f (%s); project worst %.7f m; furthest walk %.2f m; %d/%d unheld" % [
			worst_eval, worst_eval_at, worst_project, walked, unheld, CASES])
	assert_gt(unheld, CASES / 4, "the fuzz reaches poses the body cannot hold")
	assert_lt(worst_eval, TOLERANCE, "every limit agrees")
	assert_lt(worst_project, PROJECT_TOLERANCE, "the held hand agrees")

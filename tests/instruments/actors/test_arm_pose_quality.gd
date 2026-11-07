extends GutTest

# How the arms are posed all round the body, by the measures an elbow choice
# decides: the live controller carrying, the cursor held at each bearing and
# reach off the facing (+ forehand), standing with the facing held so the
# blade goes round the body, a fresh carrier for each. Over the last ticks of
# each settle, per arm (top / bottom), the worst of:
#   slv   the sleeve in the jersey past contact (mm, 0.03), from the upper arm's
#         elbow half to the wrist — the fist is where gameplay put the hand
#   avd   how much of that some other elbow on the same circle would have
#         kept out (mm): the share the elbow's choice is answerable for
#   elev  the upper arm raised from hanging, past 60° (°): the chicken wing
#   back  the upper arm behind the chest's plane (°, past 30)
#   slip  the shaft off the glove's grip, where the wrist ran out (°)
#   step  the elbow's largest move in one tick with the cursor held (mm)
# Then the cursor settled at -150° and swept to +150° at a carry's pace,
# standing and skating: the elbow's largest move in a tick, against the hand's in the same
# tick, and how often it outran the hand.
#
# Asserts nothing: run it when the question is "how do the arms solve".
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors -gselect=test_arm_pose_quality
# ARM_QUALITY_SWEEPS_ONLY=1 runs the sweeps alone, in seconds;
# ARM_QUALITY_GDSCRIPT=1 draws the arms by the GDScript reference, not the port.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const ANGLES_DEG: Array[float] = [-150.0, -120.0, -90.0, -60.0, -30.0, 0.0, 30.0, 60.0,
		90.0, 120.0, 150.0]
const RADII_M: Array[float] = [0.5, 0.8, 1.1, 1.5]
const SETTLE_TICKS: int = 120
const WATCH_TICKS: int = 30
# Warm-up, settle and sweep together skate the rink's length from SKATE_START_Z
# and no further: past it the skater meets the end boards.
const SKATE_WARMUP_TICKS: int = 180
const SWEEP_SETTLE_TICKS: int = 60
const SKATE_START_Z: float = 26.0
# Only the upper arm's elbow half: hanging relaxed, the half by the armpit lies
# against the jersey's side, where the skin blends the two.
const ELBOW_HALF: float = 0.5
const BACK_FROM_DEG: float = 30.0
const ELEV_FROM_DEG: float = 60.0
const CIRCLE_SAMPLES: int = 72
const MEASURES: Array[String] = ["slv", "avd", "elev", "back", "slip", "step"]
const SWEEP_RATE_DEG_S: float = 90.0
const SWEEP_TICKS: int = int(300.0 / SWEEP_RATE_DEG_S / DT)
const _ARMS: Array[Array] = [
	[UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM, UpperBone.TOP_ELBOW, UpperBone.TOP_HAND],
	[UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_ELBOW,
			UpperBone.BOTTOM_HAND],
]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _last_elbow: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _last_hand: Array[Vector3] = [Vector3.INF, Vector3.INF]


func test_arm_pose_quality() -> void:
	gut.p("\nnative arms: %s" % (ClassDB.class_exists(&"NativeArmRig")
			and OS.get_environment("ARM_QUALITY_GDSCRIPT") != "1"))
	for arm: int in (0 if OS.get_environment("ARM_QUALITY_SWEEPS_ONLY") == "1" else 2):
		var grids: Dictionary = {}
		var totals: Dictionary = {}
		for m: String in MEASURES:
			grids[m] = []
			totals[m] = 0.0
		for a: float in ANGLES_DEG:
			var rows: Dictionary = {}
			for m: String in MEASURES:
				rows[m] = []
			for r: float in RADII_M:
				var worst: Dictionary = _cell(a, r, arm)
				for m: String in MEASURES:
					(rows[m] as Array).append(worst[m])
					totals[m] = maxf(totals[m], worst[m])
			for m: String in MEASURES:
				(grids[m] as Array).append(rows[m])
		gut.p("\n══ %s arm, standing, facing held (worst: %s)" % [
				"top" if arm == 0 else "bottom", _fmt(totals)])
		for m: String in MEASURES:
			gut.p(_grid(m, grids[m]))
	for skating: bool in [false, true]:
		for r: float in [0.6, 1.2]:
			gut.p(_sweep(r, skating))
	assert_true(true)


func _fmt(totals: Dictionary) -> String:
	return "slv %.0f mm, avd %.0f mm, elev %.0f°, back %.0f°, slip %.0f°, step %.0f mm" % [
			totals["slv"], totals["avd"], totals["elev"], totals["back"], totals["slip"],
			totals["step"]]


func _grid(m: String, rows: Array) -> String:
	var titles: Dictionary = {"slv": "sleeve in the jersey (mm)",
		"avd": "of it, another elbow would have kept out (mm)",
		"elev": "upper arm raised past 60° (°)", "back": "upper arm behind the chest (°)",
		"slip": "shaft off the grip (°)", "step": "elbow's largest tick, held (mm)"}
	var out: String = "  %s\n         " % titles[m]
	for r: float in RADII_M:
		out += "%6.1fm" % r
	for i: int in ANGLES_DEG.size():
		out += "\n  %+5.0f° " % ANGLES_DEG[i]
		for v: float in rows[i]:
			out += "      ." if v <= 0.5 else "%7.0f" % v
	return out


func _cell(deg: float, r: float, arm: int) -> Dictionary:
	_build(false)
	var aim: Vector3 = _aim(deg, r)
	var worst: Dictionary = {}
	for k: String in MEASURES:
		worst[k] = 0.0
	var input := InputState.new()
	_last_elbow[arm] = Vector3.INF
	for i: int in SETTLE_TICKS:
		_step(input, aim, false)
		if i < SETTLE_TICKS - WATCH_TICKS:
			continue
		var m: Dictionary = _measure(arm)
		for k: String in MEASURES:
			worst[k] = maxf(worst[k], m[k])
	_free()
	return worst


# The cursor swept round the body: the elbow's per-tick move against the
# hand's, and how many ticks it moved more than 2 cm (a flip, at a carry's pace).
func _sweep(r: float, skating: bool) -> String:
	_build(skating)
	var input := InputState.new()
	var out: String = "\n══ sweep at %.1f m, %s" % [r, "skating" if skating else "standing"]
	for arm: int in 2:
		_last_elbow[arm] = Vector3.INF
	var worst_ratio: Array[float] = [0.0, 0.0]
	var worst_step: Array[float] = [0.0, 0.0]
	var flips: Array[int] = [0, 0]
	var at_deg: Array[float] = [0.0, 0.0]
	for _i: int in SWEEP_SETTLE_TICKS:
		_step(input, _aim(-150.0, r), skating)
	for arm: int in 2:
		_measure(arm)
	for i: int in SWEEP_TICKS:
		var deg: float = -150.0 + SWEEP_RATE_DEG_S * DT * i
		_step(input, _aim(deg, r), skating)
		for arm: int in 2:
			var m: Dictionary = _measure(arm)
			var hand_step: float = m["hand_step"]
			var step: float = m["step"]
			if step > hand_step + 10.0:
				flips[arm] += 1
			if step > worst_step[arm]:
				worst_step[arm] = step
				at_deg[arm] = deg
			worst_ratio[arm] = maxf(worst_ratio[arm], step / maxf(hand_step, 1.0))
	for arm: int in 2:
		out += "\n  %s: largest elbow tick %.0f mm (cursor %+.0f°), %.1f× the hand's, %d ticks it outran the hand by 1 cm" % [
				"top" if arm == 0 else "bottom", worst_step[arm], at_deg[arm], worst_ratio[arm],
				flips[arm]]
	_free()
	return out


func _aim(deg: float, r: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	var fh: float = signf(_skater.bottom_shoulder.position.x)
	return Vector3(sin(a) * r * fh, 0.0, -cos(a) * r)


func _measure(arm: int) -> Dictionary:
	var body: Skeleton3D = _skater._arms._skeleton
	var parts: Array = _ARMS[arm]
	var upper: Transform3D = body.get_bone_global_pose(parts[0])
	var shoulder: Vector3 = upper.origin + upper.basis.z * 0.5
	var elbow: Vector3 = body.get_bone_global_pose(parts[2]).origin
	var hand: Vector3 = body.get_bone_global_pose(parts[3]).origin
	var spine: Basis = body.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE).basis.orthonormalized()
	var u: Vector3 = spine.inverse() * (elbow - shoulder).normalized()
	var out: Dictionary = {}
	out["slv"] = _sleeve_depth(shoulder, elbow, hand) * 1000.0
	out["avd"] = maxf(out["slv"] - _best_depth(shoulder, elbow, hand) * 1000.0, 0.0)
	out["elev"] = maxf(rad_to_deg(acos(clampf(-u.y, -1.0, 1.0))) - ELEV_FROM_DEG, 0.0)
	out["back"] = maxf(rad_to_deg(asin(clampf(u.z, -1.0, 1.0))) - BACK_FROM_DEG, 0.0)
	out["slip"] = _slip(arm)
	out["step"] = 0.0 if _last_elbow[arm] == Vector3.INF \
			else elbow.distance_to(_last_elbow[arm]) * 1000.0
	out["hand_step"] = 0.0 if _last_hand[arm] == Vector3.INF \
			else hand.distance_to(_last_hand[arm]) * 1000.0
	_last_elbow[arm] = elbow
	_last_hand[arm] = hand
	return out


func _sleeve_depth(shoulder: Vector3, elbow: Vector3, hand: Vector3) -> float:
	var deepest: float = 0.0
	for k: int in 9:
		var along: float = float(k) / 8.0
		for p: Vector3 in [shoulder.lerp(elbow, lerpf(ELBOW_HALF, 1.0, along)),
				elbow.lerp(hand, along * 0.85)]:
			deepest = maxf(deepest, SkaterMeshBuilder.SLEEVE_RADIUS_M - SkaterArmPoses.SWIVEL_CONTACT_M
					- _skater._arms.torso_clearance(p))
	return deepest


# The least sleeve depth any elbow on this arm's circle would have.
func _best_depth(shoulder: Vector3, elbow: Vector3, hand: Vector3) -> float:
	var axis: Vector3 = (hand - shoulder).normalized()
	var foot: Vector3 = shoulder + axis * (elbow - shoulder).dot(axis)
	var off: Vector3 = elbow - foot
	var best: float = INF
	for k: int in CIRCLE_SAMPLES:
		best = minf(best, _sleeve_depth(shoulder,
				foot + off.rotated(axis, TAU * k / CIRCLE_SAMPLES), hand))
	return best


# How far the shaft sits off the glove's grip (°), as tools/arm_sweep_runner.gd
# measures it.
func _slip(arm: int) -> float:
	var parts: Array = _ARMS[arm]
	var hand_local: Vector3 = _skater.drawn_top_hand() if arm == 0 else _skater.bottom_hand.position
	var shaft: Vector3 = _skater.drawn_upper_body().basis * _skater.stick_grip_axis(hand_local)
	if shaft == Vector3.ZERO:
		return 0.0
	var fist: Transform3D = _skater._arms._skeleton.get_bone_global_pose(parts[3])
	var grip: float = _skater.top_grip_angle_deg if arm == 0 else _skater.bottom_grip_angle_deg
	return absf(rad_to_deg((-fist.basis.y).angle_to(shaft.normalized())) - grip)


func _build(skating: bool) -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, gs)
	_controller.apply_attributes(PlayerAttributes.neutral())
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT,
			SKATE_START_Z if skating else 0.0)
	_skater._process(DT)
	_skater._arms.native_enabled = OS.get_environment("ARM_QUALITY_GDSCRIPT") != "1"
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	_last_elbow = [Vector3.INF, Vector3.INF]
	_last_hand = [Vector3.INF, Vector3.INF]
	if skating:
		var input := InputState.new()
		for _i: int in SKATE_WARMUP_TICKS:
			_step(input, Vector3(0.0, 0.0, -1.2), true)


func _free() -> void:
	_skater.get_parent().remove_child(_skater)
	_skater.queue_free()


func _step(input: InputState, aim: Vector3, skating: bool) -> void:
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
	if not skating:
		_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_skater.velocity = Vector3.ZERO
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
	# The cursor stays where it was put across the ice, off up-ice (the facing
	# held standing, the travel skating): aimed off the facing as it turns, a
	# cursor behind him runs round with him and he spins after it.
	input.mouse_world_pos = _skater.global_position + aim
	input.mouse_world_pos.y = 0.0
	_skater.capture_prev_blade_contact()
	_controller._process_input(input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)

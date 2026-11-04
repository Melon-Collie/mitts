extends GutTest

# Where the carry clips, all round the body: the live controller carrying, the
# cursor held at each bearing and reach off the facing (+ forehand), standing
# with the facing held (so the blade goes round the body) and skating up-ice,
# a fresh carrier for each. Over the last ticks of each settle, the worst of:
#   arm   a sleeve or fist in the jersey past its surface (mm; the armhole's own
#         seam left out, as tools/arm_sweep_runner.gd leaves it)
#   jer   the shaft in the jersey (mm)
#   leg   the shaft in the pants or socks (mm)
#   off   the bottom glove off the shaft (mm)
# A grid per measure, bearings down and reaches across; "." is clear.
#
# Asserts nothing: run it when the question is "where does the carry clip".
#   bash .claude/hooks/run-gut.sh -gdir=res://tests/instruments/actors -gselect=test_carry_clipping

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
const LegBone = SkaterMeshBuilder.LegBone
const ANGLES_DEG: Array[float] = [-150.0, -135.0, -120.0, -105.0, -90.0, -75.0, -60.0,
		-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 105.0, 120.0, 135.0,
		150.0]
const RADII_M: Array[float] = [0.5, 0.8, 1.1, 1.4, 1.8]
const SETTLE_TICKS: int = 120
const WATCH_TICKS: int = 45
const SKATE_WARMUP_TICKS: int = 240
const SKATE_START_Z: float = 26.0
const ARMHOLE_M: float = 0.12
const SHAFT_RADIUS_M: float = 0.015
const SHAFT_SAMPLES: int = 16
# The shaft from this share of the way down from the top hand: the top fist
# itself sits on it.
const SHAFT_FROM: float = 0.12
const MEASURES: Array[String] = ["arm", "jer", "leg", "off"]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater
var _controller: SkaterController
var _thigh_r: float = 0.0
var _shin_r: float = 0.0


func test_carry_clipping() -> void:
	for skating: bool in [false, true]:
		var grids: Dictionary = {}
		for m: String in MEASURES:
			grids[m] = []
		var counts: Dictionary = {}
		for a: float in ANGLES_DEG:
			var rows: Dictionary = {}
			for m: String in MEASURES:
				rows[m] = []
			for r: float in RADII_M:
				var worst: Dictionary = _cell(a, r, skating)
				for m: String in MEASURES:
					(rows[m] as Array).append(worst[m])
					if worst[m] > 0.005:
						counts[m] = int(counts.get(m, 0)) + 1
			for m: String in MEASURES:
				(grids[m] as Array).append(rows[m])
		var what: String = "skating up-ice" if skating else "standing, facing held"
		gut.p("\n══ %s (mm past the surface; cells over 5 mm: %s)" % [what, counts])
		for m: String in MEASURES:
			gut.p(_grid(m, grids[m]))
	assert_true(true)


func _grid(m: String, rows: Array) -> String:
	var titles: Dictionary = {"arm": "arm in the jersey", "jer": "shaft in the jersey",
		"leg": "shaft in the legs", "off": "bottom glove off the shaft"}
	var out: String = "  %s\n         " % titles[m]
	for r: float in RADII_M:
		out += "%6.1fm" % r
	for i: int in ANGLES_DEG.size():
		out += "\n  %+5.0f° " % ANGLES_DEG[i]
		for v: float in rows[i]:
			out += "      ." if v <= 0.005 else "%7.0f" % (v * 1000.0)
	return out


# The worst of each measure over the last WATCH_TICKS of a carry settled with
# the cursor at `deg` and `r` m off the facing.
func _cell(deg: float, r: float, skating: bool) -> Dictionary:
	_build(skating)
	var a: float = deg_to_rad(deg)
	var fh: float = signf(_skater.bottom_shoulder.position.x)
	# Facing -Z, +X the skater's right; the forehand is the bottom shoulder's side.
	var aim := Vector3(sin(a) * r * fh, 0.0, -cos(a) * r)
	var worst: Dictionary = {"arm": -INF, "jer": -INF, "leg": -INF, "off": -INF}
	var input := InputState.new()
	for i: int in SETTLE_TICKS:
		_step(input, aim, skating)
		if i < SETTLE_TICKS - WATCH_TICKS:
			continue
		worst["arm"] = maxf(worst["arm"], _arm_depth())
		var shaft: Vector2 = _shaft_depth()
		worst["jer"] = maxf(worst["jer"], shaft.x)
		worst["leg"] = maxf(worst["leg"], shaft.y)
		worst["off"] = maxf(worst["off"], _bottom_off())
	_skater.get_parent().remove_child(_skater)
	_skater.queue_free()
	return worst


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
	puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()
	if _thigh_r <= 0.0:
		_thigh_r = _widest(SkaterConnectedPants.leg_stations(false))
		_shin_r = _widest(SkaterConnectedPants.leg_stations(true))
	if skating:
		var input := InputState.new()
		for _i: int in SKATE_WARMUP_TICKS:
			_step(input, Vector3(0.0, 0.0, -1.2), true)


func _step(input: InputState, aim: Vector3, skating: bool) -> void:
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
	if not skating:
		_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		_skater.velocity = Vector3.ZERO
		_controller._pose.facing = Vector2(0.0, -1.0)
		_skater.set_facing(_controller._pose.facing)
	input.mouse_world_pos = _skater.global_position + _skater.global_transform.basis * aim
	input.mouse_world_pos.y = 0.0
	_skater.capture_prev_blade_contact()
	_controller._process_input(input, DT)
	_skater._physics_process(DT)
	_skater._process(DT)


# Either arm's deepest point in the jersey past its sleeve or fist (m).
func _arm_depth() -> float:
	var body: Skeleton3D = _skater._arms._skeleton
	var deepest: float = -INF
	for arm: Array in [[UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM, UpperBone.TOP_HAND],
			[UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_HAND]]:
		for seg: int in 2:
			var pose: Transform3D = body.get_bone_global_pose(arm[seg])
			var length: float = pose.basis.z.length()
			for k: int in 9:
				var along: float = float(k) / 8.0
				if seg == 0 and along * length < ARMHOLE_M:
					continue
				var p: Vector3 = pose.origin + pose.basis.z * (0.5 - along)
				deepest = maxf(deepest, SkaterMeshBuilder.SLEEVE_RADIUS_M
						- _skater._arms.torso_clearance(p))
		deepest = maxf(deepest, _skater.hand_sphere_radius
				- _skater._arms.torso_clearance(body.get_bone_global_pose(arm[2]).origin))
	return deepest


# The shaft's deepest point in the jersey (x) and in the legs (y), m, from just
# below the top hand to the heel, as drawn (the skeleton's space).
func _shaft_depth() -> Vector2:
	var ub: Transform3D = _skater.drawn_upper_body()
	var hand: Vector3 = ub * _skater.drawn_top_hand()
	var heel: Vector3 = ub * _skater.drawn_blade().origin
	var skel: Skeleton3D = _skater._arms._skeleton
	var legs: Array[PackedVector3Array] = []
	for leg: Array in [[LegBone.LEG_L, LegBone.KNEE_L, LegBone.SKATE_L],
			[LegBone.LEG_R, LegBone.KNEE_R, LegBone.SKATE_R]]:
		var joints := PackedVector3Array()
		for bone: int in leg:
			joints.append(skel.get_bone_global_pose(SkaterBodySkeleton.LEG_BONE_OFFSET + bone).origin)
		legs.append(joints)
	var jersey: float = -INF
	var legs_depth: float = -INF
	for k: int in SHAFT_SAMPLES + 1:
		var p: Vector3 = hand.lerp(heel, lerpf(SHAFT_FROM, 1.0, float(k) / SHAFT_SAMPLES))
		jersey = maxf(jersey, SHAFT_RADIUS_M - _skater._arms.torso_clearance(p))
		for j: PackedVector3Array in legs:
			legs_depth = maxf(legs_depth, _thigh_r + SHAFT_RADIUS_M
					- p.distance_to(Geometry3D.get_closest_point_to_segment(p, j[0], j[1])))
			legs_depth = maxf(legs_depth, _shin_r + SHAFT_RADIUS_M
					- p.distance_to(Geometry3D.get_closest_point_to_segment(p, j[1], j[2])))
	return Vector2(jersey, legs_depth)


# How far the drawn bottom glove sits off the drawn shaft (m).
func _bottom_off() -> float:
	var hand: Vector3 = _skater.drawn_top_hand()
	var shaft: Vector3 = _skater.drawn_blade().origin - hand
	var bh: Vector3 = _skater.bottom_hand.position
	var t: float = clampf((bh - hand).dot(shaft) / shaft.length_squared(), 0.0, 1.0)
	return bh.distance_to(hand + shaft * t)


static func _widest(stations: PackedVector3Array) -> float:
	var widest: float = 0.0
	for s: Vector3 in stations:
		widest = maxf(widest, s.y)
	return widest

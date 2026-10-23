extends GutTest

# Measures where the drawn body pops. Skates the real controller through the
# transitions a player makes (scenarios(), one list for every reader) and
# reports, per region of the figure, the largest per-frame jerk any bone made:
# the second difference of its position, the skater's own travel taken out. A
# stroke moves a joint smoothly (a few mm per tick²); a pop is a frame where one
# jumps. Read by the instrument (instruments/actors/test_body_smoothness.gd),
# which prints every scenario, and the gate (unit/actors/test_body_stays_smooth.gd),
# which bounds the transitions.

const DT: float = 1.0 / 120.0
const UpperBone = SkaterMeshBuilder.UpperBone
const LEG: int = SkaterBodySkeleton.LEG_BONE_OFFSET
# Ticks every scenario skates before its first measured frame, to settle the
# springs a fresh spawn starts out of.
const SETTLE_TICKS: int = 120
# A jerk above this (mm per tick²) is listed frame by frame, not just as the max.
const SPIKE_MM: float = 8.0

# Scenario names for the cellies, by CellyRegistry index.
const CELLY_NAMES: Array[String] = ["raised stick", "sword sheath", "knee slide",
		"hot stick", "bow and arrow", "can't hear you"]
const REGIONS: Dictionary = {
	"legs": [LEG + 0, LEG + 1, LEG + 2, LEG + 3, LEG + 5, LEG + 6,
			LEG + 7, LEG + 8, LEG + 9, LEG + 10, LEG + 12, LEG + 13],
	"trunk": [SkaterBodySkeleton.HIPS_BONE, SkaterBodySkeleton.WAIST_BONE,
			SkaterBodySkeleton.SPINE_BONE, SkaterBodySkeleton.NECK_BONE,
			UpperBone.TORSO, UpperBone.PELVIS, UpperBone.SHOULDER_L, UpperBone.SHOULDER_R],
	"head": [UpperBone.HELMET],
	"top_arm": [UpperBone.TOP_UPPER_ARM, UpperBone.TOP_FOREARM, UpperBone.TOP_HAND],
	"bot_arm": [UpperBone.BOTTOM_UPPER_ARM, UpperBone.BOTTOM_FOREARM, UpperBone.BOTTOM_HAND],
}


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func _rig(start_z: float) -> void:
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(30.0, 0.0, 30.0)
	_skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, start_z)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = SkaterController.new()
	add_child_autofree(_controller)
	_controller.setup(_skater, _puck, state)
	# GameManager's half of a release, as a client runs it: the puck leaves the
	# blade inside the release, before the follow-through begins.
	_controller.puck_release_requested.connect(
			func(_dir: Vector3, _power: float, _slapper: bool) -> void: _drop())
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_controller._pose.facing = Vector2(0.0, -1.0)
	_skater.set_facing(Vector2(0.0, -1.0))


# Every tracked point, world space less the skater's position. The skeleton's
# own global_transform is stale in a hand-ticked harness, so compose by hand.
func _sample() -> Dictionary:
	var body: Skeleton3D = _skater.mesh_root.get_node("BodyRig") as Skeleton3D
	var root: Transform3D = _skater.global_transform * _skater.mesh_root.transform * body.transform
	var at: Vector3 = _skater.global_position
	var out: Dictionary = {}
	for region: String in REGIONS:
		var pts := PackedVector3Array()
		for bone: int in REGIONS[region]:
			pts.append((root * body.get_bone_global_pose(bone)).origin - at)
		out[region] = pts
	var stick_xf: Transform3D = _skater.global_transform * _skater.mesh_root.transform \
			* _skater.upper_body.transform * _skater.stick_mesh.transform
	var stick := PackedVector3Array()
	stick.append(stick_xf.origin - at)
	stick.append(stick_xf * Vector3(0.0, 0.0, 0.5) - at)
	stick.append(stick_xf * Vector3(0.0, 0.0, -0.5) - at)
	out["stick"] = stick
	return out


func _context(i: int) -> String:
	var m: LocomotionRules.Mix = _controller._skating.locomotion_mix()
	var names: Array[String] = ["glide", "stride", "cross", "carve", "back", "shuffle",
			"skid", "tight", "stop"]
	var w: Array[float] = [m.glide, m.stride, m.crossover, m.carve, m.backward,
			m.shuffle, m.skid, m.tight, m.stop]
	var mix: String = ""
	for k: int in w.size():
		if w[k] > 0.15:
			mix += "%s %.2f " % [names[k], w[k]]
	var v := Vector2(_skater.velocity.x, _skater.velocity.z)
	var state: String = SkaterStateMachine.State.keys()[_controller._sm.get_state()]
	return "t%d %s puck=%s %.1fm/s lean=%.0f° twist=%.0f° | %s" % [i, state,
			_controller.has_puck, v.length(), rad_to_deg(_skater.upper_body.rotation.x),
			rad_to_deg(_skater.upper_body.rotation.y), mix]


# Runs `steer` (fills the input for tick i and returns the cursor's offset; i
# counts from the first measured tick, negative while settling) for `ticks`,
# from `start_z` (pick it so the skate stays well inside the boards), and prints
# the worst jerk per region and the worst ticks.
# `puck_ahead` ≥ 0 keeps a loose puck that far up-ice of the skater, skating
# with him, until something carries it: something for the stick to reach for.
# Skates one scenario and returns each region's worst jerk (mm/tick²) from tick
# `from_tick` on. With `report`, prints the worst per region and every frame
# over SPIKE_MM.
func measure(s: Dictionary, report: bool = false, from_tick: int = 2) -> Dictionary:
	var steer: Callable = s["steer"]
	var puck_ahead: float = s["puck_ahead"]
	_rig(s["start_z"])
	var input := InputState.new()
	var hist: Array[Dictionary] = []
	var worst: Dictionary = {}
	var rows: Array = []
	for i: int in range(-SETTLE_TICKS, int(s["ticks"])):
		input.delta = DT
		input.host_timestamp += DT
		input.brake = false
		input.stance_held = false
		input.block_held = false
		input.shoot_held = false
		input.shoot_pressed = false
		input.slap_held = false
		input.slap_pressed = false
		input.quick_pass_pressed = false
		input.hit_held = false
		if puck_ahead >= 0.0 and _puck.get_carrier() == null:
			_puck.global_position = _skater.global_position + _up(puck_ahead)
			_puck.global_position.y = 0.0
			_puck.linear_velocity = _skater.velocity
		var aim: Vector3 = steer.call(input, i)
		input.mouse_world_pos = _skater.global_position + aim
		input.mouse_world_pos.y = 0.0
		_controller._process_input(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)
		hist.append(_sample())
		if hist.size() > 3:
			hist.pop_front()
		if i < from_tick or hist.size() < 3:
			continue
		var line: String = ""
		var tick_max: float = 0.0
		for region: String in hist[2]:
			var a: PackedVector3Array = hist[0][region]
			var b: PackedVector3Array = hist[1][region]
			var c: PackedVector3Array = hist[2][region]
			var region_max: float = 0.0
			for k: int in c.size():
				region_max = maxf(region_max, (c[k] - 2.0 * b[k] + a[k]).length() * 1000.0)
			if not worst.has(region) or region_max > float(worst[region][0]):
				worst[region] = [region_max, _context(i) if report else ""]
			if report:
				line += "%s %5.1f " % [region, region_max]
			tick_max = maxf(tick_max, region_max)
		if report and tick_max > SPIKE_MM:
			rows.append([tick_max, line + "| " + _context(i)])
	if report:
		gut.p("── %s" % s["name"])
		for region: String in worst:
			gut.p("  %-8s max %5.1f mm/tick²  at %s" % [region, worst[region][0], worst[region][1]])
		rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		for r: int in mini(rows.size(), 12):
			gut.p("    " + String(rows[r][1]))
		if rows.size() > 12:
			gut.p("    … %d more ticks over %.0f mm" % [rows.size() - 12, SPIKE_MM])
	var out: Dictionary = {}
	for region: String in worst:
		out[region] = float(worst[region][0])
	return out


static func _up(dist: float) -> Vector3:
	return Vector3(0.0, 0.0, -dist)


func _pickup() -> void:
	_puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network()


func _drop() -> void:
	_puck.set_carrier(null)
	_controller.on_puck_released_network()


func _add(out: Array[Dictionary], scenario_name: String, ticks: int, steer: Callable,
		start_z: float = 0.0, puck_ahead: float = -1.0) -> void:
	out.append({"name": scenario_name, "ticks": ticks, "steer": steer, "start_z": start_z,
			"puck_ahead": puck_ahead})


func scenarios() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Noise floor: a steady stride, cursor ahead at a comfortable carry.
	_add(out, "steady stride, cursor 1.5 m ahead", 240, func(inp: InputState, _i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		return _up(1.5), 26.0)
	# Cursor far ahead (the usual case: the mouse is somewhere up the ice).
	_add(out, "steady stride, cursor 6 m ahead", 240, func(inp: InputState, _i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		return _up(6.0), 26.0)
	# Reach: in close, out to the rim and past, back in — one and two hands.
	_add(out, "reach in→out→in while skating", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		var s: float = 0.5 - 0.5 * cos(float(i) / 360.0 * TAU)
		return _up(0.8 + 2.4 * s), 26.0)
	_add(out, "reach in→out→in skating, puck near", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		var s: float = 0.5 - 0.5 * cos(float(i) / 360.0 * TAU)
		return _up(0.8 + 2.4 * s), 26.0, 2.0)
	_add(out, "reach in→out→in standing", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2.ZERO
		var s: float = 0.5 - 0.5 * cos(float(i) / 360.0 * TAU)
		return _up(0.8 + 2.4 * s))
	# The blade swept forehand → backhand and back at 1.2 m (the angle release).
	_add(out, "sweep forehand→backhand standing", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2.ZERO
		var a: float = deg_to_rad(80.0) * cos(float(i) / 360.0 * TAU)
		return Vector3(sin(a) * 1.2, 0.0, -cos(a) * 1.2))
	# A flick: the cursor jumps across the body in one tick.
	_add(out, "flick forehand→backhand", 180, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2.ZERO
		return Vector3(1.0, 0.0, -0.8) if i < 60 else Vector3(-1.0, 0.0, -0.8))
	# Pickup and drop with the cursor out at the rim: the carry's two-hand stop.
	_add(out, "pickup / drop, cursor far ahead", 300, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		if i == 60:
			_pickup()
		elif i == 180:
			_drop()
		return _up(6.0), 26.0, 1.7)
	# Forward to backward: travelling up-ice, the cursor flipped behind.
	_add(out, "forward → backward pivot (cursor flipped)", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		return _up(3.0) if i < 60 or i >= 240 else _up(-3.0), 26.0)
	# Backward to forward: skating backward, then driving the other way.
	_add(out, "backward → forward (move reversed)", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, 1.0) if i < 120 else Vector2(0.0, -1.0)
		return _up(3.0), -12.0)
	# Forward to backward on the keys alone, cursor held up-ice.
	_add(out, "forward → backward (move reversed)", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0) if i < 120 else Vector2(0.0, 1.0)
		return _up(3.0), 12.0)
	# The loaded stance on and off, skating and standing.
	_add(out, "stance on/off while skating", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.stance_held = i >= 60 and i < 200
		return _up(2.0), 26.0)
	_add(out, "stance on/off standing", 300, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2.ZERO
		inp.stance_held = i >= 60 and i < 180
		return _up(1.5))
	# A stop, a pause, and the restart.
	_add(out, "stop and restart", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0) if i < 60 or i >= 200 else Vector2.ZERO
		inp.brake = i >= 60 and i < 200
		return _up(2.0), 26.0)


	_add_play(out)
	return out


# Shots, passes, turns, contact and the celebration.
func _add_play(out: Array[Dictionary]) -> void:
	_add(out, "wrister: carry, charge, release, skating", 300, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		if i == 0:
			_pickup()
		inp.shoot_pressed = i == 60
		inp.shoot_held = i >= 60 and i < 120
		return Vector3(0.8, 0.0, -3.0), 26.0)
	_add(out, "wrister standing, cursor to the backhand", 300, func(inp: InputState, i: int) -> Vector3:
		if i == 0:
			_pickup()
		inp.shoot_pressed = i == 60
		inp.shoot_held = i >= 60 and i < 110
		return Vector3(-2.0, 0.0, -2.0))
	_add(out, "slapshot: wind-up and release", 300, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0) if i < 60 else Vector2.ZERO
		if i == 0:
			_pickup()
		inp.slap_pressed = i == 60
		inp.slap_held = i >= 60 and i < 150
		return Vector3(0.0, 0.0, -4.0), 26.0)
	_add(out, "quick pass while skating", 240, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		if i == 0:
			_pickup()
		inp.quick_pass_pressed = i == 60
		return Vector3(2.5, 0.0, -2.0), 26.0)
	# Ends before the turn carries him to the boards (x 12.5 at t290), whose stick
	# clamp and impact are not the crossover's.
	_add(out, "crossovers into and out of a held turn", 265, func(inp: InputState, i: int) -> Vector3:
		var v := Vector2(_skater.velocity.x, _skater.velocity.z)
		var travel: Vector2 = v.normalized() if v.length() > 0.5 else Vector2(0.0, -1.0)
		inp.move_vector = (travel + Vector2(-travel.y, travel.x)).normalized() \
				if i >= 60 and i < 210 else travel
		return Vector3(travel.x, 0.0, travel.y) * 3.0, 20.0)
	_add(out, "carrying through a weave", 420, func(inp: InputState, i: int) -> Vector3:
		if i == 0:
			_pickup()
		var a: float = 0.6 * sin(float(i) / 120.0 * TAU)
		inp.move_vector = Vector2(sin(a), -cos(a))
		return Vector3(sin(a), 0.0, -cos(a)) * 1.6, 26.0)
	_add(out, "body-check commit while skating", 300, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		inp.hit_held = i >= 60 and i < 150
		return _up(2.0), 26.0)
	_add(out, "knocked down from the side and up again", 420, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0)
		if i == 60:
			_controller._on_body_check_received(Vector3(3.0, 0.0, 0.0))
		return _up(2.0), 26.0)
	_add(out, "shot block down and back up, puck ahead", 300, func(inp: InputState, i: int) -> Vector3:
		inp.block_held = i >= 60 and i < 180
		return _up(2.0), 0.0, 8.0)
	_add(out, "goal celebration while gliding", 360, func(inp: InputState, i: int) -> Vector3:
		inp.move_vector = Vector2(0.0, -1.0) if i < 40 else Vector2.ZERO
		if i == 60:
			_controller.start_celebration(2.0)
		return _up(2.0), 26.0)
	# The other cellies, the same glide.
	for celly: int in range(1, CellyRegistry.count()):
		_add(out, "goal celebration while gliding: %s" % CELLY_NAMES[celly], 360,
				func(inp: InputState, i: int) -> Vector3:
					inp.move_vector = Vector2(0.0, -1.0) if i < 40 else Vector2.ZERO
					if i == 60:
						_controller.start_celebration(2.0, celly)
					return _up(2.0), 26.0)
	_add(out, "shuffle: Space + D held, released", 300, func(inp: InputState, i: int) -> Vector3:
		inp.brake = true
		inp.move_vector = Vector2(1.0, 0.0) if i >= 30 and i < 150 else Vector2.ZERO
		return _up(2.0))

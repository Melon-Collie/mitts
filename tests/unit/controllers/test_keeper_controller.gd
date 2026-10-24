extends GutTest

# The rebuilt keeper in a match (KeeperController on the Goalie node): the old
# body hidden and its colliders off, his gear's save boxes live where his gear
# is; on either net he goes where the brain puts him, square to the puck; a shot
# at his pad meets a pad box through the puck's own contact test; a shot is
# saved, the puck meeting what he puts in its way; a catch is held in his
# glove and covered, then set down and swept out; and a puck at his feet is
# covered, unless it is poked away before his glove is on it.

const DT: float = 1.0 / 120.0
# How far a save box on a client may lie from the host's: the root's centimetre
# on the wire, and the pose's millimetres carried out along a limb.
const WIRE_TOLERANCE_M: float = 0.015
const GOALIE_SCENE: PackedScene = preload("res://Scenes/Goalie.tscn")

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null


func _spawn(goal_line_z: float) -> void:
	_goalie = GOALIE_SCENE.instantiate() as Goalie
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_keeper)
	_puck.global_position = Vector3(0.0, _puck.ice_height, goal_line_z * 0.7)
	_keeper.setup(_goalie, _puck, goal_line_z, true)


func _run(seconds: float) -> void:
	for i: int in int(seconds / DT):
		_keeper._physics_process(DT)


func _live_boxes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for cs: CollisionShape3D in _goalie.get_collision_parts():
		if not cs.disabled:
			out.append(cs)
	return out


func test_his_gear_is_the_save_geometry_and_the_old_body_is_hidden() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_run(0.5)
	var live: Array[CollisionShape3D] = _live_boxes()
	assert_eq(live.size(), KeeperGear.PART_COUNT, "one live box per piece of his gear")
	var skel: KeeperSkeleton = _keeper._keeper.skeleton
	for part: int in KeeperGear.PART_COUNT:
		var want: Transform3D = _goalie.global_transform * KeeperGear.box(skel, part)
		var found: bool = false
		for box: CollisionShape3D in live:
			if box.global_transform.origin.distance_to(want.origin) < 1e-4 \
					and (box.shape as BoxShape3D).size.is_equal_approx(KeeperGear.half_extents(part) * 2.0):
				found = true
		assert_true(found, "%s's box where his gear is" % KeeperGear.Part.keys()[part])
	for node: Node in _goalie.find_children("*", "VisualInstance3D", true, false):
		if not _keeper._keeper.is_ancestor_of(node):
			assert_false((node as VisualInstance3D).visible, "%s hidden" % node.name)


func test_on_either_net_he_stands_on_the_angle_line_square_to_the_puck() -> void:
	for goal_line_z: float in [GameRules.GOAL_LINE_Z, -GameRules.GOAL_LINE_Z]:
		_spawn(goal_line_z)
		var out: float = -signf(goal_line_z)
		_puck.global_position = Vector3(3.0, _puck.ice_height, goal_line_z + out * 8.0)
		_run(2.0)
		var net := Vector3(0.0, 0.0, goal_line_z)
		var at: Vector3 = _goalie.global_position
		var to_puck: Vector3 = (_puck.global_position - net) * Vector3(1.0, 0.0, 1.0)
		var off_line: float = absf((at - net).cross(to_puck.normalized()).y)
		assert_lt(off_line, KeeperRoute.THERE_M + 0.01, "%.2f: on the angle line" % goal_line_z)
		assert_almost_eq((at - net).length(), KeeperPositioning.crease_edge(Vector2(3.0, 8.0).normalized()),
				KeeperRoute.THERE_M + 0.01, "%.2f: at the top of the crease" % goal_line_z)
		var forward: Vector3 = -_goalie.global_transform.basis.z
		var look: Vector3 = ((_puck.global_position - at) * Vector3(1.0, 0.0, 1.0)).normalized()
		assert_gt(forward.dot(look), cos(deg_to_rad(3.0)), "%.2f: square to the puck" % goal_line_z)


func test_a_shot_at_his_pad_meets_a_pad_box() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_puck.global_position = Vector3(0.0, _puck.ice_height, GameRules.GOAL_LINE_Z - 8.0)
	_run(1.5)
	# The glove-side pad's outer half, over the blade laid along the ice in
	# front of it and wide of the paddle rising to his blocker hand.
	var pad: Transform3D = _goalie.global_transform * KeeperGear.box(_keeper._keeper.skeleton, KeeperGear.Part.PAD_G)
	var aim: Vector3 = pad.origin + pad.basis.x.normalized() * -signf(pad.basis.x.x) * 0.08
	aim.y = 0.35
	var from: Vector3 = aim + Vector3(0.0, 0.0, -2.0)
	var to: Vector3 = aim + Vector3(0.0, 0.0, 0.5)
	var contact := GoalieContactDetector.Contact.new()
	var hit: bool = GoalieContactDetector.nearest([_goalie], from, to, GameRules.PUCK_COLLISION_RADIUS,
			SweptDiscOBB.Result.new(), contact)
	assert_true(hit, "the shot meets him")
	assert_eq(_puck._classify_save_part(contact.part as Node3D), GoalieSaveRules.SavePart.PAD, "on a pad")


func test_a_catch_is_held_in_his_glove_and_covered_then_played_out() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_run(0.5)
	watch_signals(_keeper)
	_puck.puck_caught_by_goalie.emit(_goalie)
	_keeper._physics_process(DT)
	assert_signal_emitted(_keeper, "puck_covered")
	assert_true(_puck.motion_pinned and _puck.pickup_locked, "held")
	assert_almost_eq(_puck.global_position, _goalie.get_glove_world_position(), Vector3.ONE * 1e-4, "in his glove")
	_run(KeeperController.CATCH_HOLD_S + 0.1)
	assert_false(_puck.motion_pinned or _puck.pickup_locked, "set down")
	assert_almost_eq(_puck.global_position.y, _puck.ice_height, 1e-4, "on the ice")
	assert_almost_eq(_puck.get_puck_velocity().length(), KeeperController.PLAY_OUT_M_S, 1e-3,
			"swept out of his reach")


# On a client, and in a replay, he is the host's: his state through the wire
# and posed from it puts every save box where the host's is, tick by tick as
# he moves.
func test_a_client_poses_him_as_the_host_has_him() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	var client_goalie := GOALIE_SCENE.instantiate() as Goalie
	var client := KeeperController.new()
	add_child_autofree(client_goalie)
	add_child_autofree(client)
	client.setup(client_goalie, _puck, GameRules.GOAL_LINE_Z, false)
	var s := GoalieNetworkState.new()
	var worst: float = 0.0
	var spots: Array[Vector3] = [Vector3(3.0, 0.0, -7.0), Vector3(-2.5, 0.0, -4.0), Vector3(4.5, 0.0, -1.2)]
	for spot: Vector3 in spots:
		_puck.global_position = Vector3(spot.x, _puck.ice_height, GameRules.GOAL_LINE_Z + spot.z)
		for i: int in 60:
			_keeper._physics_process(DT)
			_keeper.fill_state(s)
			var sent: GoalieNetworkState = WorldStateCodec._decode_goalie_quantized(
					WorldStateCodec._encode_goalie_quantized(s))
			client.apply_replay_state(sent, DT)
			var host_boxes: Array[CollisionShape3D] = _live_boxes()
			var client_boxes: Array[CollisionShape3D] = []
			for cs: CollisionShape3D in client_goalie.get_collision_parts():
				if not cs.disabled:
					client_boxes.append(cs)
			assert_eq(client_boxes.size(), host_boxes.size())
			for b: int in host_boxes.size():
				var off: float = host_boxes[b].global_position.distance_to(client_boxes[b].global_position)
				if off >= WIRE_TOLERANCE_M:
					assert_lt(off, WIRE_TOLERANCE_M, "tick %d box %d" % [i, b])
				worst = maxf(worst, off)
	gut.p("worst save box off on the client: %.4f m" % worst)


# Settled facing a puck out front, then the puck at his feet, `ahead` in front
# of him and `across` toward his blocker side.
func _puck_at_his_feet(ahead: float, across: float) -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_puck.global_position = Vector3(0.0, _puck.ice_height, GameRules.GOAL_LINE_Z - 8.0)
	_run(1.0)
	var basis: Basis = _goalie.global_transform.basis
	var at: Vector3 = _goalie.global_position - basis.z * ahead + basis.x * across
	_puck.global_position = Vector3(at.x, _puck.ice_height, at.z)


func test_a_puck_at_his_feet_is_covered() -> void:
	_puck_at_his_feet(0.6, -0.2)
	watch_signals(_keeper)
	_run(0.6)
	assert_signal_emitted(_keeper, "puck_covered")
	assert_true(_puck.motion_pinned and _puck.pickup_locked, "dead under him")
	assert_almost_eq(_puck.global_position, _goalie.get_glove_world_position(), Vector3.ONE * 1e-4,
			"under his glove")
	assert_true(_keeper.is_butterfly(), "down on it")


func test_a_puck_poked_away_before_his_glove_is_on_it_escapes() -> void:
	_puck_at_his_feet(0.6, -0.2)
	watch_signals(_keeper)
	_run(0.05)
	assert_true(_keeper._covering, "going for it")
	_puck.global_position += -_goalie.global_transform.basis.z * 2.0
	_run(0.6)
	assert_signal_not_emitted(_keeper, "puck_covered")
	assert_false(_puck.pickup_locked, "still live")
	assert_false(_keeper._covering, "the cover given up")


# Flies the puck from `from` to arrive on the goal line at `to` (x across from
# the net's centre, height), released on its way; the save part it first meets.
func _shot(from: Vector3, to: Vector2, speed: float) -> int:
	var line_z: float = GameRules.GOAL_LINE_Z
	var at_line := Vector3(to.x, to.y, line_z)
	var t: float = from.distance_to(at_line) / speed
	var v: Vector3 = (at_line - from) / t
	var lifted: bool = from.y > _puck.ice_height or to.y > _puck.ice_height
	if lifted:
		v.y += 0.5 * GameRules.GRAVITY_M_S2 * t
	_puck.global_position = from
	_puck.set_puck_velocity(v)
	_puck.puck_released.emit()
	var contact := GoalieContactDetector.Contact.new()
	for i: int in int(1.5 / DT):
		var was: Vector3 = _puck.global_position
		var next: Vector3 = was + v * DT
		if lifted:
			v.y -= GameRules.GRAVITY_M_S2 * DT
		_puck.global_position = next
		_puck.set_puck_velocity(v)
		_keeper._physics_process(DT)
		if GoalieContactDetector.nearest([_goalie], was, next, GameRules.PUCK_COLLISION_RADIUS,
				SweptDiscOBB.Result.new(), contact):
			return _puck._classify_save_part(contact.part as Node3D)
		if next.z >= line_z:
			return -1
	return -1


func test_a_shot_is_met_by_what_he_puts_in_its_way() -> void:
	var cases: Array = [
		[Vector2(-0.84, 0.4), GoalieSaveRules.SavePart.GLOVE, "to his glove side over the pad"],
		[Vector2(0.75, KeeperShotRead.ON_ICE_Y), GoalieSaveRules.SavePart.STICK, "along the ice to his blocker side, the blade leading"],
	]
	for case: Array in cases:
		_spawn(GameRules.GOAL_LINE_Z)
		_puck.global_position = Vector3(0.0, _puck.ice_height, GameRules.GOAL_LINE_Z - 9.0)
		_run(1.5)
		var to: Vector2 = case[0]
		var from := Vector3(0.0, 0.3 if to.y > 0.1 else _puck.ice_height, GameRules.GOAL_LINE_Z - 9.0)
		assert_eq(_shot(from, to, 22.0), case[1], case[2])


# A shot in on him before his legs have read it (set for a puck wide of him,
# fired from in tight across him) still gets his save once he has, late, and he
# goes all the way into it rather than standing still.
func test_a_shot_that_beats_his_read_is_still_answered() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_puck.global_position = Vector3(1.6, _puck.ice_height, GameRules.GOAL_LINE_Z - 4.5)
	_run(1.5)
	var to := Vector2(-0.7, 0.9)
	var from := Vector3(0.2, _puck.ice_height, GameRules.GOAL_LINE_Z - 2.8)
	assert_lt(from.distance_to(Vector3(to.x, to.y, GameRules.GOAL_LINE_Z)) / 26.0, _keeper.read.leg_delay_s,
			"in before his read")
	assert_eq(_shot(from, to, 26.0), -1, "it beats him")
	assert_false(_keeper._chosen, "nothing chosen before it was in")
	var made: bool = false
	var into: bool = false
	for i: int in int(0.5 / DT):
		_keeper._physics_process(DT)
		var low: bool = _keeper.save.low != KeeperSaveMove.Low.NONE
		made = made or low or _keeper.save.hand != KeeperSave.Hand.NONE
		into = into or (low and _keeper.motor.save_move.state == KeeperSaveMove.State.HELD) \
				or _keeper.save.hand_there()
	assert_true(made, "a save made once he has read it")
	assert_true(into, "and carried all the way into")


# A puck that hits him he feels: once his save is there, the shot off him, he
# starts back at once rather than a read later.
func test_hit_he_starts_his_recovery_at_once() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	_puck.global_position = Vector3(0.0, _puck.ice_height, GameRules.GOAL_LINE_Z - 12.0)
	_run(1.5)
	var from := Vector3(0.0, 0.3, GameRules.GOAL_LINE_Z - 12.0)
	var part: int = _shot(from, Vector2(-0.84, 1.0), 20.0)
	assert_eq(part, GoalieSaveRules.SavePart.GLOVE, "met by the glove")
	assert_true(_keeper.read.reading(), "still on it as it hits him")
	assert_lte(_keeper._chosen_at + _keeper.save.ready_s, _keeper.read.age, "his glove there first")
	_puck.puck_touched_goalie.emit(_goalie)
	var ticks: int = 0
	while _keeper.read.reading() and ticks < 60:
		_keeper._physics_process(DT)
		ticks += 1
	assert_lte(ticks, 1, "let go the tick he feels it")


# A tier changed in the session (free play's picker, the tutorial) reaches his
# reads and his hands.
func test_a_tier_set_later_reaches_his_saves() -> void:
	_spawn(GameRules.GOAL_LINE_Z)
	var easy: GoalieSkillProfile = GoalieSkillProfile.easy()
	_keeper.apply_skill_profile(easy)
	assert_eq(_keeper.read.leg_delay_s, easy.reaction_delay_s)
	assert_eq(_keeper.read.arm_delay_s, easy.arm_reaction_delay_s)
	assert_eq(_keeper.save.glove_speed_m_s, easy.glove_react_max_speed_mps)
	assert_eq(_keeper.motor.save_move.drop_s, easy.butterfly_drop_s)
	_keeper.reset_to_crease()
	assert_eq(_keeper.read.leg_delay_s, easy.reaction_delay_s, "and keeps it through a reset")

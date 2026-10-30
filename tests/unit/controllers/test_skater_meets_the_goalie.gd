extends GutTest

# A skater against the goalie through the real controller (SkaterController,
# SkaterIKCoordinator.resolve_blade_against_goalies, _pinned_puck_off_goalies,
# Skater.clamp_body_to_goalies): a carrier skating at a goalie set in front of
# his net, the cursor swept across him and driven through him. His gear is a
# wall: the blade never goes into it, the carried puck is held off it, and
# touching him strips nothing, however long it is pressed there. Without the
# puck the blade stops on him the same way, and the body skated into him stops
# on his gear and slides along it.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const TICKS: int = 300
# How far into his gear the blade or the puck may sit: the blade's own
# thickness rounds, no more.
const SINK_M: float = 0.02
# How near him the skater's body comes, from his centre.
const STOP_M: float = 1.3


class GameStateStub:
	extends Node

	var boxes := PackedFloat32Array()

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func get_goalie_boxes() -> PackedFloat32Array:
		return boxes


func test_carrying_into_him_the_stick_and_puck_stop_on_his_gear_and_he_strips_nothing() -> void:
	for down: bool in [false, true]:
		var run: Dictionary = _skate_into_him(true, down)
		var what: String = "him %s" % ("down" if down else "standing")
		assert_gt(run["touching"], 0, what + ": the blade met him")
		assert_lt(run["blade_in"], SINK_M, what + ": the blade never into his gear")
		assert_lt(run["puck_in"], SINK_M, what + ": the puck held off his gear")
		assert_eq(run["releases"], 0, what + ": nothing stripped")
		assert_true(run["has_puck"], what + ": still carrying")


func test_without_the_puck_the_stick_stops_on_him_too() -> void:
	var run: Dictionary = _skate_into_him(false, false)
	assert_gt(run["touching"], 0, "the blade met him")
	assert_lt(run["blade_in"], SINK_M, "the blade never into his gear")


# A carrier (or not) skating at a goalie in front of the net, the cursor swept
# across and through him. The deepest the blade and the puck sat in his gear,
# the ticks the blade lay against it, and the releases.
func _skate_into_him(carry: bool, down: bool) -> Dictionary:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	var goalie_at := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 1.2)
	gs.boxes = _keeper_boxes(goalie_at, PI, down)
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.3, GameRules.FACEOFF_SPAWN_HEIGHT, GameRules.GOAL_LINE_Z - 4.0)
	if carry:
		c.has_puck = true
		c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	var releases := PackedVector3Array()
	c.puck_release_requested.connect(func(dir: Vector3, _power: float, _slapper: bool) -> void: releases.append(dir))
	var blade_in: float = 0.0
	var puck_in: float = 0.0
	var touching: int = 0
	var input := InputState.new()
	for i: int in TICKS:
		input.delta = DT
		input.host_timestamp += DT
		# Up to him and no further: the body clamp, not in this stub, holds a
		# skater off him in a match.
		var to_him: Vector3 = goalie_at - skater.global_position
		to_him.y = 0.0
		input.move_vector = Vector2(to_him.x, to_him.z).normalized() * (0.6 if to_him.length() > STOP_M else 0.0)
		input.mouse_world_pos = goalie_at + Vector3(sin(float(i) * 0.07) * 0.8, 0.0, 0.3)
		# As every controller does at the top of its tick: the blade's sweep starts
		# where it was drawn last.
		skater.capture_prev_blade_contact()
		c._process_input(input, DT)
		var heel: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
		var mid: Vector3 = skater.get_blade_contact_global()
		var toe: Vector3 = heel + (mid - heel) * 2.0
		var held: Vector3 = GoalieGearCollision.resolve(mid, heel, toe, c.net_blade_half_thickness, gs.boxes)
		blade_in = maxf(blade_in, held.length())
		if GoalieGearCollision.resolve(mid, heel, toe, c.net_blade_half_thickness + 0.01, gs.boxes) != Vector3.ZERO:
			touching += 1
		if carry:
			var pin: Vector3 = skater.get_carry_target_global()
			puck_in = maxf(puck_in, GoalieGearCollision.resolve(pin, pin, pin, 0.0, gs.boxes).length())
		skater._physics_process(DT)
	return {"blade_in": blade_in, "puck_in": puck_in, "touching": touching, "releases": releases.size(),
			"has_puck": c.has_puck}


# The keeper's save boxes standing ready or down in the butterfly, at `at`
# turned `yaw`, packed as GameManager gathers them.
func _keeper_boxes(at: Vector3, yaw: float, down: bool) -> PackedFloat32Array:
	var p := KeeperPose.new()
	if down:
		KeeperPoses.butterfly(p)
	else:
		KeeperPoses.ready(p)
	var skel := KeeperSkeleton.new()
	skel.pose(p)
	var place := Transform3D(Basis(Vector3.UP, yaw), at)
	var out := PackedFloat32Array()
	for part: int in KeeperGear.PART_COUNT:
		var xf: Transform3D = place * KeeperGear.box(skel, part)
		var h: Vector3 = KeeperGear.half_extents(part)
		out.append_array([xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
				xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z, h.x, h.y, h.z])
	return out


# The skater's body against him (Skater.clamp_body_to_goalies): skated into him
# at an angle, standing and down, it stops on his gear, never in it, and slides
# along it rather than sticking.
func test_skating_into_him_the_body_stops_on_his_gear_and_slides_off() -> void:
	for down: bool in [false, true]:
		var skater: Skater = SKATER_SCENE.instantiate() as Skater
		add_child_autofree(skater)
		skater.set_process(false)
		skater.set_physics_process(false)
		var puck: Puck = PUCK_SCENE.instantiate() as Puck
		add_child_autofree(puck)
		puck.set_physics_process(false)
		var gs := GameStateStub.new()
		var goalie_at := Vector3(0.0, 0.0, GameRules.GOAL_LINE_Z - 1.2)
		gs.boxes = _keeper_boxes(goalie_at, PI, down)
		add_child_autofree(gs)
		var c := SkaterController.new()
		add_child_autofree(c)
		c.setup(skater, puck, gs)
		c.apply_attributes(PlayerAttributes.neutral())
		skater.set_goalie_boxes_provider(func() -> PackedFloat32Array: return gs.boxes)
		skater.global_position = Vector3(-0.9, GameRules.FACEOFF_SPAWN_HEIGHT, GameRules.GOAL_LINE_Z - 4.0)
		var what: String = "him %s" % ("down" if down else "standing")
		var deepest: float = 0.0
		var met: bool = false
		var slid_from: float = INF
		var input := InputState.new()
		for i: int in 240:
			input.delta = DT
			input.host_timestamp += DT
			input.move_vector = Vector2(0.35, 1.0).normalized()
			input.mouse_world_pos = skater.global_position + Vector3(0.0, 0.0, 1.0)
			if met and slid_from == INF:
				slid_from = skater.global_position.x
			skater.capture_prev_blade_contact()
			c._process_input(input, DT)
			skater._physics_process(DT)
			var into: Vector3 = GoalieGearCollision.body_out(skater.global_position, skater.collision_radius(), gs.boxes)
			deepest = maxf(deepest, into.length())
			met = met or into != Vector3.ZERO or GoalieGearCollision.body_out(skater.global_position,
					skater.collision_radius() + 0.01, gs.boxes) != Vector3.ZERO
		assert_lt(deepest, SINK_M, what + ": the body never in his gear")
		assert_true(met, what + ": met him")
		assert_gt(skater.global_position.x - slid_from, 0.3, what + ": slid along him")

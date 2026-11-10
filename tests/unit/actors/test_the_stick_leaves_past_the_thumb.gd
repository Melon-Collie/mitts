extends GutTest

# The stick leaves each fist past the thumb toward the blade: the thumb is nearer
# the blade than the little finger on both drawn gloves (the thumb's and the
# little finger's rolls, SkaterMeshBuilder.shared_glove_fist), and the top hand
# caps the stick, its knob (SkaterStickRig.SHAFT_BUTT_EXTEND_M) ending inside the
# fist rather than out past the little finger. Measured along the drawn shaft,
# carrying round the body standing and skating. The basis alone is held by
# test_glove_grips_the_shaft.gd; this holds the rig that poses it, the pair a
# shot puts on and the shaft it is handed.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const UpperBone = SkaterMeshBuilder.UpperBone
# The thumb clears the little finger toward the blade by this much at the least
# (m): a fist's width is ~0.2 m, so anything under it is a fist turned edge-on.
const LEAD_MIN_M: float = 0.03
# A hand further than this off the drawn shaft has let go of it.
const ON_SHAFT_M: float = 0.06
# The little finger's roll: the fingers' quarter on the fist's −X end.
const LITTLE_FINGER_X: float = -0.6
# The fist's little-finger end, every part of it (back, fingers): where the
# knob would show past it.
const LITTLE_FINGER_END_X: float = -0.9
const BEARINGS_DEG: Array[float] = [-120.0, -60.0, 0.0, 60.0, 120.0]
const RADII_M: Array[float] = [1.2, 1.8]


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


func _make_carrier(left: bool) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	skater.is_left_handed = left
	# The kit builds the stick's knob.
	skater.set_uniform(TeamColorRegistry.get_colors(0, 0))
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


func _centroid(verts: PackedVector3Array, below_x: float) -> Vector3:
	var sum := Vector3.ZERO
	var n: int = 0
	for v: Vector3 in verts:
		if v.x <= below_x:
			sum += v
			n += 1
	return sum / maxf(n, 1)


# The thumb's lead over the little finger toward the blade along the drawn shaft
# (m), or NAN for a hand off the shaft. Skeleton space throughout.
func _lead(sk: Skater, top: bool) -> float:
	var body: Skeleton3D = sk._arms._skeleton
	var ub: Transform3D = sk.drawn_upper_body()
	var hand: Vector3 = ub * sk.drawn_top_hand()
	var shaft: Vector3 = (ub * sk.drawn_blade().origin - hand).normalized()
	var pose: Transform3D = body.get_bone_global_pose(
			UpperBone.TOP_HAND if top else UpperBone.BOTTOM_HAND)
	var off: Vector3 = pose.origin - hand
	if (off - shaft * off.dot(shaft)).length() > ON_SHAFT_M:
		return NAN
	# A left shot's top hand is his right.
	var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist(sk.is_left_handed == top)
	var thumb: Vector3 = _centroid(fist.surface_get_arrays(
			SkaterMeshBuilder.FIST_PART_THUMB)[Mesh.ARRAY_VERTEX], INF)
	var little: Vector3 = _centroid(fist.surface_get_arrays(
			SkaterMeshBuilder.FIST_PART_FINGERS)[Mesh.ARRAY_VERTEX], LITTLE_FINGER_X)
	return (pose * thumb - pose * little).dot(shaft)


# How far the knob's top shows past the top fist's little-finger end, up the
# drawn shaft (m; negative inside the glove).
func _knob_out(sk: Skater) -> float:
	var body: Skeleton3D = sk._arms._skeleton
	var ub: Transform3D = sk.drawn_upper_body()
	var hand: Vector3 = ub * sk.drawn_top_hand()
	var up_shaft: Vector3 = (hand - ub * sk.drawn_blade().origin).normalized()
	var knob_top: Vector3 = ub * sk.stick_knob_mesh.transform.origin \
			+ up_shaft * SkaterMeshBuilder.KNOB_HEIGHT_M * 0.5
	var pose: Transform3D = body.get_bone_global_pose(UpperBone.TOP_HAND)
	var fist: ArrayMesh = SkaterMeshBuilder.shared_glove_fist(sk.is_left_handed)
	var edge: float = -INF
	for part: int in [SkaterMeshBuilder.FIST_PART_BACK, SkaterMeshBuilder.FIST_PART_FINGERS]:
		for v: Vector3 in fist.surface_get_arrays(part)[Mesh.ARRAY_VERTEX]:
			if v.x <= LITTLE_FINGER_END_X:
				edge = maxf(edge, (pose * v - hand).dot(up_shaft))
	return (knob_top - hand).dot(up_shaft) - edge


func test_the_stick_leaves_each_fist_past_the_thumb() -> void:
	for left: bool in [true, false]:
		for skating: bool in [false, true]:
			for bearing: float in BEARINGS_DEG:
				for r: float in RADII_M:
					var c: SkaterController = _make_carrier(left)
					var sk: Skater = c.skater
					var a: float = deg_to_rad(bearing)
					var fh: float = signf(sk.bottom_shoulder.position.x)
					var aim := Vector3(sin(a) * r * fh, 0.0, -cos(a) * r)
					var input := InputState.new()
					for _i: int in 120:
						input.delta = DT
						input.host_timestamp += DT
						input.move_vector = Vector2(0.0, -1.0) if skating else Vector2.ZERO
						input.mouse_world_pos = sk.global_position + sk.global_transform.basis * aim
						input.mouse_world_pos.y = 0.0
						c._process_input(input, DT)
						sk._physics_process(DT)
						sk._process(DT)
					var what: String = "%s shot, %s, %+.0f° at %.1f m" % [
							"left" if left else "right", "skating" if skating else "standing",
							bearing, r]
					assert_lt(_knob_out(sk), 0.0, "%s: the knob inside the top fist" % what)
					for top: bool in [true, false]:
						var lead: float = _lead(sk, top)
						if is_nan(lead):
							continue
						assert_gt(lead, LEAD_MIN_M, "%s: the %s hand" % [what,
								"top" if top else "bottom"])

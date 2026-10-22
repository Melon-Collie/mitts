extends GutTest

# ── THE KEEPER'S SKATES ──────────────────────────────────────────────────────
# A boot and blade under each pad's foot, level on the ice whatever the pad does
# above it, with the pad's toe bridge laid over its front (GoalieSkates). Each
# piece is a save surface of its own pad and is re-placed on every pad write.

const State := GoalieStateMachine.State
const STATES: Array[int] = [State.STANDING, State.READY, State.LOW_READY, State.BUTTERFLY,
		State.HALF_BUTTERFLY_LEFT, State.RVH_LEFT, State.VH_RIGHT, State.COVERING]
const PIECES: Array[String] = ["Skate", "ToeCap"]


func _goalie() -> Goalie:
	var g: Goalie = load("res://Scenes/Goalie.tscn").instantiate()
	add_child_autofree(g)
	return g


func _pose(g: Goalie, state: int) -> void:
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = state
	i.direction_sign = 1
	g.apply_body_config(GoalieBodyConfigBuilder.new().build(i), 1.0)


# The skate and toe cap under `pad_name`, in that order.
func _pieces_of(g: Goalie, pad_name: String) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for piece: String in PIECES:
		out.append(g.get_node("%s/%s" % [pad_name, piece]) as CollisionShape3D)
	return out


func _in_goalie(g: Goalie, n: Node3D) -> Transform3D:
	return g.global_transform.affine_inverse() * n.global_transform


func test_every_piece_stands_level_on_the_ice_in_every_stance() -> void:
	var g := _goalie()
	for state: int in STATES:
		_pose(g, state)
		for pad: String in ["LeftPad", "RightPad"]:
			for piece: CollisionShape3D in _pieces_of(g, pad):
				var xf: Transform3D = _in_goalie(g, piece)
				var label := "%s %s %s" % [State.keys()[state], pad, piece.name]
				assert_almost_eq(xf.basis.y.dot(Vector3.UP), 1.0, 1e-4, label + " is level")
				var half_y: float = (piece.shape as BoxShape3D).size.y * 0.5
				assert_almost_eq(xf.origin.y - half_y, 0.0, 1e-4, label + " is on the ice")


func test_each_piece_is_its_pads_save_surface() -> void:
	var g := _goalie()
	var parts: Array[CollisionShape3D] = g.get_collision_parts()
	var bodies: Array[Node] = g.get_collision_part_bodies()
	var found: int = 0
	for i: int in parts.size():
		if parts[i].name in PIECES:
			found += 1
			assert_true(bodies[i].name in ["LeftPad", "RightPad"],
					"%s saves as its pad" % parts[i].name)
	assert_eq(found, 4, "a skate and a toe cap on each pad")


func test_the_skates_follow_the_pads() -> void:
	var g := _goalie()
	_pose(g, State.READY)
	var ready_x: float = _in_goalie(g, _pieces_of(g, "RightPad")[0]).origin.x
	_pose(g, State.LOW_READY)
	var low_x: float = _in_goalie(g, _pieces_of(g, "RightPad")[0]).origin.x
	assert_gt(absf(low_x), absf(ready_x) + 0.1, "the low ready's wide A carries the skate out")


func test_the_toe_cap_reaches_past_the_boot() -> void:
	var g := _goalie()
	_pose(g, State.LOW_READY)
	var pieces: Array[CollisionShape3D] = _pieces_of(g, "LeftPad")
	var boot_half: Vector3 = (pieces[0].shape as BoxShape3D).size * 0.5
	var cap_half: Vector3 = (pieces[1].shape as BoxShape3D).size * 0.5
	var cap_in_boot: Transform3D = pieces[0].global_transform.affine_inverse() \
			* pieces[1].global_transform
	assert_almost_eq(cap_in_boot.origin.z - cap_half.z, -boot_half.z - GoalieSkates.TOE_CAP_OVERHANG_M,
			1e-4, "the toe's front edge lies past the boot's toe, forward (-Z)")

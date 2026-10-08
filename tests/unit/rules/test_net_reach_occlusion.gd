extends GutTest

# A blade reaches a puck only when no solid part of the net stands between them
# (NetGeometry.path_blocked, applied by PuckInteractionRules' swept checks and the
# client's claim gates). The pickup radius is half a metre and the twine is
# centimetres thick, so without it a stick reaching into the cage through the
# mouth picks up — and then scores — pucks lying against the outside of the mesh.
#
# Positions are built from GameRules so the cases follow the net if it moves.

const G: float = GameRules.GOAL_LINE_Z
const HW: float = GameRules.NET_HALF_WIDTH
const R: float = GameRules.PUCK_COLLISION_RADIUS
const BAND: float = GameRules.NET_BLADE_MESH_GIVE
const PICKUP: float = PuckController.PICKUP_RADIUS
const POKE: float = PuckController.POKE_RADIUS
# A puck resting against the outside of the side twine, just past the goal line.
const PUCK_BESIDE_POST := Vector3(HW + R + 0.02, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + 0.03)
# A blade reached into the cage through the mouth, near that side panel.
const BLADE_IN_CAGE_SIDE := Vector3(HW - 0.1, 0.03, G + 0.2)


func _picks(blade: Vector3, puck: Vector3) -> bool:
	return PuckInteractionRules.check_pickup(puck, puck, blade, blade, PICKUP)


func _mirror(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, -p.z)


# ── Through the twine: never ─────────────────────────────────────────────────

func test_stick_in_the_cage_cannot_pick_up_a_puck_outside_the_side_twine() -> void:
	assert_lt(BLADE_IN_CAGE_SIDE.distance_to(PUCK_BESIDE_POST), PICKUP,
			"precondition: in pickup range by distance alone")
	assert_false(_picks(BLADE_IN_CAGE_SIDE, PUCK_BESIDE_POST),
			"the side twine is between them")


func test_stick_in_the_cage_cannot_pick_up_a_puck_behind_the_back_twine() -> void:
	var blade := Vector3(0.2, 0.03, G + GameRules.NET_DEPTH - 0.1)
	var puck := Vector3(0.3, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + GameRules.NET_DEPTH + R + 0.05)
	assert_lt(blade.distance_to(puck), PICKUP, "precondition: in range")
	assert_false(_picks(blade, puck), "the back twine is between them")


func test_stick_outside_cannot_reach_into_the_cage_through_the_side() -> void:
	var blade := Vector3(HW + 0.25, 0.03, G + 0.4)
	var puck := Vector3(HW - R - 0.02, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + 0.4)
	assert_false(_picks(blade, puck), "side twine from outside")


func test_a_stick_buried_in_the_twine_reaches_nothing_beyond_it() -> void:
	# Sunk the full give past the plane from inside: the puck on the far side is
	# within distance of it, and still not reachable.
	var blade := Vector3(HW + BAND, 0.03, G + 0.3)
	var puck := Vector3(HW + R, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + 0.3)
	assert_false(_picks(blade, puck), "a stick tangled in the mesh")


func test_a_path_across_a_post_is_blocked() -> void:
	var blade := Vector3(HW - 0.2, 0.03, G)
	var puck := Vector3(HW + 0.2, GameRules.PUCK_COLLISION_HALF_HEIGHT, G)
	assert_true(NetGeometry.path_blocked(blade, puck, 0.0), "iron between them")


func test_poke_through_the_net_is_blocked_too() -> void:
	assert_false(PuckInteractionRules.check_poke(
			PUCK_BESIDE_POST, PUCK_BESIDE_POST, BLADE_IN_CAGE_SIDE, BLADE_IN_CAGE_SIDE, POKE),
			"a carrier beside the net can't be poked from inside it")


func test_the_far_net_mirrors() -> void:
	assert_false(_picks(_mirror(BLADE_IN_CAGE_SIDE), _mirror(PUCK_BESIDE_POST)),
			"-Z net blocks the same reach")


func test_a_swept_blade_is_judged_where_it_met_the_puck() -> void:
	# The blade sweeps from in front of the mouth into the cage past a puck that
	# is outside the side twine. Its closest approach is inside the cage, across
	# the mesh — the sweep starting on the open side doesn't buy the pickup.
	var blade_prev := Vector3(HW - 0.15, 0.03, G - 0.6)
	var blade_curr := BLADE_IN_CAGE_SIDE
	assert_false(PuckInteractionRules.check_pickup(
			PUCK_BESIDE_POST, PUCK_BESIDE_POST, blade_prev, blade_curr, PICKUP))


# ── The open mouth and open ice: unaffected ──────────────────────────────────

func test_stick_in_the_cage_still_picks_up_a_puck_in_front_of_the_mouth() -> void:
	var blade := Vector3(0.3, 0.03, G + 0.2)
	var puck := Vector3(0.3, GameRules.PUCK_COLLISION_HALF_HEIGHT, G - 0.2)
	assert_true(_picks(blade, puck), "reaching in and out through the mouth is net-front play")


func test_both_beside_the_net_is_unaffected() -> void:
	var blade := Vector3(HW + 0.4, 0.03, G + 0.3)
	assert_true(_picks(blade, PUCK_BESIDE_POST), "same side of the twine")


func test_both_behind_the_net_is_unaffected() -> void:
	var back: float = G + GameRules.NET_DEPTH
	assert_true(_picks(Vector3(0.0, 0.03, back + 0.5), Vector3(0.2, 0.0175, back + 0.15)),
			"behind the back twine, same side")


func test_puck_against_the_outside_of_the_twine_is_reachable_from_outside() -> void:
	# The blade pressed into the mesh from outside — at the plane — still plays
	# a puck resting on the outside of it.
	var blade := Vector3(HW + 0.08, 0.03, G + 0.5)
	var puck := Vector3(HW + R, GameRules.PUCK_COLLISION_HALF_HEIGHT, G + 0.45)
	assert_true(_picks(blade, puck))


func test_open_ice_is_unaffected() -> void:
	assert_true(_picks(Vector3(0.0, 0.03, 0.0), Vector3(0.3, 0.0175, 0.1)))
	assert_false(NetGeometry.path_blocked(Vector3(-5.0, 0.0, G), Vector3(5.0, 0.0, G - 3.0), BAND),
			"a path that never comes near the cage")


func test_over_the_crossbar_is_not_the_net() -> void:
	var over := GameRules.NET_HEIGHT + 0.1
	assert_false(NetGeometry.path_blocked(
			Vector3(0.0, over, G - 0.3), Vector3(0.0, over, G + 0.5), BAND))


# ── The client gate asks the same question ───────────────────────────────────

func test_net_between_matches_the_swept_check() -> void:
	assert_true(PuckInteractionRules.net_between(BLADE_IN_CAGE_SIDE, PUCK_BESIDE_POST))
	assert_false(PuckInteractionRules.net_between(
			Vector3(0.3, 0.03, G + 0.2), Vector3(0.3, 0.0175, G - 0.2)))

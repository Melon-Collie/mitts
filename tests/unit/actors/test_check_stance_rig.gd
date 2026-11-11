extends GutTest

# The check-commit load-up on a LIVE rig rather than on the pure geometry
# (CheckStanceRules has its own suite): the arm's root on the visible trunk
# (`SkaterArmRig._textured_shoulder`), which the skin's sleeve grows from, and
# the side plumbing the rule cannot see — handedness → stick side → which
# shoulder loads.

const _SCENE: String = "res://Scenes/Skater.tscn"
const _DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# Enough ticks for the lead ease to converge (_CHECK_LEAD_SPEED is 5/s).
const _TICKS: int = 60
# A representative commit texture: the stance's own forward lean, plus a roll
# the gait can still be carrying from a stride underneath it.
const _PITCH: float = -0.244   # ~14°, hit_commit_lean_deg
const _ROLL: float = 0.09


func _rig(lefty: bool, committed: bool) -> Skater:
	var skater: Skater = (load(_SCENE) as PackedScene).instantiate() as Skater
	skater.is_left_handed = lefty
	add_child_autofree(skater)
	# Driven by hand — nothing here wants the gait or the physics integration.
	skater.set_process(false)
	skater.set_physics_process(false)
	skater.hit_committed = committed
	for _i: int in _TICKS:
		skater._update_commit_stance(_DT)
	skater.set_trunk_texture(_PITCH, _ROLL)
	return skater


# The arm root on `side_sign`'s side, in the spine's frame.
func _root(skater: Skater, side_sign: float) -> Vector3:
	var marker: Vector3 = skater.shoulder.position
	if signf(marker.x) != side_sign:
		marker = skater.bottom_shoulder.position
	return skater._arms._textured_shoulder(marker)


# Handedness → stick side → lead side, end to end through the real skater. A
# right-handed shot carries the stick on his right, so he throws the left
# shoulder; a lefty throws the right.
func test_the_thrown_shoulder_is_the_one_off_the_stick() -> void:
	assert_gt(_rig(true, true).get_check_lead(), 0.0,
			"a left-handed shot leads with the RIGHT shoulder")
	assert_lt(_rig(false, true).get_check_lead(), 0.0,
			"a right-handed shot leads with the LEFT shoulder")


func test_an_uncommitted_skater_has_no_lead_at_all() -> void:
	assert_eq(_rig(true, false).get_check_lead(), 0.0,
			"the stance is off until the Hit button commits")


# The asymmetry itself, measured on the rig: the trailing shoulder may only move
# by whatever the (symmetric) trunk texture does to both of them, while the
# leading one travels further forward and further down on top of that.
func test_only_the_thrown_shoulder_leaves_the_trunk_texture() -> void:
	var rest: Skater = _rig(false, false)
	var loaded: Skater = _rig(false, true)
	# Right-handed: the LEFT shoulder is thrown, the right one only rides the
	# texture.
	var trailing_moved: float = _root(rest, 1.0).distance_to(_root(loaded, 1.0))
	var leading_moved: float = _root(rest, -1.0).distance_to(_root(loaded, -1.0))
	assert_almost_eq(trailing_moved, 0.0, 1e-5,
			"the trailing shoulder holds its place under an unchanged texture")
	assert_gt(leading_moved, 0.03,
			"the thrown shoulder travels a real distance, not a token one")
	assert_lt(_root(loaded, -1.0).z, _root(rest, -1.0).z,
			"and it travels FORWARD (−z), which is what loading up looks like")
	assert_lt(_root(loaded, -1.0).y, _root(rest, -1.0).y, "and a little down")
	assert_gt(_root(loaded, -1.0).x, _root(rest, -1.0).x,
			"and inward across the chest")

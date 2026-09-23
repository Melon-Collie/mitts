extends GutTest

# ── ROOM TO SEE AROUND A SCREEN ──────────────────────────────────────────────
# A net-front screener, dead on the line from a shooter to the goal, and the
# live goalie settled against the carrier. The one depth term screens earn
# (GoalieScreenDepth): no closer to a body than he needs to look around it.
#
# ── WHAT IT MEASURED (2026-09) ───────────────────────────────────────────────
# Cold 30 m/s release, 7 aims x 4 lofts. `r` is his challenge radius at the
# release, `blind` the screen delay he reads it with.
#
#                               WITHOUT ROOM             WITH ROOM
#   shooter      screener       r     blind  goals       r     blind  goals
#   18 m centre  2.1 m          1.72  300ms  0           1.49  0      2
#   18 m centre  2.3 m          1.73  300ms  2           1.64  0      2
#   15 m, 4 off  2.1 m          1.72  300ms  3           1.37  0      4
#   15 m, 4 off  2.3 m          1.73  300ms  5           1.57  0      5
#   10 m centre  2.1 m          1.72  263ms  7           1.50  0      3
#   10 m centre  2.3 m          1.73  257ms  7           1.64  0      4
#
# Chest to chest he was blind to every release (the body inside the peek's
# reach fills the view); a stick of room gives him the look, at 0.1-0.35 m of
# challenge. Screeners 2.6 m and further out are untouched: at challenge depth
# he is already tight enough to look around them, or — dead on at 4-5 m — cannot
# see around them from anywhere, and the blocking drop answers the release.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const SHOOTER := Vector3(0.0, 0.0, GOAL_Z + 10.0)

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _screener: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	_shooter = skater_scene.instantiate() as Skater
	_screener = skater_scene.instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_screener)
	add_child_autofree(_ctrl)
	_screener.set_physics_process(false)
	_screener.set_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)
	_ctrl.set_skater_getter(func() -> Array: return [_shooter, _screener])


func _settle_with_screener_at(dist: float) -> void:
	_screener.global_position = Vector3(0.0, 0.0, GOAL_Z + dist)
	_h.settle_ready(SHOOTER)


func _radius() -> float:
	return Vector2(_goalie.global_position.x, _goalie.global_position.z - GOAL_Z).length()


func _blind() -> float:
	return _ctrl._screen_delay(Vector3(0.0, 0.0, GOAL_Z) - SHOOTER)


func test_chest_to_chest_he_gives_room_and_sees_the_release() -> void:
	_ctrl.screen_room = false
	_settle_with_screener_at(2.1)
	var r_off: float = _radius()
	assert_gt(_blind(), 0.0, "on top of the screener, the body fills his view")
	_ctrl.screen_room = true
	_settle_with_screener_at(2.1)
	assert_lt(_radius(), r_off - 0.1, "he backs off the body")
	assert_eq(_blind(), 0.0, "and from there he looks around it")


func test_a_screener_he_can_see_around_leaves_his_depth_alone() -> void:
	var radii: Array[float] = []
	for flag: bool in [false, true]:
		_ctrl.screen_room = flag
		_settle_with_screener_at(2.8)
		radii.append(_radius())
	assert_almost_eq(radii[1], radii[0], 0.01)


# A dead-on screen gives the peek no side of its own. He picks one and keeps it;
# the side used to come from float noise and flip from tick to tick.
func test_the_peek_holds_its_side_of_a_dead_on_screen() -> void:
	_settle_with_screener_at(2.1)
	var side: float = signf(_ctrl._eye_offset_x)
	assert_ne(side, 0.0, "he is peeking")
	for _i: int in 120:
		_puck.global_position = SHOOTER
		_ctrl._physics_process(DT)
		assert_eq(signf(_ctrl._eye_offset_x), side)

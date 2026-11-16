extends GutTest

# The goalie's hands in tight, in a match (KeeperController, KeeperHandsLow):
# the live keeper, down for a real carrier in tight, sets his glove and blocker
# down for the height a puck from there can be lifted to, before any shot;
# they come back up when the carrier backs off out of range, and are never
# asked down while he is on his feet.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
# The carrier's start and drive, net frame (x across, z back into the net),
# and where he pulls up: in tight.
const FROM := Vector2(0.0, -7.0)
const DRIVING := Vector2(0.0, 4.0)
const STOP_Z: float = -2.3
const HELD := Vector2(0.0, 0.3)

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _carrier: Skater = null
var _body := Vector2.ZERO


func before_each() -> void:
	_goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	_puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	_carrier = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	_keeper = KeeperController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_carrier)
	add_child_autofree(_keeper)
	_keeper.setup(_goalie, _puck, GameRules.GOAL_LINE_Z, true)
	_keeper.set_skater_getter(func() -> Array: return [_carrier])
	_puck.set_carrier(_carrier)
	_body = FROM


# One tick: the carrier's body moving at `moving`, the puck `held` from it.
func _tick(moving: Vector2, held: Vector2) -> void:
	_body += moving * DT
	_carrier.global_position = _keeper._net * Vector3(_body.x, 0.0, _body.y)
	_carrier.velocity = _keeper._net.basis * Vector3(moving.x, 0.0, moving.y)
	var on_blade: Vector2 = _body + held
	_puck.global_position = _keeper._net * Vector3(on_blade.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, on_blade.y)
	_keeper._view.invalidate()
	_keeper._physics_process(DT)


func _top(part: int) -> float:
	var t: Transform3D = KeeperGear.box(_keeper._keeper.skeleton, part)
	var h: Vector3 = KeeperGear.half_extents(part)
	return t.origin.y + absf(t.basis.x.y) * h.x + absf(t.basis.y.y) * h.y + absf(t.basis.z.y) * h.z


func test_down_for_a_carrier_in_tight_his_hands_are_set_for_what_he_can_lift() -> void:
	while _body.y < STOP_Z:
		_tick(DRIVING, HELD)
	for i: int in int(0.8 / DT):
		_tick(Vector2.ZERO, HELD)
		assert_false(_keeper.read.reading(), "no shot")
	assert_eq(_keeper.motor.rest, KeeperRoute.Rest.DOWN, "down for the carrier in tight")
	var hands: KeeperHandsLow = _keeper.motor.hands_low
	var reach: float = GameRules.PUCK_COLLISION_HALF_HEIGHT + PlayerAttributes.steepest_loft_tan() \
			* _keeper.play.puck.distance_to(Vector2(_keeper.motor.x, _keeper.motor.z))
	assert_almost_eq(hands.asked, reach, 1e-3, "asked for the height a puck from there is lifted to at him")
	assert_lt(reach, KeeperHandsLow.highest(), "lower than the butterfly holds them")
	assert_almost_eq(hands.set_m, maxf(reach, KeeperHandsLow.lowest()), 1e-3, "and set for it")
	var taught := KeeperSkeleton.new()
	var pose := KeeperPose.new()
	KeeperPoses.butterfly(pose)
	taught.pose(pose)
	for part: int in [KeeperGear.Part.GLOVE, KeeperGear.Part.BLOCKER]:
		var held: Transform3D = KeeperGear.box(taught, part)
		var h: Vector3 = KeeperGear.half_extents(part)
		var was: float = held.origin.y + absf(held.basis.x.y) * h.x + absf(held.basis.y.y) * h.y + absf(held.basis.z.y) * h.z
		assert_lt(_top(part), was - 0.1, "%s: well below where the butterfly holds it" % KeeperGear.Part.keys()[part])


func test_they_come_back_up_when_the_carrier_backs_off() -> void:
	while _body.y < STOP_Z:
		_tick(DRIVING, HELD)
	for i: int in int(0.8 / DT):
		_tick(Vector2.ZERO, HELD)
	assert_lt(_keeper.motor.hands_low.set_m, KeeperHandsLow.highest(), "set low in tight")
	while _body.y > -9.0:
		_tick(-DRIVING, HELD)
	for i: int in int(0.5 / DT):
		_tick(Vector2.ZERO, HELD)
	assert_eq(_keeper.motor.hands_low.set_m, KeeperHandsLow.highest(), "back as his stance holds them")


func test_on_his_feet_they_are_never_asked_down() -> void:
	for i: int in int(1.0 / DT):
		_tick(Vector2.ZERO, Vector2(0.6, 0.0))
		assert_eq(_keeper.motor.hands_low.asked, KeeperHandsLow.highest(), "tick %d" % i)
	assert_eq(_keeper.motor.rest, KeeperRoute.Rest.FEET)

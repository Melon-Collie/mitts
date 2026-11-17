extends GutTest

# The goalie's reach for a puck going wide of him, in a match (KeeperController,
# KeeperReach, KeeperPadOut): the live keeper, down for a real carrier in
# tight, drives the pad on the puck's side out along the ice when the puck is
# carried wide of what his butterfly shuts, before any shot, and brings it back
# under him when the puck comes back in front; a puck held in front of him he
# never reaches for, nor one wide of him while he is on his feet.

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


# The carrier in on him and pulled up in tight, the keeper down for him.
func _in_tight() -> void:
	while _body.y < STOP_Z:
		_tick(DRIVING, HELD)
	for i: int in int(0.8 / DT):
		_tick(Vector2.ZERO, HELD)


func test_a_puck_held_in_front_of_him_he_does_not_reach_for() -> void:
	_in_tight()
	assert_eq(_keeper.motor.rest, KeeperRoute.Rest.DOWN, "down for the carrier in tight")
	assert_eq(_keeper.motor.pad_out.share, 0.0, "both pads under him")
	assert_eq(_keeper.motor.pad_out.asked, 0.0)


func test_a_puck_carried_wide_of_him_he_reaches_a_pad_out_to() -> void:
	for side: float in [1.0, -1.0]:
		before_each()
		_in_tight()
		var what: String = "%+.0f" % side
		var out_to: float = 0.0
		var furthest: float = 0.0
		# The carrier steps wide and holds the puck out past him, shooting nothing.
		for i: int in int(0.9 / DT):
			_tick(Vector2(side * 3.0, 0.0) if absf(_body.x) < 1.0 else Vector2.ZERO, Vector2(side * 0.6, 0.3))
			assert_false(_keeper.read.reading(), "%s: no shot" % what)
			if _keeper.motor.pad_out.share > furthest:
				furthest = _keeper.motor.pad_out.share
				out_to = _keeper.motor.pad_out.side
		assert_gt(furthest, 0.5, "%s: a pad well on its way out before any shot" % what)
		assert_eq(out_to, side, "%s: the one on the puck's side" % what)
		assert_ne(_keeper.motor.rest, KeeperRoute.Rest.FEET, "%s: on his knees throughout" % what)
		# Back in front of him, and held there.
		for i: int in int(1.5 / DT):
			_tick(Vector2(-side * 3.0, 0.0) if absf(_body.x) > 0.05 else Vector2.ZERO, HELD)
		assert_eq(_keeper.motor.pad_out.share, 0.0, "%s: back under him with the puck in front" % what)


func test_on_his_feet_he_reaches_for_nothing() -> void:
	for i: int in int(1.0 / DT):
		_tick(Vector2.ZERO, Vector2(1.6, 0.0))
		assert_eq(_keeper.motor.pad_out.asked, 0.0, "tick %d" % i)
	assert_eq(_keeper.motor.rest, KeeperRoute.Rest.FEET)

extends GutTest

# The goalie's poke check in a match (KeeperController, KeeperPoke): a real
# carrier driving in on him with the puck out in front of his body, the live
# keeper stepped as the game steps him and his gear a wall to the carried puck
# (GoalieGearCollision, as the carrier's controller holds it), his blade box
# meets the puck and knocks it off, crediting no skater, the brain placing him
# all the while. A carrier holding it behind his body he leaves; one who pulls
# it back once he has thrust has it gone when the blade arrives, and the stick
# comes back.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 3.0
# The carrier's start and drive, and where he holds the puck from his body,
# net frame (x across, z back into the net).
const FROM := Vector2(-0.4, -6.5)
const DRIVING := Vector2(0.0, 3.0)
const OUT_FRONT := Vector2(0.0, 0.7)
const BEHIND := Vector2(0.3, -0.6)
# Where the carrier pulls up: in tight, short of the crease.
const STOP_Z: float = -2.4


# The brain, counting the times it decides while a poke is under way.
class CountingBrain extends KeeperPositioning:
	var keeper: KeeperController = null
	var while_poking: int = 0

	func decide(puck_at: Vector2, motion: Vector2, motor: KeeperMotor) -> void:
		if keeper._poking:
			while_poking += 1
		super.decide(puck_at, motion, motor)


var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _carrier: Skater = null
var _brain: CountingBrain = null
var _strips: Array[Skater] = []
var _checkers: Array = []
var _poked: bool = false
var _boxes := PackedFloat32Array()
var _parts: Array = []
var _part_goalies: Array = []
var _velocities := PackedVector3Array()


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
	_brain = CountingBrain.new()
	_brain.keeper = _keeper
	_brain.play = _keeper.play
	_keeper.brain = _brain
	_strips.clear()
	_checkers.clear()
	_poked = false
	_puck.puck_stripped.connect(func(ex: Skater, checker: Skater) -> void:
		_strips.append(ex)
		_checkers.append(checker))


func test_a_puck_driven_at_him_out_in_front_he_pokes_off() -> void:
	_drive_in(OUT_FRONT)
	assert_eq(_strips.size(), 1, "poked off once")
	if _strips.is_empty():
		return
	assert_eq(_strips[0], _carrier, "off the carrier")
	assert_null(_checkers[0], "no skater credited")
	assert_null(_puck.get_carrier(), "loose")
	assert_gt(_brain.while_poking, 0, "placed by the brain as he poked")


func test_a_puck_held_behind_its_carrier_he_leaves() -> void:
	_drive_in(BEHIND)
	assert_false(_poked, "the body between: not poked at")
	assert_eq(_strips.size(), 0, "not poked off")


func test_a_puck_pulled_back_once_he_has_thrust_he_misses() -> void:
	_drive_in(OUT_FRONT, BEHIND)
	assert_true(_poked, "poked at")
	assert_eq(_strips.size(), 0, "pulled back: missed")
	assert_false(_keeper._poking, "the poke over")
	assert_eq(_keeper.save.hand, KeeperSave.Hand.NONE, "the stick home")
	assert_gt(_brain.while_poking, 0, "placed by the brain as he poked")


# The carrier driving in and pulling up in tight, the puck held at `held` from
# his body (at `pulled` once a poke is under way) and held off the goalie's
# gear, until it is poked off or the time is up.
func _drive_in(held: Vector2, pulled: Vector2 = held) -> void:
	_puck.set_carrier(_carrier)
	var body: Vector2 = FROM
	var was := Vector3.INF
	var t: float = 0.0
	while t < SECONDS and _puck.get_carrier() == _carrier:
		var moving: Vector2 = DRIVING if body.y < STOP_Z else Vector2.ZERO
		body += moving * DT
		_carrier.global_position = _keeper._net * Vector3(body.x, 0.0, body.y)
		_carrier.velocity = _keeper._net.basis * Vector3(moving.x, 0.0, moving.y)
		var on_blade: Vector2 = body + (pulled if _poked else held)
		var at: Vector3 = _keeper._net * Vector3(on_blade.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, on_blade.y)
		_puck.global_position = at + _off_his_gear(at if was == Vector3.INF else was, at)
		was = _puck.global_position
		_keeper._view.invalidate()
		_keeper._physics_process(DT)
		_poked = _poked or _keeper._poking
		t += DT


func _off_his_gear(prev: Vector3, at: Vector3) -> Vector3:
	var n: int = GoalieContactDetector.gather_boxes([_goalie], _boxes, _parts, _part_goalies, _velocities, false)
	_boxes.resize(n * GoalieGearCollision.FLOATS_PER_BOX)
	return GoalieGearCollision.resolve(prev, at, at, GameRules.PUCK_COLLISION_RADIUS, _boxes)

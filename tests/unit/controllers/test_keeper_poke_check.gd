extends GutTest

# The goalie's poke check in a match (KeeperController, KeeperPoke): a real
# carrier skating in on him with the puck out in front of his body, the live
# keeper stepped as the game steps him, his blade box meets the puck and knocks
# it off, crediting no skater. A carrier holding it behind his body he leaves;
# one who pulls it back once he has thrust has it gone when the blade arrives,
# and the stick comes back.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SECONDS: float = 3.0
# The carrier's start and skating, and where he holds the puck from his body,
# net frame (x across, z back into the net).
const FROM := Vector2(-0.4, -5.5)
const SKATING := Vector2(0.0, 1.8)
const OUT_FRONT := Vector2(0.0, 0.7)
const BEHIND := Vector2(0.3, -0.6)
# Where the carrier pulls up: in tight, short of the crease.
const STOP_Z: float = -2.4

var _goalie: Goalie = null
var _puck: Puck = null
var _keeper: KeeperController = null
var _carrier: Skater = null
var _strips: Array[Skater] = []
var _checkers: Array = []


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
	_strips.clear()
	_checkers.clear()
	_puck.puck_stripped.connect(func(ex: Skater, checker: Skater) -> void:
		_strips.append(ex)
		_checkers.append(checker))


func test_a_puck_out_in_front_of_its_carrier_he_pokes_off() -> void:
	_skate_in(OUT_FRONT)
	assert_eq(_strips.size(), 1, "poked off once")
	if _strips.is_empty():
		return
	assert_eq(_strips[0], _carrier, "off the carrier")
	assert_null(_checkers[0], "no skater credited")
	assert_null(_puck.get_carrier(), "loose")


func test_a_puck_held_behind_its_carrier_he_leaves() -> void:
	_skate_in(BEHIND)
	assert_eq(_strips.size(), 0, "the body between: not poked")


func test_a_puck_pulled_back_once_he_has_thrust_he_misses() -> void:
	_skate_in(OUT_FRONT, BEHIND)
	assert_eq(_strips.size(), 0, "pulled back: missed")
	assert_lt(_keeper._poking, 0.0, "the poke over")
	assert_eq(_keeper.save.hand, KeeperSave.Hand.NONE, "the stick home")


# The carrier skating in and pulling up in tight, the puck held at `held` from
# his body (at `pulled` once a poke is under way), until it is poked off or the
# time is up.
func _skate_in(held: Vector2, pulled: Vector2 = held) -> void:
	_puck.set_carrier(_carrier)
	var body: Vector2 = FROM
	var t: float = 0.0
	while t < SECONDS and _puck.get_carrier() == _carrier:
		var moving: Vector2 = SKATING if body.y < STOP_Z else Vector2.ZERO
		body += moving * DT
		_carrier.global_position = _keeper._net * Vector3(body.x, 0.0, body.y)
		_carrier.velocity = _keeper._net.basis * Vector3(moving.x, 0.0, moving.y)
		if _keeper._poking >= 0.0:
			held = pulled
		var at: Vector2 = body + held
		_puck.global_position = _keeper._net * Vector3(at.x, GameRules.PUCK_COLLISION_HALF_HEIGHT, at.y)
		_keeper._view.invalidate()
		_keeper._physics_process(DT)
		t += DT

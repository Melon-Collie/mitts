extends GutTest

# The host's punch judge (FightPunchJudge): a fist swept into the other man's
# head fast enough lands on it, an arm up in his guard in its way blocks it (one
# thrown or holding does not), one too slow lands nothing, a fist that landed
# lands nothing more for the cooldown, and nothing lands with a man down.
# Real Skater scenes, never ticked; the fists placed on their markers by hand.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 90.0
const Hit = FightPunchRules.Hit

var _judge: FightPunchJudge = null
var _a: Skater = null
var _b: Skater = null
var _now: float = 10.0
var _landed: Array = []


func before_each() -> void:
	_a = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0), Vector2(0.0, -1.0))
	_b = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, -0.9), Vector2(0.0, 1.0))
	for s: Skater in [_a, _b]:
		s.fight_role = FightRules.Role.FIGHTING
		s.fight_punch_side = FightHoldRules.Side.TOP
	_now = 10.0
	_landed.clear()
	_judge = FightPunchJudge.new()
	_judge.setup(func(s: Skater) -> Skater: return _b if s == _a else _a,
			func() -> float: return _now)
	_judge.punch_landed.connect(func(at: Skater, v: Skater, hit: int, speed: float,
			_toward: Vector3) -> void: _landed.append([at, v, hit, speed]))


func _spawn(at: Vector3, facing: Vector2) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(s)
	s.set_process(false)
	s.set_physics_process(false)
	s.global_position = at
	s.set_facing(facing)
	return s


# A's punching fist put at `world`, both men's off hands kept down out of it.
func _fist_at(world: Vector3) -> void:
	_a.set_top_hand_position(_a.upper_body_to_local(world))
	_a.set_blade_position(_a.upper_body_to_local(_a.global_position + Vector3(0.3, -0.5, 0.0)))
	_b.set_blade_position(_b.upper_body_to_local(_b.global_position + Vector3(0.3, -0.5, 0.0)))
	_b.set_top_hand_position(_b.upper_body_to_local(_b.global_position + Vector3(-0.3, -0.5, 0.0)))


func _tick() -> void:
	_judge.tick([_a, _b] as Array[Skater], DT)
	_now += DT


func _punch(from_world: Vector3, to_world: Vector3) -> void:
	_fist_at(from_world)
	_tick()
	_fist_at(to_world)
	_tick()


func test_a_fast_fist_through_his_head_lands_on_it() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	_punch(head + Vector3(0.0, 0.0, 8.0 * DT), head)
	assert_eq(_landed.size(), 1)
	assert_eq(_landed[0][2], Hit.HEAD)
	assert_almost_eq(float(_landed[0][3]), 8.0, 0.5, "at the fist's speed")


func test_a_slow_fist_is_a_hand_on_him() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	_punch(head + Vector3(0.0, 0.0, 0.14), head + Vector3(0.0, 0.0, 0.12))
	assert_true(_landed.is_empty())


func test_an_arm_in_the_way_blocks_it() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	var from: Vector3 = head + Vector3(0.0, 0.0, 0.25)
	_fist_at(from)
	_tick()
	_fist_at(head)
	# His top arm up across his face, between the fist and his chin.
	var guard: Vector3 = head + Vector3(0.0, -0.02, 0.15)
	_b.set_top_hand_position(_b.upper_body_to_local(guard))
	_tick()
	var mine: Array = _landed.filter(func(l: Array) -> bool: return l[0] == _a)
	assert_eq(mine.size(), 1)
	assert_eq(mine[0][2], Hit.BLOCKED)


func test_an_arm_thrown_guards_nothing() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	_fist_at(head + Vector3(0.0, 0.0, 0.8))
	_tick()
	_fist_at(head)
	# His punching arm out at us, along the fist's way in.
	_b.set_top_hand_position(_b.upper_body_to_local(head + Vector3(0.0, -0.02, 0.6)))
	assert_true(SkaterFightHands.arm_thrown(_b, true))
	_tick()
	var mine: Array = _landed.filter(func(l: Array) -> bool: return l[0] == _a)
	assert_eq(mine.size(), 1)
	assert_eq(mine[0][2], Hit.HEAD)


func test_the_off_hand_guards_until_it_holds() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	var guard: Vector3 = head + Vector3(0.0, -0.02, 0.15)
	for grip: int in [FightHoldRules.Grip.NONE, FightHoldRules.Grip.JERSEY]:
		_landed.clear()
		_now += 1.0
		_fist_at(head + Vector3(0.0, 0.0, 0.25))
		_tick()
		_fist_at(head)
		_b.set_blade_position(_b.upper_body_to_local(guard))
		_b.fight_grip = grip
		_tick()
		var mine: Array = _landed.filter(func(l: Array) -> bool: return l[0] == _a)
		assert_eq(mine.size(), 1)
		assert_eq(mine[0][2], Hit.BLOCKED if grip == FightHoldRules.Grip.NONE else Hit.HEAD)


func test_nothing_lands_with_a_man_down() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	_b.is_knocked_down = true
	_punch(head + Vector3(0.0, 0.0, 0.2), head)
	assert_true(_landed.is_empty(), "not on a man on the ice")
	_b.is_knocked_down = false
	_a.is_knocked_down = true
	_now += 1.0
	_punch(head + Vector3(0.0, 0.0, 0.2), head)
	assert_true(_landed.is_empty(), "and not from one")


func test_one_punch_lands_once() -> void:
	var head: Vector3 = FightPunchJudge.head_center(_b)
	_punch(head + Vector3(0.0, 0.0, 0.2), head)
	_punch(head + Vector3(0.0, 0.0, 0.2), head)
	assert_eq(_landed.size(), 1, "inside the cooldown the second lands nothing")
	_now += FightPunchRules.HIT_COOLDOWN_S
	_punch(head + Vector3(0.0, 0.0, 0.2), head)
	assert_eq(_landed.size(), 2)

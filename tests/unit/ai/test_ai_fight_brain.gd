extends GutTest

# AIFightBrain: a bot fights with the three controls a human does. It guards
# and holds the sweater, throws through the open side of the man's guard on its
# tier's cadence, and — reading it a reaction delay late — catches his thrown
# arm and swaps hands out of a tie. Easy does neither of the last two.

const DT: float = 1.0 / 90.0

var _v := AIFightBrain.View.new()


func before_each() -> void:
	_v = AIFightBrain.View.new()
	_v.me = Vector3.ZERO
	_v.facing = Vector2(0.0, -1.0)
	_v.head = Vector3(0.0, 1.6, -0.9)
	_v.his_top_fist = Vector3(0.15, 1.6, -0.6)     # covering the line to his head
	_v.his_bottom_fist = Vector3(-0.4, 1.2, -0.7)  # down and out on the other side


func _brain(profile: BotSkillProfile, phase_s: float = 0.0) -> AIFightBrain:
	var b := AIFightBrain.new()
	b.setup(profile, phase_s)
	return b


func _run(b: AIFightBrain, seconds: float) -> Array[AIFightBrain.Decision]:
	var out: Array[AIFightBrain.Decision] = []
	for i: int in roundi(seconds / DT):
		var d: AIFightBrain.Decision = b.decide(_v, DT)
		var copy := AIFightBrain.Decision.new()
		copy.aim = d.aim
		copy.grab = d.grab
		copy.swap = d.swap
		out.append(copy)
	return out


func _throws(ds: Array[AIFightBrain.Decision]) -> int:
	var n: int = 0
	var out: bool = false
	for d: AIFightBrain.Decision in ds:
		var throwing: bool = d.aim.distance_to(_v.me) > 0.6
		if throwing and not out:
			n += 1
		out = throwing
	return n


func test_between_throws_it_guards_and_holds_the_sweater() -> void:
	var b := _brain(BotSkillProfile.normal(), 1.0)
	var d: AIFightBrain.Decision = b.decide(_v, DT)
	assert_almost_eq(d.aim.distance_to(_v.me), AIFightBrain.GUARD_AHEAD_M, 1e-4)
	assert_true(d.grab)
	assert_false(d.swap)


func test_it_throws_through_his_head_on_its_cadence() -> void:
	var b := _brain(BotSkillProfile.normal(), 0.0)
	var ds: Array[AIFightBrain.Decision] = _run(b, 5.0)
	assert_gt(_throws(ds), 2, "several punches in five seconds")
	var thrown: AIFightBrain.Decision = null
	for d: AIFightBrain.Decision in ds:
		if d.aim.distance_to(_v.me) > 0.6:
			thrown = d
			break
	assert_lt(thrown.aim.z, _v.head.z, "driven through, past his head")


func test_an_aggressive_tier_throws_more() -> void:
	var hard: int = _throws(_run(_brain(BotSkillProfile.hard()), 10.0))
	var easy: int = _throws(_run(_brain(BotSkillProfile.easy()), 10.0))
	assert_gt(hard, easy)


func test_it_goes_round_the_side_his_guard_leaves_open() -> void:
	var b := _brain(BotSkillProfile.normal(), 0.0)
	var d: AIFightBrain.Decision = b.decide(_v, DT)
	# His top fist covers the line on +x; the throw goes round on −x.
	assert_lt(d.aim.x, 0.0)


func test_it_does_not_throw_with_its_arm_held() -> void:
	_v.my_arm_held = true
	var easy := _brain(BotSkillProfile.easy(), 0.0)
	assert_eq(_throws(_run(easy, 4.0)), 0)


func test_it_swaps_out_of_a_tie_a_reaction_late() -> void:
	_v.my_arm_held = true
	var profile := BotSkillProfile.normal()
	var ds: Array[AIFightBrain.Decision] = _run(_brain(profile, 1.0), 1.0)
	var first: int = -1
	for i: int in ds.size():
		if ds[i].swap:
			first = i
			break
	assert_gt(first, -1, "it frees its arm")
	assert_almost_eq(float(first + 1) * DT, profile.carrier_reaction_delay_s, DT * 1.5,
			"once it has seen it held")
	assert_false(_run(_brain(BotSkillProfile.easy(), 1.0), 2.0).any(
			func(d: AIFightBrain.Decision) -> bool: return d.swap), "Easy never swaps")


func test_it_catches_a_thrown_arm_a_reaction_late() -> void:
	_v.his_arm_thrown = true
	_v.my_grip = FightHoldRules.Grip.JERSEY
	var profile := BotSkillProfile.normal()
	var ds: Array[AIFightBrain.Decision] = _run(_brain(profile, 1.0), 0.6)
	var let_go: int = -1
	for i: int in ds.size():
		if not ds[i].grab:
			let_go = i
			break
	assert_gt(let_go, -1, "it lets the sweater go for his arm")
	assert_almost_eq(float(let_go + 1) * DT, profile.carrier_reaction_delay_s, DT * 1.5)
	assert_true(ds[let_go + 1].grab, "for one tick: the grab takes again at once")
	assert_false(_run(_brain(BotSkillProfile.easy(), 1.0), 2.0).any(
			func(d: AIFightBrain.Decision) -> bool: return not d.grab), "Easy keeps the sweater")


func test_holding_his_arm_it_keeps_it() -> void:
	_v.his_arm_thrown = true
	_v.my_grip = FightHoldRules.Grip.ARM_TOP
	assert_false(_run(_brain(BotSkillProfile.hard(), 1.0), 1.0).any(
			func(d: AIFightBrain.Decision) -> bool: return not d.grab))

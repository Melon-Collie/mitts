extends GutTest

# AIFightBrain: a bot fights with the controls a human does. It skates in to
# where its fist reaches, guards and holds the sweater, throws on its tier's
# cadence — straight through an open man's head, a hook round the open side of a
# guard — and, reading it a reaction delay late, catches his thrown arm and
# swaps hands out of a tie. Easy does neither of the last two. With a man down
# it stands off.

const DT: float = 1.0 / 90.0

var _v := AIFightBrain.View.new()


func before_each() -> void:
	_v = AIFightBrain.View.new()
	_v.me = Vector3.ZERO
	_v.facing = Vector2(0.0, -1.0)
	_v.reach = 0.7
	_v.him = Vector3(0.0, 0.0, -0.72)
	_v.head = Vector3(0.0, 1.6, -0.72)
	_v.his_top_fist = Vector3(0.05, 1.6, -0.45)    # up in front of his face
	_v.his_bottom_fist = Vector3(-0.4, 1.5, -0.6)  # up, out on the other side
	_v.his_top_guards = true
	_v.his_bottom_guards = true


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
		copy.move = d.move
		copy.brake = d.brake
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


func test_it_throws_on_its_cadence() -> void:
	var ds: Array[AIFightBrain.Decision] = _run(_brain(BotSkillProfile.normal(), 0.0), 5.0)
	assert_gt(_throws(ds), 2, "several punches in five seconds")


func test_with_no_guard_up_it_throws_straight_through_his_head() -> void:
	_v.his_top_guards = false
	_v.his_bottom_guards = false
	var d: AIFightBrain.Decision = _brain(BotSkillProfile.normal(), 0.0).decide(_v, DT)
	assert_almost_eq(d.aim.x, 0.0, 1e-4)
	assert_lt(d.aim.z, _v.head.z, "driven through, past his head")


func test_it_hooks_round_the_side_his_guard_leaves_open() -> void:
	# His off hand guards out on −x: the hook winds out beside his head on +x,
	# then goes across through it.
	var ds: Array[AIFightBrain.Decision] = _run(_brain(BotSkillProfile.normal(), 0.0),
			AIFightBrain.WIND_S + AIFightBrain.THROW_S)
	assert_almost_eq(ds[0].aim.x, AIFightBrain.HOOK_OUT_M, 1e-4, "out beside his head")
	assert_almost_eq(ds[0].aim.z, _v.head.z, 1e-4)
	assert_lt(ds[ds.size() - 1].aim.x, _v.head.x, "then across, through it")


func test_an_arm_that_holds_or_punches_is_no_guard_to_go_round() -> void:
	# His off hand on our sweater: only the fist in front of his face guards, a
	# touch to +x of the line, so the hook goes round on −x.
	_v.his_bottom_guards = false
	var d: AIFightBrain.Decision = _brain(BotSkillProfile.normal(), 0.0).decide(_v, DT)
	assert_almost_eq(d.aim.x, -AIFightBrain.HOOK_OUT_M, 1e-4)


func test_it_skates_in_until_its_fist_reaches_and_throws_only_from_there() -> void:
	_v.him = Vector3(0.0, 0.0, -2.0)
	_v.head = Vector3(0.0, 1.6, -2.0)
	var b := _brain(BotSkillProfile.hard(), 0.0)
	var ds: Array[AIFightBrain.Decision] = _run(b, 3.0)
	assert_eq(_throws(ds), 0, "nothing thrown at a man out of reach")
	assert_almost_eq(ds[0].move, Vector2(0.0, -1.0), Vector2(1e-4, 1e-4), "it skates at him")
	assert_false(ds[0].brake)
	_v.him = Vector3(0.0, 0.0, -0.72)
	_v.head = Vector3(0.0, 1.6, -0.72)
	var d: AIFightBrain.Decision = b.decide(_v, DT)
	assert_eq(d.move, Vector2.ZERO, "and stands once it is there")
	assert_true(d.brake)


func test_a_man_who_has_skated_off_is_let_go() -> void:
	_v.him = Vector3(0.0, 0.0, -(FightRules.DISENGAGE_M + 0.5))
	var d: AIFightBrain.Decision = _brain(BotSkillProfile.hard(), 0.0).decide(_v, DT)
	assert_eq(d.move, Vector2.ZERO)
	assert_true(d.brake)


func test_with_a_man_down_it_stands_off() -> void:
	_v.man_down = true
	var b := _brain(BotSkillProfile.hard(), 0.0)
	var ds: Array[AIFightBrain.Decision] = _run(b, 3.0)
	assert_eq(_throws(ds), 0)
	assert_false(b.throwing())
	for d: AIFightBrain.Decision in ds:
		assert_false(d.grab, "it lets him go")
		assert_eq(d.move, Vector2.ZERO)


func test_an_aggressive_tier_throws_more() -> void:
	var hard: int = _throws(_run(_brain(BotSkillProfile.hard()), 10.0))
	var easy: int = _throws(_run(_brain(BotSkillProfile.easy()), 10.0))
	assert_gt(hard, easy)


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

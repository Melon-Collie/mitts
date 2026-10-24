extends GutTest

# The press is laid by both bodies of a pair, on the host and again on a client
# in its live step and its reconcile replay, so every one of them must read the
# other body at one instant (Scripts/networking/CLAUDE.md, the body-contact
# rule). Three parts of it:
# - the host's controllers run in scene order, and which runs first must not
#   change the press;
# - a client reads the other body from the host's snapshots, which it can place
#   on the host's tick only to within a tick, so the contact must hold through a
#   tick of the other body's travel at any speed a press reaches;
# - a client's live step reads the other body from the same buffered sample its
#   replay does, not from the node drawn on screen.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUSH_S: float = 2.0
const DT: float = PressHarness.DT


func _carry_spec() -> PressHarness.Spec:
	var s := PressHarness.Spec.new()
	s.man_brake = true
	s.attacker = "skate commit"
	return s


func test_the_host_presses_the_same_whichever_controller_runs_first() -> void:
	var first := PressHarness.new(self)
	var a: PressHarness.Result = first.run(_carry_spec(), 0.5)
	var second := PressHarness.new(self)
	second.attacker_first = true
	var b: PressHarness.Result = second.run(_carry_spec(), 0.5)
	assert_gt(a.gave, 0.01, "the braking man gave ground, so the press ran")
	for k: int in a.man_at.size():
		if not a.man_at[k].is_equal_approx(b.man_at[k]):
			fail_test("tick %d: the man at %s or %s by controller order" % [k, a.man_at[k],
					b.man_at[k]])
			return
	pass_test("one trajectory")


# A man doing nothing, carried by a committed drive from behind: the pair runs up
# to the power-limited stride.
func _carried() -> PressHarness:
	var h := PressHarness.new(self)
	var s := PressHarness.Spec.new()
	s.attacker = "skate commit"
	h.set_meta("result", h.run(s, PUSH_S))
	return h


# Body edge to body edge from the attacker as the host had him at the start of
# tick k to the man as a client reads him `ticks` from there (either side,
# between the host's end-of-tick states).
func _gap(h: PressHarness, k: int, ticks: float) -> float:
	var r: PressHarness.Result = h.get_meta("result")
	var at: float = float(k - 1) + ticks
	var lo: int = floori(at)
	var man_at: Vector3 = r.man_at[lo].lerp(r.man_at[mini(lo + 1, r.man_at.size() - 1)],
			at - float(lo))
	var d: Vector3 = man_at - r.attacker_at[k - 1]
	d.y = 0.0
	return d.length() - h.man.skater.collision_radius() - h.attacker.skater.collision_radius()


# Ticks where the host had the pair touching and a client reading the man up to
# `ticks_off` ticks either side would call them apart under `touching`
# (Callable(gap, the man's speed along the line) → bool).
func _lost_ticks(h: PressHarness, touching: Callable, ticks_off: float) -> int:
	var r: PressHarness.Result = h.get_meta("result")
	var lost: int = 0
	for k: int in range(1 + ceili(ticks_off), r.man_at.size() - ceili(ticks_off)):
		if _gap(h, k, 0.0) >= PressRules.CONTACT_SLACK_M:
			continue
		var n: Vector3 = (r.man_at[k - 1] - r.attacker_at[k - 1]).normalized()
		var speed_along: float = r.man_vel[k - 1].dot(n)
		for ticks: float in [-ticks_off, -0.5 * ticks_off, 0.5 * ticks_off, ticks_off]:
			if not touching.call(_gap(h, k, ticks), speed_along):
				lost += 1
				break
	return lost


func test_a_fixed_slack_loses_a_carried_man_a_tick_off() -> void:
	var h: PressHarness = _carried()
	var r: PressHarness.Result = h.get_meta("result")
	assert_gt(r.man_speed, PressRules.CONTACT_SLACK_M / DT,
			"carried past a slack's worth of travel a tick")
	var fixed := func(gap: float, _speed_along: float) -> bool:
		return gap < PressRules.CONTACT_SLACK_M
	assert_gt(_lost_ticks(h, fixed, 1.0), 0, "the read a tick off is what the slack must cover")


func test_a_client_keeps_a_carried_man_through_its_timing() -> void:
	var h: PressHarness = _carried()
	var client := func(gap: float, speed_along: float) -> bool:
		return PressRules.touching(gap, speed_along, LocalController.PRESS_READ_TIMING_S)
	var off: float = LocalController.PRESS_READ_TIMING_S / DT
	assert_eq(_lost_ticks(h, client, off), 0, "never lost while the host has him")


# A client's live step, not replaying, on a client: the man is where the buffered
# sample has him, touching, while his node is drawn 30 cm off.
func test_a_clients_live_step_reads_the_buffered_partner() -> void:
	var me: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(me)
	me.set_physics_process(false)
	me.set_process(false)
	var man: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(man)
	man.set_physics_process(false)
	man.set_process(false)
	man.press_cfg = SkaterMovementRules.league_config()
	man.global_position = me.global_position + Vector3(0.0, 0.0, 0.3 + me.collision_radius()
			+ man.collision_radius())
	me.set_skater_collision_provider(func() -> Array: return [me, man])
	var sampled: Vector3 = me.global_position + Vector3(0.0, 0.0,
			me.collision_radius() + man.collision_radius())
	var record: Dictionary = {"skater": man, "position": sampled, "velocity": Vector3.ZERO,
			"hit": false, "puck": false, "ghost": false, "shot_state": 0,
			"facing": Vector2(0.0, -1.0), "intent": Vector2.ZERO, "brake": true,
			"stance": true, "stagger": 0.0}
	var ctrl := LocalController.new()
	autofree(ctrl)
	ctrl.skater = me
	ctrl._is_host = false
	ctrl.set_historical_others_provider(func(_s: Skater, _ts: float) -> Array: return [record])
	var out := SkaterController.PressPartner.new()
	assert_true(ctrl._find_press_partner(1.0, out), "touching where the sample has him")
	assert_eq(out.position, sampled)
	assert_true(out.braking, "and as the sample has him: dug in")

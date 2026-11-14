extends GutTest

# The duel harness's press (duel_harness.gd:_press) against the live rig's
# (PressHarness: two real SkaterControllers): the same push, from behind, for
# the same time, moves the man as far.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const PRESS_S: float = 0.75
# The live body's own contact resolution and integration differ from the
# duel's in the last centimetres.
const TOLERANCE_M: float = 0.02


func _live(man: String) -> float:
	var s := PressHarness.Spec.new()
	s.man_does(man)
	s.attacker = "skate commit"
	return PressHarness.new(self).run(s, PRESS_S).gave


# The duel's man at the origin facing +z, the attacker touching him from
# behind, driving +z with the check button down, its drive long spent.
func _duel(man: String) -> float:
	var duel: Object = Duel.new()
	var r: float = duel._match_body.radius if duel._match_body != null else 0.4
	duel.add_skater(1, 0, Vector3(0.0, 0.0, 0.0))
	duel.add_skater(2, 1, Vector3(0.0, 0.0, -2.0 * r))
	duel.start(-1, Vector3(20.0, 0.0, 20.0))
	var m: Object = duel.skaters[0]
	var a: Object = duel.skaters[1]
	m.facing = Vector2(0.0, 1.0)
	a.facing = Vector2(0.0, 1.0)
	a.drive_phase = CheckDriveRules.Phase.SPENT
	a.drive_elapsed = CheckDriveRules.REARM_S
	if man.contains("commit"):
		m.drive_phase = CheckDriveRules.Phase.SPENT
		m.drive_elapsed = CheckDriveRules.REARM_S
	m.input_override = func(s: Object) -> void:
		SkaterAgent.zero_input(s.input, Duel.DT, s.input.host_timestamp)
		s.input.hit_held = man.contains("commit")
		s.input.brake = man.contains("brake")
		s.input.mouse_world_pos = s.pos + Vector3(0.0, 0.0, 3.0)
	a.input_override = func(s: Object) -> void:
		SkaterAgent.zero_input(s.input, Duel.DT, s.input.host_timestamp)
		s.input.hit_held = true
		s.input.move_vector = Vector2(0.0, 1.0)
		s.input.mouse_world_pos = s.pos + Vector3(0.0, 0.0, 3.0)
	var from: Vector3 = m.pos
	duel.run(PRESS_S)
	return m.pos.z - from.z


func test_the_duel_press_moves_a_man_as_the_live_rig_does() -> void:
	for man: String in ["nothing", "brake", "commit brake", "commit"]:
		var live: float = _live(man)
		var duel: float = _duel(man)
		gut.p("press %s: live %.3f m, duel %.3f m" % [man, live, duel])
		assert_almost_eq(duel, live, TOLERANCE_M, man)

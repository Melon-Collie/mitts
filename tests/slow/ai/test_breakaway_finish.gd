extends GutTest

# A breakaway ends in a shot, skated in facing the net.
#
# A real bot carrier against the real keeper (KeeperController on Goalie.tscn,
# ticked off the bot's puck), alone or with a backchecker on his tail, from the
# red line and the blue line. Each run must release a shot inside the window,
# never lose the puck, and never turn to skate backward or pull up on the way in:
# a carry that cannot price a drive at the net brakes in the slot or cuts back
# toward it facing up the ice, and stands there.
#
# The bots get the controller's own carry facing (its backhand edge), as
# PlayerRegistry hands them in a match; the duel harness's league caps would let
# the shot's hold reach further round the backhand than the body turns.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = 1.0 / 120.0
const CARRIER := 1
const CHASER := 201
const WINDOW_S: float = 4.0

var _goalie: Node
var _puck: Node
var _shooter: Skater
var _ctrl: GoalieController


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_shooter.set_physics_process(false)
	_shooter.set_process(false)
	_ctrl.setup(_goalie, _puck, -GameRules.GOAL_LINE_Z, true)
	_ctrl.reset_to_crease()


func _match_caps(duel: RefCounted) -> void:
	var ctrl := SkaterController.new()
	var caps_by_peer: Dictionary = {}
	for sk: Object in duel.skaters:
		var caps := AISkaterCaps.new()
		caps.facing_rules = ctrl.facing_rules
		var carry := FacingRules.Config.new()
		carry.forehand_edge_rad = ctrl.facing_rules.forehand_edge_rad
		carry.backhand_edge_rad = deg_to_rad(ctrl.bh_release_angle_deg)
		carry.forehand_yield_rad = deg_to_rad(ctrl.carry_forehand_yield_deg)
		caps.carry_facing_rules = carry
		caps.is_left_handed = false
		caps_by_peer[sk.peer_id] = caps
	ctrl.free()
	for sk: Object in duel.skaters:
		sk.agent.setup(sk.peer_id, sk.team_id, duel.brains[sk.team_id], duel.team_map, false,
				caps_by_peer)
		sk.agent.apply_capabilities(caps_by_peer[sk.peer_id])


# Skates one breakaway; returns {shot, lost, backward_ticks, min_speed, release,
# start_speed}.
func _breakaway(start: Vector3, vel: Vector3, chaser_offset: Vector3) -> Dictionary:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, start, null, vel)
	if chaser_offset.is_finite():
		duel.add_skater(CHASER, 1, start + chaser_offset, null, vel)
	duel.start(CARRIER)
	_match_caps(duel)
	_shooter.global_position = start
	_puck.set_carrier(_shooter)
	duel.goalie_provider = func(team_id: int, puck_pos: Vector3) -> Variant:
		if team_id != 1:
			return null
		_shooter.global_position = puck_pos
		_puck.global_position = puck_pos
		_ctrl._physics_process(DT)
		return _goalie.global_position
	var out := {"shot": false, "lost": false, "backward_ticks": 0, "release": Vector3.INF,
			"min_speed": INF, "start_speed": vel.length()}
	for _t: int in int(WINDOW_S / DT):
		var before: int = duel.releases.size()
		duel.step()
		var s: Object = duel._skater(CARRIER)
		if duel.releases.size() > before:
			out["shot"] = duel.releases[-1].get("decision", "") == "SHOOT"
			out["release"] = s.pos
			return out
		if duel.carrier_id != CARRIER:
			out["lost"] = true
			return out
		var v := Vector2(s.vel.x, s.vel.z)
		out["min_speed"] = minf(out["min_speed"], v.length())
		if v.length() > 1.0 and v.normalized().dot(s.facing) < -0.3:
			out["backward_ticks"] += 1
	return out


func _assert_finished(label: String, r: Dictionary) -> void:
	gut.p("%s: shot %s, lost %s, backward %d ticks, slowest %.1f m/s, release %s" % [
			label, r["shot"], r["lost"], r["backward_ticks"], r["min_speed"], r["release"]])
	assert_false(r["lost"], "%s: the carrier keeps the puck to the shot" % label)
	assert_true(r["shot"], "%s: the breakaway ends in a shot inside %.0f s" % [label, WINDOW_S])
	assert_eq(r["backward_ticks"], 0, "%s: he never turns to skate backward" % label)
	assert_gt(r["min_speed"], 0.5 * r["start_speed"],
			"%s: he drives in rather than pulling up in the slot" % label)


func test_a_clean_breakaway_from_the_red_line() -> void:
	_assert_finished("clean", _breakaway(Vector3(0, 0, -1), Vector3(0, 0, -8.5), Vector3.INF))


func test_a_breakaway_with_a_backchecker_on_his_tail() -> void:
	_assert_finished("chased", _breakaway(Vector3(0, 0, -1), Vector3(0, 0, -8.5),
			Vector3(0.5, 0, 3.0)))


func test_a_breakaway_down_the_wing_with_a_backchecker() -> void:
	_assert_finished("wing", _breakaway(Vector3(6, 0, -3), Vector3(-1, 0, -8.5),
			Vector3(-1, 0, 4.0)))


func test_a_slow_breakaway_from_the_blue_line() -> void:
	_assert_finished("slow", _breakaway(Vector3(-2, 0, -GameRules.GOAL_LINE_Z + 19.0),
			Vector3(0, 0, -5.0), Vector3(0, 0, 5.0)))

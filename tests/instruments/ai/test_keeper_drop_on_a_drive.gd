extends GutTest

# ── When the live keeper goes down on a carrier driving in (#946) ─────────────
# A carrier of theirs skating straight in from 20 m out, at several paces and
# lanes, the keeper tracking him from a standing start: where the puck is when
# he first leaves his feet, how long after it came inside
# KeeperPositioning.TIGHT_M of the net's centre, and where he is then. The bots'
# arrival read predicts his stance from this (AIGoalieModel).

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const FROM_M: float = 20.0

var _s: RefCounted = null
var _h: RefCounted = null
var _ctrl: KeeperController = null
var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = KeeperController.new()
	for n: Node in [_goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_s = Stager.new(_goalie, _puck, _ctrl, _shooter)
	_h = _s._h


# Drives in lane `x` at `speed` tick by tick until he leaves his feet or the
# puck reaches the crease; returns the row.
func _drive(x: float, speed: float) -> String:
	_h.settle_ready(Vector3(x, 0.0, GOAL_Z + FROM_M))
	_puck.set_carrier(_shooter)
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	var vel := Vector3(0.0, 0.0, -signf(-GOAL_Z) * speed)
	var pos := Vector3(x, 0.0, GOAL_Z + FROM_M)
	var tight_at: float = NAN
	var t: float = 0.0
	while pos.z - GOAL_Z > CreaseRules.ARC_RADIUS:
		_shooter.global_position = pos
		_shooter.velocity = vel
		_puck.global_position = pos
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(Stager.DT)
		var from_centre: float = Vector2(pos.x, pos.z - GOAL_Z).length()
		if is_nan(tight_at) and from_centre <= KeeperPositioning.TIGHT_M:
			tight_at = t
		if not _ctrl._sm.is_upright():
			var k: Vector3 = (_goalie as Node3D).global_position
			return "lane %4.1f  %4.1f m/s | down with the puck %.2f m from the centre (%.2f off the line), %.2f s after it came within TIGHT_M | keeper (%.2f, %.2f off)" % [
					x, speed, from_centre, pos.z - GOAL_Z, t - tight_at, k.x, k.z - GOAL_Z]
		pos.z += vel.z * Stager.DT
		t += Stager.DT
	return "lane %4.1f  %4.1f m/s | never down before the crease" % [x, speed]


func test_report_when_he_drops() -> void:
	var lines: PackedStringArray = ["TIGHT_M %.2f m, leg read %.3f s, drop %.3f s" % [
			KeeperPositioning.TIGHT_M, AIGoalieModel.goalie_leg_delay_s,
			GoalieSkillProfile.hard().butterfly_drop_s]]
	for x: float in [0.0, 1.0, 2.0]:
		for speed: float in [3.0, 6.0, 9.0]:
			lines.append(_drive(x, speed))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)

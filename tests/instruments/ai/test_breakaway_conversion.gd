extends GutTest

# ── Do the bots' breakaways go in? (#943, #946) ───────────────────────────────
# A real bot carrier alone on a breakaway against the real keeper
# (bot_vs_goalie_harness: the bot picks the shot, the keeper tries to stop it,
# rebounds played out), from three lanes at the red line at a breakaway's pace
# and two at the blue line slower, per tier: how many shots, how many in, and
# where they were released. The measure a release-distance proxy stands for.

const BotGoalie := preload("res://tests/unit/ai/bot_vs_goalie_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z

var _bg: RefCounted = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	var ctrl := KeeperController.new()
	for n: Node in [goalie, puck, shooter, ctrl]:
		add_child_autofree(n)
	shooter.set_physics_process(false)
	shooter.set_process(false)
	_bg = BotGoalie.new()
	_bg.setup(goalie, puck, ctrl, shooter)


static func _starts() -> Array:
	return [
		[Vector3(-3.0, 0.0, -1.0), Vector3(0.0, 0.0, -8.5)],
		[Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -8.5)],
		[Vector3(3.0, 0.0, -1.0), Vector3(0.0, 0.0, -8.5)],
		[Vector3(-2.0, 0.0, GOAL_Z + 19.0), Vector3(0.0, 0.0, -5.0)],
		[Vector3(2.0, 0.0, GOAL_Z + 19.0), Vector3(0.0, 0.0, -5.0)],
	]


func test_report_breakaway_conversion() -> void:
	var lines: PackedStringArray = ["tier   | shots | goals | mean release off the line | per start (off, outcome)"]
	for tier: Array in [["hard", BotSkillProfile.hard()], ["normal", BotSkillProfile.normal()],
			["easy", BotSkillProfile.easy()]]:
		var shots: int = 0
		var goals: int = 0
		var off_sum: float = 0.0
		var per: PackedStringArray = []
		for st: Array in _starts():
			var rec: Dictionary = _bg.run_rush(st[0], st[1], tier[1], 4.0, true)
			if rec["outcome"] == BotGoalie.NO_SHOT:
				per.append("none")
				continue
			shots += 1
			var off: float = rec["body"].z - GOAL_Z
			off_sum += off
			var scored: bool = rec["outcome"] == BotGoalie.GOAL or rec["rebound_goal"]
			goals += 1 if scored else 0
			per.append("%.1f %s" % [off, "G" if scored else "s"])
		lines.append("%-6s | %5d | %5d | %25.2f | %s" % [tier[0], shots, goals,
				off_sum / maxi(shots, 1), "  ".join(per)])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)

extends GutTest

# ── Do the bots' breakaways go in? (#943, #946) ───────────────────────────────
# A real bot carrier alone on a breakaway against the real keeper
# (bot_vs_goalie_harness: the bot picks the shot, the keeper tries to stop it,
# rebounds played out), from three lanes at the red line at a breakaway's pace
# and two at the blue line slower, per tier: how many shots, how many in, and
# where they were released. The measure a release-distance proxy stands for.
# Each start is run over SEEDS carrier peer ids, which seed the hands' draws:
# one id releases every shot at the same point of the tier's hold.

const BotGoalie := preload("res://tests/unit/ai/bot_vs_goalie_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const SEEDS: int = 12
# Release bands (body off the goal line, m) for the priced-against-scored table.
const BANDS_M: Array[float] = [1.5, 2.5, 3.5, 4.5, 6.0, 99.0]

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
	var lines: PackedStringArray = ["tier   | shots/runs | goals | mean body off the line at release | per start (goals/shots)"]
	for tier: Array in [["hard", BotSkillProfile.hard()], ["normal", BotSkillProfile.normal()],
			["easy", BotSkillProfile.easy()]]:
		var shots: int = 0
		var goals: int = 0
		var off_sum: float = 0.0
		var per: PackedStringArray = []
		var runs: int = 0
		var band_n: Array[int] = []
		var band_priced: Array[float] = []
		var band_goals: Array[int] = []
		band_n.resize(BANDS_M.size())
		band_priced.resize(BANDS_M.size())
		band_goals.resize(BANDS_M.size())
		for st: Array in _starts():
			var start_goals: int = 0
			var start_shots: int = 0
			for seed_id: int in range(1, SEEDS + 1):
				_bg.carrier_peer = seed_id
				var rec: Dictionary = _bg.run_rush(st[0], st[1], tier[1], 4.0, true)
				runs += 1
				if rec["outcome"] == BotGoalie.NO_SHOT:
					continue
				shots += 1
				start_shots += 1
				var off: float = rec["body"].z - GOAL_Z
				off_sum += off
				var b: int = 0
				while off >= BANDS_M[b] and b < BANDS_M.size() - 1:
					b += 1
				band_n[b] += 1
				band_priced[b] += maxf(rec["priced"], 0.0)
				if rec["outcome"] == BotGoalie.GOAL or rec["rebound_goal"]:
					goals += 1
					start_goals += 1
					band_goals[b] += 1
			per.append("%d/%d" % [start_goals, start_shots])
		lines.append("%-6s | %2d/%3d | %5d | %25.2f | %s" % [tier[0], shots, runs, goals,
				off_sum / maxi(shots, 1), "  ".join(per)])
		var bands: PackedStringArray = []
		var lo: float = 0.0
		for b: int in BANDS_M.size():
			if band_n[b] > 0:
				bands.append("%.1f-%.1f m: %d shots, priced %.2f, scored %.2f" % [lo, BANDS_M[b],
						band_n[b], band_priced[b] / band_n[b], float(band_goals[b]) / band_n[b]])
			lo = BANDS_M[b]
		lines.append("         " + " | ".join(bands))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)

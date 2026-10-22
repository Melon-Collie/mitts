extends GutTest

# ── THE FIVE-HOLE IN CLOSE, BY RANGE ─────────────────────────────────────────
# `test_goalie_five_hole_window` walks the middle of the net from the dot line
# only. This walks it (+/-0.30 m, 2 cm steps, 70 mph cold) from every range a
# slot shot is taken from, against a keeper settled on a parked shooter and one
# driving in and releasing off the drive, and prints the stance and his
# distance at the release. The silhouette draws the five-hole as the puck sees
# it straight on: `.` where a puck's centre passes, `#` where it meets him.
#
# ── WHAT IT MEASURED (2026-10, the 3 in puck) ────────────────────────────────
# LOW-loft goals of 31 aims, perpendicular range from the goal line:
#
#                       2.5   3.5   4.5   6.1 m
#   READY     settled     0     0    21    17
#             drive-in    0    20    17     5
#   LOW_READY settled     0     0     3     3
#             drive-in    0     3     1     0
#
# FLAT scores 0 everywhere in both (the blade). READY's five-hole is a slot 18-28
# cm wide for the puck's centre from 0.16 to 0.54 m; the low ready's is a slit
# 6-10 cm wide from 0.16 to ~0.40. READY's 0 settled at 3.5 m is not coverage:
# that slot is open there too, and the lifted puck clips the blade's top edge
# 0.6 m out by ~4 mm.
# He is low out to 6.1 m from the goalie (7.5 m out) and in READY at 9 m.
#
const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const MPH_TO_MS: float = 0.44704
const SHOT_MPH: float = 70.0
const SETTLE_TICKS: int = 90
const STEP_M: float = 0.02
const SPAN_M: float = 0.30
const RANGES_M: Array[float] = [2.5, 3.5, 4.5, 6.1, 7.5, 9.0]
const DRIVE_START_M: float = 12.0
const DRIVE_MPS: float = 8.0

var _goalie: Node = null
var _puck: Node = null
var _shooter: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
static var _part_names: Array = GoalieSaveRules.SavePart.keys()
static var _state_names: Array = GoalieStateMachine.State.keys()


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_shooter)
	add_child_autofree(_ctrl)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _shooter)


func _walk(range_m: float, loft: int, driving: bool) -> String:
	var row: String = ""
	var goals: int = 0
	var states: Dictionary = {}
	var a: float = -SPAN_M
	while a <= SPAN_M + 0.0001:
		var aim := Vector3(a, 0.0, GOAL_Z)
		_ctrl.reset_to_crease()
		var spot: Vector3
		if driving:
			_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + DRIVE_START_M))
			spot = _h.drive_in(0.0, DRIVE_START_M, range_m, DRIVE_MPS)
		else:
			spot = Vector3(0.0, 0.0, GOAL_Z + range_m)
			_h.settle(spot, SETTLE_TICKS)
		var at_release: String = "%s@%.1fm" % [_state_names[_ctrl._sm.current],
				Vector2(spot.x - _goalie.global_position.x, spot.z - _goalie.global_position.z).length()]
		states[at_release] = int(states.get(at_release, 0)) + 1
		var o: int = _h.fire_at(spot, aim, loft, SHOT_MPH * MPH_TO_MS, 0.0)
		if o == Harness.GOAL:
			row += "G"
			goals += 1
		elif o == Harness.SAVE:
			row += _part_names[_h.last_part].substr(0, 1).to_lower() \
					if _h.last_part >= 0 else "?"
		else:
			row += "x"
		a += STEP_M
	return "|%s| %2d goals  release-state %s" % [row, goals, str(states)]


const CELL_M: float = 0.02


# The five-hole as the puck sees it from straight on, after he settles on a
# parked carrier `range_m` out: one row per height, `.` where a puck's centre
# passes clean, `#` where it touches him.
func _silhouette(range_m: float) -> void:
	_ctrl.reset_to_crease()
	_h.settle(Vector3(0.0, 0.0, GOAL_Z + range_m), SETTLE_TICKS)
	gut.p("  silhouette from %.1f m, state %s (x -0.40 .. +0.40, goalie-local, +x blocker)"
			% [range_m, _state_names[_ctrl._sm.current]])
	var y: float = 0.70
	while y >= 0.0:
		var row: String = ""
		var x: float = -0.40
		while x <= 0.40 + 0.0001:
			row += "#" if _h.puck_meets_him_at(x, y) else "."
			x += CELL_M
		gut.p("    y %.2f |%s|" % [y, row])
		y -= CELL_M


func test_report_the_silhouette() -> void:
	_silhouette(12.0)
	_silhouette(4.5)


func test_report_the_five_hole_by_range() -> void:
	gut.p("%.0f mph, %d cm aim steps across +/-%.2f m of centre (world +x = glove)."
			% [SHOT_MPH, int(STEP_M * 100.0), SPAN_M])
	for driving: bool in [false, true]:
		gut.p("── %s" % ("DRIVE-IN at %.0f m/s from %.0f m, cold release" % [DRIVE_MPS, DRIVE_START_M]
				if driving else "SETTLED on a parked shooter, cold release"))
		for r: float in RANGES_M:
			for loft: int in [ShotMechanics.ELEVATION_FLAT, ShotMechanics.ELEVATION_LOW]:
				gut.p("  %.1f m %-4s %s" % [r, "FLAT" if loft == ShotMechanics.ELEVATION_FLAT
						else "LOW", _walk(r, loft, driving)])
	assert_true(true, "report")

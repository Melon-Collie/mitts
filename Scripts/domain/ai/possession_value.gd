class_name AIPossessionValue
extends RefCounted

# What the puck at a spot is worth to the side attacking `goal`, in the shot
# field's unit — the odds of the first shot that side gets to from it, against
# the defence as it stands:
#
#   in the zone   the better of the shot from here and one straight drive in
#   outside it    the best zone entry × the skate there × the race to it
#
# A drive is worth the shot where it ends × the odds of keeping the puck that
# far × the delay discount of the skate. An entry is worth the better of its
# shot and the drive in from it, × the skate there × the race to it: the side's
# man from the spot against the defence's first arrival (AIActionScoring
# .arrival_race, its band widened by the arrival clock's error). Entry worths
# depend only on the defence, so fill() prices them once per read of the ice.
#
# Every shot is against a keeper who tracked the play: set and square
# (AIShotValue.set_keeper). Not modelled: passes — one man carries — and where
# the defence will be by the time he gets anywhere.

# Where a side enters: a stride past the line, in the middle and in each wall lane.
const ENTRY_LEAD_M: float = 3.0
const ENTRY_WALL_INSET_M: float = 2.0
# A drive in: straight at the net, at most this far, stopping this far out.
const DRIVE_MAX_M: float = 12.0
const DRIVE_MIN_NET_DIST_M: float = 3.0

var _goal: Vector3 = Vector3.ZERO
var _defenders: Array[Vector3] = []
var _defender_vels: Array[Vector3] = []
var _defender_caps: Array = []
var _entry_spots: Array[Vector3] = []
var _entry_worth: Array[float] = []
var _projected: Array[Vector3] = []


# Reads the ice for the side attacking `goal` against `defenders` (velocities and
# caps index-matched) and prices its entries, unless `in_zone_only`: then only
# spots in the zone may be read. The arrays are read, not copied: refill them in
# place and call fill() again when the ice changes.
func fill(goal: Vector3, defenders: Array[Vector3], defender_vels: Array[Vector3],
		defender_caps: Array, in_zone_only: bool = false) -> void:
	_goal = goal
	_defenders = defenders
	_defender_vels = defender_vels
	_defender_caps = defender_caps
	_entry_spots.clear()
	_entry_worth.clear()
	if in_zone_only:
		return
	var z: float = signf(goal.z) * (GameRules.BLUE_LINE_Z + ENTRY_LEAD_M)
	var wide_x: float = GameRules.RINK_HALF_WIDTH - ENTRY_WALL_INSET_M
	for x: float in [-wide_x, 0.0, wide_x]:
		var spot := Vector3(x, 0.0, z)
		_entry_spots.append(spot)
		_entry_worth.append(maxf(_shot(spot), _drive(spot, 0.0)))


# The puck at `pos` for the side fill() priced, its man there `start_s` from now.
func at(pos: Vector3, start_s: float = 0.0) -> float:
	if AIActionScoring.in_offensive_zone(pos, _goal):
		return maxf(_shot(pos) * AIActionScoring.delay_discount(start_s),
				_drive(pos, start_s))
	var best: float = 0.0
	for i: int in _entry_spots.size():
		var t: float = start_s + AIArrival.time_to_arrive(pos, _entry_spots[i], Vector3.ZERO)
		var timed: float = _entry_worth[i] * AIActionScoring.delay_discount(t)
		if timed <= best:
			continue
		best = maxf(best, timed * AIActionScoring.arrival_race(_entry_spots[i], t,
				_defenders, _defender_vels, true))
	return best


func _shot(pos: Vector3) -> float:
	return AIActionScoring.score_shoot_value(pos, _goal, Vector3.INF, _defenders, 0.0,
			AIShotOdds.Stance.UPRIGHT, AIBotMechanics.WRISTER_SHOT_SPEED_M_S, _defender_caps)


# One straight drive at the net from `from`, the man there `start_s` from now:
# credited as far as the path stays clear and at the odds it is kept that far
# (AICarrySpace's reachable sets, a man he out-skates beaten — as the carrier's
# own drive-in is), against the defence carried on to when he sets off.
func _drive(from: Vector3, start_s: float) -> float:
	var to_net := Vector3(_goal.x - from.x, 0.0, _goal.z - from.z)
	var d: float = to_net.length()
	if d <= DRIVE_MIN_NET_DIST_M + 0.1:
		return 0.0
	var target: Vector3 = from + to_net * (minf(DRIVE_MAX_M, d - DRIVE_MIN_NET_DIST_M) / d)
	if AINetObstacle.carry_path_blocked_by_net(from, target):
		return 0.0
	var defence: Array[Vector3] = _defenders
	if start_s > 0.0:
		_projected.clear()
		for i: int in _defenders.size():
			_projected.append(AITrajectory.predict_at(_defenders[i], _defender_vels[i], start_s))
		defence = _projected
	var t: float = AIArrival.time_to_arrive(from, target, Vector3.ZERO)
	var keep: float = AICarrySpace.carry_safety(from, target, t, defence, _defender_vels,
			_defender_caps, true)
	if keep <= 0.0:
		return 0.0
	var reached: Vector3 = target
	if keep < 1.0:
		reached = AICarrySpace.carry_strip_point(from, target, t, defence,
				_defender_vels, _defender_caps, true, true)
		if reached != target:
			t = AIArrival.time_to_arrive(from, reached, Vector3.ZERO)
	return _shot(reached) * keep * AIActionScoring.delay_discount(start_s + t)

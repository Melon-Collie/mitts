extends "res://tests/unit/ai/real_goalie_shot_harness.gd"

# real_goalie_shot_harness's rebound-tracking shot, fired from the release path
# (the keeper read the wind-up hold_windup_at published, and the release runs his
# _on_puck_released, as in a match), with the rebound sampled as it plays out:
# every SAMPLE_TICKS from the first contact, the puck's position and velocity
# and the keeper as replicated. And the second chance it leaves, measured: at
# the contest sample (the first within CONTEST_HORIZON_S where the puck is on
# the ice, playable and in front of the goal line) and LATE_SAMPLES after it,
# the keeper is captured as he then is, and second_shots fires from the puck
# there at him, restored before each (a puck at rest stays put: a clear he
# would make of it is not played). The rebound field
# (test_generate_rebound_field) reads it. A subclass, so the base, which the
# shot field's fingerprint hashes, is untouched. No class_name (test infra).

const Cloner := preload("res://tests/instruments/keeper/keeper_state_cloner.gd")

const SAMPLE_TICKS: int = 22   # ~0.25 s at the 90 Hz tick
const CONTEST_HORIZON_S: float = 1.5
const LATE_SAMPLES: int = 2

var sample_pos: PackedVector3Array = PackedVector3Array()
var sample_vel: PackedVector3Array = PackedVector3Array()
var sample_keeper: Array[GoalieNetworkState] = []
# The contest sample (-1: none), and the samples the keeper was captured at
# (the contest, then LATE_SAMPLES on), with the puck there.
var contest_k: int = -1
var capture_k: Array[int] = []
var capture_pos: Array[Vector3] = []
var _captured: Array[Dictionary] = []
var _cloner: RefCounted = Cloner.new()
var _sampling: bool = false
var _since_contact: int = 0


func fire_release_tracking_rebound(shooter: Vector3, aim: Vector3, loft_level: int,
		speed_m_s: float) -> int:
	var vel: Vector3 = shot_velocity_at(shooter, aim, loft_level, speed_m_s, 0.0)
	if vel == Vector3.ZERO:
		return WIDE
	sample_pos.clear()
	sample_vel.clear()
	sample_keeper.clear()
	contest_k = -1
	capture_k.clear()
	capture_pos.clear()
	_captured.clear()
	_since_contact = 0
	_shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	var at: Vector3 = shooter
	at.y = _puck.ice_height
	_puck.global_position = at
	_puck.apply_release_velocity(vel)
	_puck.puck_released.emit()
	_sampling = true
	var outcome: int = fire_tracking_rebound(shooter, aim, loft_level, speed_m_s, 0.0)
	_sampling = false
	if last_part == -1 or rebound_goal or rebound_caught or rebound_held \
			or not rebound_pos.is_finite():
		return outcome
	# At rest before the samples ran out (dead at his feet on the contact tick,
	# or settled in front of him): it stays there, and he plays on against it.
	if sample_pos.is_empty():
		_record(rebound_pos, Vector3.ZERO)
	while contest_k >= 0 and capture_k.size() < 2 \
			and sample_pos.size() <= contest_k + LATE_SAMPLES:
		for _i: int in SAMPLE_TICKS:
			_puck.global_position = rebound_pos
			_puck.linear_velocity = Vector3.ZERO
			super._tick_goalie()
			if _puck.motion_pinned:
				return outcome   # he covered it: no chance after the contest
		_record(rebound_pos, Vector3.ZERO)
	return outcome


# How many of a second shot from the `c`-th capture, at each of `aims` (net-plane
# x) and `lofts`, score; the keeper restored to the capture before every one.
func second_shots(c: int, aims: Array[float], lofts: Array[int], speed_m_s: float) -> int:
	var goals: int = 0
	for loft: int in lofts:
		for a: float in aims:
			_cloner.restore(_captured[c], _ctrl as KeeperController)
			_begin_play()
			if fire_at(capture_pos[c], Vector3(a, 0.0, _goal_z), loft, speed_m_s, 0.0) == GOAL:
				goals += 1
	return goals


# The base loop places the puck (position and velocity) before each goalie
# tick, and `last_part` is set from the first contact on.
func _tick_goalie() -> void:
	if _sampling and last_part != -1:
		if _since_contact % SAMPLE_TICKS == 0:
			_record(_puck.global_position, _puck.linear_velocity)
		_since_contact += 1
	super._tick_goalie()


func _record(pos: Vector3, vel: Vector3) -> void:
	var gs := GoalieNetworkState.new()
	_ctrl.fill_state(gs)
	sample_pos.append(pos)
	sample_vel.append(vel)
	sample_keeper.append(gs)
	var k: int = sample_pos.size() - 1
	var out: float = (pos.z - _goal_z) * -signf(_goal_z)
	if contest_k < 0 and k * SAMPLE_TICKS * DT <= CONTEST_HORIZON_S and pos.y <= ON_ICE_M \
			and Vector2(vel.x, vel.z).length() <= PLAYABLE_SPEED_M_S and out > 0.0:
		contest_k = k
		_capture(k, pos)
	elif contest_k >= 0 and k == contest_k + LATE_SAMPLES:
		_capture(k, pos)


func _capture(k: int, pos: Vector3) -> void:
	capture_k.append(k)
	capture_pos.append(Vector3(pos.x, 0.0, pos.z))
	_captured.append(_cloner.capture(_ctrl as KeeperController))

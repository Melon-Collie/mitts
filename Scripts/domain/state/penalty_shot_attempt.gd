class_name PenaltyShotAttempt
extends RefCounted

# One penalty shot from the whistle to its result: the running numbers
# PenaltyShotRules.classify reads, stepped once a tick by whoever is running
# the shot (the drill, or a match's penalty shot).
#
# Nothing is judged until the shooter has the puck. From there the keep-driving
# rules measure his progress from where he picked it up, and retire for good
# once it leaves his blade.

var cfg := PenaltyShotRules.Config.new()
# Longest a shot may stay unresolved once the shooter has the puck: a puck
# wedged somewhere must not hang the game.
var max_live_s: float = 20.0
# How long the shooter has to collect the puck; INF waits for him.
var max_wait_s: float = INF
# Whether a shot is over once the puck is off the blade and no longer going at
# the net (PenaltyShotRules.shot_is_dead): a save, a post, a puck lost wide.
var ends_when_shot_dies: bool = false

var _attack_dir_z: float = -1.0
var _goal_line_z: float = 0.0
var _half_width: float = 0.0
var _start_z: float = 0.0
var _last_progress: float = 0.0
var _max_progress: float = 0.0
var _started: bool = false
var _stall_time: float = 0.0
var _rush_time: float = 0.0
var _live_time: float = 0.0
var _wait_time: float = 0.0
var _has_possessed: bool = false
var _released: bool = false
var _released_time: float = 0.0


# `attack_dir_z` is the shooter's direction along Z, `goal_line_z` the line he
# shoots at and `half_width` the net's.
func begin(attack_dir_z: float, goal_line_z: float, half_width: float) -> void:
	_attack_dir_z = attack_dir_z
	_goal_line_z = goal_line_z
	_half_width = half_width
	_start_z = 0.0
	_last_progress = 0.0
	_max_progress = 0.0
	_started = false
	_stall_time = 0.0
	_rush_time = 0.0
	_live_time = 0.0
	_wait_time = 0.0
	_has_possessed = false
	_released = false
	_released_time = 0.0


func step(delta: float, shooter_z: float, shooter_has_puck: bool,
		puck_pos: Vector3, puck_vel_z: float) -> PenaltyShotRules.Outcome:
	if not _has_possessed:
		if not shooter_has_puck:
			_wait_time += delta
			return PenaltyShotRules.Outcome.MISS if _wait_time >= max_wait_s \
					else PenaltyShotRules.Outcome.LIVE
		# The rush is measured from the pickup, not from where he was stood.
		_has_possessed = true
		_start_z = shooter_z
		return PenaltyShotRules.Outcome.LIVE

	_live_time += delta
	if not shooter_has_puck:
		_released = true

	var progress: float = 0.0
	var forward_speed: float = 0.0
	if not _released:
		progress = PenaltyShotRules.forward_progress(shooter_z, _start_z, _attack_dir_z)
		forward_speed = (progress - _last_progress) / delta if delta > 0.0 else 0.0
		_last_progress = progress
		_max_progress = maxf(_max_progress, progress)
		if not _started and progress >= cfg.start_progress:
			_started = true
		if _started:
			_rush_time += delta
			# No stall time is banked inside the running-start grace, or a slow
			# start would end the shot the instant the grace lifts.
			if _rush_time < cfg.start_grace:
				_stall_time = 0.0
			elif forward_speed <= cfg.rest_speed:
				_stall_time += delta
			else:
				_stall_time = 0.0

	var outcome: PenaltyShotRules.Outcome = PenaltyShotRules.classify(
			puck_pos.x, puck_pos.y, puck_pos.z, forward_speed, progress, _max_progress,
			_started, _released, _stall_time, _rush_time,
			_attack_dir_z, _goal_line_z, _half_width, cfg)
	if outcome != PenaltyShotRules.Outcome.LIVE:
		return outcome
	if _released and ends_when_shot_dies:
		_released_time += delta
		if PenaltyShotRules.shot_is_dead(puck_vel_z, _attack_dir_z, _released_time):
			return PenaltyShotRules.Outcome.MISS
	if _live_time >= max_live_s:
		return PenaltyShotRules.Outcome.MISS
	return PenaltyShotRules.Outcome.LIVE

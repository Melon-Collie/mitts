extends "res://tests/unit/ai/real_goalie_shot_harness.gd"

# real_goalie_shot_harness's rebound-tracking shot, fired from the release path
# (the keeper read the wind-up hold_windup_at published, and the release runs his
# _on_puck_released, as in a match), with the rebound sampled as it plays out:
# every SAMPLE_TICKS from the first contact, the puck's position and velocity
# and the keeper as replicated. The rebound field (test_generate_rebound_field)
# reads it. A subclass, so the base, which the shot field's fingerprint hashes,
# is untouched. No class_name (test infra).

const SAMPLE_TICKS: int = 22   # ~0.25 s at the 90 Hz tick

var sample_pos: PackedVector3Array = PackedVector3Array()
var sample_vel: PackedVector3Array = PackedVector3Array()
var sample_keeper: Array[GoalieNetworkState] = []
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
	return outcome


# The base loop places the puck (position and velocity) before each goalie
# tick, and `last_part` is set from the first contact on.
func _tick_goalie() -> void:
	if _sampling and last_part != -1:
		if _since_contact % SAMPLE_TICKS == 0:
			var gs := GoalieNetworkState.new()
			_ctrl.fill_state(gs)
			sample_pos.append(_puck.global_position)
			sample_vel.append(_puck.linear_velocity)
			sample_keeper.append(gs)
		_since_contact += 1
	super._tick_goalie()

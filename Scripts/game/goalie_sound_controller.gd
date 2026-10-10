class_name GoalieSoundController
extends Node

# Pad sounds read off the goalie's stance as this peer renders it. The host's AI,
# a client's interpolated broadcast and a replay all set that same stance, so one
# read voices every peer with nothing extra on the wire.

# A single pad landing carries half the energy of two.
const _ONE_PAD_DB: float = -3.0

var _controller: GoalieController = null
var _goalie: Goalie = null
var _last_stance: int = -1


func setup(controller: GoalieController, goalie: Goalie) -> void:
	_controller = controller
	_goalie = goalie


# Render rate: audio only, and a stance held for a tick is still there next frame.
func _process(_delta: float) -> void:
	if _controller == null:
		return
	var stance: int = _controller.stance()
	if stance == _last_stance:
		return
	if _last_stance != -1:
		_voice_change(_last_stance as GoalieStateMachine.State, stance as GoalieStateMachine.State)
	_last_stance = stance


func _voice_change(from: GoalieStateMachine.State, to: GoalieStateMachine.State) -> void:
	var landed: int = GoalieStateMachine.pads_on_ice(to) - GoalieStateMachine.pads_on_ice(from)
	if landed > 0:
		SoundManager.play_world(SoundManager.Sound.GOALIE_PAD_DROP, _goalie.global_position,
				0.0 if landed >= 2 else _ONE_PAD_DB, 0.06)
	if to == GoalieStateMachine.State.SLIDING:
		SoundManager.play_world(SoundManager.Sound.GOALIE_PAD_SLIDE, _goalie.global_position, 0.0, 0.05)

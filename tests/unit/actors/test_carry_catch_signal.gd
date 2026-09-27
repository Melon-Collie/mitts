extends GutTest

# The stickhandling tap listens for carry_catch_landed, which fires where a
# stroke's transit hop lands on the puck's far face — and only while carrying.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const DT: float = 1.0 / 120.0

var _skater: Skater = null


func before_each() -> void:
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	watch_signals(_skater)


func test_a_landing_hop_fires_the_catch_while_carrying() -> void:
	_skater.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_skater._update_carry_contact(DT)  # seeds the carry side
	_skater._transit_hop = DT * 0.5 / _skater.carry_transit_hop_time
	_skater._update_carry_contact(DT)
	assert_signal_emit_count(_skater, "carry_catch_landed", 1)


func test_no_catch_once_the_puck_is_gone() -> void:
	_skater.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	_skater._transit_hop = DT * 0.5 / _skater.carry_transit_hop_time
	_skater._update_carry_contact(DT)
	assert_signal_not_emitted(_skater, "carry_catch_landed")


func test_a_hop_still_in_the_air_does_not_fire() -> void:
	_skater.current_shot_state = SkaterStateMachine.State.SKATING_WITH_PUCK
	_skater._update_carry_contact(DT)
	_skater._transit_hop = 1.0
	_skater._update_carry_contact(DT)
	assert_signal_not_emitted(_skater, "carry_catch_landed")

extends GutTest

# The pass's pace feeds a caught one-timer (docs/slapshot-realism-plan.md,
# Phase 5): struck on the beat, a feed at the swing adds pace and one across the
# line pulls the shot; held on the blade it fades to a slapshot off a still puck.
# Driven through the real controller, the feed handed in as the grant does.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const State = SkaterStateMachine.State
const DT: float = 1.0 / 120.0
const AHEAD := Vector3(0.0, 0.0, -12.0)
const FEED_SPEED: float = 15.0
# Past the one-timer's minimum, and short enough that a fed swing stays under
# the puck's cap.
const WIND_UP_TICKS: int = 24


# The host simulating a remote carrier: its window opens `GRACE_TICKS` early.
class HostCopy extends SkaterController:
	func one_timer_window_lag_grace() -> float:
		return GRACE_TICKS * DT


const GRACE_TICKS: int = 6


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


var _skater: Skater = null
var _controller: SkaterController = null
var _input := InputState.new()
var _fired: Array[Vector3] = []


func before_each() -> void:
	_setup(SkaterController.new())


func _setup(controller: SkaterController) -> void:
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	_skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 10.0)
	_skater.set_process(false)
	_skater.set_physics_process(false)
	var state := StubGameState.new()
	add_child_autofree(state)
	_controller = controller
	add_child_autofree(_controller)
	_controller.setup(_skater, puck, state)
	_controller.set_process(false)
	_controller.set_physics_process(false)
	_fired.clear()
	_controller.puck_release_requested.connect(
			func(direction: Vector3, power: float, _slapper: bool) -> void:
				_fired.append(direction * power))


func _tick(slap: bool, press: bool = false) -> void:
	_input.delta = DT
	_input.host_timestamp += DT
	_input.move_vector = Vector2.ZERO
	_input.mouse_world_pos = _skater.global_position + AHEAD
	_input.mouse_world_pos.y = 0.0
	_input.slap_held = slap
	_input.slap_pressed = press
	_controller._process_input(_input, DT)
	_skater._physics_process(DT)


# A puckless wind-up, the feed caught WIND_UP_TICKS in, the swing let go
# `held_ticks` after the catch. `feed_local` is the feed in the shot line's
# frame: x across it toward the skater's right of the line, y along it.
# Returns the shot.
func _one_timer(feed_local: Vector2, held_ticks: int, wind_up_ticks: int = WIND_UP_TICKS) -> Vector3:
	_tick(true, true)
	assert_eq(_skater.current_shot_state, State.SLAPPER_CHARGE_WITHOUT_PUCK)
	for i: int in wind_up_ticks:
		_tick(true)
	var line: Vector2 = _controller._sm.locked_slapper_dir
	var across := Vector2(-line.y, line.x)
	_controller.puck.set_carrier(_skater)
	_controller.on_puck_picked_up_network(0, line * feed_local.y + across * feed_local.x)
	assert_gt(_controller._aiming.one_timer_window_timer, 0.0, "a one-timer's window")
	for i: int in held_ticks:
		_tick(true)
	var t: int = 0
	while _fired.is_empty() and t < 120:
		_tick(false)
		t += 1
	assert_eq(_fired.size(), 1, "the one-timer fired")
	return _fired[0] if not _fired.is_empty() else Vector3.ZERO


func _horiz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_a_feed_at_the_swing_adds_pace_struck_on_the_beat() -> void:
	var still: Vector3 = _one_timer(Vector2.ZERO, 0)
	before_each()
	var fed: Vector3 = _one_timer(Vector2(0.0, -FEED_SPEED), 0)
	assert_gt(fed.length(), still.length() + 0.15 * FEED_SPEED * 0.9,
			"at least the hardest face's restitution of the feed (%.2f -> %.2f m/s)"
			% [still.length(), fed.length()])


# Held to the middle of the fade (where the swing alone is still under the
# puck's cap), the swing meets about half the feed it met on the beat.
func test_a_feed_held_on_the_blade_fades_to_a_slapshot() -> void:
	var lenient: float = _controller.one_timer_leniency_time
	var held: int = roundi(0.5 * (lenient + _controller.one_timer_window_duration) / DT)
	var still_late: Vector3 = _one_timer(Vector2.ZERO, held)
	before_each()
	var fed_late: Vector3 = _one_timer(Vector2(0.0, -FEED_SPEED), held)
	before_each()
	var still_now: Vector3 = _one_timer(Vector2.ZERO, 0)
	before_each()
	var fed_now: Vector3 = _one_timer(Vector2(0.0, -FEED_SPEED), 0)
	var gain_now: float = fed_now.length() - still_now.length()
	var gain_late: float = fed_late.length() - still_late.length()
	assert_lt(fed_late.length(), _controller.puck.max_speed, "measured under the cap")
	assert_gt(gain_now, 0.0)
	assert_between(gain_late / gain_now, 0.3, 0.7,
			"half-way through the fade, about half the feed (%.2f of %.2f m/s)"
			% [gain_late, gain_now])


func test_a_feed_across_the_line_pulls_the_shot_its_way() -> void:
	var still: Vector3 = _one_timer(Vector2.ZERO, 0)
	before_each()
	var fed: Vector3 = _one_timer(Vector2(FEED_SPEED, 0.0), 0)
	var turn: float = _horiz(still).angle_to(_horiz(fed))
	var line: Vector2 = _controller._sm.locked_slapper_dir
	var across := Vector2(-line.y, line.x)
	assert_gt(_horiz(fed).dot(across), 0.0, "pulled toward the way the pass went")
	assert_gt(rad_to_deg(absf(turn)), 3.0, "by a visible amount (%.1f°)" % rad_to_deg(turn))


# The host grants the catch before its client can see it, and opens that
# carrier's window early by the grace; the client catches later on its own
# clock. Let go on the same input, both strike the same share of the feed.
func test_host_and_client_strike_the_same_caught_feed() -> void:
	var held: int = 20
	var feed := Vector2(4.0, -FEED_SPEED)
	var client: Vector3 = _one_timer(feed, held, WIND_UP_TICKS + GRACE_TICKS)
	_setup(HostCopy.new())
	var host: Vector3 = _one_timer(feed, held + GRACE_TICKS, WIND_UP_TICKS)
	assert_almost_eq(host, client, Vector3.ONE * 0.001,
			"the same shot off the same input (%s vs %s)" % [host, client])

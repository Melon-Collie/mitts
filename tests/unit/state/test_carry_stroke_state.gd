extends GutTest

# CarryStrokeState — when the blade lets a hard stroke go and goes over the puck
# to catch it on the far face, and what it ignores. side is a face-normal sign;
# v_perp is the puck's velocity along +face_normal, so a blade at side +1
# pushes with v_perp < 0.

const FLIP: float = 0.6
const FLIP_DISTANCE: float = 0.04
const RELEASE: float = 1.8
const DROP: float = 0.2
const STOP_S: float = 0.12
const REPUSH: float = 1.2
const SMOOTHING: float = 0.04
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION

var _state: CarryStrokeState


func before_each() -> void:
	_state = CarryStrokeState.new()


# Unfiltered unless `smoothing` is given, so the rules read exact speeds.
func _step(side: int, v_perp: float, smoothing: float = 0.0) -> int:
	return _state.step(side, v_perp, DT, smoothing, FLIP, FLIP_DISTANCE, RELEASE, DROP, STOP_S, REPUSH)


# Steps a lateral velocity profile, applying every flip, and returns each event
# as [tick, event].
func _run(side: int, profile: Array[float], smoothing: float = 0.0) -> Array:
	var events: Array = []
	for i: int in profile.size():
		var event: int = _step(side, profile[i], smoothing)
		if event != CarryStrokeState.Event.NONE:
			events.append([i, event])
			side = -side
	return events


func _held(v: float, ticks: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in ticks:
		out.append(v)
	return out


# A side-to-side sweep's velocity, plus a hand's tremor, sampled as the blade's
# inertia delivers a cursor that moves on alternate ticks: a dip on the ticks
# it holds.
func _sweep(amplitude_m: float, hz: float, seconds: float, tremor_m: float = 0.0,
		tremor_hz: float = 9.0, held_dip: float = 0.0) -> Array[float]:
	var out: Array[float] = []
	for i: int in int(seconds / DT):
		var t: float = i * DT
		var v: float = amplitude_m * TAU * hz * cos(TAU * hz * t) \
				+ tremor_m * TAU * tremor_hz * cos(TAU * tremor_hz * t + 1.3)
		out.append(v * (1.0 - held_dip) if i % 2 == 1 else v * (1.0 + held_dip))
	return out


func test_a_hard_stroke_is_released_once_it_has_lost_its_drop() -> void:
	var profile: Array[float] = []
	for i: int in 10:
		profile.append(-0.3 * float(i + 1))
	for v: float in [-2.9, -2.6, -2.3, -2.0]:
		profile.append(v)
	var events: Array = _run(1, profile)
	assert_eq(events.size(), 1)
	assert_eq(events[0][1], CarryStrokeState.Event.RELEASE)
	assert_eq(profile[events[0][0]], -2.3, "released at the first speed past the drop")
	assert_eq(_state.release_peak, 3.0, "as hard as its peak")
	assert_true(_state.catching, "the far face is now catching")
	assert_eq(_state.last_cause, CarryStrokeState.Cause.RELEASE)
	assert_almost_eq(_state.last_speed, 2.3, 0.0001, "noted at the speed it let go at")


func test_a_pause_in_a_stroke_is_not_its_end() -> void:
	var events: Array = _run(1, [-1.0, -2.0, -3.0, -2.5, -2.5, -2.5, -3.2, -3.5] as Array[float])
	assert_eq(events.size(), 0, "a stroke that only eases off is still being pushed")


func test_a_slow_stroke_holds_its_face_until_it_comes_back() -> void:
	assert_eq(_run(1, _held(-1.2, 60)).size(), 0, "a push under the release speed holds its face")
	var back: Array = _run(1, _held(1.0, 10))
	assert_eq(back.size(), 1, "coming back faster than the flip speed flips")
	assert_eq(back[0][1], CarryStrokeState.Event.FLIP)
	assert_eq(back[0][0], int(ceil(FLIP_DISTANCE / (1.0 * DT))) - 1,
			"once the puck has come the flip distance")
	assert_eq(_state.last_cause, CarryStrokeState.Cause.RETURN, "noted as the puck coming back")
	assert_almost_eq(_state.last_speed, 1.0, 0.0001)
	assert_gte(_state.last_travel_m, FLIP_DISTANCE)


func test_a_quick_twitch_back_does_not_flip() -> void:
	_run(1, _held(-1.2, 30))
	# 1.5 m/s back for 2 cm, then on with the stroke.
	var twitch: Array = _run(1, _held(1.5, int(0.02 / (1.5 * DT))))
	assert_eq(twitch.size(), 0, "a twitch shorter than the flip distance is ignored")
	assert_eq(_run(1, _held(-1.2, 30)).size(), 0)


func test_the_catch_does_not_flip_back_while_the_puck_slows() -> void:
	_release_from_plus_one()
	var events: Array = _run(-1, [-1.8, -1.6, -1.2, -0.8, -0.4, -0.1] as Array[float])
	assert_eq(events.size(), 0, "a slowing puck is a catch")
	assert_true(_state.catching)


func test_the_throw_after_the_catch_is_a_push() -> void:
	_release_from_plus_one()
	_run(-1, [-1.0, -0.3] as Array[float])
	assert_eq(_step(-1, 0.4), CarryStrokeState.Event.NONE)
	assert_false(_state.catching, "the puck turning ends the catch")


func test_speeding_up_toward_the_leading_face_repushes() -> void:
	_release_from_plus_one()
	var profile: Array[float] = [-1.6, -1.2]
	profile.append_array(_held(-2.6, 30))
	var events: Array = _run(-1, profile)
	assert_eq(events.size(), 1, "pushed again the same way")
	assert_eq(events[0][1], CarryStrokeState.Event.FLIP)
	assert_gt(events[0][0], 2, "only once it has come the flip distance past the margin")
	assert_eq(_state.last_cause, CarryStrokeState.Cause.REPUSH, "noted as a second push")


func test_a_wobble_in_a_repush_is_not_one() -> void:
	_release_from_plus_one()
	var events: Array = _run(-1, [-1.6, -1.2, -1.9, -1.3, -1.9, -1.2, -0.9] as Array[float])
	assert_eq(events.size(), 0, "speed under the margin over the slowest is a wobble")


func test_a_dangle_releases_each_sweep_and_lands_at_its_end() -> void:
	# 0.2 m amplitude at 2 Hz: ~2.5 m/s at centre. Strokes peak where the puck
	# crosses centre and stop at the turnaround, a quarter period on.
	var hz: float = 2.0
	var side: int = -1
	var half_period_s: float = 0.5 / hz
	var turnaround: float = half_period_s * 0.5
	var releases: int = 0
	var profile: Array[float] = _sweep(0.2, hz, 2.0)
	for i: int in profile.size():
		var event: int = _step(side, profile[i], SMOOTHING)
		if event == CarryStrokeState.Event.NONE:
			continue
		assert_eq(event, CarryStrokeState.Event.RELEASE, "a clean dangle only releases")
		side = -side
		releases += 1
		var into_sweep: float = fmod(i * DT, half_period_s)
		assert_lt(into_sweep, turnaround, "released before the turnaround")
		assert_almost_eq(into_sweep + _state.stop_in_s, turnaround, turnaround * 0.25,
				"and the far face is there as the puck stops")
		assert_lt(into_sweep + _state.stop_in_s, turnaround + 0.005, "never late")
	assert_between(releases, 7, 8, "one release per stroke")


func test_a_wobbling_hand_changes_face_once_a_stroke() -> void:
	for spec: Array in [[0.35, 2.0], [0.4, 1.0], [0.4, 0.5]]:
		var hz: float = spec[1]
		var seconds: float = 4.0 / hz
		var events: Array = _run(-1, _sweep(spec[0], hz, seconds, 0.015, 9.0, 0.5), SMOOTHING)
		assert_between(events.size(), int(seconds * hz * 2.0) - 1, int(seconds * hz * 2.0),
				"a %.1f Hz sweep with a tremor and a stepping cursor: one face a stroke" % hz)


func test_a_tremor_alone_never_changes_face() -> void:
	var events: Array = _run(1, _sweep(0.0, 1.0, 3.0, 0.015, 9.0, 0.5), SMOOTHING)
	assert_eq(events.size(), 0, "a hand held still")


func test_reset_forgets_the_push() -> void:
	for i: int in 10:
		_step(1, -0.3 * float(i + 1))
	_state.reset()
	assert_false(_state.catching)
	assert_eq(_step(1, -1.5), CarryStrokeState.Event.NONE)
	assert_eq(_step(1, -0.9), CarryStrokeState.Event.NONE,
			"a reset peak is rebuilt, here under the release speed")


func test_a_side_told_from_outside_is_noted_as_told() -> void:
	_state.observe(1, -0.2, DT, 0.0)
	assert_eq(_state.wire_flip(1, 0.0, FLIP, RELEASE), CarryStrokeState.Event.FLIP)
	assert_eq(_state.last_cause, CarryStrokeState.Cause.TOLD)


func _release_from_plus_one() -> void:
	var events: Array = _run(1, [-1.0, -2.0, -3.0, -2.5, -1.9] as Array[float])
	assert_eq(events.size(), 1)
	assert_eq(events[0][1], CarryStrokeState.Event.RELEASE)


# A sweep one way that eases off and pushes on — the hand speeding up and
# slowing through a circle round the body — never comes back at the blade, so
# the blade keeps its face behind it.
func test_an_uneven_sweep_one_way_keeps_its_face() -> void:
	for spec: Array in [[0.5, 1.5, 0.0], [0.4, 1.0, 0.015], [0.3, 2.0, 0.015]]:
		var profile: Array[float] = []
		var hz: float = spec[1]
		for i: int in int(3.0 / DT):
			var t: float = i * DT
			var v: float = -3.85 * (1.0 + spec[0] * sin(TAU * hz * t)) \
					- spec[2] * TAU * 9.0 * cos(TAU * 9.0 * t + 1.3)
			profile.append(v)
		var events: Array = _run(1, profile, SMOOTHING)
		assert_eq(events.size(), 0,
				"speed ±%d%% at %.1f Hz: one push, eased and renewed" % [spec[0] * 100.0, hz])

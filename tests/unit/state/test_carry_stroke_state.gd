extends GutTest

# CarryStrokeState — when the blade lets a hard stroke go and goes over the puck
# to catch it on the far face. side is a face-normal sign; v_perp is the puck's
# velocity along +face_normal, so a blade at side +1 pushes with v_perp < 0.

const FLIP: float = 0.8
const RELEASE: float = 1.8
const HOLD: float = 0.03
const REPUSH: float = 0.6
const DT: float = 1.0 / 120.0

var _state: CarryStrokeState


func before_each() -> void:
	_state = CarryStrokeState.new()


func _step(side: int, v_perp: float) -> int:
	return _state.step(side, v_perp, DT, FLIP, RELEASE, HOLD, REPUSH)


# Steps a sampled lateral velocity profile, applying every flip, and returns the
# tick index of each event as [index, event].
func _run(side: int, profile: Array[float]) -> Array:
	var events: Array = []
	for i: int in profile.size():
		var event: int = _step(side, profile[i])
		if event != CarryStrokeState.Event.NONE:
			events.append([i, event])
			side = -side
	return events


func _sine_dangle(amplitude_m: float, hz: float, seconds: float) -> Array[float]:
	var out: Array[float] = []
	var omega: float = TAU * hz
	for i: int in int(seconds / DT):
		out.append(amplitude_m * omega * cos(omega * i * DT))
	return out


func test_a_hard_stroke_is_released_once_it_stops_gaining_speed() -> void:
	# Pushed off a +1 blade (v_perp < 0) up to 3 m/s, then coasting.
	var released_at: int = -1
	for i: int in 30:
		var v: float = -minf(0.3 * float(i + 1), 3.0)
		if _step(1, v) == CarryStrokeState.Event.RELEASE:
			released_at = i
			break
	assert_gt(released_at, 9, "no release while the puck is still gaining speed")
	assert_lt(released_at, 9 + int(ceil(HOLD / DT)) + 2,
			"released within the hold of the peak")
	assert_true(_state.catching, "the far face is now catching")


func test_a_slow_stroke_holds_its_face_until_it_comes_back() -> void:
	for i: int in 60:
		assert_eq(_step(1, -1.2), CarryStrokeState.Event.NONE,
				"a push under the release speed is held on one face")
	assert_eq(_step(1, 0.5), CarryStrokeState.Event.NONE, "a slow return holds")
	assert_eq(_step(1, 1.0), CarryStrokeState.Event.FLIP,
			"coming back faster than the flip speed flips, as the plain stroke rule does")


func test_the_catch_does_not_flip_back_while_the_puck_slows() -> void:
	_release_from_plus_one()
	# The blade is now at -1: the puck coming at it is v_perp < 0, slowing.
	var events: Array = _run(-1, [-3.0, -2.6, -2.0, -1.4, -0.8, -0.2] as Array[float])
	assert_eq(events.size(), 0, "a slowing puck is a catch")
	assert_true(_state.catching)


func test_the_throw_after_the_catch_is_a_push() -> void:
	_release_from_plus_one()
	_run(-1, [-2.0, -0.5] as Array[float])
	assert_eq(_step(-1, 0.4), CarryStrokeState.Event.NONE)
	assert_false(_state.catching, "the puck turning ends the catch")


func test_speeding_up_toward_the_leading_face_repushes() -> void:
	_release_from_plus_one()
	var events: Array = _run(-1, [-3.0, -2.4, -2.6, -3.1] as Array[float])
	assert_eq(events.size(), 1, "pushed again the same way")
	assert_eq(events[0][1], CarryStrokeState.Event.FLIP)
	assert_eq(events[0][0], 3, "only past the margin over the slowest it came")


func test_a_dangle_releases_mid_sweep_once_per_stroke() -> void:
	# 0.2 m amplitude at 2 Hz: ~2.5 m/s at centre. Strokes peak where the puck
	# crosses centre (v = ±peak at cos = ±1), so the releases land just past
	# each peak, not at the turnarounds.
	var hz: float = 2.0
	var profile: Array[float] = _sine_dangle(0.2, hz, 2.0)
	var events: Array = _run(-1, profile)
	var releases: int = 0
	var half_period_ticks: float = 0.5 / hz / DT
	for e: Array in events:
		assert_eq(e[1], CarryStrokeState.Event.RELEASE, "a clean dangle only releases")
		releases += 1
		var phase: float = fmod(float(e[0]), half_period_ticks) / half_period_ticks
		assert_lt(phase, 0.25, "released in the first quarter after a centre crossing")
	assert_between(releases, 6, 8, "one release per stroke")


func test_reset_forgets_the_push() -> void:
	for i: int in 10:
		_step(1, -0.3 * float(i + 1))
	_state.reset()
	assert_false(_state.catching)
	for i: int in 3:
		assert_eq(_step(1, -2.5), CarryStrokeState.Event.NONE,
				"a reset peak is rebuilt before it can be spent")


func _release_from_plus_one() -> void:
	var events: Array = _run(1, [-1.0, -2.0, -3.0, -3.0, -3.0, -3.0, -3.0] as Array[float])
	assert_eq(events.size(), 1)
	assert_eq(events[0][1], CarryStrokeState.Event.RELEASE)

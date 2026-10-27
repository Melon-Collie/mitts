extends GutTest

# A hard dangle lets the puck go, and a hand's wobble does not tap the stick: the blade leaves each push mid-sweep, goes
# over the free puck at the top of its hop and lands on the far face standing
# off it, and the catch closes that gap. All of it on the blade mesh — the puck
# stays where the cursor put it. Driven through the real controller and render
# pass, since the release reads the pin the IK places.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


class Sample:
	var side: int
	var factor: float
	var transit: float
	var mesh_standoff: float
	var marker_standoff: float
	var release_hop: bool


func _make_carrier() -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(PlayerAttributes.neutral())
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	puck.set_carrier(skater)
	c.on_puck_picked_up_network()
	return c


# The cursor swept side to side in front of the skater, `half_width_m` either
# side of centre at `hz`, after a settle at centre — with a hand's 9 Hz tremor of
# `tremor_m` on top, read every `ticks_per_frame` ticks (2 at 60 fps).
func _dangle(c: SkaterController, half_width_m: float, hz: float, seconds: float,
		tremor_m: float = 0.0, ticks_per_frame: int = 1) -> Array[Sample]:
	var sk: Skater = c.skater
	var input := InputState.new()
	var out: Array[Sample] = []
	var settle: int = 60
	var x: float = 0.0
	for t: int in settle + int(seconds / DT):
		if t % ticks_per_frame == 0 and t >= settle:
			var s: float = (t - settle) * DT
			x = half_width_m * sin(TAU * hz * s) + tremor_m * sin(TAU * 9.0 * s + 1.3)
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = sk.global_position + Vector3(x, 0.0, 1.2)
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)
		if t >= settle:
			out.append(_sample(sk))
	return out


# How far the blade (marker, and the drawn mid-blade) sits off the puck along
# the face normal — the axis the carry offsets the blade along.
func _sample(sk: Skater) -> Sample:
	var s := Sample.new()
	s.side = sk._carry_side
	s.factor = sk.get_carry_forehand_factor()
	s.transit = sk.get_carry_transit_factor()
	s.release_hop = sk._release_hop
	var pin: Vector3 = sk.get_carry_target_global()
	var stick: Vector3 = sk.get_blade_contact_global() - sk.top_hand.global_position
	stick.y = 0.0
	stick = stick.normalized()
	var face_normal := Vector3(-stick.z, 0.0, stick.x)
	var mesh: MeshInstance3D = sk._blade_mesh_instance
	var mid: Vector3 = mesh.global_transform * Vector3(0.0, 0.0, -sk.blade_length * 0.5)
	s.mesh_standoff = absf((mid - pin).dot(face_normal))
	s.marker_standoff = absf((sk.get_blade_contact_global() - pin).dot(face_normal))
	return s


func test_the_blade_crosses_the_puck_in_the_air() -> void:
	var samples: Array[Sample] = _dangle(_make_carrier(), 0.35, 2.0, 2.0)
	var crossings: int = 0
	var released: int = 0
	var lowest: float = INF
	var first: bool = true
	for i: int in range(1, samples.size()):
		if signf(samples[i].factor) != signf(samples[i - 1].factor):
			if first:
				first = false  # from rest, onto whichever face the pickup left
				continue
			crossings += 1
			released += 1 if samples[i].release_hop else 0
			lowest = minf(lowest, samples[i].transit)
	assert_gt(crossings, 5, "a 2 Hz dangle flips the face every stroke")
	assert_eq(released, crossings, "every flip of a hard dangle is a release")
	assert_gt(lowest, 0.9, "the blade crosses the puck near the top of the hop")


func test_the_blade_stands_off_the_free_puck() -> void:
	var c: SkaterController = _make_carrier()
	var sk: Skater = c.skater
	var samples: Array[Sample] = _dangle(c, 0.35, 2.0, 2.0)
	var widest: float = 0.0
	var off: int = 0
	for s: Sample in samples:
		assert_almost_eq(s.marker_standoff, absf(s.factor) * sk.carry_blade_offset, 0.002,
				"the gap is the mesh's: the marker keeps the carry offset")
		if absf(s.factor) > 0.9:
			widest = maxf(widest, s.mesh_standoff)
		if s.transit > 0.3 or s.mesh_standoff > sk.carry_blade_offset + 0.02:
			off += 1
	assert_gt(widest, sk.carry_blade_offset + 0.5 * sk.carry_free_gap,
			"a released blade lands wide of the puck")
	var share: float = float(off) / float(samples.size())
	gut.p("blade off the puck %.0f%% of a hard dangle" % (share * 100.0))
	assert_gt(share, 0.4, "a hard dangle is mostly a free puck")


func test_a_slow_carry_keeps_the_blade_on_the_puck() -> void:
	var c: SkaterController = _make_carrier()
	var sk: Skater = c.skater
	for s: Sample in _dangle(c, 0.25, 0.4, 2.5):
		assert_false(s.release_hop, "a slow sweep never releases")
		assert_lt(s.mesh_standoff, sk.carry_blade_offset + 0.01,
				"a slow sweep keeps the blade on the puck")


func _face_changes(samples: Array[Sample]) -> int:
	var changes: int = 0
	for i: int in range(1, samples.size()):
		if samples[i].side != samples[i - 1].side:
			changes += 1
	return changes


func test_a_wobbling_hand_changes_face_once_a_stroke() -> void:
	# [half width, Hz, ticks per frame]: hard and slow sweeps, at 240 and 60 fps.
	for spec: Array in [[0.35, 2.0, 1], [0.35, 2.0, 2], [0.4, 1.0, 1], [0.4, 1.0, 2],
			[0.4, 0.5, 2]]:
		var hz: float = spec[1]
		var seconds: float = 4.0 / hz
		var strokes: int = int(seconds * hz * 2.0)
		var changes: int = _face_changes(_dangle(_make_carrier(), spec[0], hz, seconds,
				0.015, spec[2]))
		assert_between(changes, strokes - 1, strokes + 1,
				"%.1f Hz sweep, 1.5 cm tremor, %d ticks a frame: a face a stroke" % [hz, spec[2]])


func test_a_still_hand_never_changes_face() -> void:
	for ticks_per_frame: int in [1, 2]:
		assert_eq(_face_changes(_dangle(_make_carrier(), 0.0, 1.0, 3.0, 0.015, ticks_per_frame)), 0,
				"a 1.5 cm tremor is not a stroke")


func test_a_tight_dangle_still_changes_face() -> void:
	var changes: int = _face_changes(_dangle(_make_carrier(), 0.06, 3.0, 3.0, 0.0, 2))
	assert_gt(changes, 14, "a hand's-width dangle at 3 Hz flips its face nearly every stroke")


# Each face change says why (StickDebugOverlay logs it): a hard dangle's are
# releases, a slow sweep's the puck coming back at the blade.
func test_a_face_change_says_why() -> void:
	var causes: Array[int] = []
	var hard: SkaterController = _make_carrier()
	hard.skater.carry_face_changed.connect(
			func(cause: int, _speed: float, _travel_m: float) -> void: causes.append(cause))
	var hard_samples: Array[Sample] = _dangle(hard, 0.35, 2.0, 2.0)
	var changes: int = _face_changes(hard_samples)
	assert_eq(causes.size(), changes, "one signal a face change")
	assert_gt(causes.count(CarryStrokeState.Cause.RELEASE), causes.size() - 2,
			"a hard dangle's are releases, past the first stroke from rest")
	causes.clear()
	var slow: SkaterController = _make_carrier()
	slow.skater.carry_face_changed.connect(
			func(cause: int, _speed: float, _travel_m: float) -> void: causes.append(cause))
	# ~1.3 m/s across the middle: strokes under the release speed.
	_dangle(slow, 0.35, 0.6, 3.4)
	assert_gt(causes.size(), 2)
	assert_eq(causes.count(CarryStrokeState.Cause.RETURN), causes.size(),
			"a slow sweep's are the puck coming back")


# The cursor swung round the body at a hand's uneven pace (±50% at 1.5 Hz, with
# a 2 cm tremor), either way round: the puck never comes back at the blade, so
# the face holds.
func test_an_uneven_sweep_round_the_body_keeps_its_face() -> void:
	for way: float in [1.0, -1.0]:
		var c: SkaterController = _make_carrier()
		var sk: Skater = c.skater
		var changes: Array[int] = [0]
		sk.carry_face_changed.connect(
				func(_cause: int, _speed: float, _travel_m: float) -> void: changes[0] += 1)
		var input := InputState.new()
		for t: int in 90 + int(3.0 / DT):
			var s: float = maxf(t - 90, 0) * DT
			var ang: float = way * deg_to_rad(200.0) \
					* (s - 0.5 / (TAU * 1.5) * cos(TAU * 1.5 * s))
			input.delta = DT
			input.host_timestamp += DT
			input.mouse_world_pos = sk.global_position + Vector3(sin(ang), 0.0, -cos(ang)) \
					* (1.1 + 0.02 * sin(TAU * 9.0 * s + 1.3))
			input.mouse_world_pos.y = 0.0
			if t == 90:
				changes[0] = 0
			c._process_input(input, DT)
			sk._physics_process(DT)
			sk._process(DT)
		assert_lt(changes[0], 2, "one push round, eased and renewed, %s" % (
				"clockwise" if way > 0.0 else "anticlockwise"))

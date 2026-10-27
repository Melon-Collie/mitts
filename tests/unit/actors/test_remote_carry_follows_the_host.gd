extends GutTest

# A client draws someone else's carry on the host's side. The carrier is the
# real controller; every other tick it is broadcast as the host does (60 Hz,
# blade and hand at the wire's centimetre) and a second skater is drawn from the
# snapshots the way RemoteController draws one: the blade lerped between them
# some ticks behind, the blade side off the wire. It must change face when the
# carrier does — deciding the side itself, off a blade placed with the
# carrier's, it read the difference as strokes and tapped about twice a stroke —
# and pin the puck where the carrier has it.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SNAP_TICKS: int = 2
const DELAY_TICKS: int = 5
const WIRE_M: float = 0.01


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


class Snap:
	var state := SkaterNetworkState.new()
	var pin: Vector3
	var side: int


class Result:
	var owner_changes: int = 0
	var remote_changes: int = 0
	var remote_releases: int = 0
	var disagree_ticks: int = 0
	var pin_errors: Array[float] = []
	var ticks: int = 0


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


func _make_remote() -> Skater:
	var r: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(r)
	r.set_process(false)
	r.set_physics_process(false)
	r.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	return r


static func _wire(v: Vector3) -> Vector3:
	return Vector3(roundf(v.x / WIRE_M), roundf(v.y / WIRE_M), roundf(v.z / WIRE_M)) * WIRE_M


# The carrier sweeps the cursor `half_width_m` either side at `hz` with a hand's
# 9 Hz tremor of `tremor_m`, the cursor read as a `fps` display presents it.
func _broadcast(half_width_m: float, hz: float, tremor_m: float, fps: float,
		seconds: float) -> Result:
	var c: SkaterController = _make_carrier()
	var sk: Skater = c.skater
	var r: Skater = _make_remote()
	var input := InputState.new()
	var settle: int = 60
	var snaps: Array[Snap] = []
	var owner_sides: Array[int] = []
	var frame_t: float = 0.0
	var next_frame: float = 0.0
	var out := Result.new()
	var owner_last: int = 0
	var remote_last: int = 0
	for t: int in settle + int(seconds / DT):
		var now: float = maxf(t - settle, 0) * DT
		while next_frame <= now:
			frame_t = next_frame
			next_frame += 1.0 / fps
		var x: float = 0.0 if t < settle else half_width_m * sin(TAU * hz * frame_t) \
				+ tremor_m * sin(TAU * 9.0 * frame_t + 1.3)
		input.delta = DT
		input.host_timestamp += DT
		input.mouse_world_pos = sk.global_position + Vector3(x, 0.0, 1.2)
		input.mouse_world_pos.y = 0.0
		c._process_input(input, DT)
		sk._physics_process(DT)
		sk._process(DT)
		owner_sides.append(sk._carry_side)
		if t % SNAP_TICKS == 0:
			var snap := Snap.new()
			c.fill_network_state(snap.state)
			snap.state.blade_position = _wire(snap.state.blade_position)
			snap.state.top_hand_position = _wire(snap.state.top_hand_position)
			snap.pin = sk.get_carry_target_raw()
			snaps.append(snap)
		var rt: float = float(t - DELAY_TICKS)
		if rt < 0.0:
			continue
		var a: int = mini(int(rt / SNAP_TICKS), snaps.size() - 1)
		var b: int = mini(a + 1, snaps.size() - 1)
		var f: float = (rt - a * SNAP_TICKS) / SNAP_TICKS
		var from: SkaterNetworkState = snaps[a].state
		var to: SkaterNetworkState = snaps[b].state
		r.set_facing(from.facing)
		r.set_balance_tilt(from.balance_tilt, Vector2.ZERO)
		r.set_upper_body_rotation(lerpf(from.upper_body_rotation_y, to.upper_body_rotation_y, f))
		r.set_top_hand_position(from.top_hand_position.lerp(to.top_hand_position, f))
		r.set_blade_position(from.blade_position.lerp(to.blade_position, f))
		r.current_shot_state = to.shot_state
		r.apply_wire_blade_side(to.blade_side)
		var was_release: bool = r._release_hop
		r._physics_process(DT)
		r._process(DT)
		if t < settle + DELAY_TICKS:
			continue
		out.ticks += 1
		var owner_side: int = owner_sides[int(rt)]
		if owner_last != 0 and owner_side != owner_last:
			out.owner_changes += 1
		if remote_last != 0 and r._carry_side != remote_last:
			out.remote_changes += 1
			if r._release_hop and not was_release:
				out.remote_releases += 1
		if r._carry_side != owner_side:
			out.disagree_ticks += 1
		var pin: Vector3 = snaps[a].pin.lerp(snaps[b].pin, f)
		out.pin_errors.append(Vector2(r.get_carry_target_raw().x - pin.x,
				r.get_carry_target_raw().z - pin.z).length())
		owner_last = owner_side
		remote_last = r._carry_side
	out.pin_errors.sort()
	return out


func test_a_remote_changes_face_with_the_carrier() -> void:
	# [half width, Hz, tremor, fps]: a hard dangle, wobbling sweeps, a tight one.
	for spec: Array in [[0.35, 2.0, 0.0, 240.0], [0.35, 2.0, 0.015, 240.0],
			[0.4, 1.0, 0.015, 240.0], [0.4, 0.5, 0.02, 240.0], [0.4, 1.0, 0.015, 60.0],
			[0.06, 3.0, 0.0, 240.0]]:
		var hz: float = spec[1]
		var r: Result = _broadcast(spec[0], hz, spec[2], spec[3], 4.0 / hz)
		var what: String = "±%.0f cm at %.1f Hz, %.1f cm tremor, %.0f fps" % [
				spec[0] * 100.0, hz, spec[2] * 100.0, spec[3]]
		gut.p("%s: carrier %d changes, remote %d, sides apart %d/%d ticks, pin p50 %.1f max %.1f cm" % [
				what, r.owner_changes, r.remote_changes, r.disagree_ticks, r.ticks,
				r.pin_errors[r.pin_errors.size() / 2] * 100.0, r.pin_errors[-1] * 100.0])
		assert_eq(r.remote_changes, r.owner_changes, "%s: the remote changes face with the carrier" % what)
		# A side change rides the snapshot after the blade it goes with, so the
		# two sit a tick or two apart at each flip, and never between.
		assert_lte(r.disagree_ticks, 2 * r.owner_changes + 2, "%s: and on the same side" % what)
		# The wire's centimetre, outside a flip; through one the remote eases
		# the blade across itself, a tick or so off the carrier — but never by a
		# whole side's offset, which is what deciding the side itself left.
		assert_lt(r.pin_errors[r.pin_errors.size() / 2], 0.015,
				"%s: its puck pinned where the carrier's is" % what)
		var c: SkaterController = _make_carrier()
		assert_lt(r.pin_errors[-1], c.skater.carry_blade_offset * 1.5,
				"%s: and only a flip's worth off through one" % what)


func test_a_remote_sees_a_hard_dangle_release() -> void:
	var r: Result = _broadcast(0.35, 2.0, 0.0, 240.0, 2.0)
	assert_gt(r.remote_releases, r.remote_changes - 2,
			"the release hop, not a plain flip, on all but the first stroke from rest")

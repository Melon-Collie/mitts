class_name ReplayPlaybackEngine
extends RefCounted

# Stateless interpolation core shared by GoalReplayDriver (in-memory ring
# buffer of recent broadcasts) and FileReplayDriver (frames decoded from a
# .mreplay file). Given two decoded snapshots and a t ∈ [0, 1], applies the
# interpolated pose to every actor the caller passes in.
#
# The two drivers differ only in where their snapshot pairs come from and
# what extra side effects they own (host-side sim freeze, virtual clock
# control, file load). The interpolation math is identical, so it lives here.

# Skaters: Hermite position (velocity as tangent), Hermite angle for facing
# and upper_body_rotation, linear lerp for blade/hand (local-space, no
# derivative). Puck: Hermite position with velocity zeroed, since the parked
# puck is posed rather than simulated — except while CARRIED, where
# it rides the carrier's just-applied pose (see _place_carried_puck)
# because independently-interpolated puck and skater paths visibly jitter
# against each other. Goalies: position / rotation
# / five_hole_openness lerp, state_enum is whichever bracket end is closer
# (apply_replay_state sets those then calls _update_body_parts so pad / body
# animations track the recorded pose rather than re-simulating from AI).
# Authoritative pose fields (body lean, pad / glove / blocker / head transforms)
# are also lerped between snapshots so playback reflects the host's actual
# saves, not the client AI's reconstruction.
static func apply_interpolated_snapshot(
		from_snap: Dictionary,
		to_snap: Dictionary,
		t: float,
		dt: float,
		sim_delta: float,
		records: Dictionary,
		puck: Puck,
		goalie_controllers: Array) -> void:
	# `dt` is the bracket span (for Hermite tangent scaling); `sim_delta` is the
	# virtual-clock time advanced this frame — slow-mo-scaled and 0 on a paused
	# scrub. The skater leg gait integrates it; goalies currently ignore it.
	# `records` is peer_id → PlayerRecord. GoalReplayDriver passes
	# PlayerRegistry.all() (the underlying dict); FileReplayDriver builds its
	# own dict from the .mreplay header so the viewer doesn't need to stand
	# up a full registry / state machine just to feed this engine.
	var from_skaters: Dictionary = from_snap.skaters
	var to_skaters: Dictionary = to_snap.skaters
	for peer_id: int in from_skaters:
		if not to_skaters.has(peer_id):
			continue
		var record: PlayerRecord = records.get(peer_id)
		if record == null or record.controller == null:
			continue
		var fs: SkaterNetworkState = from_skaters[peer_id]
		var ts: SkaterNetworkState = to_skaters[peer_id]
		var interp := SkaterNetworkState.new()
		interp.position = BufferedStateInterpolator.hermite(
				fs.position, fs.velocity, ts.position, ts.velocity, t, dt)
		interp.velocity = fs.velocity.lerp(ts.velocity, t)
		var fa: float = BufferedStateInterpolator.hermite_angle(
				atan2(fs.facing.x, fs.facing.y), fs.facing_angular_velocity,
				atan2(ts.facing.x, ts.facing.y), ts.facing_angular_velocity, t, dt)
		interp.facing = Vector2(sin(fa), cos(fa))
		interp.upper_body_rotation_y = BufferedStateInterpolator.hermite_angle(
				fs.upper_body_rotation_y, fs.upper_body_angular_velocity,
				ts.upper_body_rotation_y, ts.upper_body_angular_velocity, t, dt)
		interp.blade_position = fs.blade_position.lerp(ts.blade_position, t)
		interp.top_hand_position = fs.top_hand_position.lerp(ts.top_hand_position, t)
		interp.is_ghost = ts.is_ghost
		# Cosmetic-state carry-through: every replicated field the render side
		# consumes (gait intent, stick flex, blade scoop, stagger stumble,
		# stance) rides along, so playback poses from the
		# RECORDED values instead of fresh-state defaults (file viewer) or
		# whatever live play left on the actors (goal replay). Discrete reads
		# take the newest bracket end, like is_ghost; scalars lerp.
		# test_replay_playback_carries_the_state.gd holds the list against
		# SkaterNetworkState.
		interp.move_intent = ts.move_intent
		interp.brake_intent = ts.brake_intent
		interp.hit_committed = ts.hit_committed
		interp.copy_stick_play_from(ts)
		interp.shot_state = ts.shot_state
		interp.elevation_level = ts.elevation_level
		interp.shot_charge = lerpf(fs.shot_charge, ts.shot_charge, t)
		interp.stance_active = ts.stance_active
		interp.blade_side = ts.blade_side
		interp.recoil_dir = ts.recoil_dir
		interp.stagger_timer = lerpf(fs.stagger_timer, ts.stagger_timer, t)
		interp.knockdown_timer = lerpf(fs.knockdown_timer, ts.knockdown_timer, t)
		# The leans place the UpperBody frame the recorded blade is local to.
		interp.balance_tilt = fs.balance_tilt.lerp(ts.balance_tilt, t)
		interp.balance_tilt_vel = fs.balance_tilt_vel.lerp(ts.balance_tilt_vel, t)
		interp.torso_lean = fs.torso_lean.lerp(ts.torso_lean, t)
		interp.posture_lean = lerpf(fs.posture_lean, ts.posture_lean, t)
		record.controller.apply_replay_state(interp, sim_delta)

	var fp: PuckNetworkState = from_snap.puck
	var tp: PuckNetworkState = to_snap.puck
	if puck != null and fp != null and tp != null:
		if not _place_carried_puck(from_snap, to_snap, t, records, puck):
			puck.set_puck_position(BufferedStateInterpolator.hermite(
					fp.position, fp.velocity, tp.position, tp.velocity, t, dt))
		puck.set_puck_velocity(Vector3.ZERO)

	var from_goalies: Array = from_snap.goalies
	var to_goalies: Array = to_snap.goalies
	for i: int in from_goalies.size():
		if i >= goalie_controllers.size() or i >= to_goalies.size():
			break
		var fg: GoalieNetworkState = from_goalies[i]
		var tg: GoalieNetworkState = to_goalies[i]
		var interp := GoalieNetworkState.new()
		interp.position_x = lerpf(fg.position_x, tg.position_x, t)
		interp.position_z = lerpf(fg.position_z, tg.position_z, t)
		interp.rotation_y = lerp_angle(fg.rotation_y, tg.rotation_y, t)
		interp.five_hole_openness = lerpf(fg.five_hole_openness, tg.five_hole_openness, t)
		interp.state_enum = tg.state_enum if t >= 0.5 else fg.state_enum
		interp.pose.blend(fg.pose, tg.pose, t)
		goalie_controllers[i].apply_replay_state(interp, sim_delta)


# A carried puck rides its carrier's interpolated pose, never its own Hermite
# bracket: the recorded carry velocity is near zero (the puck is posed, not
# simulated), so each bracket eases in and out and the puck jitters against the
# skater it should be stuck to. Runs AFTER the skater loop, so the carrier's
# replay pose is already applied for this frame.
#
# On the blade, it pins to the blade, as a live remote carrier's does
# (PuckController._pin_puck_to_carrier). Held on the ice (slapshot_pinned: a
# wind-up, or the recovery after one is called off, while the blade is up or
# coming down to it) it holds the recorded spot off the carrier instead
# (slapshot_pin_offset), carried along with him, as a live remote's pin does
# (RemoteController._adopt_slapshot_pin); the raised blade is the wrong thing to
# follow.
#
# Returns false (the caller interpolates the recorded positions) when there is
# no carrier, the bracket ends disagree on who carries it (pickup and release
# brackets are discontinuous either way), or the carrier's actor is missing.
static func _place_carried_puck(
		from_snap: Dictionary,
		to_snap: Dictionary,
		t: float,
		records: Dictionary,
		puck: Puck) -> bool:
	var carrier_id: int = int(to_snap.carrier_peer_id)
	if carrier_id == -1 or int(from_snap.carrier_peer_id) != carrier_id:
		return false
	var record: PlayerRecord = records.get(carrier_id)
	if record == null or record.controller == null \
			or record.skater == null or not is_instance_valid(record.skater):
		return false
	var fs: SkaterNetworkState = from_snap.skaters.get(carrier_id)
	var ts: SkaterNetworkState = to_snap.skaters.get(carrier_id)
	if fs == null or ts == null:
		return false
	if fs.slapshot_pinned or ts.slapshot_pinned or _winding_up(record.skater):
		var off: Vector2 = fs.slapshot_pin_offset.lerp(ts.slapshot_pin_offset, t)
		var held := Vector3(record.skater.global_position.x + off.x, puck.ice_height,
				record.skater.global_position.z + off.y)
		puck.set_puck_position(held)
		return true
	var contact: Vector3 = record.skater.get_blade_contact_global()
	contact.y = puck.ice_height
	puck.set_puck_position(contact)
	return true


# A recording made before the pin rode the wire (protocol v91) shows it only
# through the wind-up's states; the one-timer's retention hold keeps the same pin.
static func _winding_up(skater: Skater) -> bool:
	return skater.current_shot_state == SkaterStateMachine.State.SLAPPER_CHARGE_WITH_PUCK \
			or skater.current_shot_state == SkaterStateMachine.State.ONE_TIMER_RETENTION

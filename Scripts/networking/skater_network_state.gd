class_name SkaterNetworkState

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var blade_position: Vector3 = Vector3.ZERO
var top_hand_position: Vector3 = Vector3.ZERO
var upper_body_rotation_y: float = 0.0
var facing: Vector2 = Vector2.ZERO
var facing_angular_velocity: float = 0.0      # rad/s; used for Hermite interpolation on remotes
var upper_body_angular_velocity: float = 0.0  # rad/s
var shot_state: int = 0
var shot_charge: float = 0.0
var last_processed_host_timestamp: float = 0.0
var is_ghost: bool = false
# Loft mode (0 flat / 1 low saucer / 2 high), from the skater's input frame.
# Replicated so AI off-puck bots (e.g., FINISHER) can read teammate loft
# directly instead of inferring from puck physics.
var elevation_level: int = 0
# True when the blade is lifted off the ice (own Q held, or involuntarily
# popped up by an opponent's stick lift). Effective value: the receiver only
# needs the resolved "is the blade up" answer for rendering and the
# on-ice/off-ice interaction gate.
var blade_up: bool = false
# The stick-lift phase (StickCheckRules.Phase) and seconds into it. Remotes pose
# the raised blade from it, the lift resolver checks the claimant was hooking,
# and the local reconcile adopts it before replay.
var stick_check_phase: int = 0
var stick_check_elapsed: float = 0.0
# Skater.stick_tied: host-authoritative, applied every broadcast like is_ghost.
var stick_tied: bool = false
# Board pin (BoardPinTracker): the role (BoardPinRules.Role) and the pinner's
# weight share. Host-authoritative, applied every broadcast like stick_tied, and
# fed to the forward prediction (BoardPinRules.forward_cap) on the render and the
# rewind.
var pin_role: int = 0
var pin_strength: float = 0.0
# Skater.is_diving: a dive's down window rides knockdown_timer and recoil_dir;
# this says it is a dive (its stick still plays, its body blocks low).
var diving: bool = false
# Skater.is_slapshot_pinning: the carried puck holds its spot on the ice instead
# of riding the blade — through a slapshot's wind-up, and through the recovery
# after one is called off, while the blade comes back down to it. A replay
# follows the recorded puck while it is set and pins to the blade otherwise.
var slapshot_pinned: bool = false
# Body-check stagger: seconds of thrust/grip-penalty recovery remaining on the
# victim. Replicated so the local player's reconcile can snap it to the host
# baseline before replay — same treatment as velocity — and it decays
# deterministically forward
# (see BodyCheckRules / SkaterController._apply_movement). Host-authoritative: only
# the host sets it on a hit; clients receive the resolved value off the wire.
var stagger_timer: float = 0.0
# Body-check knockdown: seconds of full movement lockout remaining. Replicated for
# the same reason as stagger_timer — the local victim's reconcile snaps it to the
# host baseline and it decays deterministically forward. Host-authoritative.
var knockdown_timer: float = 0.0
# Movement INTENT: the raw WASD vector (world frame, 8-way quantized on the
# wire) and the brake hold. The gait reads what the player is TRYING to do —
# crossover intent, deliberate hockey stop, no-keys glide — a beat before
# velocity responds. They are also LOAD-BEARING, not merely cosmetic: they drive
# SkaterMovementRules.integrate_forward on both the client render
# (RemoteController) and the host claim rewind
# (LagCompRewind.forward_predict_skater), so render == rewind depends on them
# surviving the rewind snapshot (StateBufferManager copies them). One byte on
# the wire (v15).
var move_intent: Vector2 = Vector2.ZERO
var brake_intent: bool = false
# Resolved stance, from SkaterController.stance_active on the simulating machine.
# Drives the stance gait read on client-rendered remotes, which never resolve the
# stance themselves, and the posture term of the forward prediction
# (load-bearing, like move_intent above). Bit 5 of the intent byte.
var stance_active: bool = false
# Resolved hit-commit (the Hit button held, locomotion not suppressed), from
# SkaterController.hit_committed on the simulating machine. Replicated so the
# body-check resolver reads a REMOTE victim's brace and a remote attacker's
# full-vs-passive delivery correctly on a client (the host knows all locally).
# Bit 6 of the intent byte (no block growth).
var hit_committed: bool = false
# Which side of the puck the blade is on (±1, Skater.wire_blade_side), read by
# state: in WRISTER_AIM the face of the still puck the frozen blade addresses
# (face-normal sign) — the re-address tell, so render-only clients show the
# shooter's blade on the side the shot will push from; in SKATING_WITH_PUCK the
# carry side (forehand-normalized) — the host's, which places its puck, so a
# client draws the blade and puck where the host has them rather than deciding
# the side again off a blade placed with the host's. Garbage in any other state
# (validity is implicit in it, so the wire spends one bit); consumers go
# through Skater.apply_wire_blade_side, which gates on it.
var blade_side: int = 1
# The balance lean (world XZ, radians) and its spring rate. LOAD-BEARING: the
# lean translates the UpperBody frame the wire's blade_position and
# top_hand_position are local to, so a receiver that placed the frame from any
# other lean would put the blade somewhere else. The local reconcile snaps both
# to the host's before replay (v61).
var balance_tilt: Vector2 = Vector2.ZERO
var balance_tilt_vel: Vector2 = Vector2.ZERO
# The torso's smoothed lean (SkaterPoseCoordinator): the reach lean (pitch,
# roll) and the skating posture's pitch, radians. LOAD-BEARING for the same
# reason — UpperBody's tilt is what puts the wire's local blade on the ice —
# and like the balance lean the reconcile snaps them before replay (v62).
var torso_lean: Vector2 = Vector2.ZERO
var posture_lean: float = 0.0
# Body-frame direction the last check shoved this skater (x = right, y =
# forward), unit length. The stagger reel and the knockdown fall both tip this
# way, and the reel tilts UpperBody (v63).
var recoil_dir: Vector2 = Vector2(0.0, 1.0)
var host_timestamp: float = 0.0         # host-only, not serialized
var blade_contact_world: Vector3 = Vector3.ZERO  # host-only, not serialized
# World-space top-hand (grip) point. host-only, not serialized — paired with
# blade_contact_world to form the shaft segment for stick-lift claim
# resolution. The wire `top_hand_position` is upper-body-local, so it can't be
# used for host-side world-space geometry.
var top_hand_world: Vector3 = Vector3.ZERO  # host-only, not serialized
# Seconds of the catch's settle lock left (SkaterSettleGate), for the host's
# bots. host-only, not serialized — a client's own lock rides the pickup grant.
var settle_left_s: float = 0.0

func to_array() -> Array:
	return [
		position,
		velocity,
		blade_position,
		top_hand_position,
		upper_body_rotation_y,
		facing,
		last_processed_host_timestamp,
		is_ghost,
		shot_state,
		shot_charge,
		facing_angular_velocity,
		upper_body_angular_velocity,
		elevation_level,
		blade_up,
		stagger_timer,
		move_intent,
		brake_intent,
		stance_active,
		knockdown_timer,
		hit_committed,
		blade_side,
		balance_tilt,
		balance_tilt_vel,
		torso_lean,
		posture_lean,
		recoil_dir,
		stick_check_phase,
		stick_check_elapsed,
		stick_tied,
		pin_role,
		pin_strength,
		diving,
		slapshot_pinned,
	]

# The stick-play, pin and dive fields, which are discrete: a reader between two
# snapshots (interpolation, the rewind buffer, replay playback) takes them whole
# from one, never blends them.
func copy_stick_play_from(s: SkaterNetworkState) -> void:
	blade_up = s.blade_up
	stick_check_phase = s.stick_check_phase
	stick_check_elapsed = s.stick_check_elapsed
	stick_tied = s.stick_tied
	pin_role = s.pin_role
	pin_strength = s.pin_strength
	diving = s.diving
	slapshot_pinned = s.slapshot_pinned


func copy_from(s: SkaterNetworkState) -> void:
	position = s.position
	velocity = s.velocity
	blade_position = s.blade_position
	top_hand_position = s.top_hand_position
	upper_body_rotation_y = s.upper_body_rotation_y
	facing = s.facing
	facing_angular_velocity = s.facing_angular_velocity
	upper_body_angular_velocity = s.upper_body_angular_velocity
	last_processed_host_timestamp = s.last_processed_host_timestamp
	is_ghost = s.is_ghost
	elevation_level = s.elevation_level
	blade_up = s.blade_up
	shot_state = s.shot_state
	shot_charge = s.shot_charge
	stagger_timer = s.stagger_timer
	knockdown_timer = s.knockdown_timer
	move_intent = s.move_intent
	brake_intent = s.brake_intent
	stance_active = s.stance_active
	hit_committed = s.hit_committed
	blade_side = s.blade_side
	balance_tilt = s.balance_tilt
	balance_tilt_vel = s.balance_tilt_vel
	torso_lean = s.torso_lean
	posture_lean = s.posture_lean
	recoil_dir = s.recoil_dir
	stick_check_phase = s.stick_check_phase
	stick_check_elapsed = s.stick_check_elapsed
	stick_tied = s.stick_tied
	pin_role = s.pin_role
	pin_strength = s.pin_strength
	diving = s.diving
	slapshot_pinned = s.slapshot_pinned
	host_timestamp = s.host_timestamp
	blade_contact_world = s.blade_contact_world
	top_hand_world = s.top_hand_world
	settle_left_s = s.settle_left_s

static func from_array(data: Array) -> SkaterNetworkState:
	var state := SkaterNetworkState.new()
	state.position = data[0]
	state.velocity = data[1]
	state.blade_position = data[2]
	state.top_hand_position = data[3]
	state.upper_body_rotation_y = data[4]
	state.facing = data[5]
	state.last_processed_host_timestamp = data[6]
	state.is_ghost = data[7]
	state.shot_state = data[8]
	state.shot_charge = data[9]
	state.facing_angular_velocity = data[10]
	state.upper_body_angular_velocity = data[11]
	if data.size() > 12:
		state.elevation_level = data[12]
	if data.size() > 13:
		state.blade_up = data[13]
	if data.size() > 14:
		state.stagger_timer = data[14]
	if data.size() > 16:
		state.move_intent = data[15]
		state.brake_intent = data[16]
	if data.size() > 17:
		state.stance_active = data[17]
	if data.size() > 18:
		state.knockdown_timer = data[18]
	if data.size() > 19:
		state.hit_committed = data[19]
	if data.size() > 20:
		state.blade_side = data[20]
	if data.size() > 22:
		state.balance_tilt = data[21]
		state.balance_tilt_vel = data[22]
	if data.size() > 24:
		state.torso_lean = data[23]
		state.posture_lean = data[24]
	if data.size() > 25:
		state.recoil_dir = data[25]
	if data.size() > 27:
		state.stick_check_phase = data[26]
		state.stick_check_elapsed = data[27]
	if data.size() > 28:
		state.stick_tied = data[28]
	if data.size() > 30:
		state.pin_role = data[29]
		state.pin_strength = data[30]
	if data.size() > 31:
		state.diving = data[31]
	if data.size() > 32:
		state.slapshot_pinned = data[32]
	return state

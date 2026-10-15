class_name SkaterAgentPokeEvade
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# Poke-evade: when an opponent's blade reaches poke range from the front, commit
# for a brief window to a full-thrust CUT toward the directed seam, so the poke
# timed for our current trajectory swings through empty ice. Front-hemisphere
# only: a defender chasing from behind closes faster on a sideways cut.
const POKE_EVADE_TRIGGER_REACH_M: float = 2.5
const POKE_EVADE_MIN_CLOSING_VEL_M_S: float = 1.0
const POKE_EVADE_MIN_SELF_SPEED_M_S: float = 2.0
# Long enough for a visible cut (lateral velocity reaches a few m/s), short
# enough that anchor attraction pulls us back on line.
const POKE_EVADE_ACTIVE_TICKS: int = _PhysicsConstants.PHYSICS_TICK * 3 / 20   # ~150 ms
const POKE_EVADE_ACTIVE_S: float = float(POKE_EVADE_ACTIVE_TICKS) / _PhysicsConstants.PHYSICS_TICK
# Cooldown after an evade, so a defender hanging in our face doesn't loop us into
# a constant cut.
const POKE_EVADE_COOLDOWN_TICKS: int = _PhysicsConstants.PHYSICS_TICK / 2   # ~500 ms
# Least distance to the evasion seam that still defines a deke direction; under
# it the model is saying HOLD, so no evade triggers. There is deliberately no
# blind-perpendicular fallback: without a seam read (always, on Easy's closed
# protect gate) there is no deke.
const POKE_EVADE_SEAM_MIN_DIST_M: float = 0.75

# FAKE-THEN-CUT deke windows, in ticks, derived from AICarrySpace.DEKE_FAKE_S /
# DEKE_CUT_S so the gesture performed is the one the eval priced. The cooldown is
# longer than the plain cut's so dekes read as deliberate, occasional moves.
const DEKE_FAKE_TICKS: int = int(
		AICarrySpace.DEKE_FAKE_S * _PhysicsConstants.PHYSICS_TICK)
const DEKE_CUT_TICKS: int = int(
		AICarrySpace.DEKE_CUT_S * _PhysicsConstants.PHYSICS_TICK)
const DEKE_COOLDOWN_TICKS: int = _PhysicsConstants.PHYSICS_TICK   # ~1 s

# One carrier's discrete poke-evade: the committed cut or fake-then-cut deke, and the carry cursor that sells the deke. Owns the window
# and what it latched; the carrier's read and the bot's knobs come in per call.
# Public so tests can stage a window; the agent itself only calls methods.

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
# The window and cooldown. While active, the evade overrides move_vector.
var active_ticks: int = 0
var cooldown_ticks: int = 0
# Cut direction LATCHED at trigger toward the carrier's directed evasion seam —
# re-reading it per tick would spiral as our own velocity rotates mid-cut.
# Non-zero whenever a CUT window is active; ZERO otherwise.
var cut_seam_dir: Vector2 = Vector2.ZERO
# Maneuver LATCHED at trigger: the FAKE-THEN-CUT deke. Phase splits on the
# remaining active ticks (fake while > DEKE_CUT_TICKS, then the cut); both
# directions latched from the carrier's manufactured-opening read at trigger
# (a deke re-read mid-gesture would un-sell the fake).
var deking: bool = false
var deke_fake_dir: Vector2 = Vector2.ZERO
var deke_cut_dir: Vector2 = Vector2.ZERO


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer


# Back to idle: no window, no cooldown, nothing latched.
func reset() -> void:
	active_ticks = 0
	cooldown_ticks = 0
	cut_seam_dir = Vector2.ZERO
	deking = false
	deke_fake_dir = Vector2.ZERO
	deke_cut_dir = Vector2.ZERO


# Poke-evade (see the POKE_EVADE_* constants): overrides steering for a brief
# committed window — a CUT toward the carrier's directed evasion seam (latched
# at trigger, _seam_cut_direction; no seam, no cut) or the FAKE-THEN-CUT deke.
# A stop is not one of them: the carrier's rolled carry prices BRAKE against the
# same pressure, and when it picked it the evade stands down so the stop plays.
#
# Lifecycle: while active, drive the maneuver and count down, then start the
# cooldown; during the cooldown, normal steering; otherwise scan for a trigger.
#
# Trigger (ALL must hold): own speed ≥ POKE_EVADE_MIN_SELF_SPEED_M_S (slower is
# the deke's home, not the cut's); an opposing blade within
# POKE_EVADE_TRIGGER_REACH_M of our puck, in our FRONT hemisphere by velocity;
# RELATIVE closing ≥ POKE_EVADE_MIN_CLOSING_VEL_M_S — the carrier driving at a
# waiting defender counts.
# `carrier` is the bot's AIRoleCarrier, read for its published evasion read and
# rolled move; `upright_lateral_accel` what the bot's edges can turn; the window counts down by
# `dispatch_period_ticks`, the span one call covers.
func modulate(input: InputState, snapshot: WorldSnapshot, self_pos: Vector3,
		carrier: AIRoleCarrier, protects_the_puck: bool,
		upright_lateral_accel: float, dispatch_period_ticks: int) -> void:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		return
	var vel_xz := Vector2(self_state.velocity.x, self_state.velocity.z)
	if active_ticks > 0:
		_drive(input, vel_xz, upright_lateral_accel)
		# Decrement by the dispatch span: the window is sized in physics ticks.
		active_ticks -= dispatch_period_ticks
		if active_ticks <= 0:
			active_ticks = 0
			cooldown_ticks = DEKE_COOLDOWN_TICKS \
					if deking else POKE_EVADE_COOLDOWN_TICKS
			deking = false
		return
	if cooldown_ticks > 0:
		cooldown_ticks = maxi(0, cooldown_ticks - dispatch_period_ticks)
		return
	var speed: float = vel_xz.length()
	if speed < POKE_EVADE_MIN_SELF_SPEED_M_S:
		# Too slow for the cut (it reads as a wiggle), but the standstill duel
		# against a patient container is the deke's home.
		if carrier.deke_go:
			_start_deke(input, vel_xz, carrier, upright_lateral_accel)
		return
	var forward: Vector2 = vel_xz / speed
	# Same carried-puck point the stickhandle uses.
	var forward_3d := Vector3(forward.x, 0.0, forward.y)
	var carry_pos: Vector3 = self_pos + forward_3d * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M
	var trigger_threat: SkaterNetworkState = null
	for peer_id: int in snapshot.skater_states:
		if peer_id == _peer_id:
			continue
		if _team_id_by_peer.get(peer_id, -1) == _team_id:
			continue
		var opp_state: SkaterNetworkState = snapshot.skater_states[peer_id]
		var threat_pos: Vector3 = opp_state.blade_contact_world
		if threat_pos == Vector3.ZERO:
			threat_pos = opp_state.position
		var blade_to_puck: Vector3 = threat_pos - carry_pos
		blade_to_puck.y = 0.0
		if blade_to_puck.length() > POKE_EVADE_TRIGGER_REACH_M:
			continue
		# Front hemisphere by our VELOCITY, not facing: the poke is timed for
		# where we're moving.
		var to_opp_3d: Vector3 = opp_state.position - self_pos
		to_opp_3d.y = 0.0
		var to_opp_len: float = to_opp_3d.length()
		if to_opp_len < 0.001:
			continue
		var to_opp_norm: Vector3 = to_opp_3d / to_opp_len
		if to_opp_norm.x * forward.x + to_opp_norm.z * forward.y <= 0.0:
			continue
		# RELATIVE closing: skating into a stationary defender closes the gap as
		# surely as one stepping up.
		var closing: float = (self_state.velocity - opp_state.velocity).dot(to_opp_norm)
		if closing < POKE_EVADE_MIN_CLOSING_VEL_M_S:
			continue
		trigger_threat = opp_state
		break
	if trigger_threat == null:
		# CONTAINMENT trigger: a patient container never closes fast enough to
		# register as a poke, so the deke commits here when the carrier's
		# re-eval says a fake would manufacture an opening.
		if carrier.deke_go:
			_start_deke(input, vel_xz, carrier, upright_lateral_accel)
		return
	# Maneuver pick, latched for the window: the rolled stop the carry already
	# chose; else the deke against patient pressure; else the cut toward the
	# seam. No usable maneuver means no trigger: the window and cooldown are
	# only spent on a committed move.
	if carrier.carry_move == AICarryRollout.Move.BRAKE:
		return
	if carrier.deke_go:
		_start_deke(input, vel_xz, carrier, upright_lateral_accel)
		return
	var cut_dir: Vector2 = _seam_cut_direction(self_pos, carrier, protects_the_puck)
	if cut_dir == Vector2.ZERO:
		return
	cut_seam_dir = cut_dir
	active_ticks = POKE_EVADE_ACTIVE_TICKS
	_drive(input, vel_xz, upright_lateral_accel)


# The cut direction: toward the carrier's DIRECTED evasion seam (from the last
# re-eval, re-based on the live body). The seam reads every defender's momentum,
# so a charger's cut resolves behind him and a jockeying defender's past his
# open side. ZERO when this tier doesn't protect the puck, there is no seam yet,
# or the seam is underfoot.
func _seam_cut_direction(self_pos: Vector3, carrier: AIRoleCarrier,
		protects_the_puck: bool) -> Vector2:
	if not protects_the_puck:
		return Vector2.ZERO
	var seam: Vector3 = carrier.evade_seam_world
	if not seam.is_finite():
		return Vector2.ZERO
	var to_seam := Vector2(seam.x - self_pos.x, seam.z - self_pos.z)
	if to_seam.length() < POKE_EVADE_SEAM_MIN_DIST_M:
		return Vector2.ZERO
	return to_seam.normalized()


# Latch and start the FAKE-THEN-CUT deke: one committed window covering both
# phases; the drive below splits them on the remaining ticks. Directions come
# from the carrier's manufactured-opening read (same axis frame as the eval,
# so the gesture performed is the gesture priced).
func _start_deke(input: InputState, vel_xz: Vector2, carrier: AIRoleCarrier,
		upright_lateral_accel: float) -> void:
	deking = true
	deke_fake_dir = carrier.deke_fake_dir
	deke_cut_dir = carrier.deke_cut_dir
	cut_seam_dir = Vector2.ZERO
	active_ticks = DEKE_FAKE_TICKS + DEKE_CUT_TICKS
	_drive(input, vel_xz, upright_lateral_accel)


# One active-window tick of the committed maneuver. DEKE: thrust the fake side,
# then across to the cut side (the cursor follows — mouse_target). CUT: the
# latched seam direction. Both cuts dig in the stance when the upright edges can't turn onto them inside
# their window (AISteering.stance_cuts_onto).
func _drive(input: InputState, vel_xz: Vector2, upright_lateral_accel: float) -> void:
	if deking:
		var cutting: bool = active_ticks <= DEKE_CUT_TICKS
		input.move_vector = deke_cut_dir if cutting else deke_fake_dir
		input.stance_held = cutting and AISteering.stance_cuts_onto(
				deke_cut_dir, vel_xz, upright_lateral_accel, AICarrySpace.DEKE_CUT_S)
		return
	input.move_vector = cut_seam_dir
	input.stance_held = AISteering.stance_cuts_onto(cut_seam_dir, vel_xz,
			upright_lateral_accel, POKE_EVADE_ACTIVE_S)


# The deke's carry-cursor override: sell the fake WITH THE PUCK — the
# defender's read tracks the puck, not the chest — then snap it across for
# the cut; the pull through the wide ROM is the visible toe-drag. INF when no
# deke is active (the normal carry aim runs). Board + net clamps keep the
# blade legal against the walls and the cage.
func mouse_target(self_pos: Vector3) -> Vector3:
	if not deking or active_ticks <= 0:
		return Vector3.INF
	var dir: Vector2 = deke_fake_dir \
			if active_ticks > DEKE_CUT_TICKS else deke_cut_dir
	if dir == Vector2.ZERO:
		return Vector3.INF
	var target := Vector3(
			self_pos.x + dir.x * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M, 0.0,
			self_pos.z + dir.y * AIBotMechanics.CARRY_BLADE_AIM_FORWARD_M)
	var on_ice: Vector2 = GameRules.clamp_to_rink_inner(
			Vector2(target.x, target.z), AIBotMechanics.CARRY_BLADE_WALL_MARGIN_M)
	target.x = on_ice.x
	target.z = on_ice.y
	return AINetObstacle.net_safe_blade_target(self_pos, target)

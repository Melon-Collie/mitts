class_name SkaterStateMachine
extends RefCounted

enum State {
	SKATING_WITHOUT_PUCK,
	SKATING_WITH_PUCK,
	WRISTER_AIM,
	SLAPPER_CHARGE_WITH_PUCK,
	SLAPPER_CHARGE_WITHOUT_PUCK,
	FOLLOW_THROUGH,
	SHOT_BLOCKING,
	ONE_TIMER_RETENTION,
}
# The wire packs shot_state into 3 bits (WorldStateCodec's skater flags byte), so
# this enum is FULL at 8 values. A ninth state costs a flags-byte repack and a
# PROTOCOL_VERSION bump.


# States in which the skater is handling the puck — carrying, aiming a wrister, or
# a slapper wind-up that still holds it (the one-timer SLAPPER_CHARGE_WITHOUT_PUCK
# does NOT). Pure/static so it reads the same on host, client, reconcile replay,
# and the lag-comp claim path (which only has the replicated shot_state, not a live
# carrier reference). Gates the "committed check" split: a carrier can hold the Hit
# button to BRACE but can't DELIVER an offensive check while carrying.
static func state_has_puck(state: int) -> bool:
	return state == State.SKATING_WITH_PUCK \
			or state == State.WRISTER_AIM \
			or state == State.SLAPPER_CHARGE_WITH_PUCK

# States in which the puck is RIGIDLY PINNED to the carrier's body rather than
# riding a live, sweeping blade — the shot wind-ups plus the one-timer retention
# hold, which keeps the wind-up's pin while the shaft loads. WRISTER_AIM freezes the
# blade at its body-local pose (SkaterIKCoordinator.apply_blade_from_mouse under
# hold_blade, which also carries the smoothed blade along with skater
# translation); SLAPPER_CHARGE_WITH_PUCK pins to a skater-local spot
# (Skater.enter_slapshot_pinning). Either way there is NO independent puck motion
# left: the puck's world velocity IS the carrier's, and a position-derived puck
# velocity estimate double-counts the body if it's added on top of a carrier lead.
# The one exception is a carried slapshot's set-up, the first fraction of a
# second, while the blade is still bringing the puck to the strike spot; the
# replicated state cannot tell it apart.
#
# Distinct from state_has_puck (which includes ordinary carry, where the blade
# genuinely dangles independently of the body — the motion the puck lead exists
# to catch). Consumed by the goalie's threat tracking; pure/static so it reads
# identically from a replicated shot_state with no live carrier reference.
#
# NOTE this says nothing about the carrier's MOBILITY, which differs sharply
# between the two: the slapper takes no stride or steer and glides on its
# momentum, while the wrister suppresses nothing and stays fully steerable.
# Reads that depend on the shooter's mobility must test for that separately —
# see GoalieController._reading_planted_windup.
static func state_pins_puck(state: int) -> bool:
	return state == State.WRISTER_AIM \
			or state == State.SLAPPER_CHARGE_WITH_PUCK \
			or state == State.ONE_TIMER_RETENTION

# A skater waiting on a feed with the shot already loaded — the one-timer wind-up
# taken before the puck arrives, or the committed swing it becomes. Visible on
# every peer from the replicated shot_state, so it is a read a goalie can make.
static func state_loads_one_timer(state: int) -> bool:
	return state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
			or state == State.ONE_TIMER_RETENTION

# Controller operations injected at setup. All methods that need @export params
# or actor/puck references stay on SkaterController and are wired as Callables
# so the state machine only owns transition logic.
class Callbacks:
	# Blade / IK
	var apply_blade_from_mouse: Callable          # (input: InputState, delta: float)
	var apply_wrister_aim_blade: Callable         # (input: InputState, delta: float) — holds the blade at the shot origin while the torso coils
	var apply_slapper_blade_position: Callable    # ()
	var apply_slapper_setup: Callable             # (input: InputState, delta: float) — the blade takes the puck to the strike spot
	var update_slapper_aim: Callable              # (input: InputState) — the aim, live until the swing commits
	var apply_block_blade_position: Callable      # ()
	var apply_wrister_follow_through: Callable    # ()
	var apply_slapper_follow_through: Callable    # ()
	# State entry
	var enter_shot_block: Callable                # ()
	var enter_slapper_charge: Callable            # (input: InputState)
	var cancel_slapper: Callable                  # (input: InputState) — call a slapshot off: the stick comes back down
	var transition_to_skating: Callable           # ()
	# Shot releases
	var release_wrister: Callable                 # (input: InputState)
	var fire_quick_pass: Callable                 # (input: InputState) — instant quick pass
	var release_slapper: Callable                 # (input: InputState)
	# One-timer retention: the swing commits, the shaft loads for one beat, THEN
	# the shot leaves. `enter` arms the hold timer; `release` fires whichever
	# one-timer path applies once it expires and returns
	# { fired: bool, direction: Vector3, follow_through_duration: float }.
	var enter_one_timer_retention: Callable       # ()
	var release_retained_one_timer: Callable      # (input: InputState) -> Dictionary
	# Per-frame updates that need @export params from SkaterController
	var update_wrister_charge: Callable           # (input: InputState)
	var update_slapper_charge: Callable           # (delta: float)
	var apply_block_movement: Callable            # (input: InputState, delta: float)

# ── Owned state (moved from SkaterController) ─────────────────────────────────
var _state: State = State.SKATING_WITHOUT_PUCK
# No underscore: LocalController accesses these directly in reconcile().
var follow_through_timer: float = 0.0
var follow_through_is_slapper: bool = false
# Total the timer started from (normalizes follow-through progress — durations
# differ per shot type) and the amplitude scale of this follow-through (set at
# release: wrister by charge, quick pass fixed low, slapper full). Saved and
# restored through reconcile in LocalController alongside the timer.
var follow_through_duration_total: float = 0.25
var follow_through_power: float = 1.0
var shot_dir: Vector3 = Vector3.ZERO
var locked_slapper_dir: Vector2 = Vector2.ZERO

var _cb: Callbacks
var _aiming: SkaterAimingBehavior

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(callbacks: Callbacks, aiming: SkaterAimingBehavior) -> void:
	_cb = callbacks
	_aiming = aiming

# ── State accessors ───────────────────────────────────────────────────────────

func get_state() -> State:
	return _state


func set_state(s: State) -> void:
	_state = s

# ── Dispatch ─────────────────────────────────────────────────────────────────

func dispatch(skater: Skater, input: InputState, delta: float, has_puck: bool, is_movement_locked: bool) -> void:
	match _state:
		State.SKATING_WITHOUT_PUCK:
			_state_skating_without_puck(skater, input, delta, has_puck, is_movement_locked)
		State.SKATING_WITH_PUCK:
			_state_skating_with_puck(skater, input, delta, has_puck, is_movement_locked)
		State.WRISTER_AIM:
			_state_wrister_aim(skater, input, delta, has_puck, is_movement_locked)
		State.SLAPPER_CHARGE_WITH_PUCK:
			_state_slapper_charge_with_puck(skater, input, delta, has_puck, is_movement_locked)
		State.SLAPPER_CHARGE_WITHOUT_PUCK:
			_state_slapper_charge_without_puck(skater, input, delta, has_puck, is_movement_locked)
		State.FOLLOW_THROUGH:
			_state_follow_through(skater, input, delta, has_puck, is_movement_locked)
		State.SHOT_BLOCKING:
			_state_shot_blocking(skater, input, delta, has_puck, is_movement_locked)
		State.ONE_TIMER_RETENTION:
			_state_one_timer_retention(skater, input, delta, has_puck, is_movement_locked)

# ── State handlers ────────────────────────────────────────────────────────────

func _state_skating_without_puck(_skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	if input.block_held:
		_cb.enter_shot_block.call()
		return
	_cb.apply_blade_from_mouse.call(input, delta)
	if input.shoot_pressed:
		_state = State.WRISTER_AIM
		shot_dir = Vector3.ZERO
	if input.slap_pressed:
		_cb.enter_slapper_charge.call(input)


func _state_skating_with_puck(skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	_cb.apply_blade_from_mouse.call(input, delta)
	# Quick pass: dedicated button, fires instantly (no aim state). Checked
	# before the wrister so the blade target computed above is this tick's, and
	# returns so a same-tick shoot/slap press can't stack on top.
	if input.quick_pass_pressed:
		_cb.fire_quick_pass.call(input)
		return
	if input.shoot_pressed:
		_enter_wrister_aim(skater, input)
	if input.slap_pressed:
		_cb.enter_slapper_charge.call(input)


func _state_wrister_aim(_skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	# The OTHER shot button cancels: tap the slapper (RMB) to bail a wrister
	# charge back to carry without firing. The slap_pressed edge is consumed here,
	# so returning to carry this tick can't stack into a slapper charge next tick.
	if input.slap_pressed:
		_cb.transition_to_skating.call()
		return
	# Holds the blade frozen at the shot origin (the puck sits still where the shot
	# fires from) while the torso coils toward the cursor.
	_cb.apply_wrister_aim_blade.call(input, delta)
	_cb.update_wrister_charge.call(input)
	if not input.shoot_held:
		_cb.release_wrister.call(input)


func _state_slapper_charge_with_puck(_skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	# The OTHER shot button cancels: tap the wrister (LMB) to bail the slapper
	# wind-up back to carry. Block is the shot-block stance and cancels nothing.
	if input.shoot_pressed:
		_cancel_slapper_internal(input)
		return

	# Set-up: the blade is still taking the puck to the strike spot and the
	# charge has not started. Letting go before it is set is no shot at all.
	if not _aiming.slapper_setup_done:
		if not input.slap_held:
			_cancel_slapper_internal(input)
			return
		_cb.update_slapper_aim.call(input)
		_cb.apply_slapper_setup.call(input, delta)
		return

	# One-timer window: puck arrived mid-charge. Player must release before
	# the window expires or the shot is cancelled (they keep the puck).
	if _aiming.one_timer_window_timer > 0.0:
		_aiming.tick_one_timer_window(delta)
		if _aiming.one_timer_window_timer <= 0.0:
			# Window expired — cancel slapper, keep puck in carry state.
			_cancel_slapper_internal(input)
			return
		if not input.slap_held:
			# A one-timer does not leave on the button edge: the swing commits
			# into the retention hold (puck stays pinned, shaft loads) and the
			# shot fires at the end of it. A plain carried slapshot — no window
			# armed — still releases immediately below.
			_cb.enter_one_timer_retention.call()
			_state = State.ONE_TIMER_RETENTION
			return

	_cb.update_slapper_aim.call(input)
	_cb.update_slapper_charge.call(delta)
	_cb.apply_slapper_blade_position.call()

	if not input.slap_held:
		_cb.release_slapper.call(input)


func _state_slapper_charge_without_puck(_skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	# The OTHER shot button cancels: tap the wrister (LMB) to bail a one-timer
	# wind-up back to carry.
	if input.shoot_pressed:
		_cancel_slapper_internal(input)
		return

	_cb.update_slapper_aim.call(input)
	_cb.update_slapper_charge.call(delta)
	_cb.apply_slapper_blade_position.call()

	if not input.slap_held:
		# The swing commits here but the puck does NOT leave yet — the blade has
		# to travel down to it. ONE_TIMER_RETENTION holds that beat; the range
		# check and the shot itself run at the end of it (see
		# _state_one_timer_retention).
		_cb.enter_one_timer_retention.call()
		_state = State.ONE_TIMER_RETENTION


# The one-timer's catch-and-load beat. The swing is already committed — no input
# is read here, not even a cancel — so the ONLY exit is the shot (or its whiff)
# at the end of the hold. The blade holds its wind-up pose and the shaft loads
# (Skater._update_stick_flex keys the bow off this state), which is the visible
# "caught it, now it's loading" read.
#
# The range check and every downstream consequence (the lag-comped one-timer
# claim, the host's authoritative fire, the local prediction seed) run at the END
# of the hold, unchanged — retention shifts WHEN they run, not what they do.
func _state_one_timer_retention(_skater: Skater, input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	_cb.apply_slapper_blade_position.call()
	_aiming.tick_one_timer_retention(delta)
	if _aiming.one_timer_retention_timer > 0.0:
		return
	var result: Dictionary = _cb.release_retained_one_timer.call(input)
	if result.get("fired", false):
		shot_dir = result.direction
	else:
		# Whiffed one-timer: the swing is already committed — play the full
		# follow-through through empty air (shot_dir stays zero; the pose falls
		# back to locked_slapper_dir) rather than snapping the wind-up away.
		shot_dir = Vector3.ZERO
	follow_through_is_slapper = true
	_state = State.FOLLOW_THROUGH
	follow_through_timer = result.get("follow_through_duration", 0.5)
	follow_through_duration_total = follow_through_timer


func _state_follow_through(_skater: Skater, _input: InputState, delta: float, _has_puck: bool, _is_movement_locked: bool) -> void:
	if follow_through_is_slapper:
		_cb.apply_slapper_follow_through.call()
	else:
		_cb.apply_wrister_follow_through.call()
	follow_through_timer -= delta
	if follow_through_timer <= 0.0:
		_cb.transition_to_skating.call()


func _state_shot_blocking(skater: Skater, input: InputState, delta: float, _has_puck: bool, is_movement_locked: bool) -> void:
	if not input.block_held or is_movement_locked:
		skater.set_block_stance(false)
		_cb.transition_to_skating.call()
		return
	_cb.apply_block_movement.call(input, delta)
	_cb.apply_block_blade_position.call()

# ── Internal helpers ──────────────────────────────────────────────────────────

func _enter_wrister_aim(skater: Skater, input: InputState) -> void:
	_state = State.WRISTER_AIM
	shot_dir = Vector3.ZERO
	# Seed the cursor (screen-space) baseline the speed EMA differences against,
	# so the first tick after press reads zero speed rather than a jump.
	var intent_pos := Vector3(input.mouse_screen_pos.x, 0.0, input.mouse_screen_pos.y)
	# Pin the aim ORIGIN at stroke start (the puck's on-blade contact point, where
	# the shot will fire from) for the positional-aim wrister — see
	# SkaterAimingBehavior.wrister_origin_world. Anchoring here, before the blade
	# sweeps, is what keeps origin→cursor stable through the stroke.
	var origin_world: Vector3 = skater.get_blade_contact_global()
	# Skater position at the pin (XZ): what the frozen puck rides along from
	# (WristerLoad).
	var origin_skater_pos: Vector3 = skater.global_position
	origin_skater_pos.y = 0.0
	_aiming.reset_wrister(intent_pos, origin_world, origin_skater_pos)


func _cancel_slapper_internal(input: InputState) -> void:
	_cb.cancel_slapper.call(input)

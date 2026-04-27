extends Node

# ── Step definition ───────────────────────────────────────────────────────────

class TutorialStep:
	var title: String
	var instruction: String
	var hint: String

	func _init(t: String, i: String, h: String = "") -> void:
		title = t
		instruction = i
		hint = h


# ── Step index constants ──────────────────────────────────────────────────────

const STEP_SKATE:       int = 0
const STEP_BRAKE:       int = 1
const STEP_QUICK_SHOT:  int = 2
const STEP_WRIST_SHOT:  int = 3
const STEP_SLAPSHOT:    int = 4
const STEP_ONE_TIMER:   int = 5
const STEP_SHOT_BLOCK:  int = 6
const STEP_STICKCHECK:  int = 7
const STEP_BODY_CHECK:  int = 8
const STEP_ELEVATION:   int = 9
const STEP_OFFSIDES:    int = 10
const STEP_ICING:       int = 11

# Duration thresholds for sustained-hold steps
const _SKATE_HOLD:           float = 1.5
const _BRAKE_HOLD:           float = 1.0
const _BLOCK_HOLD:           float = 2.0
const _SHOT_BLOCK_HOLD:      float = 1.0
# Wrist shot: must hold WRISTER_AIM for this long to distinguish from quick shot
const _WRIST_HOLD_MIN:       float = 0.4
# One-timer puck launch speed (m/s toward player)
const _ONE_TIMER_PUCK_SPEED: float = 8.0
# Shot block: puck comes from the offensive zone toward the player's goal
const _SHOT_BLOCK_PUCK_SPEED: float = 10.0
# Ice height for puck placement
const _ICE_Y:                float = 0.05

# ── References ────────────────────────────────────────────────────────────────

var _local_record:     PlayerRecord    = null
var _local_controller: LocalController = null
var _skater:           Skater          = null
var _puck:             Puck            = null
var _dummy_skater:     Skater          = null
var _dummy_controller: Node            = null

# ── State ─────────────────────────────────────────────────────────────────────

var _steps:              Array[TutorialStep] = []
var _current_step:       int   = 0
var _step_timer:         float = 0.0
var _hint_timer:         float = 0.0
var _complete_flash_timer: float = 0.0
var _wrister_aim_start:  float = -1.0   # -1 when not in WRISTER_AIM
var _offside_ghost_seen: bool  = false
var _icing_armed:        bool  = false  # true once puck is staged and loose
var _icing_scored:       bool  = false  # true after puck crosses goal line

var _hud: TutorialHUD = null

# Restage timer: counts down after a failed shot; re-places puck when it hits 0
var _restage_timer: float = -1.0
const _RESTAGE_DELAY: float = 1.5

# Connected callables stored for safe disconnection
var _on_release_callable:    Callable = Callable()
var _on_one_timer_callable:  Callable = Callable()
var _on_body_check_callable: Callable = Callable()
var _on_regular_shot_in_one_timer: Callable = Callable()


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_local_record = GameManager.get_local_player()
	if _local_record == null:
		push_error("TutorialManager: no local player found")
		return
	_local_controller = _local_record.controller as LocalController
	_skater = _local_record.skater
	_puck = GameManager.get_puck()

	_build_steps()

	_hud = TutorialHUD.new()
	add_child(_hud)
	_hud.skip_pressed.connect(_on_skip)

	_begin_step(_current_step)


func _exit_tree() -> void:
	_disconnect_all_signals()
	_free_dummy()
	NetworkManager.is_tutorial_mode = false


# ── Step definitions ──────────────────────────────────────────────────────────

func _build_steps() -> void:
	_steps.clear()
	_steps.append(TutorialStep.new(
		"Skate",
		"Use the move stick / WASD to skate around the ice.",
		"Push the stick in any direction to build up speed."))
	_steps.append(TutorialStep.new(
		"Brake",
		"Hold [Brake] with no direction to stop, or hold it with a direction to carve.",
		"Brake key is Space (keyboard) or LB/L1 (controller)."))
	_steps.append(TutorialStep.new(
		"Quick Shot",
		"Skate to the puck to pick it up, then tap [Shoot] quickly for a Quick Shot.",
		"Just flick the Shoot button — don't hold it."))
	_steps.append(TutorialStep.new(
		"Wrist Shot",
		"Pick up the puck, hold [Shoot], and sweep the mouse / stick to aim a Wrist Shot.",
		"Hold Shoot and drag — the longer you hold, the more power."))
	_steps.append(TutorialStep.new(
		"Slapshot",
		"Pick up the puck, hold [Slap] to wind up, then release for a Slapshot.",
		"Slap key is RMB / LT / L2."))
	_steps.append(TutorialStep.new(
		"One-timer",
		"Wind up [Slap] before the puck arrives, then release the moment it reaches you.",
		"Start the Slap windup first — the puck is coming toward you!"))
	_steps.append(TutorialStep.new(
		"Shot Block",
		"A shot is coming at you — hold [Block] to get into a deflecting stance.",
		"Block key is RMB / RB / R1."))
	_steps.append(TutorialStep.new(
		"Stickcheck",
		"Hold [Block] while close to the opponent with the puck to attempt a stickcheck.",
		"Stay tight to the opponent and hold Block."))
	_steps.append(TutorialStep.new(
		"Body Check",
		"Skate directly into the opponent to body check them.",
		"Pick up speed and aim straight at them."))
	_steps.append(TutorialStep.new(
		"Elevation",
		"Pick up the puck, hold [Elevation Up], then shoot to lift the puck off the ice.",
		"Hold Elevation Up (E / D-Up) before pressing Shoot or Slap."))
	_steps.append(TutorialStep.new(
		"Offsides",
		"You're in the offensive zone before the puck — that's offside. Skate back past the blue line to reset!",
		"The blue line marks the boundary between neutral and offensive zones."))
	_steps.append(TutorialStep.new(
		"Icing",
		"Shooting the puck from your own end past the far goal line is icing — your whole team goes ghost, giving the other team free possession. Try it now.",
		"Wind up a big Slapshot and fire toward the far end."))


# ── Step sequencing ───────────────────────────────────────────────────────────

func _begin_step(index: int) -> void:
	_disconnect_all_signals()
	_step_timer         = 0.0
	_hint_timer         = 0.0
	_complete_flash_timer = 0.0
	_restage_timer      = -1.0
	_wrister_aim_start  = -1.0
	_offside_ghost_seen = false
	_icing_armed        = false
	_icing_scored       = false

	var step: TutorialStep = _steps[index]
	_hud.set_step(index, _steps.size(), step.title, step.instruction, step.hint)

	match index:
		STEP_SKATE:
			_local_controller.teleport_to(Vector3(0.0, 1.0, 5.0))
			_place_puck(Vector3(100.0, _ICE_Y, 100.0))  # out of the way

		STEP_BRAKE:
			pass  # player is already on the ice from the skate step

		STEP_QUICK_SHOT, STEP_WRIST_SHOT, STEP_SLAPSHOT, STEP_ELEVATION:
			_local_controller.teleport_to(Vector3(0.0, 1.0, 5.0))
			# Puck 1 m ahead in attacking direction (-Z)
			_place_puck(Vector3(0.0, _ICE_Y, 3.5))
			_on_release_callable = func(dir: Vector3, power: float, is_slapper: bool) -> void:
				_on_shot_released(dir, power, is_slapper)
			_local_controller.puck_release_requested.connect(_on_release_callable)

		STEP_ONE_TIMER:
			_local_controller.teleport_to(Vector3(0.0, 1.0, -3.0))
			_fire_puck_at_player()
			_on_one_timer_callable = func(_dir: Vector3, _power: float) -> void:
				_complete_step()
			_local_controller.one_timer_release_requested.connect(_on_one_timer_callable)
			# If player picks up puck normally and shoots, re-stage
			_on_regular_shot_in_one_timer = func(_dir: Vector3, _power: float, _is_slapper: bool) -> void:
				_local_controller.teleport_to(Vector3(0.0, 1.0, -3.0))
				_fire_puck_at_player()
			_local_controller.puck_release_requested.connect(_on_regular_shot_in_one_timer)

		STEP_SHOT_BLOCK:
			_local_controller.teleport_to(Vector3(0.0, 1.0, 5.0))
			_fire_puck_for_shot_block()

		STEP_STICKCHECK:
			_local_controller.teleport_to(Vector3(0.0, 1.0, 2.0))
			_ensure_dummy(Vector3(0.0, 1.0, 0.0))
			# Puck near the dummy so the stickcheck context makes sense
			_place_puck(Vector3(0.0, _ICE_Y, 0.2))

		STEP_BODY_CHECK:
			_local_controller.teleport_to(Vector3(-4.0, 1.0, 0.0))
			_place_puck(Vector3(100.0, _ICE_Y, 100.0))
			_ensure_dummy(Vector3(4.0, 1.0, 0.0))
			_on_body_check_callable = func(_victim: Skater, _force: float, _dir: Vector3) -> void:
				_complete_step()
			_skater.body_checked_player.connect(_on_body_check_callable)

		STEP_OFFSIDES:
			# Place player deep in offensive zone (past far blue line, -Z direction)
			_local_controller.teleport_to(Vector3(0.0, 1.0, -12.0))
			# Puck in neutral zone — player is immediately offside
			_place_puck(Vector3(0.0, _ICE_Y, 0.0))

		STEP_ICING:
			# Player at own defensive end, offset from center to shoot wide of the net
			_local_controller.teleport_to(Vector3(-5.0, 1.0, 20.0))
			_place_puck(Vector3(-5.0, _ICE_Y, 18.5))
			_icing_armed = false  # armed after one frame below


func _complete_step() -> void:
	_disconnect_all_signals()
	_complete_flash_timer = TutorialHUD._COMPLETE_FLASH_DURATION
	_hud.flash_complete()
	if _current_step == STEP_BODY_CHECK:
		_free_dummy()


func _advance_step() -> void:
	_hud.hide_complete_flash()
	_current_step += 1
	if _current_step >= _steps.size():
		_hud.show_tutorial_complete()
	else:
		_begin_step(_current_step)


func _on_skip() -> void:
	if _current_step in [STEP_SHOT_BLOCK]:
		_place_puck(Vector3(100.0, _ICE_Y, 100.0))  # clear the in-flight puck
	if _current_step in [STEP_STICKCHECK, STEP_BODY_CHECK]:
		_free_dummy()
	_complete_step()


# ── Per-frame logic ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _local_record == null:
		return

	if _complete_flash_timer > 0.0:
		_complete_flash_timer -= delta
		if _complete_flash_timer <= 0.0:
			_advance_step()
		return

	_hint_timer += delta
	if _hint_timer >= TutorialHUD._HINT_DELAY:
		_hud.show_hint()

	# Puck re-stage after a failed shot attempt
	if _restage_timer >= 0.0:
		_restage_timer -= delta
		if _restage_timer <= 0.0:
			_restage_timer = -1.0
			_local_controller.teleport_to(Vector3(0.0, 1.0, 5.0))
			_place_puck(Vector3(0.0, _ICE_Y, 3.5))

	# Track WRISTER_AIM (state 2) entry for quick vs wrist shot distinction
	var shot_state: int = _local_controller.get_shot_state()
	if shot_state == 2:
		if _wrister_aim_start < 0.0:
			_wrister_aim_start = Time.get_ticks_msec() / 1000.0
	else:
		if _wrister_aim_start >= 0.0:
			_wrister_aim_start = -1.0

	match _current_step:
		STEP_SKATE:
			if _skater.velocity.length() > 2.5:
				_step_timer += delta
				if _step_timer >= _SKATE_HOLD:
					_complete_step()
			else:
				_step_timer = 0.0

		STEP_BRAKE:
			if _skater.is_braking:
				_step_timer += delta
				if _step_timer >= _BRAKE_HOLD:
					_complete_step()
			else:
				_step_timer = 0.0

		STEP_SHOT_BLOCK:
			# Complete when player holds the block stance for long enough
			if _local_controller.get_shot_state() == 6:  # SHOT_BLOCKING
				_step_timer += delta
				if _step_timer >= _SHOT_BLOCK_HOLD:
					_complete_step()
			else:
				_step_timer = 0.0
			# Re-fire if puck passed the player or stopped before reaching them
			if _puck.carrier == null:
				var puck_z: float = _puck.get_puck_position().z
				if puck_z > _skater.global_position.z + 4.0:
					_fire_puck_for_shot_block()

		STEP_STICKCHECK:
			if _local_controller.get_current_input().block_held:
				_step_timer += delta
				if _step_timer >= _BLOCK_HOLD:
					_complete_step()
			else:
				_step_timer = 0.0

		STEP_ONE_TIMER:
			# Re-fire puck if it stopped or left the play area
			if _icing_armed and _puck.carrier == null:
				var puck_pos: Vector3 = _puck.get_puck_position()
				var puck_speed: float = _puck.get_puck_velocity().length()
				if puck_pos.z < -8.0 or (puck_speed < 0.3 and absf(puck_pos.z - (-3.0)) > 2.0):
					_fire_puck_at_player()

		STEP_OFFSIDES:
			if not _offside_ghost_seen:
				if _skater.is_ghost:
					_offside_ghost_seen = true
					_hud.set_step(_current_step, _steps.size(),
						"Offsides",
						"Now you're a ghost — passes skip right over you. Cross back past the blue line to tag up!",
						"Head toward your own end and cross the blue line.")
			else:
				if not _skater.is_ghost:
					_complete_step()

		STEP_ICING:
			if not _icing_armed:
				# Arm after the first physics frame so puck settles from placement
				_icing_armed = true
				return
			if not _icing_scored:
				# Wait for puck to cross the far goal line (team 0 attacks toward -Z)
				if _puck.carrier == null:
					var puck_z: float = _puck.get_puck_position().z
					if puck_z < -(GameRules.GOAL_LINE_Z - 1.0):
						_icing_scored = true
						# Trigger ghost mode directly — single-player can't win the
						# hybrid icing race (no defending-team players to compare against)
						GameManager.trigger_tutorial_icing()
						_hud.set_step(_current_step, _steps.size(),
							"Icing — You're Ghosted",
							"See? Your whole team goes ghost. In a real game, opponents skate in and grab the puck freely. Ghost clears in a moment.",
							"Avoid icing in real games — free possession for the other team is bad news.")
			else:
				# Wait for the ghost timer to expire and ghost to clear
				if not _skater.is_ghost:
					_complete_step()


# ── Shot signal handler ───────────────────────────────────────────────────────

func _on_shot_released(dir: Vector3, power: float, is_slapper: bool) -> void:
	var completed := false
	match _current_step:
		STEP_QUICK_SHOT:
			if not is_slapper:
				var elapsed: float = 0.0
				if _wrister_aim_start >= 0.0:
					elapsed = Time.get_ticks_msec() / 1000.0 - _wrister_aim_start
				if elapsed < _WRIST_HOLD_MIN:
					completed = true
		STEP_WRIST_SHOT:
			if not is_slapper:
				var elapsed: float = 0.0
				if _wrister_aim_start >= 0.0:
					elapsed = Time.get_ticks_msec() / 1000.0 - _wrister_aim_start
				if elapsed >= _WRIST_HOLD_MIN:
					completed = true
		STEP_SLAPSHOT:
			if is_slapper:
				completed = true
		STEP_ELEVATION:
			if dir.y > 0.1:
				completed = true
	if completed:
		_complete_step()
	else:
		# Re-stage puck after a short delay so the player can try again
		_restage_timer = _RESTAGE_DELAY


# ── Staging helpers ───────────────────────────────────────────────────────────

# Places the puck at a position with zero velocity.
# Does NOT use Puck.reset() (which always resets to center ice).
func _place_puck(pos: Vector3) -> void:
	if _puck.carrier != null:
		_puck.drop()
	_puck.set_puck_position(pos)
	# Velocity: Jolt zeroes it on the first dynamic step after unfreeze, which is fine.
	_puck.linear_velocity = Vector3.ZERO


# Fires the puck from the offensive zone toward the player's goal for the shot-block step.
# Player is at z≈5 (own half); puck comes from z=-8 in the +Z direction.
func _fire_puck_for_shot_block() -> void:
	if _puck.carrier != null:
		_puck.drop()
	_puck.set_puck_position(Vector3(0.0, _ICE_Y, -8.0))
	_puck.apply_release_velocity(Vector3(0.0, 0.001, _SHOT_BLOCK_PUCK_SPEED))


# Fires the puck from z=+15 toward the player at z=-3 for the one-timer step.
# Uses apply_release_velocity with tiny Y so velocity persists through Jolt's
# first-dynamic-step zeroing (same technique as Puck.release()).
func _fire_puck_at_player() -> void:
	if _puck.carrier != null:
		_puck.drop()
	_puck.set_puck_position(Vector3(0.0, _ICE_Y, 15.0))
	# Tiny Y component forces _pending_elevation_vel path in _integrate_forces,
	# which writes velocity directly into Jolt's state before it can be zeroed.
	_puck.apply_release_velocity(Vector3(0.0, 0.001, -_ONE_TIMER_PUCK_SPEED))
	_icing_armed = true


func _ensure_dummy(position: Vector3) -> void:
	if is_instance_valid(_dummy_skater):
		_dummy_skater.global_position = position
		return
	var spawned: Dictionary = GameManager.spawn_tutorial_dummy(position)
	_dummy_skater = spawned.skater as Skater
	_dummy_controller = spawned.controller as Node


func _free_dummy() -> void:
	if is_instance_valid(_dummy_skater):
		_dummy_skater.queue_free()
		_dummy_skater = null
	if is_instance_valid(_dummy_controller):
		_dummy_controller.queue_free()
		_dummy_controller = null


# ── Signal management ─────────────────────────────────────────────────────────

func _disconnect_all_signals() -> void:
	if _local_controller == null:
		return

	if _on_release_callable.is_valid():
		if _local_controller.puck_release_requested.is_connected(_on_release_callable):
			_local_controller.puck_release_requested.disconnect(_on_release_callable)
		_on_release_callable = Callable()

	if _on_one_timer_callable.is_valid():
		if _local_controller.one_timer_release_requested.is_connected(_on_one_timer_callable):
			_local_controller.one_timer_release_requested.disconnect(_on_one_timer_callable)
		_on_one_timer_callable = Callable()

	if _on_body_check_callable.is_valid() and _skater != null:
		if _skater.body_checked_player.is_connected(_on_body_check_callable):
			_skater.body_checked_player.disconnect(_on_body_check_callable)
		_on_body_check_callable = Callable()

	if _on_regular_shot_in_one_timer.is_valid():
		if _local_controller.puck_release_requested.is_connected(_on_regular_shot_in_one_timer):
			_local_controller.puck_release_requested.disconnect(_on_regular_shot_in_one_timer)
		_on_regular_shot_in_one_timer = Callable()

extends GutTest

# ── A PASS IS NOT A SHOT ─────────────────────────────────────────────────────
# The doctrine is Scripts/controllers/CLAUDE.md → "A pass is not a shot while a
# stick can still take it". Feeds fire the real puck_released event, as a pass
# does in play, so the shot reaction and the pass read both see them.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0
const PASS_SPEED: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
const REACH: float = GameRules.DEFAULT_STICK_LENGTH_M

const HIGH_SLOT := Vector3(0.0, 0.0, GOAL_Z + 12.0)
const LOW_SLOT := Vector3(1.0, 0.0, GOAL_Z + 4.0)
const POINT_C := Vector3(0.0, 0.0, GOAL_Z + 18.0)
const BACKDOOR_R := Vector3(2.0, 0.0, GOAL_Z + 3.0)

var _goalie: Node = null
var _puck: Node = null
var _passer: Skater = null
var _receiver: Skater = null
var _ctrl: GoalieController = null
var _h: RefCounted = null
var _pos: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO


func before_each() -> void:
	_goalie = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	var skater_scene: PackedScene = load("res://Scenes/Skater.tscn")
	_passer = skater_scene.instantiate() as Skater
	_receiver = skater_scene.instantiate() as Skater
	_ctrl = GoalieController.new()
	add_child_autofree(_goalie)
	add_child_autofree(_puck)
	add_child_autofree(_passer)
	add_child_autofree(_receiver)
	add_child_autofree(_ctrl)
	_receiver.set_physics_process(false)
	_receiver.set_process(false)
	_h = Harness.new()
	_h.setup(_goalie, _puck, _ctrl, _passer)
	_ctrl.set_skater_getter(func() -> Array: return [_passer, _receiver])


# Settle him on a carrier at `from`, then release the puck at `speed` toward
# `to` through the real puck_released event and march it `metres` along its
# line (default: to a stick length short of `to`, where the receiver plays it).
# Returns whether he went down at any point in the flight.
func _feed(from: Vector3, to: Vector3, speed: float, receiver_state: int,
		metres: float = -1.0) -> bool:
	_ctrl.reset_to_crease()
	_receiver.global_position = to
	_receiver.velocity = Vector3.ZERO
	_receiver.current_shot_state = receiver_state
	_h.settle(from, 240)
	_passer.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	_puck.clear_carrier()
	_vel = (to - from).normalized() * speed
	_pos = from
	_pos.y = _puck.ice_height
	_puck.global_position = _pos
	_puck.apply_release_velocity(_vel)
	_puck.puck_released.emit()
	if metres < 0.0:
		metres = from.distance_to(to) - REACH
	var went_down: bool = false
	for _i: int in int(metres / speed / DT):
		_step_loose()
		went_down = went_down or not _ctrl._sm.is_upright()
	return went_down


func _step_loose() -> void:
	_pos += _vel * DT
	_puck.global_position = _pos
	_puck.linear_velocity = _vel
	_ctrl._physics_process(DT)


func test_a_feed_to_a_stick_in_front_does_not_drop_him() -> void:
	var feeds: Array = [
		[HIGH_SLOT, LOW_SLOT, [10.0, PASS_SPEED, 20.0]],
		[POINT_C, BACKDOOR_R, [10.0, PASS_SPEED]],
	]
	for f: Array in feeds:
		for spd: float in f[2]:
			var down: bool = _feed(f[0], f[1], spd,
					SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
			assert_false(down, "%s -> %s at %.0f m/s: on his feet for the catch"
					% [f[0], f[1], spd])


func test_a_receiver_loaded_for_the_one_timer_still_gets_the_slide() -> void:
	for spd: float in [10.0, PASS_SPEED]:
		var down: bool = _feed(POINT_C, BACKDOOR_R, spd,
				SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK)
		assert_true(down, "%.0f m/s to a loaded back door: pads-first to its angle" % spd)


func test_a_feed_that_slips_past_the_stick_still_drops_him_in_time() -> void:
	# The receiver whiffs: the puck runs on along the same line at the net.
	var to_net: float = HIGH_SLOT.z - GOAL_Z
	_feed(HIGH_SLOT, LOW_SLOT, PASS_SPEED,
			SkaterStateMachine.State.SKATING_WITHOUT_PUCK, 0.0)
	var down_at_m: float = -1.0
	for _i: int in int(to_net / PASS_SPEED / DT):
		_step_loose()
		if not _ctrl._sm.is_upright():
			down_at_m = _pos.z - GOAL_Z
			break
	assert_gt(down_at_m, 0.0, "he went down for the puck the stick let through")
	assert_lt(down_at_m, LOW_SLOT.z - GOAL_Z, "but not before it was past the stick")
	assert_gte(down_at_m / PASS_SPEED, _ctrl.butterfly_drop_speed - DT,
			"with the drop's own time still left before the goal line")


func test_a_shot_through_a_net_front_stick_still_drops_him() -> void:
	# The tip doctrine: no time is left after a doorstep blade, so the shot
	# through it is played as a shot, at the same imminence as with nobody there.
	# Five-hole, so the answer is the full drop rather than a stand-up save.
	var drop_m: Array[float] = []
	for stick: Vector3 in [Vector3(0.0, 0.0, GOAL_Z + 30.0), Vector3(0.3, 0.0, GOAL_Z + 1.6)]:
		_feed(POINT_C, Vector3(0.0, 0.0, GOAL_Z), 25.0,
				SkaterStateMachine.State.SKATING_WITHOUT_PUCK, 0.0)
		_receiver.global_position = stick
		var at: float = -1.0
		for _i: int in int((POINT_C.z - GOAL_Z) / 25.0 / DT):
			_step_loose()
			if not _ctrl._sm.is_upright():
				at = _pos.z - GOAL_Z
				break
		drop_m.append(at)
	assert_gt(drop_m[1], 0.0, "he dropped for the shot past the doorstep stick")
	assert_gt(drop_m[0], 0.0, "and with nobody there")
	assert_almost_eq(drop_m[1], drop_m[0], 0.3, "at the same point as with no stick there")


func test_a_caught_feed_does_not_drop_him_when_the_receiver_drives_the_net() -> void:
	_feed(POINT_C, BACKDOOR_R, 10.0, SkaterStateMachine.State.SKATING_WITHOUT_PUCK)
	assert_true(_ctrl._sm.is_upright())
	_puck.set_carrier(_receiver)
	var drive := Vector3(0.0, 0.0, -8.0)
	_receiver.velocity = drive
	var stayed_up: bool = true
	for _i: int in 24:
		_pos += drive * DT
		_receiver.global_position += drive * DT
		_puck.global_position = _pos
		_puck.linear_velocity = Vector3.ZERO
		_ctrl._physics_process(DT)
		stayed_up = stayed_up and _ctrl._sm.is_upright()
	assert_true(stayed_up, "the read he froze on was a pass, and the carrier is the save now")

extends GutTest

# ── DOWN AFTER A SAVE: WHEN DOES HE GET UP? ──────────────────────────────────
# Staying down used to race every nearby opponent at top speed from a
# standstill, which counts anyone within a stick plus 0.35 s of sprint (4.8 m)
# of a loose rebound as about to touch it. Measured on a pad save from 8 m with
# the rebound sliding out and a man standing 4 m off it, not moving: he never
# got up — 2.5 s and counting — and any later shot met him on the ice. Raced as
# that man is actually moving, he is up in 0.42 s. A man crashing the rebound
# still keeps him down.
#
# And once that man HAS the puck: an undeclared carrier is no shot yet, so he
# rises, but a carrier loading a wrister off the rebound keeps him down — rising
# is 0.35 s he can do nothing in, and the loaded shot is there to punish it.
# Nor does he stand up in the middle of a poke check thrown from the butterfly,
# which he did whenever the pickup was at his doorstep.

const Harness := preload("res://tests/unit/ai/real_goalie_shot_harness.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0

var _h: RefCounted = null
var _ctrl: GoalieController = null
var _puck: Node = null
var _shooter: Skater = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	_puck = load("res://Scenes/Puck.tscn").instantiate()
	_shooter = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [goalie, _puck, _shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(goalie, _puck, _ctrl, _shooter)


# Pad save from 8 m, the rebound sliding out, then `seconds` of play with the
# opponent at `man` moving at `man_vel` (straight, never touching the puck).
# Returns the first second he is upright again, or INF.
func _upright_after(man: Vector3, man_speed_at_puck: float, seconds: float) -> float:
	var spot := Vector3(0.0, 0.0, GOAL_Z + 8.0)
	_h.settle_ready(spot)
	assert_eq(_h.fire_at(spot, Vector3(0.45, 0.0, GOAL_Z), ShotMechanics.ELEVATION_FLAT,
			26.0, 0.0), Harness.SAVE, "precondition: the pad takes the shot")
	assert_false(_ctrl._sm.is_upright(), "precondition: the save put him down")
	var pos: Vector3 = Vector3(_h.last_contact_pos.x, 0.0, _h.last_contact_pos.z)
	var vel: Vector3 = Vector3(1.5, 0.0, 3.0).normalized() * 3.0
	var body: Vector3 = man
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	for i: int in int(seconds / DT):
		vel = vel.normalized() * maxf(vel.length() - DT, 0.0)
		pos += vel * DT
		var to_puck: Vector3 = pos - body
		to_puck.y = 0.0
		var man_vel: Vector3 = Vector3.ZERO
		if man_speed_at_puck > 0.0 and to_puck.length() > 1.6:
			man_vel = to_puck.normalized() * man_speed_at_puck
		body += man_vel * DT
		_shooter.global_position = body
		_shooter.velocity = man_vel
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		if _ctrl._sm.is_upright():
			return float(i + 1) * DT
	return INF


func test_a_man_standing_off_the_rebound_lets_him_up() -> void:
	var up: float = _upright_after(Vector3(-2.0, 0.0, GOAL_Z + 5.0), 0.0, 2.0)
	gut.p("standing man 4 m off the rebound: up at %.2f s" % up)
	assert_lt(up, 1.0, "he is back on his feet inside a second")


func test_a_man_crashing_the_rebound_keeps_him_down() -> void:
	var up: float = _upright_after(Vector3(0.0, 0.0, GOAL_Z + 6.0), 8.0, 0.4)
	assert_true(is_inf(up), "a crasher arriving at speed keeps him sealed")


var _rose_mid_poke: bool = false


# Crasher skates the rebound down, takes it, and holds `state` for `hold_s`.
# Returns whether the goalie ever started back up after the pickup.
func _rose_after_pickup(state: int, hold_s: float) -> bool:
	_rose_mid_poke = false
	var spot := Vector3(0.0, 0.0, GOAL_Z + 8.0)
	_h.settle_ready(spot)
	_h.fire_at(spot, Vector3(0.45, 0.0, GOAL_Z), ShotMechanics.ELEVATION_FLAT, 26.0, 0.0)
	assert_false(_ctrl._sm.is_upright(), "precondition: the save put him down")
	var pos: Vector3 = Vector3(_h.last_contact_pos.x, 0.0, _h.last_contact_pos.z)
	var vel: Vector3 = Vector3(1.5, 0.0, 3.0).normalized() * 3.0
	var body := Vector3(0.0, 0.0, GOAL_Z + 6.0)
	_shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	var held: float = -1.0
	for _i: int in int(2.0 / DT):
		var man_vel := Vector3.ZERO
		if held < 0.0:
			vel = vel.normalized() * maxf(vel.length() - DT, 0.0)
			pos += vel * DT
			var to_puck: Vector3 = pos - body
			to_puck.y = 0.0
			if to_puck.length() <= 0.4:
				held = 0.0
				_puck.set_carrier(_shooter)
				_shooter.current_shot_state = state
			else:
				man_vel = to_puck.normalized() * 7.0
				body += man_vel * DT
		else:
			pos = body
			vel = Vector3.ZERO
			held += DT
			if held >= hold_s:
				return false
		_shooter.global_position = body
		_shooter.velocity = man_vel
		_puck.global_position = pos
		_puck.linear_velocity = vel
		_ctrl._physics_process(DT)
		if held >= 0.0 and _ctrl.stance() == GoalieStateMachine.State.RECOVERING:
			_rose_mid_poke = _ctrl._lunge_active_timer > 0.0
			return true
	assert_true(held >= 0.0, "precondition: the crasher took the puck")
	return false


func test_a_carrier_loading_a_shot_off_the_rebound_keeps_him_down() -> void:
	assert_false(_rose_after_pickup(SkaterStateMachine.State.WRISTER_AIM, 0.6),
			"he does not stand up into a wrister being loaded in front of him")


func test_an_undeclared_carrier_still_lets_him_up() -> void:
	assert_true(_rose_after_pickup(SkaterStateMachine.State.SKATING_WITH_PUCK, 0.6),
			"a carrier who has declared nothing does not pin him down")
	assert_false(_rose_mid_poke, "but he finishes his poke check before getting up")

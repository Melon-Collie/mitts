extends RefCounted

# One world of the real keeper (KeeperController on Goalie.tscn), the real
# puck's server tick and one opposing skater, ticked by hand through a scripted
# play: settled on his spot with the puck, then a wrister from the slot or a
# carry across the slot and a shot. Two worlds made from it play the same play
# tick for tick, which is what the keeper's wire tests and benchmark hold one
# against the other. The caller owns the nodes (`add` adds each to its tree).

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const AIM_X: float = GameRules.NET_HALF_WIDTH - 0.12
const SETTLE_TICKS: int = 150
const TAIL_TICKS: int = 90
const CARRY_AHEAD_M: float = 0.5

enum Play { SLOT_SHOT, CARRY_ACROSS }

var goalie: Goalie = null
var puck: Puck = null
var ctrl: KeeperController = null
var shooter: Skater = null
# The tick the puck first met him on, -1 none yet, and whether he caught it.
var first_contact: int = -1
var caught: bool = false
# Seconds his read of the shot is started back from its release, as the host's
# lag comp once did for a remote shooter; 0, as it does now.
var release_back_date: float = 0.0
var _t: int = 0


func _init(add: Callable) -> void:
	goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	shooter = (load("res://Scenes/Skater.tscn") as PackedScene).instantiate() as Skater
	ctrl = KeeperController.new()
	for n: Node in [goalie, puck, shooter, ctrl]:
		add.call(n)
		n.set_physics_process(false)
		n.set_process(false)
	puck.set_server_mode(true)
	puck.set_goalie_provider(func() -> Array: return [goalie])
	var skaters: Array = [shooter]
	ctrl.set_skater_getter(func() -> Array: return skaters)
	ctrl.setup(goalie, puck, GOAL_Z, true)
	ctrl.apply_skill_profile(GoalieSkillProfile.hard())
	ctrl.reset_to_crease()
	puck.puck_touched_goalie.connect(func(_g: Goalie) -> void: _contact(false))
	puck.puck_caught_by_goalie.connect(func(_g: Goalie) -> void: _contact(true))


static func length(play: int) -> int:
	return SETTLE_TICKS + (150 if play == Play.CARRY_ACROSS else 36) + TAIL_TICKS


# Tick `t` of `play`: the skater and the puck, his tick, the puck's own tick
# while it is loose.
func tick(play: int, t: int) -> void:
	drive(play, t)
	ctrl._physics_process(DT)
	puck_tick()


# The skater and the puck as tick `t` of `play` has them before his tick.
func drive(play: int, t: int) -> void:
	_t = t
	ctrl._view.invalidate()
	_drive(play, t)


# The puck's own tick while it is loose; `before_events`, if valid, called
# between the tick and the contacts it heard.
func puck_tick(before_events: Callable = Callable()) -> void:
	var loose: bool = puck.get_carrier() == null
	if loose:
		goalie._part_velocity_frame = Engine.get_physics_frames() - 1
		goalie.get_collision_part_velocities()
		puck._physics_process(DT)
	if before_events.is_valid():
		before_events.call()
	if loose:
		puck.drain_contact_events()


# The farthest any corner of any of his seated save boxes sits from its place
# in `other`'s.
func box_gap(other: Goalie) -> float:
	var worst: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var h: Vector3 = KeeperGear.half_extents(part)
		var xa: Transform3D = goalie._save_boxes[part].global_transform
		var xb: Transform3D = other._save_boxes[part].global_transform
		for i: int in 8:
			var c := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
			worst = maxf(worst, (xa * c).distance_to(xb * c))
	return worst


func save_state() -> Vector4i:
	return Vector4i(1 if ctrl._chosen else 0, ctrl.save.low, ctrl.save.hand, int(signf(ctrl.save.low_side)))


func _contact(was_caught: bool) -> void:
	if first_contact < 0:
		first_contact = _t
		caught = was_caught


func _drive(play: int, t: int) -> void:
	var a: int = t - SETTLE_TICKS
	match play:
		Play.SLOT_SHOT:
			var spot := Vector3(0.0, 0.0, GOAL_Z + 9.0)
			if a < 36:
				_carry(spot, Vector3.ZERO, SkaterStateMachine.State.WRISTER_AIM if a >= 0
						else SkaterStateMachine.State.SKATING_WITH_PUCK)
			elif a == 36:
				_release(spot, Vector3(AIM_X, 0.0, GOAL_Z), 26.0)
			else:
				shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
		Play.CARRY_ACROSS:
			var from := Vector3(-5.0, 0.0, GOAL_Z + 8.0)
			var vel := Vector3(6.0, 0.0, 0.0)
			if a < 150:
				_carry(from + vel * float(maxi(a, 0)) * DT, vel if a >= 0 else Vector3.ZERO,
						SkaterStateMachine.State.SKATING_WITH_PUCK)
			elif a == 150:
				_release(from + vel * 150.0 * DT, Vector3(-AIM_X, 0.1, GOAL_Z), 26.0)
			else:
				shooter.velocity = Vector3.ZERO
				shooter.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK


func _carry(at: Vector3, vel: Vector3, state: int) -> void:
	shooter.global_position = at
	shooter.velocity = vel
	shooter.current_shot_state = state
	if puck.get_carrier() != shooter:
		puck.set_carrier(shooter)
	puck.global_position = Vector3(at.x, puck.ice_height, at.z - CARRY_AHEAD_M)
	puck.linear_velocity = vel


func _release(at: Vector3, target: Vector3, speed: float) -> void:
	shooter.global_position = at
	shooter.velocity = Vector3.ZERO
	shooter.current_shot_state = SkaterStateMachine.State.FOLLOW_THROUGH
	var from: Vector3 = puck.global_position
	puck.clear_carrier()
	puck.apply_release_velocity(_flight(from, target, speed))
	puck.puck_released.emit()
	if release_back_date > 0.0:
		ctrl.read.start(ctrl.play.primed(), release_back_date, ctrl.screen_delay_for(puck.get_release_velocity()))


# The flight from `from` crossing the goal line at `target` at `speed`.
static func _flight(from: Vector3, target: Vector3, speed: float) -> Vector3:
	var flat := Vector2(target.x - from.x, target.z - from.z)
	var flight_s: float = flat.length() / speed
	var vy: float = 0.0
	if target.y > 0.0:
		vy = (target.y + 0.5 * GameRules.GRAVITY_M_S2 * flight_s * flight_s) / flight_s
	var along: Vector2 = flat.normalized() * speed
	return Vector3(along.x, vy, along.y)

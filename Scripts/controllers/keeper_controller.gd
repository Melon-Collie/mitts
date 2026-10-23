class_name KeeperController
extends GoalieController

# The rebuilt goalie in a match (Scripts/domain/keeper/): the keeper drawn and
# saving in the Goalie node's place, where KeeperPositioning wants him and
# KeeperMotor gets him, the node placed on him every tick and his gear's save
# boxes on its part bodies, so the puck, the skaters and the bots address him
# through the old controller's interface unchanged.
#
# Host and offline only: nothing of his pose goes on the wire, and he makes no
# shot reactions yet. A glove catch is held and covered; every other contact is
# the puck's rebound off the box it struck.
#
# His frame is the net's: the Goalie node's turn at the goal line's centre, x
# across (+ his blocker side), z back into the net, as KeeperPositioning reads.

# The planner's rate, against the 120 Hz tick.
const PLANNER_EVERY: int = 4
# How long he holds a caught puck before he sets it down, where no whistle has
# come for the cover.
const CATCH_HOLD_S: float = 1.0
# Where he sets it: out from his glove side, on the ice.
const SET_DOWN_OUT_M: float = 0.9

var motor := KeeperMotor.new()
var brain := KeeperPositioning.new()

var _keeper: Keeper = null
var _keeper_pose := KeeperPose.new()
var _net := Transform3D.IDENTITY
var _ticks: int = 0
var _last_puck := Vector3.ZERO
# Seconds he has held a caught puck; below zero, none.
var _holding: float = -1.0


func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float, assigned_is_server: bool,
		profile: GoalieSkillProfile = null) -> void:
	super.setup(assigned_goalie, assigned_puck, assigned_goal_line_z, assigned_is_server, profile)
	_net = Transform3D(Basis(Vector3.UP, goalie.get_goalie_rotation_y()), Vector3(0.0, 0.0, assigned_goal_line_z))
	_keeper = Keeper.new()
	goalie.set_stand_in(_keeper)
	for part: int in KeeperGear.PART_COUNT:
		goalie.add_save_box(KeeperGear.save_part(part), _glove_side(part), KeeperGear.half_extents(part))
	_last_puck = puck.global_position
	_place_in_crease()


static func _glove_side(part: int) -> bool:
	return String(KeeperGear.Part.keys()[part]).ends_with("_G")


# On his feet at the top of the crease, square to the ice in front of him.
func _place_in_crease() -> void:
	motor = KeeperMotor.new()
	brain = KeeperPositioning.new()
	motor.z = -KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	_holding = -1.0
	_velocity_x = 0.0
	_velocity_z = 0.0
	_place_body()
	goalie.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if goalie == null or puck == null or not is_server:
		return
	var in_net: Vector3 = _net.affine_inverse() * puck.global_position
	var moved: Vector3 = _net.basis.inverse() * (puck.global_position - _last_puck) / maxf(delta, 1e-4)
	_last_puck = puck.global_position
	if _ticks % PLANNER_EVERY == 0 and _holding < 0.0:
		brain.decide(Vector2(in_net.x, in_net.z), Vector2(moved.x, moved.z), motor)
	_ticks += 1
	var was: Vector3 = goalie.global_position
	motor.step(delta)
	_place_body()
	_velocity_x = (goalie.global_position.x - was.x) / maxf(delta, 1e-4)
	_velocity_z = (goalie.global_position.z - was.z) / maxf(delta, 1e-4)
	if _holding >= 0.0:
		_hold_catch(delta)


# The node on him, his body posed, and his gear's save boxes on it.
func _place_body() -> void:
	motor.pose(_keeper_pose)
	_keeper.apply_pose(_keeper_pose)
	goalie.global_transform = _net * Transform3D(Basis(Vector3.UP, motor.yaw), Vector3(motor.x, 0.0, motor.z))
	for part: int in KeeperGear.PART_COUNT:
		goalie.seat_save_box(part, KeeperGear.box(_keeper.skeleton, part))


func is_butterfly() -> bool:
	return motor.rest != KeeperRoute.Rest.FEET


func reset_to_crease() -> void:
	if puck != null:
		puck.motion_pinned = false
	goalie.set_stick_collision_enabled(true)
	_place_in_crease()


func fill_state(s: GoalieNetworkState) -> void:
	super.fill_state(s)
	s.state_enum = _stance() as int


# His rest as the old goalie's stances, for the bots' read of him.
func _stance() -> GoalieStateMachine.State:
	match motor.rest:
		KeeperRoute.Rest.DOWN:
			return GoalieStateMachine.State.BUTTERFLY
		KeeperRoute.Rest.POST:
			return GoalieStateMachine.State.RVH_LEFT if motor.post.side < 0.0 \
					else GoalieStateMachine.State.RVH_RIGHT
	return GoalieStateMachine.State.READY


# No shot reactions yet: a release is read by where he stands.
func _on_puck_released() -> void:
	pass


func _on_puck_contact(contacted: Goalie) -> void:
	if contacted == goalie:
		_last_save_time = float(Time.get_ticks_msec()) * 0.001


# Caught: into the glove and covered for the whistle.
func _on_puck_caught(contacted: Goalie) -> void:
	if contacted != goalie or not is_server or _holding >= 0.0:
		return
	if puck.pickup_locked or puck.get_carrier() != null:
		return
	_holding = 0.0
	puck.pickup_locked = true
	puck.motion_pinned = true
	puck.set_puck_velocity(Vector3.ZERO)
	puck_covered.emit(team_id)


# Held in the glove; with no whistle for it, set down out from his glove side.
func _hold_catch(delta: float) -> void:
	puck.set_puck_position(goalie.get_glove_world_position())
	_holding += delta
	if _holding < CATCH_HOLD_S:
		return
	_holding = -1.0
	var out: Vector3 = _net * Vector3(motor.x - SET_DOWN_OUT_M, 0.0, motor.z)
	puck.set_puck_position(Vector3(out.x, puck.ice_height, out.z))
	puck.set_puck_velocity(Vector3.ZERO)
	puck.motion_pinned = false
	puck.pickup_locked = false

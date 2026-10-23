class_name KeeperController
extends GoalieController

# The rebuilt goalie in a match (Scripts/domain/keeper/): the keeper drawn and
# saving in the Goalie node's place, where KeeperPositioning wants him and
# KeeperMotor gets him, the node placed on him every tick and his gear's save
# boxes on its part bodies, so the puck, the skaters and the bots address him
# through the old controller's interface unchanged.
#
# Host and offline only: nothing of his pose goes on the wire. A shot is read
# from its release (KeeperShotRead, restarted by a tip) and saved with the
# save his gear says covers it (KeeperSave, its low half through the motor),
# held until the shot is over: it meets him, goes past, stops coming, or is
# picked up. A glove catch is held and covered; every other contact is the
# puck's rebound off the box it struck.
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
var read := KeeperShotRead.new()
var play := KeeperPlayRead.new()
var save := KeeperSave.new()

var _keeper: Keeper = null
var _keeper_pose := KeeperPose.new()
var _net := Transform3D.IDENTITY
var _ticks: int = 0
var _last_velocity := Vector3.ZERO
# The skaters in the net's frame, refilled for each read: an opposing
# carrier's teammates off the puck, every opponent, his own teammates.
var _attackers := PackedVector2Array()
var _opponents := PackedVector2Array()
var _defenders := PackedVector2Array()
# Seconds he has held a caught puck; below zero, none.
var _holding: float = -1.0
var _profile: GoalieSkillProfile = GoalieSkillProfile.hard()
# Whether the shot being read has had its save chosen.
var _chosen: bool = false


func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float, assigned_is_server: bool,
		profile: GoalieSkillProfile = null) -> void:
	super.setup(assigned_goalie, assigned_puck, assigned_goal_line_z, assigned_is_server, profile)
	if profile != null:
		_profile = profile
	if is_server:
		puck.puck_touched_loose.connect(_on_puck_touched_loose)
	_net = Transform3D(Basis(Vector3.UP, goalie.get_goalie_rotation_y()), Vector3(0.0, 0.0, assigned_goal_line_z))
	_keeper = Keeper.new()
	goalie.set_stand_in(_keeper)
	for part: int in KeeperGear.PART_COUNT:
		goalie.add_save_box(KeeperGear.save_part(part), _glove_side(part), KeeperGear.half_extents(part))
	_place_in_crease()


static func _glove_side(part: int) -> bool:
	return String(KeeperGear.Part.keys()[part]).ends_with("_G")


func apply_skill_profile(profile: GoalieSkillProfile) -> void:
	super.apply_skill_profile(profile)
	if profile != null:
		_profile = profile
		_tier()


# The tier's reads and speeds onto the read, the save and the motor's save;
# and no reach to clear a loose puck with, since he does not take one yet.
func _tier() -> void:
	clear_reach = 0.0
	read.leg_delay_s = _profile.reaction_delay_s
	read.primed_delay_s = _profile.prearmed_reaction_delay_s
	play.primed_delay_s = _profile.prearmed_reaction_delay_s
	play.delay_s = _profile.reaction_delay_s
	read.arm_delay_s = _profile.arm_reaction_delay_s
	save.glove_speed_m_s = _profile.glove_react_max_speed_mps
	save.blocker_speed_m_s = _profile.blocker_react_max_speed_mps
	save.drop_s = _profile.butterfly_drop_s
	motor.save_move.drop_s = _profile.butterfly_drop_s


# On his feet at the top of the crease, square to the ice in front of him.
func _place_in_crease() -> void:
	motor = KeeperMotor.new()
	brain = KeeperPositioning.new()
	read = KeeperShotRead.new()
	play.reset()
	brain.play = play
	save = KeeperSave.new()
	_chosen = false
	_tier()
	motor.z = -KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	_holding = -1.0
	_velocity_x = 0.0
	_velocity_z = 0.0
	_last_velocity = Vector3.ZERO
	_keeper.acceleration = Vector3.ZERO
	_place_body()
	goalie.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if goalie == null or puck == null or not is_server:
		return
	var in_net: Vector3 = _net.affine_inverse() * puck.global_position
	_read_play(delta, in_net)
	read.step(delta, in_net, _net.basis.inverse() * puck.get_puck_velocity())
	_save_the_shot()
	if _ticks % PLANNER_EVERY == 0 and _holding < 0.0 and not _chosen:
		_read_receivers()
		brain.decide(play.puck, play.motion, motor)
	_ticks += 1
	var was: Vector3 = goalie.global_position
	motor.step(delta)
	_place_body()
	_velocity_x = (goalie.global_position.x - was.x) / maxf(delta, 1e-4)
	_velocity_z = (goalie.global_position.z - was.z) / maxf(delta, 1e-4)
	var velocity := Vector3(_velocity_x, 0.0, _velocity_z)
	_keeper.acceleration = _keeper.global_basis.orthonormalized().inverse() \
			* (velocity - _last_velocity) / maxf(delta, 1e-4)
	_last_velocity = velocity
	if _holding >= 0.0:
		_hold_catch(delta)


# His look at the play: the carrier's body moving it, or the loose puck's own
# motion. A shot's flight reaches the brain no sooner than his legs read it, and
# by then the brain is resting on the save.
func _read_play(delta: float, in_net: Vector3) -> void:
	var carrier: Skater = puck.get_carrier()
	var moving: Vector3 = _net.basis.inverse() * (carrier.velocity if carrier != null else puck.get_puck_velocity())
	var holder: Vector2 = KeeperPlayRead.NO_CARRIER
	if carrier != null:
		var body: Vector3 = _net.affine_inverse() * carrier.global_position
		holder = Vector2(body.x, body.z)
	# A wind-up shows as the opposing carrier holding the puck on his blade for
	# a shot: the wrister's address, the slapper's charge, the one-timer's.
	play.theirs = carrier != null and (team_id == -1 or carrier.get_team_id() != team_id)
	var winding: bool = play.theirs and SkaterStateMachine.state_pins_puck(carrier.current_shot_state)
	play.step(delta, Vector2(in_net.x, in_net.z), Vector2(moving.x, moving.z), winding, holder)


# Who an opposing carrier could pass to, through which lanes; and which of
# them a puck he sees loose goes to.
func _read_receivers() -> void:
	_attackers.clear()
	_defenders.clear()
	_opponents.clear()
	_ensure_view()
	var to_net: Transform3D = _net.affine_inverse()
	for at: Vector3 in _view.opponents:
		var mine: Vector3 = to_net * at
		_opponents.append(Vector2(mine.x, mine.z))
	var carrier: Skater = puck.get_carrier()
	if carrier != null and (team_id == -1 or carrier.get_team_id() != team_id):
		for at: Vector3 in _view.off_puck_opponents:
			var mine: Vector3 = to_net * at
			_attackers.append(Vector2(mine.x, mine.z))
		for at: Vector3 in _view.teammates:
			var mine: Vector3 = to_net * at
			_defenders.append(Vector2(mine.x, mine.z))
	play.read_receivers(_attackers, _defenders)
	play.read_pass(_opponents)


# Once his legs have read a shot on net, the save, the brain resting until it
# is over; while it is under way, its end once the shot is over.
func _save_the_shot() -> void:
	if not read.reading():
		return
	var over: bool = read.time_to_line() == INF or puck.get_carrier() != null \
			or (_chosen and read.age > save.impact_s + _profile.arm_reaction_delay_s)
	if over:
		_end_save()
		return
	if _chosen or not read.legs_read():
		return
	if not read.on_net():
		read.stop()
		return
	_chosen = true
	save.choose(read, motor, _keeper.skeleton.mirrored)
	if save.low != KeeperSaveMove.Low.NONE:
		motor.save(save.low, save.low_side)
	elif motor.rest == KeeperRoute.Rest.FEET:
		# Set for it where he is: the hand was aimed from here.
		motor.go_to(Vector2(motor.x, motor.z), motor.route.facing)


func _end_save() -> void:
	read.stop()
	_chosen = false
	save.release()
	motor.end_save()


# The node on him, his body posed with the save's hand over it, and his gear's
# save boxes on it, where it moved.
func _place_body() -> void:
	motor.pose(_keeper_pose)
	save.step(get_physics_process_delta_time(), read.arms_read(), _keeper_pose)
	save.overlay(_keeper_pose)
	goalie.global_transform = _net * Transform3D(Basis(Vector3.UP, motor.yaw), Vector3(motor.x, 0.0, motor.z))
	_report_state()
	if not _keeper.apply_pose(_keeper_pose):
		return
	for part: int in KeeperGear.PART_COUNT:
		goalie.seat_save_box(part, KeeperGear.box(_keeper.skeleton, part))


# The old goalie's reads of him, kept true for whatever still asks them (the
# shot log's context, the scoreboard's harness): his stance in the old state
# machine, set without its transition handler, which is the old tick's; and
# where he stands as its lateral x and challenge radius.
func _report_state() -> void:
	_sm.current = _stance()
	_current_x = goalie.global_position.x
	_current_depth = GoalieBehaviorRules.threat_distance_to_goal(goalie.global_position, _goal_line_z,
			_goal_center_x)


func is_butterfly() -> bool:
	return motor.rest != KeeperRoute.Rest.FEET or _down_in_a_save()


func _down_in_a_save() -> bool:
	return motor.save_move.state != KeeperSaveMove.State.NONE and motor.save_move.rests_down()


func reset_to_crease() -> void:
	if puck != null:
		puck.motion_pinned = false
	goalie.set_stick_collision_enabled(true)
	_place_in_crease()


func fill_state(s: GoalieNetworkState) -> void:
	super.fill_state(s)
	s.state_enum = _stance() as int


# His rest as the old goalie's stances, for the bots' read of him: down in a
# low save that rests him there as in the butterfly.
func _stance() -> GoalieStateMachine.State:
	if motor.rest == KeeperRoute.Rest.FEET and _down_in_a_save():
		return GoalieStateMachine.State.BUTTERFLY
	match motor.rest:
		KeeperRoute.Rest.DOWN:
			return GoalieStateMachine.State.BUTTERFLY
		KeeperRoute.Rest.POST:
			return GoalieStateMachine.State.RVH_LEFT if motor.post.side < 0.0 \
					else GoalieStateMachine.State.RVH_RIGHT
	return GoalieStateMachine.State.READY


func _on_puck_released() -> void:
	_end_save()
	read.start(play.primed())


# A tip or a deflection: a new shot to read from the start.
func _on_puck_touched_loose(_skater: Skater) -> void:
	if read.reading():
		_end_save()
		read.start()


# The puck off the boards, a post or the net: the shot is over.
func _on_reaction_resolved() -> void:
	_end_save()


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

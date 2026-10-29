class_name KeeperController
extends GoalieController

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# The rebuilt goalie in a match (Scripts/domain/keeper/): the keeper drawn and
# saving in the Goalie node's place, where KeeperPositioning wants him and
# KeeperMotor gets him, the node placed on him every tick and his gear's save
# boxes on its part bodies, so the puck, the skaters and the bots address him
# through GoalieController's interface.
#
# He plays on the host (and offline); his pose goes on the wire, and a client
# or a replay poses him from it with no AI of its own. A shot is read
# from its release (KeeperShotRead, restarted by a tip) and saved with the
# save he is taught for where it passes him (KeeperSave, its low half through
# the motor), held until it is there and he has read the shot is over (it
# meets him, goes past, stops coming), or it is picked up; a shot that beat
# his read answered all the same once he has read it. His eyes follow the puck
# throughout (KeeperLook). A catch, in the glove or on his chest, is held and
# covered, him frozen where he made it; every other contact is the puck's
# rebound off the box it struck. A loose puck he can reach he covers
# (KeeperCover): down over it, the glove onto it, live until the glove is on
# it; one a push away that no opponent can get to first he skates to and
# covers (KeeperFetch).
#
# His frame is the net's: the Goalie node's turn at the goal line's centre, x
# across (+ his blocker side), z back into the net, as KeeperPositioning reads.

# Ticks between the planner's runs: 30 Hz.
const PLANNER_EVERY: int = _PhysicsConstants.PHYSICS_TICK / 30
# How long he holds a caught or covered puck before he plays it out, where no
# whistle has come for it (GameRules.whistles_a_cover).
const CATCH_HOLD_S: float = 1.0
# Where he sets it: out from his glove side, on the ice; and how hard he sweeps
# it on toward that corner, out of his own reach so he does not cover it again.
const SET_DOWN_OUT_M: float = 0.9
const PLAY_OUT_M_S: float = 6.0

var motor := KeeperMotor.new()
var brain := KeeperPositioning.new()
var read := KeeperShotRead.new()
var play := KeeperPlayRead.new()
var save := KeeperSave.new()
var cover := KeeperCover.new()
var look := KeeperLook.new()
var fetch := KeeperFetch.new()

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
# Whether the shot being read has had its save chosen; whether he is covering
# a loose puck.
var _chosen: bool = false
var _covering: bool = false
# Whether he is skating to a loose puck to cover it (KeeperFetch).
var _fetching: bool = false
# Skating onto the line of a shot he has read before he sets for its save.
var _squaring: bool = false
# Seconds into the read the save was chosen, and the shot over; below zero, not
# yet.
var _chosen_at: float = -1.0
var _over_at: float = -1.0
# Whether the shot being read has hit him.
var _felt: bool = false
# Where a puck caught on his chest is held, in the chest protector's frame;
# INF none (a glove catch is held in the glove).
var _chest_held := Vector3.INF


func setup(assigned_goalie: Goalie, assigned_puck: Puck, assigned_goal_line_z: float, assigned_is_server: bool,
		profile: GoalieSkillProfile = null) -> void:
	super.setup(assigned_goalie, assigned_puck, assigned_goal_line_z, assigned_is_server, profile)
	if profile != null:
		_profile = profile
	if is_server:
		puck.puck_touched_loose.connect(_on_puck_touched_loose)
		goalie.chest_contact = _chest_contact
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


# The tier's reads and speeds onto the read, the save and the motor's save.
func _tier() -> void:
	read.leg_delay_s = _profile.reaction_delay_s
	read.primed_delay_s = _profile.prearmed_reaction_delay_s
	play.primed_delay_s = _profile.prearmed_reaction_delay_s
	play.delay_s = _profile.reaction_delay_s
	save.glove_speed_m_s = _profile.glove_react_max_speed_mps
	save.blocker_speed_m_s = _profile.blocker_react_max_speed_mps
	save.drop_s = _profile.butterfly_drop_s
	motor.save_move.drop_s = _profile.butterfly_drop_s
	cover.glove_speed_m_s = _profile.glove_react_max_speed_mps


# On his feet at the top of the crease, square to the ice in front of him.
func _place_in_crease() -> void:
	motor = KeeperMotor.new()
	brain = KeeperPositioning.new()
	read = KeeperShotRead.new()
	play.reset()
	brain.play = play
	save = KeeperSave.new()
	cover = KeeperCover.new()
	look.reset()
	_ticks = 0
	_chosen = false
	_covering = false
	_fetching = false
	_squaring = false
	_chosen_at = -1.0
	_over_at = -1.0
	_felt = false
	_tier()
	motor.z = -KeeperPositioning.crease_edge(Vector2(0.0, -1.0))
	_holding = -1.0
	_chest_held = Vector3.INF
	_velocity_x = 0.0
	_velocity_z = 0.0
	_last_velocity = Vector3.ZERO
	_keeper.acceleration = Vector3.ZERO
	_place_body()
	goalie.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if goalie == null or puck == null:
		return
	# A back-date is for the release it was set before, never a later one.
	_pending_reaction_back_date = 0.0
	var was: Vector3 = goalie.global_position
	var t0: int = Time.get_ticks_usec()
	if is_server:
		_play(delta)
	else:
		if _rejoin_blend_elapsed >= 0.0:
			_rejoin_blend_elapsed += delta
		_interpolate_and_apply()
	_measure_motion(was, delta)
	if is_server and _holding >= 0.0:
		_hold_catch(delta)
	HostCostProbe.record(HostCostProbe.Section.GOALIE_PHYS, Time.get_ticks_usec() - t0)


# His tick on the host: what he reads of the play and the shot, the save and
# the cover, the brain at the planner's rate, and the motor moving him.
func _play(delta: float) -> void:
	var in_net: Vector3 = _net.affine_inverse() * puck.global_position
	_read_play(delta, in_net)
	read.step(delta, in_net, _net.basis.inverse() * puck.get_puck_velocity())
	_save_the_shot()
	_cover_the_puck(in_net)
	if _ticks % PLANNER_EVERY == 0 and _holding < 0.0 and not _chosen and not _covering and not _squaring:
		_read_receivers()
		_fetch_the_puck(in_net)
		if not _fetching:
			brain.decide(play.puck, play.motion, motor)
	_ticks += 1
	motor.step(delta)
	_place_body()


# His velocity from where the node was a tick ago, and his acceleration in his
# own frame from it, which his jersey's tail swings to.
func _measure_motion(was: Vector3, delta: float) -> void:
	_velocity_x = (goalie.global_position.x - was.x) / maxf(delta, 1e-4)
	_velocity_z = (goalie.global_position.z - was.z) / maxf(delta, 1e-4)
	var velocity := Vector3(_velocity_x, 0.0, _velocity_z)
	_keeper.acceleration = _keeper.global_basis.orthonormalized().inverse() \
			* (velocity - _last_velocity) / maxf(delta, 1e-4)
	_last_velocity = velocity


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
	var theirs: bool = carrier != null and (team_id == -1 or carrier.get_team_id() != team_id)
	var winding: bool = theirs and SkaterStateMachine.state_pins_puck(carrier.current_shot_state)
	play.eyes = Vector2(motor.x, motor.z)
	play.step(delta, Vector2(in_net.x, in_net.z), Vector2(moving.x, moving.z), winding, holder, theirs)


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
# is over. A save under way goes on until it is there, and he lets it go once
# it is and the shot is over: at once for a puck that hit him, which he feels,
# as goalies are taught to start their recovery the moment it does; his leg
# read after it for one that went by him (past, off the iron or boards,
# stopped), which he has to see. So one made too late is still seen made. A shot over before he has
# read it at all he answers once he has: the save for the flight he saw leave
# the stick, however late. One chosen where he could not go down (mid-slide)
# is chosen again once he can, while the puck is still coming. One with time to
# spare he first skates onto the line of (`KeeperSave.square_up_spot`).
func _save_the_shot() -> void:
	if not read.reading():
		_squaring = false
		return
	if puck.get_carrier() != null:
		_end_save()
		return
	if _over_at < 0.0 and (read.time_to_line() == INF or (_chosen and read.age > _chosen_at + save.impact_s)):
		_over_at = read.age
	if _chosen:
		if not save.lows_open and _over_at < 0.0 and (motor.can_save(false) or motor.can_save(true)):
			_choose()
			return
		# A puck off him he feels at once; one by him he has to see.
		var noticed: float = 0.0 if _felt else read.leg_delay_s
		if _over_at >= 0.0 and read.age >= maxf(_over_at, _chosen_at + save.ready_s) + noticed:
			_end_save()
		return
	if not read.legs_read():
		return
	if _over_at >= 0.0:
		read.rewind()
	if not read.on_net():
		read.stop()
		return
	if _square_up():
		return
	_chosen = true
	_choose()


# Onto the line of a shot with time to spare, on his feet, square to it; false
# once there, or once there is no time left to move before he sets.
func _square_up() -> bool:
	_squaring = false
	if motor.rest != KeeperRoute.Rest.FEET:
		return false
	var spot: Vector2 = KeeperSave.square_up_spot(read, motor, save.drop_s * motor.fall)
	if spot == Vector2.INF:
		return false
	_squaring = true
	motor.go_to(spot, KeeperPositioning.facing(spot, Vector2(read.at.x, read.at.z)), KeeperRoute.Rest.FEET,
			Vector2.ZERO, true)
	return true


func _choose() -> void:
	_chosen_at = read.age
	save.choose(read, motor, _keeper.skeleton.mirrored)
	if save.low != KeeperSaveMove.Low.NONE:
		motor.save(save.low, save.low_side)
	elif motor.rest == KeeperRoute.Rest.FEET:
		# Set for it where he is: the hand was aimed from here.
		motor.go_to(Vector2(motor.x, motor.z), motor.route.facing)


func _end_save() -> void:
	read.stop()
	_squaring = false
	_chosen = false
	_chosen_at = -1.0
	_over_at = -1.0
	_felt = false
	save.release()
	motor.end_save()


# A loose puck he can reach, with no shot to save: down over it and the glove
# onto it, the glove following it as it slides; secured once the glove is on
# it with the puck under it. Until then it is live, and a puck poked out of his
# reach ends the cover.
func _cover_the_puck(in_net: Vector3) -> void:
	# Skating to one, he stops on his spot before he goes down on it.
	var coverable: bool = _holding < 0.0 and not read.reading() and puck.get_carrier() == null \
			and not puck.pickup_locked and (_covering or not _fetching or motor.is_idle()) \
			and cover.plan(in_net, _net.basis.inverse() * puck.get_puck_velocity(), motor, _keeper.skeleton.mirrored)
	if not coverable:
		if _covering:
			_covering = false
			save.release()
			motor.end_save()
		return
	if not _covering:
		_covering = true
		if motor.can_save(false):
			motor.save(KeeperSaveMove.Low.BUTTERFLY, signf(cover.target.x))
	save.cover(cover.target, cover.lean)
	if save.hand_there() and _glove_on_puck():
		_covering = false
		_secure()


# A loose puck near him that no opponent will get to first: skated to, square
# to it, until it is in his reach to cover (KeeperFetch).
func _fetch_the_puck(in_net: Vector3) -> void:
	var v: Vector3 = _net.basis.inverse() * puck.get_puck_velocity()
	_fetching = not read.reading() and puck.get_carrier() == null and not puck.pickup_locked \
			and fetch.plan(Vector2(in_net.x, in_net.z), Vector2(v.x, v.z), motor, _opponents, play.delay_s, _fetching)
	if _fetching:
		motor.go_to(fetch.spot, fetch.facing, KeeperRoute.Rest.FEET, Vector2.ZERO, true)


# The puck under the glove's palm, across the ice and no higher than the glove.
func _glove_on_puck() -> bool:
	var glove: Vector3 = goalie.get_glove_world_position()
	var at: Vector3 = puck.global_position
	return Vector2(glove.x - at.x, glove.z - at.z).length() <= KeeperCover.PIN_M \
			and at.y <= glove.y + KeeperGear.half_extents(KeeperGear.Part.GLOVE).y


# The node on him, his body posed with the save's hand over it and his eyes on
# the puck, and his gear's save boxes on it, where it moved.
func _place_body() -> void:
	var dt: float = get_physics_process_delta_time()
	motor.pose(_keeper_pose)
	save.step(dt, read.legs_read(), _keeper_pose)
	save.overlay(_keeper_pose)
	look.step(dt, _keeper_pose, _in_his_space(puck.global_position))
	goalie.global_transform = _net * Transform3D(Basis(Vector3.UP, motor.yaw), Vector3(motor.x, 0.0, motor.z))
	_report_state()
	_seat(_keeper_pose)


# `at` in the rink, in his authored space (KeeperPose's): from where the motor
# has him, turned his way, reflected for a right-catcher.
func _in_his_space(at: Vector3) -> Vector3:
	var mine: Vector3 = Basis(Vector3.UP, motor.yaw).inverse() * (_net.affine_inverse() * at - Vector3(motor.x, 0.0, motor.z))
	if _keeper.skeleton.mirrored:
		mine.x = -mine.x
	return mine


# His body posed from `p`, and his gear's save boxes on it where it moved.
func _seat(p: KeeperPose) -> void:
	if not _keeper.apply_pose(p):
		return
	for part: int in KeeperGear.PART_COUNT:
		goalie.seat_save_box(part, KeeperGear.box(_keeper.skeleton, part))


# On a client, the snapshots' poses blended as their roots are
# (GoalieController._interpolate_and_apply).
func _lerp_goalie_state(from_s: GoalieNetworkState, to_s: GoalieNetworkState, t: float) -> GoalieNetworkState:
	var r: GoalieNetworkState = super._lerp_goalie_state(from_s, to_s, t)
	r.pose.blend(from_s.pose, to_s.pose, t)
	return r


func _apply_interpolated(s: GoalieNetworkState) -> void:
	_current_x = s.position_x
	_follow(s)


func apply_replay_state(state: GoalieNetworkState, _delta: float) -> void:
	_follow(state)


# Him as a snapshot has him: the node where it was, his body posed from it and
# his gear's save boxes on that body, so the puck meets what the host's met.
func _follow(s: GoalieNetworkState) -> void:
	_sm.current = s.state_enum as GoalieStateMachine.State
	goalie.set_goalie_position(s.position_x, s.position_z)
	goalie.set_goalie_rotation_y(s.rotation_y)
	_seat(s.pose)


# Where he stands as the shot log and the bots read him: his stance as the
# wire's, his lateral x and his challenge radius.
func _report_state() -> void:
	_sm.current = _stance()
	_current_x = goalie.global_position.x
	_current_depth = Vector2(goalie.global_position.x - _goal_center_x,
			goalie.global_position.z - _goal_line_z).length()


func is_butterfly() -> bool:
	return motor.rest != KeeperRoute.Rest.FEET or _down_in_a_save()


func _down_in_a_save() -> bool:
	return motor.save_move.state != KeeperSaveMove.State.NONE and motor.save_move.rests_down()


func reset_to_crease() -> void:
	if puck != null:
		puck.motion_pinned = false
	_place_in_crease()


# Set in his crease, his stance's five-hole open between the pads.
func snap_to_standing_pose(_open_five_hole: bool = false) -> void:
	reset_to_crease()


func fill_state(s: GoalieNetworkState) -> void:
	super.fill_state(s)
	s.state_enum = _stance() as int
	s.pose.copy_from(_keeper_pose)


# His rest as the wire's stances, for the bots' read of him: down in a low
# save that rests him there as in the butterfly.
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


# A remote shooter's release is read from when he saw it leave, the back-date
# GameManager sets just before it (Scripts/networking/CLAUDE.md, shot lag comp).
func _on_puck_released() -> void:
	_end_save()
	read.start(play.primed(), _pending_reaction_back_date)
	_pending_reaction_back_date = 0.0


# A tip or a deflection: a new shot to read from the start.
func _on_puck_touched_loose(_skater: Skater) -> void:
	if read.reading():
		_end_save()
		read.start()


# The puck off the boards, a post or the net: the shot is over.
func _on_reaction_resolved() -> void:
	if read.reading() and _over_at < 0.0:
		_over_at = read.age


func _on_puck_contact(contacted: Goalie) -> void:
	if contacted == goalie:
		_last_save_time = float(Time.get_ticks_msec()) * 0.001
		if read.reading():
			_felt = true
			if _over_at < 0.0:
				_over_at = read.age


# Goalie.chest_contact: a contact on his chest's save part, given the puck's
# incoming velocity, the contact point and normal, the struck part's velocity
# and the shared rule's result, which it rewrites. Caught at the logo when his
# arms close on it before it comes off him (KeeperChestTrap); anywhere
# else, or too hard for that, it comes off the foam as any rebound does rather
# than dying on him whatever its pace.
func _chest_contact(incoming: Vector3, point: Vector3, normal: Vector3, surface: Vector3,
		result: GoalieSaveRules.ContactResult) -> void:
	if not result.trapped:
		return
	result.trapped = false
	var mine: Vector3 = goalie.global_transform.affine_inverse() * point
	var reach_s: float = minf(goalie.get_glove_world_position().distance_to(point) / save.glove_speed_m_s,
			goalie.get_blocker_world_position().distance_to(point) / save.blocker_speed_m_s)
	if KeeperChestTrap.at_logo(_keeper.skeleton, mine) and KeeperChestTrap.closes_on((surface - incoming).dot(normal), reach_s):
		result.velocity = Vector3.ZERO
		result.caught = true
		_chest_held = KeeperGear.box(_keeper.skeleton, KeeperGear.Part.CHEST).affine_inverse() * mine
		return
	result.velocity = GoalieSaveRules.rebound_velocity(incoming, GoalieSaveRules.SavePart.CHEST, normal, surface)


# Caught: in the glove, or held to his chest with the glove come over it; and
# covered for the whistle.
func _on_puck_caught(contacted: Goalie) -> void:
	if contacted != goalie or not is_server or _holding >= 0.0:
		_chest_held = Vector3.INF
		return
	if puck.pickup_locked or puck.get_carrier() != null:
		_chest_held = Vector3.INF
		return
	_secure()
	if _chest_held != Vector3.INF:
		var chest: Transform3D = KeeperGear.box(_keeper.skeleton, KeeperGear.Part.CHEST)
		var over: Vector3 = chest * _chest_held - chest.basis.z.normalized() * KeeperChestTrap.GLOVE_OFF_CHEST_M
		if _keeper.skeleton.mirrored:
			over.x = -over.x
		save.trap(over)


# Where the puck he holds is: in his glove, or on his chest where it was caught.
func _held_at() -> Vector3:
	if _chest_held == Vector3.INF:
		return goalie.get_glove_world_position()
	return goalie.global_transform * (KeeperGear.box(_keeper.skeleton, KeeperGear.Part.CHEST) * _chest_held)


# Under the glove, dead, and covered for the whistle, him frozen where he holds
# it.
func _secure() -> void:
	_holding = 0.0
	motor.freeze()
	puck.pickup_locked = true
	puck.motion_pinned = true
	puck.set_puck_velocity(Vector3.ZERO)
	puck_covered.emit(team_id)


# Held in the glove or to his chest; with no whistle for it, set down out from
# his glove side and swept on toward that corner.
func _hold_catch(delta: float) -> void:
	puck.set_puck_position(_held_at())
	_holding += delta
	if _holding < CATCH_HOLD_S:
		return
	_holding = -1.0
	_chest_held = Vector3.INF
	var glove_side: float = 1.0 if _keeper.skeleton.mirrored else -1.0
	var out: Vector3 = _net * Vector3(motor.x + glove_side * SET_DOWN_OUT_M, 0.0, motor.z)
	puck.set_puck_position(Vector3(out.x, puck.ice_height, out.z))
	puck.set_puck_velocity(_net.basis * Vector3(glove_side, 0.0, -0.5).normalized() * PLAY_OUT_M_S)
	puck.motion_pinned = false
	puck.pickup_locked = false
	motor.thaw()
	save.release()
	motor.end_save()

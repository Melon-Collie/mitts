class_name GoalieNetworkState

# Goalie wire state — populated on the host each tick and broadcast as part of
# the world snapshot.
#
#   - Root: position_x/z + rotation_y carry the Goalie node's world placement;
#     velocity_x/z feed the client's dead-reckon past the newest sample, and
#     state_enum + five_hole_openness are read back through the accessors below
#     (the bot shot model's stance read). Clients run no goalie AI of their own.
#   - Pose: the keeper's pose (KeeperPose), every target his skeleton solves
#     from, so a client and a replay rebuild the body the host saved with.
var position_x: float = 0.0
var position_z: float = 0.0
var rotation_y: float = 0.0
var state_enum: int = 0
var five_hole_openness: float = 0.0
var velocity_x: float = 0.0
var velocity_z: float = 0.0
var pose := KeeperPose.new()

var host_timestamp: float = 0.0  # host-only, not serialized


# Pads ON the ice (the butterfly, the RVH, the covers, and the old goalie's
# down stances the wire still names) vs on his feet. state_enum is written as
# `GoalieStateMachine.State as int` (KeeperController._stance); this accessor
# is the one place that mapping is interpreted off the wire, so readers (the
# bots' shot model) never hand-roll the enum split.
func is_down() -> bool:
	return state_enum == GoalieStateMachine.State.BUTTERFLY as int \
			or state_enum == GoalieStateMachine.State.SLIDING as int \
			or state_enum == GoalieStateMachine.State.RVH_LEFT as int \
			or state_enum == GoalieStateMachine.State.RVH_RIGHT as int \
			or state_enum == GoalieStateMachine.State.COILING as int \
			or state_enum == GoalieStateMachine.State.VH_LEFT as int \
			or state_enum == GoalieStateMachine.State.VH_RIGHT as int \
			or state_enum == GoalieStateMachine.State.COVERING as int \
			or state_enum == GoalieStateMachine.State.CATCHING_DOWN as int


# World-x sign (±1.0) of the post a seal (RVH, and the old goalie's VH) is
# committed to; 0.0 in any other state. LEFT/RIGHT in the state names are the
# goalie's own, so his LEFT sits at world-x sign(−goal_z). Callers pass the z of
# the goal this goalie guards (the shooter's attacking_goal.z). Like is_down(),
# the one place the state_enum ↔ world mapping is interpreted off the wire.
func post_seal_x_sign(guarded_goal_z: float) -> float:
	var left_sign: float = signf(-guarded_goal_z)
	if state_enum == GoalieStateMachine.State.VH_LEFT as int \
			or state_enum == GoalieStateMachine.State.RVH_LEFT as int:
		return left_sign
	if state_enum == GoalieStateMachine.State.VH_RIGHT as int \
			or state_enum == GoalieStateMachine.State.RVH_RIGHT as int:
		return -left_sign
	return 0.0


func copy_from(s: GoalieNetworkState) -> void:
	position_x = s.position_x
	position_z = s.position_z
	rotation_y = s.rotation_y
	state_enum = s.state_enum
	five_hole_openness = s.five_hole_openness
	velocity_x = s.velocity_x
	velocity_z = s.velocity_z
	pose.copy_from(s.pose)
	host_timestamp = s.host_timestamp

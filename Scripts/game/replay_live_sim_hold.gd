class_name ReplayLiveSimHold
extends RefCounted

# Parks the live world while a replay driver scrubs the actors through it, and
# puts it back exactly as it was.
#
# Both halves matter, and the second is the one that was worth extracting: the
# goalies are restored to their OWN saved processing state rather than blanket
# re-enabled, because a goalie already disabled for some other reason must not
# come back on when a replay ends. That is four lines of bookkeeping which
# looked incidental in both copies.

var _puck: Puck = null
var _goalie_controllers: Array[GoalieController] = []
var _saved_goalie_processing: Array[bool] = []
# Every actor the replay poses, beside the interpolation mode it had.
var _posed: Array[Node3D] = []
var _saved_interpolation: Array[Node.PhysicsInterpolationMode] = []


# The hold flag parks the analytic loose-puck sim; the goalies stop ticking so
# their AI cannot fight the poses being applied.
#
# The posed actors stop interpolating. A driver samples the clip at render time,
# and an interpolated node is drawn between its pose at the last tick and the
# one just set, so each frame would land a different fraction of a frame behind
# the clip — the replay's judder.
func grab(puck: Puck, goalie_controllers: Array[GoalieController],
		skaters: Array[Skater]) -> void:
	_puck = puck
	_goalie_controllers = goalie_controllers
	if _puck != null:
		_puck.set_replay_hold(true)
		_draw_as_posed(_puck)
	_saved_goalie_processing.clear()
	for gc: GoalieController in _goalie_controllers:
		_saved_goalie_processing.append(gc.is_physics_processing())
		gc.set_physics_process(false)
		_draw_as_posed(gc.goalie)
	for skater: Skater in skaters:
		_draw_as_posed(skater)


# Dropping the puck hold is all the drive needs to resume — the game transitions
# to FACEOFF_PREP after a replay stops, which calls puck.reset().
func release() -> void:
	if _puck != null:
		_puck.set_replay_hold(false)
	for i: int in _goalie_controllers.size():
		var was: bool = _saved_goalie_processing[i] if i < _saved_goalie_processing.size() else true
		_goalie_controllers[i].set_physics_process(was)
	_saved_goalie_processing.clear()
	for i: int in _posed.size():
		var node: Node3D = _posed[i]
		if is_instance_valid(node):
			node.physics_interpolation_mode = _saved_interpolation[i]
			# Its last tick pose predates the replay.
			node.reset_physics_interpolation()
	_posed.clear()
	_saved_interpolation.clear()
	_puck = null
	_goalie_controllers = []


func _draw_as_posed(node: Node3D) -> void:
	if node == null:
		return
	_posed.append(node)
	_saved_interpolation.append(node.physics_interpolation_mode)
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

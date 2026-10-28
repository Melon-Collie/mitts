class_name Keeper
extends Node3D

# The new goalie's body in the scene: a KeeperSkeleton solved from a KeeperPose,
# the gear drawn on it, and the save boxes the puck meets. Its local space is
# keeper space (KeeperAnatomy); the node's transform places him in the rink.
# The skeleton is solved when posed, since the saves read it; the gear is drawn
# from it at render rate, only once it has moved and only while on camera. The
# jersey's tail is cloth and swings every frame, on camera or not.

var skeleton := KeeperSkeleton.new()
var show_boxes: bool = false
# His acceleration, keeper space, set by whatever moves him; the jersey's tail
# swings against it.
var acceleration := Vector3.ZERO

var _gear: KeeperGearView = null
var _boxes: KeeperBoxView = null
# The kit and lettering, held until the gear is built to wear them.
var _colors: Dictionary = {}
var _player_name: String = ""
var _jersey_number: int = 0
# The skeleton as last solved, to tell a pose that moved him from one that
# did not; and whether the gear is drawn on the latest one (at rest until he is
# first posed).
var _was := KeeperSkeleton.new()
var _drawn: bool = true


func _ready() -> void:
	_gear = KeeperGearView.new()
	add_child(_gear)
	if not _colors.is_empty():
		_gear.apply_uniform(_colors)
	_gear.apply_jersey_info(_player_name, _jersey_number)
	if show_boxes:
		_boxes = KeeperBoxView.new()
		add_child(_boxes)


# A team's kit, as TeamColorRegistry.get_colors returns it.
func apply_uniform(colors: Dictionary) -> void:
	_colors = colors
	if _gear != null:
		_gear.apply_uniform(colors)


func apply_jersey_info(p_name: String, number: int) -> void:
	_player_name = p_name
	_jersey_number = number
	if _gear != null:
		_gear.apply_jersey_info(p_name, number)


# Solves the skeleton for `p`; whether it moved since the last.
func apply_pose(p: KeeperPose) -> bool:
	skeleton.pose(p)
	if _same_as_was():
		return false
	_keep_as_was()
	_drawn = false
	return true


func _process(delta: float) -> void:
	var seen: bool = SkaterCameraCull.sees(self)
	if not _drawn and seen:
		draw_now()
	step_cloth(delta, seen)


# One step of the jersey's tail against his acceleration, its bones written if
# `write`. A tool posing him shot by shot steps it itself.
func step_cloth(delta: float, write: bool) -> void:
	if _gear != null:
		_gear.step_tail(delta, global_basis.orthonormalized().inverse() * Vector3.DOWN, acceleration, write)


# The gear on the skeleton as it stands, whether or not it is on camera.
func draw_now() -> void:
	_drawn = _gear != null
	if _gear != null:
		_gear.update(skeleton)
	if _boxes != null:
		_boxes.update(skeleton)


func _same_as_was() -> bool:
	if _was.mirrored != skeleton.mirrored or _was.grip != skeleton.grip \
			or _was.stick_heel != skeleton.stick_heel or _was.stick_paddle_dir != skeleton.stick_paddle_dir \
			or _was.stick_blade_dir != skeleton.stick_blade_dir or _was.stick_face != skeleton.stick_face:
		return false
	for b: int in KeeperSkeleton.BONE_COUNT:
		if _was.xf[b] != skeleton.xf[b]:
			return false
	return true


func _keep_as_was() -> void:
	_was.mirrored = skeleton.mirrored
	_was.grip = skeleton.grip
	_was.stick_heel = skeleton.stick_heel
	_was.stick_paddle_dir = skeleton.stick_paddle_dir
	_was.stick_blade_dir = skeleton.stick_blade_dir
	_was.stick_face = skeleton.stick_face
	for b: int in KeeperSkeleton.BONE_COUNT:
		_was.xf[b] = skeleton.xf[b]

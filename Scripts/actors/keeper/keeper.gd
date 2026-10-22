class_name Keeper
extends Node3D

# The new goalie's body in the scene: a KeeperSkeleton solved from a KeeperPose,
# the gear drawn on it, and the save boxes the puck meets. Its local space is
# keeper space (KeeperAnatomy); the node's transform places him in the rink.

var skeleton := KeeperSkeleton.new()
var show_boxes: bool = false

var _gear: KeeperGearView = null
var _boxes: KeeperBoxView = null
# The kit and lettering, held until the gear is built to wear them.
var _colors: Dictionary = {}
var _player_name: String = ""
var _jersey_number: int = 0


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


func apply_pose(p: KeeperPose) -> void:
	skeleton.pose(p)
	if _gear != null:
		_gear.update(skeleton)
	if _boxes != null:
		_boxes.update(skeleton)

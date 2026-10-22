class_name Keeper
extends Node3D

# The new goalie's body in the scene: a KeeperSkeleton solved from a KeeperPose,
# the gear drawn on it, and the save boxes the puck meets. Its local space is
# keeper space (KeeperAnatomy); the node's transform places him in the rink.

var skeleton := KeeperSkeleton.new()
var show_boxes: bool = false

var _gear: KeeperGearView = null
var _boxes: KeeperBoxView = null


func _ready() -> void:
	_gear = KeeperGearView.new()
	add_child(_gear)
	if show_boxes:
		_boxes = KeeperBoxView.new()
		add_child(_boxes)


func apply_pose(p: KeeperPose) -> void:
	skeleton.pose(p)
	if _gear != null:
		_gear.update(skeleton)
	if _boxes != null:
		_boxes.update(skeleton)

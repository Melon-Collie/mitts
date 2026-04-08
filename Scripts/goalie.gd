class_name Goalie
extends Node3D

@onready var _left_pad: StaticBody3D = $LeftPad
@onready var _right_pad: StaticBody3D = $RightPad
@onready var _body: StaticBody3D = $Body
@onready var _glove: StaticBody3D = $Glove
@onready var _blocker: StaticBody3D = $Blocker
@onready var _stick: StaticBody3D = $Stick

func apply_body_config(config: GoalieBodyConfig, t: float) -> void:
	_lerp_part(_left_pad,  config.left_pad_pos,  config.left_pad_rot,  t)
	_lerp_part(_right_pad, config.right_pad_pos, config.right_pad_rot, t)
	_lerp_part(_body,      config.body_pos,      config.body_rot,      t)
	_lerp_part(_glove,     config.glove_pos,     config.glove_rot,     t)
	_lerp_part(_blocker,   config.blocker_pos,   config.blocker_rot,   t)
	_lerp_part(_stick,     config.stick_pos,     config.stick_rot,     t)

func set_goalie_position(x: float, z: float) -> void:
	global_position = Vector3(x, 0.0, z)

func set_goalie_rotation_y(y: float) -> void:
	rotation.y = y

func get_goalie_rotation_y() -> float:
	return rotation.y

func _lerp_part(part: StaticBody3D, target_pos: Vector3, target_rot_deg: Vector3, t: float) -> void:
	part.position = part.position.lerp(target_pos, t)
	part.rotation_degrees = part.rotation_degrees.lerp(target_rot_deg, t)

class_name Goalie
extends Node3D

# The goalie's shell: the node the puck, the skaters, the bots and the game
# address, whoever is drawn in it (`set_stand_in`: the keeper). Its part bodies
# carry his save boxes, each named for the material a puck rebounds off
# (Puck._classify_save_part → GoalieSaveRules.SavePart), so a pad rebound and a
# stick rebound are two nodes. `_block_arm` is the blocker hand: the Blocker
# and the Stick hang from it.
@onready var _left_pad: StaticBody3D = $LeftPad
@onready var _right_pad: StaticBody3D = $RightPad
@onready var _body: StaticBody3D = $Body
@onready var _head: StaticBody3D = $Head
@onready var _glove: StaticBody3D = $Glove
@onready var _block_arm: Node3D = $BlockArm
@onready var _blocker: StaticBody3D = $BlockArm/Blocker
@onready var _stick: StaticBody3D = $BlockArm/Stick


func _ready() -> void:
	# Identity tags, not collision (see Constants — every mask in the project is 0).
	# The stick is tagged apart from the body because the two are read differently:
	# skaters ignore it entirely, while the body parts define the footprint
	# Skater.clamp_body_to_goalies holds them out of. Both feed the puck's analytic
	# save contacts, which read these parts' shapes and transforms directly
	# (GoalieContactDetector) — and skip any part whose layer is 0.
	_stick.collision_layer = Constants.LAYER_GOALIE_STICK
	_left_pad.collision_layer = Constants.LAYER_GOALIE_BODIES
	_right_pad.collision_layer = Constants.LAYER_GOALIE_BODIES
	_body.collision_layer = Constants.LAYER_GOALIE_BODIES
	_head.collision_layer = Constants.LAYER_GOALIE_BODIES
	_glove.collision_layer = Constants.LAYER_GOALIE_BODIES
	_blocker.collision_layer = Constants.LAYER_GOALIE_BODIES
	for part: StaticBody3D in [_stick, _left_pad, _right_pad, _body, _head, _glove, _blocker]:
		part.collision_mask = 0


func apply_jersey_info(p_name: String, number: int) -> void:
	if _stand_in != null:
		_stand_in.call(&"apply_jersey_info", p_name, number)


func apply_uniform(colors: Dictionary) -> void:
	if _stand_in != null:
		_stand_in.call(&"apply_uniform", colors)


# ── A stand-in body: the keeper (Scripts/domain/keeper/CLAUDE.md → In a match)
var _stand_in: Node3D = null
var _save_boxes: Array[CollisionShape3D] = []
# Per box: the node it places, or null where an earlier box places it.
var _save_box_places: Array[Node3D] = []
var chest_contact := Callable()  # the stand-in's rule for a contact on the chest's part (Puck)


func set_stand_in(stand_in: Node3D) -> void:
	_stand_in = stand_in
	add_child(stand_in)
	_blocker.transform = Transform3D.IDENTITY
	_stick.transform = Transform3D.IDENTITY


# A save box of `half_extents` for the stand-in, rebounding as `save_part`
# (GoalieSaveRules.SavePart; a pad on his glove side if `glove_side`). Boxes
# are indexed in the order added.
func add_save_box(save_part: int, glove_side: bool, half_extents: Vector3) -> void:
	var body: StaticBody3D = _save_part_body(save_part, glove_side)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half_extents * 2.0
	cs.shape = box
	body.add_child(cs)
	var place: Node3D = _block_arm if save_part == GoalieSaveRules.SavePart.BLOCKER else body
	_save_boxes.append(cs)
	_save_box_places.append(null if _save_box_places.has(place) else place)
	_collision_parts_cache.clear()
	_collision_part_bodies.clear()
	_collision_part_half_extents.clear()


# Puts save box `i` at `xf` in this node's frame, the boxes in the order added.
func seat_save_box(i: int, xf: Transform3D) -> void:
	var place: Node3D = _save_box_places[i]
	if place != null:
		place.transform = _in_own_frame(place.get_parent() as Node3D).affine_inverse() * xf
	var cs: CollisionShape3D = _save_boxes[i]
	cs.transform = _in_own_frame(cs.get_parent() as Node3D).affine_inverse() * xf


# `node`'s transform in this node's frame (identity for this node itself).
func _in_own_frame(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while node != null and node != self:
		xf = node.transform * xf
		node = node.get_parent() as Node3D
	return xf


func _save_part_body(save_part: int, glove_side: bool) -> StaticBody3D:
	match save_part:
		GoalieSaveRules.SavePart.GLOVE:
			return _glove
		GoalieSaveRules.SavePart.BLOCKER:
			return _blocker
		GoalieSaveRules.SavePart.CHEST:
			return _body
		GoalieSaveRules.SavePart.MASK:
			return _head
		GoalieSaveRules.SavePart.STICK:
			return _stick
	return _left_pad if glove_side else _right_pad


func set_goalie_position(x: float, z: float) -> void:
	global_position = Vector3(x, 0.0, z)

func set_goalie_rotation_y(y: float) -> void:
	rotation.y = y

func get_goalie_rotation_y() -> float:
	return rotation.y

# Cached list of this goalie's CollisionShape3D parts (pads / body / head / glove /
# stick / blocker) for the analytic puck drive's contact queries. The subtree is
# static after _ready — only transforms move — so one gather serves every query.
# Re-gathering per sub-step instead costs hundreds of array allocations per tick in
# a crease scramble. A part switched off (its layer, or the shape disabled) is
# filtered at QUERY time from the live flags, so the cache never goes stale.
var _collision_parts_cache: Array[CollisionShape3D] = []
# Parallel to _collision_parts_cache: the owning StaticBody3D per part (otherwise a
# parent-walk per part per query) and each BoxShape3D's half extents (otherwise a
# per-query `box.size * 0.5` read). Both are fixed once the
# subtree exists; (-1,-1,-1) marks a non-box shape, standing in for the detector's
# live `shape as BoxShape3D == null` skip. Lifetime matches the shapes cache (all
# nodes are in this goalie's own subtree), so freeing the goalie frees the lot.
var _collision_part_bodies: Array[Node] = []
var _collision_part_half_extents: PackedVector3Array = PackedVector3Array()
# Also parallel: each part's world velocity in m/s, and the origins it was
# differenced from. Unlike the two above these are NOT fixed — see
# get_collision_part_velocities.
var _collision_part_velocities: PackedVector3Array = PackedVector3Array()
var _collision_part_prev_origins: PackedVector3Array = PackedVector3Array()
var _part_velocity_frame: int = -1


func get_collision_parts() -> Array[CollisionShape3D]:
	if _collision_parts_cache.is_empty():
		_gather_collision_parts(self, _collision_parts_cache)
		for cs: CollisionShape3D in _collision_parts_cache:
			var p: Node = cs.get_parent()
			while p != null and not (p is StaticBody3D):
				p = p.get_parent()
			_collision_part_bodies.append(p)
			var box := cs.shape as BoxShape3D
			_collision_part_half_extents.append(
					box.size * 0.5 if box != null else Vector3(-1.0, -1.0, -1.0))
	return _collision_parts_cache


# Parallel caches — valid after get_collision_parts() has filled the shapes cache.
func get_collision_part_bodies() -> Array[Node]:
	if _collision_parts_cache.is_empty():
		get_collision_parts()
	return _collision_part_bodies


func get_collision_part_half_extents() -> PackedVector3Array:
	if _collision_parts_cache.is_empty():
		get_collision_parts()
	return _collision_part_half_extents


# Each part's WORLD velocity (m/s) over the physics tick that ended at its
# current pose — what the analytic save needs to resolve a rebound in the frame
# of the surface it struck, because no part of a goalie is ever a static wall:
# a blocker tracks a shot at up to blocker_react_max_speed and the whole body
# slides in and out under depth_max_speed.
#
# Differenced from WORLD origins, not from the pose config, and that is the
# point: body translation, body yaw and part-local motion are already composed
# into the world transform, so one sample serves the host's built pose, a
# client's applied network pose and a replay's scrubbed pose without any of the
# three knowing about it.
#
# Sampled at most once per physics frame, on demand. On demand because the puck
# only asks near the net, so a goalie at the far end pays nothing; at most once
# because the client's re-predict calls the gather several times inside one
# frame, and differencing across those would report a tick of motion as several.
# A gap of more than one frame (the puck was up ice) leaves no honest estimate,
# so those re-baseline to zero rather than average over the gap — one tick of no
# push, spent while the puck is still metres out.
func get_collision_part_velocities() -> PackedVector3Array:
	var frame: int = Engine.get_physics_frames()
	if frame == _part_velocity_frame:
		return _collision_part_velocities
	var parts: Array[CollisionShape3D] = get_collision_parts()
	var n: int = parts.size()
	var contiguous: bool = frame == _part_velocity_frame + 1 \
			and _collision_part_prev_origins.size() == n
	if not contiguous:
		_collision_part_prev_origins.resize(n)
		_collision_part_velocities.resize(n)
	# Nominal step, not the frame's measured delta: the simulation advances by a
	# fixed step even when the host overruns and real time dilates around it.
	var inv_dt: float = float(Engine.physics_ticks_per_second)
	for i: int in n:
		var origin: Vector3 = parts[i].global_transform.origin
		_collision_part_velocities[i] = (origin - _collision_part_prev_origins[i]) * inv_dt \
				if contiguous else Vector3.ZERO
		_collision_part_prev_origins[i] = origin
	_part_velocity_frame = frame
	return _collision_part_velocities


static func _gather_collision_parts(node: Node, found: Array[CollisionShape3D]) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			found.append(child)
		_gather_collision_parts(child, found)

# Glove world position — the pin point for a caught puck (catch-and-hold).
func get_glove_world_position() -> Vector3:
	return _glove.global_position

# Blocker-assembly world position — the glove's opposite number, for which hand
# reaches a puck sooner (KeeperController._chest_contact).
func get_blocker_world_position() -> Vector3:
	return _block_arm.global_position


# The mask's world position: where his eyes are.
func get_mask_world_position() -> Vector3:
	return _head.global_position

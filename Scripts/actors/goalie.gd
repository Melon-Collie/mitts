class_name Goalie
extends Node3D

# `_block_arm` is the blocker HAND: its origin is the grip on the shaft, and the
# stick (shaft, paddle, blade) hangs rigidly from it. Driven by a single
# transform (`blocker_pos` + `blocker_rot` from the body config). The stick
# geometry is baked into the mesh layout — different states get the blade in
# the right place via different hand rotations, not by tracking the blade
# independently. The Blocker board rides the hand (_seat_blocker). The Blocker
# and Stick are SEPARATE child StaticBody3Ds under BlockArm — the analytic save
# resolver identifies the struck part BY NODE NAME (Puck._classify_save_part →
# GoalieSaveRules.SavePart), so a pad rebound and a stick rebound have to be two
# nodes.
@onready var _left_pad: StaticBody3D = $LeftPad
@onready var _right_pad: StaticBody3D = $RightPad
@onready var _body: StaticBody3D = $Body
@onready var _head: StaticBody3D = $Head
@onready var _glove: StaticBody3D = $Glove
@onready var _block_arm: Node3D = $BlockArm
@onready var _blocker: StaticBody3D = $BlockArm/Blocker
@onready var _stick: StaticBody3D = $BlockArm/Stick
@onready var _stick_blade: CollisionShape3D = $BlockArm/Stick/StickBladeCollider
@onready var stick_blade_mesh: MeshInstance3D = $BlockArm/Stick/StickBladeMesh

# Visual mesh refs — public so GoalieUniformCoordinator can read them directly
# without a growing parameter list, matching the SkaterUniformCoordinator pattern.
@onready var body_mesh: MeshInstance3D = $Body/MeshInstance3D
@onready var head_mesh: MeshInstance3D = $Head/MeshInstance3D
@onready var left_pad_mesh: MeshInstance3D = $LeftPad/MeshInstance3D
@onready var right_pad_mesh: MeshInstance3D = $RightPad/MeshInstance3D
@onready var glove_main_mesh: MeshInstance3D = $Glove/Main
@onready var blocker_mesh: MeshInstance3D = $BlockArm/Blocker/BlockerPadMesh
@onready var stick_shaft_mesh: MeshInstance3D = $BlockArm/Stick/StickShaftMesh

# Arm-to-glove segments. 0.76 per side is ~104% wingspan-equivalent on the
# ~1.92 m frame — same anthropometry target as the skaters. The arms draw to the
# pose-driven hands; the poses in turn hold the hands at a distance these arms
# reach at a real bend (GoalieAnatomy.hand_depth_for_bend).
const _ARM_UPPER_LEN: float = GoalieAnatomy.ARM_UPPER_M
const _ARM_FOREARM_LEN: float = GoalieAnatomy.ARM_FOREARM_M
# A chest protector's arms are padded: a thick bicep, an elbow cap, and a
# forearm pad tapering to the wrist.
const _UPPER_ARM_RADIUS: float = 0.09
const _FOREARM_RADIUS: float = 0.075
const _ELBOW_SPHERE_RADIUS: float = 0.09
# Shoulder floaters: the broad caps a chest protector carries over each
# shoulder, set outboard and up of the joint so they stand past the trunk and
# above the collar, which is the goalie's shoulder line from the top-down
# camera. Semi-axes in the body's frame; tilt with the trunk.
const FLOATER_SEMI_AXES := Vector3(0.13, 0.10, 0.125)
const FLOATER_OUTSET := Vector3(0.02, 0.03, 0.0)
# The glove forearm ends here, in the Glove's frame, rather than at its origin:
# behind the trapper's heel, where the cuff opening takes a real forearm, so
# the arm meets the back of the hand instead of running through its thumb.
const _GLOVE_CUFF_IN_GLOVE := Vector3(0.0, -0.03, 0.07)
# How far outboard of the shoulder joint the elbow must be before it may hang
# back past it: to the trunk's side face, plus the arm's own thickness.
const _ELBOW_CLEARS_TRUNK_M: float = GoalieAnatomy.TORSO_BOX_WIDTH_M * 0.5 \
		- GoalieAnatomy.SHOULDER_OFFSET.x + _UPPER_ARM_RADIUS

# The pads' eased stance, which apply_body_config lerps toward the config and
# lays the footwork step over; the nodes carry the sum.
var _left_pad_eased_pos: Vector3 = Vector3.ZERO
var _left_pad_eased_rot: Vector3 = Vector3.ZERO
var _right_pad_eased_pos: Vector3 = Vector3.ZERO
var _right_pad_eased_rot: Vector3 = Vector3.ZERO
# The blocker arm's elbow from the last _seat_blocker, goalie-local; the drawn
# arm reads it so it is the arm the board rides.
var _blocker_elbow: Vector3 = Vector3.ZERO
# The board lies over the back of the glove (the smother) instead of standing
# square to the shooter.
var _blocker_over_glove: bool = false

var _uniform_coordinator: GoalieUniformCoordinator
# Dynamic visual nodes — public for GoalieUniformCoordinator access.
var left_hip_connector: MeshInstance3D = null
var right_hip_connector: MeshInstance3D = null
var glove_upper_arm: Node3D = null
var glove_forearm: Node3D = null
var blocker_upper_arm: Node3D = null
var blocker_forearm: Node3D = null
var glove_shoulder_sphere: MeshInstance3D = null
var blocker_shoulder_sphere: MeshInstance3D = null
var glove_elbow_sphere: MeshInstance3D = null
var blocker_elbow_sphere: MeshInstance3D = null

# Dirty-skip cache for `_update_connectors`. The arm-IK + connector rebuild
# is value-type-cheap but runs every rendered frame for both goalies; the pose
# only changes when `apply_body_config` / `apply_network_pose` move a part, and
# a settled goalie holds its stance for seconds, so we recompute only when one
# of the body-local part transforms actually changed. Default-mismatched so the
# first frame always rebuilds.
var _last_body_xform: Transform3D
var _last_left_pad_pos: Vector3 = Vector3.INF
var _last_right_pad_pos: Vector3
var _last_glove_xform: Transform3D = Transform3D()
var _last_block_arm_xform: Transform3D = Transform3D()


func _ready() -> void:
	# Identity tags, not collision (see Constants — every mask in the project is 0).
	# The stick is tagged apart from the body because the two are read differently:
	# skaters ignore it entirely, while the body parts define the footprint
	# Skater.clamp_body_to_goalies holds them out of. Both feed the puck's analytic
	# save contacts, which read these parts' shapes and transforms directly
	# (GoalieContactDetector) — and skip any part whose layer is 0, which is how
	# set_stick_collision_enabled takes the stick out of play mid-sweep.
	_stick.collision_layer = Constants.LAYER_GOALIE_STICK
	_left_pad.collision_layer = Constants.LAYER_GOALIE_BODIES
	_right_pad.collision_layer = Constants.LAYER_GOALIE_BODIES
	_body.collision_layer = Constants.LAYER_GOALIE_BODIES
	_head.collision_layer = Constants.LAYER_GOALIE_BODIES
	_glove.collision_layer = Constants.LAYER_GOALIE_BODIES
	_blocker.collision_layer = Constants.LAYER_GOALIE_BODIES
	for part: StaticBody3D in [_stick, _left_pad, _right_pad, _body, _head, _glove, _blocker]:
		part.collision_mask = 0
	# Swap the scene's primitive part meshes for the shared low-poly faceted
	# set (colliders untouched). Before the uniform coordinator only by
	# convention — painting is material_override / ShaderMaterial, mesh-free.
	GoalieMeshBuilder.apply_goalie(self)
	_seat_blade()
	_init_stick_knob()
	_init_connectors()
	_init_arm_bones()
	_seat_blocker()
	_rebase_pads()
	_setup_uniform_coordinator()
	var vfx := GoalieVFX.new()
	vfx.name = "VFX"
	add_child(vfx)


func _process(_delta: float) -> void:
	if _stand_in == null:
		_update_connectors()


func apply_jersey_info(p_name: String, number: int) -> void:
	if _stand_in != null:
		_stand_in.call(&"apply_jersey_info", p_name, number)
		return
	_uniform_coordinator.apply_jersey_info(p_name, number)


func apply_uniform(colors: Dictionary) -> void:
	if _stand_in != null:
		_stand_in.call(&"apply_uniform", colors)
		return
	_uniform_coordinator.apply_uniform(colors)


# ── A stand-in body: the keeper (Scripts/domain/keeper/CLAUDE.md → In a match)
var _stand_in: Node3D = null
var _save_boxes: Array[CollisionShape3D] = []
# Per box: the node it places, or null where an earlier box places it.
var _save_box_places: Array[Node3D] = []
var chest_contact := Callable()  # the stand-in's rule for a contact on the chest's part (Puck)


func set_stand_in(stand_in: Node3D) -> void:
	_stand_in = stand_in
	_hide_own_meshes(self)
	add_child(stand_in)
	for cs: CollisionShape3D in get_collision_parts():
		cs.disabled = true
	_blocker.transform = Transform3D.IDENTITY
	_stick.transform = Transform3D.IDENTITY


func _hide_own_meshes(node: Node) -> void:
	for child: Node in node.get_children():
		if child == _stand_in:
			continue
		if child is VisualInstance3D:
			(child as VisualInstance3D).visible = false
		child.set_process(false)
		_hide_own_meshes(child)


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

# `glove_max_step` / `blocker_max_step`: optional caps on linear movement
# this frame (metres). Callers pass `*_react_max_speed * delta` to enforce a
# realistic arm-speed limit so the catch / block reach can't perfectly beat
# the puck to the spot. -1 disables the cap (target uses the shared lerp).
# Rotations still lerp at the shared `t` regardless — wrist orientation
# tracks position closely enough not to need its own cap. The blocker step
# applies to the entire BlockArm (pad + stick rigid assembly).
func apply_body_config(config: GoalieBodyConfig, t: float, glove_max_step: float = -1.0, blocker_max_step: float = -1.0) -> void:
	_left_pad_eased_pos = _left_pad_eased_pos.lerp(config.left_pad_pos, t)
	_left_pad_eased_rot = _lerp_euler_deg(_left_pad_eased_rot, config.left_pad_rot, t)
	_left_pad.position = _left_pad_eased_pos + config.left_pad_step_pos
	_left_pad.rotation_degrees = _left_pad_eased_rot + config.left_pad_step_rot
	_right_pad_eased_pos = _right_pad_eased_pos.lerp(config.right_pad_pos, t)
	_right_pad_eased_rot = _lerp_euler_deg(_right_pad_eased_rot, config.right_pad_rot, t)
	_right_pad.position = _right_pad_eased_pos + config.right_pad_step_pos
	_right_pad.rotation_degrees = _right_pad_eased_rot + config.right_pad_step_rot
	_lerp_part(_body,      config.body_pos,      config.body_rot,      t)
	_lerp_part(_head,      config.head_pos,      config.head_rot,      t)
	if glove_max_step < 0.0:
		_lerp_part(_glove, config.glove_pos, config.glove_rot, t)
	else:
		_glove.position = _glove.position.move_toward(config.glove_pos, glove_max_step)
		_glove.rotation_degrees = _lerp_euler_deg(_glove.rotation_degrees, config.glove_rot, t)
	# The blocker hand, with the stick rigid in it. Single transform via
	# `blocker_pos` / `blocker_rot`; the board then rides the arm
	# (_seat_blocker). When reaching for a blocker save the position is
	# rate-limited via `blocker_max_step` the same way the glove is, so the
	# hand can't teleport to the impact point.
	if blocker_max_step < 0.0:
		_lerp_part(_block_arm, config.blocker_pos, config.blocker_rot, t)
	else:
		_block_arm.position = _block_arm.position.move_toward(config.blocker_pos, blocker_max_step)
		_block_arm.rotation_degrees = _lerp_euler_deg(_block_arm.rotation_degrees, config.blocker_rot, t)
	_blocker_over_glove = config.blocker_over_glove
	_seat_blocker()

func set_goalie_position(x: float, z: float) -> void:
	global_position = Vector3(x, 0.0, z)

func set_goalie_rotation_y(y: float) -> void:
	rotation.y = y

func get_goalie_rotation_y() -> float:
	return rotation.y

# Current body-local position of the glove and blocker assembly. Read by the
# controller to pace the shot hand reach so the arm arrives WITH the puck
# rather than sprinting to the destination at max speed and sitting idle until
# impact. Returned in goalie-local space (the same space the config targets
# live in) so the caller can `distance_to(config.glove_pos)` directly.
func get_glove_position() -> Vector3:
	return _glove.position

# Live body-local chest position. GoalieVFX reads its height to tell a
# committed butterfly drop (fast fall into the low band) from a stance lerp.
func get_body_position() -> Vector3:
	return _body.position

# Clear-sweep follow-through moves the BlockArm (and its child Stick, off which
# the puck rebounds during saves) through the puck's exit path. Without this the
# "cosmetic" swing can re-strike the puck moments after the clear velocity was
# imparted and deflect it anywhere, including back into the goalie's own net.
# Disabled for the swing's duration.
func set_stick_collision_enabled(enabled: bool) -> void:
	_stick.collision_layer = Constants.LAYER_GOALIE_STICK if enabled else 0


# Cached list of this goalie's CollisionShape3D parts (pads / body / head / glove /
# stick / blocker) for the analytic puck drive's contact queries. The subtree is
# static after _ready — only transforms move — so one gather serves every query.
# Re-gathering per sub-step instead costs hundreds of array allocations per tick in
# a crease scramble. Runtime enable/disable (the clear-sweep stick toggle
# above) is filtered at QUERY time from the live layer/disabled flags, so the cache
# never goes stale.
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

func get_blocker_position() -> Vector3:
	return _block_arm.position

# Glove world position — the pin point for a caught puck (catch-and-hold).
func get_glove_world_position() -> Vector3:
	return _glove.global_position

# Blocker-assembly world position — the glove's opposite number. Read by the
# shot-read instrumentation, which has to ask "how far is the NEAREST arm from
# this shot" (on an elevated shot either arm can make the save, so keying on the
# glove alone measures glove-side-vs-blocker-side rather than reach).
func get_blocker_world_position() -> Vector3:
	return _block_arm.global_position

# Pose accessors used by goalie_controller.fill_state() to fill the
# authoritative socket transforms broadcast in the world snapshot. All values
# returned in goalie-local space; rotations in radians.
func get_left_pad_position() -> Vector3:
	return _left_pad.position

func get_left_pad_rotation() -> Vector3:
	return _left_pad.rotation

func get_right_pad_position() -> Vector3:
	return _right_pad.position

func get_right_pad_rotation() -> Vector3:
	return _right_pad.rotation

func get_body_rotation() -> Vector3:
	return _body.rotation

func get_glove_rotation() -> Vector3:
	return _glove.rotation

func get_blocker_rotation() -> Vector3:
	return _block_arm.rotation

func get_head_yaw() -> float:
	return _head.rotation.y

# Stick blade world position. Used by the controller's goalie poke check —
# the puck is magneted to the carrier's blade with no physics during carry,
# so we can't rely on RigidBody contact firing. The check is host-side:
# when this position is within poke radius of a carried puck, the goalie
# strips the puck.
func get_blade_world_position() -> Vector3:
	return _stick_blade.global_position


# Apply an authoritative pose snapshot directly to the body parts. Used by
# both live client rendering (interpolated broadcast pose) and replay playback
# — neither runs the local AI, so this writes the host's socket transforms
# straight onto the scene nodes. Skips the body_config_builder entirely.
# Rotations come in radians (matching the wire format); axes we don't carry on
# the wire (body yaw, blocker/glove roll) are left intact so whatever was last
# set survives. Pad yaw IS carried (wire v13): it steers the rebound, so a remote
# client rendering square pads would show rebounds kicking cornerward for no
# visible reason.
func apply_network_pose(state: GoalieNetworkState) -> void:
	# Body + head positions are state-dependent (the pose builder hardcodes
	# different y-heights per state — body 0.64 in butterfly, 1.22 standing
	# etc.). The wire format doesn't carry them, so derive from state_enum
	# via the pose builder's lookup. Without this the chest/head freeze at
	# the scene-default standing height while the legs animate, which reads
	# as a floating head over crouching pads.
	_body.position = GoalieBodyConfigBuilder.resting_body_position_for_state(state.state_enum)
	_body.rotation = Vector3(state.body_pitch, _body.rotation.y, state.body_roll)
	_head.position = GoalieBodyConfigBuilder.resting_head_position_for_state(state.state_enum)
	if GoalieStateMachine.is_on_his_feet(state.state_enum):
		# On his feet the trunk leans from the hips, the head riding it — derived
		# from the roll, which is all the wire carries of it.
		var roll_deg: float = rad_to_deg(state.body_roll)
		_head.position.x += GoalieAnatomy.head_shift_for_roll(
				_head.position.y, _body.position.y, roll_deg)
		_body.position.x += GoalieAnatomy.trunk_shift_for_roll(roll_deg)
	_head.rotation = Vector3(_head.rotation.x, state.head_yaw, _head.rotation.z)
	_left_pad.position = state.left_pad_offset
	_left_pad.rotation = Vector3(state.left_pad_pitch, state.left_pad_yaw, state.left_pad_roll)
	_right_pad.position = state.right_pad_offset
	_right_pad.rotation = Vector3(state.right_pad_pitch, state.right_pad_yaw, state.right_pad_roll)
	_rebase_pads()
	_glove.position = state.glove_offset
	_glove.rotation = Vector3(state.glove_pitch, state.glove_yaw, _glove.rotation.z)
	_block_arm.position = state.blocker_offset
	_block_arm.rotation = Vector3(state.blocker_pitch, state.blocker_yaw, _block_arm.rotation.z)
	_blocker_over_glove = GoalieBodyConfigBuilder.blocker_over_glove_for_state(state.state_enum)
	_seat_blocker()

# Take the pads' eased stance from where they stand — after any pose written
# straight onto them, so the next eased pose carries on from it.
func _rebase_pads() -> void:
	_left_pad_eased_pos = _left_pad.position
	_left_pad_eased_rot = _left_pad.rotation_degrees
	_right_pad_eased_pos = _right_pad.position
	_right_pad_eased_rot = _right_pad.rotation_degrees


# Seat the blade at its lie and curve (GoalieStickRules.blade_rotation), which
# the authored square L does not carry. Applied once at build time: a lie is a
# property of the stick, so the blade stays rigid to the shaft and every stance
# inherits it through the assembly transform. Collider and mesh together, which
# is why the blade is held out of the stick mesh merge.
#
# IT PIVOTS ABOUT THE HEEL, not the blade's middle. The heel is where the blade
# meets the paddle, so it is the one point that may not move; rotating the box
# about its centre swings the heel out of the paddle and leaves an open joint.
func _seat_blade() -> void:
	var rot: Basis = GoalieStickRules.blade_rotation()
	# The heel is the authored box's +X end, and the only point that may not move.
	var half := Vector3(GoalieStickRules.BLADE_WIDTH_M * 0.5, 0.0, 0.0)
	var heel: Vector3 = _stick_blade.position + half
	_stick_blade.transform = Transform3D(rot, heel - rot * half)
	# The mesh is heel-origin already, so it hangs straight off the joint. Its
	# builder runs the blade down -Z where the collider runs it down -X, hence
	# the quarter turn.
	stick_blade_mesh.mesh = GoalieMeshBuilder.shared_goalie_blade()
	stick_blade_mesh.transform = Transform3D(
			rot * Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0)), heel)


func _lerp_part(part: Node3D, target_pos: Vector3, target_rot_deg: Vector3, t: float) -> void:
	part.position = part.position.lerp(target_pos, t)
	part.rotation_degrees = _lerp_euler_deg(part.rotation_degrees, target_rot_deg, t)


# Wrap-safe Euler lerp: rotation_degrees.lerp on a Vector3 interpolates each
# axis linearly, which crosses through 0° instead of through 180° at sign
# flips (-179° → +179° becomes a 358° spin through 0°, not a 2° step). All
# current goalie body parts stay within ±90°, but the moment any rotation
# range crosses ±180° the latent bug surfaces. Reduce the per-axis delta
# into [-180°, +180°] via fmod so the lerp always takes the short way.
static func _lerp_euler_deg(from: Vector3, to: Vector3, t: float) -> Vector3:
	return Vector3(
		from.x + _shortest_deg_delta(from.x, to.x) * t,
		from.y + _shortest_deg_delta(from.y, to.y) * t,
		from.z + _shortest_deg_delta(from.z, to.z) * t,
	)


static func _shortest_deg_delta(from: float, to: float) -> float:
	var delta: float = fmod(to - from + 540.0, 360.0) - 180.0
	return delta


func _setup_uniform_coordinator() -> void:
	_uniform_coordinator = GoalieUniformCoordinator.new()
	_uniform_coordinator.setup(self)


func _init_connectors() -> void:
	left_hip_connector = _make_connector_mesh()
	add_child(left_hip_connector)
	right_hip_connector = _make_connector_mesh()
	add_child(right_hip_connector)


func _init_arm_bones() -> void:
	glove_upper_arm = _make_arm_bone(_UPPER_ARM_RADIUS)
	add_child(glove_upper_arm)
	glove_forearm = _make_arm_bone(_FOREARM_RADIUS)
	add_child(glove_forearm)
	blocker_upper_arm = _make_arm_bone(_UPPER_ARM_RADIUS)
	add_child(blocker_upper_arm)
	blocker_forearm = _make_arm_bone(_FOREARM_RADIUS)
	add_child(blocker_forearm)
	glove_shoulder_sphere = _make_sphere_mesh(1.0)
	add_child(glove_shoulder_sphere)
	blocker_shoulder_sphere = _make_sphere_mesh(1.0)
	add_child(blocker_shoulder_sphere)
	glove_elbow_sphere = _make_sphere_mesh(_ELBOW_SPHERE_RADIUS)
	add_child(glove_elbow_sphere)
	blocker_elbow_sphere = _make_sphere_mesh(_ELBOW_SPHERE_RADIUS)
	add_child(blocker_elbow_sphere)


# White tape knob capping the shaft butt — the fixed house look for the
# goalie stick. Goalies tape heavily and white is the norm; unlike the
# skater's knob it never tracks a kit color, so it's created once here
# (geometry side) while GoalieUniformCoordinator paints the shaft, paddle,
# and blade. Shaft top is at Stick-local y = 0.5 (mesh at 0.25, box 0.5
# tall); the knob sits proud of it by the same 1 cm as the skater's.
func _init_stick_knob() -> void:
	var knob := MeshInstance3D.new()
	knob.name = "StickKnob"
	knob.mesh = SkaterMeshBuilder.shared_knob()
	knob.position = Vector3(0.0, 0.5 - SkaterMeshBuilder.KNOB_HEIGHT_M * 0.5 + 0.01, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.93, 0.90)
	mat.roughness = 0.9
	BodyRim.apply(mat)
	knob.material_override = mat
	_stick.add_child(knob)


# Unit-height shared tube (radius baked at HIP_CONNECTOR_RADIUS); the
# per-frame stretch lives in _point_connector's basis, not the mesh.
func _make_connector_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = GoalieMeshBuilder.shared_connector_tube()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# The blocker is a glove on the arm, not an end point: the hand (BlockArm) is
# what is posed, the elbow hangs as low as lets the wrist stand the board
# upright (higher only for a hand held high), and the board stands on the back
# of the hand — along the forearm, cocked toward upright at the wrist — face
# rotated slightly out toward the corner, so it moves and turns with the arm.
# Smothering, it lies face up over the glove instead.
# Runs wherever the hand or the trunk is posed — the host's tick and every
# client and replay alike — because the board is a save surface, and from the
# arm's own solve so the drawn arm is the one it rides.
func _seat_blocker() -> void:
	var shoulder: Vector3 = _body.position + _body.basis * GoalieAnatomy.SHOULDER_OFFSET
	var grip: Vector3 = _block_arm.position
	_blocker_elbow = TwoBoneIK.solve_elbow_hanging(shoulder, grip,
			_ARM_UPPER_LEN, _ARM_FOREARM_LEN, Vector3.FORWARD, Vector3.RIGHT,
			_ELBOW_CLEARS_TRUNK_M, deg_to_rad(GoalieAnatomy.BLOCKER_WRIST_COCK_MAX_DEG))
	var along: Vector3   # wrist → fingertips
	var presented: Vector3
	if _blocker_over_glove:
		along = _laid_flat(grip - _blocker_elbow)
		presented = Vector3.UP
	else:
		along = _cocked_wrist(grip - _blocker_elbow)
		var turn: float = deg_to_rad(GoalieAnatomy.BLOCKER_FACE_OUTWARD_DEG)
		presented = Vector3(sin(turn), 0.0, -cos(turn))
	var face: Vector3 = presented - along * presented.dot(along)
	face = face.normalized() if face.length_squared() > 1e-8 else Vector3.RIGHT
	var board := Basis(along.cross(-face), along, -face)
	var centre: Vector3 = grip - along * GoalieAnatomy.BLOCKER_BOARD_ALONG_M \
			+ face * GoalieAnatomy.BLOCKER_BOARD_OUT_M
	_blocker.transform = _block_arm.transform.affine_inverse() * Transform3D(board, centre)


# The hand's long axis laid over the glove: the forearm's heading, level.
static func _laid_flat(forearm: Vector3) -> Vector3:
	var level := Vector3(forearm.x, 0.0, forearm.z)
	return level.normalized() if level.length_squared() > 1e-8 else Vector3.FORWARD


# The hand's long axis: the forearm's direction (elbow → grip), turned toward
# hanging straight down by as much as the wrist allows.
static func _cocked_wrist(forearm: Vector3) -> Vector3:
	if forearm.length_squared() < 1e-8:
		return Vector3.DOWN
	var dir: Vector3 = forearm.normalized()
	var off_vertical: float = dir.angle_to(Vector3.DOWN)
	if off_vertical < 1e-4:
		return dir
	var hinge: Vector3 = dir.cross(Vector3.DOWN)
	hinge = hinge.normalized() if hinge.length_squared() > 1e-8 else Vector3.RIGHT
	var cock: float = minf(off_vertical, deg_to_rad(GoalieAnatomy.BLOCKER_WRIST_COCK_MAX_DEG))
	return dir.rotated(hinge, cock)


# Two-bone arm IK. shoulder_local / hand_local are in goalie-local space;
# outward_local is the arm's side (±X), which the elbow may not fold inside of.
func _update_arm_ik(upper: Node3D, forearm_bone: Node3D,
		shoulder_local: Vector3, hand_local: Vector3, outward_local: Vector3,
		elbow_sphere: MeshInstance3D = null) -> void:
	if upper == null or forearm_bone == null:
		return
	var shoulder_w: Vector3 = to_global(shoulder_local)
	var hand_w: Vector3 = to_global(hand_local)
	# He faces local -Z.
	var elbow_w: Vector3 = TwoBoneIK.solve_elbow_hanging(
			shoulder_w, hand_w, _ARM_UPPER_LEN, _ARM_FOREARM_LEN,
			global_transform.basis * Vector3.FORWARD, global_transform.basis * outward_local,
			_ELBOW_CLEARS_TRUNK_M)
	var elbow_local: Vector3 = to_local(elbow_w)
	if elbow_sphere != null:
		elbow_sphere.position = elbow_local
	_update_arm_bone(upper, shoulder_local, elbow_local)
	_update_arm_bone(forearm_bone, elbow_local, hand_local)


func _update_arm_bone(bone: Node3D, a_local: Vector3, b_local: Vector3) -> void:
	if bone == null:
		return
	var span: Vector3 = b_local - a_local
	var length: float = span.length()
	var center: Vector3 = (a_local + b_local) * 0.5
	if length < 0.0001:
		bone.position = center
		return
	# One local transform write, not position + scale + look_at. look_at costs
	# six transform operations, two of which resolve the global chain; the prism
	# is rotationally symmetric so the up vector only has to dodge colinearity.
	# X/Y carry the arm thickness and stay as the sizing seam left them.
	var bone_scale: Vector3 = bone.scale
	bone_scale.z = length
	bone.transform = Transform3D(
			Basis.looking_at(span / length, _up_for_look_at(span)).scaled_local(bone_scale),
			center)


static func _up_for_look_at(direction: Vector3) -> Vector3:
	if absf(direction.normalized().y) > 0.99:
		return Vector3.FORWARD
	return Vector3.UP


# ONE MeshInstance3D per bone, carrying the prism whose long axis is already local
# Z (shared_arm_bone_z bakes that rotation into the mesh, so no child node has to
# apply it). X/Y are the arm THICKNESS; Z is the length _update_arm_bone() rewrites
# per tick — each writer reads the other's components back rather than overwriting
# the whole vector. Same rig contract as Skater._resolve_or_create_bone_mesh.
func _make_arm_bone(radius: float) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SkaterMeshBuilder.shared_arm_bone_z()
	mi.scale = Vector3(radius, radius, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_sphere_mesh(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SkaterMeshBuilder.shared_joint_ball()
	mi.scale = Vector3.ONE * radius
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# Bridge each body-part pair with a cylinder that tracks their current positions
# every frame. All positions are in goalie-local space (direct children of the
# Goalie root), so no coordinate conversion needed.
#
# Value-type-cheap but runs every rendered frame for both goalies. Skip when
# the goalie is hidden, and when no part moved since the last frame — a settled
# goalie's `apply_body_config` lerp converges to a fixed pose, so holding a
# stance skips the arm-IK rebuild entirely. Root translation/yaw doesn't dirty
# the pose: the arms are children and ride along rigidly, so only the body-local
# part transforms matter. Nothing here feeds gameplay (colliders are read
# directly), so a skipped frame is purely cosmetic.
func _update_connectors() -> void:
	if not is_visible_in_tree():
		return
	if not _connectors_pose_changed():
		return
	# Anchor offsets are body-local against the torso box in Goalie.tscn
	# (half-height 0.36): hips near the box bottom, shoulders a hand's width
	# below the box top.
	_point_connector(left_hip_connector,
		_body.position + _body.basis * Vector3(-0.10, -0.30, 0.0),
		_left_pad.position)
	_point_connector(right_hip_connector,
		_body.position + _body.basis * Vector3(0.10, -0.30, 0.0),
		_right_pad.position)
	# Shoulder floaters follow the body pivot each frame, and tilt with it.
	var glove_shoulder: Vector3 = _body.position + _body.basis * Vector3(
			-GoalieAnatomy.SHOULDER_OFFSET.x, GoalieAnatomy.SHOULDER_OFFSET.y, 0.0)
	var blocker_shoulder: Vector3 = _body.position + _body.basis * GoalieAnatomy.SHOULDER_OFFSET
	var floater_basis: Basis = _body.basis.scaled_local(FLOATER_SEMI_AXES)
	glove_shoulder_sphere.transform = Transform3D(floater_basis, glove_shoulder
			+ _body.basis * Vector3(-FLOATER_OUTSET.x, FLOATER_OUTSET.y, FLOATER_OUTSET.z))
	blocker_shoulder_sphere.transform = Transform3D(floater_basis,
			blocker_shoulder + _body.basis * FLOATER_OUTSET)
	# Glove arm: shoulder on body's left side (goalie's catch hand).
	_update_arm_ik(glove_upper_arm, glove_forearm,
		glove_shoulder, _glove.position + _glove.basis * _GLOVE_CUFF_IN_GLOVE, Vector3.LEFT,
		glove_elbow_sphere)
	# Blocker arm: the elbow _seat_blocker raised and laid the board along.
	blocker_elbow_sphere.position = _blocker_elbow
	_update_arm_bone(blocker_upper_arm, blocker_shoulder, _blocker_elbow)
	_update_arm_bone(blocker_forearm, _blocker_elbow, _block_arm.position)


# Returns true (and refreshes the snapshot) when any input to `_update_connectors`
# moved since the last rebuild. Exact equality is sufficient: a converged lerp
# produces bit-identical transforms tick over tick, and any real movement trips
# the compare. Body transform covers both the shoulder pivots (position + basis)
# and the connector roots in one check.
func _connectors_pose_changed() -> bool:
	if _body.transform == _last_body_xform \
			and _left_pad.position == _last_left_pad_pos \
			and _right_pad.position == _last_right_pad_pos \
			and _glove.transform == _last_glove_xform \
			and _block_arm.transform == _last_block_arm_xform:
		return false
	_last_body_xform = _body.transform
	_last_left_pad_pos = _left_pad.position
	_last_right_pad_pos = _right_pad.position
	_last_glove_xform = _glove.transform
	_last_block_arm_xform = _block_arm.transform
	return true


func _point_connector(mesh: MeshInstance3D, from_pos: Vector3, to_pos: Vector3) -> void:
	var diff: Vector3 = to_pos - from_pos
	var length: float = diff.length()
	if length < 0.02:
		mesh.visible = false
		return
	mesh.visible = true
	mesh.position = (from_pos + to_pos) * 0.5
	# Orient the unit tube (Y-axis aligned) to point from from_pos to to_pos.
	# The stretch to the span's length rides the basis Y column — mesh
	# mutation would leak through the shared connector mesh to every goalie.
	var y_axis: Vector3 = diff / length
	var ref: Vector3 = Vector3.FORWARD if abs(y_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	mesh.basis = Basis(x_axis, y_axis * length, z_axis)

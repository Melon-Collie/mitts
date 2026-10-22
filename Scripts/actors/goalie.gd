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

# The pads' eased stance, which apply_body_config lerps toward the config and
# lays the footwork step over; the nodes carry the sum.
var _left_pad_eased_pos: Vector3 = Vector3.ZERO
var _left_pad_eased_rot: Vector3 = Vector3.ZERO
var _right_pad_eased_pos: Vector3 = Vector3.ZERO
var _right_pad_eased_rot: Vector3 = Vector3.ZERO
# The blocker arm's elbow from the last _seat_blocker, goalie-local.
var _blocker_elbow: Vector3 = Vector3.ZERO
# The board lies over the back of the glove (the smother) instead of standing
# square to the shooter.
var _blocker_over_glove: bool = false

var _uniform_coordinator: GoalieUniformCoordinator


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
	_seat_blocker()
	_rebase_pads()
	_setup_uniform_coordinator()
	var vfx := GoalieVFX.new()
	vfx.name = "VFX"
	add_child(vfx)


func apply_jersey_info(p_name: String, number: int) -> void:
	_uniform_coordinator.apply_jersey_info(p_name, number)


func apply_uniform(colors: Dictionary) -> void:
	_uniform_coordinator.apply_uniform(colors)

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

# The elbow the board was seated from (goalie-local), so the drawn arm
# (GoalieLimbRig) is the arm the board rides.
func get_blocker_elbow() -> Vector3:
	return _blocker_elbow

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
	# different y-heights per state — body 0.40 in butterfly, 1.22 standing
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
			GoalieAnatomy.ARM_UPPER_M, GoalieAnatomy.ARM_FOREARM_M, Vector3.FORWARD,
			Vector3.RIGHT, GoalieAnatomy.ELBOW_CLEARS_TRUNK_M, deg_to_rad(GoalieAnatomy.BLOCKER_WRIST_COCK_MAX_DEG))
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

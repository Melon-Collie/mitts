class_name Skater
extends CharacterBody3D

# ── Character ─────────────────────────────────────────────────────────────────
@export var is_left_handed: bool = true

# ── Blade Tuning ──────────────────────────────────────────────────────────────
@export var blade_height: float = 0.0
# Shoulder anchor offset from body center. The shoulder (top-hand anchor)
# sits on the OPPOSITE side of the body from the blade: a left-handed shooter
# (blade on −X) has the top hand on the right shoulder (+X), and vice versa.
# Baseline ~0.22 m (half of adult shoulder-to-shoulder breadth).
@export var shoulder_offset: float = 0.22
# Shoulder Y in upper-body-local space. Positions the arm's anchor high on
# the torso (near the top of the upper body mesh) so the visible arm spans
# from the shoulder down to the hand rather than both points collapsing to
# the same Y. With hand_rest_y = 0, a drop of ~0.5 m is natural; too large
# and the arm may visibly stretch at max backhand reach (see
# rom_backhand_reach_max interaction).
@export var shoulder_height: float = 0.5
# Blade length (heel to toe). The Blade Marker3D represents the heel (where
# the shaft meets the blade); the blade mesh extends forward by this distance.
# The puck plays at the contact point, which is blade_length * 0.5 forward
# of the Marker3D along its local forward axis. Must match the blade mesh Z
# size in Scenes/Skater.tscn.
@export var blade_length: float = 0.30
@export var wall_squeeze_threshold: float = 0.3

# ── Arm Tuning ────────────────────────────────────────────────────────────────
# Two-bone arm IK: shoulder → elbow → top_hand. Upper + forearm length should
# sum to ≈ rom_backhand_reach_max (SkaterController) so the hand is always
# within arm reach.
@export var upper_arm_length: float = 0.33
@export var forearm_length: float = 0.37
# Pole direction for the elbow (upper-body local). Pulled toward the top-hand
# side of the body (X sign flipped internally by handedness) and downward.
@export var arm_pole_local: Vector3 = Vector3(0.2, -1.0, 0.0)
# Base size of the arm bone meshes. scale.z is set per tick to the bone's
# actual length; X/Y control arm thickness.
@export var arm_mesh_thickness: float = 0.08

# ── Body Check Tuning ─────────────────────────────────────────────────────────
@export var weight: float = 1.0                   # dimensionless — scale up for heavy players
@export var body_check_restitution: float = 0.3   # fraction of approach speed bounced back to self
@export var body_check_transfer: float = 0.8      # fraction of approach speed pushed to victim (before weight ratio)

# ── Body Block Tuning ─────────────────────────────────────────────────────────
@export var body_block_radius: float = 0.5
@export var block_body_radius: float = 0.9    # expanded radius during active shot-block stance
@export var block_crouch_depth: float = 0.35  # how far upper_body drops during block

# ── Node References ───────────────────────────────────────────────────────────
@onready var lower_body: Node3D = $LowerBody
@onready var upper_body: Node3D = $UpperBody
@onready var blade: Marker3D = $UpperBody/Blade
@onready var shoulder: Marker3D = $UpperBody/Shoulder
@onready var stick_raycast: RayCast3D = $StickRaycast
@onready var stick_mesh: MeshInstance3D = $UpperBody/StickMesh
@onready var _upper_body_mesh: MeshInstance3D = $UpperBody/UpperBodyMesh
@onready var _blade_mesh: MeshInstance3D = $UpperBody/Blade/MeshInstance3D
@onready var _lower_body_mesh: MeshInstance3D = $LowerBody/LowerBodyMesh
@onready var _direction_indicator: MeshInstance3D = $UpperBody/DirectionIndicator

# Top hand: the moving IK output. Positioned by the controller each tick.
# If the scene file provides a `TopHand` Marker3D under UpperBody, we use it;
# otherwise we create one programmatically. Created/resolved in _ready.
var top_hand: Marker3D = null

# Bottom shoulder: anchor for the bottom (off-stick) hand. Sits on the OPPOSITE
# side from `shoulder` — the blade side. For a lefty (blade on −X), the bottom
# shoulder sits on −X. Created/resolved in _ready; scene can override by
# placing `BottomShoulder` as a Marker3D under UpperBody.
var bottom_shoulder: Marker3D = null

# Bottom hand: the reactive IK output for the bottom grip on the stick shaft.
# The controller solves its position via `BottomHandIK.solve` each tick based
# on the current top_hand + blade pose. Created/resolved in _ready like TopHand.
var bottom_hand: Marker3D = null

# Arm visual meshes (shoulder → elbow → top_hand). Created/resolved in
# _ready; scene can override by placing `UpperArmMesh` / `ForearmMesh` under
# UpperBody for custom materials.
var upper_arm_mesh: MeshInstance3D = null
var forearm_mesh: MeshInstance3D = null

# Bottom-arm visual meshes (bottom_shoulder → elbow → bottom_hand). Same
# resolve-or-create pattern as the top arm meshes.
var bottom_upper_arm_mesh: MeshInstance3D = null
var bottom_forearm_mesh: MeshInstance3D = null

signal body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3)
signal body_block_hit(body: Node3D)

# ── Runtime ───────────────────────────────────────────────────────────────────
var _facing: Vector2 = Vector2.DOWN
var is_elevated: bool = false
var is_ghost: bool = false
var blade_world_velocity: Vector3 = Vector3.ZERO
var _prev_blade_world_pos: Vector3 = Vector3.ZERO
var _body_block_area: Area3D = null
var _body_block_sphere: SphereShape3D = null
var _blade_area: Area3D = null
var _default_upper_body_y: float = 0.0

func _ready() -> void:
	# Shoulder anchors the top hand. The top hand lives on the OPPOSITE side
	# from the blade: a left-handed shooter grips with the right hand on top,
	# so the shoulder (anchor) is on the right (+X). Flipped for righties.
	# Y is lifted to `shoulder_height` so the shoulder sits up on the torso,
	# not down at the waist where the hand rests.
	var top_hand_side_sign: float = 1.0 if is_left_handed else -1.0
	shoulder.position = Vector3(top_hand_side_sign * shoulder_offset, shoulder_height, 0.0)

	# Resolve or create the TopHand marker. It starts at the shoulder's XZ
	# but at Y=0 (waist level) — the controller writes the IK-solved hand
	# position every tick, this is just the initial pose before that runs.
	top_hand = upper_body.get_node_or_null("TopHand") as Marker3D
	if top_hand == null:
		top_hand = Marker3D.new()
		top_hand.name = "TopHand"
		upper_body.add_child(top_hand)
	top_hand.position = Vector3(shoulder.position.x, 0.0, 0.0)

	# Bottom shoulder anchors the bottom hand on the OPPOSITE side — a lefty's
	# bottom hand lives on the left (−X), where the blade also is. Same Y lift
	# as the top shoulder so both arms span from the upper torso down.
	bottom_shoulder = upper_body.get_node_or_null("BottomShoulder") as Marker3D
	if bottom_shoulder == null:
		bottom_shoulder = Marker3D.new()
		bottom_shoulder.name = "BottomShoulder"
		upper_body.add_child(bottom_shoulder)
	bottom_shoulder.position = Vector3(-top_hand_side_sign * shoulder_offset, shoulder_height, 0.0)

	# Resolve or create the BottomHand marker. Mirrors TopHand.
	bottom_hand = upper_body.get_node_or_null("BottomHand") as Marker3D
	if bottom_hand == null:
		bottom_hand = Marker3D.new()
		bottom_hand.name = "BottomHand"
		upper_body.add_child(bottom_hand)
	bottom_hand.position = Vector3(bottom_shoulder.position.x, 0.0, 0.0)

	_prev_blade_world_pos = upper_body.to_global(blade.position)
	_default_upper_body_y = upper_body.position.y

	collision_layer = Constants.LAYER_SKATER_BODIES
	collision_mask  = Constants.MASK_SKATER
	stick_raycast.collision_mask = Constants.MASK_SKATER

	_blade_area = Area3D.new()
	_blade_area.name = "BladeArea"
	_blade_area.collision_layer = Constants.LAYER_BLADE_AREAS
	_blade_area.collision_mask = 0
	# Offset the pickup sphere forward by half the blade length so it centers
	# on mid-blade (the contact point) rather than the heel (Marker3D origin).
	# Forward in the Blade node's local frame is -Z (set by look_at each tick).
	_blade_area.position = Vector3(0.0, 0.0, -blade_length * 0.5)
	var blade_shape = CollisionShape3D.new()
	var blade_sphere = SphereShape3D.new()
	blade_sphere.radius = 0.3
	blade_shape.shape = blade_sphere
	_blade_area.add_child(blade_shape)
	blade.add_child(_blade_area)

	_body_block_area = Area3D.new()
	_body_block_area.name = "BodyBlockArea"
	_body_block_area.collision_layer = 0
	_body_block_area.collision_mask = Constants.LAYER_PUCK
	var block_shape := CollisionShape3D.new()
	_body_block_sphere = SphereShape3D.new()
	_body_block_sphere.radius = body_block_radius
	block_shape.shape = _body_block_sphere
	_body_block_area.add_child(block_shape)
	add_child(_body_block_area)
	_body_block_area.body_entered.connect(func(body: Node3D) -> void: body_block_hit.emit(body))

	# Resolve or create the arm meshes. Same pattern as TopHand — scene can
	# pre-place them to customize materials/size, otherwise we spawn a pair of
	# thin box meshes whose Z is stretched per tick to match the bone length.
	upper_arm_mesh = _resolve_or_create_bone_mesh("UpperArmMesh")
	forearm_mesh = _resolve_or_create_bone_mesh("ForearmMesh")
	bottom_upper_arm_mesh = _resolve_or_create_bone_mesh("BottomUpperArmMesh")
	bottom_forearm_mesh = _resolve_or_create_bone_mesh("BottomForearmMesh")

func _resolve_or_create_bone_mesh(node_name: String) -> MeshInstance3D:
	var existing: MeshInstance3D = upper_body.get_node_or_null(node_name) as MeshInstance3D
	if existing != null:
		return existing
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	# Base Z = 1.0; scale.z per tick stretches to the actual bone length.
	box.size = Vector3(arm_mesh_thickness, arm_mesh_thickness, 1.0)
	mesh_instance.mesh = box
	upper_body.add_child(mesh_instance)
	return mesh_instance

func _physics_process(delta: float) -> void:
	var blade_world_pos: Vector3 = upper_body.to_global(blade.position)
	blade_world_velocity = (blade_world_pos - _prev_blade_world_pos) / delta
	_prev_blade_world_pos = blade_world_pos
	var vel_before: Vector3 = velocity
	move_and_slide()
	_resolve_player_collisions(vel_before)

func _resolve_player_collisions(vel_before: Vector3) -> void:
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		if not col.get_collider() is Skater:
			continue
		var other := col.get_collider() as Skater
		# Use horizontal normal only — skater collisions are on the XZ plane.
		var raw_normal: Vector3 = col.get_normal()
		var normal := Vector3(raw_normal.x, 0.0, raw_normal.z)
		if normal.length() < 0.001:
			continue
		normal = normal.normalized()
		var vel_horiz := Vector3(vel_before.x, 0.0, vel_before.z)
		var approach: float = vel_horiz.dot(-normal)
		if approach <= 0.0:
			continue
		# Bounce self back away from other.
		velocity += normal * approach * body_check_restitution
		# Push other away; heavier checker transfers more to a lighter victim.
		other.velocity -= normal * approach * (weight / other.weight) * body_check_transfer
		# Signal for server-side puck strip check.
		body_checked_player.emit(other, weight * approach, -normal)

# ── Facing ────────────────────────────────────────────────────────────────────
func set_facing(facing: Vector2) -> void:
	_facing = facing
	rotation.y = atan2(-_facing.x, -_facing.y)
	lower_body.rotation.y = 0.0

func get_facing() -> Vector2:
	return _facing

func set_player_color(primary_color: Color, secondary_color: Color) -> void:
	# Primary: jersey, blade, arms
	var primary_mat := StandardMaterial3D.new()
	primary_mat.albedo_color = primary_color
	_upper_body_mesh.material_override = primary_mat
	_blade_mesh.material_override = primary_mat.duplicate()
	if upper_arm_mesh != null:
		upper_arm_mesh.material_override = primary_mat.duplicate()
	if forearm_mesh != null:
		forearm_mesh.material_override = primary_mat.duplicate()
	if bottom_upper_arm_mesh != null:
		bottom_upper_arm_mesh.material_override = primary_mat.duplicate()
	if bottom_forearm_mesh != null:
		bottom_forearm_mesh.material_override = primary_mat.duplicate()
	# Secondary: legs + helmet
	var secondary_mat := StandardMaterial3D.new()
	secondary_mat.albedo_color = secondary_color
	_lower_body_mesh.material_override = secondary_mat
	_direction_indicator.material_override = secondary_mat.duplicate()
	# Fixed stick shaft color — set explicitly so ghost mode never creates a
	# blank gray override and corrupts the color after ghost ends.
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.705, 0.640, 0.605)
	stick_mesh.material_override = stick_mat

# ── Blade ─────────────────────────────────────────────────────────────────────
func set_blade_position(pos: Vector3) -> void:
	blade.position = pos
	# Rotate blade (and its children: mesh, BladeArea) to face along the shaft.
	# Use horizontal projection so the blade stays upright despite blade_height offset.
	# Shaft origin is now the top hand (IK output), not the fixed shoulder.
	var blade_world: Vector3 = upper_body.to_global(pos)
	var hand_world: Vector3 = upper_body.to_global(top_hand.position)
	var shaft_horiz: Vector3 = blade_world - hand_world
	shaft_horiz.y = 0.0
	if shaft_horiz.length() > 0.001:
		blade.look_at(blade_world + shaft_horiz.normalized(), Vector3.UP)

func get_blade_position() -> Vector3:
	return blade.position

# World position where the puck plays on the blade — mid-blade by default.
# The Blade Marker3D is at the heel (shaft-to-blade joint); the contact point
# is blade_length * 0.5 forward along the blade's local forward axis (-Z in
# local, which set_blade_position() orients along the shaft direction each
# tick via look_at).
func get_blade_contact_global() -> Vector3:
	var heel_world: Vector3 = upper_body.to_global(blade.position)
	var forward: Vector3 = -blade.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return heel_world
	return heel_world + forward.normalized() * (blade_length * 0.5)

# ── Top Hand ──────────────────────────────────────────────────────────────────
func set_top_hand_position(pos: Vector3) -> void:
	top_hand.position = pos

func get_top_hand_position() -> Vector3:
	return top_hand.position

# ── Bottom Hand ───────────────────────────────────────────────────────────────
func set_bottom_hand_position(pos: Vector3) -> void:
	bottom_hand.position = pos

func get_bottom_hand_position() -> Vector3:
	return bottom_hand.position

# ── Upper Body ────────────────────────────────────────────────────────────────
func set_upper_body_rotation(angle: float) -> void:
	upper_body.rotation.y = angle

func get_upper_body_rotation() -> float:
	return upper_body.rotation.y

# ── Wall Clamping ─────────────────────────────────────────────────────────────
func clamp_blade_to_walls(local_pos: Vector3) -> Vector3:
	var to_blade: Vector3 = local_pos
	to_blade.y = 0.0
	stick_raycast.target_position = to_blade
	stick_raycast.force_raycast_update()

	if stick_raycast.is_colliding():
		var hit_dist: float = global_position.distance_to(stick_raycast.get_collision_point())
		var blade_dist: float = to_blade.length()
		if hit_dist < blade_dist:
			var clamped_dist: float = maxf(hit_dist - 0.05, 0.1)
			local_pos = to_blade.normalized() * clamped_dist
			local_pos.y = blade_height

	return local_pos

func get_wall_squeeze(intended_pos: Vector3, clamped_pos: Vector3) -> float:
	return intended_pos.length() - clamped_pos.length()

func get_blade_wall_normal() -> Vector3:
	if stick_raycast.is_colliding():
		return stick_raycast.get_collision_normal()
	return Vector3.ZERO

# ── Stick Mesh ────────────────────────────────────────────────────────────────
func update_stick_mesh() -> void:
	# Stick runs from the top hand (IK output) to the blade.
	var stick_origin: Vector3 = top_hand.position
	var to_blade: Vector3 = blade.position - stick_origin
	stick_mesh.position = stick_origin + to_blade / 2.0
	stick_mesh.scale.z = to_blade.length()
	stick_mesh.look_at(upper_body.to_global(blade.position), Vector3.UP)

# ── Arm Mesh ──────────────────────────────────────────────────────────────────
# Renders the two-bone arm between the shoulder (anchor) and top_hand (IK
# output). Elbow position from TwoBoneIK.solve_elbow; pole direction is pulled
# toward the top-hand side of the body and slightly downward so the elbow
# hangs naturally.
func update_arm_mesh() -> void:
	var shoulder_w: Vector3 = upper_body.to_global(shoulder.position)
	var hand_w: Vector3 = upper_body.to_global(top_hand.position)
	# Flip the pole's X toward the top-hand side of the body. Pole is expressed
	# as if the top hand were on +X; handedness flip mirrors for righties.
	var pole_local: Vector3 = arm_pole_local
	pole_local.x *= 1.0 if is_left_handed else -1.0
	var pole_w: Vector3 = upper_body.global_transform.basis * pole_local
	var elbow_w: Vector3 = TwoBoneIK.solve_elbow(
			shoulder_w, hand_w, upper_arm_length, forearm_length, pole_w)
	_update_bone_mesh(upper_arm_mesh, shoulder_w, elbow_w)
	_update_bone_mesh(forearm_mesh, elbow_w, hand_w)

# ── Bottom Arm Mesh ───────────────────────────────────────────────────────────
# Renders the two-bone arm for the bottom hand. Same anatomy (upper_arm_length
# / forearm_length) as the top arm; pole direction is mirrored so the bottom
# elbow hangs toward its own (blade) side.
func update_bottom_arm_mesh() -> void:
	var shoulder_w: Vector3 = upper_body.to_global(bottom_shoulder.position)
	var hand_w: Vector3 = upper_body.to_global(bottom_hand.position)
	# Mirror of the top-arm pole flip: bottom elbow leans toward the bottom-hand
	# side, which is the opposite X sign from the top hand.
	var pole_local: Vector3 = arm_pole_local
	pole_local.x *= -1.0 if is_left_handed else 1.0
	var pole_w: Vector3 = upper_body.global_transform.basis * pole_local
	var elbow_w: Vector3 = TwoBoneIK.solve_elbow(
			shoulder_w, hand_w, upper_arm_length, forearm_length, pole_w)
	_update_bone_mesh(bottom_upper_arm_mesh, shoulder_w, elbow_w)
	_update_bone_mesh(bottom_forearm_mesh, elbow_w, hand_w)

func _update_bone_mesh(mesh: MeshInstance3D, a_world: Vector3, b_world: Vector3) -> void:
	if mesh == null:
		return
	var a_local: Vector3 = upper_body.to_local(a_world)
	var b_local: Vector3 = upper_body.to_local(b_world)
	var length: float = (b_local - a_local).length()
	mesh.position = (a_local + b_local) * 0.5
	mesh.scale = Vector3(1.0, 1.0, maxf(length, 0.001))
	if (b_world - a_world).length() > 0.0001:
		mesh.look_at(b_world, Vector3.UP)

# ── Coordinate Helpers ────────────────────────────────────────────────────────
func upper_body_to_global(local_pos: Vector3) -> Vector3:
	return upper_body.to_global(local_pos)

func upper_body_to_local(world_pos: Vector3) -> Vector3:
	return upper_body.to_local(world_pos)

# ── Ghost Mode ────────────────────────────────────────────────────────────
func set_ghost(ghost: bool) -> void:
	if is_ghost == ghost:
		return
	is_ghost = ghost
	if ghost:
		_blade_area.collision_layer = 0
		_body_block_area.collision_mask = 0
		collision_layer = 0
		collision_mask = Constants.LAYER_WALLS
	else:
		_blade_area.collision_layer = Constants.LAYER_BLADE_AREAS
		_body_block_area.collision_mask = Constants.LAYER_PUCK
		collision_layer = Constants.LAYER_SKATER_BODIES
		collision_mask = Constants.MASK_SKATER
	_apply_ghost_visual(ghost)

# ── Shot-Block Stance ─────────────────────────────────────────────────────────
func set_block_stance(active: bool) -> void:
	_body_block_sphere.radius = block_body_radius if active else body_block_radius
	upper_body.position.y = _default_upper_body_y - block_crouch_depth if active else _default_upper_body_y
	# Disable blade pickup while blocking so the puck can't be picked up
	_blade_area.collision_layer = 0 if active else Constants.LAYER_BLADE_AREAS

func _apply_ghost_visual(ghost: bool) -> void:
	var meshes: Array[MeshInstance3D] = [
			_upper_body_mesh, _blade_mesh, stick_mesh,
			upper_arm_mesh, forearm_mesh,
			bottom_upper_arm_mesh, bottom_forearm_mesh,
			_lower_body_mesh, _direction_indicator,
		]
	for mesh: MeshInstance3D in meshes:
		if mesh == null:
			continue
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh.material_override = mat
		if ghost:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.3
		else:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0

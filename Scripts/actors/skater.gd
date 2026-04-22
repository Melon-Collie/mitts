class_name Skater
extends CharacterBody3D

# ── Character ─────────────────────────────────────────────────────────────────
@export var is_left_handed: bool = true

# ── Blade Tuning ──────────────────────────────────────────────────────────────
# Shoulder anchor offset from body center. The shoulder (top-hand anchor)
# sits on the OPPOSITE side of the body from the blade: a left-handed shooter
# (blade on −X) has the top hand on the right shoulder (+X), and vice versa.
# Baseline ~0.22 m (half of adult shoulder-to-shoulder breadth).
@export var shoulder_offset: float = 0.22
# Shoulder Y in upper-body-local space. Positions the arm's anchor high on
# the torso (near the top of the upper body mesh) so the visible arm spans
# from the shoulder down to the hand. Vertical drop from shoulder to hand at
# rest = shoulder_height − hand_rest_y (currently 0.35 − (−0.17) = 0.52 m).
# If rom_backhand_reach_max is raised, verify sqrt(drop² + reach²) stays
# under upper_arm_length + forearm_length to avoid visible arm stretch.
@export var shoulder_height: float = 0.35
# Blade length (heel to toe). The Blade Marker3D represents the heel (where
# the shaft meets the blade); the blade mesh extends forward by this distance.
# The puck plays at the contact point, which is blade_length * 0.5 forward
# of the Marker3D along its local forward axis. Must match the blade mesh Z
# size in Scenes/Skater.tscn.
@export var blade_length: float = 0.30
@export var wall_squeeze_threshold: float = 0.3

# ── Arm Tuning ────────────────────────────────────────────────────────────────
# Two-bone arm IK: shoulder → elbow → top_hand. Sum must exceed
# sqrt(drop² + rom_backhand_reach_max²) where drop = shoulder_height − hand_rest_y.
# Current drop = 0.35 − (−0.17) = 0.52 m; max safe reach = sqrt(0.90²−0.52²) ≈ 0.735 m,
# which clears rom_backhand_reach_max (0.70 m) with headroom.
@export var upper_arm_length: float = 0.44
@export var forearm_length: float = 0.46
# Pole direction for the elbow (upper-body local). Pulled toward the top-hand
# side of the body (X sign flipped internally by handedness) and downward.
@export var arm_pole_local: Vector3 = Vector3(0.2, -1.0, 0.0)
# Base size of the arm bone meshes. scale.z is set per tick to the bone's
# actual length; X/Y control arm thickness.
@export var arm_mesh_thickness: float = 0.10

# ── Body Check Tuning ─────────────────────────────────────────────────────────
@export var weight: float = 1.0                   # dimensionless — scale up for heavy players
@export var body_check_restitution: float = 0.3   # fraction of approach speed bounced back to self
@export var body_check_transfer: float = 0.8      # fraction of approach speed pushed to victim (before weight ratio)
@export var body_check_brace_resistance: float = 0.4  # multiplier on transfer when the victim is braced (holding brake)

# ── Body Block Tuning ─────────────────────────────────────────────────────────
@export var body_block_radius: float = 0.5
@export var block_body_radius: float = 0.9    # expanded radius during active shot-block stance
@export var block_crouch_depth: float = 0.35  # how far upper_body drops during block

# ── Node References ───────────────────────────────────────────────────────────
@onready var mesh_root: Node3D = $MeshRoot
@onready var lower_body: Node3D = $MeshRoot/LowerBody
@onready var upper_body: Node3D = $MeshRoot/UpperBody
@onready var blade: Marker3D = $MeshRoot/UpperBody/Blade
@onready var shoulder: Marker3D = $MeshRoot/UpperBody/Shoulder
@onready var stick_mesh: MeshInstance3D = $MeshRoot/UpperBody/StickMesh
@onready var _upper_body_mesh: MeshInstance3D = $MeshRoot/UpperBody/UpperBodyMesh
@onready var _blade_mesh: MeshInstance3D = $MeshRoot/UpperBody/Blade/MeshInstance3D
@onready var _lower_body_mesh: MeshInstance3D = $MeshRoot/LowerBody/LowerBodyMesh
@onready var _direction_indicator: MeshInstance3D = $MeshRoot/UpperBody/DirectionIndicator

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

# Optional sock and skate meshes. Resolved from scene nodes in _ready;
# guarded by null-checks so the skater works before the user adds the meshes.
var _sock_mesh: MeshInstance3D = null
var _skate_mesh: MeshInstance3D = null

signal body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3)
signal body_check_impulse_applied(impulse: Vector3)
signal body_block_hit(body: Node3D)
# ── Runtime ───────────────────────────────────────────────────────────────────
var _ring_mesh: MeshInstance3D = null
var _facing: Vector2 = Vector2.DOWN
var is_elevated: bool = false
var is_ghost: bool = false
var is_braking: bool = false
var is_braced: bool = false
var shot_charge: float = 0.0
var slapper_aim_dir: Vector3 = Vector3.ZERO
var blade_world_velocity: Vector3 = Vector3.ZERO
var _prev_blade_world_pos: Vector3 = Vector3.ZERO
var _prev_blade_contact: Vector3 = Vector3.ZERO
var _last_wall_normal: Vector3 = Vector3.ZERO
var _body_block_area: Area3D = null
var _body_block_sphere: SphereShape3D = null
var _blade_area: Area3D = null
# Ground-level pickup zone for slapper one-timers. Activated during
# SLAPPER_CHARGE_WITHOUT_PUCK so the puck can be detected at ice level even
# though the blade is lifted. Child of the Skater body (not the blade) so its
# Y stays fixed at ground level regardless of blade pose.
var _slapper_zone_area: Area3D = null
var _slapper_zone_sphere: SphereShape3D = null
var _default_upper_body_y: float = 0.0
# Visual-only offset applied to MeshRoot each frame. Set by LocalController
# during reconcile blending to ease the visible correction over a few ticks.
# Physics body (CharacterBody3D) is always at the authoritative position.
var visual_offset: Vector3 = Vector3.ZERO:
	set(v):
		visual_offset = v
		if mesh_root != null:
			mesh_root.position = global_transform.basis.inverse() * v


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

	# Slapper one-timer zone: ice-level sphere on the skater body. Activated only
	# during SLAPPER_CHARGE_WITHOUT_PUCK via set_slapper_zone(). Radius is set at
	# activation time (controller passes slapper_zone_radius). Starts inactive.
	_slapper_zone_area = Area3D.new()
	_slapper_zone_area.name = "SlapperZoneArea"
	_slapper_zone_area.collision_layer = 0
	_slapper_zone_area.collision_mask = 0
	var zone_shape := CollisionShape3D.new()
	_slapper_zone_sphere = SphereShape3D.new()
	_slapper_zone_sphere.radius = 1.0
	zone_shape.shape = _slapper_zone_sphere
	_slapper_zone_area.add_child(zone_shape)
	add_child(_slapper_zone_area)

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

	_sock_mesh  = lower_body.get_node_or_null("SockMesh") as MeshInstance3D
	_skate_mesh = lower_body.get_node_or_null("SkateMesh") as MeshInstance3D

	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "RingIndicator"
	_ring_mesh.mesh = _create_ring_mesh(0.34, 0.45, 32)
	_ring_mesh.position = Vector3.ZERO
	_ring_mesh.visible = false
	add_child(_ring_mesh)

	var vfx := SkaterVFX.new()
	vfx.name = "VFX"
	add_child(vfx)

func _create_ring_mesh(inner_r: float, outer_r: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i: int in segments:
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var base: int = verts.size()
		verts.append(Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r))
		verts.append(Vector3(cos(a0) * outer_r, 0.0, sin(a0) * outer_r))
		verts.append(Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r))
		verts.append(Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r))
		for _n: int in 4:
			normals.append(Vector3.UP)
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

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
	_prev_blade_contact = get_blade_contact_global()
	var blade_world_pos: Vector3 = upper_body.to_global(blade.position)
	blade_world_velocity = (blade_world_pos - _prev_blade_world_pos) / delta
	_prev_blade_world_pos = blade_world_pos
	var vel_before: Vector3 = velocity
	move_and_slide()
	var vel_after_slide: Vector3 = velocity
	_resolve_player_collisions(vel_before)
	var body_check_delta: Vector3 = velocity - vel_after_slide
	if body_check_delta.length_squared() > 0.0001:
		body_check_impulse_applied.emit(body_check_delta)
	if _ring_mesh != null:
		_ring_mesh.global_position.y = 0.05

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
		# Reduce transfer when the victim is bracing (holding brake).
		var effective_transfer: float = body_check_transfer * (other.body_check_brace_resistance if other.is_braced else 1.0)
		other.velocity -= normal * approach * (weight / other.weight) * effective_transfer
		# Signal for server-side puck strip check.
		body_checked_player.emit(other, weight * approach, -normal)

# ── Facing ────────────────────────────────────────────────────────────────────
func set_facing(facing: Vector2) -> void:
	_facing = facing
	rotation.y = atan2(-_facing.x, -_facing.y)

func set_lower_body_lag(angle: float) -> void:
	lower_body.rotation.y = angle

func get_facing() -> Vector2:
	return _facing

func _make_solid_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func set_player_color(
		jersey_color: Color,
		helmet_color: Color,
		pants_color: Color,
		socks_color: Color) -> void:
	var jersey_mat: StandardMaterial3D = _make_solid_mat(jersey_color)
	_upper_body_mesh.material_override = jersey_mat
	_blade_mesh.material_override = jersey_mat.duplicate()
	if upper_arm_mesh != null:
		upper_arm_mesh.material_override = jersey_mat.duplicate()
	if forearm_mesh != null:
		forearm_mesh.material_override = jersey_mat.duplicate()
	if bottom_upper_arm_mesh != null:
		bottom_upper_arm_mesh.material_override = jersey_mat.duplicate()
	if bottom_forearm_mesh != null:
		bottom_forearm_mesh.material_override = jersey_mat.duplicate()
	_direction_indicator.material_override = _make_solid_mat(helmet_color)
	_lower_body_mesh.material_override = _make_solid_mat(pants_color)
	if _sock_mesh != null:
		_sock_mesh.material_override = _make_solid_mat(socks_color)
	# Fixed colors — set explicitly so ghost mode never creates a blank gray
	# override and corrupts the color after ghost ends.
	stick_mesh.material_override = _make_solid_mat(Color(0.705, 0.640, 0.605))
	if _skate_mesh != null:
		_skate_mesh.material_override = _make_solid_mat(Color(0.08, 0.08, 0.08))

func set_ring_color(color: Color) -> void:
	if _ring_mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	_ring_mesh.material_override = mat
	_ring_mesh.visible = true

func set_jersey_info(p_name: String, number: int, text_color: Color) -> void:
	for child: Node in upper_body.get_children():
		if child.name in ["JerseyBackMesh", "JerseyShoulderL", "JerseyShoulderR"]:
			child.queue_free()

	var tex: ImageTexture = JerseyTextureGenerator.make_jersey_texture(p_name, number, text_color)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	# UpperBodyMesh is a 0.5×0.65×0.28 BoxMesh centered at (0, 0.3, 0) in
	# UpperBody local space. Back surface is at Z = +0.14; place the quad just
	# outside it. Quad faces +Z by default (toward viewer standing behind).
	var quad := QuadMesh.new()
	quad.size = Vector2(0.40, 0.30)  # 4:3 matches 256×192 texture

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "JerseyBackMesh"
	mesh_inst.mesh = quad
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(0.0, 0.36, 0.15)
	upper_body.add_child(mesh_inst)

	var shoulder_tex: ImageTexture = JerseyTextureGenerator.make_shoulder_texture(number, text_color)
	var left_shoulder: MeshInstance3D = JerseyTextureGenerator.make_shoulder_mesh(shoulder_tex, -0.14)
	left_shoulder.name = "JerseyShoulderL"
	var right_shoulder: MeshInstance3D = JerseyTextureGenerator.make_shoulder_mesh(shoulder_tex, 0.14)
	right_shoulder.name = "JerseyShoulderR"
	upper_body.add_child(left_shoulder)
	upper_body.add_child(right_shoulder)


func set_jersey_stripes(
		jersey_stripe_color: Color,
		pants_stripe_color: Color,
		socks_stripe_color: Color) -> void:
	# Remove any previously generated stripe nodes.
	for node: Node in upper_body.get_children():
		if node.name.begins_with("Stripe_"):
			node.queue_free()
	for node: Node in lower_body.get_children():
		if node.name.begins_with("Stripe_"):
			node.queue_free()
	if top_hand != null:
		for node: Node in top_hand.get_children():
			if node.name.begins_with("Stripe_"):
				node.queue_free()
	if bottom_hand != null:
		for node: Node in bottom_hand.get_children():
			if node.name.begins_with("Stripe_"):
				node.queue_free()

	# Jersey hem band — bottom 0.08 m of the UpperBodyMesh
	# (BoxMesh 0.5×0.65×0.28, center (0,0.3,0) → bottom at y = -0.025).
	var hem_quads: Array = JerseyTextureGenerator.make_box_stripe_band(
			Vector3(0.0, 0.3, 0.0), Vector3(0.25, 0.325, 0.14),
			-0.025, 0.08, jersey_stripe_color, "Stripe_JerseyHem")
	for q: MeshInstance3D in hem_quads:
		upper_body.add_child(q)

	# Sleeve cuff band — around the wrist at top_hand / bottom_hand positions.
	var cuff_half: float = arm_mesh_thickness * 0.5 + 0.01
	if top_hand != null:
		var top_cuffs: Array = JerseyTextureGenerator.make_sleeve_cuff(
				cuff_half, 0.06, jersey_stripe_color, "Stripe_CuffTop")
		for q: MeshInstance3D in top_cuffs:
			top_hand.add_child(q)
	if bottom_hand != null:
		var bot_cuffs: Array = JerseyTextureGenerator.make_sleeve_cuff(
				cuff_half, 0.06, jersey_stripe_color, "Stripe_CuffBot")
		for q: MeshInstance3D in bot_cuffs:
			bottom_hand.add_child(q)

	# Pants side stripe — full-height vertical piping on the ±X faces
	# (LowerBodyMesh BoxMesh 0.45×0.4×0.3, center (0,−0.2,0)).
	var pants_quads: Array = JerseyTextureGenerator.make_box_side_stripe(
			Vector3(0.0, -0.2, 0.0), Vector3(0.225, 0.2, 0.15),
			0.07, pants_stripe_color, "Stripe_Pants")
	for q: MeshInstance3D in pants_quads:
		lower_body.add_child(q)

	# Sock stripe — if SockMesh is present in the scene.
	if _sock_mesh != null:
		var sock_box: BoxMesh = _sock_mesh.mesh as BoxMesh
		if sock_box != null:
			var sh: Vector3 = sock_box.size * 0.5
			var sc: Vector3 = _sock_mesh.position
			var sock_quads: Array = JerseyTextureGenerator.make_box_stripe_band(
					sc, sh, sc.y + sh.y * 0.3, sh.y * 0.4,
					socks_stripe_color, "Stripe_Sock")
			for q: MeshInstance3D in sock_quads:
				lower_body.add_child(q)

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

func get_prev_blade_contact_global() -> Vector3:
	return _prev_blade_contact

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

func set_upper_body_lean(lean_x: float, lean_z: float = 0.0) -> void:
	upper_body.rotation.x = lean_x
	upper_body.rotation.z = lean_z

func set_lower_body_lean(lean_x: float, lean_z: float) -> void:
	lower_body.rotation.x = lean_x
	lower_body.rotation.z = lean_z

func set_head_angle(angle: float) -> void:
	_direction_indicator.rotation.y = angle

func set_slapper_mode(active: bool) -> void:
	_blade_area.collision_layer = 0 if active else Constants.LAYER_BLADE_AREAS

func set_slapper_zone(active: bool, radius: float = 0.0, offset_x: float = 0.0, offset_z: float = 0.0) -> void:
	if active and radius > 0.0:
		_slapper_zone_sphere.radius = radius
		var blade_side_sign: float = -1.0 if is_left_handed else 1.0
		_slapper_zone_area.position = Vector3(blade_side_sign * offset_x, 0.0, offset_z)
	_slapper_zone_area.collision_layer = Constants.LAYER_BLADE_AREAS if active else 0

func is_slapper_zone_active() -> bool:
	return _slapper_zone_area.collision_layer != 0

func get_slapper_zone_global_position() -> Vector3:
	return _slapper_zone_area.global_position

func get_slapper_zone_radius() -> float:
	return _slapper_zone_sphere.radius

func get_upper_body_rotation() -> float:
	return upper_body.rotation.y

# ── Wall Clamping ─────────────────────────────────────────────────────────────
# Analytic rink boundary check using the rounded-rectangle inner wall surface.
# Replaces the old RayCast3D approach, which could miss gaps between the
# segmented corner collision boxes and let the blade clip through curved walls.
func clamp_blade_to_walls(local_pos: Vector3) -> Vector3:
	_last_wall_normal = Vector3.ZERO
	var blade_world: Vector3 = upper_body.to_global(local_pos)
	var blade_xz := Vector2(blade_world.x, blade_world.z)
	var clamped_xz: Vector2 = GameRules.clamp_to_rink_inner(blade_xz)
	if clamped_xz.distance_squared_to(blade_xz) < 0.0001:
		return local_pos
	# Inward-pointing wall normal (direction to push the puck away from the wall).
	_last_wall_normal = Vector3(
		clamped_xz.x - blade_xz.x,
		0.0,
		clamped_xz.y - blade_xz.y
	).normalized()
	var clamped_world := Vector3(clamped_xz.x, blade_world.y, clamped_xz.y)
	return upper_body.to_local(clamped_world)

func get_wall_squeeze(intended_pos: Vector3, clamped_pos: Vector3) -> float:
	return intended_pos.length() - clamped_pos.length()

func get_blade_wall_normal() -> Vector3:
	return _last_wall_normal

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
		_slapper_zone_area.collision_layer = 0
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
			_sock_mesh, _skate_mesh,
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
	for n: String in ["JerseyBackMesh", "JerseyShoulderL", "JerseyShoulderR"]:
		var m: Node = upper_body.get_node_or_null(n)
		if m:
			m.visible = not ghost

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
# Sleeve cuff stripe meshes. Created by set_jersey_stripes() and updated
# each frame in update_arm_mesh() / update_bottom_arm_mesh() so they stay
# perpendicular to the forearm bone direction as the arm moves.
var _top_cuff_mesh: MeshInstance3D = null
var _bot_cuff_mesh: MeshInstance3D = null

signal body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3)
signal body_check_impulse_applied(impulse: Vector3)
signal body_block_hit(body: Node3D)
# ── Runtime ───────────────────────────────────────────────────────────────────
var _ring_mesh: MeshInstance3D = null
var _charge_ring_mesh: MeshInstance3D = null
var _charge_ring_mat: ShaderMaterial = null
var _chevron_mesh: MeshInstance3D = null
var _name_label_root: Node3D = null
var _name_char_labels: Array[Label3D] = []
var _name_text: String = ""
var _slapper_arrow_mesh: MeshInstance3D = null
var _slapper_arrow_root: Node3D = null
var _slapper_indicator: Node3D = null
var _slapper_indicator_mat: StandardMaterial3D = null
var _slapper_arm_nodes: Array[MeshInstance3D] = []
const _SLAPPER_ARM_DIRS: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
]
# All arm constants are in unit (1 m) space; _slapper_indicator.scale applies radius.
const _SLAPPER_ARM_LENGTH: float = 0.30  # fixed arm length; arms slide, don't resize

# ── HUD geometry (ice-blue overlay system) ────────────────────────────────────
# Slot ring sits just inside RING_OUTER_R. Charge ring is concentric, just
# outside, with a small gap. Chevron and player name sit below the rings on
# the +Z side (player's "back-of-feet" relative to camera).
const RING_OUTER_R: float       = 0.45
const CHARGE_RING_GAP: float    = 0.02
const CHARGE_RING_OUTER_R: float = 0.49
const CHARGE_RING_INNER_R: float = CHARGE_RING_OUTER_R - 0.04
const _CHARGE_FULL_PULSE_HZ: float = 3.0
const _CHARGE_LOST_FLASH_DURATION: float = 0.35

# Curved-name layout. Each character is its own Label3D positioned on an arc
# centered on the screen-down direction. Radius and per-char angular spacing
# are tuned for readability at typical hockey camera height.
const _NAME_ARC_RADIUS: float = RING_OUTER_R + 0.22
const _NAME_CHAR_ANGLE_DEG: float = 7.0
const _NAME_CHEVRON_GAP_DEG: float = 7.0

# Charge ring shader: angle-mask + tri-color blend. Fill goes clockwise from 12
# o'clock as viewed from above. UV.x of the procedural ring encodes 0..1
# clockwise; fragment discards above `fill`. Lost-flash overrides fill color.
const _CHARGE_RING_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;       // 1.0 at full charge → modulates alpha
uniform float lost_flash : hint_range(0.0, 1.0) = 0.0;  // 1.0 just after charge cancel
uniform vec4 color_low;
uniform vec4 color_high;
uniform vec4 color_full;
uniform vec4 color_lost;
uniform float opacity = 0.7;

void fragment() {
	float t = UV.x;
	if (t > fill && lost_flash < 0.001) {
		discard;
	}
	vec3 base = mix(color_low.rgb, color_high.rgb, clamp(fill, 0.0, 1.0));
	if (pulse > 0.001) {
		base = mix(base, color_full.rgb, pulse);
	}
	if (lost_flash > 0.001) {
		base = mix(base, color_lost.rgb, lost_flash);
	}
	ALBEDO = base;
	ALPHA = opacity * (lost_flash > 0.001 ? lost_flash : 1.0);
}
"""
var _facing: Vector2 = Vector2.DOWN
var is_elevated: bool = false
var is_ghost: bool = false
var is_braking: bool = false
var is_braced: bool = false
var shot_charge: float = 0.0
var slapper_aim_dir: Vector3 = Vector3.ZERO
# Drives the charge ring + lost-flash pulse. Set by LocalController only;
# remote skaters leave these at defaults so the charge ring stays hidden.
var _charge_ring_visible: bool = false
var _charge_lost_flash_timer: float = 0.0
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
	_ring_mesh.mesh = _create_ring_mesh(RING_OUTER_R - MenuStyle.HUD_LINE_THIN, RING_OUTER_R, 48)
	_ring_mesh.position = Vector3.ZERO
	_ring_mesh.material_override = _make_hud_ice_material()
	add_child(_ring_mesh)

	_charge_ring_mesh = MeshInstance3D.new()
	_charge_ring_mesh.name = "ChargeRing"
	_charge_ring_mesh.mesh = _create_ring_mesh_with_uv(
			CHARGE_RING_INNER_R, CHARGE_RING_OUTER_R, 64)
	_charge_ring_mat = _make_charge_ring_material()
	_charge_ring_mesh.material_override = _charge_ring_mat
	_charge_ring_mesh.visible = false
	add_child(_charge_ring_mesh)

	_chevron_mesh = MeshInstance3D.new()
	_chevron_mesh.name = "ElevatedChevron"
	_chevron_mesh.top_level = true
	_chevron_mesh.mesh = _create_chevron_mesh()
	_chevron_mesh.material_override = _make_hud_ice_material()
	_chevron_mesh.visible = false
	add_child(_chevron_mesh)

	# Player name billboard. `top_level = true` so it inherits neither the
	# skater's rotation nor its body Y — its world transform is rewritten each
	# tick in _physics_process so the on-screen position stays stable as the
	# skater turns. Always reads at +Z world offset from the body, so on a
	# typical end-on hockey camera it sits at a consistent screen edge.
	# Curved player name. One Label3D per character, parented under a
	# top-level root so we can keep the per-tick world placement loop tight
	# (just walk the children). Each label billboards to face the camera
	# while its position rides an arc around the slot ring.
	_name_label_root = Node3D.new()
	_name_label_root.name = "PlayerNameRoot"
	_name_label_root.top_level = true
	add_child(_name_label_root)

	_slapper_indicator = Node3D.new()
	_slapper_indicator.name = "SlapperIndicator"
	_slapper_indicator.visible = false
	add_child(_slapper_indicator)
	_slapper_indicator_mat = _make_hud_ice_material()
	# Y rotations that align each arm's local +Z with its world direction.
	var arm_y_rots: Array[float] = [90.0, -90.0, 0.0, 180.0]
	for i: int in _SLAPPER_ARM_DIRS.size():
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(MenuStyle.HUD_LINE_THIN, 0.005, _SLAPPER_ARM_LENGTH)
		arm.mesh = box
		arm.material_override = _slapper_indicator_mat
		arm.rotation_degrees.y = arm_y_rots[i]
		_slapper_indicator.add_child(arm)
		_slapper_arm_nodes.append(arm)
	update_slapper_indicator_convergence(1.0)

	# Slapshot direction arrow. Sits at the slapper-zone center (whichever
	# offset the controller passes via set_slapshot_arrow); rotates each tick
	# to face slapper_aim_dir. Outline-only style — drawn as four thin boxes
	# (two shaft sides + two arrowhead sides).
	_slapper_arrow_root = Node3D.new()
	_slapper_arrow_root.name = "SlapperArrow"
	_slapper_arrow_root.visible = false
	add_child(_slapper_arrow_root)
	_slapper_arrow_mesh = _create_arrow_mesh()
	_slapper_arrow_mesh.material_override = _make_hud_ice_material()
	_slapper_arrow_root.add_child(_slapper_arrow_mesh)

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

# Variant of _create_ring_mesh that bakes a clockwise-from-12-o'clock UV.x onto
# every vertex (UV.x = 0 at angle 0 / +Z, growing clockwise to 1 at TAU). The
# charge-ring shader uses UV.x as the angular fill mask. UV.y stays 0/1 across
# the rim so a future "rim glow" gradient could read it.
func _create_ring_mesh_with_uv(inner_r: float, outer_r: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i: int in segments:
		# Start angle at -PI/2 (top of ring, +Z-forward in world after parent
		# rotation) and progress clockwise so charge fills like a wall clock.
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var a0: float = -PI * 0.5 - t0 * TAU
		var a1: float = -PI * 0.5 - t1 * TAU
		var base: int = verts.size()
		verts.append(Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r))
		verts.append(Vector3(cos(a0) * outer_r, 0.0, sin(a0) * outer_r))
		verts.append(Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r))
		verts.append(Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r))
		uvs.append(Vector2(t0, 0.0))
		uvs.append(Vector2(t0, 1.0))
		uvs.append(Vector2(t1, 0.0))
		uvs.append(Vector2(t1, 1.0))
		for _n: int in 4:
			normals.append(Vector3.UP)
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Upward-pointing chevron drawn flat on the ice. Two thin legs forming a "^",
# placed below the slot ring on the +Z side (back of the player relative to
# camera-forward). Thickness uses MenuStyle.HUD_LINE_THIN so it visually
# matches the slot ring stroke.
func _create_chevron_mesh() -> ArrayMesh:
	# Built at the origin pointing UP in screen-space (vertex tip toward -Z in
	# the chevron's local frame). The mesh is repositioned each tick from
	# _physics_process using camera-aware screen axes.
	var size: float = 0.28                       # full chevron height/width (bigger so it reads at 15m camera)
	var leg_len: float = size * 0.7
	var thickness: float = MenuStyle.HUD_LINE_THICK
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	# Two legs of a "^" meeting at origin, each angled 45° off the chevron's
	# local +Z axis. After the per-tick world transform places the chevron at
	# the right of the name label and rotates it to face screen-up, the legs
	# read as an upward chevron regardless of camera flip.
	var legs: Array = [
		{ "rot": deg_to_rad(135.0), "anchor": Vector3.ZERO },
		{ "rot": deg_to_rad(-135.0), "anchor": Vector3.ZERO },
	]
	for leg: Dictionary in legs:
		var rot_y: float = leg.rot
		var anchor: Vector3 = leg.anchor
		var dir := Vector3(sin(rot_y), 0.0, -cos(rot_y))   # forward along the leg
		var perp := Vector3(cos(rot_y), 0.0, sin(rot_y))   # widthwise
		var half_t: float = thickness * 0.5
		var p0: Vector3 = anchor + perp * half_t
		var p1: Vector3 = anchor - perp * half_t
		var p2: Vector3 = anchor + dir * leg_len + perp * half_t
		var p3: Vector3 = anchor + dir * leg_len - perp * half_t
		var base: int = verts.size()
		verts.append(p0); verts.append(p1); verts.append(p2); verts.append(p3)
		for _n: int in 4:
			normals.append(Vector3.UP)
		indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Outline arrow drawn flat on the ice, pointing along +Z. Six edges form a
# closed arrow shape with the base (z = 0) left open: two shaft sides + two
# shoulder segments (where the shaft widens into the head) + two head
# diagonals meeting at the tip. Drawn as thin strips, one per edge.
func _create_arrow_mesh() -> MeshInstance3D:
	var shaft_len: float = 0.55
	var head_len: float  = 0.18
	var head_half_w: float = 0.16
	var shaft_half_w: float = 0.05
	var thickness: float = MenuStyle.HUD_LINE_THICK
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var tip := Vector2(0.0, shaft_len + head_len)

	# Shape edges, each a 2D segment in (x, z). Drawn as a thin strip of width
	# `thickness` perpendicular to the segment direction.
	var edges: Array[Array] = []
	for sign_x: float in [-1.0, 1.0]:
		var shaft_base   := Vector2(sign_x * shaft_half_w, 0.0)
		var shaft_top    := Vector2(sign_x * shaft_half_w, shaft_len)
		var head_shoulder := Vector2(sign_x * head_half_w,  shaft_len)
		# Shaft side: base → shoulder-base
		edges.append([shaft_base, shaft_top])
		# Shoulder: shaft top → head outer corner (perpendicular to shaft)
		edges.append([shaft_top, head_shoulder])
		# Head diagonal: head outer corner → tip
		edges.append([head_shoulder, tip])

	for edge_pair: Array in edges:
		var a_pt: Vector2 = edge_pair[0]
		var b_pt: Vector2 = edge_pair[1]
		var edge: Vector2 = b_pt - a_pt
		var edge_len: float = edge.length()
		if edge_len < 0.0001:
			continue
		var edge_dir: Vector2 = edge / edge_len
		var edge_perp := Vector2(-edge_dir.y, edge_dir.x)
		var half_t: float = thickness * 0.5
		var p0: Vector2 = a_pt + edge_perp * half_t
		var p1: Vector2 = a_pt - edge_perp * half_t
		var p2: Vector2 = b_pt - edge_perp * half_t
		var p3: Vector2 = b_pt + edge_perp * half_t
		_append_quad(verts, normals, indices,
				p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	return inst

# Append an XZ-plane quad (Y = 0) defined by 4 corner XZ pairs. Triangulated
# fan-style: (0,1,2), (0,2,3). Caller must supply corners in CW or CCW order.
func _append_quad(
		verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		x0: float, z0: float, x1: float, z1: float,
		x2: float, z2: float, x3: float, z3: float) -> void:
	var base: int = verts.size()
	verts.append(Vector3(x0, 0.0, z0))
	verts.append(Vector3(x1, 0.0, z1))
	verts.append(Vector3(x2, 0.0, z2))
	verts.append(Vector3(x3, 0.0, z3))
	for _n: int in 4:
		normals.append(Vector3.UP)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

# Solid ice-blue material at HUD opacity, unshaded, alpha-blended. Shared by
# every HUD-on-ice element except the charge ring (which has its own shader).
func _make_hud_ice_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(MenuStyle.HUD_ICE.r, MenuStyle.HUD_ICE.g,
			MenuStyle.HUD_ICE.b, MenuStyle.HUD_OPACITY)
	return mat

# World XZ direction that maps to "down" on the local player's screen. The
# game camera looks straight down (rotation X = -90°) with an optional 180°
# Y flip when PlayerPrefs.attack_up + away team. The camera's basis Y, in that
# pose, points along world +Z (no flip) or -Z (flip); we want screen-DOWN
# which is the negation, projected to XZ. Falls back to +Z when there's no
# active camera (e.g. during early load).
func _hud_screen_down_xz() -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return Vector2(0.0, 1.0)
	var up_world: Vector3 = cam.global_transform.basis.y
	var down := Vector2(-up_world.x, -up_world.z)
	if down.length_squared() < 0.0001:
		return Vector2(0.0, 1.0)
	return down.normalized()

func _make_charge_ring_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _CHARGE_RING_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fill", 0.0)
	mat.set_shader_parameter("pulse", 0.0)
	mat.set_shader_parameter("lost_flash", 0.0)
	mat.set_shader_parameter("color_low", MenuStyle.CHARGE_LOW)
	mat.set_shader_parameter("color_high", MenuStyle.CHARGE_HIGH)
	mat.set_shader_parameter("color_full", MenuStyle.CHARGE_FULL)
	mat.set_shader_parameter("color_lost", MenuStyle.CHARGE_LOST)
	mat.set_shader_parameter("opacity", MenuStyle.HUD_OPACITY)
	return mat

# Slides the four fixed-length arms to visualise puck proximity.
# ratio = 1.0: puck at zone edge, arms at zone boundary.
# ratio = 0.0: puck at zone centre, arms slid inward pointing at centre.
func update_slapper_indicator_convergence(ratio: float) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	var inner_tip: float = lerpf(0.0, 1.0 - _SLAPPER_ARM_LENGTH, r)
	var arm_center: float = inner_tip + _SLAPPER_ARM_LENGTH * 0.5
	for i: int in _slapper_arm_nodes.size():
		_slapper_arm_nodes[i].position = _SLAPPER_ARM_DIRS[i] * arm_center

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
	# Camera-aware screen axes for the name + chevron. The game camera looks
	# straight down with an optional 180° Y flip (PlayerPrefs.attack_up); both
	# elements need to honor that flip so they always sit "below" the skater
	# in screen space. Falls back to +Z world-down if there's no active camera.
	var screen_down: Vector2 = _hud_screen_down_xz()
	# Position each character on an arc centered on the screen-down bisector,
	# then drop the chevron just past the last character on the same arc.
	# screen_down direction is treated as angle 0 of the local arc; characters
	# are placed at ±i * char_angle around it. atan2(screen_down.x, .y) gives
	# the world Y-rotation that maps "local +Z = screen-down" to world.
	var arc_base_angle: float = atan2(screen_down.x, screen_down.y)
	var char_angle_rad: float = deg_to_rad(_NAME_CHAR_ANGLE_DEG)
	var n: int = _name_char_labels.size()
	var rightmost_angle: float = arc_base_angle
	if n > 0:
		var center_offset: float = (n - 1) * 0.5
		for i: int in n:
			var theta: float = arc_base_angle + (float(i) - center_offset) * char_angle_rad
			var radial := Vector3(sin(theta), 0.0, cos(theta))
			# Build the character's basis so it lies flat on the ice (normal
			# up = +Y world) with its text "up" pointing radially outward
			# (away from the player center). This makes consecutive letters
			# tilt to follow the arc curve.
			# Basis columns: X = right, Y = up, Z = forward (camera-facing).
			# We want Z = +Y world (text reads from above), Y = radial, X = Y × Z.
			var label: Label3D = _name_char_labels[i]
			var pos := Vector3(
					global_position.x + radial.x * _NAME_ARC_RADIUS,
					0.05,
					global_position.z + radial.z * _NAME_ARC_RADIUS)
			var basis_y: Vector3 = radial            # text-up = radially outward
			var basis_z: Vector3 = Vector3.UP        # text-front = world up (faces camera)
			var basis_x: Vector3 = basis_y.cross(basis_z).normalized()
			label.global_transform = Transform3D(
					Basis(basis_x, basis_y, basis_z), pos)
			if i == n - 1:
				rightmost_angle = theta
	if _chevron_mesh != null:
		var was_visible: bool = _chevron_mesh.visible
		_chevron_mesh.visible = is_elevated and not is_ghost
		if _chevron_mesh.visible and not was_visible:
			print("[skater] chevron flipped visible — pos pending, mesh AABB=",
					_chevron_mesh.get_aabb(), " mat=", _chevron_mesh.material_override)
		if _chevron_mesh.visible:
			var chevron_angle: float = rightmost_angle + deg_to_rad(_NAME_CHEVRON_GAP_DEG)
			var dir := Vector3(sin(chevron_angle), 0.0, cos(chevron_angle))
			_chevron_mesh.global_position = Vector3(
					global_position.x + dir.x * _NAME_ARC_RADIUS,
					0.05,
					global_position.z + dir.z * _NAME_ARC_RADIUS)
			# Chevron's local +Z must align with screen-down so the legs open
			# downward and the tip reads "up" in screen space.
			_chevron_mesh.rotation = Vector3(0.0, arc_base_angle, 0.0)
	if _charge_ring_mesh != null and _charge_ring_mesh.visible:
		_charge_ring_mesh.global_position.y = 0.05
		var pulse_amount: float = 0.0
		if shot_charge >= 0.999:
			pulse_amount = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * _CHARGE_FULL_PULSE_HZ)
		_charge_ring_mat.set_shader_parameter("fill", clampf(shot_charge, 0.0, 1.0))
		_charge_ring_mat.set_shader_parameter("pulse", pulse_amount)
		var lost_t: float = 0.0
		if _charge_lost_flash_timer > 0.0:
			_charge_lost_flash_timer = maxf(_charge_lost_flash_timer - delta, 0.0)
			lost_t = _charge_lost_flash_timer / _CHARGE_LOST_FLASH_DURATION
		_charge_ring_mat.set_shader_parameter("lost_flash", lost_t)
		# Auto-hide once the lost flash has finished and there's nothing to show.
		if shot_charge <= 0.001 and lost_t <= 0.001 and not _charge_ring_visible:
			_charge_ring_mesh.visible = false
	if _slapper_indicator != null and _slapper_indicator.visible:
		_slapper_indicator.global_position.y = 0.05
	if _slapper_arrow_root != null and _slapper_arrow_root.visible:
		_slapper_arrow_root.global_position.y = 0.05

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

func _make_cuff_mesh(cross_size: float, height: float, color: Color, mesh_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = mesh_name
	var box := BoxMesh.new()
	box.size = Vector3(cross_size, cross_size, height)
	m.mesh = box
	m.material_override = _make_solid_mat(color)
	return m


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

func set_player_name(p_name: String) -> void:
	if _name_label_root == null:
		return
	if p_name == _name_text:
		return
	_name_text = p_name
	# Rebuild per-character labels. Cheap — names change only on spawn or
	# slot-swap, never per-tick.
	for old_label: Label3D in _name_char_labels:
		if is_instance_valid(old_label):
			_name_label_root.remove_child(old_label)
			old_label.queue_free()
	_name_char_labels.clear()
	for i: int in p_name.length():
		var label := Label3D.new()
		label.text = p_name.substr(i, 1)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		label.fixed_size = false
		label.font_size = 40
		label.outline_size = 0
		label.modulate = Color(MenuStyle.HUD_ICE.r, MenuStyle.HUD_ICE.g,
				MenuStyle.HUD_ICE.b, MenuStyle.HUD_OPACITY)
		label.pixel_size = 0.005
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label_root.add_child(label)
		_name_char_labels.append(label)

# Local-only: enable/disable the concentric charge ring under this skater.
# Driven by the controller; remote skaters never call this so the ring stays
# hidden. The actual fill level animates from `shot_charge` in _physics_process.
func set_charge_ring_visible(visible: bool) -> void:
	_charge_ring_visible = visible
	if _charge_ring_mesh != null:
		_charge_ring_mesh.visible = visible or _charge_lost_flash_timer > 0.0

# Local-only: trigger the red lost-charge flash on the charge ring. The ring
# stays visible for _CHARGE_LOST_FLASH_DURATION seconds, fades to red, then
# auto-hides via _physics_process.
func trigger_charge_lost_flash() -> void:
	_charge_lost_flash_timer = _CHARGE_LOST_FLASH_DURATION
	if _charge_ring_mesh != null:
		_charge_ring_mesh.visible = true

# Local-only: enable the slapshot direction arrow at the given zone offset.
# `offset_x` matches slapper_zone_offset_x (controller-side), already pre-signed.
# Arrow rotates each tick to face slapper_aim_dir.
func set_slapshot_arrow(active: bool, offset_x: float = 0.0, offset_z: float = 0.0) -> void:
	if _slapper_arrow_root == null:
		return
	if not active:
		_slapper_arrow_root.visible = false
		return
	var blade_side_sign: float = -1.0 if is_left_handed else 1.0
	_slapper_arrow_root.position = Vector3(blade_side_sign * offset_x, 0.05, offset_z)
	_slapper_arrow_root.visible = true

func update_slapshot_arrow_direction(world_dir: Vector3) -> void:
	if _slapper_arrow_root == null or not _slapper_arrow_root.visible:
		return
	if world_dir.length() < 0.001:
		return
	var local_dir: Vector3 = global_transform.basis.inverse() * world_dir
	local_dir.y = 0.0
	if local_dir.length() < 0.001:
		return
	# Arrow mesh is built pointing along +Z, so atan2 of (x, z) gives Y rotation.
	_slapper_arrow_root.rotation.y = atan2(local_dir.x, local_dir.z)

func set_slapper_indicator(active: bool, offset_x: float = 0.0, offset_z: float = 0.0, radius: float = 0.5) -> void:
	if not active:
		_slapper_indicator.visible = false
		return
	var blade_side_sign: float = -1.0 if is_left_handed else 1.0
	_slapper_indicator.position = Vector3(blade_side_sign * offset_x, 0.0, offset_z)
	_slapper_indicator.scale = Vector3(radius, 1.0, radius)
	_slapper_indicator.visible = true
	update_slapper_indicator_convergence(1.0)

# Kept as no-ops so the existing controller signature compiles. The reticle is
# now monochromatic ice blue — readiness/window timing read from blade pose,
# not from a color change. If we want timing feedback back, drive a uniform.
func set_slapper_indicator_ready(_is_ready: bool) -> void:
	pass

func update_slapper_indicator_window(_t: float) -> void:
	pass

func set_jersey_info(p_name: String, number: int, text_color: Color) -> void:
	for child: Node in upper_body.get_children():
		if child.name in ["JerseyBackMesh", "JerseyShoulderL", "JerseyShoulderR"]:
			upper_body.remove_child(child)
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
	# Free cuff meshes from a previous call before rebuilding stripes.
	if _top_cuff_mesh != null and is_instance_valid(_top_cuff_mesh):
		upper_body.remove_child(_top_cuff_mesh)
		_top_cuff_mesh.queue_free()
	_top_cuff_mesh = null
	if _bot_cuff_mesh != null and is_instance_valid(_bot_cuff_mesh):
		upper_body.remove_child(_bot_cuff_mesh)
		_bot_cuff_mesh.queue_free()
	_bot_cuff_mesh = null

	# Remove any previously generated stripe nodes.
	for node: Node in upper_body.get_children():
		if node.name.begins_with("Stripe_"):
			upper_body.remove_child(node)
			node.queue_free()
	for node: Node in lower_body.get_children():
		if node.name.begins_with("Stripe_"):
			lower_body.remove_child(node)
			node.queue_free()

	# Jersey hem band — bottom 0.08 m of the UpperBodyMesh
	# (BoxMesh 0.5×0.65×0.28, center (0,0.3,0) → bottom at y = -0.025).
	var hem_quads: Array = JerseyTextureGenerator.make_box_stripe_band(
			Vector3(0.0, 0.3, 0.0), Vector3(0.25, 0.325, 0.14),
			-0.025, 0.08, jersey_stripe_color, "Stripe_JerseyHem")
	for q: MeshInstance3D in hem_quads:
		upper_body.add_child(q)

	# Sleeve cuffs — solid box meshes as children of upper_body. Their
	# transforms are updated each frame in update_arm_mesh() /
	# update_bottom_arm_mesh() using the elbow→hand direction so they stay
	# perpendicular to the forearm bone regardless of arm pose.
	var cuff_size: float = arm_mesh_thickness + 0.02
	_top_cuff_mesh = _make_cuff_mesh(cuff_size, 0.06, jersey_stripe_color, "CuffTop")
	upper_body.add_child(_top_cuff_mesh)
	_bot_cuff_mesh = _make_cuff_mesh(cuff_size, 0.06, jersey_stripe_color, "CuffBot")
	upper_body.add_child(_bot_cuff_mesh)

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
	_update_cuff_transform(_top_cuff_mesh, elbow_w, hand_w)

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
	_update_cuff_transform(_bot_cuff_mesh, elbow_w, hand_w)

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

# Positions a cuff mesh at hand_w and orients it so its Z axis aligns with the
# forearm (elbow→hand), making the cuff disk perpendicular to the bone.
func _update_cuff_transform(mesh: MeshInstance3D, elbow_w: Vector3, hand_w: Vector3) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	mesh.position = upper_body.to_local(hand_w)
	var bone_dir: Vector3 = hand_w - elbow_w
	if bone_dir.length() > 0.0001:
		mesh.look_at(hand_w + bone_dir.normalized(), Vector3.UP)

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
			_sock_mesh, _skate_mesh, _top_cuff_mesh, _bot_cuff_mesh,
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
	for node: Node in upper_body.get_children():
		if node.name.begins_with("Stripe_"):
			node.visible = not ghost
	for node: Node in lower_body.get_children():
		if node.name.begins_with("Stripe_"):
			node.visible = not ghost
	# HUD-on-ice elements: hide during ghost so a "phantom" skater doesn't
	# carry rings, name, or charge UI. The chevron already gates on is_ghost
	# in _physics_process; the rest are explicitly toggled here.
	if _ring_mesh != null:
		_ring_mesh.visible = not ghost
	if _name_label_root != null:
		_name_label_root.visible = not ghost
	if _charge_ring_mesh != null and ghost:
		_charge_ring_mesh.visible = false
	if _slapper_indicator != null and ghost:
		_slapper_indicator.visible = false
	if _slapper_arrow_root != null and ghost:
		_slapper_arrow_root.visible = false

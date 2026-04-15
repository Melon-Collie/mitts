class_name GameCamera
extends Camera3D

# ── Target References ─────────────────────────────────────────────────────────
@export var skater: Skater
@export var puck: Puck
@export var attacking_goal: Node3D
@export var local_controller: LocalController

# ── Anchor Weights ────────────────────────────────────────────────────────────
@export var puck_weight: float = 1.0
@export var mouse_weight: float = 0.5
@export var goal_weight: float = 0.3

# ── Zoom Tuning ───────────────────────────────────────────────────────────────
@export var min_height: float = 12
@export var max_height: float = 40.0
@export var zoom_speed: float = 3.0
@export var zoom_padding: float = 2.0		# extra height added on top of what's needed to show puck

# ── Player Frame Margin ───────────────────────────────────────────────────────
@export var player_margin: float = 0.8

# ── Rink Bounds ───────────────────────────────────────────────────────────────
@export var rink_half_width: float = 13.0
@export var rink_half_length: float = 30.0

# ── Smoothing ─────────────────────────────────────────────────────────────────
@export var smooth_speed: float = 5.0

# ── Runtime ───────────────────────────────────────────────────────────────────
var _current_height: float = 15.0

func _ready() -> void:
	make_current()

func _physics_process(delta: float) -> void:
	if not skater:
		print("Game Camera: skater is null")
		return

	var player_pos: Vector3 = skater.global_position
	player_pos.y = 0.0

	# ── Step 1: Weighted Target Position ─────────────────────────────────────
	var total_weight: float = 1.0
	var weighted_pos: Vector3 = player_pos

	if puck:
		var puck_pos: Vector3 = puck.global_position
		puck_pos.y = 0.0
		weighted_pos += puck_pos * puck_weight
		total_weight += puck_weight

	var mouse_pos: Vector3 = local_controller.get_current_input().mouse_world_pos
	mouse_pos.y = 0.0
	weighted_pos += mouse_pos * mouse_weight
	total_weight += mouse_weight

	if attacking_goal:
		var goal_pos: Vector3 = attacking_goal.global_position
		goal_pos.y = 0.0
		weighted_pos += goal_pos * goal_weight
		total_weight += goal_weight

	var target_xz: Vector3 = weighted_pos / total_weight

	# ── Step 2: Player-First Clamp ────────────────────────────────────────────
	# Use current height to compute visible extents for clamping
	var fov_rad: float = deg_to_rad(fov)
	var aspect: float = get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	var tan_half_fov: float = tan(fov_rad / 2.0)
	var visible_half_x: float = tan_half_fov * aspect * _current_height
	var visible_half_z: float = tan_half_fov * _current_height

	var max_offset_x: float = visible_half_x * player_margin
	var max_offset_z: float = visible_half_z * player_margin

	target_xz.x = clampf(target_xz.x, player_pos.x - max_offset_x, player_pos.x + max_offset_x)
	target_xz.z = clampf(target_xz.z, player_pos.z - max_offset_z, player_pos.z + max_offset_z)

	# ── Step 3: Soft Rink Clamp ───────────────────────────────────────────────
	var safe_x: float = maxf(rink_half_width - visible_half_x, 0.0)
	var safe_z: float = maxf(rink_half_length - visible_half_z, 0.0)

	target_xz.x = clampf(target_xz.x, -safe_x, safe_x)
	target_xz.z = clampf(target_xz.z, -safe_z, safe_z)

	# ── Step 4: Zoom based on clamped position ────────────────────────────────
	# Now that we know where the camera will actually be, compute how high
	# it needs to be to show the puck from that position.
	var target_height: float = min_height

	if puck:
		var puck_pos: Vector3 = puck.global_position
		puck_pos.y = 0.0
		var puck_offset_x: float = abs(puck_pos.x - target_xz.x)
		var puck_offset_z: float = abs(puck_pos.z - target_xz.z)
		# Height needed to fit puck in frame on each axis
		var needed_x: float = puck_offset_x / (tan_half_fov * aspect)
		var needed_z: float = puck_offset_z / tan_half_fov
		target_height = clampf(maxf(needed_x, needed_z) + zoom_padding, min_height, max_height)

	_current_height = lerpf(_current_height, target_height, zoom_speed * delta)

	# ── Step 5: Smooth Movement ───────────────────────────────────────────────
	var target_pos: Vector3 = Vector3(target_xz.x, _current_height, target_xz.z)
	global_position = global_position.lerp(target_pos, smooth_speed * delta)

	# ── Orientation ───────────────────────────────────────────────────────────
	rotation_degrees = Vector3(-90.0, 0.0, 0.0)

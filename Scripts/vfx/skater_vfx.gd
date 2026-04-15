class_name SkaterVFX
extends Node3D

const SPRAY_THRESHOLD: float = 8.0    # m/s² velocity change to trigger spray
const MIN_SPRAY_SPEED: float = 1.5    # minimum speed at time of spray trigger
const TRAIL_MIN_SPEED: float = 0.5    # minimum speed for trail emission
const SPEED_LINE_MIN_SPEED: float = 5.5  # minimum speed for speed line effect
const TELEPORT_THRESHOLD: float = 1.0 # skip frame if skater moved this far (reconcile/faceoff guard)

# Spray particle tuning.
# SPRAY_UPWARD_TILT controls the blend between forward (along velocity) and straight up.
# 0.0 = purely horizontal, 1.0 = purely vertical. ~0.5 gives a 45° forward-and-up kick.
const SPRAY_UPWARD_TILT: float = 0.5
const SPRAY_SPREAD: float = 35.0  # degrees of cone spread around the computed direction

var _spray_emitters: Array[CPUParticles3D] = []
var _trail_emitters: Array[CPUParticles3D] = []
var _speed_lines: CPUParticles3D = null
var _body_check_burst: CPUParticles3D = null
var _charge_light: OmniLight3D = null
var _prev_vel: Vector3 = Vector3.ZERO
var _prev_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	for _side: float in [-1.0, 1.0]:
		var spray: CPUParticles3D = _make_spray_emitter()
		add_child(spray)
		_spray_emitters.append(spray)

		var trail: CPUParticles3D = _make_trail_emitter()
		trail.position = Vector3(_side * 0.15, 0.02, 0.0)
		add_child(trail)
		_trail_emitters.append(trail)

	_speed_lines = _make_speed_lines_emitter()
	_speed_lines.position = Vector3(0.0, 0.3, 0.0)
	add_child(_speed_lines)

	_body_check_burst = _make_body_check_emitter()
	add_child(_body_check_burst)

	_charge_light = OmniLight3D.new()
	_charge_light.omni_range = 3.0
	_charge_light.light_energy = 0.0
	_charge_light.light_color = Color(0.3, 0.6, 1.0)
	_charge_light.visible = false
	add_child(_charge_light)

	var skater: Skater = get_parent() as Skater
	if skater != null:
		skater.body_checked_player.connect(_on_body_check)

	_prev_pos = global_position

func _process(delta: float) -> void:
	var skater: Skater = get_parent() as Skater
	if skater == null:
		return

	var curr_pos: Vector3 = skater.global_position
	var curr_vel: Vector3 = skater.velocity

	# Reconcile / faceoff teleport guard: skip emission on large position jumps
	# so reconcile snaps don't trigger false spray bursts or stray trail marks.
	if (curr_pos - _prev_pos).length() > TELEPORT_THRESHOLD:
		_prev_vel = curr_vel
		_prev_pos = curr_pos
		_set_trail_emitting(false)
		_speed_lines.emitting = false
		_charge_light.visible = false
		return

	_prev_pos = curr_pos

	var flat_vel: Vector3 = Vector3(curr_vel.x, 0.0, curr_vel.z)
	var speed: float = flat_vel.length()
	var delta_vel: float = (curr_vel - _prev_vel).length() / delta if delta > 0.0 else 0.0
	_prev_vel = curr_vel

	# Suppress all VFX when ghosted (offsides / icing)
	if skater.is_ghost:
		_set_trail_emitting(false)
		_speed_lines.emitting = false
		_charge_light.visible = false
		return

	# Ice spray: burst on hard braking or sharp direction change.
	# Emitters are repositioned to behind the skater along their velocity,
	# so the spray appears where the skates are digging in.
	if delta_vel > SPRAY_THRESHOLD and speed > MIN_SPRAY_SPEED:
		_emit_spray(skater, flat_vel)

	# Skate trails: continuous faint marks on ice while moving
	_set_trail_emitting(speed > TRAIL_MIN_SPEED)

	# Speed lines: small streaks behind the skater at high speed.
	# direction is in local space — convert world-space backward vector via basis inverse
	# so particles go backward along velocity regardless of the skater's facing.
	if speed > SPEED_LINE_MIN_SPEED and flat_vel.length() > 0.1:
		_speed_lines.emitting = true
		_speed_lines.direction = skater.global_transform.basis.inverse() * (-flat_vel.normalized())
	else:
		_speed_lines.emitting = false

	# Shot charge glow: light at blade scales with charge (wrister sweep or slapper wind-up)
	if skater.shot_charge > 0.01:
		_charge_light.visible = true
		_charge_light.global_position = skater.get_blade_contact_global() + Vector3(0.0, 0.15, 0.0)
		_charge_light.light_energy = skater.shot_charge * 2.5
	else:
		_charge_light.visible = false

func _emit_spray(skater: Skater, flat_vel: Vector3) -> void:
	# Place each spray emitter in front of the skater (in the direction of travel)
	# where the skate blades are digging in and kicking up ice.
	# Direction kicks forward along velocity with an upward tilt, converted to
	# each emitter's local space (the emitter inherits the skater's Y rotation).
	var forward: Vector3 = flat_vel.normalized()
	var perp: Vector3 = flat_vel.cross(Vector3.UP).normalized()
	var world_dir: Vector3 = (forward + Vector3(0.0, SPRAY_UPWARD_TILT, 0.0)).normalized()
	var sides: Array[float] = [-1.0, 1.0]
	for i: int in _spray_emitters.size():
		_spray_emitters[i].global_position = (
			skater.global_position
			+ forward * 0.25
			+ perp * sides[i] * 0.15
			+ Vector3(0.0, 0.05, 0.0)
		)
		_spray_emitters[i].direction = _spray_emitters[i].global_transform.basis.inverse() * world_dir
		_spray_emitters[i].restart()

func _on_body_check(victim: Skater, _force: float, hit_dir: Vector3) -> void:
	# Burst at the victim's position, emitting outward along the hit direction.
	# direction must be in the emitter's local space — convert the world-space
	# hit vector using the emitter's inverse basis (inherited from the skater's facing).
	_body_check_burst.global_position = victim.global_position + Vector3(0.0, 0.5, 0.0)
	var flat_hit: Vector3 = Vector3(hit_dir.x, 0.0, hit_dir.z)
	var world_dir: Vector3 = (flat_hit + Vector3(0.0, 0.4, 0.0)).normalized()
	_body_check_burst.direction = _body_check_burst.global_transform.basis.inverse() * world_dir
	_body_check_burst.restart()

func _set_trail_emitting(active: bool) -> void:
	for emitter: CPUParticles3D in _trail_emitters:
		emitter.emitting = active

func _make_spray_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 10
	e.lifetime = 0.2
	e.one_shot = true
	e.explosiveness = 0.95
	e.randomness = 0.3
	e.local_coords = false
	e.direction = Vector3(0.0, 1.0, 0.0)  # overwritten per burst in _emit_spray
	e.spread = SPRAY_SPREAD
	e.initial_velocity_min = 3.0
	e.initial_velocity_max = 6.0
	e.gravity = Vector3(0.0, -30.0, 0.0)
	e.scale_amount_min = 0.03
	e.scale_amount_max = 0.06
	e.mesh = _make_sphere_mesh(Color(0.9, 0.95, 1.0, 0.85))
	return e

func _make_trail_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 5
	e.lifetime = 2.5
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.5
	e.local_coords = false
	e.direction = Vector3(0.0, 1.0, 0.0)
	e.spread = 180.0
	e.initial_velocity_min = 0.0
	e.initial_velocity_max = 0.05
	e.gravity = Vector3.ZERO
	e.scale_amount_min = 0.05
	e.scale_amount_max = 0.09
	e.mesh = _make_flat_mesh(Color(1.0, 1.0, 1.0, 0.3))
	return e

func _make_speed_lines_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 8
	e.lifetime = 0.12
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.3
	e.local_coords = false
	e.direction = Vector3(0.0, 0.0, 1.0)  # updated each frame to face backward along velocity
	e.spread = 10.0
	e.initial_velocity_min = 5.0
	e.initial_velocity_max = 8.0
	e.gravity = Vector3.ZERO
	e.scale_amount_min = 0.015
	e.scale_amount_max = 0.03
	e.mesh = _make_sphere_mesh(Color(0.85, 0.92, 1.0, 0.5))
	return e

func _make_body_check_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 20
	e.lifetime = 0.4
	e.one_shot = true
	e.explosiveness = 0.95
	e.randomness = 0.4
	e.local_coords = false
	e.direction = Vector3(0.0, 1.0, 0.0)  # overwritten per hit
	e.spread = 50.0
	e.initial_velocity_min = 3.0
	e.initial_velocity_max = 7.0
	e.gravity = Vector3(0.0, -12.0, 0.0)
	e.scale_amount_min = 0.04
	e.scale_amount_max = 0.08
	e.mesh = _make_sphere_mesh(Color(0.9, 0.95, 1.0, 0.9))
	return e

func _make_sphere_mesh(color: Color) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 4
	sphere.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	sphere.material = mat
	return sphere

func _make_flat_mesh(color: Color) -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.05, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	box.material = mat
	return box

class_name SkaterVFX
extends Node3D

const TRAIL_MIN_SPEED: float = 0.5    # minimum speed for trail emission
const SPEED_LINE_MIN_SPEED: float = 5.5  # minimum speed for speed line effect
const TELEPORT_THRESHOLD: float = 1.0 # skip frame if skater moved this far (reconcile/faceoff guard)

# Hockey stop VFX — two-layer effect (surface marks + airborne spray) per blade side.
const STOP_DECEL_THRESHOLD: float = 8.0  # m/s² velocity change to trigger
const STOP_MIN_SPEED: float = 2.5        # minimum speed at trigger time

# Blade trail — same zero-gap GPU approach as puck trail, one system per skate.
# Two dots per trail (left/right blade) pinned to ICE_Y so marks scrape the ice surface.
const BLADE_TRAIL_SPACING: float = 0.05   # meters between skate mark dots
const BLADE_TRAIL_LIFETIME: float = 1.5   # seconds each mark lingers
const BLADE_TRAIL_AMOUNT: int = 300       # max concurrent marks per blade
const BLADE_TRAIL_RADIUS: float = 0.025   # dot radius (smaller than puck's 0.055)
const BLADE_TRAIL_COLOR: Color = Color(0.95, 0.93, 0.88, 0.5)
const BLADE_X_OFFSET: float = 0.12       # left/right blade separation from center
const ICE_Y: float = 0.005              # world Y for trail dots (just above ice)

# Two GPU trail systems: index 0 = left blade, 1 = right blade
var _blade_trail_emitters: Array[GPUParticles3D] = []
var _blade_trail_particles: Array[GPUParticles3D] = []
var _stop_mark_emitters: Array[CPUParticles3D] = []   # surface scrape marks, one per side
var _stop_spray_emitters: Array[CPUParticles3D] = []  # airborne snow spray, one per side
var _speed_lines: CPUParticles3D = null
var _body_check_burst: CPUParticles3D = null
var _charge_light: OmniLight3D = null
var _prev_pos: Vector3 = Vector3.ZERO
var _prev_vel: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Build left/right blade trail systems (same zero-gap GPU approach as puck).
	# Sub-emitters are added before their parents so the NodePath can reference siblings.
	for i: int in 2:
		var side_x: float = [-BLADE_X_OFFSET, BLADE_X_OFFSET][i]
		var sub_name: String = "BladeTrailParticles%d" % i
		var sub: GPUParticles3D = _make_blade_trail_sub_emitter(sub_name)
		add_child(sub)
		_blade_trail_particles.append(sub)

		var emitter: GPUParticles3D = _make_blade_trail_emitter(i)
		emitter.position = Vector3(side_x, 0.0, 0.0)  # Y updated each frame to ICE_Y
		emitter.sub_emitter = NodePath("../%s" % sub_name)
		add_child(emitter)
		_blade_trail_emitters.append(emitter)

	for _i: int in 2:
		var marks: CPUParticles3D = _make_stop_marks_emitter()
		add_child(marks)
		_stop_mark_emitters.append(marks)

		var spray: CPUParticles3D = _make_stop_spray_emitter()
		add_child(spray)
		_stop_spray_emitters.append(spray)

	_speed_lines = _make_speed_lines_emitter()
	_speed_lines.position = Vector3(0.0, 0.3, 0.0)
	add_child(_speed_lines)

	_body_check_burst = _make_body_check_emitter()
	add_child(_body_check_burst)

	_charge_light = OmniLight3D.new()
	_charge_light.omni_range = 2.0
	_charge_light.light_energy = 0.0
	_charge_light.light_color = Color(0.95, 0.93, 0.88)
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
	# so reconcile snaps don't trigger false trail marks or stop bursts.
	if (curr_pos - _prev_pos).length() > TELEPORT_THRESHOLD:
		_prev_pos = curr_pos
		_prev_vel = curr_vel
		_set_blade_trails_emitting(false)
		_speed_lines.emitting = false
		_charge_light.visible = false
		return

	_prev_pos = curr_pos

	var flat_vel: Vector3 = Vector3(curr_vel.x, 0.0, curr_vel.z)
	var speed: float = flat_vel.length()
	var prev_speed: float = Vector3(_prev_vel.x, 0.0, _prev_vel.z).length()
	var decel: float = (prev_speed - speed) / delta if delta > 0.0 else 0.0
	_prev_vel = curr_vel

	# Suppress all VFX when ghosted (offsides / icing)
	if skater.is_ghost:
		_set_blade_trails_emitting(false)
		_speed_lines.emitting = false
		_charge_light.visible = false
		return

	# Pin blade trail emitters to ice level (skater origin is ~1m above ice).
	var ice_local_y: float = ICE_Y - curr_pos.y
	for i: int in _blade_trail_emitters.size():
		_blade_trail_emitters[i].position.y = ice_local_y

	# Skate trails: continuous marks on ice while moving
	_set_blade_trails_emitting(speed > TRAIL_MIN_SPEED)

	# Hockey stop: fire only when speed is dropping sharply (braking).
	if decel > STOP_DECEL_THRESHOLD and speed > STOP_MIN_SPEED:
		_emit_hockey_stop(skater, flat_vel)

	# Speed lines: small streaks behind the skater at high speed.
	# direction is in local space — convert world-space backward vector via basis inverse
	# so particles go backward along velocity regardless of the skater's facing.
	if speed > SPEED_LINE_MIN_SPEED and flat_vel.length() > 0.1:
		_speed_lines.emitting = true
		_speed_lines.direction = skater.global_transform.basis.inverse() * (-flat_vel.normalized())
	else:
		_speed_lines.emitting = false

	# Shot charge glow: cream → orange, matching the puck trail gradient.
	if skater.shot_charge > 0.01:
		var c: float = skater.shot_charge
		_charge_light.visible = true
		_charge_light.global_position = skater.get_blade_contact_global() + Vector3(0.0, 0.12, 0.0)
		_charge_light.light_color = Color(0.95, 0.93, 0.88).lerp(Color(1.0, 0.45, 0.05), c)
		_charge_light.light_energy = c * 1.5
		_charge_light.omni_range = lerpf(2.0, 3.5, c)
	else:
		_charge_light.visible = false
		_charge_light.omni_range = 2.0


func _on_body_check(victim: Skater, _force: float, hit_dir: Vector3) -> void:
	# Burst at the victim's position, emitting outward along the hit direction.
	# direction must be in the emitter's local space — convert the world-space
	# hit vector using the emitter's inverse basis (inherited from the skater's facing).
	_body_check_burst.global_position = victim.global_position + Vector3(0.0, 0.5, 0.0)
	var flat_hit: Vector3 = Vector3(hit_dir.x, 0.0, hit_dir.z)
	var world_dir: Vector3 = (flat_hit + Vector3(0.0, 0.4, 0.0)).normalized()
	_body_check_burst.direction = _body_check_burst.global_transform.basis.inverse() * world_dir
	_body_check_burst.restart()

func _set_blade_trails_emitting(active: bool) -> void:
	for emitter: GPUParticles3D in _blade_trail_emitters:
		emitter.emitting = active

func _make_blade_trail_emitter(index: int) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = "BladeTrailEmitter%d" % index
	e.amount = 1
	e.lifetime = 3600.0
	e.one_shot = false
	e.explosiveness = 0.0
	e.fixed_fps = 0
	e.local_coords = false
	e.emitting = false

	var shader := Shader.new()
	shader.code = """shader_type particles;

void start() {
	CUSTOM.xyz = EMISSION_TRANSFORM[3].xyz;
}

void process() {
	float spacing = %f;
	for (int i = 0; i < int(distance(EMISSION_TRANSFORM[3].xyz, CUSTOM.xyz) / spacing); i++) {
		CUSTOM.xyz += normalize(EMISSION_TRANSFORM[3].xyz - CUSTOM.xyz) * spacing;
		mat4 custom_transform = mat4(1.0);
		custom_transform[3].xyz = CUSTOM.xyz;
		emit_subparticle(custom_transform, vec3(0.0), vec4(0.0), vec4(0.0), FLAG_EMIT_POSITION);
	}
}
""" % BLADE_TRAIL_SPACING

	var mat := ShaderMaterial.new()
	mat.shader = shader
	e.process_material = mat
	return e

func _make_blade_trail_sub_emitter(sub_name: String) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = sub_name
	e.amount = BLADE_TRAIL_AMOUNT
	e.lifetime = BLADE_TRAIL_LIFETIME
	e.one_shot = false
	e.explosiveness = 0.0
	e.fixed_fps = 0
	e.local_coords = false
	e.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.ZERO
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	mat.color = BLADE_TRAIL_COLOR
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.5))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	e.process_material = mat

	var disk := CylinderMesh.new()
	disk.top_radius = BLADE_TRAIL_RADIUS
	disk.bottom_radius = BLADE_TRAIL_RADIUS
	disk.height = 0.003
	disk.radial_segments = 8
	disk.rings = 1
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.albedo_color = Color.WHITE
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disk.material = mesh_mat
	e.draw_pass_1 = disk
	return e

func _emit_hockey_stop(skater: Skater, flat_vel: Vector3) -> void:
	# Snow fans outward to both sides, perpendicular to travel direction.
	# Each side fires surface marks (linger on ice) + airborne spray (brief arc).
	var forward: Vector3 = flat_vel.normalized()
	var perp: Vector3 = flat_vel.cross(Vector3.UP).normalized()
	var sides: Array[float] = [-1.0, 1.0]
	for i: int in 2:
		var outward: Vector3 = perp * sides[i]
		var world_dir: Vector3 = (outward + forward * 0.2 + Vector3(0.0, 0.04, 0.0)).normalized()
		var world_pos: Vector3 = (
			skater.global_position
			+ forward * 0.4
			+ outward * 0.2
			+ Vector3(0.0, 0.01, 0.0)
		)
		var local_dir: Vector3 = _stop_mark_emitters[i].global_transform.basis.inverse() * world_dir
		_stop_mark_emitters[i].global_position = world_pos
		_stop_mark_emitters[i].direction = local_dir
		_stop_mark_emitters[i].restart()

		_stop_spray_emitters[i].global_position = world_pos
		_stop_spray_emitters[i].direction = local_dir
		_stop_spray_emitters[i].restart()

func _make_stop_marks_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 55
	e.lifetime = 1.5
	e.one_shot = true
	e.explosiveness = 0.9
	e.randomness = 0.3
	e.local_coords = false
	e.direction = Vector3(1.0, 0.0, 0.0)  # overwritten per burst
	e.spread = 65.0
	e.initial_velocity_min = 1.5
	e.initial_velocity_max = 5.0
	e.gravity = Vector3.ZERO
	e.scale_amount_min = 0.03
	e.scale_amount_max = 0.07
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.5
	disk.height = 0.05
	disk.radial_segments = 8
	disk.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.93, 0.88, 0.7)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disk.material = mat
	e.mesh = disk
	return e

func _make_stop_spray_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 35
	e.lifetime = 0.3
	e.one_shot = true
	e.explosiveness = 0.9
	e.randomness = 0.4
	e.local_coords = false
	e.direction = Vector3(1.0, 0.0, 0.0)  # overwritten per burst
	e.spread = 45.0
	e.initial_velocity_min = 6.0
	e.initial_velocity_max = 14.0
	e.gravity = Vector3(0.0, -18.0, 0.0)
	e.scale_amount_min = 0.02
	e.scale_amount_max = 0.04
	e.mesh = _make_sphere_mesh(Color(0.95, 0.93, 0.88, 0.85))
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


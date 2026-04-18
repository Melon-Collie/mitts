class_name SkaterVFX
extends Node3D

const TRAIL_MIN_SPEED: float = 0.5    # minimum speed for trail emission
const SPEED_LINE_MIN_SPEED: float = 5.5  # minimum speed for speed line effect
const TELEPORT_THRESHOLD: float = 1.0 # skip frame if skater moved this far (reconcile/faceoff guard)

# Hockey stop VFX — two-layer effect (surface marks + airborne spray) per blade side.
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
var _stop_spray_emitter: CPUParticles3D = null  # forward fan spray on brake
var _speed_lines: CPUParticles3D = null
var _body_check_burst: CPUParticles3D = null
var _dash_push_emitter: CPUParticles3D = null
var _charge_light: OmniLight3D = null
var _1t_ring: MeshInstance3D = null
var _1t_arrow: MeshInstance3D = null
var _1t_ring_radius: float = -1.0
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

	_stop_spray_emitter = _make_stop_spray_emitter()
	add_child(_stop_spray_emitter)

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

	_dash_push_emitter = _make_dash_push_emitter()
	add_child(_dash_push_emitter)

	_1t_ring = MeshInstance3D.new()
	_1t_ring.mesh = _make_ring_mesh(1.0, 0.03, Color(0.2, 0.6, 1.0, 0.6))
	_1t_ring.visible = false
	add_child(_1t_ring)

	_1t_arrow = MeshInstance3D.new()
	_1t_arrow.mesh = _make_arrow_mesh(1.2, 0.04, Color(0.2, 0.6, 1.0, 0.7))
	_1t_arrow.visible = false
	add_child(_1t_arrow)

	var skater: Skater = get_parent() as Skater
	if skater != null:
		skater.body_checked_player.connect(_on_body_check)
		skater.pulse_dashed.connect(_on_pulse_dashed)

	_prev_pos = global_position

func _process(_delta: float) -> void:
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

	# Hockey stop: emit continuously while pure braking, stop when not.
	if skater.is_braking and speed > STOP_MIN_SPEED:
		_emit_hockey_stop(skater, flat_vel)
	else:
		_stop_spray_emitter.emitting = false

	# Speed lines: small streaks behind the skater at high speed.
	# direction is in local space — convert world-space backward vector via basis inverse
	# so particles go backward along velocity regardless of the skater's facing.
	if speed > SPEED_LINE_MIN_SPEED and flat_vel.length() > 0.1:
		_speed_lines.emitting = true
		_speed_lines.direction = skater.global_transform.basis.inverse() * (-flat_vel.normalized())
	else:
		_speed_lines.emitting = false

	# Shot charge glow: cream → orange — wrister only, not slapper.
	if skater.shot_charge > 0.01 and skater.slapper_aim_dir == Vector3.ZERO:
		var c: float = skater.shot_charge
		_charge_light.visible = true
		_charge_light.global_position = skater.upper_body_to_global(skater.get_blade_position())
		_charge_light.light_color = Color(0.95, 0.93, 0.88).lerp(Color(1.0, 0.45, 0.05), c)
		_charge_light.light_energy = c * 1.5
		_charge_light.omni_range = lerpf(2.0, 3.5, c)
	else:
		_charge_light.visible = false
		_charge_light.omni_range = 2.0

	# One-timer zone ring + aim arrow — only when charging without puck.
	if skater.is_slapper_zone_active():
		var zone_pos: Vector3 = skater.get_slapper_zone_global_position()
		zone_pos.y = 0.01
		var r: float = skater.get_slapper_zone_radius()
		if not is_equal_approx(r, _1t_ring_radius):
			_1t_ring.mesh = _make_ring_mesh(r, 0.03, Color(0.2, 0.6, 1.0, 0.6))
			_1t_ring_radius = r
		_1t_ring.global_position = zone_pos
		_1t_ring.visible = true

		var aim: Vector3 = skater.slapper_aim_dir
		if aim.length() > 0.01:
			aim = aim.normalized()
			_1t_arrow.global_position = zone_pos + aim * (r + 0.6)
			_1t_arrow.global_rotation.y = atan2(aim.x, aim.z)
			_1t_arrow.visible = true
		else:
			_1t_arrow.visible = false
	else:
		_1t_ring.visible = false
		_1t_arrow.visible = false


func _on_pulse_dashed(dash_direction: Vector3) -> void:
	_emit_dash_push(dash_direction)

func _emit_dash_push(dash_direction: Vector3) -> void:
	# Spray fires OPPOSITE the dash — the pushing foot kicks ice backward.
	var anti_dir: Vector3 = -dash_direction
	anti_dir.y = 0.0
	if anti_dir.length() < 0.001:
		return
	anti_dir = anti_dir.normalized()

	var skater: Skater = get_parent() as Skater
	if skater == null:
		return

	var world_dir: Vector3 = (anti_dir + Vector3(0.0, 0.03, 0.0)).normalized()
	var local_dir: Vector3 = _dash_push_emitter.global_transform.basis.inverse() * world_dir
	_dash_push_emitter.global_position = skater.global_position + anti_dir * 0.2 + Vector3(0.0, 0.005, 0.0)
	_dash_push_emitter.direction = local_dir
	_dash_push_emitter.restart()

func _make_dash_push_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 25
	e.lifetime = 0.35
	e.one_shot = true
	e.explosiveness = 0.95
	e.randomness = 0.3
	e.local_coords = false
	e.direction = Vector3(1.0, 0.0, 0.0)  # overwritten at emit time
	e.spread = 25.0
	e.initial_velocity_min = 4.0
	e.initial_velocity_max = 10.0
	e.gravity = Vector3(0.0, -25.0, 0.0)
	e.scale_amount_min = 0.04
	e.scale_amount_max = 0.08
	e.mesh = _make_sphere_mesh(Color(0.95, 0.93, 0.88, 0.80))
	return e

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
	# Snow fans forward in the direction of travel — snowplow look.
	var forward: Vector3 = flat_vel.normalized()
	var world_dir: Vector3 = (forward + Vector3(0.0, 0.36, 0.0)).normalized()
	var local_dir: Vector3 = _stop_spray_emitter.global_transform.basis.inverse() * world_dir
	_stop_spray_emitter.global_position = skater.global_position + forward * 0.7 + Vector3(0.0, 0.005, 0.0)
	_stop_spray_emitter.direction = local_dir
	_stop_spray_emitter.emitting = true

func _make_stop_spray_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 150
	e.lifetime = 0.35
	e.one_shot = false
	e.explosiveness = 0.0
	e.randomness = 0.3
	e.local_coords = false
	e.direction = Vector3(1.0, 0.0, 0.0)  # overwritten per burst
	e.spread = 65.0                        # wide forward fan
	e.initial_velocity_min = 3.0
	e.initial_velocity_max = 9.0
	e.gravity = Vector3(0.0, -25.0, 0.0)
	e.scale_amount_min = 0.03
	e.scale_amount_max = 0.06
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
	e.gravity = Vector3(0.0, -25.0, 0.0)
	e.scale_amount_min = 0.04
	e.scale_amount_max = 0.08
	e.mesh = _make_sphere_mesh(Color(0.9, 0.95, 1.0, 0.9))
	return e

func _make_ring_mesh(radius: float, thickness: float, color: Color) -> ArrayMesh:
	var segments: int = 48
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var inner_r: float = radius - thickness
	var outer_r: float = radius + thickness
	for i: int in segments:
		var a: float = TAU * i / segments
		var c: float = cos(a)
		var s: float = sin(a)
		verts.append(Vector3(c * inner_r, 0.0, s * inner_r))
		verts.append(Vector3(c * outer_r, 0.0, s * outer_r))
		colors.append(color)
		colors.append(color)
	for i: int in segments:
		var i0: int = i * 2
		var i1: int = i * 2 + 1
		var i2: int = ((i + 1) % segments) * 2
		var i3: int = ((i + 1) % segments) * 2 + 1
		indices.append_array([i0, i1, i2, i1, i3, i2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh

func _make_arrow_mesh(length: float, width: float, color: Color) -> Mesh:
	# Thin flat box pointing along +Z, pivoted at center so offset by length/2 positions tip.
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.003, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	return box

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

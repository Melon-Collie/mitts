class_name PuckVFX
extends Node3D

const MIN_SPEED: float = 1.5
const IMPACT_SPEED_MIN: float = 3.0       # m/s flat speed before impact to trigger burst
const IMPACT_DOT_THRESHOLD: float = -0.25 # normalized velocity dot to detect direction reversal

var _particles: GPUParticles3D = null
var _impact_particles: CPUParticles3D = null
var _prev_pos: Vector3 = Vector3.ZERO
var _prev_vel: Vector3 = Vector3.ZERO

func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "Trail"
	# amount must cover the full trail at continuous emission rate:
	# rate = amount / lifetime, trail fills in trail_lifetime seconds → amount ≥ rate * trail_lifetime.
	# At amount=32 and lifetime=0.5: rate≈64/s, trail fills in 0.5s → 32 particles visible. ✓
	_particles.amount = 32
	_particles.lifetime = 0.5
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.fixed_fps = 60
	_particles.trail_enabled = true
	_particles.trail_lifetime = 0.5
	_particles.local_coords = false  # trail sections stay in world space as puck moves
	_particles.emitting = false

	# Particles don't move — the emitter moves with the puck.
	# The trail system records emitter world positions to build the ribbon.
	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 0.0, 1.0)
	process_mat.spread = 0.0
	process_mat.initial_velocity_min = 0.0
	process_mat.initial_velocity_max = 0.0
	process_mat.gravity = Vector3.ZERO
	# Fade from opaque at birth (front of trail, near puck) to transparent at death (tail end).
	var grad := Gradient.new()
	grad.set_color(0, Color(0.82, 0.93, 1.0, 0.75))
	grad.set_color(1, Color(0.82, 0.93, 1.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	process_mat.color_ramp = grad_tex
	_particles.process_material = process_mat

	# RibbonTrailMesh: the particle system animates its skeleton to follow the
	# emitter path, producing a ribbon. SHAPE_CROSS (two perpendicular quads)
	# keeps the trail visible from any camera angle.
	var ribbon := RibbonTrailMesh.new()
	ribbon.sections = 8
	ribbon.section_length = 0.05
	ribbon.section_segments = 3
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = 0.18  # slightly narrower than puck diameter for a sleek blur look
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true  # receives the color_ramp fade from the process material
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides of the ribbon quads
	ribbon.material = mat
	_particles.draw_pass_1 = ribbon

	add_child(_particles)

	_impact_particles = _make_impact_emitter()
	add_child(_impact_particles)

	_prev_pos = global_position

func _process(delta: float) -> void:
	var curr_pos: Vector3 = global_position
	var vel: Vector3 = (curr_pos - _prev_pos) / delta if delta > 0.0 else Vector3.ZERO
	_prev_pos = curr_pos
	var speed: float = Vector3(vel.x, 0.0, vel.z).length()
	_particles.emitting = speed >= MIN_SPEED
	_detect_impact(vel)

func _detect_impact(curr_vel: Vector3) -> void:
	var prev_flat_speed: float = Vector3(_prev_vel.x, 0.0, _prev_vel.z).length()
	if prev_flat_speed >= IMPACT_SPEED_MIN and curr_vel.length() > 0.5:
		var prev_dir: Vector3 = _prev_vel.normalized()
		var curr_dir: Vector3 = curr_vel.normalized()
		if prev_dir.dot(curr_dir) < IMPACT_DOT_THRESHOLD:
			_impact_particles.restart()
	_prev_vel = curr_vel

func _make_impact_emitter() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.amount = 12
	e.lifetime = 0.3
	e.one_shot = true
	e.explosiveness = 0.95
	e.randomness = 0.4
	e.local_coords = false
	e.direction = Vector3(0.0, 1.0, 0.0)
	e.spread = 60.0
	e.initial_velocity_min = 1.5
	e.initial_velocity_max = 4.0
	e.gravity = Vector3(0.0, -15.0, 0.0)
	e.scale_amount_min = 0.02
	e.scale_amount_max = 0.05
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

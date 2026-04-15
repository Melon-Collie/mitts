class_name GoalVFX
extends Node3D

var _particles: GPUParticles3D = null
var _light: OmniLight3D = null

func _ready() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = 60
	_particles.lifetime = 1.5
	_particles.one_shot = true
	_particles.explosiveness = 0.9
	_particles.fixed_fps = 60
	_particles.local_coords = false
	_particles.emitting = false

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 70.0
	process_mat.initial_velocity_min = 3.0
	process_mat.initial_velocity_max = 9.0
	process_mat.gravity = Vector3(0.0, -5.0, 0.0)
	process_mat.scale_min = 0.06
	process_mat.scale_max = 0.14
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	grad.set_color(1, Color(1.0, 0.9, 0.3, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	process_mat.color_ramp = grad_tex
	_particles.process_material = process_mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 4
	sphere.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	sphere.material = mat
	_particles.draw_pass_1 = sphere
	add_child(_particles)

	_light = OmniLight3D.new()
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	_light.light_color = Color(1.0, 0.85, 0.3)
	add_child(_light)

func celebrate() -> void:
	_particles.restart()
	_light.light_energy = 4.0
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 0.0, 1.8)

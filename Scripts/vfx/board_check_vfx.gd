class_name BoardCheckVFX
extends Node3D

# What the boards do when a body is driven into them (GameManager.boards_checked):
# the glass rattles where he hit it (rink_glass.gdshader's rattle), and snow
# kicks up off the foot of the boards below. One emitter and one rattle at a
# time: a second check restarts both where it landed.

# How long the glass rattles, at full and at the softest heard check.
const RATTLE_TIME_HARD: float = 0.9
const RATTLE_TIME_SOFT: float = 0.5
const RATTLE_STRENGTH_SOFT: float = 0.35

const PUFF_AMOUNT_SOFT: int = 28
const PUFF_AMOUNT_HARD: int = 70
const PUFF_SPEED_SOFT: float = 2.0
const PUFF_SPEED_HARD: float = 5.5
# Snow is thrown off the kickplate, into the rink and up.
const PUFF_LIFT: float = 0.7

var _glass: ShaderMaterial = null
var _puff: CPUParticles3D = null
var _rattle_tween: Tween = null


func setup(glass: ShaderMaterial) -> void:
	_glass = glass
	_puff = _make_puff()
	add_child(_puff)


# `contact` is where he met the glass, in this node's frame (the rink's), and
# `t` how hard, 0..1 (SkaterVFX.check_intensity).
func fire(contact: Vector3, t: float) -> void:
	_rattle(contact, t)
	var out_xz: Vector2 = BoardCheckRules.outward_at(Vector2(contact.x, contact.z))
	var inward := Vector3(-out_xz.x, 0.0, -out_xz.y)
	_puff.position = Vector3(contact.x, IceVFX.ICE_Y + 0.15, contact.z) + inward * 0.25
	_puff.direction = (inward + Vector3.UP * PUFF_LIFT).normalized()
	_puff.amount = int(lerpf(PUFF_AMOUNT_SOFT, PUFF_AMOUNT_HARD, t))
	_puff.initial_velocity_min = lerpf(PUFF_SPEED_SOFT, PUFF_SPEED_HARD, t) * 0.4
	_puff.initial_velocity_max = lerpf(PUFF_SPEED_SOFT, PUFF_SPEED_HARD, t)
	_puff.restart()


func _rattle(contact: Vector3, t: float) -> void:
	if _glass == null:
		return
	if _rattle_tween != null and _rattle_tween.is_running():
		_rattle_tween.kill()
	_glass.set_shader_parameter(&"rattle_pos", contact)
	_glass.set_shader_parameter(&"rattle_strength", lerpf(RATTLE_STRENGTH_SOFT, 1.0, t))
	_rattle_tween = create_tween()
	_rattle_tween.tween_method(func(v: float) -> void:
			_glass.set_shader_parameter(&"rattle_t", v),
			0.0, 1.0, lerpf(RATTLE_TIME_SOFT, RATTLE_TIME_HARD, t))


func _make_puff() -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.name = "BoardCheckPuff"
	e.emitting = false
	e.one_shot = true
	e.lifetime = 0.55
	e.explosiveness = 0.9
	e.randomness = 0.5
	e.local_coords = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(0.5, 0.15, 0.5)
	e.spread = 50.0
	e.gravity = Vector3(0.0, -12.0, 0.0)
	e.damping_min = 1.0
	e.damping_max = 3.0
	e.scale_amount_min = 0.06
	e.scale_amount_max = 0.14
	e.mesh = IceVFX.blob(IceVFX.snow(0.85))
	return e

class_name BladeSprayVFX
extends Node3D

# Snow off a carrier's blade: a puff where it lands on the puck (the catch), a
# flick off it as it lets the puck go (the release), and a scrape from the toe
# through a toe drag. Thrown along the way the hands move the puck, harder the
# harder the stroke. Cosmetic, per machine, off the carry events every peer
# raises for every carrier.

# A catch or release at this stroke speed (m/s) throws its full burst.
const FULL_STROKE_M_S: float = 4.0
# Bursts can overlap a hard dangle's strokes, so they round-robin a few
# one-shot emitters rather than restarting one mid-burst.
const BURST_POOL: int = 3
# A toe drag scrapes once it is this far in (Skater.get_toe_drag_factor) and the
# puck moves at least this fast off the body (m/s).
const SCRAPE_MIN_DRAG: float = 0.5
const SCRAPE_MIN_SPEED: float = 0.8
# Where along the blade the toe scrapes, heel 0 to toe 1.
const TOE_U: float = 0.9

var _skater: Skater = null
var _bursts: Array[CPUParticles3D] = []
var _next_burst: int = 0
var _scrape: CPUParticles3D = null


func watch(skater: Skater) -> void:
	_skater = skater
	for _i: int in BURST_POOL:
		var b: CPUParticles3D = _make_emitter(true)
		add_child(b)
		_bursts.append(b)
	_scrape = _make_emitter(false)
	add_child(_scrape)
	skater.carry_caught.connect(_on_caught)
	skater.carry_face_changed.connect(_on_face_changed)


func _on_caught(stroke_speed: float) -> void:
	_burst(0.5, stroke_speed, 1.0)


func _on_face_changed(cause: int, speed: float, _travel_m: float) -> void:
	if cause == CarryStrokeState.Cause.RELEASE:
		_burst(TOE_U, speed, 0.6)


func _burst(u: float, stroke_speed: float, share: float) -> void:
	if CosmeticFreeze.vfx or _skater == null:
		return
	var strength: float = clampf(stroke_speed / FULL_STROKE_M_S, 0.0, 1.0) * share
	if strength < 0.15:
		return
	var e: CPUParticles3D = _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % BURST_POOL
	_aim(e, u)
	e.initial_velocity_min = 0.6 * strength
	e.initial_velocity_max = 2.4 * strength
	e.restart()


func _process(_delta: float) -> void:
	if _skater == null:
		return
	var scraping: bool = not CosmeticFreeze.vfx \
			and _skater.current_shot_state == SkaterStateMachine.State.SKATING_WITH_PUCK \
			and _skater.get_toe_drag_factor() >= SCRAPE_MIN_DRAG \
			and _skater.carry_hands_velocity.length() >= SCRAPE_MIN_SPEED
	if scraping:
		_aim(_scrape, TOE_U)
	_scrape.emitting = scraping


# At the drawn blade's sole, thrown up and along the puck's motion off the body.
func _aim(e: CPUParticles3D, u: float) -> void:
	var at: Vector3 = _skater.drawn_blade_point(u)
	e.global_position = Vector3(at.x, IceVFX.ICE_Y, at.z)
	var along: Vector3 = _skater.carry_hands_velocity
	var world_dir: Vector3 = Vector3.UP
	if along.length_squared() > 0.0001:
		world_dir = (along.normalized() + Vector3(0.0, 0.8, 0.0)).normalized()
	e.direction = e.global_transform.basis.inverse() * world_dir


func _make_emitter(one_shot: bool) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.one_shot = one_shot
	e.amount = 14 if one_shot else 10
	e.lifetime = 0.3
	e.explosiveness = 0.9 if one_shot else 0.0
	e.randomness = 0.4
	e.local_coords = false
	e.spread = 40.0
	e.initial_velocity_min = 0.4
	e.initial_velocity_max = 1.2
	e.gravity = Vector3(0.0, -20.0, 0.0)
	e.scale_amount_min = 0.012
	e.scale_amount_max = 0.03
	e.mesh = IceVFX.blob(IceVFX.snow(0.8))
	return e

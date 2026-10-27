class_name PuckSpinRig
extends RefCounted

# The puck's attitude on screen: spin about its axis, the wobble after a hit,
# the tumble of a lofted puck that left without spin. Cosmetic only — the
# analytic puck is a flat disc and nothing in gameplay reads this. It writes
# the mesh's local transform and nothing else.
#
# It works from the puck's rendered position alone, so every peer derives the
# same look from what it already draws: the host from its drive, a client from
# its prediction or interpolation. Contacts are host-side events a client never
# sees, so a contact is read off the motion instead — a velocity change no
# friction or gravity could make in one tick.
#
# Runs on the physics tick and writes the mesh there, so the engine's physics
# interpolation carries the attitude between ticks with the puck it sits on.

# Disc: regulation 3 × 1 in, the same extents the analytic puck collides with.
const RADIUS: float = GameRules.PUCK_COLLISION_RADIUS
const HALF_HEIGHT: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
# Rim contact against boards, posts, blades and pads — the boards' own Coulomb
# coefficient, the one the analytic carom bleeds tangential speed with.
const RIM_FRICTION: float = GameRules.PUCK_BOARD_FRICTION
# Ice friction torque on a disc spinning in place, over its inertia: the
# contact patch is the whole face, (2/3)·μ·m·g·R against ½·m·R².
const SPIN_DECEL_AT_REST: float = (4.0 / 3.0) * GameRules.ICE_FRICTION * GameRules.GRAVITY_M_S2 / RADIUS

# Velocity change in one tick that only a contact makes (m/s). Gravity is
# 0.11 a tick at 90 Hz and ice friction a twentieth of that.
var impact_min_dv: float = 1.0
# Share of the gap between the observed velocity and the impact reference
# closed each tick, so a contact smoothed across a few ticks (a client
# correction) still reads as one change rather than several small ones.
var impact_ref_follow: float = 0.5
# Further than this in one tick (m) is a restage, not motion: 67 m/s at 90 Hz.
var teleport_dist: float = 0.75
# Loose ticks after a release before its velocity is trusted — the first
# ticks carry the jump from the blade pin to the release point.
var release_settle_ticks: int = 2
# Share of the release speed the puck rolls off the blade with, heel to toe:
# ω = share · v / R. 0.1 puts a 12 m/s pass at ~5 rev/s and a 30 m/s shot at
# ~12.
var release_roll_share: float = 0.1
# Visible spin cap (rad/s): above ~π a tick the interpolated rotation would
# run backward.
var max_spin: float = 120.0
# Tilt a lateral hit gives the disc per m/s of velocity change (rad) — the
# contact sits below the centre (a blade, the kickplate's curve), so the hit
# rocks the disc as well as turning it.
var impact_tilt_per_dv: float = 0.03
# Tilt a landing gives per m/s of fall speed stopped (rad): the leading edge
# catches.
var landing_tilt_per_dv: float = 0.06
var max_tilt_on_ice: float = 0.5
# Below this the disc lies flat (rad).
var rest_tilt: float = 0.01
# Wobble settle rate on the ice (1/s), for a disc not spinning.
var tilt_settle_rate: float = 7.0
# Spin at which gyroscopic stiffness has halved both the settle rate and the
# tilt or tumble a hit can start (rad/s).
var gyro_ref_spin: float = 40.0
# The Euler's-disk precession speeds up without bound as the tilt goes to
# zero; past this (rad/s) it would alias on screen.
var max_precession: float = TAU * 12.0
# Tumble a hit gives an airborne puck per m/s of velocity change (rad/s).
var tumble_per_dv: float = 4.0
# Spin and tilt bleed off this fast while a blade carries the puck (1/s).
var carry_settle_rate: float = 20.0

# Spin about the disc's own axis, rad/s, positive counter-clockwise from above.
var spin: float = 0.0
# Wobble tilt from flat (rad) and the azimuth the disc's axis leans toward.
var tilt: float = 0.0
var tilt_azimuth: float = 0.0
# End-over-end rotation of an airborne puck, about a horizontal axis fixed at
# the hit that started it.
var tumble_rate: float = 0.0
var _tumble_angle: float = 0.0
var _tumble_axis: Vector3 = Vector3.RIGHT
var _spin_angle: float = 0.0
var _precession_dir: float = 1.0

var _mesh: Node3D = null
var _prev_pos: Vector3 = Vector3.INF
var _vel: Vector3 = Vector3.ZERO
var _vel_ref: Vector3 = Vector3.ZERO
var _vel_valid: bool = false
var _was_carried: bool = false
var _carrier_pos: Vector3 = Vector3.ZERO
var _release_ticks: int = -1
var _mesh_flat: bool = true


func _init(mesh: Node3D) -> void:
	_mesh = mesh


# `carrier_pos` is the carrying skater's position, or INF when the puck is
# loose; `clearance` is the disc's bottom height above the ice.
func step(dt: float, pos: Vector3, airborne: bool, clearance: float,
		carrier_pos: Vector3) -> void:
	if dt <= 0.0:
		return
	var carried: bool = carrier_pos.is_finite()
	_track_velocity(dt, pos)
	if carried:
		_carrier_pos = carrier_pos
		_step_carried(dt)
	else:
		if _was_carried:
			_release_ticks = 0
		_step_loose(dt, airborne)
	_was_carried = carried
	_spin_angle = fposmod(_spin_angle + spin * dt, TAU)
	if airborne:
		_tumble_angle = fposmod(_tumble_angle + tumble_rate * dt, TAU)
	_write_mesh(clearance)


func is_flat() -> bool:
	return tilt == 0.0 and _tumble_angle == 0.0 and tumble_rate == 0.0


# The disc's axis in the world.
func axis() -> Vector3:
	return _attitude() * Vector3.UP


func _track_velocity(dt: float, pos: Vector3) -> void:
	if not _prev_pos.is_finite() or pos.distance_to(_prev_pos) > teleport_dist:
		_restage()
	elif not _vel_valid:
		_vel = (pos - _prev_pos) / dt
		_vel_ref = _vel
		_vel_valid = true
	else:
		_vel = (pos - _prev_pos) / dt
	_prev_pos = pos


func _restage() -> void:
	spin = 0.0
	tilt = 0.0
	tumble_rate = 0.0
	_tumble_angle = 0.0
	_vel = Vector3.ZERO
	_vel_ref = Vector3.ZERO
	_vel_valid = false
	_release_ticks = -1


func _step_carried(dt: float) -> void:
	var k: float = exp(-carry_settle_rate * dt)
	spin *= k
	tilt *= k
	if tilt < rest_tilt:
		tilt = 0.0
	tumble_rate = 0.0
	_tumble_angle = 0.0
	_vel_ref = _vel
	_release_ticks = -1


func _step_loose(dt: float, airborne: bool) -> void:
	if _release_ticks >= 0:
		_release_ticks += 1
		_vel_ref = _vel
		if _release_ticks > release_settle_ticks:
			_release_ticks = -1
			_roll_off_blade()
	elif _vel_valid:
		var dv: Vector3 = _vel - _vel_ref
		if dv.length() > impact_min_dv:
			_impact(_vel_ref, _vel, airborne)
			_vel_ref = _vel
		else:
			_vel_ref = _vel_ref.lerp(_vel, impact_ref_follow)
	if airborne:
		return
	if _tumble_angle != 0.0 or tumble_rate != 0.0:
		_land_tumble()
	_settle_on_ice(dt)


# A shot or pass rolls off the blade heel to toe, and leaves flat. The roll's
# sense is the blade's sweep about the carrier.
func _roll_off_blade() -> void:
	var lever: Vector3 = _prev_pos - _carrier_pos
	var sweep: float = lever.cross(_vel).y
	var sense: float = 1.0 if sweep >= 0.0 else -1.0
	spin = clampf(sense * release_roll_share * _vel.length() / RADIUS, -max_spin, max_spin)
	tilt = 0.0
	tumble_rate = 0.0
	_tumble_angle = 0.0


func _impact(v0: Vector3, v1: Vector3, airborne: bool) -> void:
	var dv: Vector3 = v1 - v0
	var dv_h := Vector3(dv.x, 0.0, dv.z)
	var gyro: float = _gyro_damping()
	if v0.y < 0.0 and dv.y > dv_h.length():
		_land(minf(dv.y, -v0.y), v1, gyro)
		return
	var dv_h_len: float = dv_h.length()
	if dv_h_len > 1e-4:
		_rim_friction(v0, dv_h / dv_h_len, dv_h_len)
	if airborne or v1.y > 0.0:
		_kick_tumble(v1, dv.length() * tumble_per_dv * gyro)
	elif dv_h_len > 1e-4:
		_kick_tilt(-dv_h / dv_h_len, dv_h_len * impact_tilt_per_dv * gyro)


# Coulomb friction where the rim meets what hit it: the contact point's slip
# along the contact face, opposed by μ times the normal impulse, at most the
# impulse that stops the slip (a third of it for a disc struck on its rim —
# the same ceiling the analytic carom takes along-board speed with). Its
# torque about the axis spins the disc. `n` is the impulse direction on the
# puck, which a contact's change of velocity points along.
func _rim_friction(v0: Vector3, n: Vector3, normal_dv: float) -> void:
	var v0_h := Vector3(v0.x, 0.0, v0.z)
	var contact_r: Vector3 = -n * RADIUS
	var slip: Vector3 = v0_h - n * v0_h.dot(n) + (Vector3.UP * spin).cross(contact_r)
	var slip_speed: float = slip.length()
	if slip_speed < 1e-4:
		return
	var jt: float = minf(RIM_FRICTION * normal_dv, slip_speed / 3.0)
	var dw: Vector3 = n.cross(slip / slip_speed) * (2.0 * jt / RADIUS)
	spin = clampf(spin + dw.y, -max_spin, max_spin)


func _land(fall_speed: float, v1: Vector3, gyro: float) -> void:
	_land_tumble()
	var lean := Vector3(v1.x, 0.0, v1.z)
	if lean.length_squared() < 1e-6:
		lean = Vector3(cos(tilt_azimuth), 0.0, sin(tilt_azimuth))
	_kick_tilt(lean.normalized(), fall_speed * landing_tilt_per_dv * gyro)


# Folds an airborne tumble into the wobble it lands with. The disc is the same
# upside down, so an axis pointing below the horizon is taken as its opposite.
func _land_tumble() -> void:
	var n: Vector3 = axis()
	if n.y < 0.0:
		n = -n
	tumble_rate = 0.0
	_tumble_angle = 0.0
	_set_tilt_vector(Vector2(n.x, n.z).normalized() * acos(clampf(n.y, -1.0, 1.0)))


func _kick_tilt(lean_dir: Vector3, amount: float) -> void:
	var t := Vector2(cos(tilt_azimuth), sin(tilt_azimuth)) * tilt
	_set_tilt_vector(t + Vector2(lean_dir.x, lean_dir.z) * amount)


func _set_tilt_vector(t: Vector2) -> void:
	tilt = minf(t.length(), max_tilt_on_ice)
	if tilt > 0.0:
		tilt_azimuth = atan2(t.y, t.x)


func _kick_tumble(v1: Vector3, rate: float) -> void:
	if rate <= 0.0:
		return
	var travel := Vector3(v1.x, 0.0, v1.z)
	if travel.length_squared() < 1e-6:
		travel = Vector3.FORWARD
	if _tumble_angle != 0.0:
		_land_tumble()
	_tumble_axis = Vector3.UP.cross(travel).normalized()
	tumble_rate += rate


# A tilted disc on the ice rolls round its rim like Euler's disk, the lean
# circling faster as it flattens; spin both slows the settling and sets which
# way it circles.
func _settle_on_ice(dt: float) -> void:
	if spin != 0.0:
		spin = move_toward(spin, 0.0, _spin_decel() * dt)
		_precession_dir = signf(spin) if spin != 0.0 else _precession_dir
	if tilt == 0.0:
		return
	tilt *= exp(-tilt_settle_rate * _gyro_damping() * dt)
	if tilt < rest_tilt:
		tilt = 0.0
		return
	var precession: float = minf(sqrt(4.0 * GameRules.GRAVITY_M_S2 / (RADIUS * sin(tilt))), max_precession)
	tilt_azimuth = fposmod(tilt_azimuth + _precession_dir * precession * dt, TAU)


# Ice friction against the spin of a sliding disc. At rest it is the whole
# face's torque; sliding, the friction lines up against the slide and its
# torque falls as ω·R/v — which is why a puck's spin and slide die together.
func _spin_decel() -> float:
	var w: float = absf(spin)
	var v_h: float = Vector2(_vel.x, _vel.z).length()
	return SPIN_DECEL_AT_REST * 0.75 * w * RADIUS / (v_h + 0.75 * w * RADIUS)


func _gyro_damping() -> float:
	return 1.0 / (1.0 + absf(spin) / gyro_ref_spin)


func _attitude() -> Basis:
	var b := Basis.IDENTITY
	if _tumble_angle != 0.0:
		b = Basis(_tumble_axis, _tumble_angle)
	if tilt > 0.0:
		b = b * Basis(Vector3(sin(tilt_azimuth), 0.0, -cos(tilt_azimuth)), tilt)
	return b


# A tilted disc dips its low rim and lifts its low face; it rises until the
# lowest point of the drawn profile, chamfer included, sits on the ice.
func _write_mesh(clearance: float) -> void:
	if _mesh == null:
		return
	if is_flat() and spin == 0.0:
		if not _mesh_flat:
			_mesh.transform = Transform3D.IDENTITY
			_mesh_flat = true
		return
	var att: Basis = _attitude()
	var n: Vector3 = att * Vector3.UP
	var s: float = sqrt(maxf(0.0, 1.0 - n.y * n.y))
	var c: float = absf(n.y)
	var reach_down: float = 0.0
	for p: Vector2 in PuckMeshBuilder.PROFILE:
		reach_down = maxf(reach_down, p.y * s + absf(p.x) * c)
	var lift: float = maxf(0.0, reach_down - HALF_HEIGHT - clearance)
	_mesh.transform = Transform3D(att * Basis(Vector3.UP, _spin_angle), Vector3(0.0, lift, 0.0))
	_mesh_flat = false

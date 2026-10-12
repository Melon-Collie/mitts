class_name BoardPinRules
extends RefCounted

# The boards as a party to body contact: a check that drives a skater into the
# wall lands harder (the wall takes the recoil his skates would have), and a
# committed checker who keeps driving him into it pins him there.
#
# The pin is a short grip refreshed on the host every tick the checker is still
# driving, decaying deterministically everywhere else — the stagger_timer rail —
# so the victim's own client reconciles it like stagger. Its 2 s cap and the
# victim's escape drain sit on a host-only budget (SkaterBoardPin).

# A victim this close to the boards (body edge to board) has nowhere to recoil.
const BACKSTOP_MARGIN_M: float = 0.15
# The hit has to be driving into the wall, not along it: within 45° of square.
const BACKSTOP_MIN_INTO_WALL: float = 0.7071

# The pin needs the victim's edge within this of the boards.
const PIN_WALL_MARGIN_M: float = 0.25
# A checker is driving the victim in when pushing into the wall at walking pace,
# or holding the stick at least half into it (pressed flat against a body his
# velocity reads ~0 — the intent is what is still pushing).
const PIN_DRIVE_MIN_M_S: float = 1.0
const PIN_DRIVE_MIN_INTENT: float = 0.5
# How long a pin outlasts the last tick the checker drove: the weight still
# leaning in. Short, so letting go of Ctrl or the stick ends it at once.
const PIN_GRIP_S: float = 0.15
const PIN_MAX_S: float = 2.0
const PIN_IMMUNITY_S: float = 1.0
# How much faster the budget drains per unit of escape drive at no strength.
const PIN_ESCAPE_RATE: float = 2.0
# Along-wall deceleration on the pinned body at full strength: a body pressed
# into the glass by another's weight. Above a stride's push, so a pinned skater
# cannot skate out along the wall — he escapes by wearing the pin down.
const PIN_HOLD_DECEL_M_S2: float = 14.0


# Outward unit normal (XZ) of the boards when a body of `body_radius` at `pos` has
# its edge within `margin` of them, else ZERO.
static func wall_normal(pos: Vector3, body_radius: float, margin: float) -> Vector2:
	var xz := Vector2(pos.x, pos.z)
	var inner: Vector2 = GameRules.clamp_to_rink_inner(xz, body_radius + margin)
	var out: Vector2 = xz - inner
	if out.length_squared() < 1e-8:
		return Vector2.ZERO
	return out.normalized()


# The hit strength the stagger and knockdown read: the victim's open-ice Δv, or,
# driven square into the boards, the whole closing speed the transfer carried —
# the wall stops him, so none of it goes into his recoil.
static func backstop_hit_strength(open_ice_dv: float, closing_speed: float,
		transfer: float, hit_dir: Vector2, wall_out: Vector2) -> float:
	if wall_out == Vector2.ZERO or hit_dir.dot(wall_out) < BACKSTOP_MIN_INTO_WALL:
		return open_ice_dv
	return maxf(open_ice_dv, closing_speed * transfer)


static func pin_strength(defender_mass: float, victim_mass: float) -> float:
	var total: float = defender_mass + victim_mass
	return 0.5 if total <= 0.0 else defender_mass / total


# A committed checker in contact, driving the victim (whose boards are `wall_out`)
# into the wall along `hit_dir`.
static func pin_holds(committed: bool, hit_dir: Vector2, defender_vel: Vector3,
		defender_intent: Vector2, wall_out: Vector2) -> bool:
	if not committed or wall_out == Vector2.ZERO \
			or hit_dir.dot(wall_out) < BACKSTOP_MIN_INTO_WALL:
		return false
	return Vector2(defender_vel.x, defender_vel.z).dot(wall_out) >= PIN_DRIVE_MIN_M_S \
			or defender_intent.dot(wall_out) >= PIN_DRIVE_MIN_INTENT


# How hard the pinned skater is working along the wall (0..1): the push that
# wears a pin down.
static func escape_drive(move_intent: Vector2, wall_out: Vector2) -> float:
	if wall_out == Vector2.ZERO:
		return 0.0
	return absf(move_intent.dot(Vector2(-wall_out.y, wall_out.x)))


static func budget_drain_rate(escape: float, strength: float) -> float:
	return 1.0 + escape * (1.0 - strength) * PIN_ESCAPE_RATE


# One tick of the pin on the victim's velocity: the along-wall part bleeds by the
# held deceleration, the rest is the wall's and the checker's business.
static func apply_pin(vel: Vector3, wall_out: Vector2, strength: float, delta: float) -> Vector3:
	if wall_out == Vector2.ZERO:
		return vel
	var along_dir := Vector2(-wall_out.y, wall_out.x)
	var v := Vector2(vel.x, vel.z)
	var along: float = v.dot(along_dir)
	var rest: Vector2 = v - along_dir * along
	along = move_toward(along, 0.0, PIN_HOLD_DECEL_M_S2 * strength * delta)
	v = rest + along_dir * along
	return Vector3(v.x, vel.y, v.y)


# The pin's effect over a forward prediction of `window_s` from a snapshot, as one
# correction to the integrated `result` (filled in place): the along-wall speed
# bled for as long as the replicated grip lasts inside the window, and the
# distance that bleed would not have covered. Integration ignores the boards, so
# this is not exact; it is the SAME correction on the client render and the host
# rewind (render == rewind), and the next snapshot absorbs the rest.
static func forward_correction(result: SkaterMovementRules.ForwardResult,
		wall_out: Vector2, pin_timer: float, strength: float, window_s: float) -> void:
	if pin_timer <= 0.0 or wall_out == Vector2.ZERO or window_s <= 0.0:
		return
	var along_dir := Vector2(-wall_out.y, wall_out.x)
	var v := Vector2(result.velocity.x, result.velocity.z)
	var along: float = v.dot(along_dir)
	var pinned_s: float = minf(pin_timer, window_s)
	var bleed: float = minf(absf(along), PIN_HOLD_DECEL_M_S2 * strength * pinned_s)
	var dir: Vector2 = along_dir * signf(along)
	# The bleed ramps in over the pinned stretch: the distance lost is the area of
	# that ramp, then the full bleed for whatever of the window remains.
	var lost: float = bleed * pinned_s * 0.5 + bleed * (window_s - pinned_s)
	result.position -= Vector3(dir.x, 0.0, dir.y) * lost
	result.velocity.x -= dir.x * bleed
	result.velocity.z -= dir.y * bleed

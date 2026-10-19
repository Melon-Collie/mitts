class_name BoardPinRules
extends RefCounted

# The boards as a party to body contact: a check that drives a skater into the
# wall lands harder (the wall takes the recoil his skates would have), and a
# checker holding his stick out on the stick button who drives an unbraced
# opponent into it pins him there.
#
# A pin locks the two players together: neither stick plays the puck, they touch
# flat (locked_contact_axis), and both slide along the wall at capped speeds — the
# pinner's above the victim's, so a pinner who reads the slide keeps up. The
# victim is free once his body is no longer lined up with the pinner's along the
# wall (PIN_ESCAPE_OFFSET_M, either side). Onset, escape and every end are the host's (BoardPinTracker); the caps
# read only the replicated role and strength, so each client predicts its own.

enum Role { NONE, PINNER, PINNED }

# A victim this close to the boards (body edge to board) has nowhere to recoil.
const BACKSTOP_MARGIN_M: float = 0.15
# The hit has to be driving into the wall, not along it: within 45° of square.
const BACKSTOP_MIN_INTO_WALL: float = 0.7071

# The pin needs the victim's edge within this of the boards.
const PIN_WALL_MARGIN_M: float = 0.25
# A pinned body pushed further off the wall than this is no longer pinned.
const PIN_WALL_RELEASE_M: float = PIN_WALL_MARGIN_M + 0.25
# A checker is driving the victim in when pushing into the wall at walking pace,
# or holding the stick at least half into it (pressed flat against a body his
# velocity reads ~0 — the intent is what is still pushing).
const PIN_DRIVE_MIN_M_S: float = 1.0
const PIN_DRIVE_MIN_INTENT: float = 0.5
# Bodies count as in contact within this of touching (the collision resolver
# leaves them about there).
const PIN_CONTACT_SLACK_M: float = 0.05
# The lock ends once the bodies are this far apart beyond touching.
const PIN_SEPARATION_M: float = 0.15
# The cap that keeps a stalemate from lasting forever; above the frozen-puck
# count (FrozenPuckRules.FROZEN_S), so a trapped puck is whistled first.
const PIN_MAX_S: float = 3.0
const PIN_IMMUNITY_S: float = 1.0

# Along-wall speed caps while locked. The victim's scales with the weight against
# him (× 2·(1 − strength): a heavier pinner slows him, a lighter one doesn't);
# the pinner's sits above the victim's fastest, so a correct read keeps up.
const PIN_SLIDE_VICTIM_M_S: float = 1.0
const PIN_SLIDE_PINNER_M_S: float = 1.4
# The victim is free once his body is this far along the wall from the pinner's,
# either side: a hip's width at the 0.35 m body radius.
const PIN_ESCAPE_OFFSET_M: float = 0.5
# The network part of how late the pinner sees the victim slide (interpolation
# plus a typical trip; the tie's budget). The offset covers a reversal read that
# late; a late human reaction is not covered — reading the slide is the skill.
const PIN_LAG_BUDGET_S: float = StickCheckRules.TIE_LAG_BUDGET_S


# Outward unit normal (XZ) of the boards when a body of `body_radius` at `pos` has
# its edge within `margin` of them, else ZERO.
static func wall_normal(pos: Vector3, body_radius: float, margin: float) -> Vector2:
	var xz := Vector2(pos.x, pos.z)
	var inner: Vector2 = GameRules.clamp_to_rink_inner(xz, body_radius + margin)
	var out: Vector2 = xz - inner
	if out.length_squared() < 1e-8:
		return Vector2.ZERO
	return out.normalized()


# The boards a locked player slides along: the victim is at them, the pinner a
# body and a separation off them, so each looks out as far as its role reaches.
static func locked_wall_normal(pos: Vector3, body_radius: float, role: int) -> Vector2:
	var margin: float = PIN_WALL_RELEASE_M
	if role == Role.PINNER:
		margin += 2.0 * body_radius + PIN_SEPARATION_M + PIN_CONTACT_SLACK_M
	return wall_normal(pos, body_radius, margin)


# The contact axis of a locked pair, from a to b: the boards' outward normal (into
# the wall when b is the pinned one). The two are pressed flat into the glass, so
# driving in presses the victim into the wall and never squeezes him along it, as
# two discs touching off-centre would. ZERO for any other pair, whose contact
# keeps the disc axis.
static func locked_contact_axis(pos_a: Vector3, role_a: int, radius_a: float,
		pos_b: Vector3, role_b: int, radius_b: float) -> Vector3:
	if role_a == Role.NONE or role_b == Role.NONE or role_a == role_b:
		return Vector3.ZERO
	var b_pinned: bool = role_b == Role.PINNED
	var out: Vector2 = locked_wall_normal(pos_b if b_pinned else pos_a,
			radius_b if b_pinned else radius_a, Role.PINNED)
	if out == Vector2.ZERO:
		return Vector3.ZERO
	var n := Vector3(out.x, 0.0, out.y)
	return n if b_pinned else -n


# How far apart a locked pair's bodies are along the boards' normal (pinner to
# victim, edge to edge): the gap their flat contact keeps, whatever the
# along-wall offset.
static func locked_gap(victim_pos: Vector3, victim_radius: float, pinner_pos: Vector3,
		pinner_radius: float, wall_out: Vector2) -> float:
	return Vector2(victim_pos.x - pinner_pos.x, victim_pos.z - pinner_pos.z).dot(wall_out) \
			- victim_radius - pinner_radius


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


# A checker in contact, reaching for the pin with his stick held out, driving an
# unbraced victim (whose boards are `wall_out`) into the wall along `hit_dir`. A
# victim holding the commit button is braced: he can be hit, but not pinned.
static func pin_holds(reaching: bool, victim_braced: bool, hit_dir: Vector2,
		defender_vel: Vector3, defender_intent: Vector2, wall_out: Vector2) -> bool:
	if not reaching or victim_braced or wall_out == Vector2.ZERO \
			or hit_dir.dot(wall_out) < BACKSTOP_MIN_INTO_WALL:
		return false
	return Vector2(defender_vel.x, defender_vel.z).dot(wall_out) >= PIN_DRIVE_MIN_M_S \
			or defender_intent.dot(wall_out) >= PIN_DRIVE_MIN_INTENT


static func slide_cap(role: int, strength: float) -> float:
	match role:
		Role.PINNER:
			return PIN_SLIDE_PINNER_M_S
		Role.PINNED:
			return PIN_SLIDE_VICTIM_M_S * 2.0 * (1.0 - clampf(strength, 0.0, 1.0))
	return INF


# The victim's along-wall offset from the pinner (signed, metres).
static func along_wall_offset(victim_pos: Vector3, pinner_pos: Vector3,
		wall_out: Vector2) -> float:
	var along := Vector2(-wall_out.y, wall_out.x)
	return Vector2(victim_pos.x - pinner_pos.x, victim_pos.z - pinner_pos.z).dot(along)


static func escaped(offset: float) -> bool:
	return absf(offset) > PIN_ESCAPE_OFFSET_M


# One tick of the lock on a body's velocity: its along-wall part clamped to the
# role's cap; the rest is the wall's and the bodies' business.
static func apply_slide_cap(vel: Vector3, wall_out: Vector2, cap: float) -> Vector3:
	if wall_out == Vector2.ZERO or cap == INF:
		return vel
	var along_dir := Vector2(-wall_out.y, wall_out.x)
	var v := Vector2(vel.x, vel.z)
	var along: float = v.dot(along_dir)
	var capped: float = clampf(along, -cap, cap)
	if capped == along:
		return vel
	v += along_dir * (capped - along)
	return Vector3(v.x, vel.y, v.y)


# forward_cap for a body locked in `role` at `pos` (a snapshot's): the one call the
# client render and the host rewind both make.
static func forward_cap_locked(result: SkaterMovementRules.ForwardResult, pos: Vector3,
		body_radius: float, role: int, strength: float, window_s: float) -> void:
	if role == Role.NONE:
		return
	forward_cap(result, locked_wall_normal(pos, body_radius, role), slide_cap(role, strength),
			window_s)


# The lock over a forward prediction of `window_s` from a snapshot, as one
# correction to the integrated `result` (filled in place): the along-wall speed
# clamped to the cap, and the travel the excess would have covered taken back.
# Integration ignores the boards, so this is not exact; it is the SAME
# correction on the client render and the host rewind (render == rewind), and the
# next snapshot absorbs the rest.
static func forward_cap(result: SkaterMovementRules.ForwardResult, wall_out: Vector2,
		cap: float, window_s: float) -> void:
	if wall_out == Vector2.ZERO or cap == INF or window_s <= 0.0:
		return
	var along_dir := Vector2(-wall_out.y, wall_out.x)
	var along: float = Vector2(result.velocity.x, result.velocity.z).dot(along_dir)
	var excess: float = along - clampf(along, -cap, cap)
	if excess == 0.0:
		return
	var back: Vector2 = along_dir * excess
	result.velocity.x -= back.x
	result.velocity.z -= back.y
	result.position.x -= back.x * window_s
	result.position.z -= back.y * window_s

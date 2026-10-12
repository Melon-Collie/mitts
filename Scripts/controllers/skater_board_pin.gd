class_name SkaterBoardPin
extends RefCounted

# The victim's side of a board pin (BoardPinRules). Owns all four fields: the
# replicated grip and strength, stepped like stagger_timer everywhere, and the
# host-only budget and immunity that cap a pin and space them out. The host
# refreshes the grip through hold() on every tick the checker drives the victim
# into the wall; nothing else starts or extends one.

var timer: float = 0.0
var strength: float = 0.0
var _budget: float = 0.0
var _immunity: float = 0.0


func is_pinned() -> bool:
	return timer > 0.0


func hold(p_strength: float) -> void:
	if _immunity > 0.0:
		return
	if timer <= 0.0:
		_budget = BoardPinRules.PIN_MAX_S
	strength = p_strength
	timer = BoardPinRules.PIN_GRIP_S


# One tick on the victim's velocity. Only the authoritative machine spends the
# budget (wearing the pin down by working along the wall) and starts immunity;
# a predicting client just lets the grip run down.
func step(vel: Vector3, wall_out: Vector2, move_intent: Vector2, authoritative: bool,
		delta: float) -> Vector3:
	if timer <= 0.0:
		if authoritative:
			_immunity = maxf(_immunity - delta, 0.0)
		return vel
	vel = BoardPinRules.apply_pin(vel, wall_out, strength, delta)
	timer = maxf(timer - delta, 0.0)
	if authoritative:
		_budget -= delta * BoardPinRules.budget_drain_rate(
				BoardPinRules.escape_drive(move_intent, wall_out), strength)
		if _budget <= 0.0:
			timer = 0.0
		if timer <= 0.0:
			_immunity = BoardPinRules.PIN_IMMUNITY_S
	return vel


func release() -> void:
	if timer > 0.0:
		timer = 0.0
		_immunity = BoardPinRules.PIN_IMMUNITY_S


func adopt(wire_timer: float, wire_strength: float) -> void:
	timer = wire_timer
	strength = wire_strength


func reset() -> void:
	timer = 0.0
	strength = 0.0
	_budget = 0.0
	_immunity = 0.0

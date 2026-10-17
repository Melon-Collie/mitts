class_name ReceptionSettle
extends RefCounted

# The receiver's hands after a hard catch: until the settle ends, no shot or
# pass may leave the blade, and a press made meanwhile is held and fires on the
# first input past the end.
#
# The window is measured on the INPUT STAMP clock, in the wire's 0.1 ms units,
# never as a countdown: the host arms it on the grant tick and the carrier's
# client adopts the same end stamp from the pickup event, so both release a held
# press on the same input, and reconcile replay re-derives every locked tick from
# the stamps alone. Only the held presses are state that replay would evolve;
# LocalController saves and restores them around it.

const _Constants: GDScript = preload("res://Scripts/game/constants.gd")

# End of the window, exclusive. 0 = not settling.
var until_units: int = 0
# Stamp of the input the controller is processing.
var stamp_units: int = 0
var held_quick_pass: bool = false
var held_shoot: bool = false
var held_slap: bool = false


static func to_units(stamp_s: float) -> int:
	return roundi(maxf(stamp_s, 0.0) * _Constants.TIME_WIRE_SCALE)


func observe(stamp_s: float) -> void:
	stamp_units = to_units(stamp_s)


# Host: open a window of `seconds` past the input just processed. Returns the end
# stamp the carrier's client must adopt (0 when there is nothing to settle).
func arm(seconds: float) -> int:
	clear()
	if seconds <= 0.0:
		return 0
	until_units = stamp_units + roundi(seconds * _Constants.TIME_WIRE_SCALE)
	return until_units


func adopt(end_units: int) -> void:
	clear()
	until_units = maxi(end_units, 0)


func clear() -> void:
	until_units = 0
	held_quick_pass = false
	held_shoot = false
	held_slap = false


func is_locked() -> bool:
	return stamp_units < until_units


func remaining_s() -> float:
	return maxf(0.0, float(until_units - stamp_units) / _Constants.TIME_WIRE_SCALE)


func copy_from(other: ReceptionSettle) -> void:
	until_units = other.until_units
	stamp_units = other.stamp_units
	held_quick_pass = other.held_quick_pass
	held_shoot = other.held_shoot
	held_slap = other.held_slap


func hold(input: InputState) -> void:
	held_quick_pass = held_quick_pass or input.quick_pass_pressed
	held_shoot = held_shoot or input.shoot_pressed
	held_slap = held_slap or input.slap_pressed

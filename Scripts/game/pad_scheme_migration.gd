class_name PadSchemeMigration
extends RefCounted

# One-time remaps of saved gamepad binds when the default pad scheme changes.
# A saved config holds every pad bind, defaults included, so a new default never
# reaches an existing player on its own.

# The defaults scheme 2 moved off: the loft and the ping onto the D-pad.
const SCHEME_1_DEFAULTS: Dictionary = {
	"elevation_up": JOY_BUTTON_Y,
	"elevation_down": JOY_BUTTON_X,
	"smart_ping": JOY_BUTTON_DPAD_UP,
}

# The defaults scheme 3 moved off: the hit onto RB, the deflect onto L3.
const SCHEME_2_DEFAULTS: Dictionary = {
	"hit": JOY_BUTTON_LEFT_STICK,
	"stick_lift": JOY_BUTTON_RIGHT_SHOULDER,
}


static func to_scheme_2(pad: Dictionary, defaults: Dictionary) -> void:
	_move_off(pad, defaults, SCHEME_1_DEFAULTS)


static func to_scheme_3(pad: Dictionary, defaults: Dictionary) -> void:
	_move_off(pad, defaults, SCHEME_2_DEFAULTS)


# Each action still on its `old` default is erased so the caller's default fill
# reseeds it from `defaults`. One the player rebound stays put, and so does one
# whose new button another of the player's binds already holds, which would
# otherwise double-fire off one press. An action that stays keeps its old
# button, which can in turn block another (the ping staying on D-pad up blocks
# the loft), hence the loop to a fixed point.
static func _move_off(pad: Dictionary, defaults: Dictionary, old: Dictionary) -> void:
	var moving: Array[String] = []
	for action: String in old:
		if int(pad.get(action, -1)) == int(old[action]):
			moving.append(action)
	var settled: bool = false
	while not settled:
		settled = true
		for action: String in moving.duplicate():
			var target: int = int(defaults[action])
			for other: String in pad:
				if not moving.has(other) and int(pad[other]) == target:
					moving.erase(action)
					settled = false
					break
	for action: String in moving:
		pad.erase(action)

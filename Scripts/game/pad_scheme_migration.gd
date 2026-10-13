class_name PadSchemeMigration
extends RefCounted

# One-time remaps of saved gamepad binds when the default pad scheme changes.
# A saved config holds every pad bind, defaults included, so a new default never
# reaches an existing player on its own.

# The defaults scheme 2 moved off.
const SCHEME_1_DEFAULTS: Dictionary = {
	"elevation_up": JOY_BUTTON_Y,
	"elevation_down": JOY_BUTTON_X,
	"smart_ping": JOY_BUTTON_DPAD_UP,
}


# Scheme 2 moves the loft and the ping onto the D-pad. Each action still on its
# scheme-1 default is erased so the caller's default fill reseeds it from
# `defaults`. One the player rebound stays put, and so does one whose new button
# another of the player's binds already holds, which would otherwise double-fire
# off one press. An action that stays keeps its old button, which can in turn
# block another (the ping staying on D-pad up blocks the loft), hence the loop to
# a fixed point.
static func to_scheme_2(pad: Dictionary, defaults: Dictionary) -> void:
	var moving: Array[String] = []
	for action: String in SCHEME_1_DEFAULTS:
		if int(pad.get(action, -1)) == int(SCHEME_1_DEFAULTS[action]):
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

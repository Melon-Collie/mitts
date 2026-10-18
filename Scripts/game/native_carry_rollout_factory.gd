class_name NativeCarryRolloutFactory

# Builds a NativeCarryRollout (C++ GDExtension, native/src/) configured from the
# live GDScript symbols — the rink and cage geometry and AICarryRollout's move
# set and clock — for AICarryRollout.native_factory. Each rollout gets its own:
# the kernel holds its results, and the bots run on the AI worker.
#
# Returns null when the extension isn't loaded; the rollout then rolls GDScript.


static func install() -> void:
	if ClassDB.class_exists(&"NativeCarryRollout"):
		AICarryRollout.native_factory = make_configured


static func make_configured() -> RefCounted:
	if not ClassDB.class_exists(&"NativeCarryRollout"):
		return null
	var native: RefCounted = ClassDB.instantiate(&"NativeCarryRollout")
	native.set_geometry(
			GameRules.INNER_HALF_WIDTH, GameRules.INNER_HALF_LENGTH,
			GameRules.INNER_CORNER_RADIUS,
			GameRules.CORNER_CENTER_X, GameRules.CORNER_CENTER_Z,
			GameRules.GOAL_LINE_Z, GameRules.NET_DEPTH, GameRules.NET_BACK_HALF_WIDTH)
	native.set_moves(AICarryRollout.SOFT_TURN_RAD, AICarryRollout.HARD_TURN_RAD,
			AICarryRollout.DT, AICarryRollout.TICKS, AICarryRollout.SAMPLES)
	native.set_stance(AICarryRollout.STANCE_TURN_WINDOW_S,
			deg_to_rad(AISteering.STANCE_CUT_MAX_ANGLE_DEG), AISteering.STANCE_RELEASE_FRACTION,
			GameRules.DEFAULT_SKATER_MAX_TURN_RATE_RAD_S, FacingRules.STANCE_SQUARE_BLEND_M_S)
	return native

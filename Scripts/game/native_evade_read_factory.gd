class_name NativeEvadeReadFactory

# Builds a NativeEvadeRead (C++ GDExtension, native/src/) configured from the
# live GDScript constants it ports (AICarrySpace, AIArrival, AIStrideRamp, the
# rink) and installs it as AIEvadeRead.native. A read keeps nothing between
# calls, so one instance serves every caller.
#
# Leaves AIEvadeRead on GDScript when the extension isn't loaded.


static func install() -> void:
	AIEvadeRead.native = make()


static func make() -> RefCounted:
	if not ClassDB.class_exists(&"NativeEvadeRead"):
		return null
	var native: RefCounted = ClassDB.instantiate(&"NativeEvadeRead")
	native.set_kinematics(AICarrySpace.MANEUVER_ACCEL_M_S2, AICarrySpace.EVADE_STICK_REACH_M,
			AIArrival.SKATER_REF_SPEED_M_S, AICarrySpace.EVADE_REACTION_S,
			AIArrival.VM_FREE_SHED_M_S, AIArrival.VM_SHED_DECEL_M_S2,
			AIArrival.REVERSAL_BRAKE_DECEL_M_S2, GameRules.DEFAULT_SKATER_POWER_KNEE_M_S,
			AIStrideRamp.EFFICIENCY, AICarrySpace.EVADE_SAFE_MARGIN_M)
	native.set_rink(GameRules.INNER_HALF_WIDTH, GameRules.INNER_HALF_LENGTH,
			GameRules.INNER_CORNER_RADIUS, GameRules.CORNER_CENTER_X, GameRules.CORNER_CENTER_Z)
	native.set_sweep(AICarrySpace.EVADE_HORIZON_S, AICarrySpace.EVADE_SAMPLE_ANGLES,
			PackedFloat64Array(AICarrySpace.EVADE_SAMPLE_RINGS),
			AICarrySpace.POKE_CONTACT_RADIUS_M + AICarrySpace.DWELL_HALF_BAND_M,
			AICarrySpace.POKE_CONTACT_RADIUS_M, AICarrySpace.DWELL_HALF_BAND_M)
	return native

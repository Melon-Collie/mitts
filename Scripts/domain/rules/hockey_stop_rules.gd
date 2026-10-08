class_name HockeyStopRules

# Pure math for the cosmetic hockey-stop pose: the LOWER BODY yaws across the
# travel direction (legs sideways, blades scraping) while the torso keeps
# facing the play — the signature stop silhouette. When the stop is on is the
# locomotion state's (LocomotionRules); this file owns the side, which must not
# wobble frame-to-frame, and the yaw.
#
# Conventions: skater local frame with −Z forward, +X right. Yaw values are
# lower-body rotation.y offsets, where POSITIVE rotation.y turns the legs
# toward −X (left).
#
# Mirrored in C++ by NativeSkaterGait (native/src/native_skater_gait.cpp);
# test_native_gait_parity.gd fails if the two drift. Change both or neither.

# Which hip leads the stop, latched ONCE at engagement (travel direction
# wobbles during the skid; re-deriving per tick would flip the legs
# mid-stop). Lateral drift picks the natural side — momentum sliding toward
# the skater's right (+X) plants the right side; dead-straight travel
# defaults to a right-side stop.
static func latch_side(local_velocity: Vector3) -> float:
	return 1.0 if local_velocity.x >= 0.0 else -1.0


# Lower-body yaw offset that turns the legs perpendicular to TRAVEL (not to
# facing — you stop across your momentum wherever you're looking), on the
# latched side, capped so the rig never fully breaks from under the torso.
# Wrapped before clamping so backward travel resolves to the near-side
# perpendicular instead of a wound-up full turn.
static func stop_yaw(local_velocity: Vector3, side: float, max_yaw: float) -> float:
	var fwd: float = -local_velocity.z
	var lat: float = local_velocity.x
	if Vector2(lat, fwd).length() < 0.01:
		return 0.0
	# Body-frame travel angle: 0 = straight ahead, positive = toward +X (right).
	var travel_angle: float = atan2(lat, fwd)
	var legs_angle: float = wrapf(travel_angle + side * PI * 0.5, -PI, PI)
	# rotation.y positive = legs toward −X (left) = NEGATIVE body-frame angle.
	return clampf(-legs_angle, -max_yaw, max_yaw)

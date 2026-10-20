class_name DeflectReachRules

# How high a committed deflect's blade rises: the puck's height where its path
# passes nearest the blade, so the player holds the button and the stick goes to
# meet the puck instead of the player pre-picking an ice or air plane.

# A line passing further than this off the blade is not coming to this stick: a
# blade reaches about this far across while the puck is in flight.
const TRACK_RADIUS_M: float = 1.5
# The blade rises for a puck arriving within this long. A full rise takes under
# a tenth of a second (Skater._BLADE_LIFT_BLEND_SPEED), so this is time to read
# the puck, not time to get there.
const TRACK_HORIZON_S: float = 0.5


# Height (m) above `rest_y` the puck's centre will sit at its closest approach to
# `blade` in XZ, within TRACK_HORIZON_S and TRACK_RADIUS_M; 0 when no puck is
# coming. Ballistic flight without bounces: a puck that lands on the way is
# met on the ice. A puck already past the blade is read where it is now.
static func lift_to_meet(puck_pos: Vector3, puck_vel: Vector3, blade: Vector3,
		rest_y: float) -> float:
	var dx: float = puck_pos.x - blade.x
	var dz: float = puck_pos.z - blade.z
	var v2: float = puck_vel.x * puck_vel.x + puck_vel.z * puck_vel.z
	var t: float = 0.0
	if v2 > 0.0001:
		t = maxf(-(dx * puck_vel.x + dz * puck_vel.z) / v2, 0.0)
	if t > TRACK_HORIZON_S:
		return 0.0
	var mx: float = dx + puck_vel.x * t
	var mz: float = dz + puck_vel.z * t
	if mx * mx + mz * mz > TRACK_RADIUS_M * TRACK_RADIUS_M:
		return 0.0
	var y: float = puck_pos.y + puck_vel.y * t - 0.5 * GameRules.GRAVITY_M_S2 * t * t
	return maxf(y - rest_y, 0.0)

class_name TorsoSection
extends RefCounted

# The jersey's torso as a stack of elliptical rings, the measure the arms are
# kept out of: `profile` is (height, radius) per ring from the collar down,
# `sway` each ring's shift toward the back (+Z), `xz_scale` the ellipse's
# lateral and depth scale on the radius. The skater's own section is
# SkaterMeshBuilder's (TORSO_PROFILE, TORSO_REAR_SWAY, TORSO_XZ_SCALE).


# How far `p` (torso-local) lies outside the rings, metres, negative inside:
# along the ellipse's radius at p's height, the circumscribed ellipse of a
# faceted ring, so a point that clears it clears the faces. Below the hem the
# section hangs on at the hem's girth; above the collar is the neck and head,
# which this does not measure, so INF.
static func clearance(p: Vector3, profile: Array[Vector2], sway: Array[float],
		xz_scale: Vector2) -> float:
	if p.y > profile[0].x + 0.0001:
		return INF
	var last: int = profile.size() - 1
	var radius: float = profile[last].y
	var back: float = sway[last]
	for i: int in last:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if p.y >= b.x:
			var t: float = (a.x - p.y) / (a.x - b.x)
			radius = lerpf(a.y, b.y, t)
			back = lerpf(sway[i], sway[i + 1], t)
			break
	var q := Vector2(p.x, p.z - back)
	var span: float = q.length()
	if span < 0.000001:
		return -radius * xz_scale.y
	var e: float = Vector2(q.x / (radius * xz_scale.x), q.y / (radius * xz_scale.y)).length()
	return span * (1.0 - 1.0 / e)

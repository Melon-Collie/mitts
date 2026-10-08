class_name BalanceRules

# How a skater's body leans to stay balanced, as pure math.
#
# A body accelerating over a fixed contact (the blades) balances by inclining
# toward its acceleration until gravity and the push resolve along the body:
# atan(|a| / g), in the direction of a. One model covers the whole family — a
# turn's centripetal acceleration banks it into the arc, a start's thrust tips it
# forward, a stop's deceleration sits it back — so none of them is authored.
#
# Getting there takes time, because the centre of mass has to be moved over the
# edges, so the lean is the response of a critically damped spring rather than
# the target itself. That is what makes a steering correction read as nothing
# and a sustained arc read as a lean: the spring passes the second and filters
# the first.
#
# Frame: XZ-plane vectors as Vector2(x, z), radians for tilt magnitudes.

const GRAVITY: float = 9.8


# The balancing tilt for a horizontal acceleration: direction of `accel`,
# magnitude atan(|a| / g) eased into `cap` (cap · tanh(angle / cap)) rather
# than clipped at it. A gentle push leans by its balancing angle; a hard one
# approaches the cap without a corner, so pushes of different strength still
# read as different leans instead of all landing on the same ceiling.
static func balance_tilt(accel: Vector2, cap: float) -> Vector2:
	var a: float = accel.length()
	if a < 1e-6 or cap <= 0.0:
		return Vector2.ZERO
	return accel / a * cap * tanh(atan2(a, GRAVITY) / cap)


# One step of a critically damped spring toward a target held over the step,
# solved exactly rather than integrated, so the result does not depend on how
# the interval is chopped (render frames come at any rate). Returns
# (x.x, x.y, v.x, v.y): a value type, so the per-frame call allocates nothing.
static func spring_step(x: Vector2, v: Vector2, target: Vector2,
		omega: float, dt: float) -> Vector4:
	var d: Vector2 = x - target
	var c: Vector2 = v + d * omega
	var e: float = exp(-omega * dt)
	var x1: Vector2 = target + (d + c * dt) * e
	var v1: Vector2 = (v - c * (omega * dt)) * e
	return Vector4(x1.x, x1.y, v1.x, v1.y)

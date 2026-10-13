class_name ClothSwayRules

# How a loose piece of kit — the jersey hem — swings on the body it hangs from,
# as pure math. Cosmetic: nothing gameplay reads comes out of here.
#
# A hem is a stiff pendulum. In a body accelerating at a it hangs back by
# atan(|a| / g) against the acceleration, which is the balance lean the skater
# already carries (BalanceRules.balance_tilt), so the hem's rest swing is a share
# of that lean pointed the other way. It gets there underdamped — cloth
# overshoots and settles — which is the one thing that separates it from the
# lean's own critically damped spring.
#
# Frame: XZ-plane vectors as Vector2(x, z) in the frame the hem hangs in, radians.


# Where the hem swings to for a balance lean `tilt` already turned into the
# hem's frame: `gain` of it, pointed away from the acceleration, eased into `cap`
# rather than clipped.
static func rest_swing(tilt: Vector2, gain: float, cap: float) -> Vector2:
	var a: float = tilt.length() * gain
	if a < 1e-6 or cap <= 0.0:
		return Vector2.ZERO
	return -tilt / tilt.length() * cap * tanh(a / cap)


# One step of an underdamped spring (0 < zeta < 1) toward a target held over the
# step, solved exactly so the result does not depend on how the interval is
# chopped. Returns (x.x, x.y, v.x, v.y) — a value type, so the per-frame call
# allocates nothing.
static func step(x: Vector2, v: Vector2, target: Vector2, omega: float, zeta: float,
		dt: float) -> Vector4:
	var d: Vector2 = x - target
	var wd: float = omega * sqrt(1.0 - zeta * zeta)
	var decay: float = exp(-zeta * omega * dt)
	var c: float = cos(wd * dt)
	var s: float = sin(wd * dt)
	var b: Vector2 = (v + d * (zeta * omega)) / wd
	var d1: Vector2 = (d * c + b * s) * decay
	var v1: Vector2 = ((b * c - d * s) * wd - (d * c + b * s) * (zeta * omega)) * decay
	var x1: Vector2 = target + d1
	return Vector4(x1.x, x1.y, v1.x, v1.y)

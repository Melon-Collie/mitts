class_name EaseRules

# A blend eased toward its target by a critically damped spring rather than a
# first-order lag. A lag answers a step in its target at full rate on the very
# first frame: every weight the gait blends by moved the body in a corner (the
# crouch dropped at ~4 m/s from rest the tick a stop began). The spring starts
# from rest, arrives in the same time and never overshoots a held target.
#
# Solved exactly, so the result does not depend on how the interval is chopped
# (render frames come at any rate). Two calls, one for each half of the state,
# so a caller keeps its scalars in 64-bit floats.

# The spring's ω for a first-order rate k (1/s): settles to 90% in about the
# time the lag took to (3.89 / ω against ln 10 / k).
const OMEGA_PER_RATE: float = 1.7


static func critical_x(x: float, v: float, target: float, omega: float, dt: float) -> float:
	var d: float = x - target
	return target + (d + (v + d * omega) * dt) * exp(-omega * dt)


static func critical_v(x: float, v: float, target: float, omega: float, dt: float) -> float:
	var c: float = v + (x - target) * omega
	return (v - c * omega * dt) * exp(-omega * dt)

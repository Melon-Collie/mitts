class_name ShuffleStepRules

# A side-stepping skate across its hip over one cycle `q` (0..1), toward the
# travel positive: planted for the first half, sweeping back at a constant rate
# from +1 to −1; lifted for the second, stepping back out. The step is the cubic
# that leaves and lands at the planted sweep's own rate, so the skate comes off
# and onto the ice at rest on it.
static func sweep(q: float) -> float:
	if q < 0.5:
		return 1.0 - 4.0 * q
	var u: float = 2.0 * q - 1.0
	return ((-8.0 * u + 12.0) * u - 2.0) * u - 1.0


static func lift(q: float) -> float:
	if q < 0.5:
		return 0.0
	return sin(PI * (2.0 * q - 1.0))

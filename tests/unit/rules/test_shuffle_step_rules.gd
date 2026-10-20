extends GutTest

# One cycle of a side-stepping skate: planted, sweeping back at a constant rate,
# then lifted and stepped back out to land where it started, at that same rate.

const H: float = 0.0001


func _rate(q: float) -> float:
	return (ShuffleStepRules.sweep(q + H) - ShuffleStepRules.sweep(q - H)) / (2.0 * H)


func test_the_cycle_closes_where_it_began() -> void:
	assert_almost_eq(ShuffleStepRules.sweep(0.0), 1.0, 1e-6)
	assert_almost_eq(ShuffleStepRules.sweep(1.0), 1.0, 1e-6)


func test_the_skate_lifts_and_lands_at_the_planted_rate() -> void:
	assert_almost_eq(ShuffleStepRules.sweep(0.5 - H), ShuffleStepRules.sweep(0.5 + H), 1e-3,
			"no jump where it lifts")
	assert_almost_eq(_rate(0.5 + 2.0 * H), -4.0, 0.05, "leaves the ice at the planted rate")
	assert_almost_eq(_rate(1.0 - 2.0 * H), -4.0, 0.05, "lands at it")


func test_it_lifts_only_while_stepping() -> void:
	assert_eq(ShuffleStepRules.lift(0.25), 0.0, "planted half")
	assert_gt(ShuffleStepRules.lift(0.75), 0.9, "lifted half")
	assert_almost_eq(ShuffleStepRules.lift(1.0), 0.0, 1e-6, "lands")

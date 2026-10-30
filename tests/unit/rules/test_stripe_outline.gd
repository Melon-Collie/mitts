extends GutTest

# A kit stripe round a tube (StripeOutline): flat, a band round the whole tube;
# peaked, a zigzag whose width stays square to its line in metres.

const _LENGTH_M: float = 0.5
const _GIRTH_M: float = 0.6


func _peaked(depth: float, count: int, first_u: float) -> Dictionary:
	return {"pos": 0.3, "width": 0.1, "color": Color.BLUE,
			"peak": {"depth": depth, "count": count, "u": first_u}}


func _inside(pieces: Array[PackedVector2Array], p: Vector2) -> bool:
	for piece: PackedVector2Array in pieces:
		if Geometry2D.is_point_in_polygon(p, piece):
			return true
	return false


# The stripe's (top, bottom) at `u`: scanned down V, each edge then bisected.
func _band_at(pieces: Array[PackedVector2Array], u: float) -> Vector2:
	var step: float = 0.002
	var v: float = -1.0
	while not _inside(pieces, Vector2(u, v)):
		v += step
	var top: float = _bisect(pieces, u, v - step, v)
	while _inside(pieces, Vector2(u, v)):
		v += step
	return Vector2(top, _bisect(pieces, u, v, v - step))


# The edge between `outside` and `inside` in V at `u`.
func _bisect(pieces: Array[PackedVector2Array], u: float, outside: float, inside: float) -> float:
	for _i: int in 30:
		var mid: float = (outside + inside) * 0.5
		if _inside(pieces, Vector2(u, mid)):
			inside = mid
		else:
			outside = mid
	return (outside + inside) * 0.5


func _centre_at(pieces: Array[PackedVector2Array], u: float) -> float:
	var band: Vector2 = _band_at(pieces, u)
	return (band.x + band.y) * 0.5


func test_a_flat_stripe_is_a_band_round_the_whole_tube() -> void:
	var pieces: Array[PackedVector2Array] = StripeOutline.of(
			{"pos": 0.3, "width": 0.1, "color": Color.BLUE}, _LENGTH_M, _GIRTH_M)
	assert_eq(pieces, [PackedVector2Array([Vector2(0.0, 0.25), Vector2(1.0, 0.25),
			Vector2(1.0, 0.35), Vector2(0.0, 0.35)])])


func test_a_peaked_stripe_drops_its_depth_at_each_peak_and_none_between() -> void:
	var pieces: Array[PackedVector2Array] = StripeOutline.of(_peaked(0.2, 2, 0.5), _LENGTH_M, _GIRTH_M)
	assert_almost_eq(_centre_at(pieces, 0.5), 0.5, 1e-4, "depth below pos on a peak")
	assert_almost_eq(_centre_at(pieces, 0.25), 0.3, 1e-4, "back at pos midway to the next")
	assert_almost_eq(_centre_at(pieces, 0.0), 0.5, 1e-4,
			"the second peak sits half way round, on the seam")


func test_a_negative_depth_peaks_up_the_tube() -> void:
	var pieces: Array[PackedVector2Array] = StripeOutline.of(_peaked(-0.1, 1, 0.5), _LENGTH_M, _GIRTH_M)
	assert_almost_eq(_centre_at(pieces, 0.5), 0.2, 1e-4)


func test_a_peaked_stripe_holds_its_width_square_to_the_line() -> void:
	var pieces: Array[PackedVector2Array] = StripeOutline.of(_peaked(0.25, 1, 0.5), _LENGTH_M, _GIRTH_M)
	# Down a slope, in metres: the vertical gap times the cosine of the slope.
	var run_m: float = 0.5 * _GIRTH_M
	var drop_m: float = 0.25 * _LENGTH_M
	var band: Vector2 = _band_at(pieces, 0.3)
	var gap_m: float = (band.y - band.x) * _LENGTH_M
	assert_almost_eq(gap_m * run_m / sqrt(run_m * run_m + drop_m * drop_m), 0.1 * _LENGTH_M, 1e-5)


func test_the_shift_turns_the_kits_u_into_the_textures() -> void:
	# A kit measuring U from a quarter turn along: its peak at 0 lands at 0.25.
	var pieces: Array[PackedVector2Array] = StripeOutline.of(_peaked(0.2, 1, 0.0), _LENGTH_M, _GIRTH_M,
			0.25)
	assert_almost_eq(_centre_at(pieces, 0.25), 0.5, 1e-4)
	assert_almost_eq(_centre_at(pieces, 0.75), 0.3, 1e-4)


func test_every_bend_keeps_the_width_and_the_seam_closes() -> void:
	# Four oscillations, kinks on the seam once the shift turns them: the band is
	# as tall on every flank, and as tall at U 0 as at U 1.
	var pieces: Array[PackedVector2Array] = StripeOutline.of(_peaked(-0.1, 4, 0.0), _LENGTH_M,
			_GIRTH_M, 0.25)
	var run_m: float = 0.125 * _GIRTH_M
	var drop_m: float = 0.1 * _LENGTH_M
	var slope_gap: float = 0.1 * sqrt(run_m * run_m + drop_m * drop_m) / run_m
	for u: float in [0.06, 0.19, 0.31, 0.44, 0.56, 0.69, 0.81, 0.94]:
		var band: Vector2 = _band_at(pieces, u)
		assert_almost_eq(band.y - band.x, slope_gap, 1e-4, "at u %.2f" % u)
	assert_almost_eq(_band_at(pieces, 0.0), _band_at(pieces, 1.0), Vector2(1e-4, 1e-4))
	for piece: PackedVector2Array in pieces:
		assert_false(Geometry2D.triangulate_polygon(piece).is_empty(), "every piece fills")


func test_the_fill_below_runs_from_the_line_down_and_follows_its_peaks() -> void:
	var area: PackedVector2Array = StripeOutline.below(_peaked(-0.1, 2, 0.0), 0.0, 1.0)
	assert_true(Geometry2D.is_point_in_polygon(Vector2(0.25, 0.35), area),
			"below the line midway, where it sits at pos")
	assert_false(Geometry2D.is_point_in_polygon(Vector2(0.25, 0.25), area), "and not above it")
	assert_true(Geometry2D.is_point_in_polygon(Vector2(0.0, 0.25), area),
			"under a peak the fill rises with it")
	var flat: PackedVector2Array = StripeOutline.below(
			{"pos": 0.3, "width": 0.1, "color": Color.BLUE}, 0.0, 1.0)
	assert_eq(flat, PackedVector2Array([Vector2(0.0, 0.3), Vector2(1.0, 0.3), Vector2(1.0, 1.0),
			Vector2(0.0, 1.0)]))


func test_a_sine_waves_through_the_same_peaks_and_troughs() -> void:
	var stripe: Dictionary = _peaked(0.2, 2, 0.5)
	stripe.peak.shape = "sine"
	var pieces: Array[PackedVector2Array] = StripeOutline.of(stripe, _LENGTH_M, _GIRTH_M)
	assert_almost_eq(_centre_at(pieces, 0.5), 0.5, 1e-3, "depth below pos on a peak")
	assert_almost_eq(_centre_at(pieces, 0.25), 0.3, 1e-3, "at pos in a trough")
	assert_almost_eq(_centre_at(pieces, 0.375), 0.4, 1e-3, "half way between, as a sine is")


func test_a_sine_holds_its_width_square_to_the_line_where_it_is_steepest() -> void:
	# Thin beside the wave, so the band's vertical cut through the steepest point
	# is its width over the slope's cosine, the curve's bend aside.
	var stripe: Dictionary = _peaked(0.2, 2, 0.5)
	stripe.width = 0.01
	stripe.peak.shape = "sine"
	var pieces: Array[PackedVector2Array] = StripeOutline.of(stripe, _LENGTH_M, _GIRTH_M)
	# The steepest point, midway from trough to peak: dV/dU = depth·π·count.
	var slope_m: float = 0.2 * PI * 2.0 * _LENGTH_M / _GIRTH_M
	var band: Vector2 = _band_at(pieces, 0.37)
	var square_m: float = (band.y - band.x) * _LENGTH_M / sqrt(1.0 + slope_m * slope_m)
	assert_almost_eq(square_m / (0.01 * _LENGTH_M), 1.0, 0.01)
	stripe.width = 0.1
	var area: PackedVector2Array = StripeOutline.below(stripe, 0.0, 1.0)
	assert_true(Geometry2D.is_point_in_polygon(Vector2(0.375, 0.45), area), "its fill follows it")
	assert_false(Geometry2D.is_point_in_polygon(Vector2(0.375, 0.35), area))

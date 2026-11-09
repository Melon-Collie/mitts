extends GutTest

# The open set's goal intervals, found from a sweep by bisecting its edges
# (open_set_edges.gd), against a keeper whose open set is known exactly.

const Edges := preload("res://tests/unit/ai/open_set_edges.gd")
const AIMS: int = 24


# A shooter against goal intervals `gaps` (m, flat [start, end, …]).
func _shooter(gaps: PackedFloat32Array) -> Callable:
	return func(aim: float) -> String:
		for k: int in range(0, gaps.size(), 2):
			if aim >= gaps[k] and aim <= gaps[k + 1]:
				return "G"
		return "s"


func _sweep(shoot: Callable) -> String:
	var s: String = ""
	for i: int in AIMS:
		s += shoot.call(Edges.aim_x(i, AIMS))
	return s


func _step() -> float:
	return 2.0 * AIShotOdds.post_reach() / float(AIMS - 1)


func test_an_interior_gap_is_found_to_within_its_last_bisection() -> void:
	var gaps := PackedFloat32Array([0.10, 0.27])
	var shoot: Callable = _shooter(gaps)
	var found: PackedFloat32Array = Edges.refine(_sweep(shoot), shoot)
	var tol: float = _step() / pow(2.0, Edges.REFINE_STEPS)
	assert_eq(found.size(), 2, "one gap")
	assert_almost_eq(found[0], gaps[0], tol, "its near edge")
	assert_almost_eq(found[1], gaps[1], tol, "its far edge")


func test_a_gap_at_the_post_ends_at_the_post() -> void:
	var reach: float = AIShotOdds.post_reach()
	var shoot: Callable = _shooter(PackedFloat32Array([-1.0, -reach + 0.02]))
	var found: PackedFloat32Array = Edges.refine(_sweep(shoot), shoot)
	assert_eq(found.size(), 2, "one gap")
	assert_almost_eq(found[0], -reach, 1e-6, "it starts at the post, not half an aim past it")
	assert_almost_eq(found[1], -reach + 0.02, _step() / pow(2.0, Edges.REFINE_STEPS),
			"and ends where the keeper's edge is")


func test_a_closed_net_has_no_intervals() -> void:
	var shoot: Callable = _shooter(PackedFloat32Array())
	assert_eq(Edges.refine(_sweep(shoot), shoot).size(), 0)


func test_the_encoding_reads_back_to_the_millimetre() -> void:
	var edges := PackedFloat32Array([-0.8469, -0.8031, 0.312, 0.398])
	var back: PackedFloat32Array = AIShotOdds.decode_intervals(Edges.encode(edges))
	assert_eq(back.size(), edges.size())
	for k: int in edges.size():
		assert_almost_eq(back[k], edges[k], 0.0005)
	assert_eq(AIShotOdds.decode_intervals("").size(), 0, "an empty loft reads as none")

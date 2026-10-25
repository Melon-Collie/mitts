extends GutTest

# The people in the building and the boxes the renderer is told they fit inside.
#
# Two unrelated things a display-less run can still check, and both have already
# shipped a bug (plus how the crowd's figure fits its seat):
#
#   · Stature. A seated spectator and a standing coach share one height and one
#     stature scale, the coach's figure two boxes joined only by
#     ArenaFigureMesh's arithmetic — a body that stretches when it should not
#     is a coach standing at a desk they should be sitting at, and a uniform
#     scale to standing height is a giant beside the crowd.
#   · Cull bounds. Every MultiMesh here declares a custom_aabb, because Godot's
#     auto-AABB mis-culls instances pushed one transform at a time. That makes
#     the box a hand-written claim about geometry the renderer never re-checks:
#     declare one smaller than its instances and they vanish the moment the
#     shortfall leaves the screen, from some camera angles and not others.
#     Instance transforms come back empty under the headless renderer, so these
#     test the growth RULE instead — that a box seeded with instance ORIGINS
#     grows enough to hold the largest figure standing at any corner of it.


func _spec() -> ArenaBowlSpec:
	return ArenaBowlSpec.new()


func _rinkside(spec: ArenaBowlSpec) -> ArenaRinkside:
	return ArenaRinkside.new(spec, ArenaBowlRake.new(spec, ArenaBowlPath.new(spec)))


# ── Stature ──────────────────────────────────────────────────────────────────

func test_standing_staff_reach_full_stature() -> void:
	# The standing body carries its own legs and scales by girth alone, while its
	# head is the seated figure's carried up by the hip height — so nothing but
	# STANDING_LIFT keeps the two joined. The crown has to land at the staffer's
	# stature above the tread they stand on, with the head resting on the body.
	var body_box: AABB = ArenaFigureMesh.standing_body_mesh().get_aabb()
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	var post := Vector3(6.0, 1.5, 2.0)
	for stature: float in [1.52, 1.75, 1.88]:
		var girth: float = ArenaFigureMesh.girth_scale(stature)
		var lift: float = ArenaFigureMesh.hip_height(stature)
		var body: Transform3D = ArenaFigureMesh.figure_transform(post, 0.0, girth)
		var head: Transform3D = ArenaFigureMesh.head_transform(post, 0.0, girth, lift)
		var body_top: float = (body * Vector3(0.0, body_box.end.y, 0.0)).y
		var head_bottom: float = (head * Vector3(0.0, head_box.position.y, 0.0)).y
		var head_top: float = (head * Vector3(0.0, head_box.end.y, 0.0)).y
		assert_almost_eq(head_top - post.y, stature, 0.001,
				"a %.2f m staffer's crown should sit %.2f m over their post"
						% [stature, stature])
		assert_gt(head_bottom, body_top, "the head should rest above the body")
		assert_lt(head_bottom - body_top, 0.05,
				"the neck gap should stay a gap, not open into a floating head")
		assert_almost_eq((body * body_box.position).y, post.y, 0.005,
				"a %.2f m staffer's shoes should stand on their post" % stature)


func test_seated_staff_sit_their_sitting_height() -> void:
	# A seated staffer is the spectator's figure at their own girth, so the crown
	# stands only their sitting height above the seat.
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	var post := Vector3(-6.0, 1.2, 0.0)
	var girth: float = ArenaFigureMesh.girth_scale(1.75)
	var head: Transform3D = ArenaFigureMesh.head_transform(post, 0.0, girth, 0.0)
	assert_almost_eq((head * Vector3(0.0, head_box.end.y, 0.0)).y - post.y,
			1.75 * ArenaFigureMesh.SITTING_HEIGHT_FRACTION, 0.001,
			"a seated staffer stands only their sitting height above the seat")


func test_a_seated_spectator_is_their_own_stature_tall() -> void:
	# The crowd's own scale is the other end of the same bridge: a spectator's
	# whole figure IS sitting height, so the crown lands at the rolled stature.
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	for stature: float in [ArenaFigureMesh.SEATED_STATURE_MIN, 0.88,
			ArenaFigureMesh.SEATED_STATURE_MAX]:
		var scale: float = ArenaFigureMesh.seated_scale(stature)
		assert_almost_eq(head_box.end.y * scale, stature, 0.0001,
				"a %.2f m seated figure should stand %.2f m over the tread"
						% [stature, stature])


# ── Postings ─────────────────────────────────────────────────────────────────

func test_only_the_coaches_stand() -> void:
	# Off-ice officials and box attendants work sitting down; the bench is the one
	# post staffed on its feet. Read through staff_postings because a MultiMesh's
	# instance transforms come back empty under the headless renderer.
	var posts: Array[Vector3] = []
	var jackets: Array[Color] = []
	var standing: Array[bool] = []
	_rinkside(_spec()).staff_postings(posts, jackets, standing)
	assert_eq(posts.size(), 9, "four coaches, two attendants, three at the table")
	assert_eq(jackets.size(), posts.size(), "every post should be dressed")
	assert_eq(standing.count(true), 4,
			"only the four bench coaches should be on their feet")
	assert_eq(standing.count(false), 5,
			"the timekeeping crew and both box attendants should be seated")


func test_seated_staff_sit_on_the_furniture_they_work_at() -> void:
	# The bug the render caught: staff placed on the terrace tread behind the
	# furniture stand a riser above the floor that furniture sits on, so they read
	# as standing ON the scorer's table. Attendants sit on the penalty bench
	# itself, and the crew's heads must clear the table without towering over it.
	var spec: ArenaBowlSpec = _spec()
	var posts: Array[Vector3] = []
	var jackets: Array[Color] = []
	var standing: Array[bool] = []
	_rinkside(spec).staff_postings(posts, jackets, standing)
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	var table_top: float = spec.stands_base_y + ArenaRinksideLayout.OFFICIALS_HEIGHT
	var seat_top: float = spec.stands_base_y + ArenaRinksideLayout.BENCH_SEAT_HEIGHT
	for i: int in posts.size():
		if standing[i]:
			continue
		var girth: float = ArenaFigureMesh.girth_scale(
				ArenaFigureMesh.STANDING_STATURE_MIN)
		assert_gt(posts[i].y + head_box.end.y * girth, table_top + 0.2,
				"a seated staffer's head should clear the counter in front of them")
		assert_lt(posts[i].y, table_top,
				"nobody should be seated above the surface they work at")
		if absf(posts[i].z) > ArenaRinksideLayout.PENALTY_BOX_CENTER_Z:
			assert_almost_eq(posts[i].y, seat_top, 0.001,
					"box attendants sit on the box's own seat block")


func test_staff_and_their_furniture_share_a_floor() -> void:
	# The whole point: nobody works a riser above the thing they work at.
	var spec: ArenaBowlSpec = _spec()
	var posts: Array[Vector3] = []
	var jackets: Array[Color] = []
	var standing: Array[bool] = []
	_rinkside(spec).staff_postings(posts, jackets, standing)
	var seat_top: float = spec.stands_base_y + ArenaRinksideLayout.BENCH_SEAT_HEIGHT
	for i: int in posts.size():
		var expected: float = spec.stands_base_y if standing[i] else seat_top
		assert_almost_eq(posts[i].y, expected, 0.0001,
				"staffer %d should stand on the furniture's own floor" % i)


# ── Cull bounds ──────────────────────────────────────────────────────────────

func test_crowd_section_bounds_hold_the_tallest_spectator() -> void:
	# The crowd figure reaches past its seat (thighs, raised arms), so the worst
	# case is its whole pose envelope at the largest roll, turned any way.
	var spec: ArenaBowlSpec = _spec()
	var crowd := ArenaCrowd.new(spec, ArenaBowlPath.new(spec),
			ArenaBowlRake.new(spec, ArenaBowlPath.new(spec)))
	var seed_box := AABB(Vector3(-4.0, 1.0, -3.0), Vector3(8.0, 2.4, 6.0))
	var grown: AABB = crowd.grow_section_aabb(seed_box)
	var pose: AABB = ArenaFigureMesh.crowd_pose_bounds()
	var scale: float = ArenaFigureMesh.CROWD_SCALE_MAX
	var reach: float = Vector2(maxf(-pose.position.x, pose.end.x),
			maxf(-pose.position.z, pose.end.z)).length() * scale
	for dx: float in [0.0, 1.0]:
		for dy: float in [0.0, 1.0]:
			for dz: float in [0.0, 1.0]:
				var foot: Vector3 = seed_box.position + seed_box.size * Vector3(dx, dy, dz)
				var figure := AABB(foot + Vector3(-reach, pose.position.y * scale, -reach),
						Vector3(reach * 2.0, pose.size.y * scale, reach * 2.0))
				assert_true(grown.encloses(figure),
						"a spectator at %v should sit inside the declared bounds" % foot)


func test_pose_bounds_hold_any_raise_of_the_arms() -> void:
	# The bound is argued, not measured from the shader: the arms only turn about
	# the shoulder and the elbow. Turn them every which way about those pivots
	# and every vertex must stay inside.
	var bounds: AABB = ArenaFigureMesh.crowd_pose_bounds().grow(0.0001)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for mesh: ArrayMesh in [ArenaFigureMesh.seated_body_mesh(), ArenaFigureMesh.far_body_mesh()]:
		var arrays: Array = mesh.surface_get_arrays(0)
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
	for i: int in verts.size():
		var part: float = uvs[i].x
		if part != ArenaFigureMesh.PART_UPPER_ARM and part != ArenaFigureMesh.PART_FOREARM:
			continue
		var m := Vector3(signf(verts[i].x), 1.0, 1.0)
		for unbend: float in [0.0, -1.0, 1.5]:
			for raise: Basis in [Basis(Vector3.RIGHT, 2.9), Basis(Vector3.RIGHT, 1.6) \
					* Basis(Vector3.BACK, 0.5), Basis(Vector3.BACK, -1.2)]:
				var v: Vector3 = verts[i]
				if part == ArenaFigureMesh.PART_FOREARM:
					var elbow: Vector3 = ArenaFigureMesh.ELBOW * m
					v = elbow + Basis(Vector3.RIGHT, unbend) * (v - elbow)
				var shoulder: Vector3 = ArenaFigureMesh.SHOULDER * m
				v = shoulder + raise * (v - shoulder)
				assert_true(bounds.has_point(v), "a raised arm at %v should stay in bounds" % v)


# ── The crowd figure in its seat ─────────────────────────────────────────────
# Each holds for both crowd figures, near and far: a far fan sits in the same
# seat as a near one.

func _crowd_bodies() -> Array[ArrayMesh]:
	return [ArenaFigureMesh.seated_body_mesh(), ArenaFigureMesh.far_body_mesh()]


func _figure_points(mesh: ArrayMesh, part_filter: float) -> PackedVector3Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var out := PackedVector3Array()
	for i: int in verts.size():
		if part_filter < 0.0 or uvs[i].x == part_filter:
			out.append(verts[i])
	return out


func test_the_crowd_body_stops_below_its_head() -> void:
	assert_lt(ArenaFigureMesh.seated_body_mesh().get_aabb().end.y,
			ArenaFigureMesh.head_mesh().get_aabb().position.y,
			"the body should stop below the head")
	assert_lt(ArenaFigureMesh.far_body_mesh().get_aabb().end.y,
			ArenaFigureMesh.far_head_mesh().get_aabb().position.y,
			"the far body should stop below its head")


func test_the_far_figure_is_as_tall_as_the_near_one() -> void:
	# The two tiers share one stature roll, so a far fan must not change height
	# where the rows hand over.
	assert_almost_eq(ArenaFigureMesh.far_head_mesh().get_aabb().end.y,
			ArenaFigureMesh.FIGURE_HEIGHT, 0.0001, "the far crown should be the figure's height")


func test_the_far_figure_costs_under_half_the_triangles() -> void:
	var near: int = ArenaFigureMesh.seated_body_mesh().surface_get_array_len(0) \
			+ ArenaFigureMesh.head_mesh().surface_get_array_len(0)
	var far: int = ArenaFigureMesh.far_body_mesh().surface_get_array_len(0) \
			+ ArenaFigureMesh.far_head_mesh().surface_get_array_len(0)
	assert_lt(far * 2, near, "the far figure should be under half the near one")


func test_knees_overhang_the_tread_but_not_the_row_below() -> void:
	# Fans sit spectator_inset_from_riser behind the drop to the row below, whose
	# seat backs stand tread_depth - BACK_OFFSET in front of them. A knee short
	# of the edge reads as legs folded into the concrete; one past the seat back
	# is through it. Checked at both stature extremes and both yaw extremes.
	var spec: ArenaBowlSpec = _spec()
	var edge: float = spec.spectator_inset_from_riser
	var row_below_back: float = spec.tread_depth - ArenaSeating.BACK_OFFSET \
			- ArenaSeating.BACK_THICKNESS * 0.5
	for mesh: ArrayMesh in _crowd_bodies():
		_assert_knees_fit(_figure_points(mesh, ArenaFigureMesh.PART_LEG), edge,
				row_below_back, spec.spectator_yaw_jitter_deg)


func _assert_knees_fit(legs: PackedVector3Array, edge: float, row_below_back: float,
		yaw_jitter_deg: float) -> void:
	for stature: float in [ArenaFigureMesh.SEATED_STATURE_MIN, ArenaFigureMesh.SEATED_STATURE_MAX]:
		var scale: float = ArenaFigureMesh.seated_scale(stature)
		for yaw_deg: float in [-yaw_jitter_deg, 0.0, yaw_jitter_deg]:
			var turn := Basis(Vector3.UP, deg_to_rad(yaw_deg))
			var farthest: float = 0.0
			for v: Vector3 in legs:
				farthest = maxf(farthest, -(turn * v).z * scale)
				assert_lt(-(turn * v).z * scale, row_below_back,
						"a %.2f m fan's knee should stop short of the row below" % stature)
			assert_gt(farthest, edge,
					"a %.2f m fan's knees should reach past the tread's edge" % stature)


func test_neighbours_elbows_do_not_meet() -> void:
	for mesh: ArrayMesh in _crowd_bodies():
		var span: float = 0.0
		for v: Vector3 in _figure_points(mesh, -1.0):
			span = maxf(span, absf(v.x))
		assert_lt(span * 2.0 * ArenaFigureMesh.CROWD_SCALE_MAX, _spec().spectator_spacing,
				"the widest fan should fit inside their seat spacing")


func test_staff_bounds_hold_the_tallest_coach() -> void:
	# The standing figure is the tall one, so the box is sized off full stature
	# rather than the seated crowd's sitting height; sideways it has to hold the
	# farthest vertex of either posture from its post, turned any way.
	var seed_box := AABB(Vector3(-14.1, 1.2, -5.6), Vector3(28.2, 0.06, 11.2))
	var grown: AABB = _rinkside(_spec()).grow_staff_aabb(seed_box)
	var girth: float = ArenaFigureMesh.girth_scale(ArenaFigureMesh.STANDING_STATURE_MAX)
	var radius: float = 0.0
	for mesh: ArrayMesh in [ArenaFigureMesh.seated_body_mesh(),
			ArenaFigureMesh.standing_body_mesh(), ArenaFigureMesh.head_mesh()]:
		for v: Vector3 in _figure_points(mesh, -1.0):
			radius = maxf(radius, Vector2(v.x, v.z).length() * girth)
	for dx: float in [0.0, 1.0]:
		for dy: float in [0.0, 1.0]:
			for dz: float in [0.0, 1.0]:
				var foot: Vector3 = seed_box.position + seed_box.size * Vector3(dx, dy, dz)
				var figure := AABB(foot - Vector3(radius, 0.0, radius), Vector3(
						radius * 2.0, ArenaFigureMesh.STANDING_STATURE_MAX, radius * 2.0))
				assert_true(grown.encloses(figure),
						"a coach at %v should sit inside the declared bounds" % foot)


func test_seat_bounds_hold_the_furniture() -> void:
	var spec: ArenaBowlSpec = _spec()
	var seating := ArenaSeating.new(spec, ArenaBowlPath.new(spec),
			ArenaBowlRake.new(spec, ArenaBowlPath.new(spec)))
	var seed_box := AABB(Vector3(-4.0, 1.0, -3.0), Vector3(8.0, 2.4, 6.0))
	var grown: AABB = seating.grow_seat_aabb(seed_box)
	var half: float = Vector2(ArenaSeating.WIDTH,
			ArenaSeating.BACK_OFFSET + ArenaSeating.BACK_THICKNESS).length() * 0.5
	for dx: float in [0.0, 1.0]:
		for dz: float in [0.0, 1.0]:
			var foot: Vector3 = seed_box.position + seed_box.size * Vector3(dx, 1.0, dz)
			assert_true(grown.encloses(AABB(foot - Vector3(half, 0.0, half),
					Vector3(half * 2.0, ArenaSeating.BACK_HEIGHT, half * 2.0))),
					"a seat at %v should sit inside the declared bounds" % foot)


func test_a_seat_clears_the_largest_occupant() -> void:
	# The seat's dimensions are all bounded by the torso they have to show around,
	# and that torso is the LARGEST stature roll, not the mesh's nominal size.
	var torso := AABB()
	var first: bool = true
	for mesh: ArrayMesh in _crowd_bodies():
		for v: Vector3 in _figure_points(mesh, ArenaFigureMesh.PART_BODY):
			torso = AABB(v, Vector3.ZERO) if first else torso.expand(v)
			first = false
	var scale: float = ArenaFigureMesh.CROWD_SCALE_MAX
	assert_gt(ArenaSeating.WIDTH, torso.size.x * scale,
			"a seat shows either side of its occupant")
	assert_lt(ArenaSeating.WIDTH, ArenaBowlSpec.new().spectator_spacing,
			"and stops short of its neighbour, or the row reads as one bench")
	assert_gt(ArenaSeating.BACK_OFFSET - ArenaSeating.BACK_THICKNESS * 0.5,
			torso.end.z * scale, "the backrest clears the deepest torso a roll can produce")


func test_only_bare_skin_is_flagged_for_hair() -> void:
	# crowd.gdshader crowns a head with hair when its paint alpha is 0, so the
	# flag must land on exactly the skin tones — never a cap, never hair.
	var spec := ArenaBowlSpec.new()
	var path := ArenaBowlPath.new(spec)
	var crowd := ArenaCrowd.new(spec, path, ArenaBowlRake.new(spec, path))
	var skin: Array[Color] = []
	for i: int in ArenaFigureMesh.BARE_HEAD_TONES:
		skin.append(ArenaFigureMesh.HEAD_PALETTE[i])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var flagged: int = 0
	for i: int in 2000:
		var picked: Array[Color] = crowd.pick_colors(rng)
		assert_eq(picked[0].a, 1.0, "a body is never flagged")
		var head: Color = picked[1]
		var opaque := Color(head.r, head.g, head.b, 1.0)
		if head.a == 0.0:
			flagged += 1
			assert_true(skin.has(opaque), "flagged head %s must be a skin tone" % head)
		else:
			assert_false(skin.has(opaque), "unflagged head %s must not be skin" % head)
	assert_gt(flagged, 0, "some of the crowd is bare-headed")


# ── Detail tiers ─────────────────────────────────────────────────────────────

func _tier_counts(detail_rows: int) -> Vector2i:
	var spec := ArenaBowlSpec.new()
	spec.num_terraces = 4
	spec.upper_terraces = 2
	spec.crowd_detail_rows = detail_rows
	var path := ArenaBowlPath.new(spec)
	var layout: Dictionary = {}
	ArenaCrowd.new(spec, path, ArenaBowlRake.new(spec, path)).fill_layout(layout)
	var counts := Vector2i.ZERO
	var bodies: Array[MultiMesh] = layout.body_mms
	var heads: Array[MultiMesh] = layout.head_mms
	for k: int in bodies.size():
		var far: bool = bodies[k].mesh.get_aabb() == ArenaFigureMesh.far_body_mesh().get_aabb()
		assert_eq(heads[k].mesh.get_aabb() == ArenaFigureMesh.far_head_mesh().get_aabb(), far,
				"a section's heads should be the same tier as its bodies")
		if far:
			counts.y += bodies[k].instance_count
		else:
			counts.x += bodies[k].instance_count
	return counts


func test_detail_rows_pick_the_near_figure() -> void:
	# Near fans are the front lower-bowl rows; everyone behind them and the
	# whole upper deck draw the far figure. Same people either way: the split
	# moves fans between tiers, never in or out of the bowl.
	var none: Vector2i = _tier_counts(0)
	var some: Vector2i = _tier_counts(2)
	var lower: Vector2i = _tier_counts(4)
	assert_eq(none.x, 0, "no detail rows should leave every fan far")
	assert_gt(some.x, 0, "the front rows should be near")
	assert_gt(some.y, 0, "the rows behind them should be far")
	assert_gt(lower.y, 0, "the upper deck stays far with the whole lower bowl near")
	assert_lt(some.x, lower.x, "more detail rows should hold more near fans")
	for counts: Vector2i in [some, lower]:
		assert_eq(counts.x + counts.y, none.y, "the split should not change the crowd")

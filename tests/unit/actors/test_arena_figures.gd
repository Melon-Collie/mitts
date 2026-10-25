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
	# Body and head ride separate transforms — only a standing body stretches —
	# so nothing but this arithmetic keeps the two joined. The crown has to land
	# at the staffer's stature above the tread they stand on, with the head
	# resting on the body rather than sunk into it.
	var body_box: AABB = ArenaFigureMesh.body_mesh().get_aabb()
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	var post := Vector3(6.0, 1.5, 2.0)
	for stature: float in [1.52, 1.75, 1.88]:
		var girth: float = ArenaFigureMesh.girth_scale(stature)
		var lift: float = ArenaFigureMesh.hip_height(stature)
		var body: Transform3D = ArenaFigureMesh.body_transform(post, 0.0, girth, lift)
		var head: Transform3D = ArenaFigureMesh.head_transform(post, 0.0, girth, lift)
		var body_top: float = body.origin.y + body_box.end.y * body.basis.get_scale().y
		var head_bottom: float = head.origin.y \
				+ head_box.position.y * head.basis.get_scale().y
		var head_top: float = head.origin.y + head_box.end.y * head.basis.get_scale().y
		assert_almost_eq(head_top - post.y, stature, 0.001,
				"a %.2f m staffer's crown should sit %.2f m over their post"
						% [stature, stature])
		assert_gt(head_bottom, body_top, "the head should rest above the body")
		assert_lt(head_bottom - body_top, 0.05,
				"the neck gap should stay a gap, not open into a floating head")


func test_seated_staff_are_the_spectator_figure() -> void:
	# Sitting is the unscaled figure, so a seated staffer (no hip lift) must come
	# out as one uniformly scaled box — the same pose the crowd is drawn in. A
	# stretched body here is someone standing at a desk they should be sitting at.
	var head_box: AABB = ArenaFigureMesh.head_mesh().get_aabb()
	var post := Vector3(-6.0, 1.2, 0.0)
	var girth: float = ArenaFigureMesh.girth_scale(1.75)
	var body: Transform3D = ArenaFigureMesh.body_transform(post, 0.0, girth, 0.0)
	var head: Transform3D = ArenaFigureMesh.head_transform(post, 0.0, girth, 0.0)
	assert_almost_eq(body.basis.get_scale().y, girth, 0.0001,
			"a seated body should not stretch")
	assert_eq(head.origin, post, "a seated head rides the body's own origin")
	assert_almost_eq(head.origin.y + head_box.end.y * girth - post.y,
			1.75 * ArenaFigureMesh.SITTING_HEIGHT_FRACTION, 0.001,
			"a seated staffer stands only their sitting height above the seat")


func test_a_seated_spectator_is_their_own_stature_tall() -> void:
	# The crowd's own scale is the other end of the same bridge: a spectator's
	# whole figure IS sitting height, so the crown lands at the rolled stature.
	var head_box: AABB = ArenaFigureMesh.crowd_head_mesh().get_aabb()
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

func _worst_case_figure(foot: Vector3, girth: float, height: float) -> AABB:
	# Widest footprint a figure can present: the body box turned 45°, so its
	# diagonal faces the camera rather than a face.
	var half: float = maxf(ArenaFigureMesh.BODY_SIZE.x, ArenaFigureMesh.BODY_SIZE.z) \
			* girth * sqrt(2.0) * 0.5
	return AABB(foot - Vector3(half, 0.0, half),
			Vector3(half * 2.0, height, half * 2.0))


func _assert_bounds_hold(grown: AABB, seed_box: AABB, girth: float, height: float,
		what: String) -> void:
	for dx: float in [0.0, 1.0]:
		for dy: float in [0.0, 1.0]:
			for dz: float in [0.0, 1.0]:
				var foot: Vector3 = seed_box.position + seed_box.size * Vector3(dx, dy, dz)
				assert_true(grown.encloses(_worst_case_figure(foot, girth, height)),
						"%s at %v should sit inside the declared bounds" % [what, foot])


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
	var arrays: Array = ArenaFigureMesh.crowd_body_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
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

func _figure_points(part_filter: float) -> PackedVector3Array:
	var arrays: Array = ArenaFigureMesh.crowd_body_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var out := PackedVector3Array()
	for i: int in verts.size():
		if part_filter < 0.0 or uvs[i].x == part_filter:
			out.append(verts[i])
	return out


func test_the_crowd_body_stops_below_its_head() -> void:
	assert_lt(ArenaFigureMesh.crowd_body_mesh().get_aabb().end.y,
			ArenaFigureMesh.crowd_head_mesh().get_aabb().position.y,
			"the body should stop below the head")


func test_knees_overhang_the_tread_but_not_the_row_below() -> void:
	# Fans sit spectator_inset_from_riser behind the drop to the row below, whose
	# seat backs stand tread_depth - BACK_OFFSET in front of them. A knee short
	# of the edge reads as legs folded into the concrete; one past the seat back
	# is through it. Checked at both stature extremes and both yaw extremes.
	var spec: ArenaBowlSpec = _spec()
	var edge: float = spec.spectator_inset_from_riser
	var row_below_back: float = spec.tread_depth - ArenaSeating.BACK_OFFSET \
			- ArenaSeating.BACK_THICKNESS * 0.5
	var legs: PackedVector3Array = _figure_points(ArenaFigureMesh.PART_LEG)
	for stature: float in [ArenaFigureMesh.SEATED_STATURE_MIN, ArenaFigureMesh.SEATED_STATURE_MAX]:
		var scale: float = ArenaFigureMesh.seated_scale(stature)
		for yaw_deg: float in [-spec.spectator_yaw_jitter_deg, 0.0, spec.spectator_yaw_jitter_deg]:
			var turn := Basis(Vector3.UP, deg_to_rad(yaw_deg))
			var farthest: float = 0.0
			for v: Vector3 in legs:
				farthest = maxf(farthest, -(turn * v).z * scale)
				assert_lt(-(turn * v).z * scale, row_below_back,
						"a %.2f m fan's knee should stop short of the row below" % stature)
			assert_gt(farthest, edge,
					"a %.2f m fan's knees should reach past the tread's edge" % stature)


func test_neighbours_elbows_do_not_meet() -> void:
	var span: float = 0.0
	for v: Vector3 in _figure_points(-1.0):
		span = maxf(span, absf(v.x))
	assert_lt(span * 2.0 * ArenaFigureMesh.CROWD_SCALE_MAX, _spec().spectator_spacing,
			"the widest fan should fit inside their seat spacing")


func test_staff_bounds_hold_the_tallest_coach() -> void:
	# The standing figure is the tall one, so the box is sized off full stature
	# rather than the seated crowd's sitting height.
	var seed_box := AABB(Vector3(-14.1, 1.2, -5.6), Vector3(28.2, 0.06, 11.2))
	_assert_bounds_hold(_rinkside(_spec()).grow_staff_aabb(seed_box), seed_box,
			ArenaFigureMesh.girth_scale(ArenaFigureMesh.STANDING_STATURE_MAX),
			ArenaFigureMesh.STANDING_STATURE_MAX, "a coach")


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
	for v: Vector3 in _figure_points(ArenaFigureMesh.PART_BODY):
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

extends GutTest

# ArenaStands as an assembled bowl — what its collaborators produce together,
# which is the half none of them can be tested for alone: that every piece is
# present, in the right order, and that the crowd's cullable slices come out
# as slices.
#
# The geometry each collaborator computes is tested next to it under
# tests/unit/actors/; this file only holds the assembly.
#
# Row counts are kept small — the invariants don't depend on bowl size and the
# full 15+10 default builds a ~10k-instance crowd per test.


func _make_stands(lower: int, upper: int) -> ArenaStands:
	var stands: ArenaStands = ArenaStands.new()
	# Configure BEFORE entering the tree: _request_rebuild no-ops outside it,
	# so _ready() builds this geometry directly instead of the default bowl.
	stands.num_terraces = lower
	stands.upper_terraces = upper
	add_child_autofree(stands)
	return stands


func _child_names(stands: ArenaStands) -> PackedStringArray:
	var out := PackedStringArray()
	for child: Node in stands.get_children():
		out.append(child.name)
	return out


func _crowd_sections(stands: ArenaStands) -> Array[MultiMesh]:
	var sections: Array[MultiMesh] = []
	for child: Node in stands.get_children():
		if child.name.begins_with("SpectatorBodies"):
			sections.append((child as MultiMeshInstance3D).multimesh)
	return sections


# The live crowd after a rebuild inside the tree, found by its shared material:
# the old nodes are only queued for freeing, so they still hold the names and
# the new ones come out auto-named.
func _live_crowd(stands: ArenaStands) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for child: Node in stands.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi != null and not mmi.is_queued_for_deletion() \
				and mmi.multimesh.mesh.surface_get_material(0) == ArenaCrowd.shared_material():
			out.append(mmi)
	return out


func _crowd_count(stands: ArenaStands) -> int:
	var total: int = 0
	for mm: MultiMesh in _crowd_sections(stands):
		total += mm.instance_count
	return total


func test_rebuild_child_inventory() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	for expected: String in ["Terraces", "Shell", "SpectatorBodies*",
			"SpectatorHeads*", "Seats*", "CrowdFlashbulbs", "VomitoryTunnels",
			"BenchSeatHome", "BenchSeatAway", "PenaltySeatHome", "OfficialsTable",
			"StaffStanding", "StaffSeated", "StaffHeads", "RibbonBoard", "RafterBanners"]:
		assert_not_null(stands.find_child(expected, false, false),
				"rebuild should produce a %s child" % expected)


func test_the_build_order_is_the_child_order() -> void:
	# Every collaborator adds its own children at the moment _rebuild calls it,
	# so the call sequence IS this list. That makes the order load-bearing in a
	# way no single collaborator can see: grouping a stage's children under one
	# root node would be tidier and would silently re-layer the bowl.
	#
	# Written as the stage sequence rather than the literal names, so a change in
	# how many cull slices the crowd splits into does not fail it — only a change
	# in which stage runs when. The per-slice runs collapse to one entry each:
	# "Seats" is eight MultiMeshes, and "Crowd" is body/head PAIRS, one per
	# slice and detail tier, each pair's two instances added together.
	var stages: PackedStringArray = PackedStringArray()
	for child_name: String in _child_names(_make_stands(3, 2)):
		var stage: String = child_name
		if child_name.begins_with("Seats"):
			stage = "Seats"
		elif child_name.begins_with("SpectatorBodies") \
				or child_name.begins_with("SpectatorHeads"):
			stage = "Crowd"
		if stages.is_empty() or stages[stages.size() - 1] != stage:
			stages.append(stage)
	assert_eq(Array(stages), [
		"Terraces", "Shell",
		# Seats before spectators so the opaque occupants draw over their own
		# seat backs rather than the other way round.
		"Seats", "Crowd", "CrowdFlashbulbs",
		"VomitoryTunnels", "VomitoryLightSpill",
		"BenchSeatAway", "BenchBackAway", "BenchSeatHome", "BenchBackHome",
		"PenaltySeatAway", "PenaltyBackAway", "PenaltyDividerAway",
		"PenaltySeatHome", "PenaltyBackHome", "PenaltyDividerHome",
		"OfficialsTable", "OfficialsSeat",
		"StaffStanding", "StaffSeated", "StaffHeads",
		"RibbonStripViewport", "RibbonBoard",
		"BannerAtlasViewport", "RafterBanners", "RafterBannersBack",
		# Added by _ready after the rebuild, and deliberately outside it: the
		# house lights hold a tween and the scene's captured light energies, so a
		# rebuild mid-cue would drop both and leave the bowl dark. The probe
		# survives too, so the Reflections setting written onto it does.
		"ArenaHouseLights", "ArenaReflection",
	], "the rebuild's stage order moved")


func test_crowd_splits_into_multiple_cullable_sections() -> void:
	# The angular split exists so the renderer can frustum-cull off-screen
	# crowd; one whole-bowl MultiMesh would defeat that. Every section's AABB
	# must also be a strict slice of the union, not a copy of it.
	var stands: ArenaStands = _make_stands(3, 2)
	var sections: Array[MultiMesh] = _crowd_sections(stands)
	assert_gt(sections.size(), 1, "crowd should split into multiple sections")
	var union: AABB = _crowd_aabb(stands)
	var union_area: float = union.size.x * union.size.z
	for mm: MultiMesh in sections:
		var area: float = mm.custom_aabb.size.x * mm.custom_aabb.size.z
		assert_lt(area, union_area,
				"each section AABB should cover only a slice of the bowl")


func test_shell_mesh_has_geometry_without_upper_deck() -> void:
	# LOW density disables the deck; the shell wall must still enclose the bowl.
	var stands: ArenaStands = _make_stands(3, 0)
	var shell: MeshInstance3D = stands.find_child("Shell", false, false)
	assert_not_null(shell)
	var mesh: ArrayMesh = shell.mesh as ArrayMesh
	assert_gt(mesh.surface_get_array_len(0), 0, "shell wall should have triangles")


func test_upper_deck_adds_spectators() -> void:
	var without_deck: int = _crowd_count(_make_stands(3, 0))
	var with_deck: int = _crowd_count(_make_stands(3, 2))
	assert_gt(without_deck, 0, "lower bowl should seat spectators")
	assert_gt(with_deck, without_deck,
			"upper deck rows should add spectators beyond the lower bowl's")


func test_crowd_aabb_covers_upper_deck() -> void:
	# The custom AABB exists because Godot's auto-AABB mis-culls the crowd; if
	# the upper deck isn't folded into it, its whole sections vanish at some
	# camera angles. Instance transforms aren't readable under the headless
	# dummy renderer, so compare the AABBs analytically: adding deck rows must
	# grow the bounds both outward and upward. The deck's first row sits above
	# an upper_deck_rise balcony, so its top face must clear that rise too.
	var flat: AABB = _crowd_aabb(_make_stands(3, 0))
	var decked: AABB = _crowd_aabb(_make_stands(3, 2))
	assert_gt(decked.size.x, flat.size.x, "deck should widen the crowd AABB")
	assert_gt(decked.size.z, flat.size.z, "deck should deepen the crowd AABB")
	assert_gt(decked.end.y, flat.end.y + 1.0,
			"deck rows should raise the crowd AABB past the balcony rise")


# Union of the per-section custom AABBs — the whole crowd's bounds.
func _crowd_aabb(stands: ArenaStands) -> AABB:
	var union: AABB = AABB()
	var first: bool = true
	for mm: MultiMesh in _crowd_sections(stands):
		union = mm.custom_aabb if first else union.merge(mm.custom_aabb)
		first = false
	return union


# ── Crowd Density ────────────────────────────────────────────────────────────

func test_hiding_the_crowd_leaves_the_building() -> void:
	# Off empties the seats. Everything else — concrete, seats, benches, staff,
	# signage, house lights, reflection probe — must stay exactly as it was, and
	# the switch must not rebuild.
	var stands: ArenaStands = _make_stands(3, 2)
	var terraces: Node = stands.find_child("Terraces", false, false)
	stands.set_crowd_density(false, true)
	assert_same(stands.find_child("Terraces", false, false), terraces,
			"hiding the crowd must not rebuild the bowl")
	assert_true(stands.visible, "the stands themselves stay drawn")
	var hidden: int = 0
	for child: Node in stands.get_children():
		var crowd: bool = child.name.begins_with("Spectator") \
				or child.name == "CrowdFlashbulbs"
		if crowd:
			hidden += 1
			assert_false((child as Node3D).visible, "%s should be hidden" % child.name)
		elif child is Node3D:
			assert_true((child as Node3D).visible, "%s should stay drawn" % child.name)
	assert_gt(hidden, 1, "there should be crowd to hide")
	var bulbs: Node = stands.find_child("CrowdFlashbulbs", false, false)
	assert_eq(bulbs.process_mode, Node.PROCESS_MODE_DISABLED,
			"hidden flashbulbs should stop spawning")
	stands.set_crowd_density(true, true)
	for child: Node in stands.get_children():
		if child.name.begins_with("Spectator"):
			assert_true((child as Node3D).visible, "%s should come back" % child.name)


func test_a_build_with_the_crowd_hidden_stays_hidden() -> void:
	# Applied before the stands enter the tree (the scene's first apply_video),
	# the setting has to survive the first build and every rebuild after it.
	var stands: ArenaStands = ArenaStands.new()
	stands.num_terraces = 3
	stands.upper_terraces = 2
	stands.set_crowd_density(false, true)
	add_child_autofree(stands)
	stands.attendance = 0.9
	var crowd: Array[MultiMeshInstance3D] = _live_crowd(stands)
	assert_gt(crowd.size(), 1, "the rebuild should have built a crowd")
	for mmi: MultiMeshInstance3D in crowd:
		assert_false(mmi.visible, "the rebuilt crowd should stay hidden")


func test_low_detail_draws_every_fan_far_in_the_same_building() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	var high: int = _crowd_count(stands)
	var far_body: AABB = ArenaFigureMesh.far_body_mesh().get_aabb()
	var near_before: int = 0
	for mm: MultiMesh in _crowd_sections(stands):
		if mm.mesh.get_aabb() != far_body:
			near_before += 1
	assert_gt(near_before, 0, "high detail should give the front rows the full figure")
	stands.set_crowd_density(true, false)
	assert_eq(stands.num_terraces, 3, "the bowl keeps its rows")
	assert_eq(stands.upper_terraces, 2, "and its upper deck")
	var far_head: AABB = ArenaFigureMesh.far_head_mesh().get_aabb()
	var fans: int = 0
	for mmi: MultiMeshInstance3D in _live_crowd(stands):
		var box: AABB = mmi.multimesh.mesh.get_aabb()
		assert_true(box == far_body or box == far_head, "every fan should be the far figure")
		if box == far_body:
			fans += mmi.multimesh.instance_count
	assert_eq(fans, high, "the same fans, only drawn cheaper")


func test_a_seat_is_built_for_every_spectator_and_then_some() -> void:
	# Seats have no vacancy roll, so at sub-1.0 attendance the bowl must hold
	# strictly more furniture than people — that daylight is what stops the
	# stands reading as a painted surface.
	var stands: ArenaStands = _make_stands(3, 2)
	var seats: int = 0
	for child: Node in stands.get_children():
		if child.name.begins_with("Seats"):
			seats += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_gt(seats, _crowd_count(stands),
			"a bowl below full attendance should show empty seats")


func test_bench_seat_center_sits_on_the_bench_it_names() -> void:
	# The lobby backdrop seats roster dummies here, and it reads the value off a
	# node it did not build, so this has to work without a rebuild of its own.
	var stands: ArenaStands = ArenaStands.new()
	var home: Vector3 = stands.bench_seat_center(0)
	var away: Vector3 = stands.bench_seat_center(1)
	assert_gt(home.z, 0.0, "home (team 0) sits on the +Z half")
	assert_almost_eq(home.z, -away.z, 0.0001, "the two benches straddle centre ice")
	assert_gt(home.x, stands.rink_width / 2.0, "and both sit beyond the boards")
	stands.free()


# ── Seating sections ─────────────────────────────────────────────────────────

func _make_sectioned_stands(aisles: int, fill: float) -> ArenaStands:
	var stands: ArenaStands = ArenaStands.new()
	stands.num_aisles = aisles
	stands.attendance = fill
	stands.num_terraces = 3
	stands.upper_terraces = 2
	add_child_autofree(stands)
	return stands


func test_aisles_clear_spectators() -> void:
	# Aisle corridors are cleared seats; a sectioned bowl must hold fewer
	# spectators than the same bowl without aisles.
	var solid: int = _crowd_count(_make_sectioned_stands(0, 1.0))
	var sectioned: int = _crowd_count(_make_sectioned_stands(12, 1.0))
	assert_gt(solid, 0)
	assert_lt(sectioned, solid, "aisles should remove seats from the bowl")


func test_attendance_scatters_empty_seats() -> void:
	var packed: int = _crowd_count(_make_sectioned_stands(0, 1.0))
	var sparse: int = _crowd_count(_make_sectioned_stands(0, 0.5))
	assert_lt(sparse, packed, "sub-1.0 attendance should leave seats empty")
	assert_gt(sparse, 0, "half attendance should still seat a crowd")


func test_away_block_flags_upper_deck_only() -> void:
	# The visiting-fan block lives in the upper deck; a deck-less bowl has no
	# flagged seats, a decked one flags some (but not most) of the crowd.
	var flat: int = _away_flag_count(_make_sectioned_stands(12, 1.0), 3, 0)
	assert_eq(flat, 0, "no upper deck → no visiting block")
	var stands: ArenaStands = _make_sectioned_stands(12, 1.0)
	var flagged: int = _away_flag_count(stands, 3, 2)
	assert_gt(flagged, 0, "decked bowl should flag a visiting block")
	assert_lt(flagged, _crowd_count(stands) / 4,
			"the visiting block is one section, not a quarter of the bowl")


func _away_flag_count(stands: ArenaStands, lower: int, upper: int) -> int:
	if stands.num_terraces != lower:
		stands.num_terraces = lower
	if stands.upper_terraces != upper:
		stands.upper_terraces = upper
	var layout: Dictionary = stands._get_or_build_layout()
	var count: int = 0
	for slice_flags: PackedByteArray in (layout.away_flags as Array[PackedByteArray]):
		for flag: int in slice_flags:
			count += flag
	return count


# ── Rinkside wells ───────────────────────────────────────────────────────────

func test_terrace_mesh_is_flat_through_the_bench_cutout() -> void:
	# ArenaBowlRake decides that the cleared rows are one flat well; this is the
	# check that the emitted concrete follows it. Row 1's tread band inside the
	# cutout must carry no geometry at the height it would have stepped to —
	# that leftover step is what a coach stood on.
	var stands: ArenaStands = _make_stands(3, 2)
	var terraces: MeshInstance3D = stands.find_child("Terraces", false, false)
	var verts: PackedVector3Array = (terraces.mesh as ArrayMesh) \
			.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var stepped: float = stands.stands_base_y + stands.riser_height
	var half_width: float = stands.rink_width / 2.0
	var inside: int = 0
	var outside: int = 0
	for v: Vector3 in verts:
		# Straight bench side only, and clear of the cutout's ends so the side
		# walls (which legitimately span both heights) stay out of it.
		var beyond: float = v.x - half_width
		if v.x < 0.0 or beyond < stands.tread_depth or beyond > stands.tread_depth * 2.0:
			continue
		if absf(v.z) < ArenaRinksideLayout.BENCH_HALF_LEN:
			inside += 1
			assert_almost_eq(v.y, stands.stands_base_y, 0.0001,
					"row 1 inside the bench cutout should be at the well floor")
		elif absf(v.z) > ArenaRinksideLayout.BENCH_CENTER_Z \
				+ ArenaRinksideLayout.BENCH_HALF_LEN + 2.0 \
				and absf(v.z) < 18.0 and is_equal_approx(v.y, stepped):
			outside += 1
	assert_gt(inside, 0, "the cutout's tread band should exist in the mesh")
	assert_gt(outside, 0, "the same band outside the cutout should still step up")


func test_hiding_ads_hides_the_ribbon_and_stops_its_scroll() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	var ribbon := stands.find_child("RibbonBoard", false, false) as MeshInstance3D
	stands.set_ads_shown(false)
	assert_same(stands.find_child("RibbonBoard", false, false), ribbon,
			"the switch must not rebuild the bowl")
	assert_false(ribbon.visible)
	assert_false(stands.is_processing(), "a hidden board has nothing to scroll")
	stands.set_ads_shown(true)
	assert_true(ribbon.visible)
	assert_true(stands.is_processing())


func test_a_build_with_ads_off_hides_the_ribbon() -> void:
	var stands: ArenaStands = ArenaStands.new()
	stands.num_terraces = 3
	stands.upper_terraces = 2
	stands.set_ads_shown(false)
	add_child_autofree(stands)
	var ribbon := stands.find_child("RibbonBoard", false, false) as MeshInstance3D
	assert_not_null(ribbon, "the board is still built, only hidden")
	assert_false(ribbon.visible)
	assert_false(stands.is_processing())


func _shown_excitement() -> float:
	return float(ArenaCrowd.shared_material().get_shader_parameter("excitement"))


func _replay_frame(stands: ArenaStands, phase: int) -> void:
	stands._on_replay_frame({"phase": phase}, -1)


# The live goal's burst is still running when the replay takes over; the play
# the replay re-runs happened before anyone cheered.
func test_a_replay_before_its_goal_shows_the_crowd_idle() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	stands.excite(1.0)
	await wait_seconds(0.3)
	assert_gt(_shown_excitement(), 0.9, "the live goal brings the bowl up")
	_replay_frame(stands, GamePhase.Phase.PLAYING)
	assert_eq(_shown_excitement(), 0.0)


func test_a_replay_brings_the_crowd_up_on_its_goal_frame() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	_replay_frame(stands, GamePhase.Phase.PLAYING)
	_replay_frame(stands, GamePhase.Phase.GOAL_CELEBRATION)
	await wait_seconds(0.3)
	assert_gt(_shown_excitement(), 0.9)


# A highlight reel runs clip after clip without stopping between them.
func test_the_next_clip_of_a_reel_starts_idle_again() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	_replay_frame(stands, GamePhase.Phase.PLAYING)
	_replay_frame(stands, GamePhase.Phase.GOAL_CELEBRATION)
	await wait_seconds(0.3)
	_replay_frame(stands, GamePhase.Phase.PLAYING)
	assert_eq(_shown_excitement(), 0.0)


func test_a_replayed_hit_rumbles_the_crowd() -> void:
	var stands: ArenaStands = _make_stands(3, 2)
	_replay_frame(stands, GamePhase.Phase.PLAYING)
	GameManager.replay_body_check.emit(1000.0)
	await wait_seconds(0.3)
	assert_gt(_shown_excitement(), 0.0)

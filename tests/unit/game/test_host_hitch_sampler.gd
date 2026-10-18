extends GutTest

# HostHitchSampler splits a stalled host frame into where its time went. The
# split is only honest if its brackets really are first and last in both the
# physics and the process order, and if the section attribution counts each
# microsecond once.

const _S := HostCostProbe.Section


func _sections() -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(HostCostProbe.SECTION_COUNT)
	return a


func test_the_buckets_partition_the_frame() -> void:
	var e: Dictionary = HostHitchSampler.build_entry(
			200_000, 150_000, 8, 120_000, 10_000, _sections(), 0, 0, 0, 0)
	assert_eq(e["frame_ms"], 200.0)
	assert_eq(e["physics_ms"], 150.0)
	assert_eq(e["process_ms"], 10.0)
	assert_eq(e["other_ms"], 40.0, "the rest is outside every callback")
	assert_eq(e["ticks"], 8)
	assert_eq(e["worst_tick_ms"], 120.0)


func test_other_never_goes_negative() -> void:
	var e: Dictionary = HostHitchSampler.build_entry(
			70_000, 60_000, 4, 20_000, 20_000, _sections(), 0, 0, 0, 0)
	assert_eq(e["other_ms"], 0.0)


func test_top_sections_rank_main_thread_time_and_skip_nested() -> void:
	var s := _sections()
	s[_S.SKATER_PHYS] = 90_000.0
	s[_S.DISPATCH] = 30_000.0
	s[_S.AI_APPLY] = 29_000.0     # nested inside DISPATCH
	s[_S.WORKER] = 500_000.0      # off-thread
	s[_S.GM_TAIL] = 5_000.0
	s[_S.PUCK_PHYS] = 1_000.0
	var e: Dictionary = HostHitchSampler.build_entry(
			200_000, 140_000, 8, 100_000, 0, s, 0, 0, 0, 0)
	var top: Dictionary = e["top_sections"]
	assert_eq(top.keys(), ["skater bodies", "dispatch (total)", "game tail"])
	assert_eq(top["skater bodies"], 90.0)
	assert_eq(e["unprobed_physics_ms"], 14.0,
			"physics less every top-level section, nested and worker time not subtracted")


func test_engine_counters_ride_along() -> void:
	var e: Dictionary = HostHitchSampler.build_entry(
			80_000, 10_000, 1, 10_000, 1_000, _sections(), 3, 250, 2048 * 1024, 900)
	assert_eq(e["pipeline_compiles"], 3)
	assert_eq(e["objects_delta"], 250)
	assert_eq(e["memory_delta_kb"], 2048)
	assert_eq(e["draw_calls"], 900)


func test_frame_sections_sum_over_ticks_and_drain() -> void:
	var was_enabled: bool = HostCostProbe.enabled
	HostCostProbe.enabled = true
	HostCostProbe.reset()
	HostCostProbe.record(_S.SKATER_PHYS, 100)
	HostCostProbe.end_tick()
	HostCostProbe.record(_S.SKATER_PHYS, 250)
	var out := _sections()
	HostCostProbe.take_frame_sections(out)
	assert_eq(out[_S.SKATER_PHYS], 350.0, "both ticks of the frame, across end_tick")
	HostCostProbe.take_frame_sections(out)
	assert_eq(out[_S.SKATER_PHYS], 0.0, "drained for the next frame")
	HostCostProbe.reset()
	HostCostProbe.enabled = was_enabled


# The brackets only measure the frame if nothing sorts outside them.
func test_no_node_sorts_outside_the_brackets() -> void:
	var re := RegEx.create_from_string("process(?:_physics)?_priority\\s*=\\s*(-?\\d+)")
	var offenders: Array[String] = []
	for path: String in _gd_files("res://Scripts"):
		if path.ends_with("host_hitch_sampler.gd"):
			continue
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
			var p: int = int(m.get_string(1))
			if p <= HostHitchSampler.HEAD_PRIORITY or p >= HostHitchSampler.TAIL_PRIORITY:
				offenders.append("%s: %d" % [path, p])
	assert_eq(offenders.size(), 0, "outside the sampler's brackets: %s" % [offenders])


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out

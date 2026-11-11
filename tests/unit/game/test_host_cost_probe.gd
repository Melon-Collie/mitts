extends GutTest

# What the probe's totals add up. A section is either a top-level main-thread
# cost, nested inside one, or the worker's; a total that counts a section in the
# wrong class reports time the main thread never spent, or spent twice.

const _S := HostCostProbe.Section
const NESTED: Array[int] = [_S.AI_APPLY, _S.SKATER_STEP, _S.AI_KICK]
const WORKER_SIDE: Array[int] = [_S.BRAINS, _S.WORKER]

var _was_enabled: bool = false


func before_each() -> void:
	_was_enabled = HostCostProbe.enabled
	HostCostProbe.enabled = true
	HostCostProbe.reset()


func after_each() -> void:
	HostCostProbe.reset()
	HostCostProbe.enabled = _was_enabled


# One window in which section s costs (s + 1) × 10 µs every tick.
func _fill_window() -> void:
	for _t: int in HostCostProbe.WINDOW_TICKS:
		for s: int in HostCostProbe.SECTION_COUNT:
			HostCostProbe.record(s, (s + 1) * 10)
		HostCostProbe.end_tick()


func test_every_section_has_a_name_and_a_class() -> void:
	assert_eq(_S.size(), HostCostProbe.SECTION_COUNT)
	assert_eq(HostCostProbe.SECTION_NAMES.size(), HostCostProbe.SECTION_COUNT)
	for s: int in HostCostProbe.SECTION_COUNT:
		var classes: int = int(s in HostCostProbe.MAIN_THREAD_SECTIONS) \
				+ int(s in NESTED) + int(s in WORKER_SIDE)
		assert_eq(classes, 1, "%s is in exactly one class" % HostCostProbe.SECTION_NAMES[s])


func test_the_tick_total_is_the_top_level_main_thread_sections() -> void:
	_fill_window()
	var expected: float = 0.0
	for s: int in HostCostProbe.MAIN_THREAD_SECTIONS:
		expected += float((s + 1) * 10)
	assert_almost_eq(HostCostProbe.tick_total_mean_us(), expected, 1e-6)


func test_the_ai_block_charges_the_main_thread_only_for_its_own_work() -> void:
	_fill_window()
	var snapshot: float = float((_S.SNAPSHOT + 1) * 10)
	var dispatch: float = float((_S.DISPATCH + 1) * 10)
	assert_almost_eq(HostCostProbe.main_thread_mean_us(), snapshot + dispatch, 1e-6,
			"the brains and the worker run off the main thread")
	assert_almost_eq(HostCostProbe.main_thread_max_us(), maxf(snapshot, dispatch), 1e-6)


func test_the_ai_itself_is_the_block_less_the_skater_step_inside_it() -> void:
	for _t: int in HostCostProbe.WINDOW_TICKS:
		HostCostProbe.record(_S.SNAPSHOT, 200)
		HostCostProbe.record(_S.DISPATCH, 900)
		HostCostProbe.record(_S.SKATER_STEP, 700)
		HostCostProbe.record(_S.BRAINS, 50)
		HostCostProbe.end_tick()
	assert_almost_eq(HostCostProbe.ai_only_mean_us(), 400.0, 1e-6)

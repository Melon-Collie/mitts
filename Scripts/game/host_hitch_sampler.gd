class_name HostHitchSampler
extends Node

# Splits every host frame by where its wall time went, and reports each frame
# past the stall band with that split (NetworkTelemetry.record_hitch). The
# tick-gap stall metric says THAT the host stalled; this says in which part of
# the frame.
#
# A frame here runs from one process-start to the next: the previous frame's
# _process callbacks, then everything outside any callback — render, the
# multiplayer poll, engine work, the OS — then this frame's physics ticks. Each
# callback phase is bracketed by this node (first in both orders) and its
# _Tail child (last in both). test_host_hitch_sampler.gd holds that no other
# node's priority falls outside the brackets.
#
# Host-only and per match: it measures while HostCostProbe.enabled. A frame
# under the band costs a handful of clock and monitor reads and no allocation.

const HEAD_PRIORITY: int = -100000
const TAIL_PRIORITY: int = 100000
const _PIPELINE_MONITORS: Array[int] = [
	Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
	Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
]
const _TOP_SECTIONS: int = 3


class _Tail extends Node:
	var sampler: HostHitchSampler = null

	func _ready() -> void:
		process_priority = TAIL_PRIORITY
		process_physics_priority = TAIL_PRIORITY

	func _physics_process(_delta: float) -> void:
		sampler._close_tick()

	func _process(_delta: float) -> void:
		sampler._close_process()


var _tick_start_us: int = 0
var _physics_us: int = 0
var _ticks: int = 0
var _worst_tick_us: int = 0
var _process_start_us: int = 0
var _process_us: int = 0
# Cumulative engine counters at the last frame boundary; a hitch reports how far
# each moved across its frame.
var _pipelines: int = 0
var _objects: int = 0
var _memory: int = 0
var _sections := PackedFloat64Array()


func _ready() -> void:
	process_priority = HEAD_PRIORITY
	process_physics_priority = HEAD_PRIORITY
	_sections.resize(HostCostProbe.SECTION_COUNT)
	var tail := _Tail.new()
	tail.sampler = self
	add_child(tail)


func _physics_process(_delta: float) -> void:
	if HostCostProbe.enabled:
		_tick_start_us = Time.get_ticks_usec()


func _close_tick() -> void:
	if _tick_start_us == 0:
		return
	var us: int = Time.get_ticks_usec() - _tick_start_us
	_tick_start_us = 0
	_physics_us += us
	_ticks += 1
	_worst_tick_us = maxi(_worst_tick_us, us)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if not HostCostProbe.enabled:
		_process_start_us = 0
		return
	var pipelines: int = _pipeline_total()
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	HostCostProbe.take_frame_sections(_sections)
	var frame_us: int = now - _process_start_us
	if _process_start_us != 0 and frame_us >= int(NetworkTelemetry.STALL_BAD_MS * 1000.0):
		NetworkTelemetry.record_hitch(build_entry(frame_us, _physics_us, _ticks,
				_worst_tick_us, _process_us, _sections, pipelines - _pipelines,
				objects - _objects, memory - _memory,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))))
	_physics_us = 0
	_ticks = 0
	_worst_tick_us = 0
	_pipelines = pipelines
	_objects = objects
	_memory = memory
	_process_start_us = now


func _close_process() -> void:
	if _process_start_us != 0:
		_process_us = Time.get_ticks_usec() - _process_start_us


func _pipeline_total() -> int:
	var total: int = 0
	for m: int in _PIPELINE_MONITORS:
		total += int(Performance.get_monitor(m))
	return total


# One hitch as the session row carries it, in ms rounded to 0.1. `other_ms` is
# what the frame spent outside every callback; `unprobed_physics_ms` the part of
# the physics ticks no HostCostProbe section accounts for (the remote clients'
# input steps, engine transform propagation, unprobed nodes).
static func build_entry(frame_us: int, physics_us: int, ticks: int, worst_tick_us: int,
		process_us: int, sections: PackedFloat64Array, pipeline_compiles: int,
		objects_delta: int, memory_delta: int, draw_calls: int) -> Dictionary:
	var probed_us: float = 0.0
	for s: int in HostCostProbe.MAIN_THREAD_SECTIONS:
		probed_us += sections[s]
	var top: Dictionary = {}
	var taken: Array[int] = []
	for _i: int in _TOP_SECTIONS:
		var best: int = -1
		for s: int in HostCostProbe.MAIN_THREAD_SECTIONS:
			if s in taken or sections[s] <= 0.0:
				continue
			if best == -1 or sections[s] > sections[best]:
				best = s
		if best == -1:
			break
		taken.append(best)
		top[HostCostProbe.SECTION_NAMES[best].strip_edges()] = _ms(sections[best])
	return {
		"frame_ms": _ms(frame_us),
		"physics_ms": _ms(physics_us),
		"ticks": ticks,
		"worst_tick_ms": _ms(worst_tick_us),
		"process_ms": _ms(process_us),
		"other_ms": _ms(maxi(frame_us - physics_us - process_us, 0)),
		"top_sections": top,
		"unprobed_physics_ms": _ms(maxf(float(physics_us) - probed_us, 0.0)),
		"pipeline_compiles": maxi(pipeline_compiles, 0),
		"objects_delta": objects_delta,
		"memory_delta_kb": roundi(memory_delta / 1024.0),
		"draw_calls": draw_calls,
	}


static func _ms(us: float) -> float:
	return snappedf(us / 1000.0, 0.1)

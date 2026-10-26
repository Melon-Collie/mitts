class_name SkaterTickProxy
extends Node

# A parallel skater's main-thread half (Skater.parallel_render). The skater's
# own thread group runs its _process on a worker, and would take its tick there
# too; this node sits beside it in the tree, so it ticks in the slot the skater
# did, on the main thread, where the tick may write other skaters. Its _process
# runs before every parallel skater's and readies what they share.

var _skater: Skater


func _init(skater: Skater) -> void:
	_skater = skater
	name = "%sTick" % skater.name
	process_physics_priority = skater.process_physics_priority
	skater.tree_exiting.connect(_on_skater_leaving)


func _physics_process(delta: float) -> void:
	if _skater.is_physics_processing():
		_skater.physics_tick(delta)


func _process(_delta: float) -> void:
	SkaterCameraCull.prepare(_skater)


# Stops at once: a queued free lands after this frame's process, and the skater
# may be freed before then.
func _on_skater_leaving() -> void:
	set_process(false)
	set_physics_process(false)
	queue_free()

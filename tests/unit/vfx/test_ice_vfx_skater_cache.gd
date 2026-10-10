extends GutTest

# IceRingField and IceScratchMap each cache the "skaters" group and revalidate
# it only when the count moves. A same-frame despawn+respawn (the replay viewer
# rebuilding its skaters on a rewind) keeps the count, so the cache holds a
# freed entry that the validation pass has to step over rather than trip on.


func _swap_one_skater(stand_in: Node) -> Node:
	var old_node: Node = Node.new()
	old_node.add_to_group("skaters")
	add_child(old_node)
	stand_in.call("_live_skaters")
	old_node.free()
	var new_node: Node = Node.new()
	new_node.add_to_group("skaters")
	add_child_autofree(new_node)
	return new_node


func _assert_cache_follows_the_swap(stand_in: Node) -> void:
	var new_node: Node = _swap_one_skater(stand_in)
	var live: Array = stand_in.call("_live_skaters")
	assert_eq(live.size(), 1)
	assert_true(live.has(new_node), "the respawned skater replaces the freed one")


func test_ice_ring_field_survives_a_same_frame_respawn() -> void:
	var field: IceRingField = IceRingField.new()
	add_child_autofree(field)
	_assert_cache_follows_the_swap(field)


func test_ice_scratch_map_survives_a_same_frame_respawn() -> void:
	var scratch: IceScratchMap = IceScratchMap.new()
	add_child_autofree(scratch)
	_assert_cache_follows_the_swap(scratch)

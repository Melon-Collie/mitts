extends GutTest

# A same-frame despawn+respawn (the replay viewer rebuilding its skaters on a
# rewind) keeps the group count, so the cache holds a freed entry that the
# validation pass has to step over rather than trip on.


func _add_skater() -> Node:
	var node: Node = Node.new()
	node.add_to_group("skaters")
	add_child(node)
	return node


func test_follows_a_same_frame_respawn() -> void:
	var cache: SkaterGroupCache = SkaterGroupCache.new()
	var old_node: Node = _add_skater()
	cache.live(get_tree())
	old_node.free()
	var new_node: Node = _add_skater()
	var live: Array = cache.live(get_tree())
	assert_eq(live.size(), 1)
	assert_true(live.has(new_node), "the respawned skater replaces the freed one")
	new_node.free()


func test_follows_a_roster_change() -> void:
	var cache: SkaterGroupCache = SkaterGroupCache.new()
	var first: Node = _add_skater()
	assert_eq(cache.live(get_tree()).size(), 1)
	var second: Node = _add_skater()
	assert_eq(cache.live(get_tree()).size(), 2)
	first.free()
	second.free()
	assert_eq(cache.live(get_tree()).size(), 0)

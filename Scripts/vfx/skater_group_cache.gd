class_name SkaterGroupCache
extends RefCounted

# The live "skaters" group, rebuilt only when the roster actually changes —
# get_nodes_in_group() allocates a fresh Array on every call, and the ice VFX
# read it every frame.
#
# Deliberately the GROUP and not PlayerRegistry.skaters(): the standalone replay
# viewer spawns its skaters straight through ActorSpawner, outside the registry,
# and (unlike the goal-replay cinematic) never sets replay mode — so a
# registry-backed list would leave replay playback with no rings or scratches.
# Equal counts can still hide a same-frame despawn+spawn (a replay rewind), which
# shows up as a freed entry, so the cache is validated as well as counted.

var _cache: Array = []


func live(tree: SceneTree) -> Array:
	if tree.get_node_count_in_group("skaters") != _cache.size():
		_cache = tree.get_nodes_in_group("skaters")
		return _cache
	# Variant, not Node: a typed loop variable errors on assigning the freed
	# entry before is_instance_valid can see it.
	for n: Variant in _cache:
		if not is_instance_valid(n):
			_cache = tree.get_nodes_in_group("skaters")
			break
	return _cache

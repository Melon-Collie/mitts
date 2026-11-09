extends RefCounted

# The goalie's open set as goal intervals across the mouth, found from a sweep of
# aims by bisecting each change between a goal and anything else. Shared by the
# stager and the resolution instrument. No class_name (test infra stays out of
# the global namespace).

# Bisections per edge: a 7.4 cm aim step down to under 5 mm.
const REFINE_STEPS: int = 4


# Aim `i` of `n` post to post, in metres across the net's frame.
static func aim_x(i: int, n: int) -> float:
	var reach: float = AIShotOdds.post_reach()
	return lerpf(-reach, reach, float(i) / float(n - 1))


# The goal intervals of `sweep` (one outcome character per aim post to post),
# each edge bisected `steps` times by `shoot` (aim x → outcome character). A
# run that reaches a post ends at the post. Flat [start, end, start, end, …].
static func refine(sweep: String, shoot: Callable, steps: int = REFINE_STEPS) -> PackedFloat32Array:
	var n: int = sweep.length()
	var reach: float = AIShotOdds.post_reach()
	var out := PackedFloat32Array()
	var i: int = 0
	while i < n:
		if sweep[i] != "G":
			i += 1
			continue
		var j: int = i
		while j + 1 < n and sweep[j + 1] == "G":
			j += 1
		var lo: float = -reach if i == 0 else _edge(aim_x(i - 1, n), aim_x(i, n), false, shoot, steps)
		var hi: float = reach if j == n - 1 else _edge(aim_x(j, n), aim_x(j + 1, n), true, shoot, steps)
		out.append(lo)
		out.append(hi)
		i = j + 1
	return out


# Where between `a` and `b` the outcome stops (or starts) being a goal: `a_goal`
# says which side scores.
static func _edge(a: float, b: float, a_goal: bool, shoot: Callable, steps: int) -> float:
	var lo: float = a
	var hi: float = b
	for _k: int in steps:
		var m: float = 0.5 * (lo + hi)
		if (String(shoot.call(m)) == "G") == a_goal:
			lo = m
		else:
			hi = m
	return 0.5 * (lo + hi)


# The inverse of AIShotOdds.decode_intervals.
static func encode(edges: PackedFloat32Array) -> String:
	var parts: PackedStringArray = []
	for k: int in range(0, edges.size(), 2):
		parts.append("%d:%d" % [roundi(edges[k] * 1000.0), roundi(edges[k + 1] * 1000.0)])
	return ";".join(parts)

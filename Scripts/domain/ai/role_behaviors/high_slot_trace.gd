class_name AIHighSlotTrace

# One HIGH_SLOT positioning read, recorded for an instrument
# (tests/instruments/ai/test_ozone_possession_5v5.gd, MITTS_OZ_TRACE_HIGH=1):
# whether he may leave the top of the slot (AIRoleHighSlot._help_free), every
# grid spot's depth, weak-signed lateral offset and score (-INF where it was
# filtered out), and which one won (-1: the far post or the incumbent).
# AIRoleHighSlot fills it only for `peer`, and only while an instrument holds one.

var peer: int = -1
var deep_ok: bool = false
var depth: Array[float] = []
var weak_u: Array[float] = []
var score: Array[float] = []
var chosen: int = -1


func clear() -> void:
	deep_ok = false
	depth.clear()
	weak_u.clear()
	score.clear()
	chosen = -1


func record(depth_m: float, u_m: float, score_v: float) -> void:
	depth.append(depth_m)
	weak_u.append(u_m)
	score.append(score_v)

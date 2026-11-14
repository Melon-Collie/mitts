class_name AIFinisherTrace

# One FINISHER / NET_FRONT positioning read, recorded for an instrument
# (tests/instruments/ai/test_ozone_possession_5v5.gd, MITTS_OZ_TRACE_FRONT=1):
# every candidate station, what kind it is, its terms and its score (-INF where
# it was filtered out), and which one won. AIRoleFinisher fills it only for
# `peer`, and only while an instrument holds one.

enum Kind { CENTER, SELF, BACKDOOR, BUMPER, WEAK_DOT, HIGH_SLOT, TIP, NET_FRONT, INCUMBENT }

var peer: int = -1
var kind: Array[int] = []
var pos: Array[Vector3] = []
var feed: Array[float] = []
var tip: Array[float] = []
var front: Array[float] = []
var reach: Array[float] = []
var score: Array[float] = []
var chosen: int = -1


func clear() -> void:
	kind.clear()
	pos.clear()
	feed.clear()
	tip.clear()
	front.clear()
	reach.clear()
	score.clear()
	chosen = -1


func record(k: int, at: Vector3, feed_v: float, tip_v: float, front_v: float,
		reach_v: float, score_v: float) -> void:
	kind.append(k)
	pos.append(at)
	feed.append(feed_v)
	tip.append(tip_v)
	front.append(front_v)
	reach.append(reach_v)
	score.append(score_v)

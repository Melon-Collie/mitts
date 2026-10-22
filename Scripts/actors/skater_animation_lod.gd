class_name SkaterAnimationLod
extends RefCounted

# How often a skater's mesh is re-posed: every frame up close, less often the
# further it is from the camera, by the player's Animation Detail setting.
#
# A frame that is not due is treated exactly like an off-camera frame — the
# gait still computes (a held pose's crouch moves the gameplay frame), and only
# the mesh work waits: leg and trunk bones, the contact seat, the head, the off
# hand, the arm and stick rebuild (the blade, which hangs from a marker the tick
# moves, is held where it was drawn). The body itself moves every frame regardless
# (physics interpolation), so a distant skater keeps gliding smoothly and only
# his limbs step at the lower rate.

const DETAIL_LOW: int = 0
const DETAIL_BALANCED: int = 1
const DETAIL_FULL: int = 2

# The player's Video setting, written by PlayerPrefs.apply_video. Full until
# then, so tests and tools that never apply prefs pose every frame.
static var detail: int = DETAIL_FULL

# Camera distance (m) at which each tier begins. The game camera sits 10-32 m
# above the ice, so NEAR is a zoomed-in frame and FAR the full-ice one.
const NEAR_M: float = 18.0
const FAR_M: float = 30.0

# Seconds between mesh passes, [near, mid, far] per detail level from Low; 0 is
# every frame. Balanced only thins what a 60 Hz display would never show.
const _INTERVALS: PackedFloat32Array = [
	1.0 / 60.0, 1.0 / 30.0, 1.0 / 20.0,
	1.0 / 120.0, 1.0 / 60.0, 1.0 / 40.0,
	0.0, 0.0, 0.0,
]

# A pass is due this close to its interval. Frame times never sum to it
# exactly (and the table is float32), so without slack a 1/60 s interval at a
# steady 60 fps would land a hair short and skip every other frame.
const _SLACK_S: float = 0.001

# Render time since the last pass that was due, including this frame's.
var span: float = 0.0
var _since: float = 0.0


# `phase` (0..1) staggers skaters so their passes spread across frames rather
# than landing on the same one.
func _init(phase: float = 0.0) -> void:
	_since = phase * _INTERVALS[2]


# Whether this frame's mesh pass is due. `full` skips the throttle (the local
# player); so does a negative distance (no camera to measure from).
func due(delta: float, distance_m: float, full: bool) -> bool:
	_since += delta
	span += delta
	var interval: float = 0.0 if full or distance_m < 0.0 else interval_for(detail, distance_m)
	if _since + _SLACK_S < interval:
		return false
	_since = minf(_since - interval, interval)
	return true


# Call once the due pass has consumed `span`, and whenever the skater leaves the
# camera — an off-camera skater is re-posed on his first frame back.
func consumed() -> void:
	span = 0.0


static func interval_for(level: int, distance_m: float) -> float:
	var tier: int = 0 if distance_m < NEAR_M else (1 if distance_m < FAR_M else 2)
	return _INTERVALS[clampi(level, DETAIL_LOW, DETAIL_FULL) * 3 + tier]

extends RefCounted

# Candidate gameplay-camera placements for the shoulder-camera experiment, and
# the one function that places a camera from them, so the stills and the
# projection table in camera_rig_runner.gd always describe the same rigs.
#
# Every rig is fixed in yaw, looking up-ice: it aims at a point `ahead` m up-ice
# of the subject, from `dist` m away along a ray pitched `pitch` degrees below
# horizontal, the whole rig slid `side` m to the subject's right. `fov` is
# vertical, as Camera3D's is.
#
# The `now_*` rows are GameCamera's own framing at its default 75° tilt, which
# aims at the subject from height h (dist = h / sin 75°): at the minimum height a
# carry collapses to, and at a typical open-play height.
const RIGS: Array[Dictionary] = [
	{"name": "now_h10", "pitch": 75.0, "dist": 10.35, "ahead": 0.0, "side": 0.0, "fov": 50.0},
	{"name": "now_h18", "pitch": 75.0, "dist": 18.6, "ahead": 0.0, "side": 0.0, "fov": 50.0},
	{"name": "sh62", "pitch": 62.0, "dist": 11.0, "ahead": 1.5, "side": 0.0, "fov": 50.0},
	{"name": "sh55", "pitch": 55.0, "dist": 11.0, "ahead": 2.0, "side": 0.0, "fov": 50.0},
	{"name": "sh45", "pitch": 45.0, "dist": 10.0, "ahead": 2.5, "side": 0.0, "fov": 50.0},
	{"name": "sh45_side", "pitch": 45.0, "dist": 10.0, "ahead": 2.5, "side": 1.2, "fov": 50.0},
	{"name": "sh45_tele", "pitch": 45.0, "dist": 15.0, "ahead": 2.5, "side": 0.0, "fov": 36.0},
	{"name": "sh35", "pitch": 35.0, "dist": 10.0, "ahead": 3.5, "side": 0.0, "fov": 50.0},
]


static func is_current_framing(rig: Dictionary) -> bool:
	var rig_name: String = rig["name"]
	return rig_name.begins_with("now_")


static func transform_for(rig: Dictionary, subject: Vector3, up_ice: Vector3) -> Transform3D:
	var fwd: Vector3 = Vector3(up_ice.x, 0.0, up_ice.z).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var pitch: float = deg_to_rad(rig["pitch"])
	var dist: float = rig["dist"]
	var ahead: float = rig["ahead"]
	var side: float = rig["side"]
	var look: Vector3 = Vector3(subject.x, 0.0, subject.z) + fwd * ahead + right * side
	var eye: Vector3 = look - fwd * (cos(pitch) * dist) + Vector3.UP * (sin(pitch) * dist)
	return Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)

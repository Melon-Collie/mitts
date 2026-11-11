extends GutTest

# Flat pucks along the ice at the keeper in each stance, against his gear boxes
# alone (KeeperGear, SweptDiscOBB, GoalieSaveRules): for each line across the
# mouth, the box it meets first, the face it enters by, and where the rebound
# goes. Keeper space: he faces -z, the goal line is +z behind him.

const SHOOTER_Z: float = -3.2
const GOAL_LINE_Z: float = 1.83
const AIMS: int = 24
const SPEED: float = 20.0

const PART_NAMES: Array[String] = [
	"PAD_G", "PAD_B", "RISE_G", "RISE_B", "BOOT_G", "BOOT_B", "SKATE_G", "SKATE_B",
	"THIGH_G", "THIGH_B", "PANTS", "CHEST", "UA_G", "FA_G", "UA_B", "FA_B",
	"GLOVE", "BLOCKER", "MASK", "BLADE", "PADDLE", "SHAFT"]
const FACE_NAMES: Array[String] = ["-x", "+x", "-y", "+y", "-z", "+z"]


func test_flat_pucks_at_each_stance() -> void:
	var poses: Dictionary = {
		"ready": func(p: KeeperPose) -> void: KeeperPoses.ready(p),
		"low_ready": func(p: KeeperPose) -> void: KeeperPoses.low_ready(p),
		"butterfly": func(p: KeeperPose) -> void: KeeperPoses.butterfly(p),
	}
	var lines: PackedStringArray = []
	for stance: String in poses:
		var pose := KeeperPose.new()
		(poses[stance] as Callable).call(pose)
		var skel := KeeperSkeleton.new()
		skel.pose(pose)
		lines.append("== %s ==" % stance)
		lines.append("  boxes at the ice: " + _ice_boxes(skel))
		for i: int in AIMS:
			var aim_x: float = lerpf(-0.83, 0.83, float(i) / float(AIMS - 1))
			lines.append("  aim %5.2f  %s" % [aim_x, _first_contact(skel, aim_x)])
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _first_contact(skel: KeeperSkeleton, aim_x: float) -> String:
	var y: float = GameRules.PUCK_COLLISION_HALF_HEIGHT
	var from := Vector3(0.0, y, SHOOTER_Z)
	var to := Vector3(aim_x, y, GOAL_LINE_Z)
	var best_t: float = INF
	var best_part: int = -1
	var best := SweptDiscOBB.Result.new()
	var r := SweptDiscOBB.Result.new()
	for part: int in KeeperGear.PART_COUNT:
		if SweptDiscOBB.contact(from, to, GameRules.PUCK_COLLISION_RADIUS,
				KeeperGear.box(skel, part), KeeperGear.half_extents(part), r) and r.toi < best_t:
			best_t = r.toi
			best_part = part
			best.normal = r.normal
			best.point = r.point
	if best_part < 0:
		return "clean through"
	var xf: Transform3D = KeeperGear.box(skel, best_part)
	var local_n: Vector3 = xf.basis.inverse() * best.normal
	var axis: int = local_n.abs().max_axis_index()
	var face: String = FACE_NAMES[axis * 2 + (1 if local_n[axis] > 0.0 else 0)]
	var vel: Vector3 = (to - from).normalized() * SPEED
	var res := GoalieSaveRules.ContactResult.new()
	GoalieSaveRules.resolve_contact(vel, KeeperGear.save_part(best_part), best.normal, res,
			Vector3(0.0, 0.0, -1.0))
	var into_net: bool = res.velocity.z > 0.0
	return "%-8s face %s at (%.2f, %.3f, %.2f) normal (%.2f, %.2f, %.2f) out (%.1f, %.1f, %.1f)%s" % [
			PART_NAMES[best_part], face, best.point.x, best.point.y, best.point.z,
			best.normal.x, best.normal.y, best.normal.z,
			res.velocity.x, res.velocity.y, res.velocity.z, "  INTO THE NET" if into_net else ""]


# The lowest point of each box from the knee down.
func _ice_boxes(skel: KeeperSkeleton) -> String:
	var out: PackedStringArray = []
	for part: int in [KeeperGear.Part.PAD_G, KeeperGear.Part.PAD_B, KeeperGear.Part.BOOT_G,
			KeeperGear.Part.BOOT_B, KeeperGear.Part.SKATE_G, KeeperGear.Part.SKATE_B,
			KeeperGear.Part.BLADE]:
		var xf: Transform3D = KeeperGear.box(skel, part)
		var he: Vector3 = KeeperGear.half_extents(part)
		var lo: float = INF
		for c: int in 8:
			lo = minf(lo, (xf * Vector3(he.x * (1 if c & 1 else -1), he.y * (1 if c & 2 else -1),
					he.z * (1 if c & 4 else -1))).y)
		out.append("%s %.3f" % [PART_NAMES[part], lo])
	return ", ".join(out)

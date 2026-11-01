extends GutTest

# Phase 1 of docs/arm-anatomy-plan.md: where on the ice a body can hold a carried
# blade (ArmAnatomySearch), against where today's gameplay puts it and how
# today's drawn arms hold it. Per build and trunk state, the cursor is held on a
# polar grid round the carrier through the real controller, and each cell reads:
#
#   today   the arms the rig draws, re-solved with only their own freedoms (the
#           elbow round its circle, the fist round the shaft): can a body hold
#           the hands where gameplay put them, and if not, what stops it;
#   any     the whole search at the blade gameplay landed: does any pose hold it;
#   target  where gameplay did not reach the cursor, the search there.
#
# Prints a map per build and state and writes it all to .preview/arm_anatomy.md.
# An instrument: it asserts nothing (tests/CLAUDE.md).

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const SETTLE_TICKS: int = 120
# Off the facing, + round the forehand (degrees), and out from the body (m).
const ANGLES: Array[float] = [-150.0, -120.0, -90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0,
		120.0, 150.0]
const RADII: Array[float] = [0.6, 0.9, 1.2, 1.5, 1.8]
# Gameplay reached the cursor when it landed the carried puck this near it (m).
const REACHED_M: float = 0.1
const SKATE_SPEED_STICK: float = 1.0
const OUT_PATH: String = "res://.preview/arm_anatomy.md"

const LETTERS := {
	ArmAnatomy.Limit.REACH: "R",
	ArmAnatomy.Limit.SHOULDER_ELEVATION: "E",
	ArmAnatomy.Limit.SHOULDER_INTERNAL: "I",
	ArmAnatomy.Limit.SHOULDER_EXTERNAL: "O",
	ArmAnatomy.Limit.ELBOW_FLEXION: "B",
	ArmAnatomy.Limit.PRONATION: "P",
	ArmAnatomy.Limit.SUPINATION: "S",
	ArmAnatomy.Limit.WRIST_FLEXION: "F",
	ArmAnatomy.Limit.WRIST_EXTENSION: "X",
	ArmAnatomy.Limit.WRIST_RADIAL: "D",
	ArmAnatomy.Limit.WRIST_ULNAR: "U",
	ArmAnatomy.Limit.ARM_IN_TORSO: "T",
	ArmAnatomy.Limit.HAND_IN_TORSO: "H",
}


class GameStateStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


class Cell:
	var angle: float = 0.0
	var radius: float = 0.0
	var landed_off_target: float = 0.0
	var today_top := ArmAnatomy.ArmPose.new()
	var today_bottom := ArmAnatomy.ArmPose.new()
	var today_twist: float = 0.0
	var any := ArmAnatomySearch.Pose.new()
	var target := ArmAnatomySearch.Pose.new()
	var reached: bool = true


var _report: PackedStringArray = []


func test_the_map() -> void:
	var builds: Array = [["short", PlayerAttributes.new(PlayerAttributes.HEIGHT_MIN)],
			["neutral", PlayerAttributes.neutral()],
			["tall", PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX)]]
	for build: Array in builds:
		for state: String in ["stand", "skate"]:
			_map(build[0], build[1], state)
	_write()
	assert_true(true)


func _map(build_name: String, attrs: PlayerAttributes, state: String) -> void:
	var c: SkaterController = _make(attrs)
	var body: ArmAnatomyBody = SkaterAnatomyCapture.capture(c)
	var search := ArmAnatomySearch.new(body)
	c.has_puck = true
	c._sm.set_state(SkaterStateMachine.State.SKATING_WITH_PUCK)
	var forehand: float = signf(body.bottom_shoulder.x)
	var cells: Array[Cell] = []
	for radius: float in RADII:
		for angle: float in ANGLES:
			var cell := Cell.new()
			cell.angle = angle
			cell.radius = radius
			var a: float = deg_to_rad(angle)
			var cursor := Vector2(sin(a) * forehand, -cos(a)) * radius
			_settle(c, cursor, state)
			_read(c, body, search, cursor, cell)
			cells.append(cell)
	_print_map("%s, %s" % [build_name, state], body, cells)


func _make(attrs: PlayerAttributes) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(skater)
	skater.set_process(false)
	skater.set_physics_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	add_child_autofree(puck)
	puck.set_physics_process(false)
	var gs := GameStateStub.new()
	add_child_autofree(gs)
	var c := SkaterController.new()
	add_child_autofree(c)
	c.setup(skater, puck, gs)
	c.apply_attributes(attrs)
	skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	skater._process(DT)
	return c


# The carrier facing -Z with the cursor held at `cursor` off him (facing frame,
# m), standing still or skating straight ahead at speed, until it settles.
func _settle(c: SkaterController, cursor: Vector2, state: String) -> void:
	var skater: Skater = c.skater
	for _i: int in SETTLE_TICKS:
		skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
		if state == "stand":
			skater.velocity = Vector3.ZERO
		c._pose.facing = Vector2(0.0, -1.0)
		skater.set_facing(c._pose.facing)
		var input := InputState.new()
		input.delta = DT
		input.move_vector = Vector2(0.0, -SKATE_SPEED_STICK) if state == "skate" else Vector2.ZERO
		input.mouse_world_pos = skater.global_position + Vector3(cursor.x, 0.0, cursor.y)
		input.mouse_world_pos.y = 0.0
		skater.capture_prev_blade_contact()
		c._process_input(input, DT)
		skater._physics_process(DT)
		skater._process(DT)


func _read(c: SkaterController, body: ArmAnatomyBody, search: ArmAnatomySearch,
		cursor: Vector2, cell: Cell) -> void:
	var skater: Skater = c.skater
	var hips: Transform3D = SkaterAnatomyCapture.hips_frame(skater)
	var to_hips: Transform3D = hips.affine_inverse()
	var heel: Vector3 = to_hips * skater.blade.global_position
	var at: Vector3 = skater.global_position + Vector3(cursor.x, 0.0, cursor.y)
	var target: Vector3 = to_hips * Vector3(at.x, skater.blade.global_position.y, at.z)
	# The puck rides a pin off the blade (Skater.get_carry_target_global): that is
	# what the cursor names.
	var pin: Vector3 = skater.get_carry_target_global()
	cell.landed_off_target = Vector2(pin.x - at.x, pin.z - at.z).length()
	# Where the heel would be with the pin on the cursor.
	target += to_hips.basis * Vector3(skater.blade.global_position.x - pin.x, 0.0,
			skater.blade.global_position.z - pin.z)
	cell.reached = cell.landed_off_target <= REACHED_M
	var trunk: ArmAnatomySearch.TrunkState = SkaterAnatomyCapture.trunk_state(skater, body)
	cell.today_twist = angle_difference(skater.drawn_lower_body_rotation().y,
			skater.drawn_upper_body_rotation().y)
	_today(skater, body, cell)
	search.solve(trunk, heel, cell.any)
	if not cell.reached:
		search.solve(trunk, target, cell.target)


# The drawn arms re-solved where they are: their roots, hands and the shaft as
# the rig has them, the elbow and the fist's roll free (the top's in its face
# window).
func _today(skater: Skater, body: ArmAnatomyBody, cell: Cell) -> void:
	var skel: Skeleton3D = SkaterAnatomyCapture.skeleton(skater)
	var spine: Transform3D = skel.get_bone_global_pose(SkaterBodySkeleton.SPINE_BONE)
	var torso: Transform3D = skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TORSO)
	var blade: Vector3 = skel.global_transform.affine_inverse() * skater.blade.global_position
	var top_hand: Vector3 = skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_HAND).origin
	var shaft: Vector3 = (blade - top_hand).normalized()
	var to_skel: Transform3D = skel.global_transform.affine_inverse()
	var up: Vector3 = (to_skel.basis * Vector3.UP).normalized()
	for arm: int in 2:
		var upper: Transform3D = skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM
				if arm == 0 else SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM)
		var glove: Transform3D = skel.get_bone_global_pose(SkaterMeshBuilder.UpperBone.TOP_HAND
				if arm == 0 else SkaterMeshBuilder.UpperBone.BOTTOM_HAND)
		var st := ArmAnatomy.ArmSetup.new()
		st.body = body
		st.shoulder = upper.origin + upper.basis.z * 0.5
		st.side = signf((spine.affine_inverse() * st.shoulder).x)
		st.thorax = spine.basis.orthonormalized()
		st.torso = torso
		st.hand = glove.origin
		st.shaft = shaft
		st.roll_up = up
		st.grip_angle = body.top_grip_angle if arm == 0 else body.bottom_grip_angle
		st.roll_free = arm == 1
		st.roll_lo = body.top_roll_square - ArmAnatomySearch.FACE_TILT_MAX
		st.roll_hi = body.top_roll_square + ArmAnatomySearch.FACE_TILT_MAX
		ArmAnatomy.solve(st, cell.today_top if arm == 0 else cell.today_bottom,
				ArmAnatomy.ArmPose.new())


# One letter per cell, the cursor's grid (rows out from the body, columns round
# it from the backhand to the forehand):
#   .  today's arms hold it
#   a letter  today's arms cannot (upper case the top arm, lower the bottom),
#      the range that stops them; a body can hold the blade some other way
#   #  no pose holds the blade gameplay landed there
#   +  gameplay stops short of the cursor, and a body could reach it
#   (space)  gameplay stops short, and no body could
func _print_map(title: String, body: ArmAnatomyBody, cells: Array[Cell]) -> void:
	var lines: PackedStringArray = []
	lines.append("### %s" % title)
	lines.append("stick %.2f m, shoulders %.2f m apart, arms %.2f + %.2f m" % [body.stick_length,
			body.top_shoulder.distance_to(body.bottom_shoulder), body.upper_len, body.fore_len])
	lines.append("```")
	var header: String = "        "
	for angle: float in ANGLES:
		header += "%5.0f" % angle
	lines.append(header + "   (deg off facing, + forehand)")
	var i: int = 0
	var counts := {}
	for radius: float in RADII:
		var row: String = "%5.1f m " % radius
		for _a: float in ANGLES:
			var cell: Cell = cells[i]
			i += 1
			var mark: String = _mark(cell)
			row += "    " + mark
			counts[mark] = int(counts.get(mark, 0)) + 1
		lines.append(row)
	lines.append("```")
	var tally: PackedStringArray = []
	for k: String in counts:
		tally.append("`%s` %d" % [k, counts[k]])
	lines.append("Cells: " + ", ".join(tally))
	lines.append("")
	lines.append("| cursor | landed off | today top | today bottom | twist | any pose | at target |")
	lines.append("|---|---|---|---|---|---|---|")
	for cell: Cell in cells:
		lines.append("| %+.0f° %.1f m | %.2f | %s | %s | %.0f° | %s | %s |" % [cell.angle, cell.radius,
				cell.landed_off_target, _arm_text(cell.today_top), _arm_text(cell.today_bottom),
				rad_to_deg(cell.today_twist), _pose_text(cell.any),
				"" if cell.reached else _pose_text(cell.target)])
	lines.append("")
	for line: String in lines:
		gut.p(line)
	_report.append_array(lines)


func _mark(cell: Cell) -> String:
	if not cell.reached:
		return "+" if cell.target.feasible() else " "
	if not cell.any.feasible():
		return "#"
	if cell.today_top.violation >= cell.today_bottom.violation and not cell.today_top.feasible():
		return LETTERS[cell.today_top.binding]
	if not cell.today_bottom.feasible():
		return String(LETTERS[cell.today_bottom.binding]).to_lower()
	return "."


func _arm_text(p: ArmAnatomy.ArmPose) -> String:
	var verdict: String = "ok" if p.feasible() else "%s +%.0f°" % [
			ArmAnatomy.Limit.keys()[p.binding], rad_to_deg(p.violation)]
	return "%s (sh %.0f/%.0f/%.0f el %.0f pr %.0f wr %.0f/%.0f)" % [verdict,
			rad_to_deg(p.elevation), rad_to_deg(p.plane), rad_to_deg(p.axial),
			rad_to_deg(p.elbow_flexion), rad_to_deg(p.pronation), rad_to_deg(p.wrist_flexion),
			rad_to_deg(p.wrist_deviation)]


func _pose_text(p: ArmAnatomySearch.Pose) -> String:
	if p.feasible():
		return "ok (tw %.0f° lie %.0f° tilt %.0f° grip %.2f)" % [rad_to_deg(p.twist),
				rad_to_deg(p.lie), rad_to_deg(p.face_tilt), p.spacing]
	var what: String = ArmAnatomySearch.Limit.keys()[p.trunk_binding] if p.binding_arm < 0 \
			else "%s %s" % ["top" if p.binding_arm == 0 else "bottom",
			ArmAnatomy.Limit.keys()[p.arm_binding]]
	return "%s +%.0f°" % [what, rad_to_deg(p.violation)]


func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.preview"))
	var f: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("# Arm anatomy map\n\nWritten by tests/instruments/actors/" \
			+ "test_arm_anatomy_map.gd. Legend in its `_print_map`.\n\n")
	f.store_string("\n".join(_report))
	f.close()

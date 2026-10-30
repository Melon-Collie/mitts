extends GutTest

# The player screen's display case: the mannequin it dresses and the camera that
# frames it. What is pinned here: a pick repaints the piece that wears it on
# both sides, the figure's geometry holds at every build (hands on the shaft,
# legs joined, feet on the ice), every framing contains its subject, and the
# turn/zoom controls behave. The rows that ask for those framings are pinned in
# test_player_settings_popup.gd.

# A synthetic kit shaped like TeamColorRegistry.get_colors' output, with every
# slot distinguishable so a zone landing on the wrong one is visible.
const _PRIMARY := Color(0.10, 0.30, 0.80)
const _SECONDARY := Color(0.90, 0.30, 0.10)
const _LIGHT := Color(0.96, 0.93, 0.84)   # cream, like Plum's
const _KIT_GLOVES := Color(0.75, 0.15, 0.15)
# Whichever team color the glove body is not — see TeamColorRegistry.
const _GLOVE_ACCENT := Color(0.20, 0.70, 0.35)
# Per arm (top, bottom): upper arm, forearm, hand, cuff.
const _ARMS: Array[Array] = [
	[SkaterMeshBuilder.UpperBone.TOP_UPPER_ARM, SkaterMeshBuilder.UpperBone.TOP_FOREARM,
			SkaterMeshBuilder.UpperBone.TOP_HAND, SkaterMeshBuilder.UpperBone.TOP_CUFF],
	[SkaterMeshBuilder.UpperBone.BOTTOM_UPPER_ARM, SkaterMeshBuilder.UpperBone.BOTTOM_FOREARM,
			SkaterMeshBuilder.UpperBone.BOTTOM_HAND, SkaterMeshBuilder.UpperBone.BOTTOM_CUFF],
]
const _Leg = SkaterMeshBuilder.LegSurface
const _Upper = SkaterMeshBuilder.UpperSurface

var _case: PlayerCase = null


func before_each() -> void:
	_case = PlayerCase.new()
	add_child_autofree(_case)


# Shaped like TeamColorRegistry.get_colors' output, typed arrays included —
# the stripe blocks really are Array[Dictionary] there, and the texture factory
# the mannequin paints through refuses an untyped one.
func _colors() -> Dictionary:
	var stripes: Array[Dictionary] = [
		{"pos": 0.55, "width": 0.10, "color": _SECONDARY},
	]
	var bare: Array[Dictionary] = []
	return {
		"primary": _PRIMARY,
		"secondary": _SECONDARY,
		"light": _LIGHT,
		"gloves": _KIT_GLOVES,
		"glove_accent": _GLOVE_ACCENT,
		"helmet": Color(0.2, 0.2, 0.2),
		"text": _LIGHT,
		"uniform": {
			"helmet": Color(0.2, 0.2, 0.2),
			"shoulders": {"color": _PRIMARY, "text": _LIGHT, "stroke": Color.TRANSPARENT},
			"jersey": {"base": _PRIMARY, "stripes": stripes, "yoke": _SECONDARY},
			"sleeve": {"base": _PRIMARY, "stripes": bare},
			"gloves": _KIT_GLOVES,
			"pants": {"base": _SECONDARY, "stripes": bare},
			"socks": {"base": _PRIMARY, "stripes": stripes},
			"text": {"color": _LIGHT, "stroke": Color.TRANSPARENT},
		},
	}


func _open(gear: GearStyleConfig = GearStyleConfig.new(),
		tape_code: int = StickTapeConfig.DEFAULT_CODE,
		attrs: PlayerAttributes = null) -> void:
	var build: PlayerAttributes = attrs if attrs != null else PlayerAttributes.neutral()
	_case.dress(build, gear, StickTapeConfig.from_code(tape_code), _colors(),
			SkinToneRegistry.DEFAULT_INDEX, false)
	_case.settle(LockerMannequin.Focus.FULL)


# The neutral build with its stick cut and pattern swapped.
func _stick(length: int, curve: int = PlayerAttributes.GEAR_BALANCED) -> PlayerAttributes:
	return PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, 0,
			PlayerAttributes.GEAR_BALANCED, curve, PlayerAttributes.GEAR_BALANCED, length)


func _mannequin() -> LockerMannequin:
	return _case.get("_mannequin") as LockerMannequin


func _kit() -> FigureKit:
	return _mannequin().get("_kit") as FigureKit


# One paint zone's color on the figure's body.
func _zone_color(zone: int) -> Color:
	return (_kit().get("_paint") as BodyZonePaint).zone(zone).albedo_color


func _upper(surface: int) -> int:
	return SkaterMeshBuilder.UPPER_ZONE_BASE + surface


# One bone's pose in the figure's rig space (the skeleton rests at its origin).
func _bone(bone: int) -> Transform3D:
	return _kit().skeleton.get_bone_global_pose(bone)


func _leg(bone: int) -> Transform3D:
	return _bone(SkaterBodySkeleton.LEG_BONE_OFFSET + bone)



func test_a_pick_repaints_the_mannequin() -> void:
	_open(GearStyleConfig.new(GearModelRegistry.SKATE_BLACKOUT,
			GearModelRegistry.GLOVE_TEAM))
	assert_eq(_zone_color(_Leg.FOOT_L_SHELL),
			GearModelRegistry.BLACK, "the stock skate is on the feet in black")
	assert_eq(_zone_color(_upper(_Upper.TOP_CUFF)), _KIT_GLOVES,
			"the stock glove cuff wears the kit")

	# Whiteout's boot is light; Pro's cuff is light. A re-dress must reach both,
	# and "light" is the TEAM's white — cream here, not a fixed one.
	_open(GearStyleConfig.new(GearModelRegistry.SKATE_WHITEOUT, GearModelRegistry.GLOVE_PRO))
	assert_eq(_zone_color(_Leg.FOOT_L_SHELL),
			_LIGHT, "the picked boot repaints in the team's own white")
	assert_eq(_zone_color(_upper(_Upper.TOP_CUFF)), _LIGHT,
			"the picked cuff repaints in the team's own white")


# Both feet and both hands wear the pick — a loop that painted only index 0
# would leave the figure in mismatched gear and nothing else would catch it.
func test_a_pick_reaches_both_sides() -> void:
	_open(GearStyleConfig.new(GearModelRegistry.SKATE_WHITEOUT, GearModelRegistry.GLOVE_PRO))
	for zone: int in [_Leg.FOOT_L_SHELL, _Leg.FOOT_R_SHELL, _upper(_Upper.TOP_CUFF),
			_upper(_Upper.BOTTOM_CUFF)]:
		assert_eq(_zone_color(zone), _LIGHT, "zone %d" % zone)


# The zones that only exist because a piece was SPLIT are the ones a wrong
# surface index would paint silently — pin that each lands on its own piece.
func test_split_pieces_paint_apart() -> void:
	# Two-Tone: light quarter, black toe cap. Pro: light toe cap under a black
	# quarter. Two-Tone gloves: the kit pairing flipped — the team's other
	# color on the back, the kit's own on the fingers.
	_open(GearStyleConfig.new(GearModelRegistry.SKATE_TWO_TONE,
			GearModelRegistry.GLOVE_TWO_TONE))
	assert_eq(_zone_color(_upper(_Upper.TOP_HAND)),
			_GLOVE_ACCENT, "Two-Tone's back takes the team's other color")
	assert_eq(_zone_color(_Leg.FOOT_L_SHELL), _LIGHT, "the quarter is the team's white")
	assert_eq(_zone_color(_Leg.FOOT_L_TOE), GearModelRegistry.BLACK, "the toe cap is black")
	assert_eq(_zone_color(_upper(_Upper.TOP_FINGERS)),
			_KIT_GLOVES, "Two-Tone's fingers keep the kit")
	assert_eq(_zone_color(_Leg.FOOT_L_HOLDER), _LIGHT, "the holder is the team's white")
	_open(GearStyleConfig.new(GearModelRegistry.SKATE_PRO, GearModelRegistry.GLOVE_TWO_TONE))
	assert_eq(_zone_color(_Leg.FOOT_L_TOE), _LIGHT, "Pro's toe cap is the team's white")
	# The steel runner is never a kit zone, whatever the model says — and it must
	# stay distinct from the white holder now sitting directly above it.
	assert_ne(_zone_color(_Leg.FOOT_L_RUNNER), _LIGHT,
			"the runner does not vanish into the holder")
	assert_eq(_zone_color(_Leg.FOOT_L_RUNNER), SkaterMeshBuilder.BLADE_STEEL_COLOR,
			"the runner stays steel")


func _head_piece(piece: int) -> MeshInstance3D:
	return (_kit().get("_head_pieces") as Array)[piece] as MeshInstance3D


func _face(option: int) -> GearStyleConfig:
	return GearStyleConfig.new(0, 0, GearStyleConfig.LACE_DEFAULT_INDEX, 0, option)


func test_face_gear_dresses_the_helmet() -> void:
	_open(_face(GearModelRegistry.FACE_VISOR))
	var piece: MeshInstance3D = _head_piece(SkaterArmRig.HeadPiece.FACE_GEAR)
	assert_not_null(piece.mesh, "the picked visor is in the helmet")
	var mat: StandardMaterial3D = piece.material_override as StandardMaterial3D
	assert_lt(mat.albedo_color.a, 1.0, "the visor preview is translucent")
	_open(_face(GearModelRegistry.FACE_CAGE))
	assert_eq(piece.mesh, SkaterMeshBuilder.shared_face_gear(GearModelRegistry.FACE_CAGE))
	_open(_face(GearModelRegistry.FACE_NONE))
	assert_null(piece.mesh, "bare leaves the helmet open")


# The figure wears the pending hair, brows included.
func test_the_figure_wears_the_pending_hair() -> void:
	_open(GearStyleConfig.new(0, 0, GearStyleConfig.LACE_DEFAULT_INDEX, 0,
			GearModelRegistry.FACE_NONE, HairStyleRegistry.HAIR_MULLET,
			HairStyleRegistry.FACIAL_STUBBLE, 6))
	var scalp: MeshInstance3D = _head_piece(SkaterArmRig.HeadPiece.SCALP)
	var facial: MeshInstance3D = _head_piece(SkaterArmRig.HeadPiece.FACIAL_HAIR)
	var brows: MeshInstance3D = _head_piece(SkaterArmRig.HeadPiece.BROWS)
	assert_eq(scalp.mesh, SkaterHairMesh.shared_hair(HairStyleRegistry.HAIR_MULLET))
	assert_eq(facial.mesh, SkaterHairMesh.shared_facial_hair(HairStyleRegistry.FACIAL_STUBBLE))
	assert_lt((facial.material_override as StandardMaterial3D).albedo_color.a, 1.0,
			"stubble previews translucent")
	assert_eq((brows.material_override as StandardMaterial3D).albedo_color,
			HairStyleRegistry.color_for(6), "the brows take the hair colour")


# The tuck is the body's shape: a pick re-drapes the figure's sweater and keeps
# its paint.
func test_a_tuck_pick_drapes_the_figure() -> void:
	_open()
	var body: MeshInstance3D = _kit().skeleton.find_child("Body", false, false) \
			as MeshInstance3D
	var paint: Material = body.get_surface_override_material(0)
	_open(GearStyleConfig.new(0, 0, GearStyleConfig.LACE_DEFAULT_INDEX, 0, 0,
			HairStyleRegistry.HAIR_SHORT, HairStyleRegistry.FACIAL_NONE, 0,
			GearModelRegistry.TUCK_RIGHT))
	assert_true(body.mesh in [SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_RIGHT, true),
			SkaterBodyMesh.shared_mesh(GearModelRegistry.TUCK_RIGHT, false)],
			"the sweater re-drapes, on whichever hand tops the figure's stick")
	assert_eq(body.get_surface_override_material(0), paint, "the sweater keeps its paint")


# A curve pick rebuilds the blade and a length pick moves the butt — the two
# stick gear rows with geometry behind them.
func test_stick_gear_reaches_the_blade_and_the_shaft() -> void:
	_open()
	var blade: MeshInstance3D = _mannequin().get("_blade") as MeshInstance3D
	var shaft: MeshInstance3D = _mannequin().get("_shaft") as MeshInstance3D
	var flat_mesh: Mesh = blade.mesh
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
			_stick(PlayerAttributes.GEAR_BALANCED, 2))   # M28 toe hook
	assert_ne(blade.mesh, flat_mesh, "a curve pick rebuilds the blade")

	_open()
	var standard_len: float = shaft.transform.basis.get_scale().z
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE, _stick(0))  # Short
	var short_len: float = shaft.transform.basis.get_scale().z
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE, _stick(2))  # Long
	assert_lt(short_len, standard_len, "a short cut shortens the shaft")
	assert_lt(standard_len, shaft.transform.basis.get_scale().z,
			"a long cut outreaches standard")


# Both fists grip the shaft, so a length change has to carry them — hands left
# behind at the old grip is exactly the failure the mannequin replaced the
# free-floating turntable to avoid.
func test_the_hands_stay_on_the_shaft_when_the_stick_is_recut() -> void:
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE, _stick(0))
	var short_grip: Vector3 = _bone(_ARMS[0][2]).origin
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE, _stick(2))
	assert_lt(short_grip.y, _bone(_ARMS[0][2]).origin.y,
			"a longer stick raises the top hand's grip")


# Distance from the shaft line to each fist. The grips are solved onto that
# line, so anything above a rounding error means a hand is holding thin air.
func _grip_offset(hand: Vector3) -> float:
	var heel: Vector3 = _mannequin().get("_shaft_heel")
	var up: Vector3 = _mannequin().get("_shaft_up")
	var along: Vector3 = hand - heel
	return (along - up * along.dot(up)).length()


# Both arms are the rig's own length. Deriving segment length from how far the
# grip happened to land built one long arm and one short one, because the two
# hands sit at very different distances from their shoulders.
func test_both_arms_are_the_same_length() -> void:
	for length: int in 3:
		_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE, _stick(length))
		var build := PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM,
				int(PlayerAttributes.NEUTRAL_WEIGHT_LBS), 1, 1, 1, length)
		# The forearm bone ends at the wrist, a hand short of the fist.
		var hand: float = LockerMannequin._HAND_M * build.height_mult()
		var spans: Array[float] = []
		for i: int in 2:
			var upper: float = _bone(_ARMS[i][0]).basis.z.length()
			var fore: float = _bone(_ARMS[i][1]).basis.z.length() + hand
			assert_almost_eq(upper, fore, 0.01,
					"arm %d bends at its midpoint (cut %d)" % [i, length])
			spans.append(upper + fore)
		assert_almost_eq(spans[0], spans[1], 0.01,
				"both arms are the same length (cut %d)" % length)
		# And that length is the rig's own bones riding the build's height, not
		# whatever distance the grip happened to land at.
		assert_almost_eq(spans[0], 0.66 * build.height_mult(), 0.01,
				"arms are the rig's 0.33 m bones, scaled by height")


# Every grip has to end up ON the shaft and inside its own arm's reach — the
# solver slides it until both hold, so neither can be traded for the other.
func test_the_grips_stay_on_the_shaft_and_inside_the_arms_reach() -> void:
	for height: int in [PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX]:
		for length: int in 3:
			_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
					PlayerAttributes.new(height,
						PlayerAttributes.coerce_weight(height, 190), 1, 1, 1, length))
			for i: int in 2:
				var hand: Vector3 = _bone(_ARMS[i][2]).origin
				assert_almost_eq(_grip_offset(hand), 0.0, 0.001,
						"hand %d grips the shaft (height %d, cut %d)" % [i, height, length])
				# The arm bones are prisms from +Z (the near joint) to −Z.
				var shoulder: Vector3 = _bone(_ARMS[i][0]) * Vector3(0.0, 0.0, 0.5)
				var upper: float = _bone(_ARMS[i][0]).basis.z.length()
				var fore: float = _bone(_ARMS[i][1]).basis.z.length()
				assert_lte(shoulder.distance_to(hand), upper + fore + 0.001,
						"hand %d is inside its arm's reach" % i)


# The leg is a CHAIN: hip, knee and boot stacked down each side at every build,
# and the skin's knee bone between thigh and shin, so the knee bends there.
func test_the_legs_chain_from_the_hip_to_the_boot() -> void:
	for height: int in [PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MEDIUM,
			PlayerAttributes.HEIGHT_MAX]:
		_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
				PlayerAttributes.new(height,
					PlayerAttributes.coerce_weight(height, 190), 1, 1, 1, 1))
		var pelvis: Vector3 = _bone(SkaterMeshBuilder.UpperBone.PELVIS).origin
		for i: int in 2:
			var leg: int = SkaterMeshBuilder.LegBone.LEG_L if i == 0 \
					else SkaterMeshBuilder.LegBone.LEG_R
			var hip: Vector3 = _leg(leg).origin
			var knee: Vector3 = _leg(leg + 3).origin
			var boot: Vector3 = _leg(leg + 6).origin
			assert_lt(hip.y, pelvis.y, "hip %d under the seat (height %d)" % [i, height])
			assert_lt(knee.y, hip.y, "knee %d under its hip (height %d)" % [i, height])
			assert_lt(boot.y, knee.y, "boot %d under its knee (height %d)" % [i, height])
			var bend: Vector3 = _bone(SkaterBodySkeleton.deform_bone(
					SkaterConnectedMesh.Deform.KNEE_L + i)).origin
			assert_almost_eq(bend, knee, Vector3.ONE * 0.001,
					"the skin's knee %d bends at the knee (height %d)" % [i, height])


# The fist and cuff bases scale their COLUMNS. Basis.scaled() scales in the
# parent frame instead, which shears a rotated grip basis into a stretched
# sheet — a blade-shaped artifact hanging off each wrist.
func test_the_hand_pieces_are_not_sheared() -> void:
	_open()
	for i: int in 2:
		for bone: int in [_ARMS[i][2], _ARMS[i][3]]:
			var b: Basis = _bone(bone).basis
			assert_almost_eq(b.x.dot(b.y), 0.0, 0.0001, "bone %d x⊥y" % bone)
			assert_almost_eq(b.y.dot(b.z), 0.0, 0.0001, "bone %d y⊥z" % bone)
			assert_almost_eq(b.z.dot(b.x), 0.0, 0.0001, "bone %d z⊥x" % bone)
		# The cuff is a unit-radius ring with its real height baked in, so only
		# its radius may scale — a stretched Y is the artifact itself.
		var cuff: Basis = _bone(_ARMS[i][3]).basis
		assert_almost_eq(cuff.y.length(), 1.0, 0.001, "cuff %d keeps its height" % i)
		assert_lt(cuff.x.length(), 0.15, "cuff %d stays a wrist ring" % i)
		assert_lt(cuff.z.length(), 0.15, "cuff %d stays a wrist ring" % i)


# The mannequin stands ON the case floor at every build: the boot is the one
# part the appearance rig never scales, so the seat has to be derived rather
# than assumed.
func test_every_build_stands_on_the_ice() -> void:
	for height: int in [PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MEDIUM,
			PlayerAttributes.HEIGHT_MAX]:
		var weight: int = PlayerAttributes.coerce_weight(height,
				int(PlayerAttributes.NEUTRAL_WEIGHT_LBS))
		_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
				PlayerAttributes.new(height, weight, PlayerAttributes.GEAR_BALANCED,
					PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED,
					PlayerAttributes.GEAR_BALANCED))
		var rig: Node3D = _mannequin().get("_rig") as Node3D
		# The runner's edge in the boot's frame (+Z down), and the mannequin's own
		# origin is the ice.
		var runner: Vector3 = _leg(SkaterMeshBuilder.LegBone.FOOT_L) \
				* Vector3(0.0, 0.0, SkaterMeshBuilder.BLADE_ICE_Z)
		assert_almost_eq(rig.position.y + runner.y, 0.0, 0.001,
				"height %d stands on the disc" % height)


# A taller build is visibly taller — the height dial has to reach the figure,
# not just the numbers in the player screen.
func test_height_reaches_the_figure() -> void:
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
			PlayerAttributes.new(PlayerAttributes.HEIGHT_MIN, 150,
				PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED,
				PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED))
	var short_head: float = _bone(SkaterMeshBuilder.UpperBone.HELMET).origin.y
	_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
			PlayerAttributes.new(PlayerAttributes.HEIGHT_MAX, 220,
				PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED,
				PlayerAttributes.GEAR_BALANCED, PlayerAttributes.GEAR_BALANCED))
	assert_lt(short_head, _bone(SkaterMeshBuilder.UpperBone.HELMET).origin.y,
			"a tall build carries its head higher")


# Every framing has to actually CONTAIN its subject, at every build — a whole-
# stick shot that crops a long cut on a tall player is the bug this replaced.
func test_the_whole_stick_shot_contains_the_whole_stick() -> void:
	for height: int in [PlayerAttributes.HEIGHT_MIN, PlayerAttributes.HEIGHT_MAX]:
		for length: int in 3:
			_open(GearStyleConfig.new(), StickTapeConfig.DEFAULT_CODE,
					PlayerAttributes.new(height,
						PlayerAttributes.coerce_weight(height, 190), 1, 1, 1, length))
			var extent: Vector2 = _mannequin().focus_extent(LockerMannequin.Focus.STICK)
			var mid: Vector3 = _mannequin().focus_anchor(LockerMannequin.Focus.STICK)
			for focus: int in [LockerMannequin.Focus.BLADE, LockerMannequin.Focus.GRIP]:
				var end_point: Vector3 = _mannequin().focus_anchor(focus)
				assert_lte(absf(end_point.y - mid.y), extent.y,
						"the stick shot holds its ends (height %d, cut %d)"
						% [height, length])
	# And the whole-stick shot is a real step in from the wide one, or hovering
	# a stick row would look like nothing happened.
	_open()
	assert_lt(_mannequin().focus_extent(LockerMannequin.Focus.STICK).y,
			_mannequin().focus_extent(LockerMannequin.Focus.FULL).y,
			"the stick shot is tighter than the wide shot")
	assert_lt(_mannequin().focus_extent(LockerMannequin.Focus.BLADE).y,
			_mannequin().focus_extent(LockerMannequin.Focus.STICK).y,
			"the blade shot is tighter than the whole stick")


# Dragging up pulls the camera in and down pushes it out, and the zoom clamps
# against the CURRENT framing rather than winding up — a multiplier that ran
# past its stop would leave the drag dead until it had been wound all the way
# back.
func test_dragging_up_and_down_zooms() -> void:
	_open()
	var wide: float = _case.call("_framed_distance")
	_case.call("_zoom_by", -0.25)
	var closer: float = _case.call("_framed_distance")
	assert_lt(closer, wide, "dragging up pulls the camera in")
	_case.call("_zoom_by", 0.5)
	assert_gt(_case.call("_framed_distance"), closer, "dragging down pushes it out")

	# Wind it hard against each stop, then reverse ONE step: the distance has to
	# move straight away. A held pad stick can hit these stops in a second, so
	# this is the pad's failure mode as much as the mouse's.
	for i: int in 40:
		_case.call("_zoom_by", -0.5)
	var pinned_near: float = _case.call("_framed_distance")
	_case.call("_zoom_by", 0.2)
	assert_gt(_case.call("_framed_distance"), pinned_near,
			"the near stop does not wind up")
	for i: int in 40:
		_case.call("_zoom_by", 0.5)
	var pinned_far: float = _case.call("_framed_distance")
	_case.call("_zoom_by", -0.2)
	assert_lt(_case.call("_framed_distance"), pinned_far,
			"the far stop does not wind up")


# The pad's right stick has to reach the same two controls the drag does, and
# agree with it on direction — a stick that zoomed the opposite way from the
# drag would read as one of the two being inverted.
func test_the_pad_stick_turns_and_zooms_the_same_way_the_drag_does() -> void:
	_open()
	# With no pad connected under GUT, the read must leave the case alone rather
	# than reading axes off a device that isn't there.
	var before_yaw: float = _case.get("_target_yaw")
	_case.call("_read_pad_look", 0.016)   # no pad connected under GUT
	assert_eq(_case.get("_target_yaw"), before_yaw,
			"no pad connected means the case is left alone")
	assert_false(_case.get("_pad_looking"), "and the idle turn keeps running")

	# The zoom path both devices share: negative pulls in on either.
	var wide: float = _case.call("_framed_distance")
	_case.call("_zoom_by", -0.3)
	assert_lt(_case.call("_framed_distance"), wide,
			"negative exponent pulls in, whichever device sent it")


# The hint has to name the device that is actually driving, and follow a swap.
func test_the_case_hint_names_the_driving_device() -> void:
	_open()
	var hint: Label = _case.get("_hint") as Label
	assert_false(hint.text.is_empty(), "the case says how to turn it")
	assert_eq(hint.text, ControllerGlyphs.prompt(
			tr(&"PLAYER_CASE_HINT_MOUSE"), tr(&"PLAYER_CASE_HINT_PAD")),
			"and names whichever device is active")


# Moving to another group hands back a framed shot, not whatever the last drag
# left behind.
func test_changing_focus_clears_the_hand_zoom() -> void:
	_open()
	_case.call("_zoom_by", -80.0)
	assert_lt(_case.get("_zoom"), 1.0)
	_case.frame(LockerMannequin.Focus.HELMET)
	assert_almost_eq(_case.get("_zoom"), 1.0, 0.0001,
			"the new framing starts framed")


# Each framing has to be its own shot — a piece anchor that never moved off the
# wide one would dolly nowhere.
func test_each_framing_looks_somewhere_different() -> void:
	_open()
	var seen: Array[Vector3] = []
	for focus: int in [LockerMannequin.Focus.FULL, LockerMannequin.Focus.STICK,
			LockerMannequin.Focus.BLADE, LockerMannequin.Focus.GRIP,
			LockerMannequin.Focus.SKATES, LockerMannequin.Focus.GLOVES,
			LockerMannequin.Focus.HELMET]:
		var anchor: Vector3 = _mannequin().focus_anchor(focus)
		for other: Vector3 in seen:
			assert_gt(anchor.distance_to(other), 0.05,
					"framing %d has its own anchor" % focus)
		seen.append(anchor)


# The case shows the sweater the ice does: the rink's own decals paint it, with
# the pending name, number and the team's crest.
func test_the_sweater_is_painted_by_the_rink_decals() -> void:
	var colors: Dictionary = TeamColorRegistry.get_colors(0, 0)
	_case.set_jersey_info("Smith", 27)
	_case.dress(PlayerAttributes.neutral(), GearStyleConfig.new(), StickTapeConfig.new(),
			colors, SkinToneRegistry.DEFAULT_INDEX, false)
	var paint: SkaterKitPaint = _kit().get("_kit") as SkaterKitPaint
	var jersey: JerseyDecal = paint.get("_jersey_decal") as JerseyDecal
	assert_eq(jersey.player_name, "Smith")
	assert_eq(jersey.jersey_number, 27)
	assert_eq(jersey.crest_fruit, TeamCrest.fruit_for(colors.preset))
	assert_eq((paint.get("_sleeve_decal") as SleeveDecal).jersey_number, 27)
	var torso: StandardMaterial3D = (_kit().get("_paint") as BodyZonePaint).zone(
			_upper(_Upper.TORSO))
	assert_eq(torso.albedo_texture, (paint.get("_jersey_viewport") as SubViewport).get_texture(),
			"the torso wears the decal's texture")

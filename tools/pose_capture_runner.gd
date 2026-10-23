extends Node

# The body of tools/pose_capture.gd — see that file for what the tool is for,
# how to run it, and why the work lives in a separate script.
#
# ── Why it drives the real controller ───────────────────────────────────────
# Poses are produced by feeding scripted InputStates to a real SkaterController
# on a real Skater, not by writing marker transforms directly. Writing the
# markers would test the renderer against itself: the conversion's whole risk is
# that a pose ARRIVES differently (a write landing on a bone instead of a node,
# in a different parent frame or a different order), and only running the code
# that produces the write exercises that.
#
# ── Determinism ─────────────────────────────────────────────────────────────
# A pixel diff is worthless if the same code renders differently twice, so
# nothing here may depend on wall-clock timing:
#   • The skater's own _process / _physics_process are switched OFF and called
#     by hand with a fixed DT, one of each per step. Real frame deltas would
#     advance the gait phase and the stick flex by a different amount each run.
#   • VFX and the world HUD are frozen (CosmeticFreeze). Both are non-rig content —
#     particle systems are stochastic and the HUD is camera-derived — so they
#     would contribute diff noise about nothing.
#   • Each pose gets a FRESH skater and controller. Charge timers, lean
#     smoothing and stamina all persist, so reusing one actor would make a
#     pose's appearance depend on which pose ran before it.
#   • No shadow maps. Shadow rasterisation is the one part of this scene that
#     wanders between runs, and the acne would read as scattered diff pixels.
#
# ── Reading a diff ──────────────────────────────────────────────────────────
# Sub-perceptual differences localised to an alpha-sort seam are acceptable;
# anything structural or scattered is not. The bounding box is what separates
# them — a change confined to a few pixels at one silhouette edge reads very
# differently from the same pixel COUNT scattered across the whole tile.

const DT: float = 1.0 / 120.0
const TILE: int = 384
const SHEET_COLS: int = 4
# Per-channel 0-255 delta below which two pixels count as equal. Software
# rasterisation is not bit-exact run to run at silhouette edges, and a baseline
# may have been recorded on a different machine.
const DIFF_TOLERANCE: int = 6

const BACKGROUND: Color = Color(0.10, 0.11, 0.14)

const OUT_DIR: String = "user://pose_capture"
const BASELINE_DIR: String = "user://pose_capture/baseline"
const CURRENT_DIR: String = "user://pose_capture/current"

# One build for every pose. Keeping it fixed keeps the diff about articulation;
# proportions across builds are skater_matrix.gd's job.
const BUILD_HEIGHT_IN: int = 73
const BUILD_WEIGHT_LB: int = 201

# Fixed camera offset from the skater, with a fixed rotation — a chase rig that
# never turns. The skater translates several metres during the gait poses, so a
# world-fixed camera would frame them differently from the standing ones; a
# camera that turned with the body would hide exactly the facing changes worth
# diffing.
#
# BOTH vectors are relative to the SKATER's origin, which sits at hip height
# (GameRules.FACEOFF_SPAWN_HEIGHT), not at the ice. Aiming at a world-space point
# instead puts the whole frame a metre high and cuts the legs off — which loses
# the skates and the gait, the half of the rig these poses exist to cover.
const CAM_OFFSET: Vector3 = Vector3(1.9, 0.6, 2.9)
const CAM_FOV: float = 45.0
const CAM_AIM: Vector3 = Vector3(0.0, -0.05, 0.0)
const CAM_HAND_FOV: float = 22.0

# Each pose: a name, whether it starts with the puck, and a list of
# [tick_count, input_spec] segments run in order. Edge fields (shoot_pressed,
# slap_pressed, stick_lift_pressed) fire on the FIRST tick of their segment
# only, which is what makes "press, then hold" expressible as two segments.
#
# Spec keys: move (Vector2, world), aim (Vector3, RELATIVE to the skater —
# absolute would swing as the body translates), stance, shoot, slap, block,
# deflect, hit, stick (the stick-check button), shove (the stick button pressed
# with Ctrl held, the cross-check), brake (bool), loft (int elevation level), face (Vector3, a
# facing set on the segment's first tick). Pose keys beyond name/puck/steps:
# cam (offset), cam_aim (the point it looks at, relative to the skater like
# cam), cam_ahead (metres down the travel line), cam_hand ("top" / "bottom":
# cam is then an offset from that hand, looked at through a narrow lens),
# game_cam, readout, faceoff, knockdown (a world-space impulse absorbed as a
# check before the first tick), tuck (a GearModelRegistry TUCK_* option worn). "readout": true also prints the pose's speed
# and body lean, which a tile can't be read for.
const POSES: Array = [
	{"name": "rest", "puck": false, "steps": [[40, {}]]},
	{"name": "carry", "puck": true, "steps": [[40, {"aim": Vector3(0.6, 0.0, -2.2)}]]},
	# Two gait phases at two facings. The tick counts are deliberately not
	# multiples of each other, so the stride lands at a different point in its
	# cycle rather than at the same phase twice.
	{"name": "stride_away", "puck": false, "steps": [
		[64, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	{"name": "stride_lateral", "puck": false, "steps": [
		[97, {"move": Vector2(1.0, 0.0), "aim": Vector3(2.0, 0.0, 1.5)}],
	]},
	# The loaded stance held at a standstill — the crouch on its own.
	{"name": "stance_rest", "puck": false, "steps": [[40, {"stance": true}]]},
	# Arm IK near its ROM limit: the cursor sits well across the body, so the
	# reach lean and the backhand ROM clamp both engage.
	{"name": "cross_body_reach", "puck": true, "steps": [
		[20, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[50, {"aim": Vector3(-2.6, 0.0, -0.4)}],
	]},
	{"name": "wrister_aim", "puck": true, "steps": [
		[10, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[45, {"aim": Vector3(1.4, 0.0, -3.0), "shoot": true}],
	]},
	# The best forehand there is: the puck out at the stick side, shot ahead.
	# `face` turns the body back to +Z on the press, which the carry alone can't
	# do — facing follows the cursor out to the puck.
	{"name": "wrister_nine", "puck": true, "readout": true, "steps": [
		[60, {"aim": Vector3(2.5, 0.0, 0.0)}],
		[40, {"aim": Vector3(0.0, 0.0, 3.0), "shoot": true, "face": Vector3(0.0, 0.0, 1.0)}],
	]},
	# The wind-up is the load (WristerLoad). This skater starts facing +Z and
	# shoots left: the puck pulled out to the stick side (+X) and aimed ahead is
	# the full forehand coil; aimed ahead with the puck straight in front there is
	# nothing to drive, so the torso stays squared.
	{"name": "wrister_loaded", "puck": true, "readout": true, "steps": [
		[60, {"aim": Vector3(0.0, 0.0, 2.5)}],
		[8, {"aim": Vector3(2.5, 0.0, 0.0)}],
		[40, {"aim": Vector3(0.0, 0.0, 3.0), "shoot": true}],
	]},
	{"name": "wrister_unloaded", "puck": true, "readout": true, "steps": [
		[60, {"aim": Vector3(0.0, 0.0, 2.5)}],
		[40, {"aim": Vector3(0.0, 0.0, 3.5), "shoot": true}],
	]},
	# Released, then held long enough for the follow-through the state machine
	# plays out to be the pose on screen.
	{"name": "wrister_follow_through", "puck": true, "steps": [
		[10, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[45, {"aim": Vector3(1.4, 0.0, -3.0), "shoot": true}],
		[14, {"aim": Vector3(1.4, 0.0, -3.0)}],
	]},
	# The overhead coil, authored in upper-body-local space — the pose most
	# likely to expose a wrong parent frame.
	# Faced up the ice first, then pressed and held through the set-up (the blade
	# bringing the puck in front, the hips opening side-on) to a full wind-up.
	{"name": "slapper_coil", "puck": true, "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[150, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	{"name": "slapper_follow_through", "puck": true, "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[150, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
		[16, {"aim": Vector3(0.8, 0.0, -3.2)}],
	]},
	# The same coil from down the shot line and from the game camera: the stance
	# (which way the hips and feet sit against the line) reads from these.
	{"name": "slapper_coil_front", "puck": true, "cam": Vector3(0.4, 0.9, -3.4), "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[150, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	# Facing the chest: side-on, the default (left-handed) shooter's chest faces
	# −X with the net up −Z. Whether the arms come up in front of the body.
	{"name": "slapper_coil_chest", "puck": true, "cam": Vector3(-3.4, 0.9, 0.3), "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[150, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	{"name": "slapper_coil_game", "puck": true, "game_cam": true, "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[150, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	# Pressed with the puck out on the backhand: a few ticks in, the blade is
	# still bringing it across to the strike spot.
	{"name": "slapper_from_backhand", "puck": true, "steps": [
		[60, {"aim": Vector3(-1.4, 0.0, -1.0)}],
		[12, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	# Loaded for a one-timer, no puck yet.
	{"name": "one_timer_loaded", "puck": false, "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[120, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	{"name": "one_timer_loaded_game", "puck": false, "game_cam": true, "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[120, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	{"name": "one_timer_loaded_front", "puck": false, "cam": Vector3(0.4, 0.9, -3.4), "steps": [
		[60, {"aim": Vector3(0.4, 0.0, -2.0)}],
		[120, {"aim": Vector3(0.8, 0.0, -3.2), "slap": true}],
	]},
	# Turning at speed: build to cruise heading -Z, then turn toward +X. A
	# striding crossover turn, the Space + side-key tight turn mid-carve, and
	# the tight turn held until it lines up with the key (where it blends into
	# a stop).
	{"name": "wiggle_aim", "puck": false, "trace": 10, "steps": [
		[40, {"aim": Vector3(3.0, 0.0, 0.0)}],
		[40, {"aim": Vector3(0.0, 0.0, -3.0)}],
		[240, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[40, {"move": Vector2(0.0, -1.0), "aim": Vector3(2.5, 0.0, -1.5)}],
		[40, {"move": Vector2(0.0, -1.0), "aim": Vector3(-2.5, 0.0, -1.5)}],
		[40, {"move": Vector2(0.0, -1.0), "aim": Vector3(2.5, 0.0, -1.5)}],
		[40, {"move": Vector2(0.0, -1.0), "aim": Vector3(-2.5, 0.0, -1.5)}],
	]},
	{"name": "wiggle_keys", "puck": false, "trace": 10, "steps": [
		[40, {"aim": Vector3(3.0, 0.0, 0.0)}],
		[40, {"aim": Vector3(0.0, 0.0, -3.0)}],
		[240, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(0.7, -0.7), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(-0.7, -0.7), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(0.7, -0.7), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(-0.7, -0.7), "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	{"name": "turn_carve_hard", "puck": false, "readout": true, "cam_ahead": 3.2, "steps": [
		[210, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[45, {"move": Vector2(1.0, 0.0), "aim": Vector3(2.2, 0.0, -2.2)}],
	]},
	{"name": "turn_tight", "puck": false, "readout": true, "cam_ahead": 3.2, "steps": [
		[210, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(1.0, 0.0), "stance": true, "aim": Vector3(2.2, 0.0, -2.2)}],
	]},
	{"name": "turn_tight_game", "puck": false, "game_cam": true, "steps": [
		[210, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(1.0, 0.0), "stance": true, "aim": Vector3(2.2, 0.0, -2.2)}],
	]},
	{"name": "turn_tight_exit", "puck": false, "readout": true, "cam_ahead": 3.2, "steps": [
		[210, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[70, {"move": Vector2(1.0, 0.0), "stance": true, "aim": Vector3(3.0, 0.0, -0.5)}],
	]},
	# The same reads from the game camera, where a pose has to work: from above,
	# the stance has to read by WIDTH, the commit by being tall and narrow.
	{"name": "rest_game", "puck": false, "game_cam": true, "steps": [[40, {}]]},
	{"name": "stance_rest_game", "puck": false, "game_cam": true,
			"steps": [[40, {"stance": true}]]},
	{"name": "skate_game", "puck": false, "game_cam": true, "steps": [
		[150, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	{"name": "stance_skate_game", "puck": false, "game_cam": true, "steps": [
		[120, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[40, {"move": Vector2(0.0, -1.0), "stance": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	{"name": "carve_game", "puck": false, "game_cam": true, "steps": [
		[210, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[30, {"move": Vector2(1.0, 0.0), "aim": Vector3(2.2, 0.0, -2.2)}],
	]},
	{"name": "hit_commit_game", "puck": false, "game_cam": true, "steps": [
		[120, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[40, {"move": Vector2(0.0, -1.0), "hit": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	# The gloves up close: the cuff over the wrist, the sleeve stopping inside
	# it, and the two fists on the shaft.
	{"name": "gloves_carry", "puck": true, "cam_hand": "bottom", "cam": Vector3(0.9, 0.5, 0.8),
		"steps": [[40, {"aim": Vector3(0.6, 0.0, -2.2)}]]},
	{"name": "gloves_front", "puck": false, "cam_hand": "top", "cam": Vector3(0.3, 0.9, -1.4),
		"steps": [[40, {}]]},
	{"name": "shot_block", "puck": false, "steps": [
		[30, {"block": true, "aim": Vector3(0.0, 0.0, -3.0)}],
	]},
	# Blade tilt extreme: deflect intent at HIGH loft lifts the blade off the ice
	# and rolls it, the widest the blade transform ever swings.
	{"name": "blade_loft_high", "puck": false, "steps": [
		[36, {"deflect": true, "loft": 3, "aim": Vector3(1.2, 0.0, -2.6)}],
	]},
	# The check-commit load-up, aimed BACK AT THE CAMERA (the only poses here
	# framed from the front): its whole content is per-shoulder asymmetry across
	# the chest, and the chase rig sees the back of every other pose.
	#
	# Straight-on first — no lateral steer at all, which is the case the stance
	# has to read in, and the one a velocity-signed pose could not express. Then
	# the same commit steering off the stick side, where the lead clamps to full:
	# the deepest the leading cap and its arm root ever travel, so it is the tile
	# that shows whether the pad still sits on the arm it grows from.
	{"name": "hit_commit", "puck": false, "steps": [
		[60, {"hit": true, "move": Vector2(0.55, 0.84), "aim": Vector3(1.6, 0.0, 2.4)}],
	]},
	{"name": "hit_commit_deep", "puck": false, "steps": [
		[60, {"hit": true, "move": Vector2(0.84, -0.55), "aim": Vector3(1.6, 0.0, 2.4)}],
	]},
	# ── Board pin ───────────────────────────────────────────────────────────
	# Both locked roles against the +x boards, facing them (the boards are not
	# drawn here; the tiles are for the lean and the sit): the pinned skater
	# pressed flat to the glass, the pinner a body off it, driving in.
	# Shot side-on from the ice (the default camera would sit outside the boards).
	{"name": "pin_pinned", "puck": false, "pin_role": BoardPinRules.Role.PINNED,
		"cam": Vector3(-0.8, 0.6, 3.2), "steps": [[60, {"aim": Vector3(3.0, 0.0, 0.0)}]]},
	{"name": "pin_pinner", "puck": false, "pin_role": BoardPinRules.Role.PINNER,
		"cam": Vector3(-0.8, 0.6, 3.2),
		"steps": [[60, {"stick": true, "aim": Vector3(3.0, 0.0, 0.0)}]]},
	# ── Cross-check ─────────────────────────────────────────────────────────
	# The Ctrl+F chord at a standstill: the shaft level across the chest, punched
	# out. Mid-push, then at full extension, aimed and framed from the front like
	# the commit (a skater at rest faces +Z).
	{"name": "cross_check_mid", "puck": false, "readout": true, "cam": Vector3(2.4, 0.5, 2.4), "steps": [
		[40, {"aim": Vector3(0.0, 0.0, 3.0)}],
		[6, {"shove": true, "aim": Vector3(0.0, 0.0, 3.0)}],
	]},
	{"name": "cross_check_full", "puck": false, "cam": Vector3(0.6, 2.4, 2.6), "steps": [
		[40, {"aim": Vector3(0.0, 0.0, 3.0)}],
		[12, {"shove": true, "aim": Vector3(0.0, 0.0, 3.0)}],
	]},
	# Thrown at a cursor 50° off the hips: the chest and the shaft turn to it.
	{"name": "cross_check_aimed", "puck": false, "cam": Vector3(0.6, 2.4, 2.6), "steps": [
		[40, {"aim": Vector3(0.0, 0.0, 3.0)}],
		[12, {"shove": true, "aim": Vector3(2.3, 0.0, 1.93)}],
	]},
	# ── Jersey ──────────────────────────────────────────────────────────────
	# The sweater over the pants: loose, each corner (one from its own front
	# three-quarter, one head-on, where the hem's slope off it reads), all the
	# way in, and a corner from behind, where its lifted hem must show. Then the drape under
	# the two things that move it most — the stance's fold, side-on, where the
	# front must bunch over the pants rather than sink into them, and a stride.
	# A skater at rest faces +Z, so the wearer's right is world −X.
	{"name": "jersey_loose", "puck": false, "cam": Vector3(0.0, 0.2, 2.0),
		"cam_aim": Vector3(0.0, -0.1, 0.0), "steps": [[40, {"aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_tuck_left", "puck": false, "tuck": GearModelRegistry.TUCK_LEFT,
		"cam": Vector3(1.2, 0.2, 1.6), "cam_aim": Vector3(0.0, -0.1, 0.0),
		"steps": [[40, {"aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_tuck_full", "puck": false, "tuck": GearModelRegistry.TUCK_FULL,
		"cam": Vector3(0.0, 0.2, 2.0), "cam_aim": Vector3(0.0, -0.1, 0.0),
		"steps": [[40, {"aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_tuck_right", "puck": false, "tuck": GearModelRegistry.TUCK_RIGHT,
		"cam": Vector3(0.0, 0.2, 2.0), "cam_aim": Vector3(0.0, -0.1, 0.0),
		"steps": [[40, {"aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_tuck_right_rear", "puck": false, "tuck": GearModelRegistry.TUCK_RIGHT,
		"cam": Vector3(-1.2, 0.2, -1.6), "cam_aim": Vector3(0.0, -0.1, 0.0),
		"steps": [[40, {"aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_fold_loose", "puck": false, "cam": Vector3(2.6, 0.1, 0.4),
		"steps": [[40, {"stance": true, "aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_fold_tucked", "puck": false, "tuck": GearModelRegistry.TUCK_RIGHT,
		"cam": Vector3(2.6, 0.1, 0.4),
		"steps": [[40, {"stance": true, "aim": Vector3(0.0, 0.0, 3.0)}]]},
	{"name": "jersey_stride_loose", "puck": false, "cam": Vector3(2.6, 0.1, 0.0),
		"steps": [[64, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}]]},
	# ── Dive ────────────────────────────────────────────────────────────────
	# Stance + block out of a skate: down and sliding on, laid out across the
	# line of travel toward the cursor, stick along the ice. Mid-slide.
	{"name": "dive", "puck": false, "game_cam": true, "steps": [
		[120, {"move": Vector2(0.0, -1.0), "aim": Vector3(0.0, 0.0, -3.0)}],
		[40, {"stance": true, "block": true, "aim": Vector3(2.5, 0.0, -1.0)}],
	]},
	# ── Knockdown ───────────────────────────────────────────────────────────
	# A hit hard enough to put the skater down, mid-fall and lying, shoved to
	# the side and backward. These are the tiles that show where the fall
	# pivots: a body lying a hip-height above the ice, or one sunk through it,
	# is a proportion no display-less test catches.
	{"name": "knockdown_mid_fall", "puck": false, "knockdown": Vector3(3.0, 0.0, 0.0),
		"cam": Vector3(0.6, -0.2, 3.4), "cam_aim": Vector3(0.6, -0.5, 0.0),
		"steps": [[30, {}]]},
	{"name": "knockdown_lying_side", "puck": false, "knockdown": Vector3(3.0, 0.0, 0.0),
		"cam": Vector3(0.9, -0.45, 2.6), "cam_aim": Vector3(0.9, -0.95, 0.0),
		"steps": [[100, {}]]},
	{"name": "knockdown_lying_back", "puck": false, "knockdown": Vector3(0.0, 0.0, 3.0),
		"cam": Vector3(2.6, -0.45, 0.9), "cam_aim": Vector3(0.0, -0.95, 0.9),
		"steps": [[100, {}]]},
	# ── FACEOFF_PREP ──────────────────────────────────────────────────────────
	# The locked-phase path (begin_approach → tick_faceoff_approach →
	# apply_blade_aim_only), which _process_input never reaches, so the specs
	# above cover none of it. `faceoff` names the walk-in; `hold` is the ticks
	# spent set at the dot afterwards.
	#
	# Mid-walk-in: the stride the players skate to the dot on.
	{"name": "faceoff_walkin", "puck": false, "faceoff": {
		"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 90, "hold": 0,
	}},
	# Set at the dot: the winger's ready stance, then the centre's crouch over
	# the dot. Both hold well past every ease so the tile is the settled pose.
	{"name": "faceoff_winger", "puck": false, "faceoff": {
		"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
	}},
	{"name": "faceoff_center", "puck": false, "cam": Vector3(3.1, 0.5, 0.2),
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
			"center": true,
		}},
	# Head-on, because the address's base is a front-view read: from the side the
	# two skates overlap, so a leg splayed out reads the same as one staggered
	# back, and whether the ankles put both blades flat cannot be seen at all.
	{"name": "faceoff_center_front", "puck": false, "cam": Vector3(0.2, 0.75, -3.0),
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
			"center": true,
		}},
	{"name": "faceoff_center_rear", "puck": false, "cam": Vector3(0.35, 0.30, 1.15),
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
			"center": true,
		}},
	# The same address, and a plain stride, from the seat the game is played
	# from. Two tiles rather than one because the question they answer is
	# comparative: the centre is supposed to look like a different pose from up
	# there, not just a skater standing near a dot.
	{"name": "faceoff_center_game", "puck": false, "game_cam": true,
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
			"center": true,
		}},
	{"name": "faceoff_winger_game", "puck": false, "game_cam": true,
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
		}},
	# A blocker caught by the whistle: the shot-block stance must not ride
	# through the walk-in (the state machine is not dispatched while locked).
	{"name": "faceoff_after_block", "puck": false,
		"steps": [[30, {"block": true, "aim": Vector3(0.0, 0.0, -3.0)}]],
		"faceoff": {
			"from": Vector3(-1.5, 0.0, 7.0), "duration": 1.4, "ticks": 168, "hold": 90,
		}},
]


# Minimal stand-in for the game-state Node SkaterController takes; it only ever
# asks these two questions. Same stub the control micro-benchmark uses.
class StubGameState extends Node:
	# Flipped by the faceoff poses, which need the locked phase the skate-in and
	# the ready stance are gated on.
	var faceoff_prep: bool = false

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return faceoff_prep

	func is_faceoff_prep() -> bool:
		return faceoff_prep


var _camera: Camera3D = null
var _state: StubGameState = null
var _skater_scene: PackedScene = null
var _puck_scene: PackedScene = null
var _record_baseline: bool = false
# POSES, or the subset named by --only=<substring> (iterating on one pose should
# not cost a full set — software rasterisation makes every tile expensive).
var _poses: Array = []
var _pose_index: int = -1
var _posed: bool = false
var _images: Array[Image] = []
var _skater: Skater = null
var _controller: SkaterController = null
var _puck: Puck = null


func begin(record_baseline: bool, only: String = "") -> void:
	# Every frame posed, whatever Animation Detail the local prefs carry.
	SkaterAnimationLod.detail = SkaterAnimationLod.DETAIL_FULL
	_record_baseline = record_baseline
	# Every pose is framed by moving the camera AFTER its ticks, so while it is
	# posed the camera still frames the last one; the off-camera cull would skip
	# the rig of any pose placed away from there and the tile would draw it unposed.
	SkaterCameraCull.enabled = false
	_poses = POSES.filter(func(p: Dictionary) -> bool:
			return only == "" or String(p["name"]).contains(only))
	if _poses.is_empty():
		push_error("no pose matches --only=%s" % only)
		_poses = POSES
	CosmeticFreeze.vfx = true
	CosmeticFreeze.hud = true
	_skater_scene = load("res://Scenes/Skater.tscn")
	_puck_scene = load("res://Scenes/Puck.tscn")
	_state = StubGameState.new()
	add_child(_state)
	_build_stage()


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	env.environment = e
	add_child(env)

	_camera = Camera3D.new()
	# Every pose runs its whole tick list inside one engine frame, so an
	# interpolated transform is drawn somewhere back along the path it just
	# covered — and the camera and the body land in different places along it,
	# which frames each tile differently. Nothing here wants interpolation:
	# the pose IS the settled transform.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = CAM_FOV
	_camera.position = CAM_OFFSET
	add_child(_camera)
	_camera.look_at(CAM_AIM, Vector3.UP)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.60, 0.66)
	floor_mesh.material_override = fm
	add_child(floor_mesh)


func _process(_delta: float) -> void:
	# Three-beat cycle per pose: build the actor, run its ticks (the frame that
	# renders the pose), then grab the image. get_texture() returns the LAST
	# PRESENTED frame, so the capture has to be a frame behind the posing.
	if _posed:
		_posed = false
		_images.append(get_viewport().get_texture().get_image())
		_teardown()
		return
	if _skater != null:
		_run_pose()
		_posed = true
		return
	_pose_index += 1
	if _pose_index >= _poses.size():
		_finish()
		return
	_build_actor()


func _build_actor() -> void:
	_puck = _puck_scene.instantiate() as Puck
	add_child(_puck)
	# The puck is required by setup() and by the carry / shot paths, but nothing
	# here simulates puck physics — a released shot would otherwise fly it
	# through the frame at a position set by how many ticks it lived.
	_puck.visible = false
	_puck.set_physics_process(false)
	_puck.set_process(false)

	_skater = _skater_scene.instantiate() as Skater
	_skater.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_skater)
	_skater.global_position = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	# Driven by hand at a fixed DT. See the determinism note in the header.
	_skater.set_process(false)
	_skater.set_physics_process(false)

	var attrs := PlayerAttributes.new(BUILD_HEIGHT_IN, BUILD_WEIGHT_LB, 1, 1, 1, 1)
	var gear := GearStyleConfig.new()
	gear.jersey_tuck = int((_poses[_pose_index] as Dictionary).get("tuck",
			GearModelRegistry.TUCK_NONE))
	_skater.set_gear_style(gear)
	# Blueberry's home kit, deliberately: these tiles are read for where one
	# piece of the body ends and the next begins, and that needs a jersey, a
	# pair of pants and a stripe on them that are all told apart at 384 px.
	# Slot 1's kit is one green — under it a seat, a hip and a thigh are one
	# silhouette, and a pose that lost its pelvis would look exactly like a
	# pose that kept it.
	_skater.set_uniform(TeamColorRegistry.get_colors(5, 0))
	_skater.set_jersey_info("POSE", 8)
	_skater.apply_appearance(attrs)
	# The overhead self-beacon is chrome the camera can pass straight through,
	# and the tiles are for the body.
	_skater.set_world_hud_hidden(true)

	_controller = SkaterController.new()
	add_child(_controller)
	_controller.setup(_skater, _puck, _state)
	_controller.apply_attributes(attrs)


func _teardown() -> void:
	_controller.queue_free()
	_skater.queue_free()
	_puck.queue_free()
	_controller = null
	_skater = null
	_puck = null


func _run_pose() -> void:
	var pose: Dictionary = _poses[_pose_index]
	if bool(pose.get("puck", false)):
		_puck.set_carrier(_skater)
		_controller.on_puck_picked_up_network()

	var input := InputState.new()
	_state.faceoff_prep = false
	if pose.has("knockdown"):
		_controller._on_body_check_received(pose["knockdown"] as Vector3)
	if pose.has("pin_role"):
		_place_for_pin(int(pose["pin_role"]))
	var steps: Array = pose.get("steps", [])
	for step: Array in steps:
		var ticks: int = step[0]
		var spec: Dictionary = step[1]
		if spec.has("face"):
			var face: Vector3 = spec["face"]
			_controller._pose.facing = Vector2(face.x, face.z).normalized()
			_skater.set_facing(_controller._pose.facing)
		for t: int in ticks:
			_fill_input(input, spec, t == 0)
			# Same order as a live tick: the controller runs at physics priority
			# -1, ahead of the skater's own integration, and the cosmetic rig
			# rebuild is the render pass that follows.
			_controller._process_input(input, DT)
			_skater._physics_process(DT)
			_skater._process(DT)
			if pose.has("trace") and t % int(pose["trace"]) == 0:
				_print_trace()
			_track_reach()
	if bool(pose.get("readout", false)):
		var v: Vector3 = _skater.velocity
		print("  %s: speed %.2f heading %.0f° | lower body pitch %.1f° yaw %.1f° roll %.1f° | upper body pitch %.1f° roll %.1f°" % [
				String(pose["name"]), Vector2(v.x, v.z).length(), rad_to_deg(atan2(v.x, -v.z)),
				_skater.lower_body.rotation_degrees.x, _skater.lower_body.rotation_degrees.y,
				_skater.lower_body.rotation_degrees.z, _skater.upper_body.rotation_degrees.x,
				_skater.upper_body.rotation_degrees.z])
		print("    gait: balance lean %.1f° trunk pitch %.1f° roll %.1f° | leg roll L %.1f° R %.1f° | drop %.3f m" % [
				rad_to_deg(_skater.balance_tilt().length()),
				rad_to_deg(_controller._skating.trunk_pitch_add),
				rad_to_deg(_controller._skating.trunk_roll_add),
				rad_to_deg(_skater._legs._gait_leg_l.z), rad_to_deg(_skater._legs._gait_leg_r.z),
				_controller._skating.crouch_drop])
		var arm: float = _skater.upper_arm_length + _skater.forearm_length
		for pair: Array in [["top", _skater.shoulder, _skater.top_hand],
				["bottom", _skater.bottom_shoulder, _skater.bottom_hand]]:
			var hand_local: Vector3 = (pair[2] as Node3D).position
			var root: Vector3 = _skater._arms.arm_root((pair[1] as Node3D).position, hand_local)
			print("    %s arm reach %.2f" % [pair[0],
					root.distance_to(_skater.upper_body.transform * hand_local) / arm])
		if _controller.get_shot_state() == SkaterStateMachine.State.WRISTER_AIM:
			var pin: Vector3 = _controller._aiming.wrister_origin_world \
					- _controller._aiming.wrister_origin_skater_pos
			var puck_local: Vector3 = _skater.global_transform.basis.inverse() * pin
			print("    wrister: load %.2f %s | puck %.0f° off facing | wound %.0f°, torso %.0f°" % [
					_controller.wrister_load.load_share,
					"BH" if _controller.wrister_load.is_backhand else "FH",
					rad_to_deg(atan2(-puck_local.x, -puck_local.z)),
					rad_to_deg(_controller.wrister_load.wound_yaw),
					_skater.upper_body.rotation_degrees.y])
	if pose.has("faceoff"):
		_run_faceoff(pose["faceoff"] as Dictionary)
	print("  %s reach: worst %.2f of arm length (frame %.2f)" % [
			String(pose["name"]), _reach_worst, _reach_worst_frame])
	_reach_worst = 0.0
	_reach_worst_frame = 0.0
	# `game_cam` shoots the pose the way the PLAYER sees it; `cam` re-shoots it
	# from somewhere the chase rig can't. The centre's address needs the second:
	# he faces straight down his own stick, so from behind the shaft is a dot and
	# the fold is a silhouette.
	if bool(pose.get("game_cam", false)):
		_frame_as_the_game_does()
		return
	_camera.fov = CAM_FOV
	var offset: Vector3 = pose.get("cam", CAM_OFFSET)
	# `cam_ahead` looks back down the line of travel, which is the only view a
	# turn's lean reads from — side-on, a bank is a foreshortened tilt.
	var v_flat: Vector3 = Vector3(_skater.velocity.x, 0.0, _skater.velocity.z)
	if pose.has("cam_ahead") and v_flat.length() > 0.1:
		offset = v_flat.normalized() * float(pose["cam_ahead"]) + Vector3(0.0, 0.3, 0.0)
	if pose.has("cam_hand"):
		var hand_node: Node3D = _skater.top_hand if pose["cam_hand"] == "top" else _skater.bottom_hand
		var hand_world: Vector3 = hand_node.global_position
		_camera.fov = CAM_HAND_FOV
		_camera.global_position = hand_world + offset
		_camera.look_at(hand_world, Vector3.UP)
		return
	_camera.global_position = _skater.global_position + offset
	_camera.look_at(_skater.global_position + pose.get("cam_aim", CAM_AIM), Vector3.UP)


var _reach_worst: float = 0.0
var _reach_worst_frame: float = 0.0


# How far each arm has to stretch, as a fraction of its length: from where the
# rig roots it (the visible shoulder, plus the girdle's give), and (for
# comparison) from the shoulder on the gameplay frame. Over 1.0 is an arm the
# rig draws stretched.
func _track_reach() -> void:
	var arm: float = _skater.upper_arm_length + _skater.forearm_length
	for pair: Array in [[_skater.shoulder, _skater.top_hand],
			[_skater.bottom_shoulder, _skater.bottom_hand]]:
		var marker: Vector3 = (pair[0] as Node3D).position
		var hand_local: Vector3 = (pair[1] as Node3D).position
		var hand: Vector3 = _skater.upper_body.transform * hand_local
		var visible: Vector3 = _skater._arms.arm_root(marker, hand_local)
		var frame: Vector3 = _skater.upper_body.transform * _skater._arms._textured_shoulder(marker)
		_reach_worst = maxf(_reach_worst, visible.distance_to(hand) / arm)
		_reach_worst_frame = maxf(_reach_worst_frame, frame.distance_to(hand) / arm)


# One line of where the body's segments sit ACROSS the line of travel, metres
# (+ = travel's right): head over pelvis is the trunk's lean, pelvis over the
# hip joints is the seam between the two skeletons, hips over skates the legs'.
func _print_trace() -> void:
	var v: Vector3 = _skater.global_transform.basis.inverse() * _skater.velocity
	var flat: Vector3 = Vector3(v.x, 0.0, v.z)
	if flat.length() < 0.1:
		return
	var right: Vector3 = flat.normalized().cross(Vector3.UP)
	# Everything in the skater's own frame: the global chain is stale under a
	# hand-ticked harness (interpolation never advances).
	var body: Skeleton3D = _skater._arms._skeleton
	var off: int = SkaterBodySkeleton.LEG_BONE_OFFSET
	var head: Vector3 = body.get_bone_global_pose(SkaterMeshBuilder.UpperBone.HELMET).origin
	var pelvis: Vector3 = body.get_bone_global_pose(SkaterMeshBuilder.UpperBone.PELVIS).origin
	var hips: Vector3 = (body.get_bone_global_pose(off + SkaterMeshBuilder.LegBone.LEG_L).origin
			+ body.get_bone_global_pose(off + SkaterMeshBuilder.LegBone.LEG_R).origin) * 0.5
	var feet: Vector3 = (body.get_bone_global_pose(off + SkaterMeshBuilder.LegBone.FOOT_L).origin
			+ body.get_bone_global_pose(off + SkaterMeshBuilder.LegBone.FOOT_R).origin) * 0.5
	print("    face %+.0f° v %.1f | head-pelvis %+.2f  pelvis-hips %+.2f fwd %+.2f  hips-feet %+.2f | ub yaw %+.0f° pitch %+.0f° roll %+.0f° lb yaw %+.0f° | trunk p %+.0f° r %+.0f° | xover %.2f stride %.2f glide %.2f" % [
			_skater.rotation_degrees.y, flat.length(), (head - pelvis).dot(right), (pelvis - hips).dot(right),
			(pelvis - hips).dot(flat.normalized()), (hips - feet).dot(right),
			_skater.upper_body.rotation_degrees.y, _skater.upper_body.rotation_degrees.x,
			_skater.upper_body.rotation_degrees.z, _skater.lower_body.rotation_degrees.y,
			rad_to_deg(_controller._skating.trunk_pitch_add),
			rad_to_deg(_controller._skating.trunk_roll_add), _controller._skating.locomotion_mix().crossover,
			_controller._skating.locomotion_mix().stride, _controller._skating.locomotion_mix().glide])


# The live game's own framing, so a tile can answer the question the beauty
# shots cannot: does the pose read from where it is actually played? Which for
# a hockey game is high, tilted and some way off — a fold that is unmistakable
# from a metre away is a few dozen pixels of shoulder from up there.
#
# Geometry straight out of GameCamera Step 5a/5b: pitch is −tilt, and the rig
# is pushed BACK by height·tan(90° − tilt) so the tilt lands the subject in the
# middle of the frame rather than at its top. Tilt, height and FOV come from the
# prefs and the camera itself rather than being copied here, so a change to any
# of them turns up in these tiles instead of leaving them rendering a camera the
# game stopped having. Height is the on-puck FLOOR (GameCamera zooms out from
# there as the play spreads), which is the closest the game ever gets to a
# skater — anything unreadable here is unreadable in play.
#
# The FOV is the one number NOT taken as-is. A tile is 384 px and the game's
# frame is the project's full height, so rendering the game's own FOV here
# shrinks the player's whole screen into a thumbnail and tells you nothing about
# how big anything reads. Narrowing it by exactly that ratio instead makes the
# tile a pixel-for-pixel CROP of the middle of the player's frame: same camera,
# same perspective, same on-screen size — just less of the rink around him.
func _frame_as_the_game_does() -> void:
	var probe := GameCamera.new()
	var height: float = probe.min_height * PlayerPrefs.camera_distance
	probe.free()
	var tilt: float = PlayerPrefs.camera_tilt_deg
	var frame_px: float = float(ProjectSettings.get_setting(
			"display/window/size/viewport_height", TILE))
	_camera.fov = rad_to_deg(2.0 * atan(
			tan(deg_to_rad(PlayerPrefs.fov) * 0.5) * float(TILE) / maxf(frame_px, 1.0)))
	_camera.global_position = _skater.global_position + Vector3(
			0.0, height, height * tan(deg_to_rad(90.0 - tilt)))
	_camera.rotation_degrees = Vector3(-tilt, 0.0, 0.0)


# FACEOFF_PREP, driven through the same two entry points a locked tick uses:
# tick_faceoff_approach while the skate-in is live, apply_blade_aim_only once it
# has handed back. `ticks` is the whole prep window (the walk-in plus however
# much of the countdown it should run into); `hold` extends it after arrival, so
# a spec can frame either the stride or the settled stance.
#
# The skater always ENDS on the tile's origin so the fixed camera frames every
# pose alike; the dot is placed relative to him instead — a centre's own reach
# ahead of him, a winger's several metres off — because where the stick is
# pointed is half of what these tiles are for.
func _run_faceoff(spec: Dictionary) -> void:
	var target: Vector3 = Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	var start: Vector3 = target + (spec.get("from", Vector3.ZERO) as Vector3)
	var facing := Vector2(0.0, -1.0)
	var is_center: bool = bool(spec.get("center", false))
	_state.faceoff_prep = true
	_skater.is_faceoff_center = is_center
	var default_dot: Vector3 = Vector3(0.0, 0.0, -_controller.faceoff_center_distance()) \
			if is_center else Vector3(1.4, 0.0, -1.6)
	var dot: Vector3 = target + (spec.get("dot", default_dot) as Vector3)
	dot.y = 0.0
	_controller.begin_approach(
			start, target, facing, float(spec.get("duration", 1.4)))
	var input := InputState.new()
	var ticks: int = int(spec.get("ticks", 168)) + int(spec.get("hold", 0))
	for _t: int in ticks:
		input.delta = DT
		input.host_timestamp += DT
		# Everyone watches the dot through the countdown, and the blade IK aims
		# the stick at whatever the head is on.
		input.mouse_world_pos = dot
		if not _controller.tick_faceoff_approach(DT):
			_controller.apply_blade_aim_only(input, DT)
		_skater._physics_process(DT)
		_skater._process(DT)
		_track_reach()
	# Numbers a 384 px tile can't be read for: how far off the dot the body
	# settled, how deep the crouch went, and whether the hips came square.
	print("  %s: pos %.3v crouch %.3f hips %.1f° skates %.3f/%.3f" % [
			"centre" if is_center else "winger", _skater.global_position,
			_skater._skating_crouch_drop,
			rad_to_deg(_skater.lower_body.rotation.y),
			_skater.blade_mark_position(true).y,
			_skater.blade_mark_position(false).y])
	print("      dot %.3v stick_horiz %.3f blade %.3v" % [
			dot, _controller._ik.stick_horiz(),
			_skater.upper_body_to_global(_skater.get_blade_position())])


# Against the +x boards as the role stands there: the pinned skater's edge at the
# boards, the pinner one body and the lock's give further off.
func _place_for_pin(role: int) -> void:
	var r: float = _skater.collision_radius()
	var gap: float = 0.05
	if role == BoardPinRules.Role.PINNER:
		gap += 2.0 * r + BoardPinRules.PIN_CONTACT_SLACK_M
	_skater.global_position = Vector3(GameRules.INNER_HALF_WIDTH - r - gap,
			GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	_skater.pin_role = role
	_skater.pin_strength = 0.5


func _fill_input(input: InputState, spec: Dictionary, first: bool) -> void:
	var aim: Vector3 = spec.get("aim", Vector3(0.0, 0.0, -3.0))
	var move: Vector2 = spec.get("move", Vector2.ZERO)
	var shoot: bool = spec.get("shoot", false)
	var slap: bool = spec.get("slap", false)
	var deflect: bool = spec.get("deflect", false)
	input.delta = DT
	input.host_timestamp += DT
	input.move_vector = move
	input.mouse_world_pos = _skater.global_position + aim
	input.stance_held = spec.get("stance", false)
	var shove: bool = spec.get("shove", false)
	input.hit_held = spec.get("hit", false) or shove
	input.brake = spec.get("brake", false)
	input.block_held = spec.get("block", false)
	input.elevation_level = spec.get("loft", 0)
	input.shoot_held = shoot
	input.shoot_pressed = shoot and first
	input.slap_held = slap
	input.slap_pressed = slap and first
	input.stick_lift_held = deflect
	input.stick_lift_pressed = deflect and first
	var stick: bool = spec.get("stick", false)
	input.stick_check_held = stick
	input.stick_check_pressed = (stick or shove) and first


func _finish() -> void:
	var dir: String = BASELINE_DIR if _record_baseline else CURRENT_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for i: int in _poses.size():
		_images[i].save_png("%s/%s.png" % [dir, String(_poses[i]["name"])])
	var label: String = "baseline" if _record_baseline else "current"
	print("saved %d %s tiles to %s"
			% [_poses.size(), label, ProjectSettings.globalize_path(dir)])
	_save_sheet(_images, "%s/sheet.png" % OUT_DIR)
	if not _record_baseline:
		_diff_against_baseline()
	get_tree().quit()


# Lays the tiles out in a grid so the whole set is one glance. The legend goes to
# stdout rather than being drawn in — an Image has no text, and adding a font
# pass would put non-rig pixels into the thing being diffed.
func _save_sheet(images: Array[Image], path: String) -> void:
	var rows: int = int(ceil(float(images.size()) / float(SHEET_COLS)))
	var sheet := Image.create_empty(SHEET_COLS * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	for i: int in images.size():
		var src: Image = images[i]
		src.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		var row: int = i / SHEET_COLS
		sheet.blit_rect(src, Rect2i(0, 0, TILE, TILE),
				Vector2i((i % SHEET_COLS) * TILE, row * TILE))
	sheet.save_png(path)
	print("sheet: ", ProjectSettings.globalize_path(path))
	for i: int in _poses.size():
		@warning_ignore("integer_division")
		var row: int = i / SHEET_COLS
		print("  [%d,%d] %s" % [row, i % SHEET_COLS, String(_poses[i]["name"])])


func _diff_against_baseline() -> void:
	var missing: int = 0
	var changed_poses: int = 0
	var overlays: Array[Image] = []
	print("")
	print("── Pose diff vs baseline (tolerance %d/255) ──" % DIFF_TOLERANCE)
	for i: int in _poses.size():
		var pose_name: String = String(_poses[i]["name"])
		var baseline: Image = Image.load_from_file("%s/%s.png" % [BASELINE_DIR, pose_name])
		if baseline == null:
			print("  %-24s NO BASELINE" % pose_name)
			missing += 1
			overlays.append(_images[i])
			continue
		var report: Dictionary = ImageDiff.compare(baseline, _images[i], DIFF_TOLERANCE)
		overlays.append(report["overlay"])
		var count: int = report["count"]
		if count == 0:
			print("  %-24s clean" % pose_name)
			continue
		changed_poses += 1
		var box: Rect2i = report["box"]
		print("  %-24s %6d px changed, worst delta %3d, box %dx%d at (%d,%d)"
				% [pose_name, count, int(report["worst"]), box.size.x, box.size.y,
				box.position.x, box.position.y])
	if missing > 0:
		print("  (%d pose(s) have no baseline — run with --baseline first)" % missing)
	if changed_poses == 0 and missing == 0:
		print("  all %d poses identical" % _poses.size())
	_save_sheet(overlays, "%s/diff.png" % OUT_DIR)


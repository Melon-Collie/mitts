class_name TopHandIK

# Pure top-hand inverse kinematics. Given a desired blade target in
# upper-body-local XZ space and a fixed stick length, produces the hand and
# blade positions such that:
#
#   1. |blade − hand| == stick_length in 3D (rigid stick). In the horizontal
#      plane, |blade.xz − hand.xz| == stick_horiz = sqrt(stick_length² −
#      (hand.y − blade.y)²). Variable hand.y adjusts stick_horiz on the fly.
#   2. The hand lies within an asymmetric range-of-motion envelope centered
#      on the shoulder — a half-ellipse, longest straight ahead, short on the
#      forehand (cross-body) side, long on the backhand (same side as the top
#      hand) side.
#   3. When the target is reachable, the blade lands exactly on the target.
#      Unreachable targets fall short (past-ROM) or overshoot (past-hand-Y-
#      ceiling at close range) **along the aim line**, preserving aim
#      direction but clipping distance.
#
# Two regimes (continuous at the boundary r = stick_horiz_at_rest + floor):
#   FAR  (r ≥ stick_horiz_at_rest + floor): hand.y = hand_rest_y; hand
#         displaces in XZ toward target up to ROM; blade sits stick_horiz from
#         clamped hand along the aim line.
#   CLOSE (below it): hand.xz stays its floor (Config.hand_forward) out from
#         the shoulder along the aim; hand.y rises so stick_horiz shrinks to
#         exactly r − floor and the blade lands on target.
#         Clamped by hand_y_max — if the hand can't rise far enough, the
#         stick's min horizontal projection overshoots the target along the
#         aim line.
#
# Blade-first feel: input is treated as a desired blade position, and the
# hand is solved as a consequence. No per-frame smoothing here — caller owns
# any smoothing if desired.
#
# All coordinates are in upper-body-local space.
#
# blade_side_sign: −1.0 for a left-handed shooter (blade lives on −X),
#                  +1.0 for a right-handed shooter (blade lives on +X).
# The shoulder is expected to live on the opposite (top-hand) side.
#
# Returns a Result (hand + blade in upper-body-local space). Callers on the
# per-tick path pass a reused `out` instance to avoid per-solve allocation;
# omitting it allocates a fresh Result (fine for tests / cold paths).

class Config:
	var stick_length: float = 0.0            # rigid stick length (meters)
	var blade_y: float = 0.0                 # fixed local Y for the blade
	var hand_rest_y: float = 0.0             # hand's resting local Y (FAR regime)
	var hand_y_max: float = 0.0              # ceiling the hand may rise to (CLOSE)
	var rom_forehand_angle_max: float = 0.0  # radians; ROM on forehand side
	var rom_backhand_angle_max: float = 0.0  # radians; ROM on backhand side
	var rom_forward_reach_max: float = 0.0   # meters; max hand displacement straight ahead
	var rom_forehand_reach_max: float = 0.0  # meters; max hand displacement across the body
	var rom_backhand_reach_max: float = 0.0  # meters; max hand displacement out to the side
	# Hard cap on the blade's horizontal distance from the shoulder (meters).
	# An obstacle the blade cannot reach past — in practice the boards — makes the
	# reachable region the ROM envelope INTERSECTED with the open ice, and this is
	# that intersection expressed along the current aim line. Capping the DESIRED
	# distance up front routes a wall-limited reach into the CLOSE regime, where
	# the hand rises and the stick's horizontal projection shrinks: the choke-up a
	# real player does when jammed on the boards, rather than a full-reach pose
	# that a post-hoc clamp then has to drag back. INF = unconstrained.
	var max_blade_reach: float = INF
	# The least the hand reaches off its shoulder along the bearing to the blade
	# (meters) once the blade is round the forehand (forward_floor). Without it
	# the CLOSE regime holds the hand at the shoulder, on the backhand side: a
	# stick held round the forehand then runs from the far hip, and the other
	# hand reaches it only across the chest. All of it from
	# `hand_forward_full_angle` round the forehand (forehand-signed, radians),
	# none from `hand_forward_none_angle` back, where a top hand holds its stick
	# at its own side; all of it with the blade `hand_forward_full` off the
	# shoulder, none from `hand_forward_none` in, where pulled tight the hand
	# comes back to the hip.
	var hand_forward: float = 0.0
	var hand_forward_none: float = 0.3
	var hand_forward_full: float = 0.9
	var hand_forward_none_angle: float = deg_to_rad(10.0)
	var hand_forward_full_angle: float = deg_to_rad(55.0)

class Result:
	var hand: Vector3 = Vector3.ZERO
	var blade: Vector3 = Vector3.ZERO

# two_hand_reach's bisection: 2.5 m of reach to under a centimetre.
const _TWO_HAND_BISECTIONS: int = 9
# Half-width of the band about stick_horiz_at_rest over which the hand hands from
# rising over the shoulder (CLOSE) to reaching out at rest height (FAR). Without
# it the hand's path turns a corner there: a blade swept across the body at
# speed kinked the hand from vertical travel to horizontal in one tick.
const REGIME_BAND_M: float = 0.08
# _blade_for_span's fixed point: it contracts by the floor's slope, at most
# ~0.63 at the defaults, so twelve steps take the error under a millimetre.
const _FLOOR_ITERATIONS: int = 12

# Projects a desired blade target onto the reachable blade region (the ROM
# envelope), in upper-body-local space. This is the closed-form clamp — no
# iteration, no hand work — that decides WHERE the blade ends up. solve() builds
# the full hand pose on top of it; callers that only need the resulting blade
# position (e.g. a per-tick speed cap chasing the reachable target) use this
# directly and skip the hand reconstruction. Returns the blade as (x, blade_y, z).
static func project_blade(
		shoulder: Vector3,
		desired_blade_xz: Vector2,
		blade_side_sign: float,
		cfg: Config) -> Vector3:
	var stick_length: float = cfg.stick_length
	var blade_y: float = cfg.blade_y
	var stick_horiz_at_rest: float = _stick_horiz_for(stick_length, cfg.hand_rest_y, blade_y)

	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var delta: Vector2 = desired_blade_xz - shoulder_xz
	var r: float = delta.length()
	var aim_dir: Vector2 = delta / r if r > 0.0001 else Vector2(0.0, -1.0)
	# Obstacle cap (the boards) applied to the desired DISTANCE, before the regime
	# split, so a wall-limited reach flows into the CLOSE branch and chokes up
	# naturally instead of being clamped back out of the FAR branch afterwards.
	r = minf(r, maxf(cfg.max_blade_reach, 0.0))

	# CLOSE regime: target is inside the default stick reach. The hand would
	# rise so the stick tilts more vertically, shortening its horizontal reach
	# to hit the target exactly. If it can't rise far enough (hand_y_max clamp),
	# the blade overshoots along the aim line at the minimum stick_horiz —
	# hand_y_max IS the inner boundary: sqrt(S² − drop²) grows super-linearly
	# with stick length near the vertical limit, so a long stick's blade can't
	# work in tight to the body while a short one plays the phone booth. The
	# AIM is clamped to the same angular ROM the FAR regime enforces — the
	# wrists don't gain articulation because the puck is close; without this
	# clamp a slowly-swept cursor could walk the blade fully behind the body.
	# The hand sits its floor out along the aim (forward_floor), so the stick
	# spans what is left.
	var floor_m: float = forward_floor(r, _to_forehand(aim_dir, blade_side_sign), cfg)
	if r - floor_m < stick_horiz_at_rest:
		aim_dir = _clamp_aim_to_rom(aim_dir, blade_side_sign, cfg)
		var to_forehand: float = _to_forehand(aim_dir, blade_side_sign)
		floor_m = forward_floor(r, to_forehand, cfg)
		var span_min: float = _stick_horiz_for(stick_length, cfg.hand_y_max, blade_y)
		var d: float = r if r - floor_m >= span_min \
				else _blade_for_span(span_min, to_forehand, cfg)
		var close_blade_xz: Vector2 = shoulder_xz + aim_dir * d
		return Vector3(close_blade_xz.x, blade_y, close_blade_xz.y)

	# FAR regime: target is beyond the default stick reach. The hand displaces
	# toward the target in XZ, clamped to asymmetric ROM; the blade sits
	# stick_horiz_at_rest farther along the same (clamped) arm direction. Since
	# hand and blade are colinear from the shoulder, the blade lands at
	# radius + stick_horiz_at_rest along blade_dir — no need to place the hand.
	var disp: Vector2 = aim_dir * (r - stick_horiz_at_rest)

	# Forehand-signed polar: angle > 0 always means "displaced toward forehand
	# side of body" regardless of handedness. The shoulder lives on the
	# top-hand (backhand) side, so for a lefty a +X displacement is toward
	# the backhand side → angle_to_forehand ends up negative.
	var angle_raw: float = atan2(disp.x, -disp.y)
	var angle_to_forehand: float = angle_raw * blade_side_sign
	var radius: float = disp.length()

	# Clamp angle asymmetrically: forehand side is tight, backhand is open.
	angle_to_forehand = clampf(
			angle_to_forehand, -cfg.rom_backhand_angle_max, cfg.rom_forehand_angle_max)

	radius = clampf(radius, 0.0, max_reach_for_angle(angle_to_forehand, cfg))

	# Back to Cartesian. world_angle undoes the forehand-sign flip. Using the
	# clamped world_angle (not hand_to_target) keeps the blade at the ROM limit
	# when the mouse is past it — hand_to_target wraps around as the mouse moves
	# further past the limit, swinging the blade the wrong way.
	var world_angle: float = angle_to_forehand * blade_side_sign
	var blade_dir := Vector2(sin(world_angle), -cos(world_angle))
	var blade_xz: Vector2 = shoulder_xz + blade_dir * (radius + stick_horiz_at_rest)
	return Vector3(blade_xz.x, blade_y, blade_xz.y)

static func solve(
		shoulder: Vector3,
		desired_blade_xz: Vector2,
		blade_side_sign: float,
		cfg: Config,
		out: Result = null) -> Result:
	if out == null:
		out = Result.new()

	# Where the blade lands (closed-form ROM projection).
	var blade: Vector3 = project_blade(shoulder, desired_blade_xz, blade_side_sign, cfg)
	out.blade = blade

	# Reconstruct the hand from the blade. Hand and blade are colinear from the
	# shoulder with a rigid stick, so the blade's distance from the shoulder
	# fully determines the hand — no need to re-derive the clamped angle/regime:
	#   FAR  (d ≥ stick_horiz_at_rest): hand at rest Y, stick_horiz_at_rest
	#         closer to the shoulder along the same direction.
	#   CLOSE (d < stick_horiz_at_rest): hand at the shoulder XZ; its Y is fixed
	#         by the rigid stick (drop = sqrt(stick_length² − d²)). This inverts
	#         exactly even when the close-regime hand_y was clamped, since the
	#         blade distance already reflects the clamped stick_horiz.
	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var from_shoulder: Vector2 = Vector2(blade.x, blade.z) - shoulder_xz
	var d: float = from_shoulder.length()
	var stick_horiz_at_rest: float = _stick_horiz_for(cfg.stick_length, cfg.hand_rest_y, cfg.blade_y)
	var dir: Vector2 = from_shoulder / d if d > 0.0001 else Vector2(0.0, -1.0)
	var reach: float = floored_reach(d, stick_horiz_at_rest,
			_to_forehand(dir, blade_side_sign), cfg)
	var hand_xz: Vector2 = shoulder_xz + dir * reach
	out.hand = Vector3(hand_xz.x, _hand_y_on_stick(d - reach, cfg.stick_length,
			cfg.hand_rest_y, cfg.blade_y, stick_horiz_at_rest), hand_xz.y)
	return out


# How far out from the shoulder the hand sits for a blade `d` off it: the
# floor in close, the reach past the resting stick (`d − rest_horiz`) beyond,
# and a quadratic across REGIME_BAND_M between them, so the hand's path has no
# corner. Past the floor's band it is exactly the floorless reach.
static func floored_reach(d: float, rest_horiz: float, to_forehand: float,
		cfg: Config) -> float:
	var floor_m: float = forward_floor(d, to_forehand, cfg)
	return floor_m + hand_reach(d - floor_m, rest_horiz)


# The hand's least reach for a blade `d` off the shoulder `to_forehand` round
# the forehand (Config.hand_forward). Its slope in `d` stays under 1
# (hand_forward × 1.5 over the band, smoothstep's steepest), so the stick's span
# `d − floor` grows with `d` and a blade distance is found from a span
# (_blade_for_span).
static func forward_floor(d: float, to_forehand: float, cfg: Config) -> float:
	if cfg.hand_forward <= 0.0:
		return 0.0
	return cfg.hand_forward * smoothstep(cfg.hand_forward_none, cfg.hand_forward_full, d) \
			* smoothstep(cfg.hand_forward_none_angle, cfg.hand_forward_full_angle, to_forehand)


# The blade distance off the shoulder whose stick spans `span` across the ice
# past the floored hand: the fixed point of d = span + floor(d).
static func _blade_for_span(span: float, to_forehand: float, cfg: Config) -> float:
	var d: float = span + cfg.hand_forward
	for _i: int in _FLOOR_ITERATIONS:
		d = span + forward_floor(d, to_forehand, cfg)
	return d


# A bearing's angle round the forehand from straight ahead (radians, negative
# toward the backhand), for a skater whose blade lives on `blade_side_sign`.
static func _to_forehand(dir: Vector2, blade_side_sign: float) -> float:
	return atan2(dir.x, -dir.y) * blade_side_sign


# The floorless reach: none in close, the reach past the resting stick beyond.
static func hand_reach(d: float, rest_horiz: float) -> float:
	var x: float = d - rest_horiz
	if x >= REGIME_BAND_M:
		return x
	if x <= -REGIME_BAND_M:
		return 0.0
	return (x + REGIME_BAND_M) * (x + REGIME_BAND_M) / (4.0 * REGIME_BAND_M)


# The hand's height on a rigid stick spanning `horiz` across the ice, exactly
# the rest height where the stick lies at rest (beyond the band, where `horiz`
# is rest_horiz itself).
static func _hand_y_on_stick(horiz: float, stick_length: float, rest_y: float,
		blade_y: float, rest_horiz: float) -> float:
	if horiz >= rest_horiz:
		return rest_y
	return blade_y + sqrt(maxf(stick_length * stick_length - horiz * horiz, 0.0))

# Reconstruct the top hand for a blade position that is AUTHORITATIVE — one an
# obstacle clamp (boards, net, goalie body) has already decided and that the
# caller must not move. Unlike solve(), which is free to place the blade, this
# takes the blade as given and builds the most plausible arm that reaches it.
#
# Something has to yield when the blade is pinned, and the priority is
# anatomical: the blade stays where gameplay put it, the ARM stays inside its
# ROM, and STICK LENGTH is what gives — the hand slides down the shaft, the
# choke-up a real player does when jammed on the boards or reaching around a
# net. Translating the hand rigidly with the blade instead (which preserves
# stick length) is what puts the hand behind the shoulder and folds the elbow
# through the torso, because nothing in that translation is bounded by the arm.
#
# The arm's DIRECTION is deliberately not ROM-clamped, unlike project_blade's:
# the hand has to lie along the shaft toward the blade, and swinging it onto a
# ROM boundary ray would detach the grip from the stick — worse than a stick
# that reads short. Only the reach RADIUS yields, and rom_*_reach_max is derived
# from arm length (SkaterController.apply_attributes), so the result is always
# within anatomical reach.
#
# For a blade that solve() itself placed this is an exact inverse — same hand,
# no discontinuity when a clamp starts or stops biting.
static func hand_for_clamped_blade(
		shoulder: Vector3,
		blade_xz: Vector2,
		blade_y: float,
		blade_side_sign: float,
		cfg: Config) -> Vector3:
	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var from_shoulder: Vector2 = blade_xz - shoulder_xz
	var d: float = from_shoulder.length()
	var stick_horiz_at_rest: float = _stick_horiz_for(cfg.stick_length, cfg.hand_rest_y, blade_y)
	var bearing: Vector2 = from_shoulder / d if d > 0.0001 else Vector2(0.0, -1.0)
	var floor_m: float = forward_floor(d, _to_forehand(bearing, blade_side_sign), cfg)
	var reach: float = floor_m + hand_reach(d - floor_m, stick_horiz_at_rest)
	if reach <= floor_m:
		# CLOSE: the hand comes in to its floor along the bearing and rises,
		# tilting the stick toward vertical. hand_y_max bounds the choke-up; past
		# it the stick simply reads shorter than it is.
		var span: float = d - floor_m
		var drop_sq: float = cfg.stick_length * cfg.stick_length - span * span
		var hand_y: float = minf(blade_y + sqrt(maxf(drop_sq, 0.0)), cfg.hand_y_max)
		var close_xz: Vector2 = shoulder_xz + bearing * floor_m
		return Vector3(close_xz.x, hand_y, close_xz.y)
	var dir: Vector2 = from_shoulder / d
	var angle_to_forehand: float = clampf(
			atan2(dir.x, -dir.y) * blade_side_sign,
			-cfg.rom_backhand_angle_max, cfg.rom_forehand_angle_max)
	var held: float = minf(reach, max_reach_for_angle(angle_to_forehand, cfg))
	var hand_xz: Vector2 = shoulder_xz + dir * held
	return Vector3(hand_xz.x, minf(_hand_y_on_stick(d - reach, cfg.stick_length,
			cfg.hand_rest_y, blade_y, stick_horiz_at_rest), cfg.hand_y_max), hand_xz.y)

# Enforce the one thing in the chain that has no give: the stick's LENGTH. Takes
# a pose whose hand and blade have drifted more than a stick apart — an authored
# shot finish that reaches past the arm, or a blade an obstacle clamp has just
# moved — and closes the gap along the shaft, filling `out`.
#
# Same anatomical priority the rest of this file keeps, with the stick moved to
# the bottom of it where a rigid object belongs. The HAND yields first: it slides
# down the shaft toward the blade, bounded by the arm's own reach (and by
# hand_y_max on the way up), because a player reaching through a finish extends
# the arm before anything else. Only what the arm cannot cover comes off the
# BLADE, which falls short along the same line — the finish simply doesn't get
# there, exactly as it wouldn't with a real stick.
#
# A pose already within a stick-length is returned untouched, so this is inert on
# every pose that was authored honestly, and never lengthens a shaft that reads
# short (the choke-up is legitimate and stays).
static func enforce_rigid_stick(
		shoulder: Vector3,
		hand: Vector3,
		blade: Vector3,
		blade_side_sign: float,
		cfg: Config,
		out: Result) -> void:
	out.hand = hand
	out.blade = blade
	var to_blade: Vector3 = blade - hand
	var span: float = to_blade.length()
	var over: float = span - cfg.stick_length
	if over <= 0.0 or span < 0.000001:
		return
	var dir: Vector3 = to_blade / span
	# How far the hand may slide before it leaves the arm. ROM is a HORIZONTAL
	# displacement from the shoulder, so the limit is where the sliding hand's
	# ground track leaves that disc — a ray/circle hit, with a purely vertical
	# slide (a near-upright shaft) unconstrained by it.
	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var hand_xz := Vector2(hand.x, hand.z)
	var dir_xz := Vector2(dir.x, dir.z)
	var arm_xz: Vector2 = hand_xz - shoulder_xz
	var reach_max: float = max_reach_for_angle(
			_arm_angle_to_forehand(arm_xz, Vector2(blade.x, blade.z) - shoulder_xz,
					blade_side_sign),
			cfg)
	var slide: float = over
	var a: float = dir_xz.length_squared()
	if a > 0.000001:
		var b: float = 2.0 * arm_xz.dot(dir_xz)
		var c: float = arm_xz.length_squared() - reach_max * reach_max
		var disc: float = b * b - 4.0 * a * c
		# From inside the disc there is always a root, so no real root means the
		# arm is ALREADY at or past its reach — which is exactly what the finish
		# poses author — and sliding further along the shaft only takes it further
		# out. The hand cannot help there, so it stays and the blade pays it all.
		var limit: float = ((-b + sqrt(disc)) / (2.0 * a)) if disc > 0.0 else 0.0
		slide = clampf(minf(slide, limit), 0.0, over)
	if dir.y > 0.000001:
		# Sliding up the shaft toward a raised blade: the same ceiling the CLOSE
		# regime uses stops the hand from climbing out of the body.
		slide = minf(slide, maxf((cfg.hand_y_max - hand.y) / dir.y, 0.0))
	out.hand = hand + dir * slide
	out.blade = blade - dir * (over - slide)


# Forehand-signed arm angle for the ROM lookup, taken from the hand's own bearing
# off the shoulder and falling back to the blade's when the hand sits on top of it
# (the CLOSE poses, where the arm has no bearing of its own).
static func _arm_angle_to_forehand(
		arm_xz: Vector2, blade_from_shoulder: Vector2, blade_side_sign: float) -> float:
	var bearing: Vector2 = arm_xz if arm_xz.length_squared() > 0.000001 else blade_from_shoulder
	if bearing.length_squared() < 0.000001:
		return 0.0
	return atan2(bearing.x, -bearing.y) * blade_side_sign


# The farthest along the aim to `desired_blade_xz` the blade may sit, as a
# max_blade_reach (horizontal distance from `shoulder`), with the other hand
# still able to hold the shaft: some point of it within `bottom_reach` of
# `bottom_shoulder` and `spacing` clear of the top hand
# (BottomHandIK.reachable_grip). INF when the target itself is
# held. Along one aim the solve only carries the shaft farther from the body as
# the cap grows, so the answer is bisected; the target pose is tried first, and
# carrying inside the two-handed rim costs that one solve. Leaves
# cfg.max_blade_reach as it found it; `scratch` is overwritten.
static func two_hand_reach(shoulder: Vector3, desired_blade_xz: Vector2,
		blade_side_sign: float, cfg: Config, bottom_shoulder: Vector3, grip: float,
		bottom_reach: float, spacing: float, scratch: Result) -> float:
	solve(shoulder, desired_blade_xz, blade_side_sign, cfg, scratch)
	if BottomHandIK.reachable_grip(bottom_shoulder, scratch.hand, scratch.blade,
			grip, bottom_reach, spacing).y <= 0.0:
		return INF
	var cap: float = cfg.max_blade_reach
	var lo: float = 0.0
	var hi: float = Vector2(scratch.blade.x - shoulder.x, scratch.blade.z - shoulder.z).length()
	for _i: int in _TWO_HAND_BISECTIONS:
		var mid: float = (lo + hi) * 0.5
		cfg.max_blade_reach = mid
		solve(shoulder, desired_blade_xz, blade_side_sign, cfg, scratch)
		if BottomHandIK.reachable_grip(bottom_shoulder, scratch.hand, scratch.blade,
				grip, bottom_reach, spacing).y <= 0.0:
			lo = mid
		else:
			hi = mid
	cfg.max_blade_reach = cap
	return lo


# The farthest a blade's contact point can be from the body origin, the way the
# solve places it (SkaterIKCoordinator._solve_top_hand): the trunk pitched its
# furthest forward (`pitch`), carrying the shoulder forward and down; the hand at
# the forward reach, `hand_drop` straight below that shoulder; the stick down to
# the blade on the ice; the contact `contact_offset` along the blade. Pitching
# further only lowers the hand and flattens the stick, so the deepest pitch is
# the farthest reach. The shoulder's lateral offset is added whole rather than
# across the reach, which is the margin. Heights are above the ice; `shoulder`
# is the marker in the trunk's frame, about its origin at `frame_height`.
static func full_reach(shoulder: Vector3, pitch: float, frame_height: float,
		hand_drop: float, forward_reach: float, stick_length: float,
		blade_height: float, contact_offset: float, body_height: float) -> float:
	var hand_height: float = frame_height + shoulder.y * cos(pitch) - hand_drop
	var rise: float = hand_height - blade_height
	var stick_horiz: float = sqrt(maxf(stick_length * stick_length - rise * rise, 0.0))
	var horiz: float = absf(shoulder.x) + shoulder.y * sin(pitch) + forward_reach \
			+ stick_horiz + contact_offset
	return Vector2(horiz, body_height - blade_height).length()


# Max hand displacement from the shoulder at a forehand-signed arm angle.
static func max_reach_for_angle(angle_to_forehand: float, cfg: Config) -> float:
	return rim_reach(angle_to_forehand, cfg.rom_forward_reach_max,
			cfg.rom_forehand_reach_max, cfg.rom_backhand_reach_max)


# The ROM rim as two quarter-ellipses sharing the forward semi-axis, each with
# its own side's lateral semi-axis: straight ahead the arm reaches with the
# shoulder blade's protraction behind it, across the body the chest stops it,
# and out to the side it extends without the protraction. Both quarters meet
# at `forward` with zero slope, so the rim has no seam at 0. Past 90° (a hand
# carried behind the shoulder) the side's lateral reach holds.
static func rim_reach(angle_to_forehand: float, forward: float, forehand: float,
		backhand: float) -> float:
	var side: float = forehand if angle_to_forehand > 0.0 else backhand
	var c: float = cos(angle_to_forehand)
	if c <= 0.0:
		return side
	var s: float = sin(angle_to_forehand)
	var denom: float = sqrt(side * side * c * c + forward * forward * s * s)
	return forward * side / denom if denom > 0.000001 else 0.0

# Clamp an aim direction (unit, from the shoulder) to the asymmetric angular
# ROM — the same limits the FAR regime applies to the hand displacement.
# Returns the input unchanged when already inside the ROM, else the boundary
# ray on the exceeded side (matching FAR's clamped-world-angle behavior: past
# the limit the blade holds at the boundary rather than wrapping).
static func _clamp_aim_to_rom(aim_dir: Vector2, blade_side_sign: float, cfg: Config) -> Vector2:
	var angle_to_forehand: float = atan2(aim_dir.x, -aim_dir.y) * blade_side_sign
	var clamped: float = clampf(
			angle_to_forehand, -cfg.rom_backhand_angle_max, cfg.rom_forehand_angle_max)
	if clamped == angle_to_forehand:
		return aim_dir
	var world_angle: float = clamped * blade_side_sign
	return Vector2(sin(world_angle), -cos(world_angle))


# Horizontal stick projection at a given hand Y. Clamped to a tiny positive
# value so the solver never divides by zero even at edge cases where the
# stick is nearly vertical.
static func _stick_horiz_for(stick_length: float, hand_y: float, blade_y: float) -> float:
	var drop: float = hand_y - blade_y
	var sq: float = stick_length * stick_length - drop * drop
	return sqrt(maxf(sq, 0.0001))

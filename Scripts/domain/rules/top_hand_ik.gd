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
#      ceiling at close range) **along the aim line from the shoulder**,
#      preserving aim direction but clipping distance.
#
# Where the hand holds the stick when it is not reaching is its PIVOT
# (`pivot_xz`): a point in front of the body, ahead of the shoulder and in toward
# the forehand. Held at the shoulder itself the hand sits beside the hip, and the
# bottom arm then crosses the belly to reach a shaft that starts on the far side
# of the body. As the arm reaches the pivot hands back to the shoulder
# (`pivot_share`), so a reaching arm is solved from the shoulder alone.
#
# Two regimes (continuous at the boundary d = stick_horiz_at_rest, d the
# blade's distance from the shoulder):
#   FAR  (d ≥ stick_horiz_at_rest): hand.y = hand_rest_y; hand displaces in
#         XZ toward target up to ROM; blade sits stick_horiz from clamped
#         hand along the aim line.
#   CLOSE (d < stick_horiz_at_rest): hand.xz stays at the pivot; hand.y rises
#         so the blade lands on target. Clamped by hand_y_max — if the hand
#         can't rise far enough, the blade is pushed out along the aim line to
#         the stick's min horizontal projection off the pivot.
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
	var pivot_forward: float = 0.0           # meters; the pivot ahead of the shoulder
	var pivot_inward: float = 0.0            # meters; the pivot in from the shoulder, toward the forehand
	# Hard cap on the blade's horizontal distance from the shoulder along the aim
	# line (meters).
	# An obstacle the blade cannot reach past — in practice the boards — makes the
	# reachable region the ROM envelope INTERSECTED with the open ice, and this is
	# that intersection expressed along the current aim line. Capping the DESIRED
	# distance up front routes a wall-limited reach into the CLOSE regime, where
	# the hand rises and the stick's horizontal projection shrinks: the choke-up a
	# real player does when jammed on the boards, rather than a full-reach pose
	# that a post-hoc clamp then has to drag back. INF = unconstrained.
	var max_blade_reach: float = INF

class Result:
	var hand: Vector3 = Vector3.ZERO
	var blade: Vector3 = Vector3.ZERO

# two_hand_reach's bisection: 2.5 m of reach to under a centimetre.
const _TWO_HAND_BISECTIONS: int = 9
# How far toward its rim the arm reaches before the pivot has handed back to the
# shoulder: no further than the rim, so an arm at its rim is the shoulder's
# alone, and as far as that so the hand's path through the hand-back stays
# gentle.
const PIVOT_FADE_SHARE: float = 1.0
# Half-width of the band about stick_horiz_at_rest over which the hand hands from
# rising over the shoulder (CLOSE) to reaching out at rest height (FAR). Without
# it the hand's path turns a corner there: a blade swept across the body at
# speed kinked the hand from vertical travel to horizontal in one tick.
const REGIME_BAND_M: float = 0.08
# Slack on which quadrant an arc crossing falls in, so a crossing on an axis is
# owned by both arcs that meet there.
const _ARC_EPS_M: float = 0.000001

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
	# The aim keeps to the angular ROM in both regimes — the wrists don't gain
	# articulation because the puck is close, and past the limit the blade holds
	# at the boundary rather than wrapping round as the cursor goes further.
	aim_dir = _clamp_aim_to_rom(aim_dir, blade_side_sign, cfg)
	var target: Vector2 = shoulder_xz + aim_dir * r

	# CLOSE regime: target is inside the default stick reach. The hand would
	# rise so the stick tilts more vertically, shortening its horizontal reach
	# to hit the target exactly. hand_y_max IS the inner boundary: sqrt(S² −
	# drop²) grows super-linearly with stick length near the vertical limit, so a
	# long stick's blade can't work in tight to the body while a short one plays
	# the phone booth. Inside it the blade goes out along the aim line to the
	# circle that ceiling leaves round the pivot, eased over REGIME_BAND_M so the
	# hand comes up to its ceiling rather than stopping dead on it.
	if r < stick_horiz_at_rest:
		var pivot: Vector2 = pivot_xz(shoulder_xz, blade_side_sign, cfg)
		var min_horiz: float = _stick_horiz_for(stick_length, cfg.hand_y_max, blade_y)
		var w: Vector2 = shoulder_xz - pivot
		var wa: float = w.dot(aim_dir)
		var disc: float = wa * wa - w.length_squared() + min_horiz * min_horiz
		if disc < 0.0 or r <= -wa - sqrt(disc):
			return Vector3(target.x, blade_y, target.y)
		var floor_k: float = -wa + sqrt(disc)
		var out_xz: Vector2 = shoulder_xz + aim_dir * (floor_k + hand_reach(r, floor_k))
		return Vector3(out_xz.x, blade_y, out_xz.y)

	# FAR regime: target is beyond the default stick reach. The hand displaces
	# toward the target in XZ, as far as the rim in its direction; the blade
	# sits stick_horiz_at_rest farther along the same (clamped) aim.
	var radius: float = minf(r - stick_horiz_at_rest,
			max_reach_for_angle(atan2(aim_dir.x, -aim_dir.y) * blade_side_sign, cfg))
	var blade_xz: Vector2 = shoulder_xz + aim_dir * (radius + stick_horiz_at_rest)
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

	# Reconstruct the hand from the blade: the blade's distance from the shoulder
	# fully determines it (hand_xz_for), and its height is the rigid stick's over
	# the span left between them. This inverts exactly even when the close-regime
	# hand_y was clamped, since the blade distance already reflects it.
	var shoulder_xz := Vector2(shoulder.x, shoulder.z)
	var hand_xz: Vector2 = hand_xz_for(shoulder_xz, Vector2(blade.x, blade.z), cfg.blade_y,
			blade_side_sign, cfg)
	out.hand = Vector3(hand_xz.x, _hand_y_on_stick(Vector2(blade.x, blade.z).distance_to(hand_xz),
			cfg.stick_length, cfg.blade_y), hand_xz.y)
	return out


# Where the hand holds the stick when it is not reaching, in the solve's XZ:
# `cfg.pivot_forward` ahead of the shoulder and `cfg.pivot_inward` in toward
# the forehand side.
static func pivot_xz(shoulder_xz: Vector2, blade_side_sign: float, cfg: Config) -> Vector2:
	return pivot_at(shoulder_xz, blade_side_sign, cfg.pivot_forward, cfg.pivot_inward)


static func pivot_at(shoulder_xz: Vector2, blade_side_sign: float, forward: float,
		inward: float) -> Vector2:
	return shoulder_xz + Vector2(blade_side_sign * inward, -forward)


# How much of the pivot's offset the hand keeps at `reach` past the resting
# stick along `dir`: all of it while the stick is held close, none once the arm
# is PIVOT_FADE_SHARE of the way to its rim in that direction, eased so the
# hand's path has no corner.
static func pivot_share(reach: float, dir: Vector2, blade_side_sign: float, cfg: Config) -> float:
	if reach <= 0.0:
		return 1.0
	var rim: float = max_reach_for_angle(clampf(atan2(dir.x, -dir.y) * blade_side_sign,
			-cfg.rom_backhand_angle_max, cfg.rom_forehand_angle_max), cfg)
	return 1.0 - smoothstep(0.0, PIVOT_FADE_SHARE * rim, reach)


# The hand's place in the solve's XZ for a blade at `blade_xz`: out from the
# shoulder toward the blade by its reach past the resting stick (hand_reach),
# offset toward the pivot by its share at that reach (pivot_share, of the rim in
# that direction) — and never much further from the blade than the resting
# stick spans (eased on past it, and short of the stick's whole length), or a
# blade out on the backhand side, away from the pivot, would pull the hand down
# off its rest toward the ice. `blade_y` is the ice's height the stick spans to.
static func hand_xz_for(shoulder_xz: Vector2, blade_xz: Vector2, blade_y: float,
		blade_side_sign: float, cfg: Config) -> Vector2:
	var rest_horiz: float = _stick_horiz_for(cfg.stick_length, cfg.hand_rest_y, blade_y)
	var from_shoulder: Vector2 = blade_xz - shoulder_xz
	var d: float = from_shoulder.length()
	var reach: float = hand_reach(d, rest_horiz)
	var dir: Vector2 = from_shoulder / d if d > 0.0001 else Vector2(0.0, -1.0)
	var share: float = pivot_share(reach, dir, blade_side_sign, cfg)
	var hand: Vector2 = pivot_at(shoulder_xz + dir * reach, blade_side_sign,
			cfg.pivot_forward * share, cfg.pivot_inward * share)
	var to_hand: Vector2 = hand - blade_xz
	var span: float = to_hand.length()
	var band: float = minf(REGIME_BAND_M, (cfg.stick_length - rest_horiz) * 0.5)
	var over: float = span - (rest_horiz + band)
	if over > -band and band > 0.0:
		var eased: float = over if over >= band else (over + band) * (over + band) / (4.0 * band)
		hand = blade_xz + to_hand * ((span - eased) / span)
	return hand


# How far out from the shoulder the hand sits for a blade `d` off it: none in
# close, the reach past the resting stick (`d − rest_horiz`) beyond, and a
# quadratic across REGIME_BAND_M between them, so the hand's path has no corner.
# The same curve eases the blade onto the floor in project_blade.
static func hand_reach(d: float, rest_horiz: float) -> float:
	var x: float = d - rest_horiz
	if x >= REGIME_BAND_M:
		return x
	if x <= -REGIME_BAND_M:
		return 0.0
	return (x + REGIME_BAND_M) * (x + REGIME_BAND_M) / (4.0 * REGIME_BAND_M)


# The hand's height on a rigid stick spanning `horiz` across the ice.
static func _hand_y_on_stick(horiz: float, stick_length: float, blade_y: float) -> float:
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
# that reads short. Only the reach along it yields, and rom_*_reach_max is derived
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
	var rest_horiz: float = _stick_horiz_for(cfg.stick_length, cfg.hand_rest_y, blade_y)
	var reach: float = hand_reach(d, rest_horiz)
	if reach <= 0.0:
		# CLOSE: the hand stays at the pivot and rises, tilting the stick toward
		# vertical. hand_y_max bounds the choke-up; past it the stick simply
		# reads shorter than it is.
		var pivot: Vector2 = pivot_xz(shoulder_xz, blade_side_sign, cfg)
		return Vector3(pivot.x, minf(_hand_y_on_stick(blade_xz.distance_to(pivot),
				cfg.stick_length, blade_y), cfg.hand_y_max), pivot.y)
	var dir: Vector2 = from_shoulder / d
	var angle_to_forehand: float = clampf(
			atan2(dir.x, -dir.y) * blade_side_sign,
			-cfg.rom_backhand_angle_max, cfg.rom_forehand_angle_max)
	var held: float = minf(reach, max_reach_for_angle(angle_to_forehand, cfg))
	# The height is the one the unclamped arm holds it at, and the arm stopping
	# short of it draws the hand back along its reach — out where the pivot has
	# handed back to the shoulder — leaving the stick reading short rather than
	# the hand dropping.
	var free_xz: Vector2 = hand_xz_for(shoulder_xz, blade_xz, blade_y, blade_side_sign, cfg)
	var hand_xz: Vector2 = free_xz - dir * (reach - held)
	return Vector3(hand_xz.x, minf(_hand_y_on_stick(blade_xz.distance_to(free_xz),
			cfg.stick_length, blade_y), cfg.hand_y_max), hand_xz.y)

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


# How far the hand can go from `from` along `dir` before it leaves the ROM rim
# (rim_reach's shape about the shoulder). Both are horizontal and taken from the
# shoulder in the solve's XZ; `from` must lie inside the rim. The rim is two
# quarter-ellipses ahead of the shoulder and, behind it, a half-disc per side
# at that side's reach, so the exit is the nearest crossing of those arcs (and
# of the step between the two half-discs straight behind the shoulder).
static func rim_exit(from: Vector2, dir: Vector2, blade_side_sign: float, cfg: Config) -> float:
	return rim_exit_of(from, dir, blade_side_sign, cfg.rom_forward_reach_max,
			cfg.rom_forehand_reach_max, cfg.rom_backhand_reach_max)


static func rim_exit_of(from: Vector2, dir: Vector2, blade_side_sign: float, fw: float,
		fh: float, bh: float) -> float:
	# Forehand-signed: x toward the forehand, y straight ahead.
	var p := Vector2(from.x * blade_side_sign, -from.y)
	var u := Vector2(dir.x * blade_side_sign, -dir.y)
	var best: float = INF
	best = _arc_exit(p, u, fh, fw, 1.0, 1.0, best)
	best = _arc_exit(p, u, bh, fw, -1.0, 1.0, best)
	best = _arc_exit(p, u, fh, fh, 1.0, -1.0, best)
	best = _arc_exit(p, u, bh, bh, -1.0, -1.0, best)
	# The step behind the shoulder, crossed from the longer side to the shorter.
	if absf(u.x) > 0.000001 and signf(u.x) == signf(bh - fh):
		var k: float = -p.x / u.x
		var y: float = p.y + u.y * k
		if k >= 0.0 and y < 0.0 and -y > minf(fh, bh) and -y < maxf(fh, bh):
			best = minf(best, k)
	return maxf(best, 0.0) if best < INF else 0.0


# The nearest exit along `u` from `p` through the arc of the ellipse with
# semi-axes (`a` across, `b` ahead) in the quadrant (`x_side`, `y_side`), or
# `best` if that comes first.
static func _arc_exit(p: Vector2, u: Vector2, a: float, b: float, x_side: float,
		y_side: float, best: float) -> float:
	var ia: float = 1.0 / (a * a)
	var ib: float = 1.0 / (b * b)
	var qa: float = u.x * u.x * ia + u.y * u.y * ib
	if qa < 0.0000001:
		return best
	var qb: float = 2.0 * (p.x * u.x * ia + p.y * u.y * ib)
	var qc: float = p.x * p.x * ia + p.y * p.y * ib - 1.0
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return best
	var k: float = (-qb + sqrt(disc)) / (2.0 * qa)
	if k < -_ARC_EPS_M or k >= best:
		return best
	var q: Vector2 = p + u * k
	if q.x * x_side < -_ARC_EPS_M or q.y * y_side < -_ARC_EPS_M:
		return best
	return k


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
# ROM. Returns the input unchanged when already inside the ROM, else the
# boundary ray on the exceeded side.
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

class_name AICarrySpace

# How much room a carrier has to operate: reachable-set evasion, the safety
# maps and the crossing sample. It reads the arrival clock and its reference
# speeds from AIArrival and the net test from AINetObstacle, and
# never AIActionScoring (test_scoring_split_stays_acyclic.gd).

# ── Reachable-set evasion (pursuit-evasion possession safety) ────────────────
# Whether a defender threatens the puck is "can he get a stick to it given his
# MOMENTUM and reaction", not "how close is he". Each skater is a bounded-accel
# body: over a short horizon it rides its velocity to (pos + vel·T) and can
# deviate from that line by at most ½·A·(T−reaction)² (a double integrator's
# reachable set), with the stick reaching further. The carrier evades by placing
# the puck in his handling envelope outside every defender's disk — the SEAM.
#
# The BOARDS bound the seam search, not the clearance itself: a wall doesn't
# strip the puck, it removes escape options. So the seam samplers reject
# off-surface samples, and a wall-pinned carrier's best seam runs along the wall
# with honestly small clearance.
const MANEUVER_ACCEL_M_S2: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
const EVADE_HORIZON_S: float = 0.40    # a cut's length — the evasion look-ahead
const EVADE_REACTION_S: float = 0.15   # a defender reads a cut before he can redirect to it
const EVADE_STICK_REACH_M: float = (   # how far a defender's stick touches from his body
		GameRules.DEFAULT_STICK_LENGTH_M + GameRules.DEFAULT_BLADE_LENGTH_M)
# A full stick of clear room reads as fully safe; inside the reach reads as 0.
const EVADE_SAFE_MARGIN_M: float = EVADE_STICK_REACH_M
# Envelope sampling for the seam search (rings × angles). Coarse is fine — the
# seam is a broad region, not a point.
const EVADE_SAMPLE_RINGS: Array[float] = [0.4, 0.8, 1.0]
const EVADE_SAMPLE_ANGLES: int = 12
# The model reacts only once (the reaction gate) while a real defender re-reads
# continuously, so clearance 0 is not safe: one blade-length of air is the slop
# that survives the re-read. At or above it a sample is SAFE for the directed
# seam (progress may be preferred among safe samples); below it, clearance itself
# is the only currency.
const EVADE_SAFE_CLEAR_MIN_M: float = GameRules.DEFAULT_BLADE_LENGTH_M


# Gap (metres) from a puck point to the nearest board; negative outside the
# playing surface. INNER extents (the surface the puck lives on), rounded
# corners included: in a corner quadrant the nearest board is the arc, which a
# rectangle overshoots by metres exactly where a carrier gets pinned.
static func board_gap_m(point: Vector3) -> float:
	var ax: float = absf(point.x)
	var az: float = absf(point.z)
	if ax > GameRules.CORNER_CENTER_X and az > GameRules.CORNER_CENTER_Z:
		var dx: float = ax - GameRules.CORNER_CENTER_X
		var dz: float = az - GameRules.CORNER_CENTER_Z
		return GameRules.INNER_CORNER_RADIUS - sqrt(dx * dx + dz * dz)
	return minf(GameRules.INNER_HALF_WIDTH - ax, GameRules.INNER_HALF_LENGTH - az)


# Clearance (metres) of a puck point from every defender's reachable stick at
# `time` — >0 means no defender's stick TIP nominally reaches it (that much
# room), <0 means covered. Pure float math, no allocation.
#
# NOMINAL, not best-case: the defender's coverage is the calibrated
# time_to_arrive phase model in distance form — coast on momentum through the
# reaction gate, shed excess cross-speed at the measured rate, brake out a
# retreat (losing ground while braking), then the stride's pursuit ramp
# (AIStrideRamp.distance_in) — plus the stick span. Never a best-case 0.5·a·t²
# lunge: that over-reaches at long windows and under-reaches close in. Optimistic
# where time_to_arrive is: short perpendicular cuts at speed. The safety maps
# below carry the residual as a probability band.
# `abort_below`: exact argmax pruning for sample-scanning callers (the seam
# search) — once the running worst drops below it, the exact value cannot
# matter to the caller, so the defender loop stops early. Default −INF scans
# every defender (every value-consuming caller).
static func reach_clearance(
		puck_point: Vector3, time: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array = [], maneuver_time: float = -1.0,
		carry_dir: Vector2 = Vector2.ZERO, carry_speed: float = 0.0,
		abort_below: float = -INF, carried_from: Vector3 = Vector3.INF) -> float:
	var n: int = opponents.size()
	if n == 0 or opponent_vels.size() != n:
		return EVADE_SAFE_MARGIN_M   # nothing to evade — fully clear
	# `maneuver_time` is the defender's COMMIT window — how long he actively
	# pursues the sample point; the body coasts on momentum for the remainder.
	# Default (< 0) commits the whole window (the carry/hold reads). The
	# PASS-RECEPTION and carry-END reads pass a short window (EVADE_HORIZON_S /
	# CARRY_LUNGE_WINDOW_S): the defender isn't credited with committing to the
	# catch spot for the whole flight — the in-flight interception is the lane
	# model's ledger, and at a carry's arrival the carrier is established and
	# protecting. A man chasing a carry from `carried_from` to `puck_point`
	# commits the whole window regardless (_chases): he is after the carrier, not
	# a spot.
	var w: float = time if maneuver_time < 0.0 else minf(time, maneuver_time)
	var has_caps: bool = opponent_caps.size() == n
	var gated: bool = carry_speed > 0.0
	var worst: float = INF
	for i: int in n:
		var accel: float = MANEUVER_ACCEL_M_S2
		var stick: float = EVADE_STICK_REACH_M
		var vmax: float = AIArrival.SKATER_REF_SPEED_M_S
		var grip: float = 1.0
		if has_caps:
			# Per-opponent build — Acceleration (max_accel) sets the ramp, reach
			# (blade_span) the stick, Speed (max_speed) the cap. Empty caps →
			# league constants for all (every non-attribute caller).
			var caps: AISkaterCaps = opponent_caps[i]
			if caps != null:
				accel = caps.max_accel
				stick = caps.blade_span
				vmax = caps.max_speed
				grip = caps.lateral_grip
		# PRESCREEN (exact): the phase model's total ground toward the point is
		# bounded by the whole window at the better of current pace or cap
		# (coast ≤ |v|·coast, capped pursuit ≤ vmax·τ; shed/brake only lose
		# ground) — so clearance ≥ dist − speed_ub·time − stick. When even that
		# floor can't come under the running worst, this defender cannot move
		# the min and the full model is skipped. L1 speed (≥ L2) keeps the
		# bound conservative; squared compare avoids the sqrt.
		var speed_ub: float = maxf(vmax,
				absf(opponent_vels[i].x) + absf(opponent_vels[i].z))
		var need: float = worst + speed_ub * time + stick
		if need <= 0.0:
			continue
		var sdx: float = puck_point.x - opponents[i].x
		var sdz: float = puck_point.z - opponents[i].z
		if sdx * sdx + sdz * sdz >= need * need:
			continue
		var v_along_carry: float = 0.0
		var stride_accel: float = accel
		if gated:
			# ESCAPE-SPEED gate (opt-in, `carry_speed > 0`): a defender chasing
			# near the carrier's pace along `carry_dir` (world XZ as Vector2(x,z))
			# is committed to keeping up — only his surplus accel can redirect
			# onto the puck. Momentum progress (v0 below) is untouched: a faster
			# chaser still runs the carry down; a pace-matched one holds the gap.
			v_along_carry = opponent_vels[i].x * carry_dir.x \
					+ opponent_vels[i].z * carry_dir.y
			accel *= clampf(1.0 - maxf(v_along_carry, 0.0) / carry_speed, 0.0, 1.0)
		var w_i: float = w
		if _chases(carried_from, puck_point, opponents[i], opponent_vels[i]):
			w_i = time
		var clear: float = _reach_clearance_one(
				puck_point.x, puck_point.z, time, w_i,
				opponents[i].x, opponents[i].z,
				opponent_vels[i].x, opponent_vels[i].z, accel, stick, vmax, grip)
		if v_along_carry > 0.0 and w < time:
			# A man skating WITH the carry can also just stop: the carry is coming
			# to him, so braking commits him to no spot and starts at his read,
			# not when the commit window opens. The pace he still carries then
			# gates his stride as above. (A chaser behind only loses ground by it,
			# so the min leaves him be.)
			clear = minf(clear, _stopped_clearance(puck_point.x, puck_point.z, time, w,
					opponents[i].x, opponents[i].z, opponent_vels[i].x, opponent_vels[i].z,
					stride_accel, stick, vmax, grip, v_along_carry / carry_speed))
		if clear < worst:
			worst = clear
			if worst < abort_below:
				return worst
	return worst


# Whether a man at `pos` moving at `vel` is chasing a carry from `from` to `to`:
# behind where it starts along it and skating its way, so where it ends is where
# he is going and he is on it the whole window, never coasting past it. One
# level with the carrier or in front of the carry is not: he has to cut across
# to it, which is the reach the lunge prices.
static func _chases(from: Vector3, to: Vector3, pos: Vector3, vel: Vector3) -> bool:
	if not from.is_finite():
		return false
	var cx: float = to.x - from.x
	var cz: float = to.z - from.z
	return vel.x * cx + vel.z * cz > 0.0 and (pos.x - from.x) * cx + (pos.z - from.z) * cz < 0.0


# One defender's nominal reach clearance (see reach_clearance): coast on
# momentum until the commit window `w` opens, react, then shed / brake / ramp
# toward the point at the calibrated net kinematics. Factored out so the carry
# reads can additionally sample each defender at its own closest-approach
# moment on the path.
static func _reach_clearance_one(point_x: float, point_z: float, time: float,
		w: float, ox: float, oz: float, vx: float, vz: float,
		accel: float, stick: float, vmax: float,
		lateral_grip: float = 1.0) -> float:
	var tau: float = maxf(0.0, minf(time, w) - EVADE_REACTION_S)
	var coast: float = time - tau
	return _committed_clearance(point_x, point_z, tau, ox + vx * coast, oz + vz * coast,
			vx, vz, accel, stick, vmax, lateral_grip)


# _reach_clearance_one for a defender who brakes his run from his read instead of
# coasting until the commit window opens, then plays the point from where the
# brake left him. `pace_share` is his pace along the carry over the carry's, and
# what is left of it when he commits gates his stride (the escape gate).
static func _stopped_clearance(point_x: float, point_z: float, time: float,
		w: float, ox: float, oz: float, vx: float, vz: float,
		accel: float, stick: float, vmax: float, lateral_grip: float,
		pace_share: float) -> float:
	var tau: float = maxf(0.0, minf(time, w) - EVADE_REACTION_S)
	var read: float = minf(time - tau, EVADE_REACTION_S)
	var speed: float = sqrt(vx * vx + vz * vz)
	var brake: float = AIArrival.REVERSAL_BRAKE_DECEL_M_S2
	var t_b: float = minf(speed / brake, time - tau - read)
	var slide: float = speed * t_b - 0.5 * brake * t_b * t_b
	var left: float = (speed - brake * t_b) / speed
	return _committed_clearance(point_x, point_z, tau,
			ox + vx * read + vx / speed * slide, oz + vz * read + vz / speed * slide,
			vx * left, vz * left, accel * clampf(1.0 - pace_share * left, 0.0, 1.0),
			stick, vmax, lateral_grip)


# Clearance of the point from a defender at (px, pz) moving (vx, vz) as his
# commit window of `tau` opens.
static func _committed_clearance(point_x: float, point_z: float, tau: float,
		px: float, pz: float, vx: float, vz: float,
		accel: float, stick: float, vmax: float, lateral_grip: float) -> float:
	var dx: float = point_x - px
	var dz: float = point_z - pz
	var dist: float = sqrt(dx * dx + dz * dz)
	var d: float = 0.0
	if tau > 0.0 and dist > 0.001:
		var inv: float = 1.0 / dist
		var v_along: float = (vx * dx + vz * dz) * inv
		var v_perp: float = absf((vx * dz - vz * dx) * inv)
		# Shed excess cross-speed (a pure delay, as calibrated — authority is
		# the edge grip the movement core turns with), then brake out any
		# retreat (losing ground), then the stride's pursuit ramp.
		var grip: float = maxf(lateral_grip, 0.001)
		var tau_p: float = tau - maxf(0.0, v_perp - AIArrival.VM_FREE_SHED_M_S * grip) \
				/ (AIArrival.VM_SHED_DECEL_M_S2 * grip)
		if tau_p > 0.0:
			var v0: float = v_along
			if v0 < 0.0:
				var t_b: float = minf(-v0 / AIArrival.REVERSAL_BRAKE_DECEL_M_S2, tau_p)
				d = v0 * t_b + 0.5 * AIArrival.REVERSAL_BRAKE_DECEL_M_S2 * t_b * t_b
				v0 += AIArrival.REVERSAL_BRAKE_DECEL_M_S2 * t_b
				tau_p -= t_b
			d += AIStrideRamp.distance_in(v0, tau_p, vmax, accel)
	return dist - d - stick


# ── The safety maps: measured strip probability over nominal clearance ────────
# Production contact is a SWEEP standard, not a tip touch: a strip lands when
# the blade segment passes within the puck-contact radius
# (PuckController.PICKUP_RADIUS), so nominal tip-standard contact connects at
# +POKE_CONTACT_RADIUS_M of clearance. The two maps are the measured strip
# bands around that boundary for two regimes:
#   DWELL (clearance_to_safety) — the puck holds still at the sample (a stand,
#     a carry's arrival, a reception). A committed defender always strips a
#     dwelling puck he nominally reaches, so the band is only the model's own
#     crossing error, ± one blade length around the contact boundary.
#   TRANSIT (transit_clearance_to_safety) — the puck passes through the sample
#     mid-carry, and the defender must MEET a moving target on a delayed read:
#     staged carries at or below TRANSIT_STRIP_CLEAR_M are stripped, none above
#     TRANSIT_SAFE_CLEAR_M are, outcomes mixed between.
const POKE_CONTACT_RADIUS_M: float = 0.5
const DWELL_HALF_BAND_M: float = GameRules.DEFAULT_BLADE_LENGTH_M
const TRANSIT_STRIP_CLEAR_M: float = -0.4
const TRANSIT_SAFE_CLEAR_M: float = 0.6


# Dwelling-puck safety: 0 once the sweep standard is nominally met
# (POKE_CONTACT_RADIUS_M − DWELL_HALF_BAND_M), 1 a blade past it. The map for
# every hold/stand/arrival/reception read.
static func clearance_to_safety(clearance: float) -> float:
	return clampf(
			(clearance - (POKE_CONTACT_RADIUS_M - DWELL_HALF_BAND_M))
					/ (2.0 * DWELL_HALF_BAND_M),
			0.0, 1.0)


# Moving-puck safety: the mixed band for a puck traversing the sample at stride.
# More lenient than the dwell map — outrunning a reaction-delayed pursuit is
# real protection.
static func transit_clearance_to_safety(clearance: float) -> float:
	return clampf((clearance - TRANSIT_STRIP_CLEAR_M)
			/ (TRANSIT_SAFE_CLEAR_M - TRANSIT_STRIP_CLEAR_M), 0.0, 1.0)


# Lunge window for a defender's stick redirect onto a carried puck AT ITS
# ARRIVAL SPOT — the maneuver-time bound the carry reads apply to their END
# sample only. At the destination the carrier is established and protecting,
# so the defender gets his real lunge, not a full-window t² repositioning that
# reads every honest-length carry destination as covered. The MID sample keeps
# the full-window pursuit: en route the puck traverses the pursuit envelope at
# stride, where protection is weakest — the asymmetry that prices "thread the
# gauntlet" carries as dangerous while leaving a peel-out to open ice safe.
const CARRY_LUNGE_WINDOW_S: float = EVADE_HORIZON_S


# ── Crossing sample: the meeting-strip band ──────────────────────────────────
# The mid/end samples can straddle a defender the carry path MEETS between
# them — a pinch wall just past `from`, a forechecker met in the first
# quarter — and the strip lands at the meeting moment neither sample sees.
# Measured on staged crossings (a committed seeker under the real movement /
# blade / poke rules, across pace, miss distance and closing geometry), the
# meeting outcome is a pure DISTANCE band on the contact envelope's own radii,
# not a speed or dwell-time effect:
#   core = reach                         → keep 0 (swept at any pace)
#   edge = reach + POKE_CONTACT_RADIUS_M  → keep 1 (grazed at pace)
# where reach is his full blade reach (the build's max_blade_reach): the blade
# sent at the puck, the poke's contact past its tip.
#
# A PROTECTING carrier (puck ridden on the handle envelope away from the
# threat) shifts the whole band by CROSSING_PROTECT_SHIFT_M. The shift is a
# SHARED, DIRECTIONAL budget: the puck line can displace one way, so threats on
# one side get the full credit while an OPPOSED pair (the pinch wall, the
# corralling pincer) splits it to nothing — the optimal lateral shift between
# the per-side worst crossings. That is why lone containers are beatable while
# walls are genuinely dangerous.
#
# Slow grazes are stripped by pursuit, not the meeting, and pursuit is what the
# mid/end transit samples price. Only the window INTERIOR is sampled here.
#
# Measured by tests/instruments/ai/test_crossing_band.gd: a carrier held past a
# planted poker who leads the carry keeps the puck once his line passes his
# full reach + ~0.15 m, at every pace and on either side. The shield rides the
# puck ~0.3 m off by then (0.8 m only once the stick is already inside it), and
# the band's half width takes the rest.
const CROSSING_PROTECT_SHIFT_M: float = 0.1


# A defender's crossing span, the band's edge before any shield: his full reach
# plus the poke's contact.
static func _crossing_span(caps: AISkaterCaps) -> float:
	return (caps.max_blade_reach if caps != null else AISkaterCaps.LEAGUE_MAX_BLADE_REACH_M) \
			+ POKE_CONTACT_RADIUS_M


static func carry_crossing_keep(from: Vector3, to: Vector3, arrival_time: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array = []) -> float:
	var n: int = opponents.size()
	if n == 0 or opponent_vels.size() != n or arrival_time <= 0.0:
		return 1.0
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var seg: float = sqrt(dx * dx + dz * dz)
	if seg < 0.001:
		return 1.0
	var dirx: float = dx / seg
	var dirz: float = dz / seg
	var inv_t: float = 1.0 / arrival_time
	var pvx: float = dx * inv_t   # puck velocity along the carry
	var pvz: float = dz * inv_t
	var pv_len: float = seg * inv_t
	var has_caps: bool = opponent_caps.size() == n
	# Per-side worst crossing, in band units (d_min − span so different builds'
	# spans compose): the shared protect shift then resolves between the sides.
	var worst_l: float = INF
	var worst_r: float = INF
	for i: int in n:
		var span: float = _crossing_span(opponent_caps[i] if has_caps else null)
		var r0x: float = from.x - opponents[i].x
		var r0z: float = from.z - opponents[i].z
		# PRESCREEN (exact): the meeting can't come nearer than the current
		# separation minus the whole window's relative travel (|rv| ≤ |pv| +
		# |v|, L1-bounded), so margin ≥ |r0| − rv_ub·T − span. A margin at or
		# above the full protect budget is RESULT-identical to absence: the
		# side it would post ≥ SHIFT on either keeps its own worst (min) or,
		# as a lone entry, resolves through the shift to the same clamped
		# keep the single-sided formula gives (the two branches agree once
		# one side's slack covers the whole budget). Squared compare, no sqrt.
		var rv_ub: float = pv_len \
				+ absf(opponent_vels[i].x) + absf(opponent_vels[i].z)
		var far_need: float = span + CROSSING_PROTECT_SHIFT_M + rv_ub * arrival_time
		if r0x * r0x + r0z * r0z >= far_need * far_need:
			continue
		var rvx: float = pvx - opponent_vels[i].x
		var rvz: float = pvz - opponent_vels[i].z
		var rv_sq: float = rvx * rvx + rvz * rvz
		if rv_sq < 0.0001:
			continue   # co-moving: no meeting — endpoints cover it
		var t_star: float = -(r0x * rvx + r0z * rvz) / rv_sq
		if t_star <= 0.0 or t_star >= arrival_time:
			continue   # closest approach outside the window — endpoints cover it
		var mx: float = r0x + rvx * t_star
		var mz: float = r0z + rvz * t_star
		var d_min: float = sqrt(mx * mx + mz * mz)
		# Which side of the carry line the defender crosses on (m is puck −
		# defender at t*, so the defender sits at −m relative to the path).
		var margin: float = d_min - span
		if margin <= -(POKE_CONTACT_RADIUS_M + CROSSING_PROTECT_SHIFT_M):
			# Deeper than the full protect credit can ever recover — swept
			# regardless of the other side's slack.
			return 0.0
		if dirx * (-mz) - dirz * (-mx) >= 0.0:
			if margin < worst_l:
				worst_l = margin
		else:
			if margin < worst_r:
				worst_r = margin
	if worst_l == INF and worst_r == INF:
		return 1.0
	# Optimal shared lateral shift of the puck line between the two sides,
	# bounded by the measured protect displacement (a shift toward the right
	# widens every left-side gap and narrows every right-side one).
	var eff: float
	if worst_l < INF and worst_r < INF:
		var x: float = clampf((worst_r - worst_l) * 0.5,
				-CROSSING_PROTECT_SHIFT_M, CROSSING_PROTECT_SHIFT_M)
		eff = minf(worst_l + x, worst_r - x)
	else:
		eff = (worst_l if worst_l < INF else worst_r) + CROSSING_PROTECT_SHIFT_M
	return clampf((eff + POKE_CONTACT_RADIUS_M) / POKE_CONTACT_RADIUS_M, 0.0, 1.0)


# Possession safety [0, 1] of a carry — the regime-aware map application (see
# the safety-map doc above reach_clearance): the MID sample is a moving puck
# (transit band), the END sample a dwelling one (the carrier arrives there),
# a stand (from == to) dwells at both, and each defender the path MEETS
# between the fixed samples contributes the measured crossing band
# (carry_crossing_keep). Never one map over the worst of both samples: that
# forces the dwell band onto a puck in transit.
static func carry_safety(from: Vector3, to: Vector3, arrival_time: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array = [], apply_escape: bool = false) -> float:
	var carry_dir := Vector2.ZERO
	var carry_speed: float = 0.0
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var dist: float = sqrt(dx * dx + dz * dz)
	if apply_escape and arrival_time > 0.0 and dist > 0.001:
		carry_dir = Vector2(dx / dist, dz / dist)
		carry_speed = dist / arrival_time
	if dist < 0.001:
		# A stand: the puck dwells the whole window — both samples read dwell.
		var s_mid: float = clearance_to_safety(reach_clearance(
				from, arrival_time * 0.5, opponents, opponent_vels,
				opponent_caps))
		if s_mid <= 0.0:
			return 0.0
		return minf(s_mid, clearance_to_safety(reach_clearance(
				from, arrival_time, opponents, opponent_vels,
				opponent_caps, minf(arrival_time, CARRY_LUNGE_WINDOW_S))))
	# Sequential early-outs — each factor can only lower the min, so any zero
	# skips the remaining defender loops.
	var crossing: float = carry_crossing_keep(
			from, to, arrival_time, opponents, opponent_vels, opponent_caps)
	if crossing <= 0.0:
		return 0.0
	var t_mid: float = transit_clearance_to_safety(reach_clearance(
			from.lerp(to, 0.5), arrival_time * 0.5, opponents, opponent_vels,
			opponent_caps, -1.0, carry_dir, carry_speed))
	if t_mid <= 0.0:
		return 0.0
	return minf(crossing, minf(t_mid, clearance_to_safety(reach_clearance(
			to, arrival_time, opponents, opponent_vels,
			opponent_caps, minf(arrival_time, CARRY_LUNGE_WINDOW_S),
			carry_dir, carry_speed))))


# WHERE a carry gets stripped, if it does: the EARLIEST covered point on the path.
# The turnover cost of a carry is priced HERE, not at the destination — a strip
# surrenders the puck where you were caught, in the traffic you were skating
# through, not the safe spot you were headed for. Chronological, not tightest: the
# reach balloons with time (maneuver ∝ time²), so a far destination reads as
# "more covered", but a puck stripped mid-route never reaches it — the mid-point
# strip happens first. Mirrors lane_loss_point for passes; from == to is a stand.
# `covered_only`: how far the carry GETS — nothing covered reaches `to`.
static func carry_strip_point(from: Vector3, to: Vector3, arrival_time: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array = [], apply_escape: bool = false, covered_only: bool = false) -> Vector3:
	var carry_dir := Vector2.ZERO
	var carry_speed: float = 0.0
	if apply_escape and arrival_time > 0.0:
		var ddx: float = to.x - from.x
		var ddz: float = to.z - from.z
		var ddist: float = sqrt(ddx * ddx + ddz * ddz)
		if ddist > 0.001:
			carry_dir = Vector2(ddx / ddist, ddz / ddist)
			carry_speed = ddist / arrival_time
	# Sample windows must mirror carry_safety exactly so the strip point and
	# the safety read agree on which sample is covered (crossing = the
	# meeting-strip band's SHIFT-ADJUSTED core, mid = full pursuit, end =
	# arrival lunge). The earliest core-hit crossing pre-empts the fixed
	# samples when the meeting happens first — a pinch wall driven into
	# strips at the wall.
	var cross_t: float = INF
	var cross_pt: Vector3 = to
	var seg_x: float = to.x - from.x
	var seg_z: float = to.z - from.z
	var seg_len: float = sqrt(seg_x * seg_x + seg_z * seg_z)
	if arrival_time > 0.0 and seg_len > 0.001 \
			and opponent_vels.size() == opponents.size():
		var dirx: float = seg_x / seg_len
		var dirz: float = seg_z / seg_len
		var inv_t: float = 1.0 / arrival_time
		var pvx: float = seg_x * inv_t
		var pvz: float = seg_z * inv_t
		var has_caps: bool = opponent_caps.size() == opponents.size()
		# Pass 1: per-side worst margins → the shared protect shift, exactly
		# as carry_crossing_keep resolves it.
		var worst_l: float = INF
		var worst_r: float = INF
		for i: int in opponents.size():
			var rvx: float = pvx - opponent_vels[i].x
			var rvz: float = pvz - opponent_vels[i].z
			var rv_sq: float = rvx * rvx + rvz * rvz
			if rv_sq < 0.0001:
				continue
			var r0x: float = from.x - opponents[i].x
			var r0z: float = from.z - opponents[i].z
			var t_star: float = -(r0x * rvx + r0z * rvz) / rv_sq
			if t_star <= 0.0 or t_star >= arrival_time:
				continue
			var mx: float = r0x + rvx * t_star
			var mz: float = r0z + rvz * t_star
			var span: float = _crossing_span(opponent_caps[i] if has_caps else null)
			var margin: float = sqrt(mx * mx + mz * mz) - span
			if dirx * (-mz) - dirz * (-mx) >= 0.0:
				worst_l = minf(worst_l, margin)
			else:
				worst_r = minf(worst_r, margin)
		var shift: float = CROSSING_PROTECT_SHIFT_M
		var both: bool = worst_l < INF and worst_r < INF
		if both:
			shift = clampf((worst_r - worst_l) * 0.5,
					-CROSSING_PROTECT_SHIFT_M, CROSSING_PROTECT_SHIFT_M)
		# Pass 2 (earliest crossing whose shift-adjusted margin hits the core)
		# runs only when some crossing could be swept even under the most
		# favourable shift — the common open-ice case skips it entirely.
		if minf(worst_l, worst_r) \
				<= -POKE_CONTACT_RADIUS_M + CROSSING_PROTECT_SHIFT_M:
			for i: int in opponents.size():
				var rvx2: float = pvx - opponent_vels[i].x
				var rvz2: float = pvz - opponent_vels[i].z
				var rv_sq2: float = rvx2 * rvx2 + rvz2 * rvz2
				if rv_sq2 < 0.0001:
					continue
				var r0x2: float = from.x - opponents[i].x
				var r0z2: float = from.z - opponents[i].z
				var t_star2: float = -(r0x2 * rvx2 + r0z2 * rvz2) / rv_sq2
				if t_star2 <= 0.0 or t_star2 >= arrival_time or t_star2 >= cross_t:
					continue
				var mx2: float = r0x2 + rvx2 * t_star2
				var mz2: float = r0z2 + rvz2 * t_star2
				var span2: float = _crossing_span(opponent_caps[i] if has_caps else null)
				var margin2: float = sqrt(mx2 * mx2 + mz2 * mz2) - span2
				var left: bool = dirx * (-mz2) - dirz * (-mx2) >= 0.0
				var eff: float = margin2 + CROSSING_PROTECT_SHIFT_M
				if both:
					eff = margin2 + (shift if left else -shift)
				if eff <= -POKE_CONTACT_RADIUS_M:
					cross_t = t_star2
					cross_pt = Vector3(
							from.x + pvx * t_star2, 0.0, from.z + pvz * t_star2)
	var mid: Vector3 = from.lerp(to, 0.5)
	if cross_t < arrival_time * 0.5:
		return cross_pt   # met and swept before the mid sample
	var c_mid: float = reach_clearance(mid, arrival_time * 0.5, opponents,
			opponent_vels, opponent_caps, -1.0, carry_dir, carry_speed)
	if c_mid < 0.0:
		return mid   # covered mid-route — stripped there, before the destination
	if cross_t < arrival_time:
		return cross_pt   # met and swept between the mid and end samples
	var c_end: float = reach_clearance(to, arrival_time, opponents, opponent_vels,
			opponent_caps, minf(arrival_time, CARRY_LUNGE_WINDOW_S),
			carry_dir, carry_speed)
	if c_end < 0.0 or covered_only:
		return to    # covered at the destination, or nothing covered at all
	# Neither covered (a low strip probability anyway): the tighter of the two.
	return mid if c_mid <= c_end else to


# The carrier's best evasion target — the point in his handling envelope (where he
# can put/protect the puck over EVADE_HORIZON_S) with the most clearance from
# every defender: the SEAM. `handle_reach` is how far he holds the puck off his
# body (scaled by the blade lever), so a longer reach threads a tighter seam. Returned as a
# world point (y = 0); this max-clearance seam is the carrier's honest
# evadability read (reach_clearance at this point = "can I keep the puck at
# all"). Value-type math; allocation-free.
static func best_evade_point(
		carrier_pos: Vector3, carrier_vel: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		handle_reach: float, opponent_caps: Array = []) -> Vector3:
	var env: float = 0.5 * MANEUVER_ACCEL_M_S2 * EVADE_HORIZON_S * EVADE_HORIZON_S \
			+ handle_reach
	return _best_clear_point(
			carrier_pos.x + carrier_vel.x * EVADE_HORIZON_S,
			carrier_pos.z + carrier_vel.z * EVADE_HORIZON_S,
			env, opponents, opponent_vels, opponent_caps)


# WHERE ON THE BLADE to hold the puck under pressure: a point in the carrier's
# handling envelope ALONE (no body-maneuver term — the body keeps doing whatever
# steering wants; this is pure stick work), safe from every defender's
# momentum-reach. Returned as an OFFSET from the body (y = 0), so the consumer
# re-applies it to the live body position every tick — pull the puck off the
# presented forward spot when that spot is covered, and the body becomes the
# shield. The envelope is intersected with the playing surface, so the protected
# side is never through a wall (the escape runs along the boards).
#
# Called TWICE by the carrier, for two different questions, and the distinction
# is the point of the `objective` parameter:
#
#   HOW MUCH to shield reads the MAX-clearance seam (no objective) — the safety
#     the best available shield buys, which is what the consumer's blend weight
#     needs.
#   WHERE to put the puck reads the DIRECTED seam (objective = the presented
#     forward spot): among samples with a blade of real air
#     (EVADE_SAFE_CLEAR_MIN_M) take the one CLOSEST to that spot, falling back to
#     max clearance only when nothing in the envelope is safe.
#
# Never AIM with the max-clearance point: it is diametrically opposite the
# checker, and a checker only makes shielding necessary by being in FRONT, so
# the puck would sit on the BACK hip — on neither a shot nor a pass — for as
# long as the man is live. Directed, the seam grades with the checker's bearing,
# so the shield goes exactly as deep as it must; under a real jam, where nothing
# is safe, the fallback restores the full far-hip shield.
static func best_handle_protect_point(
		carrier_pos: Vector3, carrier_vel: Vector3,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		handle_reach: float, opponent_caps: Array = [],
		objective: Vector3 = Vector3.INF) -> Vector3:
	var proj_x: float = carrier_pos.x + carrier_vel.x * EVADE_HORIZON_S
	var proj_z: float = carrier_pos.z + carrier_vel.z * EVADE_HORIZON_S
	var best: Vector3 = _best_clear_point(
			proj_x, proj_z, handle_reach, opponents, opponent_vels, opponent_caps,
			objective)
	return Vector3(best.x - proj_x, 0.0, best.z - proj_z)


# Shared seam sampler: the max-clearance point over the disk of radius `env`
# around the (already projected) center, evaluated at the evasion horizon.
# Coarse rings × angles are fine — the seam is a broad region, not a point.
# The disk is intersected with the playing surface (off-surface samples are
# rejected — the puck can't be handled through a wall), which is what makes a
# wall-pinned carrier's best seam run ALONG the boards and read honestly tight;
# the projected center stays as the fallback even off-surface (the containment
# backstop owns that degenerate case, not the seam search).
#
# With a finite `objective`, the sweep is objective-directed: among samples
# clearing EVADE_SAFE_CLEAR_MIN_M the one closest to the objective wins; the max-clearance point remains the
# fallback when no sample is safe.
static func _best_clear_point(proj_x: float, proj_z: float, env: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		opponent_caps: Array = [], objective: Vector3 = Vector3.INF) -> Vector3:
	var directed: bool = objective.is_finite()
	var best: Vector3 = Vector3(proj_x, 0.0, proj_z)
	var best_clear: float = reach_clearance(best, EVADE_HORIZON_S, opponents, opponent_vels, opponent_caps)
	var best_safe: Vector3 = Vector3.INF
	var best_safe_progress: float = INF   # distance to objective; smaller = more progress
	if directed and best_clear >= EVADE_SAFE_CLEAR_MIN_M:
		best_safe = best
		best_safe_progress = Vector2(objective.x - best.x, objective.z - best.z).length()
	for ring: float in EVADE_SAMPLE_RINGS:
		var radius: float = env * ring
		for k: int in EVADE_SAMPLE_ANGLES:
			var ang: float = TAU * float(k) / float(EVADE_SAMPLE_ANGLES)
			var p := Vector3(proj_x + cos(ang) * radius, 0.0, proj_z + sin(ang) * radius)
			if board_gap_m(p) < 0.0:
				continue
			# Exact argmax pruning, two layers. (1) Directed with a safe sample
			# in hand: the fallback argmax is moot (the safe winner returns),
			# so a sample that can't beat the best PROGRESS never needs its
			# clearance at all — skip the defender scan wholesale. (2) A
			# sample only matters if it beats the best clearance so far, or
			# (directed) clears the safe floor — once its running worst drops
			# below both, the exact value is irrelevant and the defender scan
			# aborts early (abort_below).
			var progress: float = 0.0
			if directed:
				progress = Vector2(objective.x - p.x, objective.z - p.z).length()
				if best_safe.is_finite() and progress >= best_safe_progress:
					continue
			var abort: float = best_clear
			if directed:
				abort = minf(abort, EVADE_SAFE_CLEAR_MIN_M)
			var c: float = reach_clearance(p, EVADE_HORIZON_S, opponents,
					opponent_vels, opponent_caps, -1.0, Vector2.ZERO, 0.0, abort)
			if c > best_clear:
				best_clear = c
				best = p
			if directed and c >= EVADE_SAFE_CLEAR_MIN_M \
					and progress < best_safe_progress:
				best_safe_progress = progress
				best_safe = p
	if directed and best_safe.is_finite():
		return best_safe
	return best


# Defender reach for the CARRY-path check below — stick-blade reach plus
# a margin for the defender stepping in as the bot skates past. Distinct
# from the fired-puck lane model (which derives reach from closing time);
# a carry is a slow physical traverse, so it uses a flat poke radius.
const CARRY_PATH_CLEAR_RADIUS_M: float = 1.8

# carry_lane_clearance's "beaten trailer" gate. A defender is dropped from the lane
# only if it's BEHIND the carrier along the drive by more than LANE_BEATEN_BEHIND_M
# AND slower along it by more than LANE_BEATEN_PACE_M_S — i.e. the carrier is
# genuinely pulling away. Both are physical slacks (a body's depth behind; a real
# pace edge), not shape knobs: a man even/ahead or matching pace is never shed, so
# only a beaten trailer is dropped.
const LANE_BEATEN_BEHIND_M: float = 0.1
const LANE_BEATEN_PACE_M_S: float = 0.5

# Clearance of a CARRY path from `from` to `to`, reached in `arrival_time`:
# 1.0 when no opponent projected to arrival is within CARRY_PATH_CLEAR_RADIUS_M
# of the segment, ramping linearly to 0.0 on the line. The carrier is skating
# this segment, not firing a puck through it, so `lane_clear`'s flight-time
# reach does not apply — a defender anywhere on the path is in the way.
static func carry_lane_clearance(from: Vector3, to: Vector3, arrival_time: float,
		opponents: Array[Vector3], opponent_vels: Array[Vector3],
		max_speed: float = 0.0) -> float:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var seg_sq: float = dx * dx + dz * dz
	if seg_sq < 0.01 or arrival_time <= 0.0:
		return 1.0
	var dist: float = sqrt(seg_sq)
	var drive_speed: float = dist / arrival_time
	if max_speed > 0.0:
		drive_speed = minf(drive_speed, max_speed)
	var dir_x: float = dx / dist
	var dir_z: float = dz / dist
	# A defender the carrier has genuinely BEATEN is dropped first: behind along
	# the drive AND slower along it, so it can't strip a puck driving off. A man
	# AHEAD (a wall, a head-on rush) or one MATCHING the drive pace is never
	# dropped.
	var min_perp_sq: float = INF
	var n: int = opponents.size()
	var has_vels: bool = opponent_vels.size() == n
	for i: int in n:
		var op: Vector3 = opponents[i]
		var ovx: float = opponent_vels[i].x if has_vels else 0.0
		var ovz: float = opponent_vels[i].z if has_vels else 0.0
		var along_now: float = (op.x - from.x) * dir_x + (op.z - from.z) * dir_z
		var opp_drive_speed: float = ovx * dir_x + ovz * dir_z
		if along_now < -LANE_BEATEN_BEHIND_M and drive_speed > opp_drive_speed + LANE_BEATEN_PACE_M_S:
			continue   # behind and out-skated — beaten, shed
		var px: float = op.x + ovx * arrival_time
		var pz: float = op.z + ovz * arrival_time
		var pdx: float = px - from.x
		var pdz: float = pz - from.z
		var t: float = (pdx * dir_x + pdz * dir_z) / dist
		if t <= 0.0 or t >= 1.0:
			continue
		var perp_x: float = px - (from.x + dir_x * t * dist)
		var perp_z: float = pz - (from.z + dir_z * t * dist)
		var perp_sq: float = perp_x * perp_x + perp_z * perp_z
		if perp_sq < min_perp_sq:
			min_perp_sq = perp_sq
	if min_perp_sq == INF:
		return 1.0
	return clampf(sqrt(min_perp_sq) / CARRY_PATH_CLEAR_RADIUS_M, 0.0, 1.0)

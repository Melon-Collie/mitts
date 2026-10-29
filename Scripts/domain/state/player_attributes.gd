class_name PlayerAttributes
extends RefCounted

# A skater's build: two continuous body dials (HEIGHT in inches, WEIGHT in
# pounds) plus four discrete gear slots (skate profile, blade curve, stick flex,
# stick length — 0/1/2, 1 = the default). Every axis is lateral, so validation only
# coerces into range and never rejects. Neutral is 6'1" / 201 lbs / all-balanced,
# where every multiplier is 1.0 and the build plays the controller's defaults.
#
# What each dial routes to, and why: Scripts/domain/state/CLAUDE.md.
#
# Tuning tables are private consts read through the named accessors — never
# index a `_*` table outside this file. To add a "height/weight X scales Y"
# rule: a 5-vec table (`_FOO_H` at ANCHOR_INCHES, or `_FOO_F` at the frame
# anchors lean→heavy), an accessor returning `_h(...)` / `_f(...)`, and a
# captured base multiplied in SkaterController.apply_attributes or
# SkaterAppearanceCoordinator.apply.

# Every inch from 5'7" to 6'8" is playable; tables interpolate between the
# anchor rows.
const HEIGHT_MIN: int = 67     # 5'7"
const HEIGHT_MEDIUM: int = 73  # 6'1"  (neutral)
const HEIGHT_MAX: int = 80     # 6'8"

# Height table rows. 5'10" (row 1) is the mesh-native anchor where the
# reach/height multiplier is exactly 1.0. The two OUTER rows continue their end
# segment's per-inch slope rather than being free anchors —
#
#     V80 = V79 + (V79 − V76)/3        V67 = V68 − (V70 − V68)/2
#
# — so 5'8"–6'7" read exactly what a table anchored at 5'8"/6'7" gives. Rebalance
# both end rows by that rule if the range moves. The 4-decimal constants are
# those halvings carried to 4 places so 5'8" and 5'9" stay bit-exact.
const ANCHOR_INCHES: Array[int] = [67, 70, 73, 76, 80]  # 5'7"..6'8"

# ── Weight band ───────────────────────────────────────────────────────────────
# lbs = BMI·in²/703, bounded by a BMI interval and an absolute floor; fitted to
# a 46-player sample of listed NHL heights and weights.
#
#   • BMI is the right normalizer: ln(weight) on ln(height) regresses at an
#     exponent of 2.01, and BMI has no usable drift with height. Mean 26.05,
#     SD 1.61.
#   • The lean edge is two floors. A RATIO floor (23.0) governs 5'11" and up,
#     set just under the leanest real bodies there (Reichel 6'0"/170 = 23.05,
#     then a 23.6–23.9 cluster; 6'4" lands at 189, clearing Dobson 195 and
#     Rinzel 194). An ABSOLUTE floor (MIN_PLAYABLE_LBS) governs 5'7"–5'10",
#     where the ratio would allow 147–160 lb.
#   • The heavy edge (29.0) lands on Kaprizov (5'10"/202). Each edge excludes
#     ~2 tail bodies rather than stretching to an outlier.
#
# The band is ASYMMETRIC about BMI_MEDIUM (3.0 lean-side, 2.5 heavy-side): the
# empirical centre is 26.05, but the neutral is pinned to the 6'1"/201
# NHL-average frame every default is authored at. frame_t() is piecewise about
# it so the neutral still lands on exactly 0.5.
const BMI_LEAN: float = 23.0
const BMI_MEDIUM: float = 26.5   # neutral frame
const BMI_HEAVY: float = 29.0

# The lightest player in the NHL (Lane Hutson, 5'9"/162). The lightest bodies
# at the neighbouring short heights (Stankoven 5'8"/165, Garland 5'10"/165)
# clear it.
const MIN_PLAYABLE_LBS: int = 162

# BMI 26.5 at 73" → round(26.5·73²/703) = 201. mass_mult is linear in it, a
# 0.79..1.28 spread across the band: mass is the physical system, feeding
# delivery and brace through the collision resolver's reduced-mass math. If
# that proves too swingy, compress with an exponent ((lbs/201)^p, p ≤ 1).
const NEUTRAL_WEIGHT_LBS: float = 201.0

# ── Gear slots ───────────────────────────────────────────────────────────────
# Every slot is 0/1/2 with 1 = the default option. Discrete and chunky by
# design — never sliders.
const GEAR_BALANCED: int = 1

# Skate profile: three skates, no plain one. Stability is the default and the
# league base, so its leans are all 1.0.
const PROFILE_SHIFTY: int = 0     # tight space: edges, first step, the stance
const PROFILE_STABILITY: int = 1  # backward: the gap-control skate
const PROFILE_POWER: int = 2      # open ice: top end, glide, crossovers

const CURVE_CLOSED: int = 0      # flattest ladder, best backhand
const CURVE_BALANCED: int = 1
const CURVE_OPEN: int = 2        # steepest ladder, worst backhand

const FLEX_LOW: int = 0          # whippy: the wrist-shot stick — more shot without body load
const FLEX_MEDIUM: int = 1
const FLEX_HIGH: int = 2         # stiff: the slapshot stick — bigger slapper, longer wind-up

# The retail stiffness ladder — the flex numbers sticks actually ship in.
const FLEX_LADDER: Array[int] = [65, 75, 85, 100, 110]

# Shaft stiffness per pound of body at a matched fit. The half-bodyweight rule
# of thumb overshoots what players actually shoot; 0.42 puts the 201 lb neutral
# on an 85, the most-shipped number, and leaves one rung of headroom at both
# ends of the ladder for the gear pick to shift into.
const _MATCHED_FLEX_PER_LB: float = 0.42

const LENGTH_SHORT: int = 0      # −reach, snappiest reversal, finest close control
const LENGTH_STANDARD: int = 1
const LENGTH_LONG: int = 2       # +reach / tip speed / contest momentum, +inertia

# ── Height tables (rows at ANCHOR_INCHES) ─────────────────────────────────────
# Height trades the long frame (reach, shot power) against the short one
# (burst, turns, a quicker wind-up). Top speed is NOT a height lever: if size
# bought speed, every build would be the tallest one. It is the skates' alone.

# First-step burst: a shorter leg cycles its stride faster. Linear at 1.2% an
# inch about the neutral height.
const _ACCEL_H: Array[float] = [1.072, 1.036, 1.000, 0.964, 0.916]

# Turn rate / brake / facing / lateral grip. Small-favored.
const _AGILITY_H: Array[float] = [1.065, 1.020, 1.000, 0.960, 0.920]

# Charged-shot ceiling. Big-favored — the leverage a long frame loads into a
# shot — and the slapper wind-up with it: the long lever takes longer to load.
const _SHOT_H: Array[float] = [0.880, 0.940, 1.000, 1.050, 1.103]

# Mesh Y-scale, arm length, hand heights. Mesh-native 5'10" (row 1) is 1.0,
# not the 6'1" gameplay neutral.
const _HEIGHT: Array[float] = [0.9565, 1.000, 1.043, 1.086, 1.143]

# Stick cut to the body at ~0.65× the height deviation from 5'10" — real sticks
# track height only loosely…
const _STICK_LEN: Array[float] = [0.9715, 1.000, 1.028, 1.056, 1.093]
# …and the LENGTH slot leans that cut ±4% rather than picking an absolute
# length, so max height + LONG can't stack reach past the tuned corner.
const _LENGTH_LEAN: Array[float] = [0.960, 1.000, 1.040]  # SHORT / STANDARD / LONG

# Adult heads are nearly constant across statures, so the helmet moves a few
# percent rather than with the body — what sells a tall build as big, not
# zoomed.
const _HEAD_BULK: Array[float] = [0.935, 0.98, 1.00, 1.03, 1.07]

# ── Gear leans (indexed by the slot, 0/1/2) ───────────────────────────────────
# SKATE PROFILE — where a skater's skating lives. Each wins one kind of ice and
# pays in another, about the Stability base:
#   SHIFTY     tight space: agility (turn, stop, grip), first step, the Shift
#              stance's grip and side-step. Pays the top end and the coast.
#   STABILITY  backward: thrust and top speed skating backward (gap control).
#              Pays the crossover push across its facing.
#   POWER      open ice: top speed, glide, and the crossover push across its
#              facing (building speed wide with the shoulders squared to the
#              play). Pays the corners, the stance, and backward skating.
# Top speed is the profiles' alone (~21.5–23.3 mph). Stacked with the body,
# agility runs ~0.83 (6'8" heavy power) to ~1.16 (5'7" lean shifty).
const _PROFILE_SPEED_LEAN: Array[float] = [0.96, 1.00, 1.04]    # shifty / stability / power
const _PROFILE_AGILITY_LEAN: Array[float] = [1.06, 1.00, 0.94]
const _PROFILE_ACCEL_LEAN: Array[float] = [1.04, 1.00, 1.00]
const _PROFILE_GLIDE_LEAN: Array[float] = [1.03, 1.00, 0.96]    # drag mult: lower = coasts better
# On the controller's Stability base (crossover 0.84, backward 0.90, stance
# grip 2.0, side-step 1.2): shifty 0.90 / 0.80 / 2.4 / 1.4, power 1.00 / 0.74 /
# 1.8 / 1.1.
const _PROFILE_CROSSOVER_LEAN: Array[float] = [1.07, 1.00, 1.19]
const _PROFILE_BACKWARD_LEAN: Array[float] = [0.89, 1.00, 0.82]
const _PROFILE_STANCE_GRIP_LEAN: Array[float] = [1.20, 1.00, 0.90]
const _PROFILE_SIDESTEP_LEAN: Array[float] = [1.17, 1.00, 0.92]

# STICK FLEX — a stiff shaft pays off only when a big swing bends it; a whippy
# one bends under less. So stiff is the slapshot stick: a bigger slapper that
# needs a longer wind-up to load (the charge lean goes WITH the power lean, as
# height's does — a lateral slot trades, never stacks).
# Whippy is the wrist-shot stick: the shaft carries more of a wrister the torso
# can't load (wrister_unloaded_share 0.70 / 0.60 / 0.50 at the controller's 0.6
# base). The wrister ceiling is flex-free, so the two break even on a fully
# loaded wrister.
const _FLEX_SLAP_LEAN: Array[float] = [0.94, 1.00, 1.06]    # whippy / medium / stiff
const _FLEX_CHARGE_LEAN: Array[float] = [0.92, 1.00, 1.10]  # slapper wind-up time
const _FLEX_UNLOADED_LEAN: Array[float] = [7.0 / 6.0, 1.00, 5.0 / 6.0]
# How far the shaft visibly bows under the same shot — cosmetic, and
# exaggerated past the stiffness ratio so the stick reads from the game camera.
const _FLEX_BEND_LEAN: Array[float] = [1.40, 1.00, 0.65]

# BLADE CURVE — M88 / M92 / M28, modelled on the P88 / P92 / P28 patterns. Each
# loft level is a set launch angle from the pattern's ladder, steeper on the
# open blade at every rung; the level names the shot (a goalie-posture height)
# and the gear names the range it lands it at (M88 8.5 m, M92 6.0 m, M28
# 4.5 m). Design of record: docs/elevation-rework-plan.md §1. No LOW rung sails
# even off a max slapper.
const _CURVE_LOFT_LOW_DEG: Array[float] = [5.0, 5.5, 6.4]      # M88 / M92 / M28
const _CURVE_LOFT_MID_DEG: Array[float] = [6.9, 8.2, 10.0]
const _CURVE_LOFT_HIGH_DEG: Array[float] = [8.9, 11.0, 13.6]
# The rest of the trade, about the M92: the M88's flatter face has the best
# backhand (0.75 base × 1.08 stays under forehand parity), stays square through
# a slapper's heel contact (slapper power only), and cradles harder feeds; the
# M28 pays all three.
# The reception lean scales the deflect ceiling, never pickup_max_speed, so soft
# passes settle on every blade.
const _CURVE_BACKHAND_LEAN: Array[float] = [1.08, 1.00, 0.90]
const _CURVE_SLAP_LEAN: Array[float] = [1.03, 1.00, 0.97]
const _CURVE_RECEPTION_LEAN: Array[float] = [1.07, 1.00, 0.93]

# ── Frame tables (rows lean→heavy at frame_t 0/.25/.5/.75/1) ──────────────────
# First-step burst. Lean = quicker; heavy trades it for momentum, which the
# collision math carries through mass and the glide through girth. Multiplies
# the height baseline.
const _ACCEL_F: Array[float] = [1.080, 1.040, 1.000, 0.980, 0.970]

# F = mv²/r: at fixed leg strength more mass is a wider arc and a longer stop —
# the counterweight that makes weight a seesaw rather than a free mass buy.
# Multiplies the height baseline.
const _AGILITY_F: Array[float] = [1.030, 1.015, 1.000, 0.980, 0.960]

# ── Top speed / carry ─────────────────────────────────────────────────────────
# The normalization span the skate profile's speed lean sits in.
const _SPEED_MULT_MIN: float = 0.955
const _SPEED_MULT_MAX: float = 1.060
# Burst-band ceilings across the span — the NHL EDGE 20–25 mph band.
const TOP_SPEED_MIN: float = 1.07
const TOP_SPEED_MAX: float = 1.164
# Carry retention = base + band position × gain (~0.947–0.972). The base is
# written as the sum it derives from so the neutral value stays exact.
const CARRY_BASE: float = 0.92 + 0.07 * (0.15 / 0.39)
const CARRY_SPEED_GAIN: float = 0.025

# ── State ─────────────────────────────────────────────────────────────────────
var height: int = HEIGHT_MEDIUM
var weight: int = int(NEUTRAL_WEIGHT_LBS)
var profile: int = GEAR_BALANCED
var curve: int = GEAR_BALANCED
var flex: int = GEAR_BALANCED
var length: int = GEAR_BALANCED


func _init(p_height: int = HEIGHT_MEDIUM, p_weight: int = 0,
		p_profile: int = GEAR_BALANCED, p_curve: int = GEAR_BALANCED,
		p_flex: int = GEAR_BALANCED, p_length: int = GEAR_BALANCED) -> void:
	height = coerce_height(p_height)
	weight = coerce_weight(height, p_weight)
	profile = _clamp_gear(p_profile)
	curve = _clamp_gear(p_curve)
	flex = _clamp_gear(p_flex)
	length = _clamp_gear(p_length)


# The neutral build (6'1"/201, all-balanced).
static func neutral() -> PlayerAttributes:
	return PlayerAttributes.new()


# ── Weight band helpers ───────────────────────────────────────────────────────
# Displayed pounds for a BMI at a height: lbs = BMI·in²/703 (the BMI formula
# inverted). All band math routes through here so the interval stays single-
# sourced.
static func weight_for_bmi(inches: int, bmi: float) -> int:
	var h: int = clampi(inches, HEIGHT_MIN, HEIGHT_MAX)
	return int(roundf(bmi * float(h * h) / 703.0))


# The leaner of the two bounds never wins: the ratio floor and the absolute
# playable-mass floor are both real, so the band starts at whichever is higher.
static func weight_min(inches: int) -> int:
	return maxi(weight_for_bmi(inches, BMI_LEAN), MIN_PLAYABLE_LBS)


static func weight_max(inches: int) -> int:
	return weight_for_bmi(inches, BMI_HEAVY)


static func weight_neutral(inches: int) -> int:
	return weight_for_bmi(inches, BMI_MEDIUM)


# Clamp a pounds value into the height's band. Zero/negative means "no stored
# weight" (a defaulted wire arg or a roster card that omits it) and coerces to
# the height's neutral frame.
static func coerce_weight(inches: int, lbs: int) -> int:
	if lbs <= 0:
		return weight_neutral(inches)
	return clampi(lbs, weight_min(inches), weight_max(inches))


# Frame position 0..1 across the band (0 = LEAN, 0.5 = MEDIUM, 1 = HEAVY) —
# the height-independent "how heavy for my frame" quantity the frame tables
# index by, and what the picker preserves when the height slider moves.
# Measured in the INTEGER pounds band the player actually sees (not raw BMI):
# the band edges land exactly on 0/1 and the neutral 73"/201 lands exactly on
# 0.5, so the rounded display weight can't nudge a neutral build off the 1.0
# multipliers (raw BMI of 201 lbs is 26.515, a ~0.3% lerp leak).
func frame_t() -> float:
	return frame_t_for(height, weight)


# PIECEWISE about MEDIUM — each half of the band maps onto half of frame-t. The
# band is asymmetric (the lean side is wider, see the band block above), so a
# single lerp across [min, max] would slide the neutral build off 0.5 and cost
# it its 1.0 multipliers. Splitting at MEDIUM pins all three anchors exactly
# (min → 0, neutral → 0.5, max → 1) at every height, including the heights
# where MIN_PLAYABLE_LBS truncates the lean half.
static func frame_t_for(inches: int, lbs: int) -> float:
	var mid: float = float(weight_neutral(inches))
	var w: float = float(lbs)
	if w <= mid:
		var lo: float = float(weight_min(inches))
		return clampf(0.5 * (w - lo) / maxf(mid - lo, 1.0), 0.0, 0.5)
	var hi: float = float(weight_max(inches))
	return clampf(0.5 + 0.5 * (w - mid) / maxf(hi - mid, 1.0), 0.5, 1.0)


# Inverse of frame_t_for: the displayed pounds at a frame position. This is the
# frame-anchor constructor — LEAN/LIGHT/MEDIUM/SOLID/HEAVY are t = 0/.25/.5/
# .75/1 — and what the picker rides when the height slider moves, so a lean
# build stays lean as it grows.
static func weight_for_frame_t(inches: int, t: float) -> int:
	var mid: float = float(weight_neutral(inches))
	var f: float = clampf(t, 0.0, 1.0)
	if f <= 0.5:
		return int(roundf(lerpf(float(weight_min(inches)), mid, f / 0.5)))
	return int(roundf(lerpf(mid, float(weight_max(inches)), (f - 0.5) / 0.5)))


# Format an inches value as feet'inches" (e.g. 73 → 6'1").
static func inches_label(inches: int) -> String:
	return "%d'%d\"" % [inches / 12, inches % 12]


# ── Body: skating and shooting ────────────────────────────────────────────────
# The skate profile's top-speed lean — body-free by design. Not applied
# directly; top_speed_mult and carry_speed_mult are read off it.
func speed_mult() -> float:
	return _PROFILE_SPEED_LEAN[profile]


# max_speed multiplier. The speed lean counts twice: once raw, and again
# through its position in the 20–25 mph burst band, so the profile spread
# reaches either end of that band. Neutral build = 1.0.
func top_speed_mult() -> float:
	var s: float = speed_mult()
	return s * _top_speed_ceiling(s) / _top_speed_ceiling(1.0)


# How much of top speed survives carrying the puck (higher = less penalty).
func carry_speed_mult() -> float:
	return CARRY_BASE + _speed_band_t(speed_mult()) * CARRY_SPEED_GAIN


# Height baseline × frame term (F = mv²/r — mass widens the arc and lengthens
# the stop) × profile lean. Feeds turn / brake / facing / lateral grip.
func agility_mult() -> float:
	return _h(_AGILITY_H, height) * _f(_AGILITY_F) * _PROFILE_AGILITY_LEAN[profile]


# Glide drag (the velocity-proportional term): drag over mass, with frontal
# area ∝ sqrt(mass·height), is sqrt(height/mass) — exactly 1 / girth. So a
# heavy-for-his-height body coasts and a tall lean one scrubs speed. The profile
# lean applies too, since blade contact length is the glide surface.
func glide_drag_mult() -> float:
	return _PROFILE_GLIDE_LEAN[profile] / girth_mult()


func accel_mult() -> float:
	return _h(_ACCEL_H, height) * _f(_ACCEL_F) * _PROFILE_ACCEL_LEAN[profile]


# The skate profile's leans on the push across the facing (crossover strides),
# on backward thrust and top speed, and on the Shift stance's grip and side-step.
func crossover_mult() -> float:
	return _PROFILE_CROSSOVER_LEAN[profile]


func backward_mult() -> float:
	return _PROFILE_BACKWARD_LEAN[profile]


func stance_grip_mult() -> float:
	return _PROFILE_STANCE_GRIP_LEAN[profile]


func sidestep_mult() -> float:
	return _PROFILE_SIDESTEP_LEAN[profile]


# Linear in displayed weight — see NEUTRAL_WEIGHT_LBS.
func mass_mult() -> float:
	return float(weight) / NEUTRAL_WEIGHT_LBS


# Charged-wrister ceiling — the height baseline. Slappers read slapper_power_mult.
func shot_power_mult() -> float:
	return _h(_SHOT_H, height)


# Slapper ceiling: the height baseline × the flex and blade-curve leans.
func slapper_power_mult() -> float:
	return shot_power_mult() * _FLEX_SLAP_LEAN[flex] * _CURVE_SLAP_LEAN[curve]


# Scales wrister_unloaded_share — the share of a wrister the shaft carries with
# no torso load behind it.
func wrister_unloaded_mult() -> float:
	return _FLEX_UNLOADED_LEAN[flex]


# Slapper wind-up time, WITH power on both axes: the big frame's harder shot
# takes longer to load, and so does the stiff stick's. Small builds get the
# quicker release.
func shot_charge_mult() -> float:
	return _h(_SHOT_H, height) * _FLEX_CHARGE_LEAN[flex]


# ── Body: geometry ────────────────────────────────────────────────────────────
# Lateral girth from constant body density: cross-section ∝ mass/height, so
# girth = sqrt(mass/height), normalized to 6'1"/201. A taller body at a fixed
# BMI is absolutely broader yet relatively narrower; a short heavy one keeps
# near-neutral width on a shorter frame. Every lateral body part and the hitbox
# radius wear it. The band bounds it to ~[0.93, 1.10].
func girth_mult() -> float:
	return sqrt(mass_mult() / (float(height) / float(HEIGHT_MEDIUM)))


func height_mult() -> float:
	return _h(_HEIGHT, height)


func head_bulk_mult() -> float:
	return _h(_HEAD_BULK, height)


func stick_len_mult() -> float:
	return _h(_STICK_LEN, height) * _LENGTH_LEAN[length]


# ── Gear: blade curve and flex ────────────────────────────────────────────────
func curve_backhand_mult() -> float:
	return _CURVE_BACKHAND_LEAN[curve]


# Scales the deflect ceiling + squared-up bonus a receiver's blade can soak —
# the blade shape's force limit, read at the reception decision sites.
func reception_ceiling_mult() -> float:
	return _CURVE_RECEPTION_LEAN[curve]


# tan(launch angle) per loft level from this pattern's ladder. Every rung sits
# under ShotMechanics.MAX_LOFT_RATIO.
func curve_loft_tan_low() -> float:
	return tan(deg_to_rad(_CURVE_LOFT_LOW_DEG[curve]))


func curve_loft_tan_mid() -> float:
	return tan(deg_to_rad(_CURVE_LOFT_MID_DEG[curve]))


func curve_loft_tan_high() -> float:
	return tan(deg_to_rad(_CURVE_LOFT_HIGH_DEG[curve]))


# The steepest any pattern launches a shot: how high a puck can be lifted over
# a given distance from the blade, whoever shoots it.
static func steepest_loft_tan() -> float:
	return tan(deg_to_rad(_CURVE_LOFT_HIGH_DEG.max()))


# Cosmetic shaft bow, so the pick reads on the ice.
func stick_bend_mult() -> float:
	return _FLEX_BEND_LEAN[flex]


# The stick's real stiffness number, for display only. Weight picks the matched
# rung of the retail ladder and the FLEX slot shifts it one rung either way, so
# the numbers overlap across bodies the way stick fitting does. No multiplier
# reads it: a number-driven lean would route weight into shot power.
func flex_number() -> int:
	return flex_number_for(weight, flex)


static func flex_number_for(lbs: int, p_flex: int) -> int:
	# The matched rung is clamped off both ends of the ladder, so the gear
	# shift always lands on a real rung instead of saturating.
	var matched: int = clampi(_nearest_flex_rung(float(lbs) * _MATCHED_FLEX_PER_LB),
			1, FLEX_LADDER.size() - 2)
	return FLEX_LADDER[matched + _clamp_gear(p_flex) - GEAR_BALANCED]


# ── Serialization ─────────────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"height": height, "weight": weight,
		"profile": profile, "curve": curve, "flex": flex, "length": length,
	}


# Rebuilds from a dict; missing keys default to neutral (weight to the height's
# neutral frame), and the constructor coerces every axis.
static func from_dict(d: Dictionary) -> PlayerAttributes:
	return PlayerAttributes.new(
			int(d.get("height", HEIGHT_MEDIUM)),
			int(d.get("weight", 0)),
			int(d.get("profile", GEAR_BALANCED)),
			int(d.get("curve", GEAR_BALANCED)),
			int(d.get("flex", GEAR_BALANCED)),
			int(d.get("length", GEAR_BALANCED)))


func equals(other: PlayerAttributes) -> bool:
	if other == null:
		return false
	return height == other.height and weight == other.weight \
			and profile == other.profile and curve == other.curve \
			and flex == other.flex and length == other.length


# ── Internal ──────────────────────────────────────────────────────────────────
# Position of a speed lean across the normalization span, 0..1.
static func _speed_band_t(speed: float) -> float:
	return clampf((speed - _SPEED_MULT_MIN) / (_SPEED_MULT_MAX - _SPEED_MULT_MIN), 0.0, 1.0)


static func _top_speed_ceiling(speed: float) -> float:
	return lerpf(TOP_SPEED_MIN, TOP_SPEED_MAX, _speed_band_t(speed))


# Bracketing anchor rows for a height in inches: [lo_row, hi_row, t] where the
# interpolated value is lerp(row[lo], row[hi], t).
static func _anchor(inches: int) -> Array:
	var h: int = clampi(inches, HEIGHT_MIN, HEIGHT_MAX)
	for i: int in range(ANCHOR_INCHES.size() - 1):
		if h <= ANCHOR_INCHES[i + 1]:
			var span: float = float(ANCHOR_INCHES[i + 1] - ANCHOR_INCHES[i])
			var t: float = 0.0 if span <= 0.0 else float(h - ANCHOR_INCHES[i]) / span
			return [i, i + 1, t]
	var last: int = ANCHOR_INCHES.size() - 1
	return [last, last, 0.0]


# 5-vec lookup interpolated by height.
static func _h(table: Array[float], inches: int) -> float:
	var a: Array = _anchor(inches)
	return lerpf(table[a[0]], table[a[1]], a[2])


# 5-vec lookup interpolated by frame position. The anchors are evenly spaced in
# FRAME-T (0/.25/.5/.75/1) — not in BMI, which the asymmetric band leaves
# uneven — so frame_t maps linearly onto the row axis.
func _f(table: Array[float]) -> float:
	var pos: float = frame_t() * float(table.size() - 1)
	var lo: int = clampi(int(floorf(pos)), 0, table.size() - 2)
	return lerpf(table[lo], table[lo + 1], pos - float(lo))


static func coerce_height(v: int) -> int:
	return clampi(v, HEIGHT_MIN, HEIGHT_MAX)


static func _clamp_gear(v: int) -> int:
	return clampi(v, 0, 2)


# Nearest rung of the retail flex ladder to a raw stiffness value.
static func _nearest_flex_rung(value: float) -> int:
	var best: int = 0
	for i: int in range(1, FLEX_LADDER.size()):
		if absf(value - float(FLEX_LADDER[i])) < absf(value - float(FLEX_LADDER[best])):
			best = i
	return best

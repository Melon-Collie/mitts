class_name SkaterController
extends Node

# ── State Machine ─────────────────────────────────────────────────────────────
# Type alias so the subclasses and their callers can write `State.X`.
const State = SkaterStateMachine.State
var _sm: SkaterStateMachine = SkaterStateMachine.new()

# ── Movement Tuning ───────────────────────────────────────────────────────────
# Field meanings and units: SkaterMovementRules.MovementConfig.
var thrust: float = GameRules.DEFAULT_SKATER_THRUST_M_S2
# Push power runs out above this speed — 0→5 m/s in ~0.6 s, top speed in ~2 s.
var power_knee_speed: float = GameRules.DEFAULT_SKATER_POWER_KNEE_M_S
# Glide: ~12 s to coast down from top speed. Real ice glides several times
# longer; this keeps momentum a thing to manage without making the rink skid.
var friction: float = 0.35
var friction_drag: float = 0.09
var max_speed: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S
var move_deadzone: float = 0.1
var stop_decel: float = GameRules.DEFAULT_SKATER_STOP_DECEL_M_S2
var reverse_skid_fraction: float = GameRules.DEFAULT_SKATER_REVERSE_SKID_FRACTION
# The shuffle (Space + stick, SkaterMovementRules.is_shuffle): its pace, m/s,
# and the ground one step-together covers, m.
var shuffle_speed: float = 1.2
var shuffle_step_distance: float = 0.4
var turn_accel: float = GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2
var max_turn_rate: float = GameRules.DEFAULT_SKATER_MAX_TURN_RATE_RAD_S
# Edge grip; per-build value = base × agility_mult in apply_attributes (the
# skate profile is part of agility_mult). Turn radius at speed rides this.
var lateral_grip: float = 1.0
var puck_carry_speed_multiplier: float = 0.92  # pre-apply default; per-build value is PlayerAttributes.carry_speed_mult
# The Stability skate's (the default profile); the others lean them.
var backward_thrust_multiplier: float = 0.90
var crossover_thrust_multiplier: float = 0.84
var backward_max_speed_multiplier: float = 0.90
# Ceiling on the velocity fed to the gait during the faceoff / intro skate-in
# (see begin_approach / apply_approach). The glide always completes in a fixed
# duration, so a far start implies a high velocity — clamp it here so the stride
# animation reads as a hard skate rather than over-spinning past its range.
var approach_max_gait_speed: float = 9.0
# ── Stance Tuning ─────────────────────────────────────────────────────────────
# The stance (Shift) is low and loaded: twice the edge grip for choppy strides
# and a lower cap. Field meanings: SkaterMovementRules.MovementConfig.
var stance_grip_mult: float = 2.0
# 3 m/s² of bleed on a full-lock cut at top speed: at ×2 grip the excess there is
# turn_accel, so the scrape is that bleed over turn_accel.
var stance_scrape: float = 3.0 / GameRules.DEFAULT_SKATER_TURN_ACCEL_M_S2
var stance_stride_mult: float = 0.6
var stance_max_speed_mult: float = 0.85
# ── Hit-Button (Body-Check Commit) Tuning ─────────────────────────────────────
# The hit button (Ctrl / input.hit_held) commits a check: it delivers the full
# body-check transfer (see Skater.hit_passive_transfer_mult for the uncommitted
# floor), and pays for it by pulling the stick off the ice — while committed you
# can't poke, receive a pass, or corral a loose puck (gated in
# PuckController/PickupClaim on the replicated skater.hit_committed) — and by
# skating loaded on a shoulder: less grip, weaker strides. A commit loaded early
# is visible and can't follow a carrier who cuts; one thrown late costs almost
# nothing. Deterministic from the replicated input.hit_held, so every cost
# re-derives through reconcile replay.
var commit_grip_mult: float = 0.6
var commit_stride_mult: float = 0.5
# Commit stance (cosmetic): while the Hit button is held the skater visibly loads
# up for the check — leans into it, sinks into a crouch, drives the leading
# shoulder forward across the chest with the near arm tucked, and (empty-handed
# only) pulls the stick up off the ice. Three parts on two clocks: the lean and
# crouch are a render-rate trunk blend (GaitCheckLayer), the per-side
# shoulder load-up is physics-rate on the skater (CheckStanceRules), and the
# stick rides the IK's blade_y. All three derive from the replicated
# skater.hit_committed, so they read on every machine, and all three are
# gameplay-inert while committed. Deliberately pronounced — the commitment (and
# the withdrawn stick) has to be legible to the player and their opponent.
#
# The lean is deliberately the smallest of the three: past roughly 20° a skater
# reads as reaching for something rather than coiling behind a shoulder, so the
# pitch sets the attitude and the shoulder carries the read.
var hit_commit_lean_deg: float = 14.0         # forward trunk lean into the check
var hit_commit_crouch_m: float = 0.03         # tall over the feet — the stance is the low pose
var hit_commit_blade_lift_m: float = 0.22     # stick raise off the ice on an empty-handed commit
# Loaded stick pose: while committing (empty-handed), the stick STOPS chasing the
# cursor and eases to a body-local "ready to hit" pose, so the stance reads as a
# distinct silhouette instead of a raised-but-still-tracking stick. A BEARING off
# the posed hand, not a blade position — the blade sits one (choked) stick along
# it, so how far out it lands is the choke's business and this is purely which
# way the stick points. Dimensionless XZ: +x is the forehand side (×
# blade_side_sign), −z is in front of the skater. The sweep is signed by the lead
# (Skater.get_check_lead), which keeps the stick out of the shoulder driving into
# the contact and moves the silhouette WITH the shoulders. Gameplay-inert — the
# blade is withdrawn from puck play while committed, so this is a pure cosmetic
# override that eases back to cursor tracking on release. Feel dials; verify the
# silhouette in-game.
var hit_commit_blade_bearing_x: float = 0.25   # forehand-side lean of the loaded stick
var hit_commit_blade_bearing_z: float = -1.0   # −z = pointing ahead of the skater
var hit_commit_blade_sweep: float = 0.35       # bearing shift toward the TRAILING side
# Where the top HAND holds the loaded stick, body-local. Posed rather than left
# to the blade-first solve, which parks it at the shoulder and folds the elbow
# backwards — see SkaterIKCoordinator._commit_hand_pose. In FRONT of the
# shoulder (−z) is the load-bearing part: the arm roots at the leaning,
# load-displaced shoulder, so a hand at the body plane ends up BEHIND its own
# root. +x is the forehand side (× blade_side_sign).
var hit_commit_hand_local_x: float = 0.12
var hit_commit_hand_local_y: float = 0.05
var hit_commit_hand_local_z: float = -0.40
# Choke-up while committed, as a fraction of this skater's own stick, so it
# scales with the build for free. With the hand posed and the blade derived one
# stick along the loaded bearing, this is the dial that decides how far out that
# blade sits: choke harder and the stick is held in tighter. The shaft itself is
# rigid — SkaterStickRig gives back out of the butt whatever the grip takes, so
# the drawn stick keeps its length and only the grip moves.
var hit_commit_choke_frac: float = 0.10
var hit_commit_pose_speed: float = 9.0        # how fast the stance eases in/out
# ── Body-Check Stagger Tuning ─────────────────────────────────────────────────
# Getting checked hard staggers the victim: a temporary thrust and grip penalty,
# scaled by how hard the hit landed (the m/s transfer impulse). stagger_timer
# (seconds) holds the recovery window AND drives the penalty depth — a harder hit
# sets a longer timer, easing back to full as it decays. Flat for every player in
# v1 (the hit strength already reflects the attacker's Size/Physical/Speed and the
# victim's mass). Pure math in BodyCheckRules; deterministic and replicated so it
# survives reconcile replay.
#
# Grounded to the inelastic magnitudes: the delivered victim impulse is
# closing_speed × transfer × m_a/(m_a+m_b), so at a MEDIUM build (transfer 0.65,
# equal mass → ×0.5) it is ~0.325 × closing. The ref point is deliberately the SAME
# as the puck-strip threshold (Puck.body_check_strip_threshold, 1.35): a hit hard
# enough to count as a full check is exactly a hit hard enough to knock the puck
# loose. That lands a full check + strip at ~4 m/s closing for a medium build
# (~3.4 for a heavy one) — "square them up and skate into them with some pace".
# Closing past the ref keeps scaling the impulse linearly into the knockdown band
# below, so a full-speed / head-on collision is a bigger hit: a ceiling, not a
# requirement. Still feel tunables.
var stagger_min_impulse: float = 0.6       # m/s transfer delta below which a hit doesn't stagger
var stagger_ref_impulse: float = 1.35      # m/s transfer delta treated as a full-strength check (== puck-strip threshold)
var stagger_max_seconds: float = 1.0       # recovery window of a full-strength check
var stagger_max_thrust_penalty: float = 0.5  # peak thrust reduction at full stagger
var stagger_max_grip_penalty: float = 0.4    # peak edge-grip reduction at full stagger
# Cosmetic stumble while staggered: a decaying trunk wobble layered into the
# gait's trunk texture (GaitStaggerLayer). Amplitude tracks the time
# left on stagger_timer, and the wobble phase is derived FROM the timer, so
# every machine renders the identical stumble from the replicated value.
var stagger_wobble_deg: float = 9.0   # peak trunk wobble at full stagger
var stagger_wobble_hz: float = 3.0    # wobble frequency
# Directional recoil: on top of the wobble, the whole torso reels the way the
# hit shoved it (pitch + roll), easing out as stagger_timer decays — a body
# absorbing the check, not just shaking. Direction is the transfer impulse
# (stagger_recoil_dir, replicated). Applied in SkaterPoseCoordinator._apply_lean.
var stagger_recoil_deg: float = 13.0  # peak torso recoil lean at full stagger
# ── Rocked Tuning ─────────────────────────────────────────────────────────────
# A full check (stagger_ref_impulse and up) rocks its man: the stagger timer
# runs past stagger_max_seconds, and while it does his stick is off the ice, his
# stance and commit are gone and his edges deeper gone (BodyCheckRules, the
# rocked band). Measured in docs/hit-outcomes-plan.md.
var rocked_ref_impulse: float = 2.6      # m/s: a full-speed committed check at equal builds
var rocked_min_seconds: float = 0.5      # rocked window at stagger_ref_impulse
var rocked_max_seconds: float = 0.8      # ... at rocked_ref_impulse and beyond
var rocked_grip_penalty: float = 0.75    # peak edge-grip reduction, rocked
# The torso reels this far at the top of the rocked band, eased down onto the
# stagger's recoil as he comes out of it; the skates splay and he sits into
# them as he catches himself.
var rocked_recoil_deg: float = 30.0
var rocked_splay_m: float = 0.16         # each skate out from under its hip
var rocked_crouch: float = 1.0           # crouch floor (× stance_hip_deg), under the stance's
var rocked_catch_rate: float = 15.0      # the catch's ease rate: a step out in ~0.15 s
# ── Knockdown Tuning ──────────────────────────────────────────────────────────
# A full check that beats his balance (BodyBalanceRules: the part of his Δv his
# feet can't carry off, against what his base, his sight of the hitter, his
# posture and his height can take) KNOCKS HIM DOWN — movement locked, no puck
# interaction, the body slides from the hit and bleeds speed via
# knockdown_friction — for the fall to the ice, a lie growing with how far past
# it the hit landed (BodyCheckRules.lie_seconds_from_overshoot) and the get-up,
# so the get-up never starts before he is down. knockdown_timer rides the
# SAME replicated / snapped / decayed rail as stagger_timer. At these values a
# square, upright man rides any one-sided check below top speed, and a side hit
# floors him from ~6 m/s closing at equal builds (docs/hit-outcomes-plan.md).
var balance_ref_dv: float = 2.4            # m/s a square, upright, reference-height man rides
var balance_along_share: float = 0.5       # share of a hit along his blades that tips him
var balance_sight_behind: float = 0.6      # his balance with his back to the hitter
var balance_vulnerable_mult: float = 0.6   # ... mid-shot: a wind-up, a load, a follow-through
var balance_checker_front_share: float = 0.4  # a committed checker takes his own hit at this
var knockdown_ref_overshoot: float = 1.7   # past his balance by this, the longest knockdown
var knockdown_lie_min_seconds: float = 0.15  # on the ice before the get-up, just past his balance
var knockdown_lie_max_seconds: float = 0.7   # ... at knockdown_ref_overshoot: ~1.9 s down in all
var knockdown_friction: float = 2.0  # m/s² a downed body sheds sliding on its gear: μ ≈ 0.2, padded nylon on ice
# Knockdown pose (cosmetic): a downed player FALLS — the knees buckle into the
# collapse crouch that matches the gait's drop, the whole cosmetic rig tips
# about the skates in the hit direction under a tipping-body model
# (KnockdownFallRules, applied to MeshRoot via Skater.set_knockdown_fall),
# bounces off the ice, and lies ON it: the torso fold resolves from a reflexive
# airborne curl to the ground-plane complement (fold_at) and the limbs scatter
# from first impact by the hit's momentum and side (sprawl_into), so the lying
# pose is solved per hit rather than one authored keyframe. All driven off the
# replicated knockdown_timer (elapsed down-time = _knockdown_total − timer), so
# it renders identically on every machine and through reconcile, like the
# stagger stumble.
# knockdown_getup_seconds is the tail of the window spent getting up, staged
# knees → one knee → skates (KnockdownFallRules.lie_share and its siblings); the
# lying pose holds full while more than this much time remains.
var knockdown_pose_drop_m: float = 0.3     # buckle sink — the tilt does the lying-down
var knockdown_fold_deg: float = 20.0       # airborne torso curl; resolves to lie-flat on landing
var knockdown_getup_seconds: float = 0.8
# Back on his skates he finds his legs: a stagger this long, leaning forward.
var knockdown_getup_stagger_seconds: float = 0.5
# Fall model tunables (KnockdownFallRules.Config — units and physical
# justifications live on the fields there).
var knockdown_fall_buckle_seconds: float = 0.1
var knockdown_fall_accel: float = 6.0
var knockdown_fall_settle_deg: float = 84.0
var knockdown_fall_restitution: float = 0.3
var knockdown_fall_rest_omega: float = 0.7
var knockdown_fall_com_height_m: float = 0.95
var knockdown_fall_max_entry_omega: float = 4.2
# Head-ward extent of the tipped body (height + a little stick/arm slack): both
# the obstacle probe distance and the reach the deflection budgets against
# (KnockdownFallRules.wall_safe_fall_dir), so a fall near the glass or the goal
# net lies along the obstacle instead of through it.
var knockdown_fall_body_reach_m: float = 1.9
# A diver's top arm reaches this share of its length out along the layout,
# short of locked straight.
const DIVE_ARM_STRETCH: float = 0.85
# The get-up's held top hand, from its shoulder: down and forward, metres; the
# stick's bearing off straight ahead toward the stick side.
const GETUP_HAND_DROP_M: float = 0.3
const GETUP_HAND_FWD_M: float = 0.35
const GETUP_STICK_SPREAD_DEG: float = 25.0
var knockdown_brace_in_seconds: float = 0.15  # arms pull into the brace over this
# Downed-leg sprawl (KnockdownFallRules.sprawl_into): the scatter window after
# first ice contact, and the free leg's outward splay at a maximal hit.
var knockdown_sprawl_in_seconds: float = 0.25
var knockdown_sprawl_splay_deg: float = 18.0
# ── Facing Tuning ─────────────────────────────────────────────────────────────
# How fast facing drifts toward the cursor during normal play. Lower = more
# skating lag before the body re-orients (more backskate/crossover time).
# Good range: 1.0 (very lazy) – 3.0 (snappy).
var facing_drag_speed: float = 5.0
var facing_drag_speed_braking: float = 10.0
# How fast the body winds up a turn, rad/s²: a pivot's rate in ~50 ms, an aim
# flick's in two or three ticks (FacingRules.turn_rate).
var facing_turn_accel_max: float = 300.0
# Where a skating skater's body heads (FacingRules); setup() derives the reach
# edges from the ROM below, a carrier's backhand edge from its carry stop.
var facing_rules: FacingRules.Config = FacingRules.Config.new()
var carry_facing_rules: FacingRules.Config = FacingRules.Config.new()
# Facing RECOVERY rate during the shot follow-through. The coil freezes facing at
# the wind-up cursor position (it must — the coil is the torso twisting relative
# to the planted lower body), so at release the body is squared to where the aim
# STARTED, not the cursor. Left at the normal drag, facing can't re-square in a
# soft wrister's short follow-through, so when blade-tracking resumes the target
# is ROM-clamped to the stale facing and the stick swings to the wrong side
# before catching the cursor. Recover hard through the follow-through, toward
# the finish's own aim (the shot line, eased back to the cursor over its tail),
# so the hips hold the finish with the torso and are squared to the cursor by
# the handoff.
var follow_through_facing_recover_speed: float = 18.0

# ── Blade / Stick / Top-Hand IK Tuning ────────────────────────────────────────
# Blade world-space Y. 0.0 = ice surface. Converted to upper-body-local via
# SkaterIKCoordinator.blade_y_local() before any IK or pose call, so the blade always sits at a
# fixed world height regardless of where the upper body anchor is placed in the
# scene. This also means crouching (block stance) doesn't pull the blade
# through the ice — the local Y compensates automatically.
var blade_height: float = 0.03
# World-space height of a full lift (a stick lift, a tie, a forced pop) and the
# top of a deflect's rise (Skater.deflect_lift_share), eased by
# Skater._blade_lift_blend. Contact point = blade_height + this.
# CEILING 0.5675: a fully lifted blade plays only airborne pucks, so contact point
# − PuckController.PICKUP_RADIUS must stay at or below the airborne threshold
# (0.0675 above the ice), or some pucks are touchable by neither plane. 0.52 sits
# at the top, so a deflect reaches a net-front feed arriving at 0.9–1.1 m.
var blade_lift_height: float = 0.52
# Fixed, rigid shaft length (hand to blade heel). Baseline 1.30 m ≈ adult
# senior stick shaft (butt-to-heel). The blade mesh extends forward from the
# heel; see Skater.blade_length. Total hand-to-toe is stick_length + blade_length.
var stick_length: float = GameRules.DEFAULT_STICK_LENGTH_M
# Hand Y in upper-body-local space. Baseline resting position (used in the FAR
# regime); in the CLOSE regime the hand rises toward `hand_y_max` so the stick
# tilts more vertical and the blade can tuck in close to the body.
#
# This export is the MESH-NATIVE (Size L2, 5'10") value; apply_attributes scales it
# by height_mult, matching the appearance pass scaling the whole skeleton about the
# ice plane — so the hand sits at the same body point (0.50 m × height below the
# shoulder) on every build instead of pinning to one absolute height.
#
# The upper body rides at height_mult × 1.0 m world Y (FACEOFF_SPAWN_HEIGHT is the
# physics origin for every build — only the mesh skeleton scales; the cosmetic
# skating crouch lowers it up to ~7 cm at speed) and the blade at blade_height
# (~ice), so -0.10 gives a hand world Y of 0.90 m × height (hip height on each
# frame) and a rest stick angle of ~42° at L2, approaching a real lie-5 address
# (~45°). The steeper stick pulls the rest carry circle in ~6 cm (stick_horiz
# 1.03 → 0.97), but the shallower shoulder-to-hand drop re-aims the arm budget
# sideways (derived backhand ROM 0.37 → 0.46 m of hand displacement), so rim reach
# is roughly preserved and the directional reach lean stays pure bonus on top.
var hand_rest_y: float = -0.10
# Ceiling for hand Y in the CLOSE regime. When aiming very close to the
# skater, the hand rises to shorten the stick's horizontal projection; this
# cap keeps the pose anatomical (0.30 local = 1.30 m world at L2 — the hand
# won't climb past chest level). Mesh-native like hand_rest_y; apply_
# attributes scales it by height_mult so the ceiling stays chest-height on
# every frame. With default stick_length = 1.30 m and the blade on the ice
# (blade_y ≈ -0.97 local at L2), hand_y_max = 0.30 → hand-to-blade drop
# 1.27 → min horizontal stick reach ≈ 0.28 m.
var hand_y_max: float = 0.30
# Asymmetric ROM for the top hand (measured from shoulder in upper-body-local
# horizontal plane, expressed in "forehand side = positive angle" convention).
# The rim is a half-ellipse (TopHandIK.rim_reach): longest straight ahead,
# limited across the body, full extension out to the backhand side.
var rom_forehand_angle_max_deg: float = 90.0
var rom_backhand_angle_max_deg: float = 90.0
# Reach caps are DERIVED in apply_attributes (see _ROM_FOREHAND_OF_ARM).
var rom_forward_reach_max: float = 0.51
var rom_forehand_reach_max: float = 0.39
var rom_backhand_reach_max: float = 0.42
# Fraction of full arm extension the backhand ROM rim uses. 1.0 solves the
# reach with a ramrod-straight arm; slightly under keeps a hint of elbow bend
# at max extension so the rim pose stays organic.
var rom_arm_extension: float = 0.97
# Board shield (see BoardPlayRules): how close the boards must be before a
# CARRIER's stance starts turning parallel to them, and how far it may turn. The
# probe is roughly a stick-and-arm reach, so the shield engages exactly when the
# wall starts eating the blade's reachable set rather than at some earlier
# distance; the cap stops at "square along the boards" — the real pinned posture
# — which is what the max is measuring toward, not a feel curve to taste.
var board_shield_probe: float = 1.1
var board_shield_max_deg: float = 55.0
# Cap on how fast the aim target can move in world XZ per second. The IK consumes
# the smoothed target, so the blade visibly inherits the cap. Sits in the
# dangle-speed range (~8-14 m/s): a medium player's full ROM span is ~1.18 m, so
# 10 m/s crosses it in ~118 ms. This is the neutral build's cap; apply_attributes
# scales it by the build's blade lever (see max_blade_accel). Tune UP if
# deliberate aim feels laggy, DOWN if fast dangling feels too easy — a live-feel
# call that cannot be measured headless.
var max_blade_speed: float = 10.0
# Second-order blade: acceleration cap (m/s²) on the dangle velocity — the
# stick's INERTIA. Direction REVERSALS pay the cost, traverse speed doesn't.
# Per-build value derives from lever geometry in apply_attributes: cap ∝
# 1/lever^k — a long stick sweeps faster (tip speed below) but can't cut back
# as fast; a short stick is the scalpel. This is the hands seesaw of
# attributes v4 — geometry, never a fidelity table. The shipped 250 was
# playtest-calibrated across the min/neutral/max builds; 0 disables inertia
# entirely (the pre-v4 first-order servo, bit-exact).
var max_blade_accel: float = 250.0
# The k in cap ∝ 1/lever^k. Raw physics is k=2 (I ∝ mL²), but reversal time
# then scales ~L³ across the build range — too brutal. The model's FORM is
# physical; the exponent is feel — 1.6 is the playtest-calibrated spread
# (scalpel↔scythe contrast reads clearly without breaking the scythe).
var blade_inertia_exponent: float = 1.6

# ── Nudge (self-tap, nutmeg setup) ────────────────────────────────────────────
# Tap the deflect button (Q) while carrying in plain SKATING_WITH_PUCK to push the puck a
# tiny amount off the blade — a self-pass for threading the puck between a
# defender's legs (the body block only covers the torso now, so a grounded puck
# slips under). The released puck inherits the skater's horizontal velocity plus
# a small nudge along the blade's current motion direction, so RELATIVE to the
# carrier it's just a soft tap in the stick's sweep direction — keep skating and
# you re-collect it. nudge_speed is that relative tap speed (m/s).
var nudge_speed: float = 2.2

# Fraction of the carrier's horizontal momentum the nudged puck inherits. Below
# 1.0 the puck drifts back RELATIVE to the carrier while skating (faster skating
# → bigger drift), opening the nutmeg gap instead of the puck keeping perfect
# pace. Stationary it's a no-op (skater velocity ~ 0). Keep close to 1.0 so the
# carrier can still re-collect after the gap opens.
var nudge_velocity_retain: float = 0.85

# ── Bottom-Hand IK Tuning ─────────────────────────────────────────────────────
# The bottom hand is purely reactive: each tick it targets a point a short way
# down the stick shaft (from the top hand toward the blade). It releases toward
# a free-hand rest only when the blade's world angle exceeds the upper body's
# rotation limit — ensuring the hand stays connected during any normal swing.
# Never influences blade placement. See domain/rules/bottom_hand_ik.gd.
# Fraction along the shaft (0 = top hand, 1 = blade heel) that the bottom hand
# grips. ~0.25 on a 1.30 m shaft ≈ a typical hockey grip width.
var bottom_hand_grip_fraction: float = 0.25
# Fine-tune Y offset added to the bottom hand's shaft-derived grip height
# (SkaterIKCoordinator.update_bottom_hand lerps top-hand Y toward blade Y at
# the grip fraction, then adds this). 0.0 = grip sits exactly on the shaft.
var bh_hand_y: float = 0.0
# Blade world angle (from skater forward, toward backhand) at which the bottom
# hand starts releasing toward its rest. Match upper_body_max_twist_deg
# so the hand releases exactly when the body can no longer rotate to follow.
var bh_release_angle_deg: float = 67.0
# Degrees past bh_release_angle_deg over which the hand blends to full rest.
var bh_release_angle_band_deg: float = 15.0
# How far round the forehand a carrier's cursor goes before the hips yield to it
# (FacingRules.yield_on_forehand). The two-hand reach stops the blade at ~145°
# on every build; yielding from well inside that spreads the hips' turn over the
# sweep (test_carry_hips_yield.gd).
var carry_forehand_yield_deg: float = 110.0
# How far beyond the bottom arm's reach the nearest point of the shaft may lie
# before that hand has fully let go of the stick (m). The hand slides up the
# shaft first (BottomHandIK.reachable_grip); this band is the letting go.
var bh_reach_release_band_m: float = 0.08
# A let-go hand's rest off its shoulder, arm lengths (x out, y up, z back).
var bh_free_hand_rest_arm: Vector3 = Vector3(0.2, -0.52, -0.35)
# Its swing at full stride (SkaterIKCoordinator._free_hand_swing), arm lengths
# at the front of the swing: in toward the body, a little up, forward. The back
# of the swing mirrors it.
var bh_free_hand_swing_arm: Vector3 = Vector3(-0.12, 0.06, -0.28)
# Both hands on, the drawn top hand's pump across the body at full stride
# (SkaterIKCoordinator._stride_pump), metres in the upper body's frame.
var stride_hand_pump_m: Vector3 = Vector3(0.035, 0.01, 0.0)
# How quickly the bottom hand lets go and takes hold (rad/s, critically damped):
# about a third of a second either way.
var bh_release_omega: float = 15.0

# ── Upper Body Tuning ─────────────────────────────────────────────────────────
var upper_body_twist_ratio: float = 0.8
var upper_body_max_twist_deg: float = 67.0   # caps rotation so extreme angles don't over-rotate
var upper_body_return_speed: float = 6.0
# Upper-body twist follow-through (secondary motion) — a damped spring trails
# the tracked twist so the shoulders whip through a fast cut and settle instead
# of tracking rigidly. Renders the tracked angle plus the spring's lag; zero at
# steady state. follow_gain 0 restores rigid tracking.
var upper_body_follow_gain: float = 0.4        # how far the shoulders overshoot the whip
var upper_body_follow_stiffness: float = 110.0  # spring constant (higher = quicker catch-up)
var upper_body_follow_damping: float = 18.0     # damping (near-critical — a clean settle)
# Reach lean — the torso tips TOWARD the blade (SkaterPoseCoordinator
# .compute_upper_body_lean_target), to the side cap out either side and the
# forward cap straight ahead (_reach_lean_max_deg). It extends reach at the rim
# by only a few cm (the blade IK solves in the leaned frame); mostly it is how
# far the skater visibly lunges. engage_power > 1 keeps the torso quiet mid-ROM
# and commits the lean near full extension.
# The forward cap sits on top of the skating posture's own fold
# (velocity_lean_forward_max_deg), so the two together stay a reach, not a dive.
# Scaled by the stick's purpose (SkaterIKCoordinator.reach_purpose): with nothing
# to reach for the trunk keeps its posture.
var upper_body_lean_max_deg: float = 15.0
var upper_body_lean_forward_max_deg: float = 14.0
var upper_body_lean_engage_power: float = 1.6
var upper_body_lean_return_speed: float = 8.0
# Reach purpose (ReachPurposeRules): the puck's nearest approach over the next
# lookahead, against a band past the rim of the build's full reach. Inside
# `near` the stick reaches; from `far` out it rests in at two hands.
var reach_purpose_lookahead_s: float = 0.35
var reach_purpose_near_m: float = 0.3
var reach_purpose_far_m: float = 1.8

# ── Velocity Lean / Skating Posture Tuning ────────────────────────────────────
# Trunk lean INTO travel, eased toward a target from velocity on the simulating
# machine (SkaterPoseCoordinator.compute_velocity_lean_target) and replicated
# as SkaterNetworkState.posture_lean. Forward
# skating folds the torso forward into the attack posture that makes skating
# read as skating; backward skating sits slightly back. The lower body follows
# the pitch only fractionally — the legs stay under the hips while the trunk
# folds.
var velocity_lean_forward_max_deg: float = 20.0
var velocity_lean_back_max_deg: float = 6.0
var velocity_lean_speed: float = 6.0
var lower_body_pitch_follow: float = 0.35

# ── Lower Body Lag Tuning ─────────────────────────────────────────────────────
var lower_body_lag_max_deg: float = 20.0
var lower_body_lag_speed: float = 5.0

# ── Skating Stride Tuning ─────────────────────────────────────────────────────
# Procedural leg gait — see SkaterSkatingCoordinator. All cosmetic.
# The pace the gait and the skating posture read as full speed, per unit of leg
# length (the reader multiplies by the skater's leg_scale). It is the body's,
# never the build's own top speed: a skater looks the way his body skates at a
# speed, whatever skates he wears. Pinned so the neutral build reads its
# league-default top speed as full pace.
var gait_full_speed: float = GameRules.DEFAULT_SKATER_MAX_SPEED_M_S \
		/ PlayerAttributes.neutral().height_mult()
var stride_cadence: float = 1.4          # low-speed slope: radians of stride phase per metre skated
var stride_cadence_max_rate: float = 6.5  # rad/s ceiling the cadence saturates toward (caps top-speed leg turnover)
var accel_cadence_rate: float = 18.0      # rad/s stride rate at full effort (stride_effort_ref_accel), any speed
var carve_ref_turn_rate: float = 1.6   # rad/s of travel turn that reads as a full carve (pivot veto, glide tuck)
var carve_min_speed: float = 2.5       # m/s floor — slow turns are steps, not crossovers
var carve_engage_speed: float = 5.0    # turn-rate smoothing rate
# Crossovers as a foot path (SkaterLocomotion._crossover_path), metres from
# under each skate's own hip at full stroke intensity: lateral toward the turn's
# inside, so the outside skate lands crossed over and the inside one pushes
# under the body.
var crossover_cross_m: float = 0.30    # outside skate lands this far inside its hip
var crossover_out_m: float = 0.12      # outside skate pushes back out this far past its hip
var crossover_side_m: float = 0.05     # inside skate lands this far inside its hip
var crossover_under_m: float = 0.25    # inside skate pushes under the body this far
var crossover_back_m: float = 0.12     # both pushes end this far behind the hips
var crossover_land_fwd_m: float = 0.05 # both land this far ahead of the hips
var crossover_lift_m: float = 0.08     # recovery lift: the over-step clears the inside shin
var crossover_pass_m: float = 0.08     # the over-step passes in front, the inside recovery behind
# Crossover cadence: the over-step and under-push alternate halves of the
# cycle (two-beat), and the feet step per radian of heading change rather than
# by straight-line speed.
var crossover_phase_per_turn: float = 7.0  # stride-phase rad per rad of heading change
var carve_stance: float = 0.75         # stance floor at full carve — sit low to hold the edges
var carve_lead_m: float = 0.20         # the carve's inside skate leads the outside one
# Gliding — releasing all movement keys settles the legs to rest (the stride
# is input-gated, v15 intent byte) while this floor keeps working knees under
# a coasting skater, scaled by speed.
var glide_stance: float = 0.5
var rest_stance: float = 0.4        # stance floor standing still: soft knees, never locked
var stride_intensity_speed: float = 6.0   # how fast the legs ease in/out of motion
var stride_skew: float = 0.3              # push/recovery asymmetry of the stroke (0 = pure sine)
# The forward stride as a foot path (SkaterLocomotion._stride_path), metres of
# ankle travel per unit of stroke amplitude (intensity · push_scale, ~1 at
# cruise, up to stride_push_ceiling driving hard), at full extension.
var stride_push_out_m: float = 0.28       # out from under the hip
var stride_push_back_m: float = 0.20      # back from under the hip
var stride_land_fwd_m: float = 0.05       # where the recovery lands, ahead of the hip
var stride_lift_m: float = 0.05           # recovery lift off the ice
var vee_push_speed: float = 2.5           # m/s the leg drives a skate out: with the ground speed, how far a start's V turns out
var vee_toe_max_deg: float = 50.0         # the V's toe-out at a standstill
var stride_rock_m: float = 0.04           # both skates shift under the body toward the support leg
var stride_toe_out_deg: float = 25.0      # push skate turned out at full extension
var stride_sit_max_deg: float = 45.0      # deepest hip flex the stride sits to for its push's reach
var stride_bob_m: float = 0.02            # vertical body bob per half-stride (weight transfer)
var stride_sway_deg: float = 2.1          # torso weight-shift roll oscillating with the stride
# Trunk inertia at the texture seam: the trunk texture sums many reads and
# each carries residual step/noise from its input; the trunk — the body's
# most massive segment — cannot physically re-orient at those frequencies.
# One first-order tracker on the SUMMED texture models that inertia (the
# stagger wobble bypasses it — a stumble is supposed to shake). 0 = off.
var trunk_texture_smooth_rate: float = 14.0
# Glide-vs-push: stride amplitude scales above/below the speed baseline by the
# sign of tangential acceleration — driving digs in, coasting settles to a glide.
var stride_effort_ref_accel: float = 9.0  # m/s^2 of tangential accel mapping to full push effort
var stride_effort_speed: float = 5.0      # how fast the glide<->push effort signal eases
var stride_push_gain: float = 0.7         # how far effort drives amplitude off the speed baseline
var stride_glide_floor: float = 0.35      # min amplitude scale when coasting (the glide)
var stride_push_ceiling: float = 1.5      # max amplitude scale when driving hard
# Stance — the speed-engaged crouch. The skater sits into flexed hips/knees as
# soon as they're moving with intent; SkaterSkatingCoordinator derives the
# matching knee flex and body drop from the leg geometry so one export drives
# an anatomically consistent crouch that keeps the skates planted on the ice.
var stance_hip_deg: float = 22.0            # static hip flex at full stance
var stance_full_speed_fraction: float = 0.45  # fraction of full gait pace at which the crouch fully engages
var stance_push_gain: float = 0.35          # effort deepens (push) / shallows (glide) the stance
# Faceoff ready stance — during the FACEOFF_PREP countdown the speed-driven
# crouch is floored at faceoff_stance (players are at a standstill, so the
# intensity envelope alone would leave them bolt upright) and the feet
# stagger fore/aft (stick-side foot back, braced for the draw). Phase is
# replicated, so every machine poses its skaters identically.
var faceoff_stance: float = 0.85       # stance engagement floor at the dot
var faceoff_split_deg: float = 9.0     # fore/aft leg stagger at the dot
# The centre taking the draw holds a far deeper pose than the players lined up
# behind him (see Scripts/controllers/CLAUDE.md). Multiples of the same stance
# and split levers, so a build's own leg geometry still decides the knee angle
# and the body drop that keeps the skates on the ice.
var faceoff_center_stance: float = 2.6      # crouch floor at the dot (× stance_hip_deg)
var faceoff_center_split_deg: float = 13.0  # fore/aft foot split at the dot
var faceoff_center_lean_deg: float = 48.0   # chest folded over the dot (trunk texture)
# Lateral splay of BOTH legs — the wide base under the fold. A sit this deep
# over feet at hip width reads as a squat rather than an address; the width is
# what makes it a brace. The splay shortens each leg's vertical span by its
# cosine, so the gait pays the deficit as extra body drop and gives the angle
# back at the ankles, or the skates leave the ice on their outside edges.
var faceoff_center_width_deg: float = 16.0
# How far down the shaft the centre's bottom hand slides for the draw, against
# bottom_hand_grip_fraction's ordinary carry grip (0 = at the top hand, 1 = at
# the blade). A draw is won with the short lever, and the wide grip is half of
# what an address looks like.
var faceoff_center_grip_fraction: float = 0.55
# And how far down it the TOP hand slides, as a fraction of the stick. This is
# the lever that decides where the address's hands end up: the hand rides one
# stick-length up from a blade on the dot, so at full length a body folded over
# the dot has to hold it at shoulder height, arms collapsed. Choked, the hand
# comes down in front of the chest where a centre actually holds it.
var faceoff_center_choke_frac: float = 0.17
# How far above its carry height the address lets the top hand rise, in metres
# of upper-body-local Y (see SkaterIKCoordinator._address_hand_ceiling). This is
# where the hands sit in the address, and with the choke above it is what sets
# the shaft's angle over the dot.
var faceoff_center_hand_rise: float = 0.05
# Fraction of the ADDRESS stick span at which this skater's CENTER spawns from
# the faceoff dot — reach-derived so a Size-1 center (short stick + arms) can
# play the drop as comfortably as a Size-5 (see faceoff_center_distance).
#
# 1.0 is the shaft's own natural projection, and the useful side is just PAST
# it: there the hand comes off the body toward the dot (TopHandIK's FAR regime)
# and the arms open into the address. Short of 1.0 the hand instead rides up
# its ceiling and the arms fold shut under the shoulders.
var faceoff_center_reach_fraction: float = 1.1
# Faceoff-draw swipe capture (see Skater.begin_draw_tracking / FaceoffDrawRules).
# A center's blade-swipe crest is retained through the draw so the contest reads
# the sweep, not the raw tick-at-contact velocity — this is what lets a well-aimed
# swipe actually land. faceoff_draw_peak_decay (m/s per second) sets how long a
# crest lingers (~crest/decay seconds), giving a natural pre-roll while forgetting
# an early guess; faceoff_draw_window auto-ends tracking that long after the drop.
# The timing REWARD curve lives with the contest resolver (PuckController.contest_
# draw_timing_*). Read by PhaseCoordinator when it arms the two centers.
var faceoff_draw_peak_decay: float = 12.0
var faceoff_draw_window: float = 1.0
# Hockey stop — the brake with the stick in line turns the lower body across
# the travel direction (legs sideways, torso still on the play) on a wide base
# of two planted, edged skates; the side latches as it comes on
# (HockeyStopRules.latch_side).
var hockey_stop_min_speed: float = 3.0   # m/s floor — no stop pose from a shuffle
var hockey_stop_max_yaw_deg: float = 70.0  # lower-body turn cap across travel
# The stop as where its skates go (SkaterLocomotion._stop_path), metres.
var hockey_stop_spread_m: float = 0.10   # each skate out past its hip: a wide base along travel
var hockey_stop_lead_m: float = 0.28     # both skates set toward travel: the hips sit back of them
var hockey_stop_stagger_m: float = 0.05  # the skate on the travel side a little ahead
var hockey_stop_stance: float = 0.9      # stance floor while stopping (deep knees)
# Tight turn (the stance with the travel curving): two blades dug in under a
# deep sit, inside skate leading, no crossovers — the bank does the leaning.
var tight_turn_stance: float = 0.9       # stance floor while digging the turn
var tight_turn_lead_m: float = 0.30      # inside skate leads the outside one
# Hip-to-travel alignment — the lower body yaws toward the direction of
# MOTION (torso keeps facing the cursor) so the legs stride along travel
# instead of flailing through the crossover/backward blends whenever cursor
# and movement disagree. Clamped: misalignment beyond the cap still plays
# the backward C-cut / crossover gaits on the residual, as designed.
var hip_align_max_deg: float = 50.0  # cap on the hips' turn toward travel
var hip_align_speed: float = 6.0     # how fast the hips settle onto the travel line
# Pivot — the facing↔travel swap (PivotRules; the pivot block in
# SkaterSkatingCoordinator). ψ = travel direction in the body frame; a pivot
# is ψ transiting the lateral band at speed, driven by |dψ/dt| — facing
# whipping against travel, which a coordinated carve (both rotating together)
# never produces. While engaged the hips hold the entry orientation past the
# alignment clamp, gliding the old line under the swinging torso, then step
# around to the exit orientation over the transit's tail. Derived entirely
# from replicated facing + velocity, so every machine reads the identical
# pivot; phase comes from ψ itself, so an aborted swing unwinds cleanly.
var pivot_band_lo_deg: float = 50.0   # ψ where the transit begins — matches hip_align_max_deg for a seamless handoff
var pivot_band_hi_deg: float = 130.0  # ψ where the transit completes
var pivot_rate_min: float = 2.5       # rad/s of |dψ/dt| that reads as a pivot, not a drifting cursor
var pivot_min_speed: float = 2.5      # m/s floor — pivoting is a gliding move; slow spins are steps
var pivot_step_begin: float = 0.6     # transit fraction where the hips step around to the exit line
var pivot_depth_ramp_deg: float = 50.0  # ψ depth past the band edge over which the hold earns full authority — the aim-flick guard
var pivot_commit_time: float = 0.22   # seconds ψ must DWELL in the band before full authority — a flick returns sooner, a pivot parks
var pivot_yaw_speed: float = 12.0     # hip tracking ease while pivoting (hip_align_speed is too lazy to hold ψ)
var pivot_stride_fade: float = 0.85   # stride suppression while engaged — pivots glide, they don't stride
var pivot_stance: float = 0.8         # stance floor — the step-around needs bent knees
var pivot_mohawk_deg: float = 50.0    # lead-skate external rotation at the transit's middle (heel-to-heel V); negative mirrors the lead choice
var pivot_blend_speed: float = 8.0    # engage/release ease of the whole read
# Locomotion states (LocomotionRules, SkaterLocomotion): the physics' own split
# of the stick against travel, crossfaded.
var locomotion_blend_speed: float = 8.0  # ease rate of the state weights
# Crossovers come on slower: a quick steering correction rides the edges, and
# only a turn held long enough is skated with crossovers.
var crossover_commit_speed: float = 3.0
# The start: first strides from a standstill are quick, short chops.
var dig_in_fade_speed: float = 4.0       # m/s where the start hands off to the speed gait
var dig_in_intensity: float = 0.85       # stride intensity floor while digging in
var dig_in_cadence_rate: float = 4.5     # rad/s stride-phase floor — quick chop from a standstill
var dig_in_chop: float = 0.35            # push-amplitude cut at full dig (short strides)
var dig_in_stance: float = 0.7           # stance floor — power comes from bent knees
# Skid: the stick against travel — fighting momentum to go the other way, a
# snowplow (SkaterLocomotion._skid_path).
var reversal_stance: float = 0.85        # stance floor — sits down hard into the plant
var reversal_spread_m: float = 0.16      # each skate out past its hip
var reversal_lead_m: float = 0.10        # both skates set toward travel
var reversal_toe_in_deg: float = 20.0    # toes turned in, both blades on their inside edges
# Side-step (a push from rest to the side or back): hips square, legs step
# together (SkaterLocomotion._shuffle_path), one cycle per shuffle_step_distance.
var shuffle_intensity: float = 0.6       # stride intensity floor while side-stepping
var shuffle_blend_speed: float = 20.0    # ease rate of the side-step's weight
var shuffle_lift_m: float = 0.05         # a step's lift
var shuffle_stance: float = 1.6          # stance floor — skated low, for the leg a full step and the lean stretch
# Backward skating: C-cuts (SkaterLocomotion._ccut_path), metres per unit of
# stroke amplitude. The blades stay on the ice: each push sweeps out and ahead
# and curls back in, drawing the C.
var ccut_out_m: float = 0.20             # how far out the C bulges
var ccut_front_m: float = 0.20           # how far ahead of the hips it ends
var ccut_return_share: float = 0.25      # how much of the bulge the return keeps, close to centre
var ccut_toe_deg: float = 25.0           # toe out as the C starts, in as it ends
var backpedal_chest_deg: float = 4.0     # chest-up trunk pitch over the C-cuts
# Glide enrichment: coasting (no keys) sways weight edge-to-edge, and a carve
# released into a glide exits the turn weighted on its outside leg.
var glide_sway_deg: float = 1.8          # lazy edge-to-edge roll amplitude
var glide_sway_hz: float = 0.4           # sway frequency — far below stride cadence
var glide_inside_tuck_deg: float = 10.0  # inside-leg knee tuck — weight on the outside edge
# Stance read, off stance_active: the locomotion shortens the stride and deepens
# the sit; GaitStanceLayer poses the low, wide, folded posture over it.
var stance_stride_gain: float = -0.3     # stride amplitude change at full stance
var stance_sit_gain: float = 0.35        # extra stroke crouch in the stance
var stance_crouch: float = 1.7           # crouch floor in the stance (× stance_hip_deg)
var stance_width_m: float = 0.125        # each skate set out from under its hip
var stance_chest_deg: float = 26.0       # chest folded over the knees (trunk texture)
# Cadence "gears" — grounded in on-ice biomechanics: from acceleration to
# sustained max velocity real skaters DROP stride frequency and lengthen the
# glide (speed is power per stride, not faster turnover). cruise_gear (fast AND
# not still accelerating) eases the stride rate down, deepens the sit, and warps
# the stroke toward a longer glide dwell. All zero while accelerating/digging,
# so the start/chop feel is untouched; set these to 0 to restore the prior gait.
var cadence_cruise_falloff: float = 0.28    # max fraction the stride rate eases down at sustained cruise
var glide_hold_skew: float = 0.25           # extra stroke skew at cruise — snappier push, longer glide dwell
var cadence_glide_stance_gain: float = 0.12 # extra sit depth at sustained top speed
# Spring weight transfer (Rosen-style secondary motion) — a damped spring lags
# the lateral weight shift behind the stride so the body rides over the loaded
# leg and settles with follow-through instead of rolling rigidly with it. Adds
# "weight" for almost nothing. weight_shift_deg 0 restores the prior gait.
var weight_shift_deg: float = 1.7           # amplitude of the springy lateral body lean
var weight_spring_stiffness: float = 90.0   # spring constant (higher = snappier follow)
var weight_spring_damping: float = 14.0     # damping (near-critical — a clean settle with slight overshoot)

# ── Wrister Tuning ────────────────────────────────────────────────────────────
var min_wrister_power: float = GameRules.DEFAULT_WRISTER_POWER_MIN_M_S
var max_wrister_power: float = GameRules.DEFAULT_WRISTER_POWER_MAX_M_S
var backhand_power_coefficient: float = 0.75
# ── Wrister load (WristerLoad): what the torso and arms put into a shot ──
# Release cap: max_wrister_power × (this × arms + (1 − this) × load). With no
# turn behind it, the arms, wrists and stick flex still carry a real snap on a
# shot out from the body, and nothing on one back through it. Per-build: the
# flex pick scales it (PlayerAttributes.wrister_unloaded_mult).
var wrister_unloaded_share: float = 0.6
var wrister_full_load_arc_deg: float = 45.0
var wrister_home_reach_deg: float = 120.0
var wrister_away_reach_deg: float = 30.0
var wrister_arm_full_past_tangent_deg: float = 45.0
# ── Wrister power model (ShotMechanics.wrister_power_t) ──
# Power is a feel-curve over the release speed signal (cursor speed for humans,
# a committed target for bots — see _wrister_sweep_speed). power_curve shapes
# where an ordinary flick lands in the band. Feel tunable, NOT attribute-scaled
# (shot_power_mult scales the ceiling).
var wrister_power_curve: float = GameRules.DEFAULT_WRISTER_POWER_CURVE
# ── Pure mouse-speed wrister ──
# Wrister power is a curve over the raw SCREEN-space cursor speed (px/s) — flick
# fast = hard, sweep slow = soft — distance-independent. Direction is still the
# drag vector; power_curve (above) shapes where a flick lands.
# wrister_mouse_speed_full is the cursor speed (px/s) that reads as full power.
# It's PER-SETUP (scales with DPI/resolution), so players calibrate via the
# Shot Power Sensitivity setting rather than this raw reference.
var wrister_mouse_speed_full: float = 2500.0
var wrister_mouse_speed_smoothing: float = 14.0
# Blade-speed budget ALONG the shot axis during a wrister aim (m/s of blade
# travel, applied relative to the skater like max_blade_speed). High so the
# wind-back-and-snap of a wrister tracks responsively; the off-axis
# (lateral/dangle) component stays capped at max_blade_speed. See SkaterIKCoordinator.apply_blade_from_mouse.
var wrister_on_axis_blade_speed: float = 60.0
# Fixed power of the quick pass (blade→cursor snap fired by the dedicated
# quick_pass button). Doubles as the pass speed, so it stays flat for everyone.
var quick_pass_power: float = GameRules.DEFAULT_QUICK_PASS_POWER_M_S
# Loft-level vertical launch speeds (m/s), shared by quick passes, wristers, and
# Loft — the manual angle ladder (docs/elevation-rework-plan.md v3; the full
# story lives on the ShotMechanics loft-level doc). The fixed vertical speeds
# below feed the QUICK-PASS table only (LOW = the saucer pass, MID/HIGH = the
# flip); charged shots ride shot_loft_y — set angles from the curve gear's
# ladder (loft_tan_low/mid/high vars above, set in apply_attributes).
var loft_vertical_speed_low: float = GameRules.DEFAULT_LOFT_VY_LOW_M_S
var loft_vertical_speed_high: float = GameRules.DEFAULT_LOFT_VY_HIGH_M_S

# ── Head Tracking Tuning ─────────────────────────────────────────────────────
var head_track_speed: float = 12.0
var head_track_max_deg: float = 60.0
# A carrier glances down at the puck (degrees of nod) as the hands work it
# (the puck's speed off the body over the band, m/s) and as it comes in tight
# (its distance over the band, m), less as the skater picks up speed: eyes up
# on open ice.
var head_puck_nod_deg: float = 28.0
var head_puck_hands_band: Vector2 = Vector2(1.0, 3.5)
var head_puck_close_band: Vector2 = Vector2(0.9, 0.45)
var head_puck_skate_band: Vector2 = Vector2(3.0, 7.0)

# ── Slapper Tuning ────────────────────────────────────────────────────────────
var slapper_wind_up_height: float = 1.39
# (No separate wind-up duration — the pose fills over max_slapper_charge_time,
# see slapper_wind_up_t(), so the animation IS the charge readout.)
# Full-charge tell: with no charge ring, the wind-up pose IS the gauge, so
# "the coil is maxed" needs a live cue — a small quiver at the apex (the
# shooter straining at the top). Amplitude in metres on the blade height,
# half of it on the top hand.
var slapper_full_quiver_m: float = 0.02
var slapper_full_quiver_hz: float = 9.0
var slapper_zone_radius: float = 0.5
# The stance (SlapperRules): how far the hips open off the shot line — at 90°
# the top hand's shoulder points straight down it — and how far toward the
# front foot, off centre, the puck is played (m). The strike spot follows from
# these and the build (slapper_strike_local).
var slapper_stance_open_deg: float = 90.0
var slapper_strike_front_m: float = 0.1
# How fast the hips pivot into the stance (deg/s): a 90° set-up in about a
# fifth of a second.
var slapper_stance_turn_deg_s: float = 450.0
# Once the feet have set, how far either side of their line the shoulders can
# still turn the aim (deg); further needs the feet set again.
var slapper_aim_arc_deg: float = 20.0
# A carried slapshot's set-up ends once the hips are within this of the stance
# and the puck within this of the strike spot; the puck is pinned where it is.
var slapper_setup_facing_tol_deg: float = 2.0
var slapper_setup_spot_tol_m: float = 0.15
# Calling a slapshot off costs the stick coming back down to the puck (s), from
# a barely started backswing to the top (SlapperRules.recover_time): no shot,
# pass or nudge until it is down, and a press inside it waits for it.
var slapper_recover_min_s: float = 0.1
var slapper_recover_max_s: float = 0.45
var min_slapper_power: float = GameRules.DEFAULT_SLAPPER_POWER_MIN_M_S
var max_slapper_power: float = GameRules.DEFAULT_SLAPPER_POWER_MAX_M_S
var max_slapper_charge_time: float = 0.7
# Wind-up coil: the shoulders turn back from the open hips toward the stick
# side while the top hand comes up and across the chest. The coil fills over
# the FULL charge time (slapper_wind_up_t) — the pose is the charge gauge —
# sqrt-eased so it snaps into motion early and creeps to its apex exactly at
# max charge.
var slapper_wind_up_twist_deg: float = 30.0
# The top hand at full wind-up, in upper-body-local space (m): risen from rest
# to beside the head, carried across the chest toward the stick-side shoulder,
# and held out in front of the chest (forward is −Z) — the arms come up the
# front of the body, never behind the shoulders.
var slapper_wind_up_hand_up: float = 0.65
var slapper_wind_up_hand_forward: float = 0.3
var slapper_wind_up_hand_back: float = 0.0
var slapper_wind_up_hand_inward: float = 0.4
# The blade at full wind-up, off the top hand's shoulder in upper-body-local
# space (m), at slapper_wind_up_height: a stick's length up and out from the
# hand, so the shaft runs from in front of the chest back over the stick-side
# shoulder at about 40° — the loaded one-timer's backswing rather than a stick
# stood on end, which reads from above as nothing at all.
var slapper_wind_up_blade_x: float = 1.25
var slapper_wind_up_blade_z: float = 0.23
# Snappier lerp during the slapshot coil — the default upper_body_return_speed
# is tuned for gentle aim-tracking and lags a fast coil, which reads as a
# half-finished wind-up.
var slapper_wind_up_lerp_speed: float = 18.0
# Seconds after the puck arrives to release before the wind-up cancels back to
# carry. Every peer arms this same honest value for the carrier it is predicting;
# only the HOST simulating a REMOTE carrier adds one_timer_window_lag_grace on
# top, because it armed the window before that carrier could have seen the catch.
var one_timer_window_duration: float = 0.45
# Human timing window, in seconds, either side of the ideal commit. Applied
# ALONG the puck's line (ShotReleaseRules.one_timer_connects), so it forgives
# being early or late — never being wide.
var one_timer_leniency_time: float = 0.08
var one_timer_center_power_bonus: float = 0.10  # ±10%: edge of zone = −10%, dead centre = +10%
# How much of a feed's pace across the shot line a squared, driven face keeps
# (SlapperRules.one_timer_contact); 0 lets a one-timer go where it is aimed.
var one_timer_feed_grip: float = 0.2
# Minimum wind-up (seconds of slapper charge) before an arriving puck opens the
# timed one-timer window. Below it — the "puck was already at the stick when the
# wind-up began" case — a forced window would open at ~zero power and cancel
# straight to carry (a flicker + a shot that never happens). Under this floor the
# catch rolls into a plain slapshot charge instead: keep winding up, release when
# ready. Feel floor, deliberately small so genuine early one-timers still window.
var one_timer_min_windup_time: float = 0.15
# Retention: seconds the committed one-timer swing holds before the puck leaves.
# A real one-timer is not instant — the blade travels down onto the puck, the
# shaft loads against it, and the shot comes off the recoil. This is that beat:
# the shooter is locked in (no cancel), the shaft bows to full load, and the
# release + range check fire at the END of it. Sized to the slapper
# follow-through's own downswing (slapper_downswing_time) so the puck leaves on
# the beat the finish animation already treats as blade contact.
var one_timer_retention_time: float = 0.11

var show_one_timer_indicator: bool = false
# Whether this slapshot's aim arrow is up yet (_update_slapshot_arrow).
var _slapshot_arrow_shown: bool = false

# ── Follow Through Tuning ─────────────────────────────────────────────────────
# Seconds a finish runs, from the softest release of its band to the hardest
# (ShotMechanics.follow_through_time): a harder shot swings the stick higher and
# further, so it takes longer to come back down to the ice. The whole timer is
# FOLLOW_THROUGH, so it is also the lockout — no pickup, shot, pass, block or
# stick check until it ends. The maxima are estimates (no published measurement
# of a finish's length), set from a hard wrister's stick being back on the ice
# ~0.6–0.8 s after release and a full slapper's ~0.9–1.2 s. The quick pass is
# fixed-power, so its finish is too. Every amplitude below additionally scales
# with the shot's follow_through_power, set at release (wrister by charge,
# quick pass fixed low, slapper full).
var wrister_follow_through_time_min: float = 0.22
var wrister_follow_through_time_max: float = 0.7
var quick_pass_follow_through_duration: float = 0.18  # snap pass flick
var slapper_follow_through_time_min: float = 0.5
var slapper_follow_through_time_max: float = 1.0
# The slapper finish's opening beat, wind-up to contact. Seconds, not a share of
# the timer, so a longer finish holds longer rather than swinging down slower.
var slapper_downswing_time: float = 0.11
# Every finish SNAPS out over this, then holds and relaxes over the last
# wrister_whip_release_frac of its timer (SkaterShotPoseCoordinator
# .finish_envelope). Five ticks: shorter and a stick crossing a metre between
# frames reads as a teleport, not a whip.
var whip_attack_time: float = 0.04
# Last fraction of the wrister/quick/slapper FT spent easing the finish aim (torso
# twist + blade) from the shot line back to the LIVE cursor, so the pose ends
# where the mouse actually is and hands off to blade-tracking without re-rotating
# (the "follow-through, then a reset back" read). 0 keeps the pure shot-line
# finish. Blends the aim only in the tail so the shot-line follow-through still
# reads through the meat of the timer.
var follow_through_return_frac: float = 0.4
var wrister_follow_through_min_power: float = 0.55  # amplitude floor at zero charge
var quick_pass_follow_through_power: float = 0.5
var wrister_follow_through_hand_y: float = 0.35
var wrister_follow_through_blade_lift: float = 0.55  # high-finish blade height off the ice
var wrister_follow_through_reach: float = 0.5  # forward hand CARRY along the shot line (= arm extension; the blade reaches a full stick beyond it)
# Last fraction of every finish's timer spent relaxing out of the held pose
# (the snap is whip_attack_time).
var wrister_whip_release_frac: float = 0.45
var wrister_follow_through_twist_deg: float = 45.0   # shoulders explode through the shot (frozen wrister discharges this instantly)
var wrister_release_unwind_speed_deg: float = 1500.0  # the torso unwinding from the coil at the release
var slapper_follow_through_twist_deg: float = 50.0   # full uncoil past the shot line
var follow_through_lean_deg: float = 8.0             # trunk drives forward over the front foot
var follow_through_twist_lerp_speed: float = 15.0  # snap the torso from coil through the overshoot fast
var slapper_follow_through_arc_dist: float = 0.75  # blade XZ travel along the shot line through the finish
var slapper_follow_through_height: float = 0.85    # high-finish blade height off the ice
var slapper_follow_through_hand_y: float = 0.4     # hands rise through the finish
var slapper_follow_through_hand_follow: float = 0.4  # fraction of blade travel the hands follow (limits shaft stretch)

# ── Shot Body Animation Tuning ────────────────────────────────────────────────
# Cosmetic lower-body work for the shots (GaitShotLayer): the load
# sinks the weight onto the stick-side back leg while the charge builds, and
# the release drives it over the front foot with the back leg kicking into
# extension behind — the weight transfer that sells a shot. Wrister and
# slapper share the machinery with their own amplitude sets: the wrister load
# tracks the drag-charge, the slapper load tracks the wind-up (re-derived from
# the replicated charge — see the gait), sits deeper, and coils the hips
# harder under the 80° torso coil; the slapper kick swings bigger and always
# commits (higher min power — the swing is full-body even off a short
# wind-up). Driven entirely from the replicated fields (current_shot_state +
# shot_charge), so local, bot, and remote skaters play the identical animation
# with zero new network state (same contract as the stick flex). The kick
# runs over the finish itself — its length and its envelope — so the legs drive,
# hold and come down with the stick.
var wrister_load_stance: float = 0.55          # crouch floor at full charge (fraction of stance_hip_deg)
var wrister_load_lean_deg: float = 5.0         # shared leg roll: weight over the stick-side back leg
var wrister_load_split_deg: float = 8.0        # foot stagger: stick-side foot drops back
var wrister_load_hip_share: float = 0.85      # share of the torso's wrist-shot wind-up the hips turn with
var wrister_load_blend_speed: float = 6.0      # how fast the load pose tracks the charge (both shots)
var wrister_kick_min_power: float = 0.35       # amplitude floor so snaps and passes still read
var wrister_kick_back_deg: float = 26.0        # back (stick-side) leg drives into extension behind
var wrister_kick_knee_extend_deg: float = 30.0 # back knee straightens through the kick
var wrister_kick_lean_deg: float = 7.0         # shared leg roll: weight lands over the front foot
var wrister_kick_stance: float = 0.5           # front-leg sit through the drive
var wrister_kick_hip_yaw_deg: float = 12.0     # hips uncoil through the shot line
var slapper_load_stance: float = 0.75          # the wind-up sits DEEP — the power position
var slapper_load_lean_deg: float = 7.0         # harder weight-back than the wrister load
var slapper_load_split_deg: float = 2.0        # side-on, the feet barely stagger
var slapper_load_width_m: float = 0.12         # each skate set out from under its hip: the wide side-on base
var slapper_load_hip_coil_deg: float = 16.0    # hips coil under the wound-up torso
var slapper_kick_min_power: float = 0.6        # a slap swing commits the body even off a short wind-up
var slapper_kick_back_deg: float = 34.0        # full back-leg extension through the finish
var slapper_kick_knee_extend_deg: float = 38.0 # back knee straightens hard
var slapper_kick_lean_deg: float = 9.0         # weight lands hard over the front foot
var slapper_kick_stance: float = 0.6           # front-leg sit through the drive
var slapper_kick_hip_yaw_deg: float = 20.0     # hips uncoil hard through the shot line
var shot_stride_fade: float = 0.8              # stride suppression while loading/kicking (glide through the shot)

# ── Body Language Tuning ──────────────────────────────────────────────────────
# Remaining cosmetic body reads (GaitCheckLayer, GaitStickLiftLayer,
# GaitCelebrationLayer). Check delivery fires from the host-authoritative
# body_check_landed broadcast (start_check_drive), so the hitter's drive lands
# the same frame as the burst/thud on every machine; the stick-lift read keys
# off the replicated blade_up; the celebration bounce reads the same timer the
# raised-stick pose uses (started on every machine — see GameManager._trigger_scorer_celebration).
var check_drive_time: float = 0.45        # seconds of shoulder-drive after a landed hit
var check_drive_lean_deg: float = 14.0    # trunk drives INTO the hit at full hardness
var check_drive_stance: float = 0.6       # legs drive under the hit — the finishing base
var stick_lift_trunk_deg: float = 3.0     # slight chest-up pop while working under a stick
var stick_lift_stance: float = 0.2        # coiled working posture while the blade is up
var stick_lift_blend_speed: float = 10.0  # how fast the lift read engages/releases
# Board pin pose (GaitPinLayer): both locked bodies sit low, and lean their
# trunks into the boards — the pinned one pressed flat to the glass, the pinner
# driving in behind him, harder.
var pin_stance: float = 0.6
var pin_pressed_lean_deg: float = 12.0
var pin_drive_lean_deg: float = 18.0
var pin_pose_speed: float = 6.0
# Press pose (GaitPressLayer): the driver sits into a lunge and leans into the
# man; the man dug in sits deep and wide and leans back into the push.
var press_drive_stance: float = 0.7
var press_drive_lean_deg: float = 20.0
var press_drive_split_deg: float = 18.0
var press_anchor_stance: float = 0.9
var press_anchor_lean_deg: float = 22.0
var press_anchor_width_m: float = 0.06
var press_pose_speed: float = 6.0
var celebration_leg_stance: float = 0.6   # knee-pump depth of the celebration bounce, below standing

# ── Celebration Tuning ────────────────────────────────────────────────────────
# Cosmetic raised-stick goal celebration (SkaterShotPoseCoordinator.
# apply_celebration_pose). Bearings are upper-body local with x toward the
# arm's own side and −z forward; reaches are in arm lengths from the shoulder.
var celebration_hand_bearing := Vector3(0.18, 1.0, -0.22)  # the stick arm thrown up, a touch forward
var celebration_hand_reach: float = 0.9      # near full extension, short of a locked elbow
var celebration_hand_pump: float = 0.06      # the arm gives this much at the bottom of each hop
var celebration_stick_bearing := Vector3(0.4, 1.0, 0.12)   # shaft leans out and back, clear of the helmet
var celebration_fist_bearing := Vector3(0.22, 1.0, -0.3)
var celebration_fist_reach_low: float = 0.5  # elbow bent, fist at the face
var celebration_fist_reach_high: float = 0.78  # punched up above the helmet

# ── Shot-Block Tuning ─────────────────────────────────────────────────────────
# Movement speed while blocking (unused while the stance is fully planted; kept for tuning).
var block_speed_multiplier: float = 0.45
# Choreographed "stick down" block pose, authored in upper-body-local space.
# Forward is local −Z (toward the shooter the stance snapped to on entry); the
# stick side is +X for a righty, −X for a lefty (blade_side_sign). The blade lies
# flat on the ice (Y is lean-corrected to ice level); the top hand drops low and
# pushes forward so the shaft lies down across the lane. First-pass numbers —
# tune in the editor (see CLAUDE.md "get it working, then tune numbers").
var block_blade_reach: float = 1.0   # forward blade extension from the shoulder (m, local −Z)
var block_blade_x: float = 0.2       # lateral blade offset to the stick side (m)
var block_hand_forward: float = 0.3  # forward push of the top hand (m, local −Z)
var block_hand_x: float = 0.1        # lateral top-hand offset to the stick side (m)
var block_hand_y: float = -0.10      # top-hand height while blocking (m, local; matches mesh-native hand_rest_y)
# Cosmetic block BODY pose (gait + pose coordinator): the one-knee drop a real
# skater blocks with — the stick-side knee sinks toward the ice with the shin
# folded back along it, the far leg extends out to the other side sealing the
# ice the stick can't cover, and the chest tips forward over the down knee.
# These three leg angles fully determine the pose: the kneeling hip height falls
# out of the down leg, and the extended leg's abduction is solved from that
# height so its skate stays on the ice (GaitBlockLayer). Keyed off the
# replicated current_shot_state, so remote blockers read identically.
var block_kneel_hip_deg: float = 30.0    # down-leg thigh, forward of vertical
var block_kneel_shin_deg: float = 88.0   # down-leg shin, from vertical (90 = flat on the ice)
var block_extend_knee_deg: float = 10.0  # residual flex in the extended leg — never locked straight
var block_trunk_pitch_deg: float = 16.0  # chest tips forward over the down knee
var block_trunk_roll_deg: float = 10.0   # ...and rolls onto it, off the extended leg
var block_pose_blend_speed: float = 12.0 # snap-in speed of the body pose (the plant is committed)

# ── Net Collision ─────────────────────────────────────────────────────────────
# The stick's own reach perpendicular to the blade segment, added to the pipe
# radius so the blade stops on the outside of the iron rather than centre-on.
var net_blade_half_thickness: float = 0.012
# Floor on how briskly a puck caught on the pipe leaves the blade. A fast catch
# inherits the pipe's own rebound instead; this only covers the slow/stationary
# wedge, where there is no rebound to inherit but the puck must still come off
# rather than ride along with a stick the post is holding back.
var post_catch_release_speed: float = 1.5

# ── Goalie Body Block ─────────────────────────────────────────────────────────
# XZ cylinder radius used to push the blade (and carried puck) away from a
# goalie's body center. Tunable in the editor — matches roughly the goalie's
# padded chest width. The hand moves with the blade to keep stick length intact.
var goalie_block_radius: float = 0.50
var goalie_strip_power: float = 1.5
# Half-extents of the butterfly leg-pad strip box in goalie local XZ space.
var butterfly_pad_half_x: float = 0.84
var butterfly_pad_half_z: float = 0.25

# ── References ────────────────────────────────────────────────────────────────
var skater: Skater = null
var puck: Puck = null
# Injected at setup. Expected methods:
#   is_host() -> bool                              — changes only per session; cached in _is_host
#   is_movement_locked() -> bool                   — polled per frame
#   get_goalie_data() -> Array[Dictionary]         — position/rotation_y/is_butterfly per goalie
var _game_state: Node = null
var _is_host: bool = false

# ── Runtime State ─────────────────────────────────────────────────────────────
# Live cursor world position this tick — stamped in _process_input so the shot
# follow-through can ease its finish aim back to wherever the mouse currently is
# (see follow_through_return_frac). Fed from the replayed input during reconcile,
# so it stays deterministic. Only read by the FOLLOW_THROUGH pose branches, which
# never run on the faceoff/skate-in cosmetic paths, so a stale value is harmless.
var _current_aim_world: Vector3 = Vector3.ZERO
# Reused ShotResult for the per-tick "where would this charge go if released now"
# prediction in _update_wrister_charge — a caller-owned scratch so that hot path
# (every tick while charging, re-run per replayed input on reconcile) doesn't churn
# the heap. Pure output, overwritten each solve.
var _wrister_pred_scratch: ShotMechanics.ShotResult = ShotMechanics.ShotResult.new()
# The wrist shot's load, re-solved every aim tick and at the release from the
# replayed input, so it needs no reconcile save. Read by the aim pose.
var wrister_load: WristerLoad.Result = WristerLoad.Result.new()
# How far the aim pose winds toward wrister_load.wound_yaw: the power the shot
# would release with now, as a share of the full band.
var wrister_coil: float = 0.0
# Same scratch for the slapper windup's release-now prediction (_update_slapper_
# charge) — the goalie pre-leans off it toward a charging slapshot's aimed corner.
var _slapper_pred_scratch: ShotMechanics.ShotResult = ShotMechanics.ShotResult.new()
# Per-tick mirror of input.elevation_level (0 flat / 1 low / 2 high) — NOT
# sticky state: overwritten from the frame every tick, so reconcile replay
# re-derives it from the replayed inputs with nothing to snap.
var _elevation_level: int = 0
var _aiming: SkaterAimingBehavior = SkaterAimingBehavior.new()
var _pose: SkaterPoseCoordinator = SkaterPoseCoordinator.new()
var _shot_pose: SkaterShotPoseCoordinator = SkaterShotPoseCoordinator.new()
var _pose_bridge := SkaterPoseBridge.new()
var _skating: SkaterSkatingCoordinator = SkaterSkatingCoordinator.new()
var _ik: SkaterIKCoordinator = SkaterIKCoordinator.new()
var _stick_check: SkaterStickCheck = SkaterStickCheck.new()
var _settle: SkaterSettleGate = SkaterSettleGate.new()
# The puck's velocity in this skater's frame at its last catch (world XZ),
# quantized as the grant carries it.
var _one_timer_feed: Vector2 = Vector2.ZERO
var last_processed_host_timestamp: float = 0.0
var has_puck: bool = false
var is_replaying: bool = false
# Previous-tick puck PIN (get_carry_target_global) — the segment START the pin's
# net collision sweeps from, so the two-sided twine knows which face the puck is
# pressing. A sweep input, not a history one: nothing here asks how the puck got
# where it is. Reset when the puck comes loose. See _collide_pinned_puck_with_net.
var _prev_carry_pin: Vector3 = Vector3.ZERO
# Shared scratch for the pinned puck's net collision — filled per tick, never
# escapes _collide_pinned_puck_with_net.
var _net_pin_result := PuckGeometryCollision.Result.new()
var _has_prev_carry_pin: bool = false
# True on frames where a special locked-phase path posed the body itself this
# tick — faceoff-prep blade aim, the faceoff skate-in approach, and replay
# playback. Those paths run their own gait / head / off-hand (they're brief and
# not the per-tick × N hot path), so the render-rate cosmetic hook yields to them
# to avoid a double gait pass. The main live path (_process_input) clears it and
# delegates cosmetics to the render hook.
var _self_posing: bool = false
# Body-check stagger: seconds of thrust/grip-penalty recovery remaining. Set
# host-authoritatively when this skater absorbs a check (_on_body_check_received),
# decayed each tick in _apply_movement, and replicated so the local player's
# reconcile snaps it to the host baseline before replay.
var stagger_timer: float = 0.0
# Body-check knockdown: seconds of full movement lockout remaining. Set host-
# authoritatively (and predicted on the local victim) when a hit exceeds the
# knockdown threshold; while > 0 the skater is down (no input, sliding, no puck).
# Replicated / snapped / decayed exactly like stagger_timer.
var knockdown_timer: float = 0.0
# Rate of the balance lean's spring (rad/s, world XZ); the lean itself lives on
# the skater (Skater.balance_tilt). Stepped in the tick by _advance_balance and
# replicated — the local reconcile snaps both to the host's before replay.
var balance_tilt_vel: Vector2 = Vector2.ZERO
# Down-window metadata for the knockdown fall pose: total seconds of the current
# window (so elapsed down-time = _knockdown_total − knockdown_timer) and the
# horizontal shove speed at entry (seeds the fall's tip rate). Captured by
# whichever path observes the entry — from the transfer impulse on the
# simulating side (_set_knockdown_from_impulse), from the replicated velocity on
# receive-side rising edges (_sync_knockdown_meta) — and extended, not reset, by
# follow-up hits so the elapsed clock never restarts mid-fall. Cosmetic: the
# replicated timer that gates the pose is the deterministic rail.
var _knockdown_total: float = 0.0
var _knockdown_entry_speed: float = 0.0
# Body-frame direction the last check shoved this skater (x = right, y = forward
# in the (x, z) plane). Drives the recoil lean in SkaterPoseCoordinator and the
# knockdown fall direction; set on the local victim / host from the transfer
# impulse and replicated (SkaterNetworkState.recoil_dir) like the timer that
# gates it: receivers apply it, the local reconcile adopts the host's. The reel
# tilts UpperBody, so it moves the blade.
var stagger_recoil_dir: Vector2 = Vector2(0.0, 1.0)
# Resolved stance for this tick (Shift held, no check committed, locomotion not
# suppressed). Written in _apply_movement; the gait reads it for the stance pose
# and fill_network_state replicates it for remotes.
var stance_active: bool = false
# Resolved hit-commit (body-check button) state for this tick. Written in
# _apply_movement and mirrored to skater.hit_committed so the collision resolver
# picks full-vs-passive transfer. Deterministic from input.hit_held, so it
# re-derives through reconcile replay with no wire state.
var hit_active: bool = false

var _game_state_has_faceoff_prep: bool = false
var _game_state_has_period_break: bool = false
# Cosmetic goal-celebration window (seconds remaining / total), opened after
# _celebration_lead seconds. Started by GameManager on every machine; the
# raised-stick pose rides the normal hand/blade wire state to everyone else.
var _celebration_timer: float = 0.0
var _celebration_total: float = 1.0
var _celebration_lead: float = 0.0
# Hops across the window: the knee bounce and the fist pump share them.
const CELEBRATION_PUMPS: float = 3.0

# ── Faceoff / intro skate-in approach ─────────────────────────────────────────
# During FACEOFF_PREP the skater glides from a start point (its bench for the
# opening intro, else its current position) to the faceoff dot along a
# deterministic eased path instead of teleport-snapping — the existing
# velocity-driven gait rides on top. Position is a pure function of (start,
# target, elapsed/duration) so host and every client agree with reconcile off;
# the skater lands exactly on the dot at t=1 and hands back to the normal prep
# freeze for the rest of the countdown. See begin_approach / apply_approach.
var _approach_active: bool = false
var _approach_start: Vector3 = Vector3.ZERO
var _approach_target: Vector3 = Vector3.ZERO
var _approach_facing: Vector2 = Vector2.ZERO   # squared-up dot facing at arrival
var _approach_elapsed: float = 0.0
var _approach_duration: float = 1.0
var _approach_prev_pos: Vector3 = Vector3.ZERO
# Live planar velocity the skate-in launches from (period / stoppage faceoffs) so
# the glide flows out of the player's momentum instead of hard-stopping at the
# whistle. Zero for snap-from-rest starts (bench intro / post-goal staging).
var _approach_v0: Vector3 = Vector3.ZERO
# Below this planar speed a skate-in is treated as a snap-from-rest start (reset
# gait + square up to the path); at or above it, momentum is preserved.
const _APPROACH_CARRY_MIN: float = 0.3
# Planar speed (m/s) under which a skater in the prep has glided in and takes
# his stance: about a walking pace, the tail of the skate-in's ease onto the dot.
const FACEOFF_SET_MAX_SPEED: float = 1.0
# Reused so the per-tick skate-in render doesn't allocate an InputState.
var _approach_input: InputState = InputState.new()


# True while this skater is SET at the dot for the drop — the gait floors its
# stance crouch and staggers the feet (see faceoff_stance / faceoff_split_deg).
# A live skate-in is excluded: a player still covering ground is skating, and a
# staggered ready stance over a running stride is not a stance, it is a limp.
# Read off the body as well as the approach: a remote skater's glide runs on the
# host, so here he is only a body on the wire coming in at speed.
func is_faceoff_ready() -> bool:
	return _game_state_has_faceoff_prep and _game_state.is_faceoff_prep() \
			and not _approach_active \
			and Vector2(skater.velocity.x, skater.velocity.z).length() < FACEOFF_SET_MAX_SPEED


# `lead` seconds pass before the window opens; nothing is posed through them.
func start_celebration(duration: float, lead: float = 0.0) -> void:
	_celebration_total = maxf(duration, 0.001)
	_celebration_timer = _celebration_total
	_celebration_lead = maxf(lead, 0.0)


# Drops the window, lead and all, and hands the free hand back to the stick.
func end_celebration() -> void:
	_celebration_timer = 0.0
	_celebration_lead = 0.0
	_ik.hold_free_hand(Vector3.ZERO, 0.0)


# The window is open: the pose is live.
func is_celebrating() -> bool:
	return _celebration_timer > 0.0 and _celebration_lead <= 0.0


# A window is open or still waiting out its lead.
func has_celebration_window() -> bool:
	return _celebration_timer > 0.0


# 0..1 progress through the celebration window (0 when idle).
func celebration_progress() -> float:
	if not is_celebrating():
		return 0.0
	return 1.0 - _celebration_timer / _celebration_total


# 0 standing to 1 at the bottom of a hop, CELEBRATION_PUMPS times across the
# window: the gait's knee bounce and the pose's fist pump both ride it.
func celebration_pump() -> float:
	var progress: float = celebration_progress()
	if progress <= 0.0:
		return 0.0
	return 0.5 - 0.5 * cos(progress * TAU * CELEBRATION_PUMPS)


# Ages the celebration window, at physics rate on real ticks from both the
# simulating path and RemoteController, so the timer counts down even for
# skaters this machine doesn't simulate (the timer starts on every machine;
# see GameManager._trigger_scorer_celebration).
func tick_celebration(delta: float) -> void:
	if _celebration_lead > 0.0:
		_celebration_lead = maxf(_celebration_lead - delta, 0.0)
	elif _celebration_timer > 0.0:
		_celebration_timer = maxf(_celebration_timer - delta, 0.0)


# Check-delivery body pose: the hitter drives the shoulder through the contact.
# Fired from the host-authoritative body_check_landed broadcast (and the replay
# event dispatcher), so it reads identically on every machine — same contract
# as the burst/thud. `hit_dir` is the world-space direction the victim was
# shoved (attacker → victim); `intensity` is the 0..1 VFX hardness.
func start_check_drive(hit_dir: Vector3, intensity: float) -> void:
	_skating.start_check_drive(hit_dir, intensity)

# ── Setup ─────────────────────────────────────────────────────────────────────
func setup(assigned_skater: Skater, assigned_puck: Puck, game_state: Node) -> void:
	skater = assigned_skater
	puck = assigned_puck
	_game_state = game_state
	_is_host = game_state.is_host()
	# Cached so the per-tick gait can ask about the faceoff phase without a
	# has_method() call every tick (test stubs may not implement it).
	_game_state_has_faceoff_prep = game_state.has_method("is_faceoff_prep")
	_game_state_has_period_break = game_state.has_method("is_period_break")
	process_physics_priority = -1  # Run before Skater's integration step
	facing_rules.forehand_edge_rad = deg_to_rad(rom_forehand_angle_max_deg + upper_body_max_twist_deg)
	facing_rules.backhand_edge_rad = deg_to_rad(rom_backhand_angle_max_deg + upper_body_max_twist_deg)
	carry_facing_rules.forehand_edge_rad = facing_rules.forehand_edge_rad
	carry_facing_rules.backhand_edge_rad = deg_to_rad(bh_release_angle_deg)
	carry_facing_rules.forehand_yield_rad = deg_to_rad(carry_forehand_yield_deg)
	skater.body_checked_player.connect(_on_body_checked_player)
	skater.body_check_received.connect(_on_body_check_received)
	if game_state.has_method("is_movement_locked"):
		skater.contact_suspended_provider = game_state.is_movement_locked
	_ik.setup(skater, self, _skating)
	_shot_pose.setup(skater, _sm, _aiming, _ik, self)
	var _cb := SkaterStateMachine.Callbacks.new()
	_cb.apply_blade_from_mouse = _ik.apply_blade_from_mouse
	_cb.apply_wrister_aim_blade = _apply_wrister_aim_blade
	_cb.apply_slapper_blade_position = _shot_pose.apply_slapper_blade_position
	_cb.apply_slapper_setup = _apply_slapper_setup
	_cb.update_slapper_aim = _update_slapper_aim
	_cb.apply_block_blade_position = _shot_pose.apply_block_blade_position
	_cb.apply_wrister_follow_through = _shot_pose.apply_wrister_follow_through
	_cb.apply_slapper_follow_through = _shot_pose.apply_slapper_follow_through
	_cb.enter_shot_block = _enter_shot_block
	_cb.enter_slapper_charge = _enter_slapper_charge
	_cb.cancel_slapper = _cancel_slapper
	_cb.transition_to_skating = _transition_to_skating
	_cb.release_wrister = _release_wrister
	_cb.fire_quick_pass = _fire_quick_pass
	_cb.release_slapper = _release_slapper
	_cb.enter_one_timer_retention = _enter_one_timer_retention
	_cb.release_retained_one_timer = _release_retained_one_timer
	_cb.update_wrister_charge = _update_wrister_charge
	_cb.update_slapper_charge = _update_slapper_charge
	_cb.apply_block_movement = _apply_block_movement
	_sm.setup(_cb, _aiming)
	_pose.setup(skater, _sm, _aiming, self, _skating)
	_skating.setup(skater, _sm, self)
	# Cosmetic pose (leg gait / head / off-hand IK) now runs at render rate in
	# Skater._process instead of every physics tick — it feeds only meshes, not
	# the blade world frame. RemoteController overrides _render_pose_update to
	# drop head tracking (a wire-fed body has no cursor aim).
	skater.render_pose_update = _render_pose_update

# Reach ROM is derived from arm length, not an independent tunable. The
# forehand side is shoulder-joint-limited (about 56% of arm length — the top
# hand can't cross the body very far). The backhand side and straight ahead
# are arm-EXTENSION-limited: the hand rides at hand_rest_y, a fixed drop below
# the shoulder, so it sits at most sqrt(reach² − drop²) out — reach being
# arm × rom_arm_extension to the side, plus Skater.shoulder_reach_m ahead,
# where the shoulder blade protracts (the girdle give the arm rig roots with,
# so the drawn arm spans it). No reachable pose out-reaches the arm, and long
# arms matter most at full extension, which is the realistic shape.
const _ROM_FOREHAND_OF_ARM: float = 0.5625


# ── Player Attributes ─────────────────────────────────────────────────────────
# Base values captured on the first apply_attributes() call so subsequent
# applies (offline free-play picker re-applies) recompute from the original
# @export defaults instead of compounding with the previous multiplier.
# All tuning tables live on PlayerAttributes — see that file for the system
# overview and how to add new scalings.
var _attr_base_captured: bool = false
var _base_thrust:                       float = 0.0
var _base_crossover_thrust_multiplier:  float = 0.0
var _base_backward_thrust_multiplier:   float = 0.0
var _base_backward_max_speed_multiplier: float = 0.0
var _base_stance_grip_mult:             float = 0.0
var _base_shuffle_speed:                float = 0.0
var _base_max_speed:                    float = 0.0
var _base_facing_drag_speed:            float = 0.0
var _base_facing_drag_speed_braking:    float = 0.0
var _base_stop_decel:                   float = 0.0
var _base_friction_drag:                float = 0.0
var _base_lateral_grip:                 float = 0.0
var _base_max_wrister_power:            float = 0.0
var _base_min_slapper_power:            float = 0.0
var _base_max_slapper_power:            float = 0.0
var _base_max_slapper_charge_time:      float = 0.0
var _base_wrister_unloaded_share:       float = 0.0
var _base_skater_stick_flex_max_m:      float = 0.0
var _base_skater_stick_flex_slap_m:     float = 0.0
var _base_skater_stick_flex_windup_m:   float = 0.0
var _base_max_blade_speed:              float = 0.0
var _base_max_blade_accel:              float = 0.0
var _base_stick_length:                 float = 0.0
var _base_skater_upper_arm_length:      float = 0.0
var _base_skater_forearm_length:        float = 0.0
var _base_skater_shoulder_reach_m:      float = 0.0
var _base_skater_shoulder_offset:       float = 0.0
var _base_skater_shoulder_height:       float = 0.0
var _base_skater_weight:                float = 0.0
var _base_skater_collision_radius:      float = 0.0
var _base_backhand_power_coefficient:   float = 0.0
# The blade curve's angle ladder (tan per elevated loft level) for the
# charged-shot release math — set per-build from the curve gear in
# apply_attributes; defaults to the M92 (league-neutral) ladder.
var loft_tan_low: float = GameRules.DEFAULT_LOFT_TAN_LOW
var loft_tan_mid: float = GameRules.DEFAULT_LOFT_TAN_MID
var loft_tan_high: float = GameRules.DEFAULT_LOFT_TAN_HIGH
var _base_hand_rest_y:                  float = 0.0
var _base_hand_y_max:                   float = 0.0


# Snapshot this body's attribute-scaled capabilities as the bot AI models them —
# read off the SAME scaled fields the physics drives with (set by
# apply_attributes), so the AI never disagrees with the body. Used two ways: a
# bot's self-model (AIController.apply_attributes) and PlayerRegistry's per-peer
# caps_by_peer (every player, so other bots read real builds). Cheap and
# allocation-light; called only on apply / spawn, never per tick.
func build_ai_caps() -> AISkaterCaps:
	var caps := AISkaterCaps.new()
	caps.max_speed = max_speed
	caps.max_accel = thrust
	caps.blade_span = stick_length + GameRules.DEFAULT_BLADE_LENGTH_M
	caps.stick_reach = stick_length
	# This build's real full reach (AISkaterCaps.max_blade_reach, the claim clamp).
	caps.max_blade_reach = _ik.full_blade_reach()
	caps.max_lean_shift = skater.max_lean_shift()
	caps.wrister_shot_speed = max_wrister_power
	caps.blade_speed = max_blade_speed
	caps.lateral_grip = lateral_grip
	caps.backhand_power_coefficient = backhand_power_coefficient
	caps.wrister_load = _wrister_load_config()
	caps.facing_rules = facing_rules
	caps.carry_facing_rules = carry_facing_rules
	if skater != null:
		caps.is_left_handed = skater.is_left_handed
	caps.wrister_unloaded_share = wrister_unloaded_share
	if skater != null and skater.shoulder != null:
		var strike: Vector2 = slapper_strike_local()
		caps.slapper_strike_local = Vector2(strike.x * _blade_side_sign(), strike.y)
	caps.slapper_stance_open_rad = deg_to_rad(slapper_stance_open_deg)
	caps.slapper_stance_turn_rad_s = deg_to_rad(slapper_stance_turn_deg_s)
	caps.slapper_power_min = min_slapper_power
	caps.slapper_power_max = max_slapper_power
	caps.slapper_max_charge_s = max_slapper_charge_time
	caps.one_timer_min_windup_s = one_timer_min_windup_time
	caps.one_timer_feed_grip = one_timer_feed_grip
	caps.reception_ceiling_mult = skater.reception_ceiling_mult
	# Handle reach scales with the blade lever: max_blade_speed / its base is
	# exactly the lever ratio (attributes v4 — reach + stick length), so a
	# longer lever protects the puck further out. _base is captured on the
	# first apply_attributes (always run before this).
	if _base_max_blade_speed > 0.001:
		caps.handle_reach = AIBotMechanics.EVADE_CARRY_HANDLE_M \
				* (max_blade_speed / _base_max_blade_speed)
	# Blade reach cone: the exact IK gate SkaterPoseCoordinator.apply_facing
	# enforces (ROM backhand + torso twist), so the bot models the same off-facing
	# reach the body actually has. Fixed geometry — not attribute-scaled.
	caps.reach_cone_half_angle = deg_to_rad(
			rom_backhand_angle_max_deg + upper_body_max_twist_deg)
	# Facing turn rate: the baseline 6.0 rad/s approximation scaled by real Agility.
	# facing_drag_speed is base × agility_mult, so its ratio to base IS the Agility
	# multiplier — a nimbler bot turns (and prices a back-wedge aim) faster.
	if _base_facing_drag_speed > 0.001:
		caps.facing_turn_rate *= facing_drag_speed / _base_facing_drag_speed
	caps.movement = _build_movement_config()
	caps.facing_drag_speed = facing_drag_speed
	caps.facing_drag_speed_braking = facing_drag_speed_braking
	caps.facing_turn_accel_max = facing_turn_accel_max
	caps.board_shield_probe = board_shield_probe
	caps.board_shield_max_rad = deg_to_rad(board_shield_max_deg)
	if skater != null:
		caps.weight = skater.weight
		caps.body_check_transfer = skater.body_check_transfer
		caps.body_radius = skater.collision_radius()
	caps.height_mult = _build_height_mult
	return caps


# Modulates the controller and skater tuning fields from a PlayerAttributes
# resource. Safe to call multiple times — the first call snapshots the
# shipped @export defaults, every call recomputes live = base × multiplier.
# Called once at spawn and again whenever the local player changes picks in
# offline free-play (online matches lock attributes at join time).
func apply_attributes(attrs: PlayerAttributes) -> void:
	if attrs == null or skater == null:
		return
	if not _attr_base_captured:
		_capture_attribute_bases()
	var m_height:  float = attrs.height_mult()
	var m_agility: float = attrs.agility_mult()
	_build_height_mult = m_height / PlayerAttributes.neutral().height_mult()
	max_speed = _base_max_speed * attrs.top_speed_mult()
	thrust    = _base_thrust    * attrs.accel_mult()
	crossover_thrust_multiplier = _base_crossover_thrust_multiplier * attrs.crossover_mult()
	backward_thrust_multiplier = _base_backward_thrust_multiplier * attrs.backward_mult()
	backward_max_speed_multiplier = _base_backward_max_speed_multiplier * attrs.backward_mult()
	stance_grip_mult = _base_stance_grip_mult * attrs.stance_grip_mult()
	shuffle_speed = _base_shuffle_speed * attrs.sidestep_mult()
	facing_drag_speed           = _base_facing_drag_speed           * m_agility
	facing_drag_speed_braking   = _base_facing_drag_speed_braking   * m_agility
	stop_decel                  = _base_stop_decel                  * m_agility
	# Lateral grip is where agility's turn promise physically lands: it scales the
	# turn authority in the movement core, so the emergent turn radius
	# v²/(turn_accel·grip) genuinely widens for a heavy/tall build and tightens for a
	# lean/small one. The facing/stop terms above are the feel of quickness; this is
	# the arc itself.
	lateral_grip                = _base_lateral_grip                * m_agility
	# friction_drag is the velocity-proportional (air) drag: girth-scaled, so
	# a heavy body coasts (see glide_drag_mult).
	friction_drag               = _base_friction_drag               * attrs.glide_drag_mult()
	# A computed value, not a base × mult.
	puck_carry_speed_multiplier = attrs.carry_speed_mult()
	# The blade caps derive from LEVER GEOMETRY below, after the reach/stick
	# rescale computes this build's sweep radius. The backhand coefficient leans
	# with the blade curve (closed relaxes toward, never past, forehand parity).
	backhand_power_coefficient  = _base_backhand_power_coefficient * attrs.curve_backhand_mult()
	# Curve elevation is the blade's ANGLE LADDER: the set launch angle per
	# loft level (ShotMechanics.shot_loft_y). The whole elevation identity of
	# the pattern lives in these three numbers — steeper on the open blade at
	# every rung.
	loft_tan_low = attrs.curve_loft_tan_low()
	loft_tan_mid = attrs.curve_loft_tan_mid()
	loft_tan_high = attrs.curve_loft_tan_high()
	# Reception ceiling rides the skater body — the reception decision sites
	# (PuckController contact scan + the lag-comp pickup resolver) scale the
	# puck's league deflect thresholds by the RECEIVER's blade shape.
	skater.reception_ceiling_mult = attrs.reception_ceiling_mult()
	# Shot power scales the CHARGED-shot ceilings (wrister max + both slapper
	# pools), never min_wrister_power (the soft-touch floor) or quick_pass_power
	# (also the pass speed) — every build's touch and passes are the same.
	max_wrister_power = _base_max_wrister_power * attrs.shot_power_mult()
	wrister_unloaded_share = _base_wrister_unloaded_share * attrs.wrister_unloaded_mult()
	var m_slap: float = attrs.slapper_power_mult()
	min_slapper_power = _base_min_slapper_power * m_slap
	max_slapper_power = _base_max_slapper_power * m_slap
	max_slapper_charge_time = _base_max_slapper_charge_time * attrs.shot_charge_mult()
	# The flex pick's visual tell: how far the shaft bows on every shot.
	var m_bend: float = attrs.stick_bend_mult()
	skater.stick_flex_max_m = _base_skater_stick_flex_max_m * m_bend
	skater.stick_flex_slap_m = _base_skater_stick_flex_slap_m * m_bend
	skater.stick_flex_windup_m = _base_skater_stick_flex_windup_m * m_bend
	# Mass is the whole physical system: delivery and brace emerge from the
	# collision resolver's reduced-mass math, so no check term scales here.
	skater.weight = _base_skater_weight * attrs.mass_mult()
	# Arms scale with height_mult. The stick is equipment, not anatomy, so it
	# rides a GENTLER curve (stick_len_mult, ~0.65x the height
	# deviation): real played stick lengths track height only loosely, so a small
	# player keeps a near-full-size stick. Total blade reach is still arm-driven ROM +
	# stick (top_hand_ik FAR regime), so the eased stick is not a proportionally eased
	# reach. update_stick_mesh() and the arm bone wrappers recompute visuals from
	# these every frame, so no separate visual pass is needed.
	stick_length              = _base_stick_length              * attrs.stick_len_mult()
	# The commit choke is a fraction of the stick it slides down, so it lands in
	# metres here rather than being re-derived at the two sites that read it.
	skater.commit_grip_choke_m = stick_length * hit_commit_choke_frac
	skater.faceoff_choke_m = stick_length * faceoff_center_choke_frac
	# The CURVE gear's visual half — regenerates the blade mesh to the picked
	# pattern (gameplay half is PlayerAttributes' loft/backhand leans).
	skater.apply_blade_pattern(attrs.curve)
	skater.upper_arm_length   = _base_skater_upper_arm_length   * m_height
	skater.forearm_length     = _base_skater_forearm_length     * m_height
	skater.shoulder_reach_m   = _base_skater_shoulder_reach_m   * m_height
	# Shoulder anchors track the visual shoulder balls, which the appearance
	# pass repositions from the same multipliers (y rides height, x rides
	# girth) — the drawn arm and the IK stay rooted at the same point on
	# every build. Must run BEFORE the hand/ROM derivation below reads
	# shoulder_height.
	skater.set_shoulder_anchor(
			_base_skater_shoulder_offset * attrs.girth_mult(),
			_base_skater_shoulder_height * m_height)
	# Hand heights scale with the skeleton: the appearance pass scales the whole mesh
	# rig about the ice plane (the upper body rides at height_mult × 1.0 m world), so
	# the hand's LOCAL rest height scales by the same factor to keep the hand at the
	# same point on every body (shoulder-to-hand drop = 0.50 m × height). Same for the
	# CLOSE-regime ceiling. Near-zero gameplay cost: raising the hand shortens the
	# stick's horizontal footprint but lengthens the derived backhand ROM below at
	# almost exactly 1:1, so blade rim reach barely moves.
	hand_rest_y = _base_hand_rest_y * m_height
	hand_y_max  = _base_hand_y_max  * m_height
	# The gait's crouch drop rides the same leg scale the appearance pass
	# applies to the leg pivot chain, so flexed knees sink a tall build
	# proportionally deeper.
	_skating.leg_scale = m_height
	# Reach ROM is a derived property of arm length — forehand from the anatomical
	# cross-body ratio, backhand from the chain geometry (see the _ROM_FOREHAND_OF_ARM
	# doc block). With the whole chain scaling by height the derived reach scales by
	# height too, and long arms matter most at full extension.
	var arm_total: float = skater.upper_arm_length + skater.forearm_length
	rom_forehand_reach_max    = arm_total * _ROM_FOREHAND_OF_ARM
	var arm_eff: float = arm_total * rom_arm_extension
	var reach_drop: float = skater.shoulder_height - hand_rest_y
	rom_backhand_reach_max    = sqrt(maxf(arm_eff * arm_eff - reach_drop * reach_drop, 0.0))
	var arm_protracted: float = arm_eff + skater.shoulder_reach_m
	rom_forward_reach_max     = sqrt(maxf(
			arm_protracted * arm_protracted - reach_drop * reach_drop, 0.0))
	# The blade's sweep radius: stick + arm-driven ROM, both just rescaled above.
	var sweep_radius: float = stick_length + rom_forehand_reach_max
	# Blade caps derive from this LEVER (constitution: geometry, never a
	# fidelity table). Tip speed rides the lever linearly — v = ω·L, the same
	# angular gesture sweeps a longer blade faster in m/s, so every build's
	# wrists are heard at the same ANGULAR fidelity (traverse time across your
	# own reach envelope stays ~flat; the calibration test pins it). The
	# acceleration cap (inertia) falls with lever^k — I ∝ mL², softened to the
	# authored blade_inertia_exponent — so the long lever sweeps but can't cut
	# back, the short lever is the scalpel. Base accel 0 = inertia disabled.
	# The ratio normalizes to the NEUTRAL build's lever (6'1"/standard), NOT the
	# mesh-native base geometry (the reach-1.0 anchor is 5'10", below the
	# gameplay neutral): neutral identity demands the neutral build's caps equal
	# the shipped exports exactly.
	var neutral_attrs := PlayerAttributes.neutral()
	var neutral_sweep: float = _base_stick_length * neutral_attrs.stick_len_mult() \
			+ (_base_skater_upper_arm_length + _base_skater_forearm_length) \
			* neutral_attrs.height_mult() * _ROM_FOREHAND_OF_ARM
	var lever_ratio: float = sweep_radius / maxf(neutral_sweep, 0.001)
	max_blade_speed = _base_max_blade_speed * lever_ratio
	max_blade_accel = _base_max_blade_accel / pow(lever_ratio, blade_inertia_exponent) \
			if _base_max_blade_accel > 0.0 else 0.0
	# Hitbox: the contact disc wears the same girth the silhouette does. There is
	# no vertical extent to scale: every contact path the radius feeds is a flat
	# XZ test (skater-vs-skater, the rink / net / goalie clamps).
	skater.body_collision_radius = _base_skater_collision_radius * attrs.girth_mult()
	# Attribute scaling rewrote the exports the cached configs were built
	# from — drop them so the next tick rebuilds with the new values.
	_ik.invalidate_configs()
	_cached_move_cfg = null
	_cached_block_move_cfg = null
	_cached_wrister_cfg = null
	_cached_wrister_load_cfg = null
	_cached_slapper_cfg = null
	_skating.native_reconfigure()
	skater.apply_appearance(attrs)
	_movement_config()


func _capture_attribute_bases() -> void:
	_base_thrust                       = thrust
	_base_crossover_thrust_multiplier  = crossover_thrust_multiplier
	_base_backward_thrust_multiplier   = backward_thrust_multiplier
	_base_backward_max_speed_multiplier = backward_max_speed_multiplier
	_base_stance_grip_mult             = stance_grip_mult
	_base_shuffle_speed                = shuffle_speed
	_base_max_speed                    = max_speed
	_base_facing_drag_speed            = facing_drag_speed
	_base_facing_drag_speed_braking    = facing_drag_speed_braking
	_base_stop_decel                   = stop_decel
	_base_friction_drag                = friction_drag
	_base_lateral_grip                 = lateral_grip
	_base_max_wrister_power            = max_wrister_power
	_base_min_slapper_power            = min_slapper_power
	_base_max_slapper_power            = max_slapper_power
	_base_max_slapper_charge_time      = max_slapper_charge_time
	_base_wrister_unloaded_share       = wrister_unloaded_share
	_base_skater_stick_flex_max_m      = skater.stick_flex_max_m
	_base_skater_stick_flex_slap_m     = skater.stick_flex_slap_m
	_base_skater_stick_flex_windup_m   = skater.stick_flex_windup_m
	_base_max_blade_speed              = max_blade_speed
	_base_max_blade_accel              = max_blade_accel
	_base_backhand_power_coefficient   = backhand_power_coefficient
	_base_stick_length                 = stick_length
	_base_hand_rest_y                  = hand_rest_y
	_base_hand_y_max                   = hand_y_max
	_base_skater_upper_arm_length      = skater.upper_arm_length
	_base_skater_forearm_length        = skater.forearm_length
	_base_skater_shoulder_reach_m      = skater.shoulder_reach_m
	_base_skater_shoulder_offset       = skater.shoulder_offset
	_base_skater_shoulder_height       = skater.shoulder_height
	_base_skater_weight                       = skater.weight
	_base_skater_collision_radius = skater.body_collision_radius
	_attr_base_captured = true


func _on_body_checked_player(victim: Skater, impact_force: float, hit_direction: Vector3) -> void:
	if not _is_host:
		return
	puck.on_body_check(skater, victim, impact_force, hit_direction)

# This skater just absorbed his side of a contact (either body's). The host sets
# the stagger window scaled by hit strength, then broadcasts stagger_timer via
# fill_network_state. `max` so a weaker follow-up never shortens an in-flight
# stagger.
#
# The LOCAL skater also fires this, so it predicts its own stagger off the same
# transfer impulse rather than waiting a round-trip for the host's snapshot.
# Reconcile snaps stagger_timer to the server value and re-derives the decay, so
# a misprediction self-heals in one reconcile. Remote bodies on a client still
# defer to the snapshot (early return).
# `stagger_strength` (m/s) is how hard it landed (Skater.body_check_received);
# omitted, the impulse's own magnitude.
func _on_body_check_received(impulse: Vector3, stagger_strength: float = -1.0) -> void:
	_absorb_hit(impulse, stagger_strength)


# The outcome of a Δv `impulse` landing on him: the stagger from how hard it
# landed (`stagger_strength`, or the impulse's own magnitude), the rocked band
# and the knockdown — which reads his balance (BodyBalanceRules) against how far
# his body was driven, so the boards behind him add to the stagger and not to
# the fall. Committed to a check, he leans into it
# (BodyBalanceRules.leaned_into), whichever body's resolver landed it.
func _absorb_hit(impulse: Vector3, stagger_strength: float) -> void:
	var felt: Vector3 = impulse
	if skater.delivers_checks():
		var leaned: Vector2 = BodyBalanceRules.leaned_into(Vector2(impulse.x, impulse.z),
				skater.get_facing(), _balance_config())
		felt = Vector3(leaned.x, 0.0, leaned.y)
	var impulse_magnitude: float = felt.length()
	var felt_share: float = impulse_magnitude / maxf(impulse.length(), 1e-6)
	var stagger_from: float = maxf(impulse_magnitude, stagger_strength * felt_share)
	# Capture the recoil direction (body frame) so the torso reels the way the
	# hit shoved it — see SkaterPoseCoordinator._apply_lean. Set on every
	# machine that resolves the hit; a client-rendered remote's is overwritten by
	# the wire on its next apply.
	var local_impulse: Vector3 = skater.global_transform.basis.inverse() * impulse
	var recoil_xz: Vector2 = Vector2(local_impulse.x, local_impulse.z)
	if recoil_xz.length() > 0.001:
		stagger_recoil_dir = recoil_xz.normalized()
	# Set on both the host and the local victim's prediction, so a downed local
	# player goes down immediately and reconcile snaps the timers to the host's.
	if not _is_host and not skater.is_local_skater:
		return
	var cfg: BodyCheckRules.Config = _body_check_config()
	var knockdown_add: float = 0.0
	var overshoot: float = BodyBalanceRules.overshoot(Vector2(felt.x, felt.z),
			skater.get_facing(), _balance_posture(), _build_height_mult, _balance_config())
	if overshoot > 1.0:
		knockdown_add = KnockdownFallRules.first_impact_time(
				Vector2(impulse.x, impulse.z).length(), _fall_config()) \
				+ BodyCheckRules.lie_seconds_from_overshoot(overshoot, cfg) \
				+ knockdown_getup_seconds
	var stagger_add: float = BodyCheckRules.stagger_seconds_from_impulse(stagger_from, cfg,
			knockdown_add > 0.0)
	_set_knockdown_from_impulse(knockdown_add, impulse)
	stagger_timer = maxf(stagger_timer, stagger_add)


# How he stands for BodyBalanceRules, from replicated state.
func _balance_posture() -> BodyBalanceRules.Posture:
	return BodyBalanceRules.posture_of(stance_active,
			SkaterStateMachine.state_off_balance(_sm.get_state()))


# Extend-never-shorten knockdown write for the impulse path (host + local-victim
# prediction), keeping the fall metadata coherent: a fresh entry seeds the fall
# from the transfer impulse's horizontal shove speed (the recoil direction was
# captured from the same vector by the caller); a follow-up hit that extends an
# in-flight window grows the total by the timer delta, so the elapsed clock
# (_knockdown_total − knockdown_timer) never restarts mid-fall.
func _set_knockdown_from_impulse(add_seconds: float, impulse: Vector3) -> void:
	var prev: float = knockdown_timer
	knockdown_timer = maxf(knockdown_timer, add_seconds)
	if knockdown_timer <= prev:
		return
	if prev <= 0.0:
		_knockdown_total = knockdown_timer
		_knockdown_entry_speed = Vector2(impulse.x, impulse.z).length()
	else:
		_knockdown_total += knockdown_timer - prev


# Same bookkeeping for every path that writes knockdown_timer from a received
# state (reconcile snap, wire apply, goal replay) — call with the pre-write
# timer AFTER skater.velocity has been stamped from the same state. A rising
# edge seeds the fall's tip rate from the replicated slide speed (the post-hit
# slide IS the shove); its direction is the replicated recoil_dir. Mid-window, the total only grows when the written timer
# exceeds anything seen this window — a received value can lag the local decay
# (a reconcile baseline is an RTT old), so a plain greater-than-previous check
# would inflate the total, and with it the elapsed clock, on every snap.
func _sync_knockdown_meta(prev_timer: float) -> void:
	if knockdown_timer <= 0.0:
		return
	if prev_timer <= 0.0:
		_knockdown_total = knockdown_timer
		_knockdown_entry_speed = Vector2(skater.velocity.x, skater.velocity.z).length()
	elif knockdown_timer > _knockdown_total:
		# An unseen follow-up hit grew the window — preserve elapsed continuity.
		_knockdown_total = maxf(_knockdown_total - prev_timer, 0.0) + knockdown_timer


# ── Entry Point ───────────────────────────────────────────────────────────────
# Whether this skater is committing to a deliberate deflect this tick. Base
# behaviour (human players, local and remote-on-host): holding the DEFLECT button
# (stick_lift / Q) without the puck. The loft level (scroll) then shapes it —
# FLAT grounded redirect, LOW grounded tip up, HIGH knock an airborne puck down
# (reach follows blade_can_interact; direction from Puck.apply_blade_deflect).
# AIController
# overrides this to always-false — bots don't deliberate-deflect; their
# one-timers hold the SLAP button off-puck (the real slapper charge + pickup
# zone — the only one-timer path on_puck_picked_up_network supports: a held
# wrister's state is force-reset to SKATING_WITH_PUCK on pickup, so a wrister
# release edge can never fire on a caught feed).
func _wants_deflect(input: InputState) -> bool:
	return input.stick_lift_held and not has_puck


# The deflect blade's target: on the ice for a puck met on the ice, at most a full lift.
func _deflect_lift_share() -> float:
	if puck == null:
		return 0.0
	_sample_live_puck_view(_live_puck_view)
	var lift: float = DeflectReachRules.lift_to_meet(_live_puck_view.position,
			_live_puck_view.velocity, skater.get_blade_contact_global(), puck.ice_height)
	if lift <= GameRules.PUCK_AIRBORNE_HEIGHT_M:
		return 0.0
	return minf(lift / blade_lift_height, 1.0)


# A lift starts only from plain puckless skating: a puck on the blade, a shot, a
# block or a check owns the stick. Any of those arriving mid-lift ends it, as does
# an opponent's lift, a tie, or being pinned; a pinner's stick stays in its hold.
func _advance_stick_check(input: InputState, delta: float) -> void:
	var stick_taken: bool = has_puck or skater.hit_committed or skater.is_knocked_down \
			or skater.is_forced_lift_active() or skater.stick_tied \
			or skater.pin_role == BoardPinRules.Role.PINNED \
			or _sm.get_state() != State.SKATING_WITHOUT_PUCK
	# F under Ctrl is dead: the commit has the stick.
	_stick_check.advance(input.stick_check_pressed and not input.hit_held,
			input.stick_check_held, not stick_taken, stick_taken, delta)
	skater.stick_check_phase = _stick_check.phase
	skater.stick_check_held = input.stick_check_held


# Adopts the host's lift phase ahead of a reconcile replay, which steps it on.
func _adopt_stick_check(state: SkaterNetworkState) -> void:
	_stick_check.adopt(state.stick_check_phase, state.stick_check_elapsed)
	skater.stick_check_phase = _stick_check.phase


func _process_input(input: InputState, delta: float) -> void:
	# Stamp movement intent for the cosmetic layers (gait glide / intent
	# crossovers / brake-gated hockey stop). Local, bot, and host-side client
	# simulation all funnel through here with real inputs; client-rendered
	# remotes get the same fields off the wire in RemoteController. Gated by
	# the SAME deadzone the movement physics uses, so "trying to move" means
	# the same thing to the animation as to the thrust — bot steering emits
	# small residual vectors at rest (potential-field repels never fully
	# cancel) that would otherwise read as a perpetual dig-in chop, and the
	# wire octant would inflate them to unit length on remote clients.
	_self_posing = false  # main live path delegates cosmetics to the render hook
	skater.move_intent = input.move_vector \
			if input.move_vector.length() > move_deadzone else Vector2.ZERO
	skater.brake_intent = input.brake
	# Feed the shared host-clock stamp to an active faceoff draw so its timing is
	# judged ping-neutrally (see Skater.set_draw_input_time). Only during a draw.
	if skater.is_draw_tracking():
		skater.set_draw_input_time(input.host_timestamp)
	_elevation_level = input.elevation_level
	skater.elevation_level = _elevation_level
	_current_aim_world = input.mouse_world_pos
	skater.stick_jarred = BodyCheckRules.is_rocked(stagger_timer, _body_check_config())
	_settle.read(input, has_puck and _sm.get_state() == State.SKATING_WITH_PUCK)

	# Deliberate-deflect intent (see Skater.deflect_intent): Q without the puck
	# redirects a loose puck instead of corralling it (carrying, Q is the nudge).
	# The host reads it in PuckController._check_interactions; the loft level signs
	# the redirect. The PRESS reads the incoming puck, once: held from before a
	# release, the blade stays put, so meeting a puck means reacting to it. Live
	# only — replay must not re-read.
	var deflecting: bool = _wants_deflect(input)
	if not is_replaying and (not deflecting or not skater.deflect_intent):
		skater.deflect_lift_share = _deflect_lift_share() if deflecting else 0.0
	skater.deflect_intent = deflecting

	# The deflecting blade rises to the puck it is about to meet. A forced lift (an
	# opponent hooked under your stick, or a check that rocked you) overrides
	# regardless of possession.
	skater.blade_up = skater.deflect_lift_share > 0.0 or skater.is_forced_lift_active()

	# Nudge: a deflect-button TAP while carrying pushes the puck off the blade as a
	# soft self-pass (nutmeg setup). Edge-triggered and gated to plain carry so
	# it never fires mid-charge; the is_replaying guard inside keeps it from
	# re-emitting during reconcile (same discipline as _do_release).
	if (input.stick_lift_pressed or _settle.unqueued == SkaterSettleGate.Press.NUDGE) \
			and not _settle.settling and has_puck and _sm.get_state() == State.SKATING_WITH_PUCK:
		_nudge()

	var tick_start_velocity: Vector3 = skater.velocity
	_apply_movement(input, delta)
	skater.in_stance = stance_active
	skater.stagger_left = stagger_timer
	_apply_press(input, delta, tick_start_velocity)
	# The frame this tick's IK and twist solve in tilts with the fall: every tick
	# lays its own, replay included (Scripts/networking/CLAUDE.md).
	_apply_fall_tilt(knockdown_getup_left())
	_advance_balance(tick_start_velocity, delta)
	_pose.apply_velocity_lean(delta)
	_pose.apply_facing(input, delta)
	_apply_state(input, delta)
	# Keep the PUCK ITSELF out of the net. The blade net-clamp (in apply_blade_
	# from_mouse) keeps the BLADE out, but a carried puck pins to a carry offset
	# OFF the blade (Skater.get_carry_target_global), a separate point the blade
	# clamp never validated — so a stick reaching from behind/beside could drag
	# the pinned puck into the net even with the blade reading legal. Runs after
	# _apply_state so it sees this tick's final blade pose.
	_collide_pinned_puck_with_net()
	# Mirror the state machine into the replicated field on every simulated
	# tick, AFTER _apply_state so same-tick transitions are visible to the
	# cosmetic consumers below (gait shot stance) and to Skater._process (stick
	# flex). Local and AI controllers also stamp this after their tick, but the
	# host-side client-simulation path (RemoteController._drive_from_input)
	# previously never stamped it, so host-rendered client skaters froze at a
	# stale shot state.
	skater.current_shot_state = _sm.get_state() as int
	_advance_stick_check(input, delta)
	# Save blade/hand world positions before upper body rotation. After the body
	# rotates toward the blade, re-expressing these in the new local frame gives
	# the bottom-hand IK the post-rotation geometry — so arm reach is evaluated
	# as if the body has fully caught up, independent of lerp speed.
	#
	# Skip the preservation through the slapper's wind-up and finish: both are
	# authored in upper-body-local space, so we WANT the stick to travel with the
	# turning torso (otherwise the body rotates underneath a stationary hand — the
	# coil is invisible, and on the release tick the shoulders snapping through
	# leave the stick behind).
	var pre_state: SkaterStateMachine.State = _sm.get_state()
	var is_slapper_charge: bool = (
			pre_state == SkaterStateMachine.State.SLAPPER_CHARGE_WITH_PUCK
			or pre_state == SkaterStateMachine.State.SLAPPER_CHARGE_WITHOUT_PUCK
			or pre_state == SkaterStateMachine.State.ONE_TIMER_RETENTION
			or (pre_state == SkaterStateMachine.State.FOLLOW_THROUGH
				and _sm.follow_through_is_slapper))
	var blade_world_pre: Vector3
	var hand_world_pre: Vector3
	if not is_slapper_charge:
		blade_world_pre = skater.upper_body_to_global(skater.get_blade_position())
		hand_world_pre = skater.upper_body_to_global(skater.get_top_hand_position())
	_pose.apply_upper_body(delta)
	if not is_slapper_charge:
		skater.set_top_hand_position(skater.upper_body_to_local(hand_world_pre))
		skater.set_blade_position(skater.upper_body_to_local(blade_world_pre))
	# Head tracking, off-hand IK, and the leg gait moved to render rate
	# (Skater.render_pose_update / _render_pose_update) — they feed only meshes,
	# not the blade world frame, so they don't belong in the per-tick + reconcile-
	# replay path. Stick/arm mesh rebuild already lives in Skater._process too.
	if not is_replaying:
		_pose.update_angular_velocities(delta)
		# Age the goal-celebration timer at physics rate. It used to ride the gait
		# pass, but the gait is render-rate + visibility-gated now, so the timer
		# owns its own physics tick here (real ticks only — it must not re-decrement
		# through reconcile replay) so it stays deterministic and never freezes for
		# an off-screen scorer.
		tick_celebration(delta)
		# Goal celebration: the scorer raises the stick, over the hand/blade pose
		# the tick just placed — cosmetic-only (pickup is locked through
		# GOAL_CELEBRATION), real ticks only, and gated to plain skating so a
		# whiffed shot's follow-through isn't fought over.
		var cel_state: SkaterStateMachine.State = _sm.get_state()
		if is_celebrating() and (cel_state == SkaterStateMachine.State.SKATING_WITH_PUCK
				or cel_state == SkaterStateMachine.State.SKATING_WITHOUT_PUCK):
			_shot_pose.apply_celebration_pose(_celebration_total - _celebration_timer,
					_celebration_timer)
		else:
			_ik.hold_free_hand(Vector3.ZERO, 0.0)
		_pose_bridge.settle(skater, _sm.get_state(), delta, _aiming.slapper_setup_done,
				_sm.follow_through_is_slapper)
	# Replay too: down with block held, nothing re-solves the stick, so the next
	# tick's twist follows the one this leaves (Scripts/networking/CLAUDE.md).
	_apply_down_pose()


# Render-rate cosmetic pose pass, registered on the skater and invoked once per
# rendered frame from Skater._process (visibility-gated). Runs the purely-cosmetic
# passes that used to sit in the physics tick: the leg gait, head tracking
# (off the last-seen aim), and the off-hand grip IK. None feed the blade world
# frame, so running them at render rate can't affect pickup or reconcile. Local
# and AI controllers use this base; RemoteController overrides it to drop head
# tracking (a wire-fed body has no cursor aim).
func _render_pose_update(delta: float) -> void:
	if skater == null or _self_posing:
		return
	_skating.apply(delta)
	_apply_knockdown_fall()
	# The head and the off hand are mesh (Skater.on_camera).
	if not skater.on_camera():
		return
	_pose.apply_head_tracking(delta)
	_ik.update_bottom_hand(delta)


# Render-rate knockdown fall: tip the whole cosmetic rig about the skates in the
# recoil direction, off the tipping-body solve. Reads only replicated /
# re-derived state (timer, window total, entry shove, recoil dir), so every
# machine renders the same fall while the gameplay body underneath keeps its
# deterministic slide. Upright, it only settles the rig back level.
func _apply_knockdown_fall() -> void:
	var kd_t: float = knockdown_getup_left()
	if not _apply_fall_tilt(kd_t):
		return
	if kd_t <= 0.0 or not skater.on_camera():
		return
	# Leg sprawl overlay, composed on the gait's crumple (which zeroed the
	# stride under it). The side pick reads the RAW recoil dir, not the
	# wall-deflected one — the deflection re-resolves per frame near the glass
	# and would flip the pinned leg mid-lie. It lands after the tilt, which the
	# legs read to rest their skates on the ice.
	if _sprawl_scratch == null:
		_sprawl_scratch = KnockdownFallRules.SprawlPose.new()
	var legs: Vector3 = _skating.leg_segment_lengths()
	var share: float = knockdown_pose_weight()
	# The buckle is solved from the lying drop the gait is applying at this
	# instant: the drop is 1 − cos of the angle, so scaling a solved pose instead
	# leaves the boots under the ice part-way. It hands the legs to the get-up's
	# kneel as he comes up onto his knees.
	var lie: float = KnockdownFallRules.lie_share(kd_t)
	KnockdownFallRules.sprawl_into(_sprawl_scratch, knockdown_elapsed(),
			_fall_entry_speed(), stagger_recoil_dir, knockdown_drop_m() * share * lie,
			legs, _fall_config(), lie)
	skater.apply_knockdown_leg_overlay(_sprawl_scratch, share * lie)


# The whole-rig tilt alone; false once upright and level. A pure function of
# tick state, so the tick lays it too: the gameplay frame hangs from MeshRoot.
func _apply_fall_tilt(kd_t: float) -> bool:
	var tilt: float = knockdown_fall_tilt()
	if tilt == 0.0 and kd_t <= 0.0:
		skater.set_knockdown_fall(Vector3.UP, 0.0)
		return false
	# Fall direction is the recoil direction (body frame); the tilt axis is its
	# horizontal perpendicular, so positive tilt tips the head the way the hit
	# shoved. Falling backward lands face-up, forward face-down — the read
	# emerges from direction vs facing with no face-up/down logic of its own.
	# The wall deflection runs in WORLD space (the rink is world geometry) on the
	# capsule's live position each frame: the capsule keeps sliding while down,
	# so a body that goes down near the glass sweeps onto the wall line as it
	# slides in — the crumple-down-the-boards read — instead of resolving once at
	# entry and clipping through as the slide closes the gap.
	var dir_world: Vector3 = skater.global_transform.basis \
			* Vector3(stagger_recoil_dir.x, 0.0, stagger_recoil_dir.y)
	# Boards and the goal net both report the same proximity shape; the stronger
	# (nearer) obstacle wins the deflection. In the band behind the net where
	# both are within reach, the per-frame re-resolve self-corrects: a tangent
	# that slides toward the other obstacle raises its closeness next frame and
	# the deflection re-picks.
	var pos_xz := Vector2(skater.global_position.x, skater.global_position.z)
	var obstacle: Vector2 = BoardPlayRules.board_proximity(
			pos_xz, knockdown_fall_body_reach_m)
	var net_prox: Vector2 = GameRules.net_proximity(pos_xz, knockdown_fall_body_reach_m)
	if net_prox.length_squared() > obstacle.length_squared():
		obstacle = net_prox
	var safe_dir: Vector2 = KnockdownFallRules.wall_safe_fall_dir(
			Vector2(dir_world.x, dir_world.z), obstacle)
	var d: Vector3 = skater.global_transform.basis.inverse() \
			* Vector3(safe_dir.x, 0.0, safe_dir.y)
	var carry: Vector3 = -d * DiveRules.com_carry_m(tilt) if _diving() else Vector3.ZERO
	skater.set_knockdown_fall(Vector3.UP.cross(d), tilt, carry)
	return true


# Elapsed down-time of the current knockdown (0 when upright) — the fall clock
# every knockdown pose channel keys off. _knockdown_total is maintained through
# entry, extension, reconcile snaps, and replay sync (_sync_knockdown_meta), so
# this is as replicated-deterministic as the timer itself.
func knockdown_elapsed() -> float:
	return maxf(_knockdown_total - knockdown_timer, 0.0)


# The get-up tail left (0..1): 1 while fully down, 0 upright — the clock every
# get-up envelope in KnockdownFallRules takes.
func knockdown_getup_left() -> float:
	return clampf(knockdown_timer / maxf(knockdown_getup_seconds, 0.001), 0.0, 1.0)


# How deep into the rocked band he is, 0..1 (BodyCheckRules.rocked_share).
func rocked_share() -> float:
	return BodyCheckRules.rocked_share(stagger_timer, _body_check_config())


# How much of the down pose holds over the live one (0..1): ramped in over the
# buckle window, full through the lie and the kneel, easing out as he stands up
# off the knee. The gait's crumple sinks the body by this share of the drop, and
# the legs buckle to exactly that share.
func knockdown_pose_weight() -> float:
	var kd_t: float = knockdown_getup_left()
	if kd_t <= 0.0:
		return 0.0
	return KnockdownFallRules.stand_hold(kd_t) \
			* KnockdownFallRules.entry_ramp(knockdown_elapsed(), _fall_config())


# How far the down pose sinks the body. None for a dive: it goes down long off
# its skates rather than crumpling onto them.
func knockdown_drop_m() -> float:
	return 0.0 if _diving() else knockdown_pose_drop_m


# Current whole-body fall tilt (radians): the tipping-body solve, gone by the
# time he is on his knees. Closed-form in replicated state (timer, window total,
# entry shove), so it serves both the render-rate fall pass and the
# deterministic tick (the pose coordinator's fold) without divergence.
func knockdown_fall_tilt() -> float:
	var kd_t: float = knockdown_getup_left()
	if kd_t <= 0.0:
		return 0.0
	return KnockdownFallRules.tilt_at(
			knockdown_elapsed(), _fall_entry_speed(), _fall_config()) \
			* KnockdownFallRules.lie_share(kd_t)


# Waist-fold magnitude for the current fall instant: the reflexive airborne
# curl resolving to the lie-flat complement as the body reaches the ice
# (KnockdownFallRules.fold_at), developing through the same entry ramp as the
# gait's crumple. SkaterPoseCoordinator scales it by the lying share and
# decomposes it along the recoil direction.
func knockdown_fold_rad() -> float:
	# A diver stretches out along the layout; only a hit curls.
	var curl: float = 0.0 if _diving() else deg_to_rad(knockdown_fold_deg)
	return KnockdownFallRules.fold_at(knockdown_fall_tilt(), curl, _fall_config()) \
			* KnockdownFallRules.entry_ramp(knockdown_elapsed(), _fall_config())


# A downed player's hands over whatever the states placed — the brace, or a
# diver's stick laid out — handing back to the live IK through the get-up.
# Anything that re-solves the blade off the cursor while he is down owes this.
func _apply_down_pose() -> void:
	if knockdown_timer <= 0.0:
		return
	if skater.is_diving:
		_apply_dive_layout()
	else:
		_apply_knockdown_brace()
	_apply_getup_hold()


# The braced-arm targets for a downed player, in upper-body-local space (so they
# lie down with the tilted rig). The reflex depends on which way the body is
# going down: face-down (forward fall, local −Z) the arms shoot OUT to catch the
# ice; face-up and sideways they pull in over the chest, stick low across the
# body — the guarded curl of a player riding out a hit. A harder hit reaches
# farther, so the brace varies with the fall like the legs do.
# A diver's stick lies out along the layout, its blade flat on the ice — the
# stick that knocks a puck away. The hand reaches on from the lying shoulder and
# the blade follows one stick length past it (a held pose authored blade-first
# draws a short stick; Scripts/controllers/CLAUDE.md). On the brace's own clock,
# so going down and getting up are continuous.
func _apply_dive_layout() -> void:
	var kd_t: float = knockdown_getup_left()
	var brace_t: float = KnockdownFallRules.brace_at(
			knockdown_elapsed(), kd_t, knockdown_brace_in_seconds)
	if brace_t <= 0.001:
		return
	var layout := Vector3(skater.dive_layout.x, 0.0, skater.dive_layout.y)
	var shoulder: Vector3 = skater.upper_body_to_global(skater.shoulder.position)
	# The arm reaches down for the ice first and out along it as the body lies,
	# and up to it from a shoulder lying lower: the hand stays just off the ice.
	var reach: float = DIVE_ARM_STRETCH * (skater.upper_arm_length + skater.forearm_length)
	var down: float = clampf(shoulder.y - DiveRules.HAND_HEIGHT_M, -reach, reach)
	var hand_world: Vector3 = shoulder + layout * sqrt(reach * reach - down * down) \
			+ Vector3.DOWN * down
	var drop: float = hand_world.y - blade_height
	var span: float = sqrt(maxf(stick_length * stick_length - drop * drop, 0.0))
	var blade_world: Vector3 = Vector3(hand_world.x, blade_height, hand_world.z) + layout * span
	var hand_target: Vector3 = skater.upper_body_to_local(hand_world)
	var blade_target: Vector3 = skater.clamp_blade_to_walls(skater.upper_body_to_local(blade_world))
	skater.set_top_hand_position(skater.get_top_hand_position().lerp(hand_target, brace_t))
	skater.set_blade_position(skater.get_blade_position().lerp(blade_target, brace_t))


# Goes down in a dive: the knockdown's window and fall, laid out toward the
# cursor, with no velocity of its own — the body slides on as it was going.
func _start_dive(input: InputState) -> void:
	var travel := Vector2(skater.velocity.x, skater.velocity.z)
	skater.dive_layout = DiveRules.layout_dir(skater.global_position, input.mouse_world_pos,
			travel if travel.length_squared() > 1e-4 else _pose.facing)
	var local: Vector3 = skater.global_transform.basis.inverse() \
			* Vector3(skater.dive_layout.x, 0.0, skater.dive_layout.y)
	if Vector2(local.x, local.z).length_squared() > 1e-8:
		stagger_recoil_dir = Vector2(local.x, local.z).normalized()
	skater.is_diving = true
	_set_knockdown_from_impulse(DiveRules.DOWN_S, skater.velocity)


# The down flags off the timer. A diver's stick and low block play only while he
# lies laid out; getting up he is down like anyone (DiveRules: the timer holds at
# the get-up's start while block is held).
func _set_down_flags(diving: bool) -> void:
	skater.is_knocked_down = knockdown_timer > 0.0
	skater.is_diving = diving
	skater.dive_laid_out = diving and knockdown_timer >= knockdown_getup_seconds


# A diver's layout in world space, from the replicated fall direction (body
# frame) and the facing, which holds still while down.
func _sync_dive_layout() -> void:
	if not skater.is_diving:
		return
	var world: Vector3 = skater.global_transform.basis \
			* Vector3(stagger_recoil_dir.x, 0.0, stagger_recoil_dir.y)
	if Vector2(world.x, world.z).length_squared() > 1e-8:
		skater.dive_layout = Vector2(world.x, world.z).normalized()


func _apply_knockdown_brace() -> void:
	var kd_t: float = knockdown_getup_left()
	var brace_t: float = KnockdownFallRules.brace_at(
			knockdown_elapsed(), kd_t, knockdown_brace_in_seconds)
	if brace_t <= 0.001:
		return
	var side: float = -1.0 if skater.is_left_handed else 1.0
	var face_down: float = clampf(-stagger_recoil_dir.y, 0.0, 1.0)
	var reach: float = 0.6 + 0.4 * clampf(
			_knockdown_entry_speed / (knockdown_fall_max_entry_omega
			* maxf(knockdown_fall_com_height_m, 0.001)), 0.0, 1.0)
	var hand_target := Vector3(skater.shoulder.position.x,
			hand_rest_y * (0.8 - 0.35 * face_down),
			skater.shoulder.position.z - 0.18 - 0.35 * face_down * reach)
	var blade_target := Vector3(
			skater.shoulder.position.x + side * (0.35 + 0.2 * face_down * reach),
			0.05, skater.shoulder.position.z - 0.5 - 0.3 * face_down * reach)
	blade_target = skater.clamp_blade_to_walls(blade_target)
	skater.set_top_hand_position(skater.get_top_hand_position().lerp(hand_target, brace_t))
	skater.set_blade_position(skater.get_blade_position().lerp(blade_target, brace_t))


# Getting up, the arms hold the stick rather than dangle it: the top hand in
# front of the chest, the blade out on the ice ahead on the stick side. It
# takes over as the brace or the dive's layout lets go and gives the hands back
# to the live IK as he stands. The hand is posed and the blade derived one stick
# along the bearing (Scripts/controllers/CLAUDE.md, pose the hand), in the
# world, because the kneel has taken the frame down with the body.
func _apply_getup_hold() -> void:
	var kd_t: float = knockdown_getup_left()
	var hold: float = (1.0 - KnockdownFallRules.lie_share(kd_t)) \
			* KnockdownFallRules.stand_hold(kd_t)
	if hold <= 0.001:
		return
	var side: float = -1.0 if skater.is_left_handed else 1.0
	# In the facing's frame, which holds still while down; the shoulders keep
	# turning after the cursor.
	var body: Basis = skater.global_transform.basis
	var hand_world: Vector3 = skater.upper_body.global_position + body \
			* (skater.shoulder.position + Vector3(0.0, -GETUP_HAND_DROP_M, -GETUP_HAND_FWD_M))
	var spread: float = deg_to_rad(GETUP_STICK_SPREAD_DEG)
	var bearing: Vector3 = body * Vector3(side * sin(spread), 0.0, -cos(spread))
	var drop: float = hand_world.y - blade_height
	var span: float = sqrt(maxf(stick_length * stick_length - drop * drop, 0.0))
	var blade_world: Vector3 = Vector3(hand_world.x, blade_height, hand_world.z) + bearing * span
	var hand_target: Vector3 = skater.upper_body_to_local(hand_world)
	var blade_target: Vector3 = skater.clamp_blade_to_walls(skater.upper_body_to_local(blade_world))
	skater.set_top_hand_position(skater.get_top_hand_position().lerp(hand_target, hold))
	skater.set_blade_position(skater.get_blade_position().lerp(blade_target, hold))


# Aim-only blade update for FACEOFF_PREP: drives the blade target from the
# mouse, twists the upper body and head to follow it, and refreshes the
# dependent IK + visual meshes. Skips movement, lower-body facing rotation
# (the skater stays squared up to the dot), and state-machine dispatch.
# Callers must already have confirmed the phase allows blade aim during a
# locked phase.
func apply_blade_aim_only(input: InputState, delta: float) -> void:
	# Movement is locked — whatever keys are down, nothing is being tried.
	skater.move_intent = Vector2.ZERO
	skater.brake_intent = false
	# Nothing accelerates while locked; the lean settles.
	_advance_balance(skater.velocity, delta)
	# Feed the shared host-clock stamp to the faceoff draw (this is the countdown
	# wind-up/rip path), so its timing is judged ping-neutrally.
	if skater.is_draw_tracking():
		skater.set_draw_input_time(input.host_timestamp)
	_ik.apply_blade_from_mouse(input, delta)
	# Preserve blade/hand world positions across the upper-body rotation —
	# same dance as _process_input. Without it the blade slides sideways as
	# the torso twists, decoupling the stick from where the player aimed it.
	var blade_world_pre: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
	var hand_world_pre: Vector3 = skater.upper_body_to_global(skater.get_top_hand_position())
	_pose.apply_upper_body(delta)
	_pose.apply_head_tracking(delta)
	skater.set_top_hand_position(skater.upper_body_to_local(hand_world_pre))
	skater.set_blade_position(skater.upper_body_to_local(blade_world_pre))
	# This locked-phase path poses its own gait ready-stance + off-hand (a brief
	# countdown, not the hot path); the render hook yields to it (see _self_posing).
	_self_posing = true
	_skating.apply(delta)
	# apply_facing doesn't run here, so this is the only publisher of the lower
	# body's yaw for the whole countdown — the skate-in's hip-to-travel
	# alignment unwinds under the set skater instead of freezing at arrival.
	_pose.apply_lower_body_yaw(delta)
	_ik.update_bottom_hand(delta)


# ── Network State ─────────────────────────────────────────────────────────────
# Writes the current state into a caller-owned instance — StateBufferManager
# fills its pre-allocated ring slots through this every physics tick, so this
# path must not allocate. Flattening to Array happens at the RPC boundary
# (GameManager.get_world_state), not here.
func fill_network_state(state: SkaterNetworkState) -> void:
	state.position = skater.global_position
	state.velocity = skater.velocity
	state.blade_position = skater.get_blade_position()
	state.blade_contact_world = skater.get_blade_contact_global()
	state.settle_left_s = _settle.time_left(NetworkManager.estimated_input_stamp_time()) \
			if has_puck else 0.0
	state.top_hand_position = skater.get_top_hand_position()
	state.upper_body_rotation_y = skater.get_upper_body_rotation()
	state.facing = skater.get_facing()
	state.facing_angular_velocity = _pose.facing_angular_velocity
	state.upper_body_angular_velocity = _pose.upper_body_angular_velocity
	state.last_processed_host_timestamp = last_processed_host_timestamp
	state.is_ghost = skater.is_ghost
	state.elevation_level = skater.elevation_level
	state.blade_up = skater.blade_up
	state.stick_check_phase = _stick_check.phase
	state.stick_check_elapsed = _stick_check.elapsed
	state.stick_tied = skater.stick_tied
	state.pin_role = skater.pin_role
	state.pin_strength = skater.pin_strength
	state.diving = skater.is_diving
	# Host-only shaft segment for stick-lift claim resolution (paired with
	# blade_contact_world). World-space grip point — the wire top_hand_position
	# is upper-body-local and can't be used for host-side world geometry.
	state.top_hand_world = skater.upper_body_to_global(skater.get_top_hand_position())
	state.shot_state = _sm.get_state() as int
	# One bit, read by the shot_state it rides with (no validity flag).
	state.blade_side = skater.wire_blade_side(state.shot_state)
	# The normalized 0..1 charge (skater.shot_charge covers the wrister's
	# predicted release power AND slapper wind-up), in the u8 codec range.
	# Consumed on the receive side by the cosmetic pose layers (stick flex,
	# shot stance, wind-up engagement) — charge feedback is fully diegetic:
	# the wind-up animation itself is the gauge, there is no charge ring.
	state.shot_charge = skater.shot_charge
	state.stagger_timer = stagger_timer
	state.knockdown_timer = knockdown_timer
	state.balance_tilt = skater.balance_tilt()
	state.balance_tilt_vel = balance_tilt_vel
	state.torso_lean = Vector2(_pose.upper_body_lean, _pose.upper_body_lean_roll)
	state.posture_lean = _pose.velocity_lean_x
	state.recoil_dir = stagger_recoil_dir
	state.move_intent = skater.move_intent
	state.brake_intent = skater.brake_intent
	state.hit_committed = skater.hit_committed
	state.stance_active = stance_active

# One tick of the balance lean: the body tips toward the acceleration THIS tick's
# movement produced (BalanceRules.balance_tilt), through the critically damped
# spring. Measured across _apply_movement alone, so a body check's impulse —
# applied after the tick, in the skater's integration — never enters it, and a
# reconcile that snaps velocity replays it exactly. A body down on the ice
# balances on nothing, so its slide's friction tips nothing and the lean settles.
func _advance_balance(tick_start_velocity: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return
	var dv: Vector3 = skater.velocity - tick_start_velocity
	var target := Vector2.ZERO
	if knockdown_timer <= 0.0:
		target = BalanceRules.balance_tilt(Vector2(dv.x, dv.z) / delta,
				deg_to_rad(skater.balance_lean_cap_deg))
	var s: Vector4 = BalanceRules.spring_step(skater.balance_tilt(), balance_tilt_vel,
			target, skater.balance_omega, delta)
	balance_tilt_vel = Vector2(s.z, s.w)
	skater.set_balance_tilt(Vector2(s.x, s.y), balance_tilt_vel)


func get_shot_state() -> int:
	return _sm.get_state()


# Whether the stick has the puck to reach for this tick (ReachPurposeRules).
func reach_purpose() -> float:
	return _ik.reach_purpose


# The gait's (stop weight as the scrape hears it, skid weight, turn load) this
# render pass.
func skate_sound() -> Vector3:
	return Vector3(_skating.scrape_stop_weight(), _skating.skid_weight, _skating.turn_load)

func apply_network_state(_net_state: SkaterNetworkState, _host_ts: float) -> void:
	pass  # overridden by RemoteController on client

# Default 0 for controllers that don't queue inputs (LocalController, AIController).
# RemoteController overrides this with its actual input-queue depth, which is
# encoded into world state for client-side adaptive interpolation tuning.
func get_queue_depth() -> int:
	return 0

func apply_replay_state(state: SkaterNetworkState, delta: float) -> void:
	if skater == null:
		return
	# This path poses the gait + off-hand itself (below), so the render-rate
	# cosmetic hook yields to it while a replay is driving this skater.
	_self_posing = true
	# The replay poses the recorded body; a live celebration's knee bounce and
	# fist pump are read off this controller, and its timer is frozen here.
	end_celebration()
	skater.global_position = state.position
	skater.visual_offset = Vector3.ZERO
	skater.velocity = state.velocity
	skater.blade_up = state.blade_up
	skater.stick_check_phase = state.stick_check_phase
	skater.stick_tied = state.stick_tied
	skater.pin_role = state.pin_role
	skater.pin_strength = state.pin_strength
	# Intent feeds the gait's input-driven reads below (glide / dig-in /
	# crossovers / brake stop) — stamp it like the live controllers do, so
	# playback strides match live play instead of reading zero (file viewer)
	# or stale live-play intent (goal replay on live actors).
	skater.move_intent = state.move_intent
	skater.brake_intent = state.brake_intent
	skater.hit_committed = state.hit_committed
	# Same for the shot-state renders Skater._process drives every frame:
	# stick flex (shot_state transitions fire the release whip, shot_charge
	# sets the load bow) and the loft-level blade scoop. Goal replays run on
	# LIVE actors, so without these stamps the fields freeze at whatever the
	# live tick last wrote and the replayed shot plays with the wrong stick.
	skater.current_shot_state = state.shot_state
	# The recorded blade side (the wrister address, or the carry side), applied
	# by state like the live remote apply — the wire bit is garbage outside them.
	skater.apply_wire_blade_side(state.blade_side)
	skater.shot_charge = state.shot_charge
	skater.elevation_level = state.elevation_level
	# Skid VFX (SkaterVFX trail marks + spray) keys off is_braking — stamp it
	# from the recorded brake bit so replayed hockey stops spray like live ones.
	skater.is_braking = state.brake_intent
	# The gait's stance read keys off the controller's resolved stance — stamp
	# it from the recorded bit so a replayed stance skates like the live one.
	stance_active = state.stance_active
	stagger_timer = state.stagger_timer
	stagger_recoil_dir = state.recoil_dir
	balance_tilt_vel = state.balance_tilt_vel
	skater.set_balance_tilt(state.balance_tilt, state.balance_tilt_vel)
	var prev_kd: float = knockdown_timer
	knockdown_timer = state.knockdown_timer
	_set_down_flags(state.diving)
	# Fall metadata off the recorded velocity (stamped above), so a replayed
	# knockdown falls the way the live one did.
	_sync_knockdown_meta(prev_kd)
	skater.set_facing(state.facing)
	_sync_dive_layout()
	skater.set_upper_body_rotation(state.upper_body_rotation_y)
	skater.set_top_hand_position(state.top_hand_position)
	_pose.apply_wire_lean(state)
	skater.set_blade_position(state.blade_position)
	_ik.update_bottom_hand(delta)
	# Procedural leg gait — derived from the velocity just applied, exactly as in
	# live play, so replayed skaters stride instead of gliding rigidly. `delta` is
	# the replay's virtual-clock advance this frame (slow-mo-scaled, 0 on a paused
	# scrub) so the stride cadence tracks the visible motion rather than wall time.
	_skating.apply(delta)
	_apply_knockdown_fall()
	# Lower-body yaw channels the gait publishes (hockey-stop skid, hip-to-travel
	# alignment, wrist-shot hip coil). On the simulating machine the pose
	# coordinator writes these in apply_facing, which never runs on this path —
	# mirror the write (lower_body_lag itself is a facing-turn artifact that
	# doesn't exist here).
	skater.set_lower_body_lag(
			_skating.stop_yaw_offset + _skating.travel_align_yaw + _skating.shot_hip_yaw)

signal puck_release_requested(direction: Vector3, power: float, is_slapper: bool)
# Debug/HUD annotation for the most recent release: "FH"/"BH" for wristers
# (the classification that drove the backhand power penalty), "" for quick
# shots and slappers (no backhand concept — quick takes no penalty, there is
# no backhand slapper). Set just before puck_release_requested fires; the
# shot-speed toast reads it alongside the signal.
var last_release_hand: String = ""
# Whether the most recent release was a deliberate SHOT ATTEMPT rather than a pass
# or a forced knock-loose. Set just before puck_release_requested fires; GameManager
# reads it at _start_pending_shot_from_carrier and hands it to ShotOnGoalTracker,
# which cannot otherwise tell an errant pass from a missed shot (a pass in Mitts IS
# a paced wrister, so both arrive on the same signal).
#
# The read is the BUTTON, and deliberately only the button: quick-pass is a pass, a
# charged wrister or a slapper is a shot. A bot's PASS_PRESSED state knows more —
# it knows a charged wrister is a feed — but reading it would exempt bot passes
# from the Corsi count while a human doing the identical thing paid for it, and a
# comparative stat has to mean the same thing on every row (#579). The cost is
# symmetric: sniping with the pass button loses an attempt when it misses the net.
var last_release_was_shot: bool = false
# Fired when the player releases slap while the puck is nearby but not yet
# carried — the leniency one-timer. GameManager acquires + releases the puck;
# the controller transitions to follow-through immediately.
signal one_timer_release_requested(direction: Vector3, power: float)

func _do_release(direction: Vector3, power: float) -> void:
	if is_replaying:
		return
	# The retention hold is the tail of a slapper swing, so a shot leaving from it
	# is a slapper too — without this the one-timer's crack and replay tag would
	# come out as a wrister's.
	var slapper: bool = _sm.get_state() == State.SLAPPER_CHARGE_WITH_PUCK \
			or _sm.get_state() == State.ONE_TIMER_RETENTION
	puck_release_requested.emit(direction, power, slapper)


# Net COLLISION for the carried puck. The puck rides a pin off the blade
# (get_carry_target_raw), so it is a body in its own right and gets the same net
# every other body gets — pipes hard, twine solid but non-punitive. This is the
# only place a net contact can cost you the puck; the blade's own collision
# (SkaterIKCoordinator.resolve_blade_against_net) is pose-only.
#
# Two things this must do:
#
# 1. RESOLVE the pin, not merely test it. Puck._physics_process places the puck at
#    get_carry_target_global() every tick, so a correction that is computed and
#    discarded leaves the puck wherever the blade put it — inside the mesh included.
# 2. Remember the RESOLVED pin as the next sweep's start. The twine is two-sided
#    and NetGeometry.interior_or_mouth classifies from the segment start, so a
#    `prev` that was allowed inside the cavity flips the next tick's faces from
#    "push out" to "hold in", and one tick of penetration latches: a stick swiped
#    laterally behind the goal line walks the puck through the side mesh and across
#    the line. `prev` is therefore always a position the net has already vouched
#    for.
#
# There is no legality test here and none anywhere else. A puck ends up in the
# cage only by going through the mouth, because the mouth is the only opening and
# every other face is solid to both the puck and the stick — see
# docs/net-play-plan.md §3.
func _collide_pinned_puck_with_net() -> void:
	if not has_puck:
		_has_prev_carry_pin = false
		skater.carry_pin_correction = Vector3.ZERO
		return
	var raw: Vector3 = skater.get_carry_target_raw()
	# On the first carry tick the sweep starts at the spot the puck was picked up
	# from. Starting from the pin itself would classify the twine from the blade's
	# side, so a puck picked up across the mesh would be held on the far side of
	# it. Only the host knows the carrier; a client's local carry starts from the
	# puck it is drawing.
	var prev: Vector3 = _prev_carry_pin
	if not _has_prev_carry_pin:
		prev = puck.picked_up_from if puck.carrier == skater else puck.global_position

	# IRON — a puck caught on the pipe comes off, whatever the carrier is doing.
	# This is the distinction that matters at the net, and it is a property of the
	# SURFACE rather than of the contact: a pipe is a hard 3 cm edge, so a puck
	# pressed against it and dragged sideways snags and pops loose. Broad compliant
	# twine is the opposite — the puck slides along it and you keep handling (see
	# below), which is why stickhandling into the back of the net costs nothing.
	#
	# Deliberately NOT gated on the rebound having magnitude. deflect_velocity
	# returns zero for a stationary carrier and passes a separating velocity
	# through unchanged, so an earlier magnitude guard skipped the release in
	# exactly the case that needs it: puck wedged on the post, carrier skating off,
	# blade correctly held back by the reach limit — and the puck simply sat there.
	# A catch is a catch at any speed.
	if PuckGeometryCollision.resolve_posts(
			raw, skater.velocity, GameRules.PUCK_COLLISION_RADIUS, _net_pin_result) \
			or PuckGeometryCollision.resolve_crossbar_bends(
					raw, skater.velocity, GameRules.PUCK_COLLISION_RADIUS, _net_pin_result):
		var ring: Vector3 = _net_pin_result.velocity
		var dir: Vector3 = ring
		dir.y = 0.0
		if dir.length() < 0.001:
			# No rebound to inherit (a slow or stationary catch): the puck drops off
			# along the pipe's own outward normal, which the ejection already encodes.
			dir = _net_pin_result.position - raw
			dir.y = 0.0
		if dir.length() >= 0.001:
			_has_prev_carry_pin = false
			skater.carry_pin_correction = Vector3.ZERO
			last_release_was_shot = false  # forced dispossession, not an attempt
			_do_release(dir.normalized(), maxf(ring.length(), post_catch_release_speed))
			return

	# TWINE — solid, and it does NOT strip. Pressing the puck into the mesh holds it
	# at the surface for as long as you like; the mesh is something you cannot reach
	# through, not something that confiscates. Reach is bounded before this instead —
	# see SkaterIKCoordinator._board_reach_limit, which folds the net into the same
	# cast that bounds reach at the boards.
	var resolved: Vector3 = raw
	if PuckGeometryCollision.resolve_net_panels(
			prev, raw, skater.velocity, GameRules.PUCK_COLLISION_RADIUS, _net_pin_result):
		resolved = _net_pin_result.position
	skater.carry_pin_correction = resolved - raw
	_prev_carry_pin = resolved
	_has_prev_carry_pin = true


# Nudge: the carrier taps the puck off the blade as a soft self-pass. The
# released velocity is the skater's horizontal momentum plus a small push along
# the blade's current sweep direction — so the puck keeps pace with the carrier
# and only drifts a touch in the direction the stick was moving. Host-derived
# from the carrier's authoritative velocity exactly like a shot (the signal
# carries the host-computed velocity during remote-input replay, the
# client-predicted velocity locally). Skips during reconcile replay.
signal nudge_requested(velocity: Vector3)

func _nudge() -> void:
	if is_replaying:
		return
	var skater_vel := Vector3(skater.velocity.x, 0.0, skater.velocity.z)
	# Blade sweep RELATIVE to the carrier: the absolute blade world velocity minus
	# the skater's own translation. Using the absolute velocity made the push
	# collapse to the skating direction while moving (own velocity drowns out the
	# sweep); subtracting it recovers the true stick-sweep direction so the cursor
	# steers the nudge at speed exactly as it does standing still.
	var blade_dir := skater.blade_world_velocity - Vector3(skater.velocity.x, 0.0, skater.velocity.z)
	blade_dir.y = 0.0
	var push := Vector3.ZERO
	if blade_dir.length() > 0.01:
		push = blade_dir.normalized() * nudge_speed
	# Inherit slightly less than full momentum so the puck drifts back relative to
	# the carrier while skating — that drift plus the sweep push is the nutmeg gap.
	nudge_requested.emit(skater_vel * nudge_velocity_retain + push)

# ── Puck Signals ──────────────────────────────────────────────────────────────
# `settle_until_ms`: the catch's settle deadline (settle_deadline_ms), 0 = clean.
# `feed`: the puck's velocity in this skater's frame at the catch (world XZ),
# which a caught one-timer strikes.
func on_puck_picked_up_network(settle_until_ms: int = 0, feed: Vector2 = Vector2.ZERO) -> void:
	has_puck = true
	_settle.arm(settle_until_ms)
	_one_timer_feed = feed
	if _sm.get_state() == State.ONE_TIMER_RETENTION:
		# The feed landed during the committed hold — the swing caught it. Pin it
		# to the strike spot (or the puck snaps up to the raised blade) and let the
		# hold run out; the release at the end is now the carried slapshot rather
		# than the leniency redirect. Arm the window if the wind-up didn't already,
		# so the graded centre bonus applies to a catch made during the hold
		# exactly as to one made during the charge.
		skater.set_slapper_zone(false)
		skater.enter_slapshot_pinning(slapper_strike_local())
		if _aiming.one_timer_window_timer <= 0.0:
			_aiming.one_timer_window_timer = one_timer_window_duration
		return
	if _sm.get_state() == State.SLAPPER_CHARGE_WITHOUT_PUCK:
		# Puck arrived during a puckless slapper wind-up: it is already at the
		# strike spot, the circle it was caught in. Pin it there on the ice (or it
		# snaps to the overhead wind-up blade) and switch into the with-puck
		# charge. The centre rather than where this machine's puck happens to be,
		# so host and client pin the same point.
		skater.set_slapper_zone(false)
		skater.enter_slapshot_pinning(slapper_strike_local())
		if _aiming.slapper_stance_line == Vector2.ZERO:
			_aiming.slapper_stance_line = _sm.locked_slapper_dir
		_sm.set_state(State.SLAPPER_CHARGE_WITH_PUCK)
		if _aiming.slapper_charge_timer >= one_timer_min_windup_time:
			# A genuine one-timer: the wind-up was already built when the feed
			# arrived. Open the timing window — release within
			# one_timer_window_duration to fire, or it cancels back to carry.
			_aiming.one_timer_window_timer = one_timer_window_duration + one_timer_window_lag_grace()
			if show_one_timer_indicator:
				skater.update_slapper_indicator_convergence(1.0)
				skater.update_slapper_indicator_window(1.0)
		# else: the puck was already at the stick when the wind-up started (charge
		# still ~0). Leave the window closed so it doesn't open at no power and
		# cancel straight to carry — this is now a plain slapshot charge that keeps
		# building and fires on release. _update_one_timer_indicator drops the
		# reticle for a windowless with-puck charge, leaving just the aim arrow.
	else:
		_sm.set_state(State.SKATING_WITH_PUCK)

func on_puck_released_network() -> void:
	if not has_puck:
		return
	has_puck = false
	_settle.clear()
	if _sm.get_state() == State.ONE_TIMER_RETENTION:
		# Poked/lifted off the blade mid-hold. The swing is already committed, so
		# don't snap out of it — let the hold run down and whiff through the full
		# follow-through, the same read a missed leniency one-timer gives.
		return
	_transition_to_skating()

func teleport_to(pos: Vector3, facing: Vector2 = Vector2.ZERO) -> void:
	# A hard teleport (respawn / slot swap) overrides any in-progress skate-in.
	# begin_approach re-arms this immediately after its own teleport_to(start).
	_approach_active = false
	skater.global_position = pos
	skater.velocity = Vector3.ZERO
	# Physics interpolation renders between the last two tick poses, so a jump
	# would be drawn as a smear across the rink for one tick. Every skater
	# discontinuity — respawn, slot swap, faceoff staging, drill restage — funnels
	# through here, so this is the one place that has to drop the history.
	skater.reset_physics_interpolation()
	stance_active = false
	hit_active = false
	skater.hit_committed = false
	_stick_check.reset()
	skater.stick_check_phase = _stick_check.phase
	_settle.clear()
	stagger_timer = 0.0
	balance_tilt_vel = Vector2.ZERO
	skater.set_balance_tilt(Vector2.ZERO)
	var was_down: bool = knockdown_timer > 0.0
	knockdown_timer = 0.0
	_set_down_flags(false)
	_knockdown_total = 0.0
	_knockdown_entry_speed = 0.0
	# The render pass only clears the tilt while it runs, and it's
	# visibility-gated — stand the rig up explicitly so a teleport out of a
	# mid-fall body can't leave an off-screen skater lying down.
	skater.set_knockdown_fall(Vector3.RIGHT, 0.0)
	# The sprawl overlay is render-rate and visibility-gated like the tilt —
	# restore the rest legs for the same reason.
	if was_down:
		skater.set_leg_swing(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	# A faceoff / slot-swap teleport mid-action must put the skater back in a
	# plain skating state, or the slapper charge timer keeps ticking across the
	# respawn and a shot block rides all the way to the drop — the state machine
	# is not dispatched at all while movement is locked, so SHOT_BLOCKING's own
	# exit never runs (see SkaterStateMachine._state_shot_blocking).
	_reset_to_skating_state()
	# Faceoff / slot swap teleports pass a non-zero facing so the skater
	# squares up to the puck instead of carrying their last-frame heading
	# (which routinely left players spawned backwards). Tutorial / test
	# call sites that don't want to override facing pass Vector2.ZERO.
	if facing != Vector2.ZERO:
		skater.set_facing(facing)
		_pose.facing = facing
		# Square the body up to the dot and wipe carried-over animation state:
		# clear the upper-body twist/lean/lag so the torso points forward, and
		# plant the legs at their rest pose so the stride doesn't resume mid-swing.
		_pose.reset_lean_and_lag()
		_skating.reset_to_rest()
		# Kill any celebration remainder. The timer only ticks on live ticks,
		# which the faceoff-prep aim-only path is not — so a leftover slice
		# (goal_scored signal latency; larger on clients) would otherwise fire
		# the raised-stick pose AT the next faceoff.
		end_celebration()
	# The body (and with it the blade) just jumped, and the pose resets above
	# moved the stick again. Re-anchor the blade histories to where the stick
	# actually is now, or the next tick differences them across the whole jump:
	# a blade "velocity" of thousands of m/s feeding the faceoff draw's retained
	# crest, and a swept pickup/poke segment spanning the rink. See
	# Skater.reseed_blade_history.
	skater.reseed_blade_history()

# ── Faceoff / intro skate-in approach ─────────────────────────────────────────

# Begins the deterministic skate-in used during FACEOFF_PREP. apply_approach
# glides the body from `start` to `target` (the faceoff dot) over `duration`,
# squaring up to `settle_facing` on arrival. `initial_velocity` is the skater's
# live velocity: pass it for a period / stoppage skate-in (start == current
# position) so the glide flows out of the player's momentum instead of snapping
# to a stop at the whistle; pass zero (default) for a snap-from-rest start (the
# bench intro or post-goal staging, where the body relocates to `start` anyway).
# Deterministic per machine from (start, target, v0, elapsed) with reconcile off.
func begin_approach(start: Vector3, target: Vector3, settle_facing: Vector2,
		duration: float, initial_velocity: Vector3 = Vector3.ZERO) -> void:
	var carry := Vector3(initial_velocity.x, 0.0, initial_velocity.z)
	if carry.length() < _APPROACH_CARRY_MIN:
		# Snap-from-rest: relocate to `start`, reset the gait, and point down the
		# path (teleport_to squares up when given a non-zero facing).
		teleport_to(start, ApproachRules.path_facing(start, target, 0.0, settle_facing))
		carry = Vector3.ZERO
	else:
		# Momentum-preserving: clear the charge and drop reconcile history
		# (teleport_to with a zero facing skips the gait reset + facing snap), then
		# re-seed the live velocity so the stride carries through the whistle.
		teleport_to(start, Vector2.ZERO)
		skater.velocity = carry
	_approach_active = true
	_approach_start = start
	_approach_target = target
	_approach_facing = settle_facing
	_approach_v0 = carry
	_approach_elapsed = 0.0
	_approach_duration = maxf(duration, 0.001)
	_approach_prev_pos = start


func clear_approach() -> void:
	_approach_active = false


# Runs one skate-in tick if an approach is active for the live faceoff prep or
# the period-break skate-off (END_OF_PERIOD — see PhaseCoordinator.
# on_period_break_entered). Returns true while the skater is still gliding
# (caller skips its locked-phase freeze); false when there's no approach or the
# skater has arrived / the phase has ended (caller runs its normal freeze /
# aim-only handling). Real frames only — the skate-in is cosmetic and not part
# of the reconcile input-replay chain.
func tick_faceoff_approach(delta: float) -> bool:
	if not _approach_active:
		return false
	var in_prep: bool = _game_state_has_faceoff_prep and _game_state.is_faceoff_prep()
	var in_break: bool = _game_state_has_period_break and _game_state.is_period_break()
	if not (in_prep or in_break):
		# Left the approach phase (the drop, or an abandoned prep) with an
		# approach still set — drop it so it can't leak into a later locked phase.
		clear_approach()
		return false
	return apply_approach(delta)


# Advances the eased path one tick, moves the body, and renders the gait from a
# path-derived velocity. Returns true while gliding; on arrival (t >= 1) it snaps
# exactly onto the dot, clears the approach, and returns false so the caller
# hands back to the normal prep freeze (letting humans pre-aim the draw).
func apply_approach(delta: float) -> bool:
	_approach_elapsed += delta
	var t: float = clampf(_approach_elapsed / _approach_duration, 0.0, 1.0)
	if t >= 1.0:
		skater.global_position = _approach_target
		skater.velocity = Vector3.ZERO
		skater.set_facing(_approach_facing)
		_pose.facing = _approach_facing
		clear_approach()
		# The path eased in; the snap onto the dot is not a stop to lean into.
		_advance_balance(skater.velocity, delta)
		return false
	var new_pos: Vector3 = ApproachRules.path_position(
			_approach_start, _approach_target, t, _approach_v0, _approach_duration)
	var vel: Vector3 = (new_pos - _approach_prev_pos) / maxf(delta, 0.0001)
	_approach_prev_pos = new_pos
	# Clamp the gait-facing velocity (planar) so a long glide doesn't over-spin
	# the stride; the body still translates the full path distance this tick.
	var planar := Vector3(vel.x, 0.0, vel.z)
	if planar.length() > approach_max_gait_speed:
		planar = planar.normalized() * approach_max_gait_speed
	var tick_start_velocity: Vector3 = skater.velocity
	skater.global_position = new_pos
	skater.velocity = planar
	_advance_balance(tick_start_velocity, delta)
	# Facing follows the actual per-tick travel (the momentum path curves), then
	# settles to the dot facing near the end — so a stoppage skater keeps its
	# heading through the whistle instead of snapping toward the dot.
	var facing: Vector2 = ApproachRules.facing_along(
			Vector2(planar.x, planar.z), t, _approach_facing)
	_render_approach_pose(facing, delta)
	return true


# Cosmetic pose pass for a skate-in tick: drives facing directly (the path owns
# heading, not mouse aim), carries the blade out front, and runs the same gait /
# upper-body / IK passes _process_input's tail runs — so the skater strides,
# leans, and settles into the faceoff ready stance exactly like normal skating.
func _render_approach_pose(facing: Vector2, delta: float) -> void:
	_pose.facing = facing
	skater.set_facing(facing)
	skater.move_intent = facing
	skater.brake_intent = false
	_approach_input.delta = delta
	# Aim the blade / head a few metres ahead along travel — a neutral carry that
	# flows into the draw aim once the skater arrives and the prep freeze resumes.
	_approach_input.mouse_world_pos = skater.global_position \
			+ Vector3(facing.x, 0.0, facing.y) * 6.0
	_pose.apply_velocity_lean(delta)
	_ik.apply_blade_from_mouse(_approach_input, delta)
	# Preserve blade/hand world positions across the upper-body rotation — same
	# dance as _process_input, so the stick doesn't slide sideways as the torso
	# tracks travel.
	var blade_world_pre: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
	var hand_world_pre: Vector3 = skater.upper_body_to_global(skater.get_top_hand_position())
	_pose.apply_upper_body(delta)
	_pose.apply_head_tracking(delta)
	skater.set_top_hand_position(skater.upper_body_to_local(hand_world_pre))
	skater.set_blade_position(skater.upper_body_to_local(blade_world_pre))
	# This intro-skate path poses its own gait + off-hand (a brief locked phase,
	# not the hot path); the render hook yields to it (see _self_posing).
	_self_posing = true
	_skating.apply(delta)
	# Publish the gait's lower-body yaw (hip-to-travel alignment) — normally
	# written inside _pose.apply_facing, which this path replaces. Going through
	# the coordinator also decays the facing turn lag the pre-whistle play left
	# behind, which a bare set_lower_body_lag froze for the length of the walk-in.
	_pose.apply_lower_body_yaw(delta)
	_ik.update_bottom_hand(delta)


# Drops any non-skating shot state — a wrister/slapper wind-up, a one-timer
# hold, a follow-through, a planted shot block — back to plain skating. No-op
# when already skating, so a routine teleport doesn't disturb anything.
# Suppresses the charge-lost flash: a forced respawn isn't player-initiated
# charge loss.
func _reset_to_skating_state() -> void:
	var s: int = _sm.get_state()
	if s == State.SKATING_WITH_PUCK or s == State.SKATING_WITHOUT_PUCK:
		return
	if s == State.SHOT_BLOCKING:
		# The block widens the body-block cylinder and plants the legs; both are
		# latched, so leaving the state is not enough on its own.
		skater.set_block_stance(false)
	_aiming.reset_slapper()
	_transition_to_skating()
	# Republish the mirror the cosmetic layers read: its usual writers sit in
	# _process_input, which the locked phase this cleans up for never runs.
	skater.current_shot_state = _sm.get_state() as int

# ── State Machine ─────────────────────────────────────────────────────────────
# The settle lock (SkaterSettleGate): a plain carry inside the deadline holds the
# blade at its seat and dispatches nothing; the first input past it dispatches
# the queued press as its own.
func _apply_state(input: InputState, delta: float) -> void:
	if _settle.settling:
		if skater.is_slapshot_pinning():
			# A called-off slapshot: the blade comes down onto the held puck.
			var puck_world := Vector3(skater.global_position.x + fake_puck_offset.x, 0.0,
					skater.global_position.z + fake_puck_offset.y)
			var local: Vector3 = skater.to_local(puck_world)
			skater.enter_slapshot_pinning(Vector2(local.x, local.z))
			_ik.apply_blade_toward(puck_world, delta)
		else:
			_ik.apply_blade_from_mouse(input, delta, false, true)
		return
	if skater.is_slapshot_pinning() and _sm.get_state() == State.SKATING_WITH_PUCK:
		# The stick is down: the carry takes the puck back from where it lies.
		skater.exit_slapshot_pinning()
	var press: SkaterSettleGate.Press = _settle.unqueued
	if press == SkaterSettleGate.Press.NONE or press == SkaterSettleGate.Press.NUDGE \
			or not has_puck or _sm.get_state() != State.SKATING_WITH_PUCK:
		_sm.dispatch(skater, input, delta, has_puck, _game_state.is_movement_locked())
		return
	var was: bool = SkaterSettleGate.set_edge(input, press, true)
	_sm.dispatch(skater, input, delta, has_puck, _game_state.is_movement_locked())
	SkaterSettleGate.set_edge(input, press, was)


# Host: this carrier's settle deadline for a catch settling `settle_s`, armed by
# the on_puck_picked_up_network that follows (SkaterSettleGate.deadline_ms).
func settle_deadline_ms(settle_s: float) -> int:
	return _settle.deadline_ms(settle_s, one_timer_window_lag_grace())

# ── State Helpers ─────────────────────────────────────────────────────────────
func _transition_to_skating() -> void:
	var prev_state: int = _sm.get_state()
	skater.shot_charge = 0.0
	skater.slapper_aim_dir = Vector3.ZERO
	if has_puck:
		_sm.set_state(State.SKATING_WITH_PUCK)
	else:
		_sm.set_state(State.SKATING_WITHOUT_PUCK)
	_sm.aim_finish(Vector3.ZERO)
	# Every exit keeps the smoothed torso and hip pose and lets the skating eases
	# carry it to the new targets: zeroing it here snaps the shoulders square and
	# the trunk upright in one tick (a lost puck threw the head ~0.2 m). Out of
	# the follow-through the blade smoother is also seeded from the finish, which
	# choreographed the blade directly.
	if prev_state == State.FOLLOW_THROUGH and not is_replaying:
		_ik.seed_blade_smoothing(skater.upper_body_to_global(skater.get_blade_position()))
	skater.set_slapper_zone(false)
	skater.exit_slapshot_pinning()
	_hide_slapshot_hud()

# Aligns BOTH facing stores at spawn: the Skater node's root rotation and the
# pose coordinator's smoothed facing. The spawn path used to set only the
# skater side, leaving _pose.facing at its Vector2.DOWN default — the first
# input tick then re-asserted the stale pose facing, snapping the root up to
# 180° and dumping the whole turn into lower_body_lag: the player spawned
# visibly twisted. (The faceoff teleport already syncs both; this is the
# spawn-time equivalent.)
func set_spawn_facing(facing: Vector2) -> void:
	if facing == Vector2.ZERO:
		return
	skater.set_facing(facing)
	_pose.facing = facing
	_pose.reset_lean_and_lag()
	skater.set_lower_body_lag(0.0)
	# Plant the legs too, matching the faceoff teleport. A no-op at initial
	# spawn (the gait starts at rest), but mid-session callers — the tutorial
	# puppet repositioning between steps — would otherwise drop into the new
	# spot carrying the previous shift's mid-stride leg swing.
	_skating.reset_to_rest()


# This skater's center-slot distance from the faceoff dot: the blade radius of
# a stick held in the ADDRESS pose (its horizontal footprint) scaled by
# faceoff_center_reach_fraction, so the puck sits comfortably inside every
# build's reach at the drop — no hand displacement or lean needed. Host-computed
# by the phase coordinator and broadcast with the rest of the faceoff positions.
#
# The address, not the standing pose: the crouch drops the hands by a fifth of a
# metre, and a rigid stick reaching the ice from there covers much more ground.
# Measured from standing, the dot lands well inside the reach and the top-hand IK
# answers by standing the stick up on end (TopHandIK's CLOSE regime) — the centre
# addresses the puck with a shaft angled like a shovel instead of laid out flat.
# The live crouch is netted out because this runs at the whistle, on a body still
# carrying whatever depth it was skating at.
func faceoff_center_distance() -> float:
	# Plus the fold's own carry: the address hangs the arms off a shoulder swung
	# that far out over the dot (SkaterIKCoordinator.address_shoulder), and the
	# span below is measured from the hand, so the body has to stand back by it
	# or the stick comes up short of the reach it was sized for. The span ends at
	# the heel, and the cursor names mid-blade (SkaterIKCoordinator
	# ._blade_target_for), so the dot is half a blade further on.
	return _ik.address_carry() \
			+ _ik.address_stick_horiz() * faceoff_center_reach_fraction \
			+ skater.blade_length * 0.5


func _enter_shot_block() -> void:
	# Down (a knockdown, or a dive with the block still held) is no stance to
	# block from; a block held through the get-up starts once he is up.
	if knockdown_timer > 0.0:
		return
	_sm.set_state(State.SHOT_BLOCKING)
	skater.set_block_stance(true)
	# Snap facing toward puck on entry — locked for duration of stance
	var to_puck: Vector3 = puck.global_position - skater.global_position
	to_puck.y = 0.0
	if to_puck.length() > 0.01:
		_pose.facing = Vector2(to_puck.x, to_puck.z).normalized()
		skater.set_facing(_pose.facing)

func _enter_slapper_charge(input: InputState) -> void:
	_aiming.reset_slapper()
	_sm.aim_finish(Vector3.ZERO)
	# Nothing turns or moves on the press: the aim starts where the cursor is
	# (_update_slapper_aim) and the hips turn to its stance at their own rate.
	var strike: Vector2 = slapper_strike_local()
	_sm.locked_slapper_dir = _pose.facing
	_update_slapper_aim(input)
	if has_puck:
		# The set-up: the blade takes the puck to the strike spot before the
		# backswing starts (_apply_slapper_setup), and pins it where it lies then.
		_aiming.slapper_setup_done = false
		_slapper_setup_prev_puck = Vector2(INF, INF)
		_slapper_setup_still_s = 0.0
		_sm.set_state(State.SLAPPER_CHARGE_WITH_PUCK)
	else:
		# Activate the ice-level slapper zone so the puck can be detected at
		# ground level even though the blade is lifted during wind-up.
		skater.set_slapper_zone(true, slapper_zone_radius, strike)
		_sm.set_state(State.SLAPPER_CHARGE_WITHOUT_PUCK)
		if show_one_timer_indicator:
			skater.set_slapper_indicator(true, strike, slapper_zone_radius)
	# The aim arrow waits until the shot is set (_update_slapshot_arrow).
	_slapshot_arrow_shown = false


# A slapshot called off — the wrister button pressed, the button let go before
# the puck was set, or a caught one-timer held past its window. The stick has to
# come back down: the puck stays where it lies (pinned, if the set-up had not
# pinned it yet), and the settle lock holds every on-puck action for as long as
# that takes, from this input's own stamp (SkaterSettleGate.arm_local), while
# the blade comes down to it (_apply_state). Without the puck there is nothing to
# lock: the raised blade cannot take a pass until it is back on the ice anyway.
func _cancel_slapper(input: InputState) -> void:
	var recover_s: float = SlapperRules.recover_time(
			slapper_wind_up_t(), slapper_recover_min_s, slapper_recover_max_s)
	var pin: Vector2 = skater.slapshot_pin_local()
	if not skater.is_slapshot_pinning():
		var puck_local: Vector3 = skater.to_local(skater.get_carry_target_global())
		pin = Vector2(puck_local.x, puck_local.z)
	_aiming.reset_slapper()
	_transition_to_skating()
	if has_puck:
		skater.enter_slapshot_pinning(pin)
		var pin_world: Vector3 = skater.global_transform.basis * Vector3(pin.x, 0.0, pin.y)
		fake_puck_offset = Vector2(pin_world.x, pin_world.z)
		_settle.arm_local(input.host_timestamp + recover_s)
	if not is_replaying:
		_pose_bridge.ease_next_change(recover_s)


# Where a called-off slapshot's puck lies off the skater (world XZ): it travels
# with him, but the hips turning back out of the stance do not swing it round.
# Saved/restored across reconcile with the pin it re-seats each tick.
var fake_puck_offset: Vector2 = Vector2.ZERO


func _blade_side_sign() -> float:
	return -1.0 if skater.is_left_handed else 1.0


# Where this build strikes a slapshot, in the skater's own frame (SlapperRules):
# the top hand at rest height under its shoulder, a full stick to the ice. Read
# off the standing frame rather than the live one, so the spot is the build's,
# not the moment's — every machine and the bots derive the same point.
func slapper_strike_local() -> Vector2:
	var frame_y: float = GameRules.FACEOFF_SPAWN_HEIGHT + skater.upper_body.position.y
	var drop: float = frame_y + hand_rest_y - blade_height
	var horiz: float = sqrt(maxf(stick_length * stick_length - drop * drop, 0.0001))
	return SlapperRules.strike_spot_local(
			Vector2(skater.shoulder.position.x, skater.shoulder.position.z),
			horiz, skater.blade_length, slapper_strike_front_m, _blade_side_sign())


# The hips' facing for the shot line: the line the feet set up on once they
# have, the live aim until then.
func slapper_stance_facing() -> Vector2:
	var line: Vector2 = _aiming.slapper_stance_line
	if line == Vector2.ZERO:
		line = _sm.locked_slapper_dir
	return SlapperRules.stance_facing(line, _blade_side_sign(),
			deg_to_rad(slapper_stance_open_deg))


# The slapshot's aim, live until the swing commits (the release, or the
# one-timer's hold), which fires whatever it was on that tick. Humans aim from
# where the puck is struck toward the cursor: the pinned puck once there is one,
# else the strike spot the hips are setting for. Bots commit the direction
# (InputState.bot_slapper_aim_dir). While the hips are still setting — the
# set-up, the puckless wind-up's first pivot — the aim is free and they chase
# it; once the feet have set, the shoulders turn it at most slapper_aim_arc_deg
# off their line, and a bigger change of mind means letting go. Re-derived from
# each input, so a replay re-aims exactly.
func _update_slapper_aim(input: InputState) -> void:
	var aim := Vector2(input.bot_slapper_aim_dir.x, input.bot_slapper_aim_dir.z)
	if aim.length_squared() <= 0.0001:
		if skater.is_slapshot_pinning():
			var pinned: Vector3 = skater.get_carry_target_global()
			aim = Vector2(input.mouse_world_pos.x - pinned.x, input.mouse_world_pos.z - pinned.z)
		else:
			aim = SlapperRules.aim_from_strike(
					Vector2(skater.global_position.x, skater.global_position.z),
					Vector2(input.mouse_world_pos.x, input.mouse_world_pos.z),
					slapper_strike_local(), _blade_side_sign(),
					deg_to_rad(slapper_stance_open_deg))
	if aim.length_squared() <= 0.0001:
		return
	aim = aim.normalized()
	# A one-timer's feet set the first time the hips arrive in the stance; a
	# carried slapshot's set with the puck (_apply_slapper_setup).
	if _aiming.slapper_stance_line == Vector2.ZERO \
			and _sm.get_state() == State.SLAPPER_CHARGE_WITHOUT_PUCK and _hips_set_for_slapper():
		_aiming.slapper_stance_line = _sm.locked_slapper_dir
	if _aiming.slapper_stance_line != Vector2.ZERO:
		aim = SlapperRules.clamp_aim(aim, _aiming.slapper_stance_line,
				deg_to_rad(slapper_aim_arc_deg))
	_sm.locked_slapper_dir = aim
	skater.slapper_aim_dir = Vector3(aim.x, 0.0, aim.y)


# A carried slapshot's set-up tick: the tracked blade reaches for the strike
# spot as it would for a cursor there, so the puck rides it across at the
# dangle's own speed while the hips turn to the stance. Once the hips are there
# and the puck is too — or has come as near as the blade's reach and the
# carry's own offset let it — the puck is pinned where it lies and the
# backswing begins.
func _apply_slapper_setup(_input: InputState, delta: float) -> void:
	var strike: Vector2 = slapper_strike_local()
	var spot_world: Vector3 = skater.to_global(Vector3(strike.x, 0.0, strike.y))
	_ik.apply_blade_toward(spot_world, delta)
	var puck_local: Vector3 = skater.to_local(skater.get_carry_target_global())
	var puck_xz := Vector2(puck_local.x, puck_local.z)
	if puck_xz.distance_to(_slapper_setup_prev_puck) <= SLAPPER_SETUP_SETTLED_M_S * delta:
		_slapper_setup_still_s += delta
	else:
		_slapper_setup_still_s = 0.0
	_slapper_setup_prev_puck = puck_xz
	if _hips_set_for_slapper() and (_slapper_setup_still_s >= SLAPPER_SETUP_SETTLED_S
			or puck_xz.distance_to(strike) <= slapper_setup_spot_tol_m):
		skater.enter_slapshot_pinning(puck_xz)
		_aiming.slapper_setup_done = true
		_aiming.slapper_stance_line = _sm.locked_slapper_dir


# The hips have pivoted into the slapshot's stance.
func _hips_set_for_slapper() -> bool:
	return absf(_pose.facing.angle_to(slapper_stance_facing())) \
			<= deg_to_rad(slapper_setup_facing_tol_deg)


# A puck held slower than this in the hips' frame (m/s) for this long (s) has
# come as near the strike spot as the blade will bring it.
const SLAPPER_SETUP_SETTLED_M_S: float = 0.25
const SLAPPER_SETUP_SETTLED_S: float = 0.05
var _slapper_setup_prev_puck := Vector2(INF, INF)
var _slapper_setup_still_s: float = 0.0


func _wrister_aim_dir(input: InputState) -> Vector3:
	return ShotMechanics.wrister_aim_dir(
			input.bot_wrister_aim_dir, input.mouse_world_pos, _aiming.wrister_origin_world)

# Blade update for the WRISTER_AIM state: HOLD the blade at the shot origin — the
# puck sits still where the shot fires from while the torso coils toward the
# cursor. Routed through the state machine's apply_wrister_aim_blade callback.
func _apply_wrister_aim_blade(input: InputState, delta: float) -> void:
	# Feed the live aim line so the frozen blade visibly addresses the side of
	# the puck the shot will push from (Skater.set_wrister_address). Re-read
	# per tick: an aim swung across the stick line re-addresses on the spot.
	skater.set_wrister_address(_wrister_aim_dir(input))
	_ik.apply_blade_from_mouse(input, delta, true)

# Solves wrister_load for this tick's aim, for humans and bots alike. Call before
# _wrister_load_cap and before reading wrister_load.is_backhand (the hand).
func _solve_wrister_load(input: InputState) -> void:
	# The frozen puck rides along with the skater from its pin. Not the blade's
	# contact point, which swings with the torso's wind-up.
	var pin: Vector3 = _aiming.wrister_origin_world - _aiming.wrister_origin_skater_pos
	var to_local: Basis = skater.global_transform.basis.inverse()
	WristerLoad.solve(wrister_load, to_local * Vector3(pin.x, 0.0, pin.z),
			to_local * _wrister_aim_dir(input), skater.is_left_handed, _wrister_load_config())

# Share of the full shot the body can drive along this tick's aim (the torso's
# turn and the arms' push, before the backhand's coefficient): how far the aim
# pose squares the shoulders onto the aim.
func wrister_drive_share() -> float:
	return WristerLoad.power_share(wrister_load.load_share, wrister_load.arm_share, false,
			wrister_unloaded_share, 1.0)

# The most a release can carry once the load is applied.
func _wrister_load_cap(is_backhand: bool) -> float:
	return max_wrister_power * WristerLoad.power_share(wrister_load.load_share,
			wrister_load.arm_share, is_backhand, wrister_unloaded_share, backhand_power_coefficient)

func _release_wrister(input: InputState) -> void:
	_solve_wrister_load(input)
	if has_puck:
		var blade_world: Vector3 = _ik.last_target_blade_world
		var aim_dir: Vector3 = _wrister_aim_dir(input)
		var is_backhand: bool = wrister_load.is_backhand
		# LMB is always a charged wrister now — the quick pass lives on its own
		# button (_fire_quick_pass). A bare tap here fires a min-charge wrister.
		last_release_hand = "BH" if is_backhand else "FH"
		last_release_was_shot = true
		var result := ShotMechanics.release_wrister(
				skater.global_position,
				input.mouse_world_pos,
				blade_world,
				is_backhand,
				_elevation_level,
				_wrister_config(),
				aim_dir,
				false,
				_wrister_sweep_speed(input),
				null,
				skater.velocity)
		result.power = minf(result.power, _wrister_load_cap(is_backhand))
		var push: float = result.power
		_carry_momentum(result)
		# The finish turns the hips and swings the stick round onto the shot only
		# as far as the torso drove it; the arms alone push it from where it sat.
		var drive: float = wrister_load.load_share
		_sm.aim_finish(result.direction,
				ShotMechanics.finish_line(Vector3(_pose.facing.x, 0.0, _pose.facing.y),
						result.direction, drive),
				ShotMechanics.finish_line(
						_aiming.wrister_origin_world - _aiming.wrister_origin_skater_pos,
						result.direction, drive))
		_do_release(result.direction, result.power)
		skater.shot_charge = _wrister_charge_of(push)

	_sm.follow_through_is_slapper = false
	# Finish size follows the released POWER (pre-backhand — the body swing is the
	# same, the blade contact is what's weaker): a soft touch pass flicks, a
	# ripped full sweep finishes high. Computed from the aiming state (not
	# `result`) so a whiff still animates. Capped like the real release, so a
	# shot the torso couldn't load finishes small — the finish IS the power readout.
	var release_power_t: float = ShotMechanics.wrister_power_t(
			_wrister_sweep_speed(input), _wrister_config())
	release_power_t = minf(release_power_t, wrister_load.load_share)
	_sm.follow_through_power = lerpf(wrister_follow_through_min_power, 1.0, release_power_t)
	var finish_s: float = wrister_follow_through_time(skater.shot_charge)
	_sm.set_state(State.FOLLOW_THROUGH)
	_sm.follow_through_timer = finish_s
	_sm.follow_through_duration_total = finish_s

# Folds the skater's motion into a wrist shot's or quick pass's release
# (ReleaseMomentum): the puck keeps the body's velocity, the hands correcting it
# onto the aim out of the push; a pass keeps its vertical launch speed. A puck
# the blade leaves at rest keeps its direction at no pace.
func _carry_momentum(result: ShotMechanics.ShotResult, is_pass: bool = false) -> void:
	var v: Vector3 = ReleaseMomentum.release_velocity(result.direction, result.power,
			skater.velocity, is_pass)
	result.power = v.length()
	if result.power > 0.0001:
		result.direction = v / result.power

# Instant quick pass — the fixed-power blade→cursor snap, fired straight from
# carry by the dedicated quick_pass button (no wrister aim/charge). Backhand is
# irrelevant here: the quick pass takes no backhand penalty (its power is flat).
# apply_blade_from_mouse ran earlier this tick, so last_target_blade_world is
# current.
func _fire_quick_pass(input: InputState) -> void:
	if has_puck:
		var blade_world: Vector3 = _ik.last_target_blade_world
		last_release_hand = ""
		last_release_was_shot = false  # the dedicated pass button
		var result := ShotMechanics.release_wrister(
				skater.global_position,
				input.mouse_world_pos,
				blade_world,
				false,
				_elevation_level,
				_wrister_config(),
				Vector3.ZERO,
				true)
		_carry_momentum(result, true)
		_sm.aim_finish(result.direction)
		_do_release(result.direction, result.power)

	_sm.follow_through_is_slapper = false
	_sm.follow_through_power = quick_pass_follow_through_power
	_sm.set_state(State.FOLLOW_THROUGH)
	_sm.follow_through_timer = quick_pass_follow_through_duration
	_sm.follow_through_duration_total = quick_pass_follow_through_duration

# The slapshot's shot half — everything up to and including the release emit,
# with no state transition. Split out of _release_slapper so the retained
# one-timer can fire the identical shot at the end of its hold while owning its
# own follow-through hand-off. Returns whether a puck actually left.
func _fire_slapper_shot(input: InputState) -> bool:
	if not has_puck:
		return false
	# Direction is locked at the moment slap was pressed — no mid-swing steering.
	last_release_hand = ""
	last_release_was_shot = true  # slappers are shots; bots only slapper on one-timers
	var locked_dir_3d := Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
	var cfg: ShotMechanics.SlapperConfig = _slapper_config()
	# One-timers (puck arrived mid-charge) ride the same timer as a normal
	# release — power is whatever wind-up was actually built.
	var charge: float = _aiming.slapper_charge_timer
	var result := ShotMechanics.release_slapper(
			skater.upper_body_to_global(skater.get_blade_position()),
			input.mouse_world_pos,
			_elevation_level,
			charge,
			cfg,
			locked_dir_3d)
	# One-timer (puck arrived mid-charge → window armed): the swing strikes the
	# feed as it was caught, as much of it as the hold has not taken
	# (_caught_feed), then the SAME graded centre-timing bonus the leniency path
	# uses, so both are one mechanic on both release paths. A normal carried
	# slapshot has no window armed and is untouched.
	if _aiming.one_timer_window_timer > 0.0:
		_strike_moving_puck(result, _caught_feed())
		var zone_world: Vector3 = skater.get_slapper_zone_global_position()
		var zone_xz := Vector2(zone_world.x, zone_world.z)
		var puck_xz := Vector2(puck.global_position.x, puck.global_position.z)
		result.power = ShotReleaseRules.one_timer_power(
				result.power, one_timer_center_power_bonus,
				zone_xz, puck_xz, slapper_zone_radius)
	_sm.aim_finish(result.direction)
	_do_release(result.direction, result.power)
	return true


# The caught feed the swing still meets: the catch's, faded by how long it has
# sat on the blade. The window timer reads the same on host and client at the
# same input (the host's lag grace is the head start its catch had), so both
# fade it alike.
func _caught_feed() -> Vector2:
	var held_s: float = one_timer_window_duration - _aiming.one_timer_window_timer
	return _one_timer_feed * SlapperRules.feed_transfer(
			held_s, one_timer_leniency_time, one_timer_window_duration)


# The one-timer's contact (SlapperRules.one_timer_contact) laid onto `result`, a
# slapshot as the swing would strike a still puck. `feed`: the puck's velocity in
# the shooter's frame, world XZ.
func _strike_moving_puck(result: ShotMechanics.ShotResult, feed: Vector2) -> void:
	var e: float = SlapperRules.swing_restitution(result.power, puck.deflect_normal_restitution,
			puck.deflect_normal_restitution_min, puck.deflect_speed_ref)
	var struck: Vector3 = SlapperRules.one_timer_contact(result.direction * result.power,
			feed, e, one_timer_feed_grip, puck.max_speed)
	result.power = struck.length()
	if result.power > 0.0001:
		result.direction = struck / result.power


func _release_slapper(input: InputState) -> void:
	_fire_slapper_shot(input)
	_sm.follow_through_is_slapper = true
	# A slap swing is always full-bodied: power sets how long the finish takes to
	# come back down, never how big it is.
	_sm.follow_through_power = 1.0
	var finish_s: float = _slapper_finish_time()
	_sm.set_state(State.FOLLOW_THROUGH)
	_sm.follow_through_timer = finish_s
	_sm.follow_through_duration_total = finish_s
	# Hide the slapshot HUD the moment the shot fires: left up through the
	# follow-through, the ring/arrow appear to rotate with the skater.
	# _transition_to_skating still hides everything at the end as a safety net.
	_hide_slapshot_hud()

# Seconds a finish runs for a release whose shot_charge is `charge`. Read off
# the replicated shot_charge, so every machine's legs (GaitShotLayer) end with
# the stick the shooter swings. A wrister's charge is its released speed over
# the band, a slapper's the wind-up fraction.
func wrister_follow_through_time(charge: float) -> float:
	return ShotMechanics.follow_through_time(charge,
			wrister_follow_through_time_min, wrister_follow_through_time_max)


func slapper_follow_through_time(charge: float) -> float:
	var cfg: ShotMechanics.SlapperConfig = _slapper_config()
	return ShotMechanics.follow_through_time(
			ShotMechanics.slapper_power_t(charge * cfg.max_slapper_charge_time, cfg),
			slapper_follow_through_time_min, slapper_follow_through_time_max)


# The slapper's finish, whether the swing connects or not: publishes the wind-up
# it left with as shot_charge, then sizes the finish from that.
func _slapper_finish_time() -> float:
	skater.shot_charge = minf(_aiming.slapper_charge_timer / max_slapper_charge_time, 1.0)
	return slapper_follow_through_time(skater.shot_charge)


func _hide_slapshot_hud() -> void:
	_slapshot_arrow_shown = false
	if not show_one_timer_indicator:
		return
	skater.set_slapper_indicator(false)
	skater.set_slapshot_arrow(false)

func _update_wrister_charge(input: InputState) -> void:
	if not has_puck:
		return
	# Cursor SCREEN position, packed (x, 0, y). Screen space is the
	# camera-immune frame — pixel motion captures the player's mouse drag intent
	# independent of camera lag, body rotation, or skater locomotion.
	var intent_pos := Vector3(input.mouse_screen_pos.x, 0.0, input.mouse_screen_pos.y)
	_aiming.tick_wrister_charge(intent_pos, input.delta, wrister_mouse_speed_smoothing)
	# The ROM-clamped blade TARGET (closed-form project_blade, computed in
	# apply_blade_from_mouse this tick) — deterministic, so host and client agree.
	var blade_world: Vector3 = _ik.last_target_blade_world
	# Publish where this charge would go if released NOW, so the host-side goalie AI
	# can pre-lean toward a charging shot's predicted impact. Mirrors the release
	# math in _release_wrister exactly — same inputs, same direction and backhand —
	# and re-solves every tick, so a player who drags one way and flicks the other at
	# release moves the real impact off the goalie's lean. Works for REMOTE shooters
	# too: the host simulates their carry from replicated input, and both signals
	# ride the wire — mouse_world_pos, plus mouse_screen_pos pre-aligned to world XZ
	# by the gatherer's attack-direction negation — with the remote's Shot Power
	# Sensitivity from the join payload feeding _wrister_sweep_speed. Host-only in
	# that it runs on the authoritative sim, not that it is limited to host shooters.
	var charge_aim_dir: Vector3 = _wrister_aim_dir(input)
	_solve_wrister_load(input)
	var is_backhand: bool = wrister_load.is_backhand
	# Re-solves every tick while charging (+ per replayed input on reconcile), so
	# fill a reused scratch instead of allocating a ShotResult each time.
	var pred := ShotMechanics.release_wrister(
			skater.global_position, input.mouse_world_pos, blade_world,
			is_backhand, _elevation_level,
			_wrister_config(), charge_aim_dir, false,
			_wrister_sweep_speed(input), _wrister_pred_scratch, skater.velocity)
	pred.power = minf(pred.power, _wrister_load_cap(is_backhand))
	wrister_coil = minf(wrister_load.load_share, ShotMechanics.wrister_power_t(
			_wrister_sweep_speed(input), _wrister_config()))
	skater.predicted_shot_velocity = ReleaseMomentum.release_velocity(
			pred.direction, pred.power, skater.velocity)
	# shot_charge carries the release-now PUSH (normalized predicted power over
	# the min→max band, before the skater's own motion joins it) — the pure
	# mouse-speed model, so it always matches the blade's push this tick. This is
	# the honest readout the goalie leans on and what the stick-flex pose keys off
	# (the flex is the only visual charge feedback — there is no charge ring).
	skater.shot_charge = _wrister_charge_of(pred.power)


# A wrister's speed as shot_charge publishes it: over the min→max band.
func _wrister_charge_of(power: float) -> float:
	var power_span: float = maxf(max_wrister_power - min_wrister_power, 0.001)
	return clampf((power - min_wrister_power) / power_span, 0.0, 1.0)


func _update_slapper_charge(delta: float) -> void:
	_aiming.tick_slapper(delta)
	skater.shot_charge = minf(_aiming.slapper_charge_timer / max_slapper_charge_time, 1.0)
	# Publish where this slapshot would go if released NOW, so the host-side goalie AI
	# can pre-lean toward the aimed corner — the directional anticipation the wrister
	# gets in _update_wrister_charge. Without it the goalie squares to the pinned puck
	# but rests its glove centred and has to travel the full way to a corner on
	# reaction ("skate up and rip a slapper from the slot"). Runs on the host for
	# remotes too (RemoteController._drive_from_input simulates their carry); the
	# slapper direction (_sm.locked_slapper_dir) is re-aimed each tick from the
	# replicated mouse_world_pos, so no screen-space signal is needed, and the
	# prediction follows the aim as it moves. Gated to the WITH-PUCK windup: a one-timer wind-up has no puck
	# to lean toward, and the goalie reads only SLAPPER_CHARGE_WITH_PUCK.
	if has_puck:
		var locked_dir_3d := Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
		if locked_dir_3d.length_squared() > 0.0001:
			var pred := ShotMechanics.release_slapper(
					skater.global_position, skater.global_position,
					_elevation_level, _aiming.slapper_charge_timer,
					_slapper_config(), locked_dir_3d, _slapper_pred_scratch)
			if _aiming.one_timer_window_timer > 0.0:
				_strike_moving_puck(pred, _caught_feed())
			skater.predicted_shot_velocity = pred.direction * pred.power
	_update_slapshot_arrow()


# The aim arrow, once the shot is set to be taken: with the puck, from where
# the set-up pinned it; without, from the strike spot once the hips have
# pivoted into the stance. Shown earlier it swung round with the hips and the
# puck while they were still on their way. Once up it stays until the swing.
func _update_slapshot_arrow() -> void:
	if not show_one_timer_indicator:
		return
	if not _slapshot_arrow_shown:
		if has_puck and not skater.is_slapshot_pinning():
			return
		if not has_puck and not _hips_set_for_slapper():
			return
		_slapshot_arrow_shown = true
		skater.set_slapshot_arrow(true,
				skater.slapshot_pin_local() if has_puck else slapper_strike_local(),
				slapper_zone_radius)
	skater.update_slapshot_arrow_direction(skater.slapper_aim_dir)

# Normalized wind-up progress (0..1) over the FULL charge time. With the charge
# ring gone the wind-up pose is the charge gauge, so every pose consumer (blade
# lift, torso coil, downswing start) must reach its apex exactly at max charge —
# one definition keeps them agreeing. Deterministic through reconcile replay:
# the charge timer is saved/restored with the aiming state.
func slapper_wind_up_t() -> float:
	return clampf(_aiming.slapper_charge_timer / maxf(max_slapper_charge_time, 0.001), 0.0, 1.0)

# Seconds the charge timer has sat past full — drives the full-charge quiver
# phase deterministically (no wall clock in pose math; replay-safe).
func slapper_overcharge_seconds() -> float:
	return maxf(_aiming.slapper_charge_timer - max_slapper_charge_time, 0.0)

# The loose puck as the SHOOTER saw it at the instant their swing landed. Filled
# by sample_shooter_puck_view; one instance per controller, reused.
class PuckView extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO

var _one_timer_puck_view := PuckView.new()
var _live_puck_view := PuckView.new()


# Live puck: for a local player and for a bot, the sim and the puck view share
# one clock, so "what the shooter saw" is simply the puck. RemoteController
# overrides this — on the host a remote shooter's sim runs one input lead behind
# the puck they aimed at, and judging the swing against the host's live puck
# would slide their timing window by that lead.
func sample_shooter_puck_view(_input: InputState, out: PuckView) -> void:
	_sample_live_puck_view(out)


# The puck as this machine sees it now; a client's is LocalController's override.
func _sample_live_puck_view(out: PuckView) -> void:
	out.position = puck.global_position
	out.velocity = puck.linear_velocity


# Arms the committed catch-and-load hold. Called on the slap-release edge of
# either one-timer wind-up (puck already caught mid-charge, or still inbound);
# the state machine flips to ONE_TIMER_RETENTION and the shot fires when this
# timer runs out. The one-timer window timer is deliberately left running-but-
# unticked through the hold so the graded centre bonus still applies at the
# release — the catch that earned it already happened.
func _enter_one_timer_retention() -> void:
	_aiming.one_timer_retention_timer = one_timer_retention_time


# End of the hold: fire whichever one-timer path the puck's actual whereabouts
# select. Caught (pinned on the blade through the beat) fires the ordinary
# carried slapshot; still loose fires the leniency redirect. Both were already
# the two one-timer releases — retention only moved WHEN they run.
func _release_retained_one_timer(input: InputState) -> Dictionary:
	if not has_puck:
		return _try_one_timer_release(input)
	var fired: bool = _fire_slapper_shot(input)
	_sm.follow_through_power = 1.0
	_hide_slapshot_hud()
	return {
		fired = fired,
		direction = _sm.shot_dir,
		follow_through_duration = _slapper_finish_time(),
	}


func _try_one_timer_release(input: InputState) -> Dictionary:
	# The zone is measured at ground level in XZ — matching the ring indicator the
	# player sees, and not penalising the blade's wind-up height. The puck's own
	# HEIGHT is a separate question and one_timer_connects owns it.
	sample_shooter_puck_view(input, _one_timer_puck_view)
	var view: PuckView = _one_timer_puck_view
	var zone_world: Vector3 = skater.get_slapper_zone_global_position()
	var zone_xz := Vector2(zone_world.x, zone_world.z)
	var puck_xz := Vector2(view.position.x, view.position.z)
	# A tied stick swings through nothing: the tie holds the blade off the line.
	if skater.stick_tied or skater.pin_role != BoardPinRules.Role.NONE \
			or not ShotReleaseRules.one_timer_connects(
			zone_xz, slapper_zone_radius, puck_xz,
			Vector2(view.velocity.x, view.velocity.z),
			view.position.y > puck.ice_height + GameRules.PUCK_AIRBORNE_HEIGHT_M,
			one_timer_contact_back_time(), one_timer_leniency_time):
		# Whiff: no shot fires, but the state machine still commits the swing
		# to a full follow-through — hand it the same duration/power and drop
		# the HUD now, exactly like a connected release.
		_sm.follow_through_power = 1.0
		_hide_slapshot_hud()
		return {fired = false, follow_through_duration = _slapper_finish_time()}
	# The swing meets the puck at the strike spot, as it meets a caught one
	# (on_puck_picked_up_network): pinned there, the shot leaves from it on every
	# machine (Puck.release_origin) rather than from under the raised blade.
	skater.enter_slapshot_pinning(slapper_strike_local())
	var blade_world: Vector3 = skater.upper_body_to_global(skater.get_blade_position())
	var locked_dir_3d := Vector3(_sm.locked_slapper_dir.x, 0.0, _sm.locked_slapper_dir.y)
	var cfg: ShotMechanics.SlapperConfig = _slapper_config()
	var result := ShotMechanics.release_slapper(
			blade_world, input.mouse_world_pos,
			_elevation_level, _aiming.slapper_charge_timer, cfg, locked_dir_3d)
	_strike_moving_puck(result, Vector2(view.velocity.x - skater.velocity.x,
			view.velocity.z - skater.velocity.z))
	result.power = ShotReleaseRules.one_timer_power(
			result.power, one_timer_center_power_bonus, zone_xz, puck_xz, slapper_zone_radius)
	if not is_replaying:
		last_release_was_shot = true  # a one-timer is a shot
		one_timer_release_requested.emit(result.direction, result.power)
	# Same as _release_slapper — hide the HUD as soon as the shot fires so it
	# doesn't ride along through the follow-through. The state machine copies the
	# returned duration into follow_through_duration_total; power is set here.
	_sm.follow_through_power = 1.0
	_hide_slapshot_hud()
	return {fired = true, direction = result.direction, follow_through_duration = _slapper_finish_time()}

func _apply_block_movement(_input: InputState, delta: float) -> void:
	# Committed stance: no directional thrust. Whatever momentum you carried in
	# bleeds off under the hard brake friction, so dropping into a block reads as
	# a deliberate plant rather than crouched skating. is_braking drives the
	# hockey-stop skid VFX (gated on speed, so it only shows while sliding to a
	# stop, not once planted).
	skater.is_braking = true
	var block_cfg: SkaterMovementRules.MovementConfig = _block_movement_config()
	if _native_block_move != null:
		skater.velocity = _native_block_move.apply_movement(
				skater.velocity, Vector2.ZERO, skater.rotation.y,
				false, true, delta, SkaterMovementRules.Posture.UPRIGHT)
	else:
		skater.velocity = SkaterMovementRules.apply_movement(
				skater.velocity, Vector2.ZERO, skater.rotation.y,
				false, true, delta, block_cfg)

# How far BEHIND the strike instant the contact test still looks along the puck's
# path. The test runs at the END of the retention hold rather than on the button
# edge, so a puck struck dead-centre at the commit has already carried
# `one_timer_retention_time` past the zone by the time it is judged; without
# folding the hold in, the cleanest possible one-timer would read as a whiff.
# The forward half of the window is `one_timer_leniency_time` alone, which makes
# the tolerance ±one_timer_leniency_time around the ideal commit.
func one_timer_contact_back_time() -> float:
	return one_timer_leniency_time + one_timer_retention_time


# Would a swing landing right now connect? The HUD's ready tell (and nothing
# else) asks this — the release path asks one_timer_connects directly with its
# own view of the puck.
func one_timer_would_connect() -> bool:
	var view: PuckView = _live_puck_view
	_sample_live_puck_view(view)
	var zone_world: Vector3 = skater.get_slapper_zone_global_position()
	return ShotReleaseRules.one_timer_connects(
			Vector2(zone_world.x, zone_world.z), slapper_zone_radius,
			Vector2(view.position.x, view.position.z),
			Vector2(view.velocity.x, view.velocity.z),
			view.position.y > puck.ice_height + GameRules.PUCK_AIRBORNE_HEIGHT_M,
			one_timer_contact_back_time(), one_timer_leniency_time)


# A board pin is the host's to start and end (BoardPinTracker) and lands every
# broadcast like a tie; the replay reads the adopted role, so the cap below is
# reproduced exactly.
func _adopt_pin(state: SkaterNetworkState) -> void:
	skater.pin_role = state.pin_role
	skater.pin_strength = state.pin_strength


# Locked in a pin, the body slides along the wall no faster than its role's cap.
# After the movement kernel, which has C++ ports held by parity tests that the
# pin is not part of; a function of replicated state only.
func _apply_pin_slide_cap() -> void:
	if skater.pin_role == BoardPinRules.Role.NONE:
		return
	skater.velocity = BoardPinRules.apply_slide_cap(skater.velocity,
			BoardPinRules.locked_wall_normal(skater.global_position, skater.collision_radius(),
					skater.pin_role),
			BoardPinRules.slide_cap(skater.pin_role, skater.pin_strength))


func _apply_movement(input: InputState, delta: float) -> void:
	# Brake held — drives hockey stop VFX (gated on speed in skater_vfx.gd).
	skater.is_braking = input.brake
	skater.is_braced = input.brake

	# Knockdown: the top of the stagger continuum. Decays every tick like stagger.
	# While down, input is ignored entirely — the body keeps its momentum from the
	# hit and bleeds it via heavy friction (slides, then stops), and stagger still
	# decays, so the player recovers on every clock while grounded. All
	# deterministic → reconcile replay reproduces the down window; the flag gates
	# puck pickup (Skater.is_knocked_down).
	# The dive goes down on the knockdown's rail ahead of the decay, so its first
	# tick already slides; the get-up clears it.
	if DiveRules.starts(input.stance_held, input.block_held,
			_sm.get_state() == State.SKATING_WITHOUT_PUCK and not has_puck,
			knockdown_timer > 0.0):
		_start_dive(input)
	# A diver holding block stays lying there: the timer holds where the get-up
	# would begin, and letting go starts it.
	var down_floor: float = 0.0
	if skater.is_diving and input.block_held and knockdown_timer >= knockdown_getup_seconds:
		down_floor = knockdown_getup_seconds
	var was_down: bool = knockdown_timer > 0.0
	knockdown_timer = maxf(knockdown_timer - delta, down_floor)
	_set_down_flags(skater.is_diving and knockdown_timer > 0.0)
	if was_down and not skater.is_knocked_down:
		stagger_timer = maxf(stagger_timer, knockdown_getup_stagger_seconds)
		stagger_recoil_dir = Vector2(0.0, -1.0)
	if skater.is_knocked_down:
		stance_active = false
		hit_active = false
		skater.hit_committed = false
		stagger_timer = maxf(stagger_timer - delta, 0.0)
		skater.velocity = skater.velocity.move_toward(Vector3.ZERO, knockdown_friction * delta)
		return

	var move_state: SkaterStateMachine.State = _sm.get_state()
	var locomotion_suppressed: bool = plants_feet(move_state)
	var loaded: bool = move_state == State.SLAPPER_CHARGE_WITH_PUCK \
			or move_state == State.SLAPPER_CHARGE_WITHOUT_PUCK \
			or move_state == State.ONE_TIMER_RETENTION
	# The commit wins over the stance: being caught upright is its whole cost.
	# Mirrored to the skater so the collision resolver reads full-vs-passive
	# transfer. Deterministic from the input, so reconcile replay reproduces both.
	# Neither side of a pin commits (it is held on the stick button, and nothing
	# stacks on it); the pinned one, pressed into the glass, has no stance either.
	# A rocked skater has neither: the hit took his legs out of both.
	var locked: bool = skater.pin_role != BoardPinRules.Role.NONE
	var rocked: bool = BodyCheckRules.is_rocked(stagger_timer, _body_check_config())
	hit_active = not locomotion_suppressed and not loaded and input.hit_held and not locked \
			and not rocked
	skater.hit_committed = hit_active
	stance_active = not locomotion_suppressed and not loaded and input.stance_held \
			and not hit_active and skater.pin_role != BoardPinRules.Role.PINNED and not rocked
	# Body-check stagger decays deterministically every tick (including during a
	# planted charge/block and through reconcile replay), so the penalties ease
	# back on their own. Decayed before the suppression early-out so a player
	# checked mid-windup keeps recovering.
	stagger_timer = maxf(stagger_timer - delta, 0.0)

	if locomotion_suppressed:
		return

	var stick: Vector2 = input.move_vector
	var brake: bool = input.brake
	if loaded:
		_loaded_glide_intent(move_state)
		stick = skater.move_intent
		brake = skater.brake_intent
	var posture: SkaterMovementRules.Posture = SkaterMovementRules.posture_of(
			stance_active, hit_active)
	var cfg: SkaterMovementRules.MovementConfig = _movement_config()
	var bc: BodyCheckRules.Config = _body_check_config()
	var grip_scale: float = BodyCheckRules.grip_mult(stagger_timer, bc)
	# The stagger thrust penalty on top of the attribute-scaled base thrust.
	# cfg.thrust is set from `thrust` every tick (cheap, no allocation), so the
	# penalty is transient and never compounds into the cached config.
	cfg.thrust = thrust * BodyCheckRules.thrust_mult(stagger_timer, bc)
	if _native_move != null:
		skater.velocity = _native_move.apply_movement_staggered(
				skater.velocity, stick, skater.rotation.y,
				has_puck, brake, delta, posture, cfg.thrust, grip_scale)
	else:
		skater.velocity = SkaterMovementRules.apply_movement(
				skater.velocity, stick, skater.rotation.y,
				has_puck, brake, delta, cfg, posture, grip_scale)
	_apply_pin_slide_cap()

# The block stance plants the feet; it skates itself (_apply_block_movement).
static func plants_feet(state: int) -> bool:
	return state == State.SHOT_BLOCKING


# ── The press ────────────────────────────────────────────────────────────────
# Pressed against another body, this one's movement along the contact normal is
# the pair's (PressRules): laid over what _apply_movement did along it, from the
# velocity the tick started with, against the partner as he stood at the tick's
# start (Scripts/networking/CLAUDE.md). Both bodies of a pair lay the same
# acceleration once their inputs hold, so the pair moves as one; the contact
# resolver still separates the overlap and lands any check. Not modelled: a
# third body on the pair (the nearest partner presses), and the forward
# prediction of a pressed remote (it integrates his own movement).

# The partner's state the press reads: as his skater latched it at the end of
# the last tick, or on a client from where the host had him (LocalController).
class PressPartner:
	var position: Vector3 = Vector3.ZERO
	var weight: float = 1.0
	var cfg: SkaterMovementRules.MovementConfig = null
	var thrust: float = 0.0
	var facing: Vector2 = Vector2(0.0, -1.0)
	var intent: Vector2 = Vector2.ZERO
	var braking: bool = false
	var planted: bool = false
	var posture: int = SkaterMovementRules.Posture.UPRIGHT
	var stagger: float = 0.0

var _press_partner: PressPartner = PressPartner.new()


func _apply_press(input: InputState, delta: float, tick_start_velocity: Vector3) -> void:
	if skater.is_knocked_down or skater.is_ghost or skater.pin_role != BoardPinRules.Role.NONE \
			or plants_feet(_sm.get_state()) or delta <= 0.0:
		return
	if skater.contact_suspended_provider.is_valid() and bool(skater.contact_suspended_provider.call()):
		return
	var p: PressPartner = _press_partner
	if not _find_press_partner(input.host_timestamp, p):
		return
	var d: Vector3 = p.position - skater.global_position
	d.y = 0.0
	var dist: float = d.length()
	if dist < 0.0001:
		return
	var n3: Vector3 = d / dist
	var n := Vector2(n3.x, n3.z)
	var cfg: SkaterMovementRules.MovementConfig = _movement_config()
	var bc: BodyCheckRules.Config = _body_check_config()
	var posture: int = SkaterMovementRules.posture_of(stance_active, hit_active)
	var facing: Vector2 = skater.get_facing()
	var u: float = tick_start_velocity.dot(n3)
	var drive_self: float = PressRules.drive(cfg, thrust, posture, skater.brake_intent, false,
			BodyCheckRules.thrust_mult(stagger_timer, bc), facing,
			WorldStateCodec.quantize_move_intent(skater.move_intent), n, u)
	var drive_other: float = PressRules.drive(p.cfg, p.thrust, p.posture, p.braking, p.planted,
			BodyCheckRules.thrust_mult(p.stagger, bc), p.facing,
			WorldStateCodec.quantize_move_intent(p.intent), -n, -u)
	if not PressRules.pressing(drive_self, drive_other):
		return
	var hold_self: float = PressRules.hold(cfg, posture, skater.brake_intent, false,
			BodyCheckRules.grip_mult(stagger_timer, bc), facing, n, u)
	var hold_other: float = PressRules.hold(p.cfg, p.posture, p.braking, p.planted,
			BodyCheckRules.grip_mult(p.stagger, bc), p.facing, n, u)
	var u_new: float = u + delta * PressRules.pair_accel(skater.weight, drive_self, hold_self,
			p.weight, drive_other, hold_other, u, delta)
	# The pair goes no faster than its winner skates: a press is a stride.
	if absf(u_new) > absf(u):
		u_new = clampf(u_new, -maxf(p.cfg.max_speed, absf(u)), maxf(cfg.max_speed, absf(u)))
	skater.velocity += n3 * (u_new - skater.velocity.dot(n3))


# The nearest body this one is pressed against (PressRules.touching, exact),
# filled into `out` from what he latched at the end of the last tick; false for
# none. `_host_ts` is the input's stamp, which a client samples the partner at.
func _find_press_partner(_host_ts: float, out: PressPartner) -> bool:
	var my_pos: Vector3 = skater.global_position
	var my_radius: float = skater.collision_radius()
	var best: Skater = null
	var best_gap: float = INF
	for other: Skater in skater.contact_others():
		if other == null or other == skater or other.is_ghost or other.is_knocked_down \
				or other.pin_role != BoardPinRules.Role.NONE or other.press_cfg == null:
			continue
		var d: Vector3 = other.global_position - my_pos
		d.y = 0.0
		var gap: float = d.length() - my_radius - other.collision_radius()
		if PressRules.touching(gap, 0.0, 0.0) and gap < best_gap:
			best_gap = gap
			best = other
	if best == null:
		return false
	out.position = best.global_position
	out.weight = best.weight
	out.cfg = best.press_cfg
	out.thrust = best.press_thrust
	out.facing = best.latched_facing
	out.intent = best.latched_intent
	out.braking = best.latched_braking
	out.planted = plants_feet(best.latched_shot_state)
	out.posture = SkaterMovementRules.posture_of(best.latched_stance, best.latched_committed)
	out.stagger = best.latched_stagger
	return true


# Wound up, the hands are on the stick and the legs cannot stride: a skater
# glides on whatever momentum the wind-up found. Waiting on a feed with no puck
# yet he can still stop, and step-together onto the feed's line under
# SkaterMovementRules.SHUFFLE_MAX_SPEED (the brake with a stick), never skate.
# Published as the intent so the gait, and every peer's forward prediction,
# skate what the body does.
func _loaded_glide_intent(move_state: SkaterStateMachine.State) -> void:
	var waiting: bool = move_state == State.SLAPPER_CHARGE_WITHOUT_PUCK
	skater.brake_intent = waiting and skater.brake_intent
	skater.is_braking = skater.brake_intent
	if not skater.brake_intent:
		skater.move_intent = Vector2.ZERO

# Movement configs are cached — _apply_movement runs every physics tick (and
# once per reconcile-replayed input), and the source exports change only in
# apply_attributes. Same pattern as the goalie controller's cached rule
# configs. The block config is an independent instance, NOT a mutated copy of
# the shared one — mutating the cached base would corrupt normal skating.
var _cached_move_cfg: SkaterMovementRules.MovementConfig = null
var _cached_block_move_cfg: SkaterMovementRules.MovementConfig = null
# NativeSkaterMovement instances (null = extension absent, GDScript fallback).
# Configured lazily alongside their MovementConfig — the cache invalidation in
# apply_attributes reconfigures them on the next build. Stagger params ride
# along because integrate_forward applies the stagger thrust penalty natively.
var _native_move: RefCounted = null
var _native_block_move: RefCounted = null

func _movement_config() -> SkaterMovementRules.MovementConfig:
	if _cached_move_cfg == null:
		_cached_move_cfg = _build_movement_config()
		if skater != null:
			skater.press_cfg = _cached_move_cfg
			skater.press_thrust = thrust
		if ClassDB.class_exists(&"NativeSkaterMovement"):
			_native_move = ClassDB.instantiate(&"NativeSkaterMovement")
			var missing: String = _native_move.configure(_cached_move_cfg)
			if missing != "":
				push_error("NativeSkaterMovement disabled — config fields missing: %s" % missing)
				_native_move = null
			else:
				var bc: BodyCheckRules.Config = _body_check_config()
				_native_move.set_stagger_params(bc.max_stagger_seconds, bc.max_thrust_penalty,
						bc.max_grip_penalty, bc.rocked_max_seconds, bc.rocked_grip_penalty)
	return _cached_move_cfg

# The configured native movement kernel for this skater, or null when the
# extension isn't loaded. Shared by the live tick, RemoteController's stage-3
# forward prediction, and the host's claim rewind — one instance per skater so
# render == rewind runs the identical code path.
func native_movement() -> RefCounted:
	_movement_config()
	return _native_move

# Public read of the cached movement config (built from this skater's scaled
# tuning, rebuilt on apply_attributes). Consumed by stage-3 remote forward-
# prediction — the client (RemoteController) and host (HitClaimResolver) both
# drive SkaterMovementRules.integrate_forward with the target skater's own config.
# Live-tuning caveat aside, treat the returned object as read-only.
#
# thrust is re-normalized to the attribute-scaled base on every read: the live
# movement path transiently writes the stagger-scaled thrust into the CACHED
# config each tick, but only on the machine that simulates this skater (the
# host, or a bot's host controller) — a client's RemoteController never runs
# _apply_movement, so its copy holds base thrust. Without the reset the host
# claim rewind would integrate a recently-checked victim with present-tick
# staggered thrust while the client rendered base thrust — an input asymmetry
# breaking render == rewind right after checks, when follow-up claims cluster.
# The stagger penalty is then applied SYMMETRICALLY inside integrate_forward
# (both sides pass the snapshot's replicated stagger_timer + this skater's
# body-check config), so the normalization here is what keeps the base clean
# for that shared scaling rather than a decision to ignore stagger.
func get_movement_config() -> SkaterMovementRules.MovementConfig:
	var cfg: SkaterMovementRules.MovementConfig = _movement_config()
	cfg.thrust = thrust
	return cfg


# Public read of the cached body-check config — consumed by the stage-3 forward
# prediction (both the client render and the host claim rewind) to apply the
# victim's stagger thrust penalty identically on both sides.
func get_body_check_config() -> BodyCheckRules.Config:
	return _body_check_config()

func _block_movement_config() -> SkaterMovementRules.MovementConfig:
	if _cached_block_move_cfg == null:
		_cached_block_move_cfg = _build_movement_config()
		_cached_block_move_cfg.max_speed = max_speed * block_speed_multiplier
		_cached_block_move_cfg.thrust = thrust * block_speed_multiplier
		if ClassDB.class_exists(&"NativeSkaterMovement"):
			_native_block_move = ClassDB.instantiate(&"NativeSkaterMovement")
			if _native_block_move.configure(_cached_block_move_cfg) != "":
				# Same fields as the main config — a miss there already errored.
				_native_block_move = null
	return _cached_block_move_cfg

func _build_movement_config() -> SkaterMovementRules.MovementConfig:
	var cfg := SkaterMovementRules.MovementConfig.new()
	cfg.thrust = thrust
	cfg.power_knee_speed = power_knee_speed
	cfg.friction = friction
	cfg.friction_drag = friction_drag
	cfg.max_speed = max_speed
	cfg.move_deadzone = move_deadzone
	cfg.stop_decel = stop_decel
	cfg.reverse_skid_fraction = reverse_skid_fraction
	cfg.turn_accel = turn_accel
	cfg.max_turn_rate = max_turn_rate
	cfg.puck_carry_speed_multiplier = puck_carry_speed_multiplier
	cfg.backward_thrust_multiplier = backward_thrust_multiplier
	cfg.crossover_thrust_multiplier = crossover_thrust_multiplier
	cfg.backward_max_speed_multiplier = backward_max_speed_multiplier
	cfg.lateral_grip = lateral_grip
	cfg.stance_grip_mult = stance_grip_mult
	cfg.stance_scrape = stance_scrape
	cfg.stance_stride_mult = stance_stride_mult
	cfg.stance_max_speed_mult = stance_max_speed_mult
	cfg.shuffle_speed = shuffle_speed
	cfg.commit_grip_mult = commit_grip_mult
	cfg.commit_stride_mult = commit_stride_mult
	return cfg

# Body-check stagger config is flat (not attribute-scaled), so a single lazily-built
# instance is reused for the controller's lifetime, read both on a hit
# (_on_body_check_received) and every tick (the stagger penalties in
# _apply_movement).
var _cached_body_check_cfg: BodyCheckRules.Config = null

func _body_check_config() -> BodyCheckRules.Config:
	if _cached_body_check_cfg == null:
		_cached_body_check_cfg = BodyCheckRules.Config.new()
		_cached_body_check_cfg.min_impulse = stagger_min_impulse
		_cached_body_check_cfg.ref_impulse = stagger_ref_impulse
		_cached_body_check_cfg.max_stagger_seconds = stagger_max_seconds
		_cached_body_check_cfg.max_thrust_penalty = stagger_max_thrust_penalty
		_cached_body_check_cfg.max_grip_penalty = stagger_max_grip_penalty
		_cached_body_check_cfg.rocked_ref_impulse = rocked_ref_impulse
		_cached_body_check_cfg.rocked_min_seconds = rocked_min_seconds
		_cached_body_check_cfg.rocked_max_seconds = rocked_max_seconds
		_cached_body_check_cfg.rocked_grip_penalty = rocked_grip_penalty
		_cached_body_check_cfg.knockdown_ref_overshoot = knockdown_ref_overshoot
		_cached_body_check_cfg.min_lie_seconds = knockdown_lie_min_seconds
		_cached_body_check_cfg.max_lie_seconds = knockdown_lie_max_seconds
	return _cached_body_check_cfg

# Balance config, flat like the body-check config; the build's height enters
# per hit as _build_height_mult. The stance's base is the gait's own: each skate
# set stance_width_m out from under a hip GaitPose.HIP_HALF_WIDTH off centre.
var _cached_balance_cfg: BodyBalanceRules.Config = null
var _build_height_mult: float = 1.0

func _balance_config() -> BodyBalanceRules.Config:
	if _cached_balance_cfg == null:
		_cached_balance_cfg = BodyBalanceRules.Config.new()
		_cached_balance_cfg.balance_ref_dv = balance_ref_dv
		_cached_balance_cfg.along_share = balance_along_share
		_cached_balance_cfg.sight_behind = balance_sight_behind
		_cached_balance_cfg.vulnerable_mult = balance_vulnerable_mult
		_cached_balance_cfg.checker_front_share = balance_checker_front_share
		_cached_balance_cfg.stance_base_ratio = \
				(GaitPose.HIP_HALF_WIDTH + stance_width_m) / GaitPose.HIP_HALF_WIDTH
	return _cached_balance_cfg


func get_balance_config() -> BodyBalanceRules.Config:
	return _balance_config()

# Knockdown-fall config is flat (not attribute-scaled) — lazily built once for
# the controller's lifetime, same pattern as the body-check config above, with
# the dive's alongside it. Read every rendered frame while a skater is down
# (_apply_knockdown_fall).
var _cached_fall_cfg: KnockdownFallRules.Config = null
var _cached_dive_fall_cfg: KnockdownFallRules.Config = null

func _fall_config() -> KnockdownFallRules.Config:
	if _cached_fall_cfg == null:
		_cached_fall_cfg = KnockdownFallRules.Config.new()
		_cached_fall_cfg.buckle_seconds = knockdown_fall_buckle_seconds
		_cached_fall_cfg.fall_accel = knockdown_fall_accel
		_cached_fall_cfg.settle_angle = deg_to_rad(knockdown_fall_settle_deg)
		_cached_fall_cfg.restitution = knockdown_fall_restitution
		_cached_fall_cfg.rest_omega = knockdown_fall_rest_omega
		_cached_fall_cfg.com_height = knockdown_fall_com_height_m
		_cached_fall_cfg.max_entry_omega = knockdown_fall_max_entry_omega
		_cached_fall_cfg.sprawl_in_seconds = knockdown_sprawl_in_seconds
		_cached_fall_cfg.sprawl_splay = deg_to_rad(knockdown_sprawl_splay_deg)
		_cached_dive_fall_cfg = DiveRules.fall_config(_cached_fall_cfg)
	return _cached_dive_fall_cfg if _diving() else _cached_fall_cfg


# The shove the fall's tip rate is seeded from: the hit's, or for a dive the
# diver's own throw (DiveRules.TIP_RATE_RAD_S), whatever he was skating at.
func _fall_entry_speed() -> float:
	if _diving():
		return DiveRules.TIP_RATE_RAD_S * _fall_config().com_height
	return _knockdown_entry_speed


# The down pose is read by the gait before a skater is attached.
func _diving() -> bool:
	return skater != null and skater.is_diving


# Scratch for the sprawl solve — refilled every rendered frame while a skater
# is down (same rationale as _cached_fall_cfg above).
var _sprawl_scratch: KnockdownFallRules.SprawlPose = null

# Cached — _update_wrister_charge reads it every aim tick (replayed
# again per input through reconcile), so a per-call .new() is hot-path churn.
# Rebuilt lazily after apply_attributes nulls it (same pattern as the
# movement configs above).
var _cached_wrister_cfg: ShotMechanics.WristerConfig = null

func _wrister_config() -> ShotMechanics.WristerConfig:
	if _cached_wrister_cfg == null:
		_cached_wrister_cfg = ShotMechanics.WristerConfig.new()
		_cached_wrister_cfg.min_wrister_power = min_wrister_power
		_cached_wrister_cfg.max_wrister_power = max_wrister_power
		_cached_wrister_cfg.backhand_power_coefficient = backhand_power_coefficient
		_cached_wrister_cfg.quick_pass_power = quick_pass_power
		_cached_wrister_cfg.loft_vy_low = loft_vertical_speed_low
		_cached_wrister_cfg.loft_vy_high = loft_vertical_speed_high
		_cached_wrister_cfg.loft_tan_low = loft_tan_low
		_cached_wrister_cfg.loft_tan_mid = loft_tan_mid
		_cached_wrister_cfg.loft_tan_high = loft_tan_high
		_cached_wrister_cfg.power_curve = wrister_power_curve
		# Pure mouse-speed model: power is a curve over the cursor speed (fed as
		# sweep_speed by _wrister_sweep_speed). full_sweep_speed is the cursor
		# speed (px/s) that reads as full power.
		_cached_wrister_cfg.full_sweep_speed = wrister_mouse_speed_full
	return _cached_wrister_cfg

var _cached_wrister_load_cfg: WristerLoad.Config = null

func _wrister_load_config() -> WristerLoad.Config:
	if _cached_wrister_load_cfg == null:
		_cached_wrister_load_cfg = WristerLoad.Config.new()
		_cached_wrister_load_cfg.full_arc_rad = deg_to_rad(wrister_full_load_arc_deg)
		_cached_wrister_load_cfg.max_twist_rad = deg_to_rad(upper_body_max_twist_deg)
		_cached_wrister_load_cfg.home_reach_rad = deg_to_rad(wrister_home_reach_deg)
		_cached_wrister_load_cfg.away_reach_rad = deg_to_rad(wrister_away_reach_deg)
		_cached_wrister_load_cfg.arm_full_past_tangent_rad = \
				deg_to_rad(wrister_arm_full_past_tangent_deg)
	return _cached_wrister_load_cfg

# True for bot controllers (AIController overrides). Bots have no real cursor, so
# they drive the pure-mouse power model via a committed target fraction
# (InputState.bot_wrister_power_t) rather than a measured cursor speed.
func is_ai_controlled() -> bool:
	return false

# Shot Power Sensitivity for THIS controller. Base (bots / unknown) = 1.0;
# LocalController reads the local pref; a host-side RemoteController reads the
# value the host replicated from the remote client's join (set below), so the
# client's predicted shot power matches the host's authoritative shot.
var net_shot_power_sensitivity: float = 1.0

# Peer this controller drives, set by GameManager at spawn. Only a host-side
# RemoteController reads it (to look up that peer's measured ping); -1 elsewhere.
var net_peer_id: int = -1

func shot_power_sensitivity() -> float:
	return 1.0


# Extra time this controller holds the caught one-timer's window open (see
# ShotReleaseRules.one_timer_window_grace). Zero for anyone whose sim shares the
# host's clock — the host's own player, a bot, and every client predicting
# itself, all of which arm the window the instant they see the catch.
# RemoteController overrides it, because only the host arming a REMOTE carrier's
# window is arming it earlier than that carrier will.
func one_timer_window_lag_grace() -> float:
	return 0.0

# The speed signal fed to the wrister power model:
#   - Bots AND gamepad humans (commit_wrister_power): the cursor speed equivalent
#     to their committed target power fraction (bot_wrister_power_t) — deterministic,
#     no measured cursor. A pad parks its cursor while aiming, so its cursor speed is
#     ~0; the committed magnitude (right-stick push) is the real power signal.
#   - Mouse humans: the raw cursor speed, scaled by that player's Shot Power
#     Sensitivity (calibrates the flick-for-power feel to their mouse DPI).
func _wrister_sweep_speed(input: InputState) -> float:
	if is_ai_controlled() or input.commit_wrister_power:
		return ShotMechanics.wrister_speed_for_power_t(input.bot_wrister_power_t, _wrister_config())
	return _aiming.cursor_speed_ema * shot_power_sensitivity()

# Cached like the wrister config: _update_slapper_charge now re-solves the release
# every windup tick (× actors, replayed on reconcile) to publish
# predicted_shot_velocity, so a fresh SlapperConfig per call would be per-tick heap
# churn. Rebuilt lazily; invalidated in apply_attributes when the source exports change.
var _cached_slapper_cfg: ShotMechanics.SlapperConfig = null

func _slapper_config() -> ShotMechanics.SlapperConfig:
	if _cached_slapper_cfg == null:
		_cached_slapper_cfg = ShotMechanics.SlapperConfig.new()
		_cached_slapper_cfg.min_slapper_power = min_slapper_power
		_cached_slapper_cfg.max_slapper_power = max_slapper_power
		_cached_slapper_cfg.max_slapper_charge_time = max_slapper_charge_time
		_cached_slapper_cfg.loft_tan_low = loft_tan_low
		_cached_slapper_cfg.loft_tan_mid = loft_tan_mid
		_cached_slapper_cfg.loft_tan_high = loft_tan_high
	return _cached_slapper_cfg

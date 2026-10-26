class_name BotSkillProfile
extends RefCounted

# Per-difficulty bundle of deterministic bot-skill knobs. Every knob rides one of
# the three difficulty axes — PRECISION / PACE / COGNITION; the rules that keep
# them separate (and why aim slew is not a tier knob) are in
# Scripts/domain/ai/CLAUDE.md → "Difficulty rides three independent axes". The
# goalie's tier knobs are their own bundle (GoalieSkillProfile).
#
# To add a tier: add a Difficulty value, a factory, and a for_difficulty arm.
# To add a knob: add a field + _init param, set it in ALL THREE factories, and
# consume it where it is read — SkaterAgentStateMachine (dispatch, execution
# error, and the knobs it copies onto RoleContext), GameManager (carrier reaction
# delay), the roles (via RoleContext).

enum Difficulty {
	EASY = 0,     # the floor — well-late reads, swimmy blade, commits hard to stale reads
	NORMAL = 1,   # clearly beatable — laggier reads, trailing blade, slower cadence
	HARD = 2,     # the ceiling — "strong but human", a light humanising touch only
}

# How long the bot keeps treating the previous carrier as the carrier after the
# puck changes hands — its reaction time to a discrete possession event. Applied
# only to the carrier signal: positions stay real-time and self-possession is
# instant. Debounced globally by GameManager on the shared AI snapshot.
var carrier_reaction_delay_s: float

# Physics ticks between full decision re-evaluations during non-press states
# (press states always run full-rate). Higher = laggier reads. The one knob not
# denominated in seconds: calibrated at the 120 Hz sim, so it rescales linearly
# if the tick rate ever moves.
var dispatch_period_ticks: int

# Execution error on SHOT releases (radians of release-direction error; one
# uniform ± sample per release, held through the windup so the blade sweeps
# smoothly to a slightly wrong spot). THE conversion dial per tier: goals per
# shot fall smoothly and monotonically with it on the shot-outcome sim
# (tests/unit/ai/test_shot_sim.gd).
#
# Execution only: the carrier's shot value does not read it, so a wobblier tier
# takes the same shots and misses more of them (#699). The one selection site
# that still does is the one-timer reception gate (SkaterAgentReception.read_shot
# scores the redirect with it). The aim inset uses it so misses land on the GOALIE;
# posts and wides stay rare up to ~0.05 rad and climb past it, where a tier
# stops looking beaten and starts looking incompetent. This knob is conversion,
# not selectivity.
var shot_aim_error_rad: float

# Execution error on PASS releases and the dump, sampled the same way.
# Deliberately much smaller than shot error at the lower tiers — completed
# passes are fun to play against, every shot going in is not.
var pass_aim_error_rad: float

# Motor timing variance on the SHOT release (seconds). Each shot samples a
# late-release hold in [0, this]. Half of it (the expected lateness) is budgeted
# into the goalie's tracking time wherever the carrier scores its own shot, so a
# thin window is scored at its median release — still attempted, converted only
# when the sample lands early enough.
var shot_timing_error_s: float

# PACE: extra metres the on-puck PRESSURE defender drops its cut-off line back
# toward its own net, beyond the ladder's gap. Under a stick length he can still
# poke (see normal()); Easy sags well past it on purpose (see easy()).
var pursuit_standoff_m: float

# PACE: multiplier on the pace this bot's passes ARRIVE at (passes only, not
# shots) — AIPuckLane.pass_launch_speed then solves the launch that delivers
# it, so a softened feed still reaches the tape and still catches a streaking
# receiver.
#
# The bot is SELF-HONEST about it — every pass scoring site solves its lane
# clearance and miss probability at this same reduced pace, so a lower tier also
# stops ATTEMPTING the feeds its slower puck can no longer thread.
var pass_speed_scale: float

# PACE: how hard the on-puck pressurer hunts body checks. 1.0 = full hit-hunting;
# below 1.0 raises the required separating-hit impulse inversely so only the
# hardest hits commit; 0.0 = pure containment. Consumed in
# AIDefensiveVerbs.evaluate_body_check.
var check_aggression: float

# PACE: multiplier on DEFENSIVE_ANTICIPATION_S, how far ahead a defender READS
# the other attackers when pricing what the carrier can do with them — PRESSURE's
# and FORECHECK's pass-lane set, the unassigned marker's recovery. Lower = the
# bot scores the threats where they ARE, not where they're going.
#
# It must never move a defender's STAND: a cover point and a gap stand already
# ride their man (AIDefensiveVerbs.cover_threat), so leading the anchor as well
# double-counts his motion. The on-puck space concession is pursuit_standoff_m.
var defensive_anticipation_scale: float

# COGNITION: exploit a MOVING goalie — aiming back across the grain of a slide
# (AIShotAim's velocity-projected shadow) and valuing the re-square race a
# cross-seam feed wins. False = models the goalie as always set and shoots where
# he IS. The biggest single scoring cut, through cognition rather than wobble.
var reads_goalie_motion: bool

# COGNITION: value a play that doesn't exist yet — a finisher still skating to
# the back door, an outlet still opening — and protect the puck until it does
# (AICarrierPassSearch.developing_feed_value). False = plays only what's in front of it.
var holds_for_developing_feeds: bool

# COGNITION: price a receiver's smoothed heading turn rate as catch-point
# uncertainty, so a teammate mid-cut is a riskier feed and an elite passer waits
# for them to come out of the turn. False = blind to it, chucks feeds at turning
# players. A settled receiver reads ~0 either way, so this never slows a clean
# quick feed.
var reads_receiver_commitment: bool

# COGNITION: approach an opposing carrier from the inside to force them to the
# boards (_shade_intercept_goal_side). False = straight-line chase, so a human's
# cutback to the middle works.
var angles_the_chase: bool

# COGNITION: the last man back on a rush reads the carrier's PASSING options and
# splits toward an uncovered receiver's feed lane — the 2-on-1 "play the pass,
# the goalie takes the shooter" doctrine. False = RUSH_D1 sees only the carrier
# and retreats on the carrier→net line, so the cross-crease feed connects.
var plays_rush_pass_lanes: bool

# COGNITION: shield the puck with the body — a pressured carrier pulls the puck
# off the presented forward spot to the protected side of the reachable-set seam.
# False = the puck stays presented ~2 m ahead at all times, so a newcomer's
# straight-line poke-check genuinely works.
var protects_the_puck: bool

# COGNITION: an on-puck defender reads a shielded puck and lifts the carrier's
# stick instead of jabbing through his body (AIStickLiftRead). False = jab only,
# so shielding the puck from a beginner bot genuinely protects it.
var lifts_sticks: bool

# COGNITION: the stick battle — a covering defender ties his man's stick when the
# puck is coming to him and nothing else would stop it, and a tied attacker pulls
# his stick free (AIStickTieRead). False = neither.
var ties_sticks: bool

# COGNITION: shot blocks — a defender in a low shot's lane drops into the block,
# and a 2-on-1's last defender dives across the pass (AIShotBlockRead). False =
# neither, so a newcomer's shots and cross-ice feeds are never taken away.
var blocks_shots: bool


func _init(p_carrier_reaction_delay_s: float,
		p_dispatch_period_ticks: int,
		p_shot_aim_error_rad: float, p_pass_aim_error_rad: float,
		p_shot_timing_error_s: float,
		p_pursuit_standoff_m: float, p_pass_speed_scale: float,
		p_check_aggression: float, p_defensive_anticipation_scale: float,
		p_reads_goalie_motion: bool, p_holds_for_developing_feeds: bool,
		p_angles_the_chase: bool, p_plays_rush_pass_lanes: bool,
		p_protects_the_puck: bool,
		p_reads_receiver_commitment: bool,
		p_lifts_sticks: bool, p_ties_sticks: bool, p_blocks_shots: bool) -> void:
	carrier_reaction_delay_s = p_carrier_reaction_delay_s
	dispatch_period_ticks = p_dispatch_period_ticks
	shot_aim_error_rad = p_shot_aim_error_rad
	pass_aim_error_rad = p_pass_aim_error_rad
	shot_timing_error_s = p_shot_timing_error_s
	pursuit_standoff_m = p_pursuit_standoff_m
	pass_speed_scale = p_pass_speed_scale
	check_aggression = p_check_aggression
	defensive_anticipation_scale = p_defensive_anticipation_scale
	reads_goalie_motion = p_reads_goalie_motion
	holds_for_developing_feeds = p_holds_for_developing_feeds
	reads_receiver_commitment = p_reads_receiver_commitment
	angles_the_chase = p_angles_the_chase
	plays_rush_pass_lanes = p_plays_rush_pass_lanes
	protects_the_puck = p_protects_the_puck
	lifts_sticks = p_lifts_sticks
	ties_sticks = p_ties_sticks
	blocks_shots = p_blocks_shots


# Hard reads as a very strong human rather than a frame-perfect robot: ~50 ms
# reaction, dispatch every 2 ticks, a flat ±0.6° of execution error on both
# releases, and 0.10 s of release slop — so the doorstep lateral beat is still
# hunted but a window in the ~0.05–0.10 s band is a coin flip the goalie
# sometimes robs. Pace knobs at their no-op baseline, every cognition gate
# open.
#
# Tune carrier_reaction_delay_s UP if it matches passes too readily.
static func hard() -> BotSkillProfile:
	return BotSkillProfile.new(0.05, 2, 0.01, 0.01, 0.10,
			0.0, 1.0, 1.0, 1.0,
			true, true, true, true, true, true, true, true, true)


# Normal is the beatable tier, pushed firmly off the Hard ceiling: a ~220 ms
# reaction (it recognises a pass a clear beat late and no longer matches
# one-timers) at a third of Hard's re-decide rate. Shot error ±2.3° ≈ ±0.48 m at
# the net from 12 m, so a well-picked corner becomes goals AND saves and the
# score's spread budget stops the from-range snipes entirely; pass error stays
# near-Hard so the passing game keeps connecting.
#
# pursuit_standoff_m must stay well under a stick length: at 1.5 m the pressurer
# sits permanently outside blade reach and can never poke. At 0.75 the carrier's
# own motion brings the puck transiently into contest range while the human
# still gets his beat.
static func normal() -> BotSkillProfile:
	return BotSkillProfile.new(0.22, 6, 0.04, 0.015, 0.16,
			0.75, 0.85, 0.65, 0.6,
			true, true, true, true, true, true, true, true, true)


# Easy is the newcomer floor: a ~340 ms reaction (visibly human-slow) and a slow
# cadence, so it commits hard to a stale read and can be dragged out of position.
# Still plays positionally and shoots / passes — a real but soft opponent, not a
# stationary one. Shot error ±3.2° ≈ ±0.65 m from 12 m, so even good looks
# routinely find the goalie or the glass.
#
# Pace is low-energy across the board — defenders sag ~3 m, barely lead the play,
# never hunt body checks, and put the puck on a teammate's tape at 0.75 pace
# (15 m/s), a floaty feed a newcomer has time to step in front of.
#
# Cognition: all gates closed, so the cutback to the middle, the straight-line
# poke-check, and the cross-crease 2-on-1 glory feed all genuinely work.
static func easy() -> BotSkillProfile:
	return BotSkillProfile.new(0.34, 9, 0.055, 0.0225, 0.24,
			3.0, 0.75, 0.0, 0.2,
			false, false, false, false, false, false, false, false, false)


static func for_difficulty(difficulty: int) -> BotSkillProfile:
	match difficulty:
		Difficulty.EASY:
			return easy()
		Difficulty.NORMAL:
			return normal()
		_:
			return hard()

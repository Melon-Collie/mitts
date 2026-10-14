extends GutTest

# ── THE HUMAN'S MOVE, MEASURED ───────────────────────────────────────────────
# "Skate at the goalie to commit him to a butterfly, then skate around and wrap
# it around him." It is one player's whole offence and it is where the live log
# says the keeper is worst: inside 3 m against a DOWN keeper is 46.7% of that
# player's shots at 24.0% save percentage, and the COILING stance alone is 21.5%
# of them at 11.3%.
#
# `human_wraparound_harness` drives the real GoalieController and the real puck
# → goalie collision through the whole sequence. Everything below is either a
# structural assertion about the sequence or a pinned characterisation of it.
#
# ══ WHAT THE INSTRUMENT AGREES WITH, AND WHAT IT DOES NOT ═══════════════════
# It reproduces the SHAPE: the goals are in tight, off-angle, against a keeper
# who is not where the shot is. It does NOT reproduce the LEVEL — the best cell,
# the cutback (test_goalie_breakaway_ladder), opens under half the fan where the
# live player converts three quarters of everything he takes from that cell. Two differences are known and neither
# is modelled: every trial starts from a fully settled keeper (live, 54.5% of
# this player's shots are at a keeper still in motion, at 35.0% save percentage),
# and there is no traffic, no rebound and no prior event to have disturbed him.
# Quote the ORDERING of cells from this file, not the rates.
#
# ══ AND ONE PLACE IT CONTRADICTS THE LIVE READING ═══════════════════════════
# `tools/goalie_shot_events_depth_when_down.sql` finds save percentage falling
# hard with the keeper's radius at the release while he is down, and that was
# read as "dropping while aggressive is the defect". Held to a FIXED release
# point, this instrument finds no such thing: a commit baited further out is
# beaten no more than a late one (test_committing_further_out_is_not_what_beats_him).
#
# The committed slide spends nearly all of its travel on DEPTH (test 3), so
# whichever radius he commits from, the walk-around finds him on his line and
# sealed. That makes the live radius column a proxy for HOW RECENTLY HE WAS
# DISTURBED rather than a cause, and "he drops too far out" a description of the
# symptom rather than of the defect.

const Snapshot := preload("res://tests/snapshot.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const Harness := preload("res://tests/unit/ai/human_wraparound_harness.gd")
const SkaterScene := preload("res://Scenes/Skater.tscn")
# Seven aim points spanning the mouth, one puck radius inside each post. The
# measurement is HOW MUCH NET IS OPEN, not whether a shooter who already knows
# the answer can find it — so every trial fires the whole fan and the score is
# the count that goes in. A "best of the fan" reading would credit an oracle.
const AIM_X: Array[float] = [-0.85, -0.55, -0.25, 0.0, 0.25, 0.55, 0.85]
const SHOT_M_S: float = 18.0        # an in-tight tuck, not a bomb
const START_M: float = 9.0          # where the drive begins, perpendicular
const DRIVE_M_S: float = 5.0
const PULL_M: float = 1.1           # forehand→backhand amplitude
const PULL_S: float = 0.25

var _h: RefCounted = null
var _ctrl: GoalieController = null


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	var puck: Node = load("res://Scenes/Puck.tscn").instantiate()
	var shooter: Skater = SkaterScene.instantiate() as Skater
	_ctrl = GoalieController.new()
	for n: Node in [goalie, puck, shooter, _ctrl]:
		add_child_autofree(n)
	_h = Harness.new()
	_h.setup(goalie, puck, _ctrl, shooter)


func _reset() -> void:
	_h.settle_ready(Vector3(0.0, 0.0, GOAL_Z + START_M))
	_h.begin_trial()


# ── 1. NOTHING ABOUT DRIVING AT HIM MAKES HIM DROP ───────────────────────────
# The move is described as "skate at the goalie to commit him", and the drive on
# its own does not: not at any pace, not to any depth short of running him over,
# and not with the trigger held down the whole way in. Whatever commits him in a
# real game — traffic, a rebound, a previous shot — is not the straight skate.
#
# This has teeth in both directions. A doorstep-proximity drop reintroduced
# anywhere in `_should_block` fails it, and so does a shot-threat read that
# starts firing off a plain carried wind-up on the rush.
func test_a_straight_drive_never_takes_him_off_his_feet() -> void:
	var aims: Array = [Vector3.INF, Vector3(0.6, 0.10, GOAL_Z)]
	for declared: Vector3 in aims:
		for speed: float in [4.0, 5.5, 7.0]:
			for floor_d: float in [0.8, 1.2, 2.0, 3.2]:
				_reset()
				var down: bool = _h.bait_commit(0.0, START_M, floor_d, speed,
						0.0, PULL_S, INF, declared)
				assert_false(down,
						"%s drive at %.1f m/s to %.1f m must not take him off his feet"
						% ["winding" if declared != Vector3.INF else "cold",
						speed, floor_d])


# ── 2. THE PUCK GOING ACROSS IS THE WHOLE BAIT ───────────────────────────────
# And it commits him to a SLIDE (COILING), not to an idle butterfly — the
# beaten-wide post seal, fired on the accomplished fact that the puck has passed
# his standing sealing reach. That matters for reading the live log: the keeper
# the player describes "butterflying too far out" is a keeper mid-seal.
#
# The radius ordering is the one this test exists for. Where he commits is a
# controllable input — pull earlier and he goes down further out — which is what
# lets every table below be cut on his commit radius.
const PULL_POINTS: Array[float] = [2.5, 3.5, 4.5]


# [commit radius per pull point], asserting each bait commits him to the seal.
func _commit_radii() -> Array[float]:
	var radii: Array[float] = []
	for pull_at: float in PULL_POINTS:
		_reset()
		var down: bool = _h.bait_commit(0.0, START_M, 0.9, DRIVE_M_S,
				PULL_M, PULL_S, pull_at)
		assert_true(down, "a %.1f m pull inside %.1f m must commit him"
				% [PULL_M, pull_at])
		assert_eq(_h.commit_stance, GoalieStateMachine.State.COILING as int,
				"the commit is the beaten-wide seal, not an idle butterfly")
		radii.append(_h.commit_radius)
	return radii


func test_pulling_the_puck_across_is_what_commits_him() -> void:
	var radii: Array[float] = _commit_radii()
	assert_lt(radii[0], radii[1], "pulling later commits him deeper")
	assert_lt(radii[1], radii[2], "pulling earlier commits him further out")
	# He runs out of room to be baited short of his base depth: a pull further
	# out is inside his standing coverage and he simply tracks it, so no clean
	# walk-in reaches the band from depth_base out that the live log holds 26
	# shots in. Those rows come from somewhere this instrument does not go.
	assert_lt(radii[-1], _ctrl.depth_base,
			"a clean walk-in cannot bait a commit out at his base depth")


# ── 3. THE COMMITTED SLIDE IS A RETREAT, NOT A PUSH ──────────────────────────
# The seal target is a pad length short of the post — `net_half_width −
# pad_edge · cos(slide rotation)`, since the seal is the pad's outer edge on the
# post (test_goalie_held_puck_slide_loop holds that spot) — so the lateral leg is
# centimetres by geometry rather than by tuning, and the travel is depth.
#
# The consequence is the whole scenario. A commit out on the challenge arc is a
# keeper who owes a metre of retreat, and every tick of that is spent in
# COILING or SLIDING — the two stances the live log scores lowest against this
# player.


# [lateral travel, depth travel, seconds to an idle butterfly] of one seal.
func _seal_travel() -> Array[float]:
	_reset()
	_h.trace_enabled = true
	assert_true(_h.bait_commit(0.0, START_M, 0.9, DRIVE_M_S, PULL_M, PULL_S, 4.0),
			"precondition: the bait commits him")
	var px: float = _ctrl.lateral_x()
	var pr: float = _ctrl.challenge_radius()
	_h.wrap_to(-1.35, 0.70, 4.0)
	var lateral: float = 0.0
	var depth: float = 0.0
	var settled_s: float = INF
	for row: Array in _h.trace:
		lateral += absf(row[2] - px)
		depth += absf(row[3] - pr)
		px = row[2]
		pr = row[3]
		if is_inf(settled_s) and int(row[1]) == GoalieStateMachine.State.BUTTERFLY:
			settled_s = row[0]
	return [lateral, depth, settled_s]


func test_the_committed_slide_spends_itself_on_depth() -> void:
	var travel: Array[float] = _seal_travel()
	assert_gt(travel[1], travel[0],
			"the seal is a retreat to the line, not a sideways push")
	assert_true(is_finite(travel[2]), "and it ends in an idle butterfly")


# ── 4. COMMITTING FURTHER OUT IS NOT WHAT BEATS HIM ──────────────────────────
# The live cut says save percentage collapses with his radius at the release
# while he is down. Held to one release point, the causal version of that claim
# is false here: baiting the commit EARLIER — further out — leaves no more net
# open, because the extra time is time he spends completing the retreat
# (Scripts/controllers/CLAUDE.md). The counts are the snapshot.


# Aim points open on the walkaround after a commit baited at each pull point.
func _open_by_pull_point() -> Array[int]:
	var by_pull: Array[int] = []
	for pull_at: float in PULL_POINTS:
		var open: int = 0
		for ax: float in AIM_X:
			_reset()
			_h.bait_commit(0.0, START_M, 0.9, DRIVE_M_S, PULL_M, PULL_S, pull_at)
			var rel: Vector3 = _h.wrap_to(-1.35, 0.70, 4.0)
			if _h.fire_release_at(rel, Vector3(ax, 0.0, GOAL_Z), 0,
					SHOT_M_S, 0.0) == 0:
				open += 1
		by_pull.append(open)
	return by_pull


func test_committing_further_out_is_not_what_beats_him() -> void:
	var by_pull: Array[int] = _open_by_pull_point()
	assert_gte(by_pull[0], by_pull[-1],
			"a commit baited later (deeper) leaves at least as much net open as one baited early")


# ── 5. THE SEAL TURNS HIM TO ITS OWN POST ────────────────────────────────────
# A cut across the crease leaves him tracking the carrier, so he commits from
# OUTSIDE the seal spot and reaches it by moving back toward the middle. Turned
# the way he travelled, he would face the OTHER post, the sealing pad pointing
# away from the post it seals and the near post open while he sat there.
func test_the_seal_faces_the_post_it_seals() -> void:
	_reset()
	assert_true(_h.bait_commit(0.0, START_M, 0.9, DRIVE_M_S, PULL_M, PULL_S, 3.5),
			"precondition: the bait commits him")
	_h.wrap_to(-1.35, 0.70, 4.0)
	assert_eq(_ctrl.stance(), GoalieStateMachine.State.BUTTERFLY as int,
			"precondition: he has landed")
	assert_almost_eq(rad_to_deg(_ctrl._turn_from_seal(-1.0)), 0.0, 1.0,
			"he faces the post the puck went to")
	assert_false(_ctrl._beaten_wide_committed, "and the beat clears on arrival")


# ── THE REVIEWED MEASUREMENTS ────────────────────────────────────────────────
# Rewrite with MITTS_UPDATE_SNAPSHOTS=1 (tests/snapshot.gd) and review the diff.
func test_human_wraparound_snapshot() -> void:
	var snap := Snapshot.new("res://tests/slow/ai/snapshots/human_wraparound.txt")
	var radii: Array[float] = _commit_radii()
	var open: Array[int] = _open_by_pull_point()
	for i: int in PULL_POINTS.size():
		snap.record("pull at %.1f m: commit radius" % PULL_POINTS[i], radii[i])
		snap.record("pull at %.1f m: walkaround open of %d" % [PULL_POINTS[i], AIM_X.size()],
				open[i])
	var travel: Array[float] = _seal_travel()
	snap.record("seal from a 4.0 m pull: lateral travel", travel[0])
	snap.record("seal from a 4.0 m pull: depth travel", travel[1])
	snap.record("seal from a 4.0 m pull: seconds to an idle butterfly", travel[2])
	snap.verify(self)

extends GutTest

# Research-grounded calibration for the goalie model (docs/AUDIT_2026-07_
# GOALIE_REALISM.md). Each test pins a trigger or magnitude to a documented
# coaching doctrine or measured number from the audit's research — USA Hockey /
# Hockey Canada curricula, Clear Sight Analytics tracking, Panchuk & Vickers
# quiet-eye work, and the Brock University butterfly biomechanics study. The
# point is drift protection: if a tune moves the model outside what the
# research supports, the failing test names the doctrine being violated.


# ── Perception: reaction structure (quiet-eye / CSA / RT literature) ──────────

func test_movement_penalty_is_additive_only() -> void:
	# CSA set-vs-unset: penalties only ever ADD read latency; a set goalie is
	# never buffed past the base read.
	var cfg := GoalieBehaviorRules.MovementReadConfig.new()
	cfg.reference_speed = 2.5
	cfg.speed_delay = 0.12
	cfg.scramble_delay = 0.12
	cfg.scramble_unset = 1.0
	assert_almost_eq(GoalieBehaviorRules.movement_read_penalty(0.0, false, cfg),
			0.0, 0.0001)
	assert_almost_eq(GoalieBehaviorRules.movement_read_penalty(99.0, false, cfg),
			cfg.speed_delay, 0.0001, "penalty caps at speed_delay")


# ── Save selection: cross-crease and stay-down doctrine ───────────────────────

func test_pads_first_commit_keys_on_the_puck_not_the_body() -> void:
	# The tuck is played by the puck. A body driving across the crease with
	# the puck trailing on the far side (the forehand-drag drive) has not
	# committed anything — the wrap/cut-back is free, and a goalie who sells
	# out to the body is exactly what the move fishes for. Pads-first only
	# once the puck itself is past the standing sealing reach (the point of
	# no return: bringing it back costs the full trip around the body).
	var cfg := GoalieBehaviorRules.BeatenWideConfig.new()
	cfg.goalie_lateral_speed = 3.8
	cfg.goalie_lateral_accel = 14.0
	cfg.reach_half_width = 0.42
	cfg.min_lateral_speed = 2.5
	cfg.max_threat_distance = 4.0
	var goalie := Vector3(0.0, 0.0, 24.85)
	var body := Vector3(0.2, 0.0, 25.5)
	assert_false(GoalieBehaviorRules.is_beaten_wide(
			body, Vector3(-0.8, 0.0, 25.6), 4.0, goalie,
			26.6, 0.0, -1, 0.915, cfg),
			"puck trailing the drive → stay up, shuffle across")
	assert_true(GoalieBehaviorRules.is_beaten_wide(
			body, Vector3(0.9, 0.0, 25.6), 4.0, goalie,
			26.6, 0.0, -1, 0.915, cfg),
			"puck past the sealing reach → the tuck is live, sell out")


# ── Post play: RVH discipline and the VH split ────────────────────────────────

func test_post_stance_families_cover_both_sides_of_the_goal_line() -> void:
	# Jake Allen / Woll doctrine: RVH at/below the goal line, VH for the
	# in-front sharp-angle shot threat (keeps short-side-high coverage).
	var sm := GoalieStateMachine.new()
	sm.current = GoalieStateMachine.State.RVH_LEFT
	assert_true(sm.is_post_integrated())
	assert_false(sm.is_vh())
	sm.current = GoalieStateMachine.State.VH_LEFT
	assert_true(sm.is_post_integrated())
	assert_true(sm.is_vh())
	assert_false(sm.is_down(),
			"VH is a post stance, not butterfly-family (no slide machinery)")
	assert_false(sm.is_upright(),
			"VH is committed to the post — not a drop-eligible upright stance")


# ── Rebounds: the equipment, not a doctrine ──────────────────────────────────
# What the rebound model asserts is now a claim about GEAR — how stiff each
# surface is, and how the puck's own COR falls as the impact hardens. These pin
# the claims, not the digits: a material row may be retuned, but a blocker that
# rebounds softer than a chest protector is a bug in the table.

const _SQUARE_N := Vector3(0.0, 0.0, 1.0)   # face pointing back at the shooter


func _square_rebound(part: int, speed: float) -> float:
	return GoalieSaveRules.rebound_velocity(
			Vector3(0.0, 0.0, -speed), part, _SQUARE_N).length()


func test_save_surfaces_rank_by_how_stiff_the_gear_is() -> void:
	# Composite paddle > board-backed blocker > foam-over-core pad > foam over a
	# torso that gives > a leather pocket the hand did not close on.
	var stick: float = _square_rebound(GoalieSaveRules.SavePart.STICK, 20.0)
	var blocker: float = _square_rebound(GoalieSaveRules.SavePart.BLOCKER, 20.0)
	var pad: float = _square_rebound(GoalieSaveRules.SavePart.PAD, 20.0)
	var glove: float = _square_rebound(GoalieSaveRules.SavePart.GLOVE, 20.0)
	var chest: float = _square_rebound(GoalieSaveRules.SavePart.CHEST, 20.0)
	assert_gt(stick, blocker, "the paddle is the stiffest thing on him")
	assert_gt(blocker, pad, "a board behind thin foam beats a pad built to absorb")
	assert_gt(pad, chest, "a chest over a body that gives kills more than a leg pad")
	assert_gt(chest, glove, "and an unclosed glove kills the most")


func test_a_harder_shot_keeps_less_of_itself_but_still_rebounds_faster() -> void:
	# The two halves of the COR falloff, and the reason it is not a control knob:
	# a hard shot RETAINS a smaller fraction, which is the measured puck
	# behaviour, and still comes off FASTER in absolute terms — which is why hard
	# shots make dangerous rebounds and soft ones die in front of him.
	var soft_in: float = 8.0
	var hard_in: float = 34.0
	var soft: float = _square_rebound(GoalieSaveRules.SavePart.PAD, soft_in)
	var hard: float = _square_rebound(GoalieSaveRules.SavePart.PAD, hard_in)
	assert_lt(hard / hard_in, soft / soft_in, "the hard shot keeps a smaller share")
	assert_gt(hard, soft, "and still leaves faster — the second chance is real")


func test_a_glance_survives_where_a_square_hit_dies() -> void:
	# One contact model across the whole game: the same split that makes a
	# glancing board carom keep its pace and a glancing blade tip a redirect.
	var square: Vector3 = GoalieSaveRules.rebound_velocity(
			Vector3(0.0, 0.0, -20.0), GoalieSaveRules.SavePart.PAD, _SQUARE_N)
	var glance: Vector3 = GoalieSaveRules.rebound_velocity(
			Vector3(19.0, 0.0, -6.2), GoalieSaveRules.SavePart.PAD, _SQUARE_N)
	assert_gt(glance.length(), square.length() * 2.0,
			"a puck sliding across the pad keeps its pace; a square hit does not")


# ── Cover / freeze doctrine (USA Hockey cover-vs-clear hierarchy) ─────────────

func test_covering_is_a_committed_down_state() -> void:
	# On the wire the smother reads as a sealed (down-family) pose; in the
	# state machine it is neither upright (no drop-eligibility) nor butterfly
	# family (no slide machinery composes with a smother).
	var sm := GoalieStateMachine.new()
	sm.current = GoalieStateMachine.State.COVERING
	assert_false(sm.is_upright())
	assert_false(sm.is_down())
	assert_false(sm.is_post_integrated())
	var ns := GoalieNetworkState.new()
	ns.state_enum = GoalieStateMachine.State.COVERING as int
	assert_true(ns.is_down(), "replicated smother pose is down-family")


# ── Catch-and-hold doctrine ───────────────────────────────────────────────────

func test_catching_state_families() -> void:
	# The upright and down catch variants exist so clients' state-keyed
	# body/head heights render the right silhouette; neither is upright (no
	# drop-eligibility mid-squeeze) and only the down variant reads as a
	# down-family pose on the wire.
	var sm := GoalieStateMachine.new()
	sm.current = GoalieStateMachine.State.CATCHING
	assert_true(sm.is_catching())
	assert_false(sm.is_upright())
	assert_false(sm.is_down())
	var up := GoalieNetworkState.new()
	up.state_enum = GoalieStateMachine.State.CATCHING as int
	assert_false(up.is_down(), "upright catch keeps the standing silhouette")
	var down := GoalieNetworkState.new()
	down.state_enum = GoalieStateMachine.State.CATCHING_DOWN as int
	assert_true(down.is_down(), "butterfly catch keeps the sealed silhouette")

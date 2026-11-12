extends DrillLoop

# Offline penalty-shot drill: "how many can you score out of 10". Spawned by
# game_scene.gd via DrillRegistry when NetworkManager.drill_id selects it. Owns
# the whole loop — stage the shooter at centre with the puck a stride ahead to
# skate onto, let them pick it up and drive in on a lone reactive goalie, classify
# the attempt with PenaltyShotRules (NHL Rule 24.2, read as a gameplay rule: the
# SHOOTER must keep driving toward the net — one shot, no rebounds), tally it, and
# restage — finishing with a results card. The keep-driving rules don't arm until
# the shooter actually picks up the puck, so a loose puck waiting at centre never
# reads as a stalled shot. Because those rules track the player's own forward
# drive (not the puck), dangling or shooting the puck can't fail the attempt —
# only the shooter stalling or backing off does.
#
# Modelled on TutorialManager's lifecycle (single local player + puck, a manager
# that owns staging and a code-built HUD), minus the multi-step machinery.

# Team 0 attacks the -Z net, where spawn_penalty_goalie places the goalie.
const _GOAL_LINE_Z: float = -GameRules.GOAL_LINE_Z
const _NET_HALF_WIDTH: float = GameRules.NET_HALF_WIDTH
const _TOTAL_SHOTS: int = 10

# Centre-ice staging spot for the shooter.
const _START: Vector3 = Vector3(0.0, 1.0, 0.0)

# Safety net: an attempt that's been live this long (puck wedged, etc.) without
# resolving is force-scored as a miss so the drill can't soft-lock.
const _MAX_ATTEMPT_TIME: float = 20.0

# The attempt in flight (PenaltyShotAttempt), which a match's penalty shot
# steps too.
var _attempt := PenaltyShotAttempt.new()


func _ready() -> void:
	if not bind_local_player(_TOTAL_SHOTS):
		return
	_attempt.max_live_s = _MAX_ATTEMPT_TIME
	GameManager.spawn_penalty_goalie()
	mount_hud(PenaltyDrillHUD.new())
	_begin_attempt()


func _exit_tree() -> void:
	# Mirror TutorialManager: the manager owns the lone goalie, so tear it down
	# on the way out (covers the scene change from return_to_free_play, which
	# frees this subtree). despawn nulls the GameManager fields so the next
	# session can spawn a fresh one.
	GameManager.despawn_penalty_goalie()


# ── Attempt lifecycle ─────────────────────────────────────────────────────────

func _begin_attempt() -> void:
	_stage = Stage.LIVE
	# Stand the shooter at centre facing the net with the puck staged a stride
	# ahead to skate onto, and reset the goalie into its crease.
	_local_controller.teleport_to(_START, FACE_NET)
	stage_puck_for_player()
	GameManager.reset_penalty_goalie()
	_attempt.begin(ATTACK_DIR_Z, _GOAL_LINE_Z, _NET_HALF_WIDTH)
	show_attempt_progress()


func _resolve_attempt(made: bool) -> void:
	# Leave the puck where the attempt ended (in the net on a goal, out wide on a
	# miss) so the shooter actually SEES the result during the hold, instead of it
	# vanishing off-rink the instant it crosses. Detection is off now (_stage is
	# RESULT, so _tick_live won't run) and re-pickup is locked, so a settling
	# rebound can't re-trigger or be re-collected before the next attempt stages.
	_puck.set_skater_cooldown(_skater, RESULT_HOLD + 1.0)
	record_result(made)
	SoundManager.play_crowd(SoundManager.Sound.GOAL_HORN if made else SoundManager.Sound.FACEOFF_WHISTLE)


# ── Per-tick detection ────────────────────────────────────────────────────────

func _tick_live(delta: float) -> void:
	var outcome: PenaltyShotRules.Outcome = _attempt.step(delta,
			_skater.global_position.z, _puck.carrier == _skater,
			_puck.get_puck_position(), _puck.get_puck_velocity().z)
	if outcome == PenaltyShotRules.Outcome.LIVE:
		return
	_resolve_attempt(outcome == PenaltyShotRules.Outcome.GOAL)

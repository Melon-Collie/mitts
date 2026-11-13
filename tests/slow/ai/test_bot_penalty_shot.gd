extends GutTest

# A bot taking a penalty shot: alone on the ice with the puck laid a stride
# ahead of him at centre, as a match stages it, judged by the attempt the
# match steps (PenaltyShotAttempt). The duel harness skates the real agent;
# its keeper is the static one, so this is about the skater's part: he
# collects the puck, keeps driving the net and gets a shot away.

const Harness := preload("res://tests/unit/ai/duel_harness.gd")
const SHOOTER: int = 1
const TEAM: int = 0
const LIVE := PenaltyShotRules.Outcome.LIVE


# Runs one shot to its end. Returns what ended it and what he had done by then.
func _take_a_shot(profile: BotSkillProfile) -> Dictionary:
	var sim := Harness.new()
	sim.add_skater(SHOOTER, TEAM, PlayerRules.penalty_shot_start(), profile)
	var spot: Vector2 = PlayerRules.penalty_shot_puck_spot(TEAM)
	sim.start(-1, Vector3(spot.x, 0.0, spot.y))
	var attack_dir_z: float = -PlayerRules.own_goal_dir(TEAM)
	var attempt := PenaltyShotAttempt.new()
	attempt.max_wait_s = GameRules.FACEOFF_TIMEOUT
	attempt.begin(attack_dir_z, attack_dir_z * GameRules.GOAL_LINE_Z, GameRules.NET_HALF_WIDTH)
	var outcome: PenaltyShotRules.Outcome = LIVE
	var collected_at: float = -1.0
	var t: float = 0.0
	while outcome == LIVE and t < 40.0:
		sim.step()
		t += Harness.DT
		if collected_at < 0.0 and sim.carrier() == SHOOTER:
			collected_at = t
		outcome = attempt.step(Harness.DT, sim.skater_pos(SHOOTER).z,
				sim.carrier() == SHOOTER, sim.puck_pos, sim.puck_vel.z)
	return {
		"outcome": outcome, "ended_at": t, "collected_at": collected_at,
		"released": not sim.releases.is_empty(),
		"released_from_z": sim.skater_pos(SHOOTER).z,
	}


func test_a_bot_collects_the_puck_drives_the_net_and_shoots() -> void:
	for difficulty: int in BotSkillProfile.Difficulty.values():
		var shot: Dictionary = _take_a_shot(BotSkillProfile.for_difficulty(difficulty))
		var tier: String = BotSkillProfile.Difficulty.keys()[difficulty]
		gut.p("%s: collected at %.2f s, ended at %.2f s (%s), released %s, from z %.1f" % [
				tier, shot.collected_at, shot.ended_at,
				PenaltyShotRules.Outcome.keys()[shot.outcome], shot.released,
				shot.released_from_z])
		assert_gt(float(shot.collected_at), 0.0, "%s: he collects the puck" % tier)
		assert_true(shot.released,
				"%s: the shot ends on his release, not on him stalling" % tier)

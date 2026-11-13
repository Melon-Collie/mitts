extends GutTest

# SpecialTeamsTally — who was on the ice for a power play, a kill, and the
# goals scored on them. Real Skater scenes, never ticked; team 1 is the one
# short throughout.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const UP_A: int = 1       # team 0, a man up
const UP_B: int = 2
const KILLER: int = 3     # team 1, on the ice
const OFFENDER: int = 4   # team 1, in the box
const SHORT: int = 1

var _registry: PlayerRegistry = null
var _tally: SpecialTeamsTally = null
var _teams: Array[Team] = []


func before_each() -> void:
	_registry = PlayerRegistry.new()
	_teams = [_make_team(0), _make_team(1)]
	_add_player(UP_A, 0)
	_add_player(UP_B, 0)
	_add_player(KILLER, 1)
	_add_player(OFFENDER, 1).skater.in_box = true
	_tally = SpecialTeamsTally.new()
	_tally.setup(_registry)


func _make_team(team_id: int) -> Team:
	var t := Team.new()
	t.team_id = team_id
	return t


func _add_player(peer_id: int, team_id: int) -> PlayerRecord:
	var record := PlayerRecord.new(peer_id, 0, false, _teams[team_id])
	record.skater = SKATER_SCENE.instantiate() as Skater
	add_child_autofree(record.skater)
	record.skater.set_physics_process(false)
	record.skater.set_process(false)
	_registry._players[peer_id] = record
	return record


func _stats(peer_id: int) -> PlayerStats:
	return _registry.get_record(peer_id).stats


func test_a_power_play_is_counted_for_the_men_on_the_ice() -> void:
	_tally.note_strength(SHORT, true)
	assert_eq([_stats(UP_A).pp_opportunities, _stats(UP_A).pk_opportunities], [1, 0])
	assert_eq([_stats(KILLER).pp_opportunities, _stats(KILLER).pk_opportunities], [0, 1])


func test_the_man_in_the_box_is_not_killing_his_own_penalty() -> void:
	_tally.note_strength(SHORT, true)
	_tally.note_power_play_goal(SHORT)
	assert_eq([_stats(OFFENDER).pk_opportunities, _stats(OFFENDER).pk_on_ice_goals_against],
			[0, 0])


func test_a_change_of_the_box_inside_one_power_play_counts_nobody_twice() -> void:
	_tally.note_strength(SHORT, true)
	_tally.note_strength(SHORT, false)
	assert_eq(_stats(UP_A).pp_opportunities, 1)
	assert_eq(_stats(KILLER).pk_opportunities, 1)


func test_a_man_stepping_out_into_a_kill_still_running_joins_it() -> void:
	_tally.note_strength(SHORT, true)
	_registry.get_record(OFFENDER).skater.in_box = false
	_tally.note_strength(SHORT, false)
	assert_eq(_stats(OFFENDER).pk_opportunities, 1)


func test_a_power_play_goal_is_for_and_against_the_men_on_the_ice() -> void:
	_tally.note_strength(SHORT, true)
	_tally.note_power_play_goal(SHORT)
	assert_eq([_stats(UP_A).pp_on_ice_goals, _stats(UP_B).pp_on_ice_goals], [1, 1])
	assert_eq(_stats(KILLER).pk_on_ice_goals_against, 1)
	assert_eq(_stats(UP_A).pk_on_ice_goals_against, 0)


func test_a_skater_who_arrived_mid_power_play_is_counted_before_its_goal() -> void:
	_tally.note_strength(SHORT, true)
	_add_player(9, 1)
	_tally.note_power_play_goal(SHORT)
	assert_eq([_stats(9).pk_opportunities, _stats(9).pk_on_ice_goals_against], [1, 1],
			"never a goal against without the kill it came on")


func test_a_player_who_rejoins_is_not_counted_twice_for_one_power_play() -> void:
	_tally.note_strength(SHORT, true)
	var stats: PlayerStats = _stats(KILLER)
	_registry._players.erase(KILLER)
	_add_player(77, 1).stats = stats
	_tally.rebind(KILLER, 77)
	_tally.note_strength(SHORT, false)
	assert_eq(stats.pk_opportunities, 1)


func test_a_new_power_play_counts_everyone_again() -> void:
	_tally.note_strength(SHORT, true)
	_tally.note_strength(-1, false)
	_tally.note_strength(SHORT, true)
	assert_eq(_stats(UP_A).pp_opportunities, 2)


func test_even_strength_counts_nothing() -> void:
	_tally.note_strength(-1, false)
	assert_eq([_stats(UP_A).pp_opportunities, _stats(KILLER).pk_opportunities], [0, 0])

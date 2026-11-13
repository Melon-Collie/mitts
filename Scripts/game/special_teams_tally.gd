class_name SpecialTeamsTally
extends RefCounted

# Host: who was on the ice for each power play and each kill, and for the
# goals scored on them (PlayerStats.pp_opportunities and its kin). A man in
# the box is on neither, so nobody is credited with killing his own penalty.

var _registry: PlayerRegistry = null
# Peers already counted for the power play running now.
var _counted: Dictionary[int, bool] = {}


func setup(registry: PlayerRegistry) -> void:
	_registry = registry


# Call on every change of the box. `began` is a new power play starting
# (GameStateMachine.set_short_handed_team). A man who steps out of the box
# into a kill still running joins it here.
func note_strength(short_handed_team_id: int, began: bool) -> void:
	if began:
		_counted.clear()
	if short_handed_team_id == -1:
		return
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if _counted.has(peer_id) or not _is_on_the_ice(record):
			continue
		_counted[peer_id] = true
		if record.team.team_id == short_handed_team_id:
			record.stats.pk_opportunities += 1
		else:
			record.stats.pp_opportunities += 1


# A player who rejoins comes back under a new peer id, and is not counted a
# second time for the power play he dropped out of.
func rebind(old_peer_id: int, new_peer_id: int) -> void:
	if _counted.erase(old_peer_id):
		_counted[new_peer_id] = true


# A goal against the shorter team, before the goal lets anyone out of the box.
func note_power_play_goal(short_handed_team_id: int) -> void:
	# A skater who joined the match since the box last changed is counted now.
	note_strength(short_handed_team_id, false)
	var players: Dictionary[int, PlayerRecord] = _registry.all()
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if not _is_on_the_ice(record):
			continue
		if record.team.team_id == short_handed_team_id:
			record.stats.pk_on_ice_goals_against += 1
		else:
			record.stats.pp_on_ice_goals += 1


static func _is_on_the_ice(record: PlayerRecord) -> bool:
	return record != null and record.stats != null and record.team != null \
			and record.skater != null and not record.skater.in_box

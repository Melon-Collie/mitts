class_name IcingRace
extends RefCounted

# Host-side hybrid icing (NHL Rule 81): who last touched the puck and where,
# whether it crossed the far goal line from behind the red line, and the race to
# the end-zone dots that decides it. The puck stays live while the race runs.
# GameStateMachine owns one, gates it on rule set and phase, and turns an ICING
# call into the pending faceoff; it calls end_race(call) once it has read it.

# Last touch: the carrier's blade, a deflection, a strip, a goalie save. -1 is
# an unknown toucher, which cannot ice.
var last_touch_team_id: int = -1
var last_touch_z: float = 0.0
var last_touch_x: float = 0.0
# The offending team while a crossed puck's race runs; -1 when none is.
var pending_team_id: int = -1
# X of the offending release — the icing faceoff is on that side.
var pending_release_x: float = 0.0
# How the last race ended — NONE when a stoppage or reset ended it uncalled.
var last_call: InfractionRules.IcingCall = InfractionRules.IcingCall.NONE
# Counts races opened, so a watcher sees one that opened and ended in one tick.
var races_opened: int = 0
var _pending_time: float = 0.0


func reset() -> void:
	last_touch_team_id = -1
	end_race()


func end_race(icing_call: InfractionRules.IcingCall = InfractionRules.IcingCall.NONE) -> void:
	if pending_team_id != -1:
		last_call = icing_call
	pending_team_id = -1
	_pending_time = 0.0


func tick(delta: float) -> void:
	if pending_team_id != -1:
		_pending_time += delta


# A touch during the race decides it: the defending team's is icing, the icing
# team's or either goalie's waves it off. Outside a race it becomes the release
# point the next crossing is judged from.
func note_touch(team_id: int, puck_z: float, puck_x: float, by_goalie: bool) -> InfractionRules.IcingCall:
	last_touch_team_id = team_id
	last_touch_z = puck_z
	last_touch_x = puck_x
	if pending_team_id == -1:
		return InfractionRules.IcingCall.NONE
	if not by_goalie and team_id != -1 and team_id != pending_team_id:
		return InfractionRules.IcingCall.ICING
	return InfractionRules.IcingCall.WAVED_OFF


# Per loose-puck tick. Opens the race when the puck crosses, then judges it from
# each team's nearest skater to the dots. `positions` / `velocities` are keyed
# by peer id; `players` maps peer id to its slot ({team_id}).
func update(puck_z: float, positions: Dictionary, velocities: Dictionary,
		players: Dictionary) -> InfractionRules.IcingCall:
	if pending_team_id == -1:
		var offender: int = InfractionRules.check_icing(last_touch_team_id, last_touch_z, puck_z)
		if offender == -1:
			return InfractionRules.IcingCall.NONE
		pending_team_id = offender
		pending_release_x = last_touch_x
		last_call = InfractionRules.IcingCall.NONE
		races_opened += 1
		_pending_time = 0.0
		last_touch_team_id = -1
	if _pending_time >= GameRules.ICING_RACE_MAX_S:
		return InfractionRules.IcingCall.ICING
	var icing_eta: float = INF
	var defending_eta: float = INF
	var racing: bool = false
	for peer_id: int in positions:
		if not players.has(peer_id):
			continue
		var z: float = positions[peer_id].z
		var vz: float = velocities[peer_id].z if velocities.has(peer_id) else 0.0
		var eta: float = InfractionRules.time_to_icing_dot_line(z, vz, pending_team_id)
		if players[peer_id].team_id == pending_team_id:
			icing_eta = minf(icing_eta, eta)
			racing = racing or InfractionRules.is_racing_icing(z, vz, pending_team_id)
		else:
			defending_eta = minf(defending_eta, eta)
	if not racing:
		return InfractionRules.IcingCall.ICING
	return InfractionRules.judge_icing_race(icing_eta, defending_eta)

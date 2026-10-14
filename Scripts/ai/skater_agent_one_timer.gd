class_name SkaterAgentOneTimer
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# A ready finisher's one-timer reads: where the body settles so the wound-up
# slapper zone sits on the feed's live line, where that zone is, whether the feed
# has reached it, how long the feed has left, and whether the stance is square
# enough to press. Reads only: the state machine's ONE_TIMER_PRESSED steers,
# presses and fires on them.

# How square to the shot line the stance must ALREADY be for the one-timer
# wind-up to start. Not the blade-reach cone (~132°):
# SkaterController._enter_slapper_charge SNAPS facing to the aim at the press, so
# a wide stance whips the body in one tick. A wide stance holds with the cursor on
# the net while facing rotates in; one that can't square within the state
# machine's aim-wait backstop bails to a catch. Feel: widen if bots pass up
# one-timers, tighten if the wind-up reads as a body-whip.
const ONE_TIMER_SQUARE_UP_MAX_RAD: float = deg_to_rad(45.0)

# Cap on the feed-arrival lookahead the one-timer aim reads the goalie at —
# past this the feed is a long cross-ice saucer and the prediction is noise.
const ONE_TIMER_FEED_LOOKAHEAD_MAX_S: float = 1.2

# The slapper one-timer pickup ZONE's offset in the skater's local frame (+X =
# blade side, −Z = in front), SkaterController.slapper_zone_offset_x / _z's
# (test_bot_mirrors.gd). The wound-up blade is raised, so the ZONE makes the catch: the one-timer
# settle places THIS point on the feed's live line.
const BOT_ONE_TIMER_ZONE_OFFSET_X_M: float = 1.0
const BOT_ONE_TIMER_ZONE_OFFSET_Z_M: float = -0.4

# Release radius (m) around the slapper zone centre for the wound-up one-timer.
# Inside SkaterController.slapper_zone_radius (test_bot_mirrors.gd) so a clean feed
# attaches first and fires the with-puck release; this only catches a puck that
# slips through without attaching.
const ONE_TIMER_RELEASE_RADIUS_M: float = 0.4

# One tick of puck travel: the release reads where the puck will be when the
# input lands.
const TICK_DELTA_S: float = 1.0 / _PhysicsConstants.PHYSICS_TICK

var _peer_id: int = -1
var _team_id: int = -1
var _team_id_by_peer: Dictionary = {}
var _is_left_handed: bool = false


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		is_left_handed: bool) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_is_left_handed = is_left_handed


# True when the one-timer's committed aim can fire from the current STANCE: the
# body is already square to the shot line within ONE_TIMER_SQUARE_UP_MAX_RAD, and
# (belt-and-braces for an unusually narrow build) within `reach_gate_rad` — the
# blade reach cone less the commit margin. Unreadable facing (degenerate state)
# never blocks: missing data must not starve the wind-up.
func aim_settled(snapshot: WorldSnapshot, self_pos: Vector3, aim: Vector3,
		reach_gate_rad: float) -> bool:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null or self_state.facing.length_squared() < 0.0001:
		return true
	var aim_dir := Vector2(aim.x - self_pos.x, aim.z - self_pos.z)
	if aim_dir.length_squared() < 0.0001:
		return false
	var gate: float = minf(ONE_TIMER_SQUARE_UP_MAX_RAD, reach_gate_rad)
	return absf(self_state.facing.angle_to(aim_dir)) <= gate


# Remaining feed-flight time: the distance along the puck's live line to my
# perpendicular foot, over its current speed (the same geometry as line_anchor).
# 0 when there's no readable live feed — a dead or held puck reads as "arriving
# now", so the aim falls back to the goalie as he stands.
static func feed_time_s(snapshot: WorldSnapshot, self_pos: Vector3) -> float:
	if snapshot.puck_state == null:
		return 0.0
	var pv: Vector3 = snapshot.puck_state.velocity
	var speed_sq: float = pv.x * pv.x + pv.z * pv.z
	var trigger: float = SkaterAgentReception.RECEIVE_TRIGGER_PUCK_SPEED_M_S
	if speed_sq < trigger * trigger:
		return 0.0
	var speed: float = sqrt(speed_sq)
	var puck_pos: Vector3 = snapshot.puck_state.position
	var along: float = Vector3(
			self_pos.x - puck_pos.x, 0.0, self_pos.z - puck_pos.z) \
			.dot(Vector3(pv.x / speed, 0.0, pv.z / speed))
	return clampf(along / speed, 0.0, ONE_TIMER_FEED_LOOKAHEAD_MAX_S)


# The LIVE-line body anchor for a one-timer reception: the body spot that puts
# the slapper pickup ZONE (BOT_ONE_TIMER_ZONE_OFFSET_*) on the incoming feed's
# live line, re-derived every call so the shooter micro-shuffles onto the pass's
# actual line — one-timer footwork. Body = perp foot of self on the line minus
# the zone offset in the net-facing frame.
#
# INF when there is no live inbound feed to settle on: puck held (the REAL
# carrier), too slow, already past our level, outside the reception band, or a
# teammate better positioned for it. Same trigger constants as the rest of the
# reception family (SkaterAgentReception).
func line_anchor(snapshot: WorldSnapshot, self_pos: Vector3,
		attacking_goal: Vector3) -> Vector3:
	if snapshot.puck_state == null or snapshot.real_puck_carrier_peer_id != -1:
		return Vector3.INF
	var pv: Vector3 = snapshot.puck_state.velocity
	var speed_sq: float = pv.x * pv.x + pv.z * pv.z
	var trigger: float = SkaterAgentReception.RECEIVE_TRIGGER_PUCK_SPEED_M_S
	if speed_sq < trigger * trigger:
		return Vector3.INF
	var speed: float = sqrt(speed_sq)
	var dir := Vector3(pv.x / speed, 0.0, pv.z / speed)
	var puck_pos: Vector3 = snapshot.puck_state.position
	var to_self := Vector3(self_pos.x - puck_pos.x, 0.0, self_pos.z - puck_pos.z)
	var t: float = to_self.dot(dir)
	if t <= 0.0:
		return Vector3.INF
	var perp_foot := Vector3(puck_pos.x + dir.x * t, 0.0, puck_pos.z + dir.z * t)
	var perp_dx: float = self_pos.x - perp_foot.x
	var perp_dz: float = self_pos.z - perp_foot.z
	var my_d2: float = perp_dx * perp_dx + perp_dz * perp_dz
	var lateral: float = SkaterAgentReception.RECEIVE_TRIGGER_LATERAL_M
	if my_d2 > lateral * lateral:
		return Vector3.INF
	# Best-positioned-receiver filter, as in SkaterAgentReception.incoming_pass.
	for pid: int in snapshot.skater_states:
		if pid == _peer_id or _team_id_by_peer.get(pid, -1) != _team_id:
			continue
		var tp: Vector3 = snapshot.skater_states[pid].position
		var dx: float = tp.x - perp_foot.x
		var dz: float = tp.z - perp_foot.z
		if dx * dx + dz * dz < my_d2:
			return Vector3.INF
	var to_net: Vector3 = attacking_goal - perp_foot
	to_net.y = 0.0
	var net_len: float = to_net.length()
	if net_len < 0.001:
		return Vector3.INF
	return perp_foot - _zone_offset(to_net / net_len)


# The bot's slapper pickup-zone CENTRE in world space — self plus the zone offset
# in the net-facing frame (the mirror of line_anchor: body = perp_foot −
# zone_offset, so zone centre = self + zone_offset). The centre-timing bonus is
# graded by how close the puck is to THIS point at release.
func zone_center(self_pos: Vector3, attacking_goal: Vector3) -> Vector3:
	var to_net: Vector3 = attacking_goal - self_pos
	to_net.y = 0.0
	var net_len: float = to_net.length()
	if net_len < 0.001:
		return self_pos
	return self_pos + _zone_offset(to_net / net_len)


# Release trigger for a wound-up one-timer: is the puck (projected one tick) AT
# the slapper zone centre? Fires on the CENTRE beat; releasing at blade reach is
# far too early (the −10% end of the centre-timing bonus, and slower feeds
# whiff). A salvage for a puck that slips through without attaching (see
# ONE_TIMER_RELEASE_RADIUS_M).
func puck_at_zone(snapshot: WorldSnapshot, self_pos: Vector3,
		attacking_goal: Vector3) -> bool:
	if snapshot.puck_state == null or snapshot.real_puck_carrier_peer_id != -1:
		return false
	var center: Vector3 = zone_center(self_pos, attacking_goal)
	var pv: Vector3 = snapshot.puck_state.velocity
	var pp: Vector3 = snapshot.puck_state.position
	var dx: float = (pp.x + pv.x * TICK_DELTA_S) - center.x
	var dz: float = (pp.z + pv.z * TICK_DELTA_S) - center.z
	return dx * dx + dz * dz <= ONE_TIMER_RELEASE_RADIUS_M * ONE_TIMER_RELEASE_RADIUS_M


# The zone offset in the frame facing along the unit `net_dir`, on the blade side.
func _zone_offset(net_dir: Vector3) -> Vector3:
	var right := Vector3(-net_dir.z, 0.0, net_dir.x)
	var side: float = -1.0 if _is_left_handed else 1.0
	return right * (side * BOT_ONE_TIMER_ZONE_OFFSET_X_M) \
			- net_dir * BOT_ONE_TIMER_ZONE_OFFSET_Z_M

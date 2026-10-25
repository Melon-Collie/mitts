class_name SkaterAgentOneTimer
extends RefCounted

const _PhysicsConstants: GDScript = preload("res://Scripts/game/constants.gd")

# A ready finisher's one-timer reads: where the body settles so the wound-up
# slapper zone sits on the feed's live line, where that zone is, whether the feed
# has reached it, how long the feed has left, how long the body takes to set for
# it, and the swing that lands the shot where it is aimed. Reads only: the state
# machine's ONE_TIMER_PRESSED steers, presses and fires on them.

# Within this of its anchor the shuffle has put the circle on the line.
const ONE_TIMER_SHUFFLE_ARRIVE_M: float = SlapperRules.SET_ARRIVE_M
# The shuffle eases off over its last step, as a step-together closes: the
# stick is full until the anchor is this many seconds of shuffle away.
const ONE_TIMER_SHUFFLE_EASE_S: float = 0.15

# Cap on the feed-arrival lookahead the one-timer aim reads the goalie at —
# past this the feed is a long cross-ice saucer and the prediction is noise.
const ONE_TIMER_FEED_LOOKAHEAD_MAX_S: float = 1.2


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
# The body's strike spot (x toward the stick side) and stance opening — the
# slapper pickup ZONE is centred there, and the wound-up blade is raised, so the
# ZONE makes the catch: the one-timer settle places it on the feed's live line.
var _strike_local: Vector2 = AISkaterCaps.new().slapper_strike_local
var _stance_open_rad: float = PI * 0.5
var _caps: AISkaterCaps = AISkaterCaps.new()


func setup(peer_id: int, team_id: int, team_id_by_peer: Dictionary,
		is_left_handed: bool) -> void:
	_peer_id = peer_id
	_team_id = team_id
	_team_id_by_peer = team_id_by_peer
	_is_left_handed = is_left_handed


# This body's slapshot, off its caps: the stance (AISkaterCaps.slapper_strike_local),
# its pivot, its power over the charge and the face's grip on a feed.
func set_caps(caps: AISkaterCaps) -> void:
	_caps = caps
	_strike_local = caps.slapper_strike_local
	_stance_open_rad = caps.slapper_stance_open_rad


# Seconds this body takes, wound up now, to set for a shot along `shot_dir`
# (unit, world XZ) with its circle on `anchor` (INF: wherever it is) for a feed
# arriving in `feed_s` (SlapperRules.time_to_set).
func time_to_set(snapshot: WorldSnapshot, self_pos: Vector3, shot_dir: Vector2,
		anchor: Vector3, feed_s: float) -> float:
	var self_state: SkaterNetworkState = snapshot.skater_states.get(_peer_id)
	if self_state == null:
		return 0.0
	var to_anchor := Vector2(INF, INF)
	if anchor.is_finite():
		to_anchor = Vector2(anchor.x - self_pos.x, anchor.z - self_pos.z)
	return SlapperRules.time_to_set(self_state.facing,
			Vector2(self_state.velocity.x, self_state.velocity.z), to_anchor, shot_dir, feed_s,
			_side(), _stance_open_rad, _caps.slapper_stance_turn_rad_s,
			_caps.movement.shuffle_speed)


# The shuffle onto `anchor` once wound up (world XZ stick, under the brake), or
# ZERO once there.
func shuffle_stick(self_pos: Vector3, anchor: Vector3) -> Vector2:
	if not anchor.is_finite():
		return Vector2.ZERO
	var off := Vector2(anchor.x - self_pos.x, anchor.z - self_pos.z)
	var d: float = off.length()
	if d <= ONE_TIMER_SHUFFLE_ARRIVE_M:
		return Vector2.ZERO
	var ease_m: float = _caps.movement.shuffle_speed * ONE_TIMER_SHUFFLE_EASE_S
	return off / d * clampf(d / maxf(ease_m, 0.001), 0.0, 1.0)


# The wind-up a feed must find built for the one-timer's window to open.
func min_windup_s() -> float:
	return _caps.one_timer_min_windup_s


# The slapshot's power after `charge_s` of wind-up (ShotMechanics.release_slapper).
func power_after(charge_s: float) -> float:
	var t: float = sqrt(clampf(charge_s / maxf(_caps.slapper_max_charge_s, 0.001), 0.0, 1.0))
	return lerpf(_caps.slapper_power_min, _caps.slapper_power_max, t)


# The swing line (unit, world XZ) that sends a one-timer off `feed` (the puck's
# velocity in this body's frame) along `target`, swung at `power`: the face
# pulls the shot toward the feed's cross speed, so the swing leads against it
# (SlapperRules.aim_for_contact, at the blade's restitution as the controller
# reads it).
func swing_for(target: Vector2, feed: Vector2, power: float) -> Vector2:
	var e: float = SlapperRules.swing_restitution(power,
			AIFeedReception.DEFLECT_NORMAL_RESTITUTION,
			AIFeedReception.DEFLECT_NORMAL_RESTITUTION_MIN,
			AIFeedReception.DEFLECT_SPEED_REF_M_S)
	return SlapperRules.aim_for_contact(target, power, feed, e, _caps.one_timer_feed_grip)


# The hips' facing for a slapshot along the unit `shot_dir` (world XZ).
func stance_facing(shot_dir: Vector2) -> Vector2:
	return SlapperRules.stance_facing(shot_dir, _side(), _stance_open_rad)


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


# The LIVE-line body anchor for a one-timer reception: the nearest body spot
# that puts the slapper pickup ZONE (the strike spot) on the incoming feed's
# live line, re-derived every call so the shooter steps onto the pass's actual
# line — one-timer footwork. The body moves straight across the line by the
# zone's own miss of it, in the stance set for the net from there: the zone can
# meet the puck anywhere along its line.
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
	var zone: Vector3 = self_pos + _zone_offset(to_net / net_len)
	var zone_along: float = Vector3(zone.x - puck_pos.x, 0.0, zone.z - puck_pos.z).dot(dir)
	var zone_foot := Vector3(puck_pos.x + dir.x * zone_along, 0.0, puck_pos.z + dir.z * zone_along)
	return Vector3(self_pos.x + zone_foot.x - zone.x, 0.0, self_pos.z + zone_foot.z - zone.z)


# The bot's slapper pickup-zone CENTRE in world space — self plus the zone offset
# in the stance set for the net (the mirror of line_anchor: body = perp_foot −
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


# The zone's offset off the body once its hips have set for a shot along the
# unit `net_dir`.
func _zone_offset(net_dir: Vector3) -> Vector3:
	var off: Vector2 = SlapperRules.strike_offset(Vector2(net_dir.x, net_dir.z),
			Vector2(_strike_local.x * _side(), _strike_local.y), _side(), _stance_open_rad)
	return Vector3(off.x, 0.0, off.y)


func _side() -> float:
	return -1.0 if _is_left_handed else 1.0

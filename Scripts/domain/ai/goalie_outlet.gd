class_name GoalieOutlet
extends RefCounted

# The goalie's release once he has the puck on his stick: a pass to a teammate,
# or a clear out of the zone. Every option is priced in the currency the
# carrier's turnover model already uses — AIActionScoring.threat_surface_shoot
# at an exchange rate of 1:
#
#   value = P(keep) · threat(keep spot → their net)
#         − P(lose) · threat(loss spot → our net)
#
# so "don't give it away in front of your own net" falls out of where the loss
# would happen, with no zone flag and no aversion weight. A pass keeps the puck
# with its completion probability and loses it where the lane would be cut.
#
# A clear is a pure CONCESSION, as the carrier's own clear is (see
# AIActionScoring.dump_clear_candidates): it loses the puck where it lands unless
# we win the race there, and earns nothing for the race it wins. Paying it the
# keep term makes a clear we are certain to recover outscore every outlet pass on
# an open rink, because its landing is deeper than any receiver.
#
# What he perceives is the tier's business, not the evaluator's: a goalie who
# `reads_motion` prices the forecheckers' velocities, one who does not reads
# every body as stationary (the perception gate in Scripts/domain/ai/CLAUDE.md).
#
# Engine-free. Fills caller-owned scratch; `evaluate` allocates only inside
# AIPassLead.lead (one small Array per teammate per call), so callers throttle.

enum Kind { NONE, PASS, CLEAR }

class Choice:
	var kind: int = Kind.NONE
	# Where the release aims. A pass aims at the receiver's lead point; a clear at
	# a point along its bearing (the quick release aims blade → target).
	var target: Vector3 = Vector3.ZERO
	var launch_speed: float = 0.0
	var elevation: int = ShotMechanics.ELEVATION_FLAT
	var value: float = -INF

	func clear() -> void:
		kind = Kind.NONE
		target = Vector3.ZERO
		launch_speed = 0.0
		elevation = ShotMechanics.ELEVATION_FLAT
		value = -INF

	func copy_from(o: Choice) -> void:
		kind = o.kind
		target = o.target
		launch_speed = o.launch_speed
		elevation = o.elevation
		value = o.value


# He can only release into the half-plane he faces: a puck on the blade in front
# of his pads cannot leave backwards through them.
const MIN_FORWARD_DOT: float = 0.0
# How far along a clear's bearing its aim point sits. Direction only — the quick
# release's pace is fixed, so any distance names the same release.
const CLEAR_AIM_M: float = 10.0
# The straight leg a clear flies before the boards can turn it — what the net
# test checks the release against.
const CLEAR_NET_CHECK_M: float = 15.0
const NET_HALF_WIDTH_M: float = GameRules.NET_HALF_WIDTH

var best: Choice = Choice.new()
# The best PASS alone (kind NONE when no pass exists) — the caller's "is there a
# pass worth making now" read, separate from the overall argmax.
var best_pass: Choice = Choice.new()

var _candidate: Choice = Choice.new()
var _receiver: SkaterNetworkState = SkaterNetworkState.new()
var _teammates: Array[Vector3] = []
var _teammate_vels: Array[Vector3] = []
var _opponents: Array[Vector3] = []
var _opponent_vels: Array[Vector3] = []
var _clear_vels: Array[Vector3] = []
var _clear_spots: Array[Vector3] = []


# `facing` is his flat forward. `our_net` / `their_net` are goal-mouth centres.
# The position arrays are index-matched to their velocity arrays.
func evaluate(origin: Vector3, facing: Vector3, our_net: Vector3,
		their_net: Vector3, teammates: PackedVector3Array,
		teammate_vels: PackedVector3Array, opponents: PackedVector3Array,
		opponent_vels: PackedVector3Array, reads_motion: bool) -> void:
	best.clear()
	best_pass.clear()
	_fill(_teammates, teammates)
	_fill(_teammate_vels, teammate_vels)
	_fill(_opponents, opponents)
	_opponent_vels.clear()
	if reads_motion:
		_fill(_opponent_vels, opponent_vels)
	var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
	for i: int in _teammates.size():
		if _price_pass(origin, flat_facing, our_net, their_net, i):
			_offer(_candidate)
	var up_ice: float = signf(their_net.z - our_net.z)
	var n: int = AIActionScoring.dump_clear_candidates(
			origin, up_ice, AIActionScoring.PASS_SPEED_M_S,
			ShotMechanics.ELEVATION_HIGH, our_net, _clear_vels, _clear_spots)
	for i: int in n:
		if _price_clear(origin, flat_facing, our_net, i):
			_offer(_candidate)


func _offer(c: Choice) -> void:
	if c.value > best.value:
		best.copy_from(c)
	if c.kind == Kind.PASS and c.value > best_pass.value:
		best_pass.copy_from(c)


func _price_pass(origin: Vector3, facing: Vector3, our_net: Vector3,
		their_net: Vector3, i: int) -> bool:
	var receiver: Vector3 = _teammates[i]
	var rvel: Vector3 = _teammate_vels[i] if i < _teammate_vels.size() else Vector3.ZERO
	var to_r := Vector3(receiver.x - origin.x, 0.0, receiver.z - origin.z)
	var dist: float = to_r.length()
	if dist < 0.01:
		return false
	var dir: Vector3 = to_r / dist
	var launch: float = AIActionScoring.pass_launch_speed(dist,
			GameRules.DEFAULT_WRISTER_POWER_MAX_M_S, 1.0, rvel, dir)
	_receiver.position = receiver
	_receiver.velocity = rvel
	var lead: Vector3 = AIPassLead.lead(origin, _receiver, Vector3.ZERO, launch,
			AIRoleCarrier.PASS_LEAD_MAX_S)[0]
	lead.y = 0.0
	var aim := Vector3(lead.x - origin.x, 0.0, lead.z - origin.z)
	if aim.length_squared() < 0.0001 or aim.normalized().dot(facing) < MIN_FORWARD_DOT:
		return false
	if AIActionScoring.pass_lane_blocked_by_net(origin, lead):
		return false
	var lane: float = AIActionScoring.lane_clear(origin, lead, _opponents, launch,
			_opponent_vels, AIActionScoring.EMPTY_CAPS, true)
	var miss: float = AIActionScoring.pass_miss_prob(aim.length(), 0.0)
	var p_keep: float = lane * (1.0 - miss)
	var loss: Vector3 = AIActionScoring.lane_loss_point(origin, lead, _opponents,
			launch, _opponent_vels)
	if not loss.is_finite():
		loss = AIActionScoring.pass_miss_loss_point(origin, lead)
	_candidate.kind = Kind.PASS
	_candidate.target = lead
	_candidate.launch_speed = launch
	_candidate.elevation = ShotMechanics.ELEVATION_FLAT
	_candidate.value = p_keep * _threat(lead, their_net, their_net, _opponents) \
			- (1.0 - p_keep) * _threat(loss, our_net, origin, _teammates)
	return true


func _price_clear(origin: Vector3, facing: Vector3, our_net: Vector3,
		i: int) -> bool:
	var dir := Vector3(_clear_vels[i].x, 0.0, _clear_vels[i].z).normalized()
	if dir.dot(facing) < MIN_FORWARD_DOT:
		return false
	if AIActionScoring.pass_lane_blocked_by_net(origin, origin + dir * CLEAR_NET_CHECK_M):
		return false
	var spot: Vector3 = _clear_spots[i]
	var p_keep: float = AIActionScoring.chase_recovery(spot, _teammates, _opponents,
			_teammate_vels, _opponent_vels)
	_candidate.kind = Kind.CLEAR
	_candidate.target = origin + dir * CLEAR_AIM_M
	_candidate.launch_speed = AIActionScoring.PASS_SPEED_M_S
	_candidate.elevation = ShotMechanics.ELEVATION_HIGH
	_candidate.value = -(1.0 - p_keep) * _threat(spot, our_net, origin, _teammates)
	return true


# The value of having the puck at `spot`, against `net` guarded by `keeper` and
# `defenders`. For a loss, `keeper` is where HE is — out playing the puck, the
# threat a turnover concedes is priced against an empty net.
static func _threat(spot: Vector3, net: Vector3, keeper: Vector3,
		defenders: Array[Vector3]) -> float:
	return AIActionScoring.threat_surface_shoot(spot, net, keeper, NET_HALF_WIDTH_M,
			defenders)


static func _fill(dst: Array[Vector3], src: PackedVector3Array) -> void:
	dst.resize(src.size())
	for i: int in src.size():
		dst[i] = src[i]

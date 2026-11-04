class_name SkaterPoseBridge
extends RefCounted

# Eases the stick across a change of who poses it. The tracked IK, the slapper's
# wind-up, the follow-throughs and the shot block each place the hand and blade
# from their own authored geometry, and none of them starts where the last one
# left off, so a change of owner moved the stick up to 1.8 m in a tick. On a
# change, the stick the last tick drew is held and the new owner's pose eased in
# from it.
#
# Runs on live ticks only (SkaterController._process_input): reconcile restores
# the shot state around a replay and treats the live tick as the truth, and a
# bridge advanced through a replay would play its ease twice. Its effect rides
# the hand and blade the wire already carries.

enum Owner { TRACKED, SLAPPER, FOLLOW_THROUGH, BLOCK }

const State = SkaterStateMachine.State

# Seconds a change of owner eases over. The follow-through's is short: it is the
# shot's own whip, and the bridge only has to keep it from teleporting.
const SPAN_S: float = 0.15
const FOLLOW_THROUGH_SPAN_S: float = 0.05

var _owner: Owner = Owner.TRACKED
# The stick as last drawn: world offsets from the skater's position.
var _last_hand := Vector3.ZERO
var _last_blade := Vector3.ZERO
var _have_last: bool = false
var _from_hand := Vector3.ZERO
var _from_blade := Vector3.ZERO
var _age: float = 0.0
var _span: float = 0.0
# The span the next change of owner eases over instead of its usual one (0: the
# usual); see ease_next_change.
var _next_span: float = 0.0


# `slapper_set`: false while a slapshot's set-up still has the tracked blade
# taking the puck to the strike spot; the wind-up owns the stick from there.
# `slap_finish`: a follow-through that is a slapper's, whose downswing starts
# from the pose its wind-up ended on — one owner, so nothing holds the stick
# while the shoulders come through.
static func owner_of(state: State, slapper_set: bool = true, slap_finish: bool = false) -> Owner:
	match state:
		State.SLAPPER_CHARGE_WITH_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK, \
				State.ONE_TIMER_RETENTION:
			return Owner.SLAPPER if slapper_set else Owner.TRACKED
		State.FOLLOW_THROUGH:
			return Owner.SLAPPER if slap_finish else Owner.FOLLOW_THROUGH
		State.SHOT_BLOCKING:
			return Owner.BLOCK
	return Owner.TRACKED


# The next change of owner eases over `span` seconds: a stick brought down out of
# a called-off slapshot takes as long as its recovery, not a hand-off's blink.
func ease_next_change(span: float) -> void:
	_next_span = span


# After the tick's last write to the hand and blade: start an ease if the owner
# changed, lay it on, and remember what was drawn.
func settle(skater: Skater, state: State, delta: float, slapper_set: bool = true,
		slap_finish: bool = false) -> void:
	var owner: Owner = owner_of(state, slapper_set, slap_finish)
	if owner != _owner and _have_last:
		_from_hand = _last_hand
		_from_blade = _last_blade
		_age = 0.0
		_span = FOLLOW_THROUGH_SPAN_S if owner == Owner.FOLLOW_THROUGH else SPAN_S
		if _next_span > 0.0:
			_span = _next_span
	_next_span = 0.0
	_owner = owner
	if _span > 0.0:
		var held: float = 1.0 - smoothstep(0.0, _span, _age)
		var at: Vector3 = skater.global_position
		var hand: Vector3 = skater.get_top_hand_position()
		var blade: Vector3 = skater.get_blade_position()
		skater.set_top_hand_position(hand.lerp(skater.upper_body_to_local(at + _from_hand), held))
		skater.set_blade_position(blade.lerp(skater.upper_body_to_local(at + _from_blade), held))
		_age += delta
		if _age >= _span:
			_span = 0.0
	var origin: Vector3 = skater.global_position
	_last_hand = skater.upper_body_to_global(skater.get_top_hand_position()) - origin
	_last_blade = skater.upper_body_to_global(skater.get_blade_position()) - origin
	_have_last = true

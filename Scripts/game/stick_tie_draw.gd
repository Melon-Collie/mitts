class_name StickTieDraw
extends RefCounted

# Render-rate, every peer: draws tied sticks meeting, and clacks when a tie
# starts or ends. Every screen sees two tied sticks a little differently (each
# player's own is predicted, the other interpolated), and the host holds a tie up
# to StickCheckRules.TIE_SEPARATION_M apart, so the drawn blades are bent onto
# one meeting point — a mesh-only slide (Skater.set_tie_draw_offset), never the
# gameplay Blade marker.
#
# The pairs are derived, not replicated: each tied skater's partner is the tied
# opponent whose stick is nearest. Two ties close enough to confuse that would
# need a partner slot on the wire.

# A latch and a break land at different weights: the catch is the louder one.
const _LATCH_GAIN_DB: float = 0.0
const _BREAK_GAIN_DB: float = -4.0
# One clack per pair: an edge this close to one already played this frame is
# the same pair's other stick.
const _SAME_PAIR_M: float = 1.5

var _was_tied: Dictionary = {}           # Skater -> bool, written only on change
var _played_this_frame: Array[Vector3] = []


func update(skaters: Array[Skater], team_of: Dictionary) -> void:
	_played_this_frame.clear()
	for s: Skater in skaters:
		if not is_instance_valid(s):
			continue
		var partner: Skater = _partner(s, skaters, team_of) if s.stick_tied else null
		s.set_tie_draw_offset(_meeting_offset(s, partner) if partner != null else Vector3.ZERO)
		var was: bool = _was_tied.get(s, false)
		if was != s.stick_tied:
			_was_tied[s] = s.stick_tied
			_clack(s.get_blade_contact_global(), s.stick_tied)


func _partner(s: Skater, skaters: Array[Skater], team_of: Dictionary) -> Skater:
	var best: Skater = null
	var best_d: float = INF
	var team: int = team_of.get(s, -1)
	for o: Skater in skaters:
		if o == s or not is_instance_valid(o) or not o.stick_tied or team_of.get(o, -1) == team:
			continue
		var d: float = StickCheckRules.stick_gap(_hand(s), s.get_blade_contact_global(),
				_hand(o), o.get_blade_contact_global())
		if d < best_d:
			best_d = d
			best = o
	return best


# World XZ offset from this stick's nearest point on the partner's stick to the
# midpoint between them: half the gap, so the two meet in the middle.
func _meeting_offset(s: Skater, o: Skater) -> Vector3:
	var a0: Vector2 = _xz(_hand(s))
	var a1: Vector2 = _xz(s.get_blade_contact_global())
	var b0: Vector2 = _xz(_hand(o))
	var b1: Vector2 = _xz(o.get_blade_contact_global())
	if StickCheckRules.stick_gap(_hand(s), s.get_blade_contact_global(),
			_hand(o), o.get_blade_contact_global()) <= 0.0:
		return Vector3.ZERO  # already crossing: they meet where they cross
	# Apart, the nearest pair of points has an endpoint of one segment in it.
	var best: float = INF
	var pa := Vector2.ZERO
	var pb := Vector2.ZERO
	for i: int in 4:
		var p: Vector2 = _endpoint(i, a0, a1, b0, b1)
		var on_a: bool = i >= 2
		var q: Vector2 = _closest_on(p, a0, a1) if on_a else _closest_on(p, b0, b1)
		var d: float = p.distance_squared_to(q)
		if d < best:
			best = d
			pa = q if on_a else p
			pb = p if on_a else q
	var half: Vector2 = (pb - pa) * 0.5
	return Vector3(half.x, 0.0, half.y)


static func _endpoint(i: int, a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Vector2:
	match i:
		0:
			return a0
		1:
			return a1
		2:
			return b0
	return b1


static func _closest_on(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	var t: float = 0.0 if len_sq < 1e-10 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t


func _clack(at: Vector3, latched: bool) -> void:
	for p: Vector3 in _played_this_frame:
		if p.distance_to(at) < _SAME_PAIR_M:
			return
	_played_this_frame.append(at)
	SoundManager.play_world(SoundManager.Sound.STICK_LIFT, at,
			_LATCH_GAIN_DB if latched else _BREAK_GAIN_DB, 0.06)


static func _hand(s: Skater) -> Vector3:
	return s.upper_body_to_global(s.get_top_hand_position())


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

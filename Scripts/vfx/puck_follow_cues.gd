class_name PuckFollowCues
extends RefCounted

# The on-ice puck-following cues, as state: the carrier's thickened ring, the
# pulse that marks a change of possession, and the halo round a loose puck.
# IceRingField feeds it once per rendered frame and hands its outputs to the
# ice shader. Pure — no node, no tree — so the whole timeline is testable from
# a sequence of step() calls.
#
# Every output is written here and only read outside (Scripts/controllers/
# CLAUDE.md → *What kills a collaborator extraction*).

# The carrier's ring is drawn as a bold band rather than a second ring outside
# it: the name plate and the elevation chevrons sit just outside the slot ring
# (SkaterHUDCoordinator._NAME_RADIUS), so anything drawn there collides with
# them. Thickening inward has the ring to itself.
const CARRIER_RING_INNER_R: float = SkaterHUDCoordinator.RING_OUTER_R \
		- MenuStyle.HUD_LINE_THIN * 5.0
const CARRIER_EASE_IN_S: float = 0.12

# A fumble and regain by the same skater is not a change of possession. Loose
# this long, it is: the pulse then marks a puck won back off the boards.
const LAST_CARRIER_MEMORY_S: float = 1.0

# The pulse: a ring that leaves the new carrier's slot ring and fades as it
# grows. A turnover is the bigger, slower, heavier one; both take the new
# carrier's ring color, so from your seat a turnover also changes color group
# (ally to enemy or back).
const PULSE_START_R: float = SkaterHUDCoordinator.RING_OUTER_R
const PASS_PULSE_END_R: float = 1.4
const PASS_PULSE_S: float = 0.45
const PASS_PULSE_STROKE: float = MenuStyle.HUD_LINE_THIN * 2.0
const TURNOVER_PULSE_END_R: float = 2.4
const TURNOVER_PULSE_S: float = 0.65
const TURNOVER_PULSE_STROKE: float = MenuStyle.HUD_LINE_THIN * 3.5

# Round the loose puck: well outside the puck shadow's grounded blob
# (PuckShadow.BASE_RADIUS) so the two read as separate marks, and small enough
# not to swallow a stick in a scrum.
const LOOSE_HALO_OUTER_R: float = 0.26
const LOOSE_HALO_INNER_R: float = LOOSE_HALO_OUTER_R - MenuStyle.HUD_LINE_THIN * 1.5
const LOOSE_FADE_IN_S: float = 0.15

const NO_CARRIER: int = 0
const NO_TEAM: int = -1

# ── Outputs ───────────────────────────────────────────────────────────────────
# Instance id of the skater drawn carrying, NO_CARRIER while loose.
var carrier_id: int = NO_CARRIER
# 0..1: how far the carrier's ring has thickened toward CARRIER_RING_INNER_R.
var carrier_weight: float = 0.0
var pulse_active: bool = false
var pulse_center: Vector2 = Vector2.ZERO
var pulse_outer_r: float = 0.0
var pulse_inner_r: float = 0.0
# sRGB; alpha is the pulse's opacity this frame, already faded.
var pulse_color: Color = Color(0.0, 0.0, 0.0, 0.0)
# 0..1 opacity scale on the loose-puck halo; 0 hides it.
var loose_weight: float = 0.0

# ── Own state ─────────────────────────────────────────────────────────────────
var _last_carrier_id: int = NO_CARRIER
var _last_team: int = NO_TEAM
var _loose_s: float = 0.0
var _pulse_owner_id: int = NO_CARRIER
var _pulse_age_s: float = 0.0
var _pulse_duration_s: float = 0.0
var _pulse_end_r: float = 0.0
var _pulse_stroke: float = 0.0
var _pulse_base_color: Color = Color(0.0, 0.0, 0.0, 0.0)


func reset() -> void:
	carrier_id = NO_CARRIER
	carrier_weight = 0.0
	pulse_active = false
	pulse_color.a = 0.0
	loose_weight = 0.0
	_last_carrier_id = NO_CARRIER
	_last_team = NO_TEAM
	_loose_s = 0.0
	_pulse_owner_id = NO_CARRIER


# new_carrier_id: instance id of the skater this peer draws carrying, or
# NO_CARRIER. carrier_team: their team, NO_TEAM when unknown. carrier_xz and
# carrier_color: where their ring is drawn and its sRGB color.
# puck_loose_shown: whether a loose puck is on the ice to be haloed (in play,
# not held for a drop).
func step(delta: float, new_carrier_id: int, carrier_team: int, carrier_xz: Vector2,
		carrier_color: Color, puck_loose_shown: bool) -> void:
	if new_carrier_id == NO_CARRIER:
		_step_loose(delta, puck_loose_shown)
	else:
		_step_carried(delta, new_carrier_id, carrier_team, carrier_xz, carrier_color)
	_step_pulse(delta)


func _step_loose(delta: float, puck_loose_shown: bool) -> void:
	carrier_id = NO_CARRIER
	carrier_weight = 0.0
	_loose_s += delta
	if _loose_s >= LAST_CARRIER_MEMORY_S:
		_last_carrier_id = NO_CARRIER
	if puck_loose_shown:
		loose_weight = minf(loose_weight + delta / LOOSE_FADE_IN_S, 1.0)
	else:
		loose_weight = 0.0


func _step_carried(delta: float, new_carrier_id: int, carrier_team: int,
		carrier_xz: Vector2, carrier_color: Color) -> void:
	loose_weight = 0.0
	_loose_s = 0.0
	if new_carrier_id != carrier_id:
		carrier_weight = 0.0
	carrier_id = new_carrier_id
	carrier_weight = minf(carrier_weight + delta / CARRIER_EASE_IN_S, 1.0)
	if new_carrier_id != _last_carrier_id:
		var turnover: bool = _last_team != NO_TEAM and carrier_team != NO_TEAM \
				and carrier_team != _last_team
		_start_pulse(new_carrier_id, carrier_xz, carrier_color, turnover)
	_last_carrier_id = new_carrier_id
	if carrier_team != NO_TEAM:
		_last_team = carrier_team
	# The pulse rides its carrier while he keeps the puck, and stays where it
	# was left once he loses it.
	if new_carrier_id == _pulse_owner_id:
		pulse_center = carrier_xz


func _start_pulse(owner_id: int, center: Vector2, color: Color, turnover: bool) -> void:
	pulse_active = true
	_pulse_owner_id = owner_id
	pulse_center = center
	_pulse_age_s = 0.0
	_pulse_base_color = color
	_pulse_duration_s = TURNOVER_PULSE_S if turnover else PASS_PULSE_S
	_pulse_end_r = TURNOVER_PULSE_END_R if turnover else PASS_PULSE_END_R
	_pulse_stroke = TURNOVER_PULSE_STROKE if turnover else PASS_PULSE_STROKE


func _step_pulse(delta: float) -> void:
	if not pulse_active:
		return
	_pulse_age_s += delta
	var t: float = _pulse_age_s / _pulse_duration_s
	if t >= 1.0:
		pulse_active = false
		pulse_color.a = 0.0
		_pulse_owner_id = NO_CARRIER
		return
	# Ease-out: it leaves the ring fast and slows as it fades, so it reads as
	# coming FROM the carrier rather than as a ring that happens to be there.
	var grow: float = 1.0 - pow(1.0 - t, 3.0)
	pulse_outer_r = lerpf(PULSE_START_R, _pulse_end_r, grow)
	pulse_inner_r = maxf(pulse_outer_r - _pulse_stroke, 0.0)
	pulse_color = _pulse_base_color
	pulse_color.a = _pulse_base_color.a * (1.0 - t) * (1.0 - t)

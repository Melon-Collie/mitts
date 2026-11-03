class_name IceRingField
extends Node

# Feeds the ice shader's analytic on-ice HUD — player rings, elevation chevrons,
# and the slapper one-timer indicator (see Shaders/ice.gdshader). None of those marks is an object: a ring under a player
# is just ice coloured differently near a position, so the shader computes it and
# this node's whole job is to hand over the positions. Per frame that is a
# handful of set_shader_parameter calls, regardless of roster size.
#
# Drawing them as nodes instead would put a coplanar alpha quad per skater in the
# depth-sorted transparency pass, hovering millimetres above the ice it z-fights,
# faceting up close. As part of the opaque ice surface there is no transparency
# pass, nothing to z-fight, and the shader's fwidth feather antialiases
# analytically at any camera height.
#
# The slapper indicator is SELF-ONLY — at most one skater shows it — so it rides
# as scalar uniforms rather than arrays.
#
# The puck-following cues (PuckFollowCues) ride here too: the carrier's ring is
# one of the rings drawn thicker, and the possession pulse and loose-puck halo
# are two more rings in a small array of their own. They show only alongside
# the player rings, so the replay and spectator latches that hide those hide
# these with them.
#
# Sibling of IceScratchMap: same place in the tree, same owner (HockeyRink), same
# job of turning live skater state into something the ice shader samples.

# Shader arrays are fixed-size, so this is the ceiling on simultaneous rings —
# sized past 5v5's ten so a roster change does not silently drop one. Kept in
# lockstep with the array length declared in ice.gdshader.
const MAX_RINGS: int = 12
# The pulse and the loose halo; ice.gdshader's cue arrays are this long.
const MAX_CUES: int = 2

var _material: ShaderMaterial = null
# Reused across frames — this runs every frame, and a fresh array per frame is
# exactly the per-tick heap churn the hot-path rules warn about. Always sent
# full-length (the shader reads only the first ring_count entries).
var _positions: PackedVector4Array = PackedVector4Array()
var _colors: PackedVector4Array = PackedVector4Array()
# Elevation chevrons ride along: xy = first apex, z = how many are stacked. The
# shader stacks the rest itself, so a skater at HIGH loft — three marks, one per
# rung above flat — is still one entry.
var _chevrons: PackedVector4Array = PackedVector4Array()
var _skaters: SkaterGroupCache = SkaterGroupCache.new()
var _cues: PuckFollowCues = PuckFollowCues.new()
var _cue_positions: PackedVector4Array = PackedVector4Array()
var _cue_colors: PackedVector4Array = PackedVector4Array()
var _puck: Puck = null
# Where the puck is drawn this frame (interpolated, like the off-screen puck
# arrow that hovers on it); read once by _step_cues for both the gate and the
# halo.
var _puck_at: Vector3 = Vector3.ZERO
# The faceoff countdown: the puck waits over the dot (or is thrown down onto
# it) and is not in play, so it gets no loose halo until the drop.
var _faceoff_countdown: bool = false


func _init() -> void:
	_positions.resize(MAX_RINGS)
	_colors.resize(MAX_RINGS)
	_chevrons.resize(MAX_RINGS)
	_cue_positions.resize(MAX_CUES)
	_cue_colors.resize(MAX_CUES)


func setup(material: ShaderMaterial) -> void:
	_material = material
	# The neutral HUD stroke and the fixed stroke sizes never change, so they are
	# written once rather than per frame like the rings.
	_material.set_shader_parameter(&"hud_stroke_col", _linear_rgba(MenuStyle.HUD_ICE))
	# World-metre stroke sizes the shader cannot read from GDScript.
	_material.set_shader_parameter(&"hud_line_thin", MenuStyle.HUD_LINE_THIN)
	_material.set_shader_parameter(&"reticle_half_len",
			SkaterHUDCoordinator.RETICLE_HALF_LENGTH)
	_material.set_shader_parameter(&"chevron_stack_gap",
			SkaterHUDCoordinator.CHEVRON_STACK_GAP)


# The shader's colour uniforms are LINEAR — see the note on ring_col in
# ice.gdshader. A `source_color` hint would normally handle this, but the
# conversion is not applied elementwise when the value arrives as a packed
# array, and doing it here keeps the two colour paths (per-ring array, single
# chevron uniform) converting identically. Alpha is not a colour and is left as
# authored.
static func _linear_rgba(c: Color, alpha: float = MenuStyle.HUD_OPACITY) -> Vector4:
	var lin: Color = c.srgb_to_linear()
	return Vector4(lin.r, lin.g, lin.b, alpha)


func _process(delta: float) -> void:
	if _material == null:
		return
	var count: int = 0
	var chevron_count: int = 0
	# Screen-down is a property of the CAMERA, not of any skater — every skater's
	# copy is the same value. Taken from whichever is seen first rather than
	# recomputed here, so the camera-change check that maintains it stays in one
	# place (SkaterHUDCoordinator) instead of being duplicated.
	var screen_down: Vector2 = Vector2(0.0, 1.0)
	# The slapper indicator is SELF-ONLY: at most one skater ever shows it, so it
	# is a handful of scalar uniforms rather than an array, and the first skater
	# reporting it wins. Checked BEFORE the ring gate below — the two are
	# independent pieces of chrome and one must not suppress the other.
	# Reticle and arrow are separate gates: a plain carried slapshot charge shows
	# ONLY the aim arrow (no reticle/ring — see LocalController's
	# _update_one_timer_indicator), so the claim must trigger on either flag or
	# the arrow-only case never reaches the shader at all.
	var slapper_seen: bool = false
	var carrier: Skater = _step_cues(delta)
	for node: Node in _skaters.live(get_tree()):
		var skater: Skater = node as Skater
		if skater == null:
			continue
		if not slapper_seen and (skater.slapper_field_visible()
				or skater.slapper_field_arrow_visible()):
			slapper_seen = true
			var centre: Vector2 = skater.slapper_field_center()
			_material.set_shader_parameter(&"slapper_zone", Vector4(centre.x, centre.y,
					skater.slapper_field_radius(), skater.slapper_field_ring_scale()))
			_material.set_shader_parameter(&"slapper_dir", skater.slapper_field_arrow_dir())
			_material.set_shader_parameter(&"slapper_active", skater.slapper_field_visible())
			_material.set_shader_parameter(&"slapper_arrow",
					skater.slapper_field_arrow_visible())
		if count >= MAX_RINGS or not skater.ring_field_visible():
			continue
		screen_down = skater.hud_screen_down()
		var stack: int = skater.chevron_field_stack()
		if stack > 0 and chevron_count < MAX_RINGS:
			var apex: Vector2 = skater.chevron_field_apex()
			_chevrons[chevron_count] = Vector4(apex.x, apex.y, float(stack), 0.0)
			chevron_count += 1
		# Interpolation-correct read, so the ring tracks the RENDERED skater
		# rather than the post-tick physics pose — the same reason IceScratchMap
		# uses it. As a child node the ring inherited this for free; driving it
		# from a uniform makes the choice explicit. Every other accessor read
		# here goes through the same seam, so the whole on-ice rig — ring,
		# chevrons, reticle — moves as one body.
		var pos: Vector3 = skater.render_transform().origin
		var inner_r: float = SkaterHUDCoordinator.RING_INNER_R
		if skater == carrier:
			inner_r = lerpf(inner_r, PuckFollowCues.CARRIER_RING_INNER_R,
					_cues.carrier_weight)
		_positions[count] = Vector4(pos.x, pos.z,
				SkaterHUDCoordinator.RING_OUTER_R, inner_r)
		_colors[count] = _linear_rgba(skater.ring_field_color())
		count += 1
	# Unused tail entries are left stale on purpose: the shader never reads past
	# ring_count, and zeroing them would be work to hide data nothing looks at.
	_material.set_shader_parameter(&"ring_pos", _positions)
	_material.set_shader_parameter(&"ring_col", _colors)
	_material.set_shader_parameter(&"ring_count", count)
	_material.set_shader_parameter(&"chevron_pos", _chevrons)
	_material.set_shader_parameter(&"chevron_count", chevron_count)
	_material.set_shader_parameter(&"hud_screen_down", screen_down)
	_push_cues(count > 0)
	# Cleared explicitly: a stale `true` would leave the last charge's reticle
	# (or aim arrow) painted on the ice for the rest of the period.
	if not slapper_seen:
		_material.set_shader_parameter(&"slapper_active", false)
		_material.set_shader_parameter(&"slapper_arrow", false)


func on_phase_changed(phase: GamePhase.Phase) -> void:
	_faceoff_countdown = phase == GamePhase.Phase.FACEOFF_PREP


# Steps the cue model from the puck as this peer draws it, and returns the
# skater whose ring it thickens (null while loose or with the cues off).
func _step_cues(delta: float) -> Skater:
	if not PlayerPrefs.puck_cues_enabled or not _find_puck():
		_cues.reset()
		return null
	_puck_at = _puck.get_global_transform_interpolated().origin
	var carrier: Skater = _puck.drawn_carrier()
	if carrier != null and carrier.ring_field_visible():
		var at: Vector3 = carrier.render_transform().origin
		_cues.step(delta, carrier.get_instance_id(), carrier.get_team_id(),
				Vector2(at.x, at.z), carrier.ring_field_color(), false)
		return carrier
	_cues.step(delta, PuckFollowCues.NO_CARRIER, PuckFollowCues.NO_TEAM,
			Vector2.ZERO, Color(), _puck_on_ice() and not _faceoff_countdown)
	return null


func _find_puck() -> bool:
	if _puck == null or not is_instance_valid(_puck):
		_puck = get_tree().get_first_node_in_group(Puck.GROUP) as Puck
	return _puck != null


# A puck stashed off the sheet (the tutorial's puckless steps) or escaped over
# the boards gets no halo.
func _puck_on_ice() -> bool:
	var xz := Vector2(_puck_at.x, _puck_at.z)
	return GameRules.clamp_to_rink_inner(xz).distance_squared_to(xz) < 1e-6


# Writes the pulse and the halo. `rings_shown` false (a replay, a spectator, no
# skaters yet) clears them and forgets the possession history, so the first
# pickup back in live play pulses rather than a stale one firing.
func _push_cues(rings_shown: bool) -> void:
	var n: int = 0
	if not rings_shown:
		_cues.reset()
	else:
		if _cues.pulse_active:
			_cue_positions[n] = Vector4(_cues.pulse_center.x, _cues.pulse_center.y,
					_cues.pulse_outer_r, _cues.pulse_inner_r)
			_cue_colors[n] = _linear_rgba(_cues.pulse_color,
					_cues.pulse_color.a * MenuStyle.HUD_OPACITY)
			n += 1
		if _cues.loose_weight > 0.0:
			_cue_positions[n] = Vector4(_puck_at.x, _puck_at.z,
					PuckFollowCues.LOOSE_HALO_OUTER_R, PuckFollowCues.LOOSE_HALO_INNER_R)
			_cue_colors[n] = _linear_rgba(MenuStyle.HUD_ICE,
					_cues.loose_weight * MenuStyle.HUD_OPACITY)
			n += 1
	_material.set_shader_parameter(&"cue_pos", _cue_positions)
	_material.set_shader_parameter(&"cue_col", _cue_colors)
	_material.set_shader_parameter(&"cue_count", n)

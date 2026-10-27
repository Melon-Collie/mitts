class_name Minimap
extends Control

# Top-down rink minimap. A cosmetic HUD widget (like OffScreenPlayerIndicators):
# it reads live world state through GameManager and redraws every frame at render
# rate — never on the physics tick — so it costs nothing in the tick budget.
#
# Orientation MATCHES the game camera. The camera renders the rink with world +X
# to screen-right and world +Z toward screen-bottom, and flips 180° (yaw) only
# when the "Always Attack Up" pref is on AND the local player is on team 1 (see
# GameCamera._process step 5b). The minimap reproduces exactly that flip
# via the same boolean, so the direction the local player attacks is always the
# same on the map as it is on screen — up-screen when attack-up is on, absolute
# otherwise. Because the transform is derived from the camera's own rule rather
# than hard-coded per team, the attacking net on the map can never disagree with
# the one in the game.
#
# Toggled by PlayerPrefs.minimap_enabled (Options → Camera). Hidden during replays
# (no local frame of reference — same reason the off-screen arrows bail).
#
# TWO LAYERS, redrawn on different clocks. The rink itself — bed, boards,
# creases, faceoff spots, zone lines, nets — cannot change except when the attack
# flip or the ends swap, and redrawing it with the dots costs ~0.5 ms of a frame
# to produce the identical image (two rounded style boxes, two re-tessellated
# crease polygons each allocating a fresh PackedVector2Array, a dozen circles,
# five lines). Godot keeps each CanvasItem's recorded command list and replays it
# for free until something calls queue_redraw(), so the static half lives in its
# own CanvasItem that is NOT queued per frame. Only the dots redraw every frame.
#
# The layers are children (not this node) because siblings draw in tree order and
# children draw over their parent — the rink has to be UNDER the dots, so it
# cannot be the parent's own _draw.

# Ice draw area in virtual HUD pixels along the long (Z) axis; the short (X) axis
# is derived from the true rink aspect so the map never distorts.
const _ICE_LENGTH_PX: float = 210.0
const _MARGIN_X: float = 8.0
# Taller than the sides: the attack chevron sits in the margin past the end boards.
const _MARGIN_Y: float = 14.0

# Opaque, in the scorebug's panel language: the map is its own surface, never a
# window onto the (moving, ad-painted) ice behind it.
const _BG_COLOR: Color = MenuStyle.BROADCAST_BG
const _BG_TOP_EDGE: Color = MenuStyle.BROADCAST_BORDER_T
const _ICE_COLOR: Color = MenuStyle.SURFACE_ELEV
const _BOARD_COLOR: Color = Color(0.753, 0.847, 0.878, 0.45)
const _CENTER_LINE_COLOR: Color = Color(0.86, 0.22, 0.22, 0.85)
const _BLUE_LINE_COLOR: Color = Color(0.30, 0.52, 0.95, 0.85)
const _GOAL_LINE_COLOR: Color = Color(0.86, 0.22, 0.22, 0.4)
const _PUCK_FILL: Color = Color(0.02, 0.02, 0.02, 1.0)
const _PUCK_OUTLINE: Color = Color(1.0, 1.0, 1.0, 0.9)
# Every marker is cut out of the panel by a ring of panel colour rather than
# drawn over it in black.
const _MARKER_OUTLINE: Color = MenuStyle.BROADCAST_BG
const _LOCAL_OUTLINE: Color = Color(1.0, 1.0, 1.0, 0.95)
const _ATTACK_CHEVRON: Color = MenuStyle.TEAL
# Faceoff spots — static reference marks only (no circles, no hashmarks), muted
# and low-alpha so a live player/puck dot always wins the eye over them.
const _FACEOFF_DOT_COLOR: Color = Color(0.86, 0.22, 0.22, 0.35)
# Crease fill — Pantone 298 like the painted ice (HockeyRink), translucent so
# it stays a background reference under the goal line and the goalie dot.
const _CREASE_COLOR: Color = Color(0.392, 0.765, 0.922, 0.35)
const _CREASE_ARC_STEPS: int = 10

const _PLAYER_DOT_RADIUS: float = 4.5
const _GOALIE_HALF_SIZE: float = 3.25  # goalies draw as squares; shape marks the role
const _PUCK_DOT_RADIUS: float = 2.5
const _FACEOFF_DOT_RADIUS: float = 1.3
# The local skater's arrowhead, in map pixels from the skater's position.
const _LOCAL_TIP: float = 7.0
const _LOCAL_BACK: float = 4.0
const _LOCAL_HALF_WIDTH: float = 5.0
# The puck already sits on its carrier's stick; the carrier's marker grows by
# this factor so a scrum still shows whose stick it is on.
const _CARRIER_SCALE: float = 5.5 / _PLAYER_DOT_RADIUS

var _ice_width_px: float = 0.0   # short (X) axis, derived from rink aspect
var _bg_style: StyleBoxFlat = null
var _ice_style: StyleBoxFlat = null
# Crease outline in world metres as (x, depth-toward-center) pairs — the NHL
# D-shape from CreaseRules: goal-line corners at ±HALF_WIDTH joined by the
# ARC_RADIUS arc (the arc meets the straight sides at the caps, so no separate
# side segments are needed). Built once; both ends map through it per frame.
var _crease_template: PackedVector2Array = PackedVector2Array()

# A bare Control whose _draw defers to a Callable, so both layers can share the
# Minimap's drawing helpers without duplicating them or subclassing twice.
class _Layer extends Control:
	var painter: Callable

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)

var _static_layer: _Layer = null
var _dynamic_layer: _Layer = null

# What the static layer's image depends on. When any of these moves the rink is
# repainted — once — and otherwise its command list is replayed untouched.
# Tracked as separate scalars rather than a packed key so the comparison stays
# allocation-free on the per-frame path.
var _static_flip: bool = false
var _static_goal_count: int = -1
var _static_team_near: int = -1
var _static_team_far: int = -1
var _static_attack_team: int = -1
var _static_valid: bool = false
# Scratch for the local arrowhead, reused every frame.
var _arrow_pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arrow_outline := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
# Goalie/net jersey tints, cached per team against the colour slot they were
# built from (-1 = not yet built). See _team_color.
const _NEUTRAL_TINT := Color(0.6, 0.6, 0.6)
var _tint_slots := PackedInt32Array([-1, -1])
var _tint_cache := PackedColorArray([_NEUTRAL_TINT, _NEUTRAL_TINT])

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true  # keep an off-rink actor (tutorial stash, corner) inside the frame
	_ice_width_px = _ICE_LENGTH_PX * GameRules.RINK_HALF_WIDTH / GameRules.RINK_HALF_LENGTH

	# Anchored to the bottom-left corner of the (scalable) HUD chrome — the one
	# screen corner the existing chrome leaves clear (scorebug top-left, bug icon
	# / skip prompt / version bottom-right, chyron + menu hint bottom-center).
	var w: float = _ice_width_px + _MARGIN_X * 2.0
	var h: float = _ICE_LENGTH_PX + _MARGIN_Y * 2.0
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 8.0
	offset_right = 8.0 + w
	offset_top = -(8.0 + h)
	offset_bottom = -8.0

	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = _BG_COLOR
	_bg_style.set_corner_radius_all(4)
	_bg_style.border_color = _BG_TOP_EDGE
	_bg_style.border_width_top = 1

	# Ice bed: a rounded rect whose corner radius is the REAL rink corner radius
	# (GameRules.CORNER_RADIUS, 8.53 m) mapped through the map scale, so the map's
	# corners bow exactly like the boards do instead of reading as a square. Scale
	# is uniform (see _ice_width_px derivation), so the world's circular corner
	# stays circular here. A thin border traces the rounded shape as the boards.
	var px_per_m: float = _ICE_LENGTH_PX / (GameRules.RINK_HALF_LENGTH * 2.0)
	var corner_px: int = int(round(GameRules.CORNER_RADIUS * px_per_m))
	_ice_style = StyleBoxFlat.new()
	_ice_style.bg_color = _ICE_COLOR
	_ice_style.set_corner_radius_all(corner_px)
	_ice_style.border_color = _BOARD_COLOR
	_ice_style.set_border_width_all(1)

	_crease_template.append(Vector2(-CreaseRules.HALF_WIDTH, 0.0))
	var theta_max: float = asin(CreaseRules.HALF_WIDTH / CreaseRules.ARC_RADIUS)
	for i: int in _CREASE_ARC_STEPS + 1:
		var theta: float = lerpf(-theta_max, theta_max, float(i) / float(_CREASE_ARC_STEPS))
		_crease_template.append(Vector2(
				CreaseRules.ARC_RADIUS * sin(theta),
				CreaseRules.ARC_RADIUS * cos(theta)))
	_crease_template.append(Vector2(CreaseRules.HALF_WIDTH, 0.0))

	# Static first, dynamic second: tree order is draw order, so the rink lands
	# under the dots.
	_static_layer = _make_layer(_paint_static)
	_dynamic_layer = _make_layer(_paint_dynamic)

func _make_layer(painter: Callable) -> _Layer:
	var layer := _Layer.new()
	layer.painter = painter
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer

func _process(_delta: float) -> void:
	# Only churn a redraw when the map is actually shown. Disabled or in a replay
	# both painters early-return anyway — skip the queue so it costs nothing.
	var live: bool = PlayerPrefs.minimap_enabled and not NetworkManager.is_replay_mode()
	if not live:
		# Drop the cached rink so leaving a replay (or re-enabling the map)
		# repaints it rather than replaying a command list built for the old
		# flip or the old ends.
		_static_valid = false
		return
	_dynamic_layer.queue_redraw()
	_refresh_static_if_changed()

# Repaints the rink layer only when the image it would produce actually differs.
# Everything compared here is read per frame regardless (the dots need the flip),
# so this adds a handful of scalar compares, not a second pass over the geometry.
func _refresh_static_if_changed() -> void:
	var flip: bool = _local_attack_up_flip()
	var goals: Array = GameManager.goals
	var near_id: int = -1
	var far_id: int = -1
	if goals.size() > 0 and is_instance_valid(goals[0]):
		near_id = (goals[0] as HockeyGoal).defending_team_id
	if goals.size() > 1 and is_instance_valid(goals[1]):
		far_id = (goals[1] as HockeyGoal).defending_team_id
	var attack_team: int = _local_team_id()
	if _static_valid and flip == _static_flip and goals.size() == _static_goal_count \
			and near_id == _static_team_near and far_id == _static_team_far \
			and attack_team == _static_attack_team:
		return
	_static_flip = flip
	_static_goal_count = goals.size()
	_static_team_near = near_id
	_static_team_far = far_id
	_static_attack_team = attack_team
	_static_valid = true
	_static_layer.queue_redraw()

# The rink. Repainted only on a flip / ends change — see _refresh_static_if_changed.
func _paint_static(ci: Control) -> void:
	if not PlayerPrefs.minimap_enabled or NetworkManager.is_replay_mode():
		return
	var flip: bool = _static_flip

	# Frame + ice bed.
	ci.draw_style_box(_bg_style, Rect2(Vector2.ZERO, ci.size))
	var ice_rect := Rect2(Vector2(_MARGIN_X, _MARGIN_Y), Vector2(_ice_width_px, _ICE_LENGTH_PX))
	ci.draw_style_box(_ice_style, ice_rect)

	# Crease fills before the lines, same layering as the painted ice — the goal
	# line renders over the D.
	_draw_crease(ci, GameRules.GOAL_LINE_Z, flip)
	_draw_crease(ci, -GameRules.GOAL_LINE_Z, flip)

	# Faceoff spots first — static reference marks on the ice bed, under the lines
	# and every dynamic dot. Center ice plus the neutral- and end-zone dots, drawn
	# straight from the same geometry the faceoff staging uses.
	_draw_faceoff_dot(ci, Vector2.ZERO, flip)
	for dot: Vector2 in GameRules.NEUTRAL_ZONE_FACEOFF_DOTS:
		_draw_faceoff_dot(ci, dot, flip)
	for dot: Vector2 in GameRules.END_ZONE_FACEOFF_DOTS:
		_draw_faceoff_dot(ci, dot, flip)

	# Zone lines run across the short axis (constant world Z → constant map Y).
	_draw_zone_line(ci, 0.0, flip, _CENTER_LINE_COLOR, 1.5)
	_draw_zone_line(ci, GameRules.BLUE_LINE_Z, flip, _BLUE_LINE_COLOR, 1.5)
	_draw_zone_line(ci, -GameRules.BLUE_LINE_Z, flip, _BLUE_LINE_COLOR, 1.5)
	_draw_zone_line(ci, GameRules.GOAL_LINE_Z, flip, _GOAL_LINE_COLOR, 1.0)
	_draw_zone_line(ci, -GameRules.GOAL_LINE_Z, flip, _GOAL_LINE_COLOR, 1.0)

	# Nets — a team-tinted box sitting behind each goal line (mouth on the line,
	# NET_DEPTH toward the boards), outlined like the dots so the away team's
	# white kit still reads against the ice.
	for goal: HockeyGoal in GameManager.goals:
		if not is_instance_valid(goal):
			continue
		var net_color: Color = _team_color(goal.defending_team_id)
		# goal_line_z(), NOT global_position.z: the HockeyGoal node sits at scene
		# origin and builds its geometry around that value, so its transform reads
		# as center ice for both ends.
		var gz: float = goal.goal_line_z()
		var back_z: float = gz + signf(gz) * GameRules.NET_DEPTH
		var a: Vector2 = _map_point(-GameRules.NET_HALF_WIDTH, gz, flip)
		var b: Vector2 = _map_point(GameRules.NET_HALF_WIDTH, back_z, flip)
		var net_rect: Rect2 = Rect2(a, Vector2.ZERO).expand(b)
		ci.draw_rect(net_rect, net_color, true)
		ci.draw_rect(net_rect, _MARKER_OUTLINE, false, 1.0)
		if _static_attack_team >= 0 and goal.defending_team_id != _static_attack_team:
			_draw_attack_chevron(ci, gz, flip)

# The moving parts, and only these, per frame.
func _paint_dynamic(ci: Control) -> void:
	if not PlayerPrefs.minimap_enabled:
		return
	# Replay cuts to broadcast cameras with no local player, so there's no "attack
	# direction" to orient by — same bail as OffScreenPlayerIndicators.
	if NetworkManager.is_replay_mode():
		return
	var flip: bool = _static_flip

	# Goalies (own-team tint), then skaters, then the puck on top. Walked per
	# team rather than over GameManager.goalies: that array is positional
	# ([top, bottom]) and carries no team id, while Team.goalie_controller is the
	# authoritative team-to-goalie binding set at spawn.
	for team: Team in GameManager.teams:
		var gc: GoalieController = team.goalie_controller
		if gc == null or gc.goalie == null or not is_instance_valid(gc.goalie):
			continue
		var goalie: Goalie = gc.goalie
		var gpos: Vector2 = _map_point(goalie.global_position.x, goalie.global_position.z, flip)
		_draw_square(ci, gpos, _GOALIE_HALF_SIZE, _team_color(team.team_id))

	var puck: Puck = GameManager.puck
	var carrier: Skater = null
	if puck != null and is_instance_valid(puck):
		carrier = puck.get_carrier()

	# The local skater draws last among the skaters so a pile-up never hides it.
	var local_record: PlayerRecord = null
	var players: Dictionary[int, PlayerRecord] = GameManager.get_players()
	for peer_id: int in players:
		var record: PlayerRecord = players[peer_id]
		if record == null or record.skater == null:
			continue
		if record.is_local:
			local_record = record
			continue
		var pos: Vector2 = _map_point(record.skater.global_position.x, record.skater.global_position.z, flip)
		var radius: float = _PLAYER_DOT_RADIUS * (_CARRIER_SCALE if record.skater == carrier else 1.0)
		_draw_dot(ci, pos, radius, record.jersey_color)
	if local_record != null:
		var skater: Skater = local_record.skater
		var lpos: Vector2 = _map_point(skater.global_position.x, skater.global_position.z, flip)
		_draw_local_arrow(ci, lpos, skater.get_facing(), flip, local_record.jersey_color,
				_CARRIER_SCALE if skater == carrier else 1.0)

	if puck != null and is_instance_valid(puck):
		var ppos: Vector2 = _map_point(puck.global_position.x, puck.global_position.z, flip)
		ci.draw_circle(ppos, _PUCK_DOT_RADIUS + 1.0, _PUCK_OUTLINE, true, -1.0, true)
		ci.draw_circle(ppos, _PUCK_DOT_RADIUS, _PUCK_FILL, true, -1.0, true)

# Maps a world XZ position into map-local pixels. Base orientation matches the
# unflipped camera (world +X → right, world +Z → down); the attack-up flip
# negates both axes, exactly like the camera's 180° yaw.
func _map_point(world_x: float, world_z: float, flip: bool) -> Vector2:
	var nx: float = world_x / GameRules.RINK_HALF_WIDTH
	var nz: float = world_z / GameRules.RINK_HALF_LENGTH
	if flip:
		nx = -nx
		nz = -nz
	var cx: float = _MARGIN_X + _ice_width_px * 0.5
	var cy: float = _MARGIN_Y + _ICE_LENGTH_PX * 0.5
	return Vector2(cx + nx * _ice_width_px * 0.5, cy + nz * _ICE_LENGTH_PX * 0.5)

# A zone line spanning the rink's width at a constant world Z. Blue/center lines
# sit in the straight-wall middle, so they run the full width; the goal lines sit
# past the corner center, so this insets them to the curved boards' actual width
# there — otherwise they'd poke into the rounded-off corner void.
func _draw_zone_line(ci: Control, world_z: float, flip: bool, color: Color, width: float) -> void:
	var hw: float = _rink_half_width_at_z(world_z)
	var a: Vector2 = _map_point(-hw, world_z, flip)
	var b: Vector2 = _map_point(hw, world_z, flip)
	ci.draw_line(a, b, color, width, true)

# The rink's half-width at a given world Z, following the rounded corners: full
# width through the straight middle, shrinking along the corner arc past the
# corner center. Mirrors the board geometry in GameRules.clamp_to_rink_inner but
# on the outer (board) dimensions.
func _rink_half_width_at_z(world_z: float) -> float:
	var az: float = absf(world_z)
	var corner_center_z: float = GameRules.RINK_HALF_LENGTH - GameRules.CORNER_RADIUS
	if az <= corner_center_z:
		return GameRules.RINK_HALF_WIDTH
	var dz: float = minf(az - corner_center_z, GameRules.CORNER_RADIUS)
	var inner: float = sqrt(GameRules.CORNER_RADIUS * GameRules.CORNER_RADIUS - dz * dz)
	return (GameRules.RINK_HALF_WIDTH - GameRules.CORNER_RADIUS) + inner

# The filled crease D at a goal line. Template points are (x, depth) with depth
# extending toward center ice, so the same template serves both ends; the
# attack-up flip is handled per-vertex by _map_point like everything else.
func _draw_crease(ci: Control, goal_line_z: float, flip: bool) -> void:
	var inward: float = -signf(goal_line_z)
	var pts := PackedVector2Array()
	pts.resize(_crease_template.size())
	for i: int in _crease_template.size():
		var t: Vector2 = _crease_template[i]
		pts[i] = _map_point(t.x, goal_line_z + inward * t.y, flip)
	ci.draw_colored_polygon(pts, _CREASE_COLOR)

# A single faceoff spot. spot is (world_x, world_z); drawn as a small faint mark
# with no outline so it stays a background reference, never a foreground dot.
func _draw_faceoff_dot(ci: Control, spot: Vector2, flip: bool) -> void:
	var pos: Vector2 = _map_point(spot.x, spot.y, flip)
	ci.draw_circle(pos, _FACEOFF_DOT_RADIUS, _FACEOFF_DOT_COLOR)

func _draw_dot(ci: Control, pos: Vector2, radius: float, fill: Color) -> void:
	ci.draw_circle(pos, radius + 1.0, _MARKER_OUTLINE, true, -1.0, true)
	ci.draw_circle(pos, radius, fill, true, -1.0, true)

# You: an arrowhead along your facing, in your jersey, outlined white. Facing is
# world (x, z); the map's base orientation is x right, z down, so it maps as-is
# and the attack-up flip negates it like a position.
func _draw_local_arrow(ci: Control, pos: Vector2, facing: Vector2, flip: bool, fill: Color,
		size_factor: float) -> void:
	var dir: Vector2 = facing.normalized() if facing.length_squared() > 0.0001 else Vector2.DOWN
	if flip:
		dir = -dir
	var side: Vector2 = dir.orthogonal()
	_arrow_pts[0] = pos + dir * (_LOCAL_TIP * size_factor)
	_arrow_pts[1] = pos + (side * _LOCAL_HALF_WIDTH - dir * _LOCAL_BACK) * size_factor
	_arrow_pts[2] = pos - (side * _LOCAL_HALF_WIDTH + dir * _LOCAL_BACK) * size_factor
	ci.draw_colored_polygon(_arrow_pts, fill)
	for i: int in 3:
		_arrow_outline[i] = _arrow_pts[i]
	_arrow_outline[3] = _arrow_pts[0]
	ci.draw_polyline(_arrow_outline, _LOCAL_OUTLINE, 1.5, true)

# A chevron in the end margin past the boards the local team attacks, pointing
# off the map: which way is "up the ice" for you, whatever the camera flip.
func _draw_attack_chevron(ci: Control, goal_line_z: float, flip: bool) -> void:
	var end: Vector2 = _map_point(0.0, signf(goal_line_z) * GameRules.RINK_HALF_LENGTH, flip)
	var out: Vector2 = (end - _map_point(0.0, 0.0, flip)).normalized()
	var tip: Vector2 = end + out * (_MARGIN_Y - 3.0)
	var back: Vector2 = tip - out * 4.0
	var side: Vector2 = out.orthogonal() * 5.0
	ci.draw_polyline(PackedVector2Array([back + side, tip, back - side]), _ATTACK_CHEVRON, 2.0, true)

# Goalie marker: same outline treatment as the dots, but square — the shape
# alone says "goalie", since goalies and skaters share the team jersey tint.
func _draw_square(ci: Control, pos: Vector2, half: float, fill: Color) -> void:
	var o: float = half + 1.0
	ci.draw_rect(Rect2(pos - Vector2(o, o), Vector2(o * 2.0, o * 2.0)), _MARKER_OUTLINE, true)
	ci.draw_rect(Rect2(pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), fill, true)

# The local player's team, or -1 for a spectator / before the record exists.
func _local_team_id() -> int:
	var record: PlayerRecord = GameManager.get_local_player()
	if record == null or record.team == null:
		return -1
	return record.team.team_id

# True when the camera is (or would be) yaw-flipped for the local player: the
# "Always Attack Up" pref on and the local player on team 1. Mirrors the exact
# condition in GameCamera. Spectators / no local record → no flip.
func _local_attack_up_flip() -> bool:
	if not PlayerPrefs.attack_up:
		return false
	var record: PlayerRecord = GameManager.get_local_player()
	if record == null or record.team == null:
		return false
	return record.team.team_id == 1

# Team-identity color for net / goalie tinting: the side-aware kit jersey base,
# the same color the skater dots wear (record.jersey_color is set from it), so
# a goalie always reads as the same team as its skaters. NOT the preset's flat
# `primary` — that ignores home/away, tinting the away goalie a saturated color
# while its skaters draw in the away kit's white. Grey fallback before teams
# are wired.
#
# Cached against the team's colour slot: TeamColorRegistry.get_colors builds a
# ~15-key Dictionary (and the nested kit lookups behind it) per call, and this is
# called per goalie per rendered frame. The slot is the only input that can
# change the answer, so comparing it is a complete invalidation check.
func _team_color(team_id: int) -> Color:
	if team_id < 0 or team_id >= GameManager.teams.size():
		return _NEUTRAL_TINT
	if team_id >= _tint_slots.size():
		return _NEUTRAL_TINT
	var slot: int = GameManager.teams[team_id].color_slot
	if _tint_slots[team_id] != slot:
		var colors: Dictionary = TeamColorRegistry.get_colors(slot, team_id)
		_tint_slots[team_id] = slot
		_tint_cache[team_id] = colors.jersey
	return _tint_cache[team_id]

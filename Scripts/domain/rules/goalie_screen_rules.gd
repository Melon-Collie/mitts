class_name GoalieScreenRules

# How a body in front of the goalie hides a shot from him: the silhouette and
# the sightline, pure geometry. The goalie reads a screened shot late by the
# delay it prices (GoalieController.screen_delay_for, which the shot log
# records too), loses his look at a puck a body hides, and looks round one
# (KeeperScreen); the bots read it to clear or not make a screen in front of
# their own goalie (AIShotBlockRead, AIScreenRead).

# ── Screen occlusion (grounded sightline model) ──────────────────────────────
# A body between the shooter and the goalie hides the puck: the goalie can't start
# their read until they SEE the puck leave the shadow of the screener. This returns
# that pickup delay in SECONDS, built from geometry + shot speed rather than a flat
# "screened → +X ms" fudge.
#
# ── The shadow, solved from the goalie's eye ─────────────────────────────────
# A screen is a fact about ONE line: goalie → puck. A body standing on that line
# casts a shadow the width of its own silhouette, and the puck is hidden for
# exactly as long as it stays inside it. Two consequences fall out, and they are
# the whole model:
#
#   THE RELEASE HAS TO BE HIDDEN. If the goalie saw the puck leave the blade, he
#   has the trajectory; a body it flies past afterwards can obscure it but cannot
#   un-read it. Only a shooter who is himself behind the screen costs the goalie
#   the pickup. Never test against the SHOT line instead: that charges the goalie
#   for every body near the flight path including ones nowhere near his eyeline,
#   and simultaneously lets a body standing DEAD IN FRONT OF HIM off for a shot
#   aimed at a post, because the flight path diverges from the sightline by more
#   than a body width over 10 m.
#
#   IT ENDS WHEN THE PUCK LEAVES THE SHADOW, not when it draws level with the
#   body. A shot angled away from the screener clears his silhouette early; only
#   one fired straight down the sightline stays hidden the whole way in. That is
#   the difference between the deadly dead-on net-front screen and traffic the
#   goalie can see around, and it is geometry rather than a tuned curve.
#
# A BODY IS NOT A COLUMN, AND THAT IS WHERE THE SIGHT COMES FROM. The silhouette
# that matters is the one at the height the sightline actually passes through him,
# and the sightline to a puck on the ice runs DOWNWARD from the goalie's eye: it
# crosses a near screener at chest height (wide — the full torso) and a distant
# one down at the skates (narrow, with daylight between the legs). That is exactly
# the difference between the doorstep screen you cannot see through and the slot
# traffic you find the puck under, and it is why a goalie drops to find a puck in
# a crowd — going down lowers his eye, which drops the whole sightline into the
# leg band. One silhouette function, three measurements, no screening curve.
#
# Evaluated in the XZ plane (bodies + shots live on the ice), in the goalie's
# frame: `p` is the release point relative to his eye, the puck rides
# `d(s) = p + s·v̂`, and the screener sits at `w`. Occlusion is
# |w × d(s)| < radius·|d(s)| — a quadratic in `s`, so the exit distance is a root
# solve, no stepping. The half-width is taken once per screener, from the sightline
# height at the RELEASE: that is the moment that decides whether the goalie ever
# had the puck, and holding it fixed keeps the exit a closed-form root rather than
# a march. The worst (longest-hiding) screener wins; the shooter self-excludes via
# `min_along`. The caller clamps the result to a cap (and to the flight time).
# Returns 0 for a clean look. No allocation (scalar loop over the caller-owned
# positions array).
# NO OVER-THE-HEAD CLEARANCE, deliberately. The obvious companion rule — a
# sightline passing above the screener's helmet is clean — would be read off two
# rigs that were never authored against each other (a standing goalie's eyes sit
# near 1.8 m; the skater's helmet mesh is a shade over 1.5), and with those
# numbers a STANDING goalie looks straight over every body in the slot and the
# doorstep screen stops existing. That is a coincidence of two independent
# authorings, not a fact about the game, so the silhouette runs to the top.
class ScreenConfig:
	var eye_height: float = 1.79        # m — where the goalie is sighting FROM (stance-dependent)
	var torso_half_width: float = 0.35  # m — silhouette at and above the hips
	var leg_half_width: float = 0.16    # m — at the ice: a shin, not the stance's full span
	var hip_height: float = 0.85        # m — Skater.tscn's origin: feet ~0.85 below it
	var min_along: float = 0.6          # m — exclude the shooter / bodies right on the puck
	# How far PAST tangency a look around a body has to clear it: a sightline
	# grazing a shoulder is not a look, and a goalie steps until he SEES it.
	var peek_clearance: float = 0.05    # m


# The screener's opaque half-width at the world height a sightline crosses him.
# Linear from a shin at the ice to the full torso at the hips, because that is
# roughly how a standing body widens.
static func screener_half_width_at(sight_y: float, cfg: ScreenConfig) -> float:
	if sight_y >= cfg.hip_height:
		return cfg.torso_half_width
	return lerpf(cfg.leg_half_width, cfg.torso_half_width,
			clampf(sight_y / maxf(cfg.hip_height, 0.001), 0.0, 1.0))

# Whether `body` stands on the sightline from a goalie standing at
# `goalie_pos` to the puck at `puck_pos`: between his eyes and the puck, clear
# of both ends (the shooter, and a body on his own eyes), and within the
# body's half-width at the height the line crosses it.
static func hides(body: Vector3, goalie_pos: Vector3, puck_pos: Vector3, cfg: ScreenConfig) -> bool:
	var px: float = puck_pos.x - goalie_pos.x
	var pz: float = puck_pos.z - goalie_pos.z
	var p_len: float = sqrt(px * px + pz * pz)
	if p_len <= cfg.min_along:
		return false
	var vhx: float = px / p_len
	var vhz: float = pz / p_len
	var wx: float = body.x - goalie_pos.x
	var wz: float = body.z - goalie_pos.z
	var along: float = wx * vhx + wz * vhz
	if along <= cfg.min_along or along >= p_len - cfg.min_along:
		return false
	var eye_y: float = goalie_pos.y + cfg.eye_height
	var sight_y: float = eye_y + along / p_len * (puck_pos.y - eye_y)
	return absf(wx * -vhz + wz * vhx) < screener_half_width_at(sight_y, cfg)


# The first of `bodies` that hides the puck at `puck_pos` from a goalie at
# `goalie_pos` (`hides`); -1, a clean look.
static func hidden_by(goalie_pos: Vector3, puck_pos: Vector3, bodies: PackedVector3Array, cfg: ScreenConfig) -> int:
	for i: int in bodies.size():
		if hides(bodies[i], goalie_pos, puck_pos, cfg):
			return i
	return -1


static func screen_occlusion_delay(
		puck_position: Vector3,
		puck_velocity: Vector3,
		goalie_position: Vector3,
		screener_positions: PackedVector3Array,
		cfg: ScreenConfig) -> float:
	var speed: float = sqrt(puck_velocity.x * puck_velocity.x + puck_velocity.z * puck_velocity.z)
	if speed < 0.001:
		return 0.0
	var vhx: float = puck_velocity.x / speed
	var vhz: float = puck_velocity.z / speed
	# Release point in the goalie's frame, and how far along the shot he sits — a
	# screener must be nearer than that (a body level with or behind the goalie
	# can't hide an incoming puck).
	var px: float = puck_position.x - goalie_position.x
	var pz: float = puck_position.z - goalie_position.z
	var p_len_sq: float = px * px + pz * pz
	var pv: float = px * vhx + pz * vhz
	var goalie_along: float = -pv
	if goalie_along <= cfg.min_along:
		return 0.0
	var eye_y: float = goalie_position.y + cfg.eye_height
	var worst: float = 0.0
	for body in screener_positions:
		# Along-shot distance from the release to this body. Excludes the shooter
		# (along ≈ 0) and anything level with or behind the goalie.
		var along: float = (body.x - puck_position.x) * vhx + (body.z - puck_position.z) * vhz
		if along <= cfg.min_along or along >= goalie_along:
			continue
		var wx: float = body.x - goalie_position.x
		var wz: float = body.z - goalie_position.z
		var w_dot_p: float = wx * px + wz * pz
		if w_dot_p <= 0.0 or w_dot_p >= p_len_sq:
			continue
		# Silhouette at the height the eye→release line crosses him.
		var sight_y: float = eye_y + (w_dot_p / p_len_sq) * (puck_position.y - eye_y)
		var radius: float = screener_half_width_at(sight_y, cfg)
		var r_sq: float = radius * radius
		# Is the RELEASE hidden? The body must lie within `radius` of the eye→release
		# line (cross product over |p|).
		var cross_p: float = wx * pz - wz * px
		if cross_p * cross_p >= r_sq * p_len_sq:
			continue
		# Exit: smallest s > 0 solving |w × d(s)|² = radius²·|d(s)|², i.e.
		# (B²−r²)s² + 2(AB − r²·pv)s + (A² − r²|p|²) = 0. The constant term is
		# negative (the release is hidden), so the puck starts inside and the first
		# positive root is where it comes out.
		var cross_v: float = wx * vhz - wz * vhx
		var a2: float = cross_v * cross_v - r_sq
		var a1: float = 2.0 * (cross_p * cross_v - r_sq * pv)
		var a0: float = cross_p * cross_p - r_sq * p_len_sq
		var exit_s: float = along
		if absf(a2) < 0.000001:
			if a1 > 0.0:
				exit_s = minf(exit_s, -a0 / a1)
		else:
			var disc: float = a1 * a1 - 4.0 * a2 * a0
			if disc > 0.0:
				var root_d: float = sqrt(disc)
				var s1: float = (-a1 - root_d) / (2.0 * a2)
				var s2: float = (-a1 + root_d) / (2.0 * a2)
				var first: float = INF
				if s1 > 0.0:
					first = s1
				if s2 > 0.0 and s2 < first:
					first = s2
				exit_s = minf(exit_s, first)
		var delay: float = exit_s / speed
		if delay > worst:
			worst = delay
	return worst

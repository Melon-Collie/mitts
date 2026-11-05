class_name GoalFeatContext
extends RefCounted
## What the host knew about a credited goal, for FeatRules: who scored and fed
## it, how the shot left the stick, and who won the puck back to start the
## possession it came on. Peer ids are -1 when nobody fills the part.

var scorer: int = -1
var is_own_goal: bool = false
# Who released the shot that went in: the scorer, a teammate whose shot the
# scorer tipped, or -1 when no tracked release preceded the goal (a carry-in).
var shooter: int = -1
var primary_assist: int = -1
var is_one_timer: bool = false
var loft_level: int = ShotMechanics.ELEVATION_FLAT
var is_backhand: bool = false
# Metres from the goal line to the release point, -1 when unknown.
var release_distance_m: float = -1.0
# The release point on the ice (x, z), z signed so the goal scored on is at
# +z. Read only when release_distance_m says the release is known.
var release_xz: Vector2 = Vector2.ZERO
# The player whose interception or takeaway started the scoring team's
# possession, and which it was: FeatRules.WON_INTERCEPTION or WON_TAKEAWAY.
var won_by: int = -1
var won_kind: String = ""

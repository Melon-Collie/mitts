class_name KeeperWorldSource
extends RefCounted

# The world a predicted keeper steps against (KeeperPredictor): the shadow puck
# and the shadow skaters as this client has them at each host instant he is
# stepped to. The game's is GameKeeperWorld; a test feeds the host's own.
#
# Per stepped tick the predictor calls `stage` (the world as his tick reads it:
# the skaters after their tick, the puck after its last one, and any release it
# hears of then), steps him, then `settle` (anything the puck's own tick does to
# him after his). `anchor` comes first on every re-seed, with the instant of the
# snapshot he was re-seeded from.


# How many shadow skaters `stage` fills.
func skater_count() -> int:
	return 0


func anchor(_host_t: float) -> void:
	pass


func stage(_host_t: float, _puck: KeeperShadowPuck, _skaters: Array[KeeperShadowSkater]) -> void:
	pass


# `goalie` is the shadow goalie the puck's own contacts would name.
func settle(_host_t: float, _puck: KeeperShadowPuck, _goalie: Goalie) -> void:
	pass

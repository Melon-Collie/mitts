class_name PuckRestitution

# Coefficient of restitution of a FROZEN game puck against a rigid wall, as a
# function of the puck's normal (into-the-wall) impact speed. Every puck bounce in
# the game — boards, goal iron, goalie gear — is this curve times a surface's own
# COR scale (≤ 1): a surface can absorb more than a rigid wall, never return more.
#
# Pure / static, allocation-free; mirrored by NativePuckStep::rigid_wall_cor.

# Slow end: Haché (The Physics of Hockey) drops a frozen puck on concrete and it
# rebounds to ~12% of the drop height, so COR = √0.12 ≈ 0.35. The speed is a
# ~1 m drop (√(2·g·1 m)); the book does not publish the height.
const COR_SLOW: float = 0.35
const SLOW_SPEED_M_S: float = 4.4
# Fast end: Anderson / Bigford & Smith (WSU 2008; J. ASTM Int. 6(7), 2009) fired
# pucks at a rigid plate at 55–85 mph and found COR falling with impact speed;
# a frozen puck at shot speed sits near 0.27. Flat beyond — no data past either end.
const COR_FAST: float = 0.27
const FAST_SPEED_M_S: float = 30.0


static func rigid_wall(normal_speed_m_s: float) -> float:
	var t: float = clampf((normal_speed_m_s - SLOW_SPEED_M_S)
			/ (FAST_SPEED_M_S - SLOW_SPEED_M_S), 0.0, 1.0)
	return lerpf(COR_SLOW, COR_FAST, t)

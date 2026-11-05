extends RefCounted

# The staged states the threat truth table is measured from (docs/xt-plan.md,
# Step 1), shared by its instrument and the test that scores models against it,
# so both read the same state. No class_name (test infra stays out of the global
# namespace).
#
# Team 0 attacks −Z with the puck at the spot. Its carrier's mates support him:
# one across, one trailing; in 5v5 two more, wider and deeper. Each context:
#   SET    every defender goal-side of his man, a gap off him, all near still
#   RUSH   one defender back, goal-side of the carrier; the rest trailing the
#          play, skating back; the attack coming at pace
# A seeded generator jitters every position and velocity; none stages the
# canonical state.

const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const GAP_M: float = 2.5
const TRAIL_M: float = 4.0
const JITTER_M: float = 0.8
const JITTER_M_S: float = 1.0
const RUSH_M_S: float = 6.0
const SET_M_S: float = 1.0
# Bodies are staged this far off the boards and the cages.
const BODY_CLEARANCE_M: float = 0.6
const CONTEXTS: Array[String] = ["SET", "RUSH"]


static func spot(x: float, out: float) -> Vector3:
	return Vector3(x, 0.0, GOAL_Z + out)


# Rows [peer, team, pos, vel]: team 0's carrier is peer 1, then his mates;
# team 1 is peers 101 on, each staged against the attacker of the same index.
static func stage(at: Vector3, context: String, team_size: int,
		rng: RandomNumberGenerator = null) -> Array:
	var net := Vector3(0.0, 0.0, GOAL_Z)
	var side: float = -1.0 if at.x > 0.5 else 1.0
	var attack: Array[Vector3] = [at,
			Vector3(side * 6.0, 0.0, at.z + 1.5),
			Vector3(0.0, 0.0, at.z + 7.0)]
	if team_size >= 5:
		attack.append(Vector3(-side * 8.0, 0.0, at.z + 9.0))
		attack.append(Vector3(side * 8.0, 0.0, at.z + 10.0))
	var rush: bool = context == "RUSH"
	var attack_v := Vector3(0.0, 0.0, -RUSH_M_S if rush else -SET_M_S)
	var rows: Array = []
	for i: int in attack.size():
		var p: Vector3 = legal(attack[i] if i == 0 else attack[i] + jitter(rng))
		rows.append([1 + i, 0, p, attack_v + jitter_v(rng)])
	for i: int in attack.size():
		var man: Vector3 = rows[i][2]
		var p: Vector3
		var v: Vector3
		if not rush or i == 0:
			p = man + (net - man).normalized() * GAP_M
			v = attack_v * 0.8 if rush else Vector3.ZERO
		else:
			p = man + Vector3(0.0, 0.0, TRAIL_M)
			v = attack_v * 1.1
		rows.append([101 + i, 1, legal(p + jitter(rng)), v + jitter_v(rng)])
	return rows


static func jitter(rng: RandomNumberGenerator) -> Vector3:
	if rng == null:
		return Vector3.ZERO
	return Vector3(rng.randf_range(-JITTER_M, JITTER_M), 0.0, rng.randf_range(-JITTER_M, JITTER_M))


static func jitter_v(rng: RandomNumberGenerator) -> Vector3:
	if rng == null:
		return Vector3.ZERO
	return Vector3(rng.randf_range(-JITTER_M_S, JITTER_M_S), 0.0,
			rng.randf_range(-JITTER_M_S, JITTER_M_S))


static func legal(p: Vector3) -> Vector3:
	var xz: Vector2 = GameRules.push_out_of_net(GameRules.clamp_to_rink_inner(
			Vector2(p.x, p.z), BODY_CLEARANCE_M), BODY_CLEARANCE_M)
	return Vector3(xz.x, 0.0, xz.y)

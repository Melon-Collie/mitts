extends GutTest

# ── WHERE THE GOALIE'S ELBOWS GO ─────────────────────────────────────────────
# Builds the live rig in each stance and measures the arm. The elbow may not
# sit behind the shoulder (in his chest) or inside it (in his ribs); the
# hanging solve (TwoBoneIK.solve_elbow_hanging) holds both. The bend is reported
# alongside, because an arm folded far past a right angle is what a hand held
# too close to the body looks like, whatever the elbow does — so the stances
# that hold the glove out are held to a real bend.
#
# The butterfly BLOCKER stays cramped (~55°): the stick fixes its hand, and the
# butterfly trunk (GoalieAnatomy.torso_span) puts the shoulder barely above it.

const State := GoalieStateMachine.State
const STANCES: Array[int] = [
	State.STANDING, State.READY, State.BUTTERFLY, State.HALF_BUTTERFLY_LEFT,
	State.HALF_BUTTERFLY_RIGHT, State.SLIDING, State.RVH_LEFT, State.VH_RIGHT,
	State.COVERING, State.CATCHING,
]
const TOL: float = 0.005
# Stances whose glove is posed out in front (GoalieAnatomy.hand_depth_for_bend);
# the post stances, the smother and the catch hold committed hands.
const HELD_OUT: Array[String] = [
	"STANDING", "READY", "BUTTERFLY", "HALF_BUTTERFLY_LEFT", "HALF_BUTTERFLY_RIGHT",
	"SLIDING", "BUTTERFLY (block)",
]


func _posed(state: int, blocking: bool = false) -> Goalie:
	var g: Goalie = load("res://Scenes/Goalie.tscn").instantiate()
	add_child_autofree(g)
	var b := GoalieBodyConfigBuilder.new()
	var i := GoalieBodyConfigBuilder.Inputs.new()
	i.state = state
	i.direction_sign = 1
	i.blocking_seal = blocking
	g.apply_body_config(b.build(i), 1.0)
	g._update_connectors()
	return g


func _check(g: Goalie, label: String) -> void:
	var body: Node3D = g.get_node("Body")
	for side: float in [-1.0, 1.0]:
		var shoulder: Vector3 = body.position + body.basis * Vector3(0.23 * side, 0.24, 0.0)
		var elbow: Vector3 = (g.glove_elbow_sphere if side < 0.0 else g.blocker_elbow_sphere).position
		var hand: Vector3 = (g.get_node("Glove") if side < 0.0 else g.get_node("BlockArm")).position
		var fwd: float = shoulder.z - elbow.z          # he faces -Z
		var out: float = (elbow.x - shoulder.x) * side
		var bend: float = rad_to_deg((shoulder - elbow).angle_to(hand - elbow))
		var arm: String = "glove" if side < 0.0 else "blocker"
		gut.p("%-22s %-7s fwd %+.2f out %+.2f down %+.2f  elbow %3.0f°" % [
				label, arm, fwd, out, shoulder.y - elbow.y, bend])
		assert_gte(fwd, -TOL, "%s %s: elbow behind the shoulder" % [label, arm])
		assert_gte(out, -TOL, "%s %s: elbow inside the shoulder" % [label, arm])
		if side < 0.0 and label in HELD_OUT:
			assert_between(bend, 75.0, 160.0, "%s glove: held out at a real bend" % label)


func test_no_elbow_folds_into_the_body() -> void:
	for st: int in STANCES:
		_check(_posed(st), GoalieStateMachine.State.keys()[st])
	_check(_posed(State.BUTTERFLY, true), "BUTTERFLY (block)")

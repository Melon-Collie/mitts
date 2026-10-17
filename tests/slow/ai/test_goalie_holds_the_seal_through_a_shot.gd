extends GutTest

# A shot released while the goalie is sealed on the post (RVH or VH) keeps him
# in the seal until it resolves: standing up or swapping posts mid-flight moves
# the post pad into the puck. Slow and fast flat shots from the goal line out to
# the boards, on the real controller; and once the shot is over the seal lets go.

const Stager := preload("res://tests/unit/ai/shot_odds_stager.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = 1.0 / 120.0

var _s: RefCounted
var _c: GoalieController
var _p: Node
var _sh: Skater
var _broken: int = 0


func before_each() -> void:
	var goalie: Node = load("res://Scenes/Goalie.tscn").instantiate()
	_p = load("res://Scenes/Puck.tscn").instantiate()
	_sh = load("res://Scenes/Skater.tscn").instantiate() as Skater
	_c = GoalieController.new()
	add_child_autofree(goalie)
	add_child_autofree(_p)
	add_child_autofree(_sh)
	add_child_autofree(_c)
	_s = Stager.new(goalie, _p, _c, _sh)
	_c._sm.transitioned.connect(_on_transition)


func _on_transition(_prev: int, _now: int) -> void:
	if not _c._sm.is_post_integrated() and GoalieBehaviorRules.detect_shot_into(
			_p.global_position, _p.linear_velocity, GOAL_Z, 0.0, _c._universal_shot_cfg,
			GoalieBehaviorRules.ShotResult.new()).is_shot:
		_broken += 1


# Sealed on a carrier who came round from behind the line to `front` m in
# front of it at `x`, still inside the post-stance swap deadband or out at VH.
func _seal_at(x: float, front: float) -> Vector3:
	var behind := Vector3(x, 0.0, GOAL_Z - 0.5)
	var spot := Vector3(x, 0.0, GOAL_Z + front)
	_s._h.settle_ready(behind)
	for i: int in 30:
		var p: Vector3 = behind.lerp(spot, float(i + 1) / 30.0)
		_sh.global_position = p
		_p.global_position = p
		_c._physics_process(DT)
	for i: int in 20:
		_c._physics_process(DT)
	return spot


func test_a_shot_from_the_seal_keeps_him_sealed_until_it_resolves() -> void:
	var shots: int = 0
	for x: float in [-9.0, -5.0, -2.5, 2.5, 5.0, 9.0]:
		for front: float in [0.05, 0.3, 0.6]:
			for speed: float in [5.0, 9.0, 32.0]:
				for aim: int in [0, 6, 12, 17, 23]:
					var spot: Vector3 = _seal_at(x, front)
					if not _c._sm.is_post_integrated():
						continue
					_broken = 0
					_s._h.fire_release_at(spot, Vector3(Stager.aim_x(aim), 0.0, GOAL_Z),
							ShotMechanics.ELEVATION_FLAT, speed, 0.0)
					shots += 1
					assert_eq(_broken, 0, "x %.1f, %.2f m out, %.0f m/s, aim %d: the seal held"
							% [x, front, speed, aim])
	assert_gt(shots, 100, "the sweep staged sealed keepers")


func test_the_seal_lets_go_once_the_shot_is_over() -> void:
	var spot: Vector3 = _seal_at(5.0, 0.3)
	assert_true(_c._sm.is_post_integrated(), "precondition: sealed")
	_s._h.fire_release_at(spot, Vector3(Stager.aim_x(4), 0.0, GOAL_Z),
			ShotMechanics.ELEVATION_FLAT, 9.0, 0.0)
	# The puck is picked up out front: no shot in flight, and no longer a sharp angle.
	var slot := Vector3(0.0, 0.0, GOAL_Z + 6.0)
	_sh.global_position = slot
	_p.set_carrier(_sh)
	for i: int in 60:
		_p.global_position = slot
		_c._physics_process(DT)
	assert_false(_c._sm.is_post_integrated(), "carried out front, he comes off the post")

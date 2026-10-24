extends GutTest

# Rebounds are the equipment, not a doctrine: what the rebound model
# (GoalieSaveRules) asserts is a claim about GEAR — how stiff each
# surface is, and how the puck's own COR falls as the impact hardens. These pin
# the claims, not the digits: a material row may be retuned, but a blocker that
# rebounds softer than a chest protector is a bug in the table.

const _SQUARE_N := Vector3(0.0, 0.0, 1.0)   # face pointing back at the shooter


func _square_rebound(part: int, speed: float) -> float:
	return GoalieSaveRules.rebound_velocity(
			Vector3(0.0, 0.0, -speed), part, _SQUARE_N).length()


func test_save_surfaces_rank_by_how_stiff_the_gear_is() -> void:
	# Composite paddle > board-backed blocker > foam-over-core pad > foam over a
	# torso that gives > a leather pocket the hand did not close on.
	var stick: float = _square_rebound(GoalieSaveRules.SavePart.STICK, 20.0)
	var blocker: float = _square_rebound(GoalieSaveRules.SavePart.BLOCKER, 20.0)
	var pad: float = _square_rebound(GoalieSaveRules.SavePart.PAD, 20.0)
	var glove: float = _square_rebound(GoalieSaveRules.SavePart.GLOVE, 20.0)
	var chest: float = _square_rebound(GoalieSaveRules.SavePart.CHEST, 20.0)
	assert_gt(stick, blocker, "the paddle is the stiffest thing on him")
	assert_gt(blocker, pad, "a board behind thin foam beats a pad built to absorb")
	assert_gt(pad, chest, "a chest over a body that gives kills more than a leg pad")
	assert_gt(chest, glove, "and an unclosed glove kills the most")


func test_a_harder_shot_keeps_less_of_itself_but_still_rebounds_faster() -> void:
	# The two halves of the COR falloff, and the reason it is not a control knob:
	# a hard shot RETAINS a smaller fraction, which is the measured puck
	# behaviour, and still comes off FASTER in absolute terms — which is why hard
	# shots make dangerous rebounds and soft ones die in front of him.
	var soft_in: float = 8.0
	var hard_in: float = 34.0
	var soft: float = _square_rebound(GoalieSaveRules.SavePart.PAD, soft_in)
	var hard: float = _square_rebound(GoalieSaveRules.SavePart.PAD, hard_in)
	assert_lt(hard / hard_in, soft / soft_in, "the hard shot keeps a smaller share")
	assert_gt(hard, soft, "and still leaves faster — the second chance is real")


func test_a_glance_survives_where_a_square_hit_dies() -> void:
	# One contact model across the whole game: the same split that makes a
	# glancing board carom keep its pace and a glancing blade tip a redirect.
	var square: Vector3 = GoalieSaveRules.rebound_velocity(
			Vector3(0.0, 0.0, -20.0), GoalieSaveRules.SavePart.PAD, _SQUARE_N)
	var glance: Vector3 = GoalieSaveRules.rebound_velocity(
			Vector3(19.0, 0.0, -6.2), GoalieSaveRules.SavePart.PAD, _SQUARE_N)
	assert_gt(glance.length(), square.length() * 2.0,
			"a puck sliding across the pad keeps its pace; a square hit does not")


# ── Cover / freeze doctrine (USA Hockey cover-vs-clear hierarchy) ─────────────

# ── Catch-and-hold doctrine ───────────────────────────────────────────────────

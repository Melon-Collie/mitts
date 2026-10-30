class_name CarryPostureRules

# A skater with both hands on the stick folds his chest over it, so his
# shoulders, and with them his hands, sit out in front of his hips rather than
# over them; standing upright, the top hand hangs at his hip and the bottom one
# can only reach the shaft across his belly. The fold is the chest's alone (the
# trunk texture), never the frame the blade hangs from, and the hand solve
# measures both shoulders folded the same way, in the chest's own frame
# (SkaterIKCoordinator.arm_shoulder) — which is how the faceoff address folds.
#
# A pure function of state every peer has (the blade's place, the posture's own
# fold), so it needs no wire field and replays as it ran.


# How far the chest folds (radians, positive forward), from the blade's place
# across the ice in the skater's facing frame (−y ahead) and the posture's own
# fold (Skater.trunk_fold, negative forward): `carry_fold` while the blade is
# in front of him, out to ~37° either side, so a dangle across his front never
# moves it and the fold never feeds back into the strokes; none from ~78° round
# to behind, where a fold toward the facing carries the shoulders away from the
# blade. Pulled in tight he stands up out of it, the hands coming back to his
# hip, as far as the blade comes inside `_OUT_M` (m off his centre: none inside
# the near end, all of it past the far one, where a standing carry with the
# fold rests). It tops the posture's own fold up to that, never adds to it: a
# skater already folded over his skating has his hands out front.
const _AHEAD := Vector2(0.2, 0.8)
const _OUT_M := Vector2(0.55, 0.95)

static func fold(blade_in_facing: Vector2, posture_fold: float, carry_fold: float) -> float:
	var out: float = blade_in_facing.length()
	var ahead: float = 1.0
	if out > 0.01:
		ahead = smoothstep(_AHEAD.x, _AHEAD.y, -blade_in_facing.y / out)
	ahead *= smoothstep(_OUT_M.x, _OUT_M.y, out)
	return maxf(carry_fold * ahead - maxf(-posture_fold, 0.0), 0.0)


# A shoulder marker (UpperBody-local) as the folded chest carries it.
static func folded_shoulder(marker: Vector3, chest_fold: float) -> Vector3:
	if chest_fold < 0.00001:
		return marker
	return Basis(Vector3.RIGHT, -chest_fold) * marker

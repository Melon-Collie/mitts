extends GutTest

# ArmTechnique's rules, one at a time: a carry a player holds passes them all,
# and each rule, and only it, stops a hold that breaks it.

const DEG: float = PI / 180.0
const STICK_M: float = 1.34


func _body() -> ArmAnatomyBody:
	var body := ArmAnatomyBody.new()
	body.top_shoulder = Vector3(0.22, 0.42, 0.0)
	body.bottom_shoulder = Vector3(-0.22, 0.42, 0.0)
	body.torso_in_spine = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0))
	body.torso_profile = SkaterMeshBuilder.TORSO_PROFILE
	body.torso_sway = SkaterMeshBuilder.TORSO_REAR_SWAY
	body.torso_xz_scale = SkaterMeshBuilder.TORSO_XZ_SCALE
	body.knob_extend = 0.13
	body.blade_length = 0.3
	body.blade_lie = 42.0 * DEG
	return body


# The top hand at the hip in front of the body, the shaft standing at the
# stick's lie to a blade ahead on the forehand, the hands a forearm apart.
func _carry(body: ArmAnatomyBody) -> ArmTechnique.Hold:
	var h := ArmTechnique.Hold.new()
	h.top_hand = Vector3(0.15, 0.0, -0.3)
	_aim(h, Vector3(-0.35, 0.0, -0.94).normalized(), body.blade_lie)
	h.spacing = 0.3
	h.top_shoulder = body.top_shoulder
	h.torso = body.torso_in_spine
	return h


func _aim(h: ArmTechnique.Hold, heading: Vector3, lie: float) -> void:
	h.shaft = heading * cos(lie) + Vector3.DOWN * sin(lie)
	h.heel = h.top_hand + h.shaft * STICK_M
	h.blade_dir = heading


func _verdict(body: ArmAnatomyBody, h: ArmTechnique.Hold) -> ArmTechnique.Verdict:
	var v := ArmTechnique.Verdict.new()
	ArmTechnique.assess(body, h, v)
	return v


func test_a_carry_at_the_hip_passes_every_rule() -> void:
	var body: ArmAnatomyBody = _body()
	var v: ArmTechnique.Verdict = _verdict(body, _carry(body))
	assert_true(v.holds(), "held as players hold it (%s)" % ArmTechnique.Limit.keys()[v.binding])


func test_each_rule_stops_the_hold_that_breaks_it() -> void:
	var body: ArmAnatomyBody = _body()
	var cases := {
		ArmTechnique.Limit.TOP_HAND_LOW: func(h: ArmTechnique.Hold) -> void:
			h.top_hand.y = -0.3
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.TOP_HAND_HIGH: func(h: ArmTechnique.Hold) -> void:
			h.top_hand.y = 0.35
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.TOP_HAND_BEHIND: func(h: ArmTechnique.Hold) -> void:
			h.top_hand = Vector3(0.35, 0.0, 0.2)
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.TOP_HAND_OUT: func(h: ArmTechnique.Hold) -> void:
			h.top_hand.x = 0.55
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.TOP_HAND_ACROSS: func(h: ArmTechnique.Hold) -> void:
			h.top_hand.x = -0.3
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.HANDS_APART: func(h: ArmTechnique.Hold) -> void:
			h.spacing = 0.6,
		ArmTechnique.Limit.KNOB_IN_BODY: func(h: ArmTechnique.Hold) -> void:
			h.top_hand = Vector3(0.05, 0.05, -0.15)
			_aim(h, h.blade_dir, body.blade_lie),
		ArmTechnique.Limit.PUCK_UNDER_BODY: func(h: ArmTechnique.Hold) -> void:
			h.heel = Vector3(0.05, -1.0, -0.1)
			h.blade_dir = Vector3.LEFT,
		ArmTechnique.Limit.LIE: func(h: ArmTechnique.Hold) -> void:
			_aim(h, h.blade_dir, 70.0 * DEG),
	}
	for limit: ArmTechnique.Limit in cases:
		var h: ArmTechnique.Hold = _carry(body)
		(cases[limit] as Callable).call(h)
		var v: ArmTechnique.Verdict = _verdict(body, h)
		assert_eq(ArmTechnique.Limit.keys()[v.binding], ArmTechnique.Limit.keys()[limit],
				"the rule that stops it")
		assert_gt(v.violation, 0.0, "and by how much")

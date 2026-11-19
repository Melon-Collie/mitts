extends GutTest

# AIPingDirectives — the host-side "obey the ping" store: expiry on the
# internal clock, per-pinger replacement, slot/threat overrides, and the
# per-bot queries the state machine / carrier read through RoleContext.

const PINGER: int = 1
const BOT_A: int = 10000
const BOT_B: int = 10001
const OPP: int = 3
const OPP_B: int = 4
const TEAM: int = 0
const TEAM_BY_PEER: Dictionary = {1: 0, 2: 0, 10000: 0, 10001: 0, 3: 1, 4: 1}

var _d: AIPingDirectives


func before_each() -> void:
	_d = AIPingDirectives.new()


func test_starts_empty() -> void:
	assert_true(_d.is_empty())
	assert_eq(_d.move_target_for(BOT_A), Vector3.INF)
	assert_eq(_d.chase_peer(), -1)
	assert_false(_d.shoot_ping_for(BOT_A))
	assert_eq(_d.pass_target_for(BOT_A), -1)


func test_go_there_move_target_is_scoped_to_the_obeyer() -> void:
	var spot := Vector3(4.0, 0.0, -6.0)
	_d.add(PingRules.Type.GO_THERE, PINGER, -1, BOT_A, spot, 5.0)
	assert_eq(_d.move_target_for(BOT_A), spot)
	assert_eq(_d.move_target_for(BOT_B), Vector3.INF)


func test_directive_expires_on_the_internal_clock() -> void:
	_d.add(PingRules.Type.GO_THERE, PINGER, -1, BOT_A, Vector3.ONE, 2.0)
	_d.advance(1.9)
	assert_eq(_d.move_target_for(BOT_A), Vector3.ONE)
	_d.advance(0.2)
	assert_true(_d.is_empty())
	assert_eq(_d.move_target_for(BOT_A), Vector3.INF)


func test_new_ping_from_same_pinger_replaces_the_old_order() -> void:
	_d.add(PingRules.Type.GO_THERE, PINGER, -1, BOT_A, Vector3.ONE, 5.0)
	_d.add(PingRules.Type.SHOOT, PINGER, BOT_B, BOT_B, Vector3.ZERO, 3.0)
	assert_eq(_d.move_target_for(BOT_A), Vector3.INF, "GO_THERE was replaced")
	assert_true(_d.shoot_ping_for(BOT_B))


func test_shoot_ping_matches_the_pinged_carrier_only() -> void:
	_d.add(PingRules.Type.SHOOT, PINGER, BOT_A, BOT_A, Vector3.ZERO, 3.0)
	assert_true(_d.shoot_ping_for(BOT_A))
	assert_false(_d.shoot_ping_for(BOT_B))


func test_pass_ping_feeds_any_carrier_except_the_pinger() -> void:
	_d.add(PingRules.Type.PASS_TO_ME, PINGER, PINGER, -1, Vector3.ZERO, 4.0)
	assert_eq(_d.pass_target_for(BOT_A), PINGER)
	assert_eq(_d.pass_target_for(PINGER), -1,
			"the pinger's own carry never passes to itself")


func test_the_most_recent_pass_call_wins() -> void:
	_d.add(PingRules.Type.PASS_TO_ME, PINGER, PINGER, -1, Vector3.ZERO, 4.0)
	_d.advance(1.0)
	_d.add(PingRules.Type.IM_OPEN, PINGER + 1, PINGER + 1, -1, Vector3.ZERO, 4.0)
	assert_eq(_d.pass_target_for(BOT_A), PINGER + 1)
	_d.advance(1.0)
	_d.add(PingRules.Type.PASS_TO_ME, PINGER, PINGER, -1, Vector3.ZERO, 4.0)
	assert_eq(_d.pass_target_for(BOT_A), PINGER,
			"calling again takes it back, whatever order they first called in")


func test_chase_peer_reports_the_get_puck_obeyer() -> void:
	_d.add(PingRules.Type.GET_PUCK, PINGER, -1, BOT_B, Vector3.ZERO, 4.0)
	assert_eq(_d.chase_peer(), BOT_B)


# ── Slot / threat overrides ──────────────────────────────────────────────────

func test_cover_him_pins_mark_slot_and_threat() -> void:
	_d.add(PingRules.Type.COVER_HIM, PINGER, OPP, BOT_A, Vector3.ZERO, 6.0)
	var slots: Dictionary[int, int] = {BOT_A: AIRoleSlots.Slot.FINISHER}
	var threats: Dictionary[int, int] = {}
	_d.apply_overrides(slots, threats, -1)
	assert_eq(slots[BOT_A], AIRoleSlots.Slot.MARK)
	assert_eq(threats[BOT_A], OPP)


func test_pressure_and_get_open_and_defend_force_their_slots() -> void:
	_d.add(PingRules.Type.PRESSURE_CARRIER, PINGER, OPP, BOT_A, Vector3.ZERO, 5.0)
	_d.add(PingRules.Type.GET_OPEN, PINGER + 1, BOT_B, BOT_B, Vector3.ZERO, 4.0)
	var slots: Dictionary[int, int] = {}
	var threats: Dictionary[int, int] = {}
	_d.apply_overrides(slots, threats, -1)
	assert_eq(slots[BOT_A], AIRoleSlots.Slot.PRESSURE)
	assert_eq(slots[BOT_B], AIRoleSlots.Slot.FINISHER)

	_d.clear()
	_d.add(PingRules.Type.DEFEND, PINGER, BOT_A, BOT_A, Vector3.ZERO, 5.0)
	slots.clear()
	_d.apply_overrides(slots, threats, -1)
	assert_eq(slots[BOT_A], AIRoleSlots.Slot.MARK)


func test_overrides_never_touch_the_current_carrier() -> void:
	_d.add(PingRules.Type.GET_OPEN, PINGER, BOT_A, BOT_A, Vector3.ZERO, 4.0)
	var slots: Dictionary[int, int] = {BOT_A: AIRoleSlots.Slot.CARRIER}
	var threats: Dictionary[int, int] = {}
	_d.apply_overrides(slots, threats, BOT_A)
	assert_eq(slots[BOT_A], AIRoleSlots.Slot.CARRIER,
			"the bot playing the puck keeps its role")


func test_go_there_applies_no_slot_override() -> void:
	_d.add(PingRules.Type.GO_THERE, PINGER, -1, BOT_A, Vector3.ONE, 5.0)
	var slots: Dictionary[int, int] = {BOT_A: AIRoleSlots.Slot.SUPPORT}
	var threats: Dictionary[int, int] = {}
	_d.apply_overrides(slots, threats, -1)
	assert_eq(slots[BOT_A], AIRoleSlots.Slot.SUPPORT,
			"GO_THERE only commandeers steering, not the role")


# ── An order ends when the play it asked for is settled ──────────────────────

func _changed(prev: int, now: int) -> bool:
	return _d.on_carrier_changed(prev, now, TEAM, TEAM_BY_PEER)


func test_a_pass_call_ends_when_the_caller_has_the_puck() -> void:
	_d.add(PingRules.Type.PASS_TO_ME, PINGER, PINGER, -1, Vector3.ZERO, 4.0)
	assert_false(_changed(BOT_A, -1), "the feed in flight is still the order")
	assert_eq(_d.pass_target_for(BOT_A), PINGER)
	assert_true(_changed(-1, PINGER))
	assert_eq(_d.pass_target_for(BOT_A), -1,
			"a give-and-go back to the bot is not fed straight back")


func test_a_shoot_call_ends_when_the_carrier_lets_it_go() -> void:
	_d.add(PingRules.Type.SHOOT, PINGER, BOT_A, BOT_A, Vector3.ZERO, 3.0)
	assert_false(_changed(-1, BOT_A),
			"the brain's belief catching up to the carrier he was pinged as")
	assert_true(_d.shoot_ping_for(BOT_A))
	assert_true(_changed(BOT_A, -1))
	assert_false(_d.shoot_ping_for(BOT_A))


func test_a_retrieval_ends_when_anyone_has_the_puck() -> void:
	_d.add(PingRules.Type.GET_PUCK, PINGER, -1, BOT_A, Vector3.ZERO, 4.0)
	assert_false(_changed(OPP, -1), "it coming loose is what he was sent for")
	assert_eq(_d.chase_peer(), BOT_A)
	assert_true(_changed(-1, OPP))
	assert_eq(_d.chase_peer(), -1, "the next loose puck is the election's")


func test_get_open_ends_on_a_turnover_but_not_on_our_pass() -> void:
	_d.add(PingRules.Type.GET_OPEN, PINGER, BOT_A, BOT_A, Vector3.ZERO, 4.0)
	assert_false(_changed(PINGER, -1), "our pass on its way to him")
	assert_false(_changed(-1, BOT_B), "another of ours has it")
	assert_true(_changed(BOT_B, OPP))
	assert_true(_d.is_empty())


func test_get_open_ends_when_he_gets_the_puck() -> void:
	_d.add(PingRules.Type.GET_OPEN, PINGER, BOT_A, BOT_A, Vector3.ZERO, 4.0)
	assert_true(_changed(-1, BOT_A))


func test_defensive_orders_end_when_we_win_the_puck() -> void:
	_d.add(PingRules.Type.COVER_HIM, PINGER, OPP_B, BOT_A, Vector3.ZERO, 6.0)
	_d.add(PingRules.Type.DEFEND, PINGER + 1, BOT_B, BOT_B, Vector3.ZERO, 5.0)
	assert_false(_changed(OPP, -1), "loose is not ours yet")
	assert_false(_changed(-1, OPP_B), "the man he covers taking it is no release")
	assert_true(_changed(OPP_B, PINGER))
	assert_true(_d.is_empty(), "nobody man-marks while his own team attacks")


func test_pressure_ends_when_the_man_no_longer_has_it() -> void:
	_d.add(PingRules.Type.PRESSURE_CARRIER, PINGER, OPP, BOT_A, Vector3.ZERO, 5.0)
	assert_false(_changed(OPP_B, OPP),
			"the brain's belief catching up to the carrier he was pinged as")
	assert_true(_changed(OPP, OPP_B), "he moved it: the order was him, not the puck")
	assert_true(_d.is_empty())


func test_a_spot_is_held_until_the_bot_has_the_puck() -> void:
	var spot := Vector3(4.0, 0.0, -6.0)
	_d.add(PingRules.Type.GO_THERE, PINGER, -1, BOT_A, spot, 5.0)
	assert_false(_changed(PINGER, OPP), "a turnover does not move the spot")
	assert_eq(_d.move_target_for(BOT_A), spot)
	assert_true(_changed(OPP, BOT_A))
	assert_eq(_d.move_target_for(BOT_A), Vector3.INF)

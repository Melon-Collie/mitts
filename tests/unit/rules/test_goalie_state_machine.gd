extends GutTest

# GoalieStateMachine — the stance enum the wire carries, and its families.

var sm: GoalieStateMachine

func before_each() -> void:
	sm = GoalieStateMachine.new()

func test_initial_state_is_standing() -> void:
	assert_eq(sm.current, GoalieStateMachine.State.STANDING)

func test_is_upright_for_standing() -> void:
	assert_true(sm.is_upright())

func test_is_upright_for_ready() -> void:
	sm.current = GoalieStateMachine.State.READY
	assert_true(sm.is_upright())

func test_is_upright_false_for_recovering() -> void:
	sm.current = GoalieStateMachine.State.RECOVERING
	assert_false(sm.is_upright(), "RECOVERING is the vulnerable stand-up window; not upright")

func test_is_upright_false_for_butterfly() -> void:
	sm.current = GoalieStateMachine.State.BUTTERFLY
	assert_false(sm.is_upright())

func test_pads_on_ice_by_family() -> void:
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.READY), 0)
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.RECOVERING), 0)
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.BUTTERFLY), 2)
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.RVH_LEFT), 2)
	assert_eq(GoalieStateMachine.pads_on_ice(GoalieStateMachine.State.HALF_BUTTERFLY_RIGHT), 1)

# The values ride the wire as a u8 (GoalieNetworkState.state_enum): a reorder
# re-labels every goalie on every client.
func test_enum_int_values_are_the_wire_values() -> void:
	assert_eq(GoalieStateMachine.State.STANDING as int, 0)
	assert_eq(GoalieStateMachine.State.BUTTERFLY as int, 1)
	assert_eq(GoalieStateMachine.State.RECOVERING as int, 2)
	assert_eq(GoalieStateMachine.State.RVH_LEFT as int, 3)
	assert_eq(GoalieStateMachine.State.RVH_RIGHT as int, 4)
	assert_eq(GoalieStateMachine.State.READY as int, 5)
	assert_eq(GoalieStateMachine.State.SLIDING as int, 6)
	assert_eq(GoalieStateMachine.State.HALF_BUTTERFLY_RIGHT as int, 15)

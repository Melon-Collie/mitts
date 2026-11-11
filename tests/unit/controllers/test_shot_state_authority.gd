extends GutTest

# ShotStateAuthority.server_applies: the host's ack-time shot state overwrites
# the client's live one only when the replay from it does not land on the live
# state and no in-flight guard holds.

const State = SkaterStateMachine.State


func _applies(server: State, live: State, replayed: State,
		has_puck: bool = true, pinning: bool = false) -> bool:
	return ShotStateAuthority.server_applies(server, live, replayed, has_puck, pinning)


func test_agreement_applies_nothing() -> void:
	assert_false(_applies(State.WRISTER_AIM, State.WRISTER_AIM, State.SKATING_WITH_PUCK))


func test_a_replay_that_reproduces_the_live_state_means_the_host_is_only_late() -> void:
	# The called-off wrister, the called-off puckless wind-up, and a one-timer
	# already swung: each is the host not having read the input yet.
	assert_false(_applies(State.WRISTER_AIM, State.SKATING_WITH_PUCK, State.SKATING_WITH_PUCK))
	assert_false(_applies(State.SLAPPER_CHARGE_WITHOUT_PUCK, State.SKATING_WITHOUT_PUCK,
			State.SKATING_WITHOUT_PUCK, false))
	assert_false(_applies(State.SLAPPER_CHARGE_WITHOUT_PUCK, State.FOLLOW_THROUGH,
			State.FOLLOW_THROUGH, false))


func test_follow_through_holds_against_any_wind_up() -> void:
	for server: State in [State.WRISTER_AIM, State.SLAPPER_CHARGE_WITH_PUCK,
			State.SLAPPER_CHARGE_WITHOUT_PUCK, State.ONE_TIMER_RETENTION]:
		assert_false(_applies(server, State.FOLLOW_THROUGH, server),
				"FOLLOW_THROUGH must hold against a lagged %s" % State.keys()[server])


func test_retention_is_client_owned() -> void:
	assert_false(_applies(State.FOLLOW_THROUGH, State.ONE_TIMER_RETENTION, State.FOLLOW_THROUGH))
	assert_false(_applies(State.SKATING_WITHOUT_PUCK, State.ONE_TIMER_RETENTION,
			State.SKATING_WITHOUT_PUCK, false))


func test_an_aim_holds_against_lagged_skating_only_with_the_puck() -> void:
	assert_false(_applies(State.SKATING_WITH_PUCK, State.WRISTER_AIM, State.SKATING_WITH_PUCK))
	assert_true(_applies(State.SKATING_WITHOUT_PUCK, State.WRISTER_AIM,
			State.SKATING_WITHOUT_PUCK, false), "a steal still overrides")


func test_a_puckless_wind_up_holds_against_lagged_skating() -> void:
	assert_false(_applies(State.SKATING_WITHOUT_PUCK, State.SLAPPER_CHARGE_WITHOUT_PUCK,
			State.SKATING_WITHOUT_PUCK, false))


func test_a_called_off_slapshot_holds_through_its_recovery() -> void:
	assert_false(_applies(State.SLAPPER_CHARGE_WITH_PUCK, State.SKATING_WITH_PUCK,
			State.SLAPPER_CHARGE_WITH_PUCK, true, true))
	assert_true(_applies(State.SLAPPER_CHARGE_WITH_PUCK, State.SKATING_WITH_PUCK,
			State.SLAPPER_CHARGE_WITH_PUCK, true, false))

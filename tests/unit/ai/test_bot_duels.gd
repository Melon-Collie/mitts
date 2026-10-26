extends GutTest

# ─── BOT-vs-BOT DUELS ─────────────────────────────────────────────────────────
# Multi-second headless duels between real bot brains (duel_harness.gd — real
# agent decisions + real movement rules + real puck-contact sweeps; facing and
# blade approximated). These pin the EMERGENT sequences this branch built —
# behaviors no single-dispatch unit test can see because they only exist across
# seconds of two brains reacting to each other. Duels are deterministic (the
# bot RNG seeds off peer_id and a fixed host tick under GUT), so outcome
# assertions are stable run-to-run.
#
# ASSERTIONS ARE DELIBERATELY COARSE: "kept the puck and gained ground", never
# "was at (x, z) on tick N". Frame-exact pins would test the harness
# approximations and shatter on every feel-tuning pass.
#
# Duels pin "the duel RESOLVED"; how the carrier gets there is the rolled
# carry's choice, pinned by its own unit tests.
#
# Staging convention: team 0 attacks -Z (net at z = -GOAL_LINE_Z), team 1
# attacks +Z. Duels are staged mid-ice — the harness has no boards.

const DuelHarness := preload("res://tests/unit/ai/duel_harness.gd")

const CARRIER := 101
const DEFENDER := 201
const PUPPET := 301


func test_container_duel_resolves_with_possession() -> void:
	# The headline duel of this branch: a lone defender between the carrier
	# and the net — the containment that used to pacify the carrier into a
	# standstill forever. The carrier may create space first (retreating to
	# build speed is desired behavior), but within the window the duel must
	# RESOLVE: puck advanced past where the container stood, still on the
	# carrier's stick (or deliberately released). Six seconds of jockeying
	# with no progress is the regression this pins against.
	#
	# Staged as a LIVE RUSH, not a standing start: the carrier drives at the
	# net and the container steps up with committed forward momentum — the two
	# closing on each other. This is the regime a cut actually lives in:
	# a container carrying real along-ice momentum can't instantly redirect it,
	# so the carrier's cut beats it. A stationary standing start is the
	# degenerate case — a container with no momentum trivially mirrors every
	# lateral step (velocity-matched seek makes that near-perfect), which is not
	# how containment is ever beaten on the ice.
	#
	# They start 8 m apart, ~0.7 s of closing: nearer, the container's poke lands
	# before anyone has read anything, which is a collision rather than a duel.
	var duel: RefCounted = DuelHarness.new()
	duel.add_skater(CARRIER, 0, Vector3(0, 0, -6.0), null, Vector3(0, 0, -7.0))
	duel.add_skater(DEFENDER, 1, Vector3(0, 0, -14.0), null, Vector3(0, 0, 4.0))
	duel.start(CARRIER)
	# Resolution is checked live, not on the final frame: the carrier beats
	# the container (dump-past or carry), collects deep, and can then WRAP
	# from behind the harness's net-less goal line — that release sails
	# up-ice unobstructed (no net body for the puck) and the defender's
	# counter moves the end-of-run puck back out. Pinning the last frame
	# would test that missing net, not the duel.
	var resolved: bool = false
	for _i: int in int(6.0 / DuelHarness.DT):
		duel.step()
		if duel.puck_pos.z < -14.0 \
				and (duel.carrier() == CARRIER or duel.releases.size() > 0):
			resolved = true
	assert_true(duel.carrier() == CARRIER or duel.releases.size() > 0,
			"the carrier still owns the puck (or released it deliberately)")
	assert_true(resolved,
			"the puck got past the container's starting line in team-0 hands — the duel resolved")


func test_cornered_carrier_escapes() -> void:
	# A patient scripted container holds the line to the net while a real
	# defender pressures from behind — retreat denied, forward contained. The
	# carrier must get past: the puck crosses the container's depth floor still
	# in team-0 hands, or gets released on net once the lane opens. The
	# container holds 4 m off, its presented stick a metre and a half short of
	# the puck carried ahead: any tighter and the box is closed by the carrier's
	# own read, and the puck rides into the stick.
	var duel: RefCounted = DuelHarness.new()
	duel.add_skater(CARRIER, 0, Vector3(0, 0, -9.0))
	duel.add_puppet_container(PUPPET, 1, Vector3(0, 0, -13.0), 4.0, -13.0)
	duel.add_skater(DEFENDER, 1, Vector3(0, 0, -6.5))
	duel.start(CARRIER)
	var crossed_carrying: bool = false
	for i: int in int(6.0 / DuelHarness.DT):
		duel.step()
		if duel.carrier() == CARRIER and duel.puck_pos.z < -13.0:
			crossed_carrying = true
	assert_true(crossed_carrying or duel.releases.size() > 0,
			"puck carried past the container or released on net")


func test_loose_puck_pickup_is_blade_first() -> void:
	# A lone bot retrieving a loose puck must arrive blade-first — puck picked
	# up OUT IN FRONT of the body (the chase target backs off by the carry-arm
	# offset), not underfoot or beside after an orient-then-skate stop.
	var duel: RefCounted = DuelHarness.new()
	duel.add_skater(CARRIER, 0, Vector3.ZERO)
	duel.start(-1, Vector3(5.0, 0, -5.0))
	var attached: bool = false
	for i: int in int(5.0 / DuelHarness.DT):
		var pos_before: Vector3 = duel.skater_pos(CARRIER)
		var facing_before: Vector2 = duel.skater_facing(CARRIER)
		var puck_before: Vector3 = duel.puck_pos
		duel.step()
		if duel.carrier() == CARRIER:
			attached = true
			var to_puck := Vector3(puck_before.x - pos_before.x, 0.0,
					puck_before.z - pos_before.z)
			assert_gt(to_puck.length(), 0.7,
					"puck met outstretched — the body stops short of the puck point")
			var dir: Vector3 = to_puck.normalized()
			assert_gt(facing_before.x * dir.x + facing_before.y * dir.z, 0.5,
					"puck met out FRONT of the facing, not beside or behind")
			break
	assert_true(attached, "the bot retrieves the loose puck within 5 s")


func test_a_pass_in_flight_is_published_as_its_passers_until_it_is_picked_up() -> void:
	# The host publishes whose release a loose puck is still on
	# (WorldSnapshot.loose_puck_released_by), and the harness snapshot must too,
	# or a soft feed never reads as a pass to the bots it plays. Read over the
	# feed's flight: until someone picks it up, touches it or releases again.
	var goal_z: float = -GameRules.GOAL_LINE_Z
	var duel := DuelHarness.new()
	duel.add_skater(1, 0, Vector3(7, 0, goal_z + 4), null, Vector3(-2, 0, 0))
	duel.add_skater(2, 0, Vector3(-2.5, 0, goal_z + 2.2))
	duel.add_skater(DEFENDER, 1, Vector3(10, 0, goal_z + 7), null, Vector3(-2, 0, 0))
	duel.start(1)
	var flight_ticks: int = 0
	for _t: int in 240:
		duel.step()
		var touches: int = duel.bobbles + duel.deflects + duel.contests
		if duel.releases.size() > 1 or touches > 0:
			break
		var published: int = duel._build_snapshot().loose_puck_released_by
		if duel.releases.is_empty():
			assert_eq(published, -1, "a carried puck is nobody's release")
		elif duel.carrier_id == -1:
			assert_eq(published, 1, "the feed in flight is the passer's")
			flight_ticks += 1
		else:
			assert_eq(published, -1, "a feed picked up is nobody's release")
			break
	assert_gt(flight_ticks, 0, "the carrier fed the back door")

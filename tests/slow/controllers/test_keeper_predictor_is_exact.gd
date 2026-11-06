extends GutTest

# A client's predicted goalie (KeeperPredictor) drawn on the render clock is the
# host's at that instant (#903, docs/goalie-prediction-plan.md, Phase 2). The
# host plays a scripted play (keeper_play_harness.gd), snapping on every
# broadcast tick; a predictor is offered each broadcast's blob a one-way trip
# later and draws the goalie at the render instant (the one-way plus the input
# lead ahead of the host), against the world the host's keeper read (TRUTH),
# or with the shot's release withheld until a snapshot from it has arrived
# (HIDDEN). The drawn goalie is a client KeeperController posed from the
# predictor, as the game draws him, and his save boxes are held against the
# host's at the drawn instant.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")
const TruthWorld := preload("res://tests/harness/keeper_truth_world.gd")
# A 50 ms one-way, in ticks, and the input lead on top of it (the one-way plus
# its ~28 ms margin): the span is 2 × 5 + 3 ticks.
const ONE_WAY: int = 5
const LEAD: int = 8
# The drawn goalie is placed from the wire's root (x, z and a yaw) where the
# host's node is placed from his net's frame, so the same pose lands a few
# microns apart in float32: this is "the same", m.
const SAME_M: float = 1e-4
# Above the snapshot grid's own noise in his drawn boxes (~5 mm): drawn apart
# from the host, m.
const DRIFT_M: float = 0.02


class Run:
	var drawn_ticks: int = 0
	var worst_gap: float = 0.0
	var off_ticks: int = 0
	var first_exact_after_release: int = -1
	var worst_gap_before_release: float = 0.0
	var confirmed: int = 0
	var resteps: int = 0
	var longest_drift: int = 0
	var drift: int = 0


func _host(play: int, back_date: float = 0.0) -> TruthWorld:
	var host := Harness.new(add_child_autofree)
	host.release_back_date = back_date
	var world := TruthWorld.new(host)
	for t: int in Harness.length(play):
		world.record(play, t)
	return world


func _drawn_goalie() -> KeeperController:
	var g: Goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	var p: Puck = autofree(KeeperShadowPuck.new())
	var ctrl := KeeperController.new()
	for n: Node in [g, p, ctrl]:
		add_child_autofree(n)
		n.set_physics_process(false)
		n.set_process(false)
	ctrl.setup(g, p, Harness.GOAL_Z, false)
	return ctrl


# The client, a frame a host tick: each broadcast offered ONE_WAY ticks after
# it, the goalie drawn LEAD ticks ahead of the host, from `from` on.
func _client(world: TruthWorld, release_tick: int, from: int, half_ticks: bool = false) -> Run:
	var pred := KeeperPredictor.new()
	add_child_autofree(pred)
	pred.setup(Harness.GOAL_Z, -1, GoalieSkillProfile.hard(), world)
	var drawn: KeeperController = _drawn_goalie()
	var run := Run.new()
	var ticks: int = world.frames.size()
	for m: int in range(from, ticks - LEAD - 1):
		var n: int = m - ONE_WAY
		if n % 2 == 0:
			world.known_through = n
			pred.offer(world.blobs[n], float(n) * Harness.DT, n / 2)
			pred.note_host_state(world.hosts[n], float(n) * Harness.DT)
		var r: int = m + LEAD
		var render_t: float = (float(r) + (0.5 if half_ticks else 0.0)) * Harness.DT
		if not pred.advance(render_t):
			continue
		drawn._apply_interpolated(pred.drawn)
		run.drawn_ticks += 1
		if half_ticks:
			var a: float = world.box_gap(drawn.goalie, r)
			var b: float = world.box_gap(drawn.goalie, r + 1)
			run.worst_gap = maxf(run.worst_gap, minf(a, b))
			continue
		var gap: float = world.box_gap(drawn.goalie, r)
		run.worst_gap = maxf(run.worst_gap, gap)
		run.drift = run.drift + 1 if gap > DRIFT_M else 0
		run.longest_drift = maxi(run.longest_drift, run.drift)
		if gap > SAME_M:
			run.off_ticks += 1
		elif release_tick >= 0 and n >= release_tick and run.first_exact_after_release < 0:
			run.first_exact_after_release = n
		if release_tick >= 0 and r < release_tick:
			run.worst_gap_before_release = maxf(run.worst_gap_before_release, gap)
	run.confirmed = pred.confirmed
	run.resteps = pred.resteps
	return run


func _release_tick(play: int) -> int:
	return Harness.SETTLE_TICKS + (150 if play == Harness.Play.CARRY_ACROSS else 36)


func _exact(play: int) -> void:
	var world: TruthWorld = _host(play)
	var from: int = Harness.SETTLE_TICKS - 40
	var run: Run = _client(world, -1, from)
	gut.p("%s TRUTH: %d drawn, worst box gap %.6f m, %d snapshots confirmed, %d re-stepped" % [
			Harness.Play.keys()[play], run.drawn_ticks, run.worst_gap, run.confirmed, run.resteps])
	assert_gt(run.drawn_ticks, 100, "drawn predicted through the play")
	assert_eq(run.off_ticks, 0, "drawn instants his boxes parted from the host's")
	assert_lt(run.worst_gap, SAME_M, "the largest box gap, m")
	assert_lte(run.resteps, 0, "snapshots that re-stepped him (the first seeds him)")
	assert_gt(run.confirmed, 40, "snapshots that confirmed him")


func test_a_shot_from_the_slot_is_drawn_as_the_host_has_it() -> void:
	_exact(Harness.Play.SLOT_SHOT)


func test_a_carry_across_and_a_shot_is_drawn_as_the_host_has_it() -> void:
	_exact(Harness.Play.CARRY_ACROSS)


func test_between_ticks_he_is_drawn_between_the_host_ticks() -> void:
	var world: TruthWorld = _host(Harness.Play.SLOT_SHOT)
	var run: Run = _client(world, -1, Harness.SETTLE_TICKS - 40, true)
	assert_gt(run.drawn_ticks, 100)
	# Half a tick between two host poses lies within half their travel of one.
	assert_lt(run.worst_gap, 0.25, "a half-tick blend lies near a host tick's boxes, m")


func test_a_release_he_could_not_see_is_corrected_by_the_next_snapshot() -> void:
	var play: int = Harness.Play.SLOT_SHOT
	var world: TruthWorld = _host(play)
	var release: int = _release_tick(play)
	world.hidden_from = release
	var run: Run = _client(world, release, Harness.SETTLE_TICKS - 40)
	gut.p("HIDDEN: worst box gap %.4f m, %d off, %d confirmed, %d re-stepped; exact again from snapshot %d (release %d)"
			% [run.worst_gap, run.off_ticks, run.confirmed, run.resteps, run.first_exact_after_release, release])
	assert_lt(run.worst_gap_before_release, SAME_M, "exact until the shot")
	assert_gt(run.off_ticks, 0, "the hidden release moved the host's keeper and not the client's")
	assert_gte(run.resteps, 1, "the release's snapshot re-stepped him")
	assert_between(run.first_exact_after_release, release, release + 2,
			"drawn as the host has him from the first snapshot that carries the release")


# The shooter's own client knows his release on its tick and predicts the
# keeper reading it from there. Were the host to read it back-dated by the
# shooter's input lead (its lag comp before the goalie was predicted), the
# keeper the shooter draws would part from the host's at the shot.
func test_the_shooter_draws_the_keeper_only_a_read_from_the_release_tick_gives() -> void:
	var play: int = Harness.Play.SLOT_SHOT
	var release: int = _release_tick(play)
	var lead_s: float = float(LEAD) * Harness.DT
	var exact: Run = _client(_host(play), release, Harness.SETTLE_TICKS - 40)
	var back_dated: Run = _client(_host(play, lead_s), release, Harness.SETTLE_TICKS - 40)
	gut.p("read from the release tick: worst gap %.6f m, %d re-stepped; back-dated %.0f ms: worst gap %.4f m, %d off, %d re-stepped"
			% [exact.worst_gap, exact.resteps, lead_s * 1000.0, back_dated.worst_gap, back_dated.off_ticks,
			back_dated.resteps])
	assert_lt(exact.worst_gap, SAME_M, "read from its tick, the host's keeper is the one the shooter draws")
	assert_eq(exact.resteps, 0)
	assert_gt(back_dated.off_ticks, 0, "back-dated, the host's keeper is not the one the shooter drew")
	assert_gte(back_dated.resteps, 1, "and the release's snapshot re-steps the shooter's")


# A client's world is its own prediction on the snapshot's centimetre grid, so
# his bytes never equal the host's; confirmed against the host's drawn goalie
# within CONFIRM_GAP_M he still steps on nearly every snapshot instead of
# re-stepping the span. The grid can tip a decision the host makes inside the
# span the other way; the snapshot from that tick re-steps him, so he is drawn
# apart from the host for at most the span and a broadcast.
func test_on_the_snapshot_grid_he_confirms_within_the_tolerance() -> void:
	for play: int in [Harness.Play.SLOT_SHOT, Harness.Play.CARRY_ACROSS]:
		var world: TruthWorld = _host(play)
		world.quantized = true
		var run: Run = _client(world, -1, Harness.SETTLE_TICKS - 40)
		gut.p("%s on the grid: %d confirmed, %d re-stepped, worst box gap %.4f m, longest drift %d ticks" % [
				Harness.Play.keys()[play], run.confirmed, run.resteps, run.worst_gap, run.longest_drift])
		assert_gt(float(run.confirmed) / maxf(float(run.confirmed + run.resteps), 1.0), 0.9,
				"nearly every snapshot confirms him")
		assert_lte(run.longest_drift, ONE_WAY + LEAD + 2,
				"drawn apart from the host no longer than the span and a broadcast, ticks")

extends GutTest

# A keeper rebuilt from the host's blob steps exactly as the host's keeper does
# (#903, docs/goalie-prediction-plan.md, Phase 1). Two worlds play the same
# scripted play tick for tick (keeper_play_harness.gd): the host's keeper snaps
# his state to his blob on every broadcast tick (every 2nd); the client's is put
# back in the crease and rebuilt from the host's newest blob every SPAN ticks,
# steps on in its own world, and snaps on the same ticks as the host's, as a
# predictor will. Every tick his 22 save boxes, his save and the puck, and on a
# broadcast tick his whole blob, are held equal to the host's. The snap is held
# to the play it changes: the same play with no snap meets the shot on the same
# tick, the same way.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")
# A 50 ms one-way's span: twice the one-way plus the input lead's margin.
const SPAN: int = 12


func _exact_through(play: int) -> void:
	var host := Harness.new(add_child_autofree)
	var client := Harness.new(add_child_autofree)
	var blob := PackedByteArray()
	var mine := PackedByteArray()
	var ticks: int = Harness.length(play)
	var worst_gap: float = 0.0
	var off_ticks: int = 0
	var seeds: int = 0
	for t: int in ticks:
		host.tick(play, t)
		client.tick(play, t)
		if t % 2 == 0:
			blob.clear()
			host.ctrl.append_wire_state(blob)
			if t >= Harness.SETTLE_TICKS - 4 * SPAN and (t - Harness.SETTLE_TICKS) % SPAN == 0:
				client.ctrl._place_in_crease()
				assert_true(client.ctrl.apply_wire_state(blob), "the blob reads whole at %d" % t)
				seeds += 1
			else:
				mine.clear()
				client.ctrl.append_wire_state(mine)
				if mine != blob:
					off_ticks += 1
		var gap: float = host.box_gap(client.goalie)
		worst_gap = maxf(worst_gap, gap)
		if gap > 0.0 or host.save_state() != client.save_state() \
				or host.puck.global_position != client.puck.global_position:
			off_ticks += 1
	assert_gt(seeds, 10, "rebuilt from the bytes through the play")
	assert_gt(host.first_contact, Harness.SETTLE_TICKS, "the shot met him")
	assert_eq(host.ctrl._wire.overflow, 0, "nothing clamped")
	assert_eq(off_ticks, 0, "ticks the rebuilt keeper or his world parted from the host's, of %d" % ticks)
	assert_eq(worst_gap, 0.0, "the largest box gap, m")
	assert_eq(client.first_contact, host.first_contact)
	gut.p("%s: %d ticks, %d rebuilds, worst box gap %.6f m, first contact at %d (%s)" % [
			Harness.Play.keys()[play], ticks, seeds, worst_gap, host.first_contact,
			"caught" if host.caught else "touched"])
	var plain := Harness.new(add_child_autofree)
	for t: int in ticks:
		plain.tick(play, t)
	assert_eq(plain.first_contact, host.first_contact, "met on the same tick with the snap as without it")
	assert_eq(plain.caught, host.caught, "and the same way")
	assert_almost_eq(plain.puck.global_position, host.puck.global_position, Vector3.ONE * 0.05,
			"the puck ends where it did")


func test_a_shot_from_the_slot() -> void:
	_exact_through(Harness.Play.SLOT_SHOT)


func test_a_carry_across_the_slot_and_a_shot() -> void:
	_exact_through(Harness.Play.CARRY_ACROSS)

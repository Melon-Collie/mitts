extends GutTest

# SnapshotDelta: the host sends each client its snapshot XOR the newest one that
# client acked; the client rebuilds it. The property everything rests on: every
# snapshot a client accepts is byte-for-byte the one the host encoded, through
# loss, late acks and a sequence wrap — and one it cannot rebuild it refuses
# rather than guesses.

const SIZE: int = 941


# A snapshot's texture: most bytes still, some moving every broadcast.
func _snapshot(t: int, size: int = SIZE) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	for i: int in size:
		b[i] = (i * 31 + t * (3 if i % 4 == 0 else 0)) & 0xFF
	return b


func _events(count: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(count * SnapshotEventLog.RECORD_SIZE + 1)
	b.fill(7)
	b.encode_u8(b.size() - 1, count)
	return b


func _with_events(raw: PackedByteArray, events: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = raw.duplicate()
	out.append_array(events)
	return out


func test_a_first_snapshot_goes_whole() -> void:
	var tx := SnapshotDelta.Sender.new()
	var rx := SnapshotDelta.Receiver.new()
	tx.begin(_snapshot(0))
	var packet: PackedByteArray = tx.packet_for(-1, _events(0))
	assert_eq(packet.decode_u8(0), SnapshotDelta.Kind.FULL)
	assert_eq(rx.read(packet), _with_events(_snapshot(0), _events(0)))
	assert_eq(rx.newest_seq, 0)


func test_an_acked_baseline_sends_a_delta_that_rebuilds_exactly() -> void:
	var tx := SnapshotDelta.Sender.new()
	var rx := SnapshotDelta.Receiver.new()
	tx.begin(_snapshot(0))
	rx.read(tx.packet_for(-1, _events(0)))
	tx.begin(_snapshot(1))
	var events: PackedByteArray = _events(2)
	var packet: PackedByteArray = tx.packet_for(rx.newest_seq, events)
	assert_eq(packet.decode_u8(0), SnapshotDelta.Kind.DELTA)
	assert_eq(rx.read(packet), _with_events(_snapshot(1), events))
	var compressed_delta: int = WirePacking.pack(packet, WirePacking.SNAPSHOT_MODE).size()
	var compressed_full: int = WirePacking.pack(tx.packet_for(-1, events), WirePacking.SNAPSHOT_MODE).size()
	assert_lt(compressed_delta, compressed_full, "the delta is what makes it smaller")


func test_every_accepted_snapshot_is_the_hosts_through_loss_and_late_acks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 912
	var tx := SnapshotDelta.Sender.new()
	var rx := SnapshotDelta.Receiver.new()
	var acks_in_flight: Array[int] = []
	var host_ack: int = -1
	var accepted: int = 0
	var deltas: int = 0
	# Started just short of the u16 wrap, so the run crosses it.
	tx._next_seq = 0xFFFF - 500
	for t: int in 2000:
		tx.begin(_snapshot(t))
		var packet: PackedByteArray = tx.packet_for(host_ack, _events(t % 3))
		deltas += 1 if packet.decode_u8(0) == SnapshotDelta.Kind.DELTA else 0
		if rng.randf() > 0.1:  # 10% loss
			var got: PackedByteArray = rx.read(packet)
			if not got.is_empty():
				accepted += 1
				if got != _with_events(_snapshot(t), _events(t % 3)):
					fail_test("broadcast %d rebuilt wrong" % t)
					return
		# Acks reach the host a few broadcasts later, and some are lost.
		acks_in_flight.append(rx.newest_seq)
		if acks_in_flight.size() > 3:
			var ack: int = acks_in_flight.pop_front()
			if ack >= 0 and rng.randf() > 0.1:
				host_ack = ack
	assert_gt(accepted, 1700)
	assert_gt(deltas, 1900, "a steady link rides on deltas")
	assert_eq(rx.baseline_misses, 0, "the host only names baselines the client acked")


func test_an_ack_older_than_the_ring_goes_whole() -> void:
	var tx := SnapshotDelta.Sender.new()
	for t: int in SnapshotDelta.MAX_BASELINE_AGE + 2:
		tx.begin(_snapshot(t))
	assert_eq(tx.packet_for(0, _events(0)).decode_u8(0), SnapshotDelta.Kind.FULL)


func test_a_roster_change_goes_whole() -> void:
	var tx := SnapshotDelta.Sender.new()
	tx.begin(_snapshot(0))
	tx.begin(_snapshot(1, SIZE + 63))
	assert_eq(tx.packet_for(0, _events(0)).decode_u8(0), SnapshotDelta.Kind.FULL)


func test_a_baseline_the_client_lacks_is_refused() -> void:
	var tx := SnapshotDelta.Sender.new()
	var rx := SnapshotDelta.Receiver.new()
	tx.begin(_snapshot(0))
	tx.begin(_snapshot(1))
	assert_true(rx.read(tx.packet_for(0, _events(0))).is_empty())
	assert_eq(rx.baseline_misses, 1)


func test_malformed_packets_are_refused() -> void:
	var rx := SnapshotDelta.Receiver.new()
	assert_true(rx.read(PackedByteArray()).is_empty())
	assert_true(rx.read(PackedByteArray([9, 0, 0, 0])).is_empty(), "an unknown kind")
	var lying := PackedByteArray([SnapshotDelta.Kind.FULL, 0, 0, 1, 2, 3, 200])
	assert_true(rx.read(lying).is_empty(), "an event count past the packet")


func test_sequence_order_across_the_wrap() -> void:
	assert_eq(SnapshotDelta.seq_ahead(1, 0xFFFF), 2)
	assert_eq(SnapshotDelta.seq_ahead(0xFFFF, 1), -1)
	assert_eq(SnapshotDelta.seq_ahead(5, 5), -1)

extends GutTest

# The goalies' sim states ride behind the world-state body (KeeperWireTail),
# inside the snapshot's delta and ahead of the carrier-event block. A client
# splits them back off, so the decoders and the recorders see the old snapshot
# exactly, and each goalie gets his own blob; the host's recorded frame never
# holds them; and an offline host never writes them, so offline play never
# meets the wire.


class StubSeat:
	extends GoalieController
	var bytes := PackedByteArray()

	func append_wire_state(out: PackedByteArray) -> void:
		out.append_array(bytes)


func _seats(blobs: Array[PackedByteArray]) -> Array[GoalieController]:
	var out: Array[GoalieController] = []
	for b: PackedByteArray in blobs:
		var s := StubSeat.new()
		s.bytes = b
		autofree(s)
		out.append(s)
	return out


func _world_state(size: int, t: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	for i: int in size:
		b[i] = (i * 13 + t * (1 if i % 5 == 0 else 0)) & 0xFF
	return b


func _events(count: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(count * SnapshotEventLog.RECORD_SIZE + 1)
	b.fill(3)
	b.encode_u8(b.size() - 1, count)
	return b


func _blob(n: int, fill: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(fill)
	return b


func test_the_tail_splits_back_off_and_reaches_each_goalie() -> void:
	var ws: PackedByteArray = _world_state(941, 0)
	var seats: Array[GoalieController] = _seats([_blob(300, 1), _blob(0, 0), _blob(17, 2)])
	var body: PackedByteArray = ws.duplicate()
	KeeperWireTail.append(body, seats)
	assert_eq(body.size(), 941 + 317 + 3 * 2 + 1)
	for events: int in [0, 3]:
		var s: PackedByteArray = body.duplicate()
		s.append_array(_events(events))
		var at: Vector2i = KeeperWireTail.bounds(s)
		assert_eq(at, Vector2i(941, 941 + 317 + 7))
		var expected: PackedByteArray = ws.duplicate()
		expected.append_array(_events(events))
		assert_eq(KeeperWireTail.without(s, at), expected, "the decoders see the old snapshot exactly")
		var into: Array[GoalieController] = _seats([PackedByteArray(), PackedByteArray(), PackedByteArray()])
		KeeperWireTail.dispatch(s.slice(at.x, at.y), into, 12.5)
		assert_eq(into[0].wire_state, _blob(300, 1))
		assert_eq(into[1].wire_state, PackedByteArray(), "an empty blob leaves a seat as it was")
		assert_eq(into[2].wire_state, _blob(17, 2))
		assert_eq(into[2].wire_state_time, 12.5)


func test_a_goalie_keeps_the_newest() -> void:
	var seat: GoalieController = _seats([PackedByteArray()])[0]
	seat.receive_wire_state(_blob(4, 1), 2.0)
	seat.receive_wire_state(_blob(4, 2), 1.0)
	assert_eq(seat.wire_state, _blob(4, 1), "an older snapshot's left")
	seat.receive_wire_state(_blob(4, 3), 2.0)
	assert_eq(seat.wire_state, _blob(4, 3), "the same instant's later tick taken")


func test_a_malformed_tail_is_refused() -> void:
	assert_eq(KeeperWireTail.bounds(PackedByteArray()), Vector2i(-1, -1))
	var s := PackedByteArray([1])
	s.append_array(_events(0))
	assert_eq(KeeperWireTail.bounds(s), Vector2i(-1, -1), "a goalie count its lengths overrun")
	var long := PackedByteArray([9, 9, 0xFF, 0x00, 1])
	long.append_array(_events(0))
	assert_eq(KeeperWireTail.bounds(long), Vector2i(-1, -1), "a blob longer than the body")


func test_it_rides_the_delta_and_the_packing_exactly() -> void:
	var tx := SnapshotDelta.Sender.new()
	var rx := SnapshotDelta.Receiver.new()
	for t: int in 6:
		var ws: PackedByteArray = _world_state(941, t)
		var body: PackedByteArray = ws.duplicate()
		KeeperWireTail.append(body, _seats([_blob(2473, t), _blob(2473, 7)]))
		tx.begin(body)
		var events: PackedByteArray = _events(t % 2)
		var packed: PackedByteArray = WirePacking.pack(tx.packet_for(rx.newest_seq, events),
				WirePacking.SNAPSHOT_MODE)
		var s: PackedByteArray = rx.read(WirePacking.unpack(packed, WirePacking.SNAPSHOT_MAX_RAW,
				WirePacking.SNAPSHOT_MODE))
		assert_false(s.is_empty(), "within the raw bound, broadcast %d" % t)
		var at: Vector2i = KeeperWireTail.bounds(s)
		var expected: PackedByteArray = ws.duplicate()
		expected.append_array(events)
		assert_eq(KeeperWireTail.without(s, at), expected)
		assert_eq(s.slice(at.x, at.x + 2473), _blob(2473, t))


func test_the_host_records_the_snapshot_without_them_and_offline_writes_none() -> void:
	var nm: Node = NetworkManager
	var was_offline: bool = nm.is_offline_mode
	var was_provider: Callable = nm._world_state_provider
	var was_keepers: Callable = nm._keeper_wire_provider
	var recorded: Array[PackedByteArray] = []
	var written: Array[int] = [0]
	nm.set_world_state_provider(func() -> PackedByteArray:
		var ws: PackedByteArray = _world_state(64, 0)
		recorded.append(ws)
		return ws)
	nm.set_keeper_wire_provider(func(body: PackedByteArray) -> void:
		written[0] += 1
		body.append_array(_blob(10, 5)))
	nm.is_offline_mode = true
	nm._broadcast_state()
	assert_eq(written[0], 0, "offline, no keeper writes his state, so none snaps")
	nm.is_offline_mode = false
	nm._broadcast_state()
	assert_eq(written[0], 1, "online, the keepers write theirs")
	assert_eq(recorded[1], _world_state(64, 0), "the frame the recorders keep holds no blob")
	nm._delta_sender.reset()
	nm.is_offline_mode = was_offline
	nm.set_world_state_provider(was_provider)
	nm.set_keeper_wire_provider(was_keepers)

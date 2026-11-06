extends GutTest

# WirePacking compresses the snapshot and the input batch at the RPC boundary.
# What every reader relies on: the bytes come back exactly, and a malformed
# message unpacks to nothing rather than to a buffer the decoders would read.


func _snapshot_like(n: int) -> PackedByteArray:
	# A snapshot's texture: mostly-static fields, a few that move every tick.
	var b := PackedByteArray()
	b.resize(n)
	for i: int in n:
		b[i] = (i * 7) % 13 if i % 9 == 0 else (i / 63) & 0xFF
	return b


func test_a_snapshot_round_trips() -> void:
	var raw: PackedByteArray = _snapshot_like(941)
	var packed: PackedByteArray = WirePacking.pack(raw, WirePacking.SNAPSHOT_MODE)
	assert_lt(packed.size(), raw.size(), "a snapshot's static fields compress")
	assert_eq(WirePacking.unpack(packed, WirePacking.SNAPSHOT_MAX_RAW,
			WirePacking.SNAPSHOT_MODE), raw)


func test_an_input_batch_round_trips() -> void:
	var raw := PackedByteArray([0, 0, 2])
	for i: int in 2:
		var input := InputState.new()
		input.host_timestamp = 10.0 + float(i) / 90.0
		input.move_vector = Vector2(0.0, -1.0)
		raw.append_array(input.to_bytes())
	var packed: PackedByteArray = WirePacking.pack(raw, WirePacking.INPUT_MODE)
	assert_eq(WirePacking.unpack(packed, WirePacking.INPUT_MAX_RAW, WirePacking.INPUT_MODE), raw)


func test_malformed_messages_unpack_to_nothing() -> void:
	var good: PackedByteArray = WirePacking.pack(_snapshot_like(941), WirePacking.SNAPSHOT_MODE)
	var max_raw: int = WirePacking.SNAPSHOT_MAX_RAW
	var mode: int = WirePacking.SNAPSHOT_MODE
	assert_true(WirePacking.unpack(PackedByteArray(), max_raw, mode).is_empty(), "empty")
	assert_true(WirePacking.unpack(good.slice(0, 2), max_raw, mode).is_empty(), "header only")
	var oversize: PackedByteArray = good.duplicate()
	oversize.encode_u16(0, max_raw + 1)
	assert_true(WirePacking.unpack(oversize, max_raw, mode).is_empty(), "a size past the bound")
	var misdeclared: PackedByteArray = good.duplicate()
	misdeclared.encode_u16(0, 900)
	assert_true(WirePacking.unpack(misdeclared, max_raw, mode).is_empty(), "a size the body doesn't inflate to")
	assert_true(WirePacking.unpack(good.slice(0, good.size() / 2), max_raw, mode).is_empty(),
			"a truncated body")


func test_a_raw_layout_is_not_mistaken_for_a_packed_one() -> void:
	# What a mismatched peer would send: an unpacked batch. Refused, not decoded.
	var raw := PackedByteArray([0, 0, 1])
	raw.append_array(InputState.new().to_bytes())
	assert_true(WirePacking.unpack(raw, WirePacking.INPUT_MAX_RAW, WirePacking.INPUT_MODE).is_empty())

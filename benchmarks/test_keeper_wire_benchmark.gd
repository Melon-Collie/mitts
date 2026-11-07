extends GutTest

# What the keeper's wire state costs (#903): per broadcast (every 2nd tick) of
# the real keeper through a wrister from the slot and a carry across the slot
# and a shot (keeper_play_harness.gd), the host's write (his fields, snapped)
# and the whole append (that, his node and boxes placed on it), a client's read
# and the whole apply, in µs; and the blob's bytes whole, under zstd, and XORed
# against itself one and three broadcasts back then zstd (SnapshotDelta's
# treatment with a client's ack one or three broadcasts old). Each blob is
# compressed on its own, so each figure carries zstd's frame (an unchanged blob
# of the same length compresses to the "unchanged" figure). Report-only.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")


static func _pct(a: PackedFloat64Array, q: float) -> float:
	var s: PackedFloat64Array = a.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * float(s.size()))) - 1, 0, s.size() - 1)]


static func _mean(a: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for x: float in a:
		sum += x
	return sum / float(a.size())


static func _z(b: PackedByteArray) -> float:
	return float(b.compress(FileAccess.COMPRESSION_ZSTD).size())


static func _xor_z(b: PackedByteArray, base: PackedByteArray) -> float:
	return _z(SnapshotDelta.xor_words(SnapshotDelta.words_of(b), SnapshotDelta.words_of(base), b.size()))


func test_report_keeper_wire_cost() -> void:
	var write_us := PackedFloat64Array()
	var append_us := PackedFloat64Array()
	var read_us := PackedFloat64Array()
	var apply_us := PackedFloat64Array()
	var whole := PackedFloat64Array()
	var zstd := PackedFloat64Array()
	var back_1 := PackedFloat64Array()
	var back_3 := PackedFloat64Array()
	var unchanged: float = 0.0
	var w := KeeperWire.new()
	for play: int in [Harness.Play.SLOT_SHOT, Harness.Play.CARRY_ACROSS]:
		var host := Harness.new(add_child_autofree)
		var client := Harness.new(add_child_autofree)
		var history: Array[PackedByteArray] = []
		for t: int in Harness.length(play):
			host.tick(play, t)
			if t % 2 != 0:
				continue
			var scratch := PackedByteArray()
			var t0: int = Time.get_ticks_usec()
			w.begin_write(scratch)
			host.ctrl.wire(w)
			w.finish_write()
			var t1: int = Time.get_ticks_usec()
			var blob := PackedByteArray()
			host.ctrl.append_wire_state(blob)
			var t2: int = Time.get_ticks_usec()
			w.begin_read(blob)
			client.ctrl.wire(w)
			w.finish_read()
			var t3: int = Time.get_ticks_usec()
			client.ctrl.apply_wire_state(blob)
			var t4: int = Time.get_ticks_usec()
			write_us.append(float(t1 - t0))
			append_us.append(float(t2 - t1))
			read_us.append(float(t3 - t2))
			apply_us.append(float(t4 - t3))
			whole.append(float(blob.size()))
			zstd.append(_z(blob))
			if history.size() >= 1:
				back_1.append(_xor_z(blob, history[history.size() - 1]))
			if history.size() >= 3:
				back_3.append(_xor_z(blob, history[history.size() - 3]))
			history.append(blob)
			if unchanged == 0.0:
				var zero := PackedByteArray()
				zero.resize(blob.size())
				unchanged = _z(zero)
	var lines: PackedStringArray = ["", "### KeeperWire, per keeper per broadcast (%d broadcasts)" % write_us.size(), "",
			"| | p50 | p95 | max |", "|---|---|---|---|"]
	for row: Array in [["write, µs (his fields, snapped)", write_us], ["append, µs (write + node and boxes placed)", append_us],
			["read, µs (his fields)", read_us], ["apply, µs (read + node and boxes placed)", apply_us]]:
		var a: PackedFloat64Array = row[1]
		lines.append("| %s | %.0f | %.0f | %.0f |" % [row[0], _pct(a, 0.5), _pct(a, 0.95), _pct(a, 1.0)])
	lines.append_array(["", "| bytes | mean | p95 | max |", "|---|---|---|---|"])
	for row: Array in [["whole", whole], ["zstd", zstd], ["XOR 1 back, zstd", back_1], ["XOR 3 back, zstd", back_3]]:
		var b: PackedFloat64Array = row[1]
		lines.append("| %s | %.0f | %.0f | %.0f |" % [row[0], _mean(b), _pct(b, 0.95), _pct(b, 1.0)])
	lines.append("| an unchanged blob that long, zstd | %.0f | | |" % unchanged)
	gut.p("\n".join(lines))
	assert_true(true)

extends GutTest

# KeeperWire: every value a writer hands back is what a reader of its bytes
# decodes, at its scale, NaN and the infinities included; a value past its
# range is clamped and counted; bools go as bits after the bytes; and a read
# knows when it did not take exactly one blob.


# One pass of `fields` through `w`: the values as `w` hands them back.
func _walk(w: KeeperWire, v: Array) -> Array:
	var out: Array = []
	out.append(w.s16(v[0], KeeperWire.MM))
	out.append(w.s32(v[1], KeeperWire.MS))
	out.append(w.v2_16(v[2], KeeperWire.SPEED))
	out.append(w.v3_32(v[3], KeeperWire.MM))
	out.append(w.s8(v[4]))
	out.append(w.bit(v[5]))
	out.append(w.s16(v[6], KeeperWire.ANGLE))
	out.append(w.s32(v[7], KeeperWire.ANGLE))
	out.append(w.bit(v[8]))
	return out


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and is_nan(a):
		return typeof(b) == TYPE_FLOAT and is_nan(b)
	return a == b


func test_what_a_writer_keeps_is_what_a_reader_decodes() -> void:
	var values: Array = [0.12345, 3.0004, Vector2(1.23456, -0.5), Vector3(55.5554, -0.0004, 1e3), -7, true,
			3.0, 7.0 * PI, false]
	var out := PackedByteArray([9, 9, 9])
	var w := KeeperWire.new()
	w.begin_write(out)
	var kept: Array = _walk(w, values)
	var length: int = w.finish_write()
	assert_eq(out.size(), 3 + length, "the blob goes onto the end of what is there")
	assert_eq(out.slice(0, 3), PackedByteArray([9, 9, 9]))
	var r := KeeperWire.new()
	assert_true(r.begin_read(out, 3))
	var read: Array = _walk(r, [0.0, 0.0, Vector2.ZERO, Vector3.ZERO, 0, false, 0.0, 0.0, true])
	assert_true(r.finish_read(), "the read takes the blob exactly")
	for i: int in kept.size():
		assert_true(_same(kept[i], read[i]), "value %d: kept %s, read %s" % [i, kept[i], read[i]])
	assert_almost_eq(float(kept[0]), 0.123, 1e-12, "a millimetre")
	assert_almost_eq(float(kept[1]), 3.0, 1e-12, "a millisecond")
	assert_eq(kept[4], -7)
	assert_almost_eq(float(kept[7]), 7.0 * PI, KeeperWire.ANGLE, "a wound angle in 32 bits")
	assert_eq(w.overflow, 0)


func test_nan_and_the_infinities_have_codes_of_their_own() -> void:
	for v: float in [NAN, INF, -INF]:
		var out := PackedByteArray()
		var w := KeeperWire.new()
		w.begin_write(out)
		var a: float = w.s16(v, KeeperWire.MM)
		var b: float = w.s32(v, KeeperWire.MS)
		var c: Vector3 = w.v3_16(Vector3(v, 1.0, v), KeeperWire.MM)
		w.finish_write()
		var r := KeeperWire.new()
		r.begin_read(out)
		assert_true(_same(a, v) and _same(r.s16(0.0, KeeperWire.MM), v), "s16 %s" % v)
		assert_true(_same(b, v) and _same(r.s32(0.0, KeeperWire.MS), v), "s32 %s" % v)
		var rc: Vector3 = r.v3_16(Vector3.ZERO, KeeperWire.MM)
		assert_true(_same(c.x, v) and _same(rc.x, v) and rc.y == 1.0 and _same(rc.z, v), "v3 %s" % v)
		assert_true(r.finish_read())
		assert_eq(w.overflow, 0, "a code is not a clamp")


func test_a_value_past_its_range_is_clamped_and_counted() -> void:
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	var big: float = w.s16(40.0, KeeperWire.MM)
	var small: float = w.s16(-40.0, KeeperWire.MM)
	var edge: float = w.s16(32.766, KeeperWire.MM)
	var byte: int = w.s8(300)
	var wide: float = w.s32(40.0, KeeperWire.MM)
	w.finish_write()
	assert_almost_eq(big, 32.766, 1e-9)
	assert_almost_eq(small, -32.766, 1e-9)
	assert_almost_eq(edge, 32.766, 1e-9, "the last step is in range")
	assert_eq(byte, 127)
	assert_almost_eq(wide, 40.0, 1e-9, "32 bits hold a place anywhere on the rink")
	assert_eq(w.overflow, 3)
	var r := KeeperWire.new()
	r.begin_read(out)
	assert_almost_eq(r.s16(0.0, KeeperWire.MM), 32.766, 1e-9, "what was kept is what is read")


func test_bools_go_as_bits_after_the_bytes() -> void:
	var flags: Array[bool] = []
	for i: int in 13:
		flags.append(i % 3 == 0 or i == 12)
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.s16(1.0, KeeperWire.MM)
	for f: bool in flags:
		w.bit(f)
	w.s8(5)
	var length: int = w.finish_write()
	assert_eq(length, 2 + 3 + 2 + 4, "header, three bytes, thirteen bits in two, the digest")
	assert_eq(out.decode_u16(0), 3)
	var r := KeeperWire.new()
	r.begin_read(out)
	assert_almost_eq(r.s16(0.0, KeeperWire.MM), 1.0, 1e-12)
	for f: bool in flags:
		assert_eq(r.bit(not f), f)
	assert_eq(r.s8(0), 5)
	assert_true(r.finish_read())


func _digest_of(place: float, run: PackedByteArray, count: int, on: bool) -> int:
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.s16(place, KeeperWire.MM)
	w.flags(run)
	w.s8(count)
	w.bit(on)
	w.finish_write()
	return KeeperWire.discrete_digest(out)


# Two keepers at different places, reading different histories, are the same
# keeper to the digest until an int or a bool of theirs differs.
func test_the_digest_holds_his_ints_and_bools_only() -> void:
	var run := PackedByteArray([1, 0, 1])
	var base: int = _digest_of(1.0, run, 3, true)
	assert_eq(_digest_of(1.25, run, 3, true), base, "a place is not discrete state")
	assert_eq(_digest_of(1.0, PackedByteArray([0, 1, 1]), 3, true), base, "nor the read's history")
	assert_ne(_digest_of(1.0, run, 4, true), base, "an int is")
	assert_ne(_digest_of(1.0, run, 3, false), base, "a bool is")


func test_packed_history_and_its_flags_round_trip_in_place() -> void:
	var at := PackedVector2Array([Vector2(50.1234, -55.0), Vector2.INF, Vector2(0.0004, 1.0)])
	var on := PackedByteArray([1, 0, 1, 1, 0])
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.v2s_32(at, KeeperWire.MM)
	w.flags(on)
	w.finish_write()
	assert_eq(at[0], Vector2(50.123, -55.0), "the writer's own array snapped")
	var back := PackedVector2Array()
	back.resize(3)
	var flags := PackedByteArray()
	flags.resize(5)
	var r := KeeperWire.new()
	r.begin_read(out)
	r.v2s_32(back, KeeperWire.MM)
	r.flags(flags)
	assert_true(r.finish_read())
	assert_eq(back, at)
	assert_eq(flags, on)


func test_a_pose_is_written_as_its_codec_writes_it() -> void:
	var p := KeeperPose.new()
	KeeperPoses.butterfly(p)
	p.blade_center += Vector3(0.00049, 0.0, 0.0)
	var codec := PackedByteArray()
	codec.resize(KeeperPoseCodec.SIZE)
	KeeperPoseCodec.write(p, codec, 0)
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.pose(p)
	w.finish_write()
	assert_eq(out.slice(2, 2 + KeeperPoseCodec.SIZE), codec)
	var again_bytes := PackedByteArray()
	again_bytes.resize(KeeperPoseCodec.SIZE)
	KeeperPoseCodec.write(p, again_bytes, 0)
	assert_eq(again_bytes, codec, "the writer's pose snapped: written again, the same bytes")
	var q := KeeperPose.new()
	var r := KeeperWire.new()
	r.begin_read(out)
	r.pose(q)
	assert_true(r.finish_read())
	var again := PackedByteArray()
	again.resize(KeeperPoseCodec.SIZE)
	KeeperPoseCodec.write(q, again, 0)
	assert_eq(again, codec)
	assert_eq(q.blade_center, p.blade_center)


func test_a_leg_round_trips() -> void:
	var l := KeeperPose.Leg.new()
	l.ankle = Vector3(0.1234, 0.0, -0.3)
	l.knee_pinned = true
	l.foot_mode = KeeperPose.FootMode.ALONG_SHIN
	l.flex = 1.23456
	l.along_shin = 0.5
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.leg(l)
	w.finish_write()
	var m := KeeperPose.Leg.new()
	var r := KeeperWire.new()
	r.begin_read(out)
	r.leg(m)
	assert_true(r.finish_read())
	for f: String in ["ankle", "knee_pinned", "knee", "knee_pole", "thigh_front", "shin_front", "foot_mode", "toe",
			"flex", "along_shin"]:
		assert_eq(m.get(f), l.get(f), f)


func test_a_read_knows_a_blob_it_did_not_take_exactly() -> void:
	var out := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(out)
	w.s16(1.0, KeeperWire.MM)
	w.bit(true)
	w.finish_write()
	var r := KeeperWire.new()
	assert_true(r.begin_read(out))
	r.s16(0.0, KeeperWire.MM)
	assert_false(r.finish_read(), "a bit left unread")
	assert_true(r.begin_read(out))
	r.s16(0.0, KeeperWire.MM)
	r.bit(false)
	r.bit(false)
	r.bit(false)
	assert_true(r.finish_read(), "unused bits of the last byte are padding")
	assert_false(r.begin_read(PackedByteArray([200, 0, 1])), "a header longer than the blob")
	assert_false(r.begin_read(PackedByteArray([1])), "no header")


# Every field of a pose and of its legs: changing any one that the codec
# writes makes KeeperPoseCodec.same see it, so the writer never keeps an old
# pose's bytes for a new one.
func test_a_pose_changed_in_any_written_field_is_not_the_same() -> void:
	var base := KeeperPose.new()
	KeeperPoses.ready(base)
	var bytes := PackedByteArray()
	bytes.resize(KeeperPoseCodec.SIZE)
	KeeperPoseCodec.write(base, bytes, 0)
	KeeperPoseCodec.read(bytes, 0, base)
	var checked: int = 0
	for part: String in ["pose", "leg0", "leg1"]:
		var probe := KeeperPose.new()
		var target: Object = probe
		if part != "pose":
			target = probe.legs[1 if part == "leg1" else 0]
		for p: Dictionary in target.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or String(p["name"]) == "legs":
				continue
			var f: String = String(p["name"])
			probe.copy_from(base)
			var was: Variant = target.get(f)
			match typeof(was):
				TYPE_VECTOR3:
					target.set(f, (was as Vector3) + Vector3(0.0, 0.05, 0.0))
				TYPE_FLOAT:
					target.set(f, float(was) + 0.05)
				TYPE_BOOL:
					target.set(f, not was)
				TYPE_INT:
					target.set(f, KeeperPose.FootMode.FLAT if int(was) != KeeperPose.FootMode.FLAT
							else KeeperPose.FootMode.ALONG_SHIN)
			var moved := PackedByteArray()
			moved.resize(KeeperPoseCodec.SIZE)
			KeeperPoseCodec.write(probe, moved, 0)
			if moved != bytes:
				assert_false(KeeperPoseCodec.same(probe, base), "%s.%s written, so compared" % [part, f])
				checked += 1
	assert_gt(checked, 30, "the walk reached the pose's fields")


# A writer that remembers its last blob writes what a fresh one does, through a
# history moving on, flags flipping and a pose changing.
func test_a_writer_that_remembers_writes_what_a_fresh_one_does() -> void:
	var w := KeeperWire.new()
	var at := PackedVector2Array()
	at.resize(9)
	var on := PackedByteArray()
	on.resize(9)
	var p := KeeperPose.new()
	KeeperPoses.ready(p)
	for k: int in 12:
		at[k % 9] = Vector2(0.1234 * k, -40.00051 * k)
		on[(k * 4) % 9] = k % 2
		if k % 3 == 0:
			p.blade_center.x += 0.0123
		var mine := PackedByteArray()
		w.begin_write(mine)
		w.v2s_32(at, KeeperWire.MM)
		w.flags(on)
		w.pose(p)
		w.finish_write()
		var fresh := PackedByteArray()
		var f := KeeperWire.new()
		f.begin_write(fresh)
		f.v2s_32(at, KeeperWire.MM)
		f.flags(on)
		f.pose(p)
		f.finish_write()
		assert_eq(mine, fresh, "blob %d" % k)

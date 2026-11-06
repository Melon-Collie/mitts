class_name KeeperWire
extends RefCounted

# The keeper's whole sim state as bytes, and back: one writer-or-reader that
# every keeper class hands its own fields to in a fixed order (`wire`), so
# writing and reading walk one list and cannot disagree on the layout.
#
# A value method writes the value, or reads one, and returns the value as a
# reader decodes it; the caller stores what it returns. So writing also snaps:
# the writer's own state becomes exactly what any reader rebuilds from the bytes.
#
# Blob: a u16 count of the bytes that follow it before the bit section, those
# bytes in the order the fields were handed over, then every bool as one bit
# (a run of flags, `flags`, packs its bits into bytes where it lies). Its
# length depends on nothing but the code, so a keeper's blob is the same length
# every snapshot.
#
# A writer remembers the poses and the runs it last wrote, value for value with
# their bytes, and copies the bytes of one that has not changed rather than
# writing it again: the history and the movers' stored stances are most of a
# blob, and between two snapshots little of them moves. It compares values,
# never whose they are, so one writer serves any keeper.
#
# Q16 scales: positions at a millimetre, angles at π/32767, clocks at a
# millisecond, shares of 0..1 at 1e-4, velocities at 2.5 mm/s. A field whose
# range a 16-bit step count cannot hold (an angle that can wind past π, a clock
# that runs on, a place anywhere on the rink) is written in 32 bits at the same
# scale. NaN and ±INF have codes of their own; a value past the range is
# clamped to it and counted in `overflow`. Poses go as KeeperPoseCodec writes
# them.

const MM: float = 0.001
const ANGLE: float = PI / 32767.0
const MS: float = 0.001
const SPEED: float = 0.0025
const FRACTION: float = 1e-4

const _HEADER: int = 2
# The most a blob's byte section and its bits take: room the writer reserves
# once, so no value has to check for it.
const _MOST_BYTES: int = 4096
const _MOST_BITS: int = 512
const _NAN_16: int = -32768
const _INF_16: int = 32767
const _NEG_INF_16: int = -32767
const _MAX_16: int = 32766
const _NAN_32: int = -2147483648
const _INF_32: int = 2147483647
const _NEG_INF_32: int = -2147483647
const _MAX_32: int = 2147483646

var reading: bool = false
# Values clamped to their range since this writer or reader was made.
var overflow: int = 0

var _b := PackedByteArray()
var _start: int = 0
var _o: int = 0
var _bits := PackedByteArray()
var _bit: int = 0
var _bit_from: int = 0
var _bit_end: int = 0
var _poses: Array[KeeperPose] = []
var _pose_bytes: Array[PackedByteArray] = []
var _pose_n: int = 0
var _runs: Array[PackedVector2Array] = []
var _flags: Array[PackedByteArray] = []
var _run_bytes: Array[PackedByteArray] = []
var _run_n: int = 0


func _init() -> void:
	_bits.resize(_MOST_BITS >> 3)


# Writing a blob onto the end of `out`.
func begin_write(out: PackedByteArray) -> void:
	reading = false
	_b = out
	_start = out.size()
	_o = _start + _HEADER
	_b.resize(_o + _MOST_BYTES)
	_bits.fill(0)
	_bit = 0
	_pose_n = 0
	_run_n = 0


# The blob's header and bit section in place, `out` cut to the blob's end; its
# length.
func finish_write() -> int:
	_b.encode_u16(_start, _o - _start - _HEADER)
	var bit_bytes: int = (_bit + 7) >> 3
	for i: int in bit_bytes:
		_b[_o + i] = _bits[i]
	_b.resize(_o + bit_bytes)
	var length: int = _o + bit_bytes - _start
	_b = PackedByteArray()
	return length


# Reading the blob at `from` in `blob`, `size` bytes long; false when its header
# does not fit it.
func begin_read(blob: PackedByteArray, from: int = 0, size: int = -1) -> bool:
	reading = true
	if size < 0:
		size = blob.size() - from
	if size < _HEADER or from + size > blob.size():
		return false
	var byte_len: int = blob.decode_u16(from)
	if _HEADER + byte_len > size:
		return false
	_b = blob
	_start = from
	_o = from + _HEADER
	_bit_from = (_o + byte_len) * 8
	_bit = 0
	_bit_end = (from + size) * 8
	return true


# Whether the read took exactly the blob's bytes and no more bits than it has.
func finish_read() -> bool:
	var exact: bool = _o * 8 == _bit_from and _bit_from + _bit <= _bit_end \
			and (_bit_from + _bit + 7) >> 3 == _bit_end >> 3
	_b = PackedByteArray()
	return exact


# A NaN or an infinity fails the range test too, and takes its code there.
func s16(v: float, scale: float) -> float:
	var c: int
	if reading:
		c = _b.decode_s16(_o)
	else:
		c = roundi(v / scale) if absf(v) <= _MAX_16 * scale else _code_16(v)
		_b.encode_s16(_o, c)
	_o += 2
	return float(c) * scale if c > _NEG_INF_16 and c < _INF_16 else _special_16(c)


func s32(v: float, scale: float) -> float:
	var c: int
	if reading:
		c = _b.decode_s32(_o)
	else:
		c = roundi(v / scale) if absf(v) <= _MAX_32 * scale else _code_32(v)
		_b.encode_s32(_o, c)
	_o += 4
	return float(c) * scale if c > _NEG_INF_32 and c < _INF_32 else _special_32(c)


# s16 a component, written out: vectors are most of a blob's values.
func v2_16(v: Vector2, scale: float) -> Vector2:
	var cx: int
	var cy: int
	if reading:
		cx = _b.decode_s16(_o)
		cy = _b.decode_s16(_o + 2)
	else:
		var limit: float = _MAX_16 * scale
		cx = roundi(v.x / scale) if absf(v.x) <= limit else _code_16(v.x)
		cy = roundi(v.y / scale) if absf(v.y) <= limit else _code_16(v.y)
		_b.encode_s16(_o, cx)
		_b.encode_s16(_o + 2, cy)
	_o += 4
	return Vector2(float(cx) * scale if cx > _NEG_INF_16 and cx < _INF_16 else _special_16(cx),
			float(cy) * scale if cy > _NEG_INF_16 and cy < _INF_16 else _special_16(cy))


func v2_32(v: Vector2, scale: float) -> Vector2:
	var x: float = s32(v.x, scale)
	return Vector2(x, s32(v.y, scale))


func v3_16(v: Vector3, scale: float) -> Vector3:
	var cx: int
	var cy: int
	var cz: int
	if reading:
		cx = _b.decode_s16(_o)
		cy = _b.decode_s16(_o + 2)
		cz = _b.decode_s16(_o + 4)
	else:
		var limit: float = _MAX_16 * scale
		cx = roundi(v.x / scale) if absf(v.x) <= limit else _code_16(v.x)
		cy = roundi(v.y / scale) if absf(v.y) <= limit else _code_16(v.y)
		cz = roundi(v.z / scale) if absf(v.z) <= limit else _code_16(v.z)
		_b.encode_s16(_o, cx)
		_b.encode_s16(_o + 2, cy)
		_b.encode_s16(_o + 4, cz)
	_o += 6
	return Vector3(float(cx) * scale if cx > _NEG_INF_16 and cx < _INF_16 else _special_16(cx),
			float(cy) * scale if cy > _NEG_INF_16 and cy < _INF_16 else _special_16(cy),
			float(cz) * scale if cz > _NEG_INF_16 and cz < _INF_16 else _special_16(cz))


func v3_32(v: Vector3, scale: float) -> Vector3:
	var x: float = s32(v.x, scale)
	var y: float = s32(v.y, scale)
	return Vector3(x, y, s32(v.z, scale))


# An int in a byte, clamped to -128..127.
func s8(v: int) -> int:
	if reading:
		v = _b.decode_s8(_o)
	else:
		if v < -128 or v > 127:
			overflow += 1
			v = clampi(v, -128, 127)
		_b.encode_s8(_o, v)
	_o += 1
	return v


func bit(v: bool) -> bool:
	if reading:
		var at: int = _bit_from + _bit
		v = (_b[at >> 3] >> (at & 7)) & 1 == 1
	elif v:
		_bits[_bit >> 3] |= 1 << (_bit & 7)
	_bit += 1
	return v


# Every element of `a`, in place; its length is the code's, the same both ends.
func v2s_16(a: PackedVector2Array, scale: float) -> void:
	_v2s(a, scale, 2)


func v2s_32(a: PackedVector2Array, scale: float) -> void:
	_v2s(a, scale, 4)


# Every byte of `a` as a bit (0 or 1), in place, packed into bytes where the
# run lies.
func flags(a: PackedByteArray) -> void:
	var n: int = a.size()
	var size: int = (n + 7) >> 3
	if reading:
		for i: int in n:
			a[i] = (_b[_o + (i >> 3)] >> (i & 7)) & 1
		_o += size
		return
	var k: int = _run(size)
	var was: PackedByteArray = _flags[k]
	var bytes: PackedByteArray = _run_bytes[k]
	if was != a:
		bytes.fill(0)
		for i: int in n:
			if a[i] != 0:
				a[i] = 1
				bytes[i >> 3] |= 1 << (i & 7)
		_flags[k] = a.duplicate()
	_copy(bytes)


# `p` as KeeperPoseCodec writes it, in place.
func pose(p: KeeperPose) -> void:
	if reading:
		KeeperPoseCodec.read(_b, _o, p)
		_o += KeeperPoseCodec.SIZE
		return
	var k: int = _pose_n
	_pose_n += 1
	if k == _poses.size():
		_poses.append(null)
		var bytes := PackedByteArray()
		bytes.resize(KeeperPoseCodec.SIZE)
		_pose_bytes.append(bytes)
	var was: KeeperPose = _poses[k]
	if was == null or not KeeperPoseCodec.same(p, was):
		KeeperPoseCodec.write(p, _pose_bytes[k], 0)
		KeeperPoseCodec.read(_pose_bytes[k], 0, p)
		if was == null:
			was = KeeperPose.new()
			_poses[k] = was
		was.copy_from(p)
	_copy(_pose_bytes[k])


func leg(l: KeeperPose.Leg) -> void:
	l.ankle = v3_16(l.ankle, MM)
	l.knee_pinned = bit(l.knee_pinned)
	l.knee = v3_16(l.knee, MM)
	l.knee_pole = v3_16(l.knee_pole, MM)
	l.thigh_front = v3_16(l.thigh_front, MM)
	l.shin_front = v3_16(l.shin_front, MM)
	l.foot_mode = s8(l.foot_mode)
	l.toe = v3_16(l.toe, MM)
	l.flex = s16(l.flex, FRACTION)
	l.along_shin = s16(l.along_shin, FRACTION)


# The run of 2-D values `a`, `width` bytes a component: written, the entries
# that differ from the last write of this run encoded and snapped, the rest
# copied as they were.
func _v2s(a: PackedVector2Array, scale: float, width: int) -> void:
	var n: int = a.size()
	if reading:
		for i: int in n:
			var o: int = _o + i * 2 * width
			var cx: int = _b.decode_s16(o) if width == 2 else _b.decode_s32(o)
			var cy: int = _b.decode_s16(o + 2) if width == 2 else _b.decode_s32(o + 4)
			a[i] = Vector2(_value(cx, scale, width), _value(cy, scale, width))
		_o += n * 2 * width
		return
	var k: int = _run(n * 2 * width)
	var was: PackedVector2Array = _runs[k]
	var bytes: PackedByteArray = _run_bytes[k]
	if was.size() != n:
		was.resize(n)
		was.fill(Vector2(NAN, NAN))
	if was != a:
		var limit: float = (_MAX_16 if width == 2 else _MAX_32) * scale
		for i: int in n:
			var e: Vector2 = a[i]
			if e == was[i]:
				continue
			var cx: int = roundi(e.x / scale) if absf(e.x) <= limit else _code(e.x, width)
			var cy: int = roundi(e.y / scale) if absf(e.y) <= limit else _code(e.y, width)
			if width == 2:
				bytes.encode_s16(i * 4, cx)
				bytes.encode_s16(i * 4 + 2, cy)
			else:
				bytes.encode_s32(i * 8, cx)
				bytes.encode_s32(i * 8 + 4, cy)
			e = Vector2(_value(cx, scale, width), _value(cy, scale, width))
			a[i] = e
			was[i] = e
	_copy(bytes)


# The write-side memory for the next run, `size` bytes long; its index.
func _run(size: int) -> int:
	var k: int = _run_n
	_run_n += 1
	if k == _runs.size():
		_runs.append(PackedVector2Array())
		_flags.append(PackedByteArray())
		_run_bytes.append(PackedByteArray())
	if _run_bytes[k].size() != size:
		_run_bytes[k].resize(size)
		_runs[k] = PackedVector2Array()
		_flags[k] = PackedByteArray()
	return k


# `bytes` into the blob where the writer is.
func _copy(bytes: PackedByteArray) -> void:
	_b.resize(_o)
	_b.append_array(bytes)
	_o += bytes.size()
	_b.resize(_o + _MOST_BYTES)


func _code(v: float, width: int) -> int:
	return _code_16(v) if width == 2 else _code_32(v)


static func _value(code: int, scale: float, width: int) -> float:
	if width == 2:
		return float(code) * scale if code > _NEG_INF_16 and code < _INF_16 else _special_16(code)
	return float(code) * scale if code > _NEG_INF_32 and code < _INF_32 else _special_32(code)


# A value's code where it is not finite or not in range: its own code, or the
# range's end, counted.
func _code_16(v: float) -> int:
	if is_nan(v):
		return _NAN_16
	if is_inf(v):
		return _INF_16 if v > 0.0 else _NEG_INF_16
	overflow += 1
	return _MAX_16 if v > 0.0 else -_MAX_16


func _code_32(v: float) -> int:
	if is_nan(v):
		return _NAN_32
	if is_inf(v):
		return _INF_32 if v > 0.0 else _NEG_INF_32
	overflow += 1
	return _MAX_32 if v > 0.0 else -_MAX_32


static func _special_16(code: int) -> float:
	if code == _NAN_16:
		return NAN
	return INF if code == _INF_16 else -INF


static func _special_32(code: int) -> float:
	if code == _NAN_32:
		return NAN
	return INF if code == _INF_32 else -INF

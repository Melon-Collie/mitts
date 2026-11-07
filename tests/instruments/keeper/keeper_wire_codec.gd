extends RefCounted

# A KeeperController's wire set as bytes, and a keeper rebuilt from them: the
# fields keeper_state_cloner.gd copies, `skip` left out, walked in the same
# order (each script's variables in declaration order, the controller's world
# plumbing never), written to a flat buffer and read back onto another
# keeper's own objects.
#
# Layout: u16 offset of the bit section, the values in walk order, then every
# bool as one bit. Per value:
#   bool        a bit
#   int         s32 (EXACT, F32); s8 (Q16). KeeperController._ticks is read
#               only modulo PLANNER_EVERY and is sent as that residue, a byte.
#   float       f64 (EXACT; GDScript's floats are doubles), f32 (F32), or s16
#               at the field's scale (Q16, `scale_of`)
#   Vector2/3   f32 a component (EXACT, F32: the engine's own precision), or
#               s16 a component at the field's scale (Q16)
#   packed      u8 count, then the elements as above; a PackedByteArray as
#               bytes (EXACT, F32) or a bit each (Q16: the play read's flags)
#   Array       u8 count, then the elements
#   object      u8: 0 null, 1 written here, 2 + n the n-th object already
#               written (an alias: the route's movers are the motor's)
#   KeeperPose  in Q16, KeeperPoseCodec's 130 B; otherwise its fields
# A Q16 s16 keeps three codes for what a sentinel holds: 32767 +INF, -32767
# -INF, -32768 NaN; anything past ±32766 steps is clamped and counted in
# `overflow` by Class.field.
#
# `lossy_only` (Class names or Class.field keys, empty: everything) narrows F32
# or Q16 to those classes' own fields and those fields, the rest written
# EXACT: which fields a lossy wire breaks. `keep_exact` (Class.field keys)
# writes those EXACT whatever else is lossy.

const Cloner := preload("res://tests/instruments/keeper/keeper_state_cloner.gd")

enum Precision { EXACT, F32, Q16 }

const MM: float = 0.001
const ANGLE: float = PI / 32767.0
const MS: float = 0.001
const SPEED: float = 0.0025
const FRACTION: float = 1e-4
const _NAN_CODE: int = -32768
const _INF_CODE: int = 32767
const _NEG_INF_CODE: int = -32767
const _S16_MAX: int = 32766
const _REF_NULL: int = 0
const _REF_HERE: int = 1
const _REF_ALIAS: int = 2
const _HEADER: int = 2
const TICKS: String = "KeeperController._ticks"

# Q16 scales by Class.field, s16 steps of: angles at π/32767 (they stay
# within ±π), clocks at a millisecond, shares and fractions of 0..1 at 1e-4,
# velocities at 2.5 mm/s (±82 m/s: the puck's, and a spot's that jumps),
# everything else (metres) at a millimetre. Chosen from the largest value each
# field took over the plays (the instrument's audit).
const ANGLES: Array[String] = [
	"KeeperMotor.yaw", "KeeperMotor.lead", "KeeperMotor._face", "KeeperMotor._turn_rate",
	"KeeperMotor._anchor_yaw", "KeeperMotor._frozen_yaw", "KeeperMotor._Ask.side",
	"KeeperLook.yaw", "KeeperLook.pitch", "KeeperLook.trunk",
	"KeeperPost.yaw", "KeeperPost._yaw_from", "KeeperSlide.yaw", "KeeperSlide._yaw_from", "KeeperSlide._yaw_to",
	"KeeperSlide._heading", "KeeperRoute.facing", "KeeperSave.face_turn", "KeeperSave._face", "KeeperSave._back_face",
	"KeeperSave._poke_yaw", "KeeperPlayRead._gaze", "KeeperPositioning._seal_turn", "KeeperFootwork._turn",
	"KeeperFootwork._turn_from", "KeeperGlide._turn", "KeeperClear.way", "KeeperPose.blade_yaw",
	"KeeperPose.stick_tilt",
]
const CLOCKS: Array[String] = [
	"KeeperController._holding", "KeeperController._out_of_reach_s", "KeeperController._chosen_at",
	"KeeperController._over_at", "KeeperShotRead.age", "KeeperShotRead._hidden_s", "KeeperPlayRead.watched_s",
	"KeeperSave.ready_s", "KeeperSave.impact_s", "KeeperSave._back_at", "KeeperSave._watched",
	"KeeperMotor._spot_since", "KeeperSaveMove._clock", "KeeperDrop._clock", "KeeperPost._clock",
	"KeeperPost._drop_in_s", "KeeperSlide._clock", "KeeperSlide._turn_s", "KeeperPositioning._racing",
]
const VELOCITIES: Array[String] = [
	"KeeperMotor._spot_velocity", "KeeperMotor._velocity", "KeeperPlayRead.motion", "KeeperPlayRead._moving",
	"KeeperPositioning._velocity", "KeeperShotRead.velocity", "KeeperShotRead._from_velocity",
	"KeeperSaveMove.velocity", "KeeperGlide.velocity", "KeeperFootwork.speed", "KeeperSlide.speed",
	"KeeperSlide._stop_from_speed", "KeeperFootwork._stop_from_speed",
]
const FRACTIONS: Array[String] = [
	"KeeperMotor.fall", "KeeperSaveMove.fall", "KeeperDrop.fall", "KeeperSlide.fall", "KeeperLowReady.share",
	"KeeperLowReady._sunk", "KeeperFootwork.phase", "KeeperGlide._phase", "KeeperSlide.phase", "KeeperSlide._fold",
	"KeeperSave._lean", "KeeperSave._lean_to", "KeeperPose.Leg.flex", "KeeperPose.Leg.along_shin",
]

var precision: int = Precision.EXACT
var skip: Dictionary = {}
var lossy_only: Dictionary = {}
var keep_exact: Dictionary = {}
# Class.field → values clamped (Q16), and → the largest magnitude written.
var overflow: Dictionary = {}
var largest: Dictionary = {}
var audit: bool = false
var unsupported: Dictionary = {}
# The last decode's own time, his fields alone (no pose solved, no box seated).
var fields_us: float = 0.0

var _cloner: RefCounted = Cloner.new()
var _scales: Dictionary = {}
var _props: Dictionary = {}
var _buf := PackedByteArray()
var _bits := PackedByteArray()
var _o: int = 0
var _nbits: int = 0
var _seen: Dictionary = {}
var _objs: Array = []
var _claimed: Dictionary = {}
var _q: bool = false
var _f32: bool = false


func _init(p_precision: int = Precision.EXACT, p_skip: Dictionary = {}, p_lossy_only: Array = [],
		p_keep_exact: Array = []) -> void:
	precision = p_precision
	skip = p_skip
	for k: String in p_keep_exact:
		keep_exact[k] = true
	for c: String in p_lossy_only:
		lossy_only[c] = true
	for f: String in ANGLES:
		_scales[f] = ANGLE
	for f: String in CLOCKS:
		_scales[f] = MS
	for f: String in FRACTIONS:
		_scales[f] = FRACTION
	for f: String in VELOCITIES:
		_scales[f] = SPEED
	_buf.resize(8192)
	_bits.resize(1024)


func scale_of(key: String) -> float:
	return float(_scales.get(key, MM))


# ── Encode ────────────────────────────────────────────────────────────────────

func encode(src: KeeperController) -> PackedByteArray:
	_o = _HEADER
	_nbits = 0
	_bits.fill(0)
	_seen.clear()
	_enc_fields(src, "KeeperController", true)
	_buf.encode_u16(0, _o)
	var out: PackedByteArray = _buf.slice(0, _o)
	out.append_array(_bits.slice(0, (_nbits + 7) >> 3))
	return out


func _enc_fields(o: Object, cls: String, top: bool = false) -> void:
	var was: bool = _q
	var was_f32: bool = _f32
	for p: Array in _props_of(o, cls, top):
		var f: StringName = p[0]
		_q = p[5] and precision == Precision.Q16
		_f32 = p[5] and precision == Precision.F32
		if p[3] == TICKS:
			_room(1)
			_buf.encode_u8(_o, int(o.get(f)) % KeeperController.PLANNER_EVERY)
			_o += 1
			continue
		_enc(o.get(f), int(p[1]), p[3])
	_q = was
	_f32 = was_f32


func _enc(v: Variant, declared: int, key: String) -> void:
	var t: int = typeof(v)
	if declared == TYPE_NIL:
		_room(1)
		_buf.encode_u8(_o, t)
		_o += 1
	match t:
		TYPE_NIL:
			_room(1)
			_buf.encode_u8(_o, _REF_NULL)
			_o += 1
		TYPE_BOOL:
			_bit(bool(v))
		TYPE_INT:
			_int(int(v), key)
		TYPE_FLOAT:
			_float(float(v), key)
		TYPE_VECTOR2:
			var w: Vector2 = v
			_comp(w.x, key)
			_comp(w.y, key)
		TYPE_VECTOR3:
			var w3: Vector3 = v
			_comp(w3.x, key)
			_comp(w3.y, key)
			_comp(w3.z, key)
		TYPE_PACKED_VECTOR2_ARRAY:
			var a2: PackedVector2Array = v
			_count(a2.size())
			for e: Vector2 in a2:
				_comp(e.x, key)
				_comp(e.y, key)
		TYPE_PACKED_VECTOR3_ARRAY:
			var a3: PackedVector3Array = v
			_count(a3.size())
			for e: Vector3 in a3:
				_comp(e.x, key)
				_comp(e.y, key)
				_comp(e.z, key)
		TYPE_PACKED_BYTE_ARRAY:
			var ab: PackedByteArray = v
			_count(ab.size())
			for e: int in ab:
				if _q:
					if e > 1:
						overflow[key] = int(overflow.get(key, 0)) + 1
					_bit(e != 0)
				else:
					_room(1)
					_buf.encode_u8(_o, e)
					_o += 1
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			_count(v.size())
			for e: float in v:
				_float(e, key)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			_count(v.size())
			for e: int in v:
				_int(e, key)
		TYPE_ARRAY:
			var arr: Array = v
			_count(arr.size())
			var et: int = arr.get_typed_builtin()
			for e: Variant in arr:
				_enc(e, et, key)
		TYPE_OBJECT:
			_enc_object(v as Object, key)
		_:
			unsupported[key] = type_string(t)


func _enc_object(o: Object, key: String) -> void:
	_room(1)
	if o == null:
		_buf.encode_u8(_o, _REF_NULL)
		_o += 1
		return
	var id: int = o.get_instance_id()
	if _seen.has(id):
		_buf.encode_u8(_o, _REF_ALIAS + int(_seen[id]))
		_o += 1
		return
	_buf.encode_u8(_o, _REF_HERE)
	_o += 1
	_seen[id] = _seen.size()
	if o is Node or o is GoalieSkillProfile or o.get_script() == null:
		unsupported[key] = o.get_class()
		return
	if o is KeeperPose and _pose_q():
		_room(KeeperPoseCodec.SIZE)
		KeeperPoseCodec.write(o as KeeperPose, _buf, _o)
		_o += KeeperPoseCodec.SIZE
		return
	_enc_fields(o, _class_key(o))


func _pose_q() -> bool:
	return precision == Precision.Q16 and (lossy_only.is_empty() or lossy_only.has("KeeperPose"))


func _int(v: int, key: String) -> void:
	_room(4)
	if _q:
		if v < -128 or v > 127:
			overflow[key] = int(overflow.get(key, 0)) + 1
		_buf.encode_s8(_o, clampi(v, -128, 127))
		_o += 1
	else:
		_buf.encode_s32(_o, v)
		_o += 4


func _float(v: float, key: String) -> void:
	_room(8)
	if _q:
		_s16(v, scale_of(key), key)
	elif _f32:
		_buf.encode_float(_o, v)
		_o += 4
	else:
		_buf.encode_double(_o, v)
		_o += 8


# A vector component: f32 is the engine's own precision, so only Q16 rounds.
func _comp(v: float, key: String) -> void:
	_room(4)
	if _q:
		_s16(v, scale_of(key), key)
	else:
		_buf.encode_float(_o, v)
		_o += 4


func _s16(v: float, scale: float, key: String) -> void:
	var code: int
	if is_nan(v):
		code = _NAN_CODE
	elif is_inf(v):
		code = _INF_CODE if v > 0.0 else _NEG_INF_CODE
	else:
		var r: int = roundi(v / scale)
		if absi(r) > _S16_MAX:
			overflow[key] = int(overflow.get(key, 0)) + 1
		code = clampi(r, -_S16_MAX, _S16_MAX)
		if audit:
			largest[key] = maxf(float(largest.get(key, 0.0)), absf(v))
	_buf.encode_s16(_o, code)
	_o += 2


func _count(n: int) -> void:
	_room(1)
	_buf.encode_u8(_o, mini(n, 255))
	_o += 1


func _bit(b: bool) -> void:
	if (_nbits >> 3) >= _bits.size():
		_bits.resize(_bits.size() * 2)
	if b:
		_bits[_nbits >> 3] |= 1 << (_nbits & 7)
	_nbits += 1


func _room(n: int) -> void:
	if _o + n > _buf.size():
		_buf.resize(_buf.size() * 2)


# ── Decode ────────────────────────────────────────────────────────────────────

# `b`'s state onto `dst`: his fields, then the node placed where his motor has
# him (as KeeperController._place_body places it), his body posed from his pose
# and his save boxes seated on it.
func decode(b: PackedByteArray, dst: KeeperController) -> void:
	var t0: int = Time.get_ticks_usec()
	var own: PackedByteArray = _buf
	_buf = b
	_o = _HEADER
	_nbits = b.decode_u16(0) * 8
	_objs.clear()
	_claimed.clear()
	_dec_fields(dst, "KeeperController", true)
	_buf = own
	fields_us = float(Time.get_ticks_usec() - t0)
	dst._keeper.apply_pose(dst._keeper_pose)
	dst.goalie.global_transform = dst._net * Transform3D(Basis(Vector3.UP, dst.motor.yaw),
			Vector3(dst.motor.x, 0.0, dst.motor.z))
	for part: int in KeeperGear.PART_COUNT:
		dst.goalie.seat_save_box(part, KeeperGear.box(dst._keeper.skeleton, part))


func _dec_fields(o: Object, cls: String, top: bool = false) -> void:
	var was: bool = _q
	var was_f32: bool = _f32
	for p: Array in _props_of(o, cls, top):
		var f: StringName = p[0]
		_q = p[5] and precision == Precision.Q16
		_f32 = p[5] and precision == Precision.F32
		if p[3] == TICKS:
			o.set(f, _buf.decode_u8(_o))
			_o += 1
			continue
		o.set(f, _dec(o.get(f), int(p[1]), p[2], p[4]))
	_q = was
	_f32 = was_f32


func _dec(into: Variant, declared: int, script: Variant, scale: float) -> Variant:
	var t: int = declared
	if declared == TYPE_NIL:
		t = _buf.decode_u8(_o)
		_o += 1
	match t:
		TYPE_NIL:
			_o += 1
			return null
		TYPE_BOOL:
			return _read_bit()
		TYPE_INT:
			return _read_int()
		TYPE_FLOAT:
			return _read_float(scale)
		TYPE_VECTOR2:
			var x: float = _read_comp(scale)
			return Vector2(x, _read_comp(scale))
		TYPE_VECTOR3:
			var x3: float = _read_comp(scale)
			var y3: float = _read_comp(scale)
			return Vector3(x3, y3, _read_comp(scale))
		TYPE_PACKED_VECTOR2_ARRAY:
			var a2 := PackedVector2Array()
			a2.resize(_read_count())
			for i: int in a2.size():
				var x: float = _read_comp(scale)
				a2[i] = Vector2(x, _read_comp(scale))
			return a2
		TYPE_PACKED_VECTOR3_ARRAY:
			var a3 := PackedVector3Array()
			a3.resize(_read_count())
			for i: int in a3.size():
				var x: float = _read_comp(scale)
				var y: float = _read_comp(scale)
				a3[i] = Vector3(x, y, _read_comp(scale))
			return a3
		TYPE_PACKED_BYTE_ARRAY:
			var ab := PackedByteArray()
			ab.resize(_read_count())
			for i: int in ab.size():
				if _q:
					ab[i] = 1 if _read_bit() else 0
				else:
					ab[i] = _buf.decode_u8(_o)
					_o += 1
			return ab
		TYPE_PACKED_FLOAT32_ARRAY:
			var af := PackedFloat32Array()
			af.resize(_read_count())
			for i: int in af.size():
				af[i] = _read_float(scale)
			return af
		TYPE_PACKED_FLOAT64_ARRAY:
			var ad := PackedFloat64Array()
			ad.resize(_read_count())
			for i: int in ad.size():
				ad[i] = _read_float(scale)
			return ad
		TYPE_PACKED_INT32_ARRAY:
			var ai := PackedInt32Array()
			ai.resize(_read_count())
			for i: int in ai.size():
				ai[i] = _read_int()
			return ai
		TYPE_PACKED_INT64_ARRAY:
			var al := PackedInt64Array()
			al.resize(_read_count())
			for i: int in al.size():
				al[i] = _read_int()
			return al
		TYPE_ARRAY:
			return _dec_array(into as Array, scale)
		TYPE_OBJECT:
			return _dec_object(into, script)
	return into


# Into a new array of the same type, never the one the field holds: an array
# can be held by two fields (where the reflective copy gives each its own), and
# written in place a decode would reach both.
func _dec_array(was: Array, scale: float) -> Array:
	var n: int = _read_count()
	var arr: Array = was.duplicate(false)
	arr.resize(n)
	var et: int = arr.get_typed_builtin()
	var es: Variant = arr.get_typed_script()
	for i: int in n:
		arr[i] = _dec(was[i] if i < was.size() else null, et, es, scale)
	return arr


func _dec_object(into: Variant, script: Variant) -> Variant:
	var ref: int = _buf.decode_u8(_o)
	_o += 1
	if ref == _REF_NULL:
		return null
	if ref >= _REF_ALIAS:
		return _objs[ref - _REF_ALIAS]
	var dst: Object = null
	if into is Object and into != null and not _claimed.has((into as Object).get_instance_id()):
		dst = into
	else:
		var s: Script = script if script is Script else (into as Object).get_script() if into is Object else null
		dst = Cloner._make(s)
	_objs.append(dst)
	_claimed[dst.get_instance_id()] = true
	if dst is KeeperPose and _pose_q():
		KeeperPoseCodec.read(_buf, _o, dst as KeeperPose)
		_o += KeeperPoseCodec.SIZE
		return dst
	_dec_fields(dst, _class_key(dst))
	return dst


func _read_bit() -> bool:
	var at: int = _nbits
	_nbits += 1
	return (_buf[at >> 3] >> (at & 7)) & 1 == 1


func _read_int() -> int:
	if _q:
		_o += 1
		return _buf.decode_s8(_o - 1)
	_o += 4
	return _buf.decode_s32(_o - 4)


func _read_float(scale: float) -> float:
	if _q:
		return _read_s16(scale)
	if _f32:
		_o += 4
		return _buf.decode_float(_o - 4)
	_o += 8
	return _buf.decode_double(_o - 8)


func _read_comp(scale: float) -> float:
	if _q:
		return _read_s16(scale)
	_o += 4
	return _buf.decode_float(_o - 4)


func _read_s16(scale: float) -> float:
	var code: int = _buf.decode_s16(_o)
	_o += 2
	match code:
		_NAN_CODE:
			return NAN
		_INF_CODE:
			return INF
		_NEG_INF_CODE:
			return -INF
	return float(code) * scale


func _read_count() -> int:
	_o += 1
	return _buf.decode_u8(_o - 1)


# ── Shared ────────────────────────────────────────────────────────────────────

# The variables of `o`'s script this codec writes, cached by script: [name,
# declared type, the script an object field holds, Class.field, its Q16 scale,
# whether it is written at the codec's precision or EXACT].
func _props_of(o: Object, cls: String, top: bool) -> Array:
	var s: Script = o.get_script()
	if _props.has(s):
		return _props[s]
	var out: Array = []
	for p: Dictionary in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var f: String = String(p["name"])
		var key: String = cls + "." + f
		if (top and _cloner._world.has(f)) or skip.has(key):
			continue
		out.append([StringName(f), int(p["type"]), _script_named(String(p["class_name"])), key, scale_of(key),
				(lossy_only.is_empty() or lossy_only.has(cls) or lossy_only.has(key)) and not keep_exact.has(key)])
	_props[s] = out
	return out


static func _script_named(n: String) -> Variant:
	if n == "":
		return null
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if String(c["class"]) == n:
			return load(String(c["path"]))
	return null


func _class_key(o: Object) -> String:
	if o is KeeperMotor._Ask:
		return "KeeperMotor._Ask"
	return Cloner.class_of(o)

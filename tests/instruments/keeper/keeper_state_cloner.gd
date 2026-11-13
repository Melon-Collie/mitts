extends RefCounted

# A KeeperController's sim state copied onto another, by reflection: every
# script variable of the controller, its collaborators and the Keeper node's
# skeleton, RefCounted objects deep-copied (into the destination's own objects
# where it has one of the same script, so its aliases survive: brain.play is
# the controller's play, the route's footwork is the motor's), arrays and
# dictionaries copied, value types and packed arrays assigned (copy on write).
#
# Shared, never copied: nodes (his goalie, the puck, the skaters), the tier's
# profile, and the controller's world and wire plumbing (`WORLD`). Anything
# else the walk meets that it cannot copy (a Callable, a Signal, an engine
# object other than a node) is counted in `uncopyable`, by path, so a report
# says when the copy is incomplete.
#
# `skip` (Class.field keys) leaves those fields as the destination has them:
# the wire set's check, which copies only what the wire would carry and holds
# the result against the full copy.

const WORLD: Array[String] = ["goalie", "puck", "is_server", "team_id", "_keeper", "_view", "_skater_getter",
		"_state_buffer", "_scratch_bracket", "_scratch_state", "is_extrapolating", "_rejoin_blend_elapsed",
		"_rejoin_blend_from_x", "_rejoin_blend_from_z", "extrapolation_max_ms", "rejoin_blend_duration",
		"_goal_line_z", "_goal_center_x", "_profile", "_wire", "wire_state", "wire_state_time",
		"seat_places_only", "_predictor", "_world_source", "_restep_ease", "_drew_predicted"]
# The Keeper node's own state: the skeleton solved from his pose, the last one
# it drew (whether the next pose moved him), and the acceleration his tail
# swings to.
const KEEPER_NODE: Array[String] = ["skeleton", "_was", "acceleration"]

var uncopyable: Dictionary = {}

var _props: Dictionary = {}
var _memo: Dictionary = {}
var _claimed: Dictionary = {}
var _world: Dictionary = {}
var _skip: Dictionary = {}


func _init() -> void:
	for f: String in WORLD:
		_world[f] = true


# `src`'s state onto `dst`: the controller, the Keeper's skeleton, the node
# placed on him and his save boxes seated on that skeleton. `skip`, Class.field
# keys left as `dst` has them.
func copy(src: KeeperController, dst: KeeperController, skip: Dictionary = {}) -> void:
	_memo.clear()
	_claimed.clear()
	_skip = skip
	_copy_fields(src, dst, "KeeperController", _world)
	if skip.has("Keeper.skeleton"):
		dst._keeper.apply_pose(dst._keeper_pose)
	else:
		for f: String in KEEPER_NODE:
			dst._keeper.set(f, _value(src._keeper.get(f), dst._keeper.get(f), "Keeper." + f))
	dst.goalie.global_transform = src.goalie.global_transform
	for part: int in KeeperGear.PART_COUNT:
		dst.goalie.seat_save_box(part, KeeperGear.box(dst._keeper.skeleton, part))


# The script variables of `o`'s script, cached by script.
func names_of(o: Object) -> PackedStringArray:
	var s: Script = o.get_script()
	if _props.has(s):
		return _props[s]
	var out := PackedStringArray()
	for p: Dictionary in o.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p["name"]))
	_props[s] = out
	return out


static func class_of(o: Object) -> String:
	var s: Script = o.get_script()
	if s == null:
		return o.get_class()
	var n: String = String(s.get_global_name())
	if n != "":
		return n
	if o is KeeperPose.Leg:
		return "KeeperPose.Leg"
	return "an inner class"


func _copy_fields(src: Object, dst: Object, cls: String, except: Dictionary) -> void:
	for f: String in names_of(src):
		if except.has(f) or _skip.has(cls + "." + f):
			continue
		dst.set(f, _value(src.get(f), dst.get(f), cls + "." + f))


func _value(v: Variant, into: Variant, path: String) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _object(v as Object, into, path)
		TYPE_ARRAY:
			return _array(v as Array, into, path)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out: Dictionary = d.duplicate(false)
			for k: Variant in d:
				out[k] = _value(d[k], null, path + "[]")
			return out
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			uncopyable[path] = type_string(typeof(v))
			return into
	return v


func _object(o: Object, into: Variant, path: String) -> Variant:
	if o == null:
		return null
	if o is Node or o is GoalieSkillProfile:
		return o
	if not (o is RefCounted) or o.get_script() == null:
		uncopyable[path] = o.get_class()
		return o
	var id: int = o.get_instance_id()
	if _memo.has(id):
		return _memo[id]
	var dst: Object = null
	if into is Object and into != null and (into as Object).get_script() == o.get_script() \
			and not _claimed.has((into as Object).get_instance_id()):
		dst = into
	else:
		dst = _make(o.get_script())
	_memo[id] = dst
	_claimed[dst.get_instance_id()] = true
	_copy_fields(o, dst, class_of(o), {})
	return dst


func _array(a: Array, into: Variant, path: String) -> Array:
	var out: Array
	if into is Array and (into as Array).get_typed_builtin() == a.get_typed_builtin() \
			and (into as Array).get_typed_script() == a.get_typed_script() and not (into as Array).is_read_only():
		out = into
		var was: Array = out.duplicate(false)
		out.resize(a.size())
		for i: int in a.size():
			out[i] = _value(a[i], was[i] if i < was.size() else null, path + "[]")
		return out
	out = a.duplicate(false)
	for i: int in a.size():
		out[i] = _value(a[i], null, path + "[]")
	return out


# An instance of `s`, its constructor given each argument's type's zero.
static func _make(s: Script) -> Object:
	for m: Dictionary in s.get_script_method_list():
		if String(m["name"]) != "_init":
			continue
		var args: Array = []
		for a: Dictionary in m["args"]:
			args.append(type_convert(null, int(a["type"])))
		return s.callv("new", args)
	return s.call("new")


# What `src`'s state weighs, `skip` left out: per top-level field of the
# controller (its collaborators by name, `first` before the rest so an alias is
# counted under its owner), [raw bytes (f32 floats, i32 ints, a byte a bool),
# bytes quantized at KeeperPoseCodec's scales (a position 2 B a component, a
# scalar 2 B, an int 1 B, a bool a bit, a KeeperPose its SIZE), leaves,
# KeeperPoses]. `listing` gets each class's fields counted, by Class.
func account(src: KeeperController, skip: Dictionary, first: Array[String], listing: Dictionary) -> Dictionary:
	_memo.clear()
	_skip = skip
	var out: Dictionary = {}
	var order: Array[String] = first.duplicate()
	for f: String in names_of(src):
		if not order.has(f):
			order.append(f)
	for f: String in order:
		if _world.has(f) or skip.has("KeeperController." + f):
			continue
		var acc := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		_acc(src.get(f), acc, listing)
		_list(listing, "KeeperController", f)
		out[f] = acc
	if not skip.has("Keeper.skeleton"):
		for f: String in KEEPER_NODE:
			var acc := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
			_acc(src._keeper.get(f), acc, listing)
			_list(listing, "Keeper", f)
			out["Keeper." + f] = acc
	return out


static func _list(listing: Dictionary, cls: String, f: String) -> void:
	if not listing.has(cls):
		listing[cls] = PackedStringArray()
	var names: PackedStringArray = listing[cls]
	if not names.has(f):
		names.append(f)
		listing[cls] = names


func _acc(v: Variant, acc: PackedFloat64Array, listing: Dictionary) -> void:
	var n: float = 1.0
	match typeof(v):
		TYPE_BOOL:
			_add(acc, 1.0, 0.125, 1.0)
		TYPE_INT:
			_add(acc, 4.0, 1.0, 1.0)
		TYPE_FLOAT:
			_add(acc, 4.0, 2.0, 1.0)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			_add(acc, 8.0, 4.0, 1.0)
		TYPE_VECTOR3, TYPE_VECTOR3I:
			_add(acc, 12.0, 6.0, 1.0)
		TYPE_VECTOR4, TYPE_QUATERNION:
			_add(acc, 16.0, 6.0, 1.0)
		TYPE_BASIS:
			_add(acc, 36.0, 6.0, 1.0)
		TYPE_TRANSFORM3D:
			_add(acc, 48.0, 12.0, 1.0)
		TYPE_PACKED_VECTOR2_ARRAY:
			n = float((v as PackedVector2Array).size())
			_add(acc, 8.0 * n, 4.0 * n, n)
		TYPE_PACKED_VECTOR3_ARRAY:
			n = float((v as PackedVector3Array).size())
			_add(acc, 12.0 * n, 6.0 * n, n)
		TYPE_PACKED_FLOAT32_ARRAY:
			n = float((v as PackedFloat32Array).size())
			_add(acc, 4.0 * n, 2.0 * n, n)
		TYPE_PACKED_FLOAT64_ARRAY:
			n = float((v as PackedFloat64Array).size())
			_add(acc, 8.0 * n, 2.0 * n, n)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			n = float(v.size())
			_add(acc, 4.0 * n, n, n)
		TYPE_PACKED_BYTE_ARRAY:
			n = float((v as PackedByteArray).size())
			_add(acc, n, 0.125 * n, n)
		TYPE_ARRAY:
			for e: Variant in v:
				_acc(e, acc, listing)
		TYPE_DICTIONARY:
			for e: Variant in (v as Dictionary).values():
				_acc(e, acc, listing)
		TYPE_OBJECT:
			_acc_object(v as Object, acc, listing)


func _acc_object(o: Object, acc: PackedFloat64Array, listing: Dictionary) -> void:
	if o == null or o is Node or o is GoalieSkillProfile or not (o is RefCounted) or o.get_script() == null:
		return
	var id: int = o.get_instance_id()
	if _memo.has(id):
		return
	_memo[id] = o
	var cls: String = class_of(o)
	if o is KeeperPose:
		var pose := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		for f: String in names_of(o):
			_acc(o.get(f), pose, listing)
		_add(acc, pose[0], float(KeeperPoseCodec.SIZE), pose[2])
		acc[3] += 1.0
		return
	for f: String in names_of(o):
		if _skip.has(cls + "." + f):
			continue
		_list(listing, cls, f)
		_acc(o.get(f), acc, listing)


static func _add(acc: PackedFloat64Array, raw: float, quantized: float, leaves: float) -> void:
	acc[0] += raw
	acc[1] += quantized
	acc[2] += leaves

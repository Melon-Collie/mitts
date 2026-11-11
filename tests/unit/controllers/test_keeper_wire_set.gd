extends GutTest

# The keeper's wire set (KeeperController.wire) against what the prediction
# instrument found a client needs: every script variable reachable from his
# controller is either on the wire or named off it, where the instrument names
# what it checked a client does without (`NOT_ON_WIRE`, the cloner's `WORLD`).
# Each field reachable and not named off is given a value of its own on one
# keeper, his blob read into another, and the two held equal field by field: a
# field a keeper class gains that the hand-written walk misses fails here by
# name until it is written or named off.

const Inst := preload("res://tests/instruments/keeper/test_keeper_prediction.gd")
const Cloner := preload("res://tests/instruments/keeper/keeper_state_cloner.gd")
const GOAL_Z: float = -GameRules.GOAL_LINE_Z
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION

var _off: Dictionary = {}
var _world: Dictionary = {}


func before_all() -> void:
	for f: String in Inst.NOT_ON_WIRE:
		_off[f] = true
	for f: String in Cloner.WORLD:
		_world[f] = true


func _keeper() -> KeeperController:
	var goalie: Goalie = (load("res://Scenes/Goalie.tscn") as PackedScene).instantiate() as Goalie
	var puck: Puck = (load("res://Scenes/Puck.tscn") as PackedScene).instantiate() as Puck
	var ctrl := KeeperController.new()
	for n: Node in [goalie, puck, ctrl]:
		add_child_autofree(n)
		n.set_physics_process(false)
		n.set_process(false)
	puck.set_server_mode(true)
	ctrl.set_skater_getter(func() -> Array: return [])
	ctrl.setup(goalie, puck, GOAL_Z, true)
	ctrl.reset_to_crease()
	return ctrl


static func _class_key(o: Object) -> String:
	if o is KeeperMotor._Ask:
		return "KeeperMotor._Ask"
	return Cloner.class_of(o)


# Every field the wire must carry, as [owner, field name, Class.field], in walk
# order; an object is walked into once (the route's movers are the motor's).
func _fields(o: Object, cls: String, top: bool, seen: Dictionary, out: Array) -> void:
	for p: Dictionary in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var f: String = String(p["name"])
		var key: String = cls + "." + f
		if (top and _world.has(f)) or _off.has(key):
			continue
		var v: Variant = o.get(f)
		if v is Object and v != null and not (v is KeeperPose):
			var ob: Object = v
			if not seen.has(ob.get_instance_id()):
				seen[ob.get_instance_id()] = true
				_fields(ob, _class_key(ob), false, seen, out)
			continue
		if v is Array:
			for e: Variant in v:
				if e is Object and e != null:
					_fields(e as Object, _class_key(e as Object), false, seen, out)
		out.append([o, f, key])


# A value for field number `i` unlike any it starts with, in its wire range.
static func _perturb(v: Variant, i: int) -> Variant:
	var x: float = 0.25 + 0.01 * float(i % 50)
	match typeof(v):
		TYPE_BOOL:
			return not v
		TYPE_INT:
			return 1 if int(v) != 1 else 2
		TYPE_FLOAT:
			return x if not is_equal_approx(float(v), x) else x + 0.005
		TYPE_VECTOR2:
			return Vector2(x, -x)
		TYPE_VECTOR3:
			return Vector3(x, -x, 0.5 * x)
		TYPE_PACKED_VECTOR2_ARRAY:
			var a: PackedVector2Array = (v as PackedVector2Array).duplicate()
			for k: int in a.size():
				a[k] = Vector2(x + 0.001 * k, -x)
			return a
		TYPE_PACKED_BYTE_ARRAY:
			var b: PackedByteArray = (v as PackedByteArray).duplicate()
			for k: int in b.size():
				b[k] = (k + i) % 2
			return b
		TYPE_ARRAY:
			var arr: Array = (v as Array).duplicate()
			for k: int in arr.size():
				if arr[k] is Vector3:
					arr[k] = Vector3(x, 0.1 * k, -x)
			return arr
		TYPE_OBJECT:
			var p: KeeperPose = v
			p.pelvis += Vector3(0.1, 0.0, 0.05)
			p.blade_yaw = x
			p.legs[1].flex = x
			return p
	return v


static func _same(a: Variant, b: Variant) -> bool:
	if a is KeeperPose:
		return _pose_bytes(a) == _pose_bytes(b)
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for k: int in (a as Array).size():
			if not (a[k] is Object) and not _same(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_FLOAT and is_nan(a):
		return typeof(b) == TYPE_FLOAT and is_nan(b)
	return typeof(a) == typeof(b) and a == b


static func _pose_bytes(p: KeeperPose) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(KeeperPoseCodec.SIZE)
	KeeperPoseCodec.write(p, b, 0)
	return b


func test_every_field_off_the_named_list_is_carried() -> void:
	var a: KeeperController = _keeper()
	var b: KeeperController = _keeper()
	a.motor.face(1.0)
	a.motor.slide_to(Vector2(0.5, -1.0), 2.0)
	var fields: Array = []
	_fields(a, "KeeperController", true, {}, fields)
	for i: int in fields.size():
		var f: Array = fields[i]
		var o: Object = f[0]
		o.set(f[1], _perturb(o.get(f[1]), i))
	var blob := PackedByteArray()
	a.append_wire_state(blob)
	assert_true(b.apply_wire_state(blob), "the blob reads whole")
	var back: Array = []
	_fields(b, "KeeperController", true, {}, back)
	assert_eq(back.size(), fields.size(), "the same fields both ends")
	var missed: PackedStringArray = []
	for i: int in mini(fields.size(), back.size()):
		var fa: Array = fields[i]
		var fb: Array = back[i]
		if fa[2] != fb[2] or not _same((fa[0] as Object).get(fa[1]), (fb[0] as Object).get(fb[1])):
			missed.append(String(fa[2]))
	assert_eq(missed, PackedStringArray(), "every field the wire set holds round-trips")
	assert_gt(fields.size(), 200, "the walk reached his collaborators")
	assert_eq(b.motor._queue.size(), 2, "the moves asked for")


func test_his_blob_is_one_length_and_reads_back_to_itself() -> void:
	var a: KeeperController = _keeper()
	var b: KeeperController = _keeper()
	var at_rest := PackedByteArray()
	a.append_wire_state(at_rest)
	a.puck.global_position = Vector3(2.0, a.puck.ice_height, GOAL_Z + 6.0)
	a.puck.linear_velocity = Vector3(-3.0, 0.0, 1.0)
	for _t: int in 40:
		a._view.invalidate()
		a._physics_process(DT)
	var blob := PackedByteArray()
	a.append_wire_state(blob)
	assert_eq(blob.size(), at_rest.size(), "fixed length, whatever he is doing")
	var again := PackedByteArray()
	a.append_wire_state(again)
	assert_eq(again, blob, "his state snapped: written again, the same bytes")
	var fresh := PackedByteArray()
	var w := KeeperWire.new()
	w.begin_write(fresh)
	a.wire(w)
	w.finish_write()
	assert_eq(fresh, blob, "a writer with no memory of him writes the same")
	assert_true(b.apply_wire_state(blob))
	var from_b := PackedByteArray()
	b.append_wire_state(from_b)
	assert_eq(from_b, blob, "a keeper read from the blob writes the blob")
	assert_eq(b.goalie.global_transform, a.goalie.global_transform, "the node placed where his motor has him")
	gut.p("keeper blob: %d B" % blob.size())


func test_a_puck_anywhere_on_the_rink_fits_his_read() -> void:
	var a: KeeperController = _keeper()
	a.puck.global_position = Vector3(-12.0, a.puck.ice_height, -GOAL_Z - 2.0)
	a.puck.linear_velocity = Vector3(30.0, 0.0, 30.0)
	for _t: int in 80:
		a._view.invalidate()
		a._physics_process(DT)
	assert_gt(absf(a.play.puck.y), 32.8, "the far end, past a 16-bit millimetre")
	var blob := PackedByteArray()
	a._wire.overflow = 0
	a.append_wire_state(blob)
	assert_eq(a._wire.overflow, 0, "nothing clamped")

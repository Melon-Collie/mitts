class_name SkaterArmEnvelope
extends RefCounted

# The derived carry envelope (ArmEnvelope), read once from its data file and
# shared by every skater; null where the file is missing or out of date, and
# the carry then keeps the closed-form solve.

static var _shared: ArmEnvelope = null
static var _read: bool = false


static func shared() -> ArmEnvelope:
	if _read:
		return _shared
	_read = true
	var f: FileAccess = FileAccess.open(ArmEnvelope.PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_shared = ArmEnvelope.from_dict(parsed)
	return _shared

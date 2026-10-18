class_name NativeShotOddsFactory

# Builds a NativeShotOdds (C++ GDExtension, native/src/) for
# AIShotOdds.native_factory; AIShotOdds loads its field into it. One per field:
# the kernel holds the query it last ran, and the bots run on the AI worker.
#
# Leaves AIShotOdds on GDScript when the extension isn't loaded.


static func install() -> void:
	if ClassDB.class_exists(&"NativeShotOdds"):
		AIShotOdds.native_factory = make
		AIShotOdds.attach_native()


static func make() -> RefCounted:
	if not ClassDB.class_exists(&"NativeShotOdds"):
		return null
	return ClassDB.instantiate(&"NativeShotOdds")

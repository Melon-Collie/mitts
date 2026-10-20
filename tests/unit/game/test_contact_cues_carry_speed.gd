extends GutTest

# Every puck-contact cue the host broadcasts carries the speed it measured, which
# sets the cue's volume on the receiving client: a client's puck node holds no
# velocity of its own, so it has nothing local to read.

const CUES: Array[String] = [
	"board_hit_received", "goal_body_hit_received", "post_hit_received",
	"goalie_hit_received", "deflection_received", "body_block_received",
	"puck_strip_received", "stick_lift_received",
]


func _signal_args(signal_name: String) -> Array:
	for sig: Dictionary in NetworkManager.get_signal_list():
		if sig["name"] == signal_name:
			return sig["args"]
	return []


func test_every_contact_cue_carries_the_hosts_speed() -> void:
	for cue: String in CUES:
		var args: Array = _signal_args(cue)
		assert_eq(args.size(), 2, "%s: position and speed" % cue)
		if args.size() == 2:
			assert_eq(args[1]["name"], "speed", cue)


func test_the_received_speed_reaches_the_listener() -> void:
	var heard: Array[float] = []
	var listener := func(_pos: Vector3, spd: float) -> void: heard.append(spd)
	NetworkManager.deflection_received.connect(listener)
	NetworkManager.notify_deflection(Vector3.ZERO, 17.5)
	NetworkManager.deflection_received.disconnect(listener)
	assert_eq(heard, [17.5] as Array[float])

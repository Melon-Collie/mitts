extends GutTest

# The PDV spread (NetworkManager._record_packet_delay) is each packet's delay
# above a slow-rising floor. A delay measured against the synced clock goes
# negative whenever the clock's error exceeds the one-way trip — a LAN or a
# same-machine session — so the floor must be able to sit below zero: a
# "no floor yet" sentinel at a negative value reset it on every such packet and
# the spread read zero however much the link jittered.

var _saved: Array = []


func before_each() -> void:
	_saved = [NetworkManager._pdv_floor, NetworkManager._pdv_mean, NetworkManager._pdv_dev]
	NetworkManager._pdv_floor = INF
	NetworkManager._pdv_mean = 0.0
	NetworkManager._pdv_dev = 0.0


func after_each() -> void:
	NetworkManager._pdv_floor = _saved[0]
	NetworkManager._pdv_mean = _saved[1]
	NetworkManager._pdv_dev = _saved[2]


func _feed(delays: Array[float], rounds: int) -> void:
	for _r: int in rounds:
		for d: float in delays:
			NetworkManager._record_packet_delay(d)


func test_jitter_below_zero_is_measured() -> void:
	_feed([-0.008, 0.012] as Array[float], 40)
	assert_gt(NetworkManager.get_packet_delay_spread_ms(), 5.0,
			"20 ms of jitter around a negative delay must show in the spread")


func test_jitter_below_zero_reads_as_it_does_above() -> void:
	_feed([-0.008, 0.012] as Array[float], 40)
	var below: float = NetworkManager.get_packet_delay_spread_ms()
	before_each()
	_feed([0.042, 0.062] as Array[float], 40)
	assert_almost_eq(below, NetworkManager.get_packet_delay_spread_ms(), 0.01,
			"the spread is a property of the jitter, not of the clock's offset")


func test_an_unset_floor_displays_zero() -> void:
	assert_eq(NetworkManager.get_packet_delay_floor_ms(), 0.0)

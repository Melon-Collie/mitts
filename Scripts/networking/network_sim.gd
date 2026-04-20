extends Node

var enabled: bool = false
var delay_ms: float = 0.0    # one-way delay; set to 50 for ~100 ms RTT simulation
var jitter_ms: float = 0.0   # +/- uniform jitter added per packet
var loss_pct: float = 0.0    # 0–100; unreliable packets only

class PendingPacket:
	var fire_time: float
	var callable: Callable
	var args: Array

var _pending: Array[PendingPacket] = []

func send(c: Callable, args: Array, reliable: bool) -> void:
	if not enabled:
		c.callv(args)
		return
	if not reliable and randf() * 100.0 < loss_pct:
		return
	var jitter := randf_range(-jitter_ms, jitter_ms)
	var d := maxf((delay_ms + jitter) / 1000.0, 0.0)
	if d <= 0.0:
		c.callv(args)
		return
	var p := PendingPacket.new()
	p.fire_time = Time.get_ticks_msec() / 1000.0 + d
	p.callable = c
	p.args = args
	_pending.append(p)

func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var i := 0
	while i < _pending.size():
		if _pending[i].fire_time <= now:
			_pending[i].callable.callv(_pending[i].args)
			_pending.remove_at(i)
		else:
			i += 1

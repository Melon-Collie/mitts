extends "res://tests/instruments/ai/test_nz_entry_drill.gd"

# How steady the carrier's entry read is over the entry drill's runs: every
# quarter second with the puck outside their zone, what the read says the
# carrier's spot is worth entered a second later, against what a fresh read says
# of it a second on (the prediction's error, and its bias), and how far it moves
# across half a metre around him (the local spread). A read whose prediction
# misses by as much as its values are worth hands every re-decision a different
# best option. Reports only.

var _err_sum: float = 0.0
var _bias_sum: float = 0.0
var _n: int = 0
var _spread_sum: float = 0.0
var _ns: int = 0


func _team0_read(duel: Object) -> AIPossessionValue:
	var c: int = duel.carrier()
	if c == -1 or duel.team_map[c] != 0:
		return null
	var r: AIPossessionValue = duel._skater(c).agent._carrier._field._ours
	return r if r._entry_spots.size() == AIPossessionValue.CROSSINGS else null


func _spread(read: AIPossessionValue, pos: Vector3, vel: Vector3) -> Array:
	var lo: float = INF
	var hi: float = -INF
	for d: Vector3 in [Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
		var v: float = read.p_enter(pos + d, 0.0, vel)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return [lo, hi]


func _trace(x: float, v: float, n_def: int) -> void:
	var duel: Object = _setup(x, v, n_def)
	var due: Array = []
	for i: int in int(SECS / Duel.DT):
		duel.step()
		var t: float = (i + 1) * Duel.DT
		var read: AIPossessionValue = _team0_read(duel)
		if read == null:
			continue
		while not due.is_empty() and due[0][0] <= t:
			var p: Array = due.pop_front()
			var actual: float = read.p_enter(p[1], 0.0, p[2])
			_err_sum += absf(p[3] - actual)
			_bias_sum += p[3] - actual
			_n += 1
		if i % 30 == 0:
			var s: Object = duel._skater(duel.carrier())
			if s.pos.z > _line() + 1.0:
				var sp: Array = _spread(read, s.pos, s.vel)
				_spread_sum += sp[1] - sp[0]
				_ns += 1
				due.append([t + 1.0, s.pos, s.vel, read.p_enter(s.pos, 1.0, s.vel)])


func test_entry_read_stability() -> void:
	for n_def: int in [2, 3]:
		for x: float in [0.0, 3.0, 5.0, -6.0, -9.0]:
			for v: float in [1.0, 3.0, 5.0]:
				_trace(x, v, n_def)
	gut.p("  1 s prediction: mean |error| %.3f, bias (pred-actual) %+.3f over %d | local spread (±0.5 m) mean %.3f over %d" % [_err_sum / maxi(_n, 1), _bias_sum / maxi(_n, 1), _n, _spread_sum / maxi(_ns, 1), _ns])
	assert_true(true)

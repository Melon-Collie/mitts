extends GutTest

# The bots' read of what possession of a spot is worth, against the measured
# threat (docs/xt-plan.md, Step 1). tests/unit/ai/data/threat_truth.txt holds,
# per staged state, the next-goal value the real bots and the live keepers
# play out from it (tests/instruments/ai/test_threat_truth.gd). Each state is
# rebuilt here without the jitter (threat_stager.gd) and the model is read on
# it: today, AIPossessionValue.at for the staged attack against the staged
# defence, the carrier's read of the spot.
#
# The truth is signed (their goals count against) and today's model is not, so
# what is held is order, not scale: concordance over the pairs the truth tells
# apart (their means further apart than twice their combined standard error),
# and rank correlation. Mean |model − truth| is reported for the models that
# share the truth's unit. Both ratchets bank when a model improves.

const Stager := preload("res://tests/unit/ai/threat_stager.gd")
const TRUTH_PATH: String = "res://tests/unit/ai/data/threat_truth.txt"
const GOAL := Vector3(0.0, 0.0, -GameRules.GOAL_LINE_Z)

# The ratchets. Tighten when a model wins by more than BANK_MARGIN.
const MIN_CONCORDANCE: float = 0.62
const MIN_RANK_CORRELATION: float = 0.27
const BANK_MARGIN: float = 0.02


class Row:
	var team_size: int
	var context: String
	var x: float
	var out: float
	var mean: float
	var se: float


func _rows() -> Array[Row]:
	var rows: Array[Row] = []
	var f := FileAccess.open(TRUTH_PATH, FileAccess.READ)
	assert_not_null(f, "the truth table exists: %s" % TRUTH_PATH)
	if f == null:
		return rows
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var t: PackedStringArray = line.split("\t")
		var r := Row.new()
		r.team_size = int(t[0])
		r.context = t[1]
		r.x = float(t[2])
		r.out = float(t[3])
		r.mean = float(t[5])
		r.se = float(t[6])
		rows.append(r)
	return rows


# Today's model on the row's state: our possession of the carrier's spot
# against the staged defence.
func _today(r: Row) -> float:
	var staged: Array = Stager.stage(Stager.spot(r.x, r.out), r.context, r.team_size)
	var carrier: Array = staged[0]
	var defenders: Array[Vector3] = []
	var vels: Array[Vector3] = []
	for s: Array in staged:
		if s[1] == 1:
			defenders.append(s[2])
			vels.append(s[3])
	var poss := AIPossessionValue.new()
	poss.fill(GOAL, defenders, vels, [])
	return poss.at(carrier[2], 0.0, carrier[3])


# Over the pairs the truth tells apart, the share the model orders the same
# way (a model tie counts half).
static func concordance(truth: Array[Row], model: PackedFloat32Array) -> float:
	var agree: float = 0.0
	var pairs: int = 0
	for i: int in truth.size():
		for j: int in range(i + 1, truth.size()):
			var d: float = truth[i].mean - truth[j].mean
			if absf(d) <= 2.0 * sqrt(truth[i].se * truth[i].se + truth[j].se * truth[j].se):
				continue
			pairs += 1
			var m: float = model[i] - model[j]
			if m == 0.0:
				agree += 0.5
			elif signf(m) == signf(d):
				agree += 1.0
	return agree / float(maxi(pairs, 1))


# Spearman's rank correlation, ties at their mean rank.
static func rank_correlation(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var ra: PackedFloat32Array = _ranks(a)
	var rb: PackedFloat32Array = _ranks(b)
	var n: int = a.size()
	var ma: float = 0.0
	var mb: float = 0.0
	for i: int in n:
		ma += ra[i]
		mb += rb[i]
	ma /= n
	mb /= n
	var cov: float = 0.0
	var va: float = 0.0
	var vb: float = 0.0
	for i: int in n:
		cov += (ra[i] - ma) * (rb[i] - mb)
		va += (ra[i] - ma) * (ra[i] - ma)
		vb += (rb[i] - mb) * (rb[i] - mb)
	return cov / sqrt(maxf(va * vb, 1e-12))


static func _ranks(v: PackedFloat32Array) -> PackedFloat32Array:
	var idx: Array[int] = []
	for i: int in v.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return v[a] < v[b])
	var out := PackedFloat32Array()
	out.resize(v.size())
	var i: int = 0
	while i < idx.size():
		var j: int = i
		while j + 1 < idx.size() and v[idx[j + 1]] == v[idx[i]]:
			j += 1
		for k: int in range(i, j + 1):
			out[idx[k]] = 0.5 * float(i + j)
		i = j + 1
	return out


func test_todays_possession_read_against_the_truth() -> void:
	var rows: Array[Row] = _rows()
	if rows.is_empty():
		return
	var model := PackedFloat32Array()
	var truth := PackedFloat32Array()
	var err: float = 0.0
	for r: Row in rows:
		var m: float = _today(r)
		model.append(m)
		truth.append(r.mean)
		err += absf(m - r.mean)
	var conc: float = concordance(rows, model)
	var rho: float = rank_correlation(model, truth)
	gut.p("today's possession read: concordance %.3f, rank correlation %.3f, mean |model − truth| %.3f over %d states"
			% [conc, rho, err / rows.size(), rows.size()])
	assert_gte(conc, MIN_CONCORDANCE, "the read orders states worse than it did")
	assert_gte(rho, MIN_RANK_CORRELATION, "the read ranks states worse than it did")
	assert_false(conc > MIN_CONCORDANCE + BANK_MARGIN,
			"concordance is up to %.3f from %.3f: bank it in MIN_CONCORDANCE" % [conc, MIN_CONCORDANCE])
	assert_false(rho > MIN_RANK_CORRELATION + BANK_MARGIN,
			"rank correlation is up to %.3f from %.3f: bank it in MIN_RANK_CORRELATION"
			% [rho, MIN_RANK_CORRELATION])

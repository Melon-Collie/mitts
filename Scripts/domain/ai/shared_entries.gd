class_name AISharedEntries
extends RefCounted

# One defence's entry worths (AIPossessionValue's follow-ups), keyed on the
# exact ice they were priced against, so every bot on a side that prices the
# same entries against the same defence in one AI batch prices them once.
# `generation` moves when the slot is handed to another defence, so a read that
# holds it can tell. Reads run on the AI worker alone (as AIShotOdds' do).

var goal: Vector3 = Vector3.INF
var defenders: Array[Vector3] = []
var vels: Array[Vector3] = []
var caps: Array = []
var ride: Array[int] = []
var attackers: Array[Vector3] = []
var attacker_vels: Array[Vector3] = []
# The priced values, laid out by the read that claims the slot: < 0 until
# priced.
var worth: Array[float] = []
var generation: int = 0


func matches(g: Vector3, d: Array[Vector3], v: Array[Vector3], c: Array,
		r: Array[int], a: Array[Vector3], av: Array[Vector3]) -> bool:
	return goal == g and defenders == d and vels == v and caps == c \
			and ride == r and attackers == a and attacker_vels == av


# Hands the slot to the defence given, with `size` values to price.
func claim(g: Vector3, d: Array[Vector3], v: Array[Vector3], c: Array,
		r: Array[int], a: Array[Vector3], av: Array[Vector3], size: int) -> void:
	goal = g
	defenders.assign(d)
	vels.assign(v)
	caps.assign(c)
	ride.assign(r)
	attackers.assign(a)
	attacker_vels.assign(av)
	worth.resize(size)
	worth.fill(-1.0)
	generation += 1

extends GutTest

# Whether he gets primed against a carrier of theirs coming at him with the
# puck (KeeperPlayRead): from his spot at the top of the crease, a carrier at
# each distance standing, skating across the slot or driving in, stickhandling
# as hard as each row says, for two seconds. Per case, the share of the time he
# is primed, the longest unbroken look, and how fast the puck crosses his view
# (median and 90th percentile, deg/s) against the pursuit limit that breaks
# the look.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const EYES := Vector2(0.0, -1.2)
const SECONDS: float = 2.0
# How far the puck swings either side of its carrier, and how often.
const DANGLES: Array = [["no dangle", 0.0, 0.0], ["soft 0.3 m 1 Hz", 0.3, 1.0],
		["dangle 0.5 m 1.5 Hz", 0.5, 1.5], ["hard 0.6 m 2.5 Hz", 0.6, 2.5]]
const MOVES: Array = [["still", Vector2.ZERO], ["across 4 m/s", Vector2(4.0, 0.0)],
		["driving in 5 m/s", Vector2(0.0, 5.0)]]


func test_report() -> void:
	var lines: PackedStringArray = ["out  carrier            stickhandle          | primed  longest | crossing deg/s p50  p90 (limit %.0f)"
			% rad_to_deg(KeeperPlayRead.PURSUIT_RAD_S)]
	for out: float in [6.0, 9.0, 12.0]:
		for move: Array in MOVES:
			for dangle: Array in DANGLES:
				lines.append(_case(out, move, dangle))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _case(out: float, move: Array, dangle: Array) -> String:
	var play := KeeperPlayRead.new()
	play.eyes = EYES
	var v: Vector2 = move[1]
	var body := Vector2(-v.x * SECONDS * 0.5, -out - v.y * SECONDS * 0.5)
	var amp: float = dangle[1]
	var hz: float = dangle[2]
	var primed: int = 0
	var longest: float = 0.0
	var rates: PackedFloat32Array = []
	var was := Vector2.INF
	var ticks: int = int(SECONDS / DT)
	for i: int in ticks:
		var t: float = i * DT
		body += v * DT
		var across := Vector2(-body.y, body.x).normalized()
		var puck: Vector2 = body + across * amp * sin(TAU * hz * t) + Vector2(0.0, 0.3)
		play.step(DT, puck, v, false, body, true)
		if play.primed():
			primed += 1
		longest = maxf(longest, play.watched_s)
		if was != Vector2.INF:
			rates.append(rad_to_deg(absf((was - EYES).angle_to(puck - EYES))) / DT)
		was = puck
	rates.sort()
	return "%4.0f  %-18s %-20s | %5.0f%%  %5.2f s | %22.0f %4.0f" % [out, move[0], dangle[0],
			100.0 * primed / ticks, longest, rates[rates.size() / 2], rates[int(rates.size() * 0.9)]]

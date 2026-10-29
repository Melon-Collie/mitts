extends GutTest

# How fast he gets across his line from the low ready, by each way he has:
# skated there on his feet (the glide, as the brain asks for a spot on his
# feet), and the butterfly slide from his feet. Per distance, the time his
# centre is half way and all the way there, and how far he has got at fixed
# times after the call.

const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const DISTANCES: Array[float] = [0.3, 0.5, 0.8, 1.2]
const AT_S: Array[float] = [0.1, 0.2, 0.3, 0.4, 0.5]


func test_report() -> void:
	var lines: PackedStringArray = ["way        dist | half   there |" + "".join(AT_S.map(
			func(t: float) -> String: return "  @%.1fs" % t))]
	for d: float in DISTANCES:
		for way: String in ["glide", "slide"]:
			lines.append(_race(way, d))
	gut.p("\n" + "\n".join(lines))
	assert_true(true)


func _race(way: String, d: float) -> String:
	var motor := KeeperMotor.new()
	motor.z = -1.0
	motor.low_ready.asked = true
	for _i: int in 60:
		motor.step(DT)
	var spot := Vector2(d, -1.0)
	if way == "glide":
		motor.go_to(spot, 0.0, KeeperRoute.Rest.FEET)
	else:
		motor.slide_from_feet(spot)
	var half: float = INF
	var there: float = INF
	var at: PackedStringArray = []
	var t: float = 0.0
	var next: int = 0
	while t < 1.5:
		motor.step(DT)
		t += DT
		if motor.x >= d * 0.5 and half == INF:
			half = t
		if motor.x >= d - 0.02 and there == INF:
			there = t
		if next < AT_S.size() and t >= AT_S[next] - 1e-6:
			at.append("  %5.2f" % motor.x)
			next += 1
	return "%-6s     %.1f | %.3f  %.3f |%s" % [way, d, half, there, "".join(at)]

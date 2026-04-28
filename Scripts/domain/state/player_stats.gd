class_name PlayerStats

var goals: int = 0
var assists: int = 0
var shots_on_goal: int = 0
var hits: int = 0
var shots_blocked: int = 0
var toi_seconds: float = 0.0

func to_array() -> Array:
	return [goals, assists, shots_on_goal, hits, shots_blocked]

static func from_array(a: Array) -> PlayerStats:
	var s := PlayerStats.new()
	s.goals = a[0]
	s.assists = a[1]
	s.shots_on_goal = a[2]
	s.hits = a[3]
	s.shots_blocked = a[4] if a.size() > 4 else 0
	return s

func to_dict() -> Dictionary:
	return {
		"goals": goals,
		"assists": assists,
		"shots_on_goal": shots_on_goal,
		"hits": hits,
		"shots_blocked": shots_blocked,
		"toi_seconds": int(toi_seconds),
	}

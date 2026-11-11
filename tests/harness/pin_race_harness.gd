class_name PinRaceHarness
extends RefCounted

# Two real SkaterControllers and a real BoardPinTracker against the +x side
# boards, ticked by hand in Skater._physics_process order (movement, integrate,
# skater contact, rink clamp, then the host's pin tracker). The victim faces the
# boards; the pinner comes in square from the ice side holding the stick button.
# Positions and along-wall offsets are in metres along z.

const SKATER_SCENE: PackedScene = preload("res://Scenes/Skater.tscn")
const PUCK_SCENE: PackedScene = preload("res://Scenes/Puck.tscn")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const Role = BoardPinRules.Role
# The pinner holds still along the wall inside this read of the offset.
const PINNER_DEADBAND_M: float = 0.02


class HostStub:
	extends Node

	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false


class Race:
	var ended: String = "held"   # "escaped", "parted", "cap", "held"
	var at_s: float = INF        # seconds after the reversal (or after the lock, no juke)
	var peak_offset_m: float = 0.0


var victim: SkaterController = null
var pinner: SkaterController = null
var pins: BoardPinTracker = null
var _test: GutTest = null
var _now: float = 100.0


func _init(test: GutTest) -> void:
	_test = test


# `*_lbs` 0 keeps the controller's authored (neutral) build.
func setup(victim_lbs: int, pinner_lbs: int) -> void:
	victim = _make(victim_lbs)
	pinner = _make(pinner_lbs)
	var both: Array = [pinner.skater, victim.skater]
	victim.skater.set_skater_collision_provider(func() -> Array: return both)
	pinner.skater.set_skater_collision_provider(func() -> Array: return both)
	var reg := PlayerRegistry.new()
	reg._skaters_cache = [pinner.skater, victim.skater] as Array[Skater]
	reg.team_id_by_skater = {pinner.skater: 1, victim.skater: 0}
	pins = BoardPinTracker.new()
	pins.setup(reg, func() -> float: return _now, func(_v: Skater, _p: Skater) -> void: pass)
	victim.skater.global_position = Vector3(GameRules.INNER_HALF_WIDTH
			- victim.skater.collision_radius(), GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)


func _make(lbs: int) -> SkaterController:
	var skater: Skater = SKATER_SCENE.instantiate() as Skater
	_test.add_child_autofree(skater)
	skater.set_physics_process(false)
	skater.set_process(false)
	var puck: Puck = PUCK_SCENE.instantiate() as Puck
	_test.add_child_autofree(puck)
	puck.set_physics_process(false)
	puck.global_position = Vector3(20.0, 0.0, 20.0)
	var host := HostStub.new()
	_test.add_child_autofree(host)
	var c := SkaterController.new()
	_test.add_child_autofree(c)
	c.setup(skater, puck, host)
	if lbs > 0:
		c.apply_attributes(PlayerAttributes.new(PlayerAttributes.HEIGHT_MEDIUM, lbs))
	skater.is_host_machine = true
	skater.current_shot_state = SkaterStateMachine.State.SKATING_WITHOUT_PUCK
	skater.rotation.y = -PI / 2.0   # facing +x, the boards
	return c


func tick(victim_in: InputState, pinner_in: InputState) -> void:
	# What _process_input stamps and the pin's drive test reads.
	victim.skater.move_intent = victim_in.move_vector
	pinner.skater.move_intent = pinner_in.move_vector
	victim._advance_stick_check(victim_in, DT)
	pinner._advance_stick_check(pinner_in, DT)
	victim._apply_movement(victim_in, DT)
	pinner._apply_movement(pinner_in, DT)
	for s: Skater in [victim.skater, pinner.skater]:
		s.global_position += s.velocity * DT
		s._resolve_player_collisions()
		s.clamp_body_to_rink()
	_now += DT
	pins.tick(true)


# The pinner comes in square from just off the victim at `closing` m/s, stick
# button held from the first tick. Returns "pinned", "knockdown" or "none" once
# the lock or the knockdown lands, or after half a second.
func approach(closing: float, victim_in: InputState, pinner_in: InputState) -> String:
	var rv: float = victim.skater.collision_radius()
	var rp: float = pinner.skater.collision_radius()
	pinner.skater.global_position = Vector3(victim.skater.global_position.x - rv - rp - 0.05,
			GameRules.FACEOFF_SPAWN_HEIGHT, 0.0)
	pinner.skater.velocity = Vector3(closing, 0.0, 0.0)
	pinner_in.move_vector = Vector2(1.0, 0.0)
	pinner_in.stick_check_held = true
	for i: int in 60:
		pinner_in.stick_check_pressed = i == 0
		tick(victim_in, pinner_in)
		if victim.knockdown_timer > 0.0:
			return "knockdown"
		if victim.skater.pin_role == Role.PINNED:
			return "pinned"
	return "none"


# Lock a pin at walking pace, then the victim slides +z and, at `juke_at_s`
# (INF for none), reverses. The pinner drives into the wall with weight `drive`
# against full along-wall input toward where he read the victim `lag_s` ago.
func race(lag_s: float, juke_at_s: float, drive: float = 0.7) -> Race:
	var r := Race.new()
	var vi := InputState.new()
	var pi := InputState.new()
	if approach(1.2, vi, pi) != "pinned":
		r.ended = "no pin"
		return r
	var seen: Array[float] = []
	var lag_ticks: int = int(round(lag_s / DT))
	var t: float = 0.0
	var start: float = 0.0 if juke_at_s == INF else juke_at_s
	while t < BoardPinRules.PIN_MAX_S + 1.0:
		vi.move_vector = Vector2(0.0, -1.0 if t >= juke_at_s else 1.0)
		seen.append(victim.skater.global_position.z)
		var off: float = seen[maxi(seen.size() - 1 - lag_ticks, 0)] \
				- pinner.skater.global_position.z
		var along: float = 0.0 if absf(off) < PINNER_DEADBAND_M else signf(off)
		pi.stick_check_pressed = false
		pi.move_vector = Vector2(drive, along).normalized()
		tick(vi, pi)
		t += DT
		var live: float = victim.skater.global_position.z - pinner.skater.global_position.z
		if t >= start:
			r.peak_offset_m = maxf(r.peak_offset_m, absf(live))
		if victim.skater.pin_role != Role.PINNED:
			r.at_s = t - start
			if BoardPinRules.escaped(live):
				r.ended = "escaped"
			elif t >= BoardPinRules.PIN_MAX_S - DT:
				r.ended = "cap"
			else:
				r.ended = "parted"
			return r
	return r

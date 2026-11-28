extends GutTest

# INSTRUMENT: how fights go. Two real SkaterControllers squared up, each fought
# by a policy (the bots' AIFightBrain, or a scripted cursor standing in for a
# human's), the host's FightPunchJudge between them and what a landed punch does
# laid on as GameManager lays it. Prints, per pairing: how many punches were
# thrown, what each met (head, body, an arm in his guard, nothing) and how fast,
# the rattle reached, and how the fight ended. Asserts nothing.

const DT: float = 1.0 / 90.0
const Hit = FightPunchRules.Hit
const FIGHTS: int = 4


class StubGameState extends Node:
	func is_host() -> bool:
		return true

	func is_movement_locked() -> bool:
		return false

	func allows_blade_aim_during_lock() -> bool:
		return false

	func is_in_goal_celebration() -> bool:
		return false


# What a fighter's cursor does. BOT is AIFightBrain; the others throw on a
# cadence at a point named off the other man's head.
enum Aim { BOT, ON_HEAD, THROUGH_HEAD, HOOK }


class Policy:
	var aim: int = Aim.BOT
	var profile: BotSkillProfile = null
	var gap_s: float = 0.8        # scripted: between throws
	var throw_s: float = 0.25     # scripted: the cursor out this long
	var wind_s: float = 0.1       # scripted hook: the cursor out to the side this long first
	var closes: bool = true       # scripted: skates in as the bots do
	var swaps_after_s: float = -1.0  # scripted: swaps hands this long into a tie; < 0 never
	var side_m: float = 0.0       # scripted: the cursor off his head, across
	var grab: bool = true
	var label: String = ""


class Fighter:
	var skater: Skater
	var controller: SkaterController
	var input := InputState.new()
	var policy: Policy
	var brain := AIFightBrain.new()
	var view := AIFightBrain.View.new()
	var until_next_s: float = 0.0
	var throw_left_s: float = 0.0
	var last_fist := Vector3.ZERO
	# Tallies.
	var throws: int = 0
	var landed := [0, 0, 0, 0]          # by Hit
	var slow := [0, 0, 0, 0]            # met, under MIN_LAND_M_S, by Hit
	var head_speed: float = 0.0
	var peak_rattle: float = 0.0
	var throw_met: int = Hit.NONE       # this throw's first contact
	var tied_s: float = 0.0
	var tied_ticks: int = 0
	var bare_met: bool = false          # this throw has met his head or chest, arms aside
	var bare := [0, 0, 0, 0]            # throws by what they meet with no arm in the way
	var bare_head_speed: float = 0.0
	var throw_open: bool = false


var _puck: Puck = null
var _state: StubGameState = null
var _now: float = 0.0
var _contact := FightPunchJudge.Contact.new()


func before_each() -> void:
	_puck = load("res://Scenes/Puck.tscn").instantiate() as Puck
	add_child_autofree(_puck)
	_puck.global_position = Vector3(20.0, 0.0, 20.0)
	_state = StubGameState.new()
	add_child_autofree(_state)


func _spawn(at: Vector3, team: int, facing: Vector2, policy: Policy, phase: float) -> Fighter:
	var attrs := PlayerAttributes.new(73, 201, 1, 1, 1, 1)
	var f := Fighter.new()
	f.skater = load("res://Scenes/Skater.tscn").instantiate() as Skater
	add_child_autofree(f.skater)
	f.skater.global_position = at
	f.skater.set_process(false)
	f.skater.set_physics_process(false)
	f.skater.apply_appearance(attrs)
	f.skater.set_team_id_resolver(func() -> int: return team)
	f.controller = SkaterController.new()
	add_child_autofree(f.controller)
	f.controller.setup(f.skater, _puck, _state)
	f.controller.apply_attributes(attrs)
	f.controller._pose.facing = facing
	f.skater.set_facing(facing)
	f.policy = policy
	f.brain.setup(policy.profile, phase)
	f.until_next_s = fposmod(phase, policy.gap_s)
	f.input.delta = DT
	f.input.brake = true
	return f


func _bot(profile: BotSkillProfile, label: String) -> Policy:
	var p := Policy.new()
	p.aim = Aim.BOT
	p.profile = profile
	p.label = label
	return p


func _scripted(aim: int, side_m: float, label: String, grab: bool = true) -> Policy:
	var p := Policy.new()
	p.aim = aim
	p.side_m = side_m
	p.label = label
	p.grab = grab
	return p


# A fighter's controls this tick, as AIController._fight_tick fills them.
func _drive(f: Fighter, man: Fighter) -> void:
	var s: Skater = f.skater
	var head: Vector3 = FightPunchJudge.head_center(man.skater)
	var facing: Vector2 = s.get_facing()
	f.input.slap_pressed = false
	var to_him := Vector2(man.skater.global_position.x - s.global_position.x,
			man.skater.global_position.z - s.global_position.z)
	var down: bool = s.is_knocked_down or man.skater.is_knocked_down
	if f.policy.aim == Aim.BOT:
		var v: AIFightBrain.View = f.view
		v.me = s.global_position
		v.facing = facing
		v.my_grip = s.fight_grip
		v.reach = SkaterFightHands.arm_reach(s)
		v.man_down = down
		v.him = man.skater.global_position
		v.head = head
		v.his_top_fist = man.skater.upper_body_to_global(SkaterFightHands.fist_local(man.skater, true))
		v.his_bottom_fist = man.skater.upper_body_to_global(SkaterFightHands.fist_local(man.skater, false))
		v.my_arm_held = FightHoldRules.tied(s.fight_punch_side, man.skater.fight_grip)
		v.his_arm_thrown = SkaterFightHands.arm_thrown(man.skater,
				man.skater.fight_punch_side == FightHoldRules.Side.TOP)
		v.his_top_guards = SkaterFightHands.arm_guards(man.skater, true)
		v.his_bottom_guards = SkaterFightHands.arm_guards(man.skater, false)
		f.tied_ticks += 1 if v.my_arm_held else 0
		var was_guard: bool = f.throw_left_s <= 0.0
		var d: AIFightBrain.Decision = f.brain.decide(v, DT)
		var throwing: bool = f.brain.throwing()
		if throwing and was_guard:
			_open_throw(f)
		f.throw_left_s = 1.0 if throwing else 0.0
		f.input.mouse_world_pos = d.aim
		f.input.shoot_held = d.grab
		f.input.slap_pressed = d.swap
		f.input.move_vector = d.move
		f.input.brake = d.brake
		return
	f.input.shoot_held = f.policy.grab and not down
	var tied: bool = FightHoldRules.tied(s.fight_punch_side, man.skater.fight_grip)
	f.tied_s = f.tied_s + DT if tied else 0.0
	f.tied_ticks += 1 if tied else 0
	if f.policy.swaps_after_s >= 0.0 and f.tied_s >= f.policy.swaps_after_s:
		f.input.slap_pressed = true
		f.tied_s = 0.0
	var dist: float = to_him.length()
	var stand: float = SkaterFightHands.arm_reach(s) + AIFightBrain.STAND_PAST_REACH_M
	f.input.move_vector = to_him / dist if f.policy.closes and dist > stand and not down \
			else Vector2.ZERO
	f.input.brake = f.input.move_vector == Vector2.ZERO
	var rest: Vector3 = s.global_position + Vector3(facing.x, 0.0, facing.y) * AIFightBrain.GUARD_AHEAD_M
	f.input.mouse_world_pos = rest
	if down:
		return
	var whole: float = f.policy.throw_s + (f.policy.wind_s if f.policy.aim == Aim.HOOK else 0.0)
	if f.throw_left_s > 0.0:
		f.throw_left_s -= DT
	else:
		f.until_next_s -= DT
		if f.until_next_s <= 0.0:
			f.throw_left_s = whole
			f.until_next_s = f.policy.gap_s
			_open_throw(f)
	if f.throw_left_s > 0.0:
		var to := Vector3(head.x - s.global_position.x, 0.0, head.z - s.global_position.z).normalized()
		var across := Vector3(-to.z, 0.0, to.x)
		var flat_head := Vector3(head.x, 0.0, head.z)
		match f.policy.aim:
			Aim.ON_HEAD:
				f.input.mouse_world_pos = flat_head + across * f.policy.side_m
			Aim.THROUGH_HEAD:
				f.input.mouse_world_pos = flat_head + to * AIFightBrain.THROUGH_M \
						+ across * f.policy.side_m
			Aim.HOOK:
				# Out to the side beside his head, then across through it.
				var side: float = signf(f.policy.side_m) if f.policy.side_m != 0.0 else 1.0
				if f.throw_left_s > f.policy.throw_s:
					f.input.mouse_world_pos = flat_head + across * side * absf(f.policy.side_m)
				else:
					f.input.mouse_world_pos = flat_head - across * side * 0.3


func _open_throw(f: Fighter) -> void:
	f.throws += 1
	f.throw_met = Hit.NONE
	f.bare_met = false
	f.throw_open = true


# What the fist's sweep met first this throw, whatever its speed: the judge's
# own contact, read without its speed gate and cooldown, and what it would have
# met with no arm in the way.
func _note_contact(f: Fighter, man: Fighter) -> void:
	var fist: Vector3 = FightPunchJudge.punching_fist(f.skater)
	var from: Vector3 = f.last_fist
	f.last_fist = fist
	if not f.throw_open:
		return
	var victim: Skater = man.skater
	if not f.bare_met:
		var head: Vector3 = FightPunchJudge.head_center(victim)
		var th: float = FightPunchRules.sweep_sphere(from, fist, head,
				FightPunchRules.HEAD_RADIUS_M + FightPunchRules.FIST_RADIUS_M)
		var tb: float = FightPunchRules.sweep_sphere(from, fist, FightPunchJudge.chest_center(victim),
				FightPunchRules.BODY_RADIUS_M + FightPunchRules.FIST_RADIUS_M)
		if th >= 0.0 or tb >= 0.0:
			f.bare_met = true
			var is_head: bool = th >= 0.0 and (tb < 0.0 or th <= tb)
			f.bare[Hit.HEAD if is_head else Hit.BODY] += 1
			if is_head:
				f.bare_head_speed += FightPunchRules.closing_speed((fist - from) / DT,
						victim.velocity, (head - from).normalized())
	if f.throw_met != Hit.NONE:
		return
	FightPunchJudge.contact(from, fist, victim, _contact)
	if _contact.hit == Hit.NONE:
		return
	f.throw_met = _contact.hit
	var speed: float = FightPunchRules.closing_speed((fist - from) / DT, victim.velocity,
			(_contact.center - from).normalized())
	if not FightPunchRules.lands(speed):
		f.slow[_contact.hit] += 1


# One fight, to a man down or the linesmen. Returns how it ended.
func _fight(pa: Policy, pb: Policy, gap: float, seed_i: int) -> Dictionary:
	var a: Fighter = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0), 0,
			Vector2(0.0, -1.0), pa, 0.37 * float(seed_i + 1))
	var b: Fighter = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, -gap), 1,
			Vector2(0.0, 1.0), pb, 0.37 * float(seed_i + 2) + 0.21)
	var both: Array = [a.skater, b.skater]
	for f: Fighter in [a, b]:
		f.skater.set_skater_collision_provider(func() -> Array: return both)
		f.skater.fight_role = FightRules.Role.FIGHTING
		f.last_fist = FightPunchJudge.punching_fist(f.skater)
	_now = 0.0
	var judge := FightPunchJudge.new()
	judge.setup(func(s: Skater) -> Skater: return b.skater if s == a.skater else a.skater,
			func() -> float: return _now)
	judge.punch_landed.connect(func(at: Skater, v: Skater, hit: int, speed: float,
			toward: Vector3) -> void:
		var hitter: Fighter = a if at == a.skater else b
		var victim: Fighter = b if at == a.skater else a
		hitter.landed[hit] += 1
		if hit == Hit.HEAD:
			hitter.head_speed += speed
		var flat := Vector3(toward.x, 0.0, toward.z).normalized()
		victim.controller.absorb_punch(flat * FightPunchRules.impulse_dv(speed,
				v.weight * FightPunchRules.NEUTRAL_MASS_KG), hit, speed)
		victim.peak_rattle = maxf(victim.peak_rattle, v.fight_rattle))
	var fighters: Array[Skater] = [a.skater, b.skater]
	var end: String = "linesmen"
	var ended_at: float = FightRules.FIGHT_MAX_S
	var dist_sum: float = 0.0
	var ticks: int = 0
	while _now < FightRules.FIGHT_MAX_S:
		_drive(a, b)
		_drive(b, a)
		a.controller._process_input(a.input, DT)
		b.controller._process_input(b.input, DT)
		a.skater._physics_process(DT)
		b.skater._physics_process(DT)
		_note_contact(a, b)
		_note_contact(b, a)
		judge.tick(fighters, DT)
		_now += DT
		ticks += 1
		dist_sum += a.skater.global_position.distance_to(b.skater.global_position)
		if a.controller.knockdown_timer > 0.0 or b.controller.knockdown_timer > 0.0:
			end = "a down" if a.controller.knockdown_timer > 0.0 else "b down"
			ended_at = _now
			break
	var out := {"end": end, "at": ended_at, "a": a, "b": b,
			"dist": dist_sum / maxf(float(ticks), 1.0)}
	for f: Fighter in [a, b]:
		f.skater.queue_free()
		f.controller.queue_free()
	return out


func _run(pa: Policy, pb: Policy, gap: float) -> void:
	var ends := {"linesmen": 0, "a down": 0, "b down": 0}
	var time_sum: float = 0.0
	var dist: float = 0.0
	var rows: Array[String] = []
	var both: Array[Dictionary] = [{}, {}]
	for side: int in 2:
		both[side] = {"throws": 0, "landed": [0, 0, 0, 0], "slow": 0, "speed": 0.0, "peak": 0.0,
				"bare": 0, "bare_speed": 0.0, "tied": 0, "ticks": 0}
	for i: int in FIGHTS:
		var r: Dictionary = _fight(pa, pb, gap, i)
		ends[r["end"]] += 1
		time_sum += float(r["at"])
		dist += float(r["dist"])
		for side: int in 2:
			var f: Fighter = r["a"] if side == 0 else r["b"]
			var man: Fighter = r["b"] if side == 0 else r["a"]
			var t: Dictionary = both[side]
			t["throws"] += f.throws
			for h: int in 4:
				t["landed"][h] += f.landed[h]
				t["slow"] += f.slow[h]
			t["speed"] += f.head_speed
			t["peak"] = maxf(float(t["peak"]), man.peak_rattle)
			t["bare"] += f.bare[Hit.HEAD]
			t["bare_speed"] += f.bare_head_speed
			t["tied"] += f.tied_ticks
			t["ticks"] += roundi(float(r["at"]) / DT)
		await get_tree().process_frame
	for side: int in 2:
		var t: Dictionary = both[side]
		var landed: Array = t["landed"]
		rows.append("%-20s thrown %3d: head %3d (%.1f m/s) body %2d blocked %3d too-slow %3d | arms aside head %3d (%.1f m/s) | his peak rattle %.2f | tied %.0f%%" % [
				(pa if side == 0 else pb).label, t["throws"], landed[Hit.HEAD],
				float(t["speed"]) / maxf(float(landed[Hit.HEAD]), 1.0), landed[Hit.BODY],
				landed[Hit.BLOCKED], t["slow"], t["bare"],
				float(t["bare_speed"]) / maxf(float(t["bare"]), 1.0), t["peak"],
				100.0 * float(t["tied"]) / maxf(float(t["ticks"]), 1.0)])
	gut.p("gap %.2f (held %.2f) | %d fights: first down %d, second down %d, linesmen %d, mean %.1f s" % [
			gap, dist / float(FIGHTS), FIGHTS, ends["a down"], ends["b down"], ends["linesmen"],
			time_sum / float(FIGHTS)])
	gut.p("   " + rows[0])
	gut.p("   " + rows[1])


func test_bots_against_bots() -> void:
	for gap: float in [0.8, 0.9, 1.2, 2.5]:
		await _run(_bot(BotSkillProfile.easy(), "bot easy"), _bot(BotSkillProfile.easy(), "bot easy"), gap)
		await _run(_bot(BotSkillProfile.normal(), "bot normal"), _bot(BotSkillProfile.normal(), "bot normal"), gap)
		await _run(_bot(BotSkillProfile.hard(), "bot hard"), _bot(BotSkillProfile.hard(), "bot hard"), gap)
	await _run(_bot(BotSkillProfile.hard(), "bot hard"), _bot(BotSkillProfile.easy(), "bot easy"), 1.2)
	assert_true(true)


func test_a_scripted_cursor_against_a_bot() -> void:
	for tier: String in ["easy", "normal", "hard"]:
		var profile: BotSkillProfile = BotSkillProfile.easy() if tier == "easy" \
				else BotSkillProfile.normal() if tier == "normal" else BotSkillProfile.hard()
		var bot: Policy = _bot(profile, "bot " + tier)
		for swaps: float in [-1.0, 0.3]:
			var tag: String = "" if swaps < 0.0 else ", swaps"
			var on: Policy = _scripted(Aim.ON_HEAD, 0.0, "on head" + tag)
			var through: Policy = _scripted(Aim.THROUGH_HEAD, 0.0, "through head" + tag)
			var hook: Policy = _scripted(Aim.HOOK, -0.3, "hook -0.3" + tag)
			var hook_other: Policy = _scripted(Aim.HOOK, 0.3, "hook +0.3" + tag)
			for p: Policy in [on, through, hook, hook_other]:
				p.swaps_after_s = swaps
				await _run(p, bot, 1.2)
	assert_true(true)


func test_a_scripted_cursor_against_a_man_who_only_guards() -> void:
	var idle: Policy = _scripted(Aim.ON_HEAD, 0.0, "idle guard", false)
	idle.gap_s = 1000.0
	idle.closes = false
	for gap: float in [0.72, 0.8, 0.88]:
		for aim: int in [Aim.ON_HEAD, Aim.THROUGH_HEAD]:
			for side: float in [0.0, 0.08, -0.08, 0.15, -0.15]:
				var p: Policy = _scripted(aim, side, "%s %+.2f" % ["on" if aim == Aim.ON_HEAD else "through", side], false)
				p.closes = false
				await _run(p, idle, gap)
		for side: float in [0.3, -0.3]:
			var h: Policy = _scripted(Aim.HOOK, side, "hook %+.2f" % side, false)
			h.closes = false
			await _run(h, idle, gap)
	assert_true(true)


func test_the_geometry_of_a_squared_up_pair() -> void:
	var idle: Policy = _scripted(Aim.ON_HEAD, 0.0, "idle", false)
	idle.gap_s = 1000.0
	for gap: float in [0.8, 1.0, 1.2]:
		var a: Fighter = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, 0.0), 0,
				Vector2(0.0, -1.0), idle, 0.0)
		var b: Fighter = _spawn(Vector3(0.0, GameRules.FACEOFF_SPAWN_HEIGHT, -gap), 1,
				Vector2(0.0, 1.0), idle, 0.0)
		var both: Array = [a.skater, b.skater]
		for f: Fighter in [a, b]:
			f.skater.set_skater_collision_provider(func() -> Array: return both)
			f.skater.fight_role = FightRules.Role.FIGHTING
		for i: int in 60:
			_drive(a, b)
			_drive(b, a)
			a.controller._process_input(a.input, DT)
			b.controller._process_input(b.input, DT)
			a.skater._physics_process(DT)
			b.skater._physics_process(DT)
		var sh: Vector3 = a.skater.upper_body_to_global(a.controller._ik.arm_shoulder())
		var bsh: Vector3 = a.skater.upper_body_to_global(a.skater.bottom_shoulder.position)
		var head: Vector3 = FightPunchJudge.head_center(b.skater)
		var chest: Vector3 = FightPunchJudge.chest_center(b.skater)
		var his_top: Vector3 = b.skater.upper_body_to_global(b.skater.get_top_hand_position())
		var his_bot: Vector3 = b.skater.upper_body_to_global(b.skater.get_blade_position())
		gut.p("gap %.2f -> centres %.2f | reach %.2f radius %.2f | my top shoulder %s bottom %s | his head %s chest %s | shoulder->head %.2f (top) %.2f (bottom), ->chest %.2f | his fists top %s bottom %s | my guard fist %s" % [
				gap, a.skater.global_position.distance_to(b.skater.global_position),
				SkaterFightHands.arm_reach(a.skater), a.skater.collision_radius(),
				sh - a.skater.global_position, bsh - a.skater.global_position,
				head - b.skater.global_position, chest - b.skater.global_position,
				sh.distance_to(head), bsh.distance_to(head), sh.distance_to(chest),
				his_top - b.skater.global_position, his_bot - b.skater.global_position,
				FightPunchJudge.punching_fist(a.skater) - a.skater.global_position])
	assert_true(true)

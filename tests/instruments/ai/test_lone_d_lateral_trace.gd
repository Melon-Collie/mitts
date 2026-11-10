extends GutTest

# #916's rush (test_one_on_one_to_the_crease's v9.0/14m/c8/d3) traced tick by
# tick: the carrier down the right wall who cuts across the top of the circles,
# and the lone defender set flat in front of him. Per row, the defender's slot,
# the stand he is given (where it is relative to him, and how fast it moves
# across), the route's bounds (retreat floor, advance cap, turned to skate), the
# heading the moving-frame pursuit asks for from rest, the stick he sends, the
# brake and the stance, and the speed his body actually has across the ice.
# Team 0 attacks -Z; x is across the ice.

const Duel := preload("res://tests/unit/ai/duel_harness.gd")
const DT: float = preload("res://Scripts/game/constants.gd").TICK_DURATION
const CARRIER := 1
const DEFENDER := 2
const START_Z: float = 8.0
const EVERY_TICKS: int = 5


func _trace(carrier_x: float, d_x: float, depth: float, speed: float, secs: float) -> void:
	var duel := Duel.new()
	duel.add_skater(CARRIER, 0, Vector3(carrier_x, 0.0, START_Z), BotSkillProfile.hard(),
			Vector3(0.0, 0.0, -speed))
	duel.add_skater(DEFENDER, 1, Vector3(d_x, 0.0, START_Z - depth), BotSkillProfile.hard())
	duel.start(CARRIER)
	duel._skater(CARRIER).facing = Vector2(0.0, -1.0)
	duel._skater(DEFENDER).facing = Vector2(0.0, 1.0)
	_rows(duel, secs)


# test_one_on_one_to_the_crease's net driver: the carrier scripted straight at
# the net front, ignoring the defender.
func _trace_drive(carrier_x: float, d_x: float, depth: float, speed: float, secs: float) -> void:
	var duel := Duel.new()
	var net_front := Vector3(0.0, 0.0, -(GameRules.GOAL_LINE_Z - CreaseRules.ARC_RADIUS))
	var start := Vector3(carrier_x, 0.0, START_Z)
	duel.add_scripted_attacker(CARRIER, 0, [start, net_front] as Array[Vector3],
			duel.move_cfg.max_speed * duel.move_cfg.puck_carry_speed_multiplier)
	var car: Object = duel._skater(CARRIER)
	car.script_skates = true
	car.script_strippable = true
	duel.add_skater(DEFENDER, 1, Vector3(d_x, 0.0, START_Z - depth), BotSkillProfile.hard())
	duel.start(CARRIER)
	car.vel = (net_front - start).normalized() * speed
	car.facing = Vector2(car.vel.x, car.vel.z).normalized()
	duel._skater(DEFENDER).facing = Vector2(0.0, 1.0)
	_rows(duel, secs)


func _rows(duel: Object, secs: float) -> void:
	gut.p("   t    car(x,z)  car vx vz |   def(x,z)   def vx vz  face | slot     stand-def(dx,dz) stand vx vz | floor cap  turn chk | pursuit(x,z) stick(x,z) brk stn | gap  blade-puck aim hit")
	for t: int in int(secs / DT):
		duel.step()
		if t % EVERY_TICKS != 0:
			continue
		var car: Object = duel._skater(CARRIER)
		var def: Object = duel._skater(DEFENDER)
		var sm: SkaterAgentStateMachine = def.agent
		var d: RoleDecision = sm._cached_role_decision
		var slot: int = duel.brains[1].slot_assignments.get(DEFENDER, AIRoleSlots.Slot.NONE)
		var row: String = "%5.2f %5.1f %5.1f %5.1f %5.1f | %5.1f %5.1f %5.1f %5.1f %5.0f | %-8s" % [
				t * DT, car.pos.x, car.pos.z, car.vel.x, car.vel.z,
				def.pos.x, def.pos.z, def.vel.x, def.vel.z,
				rad_to_deg(atan2(def.facing.x, def.facing.y)), AIRoleSlots.label(slot)]
		if d != null:
			var to_stand: Vector3 = d.target_position - def.pos
			var pursue: Vector2 = AISteering._moving_frame_pursuit(to_stand,
					Vector2(to_stand.x, to_stand.z).length(), d.target_velocity, Vector3.ZERO,
					duel.move_cfg.max_speed, d.retreat_floor_center - def.pos,
					d.retreat_floor_radius_m, d.advance_cap_m_s)
			row += " %5.1f %5.1f    %5.1f %5.1f | %4.1f %4s %4s %4s | %5.2f %5.2f  %5.2f %5.2f  %s   %s" % [
					to_stand.x, to_stand.z, d.target_velocity.x, d.target_velocity.z,
					d.retreat_floor_radius_m,
					"inf" if is_inf(d.advance_cap_m_s) else "%.1f" % d.advance_cap_m_s,
					"y" if d.face_travel else "n", "y" if d.commit_check else "n",
					pursue.x, pursue.y, def.input.move_vector.x, def.input.move_vector.y,
					"B" if def.input.brake else ".", "S" if def.input.stance_held else "."]
		var me: SkaterNetworkState = SkaterNetworkState.new()
		me.position = def.pos
		me.velocity = def.vel
		me.facing = def.facing
		me.blade_contact_world = def.blade
		var snap_now: WorldSnapshot = duel._build_snapshot()
		snap_now.skater_states[DEFENDER] = me
		var aim: Vector3 = sm._carrier_stick_aim(snap_now, def.pos, me, d) if d != null \
				else Vector3.INF
		var rel_aim: String = "   -   " if not aim.is_finite() \
				else "%4.1f %4.1f" % [aim.x - def.pos.x, aim.z - def.pos.z]
		row += " | aim-def %s blade-def %4.1f %4.1f puck-def %4.1f %4.1f" % [rel_aim,
				def.blade.x - def.pos.x, def.blade.z - def.pos.z,
				duel.puck_pos.x - def.pos.x, duel.puck_pos.z - def.pos.z]
		row += " | %.1f  %.2f %s %s" % [car.pos.distance_to(def.pos), def.blade.distance_to(duel.puck_pos),
				"L" if sm._off_puck_lift_live else ("P" if sm._off_puck_stick_live else "."),
				"H" if def.input.hit_held else "."]
		gut.p(row)


func test_trace_916() -> void:
	_trace(8.0, 3.0, 14.0, 9.0, 6.5)
	assert_true(true)


func test_trace_net_driver() -> void:
	_trace_drive(0.0, 0.0, 12.0, 7.5, 5.0)
	assert_true(true)

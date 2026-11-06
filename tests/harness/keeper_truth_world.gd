extends KeeperWorldSource

# The host's world as his keeper read it, tick by tick, recorded off a
# keeper_play_harness play and fed to a KeeperPredictor as its shadow world:
# the skater and the puck before his tick and any release heard then, the puck
# after its own tick and the contacts it heard. Played back as recorded it is
# the TRUTH feed; with `hidden_from` set to a release's tick, the release and
# what follows it are withheld until a snapshot from that tick on has reached
# the client (`known_through`), the shooter and the puck held on his blade as
# they were the tick before (HIDDEN). Also keeps the host's blob on each
# broadcast tick and his save boxes on every tick, for a test to hold the
# predictor against.

const Harness := preload("res://tests/harness/keeper_play_harness.gd")
const DT: float = Harness.DT

enum Ev { RELEASED, TOUCHED_GOALIE, CAUGHT, BOARDS, POST, GOAL_BODY, TOUCHED_LOOSE }


class PuckAt:
	var carried: bool = false
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var pickup_locked: bool = false
	var motion_pinned: bool = false


class Frame:
	var shooter_at := Vector3.ZERO
	var shooter_velocity := Vector3.ZERO
	var shooter_state: int = 0
	var blade := Vector3.ZERO
	var blade_velocity := Vector3.ZERO
	var pre := PuckAt.new()
	var pre_events := PackedInt32Array()
	var post := PuckAt.new()
	var post_events := PackedInt32Array()


var frames: Array[Frame] = []
# Per broadcast tick, the host's blob; per tick, his 22 save boxes after it.
var blobs: Dictionary[int, PackedByteArray] = {}
var boxes: Array[Array] = []
var hidden_from: int = -1
var known_through: int = -1
var stage_calls: int = 0
var _radius: float = 0.0
var _host: Harness = null
var _frame: Frame = null
var _phase: int = 0


func _init(host: Harness) -> void:
	_host = host
	_radius = host.shooter.collision_radius()
	var p: Puck = host.puck
	p.puck_released.connect(func() -> void: _note(Ev.RELEASED))
	p.puck_touched_goalie.connect(func(_g: Goalie) -> void: _note(Ev.TOUCHED_GOALIE))
	p.puck_caught_by_goalie.connect(func(_g: Goalie) -> void: _note(Ev.CAUGHT))
	p.puck_hit_boards.connect(func() -> void: _note(Ev.BOARDS))
	p.puck_touched_post.connect(func() -> void: _note(Ev.POST))
	p.puck_hit_goal_body.connect(func() -> void: _note(Ev.GOAL_BODY))
	p.puck_touched_loose.connect(func(_s: Skater) -> void: _note(Ev.TOUCHED_LOOSE))


# Host tick `t` of `play`, recorded; on a broadcast tick (every 2nd) his blob
# written, snapping him as the online host does.
func record(play: int, t: int) -> void:
	var f := Frame.new()
	frames.append(f)
	_frame = f
	_phase = 1
	_host.drive(play, t)
	var s: Skater = _host.shooter
	f.shooter_at = s.global_position
	f.shooter_velocity = s.velocity
	f.shooter_state = s.current_shot_state
	f.blade = s.get_blade_contact_global()
	f.blade_velocity = s.blade_world_velocity
	_fill(f.pre)
	_phase = 0
	_host.ctrl._physics_process(DT)
	_phase = 2
	_host.puck_tick(func() -> void: _fill(f.post))
	_phase = 0
	if t % 2 == 0:
		var blob := PackedByteArray()
		_host.ctrl.append_wire_state(blob)
		blobs[t] = blob
	var at: Array[Transform3D] = []
	for part: int in KeeperGear.PART_COUNT:
		at.append(_host.goalie._save_boxes[part].global_transform)
	boxes.append(at)


# The farthest any corner of any of `goalie`'s save boxes sits from the host's
# on tick `t`, m.
func box_gap(goalie: Goalie, t: int) -> float:
	var worst: float = 0.0
	for part: int in KeeperGear.PART_COUNT:
		var h: Vector3 = KeeperGear.half_extents(part)
		var xa: Transform3D = boxes[t][part]
		var xb: Transform3D = goalie._save_boxes[part].global_transform
		for i: int in 8:
			var c := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
			worst = maxf(worst, (xa * c).distance_to(xb * c))
	return worst


func skater_count() -> int:
	return 1


func stage(host_t: float, puck: KeeperShadowPuck, skaters: Array[KeeperShadowSkater]) -> void:
	stage_calls += 1
	var k: int = roundi(host_t / DT)
	var hide: bool = _hidden(k)
	var f: Frame = frames[hidden_from - 1] if hide else frames[k]
	var s: KeeperShadowSkater = skaters[0]
	s.global_position = f.shooter_at
	s.velocity = f.shooter_velocity
	s.current_shot_state = f.shooter_state
	s.shadow_team = -1
	s.shadow_blade = f.blade
	s.blade_world_velocity = f.blade_velocity
	s.body_collision_radius = _radius
	_place(puck, f.pre, s)
	if not hide:
		_emit(puck, f.pre_events, null)


func settle(host_t: float, puck: KeeperShadowPuck, goalie: Goalie) -> void:
	var k: int = roundi(host_t / DT)
	if _hidden(k):
		return
	_place(puck, frames[k].post, puck.carrier)
	_emit(puck, frames[k].post_events, goalie)


func _hidden(k: int) -> bool:
	return hidden_from >= 0 and k >= hidden_from and known_through < hidden_from


func _note(e: int) -> void:
	if _phase == 1:
		_frame.pre_events.append(e)
	elif _phase == 2:
		_frame.post_events.append(e)


func _fill(at: PuckAt) -> void:
	var p: Puck = _host.puck
	at.carried = p.get_carrier() != null
	at.position = p.global_position
	at.velocity = p.linear_velocity
	at.pickup_locked = p.pickup_locked
	at.motion_pinned = p.motion_pinned


func _place(puck: KeeperShadowPuck, at: PuckAt, carrier: Skater) -> void:
	puck.carrier = carrier if at.carried else null
	puck.global_position = at.position
	puck.linear_velocity = at.velocity
	puck.pickup_locked = at.pickup_locked
	puck.motion_pinned = at.motion_pinned


func _emit(puck: KeeperShadowPuck, events: PackedInt32Array, goalie: Goalie) -> void:
	for e: int in events:
		match e:
			Ev.RELEASED:
				puck.puck_released.emit()
			Ev.TOUCHED_GOALIE:
				puck.puck_touched_goalie.emit(goalie)
			Ev.CAUGHT:
				puck.puck_caught_by_goalie.emit(goalie)
			Ev.BOARDS:
				puck.puck_hit_boards.emit()
			Ev.POST:
				puck.puck_touched_post.emit()
			Ev.GOAL_BODY:
				puck.puck_hit_goal_body.emit()
			Ev.TOUCHED_LOOSE:
				puck.puck_touched_loose.emit(null)

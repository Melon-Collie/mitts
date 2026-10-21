extends GutTest

# The highlight reels pose the live actors from recorded frames, so the arena
# board has to be told what the game state was at each one, or it shows the
# live state (FINAL after the game) over a goal from the first period. The reel
# reports each recorded frame it steps onto, as the goal cinematic does.
#
# Frames are hand-built packets, as in test_replay_frame_cursor.gd: no skaters,
# no goalies, and a game-state block carrying the clock under test.

const _SEQ_BYTES: int = 2
const _TIME_BYTES: int = 4

var _driver: PostGameReplayDriver
var _fed: Array[Dictionary] = []
var _saved_replay_clock: float = 0.0


func before_each() -> void:
	_saved_replay_clock = NetworkManager._replay_clock
	_fed.clear()
	var puck: Puck = Puck.new()
	add_child_autofree(puck)
	var registry: PlayerRegistry = PlayerRegistry.new()
	_driver = PostGameReplayDriver.new()
	autofree(_driver)
	_driver.setup(WorldStateCodec.new(), registry, puck, [])
	_driver.replay_frame_changed.connect(
			func(gs: Dictionary, _carrier_team: int) -> void: _fed.append(gs))


func after_each() -> void:
	NetworkManager._replay_clock = _saved_replay_clock


func _frame(time_remaining: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(WorldStateCodec.WS_HEADER_SIZE + WorldStateCodec.PUCK_BLOCK_SIZE
			+ 1 + WorldStateCodec.GAME_STATE_BLOCK_SIZE)
	b.encode_u16(0, 1)
	b.encode_u32(_SEQ_BYTES, 0)
	b.encode_u8(_SEQ_BYTES + _TIME_BYTES, 0)  # zero skaters
	var gs: int = WorldStateCodec.WS_HEADER_SIZE + WorldStateCodec.PUCK_BLOCK_SIZE + 1
	b.encode_u8(gs, 1)  # score0
	b.encode_u8(gs + 2, GamePhase.Phase.PLAYING)
	b.encode_u8(gs + 3, 1)  # period
	b.encode_u16(gs + 4, time_remaining)
	return b


# Skips start(), which mounts a camera and grabs the live sim; the clip it
# begins is the same.
func _play(clip: Dictionary) -> void:
	_driver._clips = [clip]
	_driver._active = true
	_driver._begin_clip(0)


func _clip(clocks: Array[int]) -> Dictionary:
	var frames: Array[PackedByteArray] = []
	var timestamps: Array[float] = []
	for i: int in clocks.size():
		frames.append(_frame(clocks[i]))
		timestamps.append(10.0 + i)
	return {
		"frames": frames, "timestamps": timestamps,
		"start_ts": timestamps[0], "end_ts": timestamps[-1],
	}


func test_each_recorded_frame_reaches_the_board_once() -> void:
	_play(_clip([133, 132, 131]))
	assert_eq(_fed.size(), 1, "the clip's first frame is posed as it begins")
	assert_eq(float(_fed[0].time_remaining), 132.0,
			"the frame it is heading to, as the goal cinematic reports")
	_driver._process(0.25)
	assert_eq(_fed.size(), 1, "inside one bracket the board is not re-fed")
	_driver._process(1.0)
	assert_eq(_fed.size(), 2)
	assert_eq(float(_fed[1].time_remaining), 131.0)
	assert_eq(int(_fed[1].score0), 1)
	assert_eq(int(_fed[1].period), 1)


func test_the_held_final_frame_is_not_re_fed() -> void:
	_play(_clip([133, 132]))
	_driver._process(5.0)  # runs off the end onto the held last frame
	var at_end: int = _fed.size()
	_driver._process(0.1)
	_driver._process(0.1)
	assert_eq(_fed.size(), at_end, "holding the last frame changes nothing on the board")

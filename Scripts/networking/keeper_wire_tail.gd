class_name KeeperWireTail
extends RefCounted

# The goalies' whole sim states (KeeperWire blobs) behind the world-state body,
# inside the snapshot's delta (SnapshotDelta), ahead of the carrier-event block.
#
# Layout: each goalie's blob in the codec's goalie order, then each blob's u16
# length in the same order, then a u8 count of goalies last, so a reader finds
# it from the end of the body as it finds the event block from the end of the
# packet. A goalie no keeper plays has an empty blob.

const _LENGTH: int = 2
const _COUNT: int = 1
const _MOST_GOALIES: int = 4

static var _starts := PackedInt32Array()


# Host: every goalie's blob onto the end of `body` (each goalie snapping his own
# state to it: GoalieController.append_wire_state).
static func append(body: PackedByteArray, goalies: Array[GoalieController]) -> void:
	var n: int = mini(goalies.size(), _MOST_GOALIES)
	_starts.resize(n + 1)
	for i: int in n:
		_starts[i] = body.size()
		goalies[i].append_wire_state(body)
	_starts[n] = body.size()
	var o: int = body.size()
	body.resize(o + n * _LENGTH + _COUNT)
	for i: int in n:
		body.encode_u16(o, _starts[i + 1] - _starts[i])
		o += _LENGTH
	body.encode_u8(o, n)


# Client: where the tail lies in a rebuilt snapshot `s` (the body, then the
# carrier-event block), as [start, end); (-1, -1) when it is malformed.
static func bounds(s: PackedByteArray) -> Vector2i:
	var none := Vector2i(-1, -1)
	if s.is_empty():
		return none
	var events: int = s.decode_u8(s.size() - 1)
	if events > SnapshotEventLog.MAX_EVENTS:
		return none
	var end: int = s.size() - 1 - events * SnapshotEventLog.RECORD_SIZE
	if end < _COUNT:
		return none
	var n: int = s.decode_u8(end - _COUNT)
	var lengths: int = end - _COUNT - n * _LENGTH
	if n > _MOST_GOALIES or lengths < 0:
		return none
	var start: int = lengths
	for i: int in n:
		start -= s.decode_u16(lengths + i * _LENGTH)
	return Vector2i(start, end) if start >= 0 else none


# `s` with its tail at `at` (`bounds`) cut out: the world-state body and its
# event block, as the decoders read them.
static func without(s: PackedByteArray, at: Vector2i) -> PackedByteArray:
	var out: PackedByteArray = s.slice(0, at.x)
	out.append_array(s.slice(at.y))
	return out


# Client: each goalie's blob from the tail `tail` (`s.slice(at.x, at.y)`) to
# its controller, captured at `host_ts`.
static func dispatch(tail: PackedByteArray, goalies: Array[GoalieController], host_ts: float) -> void:
	if tail.is_empty():
		return
	var n: int = tail.decode_u8(tail.size() - _COUNT)
	var lengths: int = tail.size() - _COUNT - n * _LENGTH
	var o: int = 0
	for i: int in n:
		var length: int = tail.decode_u16(lengths + i * _LENGTH)
		if i < goalies.size() and length > 0:
			goalies[i].receive_wire_state(tail.slice(o, o + length), host_ts)
		o += length

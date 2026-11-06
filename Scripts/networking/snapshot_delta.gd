class_name SnapshotDelta
extends RefCounted

# Snapshots sent as deltas against the newest one each client has acked (#912).
#
# The raw snapshot is the same for every client; only the baseline differs. The
# host keeps one ring of recent raw snapshots and each peer's ack, and sends a
# peer `raw XOR baseline` — mostly zero bytes — which WirePacking's compressor
# then all but removes (~412 B against ~659 B for a whole 10-skater snapshot,
# measured with a baseline three broadcasts back). A peer with no usable
# baseline — no ack yet, an ack older than the ring, a roster that changed size —
# gets the whole snapshot.
#
# Sequence numbers here are the delta channel's own, connection-scoped like
# SnapshotEventLog's: the codec's ws_sequence restarts every match, and an ack
# from the last match naming this match's snapshot of the same number would
# rebuild garbage.
#
# Packet, before WirePacking: u8 kind, u16 seq, [u16 baseline seq if DELTA],
# then the body (the raw snapshot, or its XOR against the baseline, which is the
# same length), then the carrier-event block as SnapshotEventLog wrote it (its
# u8 count last, which is how the receiver finds where the body ends).

enum Kind { FULL, DELTA }

const RING: int = 64
# An ack this many sequences old is too far back to rely on the receiver still
# holding it: it keeps the same ring, and the slack covers acks in flight.
const MAX_BASELINE_AGE: int = RING / 2
const SEQ_MASK: int = 0xFFFF
const _FULL_HEADER: int = 3
const _DELTA_HEADER: int = 5


# How far `newer` is past `older` in the 16-bit sequence space, or -1 when it is
# not newer (equal, or older across the wrap).
static func seq_ahead(newer: int, older: int) -> int:
	var d: int = (newer - older) & SEQ_MASK
	return d if d > 0 and d < 0x8000 else -1


# The raw bytes as 64-bit words, zero-padded to a whole word, for an XOR eight
# bytes a step.
static func words_of(raw: PackedByteArray) -> PackedInt64Array:
	var padded: PackedByteArray = raw.duplicate()
	padded.resize((raw.size() + 7) & ~7)
	return padded.to_int64_array()


# `a XOR b`, truncated to `size` bytes. Both word arrays are the same length.
static func xor_words(a: PackedInt64Array, b: PackedInt64Array, size: int) -> PackedByteArray:
	var out: PackedInt64Array = a.duplicate()
	for i: int in out.size():
		out[i] = out[i] ^ b[i]
	var bytes: PackedByteArray = out.to_byte_array()
	bytes.resize(size)
	return bytes


static func _event_block_size(packet: PackedByteArray, body_start: int) -> int:
	if packet.size() <= body_start:
		return -1
	var count: int = packet.decode_u8(packet.size() - 1)
	if count > SnapshotEventLog.MAX_EVENTS:
		return -1
	var size: int = 1 + count * SnapshotEventLog.RECORD_SIZE
	return size if packet.size() - size >= body_start else -1


# Host.
class Sender extends RefCounted:
	var _next_seq: int = 0
	var _ring_seq := PackedInt32Array()
	var _ring_raw: Array[PackedByteArray] = []
	var _ring_words: Array[PackedInt64Array] = []
	var _seq: int = -1
	var _words := PackedInt64Array()
	var _raw := PackedByteArray()
	# This broadcast's bodies by baseline seq: peers acked to the same snapshot
	# share one XOR.
	var _bodies: Dictionary = {}

	func _init() -> void:
		reset()

	func reset() -> void:
		_next_seq = 0
		_ring_seq.resize(RING)
		_ring_seq.fill(-1)
		_ring_raw.resize(RING)
		_ring_words.resize(RING)
		_seq = -1
		_bodies.clear()

	# Takes this broadcast's raw snapshot into the ring.
	func begin(raw: PackedByteArray) -> void:
		_seq = _next_seq
		_next_seq = (_next_seq + 1) & SEQ_MASK
		_raw = raw
		_words = SnapshotDelta.words_of(raw)
		var slot: int = _seq % RING
		_ring_seq[slot] = _seq
		_ring_raw[slot] = raw
		_ring_words[slot] = _words
		_bodies.clear()

	# The packet for a peer whose newest acked snapshot is `ack` (-1: none).
	func packet_for(ack: int, event_block: PackedByteArray) -> PackedByteArray:
		var base: int = _baseline(ack)
		var out := PackedByteArray()
		if base < 0:
			out.resize(_FULL_HEADER)
			out.encode_u8(0, Kind.FULL)
			out.encode_u16(1, _seq)
			out.append_array(_raw)
		else:
			if not _bodies.has(ack):
				_bodies[ack] = SnapshotDelta.xor_words(_words, _ring_words[base], _raw.size())
			out.resize(_DELTA_HEADER)
			out.encode_u8(0, Kind.DELTA)
			out.encode_u16(1, _seq)
			out.encode_u16(3, ack)
			out.append_array(_bodies[ack])
		out.append_array(event_block)
		return out

	func _baseline(ack: int) -> int:
		if ack < 0:
			return -1
		var age: int = SnapshotDelta.seq_ahead(_seq, ack)
		if age < 0 or age > MAX_BASELINE_AGE:
			return -1
		var slot: int = ack % RING
		if _ring_seq[slot] != ack or _ring_raw[slot].size() != _raw.size():
			return -1
		return slot


# Client.
class Receiver extends RefCounted:
	var _ring_seq := PackedInt32Array()
	var _ring_raw: Array[PackedByteArray] = []
	var _ring_words: Array[PackedInt64Array] = []
	# The newest snapshot rebuilt, -1 before the first: what the input batch acks.
	var newest_seq: int = -1
	var baseline_misses: int = 0

	func _init() -> void:
		reset()

	func reset() -> void:
		_ring_seq.resize(RING)
		_ring_seq.fill(-1)
		_ring_raw.resize(RING)
		_ring_words.resize(RING)
		newest_seq = -1
		baseline_misses = 0

	# The raw snapshot with its event block, as the decoders read it; empty when
	# the packet is malformed or names a baseline this receiver no longer holds.
	func read(packet: PackedByteArray) -> PackedByteArray:
		if packet.size() < _FULL_HEADER:
			return PackedByteArray()
		var kind: int = packet.decode_u8(0)
		var seq: int = packet.decode_u16(1)
		var body_start: int = _FULL_HEADER if kind == Kind.FULL else _DELTA_HEADER
		if kind != Kind.FULL and kind != Kind.DELTA:
			return PackedByteArray()
		var event_size: int = SnapshotDelta._event_block_size(packet, body_start)
		if event_size < 0:
			return PackedByteArray()
		var body: PackedByteArray = packet.slice(body_start, packet.size() - event_size)
		var raw: PackedByteArray
		if kind == Kind.FULL:
			raw = body
		else:
			var base: int = packet.decode_u16(3)
			var slot: int = base % RING
			if _ring_seq[slot] != base or _ring_raw[slot].size() != body.size():
				baseline_misses += 1
				return PackedByteArray()
			raw = SnapshotDelta.xor_words(SnapshotDelta.words_of(body), _ring_words[slot], body.size())
		var stored: int = seq % RING
		_ring_seq[stored] = seq
		_ring_raw[stored] = raw
		_ring_words[stored] = SnapshotDelta.words_of(raw)
		if newest_seq < 0 or SnapshotDelta.seq_ahead(seq, newest_seq) > 0:
			newest_seq = seq
		var out: PackedByteArray = raw.duplicate()
		out.append_array(packet.slice(packet.size() - event_size))
		return out

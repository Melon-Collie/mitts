class_name WirePacking
extends RefCounted

# Compression at the RPC boundary for the two per-tick streams: the world-state
# snapshot and the input batch. Every reader sees the raw bytes — the sender
# packs after the last write (the snapshot's carrier-event block included) and
# the receiver unpacks before the first read — so the codecs, the header peeks
# and replay recording never meet a packed buffer.
#
# A packed message is a u16 raw size and the compressed body. Measured on a
# 10-skater match (#912): a snapshot 941 → ~656 B under zstd (~20 µs to encode,
# ~2 µs to decode), an input batch 291 → ~119 B under deflate. zstd for the
# snapshot because the host encodes it every broadcast; deflate for the inputs
# because it packs the batch smaller.

const SNAPSHOT_MODE: int = FileAccess.COMPRESSION_ZSTD
const INPUT_MODE: int = FileAccess.COMPRESSION_DEFLATE
# Bounds on the raw size a receiver will inflate to, so a malformed header can't
# ask for an arbitrary allocation: a 10-skater snapshot with a full event block
# is ~1.2 KB; an input batch is at most 3 + 120 × 24 B.
const SNAPSHOT_MAX_RAW: int = 4096
const INPUT_MAX_RAW: int = 3 + 120 * InputState.BYTES_SIZE
const _HEADER: int = 2


static func pack(raw: PackedByteArray, mode: int) -> PackedByteArray:
	var body: PackedByteArray = raw.compress(mode)
	var out := PackedByteArray()
	out.resize(_HEADER)
	out.encode_u16(0, raw.size())
	out.append_array(body)
	return out


# Empty when the message is malformed: a size past `max_raw`, no body, or a body
# that does not inflate to the size it declared.
static func unpack(packed: PackedByteArray, max_raw: int, mode: int) -> PackedByteArray:
	if packed.size() <= _HEADER:
		return PackedByteArray()
	var raw_size: int = packed.decode_u16(0)
	if raw_size == 0 or raw_size > max_raw:
		return PackedByteArray()
	var raw: PackedByteArray = packed.slice(_HEADER).decompress(raw_size, mode)
	if raw.size() != raw_size:
		return PackedByteArray()
	return raw

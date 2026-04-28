class_name ReplayFileReader
extends RefCounted

# Reads a .mreplay file produced by ReplayFileWriter into a flat dict for the
# viewer / GUT tests. Format constants live on ReplayFileWriter; this class
# only knows how to parse them.
#
# Returns:
#   {
#     ok: bool,
#     header: Dictionary,            # JSON object from the file's header
#     frames: Array[Dictionary],     # each {host_ts: float, kind: int, payload: PackedByteArray}
#     footer: Dictionary,            # empty if truncated or footer JSON missing
#     truncated: bool,               # true when END_OF_RECORDS sentinel was missing
#     error: String,                 # populated when ok = false
#   }
static func read(path: String) -> Dictionary:
	var failure := func(msg: String) -> Dictionary:
		return {
			"ok": false,
			"header": {},
			"frames": [],
			"footer": {},
			"truncated": false,
			"error": msg,
		}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure.call("failed to open: %s (err %d)" % [path, FileAccess.get_open_error()])

	var magic: PackedByteArray = file.get_buffer(ReplayFileWriter.MAGIC.size())
	if magic != ReplayFileWriter.MAGIC:
		file.close()
		return failure.call("magic mismatch (not a .mreplay file?)")

	var header_size: int = file.get_32()
	var header_bytes: PackedByteArray = file.get_buffer(header_size)
	if header_bytes.size() != header_size:
		file.close()
		return failure.call("header truncated")
	var header_parsed: Variant = JSON.parse_string(header_bytes.get_string_from_utf8())
	if not header_parsed is Dictionary:
		file.close()
		return failure.call("header JSON parse failed")

	var frames: Array[Dictionary] = []
	var truncated: bool = true
	var file_len: int = file.get_length()
	while file.get_position() + 4 <= file_len:
		var frame_len: int = file.get_32()
		if frame_len == ReplayFileWriter.END_OF_RECORDS:
			truncated = false
			break
		if frame_len < ReplayFileWriter.FRAME_INNER_HEADER_SIZE:
			break  # corrupt or unexpected; treat as EOF
		if file.get_position() + frame_len > file_len:
			break  # partial trailing record (writer crashed)
		var host_ts: float = file.get_float()
		var kind: int = file.get_8()
		var payload_size: int = frame_len - ReplayFileWriter.FRAME_INNER_HEADER_SIZE
		var payload: PackedByteArray
		if payload_size > 0:
			payload = file.get_buffer(payload_size)
		else:
			payload = PackedByteArray()
		frames.append({
			"host_ts": host_ts,
			"kind": kind,
			"payload": payload,
		})

	var footer: Dictionary = {}
	if not truncated and file.get_position() + 4 <= file_len:
		var footer_size: int = file.get_32()
		if footer_size > 0 and file.get_position() + footer_size <= file_len:
			var footer_bytes: PackedByteArray = file.get_buffer(footer_size)
			var footer_parsed: Variant = JSON.parse_string(footer_bytes.get_string_from_utf8())
			if footer_parsed is Dictionary:
				footer = footer_parsed

	file.close()
	return {
		"ok": true,
		"header": header_parsed as Dictionary,
		"frames": frames,
		"footer": footer,
		"truncated": truncated,
		"error": "",
	}


# Reads only the magic + header JSON, skipping the frame stream entirely.
# Used by the main-menu replay browser to populate the list without walking
# 24K frames per file. Returns {ok, header, error} only.
static func read_header_only(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "header": {}, "error": "open failed"}
	var magic: PackedByteArray = file.get_buffer(ReplayFileWriter.MAGIC.size())
	if magic != ReplayFileWriter.MAGIC:
		file.close()
		return {"ok": false, "header": {}, "error": "magic mismatch"}
	var header_size: int = file.get_32()
	var header_bytes: PackedByteArray = file.get_buffer(header_size)
	file.close()
	if header_bytes.size() != header_size:
		return {"ok": false, "header": {}, "error": "header truncated"}
	var parsed: Variant = JSON.parse_string(header_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok": false, "header": {}, "error": "header parse failed"}
	return {"ok": true, "header": parsed as Dictionary, "error": ""}

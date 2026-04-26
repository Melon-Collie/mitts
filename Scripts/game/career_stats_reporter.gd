class_name CareerStatsReporter extends RefCounted

func report(record: PlayerRecord, goals_for: int, goals_against: int, outcome: String) -> void:
	var body: Dictionary = record.stats.to_dict()
	body["uuid"] = PlayerPrefs.player_uuid
	body["player_name"] = record.display_name()
	body["game_version"] = BuildInfo.VERSION
	body["goals_for"] = goals_for
	body["goals_against"] = goals_against
	body["outcome"] = outcome
	_post(SupabaseConfig.URL + "/rest/v1/career_stats", body)


func migrate_to_steam_id(uuid: String, steam_id: int) -> void:
	if PlayerPrefs.steam_id_linked:
		return
	var url: String = "%s/rest/v1/career_stats?uuid=eq.%s&steam_id=is.null" % [SupabaseConfig.URL, uuid]
	_patch(url, {"steam_id": steam_id})
	PlayerPrefs.steam_id_linked = true
	PlayerPrefs.save()


func fetch_totals(callback: Callable) -> void:
	var url: String = "%s/rest/v1/career_totals?uuid=eq.%s" % [
		SupabaseConfig.URL, PlayerPrefs.player_uuid
	]
	_get(url, callback)


func _post(url: String, body: Dictionary) -> void:
	_fire(url, HTTPClient.METHOD_POST, body)


func _patch(url: String, body: Dictionary) -> void:
	_fire(url, HTTPClient.METHOD_PATCH, body)


func _fire(url: String, method: HTTPClient.Method, body: Dictionary) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		if code < 200 or code >= 300:
			push_warning("CareerStatsReporter: HTTP %d on %s" % [code, url])
		req.queue_free()
	)
	var err: Error = req.request(url, _write_headers(), method, JSON.stringify(body))
	if err != OK:
		push_warning("CareerStatsReporter: request failed: %s" % error_string(err))
		req.queue_free()


func _get(url: String, callback: Callable) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
		if code == 200:
			var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
			if parsed is Array and not (parsed as Array).is_empty():
				callback.call((parsed as Array)[0] as Dictionary)
			else:
				callback.call({})
		else:
			push_warning("CareerStatsReporter: GET returned HTTP %d" % code)
			callback.call({})
		req.queue_free()
	)
	var err: Error = req.request(url, _read_headers())
	if err != OK:
		push_warning("CareerStatsReporter: GET failed: %s" % error_string(err))
		req.queue_free()
		callback.call({})


func _write_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + SupabaseConfig.ANON_KEY,
		"Authorization: Bearer " + SupabaseConfig.ANON_KEY,
		"Content-Type: application/json",
		"Prefer: return=minimal",
	])


func _read_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + SupabaseConfig.ANON_KEY,
		"Authorization: Bearer " + SupabaseConfig.ANON_KEY,
	])

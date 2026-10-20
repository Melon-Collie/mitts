class_name LobbyBench
extends RefCounted

# Who sits on the lobby backdrop's benches, and as whom: one PlayerLook per
# fielded slot, humans and bots, in slot order. The host reads a human's build
# and cosmetics from NetworkManager's join-time copy; a client keeps what the
# host's roster relayed, keyed by peer rather than slot because a slot swap
# rebuilds the slot's entry from its lettering alone.

var _peer_looks: Dictionary[int, PlayerLook] = {}


# Client: one roster entry's look (LobbyManager's roster array, cosmetics after
# its first seven fields).
func remember(entry: Array) -> void:
	var look := PlayerLook.new()
	look.cosmetics_from_wire(entry, 7)
	_peer_looks[int(entry[0])] = look


# A seated peer's whole look: the slot entry's lettering on the build and
# cosmetics the host holds for that peer.
func look_for(entry: Dictionary) -> PlayerLook:
	var peer_id: int = entry.peer_id
	var look: PlayerLook = _peer_looks.get(peer_id, PlayerLook.new())
	if NetworkManager.is_host:
		look.attributes = NetworkManager.get_peer_attributes(peer_id)
		look.skin_tone = NetworkManager.get_peer_skin_tone(peer_id)
		look.tape_code = NetworkManager.get_peer_tape_code(peer_id)
		look.gear_style_code = NetworkManager.get_peer_gear_style(peer_id)
	look.player_name = entry.player_name
	look.jersey_number = entry.get("jersey_number", 10)
	look.is_left_handed = entry.is_left_handed
	return look


# [home, away], each an Array of PlayerLook in slot order. Slots beyond the
# live team size aren't fielded, so they don't sit on the bench either.
func benches(lobby_slots: Dictionary, team_size: int) -> Array:
	var seats: Array = [[], []]
	for k: int in lobby_slots:
		if LobbySlotKey.is_spectator(k) or LobbySlotKey.slot(k) >= team_size:
			continue
		seats[LobbySlotKey.team_id(k)].append([LobbySlotKey.slot(k), look_for(lobby_slots[k])])
	var bot_id: int = 0
	for bot_key: int in NetworkManager.pending_bot_slots:
		if not NetworkManager.pending_bot_slots[bot_key]:
			continue
		if LobbySlotKey.is_spectator(bot_key) or LobbySlotKey.slot(bot_key) >= team_size:
			continue
		var slot: int = LobbySlotKey.slot(bot_key)
		seats[LobbySlotKey.team_id(bot_key)].append([slot, PlayerLook.for_bot(
				NetworkManager.pending_bot_identities.get(bot_key, {}), bot_id, slot)])
		bot_id += 1
	var out: Array = [[], []]
	for team_id: int in 2:
		seats[team_id].sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for seat: Array in seats[team_id]:
			out[team_id].append(seat[1])
	return out

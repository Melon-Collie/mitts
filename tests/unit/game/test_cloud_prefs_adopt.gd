extends GutTest

# NetworkManager copies the local identity out of PlayerPrefs in its _ready,
# but PlayerPrefs' Steam Cloud reconcile runs deferred, after every autoload's
# _ready. On a machine with no local prefs file the copy is the defaults, so a
# cloud adopt must reach it or the lobby spawns "Player" while the menus show
# the saved name.

var _saved_prefs: Array = []
var _saved_net: Array = []
var _saved_peer: Array = []


func before_each() -> void:
	_saved_prefs = [PlayerPrefs.player_name, PlayerPrefs.jersey_number, PlayerPrefs.is_left_handed]
	_saved_net = [NetworkManager.local_player_name, NetworkManager.local_jersey_number,
			NetworkManager.local_is_left_handed]
	_saved_peer = [NetworkManager._peer_names.get(1), NetworkManager._peer_numbers.get(1),
			NetworkManager._peer_handedness.get(1)]


func after_each() -> void:
	PlayerPrefs.player_name = _saved_prefs[0]
	PlayerPrefs.jersey_number = _saved_prefs[1]
	PlayerPrefs.is_left_handed = _saved_prefs[2]
	NetworkManager.local_player_name = _saved_net[0]
	NetworkManager.local_jersey_number = _saved_net[1]
	NetworkManager.local_is_left_handed = _saved_net[2]
	_restore_peer(NetworkManager._peer_names, _saved_peer[0])
	_restore_peer(NetworkManager._peer_numbers, _saved_peer[1])
	_restore_peer(NetworkManager._peer_handedness, _saved_peer[2])


func _restore_peer(map: Dictionary, value: Variant) -> void:
	if value == null:
		map.erase(1)
	else:
		map[1] = value


func test_cloud_adopt_reseeds_the_local_identity() -> void:
	NetworkManager.local_player_name = "Player"
	NetworkManager.local_jersey_number = 10
	NetworkManager.local_is_left_handed = true
	PlayerPrefs.player_name = "Cloudy"
	PlayerPrefs.jersey_number = 42
	PlayerPrefs.is_left_handed = false

	PlayerPrefs.cloud_prefs_adopted.emit()

	assert_eq(NetworkManager.local_player_name, "Cloudy")
	assert_eq(NetworkManager.local_jersey_number, 42)
	assert_false(NetworkManager.local_is_left_handed)
	assert_eq(NetworkManager._peer_names.get(1), "Cloudy",
			"start_offline seeds the host's roster entry from _peer_names[1]")

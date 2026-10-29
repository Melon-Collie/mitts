class_name PlayerDraft
extends RefCounted

# Everything the player screen edits, as one value. The screen opens a draft
# from the saved prefs, edits a copy, and compares the two: Apply commits the
# difference, Cancel drops the copy.
#
# Opened from the free-play side menu only, so a commit applies live: each
# changed field goes to PlayerPrefs and through NetworkManager's local_* path
# that GameManager listens on.

var player_name: String = ""
var jersey_number: int = 0
var is_left_handed: bool = true
# PlayerRules.POSITION_NAMES index.
var position: int = 0
var color_slot: int = TeamColorRegistry.DEFAULT_HOME_SLOT
var skin: int = SkinToneRegistry.DEFAULT_INDEX
# The build in canonical order: height in, weight lbs, gear slots 0/1/2.
var height: int = PlayerAttributes.HEIGHT_MEDIUM
var weight: int = int(PlayerAttributes.NEUTRAL_WEIGHT_LBS)
var profile: int = PlayerAttributes.GEAR_BALANCED
var curve: int = PlayerAttributes.GEAR_BALANCED
var flex: int = PlayerAttributes.GEAR_BALANCED
var length: int = PlayerAttributes.GEAR_BALANCED
var tape_code: int = StickTapeConfig.DEFAULT_CODE
# Packed GearStyleConfig: equipment models, face, tuck, and the hair.
var gear_code: int = GearStyleConfig.DEFAULT_CODE


static func from_prefs() -> PlayerDraft:
	var d := PlayerDraft.new()
	d.player_name = PlayerPrefs.player_name
	d.jersey_number = PlayerPrefs.jersey_number
	d.is_left_handed = PlayerPrefs.is_left_handed
	d.position = clampi(PlayerPrefs.preferred_position, 0, PlayerRules.POSITION_NAMES.size() - 1)
	d.color_slot = PlayerPrefs.preferred_color_slot if PlayerPrefs.preferred_color_slot >= 0 \
			else TeamColorRegistry.DEFAULT_HOME_SLOT
	d.skin = SkinToneRegistry.clamp_index(PlayerPrefs.skin_tone)
	var attrs := PlayerAttributes.new(PlayerPrefs.attr_height, PlayerPrefs.attr_weight,
			PlayerPrefs.attr_profile, PlayerPrefs.attr_curve, PlayerPrefs.attr_flex,
			PlayerPrefs.attr_length)
	d.set_attributes(attrs)
	d.tape_code = PlayerPrefs.stick_tape_code
	d.gear_code = GearStyleConfig.from_code(PlayerPrefs.gear_style_code).to_code()
	return d


func copy() -> PlayerDraft:
	var d := PlayerDraft.new()
	d.player_name = player_name
	d.jersey_number = jersey_number
	d.is_left_handed = is_left_handed
	d.position = position
	d.color_slot = color_slot
	d.skin = skin
	d.height = height
	d.weight = weight
	d.profile = profile
	d.curve = curve
	d.flex = flex
	d.length = length
	d.tape_code = tape_code
	d.gear_code = gear_code
	return d


# Coerced, so the draft only ever holds a legal body.
func attributes() -> PlayerAttributes:
	return PlayerAttributes.new(height, weight, profile, curve, flex, length)


func set_attributes(attrs: PlayerAttributes) -> void:
	height = attrs.height
	weight = attrs.weight
	profile = attrs.profile
	curve = attrs.curve
	flex = attrs.flex
	length = attrs.length


# A height move keeps the FRAME, not the pounds: riding frame-t keeps a lean
# build lean (and a neutral one neutral) across the whole range, where raw BMI
# would drift at the short heights the playable-mass floor truncates.
func set_height(inches: int) -> void:
	var frame: float = PlayerAttributes.frame_t_for(height, weight)
	height = PlayerAttributes.coerce_height(inches)
	weight = PlayerAttributes.weight_for_frame_t(height, frame)


func set_weight(lbs: int) -> void:
	weight = PlayerAttributes.coerce_weight(height, lbs)


func gear() -> GearStyleConfig:
	return GearStyleConfig.from_code(gear_code)


# Round-trips through the code so an out-of-range field lands where the wire
# format would put it.
func set_gear(g: GearStyleConfig) -> void:
	gear_code = GearStyleConfig.from_code(g.to_code()).to_code()


func tape() -> StickTapeConfig:
	return StickTapeConfig.from_code(tape_code)


# Round-trips like set_gear.
func set_tape(t: StickTapeConfig) -> void:
	tape_code = StickTapeConfig.from_code(t.to_code()).to_code()


func team_colors() -> Dictionary:
	return TeamColorRegistry.get_colors(maxi(color_slot, 0), 0)


func build_differs(other: PlayerDraft) -> bool:
	return height != other.height or weight != other.weight or profile != other.profile \
			or curve != other.curve or flex != other.flex or length != other.length


func differs(other: PlayerDraft) -> bool:
	return build_differs(other) or player_name != other.player_name \
			or jersey_number != other.jersey_number or is_left_handed != other.is_left_handed \
			or position != other.position or color_slot != other.color_slot \
			or skin != other.skin or tape_code != other.tape_code or gear_code != other.gear_code


# Saves and applies every field that differs from `since`.
func commit(since: PlayerDraft) -> void:
	if player_name != since.player_name:
		PlayerPrefs.player_name = player_name
	if jersey_number != since.jersey_number:
		PlayerPrefs.jersey_number = jersey_number
	if is_left_handed != since.is_left_handed:
		PlayerPrefs.is_left_handed = is_left_handed
	if player_name != since.player_name or jersey_number != since.jersey_number \
			or is_left_handed != since.is_left_handed:
		# GameManager turns local_identity_changed into a live skater update
		# without a respawn.
		NetworkManager.apply_local_identity(player_name, jersey_number, is_left_handed)
	if position != since.position:
		PlayerPrefs.preferred_position = position
		# Peer-map mirror only — the preference is read at the next lobby seat.
		NetworkManager.apply_local_position(position)
	if skin != since.skin:
		PlayerPrefs.skin_tone = skin
		NetworkManager.apply_local_skin(skin)
	if color_slot != since.color_slot:
		# Writes the pref too; GameManager re-tints the home team and re-rolls
		# away if the two now collide.
		NetworkManager.apply_preferred_color(color_slot)
	if build_differs(since):
		var attrs: PlayerAttributes = attributes()
		PlayerPrefs.set_player_attributes(attrs)
		# The next spawn reads the peer map; the live skater re-applies its
		# multipliers through local_attributes_changed.
		NetworkManager.apply_local_attributes(attrs)
	if tape_code != since.tape_code:
		PlayerPrefs.stick_tape_code = tape_code
		NetworkManager.apply_local_tape(tape_code)
	if gear_code != since.gear_code:
		PlayerPrefs.gear_style_code = gear_code
		NetworkManager.apply_local_gear_style(gear_code)
	PlayerPrefs.save()

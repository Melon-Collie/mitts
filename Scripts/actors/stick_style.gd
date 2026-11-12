class_name StickStyle
extends RefCounted

# Turns a stick pattern (StickModelRegistry) and its zone colours into the
# stick's surface materials: shaft paint + bands + wordmark on the flex shader,
# blade weave on the carbon shader. Every consumer (the skater's stick, the
# ghost swap, the display figures' FigureKit) builds through these factories,
# handing in the pattern, a palette index per zone
# (StickModelRegistry.zone_colors) and the team's two colours the team entries
# resolve to.
#
# Shaft: base paint with the MITTS wordmark on both wide faces (mirrored so
# each reads left-to-right), placed in real metres below the butt end so it
# sits under the grip-tape region. Blade: carbon-weave checker
# (blade_carbon.gdshader) — position-keyed, so it survives pattern rebuilds. A
# black blade keeps the shader's own carbon pair; any other colour weaves itself
# a shade darker.

const _FLEX_SHADER: Shader = preload("res://Shaders/stick_flex.gdshader")
const _CARBON_SHADER: Shader = preload("res://Shaders/blade_carbon.gdshader")
const _BRAND_TEX: Texture2D = preload("res://Assets/textures/stick_brand_mitts.png")

const SHAFT_ROUGHNESS: float = 0.4

# Wordmark start sits below the deepest grip-tape reach (0.5 m from the butt
# end), and its length preserves the baked texture's aspect over the 0.05 m
# shaft height: 0.05 × (512 / 132) ≈ 0.194.
const _BRAND_FROM_BUTT_M: float = 0.55
const _BRAND_LEN_M: float = 0.194

# Shader parameter names per band slot, index-aligned with the registry's
# bands() array: color, from_m, to_m, anchor.
const _BAND_PARAMS: Array[Array] = [
	[&"band1_color", &"band1_from_m", &"band1_to_m", &"band1_anchor"],
	[&"band2_color", &"band2_from_m", &"band2_to_m", &"band2_anchor"],
]


# How much darker a painted blade's second weave square is.
const _WEAVE_SHADE: float = 0.12


# The flex-shader shaft material for a pattern and its zone colours. Callers
# layer their own runtime uniforms on top (flex_m, shaft_len_m, the grip wrap)
# — this factory owns only the design.
static func make_shaft_material(pattern: int = StickModelRegistry.PATTERN_SOLID,
		zones: Array[int] = [], primary: Color = Color.WHITE,
		secondary: Color = Color.WHITE) -> ShaderMaterial:
	var colors: Array[int] = _zones_or_defaults(pattern, zones)
	var mat := ShaderMaterial.new()
	mat.shader = _FLEX_SHADER
	mat.set_shader_parameter(&"albedo", shaft_color(pattern, colors, primary, secondary))
	mat.set_shader_parameter(&"roughness", SHAFT_ROUGHNESS)
	mat.set_shader_parameter(&"brand_tex", _BRAND_TEX)
	mat.set_shader_parameter(&"brand_color", TapeColorRegistry.resolve(
			colors[StickModelRegistry.Zone.WORDMARK], primary, secondary))
	mat.set_shader_parameter(&"brand_from_butt_m", _BRAND_FROM_BUTT_M)
	mat.set_shader_parameter(&"brand_len_m", _BRAND_LEN_M)
	var bands: Array = StickModelRegistry.bands(pattern)
	var band_zones: Array[int] = [StickModelRegistry.Zone.BAND1, StickModelRegistry.Zone.BAND2]
	for i: int in mini(bands.size(), _BAND_PARAMS.size()):
		var band: Dictionary = bands[i]
		mat.set_shader_parameter(_BAND_PARAMS[i][0],
				TapeColorRegistry.resolve(colors[band_zones[i]], primary, secondary))
		mat.set_shader_parameter(_BAND_PARAMS[i][1], band["from_m"])
		mat.set_shader_parameter(_BAND_PARAMS[i][2], band["to_m"])
		mat.set_shader_parameter(_BAND_PARAMS[i][3], band["anchor"])
	return mat


static func make_blade_material(pattern: int = StickModelRegistry.PATTERN_SOLID,
		zones: Array[int] = [], primary: Color = Color.WHITE,
		secondary: Color = Color.WHITE) -> ShaderMaterial:
	var colors: Array[int] = _zones_or_defaults(pattern, zones)
	var mat := ShaderMaterial.new()
	mat.shader = _CARBON_SHADER
	if StickModelRegistry.is_wood(pattern):
		mat.set_shader_parameter(&"albedo_a", StickModelRegistry.WOOD_BLADE_WEAVE[0])
		mat.set_shader_parameter(&"albedo_b", StickModelRegistry.WOOD_BLADE_WEAVE[1])
	elif colors[StickModelRegistry.Zone.BLADE] != TapeColorRegistry.BLACK_INDEX:
		var base: Color = blade_color(pattern, colors, primary, secondary)
		mat.set_shader_parameter(&"albedo_a", base)
		mat.set_shader_parameter(&"albedo_b", base.darkened(_WEAVE_SHADE))
	return mat


# The shaft's base colour (the ghost stand-in and the material's albedo).
static func shaft_color(pattern: int, zones: Array[int], primary: Color,
		secondary: Color) -> Color:
	if StickModelRegistry.is_wood(pattern):
		return StickModelRegistry.WOOD_SHAFT
	return TapeColorRegistry.resolve(_zones_or_defaults(pattern, zones)[
			StickModelRegistry.Zone.SHAFT], primary, secondary)


# The blade's matte colour (the ghost stand-in, and a painted blade's weave).
static func blade_color(pattern: int, zones: Array[int], primary: Color,
		secondary: Color) -> Color:
	if StickModelRegistry.is_wood(pattern):
		return StickModelRegistry.WOOD_BLADE_BASE
	return TapeColorRegistry.resolve(_zones_or_defaults(pattern, zones)[
			StickModelRegistry.Zone.BLADE], primary, secondary)


static func _zones_or_defaults(pattern: int, zones: Array[int]) -> Array[int]:
	return zones if zones.size() == StickModelRegistry.ZONE_COUNT \
			else StickModelRegistry.default_zones(pattern)

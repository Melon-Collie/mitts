class_name StickStyle
extends RefCounted

# Turns a player's stick (GearStyleConfig: the StickModelRegistry graphic and
# its three TapeColorRegistry colors) into the stick's surface materials: shaft
# paint + bands + wordmark on the flex shader, blade weave on the carbon
# shader. Every consumer (the skater's stick, the ghost swap, the display
# figures' FigureKit) builds through these factories, handing in the kit the
# colors resolve against. Geometry (pattern, tape) stays with its own systems;
# the catalogue itself — which graphics exist — is the registry's.
#
# Shaft: base paint with the MITTS wordmark on both wide faces (mirrored so
# each reads left-to-right), placed in real metres below the butt end so it
# sits under the grip-tape region. Blade: carbon-weave checker
# (blade_carbon.gdshader) — position-keyed, so it survives pattern rebuilds —
# in the shaft's color, the way a one-piece stick is finished.

const _FLEX_SHADER: Shader = preload("res://Shaders/stick_flex.gdshader")
const _CARBON_SHADER: Shader = preload("res://Shaders/blade_carbon.gdshader")
const _BRAND_TEX: Texture2D = preload("res://Assets/textures/stick_brand_mitts.png")

const SHAFT_ROUGHNESS: float = 0.4

# The matte black a bare blade shows (ghost stand-ins) when the shaft is black;
# the shader's own defaults are that blade's weave pair.
const BLADE_CLASSIC := Color(0.05, 0.05, 0.05)
# A colored blade's weave: the shaft color and this much darker, about the
# contrast the carbon pair carries.
const _WEAVE_DARKEN: float = 0.25

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


# The stick's [shaft, primary, secondary] against the kit.
static func colors(gear: GearStyleConfig, kit_primary: Color, kit_secondary: Color,
		kit_light: Color) -> Array[Color]:
	return [
		TapeColorRegistry.resolve(gear.stick_shaft, kit_primary, kit_secondary, kit_light),
		TapeColorRegistry.resolve(gear.stick_primary, kit_primary, kit_secondary, kit_light),
		TapeColorRegistry.resolve(gear.stick_secondary, kit_primary, kit_secondary, kit_light),
	]


# The flex-shader shaft material for the player's stick. Callers layer their
# own runtime uniforms on top (flex_m, shaft_len_m, the grip wrap) — this
# factory owns only the design. Null gear is the stock stick.
static func make_shaft_material(gear: GearStyleConfig = null,
		kit_primary: Color = Color.WHITE, kit_secondary: Color = Color.WHITE,
		kit_light: Color = Color.WHITE) -> ShaderMaterial:
	var g: GearStyleConfig = gear if gear != null else GearStyleConfig.new()
	var c: Array[Color] = colors(g, kit_primary, kit_secondary, kit_light)
	var mat := ShaderMaterial.new()
	mat.shader = _FLEX_SHADER
	mat.set_shader_parameter(&"albedo", c[0])
	mat.set_shader_parameter(&"roughness", SHAFT_ROUGHNESS)
	mat.set_shader_parameter(&"brand_tex", _BRAND_TEX)
	mat.set_shader_parameter(&"brand_color", StickModelRegistry.slot_color(
			StickModelRegistry.brand_slot(g.stick_model), c[0], c[1], c[2]))
	mat.set_shader_parameter(&"brand_from_butt_m", _BRAND_FROM_BUTT_M)
	mat.set_shader_parameter(&"brand_len_m", _BRAND_LEN_M)
	var bands: Array = StickModelRegistry.bands(g.stick_model)
	for i: int in mini(bands.size(), _BAND_PARAMS.size()):
		var band: Dictionary = bands[i]
		mat.set_shader_parameter(_BAND_PARAMS[i][0],
				StickModelRegistry.slot_color(int(band["slot"]), c[0], c[1], c[2]))
		mat.set_shader_parameter(_BAND_PARAMS[i][1], band["from_m"])
		mat.set_shader_parameter(_BAND_PARAMS[i][2], band["to_m"])
		mat.set_shader_parameter(_BAND_PARAMS[i][3], band["anchor"])
	return mat


static func make_blade_material(gear: GearStyleConfig = null,
		kit_primary: Color = Color.WHITE, kit_secondary: Color = Color.WHITE,
		kit_light: Color = Color.WHITE) -> ShaderMaterial:
	var g: GearStyleConfig = gear if gear != null else GearStyleConfig.new()
	var mat := ShaderMaterial.new()
	mat.shader = _CARBON_SHADER
	if g.stick_shaft != TapeColorRegistry.BLACK_INDEX:
		var shaft: Color = colors(g, kit_primary, kit_secondary, kit_light)[0]
		mat.set_shader_parameter(&"albedo_a", shaft.darkened(_WEAVE_DARKEN))
		mat.set_shader_parameter(&"albedo_b", shaft)
	return mat


# The matte color a bare blade shows (ghost stand-ins).
static func blade_base_color(gear: GearStyleConfig, kit_primary: Color,
		kit_secondary: Color, kit_light: Color) -> Color:
	if gear.stick_shaft == TapeColorRegistry.BLACK_INDEX:
		return BLADE_CLASSIC
	return colors(gear, kit_primary, kit_secondary, kit_light)[0]

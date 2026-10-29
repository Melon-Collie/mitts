// A whole player body in one material. Each vertex carries its ZONE in UV2.x
// (BodyZoneMesh); a zone is one surface of the body as it was authored, painted
// from per-zone arrays that BodyZonePaint compiles out of StandardMaterial3D
// records. Reproduces the standard material for the subset the bodies use:
// albedo × texture × vertex colour, roughness, metallic, the rim, specular 0.5.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sized by BodyZonePaint.MAX_ZONES.
uniform vec4 zone_albedo[48];   // sRGB rgb, alpha
uniform vec4 zone_pbr[48];      // roughness, metallic, rim, rim tint
uniform vec4 zone_tex[48];      // texture slot (-1 none), u offset, vertex colour (0/1)

// Every body texture is mip-less (stripe ImageTextures, decal viewports), so
// LOD 0 is what the standard material samples too, and it keeps the branch below
// free of derivatives.
uniform sampler2D tex0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex7 : source_color, filter_linear_mipmap, repeat_enable;

#ifdef GHOST
uniform float ghost_alpha = 0.3;
#endif

// 1 on a body whose faces bend as they are skinned (SkaterConnectedMesh): each
// fragment is then lit by its triangle's own facing as drawn, from the
// position's screen derivatives, so every face stays flat however the weights
// across it pull. The vertex normals, set in the bind pose, would be skinned
// apart from each other and shade a bent face as a smear.
instance uniform float flat_from_position = 0.0;

// A source_color albedo: linear where the renderer lights in linear space, left as
// authored on Compatibility, which does not convert one either.
vec3 albedo_to_light_space(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92),
			lessThan(c, vec3(0.04045)));
#endif
}

vec4 sample_slot(int slot, vec2 uv) {
	if (slot == 0) { return textureLod(tex0, uv, 0.0); }
	if (slot == 1) { return textureLod(tex1, uv, 0.0); }
	if (slot == 2) { return textureLod(tex2, uv, 0.0); }
	if (slot == 3) { return textureLod(tex3, uv, 0.0); }
	if (slot == 4) { return textureLod(tex4, uv, 0.0); }
	if (slot == 5) { return textureLod(tex5, uv, 0.0); }
	if (slot == 6) { return textureLod(tex6, uv, 0.0); }
	if (slot == 7) { return textureLod(tex7, uv, 0.0); }
	return vec4(1.0);
}

void fragment() {
	int zone = int(round(UV2.x));
	vec4 albedo = zone_albedo[zone];
	albedo.rgb = albedo_to_light_space(albedo.rgb);
	vec4 tex = zone_tex[zone];
	int slot = int(round(tex.x));
	if (slot >= 0) {
		albedo *= sample_slot(slot, UV + vec2(tex.y, 0.0));
	}
	if (tex.z > 0.5) {
		albedo *= COLOR;
	}
	vec4 pbr = zone_pbr[zone];
	if (flat_from_position > 0.5) {
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		// Back faces are culled, so the face looks toward the camera at the origin.
		NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = pbr.x;
	METALLIC = pbr.y;
	SPECULAR = 0.5;
	RIM = pbr.z;
	RIM_TINT = pbr.w;
#ifdef GHOST
	ALPHA = albedo.a * ghost_alpha;
#endif
}

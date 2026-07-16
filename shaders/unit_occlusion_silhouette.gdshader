shader_type canvas_item;

/// Live unit frame (TEXTURE) with an occlusion mask:
/// covered pixels → silhouette color, uncovered → original colors.
/// region_uv remaps atlas UVs into 0..1 frame space for the mask.
uniform sampler2D occlusion_mask : filter_nearest, hint_default_black;
uniform vec4 silhouette_color : source_color = vec4(0.12, 0.28, 0.48, 0.82);
uniform vec4 region_uv = vec4(0.0, 0.0, 1.0, 1.0); // xy offset, zw size in atlas UV
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < alpha_threshold) {
		discard;
	}
	vec2 local_uv = (UV - region_uv.xy) / max(region_uv.zw, vec2(1e-6));
	float covered = texture(occlusion_mask, clamp(local_uv, vec2(0.0), vec2(1.0))).a;
	if (covered > 0.5) {
		COLOR = vec4(silhouette_color.rgb, silhouette_color.a * tex.a);
	} else {
		COLOR = tex;
	}
}

shader_type canvas_item;

/// Flat silhouette tint: every opaque pixel becomes silhouette_color.
/// Used while a unit is visually covered by buildings/trees/props.
uniform vec4 silhouette_color : source_color = vec4(0.12, 0.28, 0.48, 0.82);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < alpha_threshold) {
		discard;
	}
	COLOR = vec4(silhouette_color.rgb, silhouette_color.a * tex.a);
}

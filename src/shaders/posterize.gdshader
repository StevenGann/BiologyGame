shader_type canvas_item;

/// Number of color levels per channel (e.g. 32 = 5-bit, 16 = 4-bit).
/// Lower = stronger lo-fi / PS1 look.
uniform int levels : hint_range(2, 256) = 32;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float scale = float(levels - 1);
	col.rgb = floor(col.rgb * scale + 0.5) / scale;
	COLOR = col;
}

shader_type canvas_item;

/// Number of color levels per channel (e.g. 32 = 5-bit, 16 = 4-bit).
/// Lower = stronger lo-fi / PS1 look.
uniform int levels : hint_range(2, 256) = 32;

/// Film grain intensity. 0 = off.
uniform float grain : hint_range(0, 1) = 0.1;

// Improved hash for less visible patterning (based on Dave Hoskins)
vec3 _grain_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);

    vec3 seed = vec3(FRAGCOORD.xy * 0.5, fract(TIME) * 414.0);
	vec3 n = _grain_hash(seed) * 2.0 - 1.0;
	col.rgb += n * grain * 0.25;
	
	float scale = float(levels - 1);
	col.rgb = floor(col.rgb * scale + 0.5) / scale;	

	COLOR = col;
}

shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, depth_test_default,
	specular_disabled, vertex_lighting;

uniform sampler2D albedo : source_color, filter_nearest, repeat_disable;
uniform sampler2D heightmap : source_color, filter_nearest, repeat_disable;
uniform float height_min = -2.0;
uniform float height_max = 8.0;
uniform bool use_heightmap_displacement = true;
uniform float alpha_scissor : hint_range(0, 1) = 0.5;
uniform float jitter : hint_range(0, 1) = 0.25;
uniform ivec2 resolution = ivec2(320, 240);
uniform bool affine_mapping = true;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

vec4 snap_to_position(vec4 base_position) {
	vec4 snapped_position = base_position;
	snapped_position.xyz = base_position.xyz / base_position.w;

	vec2 snap_resolution = floor(vec2(resolution) * (1.0 - jitter));
	snapped_position.x = floor(snap_resolution.x * snapped_position.x) / snap_resolution.x;
	snapped_position.y = floor(snap_resolution.y * snapped_position.y) / snap_resolution.y;

	snapped_position.xyz *= base_position.w;
	return snapped_position;
}

void vertex() {
	if (use_heightmap_displacement) {
		float h = texture(heightmap, UV).r;
		VERTEX.y += mix(height_min, height_max, h);
	}

	vec4 world_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 snapped_position = snap_to_position(PROJECTION_MATRIX * world_pos);

	if (affine_mapping) {
		POSITION = snapped_position;
		POSITION /= abs(POSITION.w);
	} else {
		POSITION = snapped_position;
	}
}

void fragment() {
	vec4 texture_color = texture(albedo, UV);
	vec4 color_base = albedo_color;
	vec4 vertex_color = COLOR;

	ALBEDO = (color_base * texture_color * vertex_color).rgb;
	ALPHA = texture_color.a * color_base.a * vertex_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}

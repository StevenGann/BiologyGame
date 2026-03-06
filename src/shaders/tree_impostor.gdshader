// Tree impostor / billboard shader for far-LOD trees.
// Each instance is a camera-facing quad (QuadMesh) rendered via MultiMesh.
// Samples from a per-row texture atlas (one row per tree variant).
// Applies the same PS1-style vertex snapping as the main tree shader for visual consistency.
//
// Atlas layout: horizontal = atlas columns (optional angle views), vertical = variants.
// With ATLAS_ROWS = 9 (one per tree variant) and ATLAS_COLS = 1 (single front view):
//   UV.y selects the variant row via per-instance custom data (INSTANCE_CUSTOM.x).
//   UV.x tiles the quad across the full atlas column.
//
// Alpha scissor cuts the quad to the tree silhouette.
shader_type spatial;
render_mode
	blend_mix,
	cull_disabled,        // Double-sided: visible from both sides.
	depth_draw_opaque,
	depth_test_default,
	specular_disabled,
	vertex_lighting,
	unshaded;             // No lighting — matches PS1 style.

// Impostor texture atlas. Bake one row per tree variant facing the camera.
uniform sampler2D impostor_atlas : source_color, filter_nearest;
// Number of rows in the atlas (one per tree variant).
uniform int atlas_rows : hint_range(1, 64) = 9;
// PS1 vertex snap resolution.
uniform ivec2 resolution = ivec2(320, 240);
// Jitter strength (0 = no snap, 1 = full PS1 snap).
uniform float jitter : hint_range(0.0, 1.0) = 0.25;
// Alpha cutoff for the silhouette.
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// Uniform tint (use WHITE for no tint).
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Per-instance custom data:
//   INSTANCE_CUSTOM.x = atlas row index (float, 0..atlas_rows-1)
//   INSTANCE_CUSTOM.y = (unused, reserved)

varying vec2 _uv;

vec4 snap_vertex(vec4 clip_pos) {
	vec3 ndc = clip_pos.xyz / clip_pos.w;
	vec2 snap_res = floor(vec2(resolution) * (1.0 - jitter));
	ndc.x = floor(snap_res.x * ndc.x) / snap_res.x;
	ndc.y = floor(snap_res.y * ndc.y) / snap_res.y;
	return vec4(ndc * clip_pos.w, clip_pos.w);
}

void vertex() {
	// Billboard: replace model basis with camera-facing orientation.
	// Keep the instance's world position (from MultiMesh transform), but orient to camera.
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Camera right and up in world space.
	vec3 cam_right = vec3(INV_VIEW_MATRIX[0][0], INV_VIEW_MATRIX[1][0], INV_VIEW_MATRIX[2][0]);
	vec3 cam_up    = vec3(0.0, 1.0, 0.0);  // Y-aligned billboard (no tilt with camera).

	// Reconstruct world-space vertex from quad local VERTEX.
	// VERTEX is in [-0.5, 0.5] for a unit QuadMesh; scale by instance scale from MODEL_MATRIX.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 world_vertex = world_pos + cam_right * VERTEX.x * sx + cam_up * VERTEX.y * sy;

	// Snap to PS1 grid.
	POSITION = snap_vertex(PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_vertex, 1.0));

	// Remap UV to atlas row selected by instance custom data.
	float row = INSTANCE_CUSTOM.x;
	float row_height = 1.0 / float(atlas_rows);
	_uv = vec2(UV.x, (row + UV.y) * row_height);
}

void fragment() {
	vec4 tex_col = texture(impostor_atlas, _uv);
	ALBEDO = (tex_col * albedo_color).rgb;
	ALPHA = tex_col.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}

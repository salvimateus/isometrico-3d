shader_type spatial;

// Baked toy-paint material for merged character meshes. Per-vertex encoding (see rig_baker.gd):
// COLOR.rgb = linear albedo, COLOR.a = emission factor (albedo * a), UV = (roughness, metallic),
// UV2 = (rim, rim tint).

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = UV.x;
	METALLIC = UV.y;
	SPECULAR = 0.5 + 0.25 * step(0.01, UV.y);
	RIM = UV2.x;
	RIM_TINT = UV2.y;
	EMISSION = COLOR.rgb * COLOR.a;
}

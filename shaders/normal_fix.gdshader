
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

void fragment() {
    ALBEDO = vec3(0.75);
    ROUGHNESS = 1.0;

    // Normal da face calculada pela geometria visível.
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    NORMAL = normalize(cross(dy, dx));

    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }
}

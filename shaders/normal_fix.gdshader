
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Cor configurável pelo Inspector
uniform vec4 cor_base : source_color = vec4(0.75, 0.75, 0.75, 1.0);

void fragment() {
    ALBEDO = cor_base.rgb;
    ROUGHNESS = 1.0;

    // Normal da face calculada pela geometria visível.
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    NORMAL = normalize(cross(dy, dx));

    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }
}

shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform vec4 paper_color : source_color = vec4(0.96, 0.96, 0.92, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.55, 0.55, 0.55, 1.0);
uniform vec4 ink_color : source_color = vec4(0.03, 0.03, 0.03, 1.0);

uniform float edge_strength : hint_range(0.0, 1.0) = 0.35;
uniform float edge_power : hint_range(0.5, 8.0) = 2.5;

uniform float paper_noise_strength : hint_range(0.0, 0.15) = 0.035;
uniform float paper_noise_scale : hint_range(1.0, 200.0) = 60.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    // Corrige a iluminação usando a normal da própria geometria
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    NORMAL = normalize(cross(dy, dx));

    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }

    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    SPECULAR = 0.0;

    // Texturinha leve de papel
    float noise_value = hash(floor(UV * paper_noise_scale));
    float paper_variation = mix(1.0 - paper_noise_strength, 1.0, noise_value);

    vec3 base_paper = paper_color.rgb * paper_variation;

    // Escurece levemente perto das bordas visuais
    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), edge_power);
    vec3 ink_mix = mix(base_paper, ink_color.rgb, fresnel * edge_strength);

    ALBEDO = ink_mix;
}

void light() {
    float ndotl = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);

    // Iluminação em faixas, estilo toon/cartoon antigo
    float toon_step = smoothstep(0.2, 0.25, ndotl);

    vec3 toon_color = mix(shadow_color.rgb, ALBEDO, toon_step);

    DIFFUSE_LIGHT += toon_color * LIGHT_COLOR * ATTENUATION;
}
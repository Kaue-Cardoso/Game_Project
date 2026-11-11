shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform vec4 paper_color : source_color = vec4(0.97, 0.97, 0.94, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.58, 0.58, 0.58, 1.0);
uniform vec4 ink_color : source_color = vec4(0.02, 0.02, 0.02, 1.0);

uniform float edge_strength : hint_range(0.0, 1.0) = 0.45;
uniform float edge_power : hint_range(0.5, 8.0) = 2.8;

uniform float paper_noise_strength : hint_range(0.0, 0.15) = 0.025;
uniform float paper_noise_scale : hint_range(1.0, 200.0) = 60.0;

uniform float shadow_steps : hint_range(2.0, 6.0) = 2.0;
uniform float ink_mix_strength : hint_range(0.0, 1.0) = 0.25;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec3 dx = dFdx(VERTEX);
    vec3 dy = dFdy(VERTEX);
    NORMAL = normalize(cross(dy, dx));

    if (!FRONT_FACING) {
        NORMAL = -NORMAL;
    }

    ROUGHNESS = 1.0;
    METALLIC = 0.0;
    SPECULAR = 0.0;

    float noise_value = hash(floor(UV * paper_noise_scale));
    float paper_variation = mix(1.0 - paper_noise_strength, 1.0, noise_value);
    vec3 base_paper = paper_color.rgb * paper_variation;

    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), edge_power);

    vec3 inked = mix(base_paper, ink_color.rgb, fresnel * edge_strength);

    ALBEDO = mix(base_paper, inked, ink_mix_strength + fresnel * 0.5);
}

void light() {
    float ndotl = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0);

    float toon_step = floor(ndotl * shadow_steps) / max(shadow_steps - 1.0, 1.0);
    toon_step = smoothstep(0.0, 1.0, toon_step);

    vec3 toon_color = mix(shadow_color.rgb, ALBEDO, toon_step);

    DIFFUSE_LIGHT += toon_color * LIGHT_COLOR * ATTENUATION;
}
shader_type canvas_item;

uniform vec3 glow_color : source_color = vec3(0.0, 0.94, 1.0);
uniform float base_opacity : hint_range(0.0, 0.3) = 0.1;

void fragment() {
    vec2 centered = UV - vec2(0.5, 1.0);
    centered.y *= 3.0;  // Ellipse ratio
    float dist = length(centered);
    float gradient = 1.0 - smoothstep(0.0, 0.7, dist);

    COLOR = vec4(glow_color, gradient * base_opacity);
}

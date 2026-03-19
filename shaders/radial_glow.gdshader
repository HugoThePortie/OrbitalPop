shader_type canvas_item;

uniform vec3 glow_color : source_color = vec3(0.0, 0.94, 1.0);
uniform float base_opacity : hint_range(0.0, 0.5) = 0.15;
uniform float pulse_speed : hint_range(0.1, 1.0) = 0.33;
uniform bool animate = true;

void fragment() {
    float pulse = animate ? sin(TIME * pulse_speed * TAU) * 0.5 + 0.5 : 0.75;
    float scale = 1.0 + pulse * 0.2;
    float opacity_mod = mix(0.5, 1.0, pulse);

    vec2 centered = (UV - 0.5) * scale + 0.5;
    float dist = length(centered - 0.5) * 2.0;
    float gradient = 1.0 - smoothstep(0.0, 0.7, dist);

    COLOR = vec4(glow_color, gradient * base_opacity * opacity_mod);
}

shader_type canvas_item;

uniform float line_spacing : hint_range(1.0, 8.0) = 3.0;
uniform float line_opacity : hint_range(0.0, 0.5) = 0.12;
uniform float flicker_amount : hint_range(0.0, 0.1) = 0.03;
uniform float flicker_speed : hint_range(0.5, 5.0) = 2.5;

void fragment() {
	float scanline = step(0.5, fract(FRAGCOORD.y / line_spacing));
	float flicker = 1.0 - flicker_amount * sin(TIME * flicker_speed * TAU);
	COLOR = vec4(0.0, 0.0, 0.0, scanline * line_opacity * flicker);
}

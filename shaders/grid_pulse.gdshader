shader_type canvas_item;

uniform vec2 grid_size = vec2(40.0, 40.0);
uniform vec3 line_color : source_color = vec3(0.0, 0.94, 1.0);
uniform float line_opacity : hint_range(0.0, 0.1) = 0.03;
uniform float pulse_speed : hint_range(0.1, 1.0) = 0.25;
uniform bool animate = true;

void fragment() {
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 uv_pixels = UV * screen_size;
    vec2 grid_uv = mod(uv_pixels, grid_size);
    float line = step(grid_uv.x, 1.0) + step(grid_uv.y, 1.0);
    line = min(line, 1.0);

    float pulse = animate ? sin(TIME * pulse_speed * TAU) * 0.5 + 0.5 : 0.75;
    float opacity = line_opacity * mix(0.5, 1.0, pulse);

    COLOR = vec4(line_color, line * opacity);
}

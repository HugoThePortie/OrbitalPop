shader_type canvas_item;

// Gradient colors for title shimmer effect
uniform vec4 color_start : source_color = vec4(0.0, 0.94, 1.0, 1.0);  // Cyan #00F0FF
uniform vec4 color_mid : source_color = vec4(1.0, 0.0, 0.67, 1.0);    // Magenta #FF00AA
uniform vec4 color_end : source_color = vec4(0.0, 0.94, 1.0, 1.0);    // Cyan #00F0FF

// Animation: 0.333 = 3 second full cycle
uniform float scroll_speed : hint_range(0.1, 2.0) = 0.333;
uniform bool animate = true;

void fragment() {
    // Get the original texture color (the text glyph)
    vec4 tex_color = texture(TEXTURE, UV);

    // Calculate scrolling position (moves right to left visually)
    float scroll = animate ? TIME * scroll_speed : 0.0;
    float gradient_pos = fract(UV.x * 0.5 + scroll);

    // Create smooth gradient: cyan -> magenta -> cyan
    vec4 gradient_color;
    if (gradient_pos < 0.5) {
        // First half: cyan to magenta
        gradient_color = mix(color_start, color_mid, gradient_pos * 2.0);
    } else {
        // Second half: magenta to cyan
        gradient_color = mix(color_mid, color_end, (gradient_pos - 0.5) * 2.0);
    }

    // Apply gradient color while preserving text alpha
    COLOR = vec4(gradient_color.rgb, tex_color.a * COLOR.a);
}

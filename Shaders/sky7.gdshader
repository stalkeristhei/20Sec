shader_type sky;

// Corrected: Use : source_color for Godot 4
uniform vec4 horizon_color : source_color = vec4(0.1, 0.1, 0.2, 1.0); // Darker blue/purple
uniform vec4 zenith_color : source_color = vec4(0.01, 0.01, 0.05, 1.0);  // Almost black

uniform float horizon_height : hint_range(-1.0, 1.0) = 0.0; // Where the horizon sits
uniform float fade_power : hint_range(0.1, 10.0) = 2.0; // How fast horizon fades to zenith

uniform float star_density : hint_range(0.0, 1.0) = 0.08; // How many stars
uniform float star_sharpness : hint_range(1.0, 100.0) = 50.0; // How small/sharp stars are
uniform float star_twinkle_speed : hint_range(0.0, 10.0) = 1.0; // How fast stars flicker

uniform int color_bands : hint_range(1, 64) = 16; // Simulate color banding

// Simple noise function for stars and dithering
float random(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void sky() {
    // Corrected: Use EYEDIR instead of _sky_direction
    // EYEDIR.y goes from -1 (down) to 1 (up).
    float gradient_factor = smoothstep(-0.2 + horizon_height, 0.5 + horizon_height, EYEDIR.y);

    // Simulate banding by quantizing the gradient factor
    gradient_factor = floor(gradient_factor * float(color_bands)) / float(color_bands);

    vec3 color = mix(horizon_color.rgb, zenith_color.rgb, pow(gradient_factor, fade_power));

    // --- Add Stars ---
    // Corrected: Use EYEDIR here as well
    vec2 uv = EYEDIR.xz / EYEDIR.y; // Project direction onto a plane for consistent star distribution
    uv = fract(uv * 1000.0); // Scale and wrap UVs for star field randomness

    float star = random(uv);

    // Twinkle effect: use time and another random value for varied flickering
    float twinkle_factor = random(uv + floor(TIME * star_twinkle_speed));

    // Only show stars if their random value is below density threshold
    // and if they are "twinkling" bright enough
    if (star < star_density * (0.8 + 0.2 * twinkle_factor)) {
        // Make stars sharper/smaller based on star_sharpness
        float star_value = (1.0 - pow(star / star_density, star_sharpness));
        color += vec3(star_value * 0.8); // Add white light for stars
    }

    // --- Final Color ---
    COLOR = color;
}
shader_type spatial;
render_mode unshaded;

// --- UNIFORMS / CONTROLS ---

// Base texture
uniform sampler2D albedo_texture;

// Texture tiling and scrolling
uniform vec2 uv_scale = vec2(2.0, 2.0); // how many times to repeat texture
uniform vec2 scroll_speed = vec2(0.2, 0.0); // movement speed (x, y)

// Color tint and intensity
uniform vec4 color_tint = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 5.0) = 1.0;

// Wave distortion
uniform float wave_amplitude : hint_range(0.0, 0.5) = 0.1;
uniform float wave_frequency : hint_range(0.0, 10.0) = 3.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;

// Transparency
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    // --- 1. Continuous UV handling ---
    // Get the continuous, tiled, and scrolled UVs.
    // DO NOT apply fract() yet. This is the key.
    vec2 continuous_uv = UV * uv_scale;
    continuous_uv += scroll_speed * TIME;

    // --- 2. Distortion effect (using continuous UVs) ---
    // Calculate the distortion using the *continuous* UVs.
    // This makes the wave seamless across all tiles.
    vec2 distorted_uv = continuous_uv;
    distorted_uv.x += sin(continuous_uv.y * wave_frequency + TIME * wave_speed) * wave_amplitude;
    distorted_uv.y += cos(continuous_uv.x * wave_frequency + TIME * wave_speed) * wave_amplitude;

    // --- 3. Final UV lookup ---
    // NOW, apply fract() to the *final, distorted* coordinates.
    // This correctly wraps the texture lookup.
    vec2 final_uv = fract(distorted_uv);

    // --- 4. Sample and apply ---
    vec4 tex_color = texture(albedo_texture, final_uv);
    ALBEDO = tex_color.rgb * color_tint.rgb;
    EMISSION = ALBEDO * emission_strength;
    ALPHA = tex_color.a * color_tint.a * alpha;
}
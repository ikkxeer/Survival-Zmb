shader_type canvas_item;
// Full-screen grade: vignette, damage pulse and desaturation when the player is down.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.35;
uniform float hurt = 0.0;
uniform float down = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 d = SCREEN_UV - 0.5;
	float v = smoothstep(0.85, 0.25, length(d * vec2(1.25, 1.0)));
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey), down * 0.8);
	c *= mix(1.0, v, vignette);
	c = mix(c, vec3(0.85, 0.08, 0.12), hurt * (1.0 - v) * 0.8);
	c *= tint.rgb;
	COLOR = vec4(c, 1.0);
}

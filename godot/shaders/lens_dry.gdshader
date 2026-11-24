shader_type canvas_item;
render_mode unshaded, blend_mul;
// Dries the lens rivulet map (fx/lens_fx.gd): a full-screen rect drawn over the never-cleared map each frame,
// multiplying it (all channels: the map is premultiplied, so what is left keeps its shape) by `keep`.
uniform float keep = 0.99;

void fragment() {
	COLOR = vec4(keep);
}

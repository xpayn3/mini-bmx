#[compute]
#version 450
// fx/motion_blur.gd: copies the colour so the blur can read it while writing the colour (the colour buffer can't be
// copied with texture_copy: no COPY_FROM usage)
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform Params { vec2 size; vec2 pad; } p;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(px, ivec2(p.size)))) return;
	imageStore(dst, px, imageLoad(color, px));
}

#[compute]
#version 450
// Ruts + tyre prints window (world/ruts.gd): copies one 160 x 160-cell tile of the rut field (RutFieldCs.TilePack: per
// cell four uint32 = half pairs (depth, edge distance), (strength, blood), (cos 2a, sin 2a), (smear, 0)) into its
// toroidal place in the window textures the ground shaders read (shaders/ruts.gdshaderinc). mode 1 = clear the place.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Tiles { uint w[]; } tiles;
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D out_a;   // depth, edge distance (m), strength, blood
layout(set = 0, binding = 2, rgba8) uniform restrict writeonly image2D out_b;     // smear, (cos 2a, sin 2a) * 0.5 + 0.5, 0

layout(push_constant, std430) uniform Push {
	vec4 a;   // place in the window (texel x, y), first cell of the tile in the buffer, mode (0 copy, 1 clear)
} pc;

const int TILE = 160;
const float NO_E = 9.0;   // RutFieldCs.NO_E

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= TILE || id.y >= TILE) return;
	ivec2 dst = ivec2(pc.a.xy) + id;
	if (pc.a.w > 0.5) {
		imageStore(out_a, dst, vec4(0.0, NO_E, 0.0, 0.0));
		imageStore(out_b, dst, vec4(0.0, 0.5, 0.5, 0.0));
		return;
	}
	uint c = (uint(pc.a.z) + uint(id.y * TILE + id.x)) * 4u;
	vec2 de = unpackHalf2x16(tiles.w[c]);
	vec2 sb = unpackHalf2x16(tiles.w[c + 1u]);
	vec2 dr = unpackHalf2x16(tiles.w[c + 2u]);
	vec2 sm = unpackHalf2x16(tiles.w[c + 3u]);
	imageStore(out_a, dst, vec4(de, sb));
	imageStore(out_b, dst, vec4(clamp(sm.x, 0.0, 1.0), dr * 0.5 + 0.5, 0.0));
}

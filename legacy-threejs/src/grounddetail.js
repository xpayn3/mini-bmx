// Terrain shader: blends the two baked ground layers (terrain.js buildGen) the way modern terrain
// does -- by HEIGHT, not by a soft fade. Each layer has a small generated detail height (grass tufts,
// stones in the dirt); where both are present, whichever stands taller wins over a narrow band, so
// trail edges come out ragged and natural: stones poke out of the grass, grass grows over the dirt.
// Then each layer gets its own detail shading (grass blades, pale stones and grit, rock grain).
// All detail is procedural 3D noise on the world position (no image files, no stretching on slopes)
// and fades out before it gets smaller than a pixel, so it never shimmers.
//   map   (sRGB)  rgb = land colour (with baked AO)   a = dirt weight
//   uDirt (sRGB)  rgb = trail dirt colour (with AO)   a = rock-face weight
export const GROUND_KEY = 'ground-v2|';

export function groundDetail(shader, dirtTex) {
  shader.uniforms.uDirt = { value: dirtTex };
  shader.vertexShader = shader.vertexShader
    .replace('#include <common>', '#include <common>\nvarying vec3 vGW;')
    .replace('#include <project_vertex>', '#include <project_vertex>\nvGW = (modelMatrix * vec4(transformed, 1.0)).xyz;');
  shader.fragmentShader = shader.fragmentShader
    .replace('#include <common>', /* glsl */`#include <common>
varying vec3 vGW;
uniform sampler2D uDirt;
vec3 gdHash3(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yxz + 33.33);
  return fract((q.xxy + q.yzz) * q.zyx);
}
float gdHash(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float gdNoise3(vec3 p) {   // smooth 3D value noise, 0..1
  vec3 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(gdHash(i), gdHash(i + vec3(1, 0, 0)), u.x), mix(gdHash(i + vec3(0, 1, 0)), gdHash(i + vec3(1, 1, 0)), u.x), u.y),
             mix(mix(gdHash(i + vec3(0, 0, 1)), gdHash(i + vec3(1, 0, 1)), u.x), mix(gdHash(i + vec3(0, 1, 1)), gdHash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
// scattered stones: x = how much stone (0 none .. 1 its top), y = its tone (-1 dark .. 1 pale)
vec2 gdPebbles(vec2 p) {
  p += (vec2(gdNoise3(vec3(p * 1.7, 3.1)), gdNoise3(vec3(p * 1.7, 8.7))) - 0.5) * 0.5;   // lumpy, not round
  vec2 i = floor(p), f = fract(p);
  vec2 best = vec2(0.0);
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 g = vec2(x, y);
    vec3 h = gdHash3(i + g + 17.0);
    if (h.z < 0.55) continue;                                   // most cells: no stone
    float r = 0.08 + 0.3 * (h.z - 0.55) * (h.z - 0.55) * 4.0;   // mostly small, the odd bigger one
    vec2 dv = (g + 0.2 + 0.6 * h.xy - f) * vec2(1.0, 0.75 + 0.5 * h.x);   // a little elongated
    float k = 1.0 - smoothstep(r * 0.4, r, length(dv));
    if (k > best.x) best = vec2(k, h.y * 2.0 - 0.6);
  }
  return best;
}
`)
    .replace('#include <map_fragment>', /* glsl */`
#ifdef USE_MAP
{
  vec4 gA = texture2D(map, vMapUv), gB = texture2D(uDirt, vMapUv);
  vec3 P = vGW;
  float gpx = length(fwidth(P.xz));                    // metres per pixel
  float f1 = 1.0 - smoothstep(0.012, 0.04, gpx);       // finest detail
  float f2 = 1.0 - smoothstep(0.035, 0.12, gpx);
  float f3 = 1.0 - smoothstep(0.1, 0.45, gpx);         // the height blend itself
  float t = gA.a, rockW = gB.a;
  float n0 = gdNoise3(P * 2.3 + 3.3), n1 = gdNoise3(P * 9.0), n2 = gdNoise3(P * 23.0 + 7.1);
  // detail heights, 0..1
  float hG = mix(0.5, n1, f2) * 0.55 + mix(0.5, n2, f1) * 0.25 + n0 * 0.2;    // grass tufts
  vec2 pb = gdPebbles(P.xz * 8.0);                                           // stones in the dirt
  float peb = pb.x * f2;
  float hD = peb * 0.6 + gdNoise3(P * 3.1 + 11.0) * 0.45 + gdNoise3(P * 0.9 + 2.0) * 0.3;
  // height blend: the taller layer wins, over a band wide enough that the texel grid never shows
  float a1 = (1.0 - t) + hG * 0.75, a2 = t + hD * 0.75;
  float m = max(a1, a2) - 0.28;
  float b1 = max(a1 - m, 0.0), b2 = max(a2 - m, 0.0);
  float wd = mix(t, b2 / max(b1 + b2, 1e-4), f3);
  vec3 col = mix(gA.rgb, gB.rgb, wd);
  // per-layer detail shading
  float green = smoothstep(0.05, 0.3, (gA.g - gA.r) / max(gA.g, 1e-3));
  // (no speckled light/dark shading on the grass itself: it read as fine dotted noise; the tufts above
  // still shape the ragged grass/dirt edges)
  col *= mix(1.0, 1.0 + peb * 0.28 * pb.y + (n2 - 0.5) * 0.14 * f1, wd);           // stones (pale and dark), grit
  float rk = gdNoise3(P * 4.3 + 5.0) * 0.6 + gdNoise3(P * 13.0) * 0.4 * f2;
  col *= mix(1.0, 0.78 + 0.44 * rk, rockW * (1.0 - wd) * f3);                     // rock faces: grain
  diffuseColor *= vec4(col, 1.0);
}
#endif
`);
}

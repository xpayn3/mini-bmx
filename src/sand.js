import * as THREE from 'three';

// Fine sand detail for the terrain material (a MeshStandardMaterial with vertex colours):
//  - picks out sandy vertex colours (beach, dunes, lake bed) by hue
//  - grain: per-cell brightness jitter with dark and light specks, soft mottling, faint wind ripples
//  - sparkle: each grain gets a random facet; it glints only when that facet mirrors the sun
//    into the camera, so the glitter shifts as the view changes. Shadowed sand does not sparkle.
// All fine detail fades out once a grain gets smaller than a pixel, so it never shimmers.

export function addSandDetail(material, sunDir, waterLevel) {
  const uniforms = {
    uSandSun: { value: sunDir.clone().normalize() },
    uSandWater: { value: waterLevel },
  };
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);

    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vSandW;')
      .replace('#include <project_vertex>', '#include <project_vertex>\nvSandW = (modelMatrix * vec4(transformed, 1.0)).xyz;');

    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', /* glsl */`#include <common>
varying vec3 vSandW;
uniform vec3 uSandSun;
uniform float uSandWater;
float sandHash(vec2 p) { p = fract(p * vec2(443.897, 441.423)); p += dot(p, p.yx + 19.19); return fract((p.x + p.y) * p.x); }
vec3 sandHash3(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yxz + 33.33);
  return fract((q.xxy + q.yzz) * q.zyx);
}
float sandNoise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(sandHash(i), sandHash(i + vec2(1, 0)), u.x), mix(sandHash(i + vec2(0, 1)), sandHash(i + vec2(1, 1)), u.x), u.y);
}
float sandMask;
float sandPx;
`)
      .replace('#include <color_fragment>', /* glsl */`#include <color_fragment>
{
  // how sandy is this colour? warm, yellowish, not green, not grey
  vec3 s = pow(max(vColor.rgb, vec3(1e-4)), vec3(1.0 / 2.2));
  float gr = s.g / max(s.r, 1e-3), warm = (s.r - s.b) / max(s.r, 1e-3);
  sandMask = smoothstep(0.68, 0.76, gr) * (1.0 - smoothstep(0.98, 1.04, gr)) * smoothstep(0.16, 0.26, warm) * smoothstep(0.45, 0.6, s.r);

  vec2 p = mat2(0.8, -0.6, 0.6, 0.8) * vSandW.xz;   // rotated so nothing lines up with the axes
  sandPx = length(fwidth(p));                       // metres per pixel
  // fine noise only: two smooth octaves, faded out before they get smaller than a pixel
  float n = (sandNoise(p * 28.0) - 0.5) * (1.0 - smoothstep(0.02, 0.06, sandPx))
          + (sandNoise(p * 63.0 + 17.0) - 0.5) * (1.0 - smoothstep(0.01, 0.03, sandPx)) * 0.7;
  float k = 1.0 + n * 0.14;
  diffuseColor.rgb *= mix(1.0, k, sandMask);
}
`)
      .replace('#include <lights_fragment_end>', /* glsl */`#include <lights_fragment_end>
{
  float vis = sandMask * (1.0 - smoothstep(0.05, 0.14, sandPx)) * smoothstep(uSandWater - 0.02, uSandWater + 0.08, vSandW.y);
  if (vis > 0.0) {
    vec2 sp = vSandW.xz / 0.045;
    vec2 cell = floor(sp);
    vec3 h = sandHash3(cell + 3.7);
    vec2 c = 0.3 + 0.4 * sandHash3(cell + 11.3).xy;           // glint centre inside the cell
    float rr = length(fract(sp) - c);
    float dotMask = 1.0 - smoothstep(0.1, 0.1 + max(fwidth(rr), 0.05), rr);
    if (h.z > 0.82) {
      vec3 nW = inverseTransformDirection(normal, viewMatrix);
      vec3 facet = normalize(nW + vec3(h.x - 0.5, 0.0, h.y - 0.5) * 1.1);
      vec3 V = normalize(cameraPosition - vSandW);
      vec3 H = normalize(uSandSun + V);
      float g = pow(max(dot(facet, H), 0.0), 1400.0);
      // sunlight reaching this point (includes the shadow): recover it from the direct diffuse term
      float lumD = dot(reflectedLight.directDiffuse, vec3(0.2126, 0.7152, 0.0722));
      float lumA = max(dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722)), 1e-3);
      float sun = lumD / lumA * PI;
      reflectedLight.directSpecular += vec3(1.0, 0.96, 0.85) * g * sun * 2.5 * vis * dotMask;
    }
  }
}
`);
  };
  material.customProgramCacheKey = () => 'sand-detail-v4';
  material.needsUpdate = true;
}

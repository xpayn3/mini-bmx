import * as THREE from 'three';

// Tropical stylised water:
//  - small gerstner-ish waves in the vertex shader (damped near the shore)
//  - fine ripple normals, sun glints, sky fresnel
//  - depth-tinted lagoon colours, caustics in the shallows, animated shore foam
//  - receives the sun's shadow
// Water depth comes from a small heightmap baked from terrain.height() around the player.

const BAKE_RES = 192;     // texels per side
const BAKE_SIZE = 128;    // metres covered
const BAKE_SNAP = 16;     // bake centre snaps to this grid
const BAKE_MS = 1.5;      // per-frame time budget for the background depth bake

const vertexShader = /* glsl */`
#include <common>
#include <fog_pars_vertex>
#include <shadowmap_pars_vertex>
uniform float uTime;
uniform sampler2D uDepth;
uniform vec2 uDepthCenter;
uniform float uDepthSize;
varying vec3 vWorld;
varying float vDepth;
varying vec3 vWaveN;

float depthAt(vec2 xz) {
  vec2 uv = (xz - uDepthCenter) / uDepthSize + 0.5;
  float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  float d = texture2D(uDepth, uv).r * 5.0 - 1.0;
  return mix(1.5, d, inside);
}

// sum of travelling sine waves; returns height, writes slope
float waves(vec2 p, out vec2 g) {
  float h = 0.0; g = vec2(0.0);
  #define WAVE(dx, dy, L, A) { vec2 d = normalize(vec2(dx, dy)); float k = 6.2831853 / L; \\
    float c = sqrt(9.81 / k) * 0.45; float f = k * (dot(d, p) - c * uTime); \\
    h += A * sin(f); g += A * k * cos(f) * d; }
  WAVE( 1.0,  0.30, 4.6, 0.030)
  WAVE(-0.4,  1.00, 3.1, 0.022)
  WAVE( 0.7, -0.80, 2.2, 0.014)
  WAVE(-1.0, -0.25, 6.8, 0.026)
  WAVE( 0.2,  1.00, 1.6, 0.008)
  return h;
}

void main() {
  vec4 worldPosition = modelMatrix * vec4(position, 1.0);
  float d = depthAt(worldPosition.xz);
  float damp = smoothstep(-0.05, 0.5, d) * 0.85 + 0.15;
  vec2 g;
  float h = waves(worldPosition.xz, g);
  worldPosition.y += h * damp;
  vWaveN = normalize(vec3(-g.x * damp, 1.0, -g.y * damp));
  vWorld = worldPosition.xyz;
  vDepth = d;

  vec3 transformedNormal = normalMatrix * normal;
  #include <shadowmap_vertex>

  vec4 mvPosition = viewMatrix * worldPosition;
  gl_Position = projectionMatrix * mvPosition;
  #include <fog_vertex>
}
`;

const fragmentShader = /* glsl */`
#include <common>
#include <packing>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <shadowmap_pars_fragment>
#include <shadowmask_pars_fragment>

uniform float uTime;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uShallow, uMid, uDeep;
uniform vec3 uSkyHorizon, uSkyZenith;
uniform vec3 uFoam, uCaustic;
varying vec3 vWorld;
varying float vDepth;
varying vec3 vWaveN;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// value noise + analytic gradient
vec3 noised(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f), du = 6.0 * f * (1.0 - f);
  float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
  float k = a - b - c + d;
  return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y, du * (vec2(b - a, c - a) + k * u.yx));
}

// fine ripple slope: drifting, rotated noise octaves (no straight wave trains -> no lattice)
vec2 ripples(vec2 p, float t) {
  vec2 g = vec2(0.0);
  float amp = 0.055, freq = 1.3;
  mat2 M = mat2(1.0);
  const mat2 ROT = mat2(0.80, -0.60, 0.60, 0.80);
  for (int i = 0; i < 4; i++) {
    M = ROT * M;
    float fi = float(i);
    vec2 drift = vec2(cos(fi * 2.4 + 0.5), sin(fi * 2.4 + 0.5)) * t * (0.25 + 0.12 * fi);
    vec2 q = (M * p) * freq + drift + fi * 17.3;
    vec2 gq = noised(q).yz;
    g += (gq * M) * amp * freq;        // back to world space: transpose(M) * gq
    freq *= 1.9; amp *= 0.5;
  }
  return g;
}

float caustics(vec2 p, float t) {
  p = mat2(0.77, -0.64, 0.64, 0.77) * p;   // break axis alignment
  vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.6), cos(p.x * 1.5 - t * 0.5)) * 0.35;
  float a = sin(q.x * 3.1 + t * 0.9 + sin(q.y * 2.3 - t * 0.7) * 1.6);
  float b = sin(q.y * 3.4 - t * 0.8 + sin(q.x * 2.1 + t * 0.5) * 1.6);
  float c = pow(1.0 - abs(a * b), 12.0);
  vec2 r = mat2(0.34, 0.94, -0.94, 0.34) * p * 1.6 + 3.7;
  float a2 = sin(r.x * 2.7 - t * 0.7 + sin(r.y * 1.9 + t * 0.6) * 1.4);
  float b2 = sin(r.y * 2.9 + t * 0.6 + sin(r.x * 2.4 - t * 0.4) * 1.4);
  c += pow(1.0 - abs(a2 * b2), 14.0) * 0.6;
  return c;
}

void main() {
  float d = max(vDepth, 0.0);
  float dist = length(cameraPosition - vWorld);
  float shadow = getShadowMask();

  // normal: big waves + fading fine ripples
  vec2 rg = ripples(vWorld.xz, uTime) * (1.0 / (1.0 + dist * 0.03));
  vec3 N = normalize(vWaveN + vec3(-rg.x, 0.0, -rg.y));
  vec3 V = normalize(cameraPosition - vWorld);
  vec3 L = normalize(uSunDir);

  // lagoon colour by depth
  vec3 col = mix(uShallow, uMid, smoothstep(0.05, 0.9, d));
  col = mix(col, uDeep, smoothstep(0.7, 2.8, d));

  // caustics dancing on the sand in the shallows
  float shallow = 1.0 - smoothstep(0.15, 1.8, d);
  col += uCaustic * caustics(vWorld.xz * 1.15 + N.xz * 0.8, uTime * 1.2) * shallow * (0.3 + 0.7 * shadow);

  // simple lighting: soft wrap diffuse + shadow
  float ndl = dot(N, L) * 0.5 + 0.5;
  col *= mix(0.62, 1.0, shadow) * (0.8 + 0.25 * ndl);

  // sky reflection via fresnel
  vec3 R = reflect(-V, N);
  vec3 sky = mix(uSkyHorizon, uSkyZenith, smoothstep(0.0, 0.7, R.y));
  float fres = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
  col = mix(col, sky, clamp(fres * 1.3, 0.0, 0.85));

  // sun glints
  vec3 H = normalize(L + V);
  float nh = max(dot(N, H), 0.0);
  float sparkle = smoothstep(0.55, 0.9, vnoise(vWorld.xz * 3.0 + uTime * 0.6));   // only some facets flash
  float glintFade = 1.0 / (1.0 + dist * 0.02);
  col += uSunColor * (pow(nh, 500.0) * 3.0 * sparkle * glintFade + pow(nh, 70.0) * 0.25) * shadow;

  // shore foam: a solid lip plus bands rolling in towards the beach
  float n1 = vnoise(vWorld.xz * 2.2 + uTime * 0.25);
  float n2 = vnoise(vWorld.xz * 5.5 - uTime * 0.4);
  float lip = 1.0 - smoothstep(0.02, 0.1 + n1 * 0.08, d);
  float band = smoothstep(0.55, 0.95, sin(d * 26.0 + uTime * 2.4 + n1 * 4.0) * 0.5 + 0.5);
  band *= 1.0 - smoothstep(0.06, 0.42, d);
  float foam = max(lip, band * smoothstep(0.35, 0.7, n2));
  col = mix(col, uFoam * mix(0.75, 1.05, shadow), foam * 0.92);

  // see-through in the shallows, soft contact with the shore
  float alpha = mix(0.62, 0.95, smoothstep(0.0, 1.2, d));
  alpha = max(alpha, foam * 0.95);
  alpha = mix(alpha, 1.0, fres * 0.6);
  alpha *= smoothstep(-0.02, 0.025, vDepth);

  gl_FragColor = vec4(col, alpha);
  #include <fog_fragment>
}
`;

export class Water {
  constructor(terrain, level, sunDir) {
    this.terrain = terrain;
    this.level = level;
    this.data = new Uint8Array(BAKE_RES * BAKE_RES);
    this.tex = new THREE.DataTexture(this.data, BAKE_RES, BAKE_RES, THREE.RedFormat, THREE.UnsignedByteType);
    this.tex.magFilter = this.tex.minFilter = THREE.LinearFilter;
    this.tex.wrapS = this.tex.wrapT = THREE.ClampToEdgeWrapping;
    this.center = new THREE.Vector2(Infinity, Infinity);
    this.job = null;

    const lin = (h) => new THREE.Color(h);
    this.material = new THREE.ShaderMaterial({
      vertexShader, fragmentShader,
      lights: true, fog: true, transparent: true,
      uniforms: THREE.UniformsUtils.merge([
        THREE.UniformsLib.lights, THREE.UniformsLib.fog,
        {
          uTime: { value: 0 },
          uDepth: { value: null },
          uDepthCenter: { value: new THREE.Vector2() },
          uDepthSize: { value: BAKE_SIZE },
          uSunDir: { value: sunDir.clone() },
          uSunColor: { value: lin(0xfff1d6) },
          uShallow: { value: lin(0x38ecd2) },
          uMid: { value: lin(0x0fb9cc) },
          uDeep: { value: lin(0x0767b0) },
          uSkyHorizon: { value: lin(0xc8eef7) },
          uSkyZenith: { value: lin(0x6cc3ec) },
          uFoam: { value: lin(0xffffff) },
          uCaustic: { value: lin(0xfffbe0).multiplyScalar(0.55) },
        },
      ]),
    });
    this.material.uniforms.uDepth.value = this.tex;

    const geo = new THREE.PlaneGeometry(280, 280, 224, 224).rotateX(-Math.PI / 2);
    this.mesh = new THREE.Mesh(geo, this.material);
    this.mesh.position.y = level;
    this.mesh.receiveShadow = true;
    this.mesh.frustumCulled = false;
  }

  // virtual depth: undo the terrain's lake-bed flattening so deep lakes still read as deep
  depth(x, z) {
    const h = this.terrain.height(x, z), bed = this.level - 0.35;
    return h < bed ? 0.35 + (bed - h) / 0.08 : this.level - h;
  }

  bakeRows(job, ms) {
    const step = BAKE_SIZE / BAKE_RES, x0 = job.cx - BAKE_SIZE / 2 + step / 2, z0 = job.cz - BAKE_SIZE / 2 + step / 2;
    const deadline = performance.now() + ms;
    let j = job.row;
    for (; j < BAKE_RES; j++) {
      if (j > job.row && performance.now() >= deadline) break;
      // DataTexture row 0 is uv.y = 0 -> smallest z
      const z = z0 + j * step;
      for (let i = 0; i < BAKE_RES; i++) {
        const d = this.depth(x0 + i * step, z);
        job.buf[j * BAKE_RES + i] = Math.max(0, Math.min(255, ((d + 1) / 5) * 255));
      }
    }
    job.row = j;
    if (job.row >= BAKE_RES) {
      this.data.set(job.buf);
      this.tex.needsUpdate = true;
      this.center.set(job.cx, job.cz);
      this.material.uniforms.uDepthCenter.value.copy(this.center);
      this.job = null;
    }
  }

  // force = bake everything right now (new world / first frame)
  rebake(px, pz, force = false) {
    const cx = Math.round(px / BAKE_SNAP) * BAKE_SNAP, cz = Math.round(pz / BAKE_SNAP) * BAKE_SNAP;
    this.job = { cx, cz, row: 0, buf: new Uint8Array(BAKE_RES * BAKE_RES) };
    if (force) this.bakeRows(this.job, Infinity);
  }

  update(px, pz, time) {
    this.material.uniforms.uTime.value = time;
    this.mesh.position.set(Math.round(px / 10) * 10, this.level, Math.round(pz / 10) * 10);
    if (!Number.isFinite(this.center.x)) this.rebake(px, pz, true);
    else if (!this.job && Math.max(Math.abs(px - this.center.x), Math.abs(pz - this.center.y)) > BAKE_SNAP * 1.5) this.rebake(px, pz);
    if (this.job) this.bakeRows(this.job, BAKE_MS);   // spread the bake over a few frames
  }
}

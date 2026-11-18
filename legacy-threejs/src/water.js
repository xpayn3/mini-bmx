import * as THREE from 'three';

// Tropical stylised water:
//  - small gerstner-ish waves in the vertex shader (damped near the shore)
//  - fine ripple normals, sun glints, sky fresnel
//  - depth-tinted lagoon colours with soft patches, fine wind ripples, a soft foam edge at the shore
//  - receives the sun's shadow
// Water depth comes from a small heightmap baked from terrain.height() around the player.

const BAKE_RES = 192;     // texels per side
const BAKE_SIZE = 128;    // metres covered
const BAKE_SNAP = 16;     // bake centre snaps to this grid
const BAKE_MS = 1.5;      // per-frame time budget for the background depth bake
const SHORE_MAX = 16;     // metres of shore distance stored in the bake

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
uniform vec3 uFoam;
uniform sampler2D uDepth;
uniform vec2 uDepthCenter;
uniform float uDepthSize;
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

// FINE WAVES: drifting noise octaves, each stretched across the wind so they read as little wave crests
// rather than blotches, and rotated so nothing lines up. Each octave fades out once its wavelength gets
// near a pixel (px = metres per pixel), so the fine ones never shimmer in the distance.
vec2 ripples(vec2 p, float t, float px) {
  vec2 g = vec2(0.0);
  float amp = 0.05, freq = 1.1;
  mat2 M = mat2(1.0);
  const mat2 ROT = mat2(0.80, -0.60, 0.60, 0.80);
  for (int i = 0; i < 6; i++) {
    M = ROT * M;
    float fi = float(i);
    vec2 wind = vec2(cos(fi * 0.45 + 0.3), sin(fi * 0.45 + 0.3));                 // roughly one wind direction
    vec2 drift = wind * t * (0.3 + 0.18 * fi);
    vec2 q = (M * p) * freq;
    q = vec2(q.x * 0.55, q.y) + drift + fi * 17.3;                                   // stretched: crests, not dots
    vec2 gq = noised(q).yz * vec2(0.55, 1.0);
    float fade = 1.0 - smoothstep(0.15, 0.45, freq * px);
    g += (gq * M) * amp * freq * fade;          // back to world space: transpose(M) * gq
    freq *= 1.85; amp *= 0.56;
  }
  return g;
}

void main() {
  float d = max(vDepth, 0.0);
  float dist = length(cameraPosition - vWorld);
  float px = length(fwidth(vWorld.xz));
  float shadow = getShadowMask();

  // normal: big swell from the vertex shader + fine waves
  vec2 rg = ripples(vWorld.xz, uTime, px);
  vec3 N = normalize(vWaveN + vec3(-rg.x, 0.0, -rg.y));
  vec3 V = normalize(cameraPosition - vWorld);
  vec3 L = normalize(uSunDir);

  // DEPTH COLOUR: light dies off with depth, red first -- aqua shallows, turquoise, then deep blue
  float t1 = exp(-d * 1.9), t2 = exp(-d * 0.55);
  vec3 col = mix(uDeep, uMid, t2);
  col = mix(col, uShallow, t1);
  // big soft patches so open water isn't one flat colour
  float tint = vnoise(vWorld.xz * 0.045 + 3.1) * 0.65 + vnoise(vWorld.xz * 0.11 - 7.7) * 0.35;
  col *= mix(0.93, 1.07, tint);
  col = mix(col, col * vec3(0.92, 1.04, 1.0), smoothstep(0.4, 0.8, tint) * 0.6);   // a touch greener in places

  // light: soft wrap diffuse, sun shadow, and a glow through the slopes of the waves
  float ndl = dot(N, L) * 0.5 + 0.5;
  col *= mix(0.64, 1.0, shadow) * (0.76 + 0.32 * ndl);
  float slopeK = clamp(length(N.xz) * 5.0, 0.0, 1.0);
  col += uShallow * slopeK * 0.10 * (0.4 + 0.6 * shadow) * (1.0 - t1 * 0.5);

  // sky reflection via fresnel: the fine waves show up here as tiny changes in what they reflect
  vec3 R = reflect(-V, N);
  vec3 sky = mix(uSkyHorizon, uSkyZenith, smoothstep(0.0, 0.65, R.y));
  float fres = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
  col = mix(col, sky, clamp(fres * 1.25, 0.0, 0.8));

  // sun: a broad soft sheen plus small glints off the fine waves
  vec3 H = normalize(L + V);
  float nh = max(dot(N, H), 0.0);
  float glintFade = 1.0 / (1.0 + dist * 0.025);
  col += uSunColor * (pow(nh, 60.0) * 0.18 + pow(nh, 700.0) * 2.2 * glintFade) * shadow;
  // soft sky sheen on the faces tilted toward the light: draws the shapes of the little waves
  col += sky * smoothstep(0.35, 1.0, dot(N, normalize(L + vec3(0.0, 1.5, 0.0)))) * 0.03 * slopeK;

  // SHORE WAVES: foam lines roll in along the real distance to the shore (baked), bunch up as they reach
  // the beach and break into lacy foam -- a crisp leading edge on the beach side, a soft frothy trail.
  // A slow along-shore wobble keeps them from being perfectly parallel.
  vec2 wp = vWorld.xz;
  vec2 suv = (wp - uDepthCenter) / uDepthSize + 0.5;
  float inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
  float sd = mix(99.0, texture2D(uDepth, suv).g * 16.0, inside);              // metres to the nearest beach
  float wob = vnoise(wp * 0.12 + 4.0) * 1.2 + vnoise(wp * 0.35 - 2.0) * 0.35;  // along-shore phase wobble
  float phase = pow(max(sd, 0.0), 0.8) / 1.8 + uTime * 0.28 + wob;           // lines crowd closer near the beach
  float s = fract(phase);
  float lace = vnoise(wp * 2.4 + vec2(uTime * 0.15, -uTime * 0.11)) * 0.6 + vnoise(wp * 6.5 - uTime * 0.2) * 0.4;
  // a thin, nearly unbroken foam line at the front of each wave...
  float line = smoothstep(0.0, 0.025, s) * (1.0 - smoothstep(0.045, 0.11, s)) * mix(0.7, 1.0, lace);
  // ...trailing a light, lacy froth out to sea
  float froth = smoothstep(0.04, 0.09, s) * (1.0 - smoothstep(0.1, 0.5, s)) * smoothstep(0.48, 0.78, lace) * 0.6;
  // only near the beach: grow as they come in, dissolve into the edge foam at the waterline
  float approach = (1.0 - smoothstep(1.0, 5.5, sd)) * smoothstep(0.02, 0.08, d);
  float waves = (line + froth) * approach * 0.85;
  // edge foam swells as each wave reaches the beach
  float arrive = smoothstep(0.75, 1.0, fract(uTime * 0.28 + wob));
  float n1 = vnoise(wp * 1.6 + uTime * 0.2), n2 = vnoise(wp * 4.5 - uTime * 0.3);
  float lip = 1.0 - smoothstep(0.0, 0.045 + n1 * 0.05 + arrive * 0.04, d);
  float foam = max(lip * mix(0.55, 1.0, n2), waves * 0.95);
  // the lifted face just behind each line catches a little more light
  float face = 1.0 - smoothstep(0.0, 0.3, s);
  col += uShallow * 0.07 * face * face * approach;
  col = mix(col, uFoam * mix(0.8, 1.02, shadow), foam * 0.85);

  // see-through in the shallows, soft contact with the shore
  float alpha = mix(0.55, 0.95, 1.0 - t2);
  alpha = max(alpha, foam * 0.85);
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
    // R = (virtual) depth, G = distance to the nearest shore -- what the shore waves roll in along
    this.data = new Uint8Array(BAKE_RES * BAKE_RES * 2);
    this.tex = new THREE.DataTexture(this.data, BAKE_RES, BAKE_RES, THREE.RGFormat, THREE.UnsignedByteType);
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
      this.packShore(job.buf, step);
      this.tex.needsUpdate = true;
      this.center.set(job.cx, job.cz);
      this.material.uniforms.uDepthCenter.value.copy(this.center);
      this.job = null;
    }
  }

  // distance from every water texel to the nearest land texel (two-pass chamfer transform, metres),
  // packed next to the depth: R = depth, G = shore distance (0..SHORE_MAX m)
  packShore(depthBuf, step) {
    const N = BAKE_RES, D = new Float32Array(N * N), INF = 1e9, R2 = Math.SQRT2;
    const LAND = Math.ceil((0 + 1) / 5 * 255);   // depth byte at d = 0
    for (let k = 0; k < N * N; k++) D[k] = depthBuf[k] <= LAND ? 0 : INF;
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const k = j * N + i; let v = D[k]; if (!v) continue;
      if (i > 0) v = Math.min(v, D[k - 1] + 1);
      if (j > 0) { v = Math.min(v, D[k - N] + 1); if (i > 0) v = Math.min(v, D[k - N - 1] + R2); if (i < N - 1) v = Math.min(v, D[k - N + 1] + R2); }
      D[k] = v;
    }
    for (let j = N - 1; j >= 0; j--) for (let i = N - 1; i >= 0; i--) {
      const k = j * N + i; let v = D[k]; if (!v) continue;
      if (i < N - 1) v = Math.min(v, D[k + 1] + 1);
      if (j < N - 1) { v = Math.min(v, D[k + N] + 1); if (i < N - 1) v = Math.min(v, D[k + N + 1] + R2); if (i > 0) v = Math.min(v, D[k + N - 1] + R2); }
      D[k] = v;
    }
    for (let k = 0; k < N * N; k++) {
      this.data[k * 2] = depthBuf[k];
      this.data[k * 2 + 1] = Math.min(255, (D[k] * step / SHORE_MAX) * 255);
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

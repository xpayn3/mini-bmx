// Bike finish effects:
//  * carPaint(): metallic flake car paint. Tiny flakes (a hash of the object-space position) tilt the
//    base layer's normal so the paint glitters in the highlights, under a smooth, glossy clearcoat.
//  * RotorGlow: brake discs that heat up and glow from the braking track outwards (red -> orange ->
//    yellow), driven by how much energy the brakes have soaked up.
import * as THREE from 'three';

const HASH = /* glsl */`
vec3 flakeHash(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}`;

// mat: a MeshPhysicalMaterial (kept: colour, env map). flake: flake size in m; sparkle: 0..1 strength
export function carPaint(mat, { flake = 0.0016, sparkle = 0.22, metalness = 0.55, roughness = 0.34 } = {}) {
  if (mat.userData.carPaint) return mat;
  mat.userData.carPaint = true;
  mat.metalness = metalness; mat.roughness = roughness;   // base coat: metallic, a little soft (flakes do the sparkle)
  mat.clearcoat = 1; mat.clearcoatRoughness = 0.03;          // glassy lacquer on top
  mat.envMapIntensity = 1.3;
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uFlake = { value: 1 / flake };
    sh.uniforms.uSparkle = { value: sparkle };
    sh.vertexShader = 'varying vec3 vFlakeP;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvFlakeP = position;');
    sh.fragmentShader = 'varying vec3 vFlakeP;\nuniform float uFlake;\nuniform float uSparkle;\n' + HASH + '\n' +
      sh.fragmentShader.replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
      {
        vec3 fp = vFlakeP * uFlake;
        vec3 h = flakeHash(floor(fp)) * 2.0 - 1.0;
        // fade the flakes out where one pixel covers many of them (far away): no shimmering noise
        float aa = clamp(1.3 - length(fwidth(fp)) * 0.9, 0.0, 1.0);
        normal = normalize(normal + h * uSparkle * aa);
        // a few flakes catch the light hard: tiny bright glints that twinkle as the bike moves
        vec3 vdir = normalize(vViewPosition);
        float glint = pow(max(0.0, dot(reflect(vdir, normal), normalize(vec3(0.3, 0.9, 0.3)))), 60.0);
        flakeGlint = glint * step(0.9, flakeHash(floor(fp) + 7.0).x) * aa;
        // metallic flop: the colour goes deep and dark where the tube turns away from you
        float facing = clamp(dot(normalize(-vViewPosition), normal), 0.0, 1.0);
        diffuseColor.rgb *= mix(0.62, 1.1, pow(facing, 0.6));
      }`).replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        totalEmissiveRadiance += diffuseColor.rgb * flakeGlint * 2.0 + vec3(flakeGlint * 0.6);`);
    sh.fragmentShader = sh.fragmentShader.replace('void main() {', `void main() {
  float flakeGlint = 0.0;`);
  };
  mat.customProgramCacheKey = () => 'carPaint';
  mat.needsUpdate = true;
  return mat;
}

// Finds the disc rotor in a wheel node (a thin flat slab of verts, 6-15 cm radius, off-centre in Z),
// moves its triangles into their own mesh and gives it a heat-glow material. Returns null if none.
export class RotorGlow {
  static find(wheel) {
    let best = null;
    wheel.traverse((m) => {
      if (!m.isMesh || !m.geometry.attributes.position) return;
      const p = m.geometry.attributes.position, slabs = new Map();
      for (let i = 0; i < p.count; i++) {
        const z = Math.round(p.getZ(i) * 200) / 200, r = Math.hypot(p.getX(i), p.getY(i));
        if (Math.abs(z) < 0.02 || r > 0.15) continue;
        const s = slabs.get(z) || { n: 0, r: 0 }; s.n++; s.r = Math.max(s.r, r); slabs.set(z, s);
      }
      for (const [z, s] of slabs) if (s.n > 50 && s.r > 0.06 && (!best || s.n > best.n)) best = { mesh: m, z, n: s.n, r: s.r };
    });
    return best ? new RotorGlow(best) : null;
  }

  constructor({ mesh, z, r }) {
    const g = mesh.geometry, P = g.attributes.position;
    const idx = g.index ? g.index.array : Array.from({ length: P.count }, (_, i) => i);
    const on = (i) => Math.abs(P.getZ(i) - z) < 0.006 && Math.hypot(P.getX(i), P.getY(i)) < r + 0.004;
    const keep = [], disc = [];
    for (let t = 0; t < idx.length; t += 3) {
      const a = idx[t], b = idx[t + 1], c = idx[t + 2];
      (on(a) && on(b) && on(c) ? disc : keep).push(a, b, c);
    }
    g.setIndex(keep);
    const dg = g.clone(); dg.setIndex(disc);
    this.uHeat = { value: 0 };
    const mat = mesh.material.clone();
    mat.name = 'rotor';
    mat.userData.heat = this.uHeat;   // (debug handle)
    const uHeat = this.uHeat, r0 = r * 0.7, r1 = r * 0.86;
    mat.onBeforeCompile = (sh) => {
      sh.uniforms.uHeat = uHeat;
      sh.vertexShader = 'varying float vRotorR;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvRotorR = length(position.xy);');
      sh.fragmentShader = 'varying float vRotorR;\nuniform float uHeat;\n' + sh.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
      {
        // the pads ride on the outer band: it heats first and hottest, the glow creeping inwards as it builds
        float band = smoothstep(${r0.toFixed(4)} + 0.012 * (1.0 - uHeat), ${r1.toFixed(4)}, vRotorR);
        float h = uHeat * band;
        vec3 col = mix(vec3(0.5, 0.015, 0.0), vec3(1.0, 0.16, 0.01), smoothstep(0.2, 0.7, h));
        col = mix(col, vec3(1.0, 0.42, 0.08), smoothstep(0.8, 1.0, h));
        diffuseColor.rgb *= 1.0 - 0.6 * h;   // hot steel loses its shine to the glow
        totalEmissiveRadiance += col * h * (0.4 + 1.6 * h);
      }`);
    };
    mat.customProgramCacheKey = () => 'rotorGlow';
    this.mesh = new THREE.Mesh(dg, mat);
    this.mesh.castShadow = true;
    mesh.add(this.mesh);
  }

  // heat: 0 cold .. 1 glowing hot
  set(heat) { this.uHeat.value = Math.min(1, Math.max(0, heat)); }
}

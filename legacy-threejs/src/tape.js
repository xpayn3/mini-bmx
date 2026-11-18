import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Race course tape: thin plastic foil strung between stakes along both sides of the main downhill.
// Intact spans are static geometry animated in the vertex shader (they bow downwind and flutter with
// the gusts). Ride through one and it SNAPS: the span is hidden and replaced by two light Verlet
// ribbons that stream and float in the wind from their stakes -- or, now and then, rip off the stake
// completely and blow away across the hills.

export const WIND = { dir: new THREE.Vector3(0.8, 0, 0.6).normalize(), speed: 4, gust: 1, t: 0 };
const SEG = 30, WIDTH = 0.075, TAPE_H = 0.85;
const RED = new THREE.Color(0xe8322b), WHITE = new THREE.Color(0xf6f5ef), YEL = new THREE.Color(0xf5c518), BLK = new THREE.Color(0x26241f);
const uTime = { value: 0 }, uWind = { value: new THREE.Vector3() }, uPh = { value: 0 };   // uPh: flutter phase, integrated (see update)

export const TAPE_MAT = new THREE.MeshStandardMaterial({ vertexColors: true, side: THREE.DoubleSide, roughness: 0.42, metalness: 0.05 });
TAPE_MAT.onBeforeCompile = (sh) => {
  sh.uniforms.uTime = uTime; sh.uniforms.uWind = uWind; sh.uniforms.uPh = uPh;
  sh.vertexShader = sh.vertexShader
    .replace('#include <common>', '#include <common>\nattribute vec3 aSide; attribute vec3 aFl; attribute vec3 aVar; attribute float aAlive; uniform float uTime; uniform float uPh; uniform vec3 uWind;')
    .replace('#include <begin_vertex>', `#include <begin_vertex>
      // aFl: x = 0 at the stakes .. 1 mid-span, y = phase, z = +1 top edge / -1 bottom edge
      float ws = length(uWind);
      float push = dot(uWind, aSide);                                   // wind across the tape bows it
      // aVar (per span): x = speed, y = ripple length, z = twist -- so no two spans move alike
      // the flutter phase is integrated on the CPU (faster in gusts) -- never time * windspeed, which
      // jumps whenever the wind changes
      float tt = uTime * aVar.x, pp = uPh * aVar.x, ph = aFl.y * aVar.y;
      float wave = sin(pp - ph) * 0.55 + sin(pp * 1.53 - ph * 1.9 + aVar.z * 4.0) * 0.3
                 + sin(tt * 2.2 - ph * 0.45 + aVar.y * 7.0) * 0.35;
      float gust = 0.7 + 0.3 * sin(uTime * 0.9 * aVar.x + aVar.z * 9.0);
      float amp = aFl.x * (0.025 + 0.012 * ws) * gust;
      // twist: top and bottom edge swing opposite ways around the centre line, by a varying angle
      float tw = sin(pp * 0.4 - ph * 0.8 + aVar.y * 3.0) * aVar.z;
      transformed += aSide * (aFl.x * push * 0.035 * gust + amp * wave + aFl.x * aFl.z * 0.0375 * sin(tw));
      transformed.y += aFl.x * (0.012 * ws * sin(pp * 0.7 - ph * 0.7) - 0.02) - aFl.x * aFl.z * 0.0375 * (1.0 - cos(tw));
      transformed *= aAlive;`);
};

const STAKE_MAT = new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.6 });
const paint = (g, c) => { g = g.toNonIndexed(); g.deleteAttribute('uv'); const n = g.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) c.toArray(a, i * 3); g.setAttribute('color', new THREE.BufferAttribute(a, 3)); return g; };
const stakeGeo = mergeGeometries([   // thin white fibreglass stake with an orange cap, 0.2 m in the ground
  paint(new THREE.CylinderGeometry(0.018, 0.022, 1.15, 5).translate(0, 0.575 - 0.2, 0), new THREE.Color(0xe9e6dc)),
  paint(new THREE.CylinderGeometry(0.024, 0.024, 0.12, 5).translate(0, 0.9, 0), new THREE.Color(0xff6a1a)),
]);

// ---------------- placement: called by Terrain.buildGen for one chunk ----------------
export function buildTape(T, cx, cz, S, colliders) {
  // the stakes are planned with the course (course.js): both sides through technical sections and jump
  // lines, funnelling in and out of them, and round the outside of the road's tighter bends. A chunk
  // plants the stakes standing in it and strings each one back to the stake before it.
  const plant = (st) => {
    if (Math.hypot(st.x, st.z) < 10) return null;
    const h = T.height(st.x, st.z);
    if (h < -1.9 || T.jump(st.x, st.z)[0] > 0.05) return null;
    return { x: st.x, z: st.z, h };
  };
  const spans = [], stakes = [];
  T.course.stakes.forEach((st, k) => {
    if (Math.round(st.x / S) !== cx || Math.round(st.z / S) !== cz) return;
    const b = plant(st); if (!b) return;
    stakes.push(b);
    const a = st.prev && plant(st.prev);
    if (!a || Math.abs(b.h - a.h) > 2) return;
    spans.push({ a, b, k, side: st.side, cols: st.caution ? [YEL, BLK] : [RED, WHITE] });
  });
  if (!spans.length && !stakes.length) return [];
  const out = [];
  if (stakes.length) {
    const im = new THREE.InstancedMesh(stakeGeo, STAKE_MAT, stakes.length), m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
    stakes.forEach((s, i) => {
      const r = Math.sin(s.x * 12.9 + s.z * 78.2) * 0.04;
      im.setMatrixAt(i, m.compose(new THREE.Vector3(s.x, s.h, s.z), q.setFromEuler(e.set(r, 0, -r)), new THREE.Vector3(1, 1, 1)));
    });
    im.castShadow = true; im.receiveShadow = true; im.computeBoundingSphere();
    out.push(im);
  }
  if (!spans.length) return out;
  const nv = spans.length * SEG * 6;
  const pos = new Float32Array(nv * 3), nrm = new Float32Array(nv * 3), col = new Float32Array(nv * 3),
    side = new Float32Array(nv * 3), fl = new Float32Array(nv * 3), vr = new Float32Array(nv * 3), alive = new Float32Array(nv).fill(1);
  let v = 0;
  for (const sp of spans) {
    const { a, b } = sp, dx = b.x - a.x, dz = b.z - a.z, L = Math.hypot(dx, dz), sx = -dz / L, sz = dx / L;
    const ya = a.h + TAPE_H, yb = b.h + TAPE_H, phase0 = (sp.k * 1.7 + sp.side) % 6.28;
    const hr = (n) => { const v = Math.sin(sp.k * 127.1 + sp.side * 311.7 + n * 74.7) * 43758.5453; return v - Math.floor(v); };
    const varS = 0.6 + hr(1) * 0.6, varL = 0.6 + hr(2) * 1.1, varT = 0.3 + hr(3) * 1.4;   // speed, ripple length, twist
    sp.pts = [];
    for (let i = 0; i <= SEG; i++) {
      const t = i / SEG, x = a.x + dx * t, z = a.z + dz * t;
      let y = ya + (yb - ya) * t - Math.sin(Math.PI * t) * (0.1 + hr(4) * 0.08);   // longer spans sag more
      y = Math.max(y, T.height(x, z) + 0.35);
      sp.pts.push(new THREE.Vector3(x, y, z));
    }
    sp.v0 = v; sp.len = L;
    for (let i = 0; i < SEG; i++) {
      const p0 = sp.pts[i], p1 = sp.pts[i + 1], c = sp.cols[i & 1], t0 = i / SEG, t1 = (i + 1) / SEG;
      const corner = [[p0, t0, 1], [p0, t0, -1], [p1, t1, 1], [p1, t1, 1], [p0, t0, -1], [p1, t1, -1]];
      for (const [p, t, edge] of corner) {
        pos[v * 3] = p.x; pos[v * 3 + 1] = p.y + edge * WIDTH / 2; pos[v * 3 + 2] = p.z;
        nrm[v * 3] = sx; nrm[v * 3 + 2] = sz;
        c.toArray(col, v * 3);
        side[v * 3] = sx; side[v * 3 + 2] = sz;
        fl[v * 3] = Math.sin(Math.PI * t); fl[v * 3 + 1] = phase0 + t * L * 1.6; fl[v * 3 + 2] = edge;
        vr[v * 3] = varS; vr[v * 3 + 1] = varL; vr[v * 3 + 2] = varT;
        v++;
      }
    }
    sp.broken = false;
    const n = Math.ceil(L / 0.4);
    for (let i = 0; i <= n; i++) {
      const p = sp.pts[Math.round(i / n * SEG)];
      colliders.push({ x: p.x, z: p.z, r: 0.12, tape: sp, ceil: p.y + 0.1 });
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aSide', new THREE.BufferAttribute(side, 3));
  g.setAttribute('aFl', new THREE.BufferAttribute(fl, 3));
  g.setAttribute('aVar', new THREE.BufferAttribute(vr, 3));
  g.setAttribute('aAlive', new THREE.BufferAttribute(alive, 1));
  g.computeBoundingSphere(); g.boundingSphere.radius += 1;
  const mesh = new THREE.Mesh(g, TAPE_MAT);
  mesh.receiveShadow = true; mesh.frustumCulled = true;
  for (const sp of spans) sp.mesh = mesh;
  out.push(mesh);
  return out;
}

// ---------------- torn tape: light foil ribbons simulated with Verlet ----------------
const MAX_STRIPS = 40, SUB = 3, ITER = 6;
const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _d = new THREE.Vector3(), _w = new THREE.Vector3(), _n = new THREE.Vector3();
const UP = new THREE.Vector3(0, 1, 0);

export class TapeSim {
  constructor(scene, terrain) { this.scene = scene; this.T = terrain; this.strips = []; }
  clear() { while (this.strips.length) this.drop(this.strips[0]); }
  drop(s) { this.scene.remove(s.mesh); s.mesh.geometry.dispose(); this.strips.splice(this.strips.indexOf(s), 1); }

  // the bike (velocity vx, vy, vz) hit span `sp` near (hx, hz): tear it there
  snap(sp, hx, hz, vx, vy, vz) {
    if (sp.broken) return false;
    sp.broken = true;
    const al = sp.mesh.geometry.attributes.aAlive;
    al.array.fill(0, sp.v0, sp.v0 + SEG * 6); al.needsUpdate = true;
    let bi = 1, bd = Infinity;   // tear at the point nearest the hit
    for (let i = 1; i < SEG; i++) { const d = Math.hypot(sp.pts[i].x - hx, sp.pts[i].z - hz); if (d < bd) { bd = d; bi = i; } }
    const seg = sp.len / SEG;
    // each half: points from its stake to the tear; sometimes it rips off the stake and flies free
    const halves = [sp.pts.slice(0, bi + 1), sp.pts.slice(bi).reverse()];
    halves.forEach((pts, h) => {
      if (pts.length < 2) return;
      const free = Math.random() < 0.25;
      const cols = pts.slice(0, -1).map((_, i) => sp.cols[(h ? SEG - 1 - i : i) & 1]);
      const n = pts.length, P = pts.map((p) => p.clone()), Q = pts.map((p) => p.clone());
      for (let i = 0; i < n; i++) {   // the end near the hit is dragged along with the bike
        const near = i / (n - 1), k = near * near;
        Q[i].x -= (vx * 0.55 * k + (Math.random() - .5) * 0.6 * k) / 60;
        Q[i].y -= (Math.max(0, vy) * 0.3 * k + (0.6 + Math.random()) * k) / 60;
        Q[i].z -= (vz * 0.55 * k + (Math.random() - .5) * 0.6 * k) / 60;
      }
      this.add(P, Q, cols, seg, free ? null : pts[0].clone());
    });
    return true;
  }
  add(P, Q, cols, seg, pin) {
    while (this.strips.length >= MAX_STRIPS) this.drop(this.strips[0]);
    const n = P.length, nv = (n - 1) * 6;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(nv * 3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(nv * 3), 3));
    const c = new Float32Array(nv * 3);
    for (let i = 0; i < n - 1; i++) for (let k = 0; k < 6; k++) cols[i].toArray(c, (i * 6 + k) * 3);
    g.setAttribute('color', new THREE.BufferAttribute(c, 3));
    const mesh = new THREE.Mesh(g, STRIP_MAT); mesh.frustumCulled = false; mesh.receiveShadow = true;
    this.scene.add(mesh);
    const R = Math.random;
    this.strips.push({ P, Q, seg, pin, mesh, age: 0, tw: P.map(() => R() * 6.28), last: 1 / 60,
      // each strip twists its own way: rate, how quickly the twist turns along it, how far, a slow drift
      tr: 1.5 + R() * 5, tk: 0.1 + R() * 0.6, ta: 0.5 + R() * 1.4, td: (R() - .5) * 1.2, tp: R() * 6.28 });
  }

  update(dt, px, pz) {
    WIND.t += dt;
    // gusty wind: slowly turning direction, speed swelling between ~2 and ~8 m/s
    const t = WIND.t, ang = Math.atan2(0.6, 0.8) + Math.sin(t * 0.05) * 0.8 + Math.sin(t * 0.21) * 0.25;
    WIND.gust = 0.55 + 0.45 * (0.5 + 0.5 * Math.sin(t * 0.7) * Math.sin(t * 0.31 + 1.3)) + 0.25 * Math.max(0, Math.sin(t * 1.9) * Math.sin(t * 0.45));
    WIND.dir.set(Math.cos(ang), 0, Math.sin(ang));
    const ws = WIND.speed * WIND.gust * 1.5;
    uTime.value = t; uWind.value.copy(WIND.dir).multiplyScalar(ws);
    uPh.value += dt * (4.5 + ws * 0.7);   // flutter rate follows the wind smoothly
    const T = this.T, h = dt / SUB;
    for (let si = this.strips.length - 1; si >= 0; si--) {
      const s = this.strips[si];
      s.age += dt;
      const far = Math.hypot(s.P[0].x - px, s.P[0].z - pz);
      if (far > 180 || (!s.pin && s.age > 40)) { this.drop(s); continue; }
      if (far > 90) continue;   // out of sight: freeze
      const n = s.P.length, ratio = h / s.last; s.last = h;
      const G = s.G || (s.G = new Float32Array(n));
      for (let i = 0; i < n; i++) G[i] = T.height(s.P[i].x, s.P[i].z);   // once a frame (height() is costly)
      for (let sub = 0; sub < SUB; sub++) {
        for (let i = 0; i < n; i++) {
          const p = s.P[i], q = s.Q[i];
          // foil: tiny mass, huge drag -- it moves towards the local wind velocity instead of falling.
          // Each point sees its own turbulent wind, so the ribbon ripples and flaps.
          const tu = t * 3 + i * 0.55 + s.tw[0];
          _w.copy(WIND.dir).multiplyScalar(ws * (0.8 + 0.35 * Math.sin(tu * 1.7)));
          _w.x += Math.sin(tu * 2.3 + i) * ws * 0.35; _w.z += Math.cos(tu * 2.9 - i) * ws * 0.35;
          const alt = Math.min(1, Math.max(0, 1 - (p.y - G[i]) / 9));   // soars, but tops out ~9 m up
          _w.y = ws * (0.16 * alt + 0.3 * Math.sin(tu * 1.3 + i * 0.7));   // lift: foil floats and soars   // lift: foil floats and soars
          const vx = (p.x - q.x) / h * (sub === 0 ? ratio : 1), vy = (p.y - q.y) / h * (sub === 0 ? ratio : 1), vz = (p.z - q.z) / h * (sub === 0 ? ratio : 1);
          const drag = 3.2, ax = (_w.x - vx) * drag, ay = (_w.y - vy) * drag - 9.81 * 0.35, az = (_w.z - vz) * drag;
          q.copy(p);
          p.x += vx * h + ax * h * h; p.y += vy * h + ay * h * h; p.z += vz * h + az * h * h;
        }
        for (let it = 0; it < ITER; it++) {
          if (s.pin) s.P[0].copy(s.pin);
          for (let i = 0; i < n - 1; i++) {
            const a = s.P[i], b = s.P[i + 1];
            _d.subVectors(b, a); const l = _d.length() || 1e-6, diff = (l - s.seg) / l;
            const wa = s.pin && i === 0 ? 0 : 0.5, wb = s.pin && i === 0 ? 1 : 0.5;
            a.addScaledVector(_d, diff * wa); b.addScaledVector(_d, -diff * wb);
          }
        }
        if (s.pin) s.P[0].copy(s.pin);
        // the ground: rest on it with friction (it can still lift off when a gust gets under it)
        for (let i = 0; i < n; i++) {
          const p = s.P[i], g = G[i] + 0.01;
          if (p.y < g) { p.y = g; const q = s.Q[i]; q.x += (p.x - q.x) * 0.5; q.z += (p.z - q.z) * 0.5; q.y = p.y; }
        }
      }
      this.mesh(s, t);
    }
  }
  // ribbon geometry: the width direction twists slowly along the strip, like real foil tape
  mesh(s, t) {
    const n = s.P.length, pos = s.mesh.geometry.attributes.position, nrm = s.mesh.geometry.attributes.normal, W = WIDTH / 2;
    const E = [];
    for (let i = 0; i < n; i++) {
      const a = s.P[Math.max(0, i - 1)], b = s.P[Math.min(n - 1, i + 1)];
      _d.subVectors(b, a).normalize();
      _a.crossVectors(_d, UP); if (_a.lengthSq() < 1e-4) _a.set(1, 0, 0); _a.normalize();
      _b.crossVectors(_a, _d);
      const tw = Math.sin(s.tp + t * s.tr - i * s.tk) * s.ta + Math.sin(t * s.tr * 0.37 + i * s.tk * 2.3 + s.tw[i] * 0.15) * s.ta * 0.5 + i * s.td * 0.2 + t * s.td;
      E.push(_b.clone().multiplyScalar(Math.cos(tw) * W).addScaledVector(_a, Math.sin(tw) * W));
    }
    let v = 0;
    for (let i = 0; i < n - 1; i++) {
      const p0 = s.P[i], p1 = s.P[i + 1], e0 = E[i], e1 = E[i + 1];
      _n.subVectors(p1, p0).cross(e0).normalize();
      const quad = [[p0, e0, 1], [p0, e0, -1], [p1, e1, 1], [p1, e1, 1], [p0, e0, -1], [p1, e1, -1]];
      for (const [p, e, sgn] of quad) {
        pos.setXYZ(v, p.x + e.x * sgn, p.y + e.y * sgn, p.z + e.z * sgn); nrm.setXYZ(v, _n.x, _n.y, _n.z); v++;
      }
    }
    pos.needsUpdate = true; nrm.needsUpdate = true;
  }
}
const STRIP_MAT = new THREE.MeshStandardMaterial({ vertexColors: true, side: THREE.DoubleSide, roughness: 0.42, metalness: 0.05 });

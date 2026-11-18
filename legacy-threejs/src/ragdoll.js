import * as THREE from 'three';
import { WATER } from './terrain.js';

// Verlet-particle ragdoll for the rider. Works in world space.
// Joint order matches Rider.jointsLocal():
export const J = { HEAD: 0, CHEST: 1, PELVIS: 2, SH_L: 3, EL_L: 4, HA_L: 5, SH_R: 6, EL_R: 7, HA_R: 8,
  HIP_L: 9, KN_L: 10, FT_L: 11, HIP_R: 12, KN_R: 13, FT_R: 14 };
const RAD = [0.2, 0.15, 0.12, 0.08, 0.06, 0.06, 0.08, 0.06, 0.06, 0.08, 0.07, 0.07, 0.08, 0.07, 0.07];

// [a, b, stiffness] rigid-ish bones; the torso is cross-braced so it keeps its shape
const BONES = [
  [J.HEAD, J.CHEST, 1], [J.HEAD, J.SH_L, 0.6], [J.HEAD, J.SH_R, 0.6], [J.HEAD, J.PELVIS, 0.4],
  [J.CHEST, J.PELVIS, 1], [J.CHEST, J.SH_L, 1], [J.CHEST, J.SH_R, 1], [J.SH_L, J.SH_R, 1],
  [J.PELVIS, J.HIP_L, 1], [J.PELVIS, J.HIP_R, 1], [J.HIP_L, J.HIP_R, 1],
  [J.SH_L, J.HIP_L, 1], [J.SH_R, J.HIP_R, 1], [J.SH_L, J.HIP_R, 0.8], [J.SH_R, J.HIP_L, 0.8],
  [J.SH_L, J.EL_L, 1], [J.EL_L, J.HA_L, 1], [J.SH_R, J.EL_R, 1], [J.EL_R, J.HA_R, 1],
  [J.HIP_L, J.KN_L, 1], [J.KN_L, J.FT_L, 1], [J.HIP_R, J.KN_R, 1], [J.KN_R, J.FT_R, 1],
];
// [a, b, minFraction of rest length] soft joint limits: stop limbs folding flat onto themselves
const LIMITS = [
  [J.SH_L, J.HA_L, 0.45], [J.SH_R, J.HA_R, 0.45], [J.HIP_L, J.FT_L, 0.5], [J.HIP_R, J.FT_R, 0.5],
  [J.KN_L, J.CHEST, 0.6], [J.KN_R, J.CHEST, 0.6], [J.HA_L, J.HA_R, 0.15], [J.KN_L, J.KN_R, 0.15], [J.FT_L, J.FT_R, 0.15],
];

const _d = new THREE.Vector3();
const SUB = 3;   // substeps per frame

export class Ragdoll {
  constructor(terrain) {
    this.terrain = terrain;
    this.p = RAD.map(() => new THREE.Vector3());
    this.q = RAD.map(() => new THREE.Vector3());   // previous positions
    this.rest = BONES.map(() => 0);
    this.lim = LIMITS.map(() => 0);
    this.active = false;
    this.speed = 0;
  }

  // pts: world joint positions; vel: world velocity of the body; spin: extra velocity per unit height above pelvis
  start(pts, vel, spin, dt = 1 / 60) {
    for (let i = 0; i < this.p.length; i++) {
      this.p[i].copy(pts[i]);
      const h = pts[i].y - pts[J.PELVIS].y;
      _d.copy(vel).addScaledVector(spin, h).addScaledVector(new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5), 0.6);
      this.q[i].copy(pts[i]).addScaledVector(_d, -dt / SUB);   // Verlet velocity is per substep
    }
    BONES.forEach(([a, b], k) => { this.rest[k] = pts[a].distanceTo(pts[b]); });
    LIMITS.forEach(([a, b, f], k) => { this.lim[k] = pts[a].distanceTo(pts[b]) * f; });
    // make sure the knees/hands keep some rest spacing even if they started touching
    this.lim[6] = Math.max(this.lim[6], 0.12); this.lim[7] = Math.max(this.lim[7], 0.14); this.lim[8] = Math.max(this.lim[8], 0.14);
    this.active = true;
    this.lastH = dt / SUB;   // substep the seeded displacements (p - q) were made with
  }

  step(dt, colliders) {
    const n = SUB, h = dt / n, T = this.terrain;
    // time-corrected Verlet: p - q is a displacement over the previous substep, so rescale it to
    // this substep's length -- otherwise the fling and the tumble speed change with the frame rate
    const ratio = h / (this.lastH || h);
    this.lastH = h;
    let sp = 0;
    // collision shapes that match what you see: rocks are domes (ellipsoids sitting in the ground),
    // trunks / cacti are thin vertical cylinders at their visible width (the game's colliders are fatter
    // cylinders of infinite height, tuned for the bike -- for a flying body those act as invisible walls)
    const shapes = this.shapes || (this.shapes = []);
    shapes.length = 0;
    for (const c of colliders) {
      if (c.tape) continue;   // course tape: the body just tears through it (main.js snaps it)
      if (c.top !== undefined) {
        const base = T.height(c.x, c.z) - 0.15;
        shapes.push({ rock: true, x: c.x, z: c.z, y: base, R: c.r * 0.9, H: Math.max(0.1, c.top - base) });
      } else shapes.push({ rock: false, x: c.x, z: c.z, R: Math.max(0.08, (c.r - 0.1) * 0.6) });
    }
    for (let s = 0; s < n; s++) {
      // integrate
      for (let i = 0; i < this.p.length; i++) {
        const p = this.p[i], q = this.q[i];
        const wet = p.y < WATER;
        const damp = (wet ? 0.94 : 0.998) * (s === 0 ? ratio : 1);
        const vx = (p.x - q.x) * damp, vy = (p.y - q.y) * damp, vz = (p.z - q.z) * damp;
        q.copy(p);
        p.x += vx; p.y += vy - (wet ? 2.0 : 9.81) * h * h; p.z += vz;
      }
      // constraints
      for (let it = 0; it < 6; it++) {
        BONES.forEach(([a, b, k], j) => this.dist(a, b, this.rest[j], k, false));
        LIMITS.forEach(([a, b], j) => this.dist(a, b, this.lim[j], 1, true));
        for (let i = 0; i < this.p.length; i++) this.collide(i, T, shapes);
      }
    }
    for (let i = 0; i < this.p.length; i++) sp = Math.max(sp, this.p[i].distanceTo(this.q[i]) / h);
    this.speed = sp;
  }

  dist(a, b, len, k, minOnly) {
    const A = this.p[a], B = this.p[b];
    _d.subVectors(B, A);
    const l = _d.length();
    if (l < 1e-6 || (minOnly && l >= len)) return;
    const c = (l - len) / l * 0.5 * k;
    A.addScaledVector(_d, c); B.addScaledVector(_d, -c);
  }

  collide(i, T, colliders) {
    const p = this.p[i], q = this.q[i], r = RAD[i];
    const g = T.height(p.x, p.z) + r;
    if (p.y < g) {
      p.y = g;
      // ground friction: kill most of the sliding velocity (dirt / grass tumble)
      const f = 0.12;
      q.x += (p.x - q.x) * f; q.z += (p.z - q.z) * f;
      if (q.y < p.y - 0.02) q.y = p.y - (p.y - q.y) * 0.3;   // small bounce
    }
    for (const c of colliders) {
      const dx = p.x - c.x, dz = p.z - c.z;
      if (c.rock) {
        // ellipsoid (dome) push-out, along the scaled-space normal
        const R = c.R + r, H = c.H + r, dy = p.y - c.y;
        if (dy < -r) continue;
        const k = Math.hypot(dx / R, dy / H, dz / R);
        if (k >= 1 || k < 1e-4) continue;
        p.x = c.x + dx / k; p.y = c.y + dy / k; p.z = c.z + dz / k;
        q.x += (p.x - q.x) * 0.1; q.z += (p.z - q.z) * 0.1;   // rough rock: a bit of friction
      } else {
        const d = Math.hypot(dx, dz), m = c.R + r * 0.6;
        if (d < m && d > 1e-4) { p.x = c.x + dx / d * m; p.z = c.z + dz / d * m; }
      }
    }
  }
}

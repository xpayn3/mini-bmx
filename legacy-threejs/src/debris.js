import * as THREE from 'three';
import { WATER } from './terrain.js';

// Rigid-body debris: oriented boxes (fence posts, rails, pickets) with real rotation, impulse-based
// contacts against the terrain at their 8 corners (bounce + friction, so they tumble, roll and slide
// down slopes), buoyancy in water (wood floats), sleeping, and a slow sink-and-fade cleanup.
const MAX = 160, G = 9.81, SUB = 2;
const _v = new THREE.Vector3(), _r = new THREE.Vector3(), _c = new THREE.Vector3(), _n = new THREE.Vector3(),
  _t = new THREE.Vector3(), _a = new THREE.Vector3(), _b = new THREE.Vector3(), _dq = new THREE.Quaternion(),
  _m3 = new THREE.Matrix3(), _rt = new THREE.Matrix3(), _m4 = new THREE.Matrix4();
const CORNERS = [];
for (const x of [-1, 1]) for (const y of [-1, 1]) for (const z of [-1, 1]) CORNERS.push(new THREE.Vector3(x, y, z));

export class Debris {
  constructor(scene, terrain) {
    this.scene = scene; this.terrain = terrain; this.list = [];
  }
  // geo: centred geometry; scale: per-axis scale applied to it; vel/ang: world linear / angular velocity
  spawn(geo, material, color, pos, quat, scale, vel, ang) {
    if (!geo.boundingBox) geo.computeBoundingBox();
    const half = geo.boundingBox.getSize(new THREE.Vector3()).multiply(scale).multiplyScalar(0.5);
    const mat = material.clone(); mat.color.setHex(color);    // own material: its opacity fades at the end
    const mesh = new THREE.Mesh(geo, mat);
    mesh.castShadow = true; mesh.receiveShadow = true; mesh.matrixAutoUpdate = false;
    const m = 8 * half.x * half.y * half.z * 550;   // ~pine
    // inertia from slightly fattened dimensions: real thin planks have so little roll inertia about
    // their long axis that corner contacts make them chatter; this keeps them calm without looking off
    const hx = Math.max(half.x, 0.12), hy = Math.max(half.y, 0.12), hz = Math.max(half.z, 0.12);
    const b = {
      mesh, half, scale: scale.clone(), pos: pos.clone(), q: quat.clone(), v: vel.clone(), w: ang.clone(),
      im: 1 / m, iI: new THREE.Vector3(3 / (m * (hy * hy + hz * hz)), 3 / (m * (hx * hx + hz * hz)), 3 / (m * (hx * hx + hy * hy))),
      sleep: 0, age: 0, rest: 0, fade: 1,
    };
    this.scene.add(mesh);
    this.list.push(b);
    while (this.list.length > MAX) this.remove(this.list[0]);
    this.sync(b);
    return b;
  }
  remove(b) {
    this.scene.remove(b.mesh); b.mesh.material.dispose();
    const i = this.list.indexOf(b); if (i >= 0) this.list.splice(i, 1);
  }
  clear() { while (this.list.length) this.remove(this.list[0]); }
  sync(b) { b.mesh.matrix.compose(b.pos, b.q, b.scale); }

  // world inverse inertia: R diag(iI) R^T, applied to vector x (in place)
  invI(b, x) {
    _rt.setFromMatrix4(_m4.makeRotationFromQuaternion(b.q));
    x.applyMatrix3(_m3.copy(_rt).transpose()).multiply(b.iI).applyMatrix3(_rt);
    return x;
  }
  impulse(b, r, j) {   // apply world impulse j at offset r from the centre of mass
    b.v.addScaledVector(j, b.im);
    b.w.add(this.invI(b, _a.crossVectors(r, j)));
  }
  // effective mass along direction d at offset r
  kAlong(b, r, d) { return b.im + d.dot(_b.crossVectors(this.invI(b, _a.crossVectors(r, d)), r)); }

  // something ran into the pieces lying around: knock them along (x, y, z = where; vx, vz = its velocity)
  kick(x, y, z, vx, vz, rad = 0.7) {
    const sp = Math.hypot(vx, vz); if (sp < 1.5) return;
    for (const b of this.list) {
      const dx = b.pos.x - x, dz = b.pos.z - z;
      if (dx * dx + dz * dz > rad * rad || Math.abs(b.pos.y - y) > 1) continue;
      if (b.v.x * vx + b.v.z * vz > sp * sp * 0.8) continue;   // already moving away with us
      b.v.set(vx * 0.8 + dx * 2, 0.8 + sp * 0.15, vz * 0.8 + dz * 2);
      b.w.set((Math.random() - .5) * 8, (Math.random() - .5) * 8, (Math.random() - .5) * 8);
      b.sleep = 0; b.rest = 0;
    }
  }

  update(dt) {
    const T = this.terrain, h = dt / SUB;
    for (let i = this.list.length - 1; i >= 0; i--) {
      const b = this.list[i];
      b.age += dt;
      if (b.sleep > 0.6) {   // resting: after a while sink into the ground and fade out
        b.rest += dt;
        if (b.rest > 25) {
          b.mesh.material.transparent = true; b.fade -= dt * 0.5; b.pos.y -= dt * 0.15;
          b.mesh.material.opacity = Math.max(0, b.fade); this.sync(b);
          if (b.fade <= 0) this.remove(b);
        }
        continue;
      }
      // ground normal once per frame (height() is expensive)
      const g0 = T.height(b.pos.x, b.pos.z);
      _n.set(g0 - T.height(b.pos.x + 0.3, b.pos.z), 0.3, g0 - T.height(b.pos.x, b.pos.z + 0.3)).normalize();
      let touching = false;
      for (let s = 0; s < SUB; s++) {
        const wet = b.pos.y < WATER;
        b.v.y -= G * h;
        if (wet) {   // wood floats: buoyancy towards the surface, heavy water drag
          b.v.y += G * 1.7 * h * Math.min(1, (WATER - b.pos.y) / Math.max(0.05, b.half.y) + 0.3);
          b.v.multiplyScalar(Math.exp(-h * 2.5)); b.w.multiplyScalar(Math.exp(-h * 2));
        }
        b.pos.addScaledVector(b.v, h);
        const wl = b.w.length();
        if (wl > 1e-6) { _dq.setFromAxisAngle(_a.copy(b.w).divideScalar(wl), wl * h); b.q.premultiply(_dq).normalize(); }
        this.sync(b);
        // contacts: every corner below the ground pushes back (impulse) and drags (friction)
        let deep = 0;
        for (const k of CORNERS) {
          _c.copy(k).multiply(b.half).applyQuaternion(b.q).add(b.pos);
          const pen = T.height(_c.x, _c.z) - _c.y;
          if (pen <= 0) continue;
          touching = true; deep = Math.max(deep, pen);
          _r.subVectors(_c, b.pos);
          _v.crossVectors(b.w, _r).add(b.v);
          const vn = _v.dot(_n);
          if (vn >= 0) continue;
          const e = vn < -1.5 ? 0.28 : 0;
          const jn = -(1 + e) * vn / this.kAlong(b, _r, _n) / 2;   // shared by the corners that touch
          this.impulse(b, _r, _t.copy(_n).multiplyScalar(jn));
          _v.crossVectors(b.w, _r).add(b.v);
          _t.copy(_v).addScaledVector(_n, -_v.dot(_n));
          const vt = _t.length();
          if (vt > 1e-4) {
            _t.divideScalar(vt);
            const jt = Math.min(vt / this.kAlong(b, _r, _t), 0.6 * jn);
            this.impulse(b, _r, _t.multiplyScalar(-jt));
          }
        }
        if (deep > 0) { b.pos.addScaledVector(_n, deep * 0.8); this.sync(b); }
      }
      b.touchT = touching ? 0 : (b.touchT ?? 1) + dt;
      touching = b.touchT < 0.25;   // thin planks chatter on and off the ground: count recent contact as resting
      b.w.multiplyScalar(Math.exp(-dt * (touching ? 1.2 : 0.15)));
      if (touching) {   // rolling resistance; strong once nearly stopped, so pieces settle instead of creeping
        const slow = b.v.lengthSq() < 0.36 && b.w.lengthSq() < 3;
        b.v.multiplyScalar(Math.exp(-dt * (slow ? 5 : 0.4))); if (slow) b.w.multiplyScalar(Math.exp(-dt * 5));
      }
      b.e = (b.e ?? 1) + (b.v.lengthSq() + b.w.lengthSq() * 0.1 - (b.e ?? 1)) * Math.min(1, dt * 3);   // smoothed motion
      const calm = b.e < 0.15 && b.pos.y > WATER;
      b.sleep = touching && calm ? b.sleep + dt : 0;
      if (b.age > 60) b.sleep = 1;   // never jitter forever
    }
  }
}

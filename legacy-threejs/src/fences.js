import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Breakable wooden fences along the trails. Every chunk draws its fences with one InstancedMesh per
// piece type (posts, rails, pickets); each 2.4 m panel remembers which instances it owns. Ride into a
// panel fast enough and it smashes: its instances are hidden and replaced by rigid-body debris.

export const FENCE_MAT = new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.9 });
const strip = (g) => { g = g.index ? g.toNonIndexed() : g; g.deleteAttribute('uv'); return g; };
// all centred on the origin, so a piece's instance matrix is also its rigid body's pose
export const FENCE_GEO = {
  post: mergeGeometries([new THREE.BoxGeometry(0.13, 1, 0.13), new THREE.ConeGeometry(0.092, 0.1, 4).rotateY(Math.PI / 4).translate(0, 0.55, 0)].map(strip)).center(),
  rail: strip(new THREE.BoxGeometry(1, 1, 1)),
  picket: mergeGeometries([new THREE.BoxGeometry(0.085, 0.9, 0.025), new THREE.ConeGeometry(0.06, 0.1, 4).rotateY(Math.PI / 4).scale(1, 1, 0.3).translate(0, 0.5, 0)].map(strip)).center(),
};
const STYLES = {
  ranch: { postH: 1.2, rails: [[0.42, 0.13, 0.05], [0.85, 0.13, 0.05]], railOff: 0.09, cols: [0x8b6a4a, 0x9a7650, 0x7d5e40, 0x85704f] },
  picket: { postH: 1.05, rails: [[0.3, 0.08, 0.04], [0.72, 0.08, 0.04]], railOff: -0.05, pickets: 0.27, cols: [0xf2efe6, 0xe9e3d3, 0xf6f3ea] },
};
export const SPAN = 2.4;

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _p = new THREE.Vector3(), _s = new THREE.Vector3();

// pts: [{x, z, h}] posts in order; builds panels between neighbours into `lists`, colliders into `colliders`
export function buildFence(pts, style, rnd, lists, colliders) {
  const S = STYLES[style];
  const col = () => new THREE.Color(S.cols[(rnd() * S.cols.length) | 0]).multiplyScalar(0.92 + rnd() * 0.16);
  const add = (kind, panel, pos, quat, scale) => {
    _m.compose(pos, quat, scale);
    const c = col();
    lists[kind].push({ m: _m.clone(), col: c });
    panel.parts.push({ kind, i: lists[kind].length - 1, col: c.getHex(), scale: scale.clone() });
  };
  const post = (panel, a) => {
    _e.set((rnd() - .5) * 0.08, rnd() * 6.28, (rnd() - .5) * 0.08); _q.setFromEuler(_e);
    add('post', panel, _p.set(a.x, a.h + S.postH / 2 - 0.18, a.z), _q, _s.set(1, S.postH, 1));
  };
  for (let k = 0; k + 1 < pts.length; k++) {
    const a = pts[k], b = pts[k + 1], panel = { broken: false, parts: [], style };
    const dx = b.x - a.x, dz = b.z - a.z, L = Math.hypot(dx, dz), yaw = Math.atan2(-dz, dx);
    const pitch = Math.atan2(b.h - a.h, L), nx = -dz / L, nz = dx / L;   // nx, nz: side of the panel
    post(panel, a);
    if (k + 2 === pts.length) post(panel, b);
    _e.set(0, yaw, pitch, 'YZX'); const qr = new THREE.Quaternion().setFromEuler(_e);
    for (const [y, th, dp] of S.rails) {
      const sag = (rnd() - .5) * 0.04;
      add('rail', panel, _p.set((a.x + b.x) / 2 + nx * S.railOff, (a.h + b.h) / 2 + y + sag, (a.z + b.z) / 2 + nz * S.railOff), qr, _s.set(L + 0.12, th, dp));
    }
    if (S.pickets) {
      const n = Math.round(L / S.pickets);
      for (let i = 1; i < n; i++) {
        const t = i / n, hy = a.h + (b.h - a.h) * t;
        _e.set(0, yaw, (rnd() - .5) * 0.05, 'YZX'); _q.setFromEuler(_e);
        const hh = 0.92 + (rnd() - .5) * 0.06;
        add('picket', panel, _p.set(a.x + dx * t + nx * 0.02, hy + hh / 2 - 0.08, a.z + dz * t + nz * 0.02), _q, _s.set(1, hh, 1));
      }
    }
    // colliders: a row of small circles along the panel, all pointing back at it
    const m = Math.ceil(L / 0.45);
    for (let i = 0; i <= m; i++) colliders.push({ x: a.x + dx * i / m, z: a.z + dz * i / m, r: 0.22, fence: panel });
    panel.cx = (a.x + b.x) / 2; panel.cz = (a.z + b.z) / 2;
    lists.panels.push(panel);
  }
}

// after the chunk's InstancedMeshes exist: let every part know its mesh
export function bindFences(panels, meshes) {
  for (const p of panels) for (const part of p.parts) part.im = meshes[part.kind];
}

const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
const _mp = new THREE.Vector3(), _mq = new THREE.Quaternion(), _ms = new THREE.Vector3(), _v = new THREE.Vector3(), _w = new THREE.Vector3(),
  _ax = new THREE.Vector3(), _hit = new THREE.Vector3();
// smash a panel: vx, vy, vz = velocity of whatever hit it, at world point (hx, hz). Returns the panel's centre.
export function breakFence(panel, debris, vx, vy, vz, hx, hz) {
  if (panel.broken) return false;
  panel.broken = true;
  const sp = Math.hypot(vx, vz);
  for (const part of panel.parts) {
    const im = part.im; if (!im) continue;
    im.getMatrixAt(part.i, _m); im.setMatrixAt(part.i, ZERO); im.instanceMatrix.needsUpdate = true;
    _m.decompose(_mp, _mq, _ms);
    const geo = FENCE_GEO[part.kind];
    // pieces close to the impact take most of the hit, far ends just get yanked along
    const near = 1 / (1 + Math.hypot(_mp.x - hx, _mp.z - hz) * 0.8);
    const fling = (0.45 + 0.6 * near) * (0.75 + Math.random() * 0.35);
    const pieces = part.kind === 'rail' && Math.random() < 0.65 ? 2 : 1;   // rails often snap in two
    _ax.set(1, 0, 0).applyQuaternion(_mq);
    for (let k = 0; k < pieces; k++) {
      const off = pieces === 2 ? (k ? 0.25 : -0.25) * _ms.x : 0;
      const sc = pieces === 2 ? _ms.clone().setX(_ms.x * (0.5 - 0.02)) : _ms;
      _hit.copy(_mp).addScaledVector(_ax, off);
      _v.set(vx * fling + (Math.random() - .5) * 1.2, Math.max(0, vy) * 0.4 + 0.8 + Math.random() * (1 + sp * 0.18) * near, vz * fling + (Math.random() - .5) * 1.2);
      const spin = 2 + sp * 0.9 * near;
      _w.set((Math.random() - .5) * spin, (Math.random() - .5) * spin, (Math.random() - .5) * spin);
      if (pieces === 2) _w.addScaledVector(_ax.clone().cross(_v).normalize(), (k ? 1 : -1) * spin * 0.5);   // snap: halves fold apart
      debris.spawn(geo, FENCE_MAT, part.col, _hit, _mq, sc, _v, _w);
    }
  }
  return true;
}

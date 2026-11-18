import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Breakable cacti: the instanced cactus (terrain.js GEO.cactus) split into the chunks it snaps into --
// a lower and an upper trunk section and the two L-shaped arms. Each piece's geometry is centred,
// and `at` is where that centre sits in the cactus's own (unscaled) frame.
const strip = (g) => { g.deleteAttribute('uv'); return g.index ? g.toNonIndexed() : g; };
function piece(parts) {
  const g = mergeGeometries(parts.map(strip));
  g.computeBoundingBox();
  const at = g.boundingBox.getCenter(new THREE.Vector3());
  g.translate(-at.x, -at.y, -at.z);
  return { geo: g, at };
}
export const CACTUS_PIECES = [
  piece([new THREE.CylinderGeometry(0.17, 0.18, 0.8, 6).translate(0, 0.4, 0)]),
  piece([new THREE.CylinderGeometry(0.16, 0.17, 0.8, 6).translate(0, 1.2, 0)]),
  piece([new THREE.CylinderGeometry(0.1, 0.1, 0.5, 6).rotateZ(Math.PI / 2).translate(0.3, 0.75, 0),
    new THREE.CylinderGeometry(0.1, 0.1, 0.55, 6).translate(0.5, 1.0, 0)]),
  piece([new THREE.CylinderGeometry(0.09, 0.09, 0.4, 6).rotateZ(Math.PI / 2).translate(-0.25, 1.05, 0),
    new THREE.CylinderGeometry(0.09, 0.09, 0.45, 6).translate(-0.42, 1.25, 0)]),
];

const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
const _m = new THREE.Matrix4(), _p = new THREE.Vector3(), _q = new THREE.Quaternion(), _s = new THREE.Vector3(),
  _c = new THREE.Vector3(), _v = new THREE.Vector3(), _w = new THREE.Vector3(), _col = new THREE.Color();

// k: the cactus record { im, i, broken }; vx, vy, vz: velocity of what hit it
export function breakCactus(k, debris, material, vx, vy, vz) {
  if (k.broken || !k.im) return false;
  k.broken = true;
  k.im.getMatrixAt(k.i, _m);
  if (k.im.instanceColor) k.im.getColorAt(k.i, _col); else _col.set(0x5c9a45);
  k.im.setMatrixAt(k.i, ZERO); k.im.instanceMatrix.needsUpdate = true;
  _m.decompose(_p, _q, _s);
  const sp = Math.hypot(vx, vz);
  CACTUS_PIECES.forEach(({ geo, at }, n) => {
    _c.copy(at).applyMatrix4(_m);
    const up = n === 0 ? 0.3 : 1;   // the base just topples, the top and arms go flying
    _v.set(vx * (0.35 + 0.4 * up) + (Math.random() - .5) * 1.5, Math.max(0, vy) * 0.3 + (0.8 + Math.random() * 1.8) * up, vz * (0.35 + 0.4 * up) + (Math.random() - .5) * 1.5);
    const spin = 2 + sp * 0.7 * up;
    _w.set((Math.random() - .5) * spin, (Math.random() - .5) * spin, (Math.random() - .5) * spin);
    debris.spawn(geo, material, _col.getHex(), _c, _q, _s, _v, _w);
  });
  return true;
}

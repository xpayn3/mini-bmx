// The working drivetrain of the downhill bike: the rigged rear derailleur and the chain, both from the
// Houdini bike (tools/export_drivetrain.py -> assets/drivetrain.glb).
//  * derailleur: every moving group has its pose for each gear; setGear(f) blends between the two
//    nearest gears (fractional = mid-shift), and the pulleys spin with the chain.
//  * chain: the loop of roller centres for each gear. 108 links run along it (instanced: three draw
//    calls for the whole chain), driven by the cranks; during a shift the loop blends to the new cog.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const _q0 = new THREE.Quaternion(), _q1 = new THREE.Quaternion(), _qs = new THREE.Quaternion();
const _a = new THREE.Vector3(), _b = new THREE.Vector3(), _x = new THREE.Vector3(), _y = new THREE.Vector3(),
  _z = new THREE.Vector3(), _m = new THREE.Matrix4();
const Z = new THREE.Vector3(0, 0, 1);

// one chain plate: two round ends (on the pins) and a waist between them, flat in XY, pin A at the origin
function plateGeo(pitch, rEnd, waist, thick) {
  const s = new THREE.Shape();
  const a = Math.asin(waist / rEnd);   // where the waist line leaves each end circle
  s.absarc(0, 0, rEnd, a, Math.PI * 2 - a, false);
  s.quadraticCurveTo(pitch / 2, -waist * 0.82, pitch - rEnd * Math.cos(a), -waist);
  s.absarc(pitch, 0, rEnd, Math.PI + a, Math.PI * 3 - a, false);
  s.quadraticCurveTo(pitch / 2, waist * 0.82, rEnd * Math.cos(a), waist);
  const g = new THREE.ExtrudeGeometry(s, { depth: thick, bevelEnabled: false, curveSegments: 6 });
  g.translate(0, 0, -thick / 2);
  return g;
}

export class Drivetrain {
  // gltfScene: drivetrain.glb's scene. rigParent: the node the derailleur rides on (seatstay);
  // chainParent: the node the chain rides on (swing).
  // rest: Map node -> its rest matrix in the bike frame (captured when the bike loaded, before anything moved)
  constructor(gltfScene, { rigParent, chainParent, rest, ringTeeth = 34 }) {
    const root = gltfScene.getObjectByName('drivetrain');
    const ex = root.userData;
    this.cogs = ex.cogs; this.n = ex.cogs.length;
    this.ringTeeth = ringTeeth;
    const toLocal = (parent) => {   // bike frame -> parent's local frame, at rest
      const g = new THREE.Group();
      g.matrixAutoUpdate = false;
      g.matrix.copy(rest.get(parent)).invert();
      parent.add(g);
      return g;
    };
    // ---- derailleur ----
    this.rig = toLocal(rigParent);
    this.parts = [];
    for (const c of [...root.children]) {
      const gears = c.userData.gears;
      if (!gears) continue;
      c.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      this.rig.add(c);
      this.parts.push({ node: c, gears, spin: !!c.userData.spin });
    }
    // ---- chain ----
    this.chain = toLocal(chainParent);
    this.loops = ex.chain.map((flat) => {
      const pts = []; for (let i = 0; i < flat.length; i += 3) pts.push(new THREE.Vector3(flat[i], flat[i + 1], flat[i + 2]));
      return pts;
    });
    this.N = this.loops[0].length;
    // every gear's loop starts at the roller nearest the same spot, so blending matches link for link
    const ref = this.loops[0][0].clone();
    this.loops = this.loops.map((L) => {
      let best = 0, bd = Infinity;
      L.forEach((p, i) => { const d = p.distanceToSquared(ref); if (d < bd) { bd = d; best = i; } });
      return L.slice(best).concat(L.slice(0, best));
    });
    this.loop = this.loops[0].map((p) => p.clone());   // current (blended) loop
    const pitch = ex.pitch || 0.0127, rr = ex.rollerR > 0.001 ? ex.rollerR : 0.0039;
    const inW = ex.innerWidth > 0.001 ? ex.innerWidth : 0.0024, th = 0.0008;
    const zi = inW / 2 + th / 2, zo = zi + th * 1.05;
    const plate = plateGeo(pitch, rr * 1.18, rr * 0.82, th);
    const innerG = mergeGeometries([plate.clone().translate(0, 0, zi), plate.clone().translate(0, 0, -zi)]);
    const outerPlate = plateGeo(pitch, rr * 1.12, rr * 0.75, th);
    const pin = new THREE.CylinderGeometry(rr * 0.42, rr * 0.42, 2 * zo + th * 1.6, 8).rotateX(Math.PI / 2).toNonIndexed();   // plates are non-indexed
    const outerG = mergeGeometries([outerPlate.clone().translate(0, 0, zo), outerPlate.clone().translate(0, 0, -zo),
      pin.clone(), pin.clone().translate(pitch, 0, 0)]);
    const rollerG = new THREE.CylinderGeometry(rr * 0.98, rr * 0.98, inW, 10).rotateX(Math.PI / 2);
    const steel = new THREE.MeshStandardMaterial({ name: 'chainSteel', color: 0x8d9096, metalness: 0.9, roughness: 0.38 });
    const dark = new THREE.MeshStandardMaterial({ name: 'chainDark', color: 0x3a3c40, metalness: 0.85, roughness: 0.45 });
    const half = Math.ceil(this.N / 2);
    this.inner = new THREE.InstancedMesh(innerG, dark, half);
    this.outer = new THREE.InstancedMesh(outerG, steel, half);
    this.rollers = new THREE.InstancedMesh(rollerG, dark, this.N);
    for (const m of [this.inner, this.outer, this.rollers]) {
      m.castShadow = true; m.frustumCulled = false;
      m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      this.chain.add(m);
    }
    this.gearF = -1; this.phase = 0;
    this.setGear(0); this.update(0);
  }

  // gear: 0 .. n-1, fractional while shifting
  setGear(f) {
    f = Math.min(this.n - 1, Math.max(0, f));
    if (f === this.gearF) return;
    this.gearF = f;
    const i0 = Math.floor(f), i1 = Math.min(this.n - 1, i0 + 1), t = f - i0;
    for (const p of this.parts) {
      const a = p.gears[i0], b = p.gears[i1];
      p.node.position.set(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t);
      p.base = (p.base || new THREE.Quaternion()).slerpQuaternions(_q0.fromArray(a, 3), _q1.fromArray(b, 3), t);
      p.node.quaternion.copy(p.base);
    }
    const A = this.loops[i0], B = this.loops[i1];
    for (let k = 0; k < this.N; k++) this.loop[k].lerpVectors(A[k], B[k], t);
  }

  // crank: crank angle (rad, + = pedalling forward). Moves the chain and spins the pulleys.
  update(crank) {
    const N = this.N, L = this.loop;
    this.phase = crank / (Math.PI * 2) * this.ringTeeth;   // links that have gone by
    const ph = ((this.phase % N) + N) % N;
    const at = (u, out) => {   // point on the loop at roller index u (wraps)
      const i = Math.floor(u), t = u - i, a = L[((i % N) + N) % N], b = L[(((i + 1) % N) + N) % N];
      return out.lerpVectors(a, b, t);
    };
    let ii = 0, io = 0;
    for (let k = 0; k < N; k++) {
      at(k + ph, _a); at(k + 1 + ph, _b);
      _x.subVectors(_b, _a).normalize();
      _z.copy(Z).addScaledVector(_x, -Z.dot(_x)).normalize();
      _y.crossVectors(_z, _x);
      _m.makeBasis(_x, _y, _z).setPosition(_a);
      if (k % 2 === 0) this.inner.setMatrixAt(ii++, _m); else this.outer.setMatrixAt(io++, _m);
      this.rollers.setMatrixAt(k, _m);
    }
    this.inner.count = ii; this.outer.count = io;
    this.inner.instanceMatrix.needsUpdate = true; this.outer.instanceMatrix.needsUpdate = true;
    this.rollers.instanceMatrix.needsUpdate = true;
    // pulleys turn with the chain: one tooth per link
    const turn = this.phase * Math.PI * 2 / 11;
    for (const p of this.parts) if (p.spin) p.node.quaternion.copy(p.base).multiply(_qs.setFromAxisAngle(Z, -turn));
  }
}

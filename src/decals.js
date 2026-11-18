import * as THREE from 'three';
import { DecalGeometry } from 'three/addons/geometries/DecalGeometry.js';

// Bike decals: lettering drawn into a canvas and projected onto the model's own surface
// (DecalGeometry), so it follows the tube's curve and the tyre's bulge. Each decal is a child of the
// mesh it sits on, so it moves with it (the tyre lettering spins with the wheel).
//   downTube: lettering along the down tube, both sides
//   tyres:    lettering round both sidewalls of both tyres, twice per side

const FONT = '"Arial Black", "Helvetica Neue", Arial, sans-serif';

function canvasTex(c) {
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}

// straight lettering, sized to fill the canvas
function wordTexture(text, aspect, { fill = '#ffffff', stroke = 'rgba(20,20,24,0.85)', italic = true } = {}) {
  const W = 1024, H = Math.round(W / aspect);
  const c = document.createElement('canvas'); c.width = W; c.height = H;
  const g = c.getContext('2d');
  let px = H * 0.86;
  g.font = `${italic ? 'italic ' : ''}900 ${px}px ${FONT}`;
  const w = g.measureText(text).width;
  if (w > W * 0.94) { px *= W * 0.94 / w; g.font = `${italic ? 'italic ' : ''}900 ${px}px ${FONT}`; }
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.lineJoin = 'round'; g.lineWidth = px * 0.1; g.strokeStyle = stroke;
  g.strokeText(text, W / 2, H / 2 + px * 0.04);
  g.fillStyle = fill; g.fillText(text, W / 2, H / 2 + px * 0.04);
  return canvasTex(c);
}

// lettering bent round a circle (a tyre sidewall). The canvas spans [-R, R] of the tyre; the letters
// sit between radii r0 and r1, centred at the top and again at the bottom.
function ringTexture(text, R, r0, r1, { fill = '#f4f4f0' } = {}) {
  const S = 2048, k = S / (2 * R);
  const c = document.createElement('canvas'); c.width = c.height = S;
  const g = c.getContext('2d');
  const rMid = (r0 + r1) / 2 * k, px = (r1 - r0) * k * 0.95;
  g.font = `900 ${px}px ${FONT}`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = fill;
  g.translate(S / 2, S / 2);
  const track = px * 0.08;   // a little letter spacing
  const widths = [...text].map(ch => g.measureText(ch).width + track);
  const arc = widths.reduce((a, b) => a + b, 0) / rMid;
  for (const mid of [-Math.PI / 2, Math.PI / 2]) {   // top, then bottom (upside down, like a real tyre)
    let th = mid - arc / 2;
    [...text].forEach((ch, i) => {
      const a = th + widths[i] / 2 / rMid;
      g.save(); g.rotate(a); g.translate(rMid, 0); g.rotate(Math.PI / 2);
      g.fillText(ch, 0, 0); g.restore();
      th += widths[i] / rMid;
    });
  }
  return canvasTex(c);
}

// project a decal onto `mesh` (in the mesh's own space) and keep only the faces that look toward the
// projector, so it never wraps round to the far side of a tube or tyre
function project(mesh, pos, xAxis, zAxis, size, material) {
  const yAxis = new THREE.Vector3().crossVectors(zAxis, xAxis).normalize();
  const rot = new THREE.Euler().setFromRotationMatrix(new THREE.Matrix4().makeBasis(xAxis, yAxis, zAxis));
  const local = { geometry: mesh.geometry, matrixWorld: new THREE.Matrix4() };   // stay in the mesh's space
  const dg = new DecalGeometry(local, pos, rot, size);
  const P = dg.attributes.position, N = dg.attributes.normal, U = dg.attributes.uv;
  const p = [], n = [], u = [];
  for (let t = 0; t < P.count; t += 3) {
    let nz = 0;
    for (let j = 0; j < 3; j++) nz += N.getX(t + j) * zAxis.x + N.getY(t + j) * zAxis.y + N.getZ(t + j) * zAxis.z;
    if (nz / 3 < 0.15) continue;
    for (let j = 0; j < 3; j++) {
      p.push(P.getX(t + j), P.getY(t + j), P.getZ(t + j));
      n.push(N.getX(t + j), N.getY(t + j), N.getZ(t + j));
      u.push(U.getX(t + j), U.getY(t + j));
    }
  }
  dg.dispose();
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(n, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(u, 2));
  const d = new THREE.Mesh(g, material);
  d.receiveShadow = true; d.castShadow = false; d.renderOrder = 1;
  mesh.add(d);
  return d;
}

const decalMat = (map, roughness) => new THREE.MeshStandardMaterial({
  map, transparent: true, depthWrite: false, roughness, metalness: 0,
  polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
});

export function addBikeDecals(bike, spec) {
  if (!spec) return;
  bike.updateMatrixWorld(true);
  const Z = new THREE.Vector3(0, 0, 1), NZ = new THREE.Vector3(0, 0, -1);

  // straight lettering on a tube, both sides of the bike:
  // { mesh, from: [x, y], to: [x, y], text, length, height, z = 0, depth = 0.2, fill, stroke }
  // from -> to is the tube's centre line in the mesh's space. A pair of parts (fork legs, chainstays)
  // sits at +-z: give z (the outer face) and a shallow depth so each side only hits its own part.
  for (const L of spec.labels || []) {
    const mesh = bike.getObjectByName(L.mesh);
    if (!mesh) continue;
    const a = new THREE.Vector3(L.from[0], L.from[1], 0), b = new THREE.Vector3(L.to[0], L.to[1], 0);
    const dir = b.clone().sub(a).normalize(), mid = a.clone().lerp(b, 0.5);
    const mat = decalMat(wordTexture(L.text, L.length / L.height, L), 0.3);
    const size = new THREE.Vector3(L.length, L.height, L.depth ?? 0.2), z = L.z ?? 0;
    project(mesh, mid.clone().setZ(z), dir, Z, size, mat);                    // drive side: reads toward `to`
    project(mesh, mid.clone().setZ(-z), dir.clone().negate(), NZ, size, mat); // other side: the other way
  }

  if (spec.tyres) {   // { text, meshes: [names] } -- radii come from each tyre and its rim
    for (const name of spec.tyres.meshes) {
      const mesh = bike.getObjectByName(name);
      if (!mesh) continue;
      const bb = new THREE.Box3().setFromBufferAttribute(mesh.geometry.attributes.position);
      const c = bb.getCenter(new THREE.Vector3()), R = (bb.max.x - bb.min.x) / 2;
      const rim = mesh.parent.children.find(o => o !== mesh && o.isMesh && o.material.name === 'black');
      let rimR = R * 0.85;
      if (rim) { const rb = new THREE.Box3().setFromBufferAttribute(rim.geometry.attributes.position); rimR = Math.min(R * 0.9, (rb.max.y - rb.min.y) / 2); }
      const r0 = rimR + (R - rimR) * 0.12, r1 = rimR + (R - rimR) * 0.72;
      const mat = decalMat(ringTexture(spec.tyres.text, R, r0, r1), 0.75);
      const size = new THREE.Vector3(2 * R, 2 * R, 0.2);
      project(mesh, c, new THREE.Vector3(1, 0, 0), Z, size, mat);
      project(mesh, c, new THREE.Vector3(-1, 0, 0), NZ, size, mat);
    }
  }
}

// Rider gear built in code: moto-style goggles (curved lens, foam frame, wide strap round the
// helmet) and flat-pedal MTB shoes. Both take a materials object so the look panel can recolour them.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// ---------------- goggles ----------------
// The outline is drawn flat (u = across, v = up, metres) and then bent round a vertical axis of
// radius R, so the lens wraps the face like a real goggle. +X is forward, +Z the rider's right.
function goggleOutline(w, h, inset = 0) {
  const W = w / 2 - inset, H = h / 2 - inset, nose = 0.022 - inset * 0.5, nw = 0.024 + inset * 0.3;
  const s = new THREE.Shape();
  s.moveTo(-nw, -H);                                    // bottom, left of the nose
  s.bezierCurveTo(-W * 0.6, -H - 0.004, -W, -H * 0.7, -W, -H * 0.05);         // lower left, rounded
  s.bezierCurveTo(-W, H * 0.85, -W * 0.8, H, -W * 0.55, H);                     // upper left corner
  s.lineTo(W * 0.55, H);
  s.bezierCurveTo(W * 0.8, H, W, H * 0.85, W, -H * 0.05);
  s.bezierCurveTo(W, -H * 0.7, W * 0.6, -H - 0.004, nw, -H);
  s.bezierCurveTo(nw * 0.7, -H + nose, -nw * 0.7, -H + nose, -nw, -H);         // nose arch
  return s;
}

// bend (x = depth outward, y = v, z = u) geometry from flat (u, v, depth) onto a cylinder of radius R
function bend(geo, R) {
  const p = geo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const u = p.getX(i), v = p.getY(i), d = p.getZ(i);
    const a = u / R, r = R + d;
    p.setXYZ(i, r * Math.cos(a) - R, v, r * Math.sin(a));
  }
  geo.computeVertexNormals();
  return geo;
}

// fit (head-local metres / rad): x, y = front of the lens, tilt = top leaning back,
// w, h = goggle size, R = lens wrap radius, strap = { cx, ra, rc }: ellipse round the helmet shell.
// hug(x, y, dx, dz) -> distance from (x, y, 0) to the shell's outside along (dx, 0, dz), or null: the strap follows it
export function buildGoggles(m, { x = 0.15, y = 0.025, tilt = 0.25, w = 0.2, h = 0.075, R = 0.12,
  strap: S = { cx: 0.01, ra: 0.236, rc: 0.162 } } = {}, hug = null) {
  const root = new THREE.Group();
  const g = new THREE.Group();
  g.position.set(x, y, 0); g.rotation.z = tilt;
  root.add(g);
  // frame: the outline with the lens cut out, 12 mm deep, foam behind it
  const frameShape = goggleOutline(w, h);
  frameShape.holes.push(goggleOutline(w, h, 0.01));
  const ext = (shape, depth, bevel) => new THREE.ExtrudeGeometry(shape, { depth, steps: 1, curveSegments: 10,
    bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 2 });
  g.add(new THREE.Mesh(bend(ext(frameShape, 0.01, 0.0025).translate(0, 0, -0.012), R), m.frame));
  g.add(new THREE.Mesh(bend(ext(goggleOutline(w, h, 0.002), 0.008, 0).translate(0, 0, -0.022), R), m.foam));
  // lens: one curved sheet just inside the front of the frame
  g.add(new THREE.Mesh(bend(new THREE.ShapeGeometry(goggleOutline(w, h, 0.005), 12).translate(0, 0, -0.004), R), m.lens));
  // outriggers at the frame's ends: where the strap clips on
  const ends = [];
  for (const s of [-1, 1]) {
    const a = s * (w / 2) / R, r = R - 0.008;
    const o = new THREE.Mesh(new THREE.BoxGeometry(0.028, 0.032, 0.012), m.frame);
    o.position.set(r * Math.cos(a) - R - 0.006, 0, r * Math.sin(a) + s * 0.004);
    o.rotation.y = -a;
    g.add(o);
    ends.push(o.position.clone().applyMatrix4(new THREE.Matrix4().compose(g.position, g.quaternion, new THREE.Vector3(1, 1, 1))));
  }
  // strap (head frame): outrigger -> round the back of the shell on an ellipse -> other outrigger
  const yS = y - 0.004, pts = [];
  const ca = Math.min(0.98, Math.max(-0.98, (ends[0].x - 0.02 - S.cx) / S.ra)), a0 = Math.acos(ca);
  pts.push(ends[0].clone().setY(yS));   // left (−Z): angle runs a0 .. 2π − a0 through the back (π)
  const seg = 40;
  for (let i = 0; i <= seg; i++) {
    const a = -a0 - (Math.PI * 2 - 2 * a0) * (i / seg);
    const dx = Math.cos(a), dz = Math.sin(a);
    const r = hug ? hug(S.cx, yS, dx, dz) : null;   // distance to the shell's outside along this direction
    pts.push(r ? new THREE.Vector3(S.cx + dx * (r + 0.004), yS, dz * (r + 0.004))
      : new THREE.Vector3(S.cx + S.ra * dx, yS, S.rc * dz));
  }
  pts.push(ends[1].clone().setY(yS));
  const pos = [], idx = [], hw = 0.021;
  pts.forEach((p, i) => {
    pos.push(p.x, p.y - hw, p.z, p.x, p.y + hw, p.z);
    if (i < pts.length - 1) { const k = i * 2; idx.push(k, k + 1, k + 2, k + 1, k + 3, k + 2); }
  });
  const sg = new THREE.BufferGeometry();
  sg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); sg.setIndex(idx); sg.computeVertexNormals();
  root.add(new THREE.Mesh(sg, m.strap));
  root.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return root;
}

// ---------------- shoes ----------------
// A flat-pedal shoe in the shoe group's frame: sole at y = 0, toe towards +X, about 29 cm long.
// The foot outline (top view) drives both the cupsole and the lofted upper.
const X0 = -0.115, X1 = 0.175, LEN = X1 - X0;
const halfWidth = (x) => {           // half-width of the foot at x: narrow heel, wide ball, round toe
  const t = (x - X0) / LEN;
  const base = 0.042 + 0.016 * Math.sin(Math.min(1, t / 0.72) * Math.PI * 0.5);
  const toe = t > 0.72 ? Math.sqrt(Math.max(0, 1 - ((t - 0.72) / 0.28) ** 2)) : 1;
  const heel = t < 0.12 ? Math.sqrt(Math.max(0, 1 - ((0.12 - t) / 0.12) ** 2)) : 1;
  return base * Math.min(toe, heel) + 0.002;
};
const upperH = (x) => {              // height of the upper's top line: low toe box, high instep and heel
  const t = (x - X0) / LEN;
  if (t > 0.62) return 0.05 + 0.04 * (1 - (t - 0.62) / 0.38) ** 1.5;
  if (t > 0.25) return 0.09 + 0.005 * Math.sin((t - 0.25) / 0.37 * Math.PI);
  return 0.09 + 0.015 * (0.25 - t) / 0.25;   // heel counter up to the ankle
};

function soleGeo(inset, y0, y1, n = 28) {
  // the outline as a closed loop in (x, z); walls + caps by lathing between y0 and y1
  const pts = [];
  for (let i = 0; i <= n; i++) { const x = X0 + LEN * (i / n); pts.push([x, halfWidth(x) - inset]); }
  const loop = [...pts.map(([x, z]) => [x, z]), ...pts.slice(1, -1).reverse().map(([x, z]) => [x, -z])];
  const shape = new THREE.Shape(loop.map(([x, z]) => new THREE.Vector2(x, z)));
  const geo = new THREE.ExtrudeGeometry(shape, { depth: y1 - y0, bevelEnabled: true, bevelThickness: 0.003, bevelSize: 0.003, bevelSegments: 1, curveSegments: 4 });
  geo.rotateX(Math.PI / 2);          // extrude along -Y; shape's y becomes z
  geo.translate(0, y1, 0);
  return geo;
}

function upperGeo(n = 22, m = 12) {
  // lofted shell: m stations round each cross-section (from one side over the top to the other), n along the foot
  const pos = [], idx = [];
  for (let i = 0; i <= n; i++) {
    const x = X0 + 0.004 + (LEN - 0.012) * (i / n);
    const hw = halfWidth(x) - 0.003, h = upperH(x);
    for (let j = 0; j <= m; j++) {
      const a = Math.PI * (j / m);                 // 0 = right side, PI/2 = top, PI = left side
      const z = Math.cos(a) * hw, y = 0.022 + Math.sin(a) ** 0.7 * (h - 0.022);
      pos.push(x, y, z);
    }
  }
  const row = m + 1;
  for (let i = 0; i < n; i++) for (let j = 0; j < m; j++) {
    const k = i * row + j;
    idx.push(k, k + row, k + 1, k + 1, k + row, k + row + 1);
  }
  // close the heel and toe with fans
  const cap = (i, flip) => {
    const c = pos.length / 3, x = pos[i * row * 3];
    pos.push(x, 0.022 + (upperH(x) - 0.022) * 0.5, 0);
    for (let j = 0; j < m; j++) { const k = i * row + j; flip ? idx.push(c, k, k + 1) : idx.push(c, k + 1, k); }
  };
  cap(0, false); cap(n, true);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

export function buildShoe(m) {
  const s = new THREE.Group();
  const sole = new THREE.Mesh(soleGeo(0, 0, 0.022), m.sole);        // cupsole
  const mid = new THREE.Mesh(soleGeo(-0.001, 0.019, 0.025), m.mid);  // midsole stripe, a hair proud
  const upper = new THREE.Mesh(upperGeo(), m.upper);
  s.add(sole, mid, upper);
  // ankle collar (padded ring round the opening) and a heel tab
  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.043, 0.011, 5, 12), m.accent);
  collar.rotation.x = Math.PI / 2; collar.scale.set(1.25, 1, 1); collar.position.set(-0.055, 0.1, 0);
  collar.rotation.y = 0; collar.rotation.z = -0.18;
  s.add(collar);
  const tab = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.035, 0.03), m.accent);
  tab.position.set(-0.111, 0.095, 0); tab.rotation.z = 0.15;
  s.add(tab);
  // toe cap overlay and laces across the instep
  const toeGeo = upperGeo(6, 10);
  toeGeo.scale(1, 1, 1);
  const tp = toeGeo.attributes.position;
  for (let i = 0; i < tp.count; i++) {   // keep only the front 22% of the loft, puffed out a touch
    const x = tp.getX(i), t = (x - X0) / LEN;
    const nx = X0 + LEN * (0.78 + 0.22 * t) - 0.004;
    const hw = halfWidth(nx) - 0.001, h = upperH(nx) + 0.003;
    const z = tp.getZ(i), y = tp.getY(i);
    const hw0 = halfWidth(x) - 0.003, h0 = upperH(x);
    tp.setXYZ(i, nx, 0.02 + (y - 0.022) / Math.max(h0 - 0.022, 1e-3) * (h - 0.02), z / Math.max(hw0, 1e-3) * hw);
  }
  toeGeo.computeVertexNormals();
  s.add(new THREE.Mesh(toeGeo, m.accent));
  const laces = [];
  for (let i = 0; i < 4; i++) {
    const x = 0.045 + i * 0.022, y = upperH(x) + 0.001;
    laces.push(new THREE.BoxGeometry(0.008, 0.005, 0.048).translate(x, y, 0));
  }
  s.add(new THREE.Mesh(mergeGeometries(laces), m.laces));
  s.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return s;
}

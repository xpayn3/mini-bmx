// Procedural bike generator -- the game-side cousin of the Houdini bike_skeleton asset.
// A bike is a handful of numbers a frame builder would quote (reach, stack, head / seat angle,
// chainstay, BB drop, wheel size, fork travel + offset, bar, stem, cranks) and the solver turns
// them into points the same way the asset does:
//   * BB at the origin (x = 0), ground at y = 0, +X forward, +Y up, +Z the rider's right (drive side)
//   * the rear axle sits at chainstay length and BB drop behind the BB
//   * the head tube top is reach / stack from the BB; the steer axis runs down at the head angle
//   * the fork length is SOLVED so the front axle lands at the front wheel's radius
//     ("auto fork length": the chart numbers are quoted at sag, so the bike stands at sag)
//   * a four-bar rear end is the Houdini DH's Horst link, fitted between this bike's BB and axle
// The result has the same node split as the exported .glb bikes (frame, steer, fork_lower,
// wheel_front, wheel_rear, crank, swing, seatstay, rocker, shock_*) and the same userData,
// so the game and suspension.js treat a built bike exactly like an exported one.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const D2R = Math.PI / 180;
export const WHEELS = { '20': 406, '24': 507, '26': 559, '27.5': 584, '29': 622 };   // rim bead seat diameter, mm

// lengths in mm, angles in degrees, tyre widths in inches, travel in mm
export const PRESETS = {
  bmx: {
    name: 'BMX', type: 'bmx', style: 'bmx',
    wheelF: '20', wheelR: '20', tyreF: 2.3, tyreR: 2.3, knobs: false, discs: false, pegs: true,
    reach: 430, stack: 345, headAngle: 74.5, seatAngle: 71, chainstay: 335, bbDrop: -35,
    headTube: 115, seatTube: 225, ttJoin: 0.95, tube: 1.0, saddle: 420, saddleTilt: 12,
    fork: 'rigid', forkOffset: 28, forkTravel: 0, rear: 'hardtail', rearTravel: 0,
    bar: 'bmx', barWidth: 740, barRise: 230, stem: 50, crank: 175, ring: 25, cog: 9,
    colors: { frame: '#e8432e', fork: '#e8432e', rims: '#1a1a1c', parts: '#18181a', tyres: '#1c1c1c', spring: '#e8b030' },
  },
  dj: {
    name: 'Dirt jump', type: 'dj', style: 'dj',
    wheelF: '26', wheelR: '26', tyreF: 2.3, tyreR: 2.3, knobs: true, discs: true, pegs: false,
    reach: 430, stack: 585, headAngle: 69, seatAngle: 71, chainstay: 390, bbDrop: 0,
    headTube: 100, seatTube: 330, ttJoin: 0.93, tube: 1.1, saddle: 560, saddleTilt: 5,
    fork: 'single', forkOffset: 40, forkTravel: 100, rear: 'hardtail', rearTravel: 0,
    bar: 'riser', barWidth: 760, barRise: 50, stem: 45, crank: 170, ring: 28, cog: 13,
    colors: { frame: '#2f7de1', fork: '#1a1a1c', rims: '#1a1a1c', parts: '#18181a', tyres: '#1c1c1c', spring: '#e8b030' },
  },
  trail: {
    name: 'Enduro', type: 'trail', style: 'trail',
    wheelF: '29', wheelR: '29', tyreF: 2.4, tyreR: 2.4, knobs: true, discs: true, pegs: false,
    reach: 475, stack: 630, headAngle: 64.5, seatAngle: 77, chainstay: 440, bbDrop: 30,
    headTube: 110, seatTube: 430, ttJoin: 0.72, tube: 1.15, saddle: 600, saddleTilt: 4,   // dropper down
    fork: 'single', forkOffset: 44, forkTravel: 170, rear: 'fourbar', rearTravel: 160,
    bar: 'riser', barWidth: 780, barRise: 25, stem: 40, crank: 170, ring: 32, cog: 36,
    colors: { frame: '#3c8c5a', fork: '#1a1a1c', rims: '#1a1a1c', parts: '#18181a', tyres: '#1c1c1c', spring: '#e8b030' },
  },
  dh: {   // the Houdini DH_S3 numbers
    name: 'Downhill', type: 'dh', style: 'dh',
    wheelF: '29', wheelR: '27.5', tyreF: 2.5, tyreR: 2.5, knobs: true, discs: true, pegs: false,
    reach: 446, stack: 632, headAngle: 62.8, seatAngle: 76.8, chainstay: 443, bbDrop: 25,
    headTube: 105, seatTube: 400, ttJoin: 0.7, tube: 1.25, saddle: 560, saddleTilt: 8,
    fork: 'dual', forkOffset: 58, forkTravel: 200, rear: 'fourbar', rearTravel: 200,
    bar: 'riser', barWidth: 800, barRise: 30, stem: 50, crank: 165, ring: 34, cog: 32,
    colors: { frame: '#e8432e', fork: '#1a1a1c', rims: '#1a1a1c', parts: '#18181a', tyres: '#1c1c1c', spring: '#e8b030' },
  },
};

// the Houdini DH's four-bar (rs_* detail attributes), mm, with its BB and rear axle
const DH4 = { BB: [0, 330.1], A: [-442.294, 355.09], G1: [98.4, 397.09], G2: [-39.6, 590.49],
  C1: [-416.694, 340.59], C2: [-170.926, 643.444], D: [27.402, 643.646], FE: [40.8, 441.59] };

export function normalize(cfg) {   // fill anything missing from the preset of its type
  const base = PRESETS[cfg?.type] || PRESETS.bmx;
  return { ...structuredClone(base), ...structuredClone(cfg || {}), colors: { ...base.colors, ...(cfg?.colors || {}) } };
}

// ---------------- geometry: the numbers -> points ----------------
export function solve(cfgIn) {
  const c = normalize(cfgIn), m = (v) => v / 1000;
  const tyreH = (w) => w * 25.4 * 0.95;
  const RF = m(WHEELS[c.wheelF] / 2 + tyreH(c.tyreF)), RR = m(WHEELS[c.wheelR] / 2 + tyreH(c.tyreR));
  const bbY = RR - m(c.bbDrop);
  const BB = new THREE.Vector2(0, bbY);
  const A = new THREE.Vector2(-Math.sqrt(Math.max(1e-4, m(c.chainstay) ** 2 - m(c.bbDrop) ** 2)), RR);
  const ha = c.headAngle * D2R, sa = c.seatAngle * D2R;
  const axis = new THREE.Vector2(-Math.cos(ha), Math.sin(ha));       // steer axis, pointing up
  const fwd = new THREE.Vector2(Math.sin(ha), Math.cos(ha));         // perpendicular to it, forward
  const htTop = new THREE.Vector2(m(c.reach), bbY + m(c.stack));
  const htBot = htTop.clone().addScaledVector(axis, -m(c.headTube));
  const off = m(c.forkOffset);
  // axle = crown - axis * L + fwd * offset, with axle.y = RF  ->  L (axle-to-crown along the legs)
  const crownGap = 0.012;                                             // lower headset cup
  const crown = htBot.clone().addScaledVector(axis, -crownGap);
  const L = Math.max(0.15, (crown.y + Math.cos(ha) * off - RF) / Math.sin(ha));
  const F = crown.clone().addScaledVector(axis, -L).addScaledVector(fwd, off);
  F.y = Math.max(F.y, RF * 0.6);
  const seatDir = new THREE.Vector2(-Math.cos(sa), Math.sin(sa));
  const stTop = BB.clone().addScaledVector(seatDir, m(c.seatTube));
  const saddle = BB.clone().addScaledVector(seatDir, m(c.saddle));
  const trail = (RF * Math.cos(ha) - off) / Math.sin(ha);
  const p = { c, RF, RR, BB, A, F, axis, fwd, htTop, htBot, crown, L, off, seatDir, stTop, saddle, trail };
  if (c.rear === 'fourbar') {   // the DH linkage, similarity-mapped from its BB->axle onto ours
    const b0 = new THREE.Vector2(...DH4.BB).multiplyScalar(0.001), a0 = new THREE.Vector2(...DH4.A).multiplyScalar(0.001);
    const v0 = a0.clone().sub(b0), v1 = A.clone().sub(BB);
    const s = v1.length() / v0.length(), r = Math.atan2(v1.y, v1.x) - Math.atan2(v0.y, v0.x);
    const map = (k) => {
      const q = new THREE.Vector2(...DH4[k]).multiplyScalar(0.001).sub(b0).multiplyScalar(s);
      return new THREE.Vector2(q.x * Math.cos(r) - q.y * Math.sin(r), q.x * Math.sin(r) + q.y * Math.cos(r)).add(BB);
    };
    p.link = Object.fromEntries(['G1', 'G2', 'C1', 'C2', 'D', 'FE'].map(k => [k, map(k)]));
    p.link.A = A.clone();
  }
  p.dims = {
    wheelbase: F.x - A.x, frontCenter: F.x - BB.x, bbHeight: bbY, trail, forkLength: L + crownGap,
    reach: m(c.reach), stack: m(c.stack), chainstay: m(c.chainstay), headAngle: c.headAngle, seatAngle: c.seatAngle,
  };
  return p;
}

// ---------------- mesh helpers ----------------
const V3 = (v, z = 0) => new THREE.Vector3(v.x, v.y, z);
const UP = new THREE.Vector3(0, 1, 0);
function prep(g) {   // one attribute layout for merging: position + normal, indexed
  if (g.attributes.uv) g.deleteAttribute('uv');
  if (g.attributes.uv1) g.deleteAttribute('uv1');
  if (!g.index) { const n = g.attributes.position.count; g.setIndex([...Array(n).keys()]); }
  return g;
}
function tube(a, b, r0, r1 = r0, seg = 12) {   // tapered cylinder from a to b (Vector3)
  const d = b.clone().sub(a), len = Math.max(1e-4, d.length());
  const g = new THREE.CylinderGeometry(r1, r0, len, seg, 1, false);
  g.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(UP, d.normalize()));
  g.translate((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
  return g;
}
function curve(points, r, seg = 24, rad = 10, closed = false) {
  return new THREE.TubeGeometry(new THREE.CatmullRomCurve3(points, closed), seg, r, rad, closed);
}
function box(cx, cy, cz, sx, sy, sz, rotZ = 0) {
  const g = new THREE.BoxGeometry(sx, sy, sz);
  if (rotZ) g.rotateZ(rotZ);
  g.translate(cx, cy, cz);
  return g;
}
function axleCyl(x, y, z0, z1, r, seg = 16) { return tube(new THREE.Vector3(x, y, z0), new THREE.Vector3(x, y, z1), r, r, seg); }
function gear(teeth, rIn, depth, toothH = 0.004) {   // flat sprocket in XY, centred, extruded along Z
  const s = new THREE.Shape(), n = teeth * 2;
  const rOut = Math.max(rIn + 0.006, teeth * 0.0127 / (2 * Math.PI));
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI * 2, r = i % 2 ? rOut : rOut - toothH;
    i ? s.lineTo(Math.cos(a) * r, Math.sin(a) * r) : s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  const hole = new THREE.Path(); hole.absarc(0, 0, rIn, 0, Math.PI * 2, true); s.holes.push(hole);
  const g = new THREE.ExtrudeGeometry(s, { depth, bevelEnabled: false, curveSegments: 6 });
  g.translate(0, 0, -depth / 2);
  return { g, r: rOut - toothH / 2 };
}
function ring(rIn, rOut, depth, seg = 32) {
  const s = new THREE.Shape(); s.absarc(0, 0, rOut, 0, Math.PI * 2, false);
  const h = new THREE.Path(); h.absarc(0, 0, rIn, 0, Math.PI * 2, true); s.holes.push(h);
  const g = new THREE.ExtrudeGeometry(s, { depth, bevelEnabled: false, curveSegments: seg });
  g.translate(0, 0, -depth / 2);
  return g;
}

// ---------------- build ----------------
export function buildBike(cfgIn, rootName = 'custom') {
  const p = solve(cfgIn), c = p.c;
  const col = c.colors;
  const mats = {
    paint: new THREE.MeshPhysicalMaterial({ name: 'paint', color: col.frame, metalness: 0.25, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.06 }),
    forkpaint: new THREE.MeshPhysicalMaterial({ name: 'forkpaint', color: col.fork, metalness: 0.3, roughness: 0.35, clearcoat: 0.6 }),
    black: new THREE.MeshStandardMaterial({ name: 'black', color: col.parts, metalness: 0.6, roughness: 0.4 }),
    chrome: new THREE.MeshStandardMaterial({ name: 'chrome', color: 0xcfd0d4, metalness: 1, roughness: 0.18 }),
    rim: new THREE.MeshStandardMaterial({ name: 'rim', color: col.rims, metalness: 0.6, roughness: 0.35 }),
    rubber: new THREE.MeshStandardMaterial({ name: 'rubber', color: col.tyres, metalness: 0, roughness: 0.88 }),
    plastic: new THREE.MeshStandardMaterial({ name: 'plastic', color: 0x1b1b1d, metalness: 0, roughness: 0.6 }),
    chain: new THREE.MeshStandardMaterial({ name: 'chain', color: 0x5a5c62, metalness: 0.9, roughness: 0.45 }),
    gold: new THREE.MeshStandardMaterial({ name: 'gold', color: 0xe0a030, metalness: 1, roughness: 0.25 }),
    spring: new THREE.MeshStandardMaterial({ name: 'spring', color: col.spring, metalness: 0.4, roughness: 0.35 }),
  };
  const parts = {};   // node -> material -> [geometries] (world space, except the spring)
  const add = (node, mat, ...gs) => { ((parts[node] ||= {})[mat] ||= []).push(...gs.map(prep)); };
  const tr = c.tube;
  const { BB, A, F, axis, fwd, htTop, htBot, crown, seatDir, stTop } = p;
  const v = (q, z = 0) => V3(q, z);
  const along = (a, b, t) => a.clone().lerp(b, t);
  const full = c.rear === 'fourbar';

  // ---- frame: main triangle ----
  const htMid = along(htTop, htBot, 0.5);
  add('frame', 'paint', tube(v(htTop.clone().addScaledVector(axis, 0.008)), v(htBot.clone().addScaledVector(axis, -0.008)), 0.024 * tr, 0.026 * tr, 16));
  const ttRear = along(BB, stTop, c.ttJoin);
  const ttFront = htTop.clone().addScaledVector(axis, -0.022);
  add('frame', 'paint', tube(v(ttRear), v(ttFront), 0.016 * tr, 0.019 * tr));
  const dtFront = htBot.clone().addScaledVector(axis, 0.03);
  add('frame', 'paint', tube(v(BB), v(dtFront), 0.024 * tr, 0.021 * tr));
  add('frame', 'paint', tube(v(BB), v(stTop), 0.017 * tr, 0.016 * tr));
  add('frame', 'paint', axleCyl(BB.x, BB.y, -0.045, 0.045, 0.022));   // BB shell
  if (c.type === 'bmx') add('frame', 'paint', tube(v(along(htBot, htTop, 0.2)), v(along(BB, dtFront, 0.25)), 0.012 * tr));   // gusset brace

  // ---- seatpost + saddle ----
  const postTop = p.saddle.clone().addScaledVector(seatDir, -0.03);
  add('frame', 'black', tube(v(along(BB, stTop, 0.8)), v(postTop), 0.0155, 0.0155));
  {
    const s = new THREE.Shape(), Ls = c.type === 'bmx' ? 0.22 : 0.26, Wb = c.type === 'bmx' ? 0.065 : 0.07;
    s.moveTo(-Ls * 0.42, -Wb);
    s.bezierCurveTo(-Ls * 0.55, -Wb * 0.2, -Ls * 0.55, Wb * 0.2, -Ls * 0.42, Wb);
    s.bezierCurveTo(-Ls * 0.1, Wb * 1.05, Ls * 0.15, 0.022, Ls * 0.58, 0.016);
    s.bezierCurveTo(Ls * 0.63, 0.008, Ls * 0.63, -0.008, Ls * 0.58, -0.016);
    s.bezierCurveTo(Ls * 0.15, -0.022, -Ls * 0.1, -Wb * 1.05, -Ls * 0.42, -Wb);
    const g = new THREE.ExtrudeGeometry(s, { depth: 0.022, bevelEnabled: true, bevelThickness: 0.012, bevelSize: 0.01, bevelSegments: 3, curveSegments: 8 });
    g.rotateX(Math.PI / 2);                     // shape plane -> XZ, thickness down Y
    g.translate(0, 0.022, 0);
    g.rotateZ(c.saddleTilt * D2R * 0.3);
    g.translate(p.saddle.x + 0.02, p.saddle.y - 0.03, 0);
    add('frame', 'plastic', g);
    add('frame', 'chrome', tube(v(postTop.clone().add(new THREE.Vector2(-0.06, 0.012)), -0.02), v(postTop.clone().add(new THREE.Vector2(0.07, 0.012)), -0.02), 0.0035),
                           tube(v(postTop.clone().add(new THREE.Vector2(-0.06, 0.012)), 0.02), v(postTop.clone().add(new THREE.Vector2(0.07, 0.012)), 0.02), 0.0035));
  }

  // ---- rear end ----
  const dropZ = 0.068;
  if (!full) {
    for (const z of [-1, 1]) {
      add('frame', 'paint', tube(v(BB, z * 0.035), v(A, z * dropZ), 0.012 * tr, 0.009 * tr));
      add('frame', 'paint', tube(v(along(BB, stTop, Math.min(0.97, c.ttJoin + 0.02)), z * 0.02), v(A, z * dropZ), 0.0105 * tr, 0.008 * tr));
      add('frame', 'paint', box(A.x + 0.006, A.y + 0.006, z * dropZ, 0.04, 0.035, 0.006));
    }
    add('frame', 'paint', tube(v(along(BB, A, 0.3), -0.045), v(along(BB, A, 0.3), 0.045), 0.006));
  } else {
    const k = p.link;
    // main pivot + rocker + shock mounts on the front triangle
    add('frame', 'paint', axleCyl(k.G1.x, k.G1.y, -0.045, 0.045, 0.014));
    const nearOn = (q, a, b) => { const ab = b.clone().sub(a); const t = Math.min(1, Math.max(0, q.clone().sub(a).dot(ab) / ab.lengthSq())); return a.clone().addScaledVector(ab, t); };
    add('frame', 'paint', tube(v(k.G1), v(nearOn(k.G1, BB, dtFront)), 0.016 * tr));
    for (const z of [-1, 1]) {
      add('frame', 'paint', tube(v(k.G2, z * 0.022), v(nearOn(k.G2, BB, stTop), z * 0.012), 0.009 * tr));
      add('frame', 'paint', tube(v(k.FE, z * 0.016), v(nearOn(k.FE, BB, dtFront), z * 0.012), 0.009 * tr));
    }
    add('frame', 'chrome', axleCyl(k.G2.x, k.G2.y, -0.03, 0.03, 0.007), axleCyl(k.FE.x, k.FE.y, -0.022, 0.022, 0.006));
    // swing: chainstays G1 -> C1
    for (const z of [-1, 1]) add('swing', 'paint', tube(v(k.G1, z * 0.04), v(k.C1, z * dropZ), 0.013 * tr, 0.01 * tr));
    add('swing', 'paint', tube(v(along(k.G1, k.C1, 0.25), -0.042), v(along(k.G1, k.C1, 0.25), 0.042), 0.007));
    // seatstay: C1 -> A dropout, A -> C2 stays
    for (const z of [-1, 1]) {
      add('seatstay', 'paint', tube(v(k.C1, z * dropZ), v(A, z * dropZ), 0.012));
      add('seatstay', 'paint', box(A.x + 0.004, A.y + 0.004, z * dropZ, 0.042, 0.036, 0.007));
      add('seatstay', 'paint', tube(v(A, z * dropZ), v(k.C2, z * 0.036), 0.011 * tr, 0.012 * tr));
    }
    add('seatstay', 'paint', tube(v(along(A, k.C2, 0.62), -0.04), v(along(A, k.C2, 0.62), 0.04), 0.008));
    add('seatstay', 'chrome', axleCyl(k.C1.x, k.C1.y, -dropZ - 0.006, dropZ + 0.006, 0.006), axleCyl(k.C2.x, k.C2.y, -0.042, 0.042, 0.006));
    // rocker: G2 / C2 / D plates
    for (const z of [-1, 1]) {
      add('rocker', 'paint', tube(v(k.G2, z * 0.03), v(k.C2, z * 0.03), 0.011), tube(v(k.G2, z * 0.03), v(k.D, z * 0.03), 0.011),
                             tube(v(k.C2, z * 0.03), v(k.D, z * 0.03), 0.009));
    }
    add('rocker', 'chrome', axleCyl(k.D.x, k.D.y, -0.034, 0.034, 0.006));
    // shock: body from FE, shaft from D, spring in its own frame (+Y along the shock)
    const dir = k.D.clone().sub(k.FE), L0 = dir.length(); dir.normalize();
    const bodyEnd = k.FE.clone().addScaledVector(dir, L0 * 0.58);
    add('shock_body', 'black', tube(v(k.FE), v(bodyEnd), 0.019, 0.019, 16), axleCyl(k.FE.x, k.FE.y, -0.014, 0.014, 0.011));
    add('shock_body', 'black', tube(v(k.FE.clone().addScaledVector(dir, L0 * 0.15), 0.028), v(k.FE.clone().addScaledVector(dir, L0 * 0.45), 0.028), 0.014));   // reservoir
    add('shock_body', 'chrome', tube(v(k.FE.clone().addScaledVector(dir, L0 * 0.2)), v(k.FE.clone().addScaledVector(dir, L0 * 0.24)), 0.03, 0.03, 20));   // spring collar
    add('shock_shaft', 'chrome', tube(v(k.D), v(k.D.clone().addScaledVector(dir, -L0 * 0.62)), 0.008, 0.008, 12));
    add('shock_shaft', 'black', axleCyl(k.D.x, k.D.y, -0.014, 0.014, 0.011), tube(v(k.D.clone().addScaledVector(dir, -0.02)), v(k.D.clone().addScaledVector(dir, -0.032)), 0.03, 0.03, 20));
    const seat0 = k.FE.clone().addScaledVector(dir, L0 * 0.24);
    const springLen = Math.max(0.04, L0 * 0.76 - 0.032);
    {
      const pts = [], turns = 7, R = 0.026, n = turns * 18;
      for (let i = 0; i <= n; i++) { const a = (i / 18) * Math.PI * 2; pts.push(new THREE.Vector3(Math.cos(a) * R, (i / n) * springLen, Math.sin(a) * R)); }
      add('shock_spring', 'spring', new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), n * 2, 0.0042, 6, false));
    }
    p.spring = { seat: seat0, len: springLen, ang: Math.atan2(dir.y, dir.x) - Math.PI / 2 };
  }

  // ---- fork ----
  const legZ = c.fork === 'rigid' ? 0.052 : 0.074;
  const legAt = (s, z) => v(F.clone().addScaledVector(axis, s), z);   // point on a fork leg, s up from the axle
  const crownS = p.L, travel = c.forkTravel / 1000;
  const lowerNode = c.fork === 'rigid' ? 'steer' : 'fork_lower';
  if (c.fork === 'rigid') {
    for (const z of [-1, 1]) {
      const top = v(crown, z * 0.05), pts = [top, v(crown.clone().addScaledVector(axis, -p.L * 0.5).addScaledVector(fwd, p.off * 0.35), z * 0.052), v(F, z * legZ)];
      add('steer', 'forkpaint', curve(pts, 0.012, 20, 10));
    }
    add('steer', 'forkpaint', tube(v(crown, -0.06), v(crown, 0.06), 0.016));
  } else {
    const sag = 0.2, exposed = travel * (1 - sag) + 0.02, lowerTop = Math.max(0.12, crownS - exposed);
    const topS = c.fork === 'dual' ? crownS + (htTop.distanceTo(htBot)) + 0.03 : crownS + 0.01;
    for (const z of [-1, 1]) {
      add('steer', c.fork === 'dual' ? 'gold' : 'chrome', tube(legAt(lowerTop - 0.08, z * legZ), legAt(topS, z * legZ), 0.017, 0.017, 16));
      add('fork_lower', 'forkpaint', tube(legAt(-0.02, z * legZ), legAt(lowerTop, z * legZ), 0.022, 0.024, 16));
      add('fork_lower', 'black', tube(legAt(lowerTop - 0.004, z * legZ), legAt(lowerTop + 0.012, z * legZ), 0.0215, 0.0195, 16));   // seal
    }
    const arch = [legAt(lowerTop - 0.03, -legZ), v(F.clone().addScaledVector(axis, lowerTop - 0.005).addScaledVector(fwd, 0.035), 0), legAt(lowerTop - 0.03, legZ)];
    add('fork_lower', 'forkpaint', curve(arch, 0.013, 16, 8));
    // crowns: across the legs and back to the steerer
    const crowns = c.fork === 'dual' ? [crownS, topS - 0.012] : [crownS];
    for (const s of crowns) {
      const mid = F.clone().addScaledVector(axis, s), st = mid.clone().addScaledVector(fwd, -p.off);
      add('steer', 'black', tube(legAt(s, -legZ - 0.012), legAt(s, legZ + 0.012), 0.016, 0.016, 12), tube(v(mid), v(st), 0.02));
    }
  }
  add(lowerNode, 'black', axleCyl(F.x, F.y, -0.07, 0.07, 0.007));

  // ---- cockpit ----
  const steerTop = htTop.clone().addScaledVector(axis, c.fork === 'dual' ? 0.06 : 0.03);
  add('steer', 'black', tube(v(htTop), v(steerTop.clone().addScaledVector(axis, 0.01)), 0.0145));
  const stemDir = c.fork === 'dual' ? new THREE.Vector2(1, 0) : fwd.clone();
  const clamp = steerTop.clone().addScaledVector(stemDir, c.stem / 1000);
  add('steer', 'black', tube(v(steerTop.clone().addScaledVector(stemDir, -0.012)), v(clamp), 0.016, 0.017));
  add('steer', 'black', axleCyl(clamp.x, clamp.y, -0.03, 0.03, 0.021));
  const W = c.barWidth / 2000, rise = c.barRise / 1000, back = c.bar === 'bmx' ? 0.025 : 0.018;
  let gripPts;
  if (c.bar === 'bmx') {
    for (const z of [-1, 1]) {
      const pts = [v(clamp, z * 0.02), v(clamp.clone().add(new THREE.Vector2(-0.004, rise * 0.15)), z * 0.07),
                   v(clamp.clone().add(new THREE.Vector2(-back * 0.6, rise * 0.95)), z * 0.13), v(clamp.clone().add(new THREE.Vector2(-back, rise)), z * 0.2),
                   v(clamp.clone().add(new THREE.Vector2(-back * 1.3, rise + 0.004)), z * W)];
      add('steer', 'chrome', curve(pts, 0.011, 30, 10));
    }
    add('steer', 'chrome', tube(v(clamp.clone().add(new THREE.Vector2(-back * 0.45, rise * 0.62)), -0.115), v(clamp.clone().add(new THREE.Vector2(-back * 0.45, rise * 0.62)), 0.115), 0.0095));
    gripPts = (z) => [v(clamp.clone().add(new THREE.Vector2(-back * 1.28, rise + 0.004)), z * (W - 0.14)), v(clamp.clone().add(new THREE.Vector2(-back * 1.3, rise + 0.004)), z * (W + 0.005))];
  } else {
    for (const z of [-1, 1]) {
      const pts = [v(clamp, 0), v(clamp, z * 0.05), v(clamp.clone().add(new THREE.Vector2(-0.002, rise * 0.6)), z * 0.11),
                   v(clamp.clone().add(new THREE.Vector2(-back * 0.6, rise)), z * 0.2), v(clamp.clone().add(new THREE.Vector2(-back, rise)), z * W)];
      add('steer', 'black', curve(pts, 0.0115, 30, 10));
    }
    gripPts = (z) => [v(clamp.clone().add(new THREE.Vector2(-back * 0.97, rise)), z * (W - 0.135)), v(clamp.clone().add(new THREE.Vector2(-back, rise)), z * (W + 0.004))];
  }
  for (const z of [-1, 1]) { const [a, b] = gripPts(z); add('steer', 'rubber', tube(a, b, 0.0165, 0.0165, 14)); }
  if (c.discs) {   // brake levers
    for (const z of [-1, 1]) {
      const [a] = gripPts(z), at = a.clone().add(new THREE.Vector3(0, 0, -z * 0.015));
      add('steer', 'black', tube(at, at.clone().add(new THREE.Vector3(0.07, -0.02, z * 0.035)), 0.004));
    }
  }

  // ---- wheels ----
  const wheel = (node, cx, cy, size, tyreW, isFront) => {
    const rimR = WHEELS[size] / 2000, tH = tyreW * 0.0254 * 0.95, Rt = rimR + tH * 0.5;
    const tyre = new THREE.TorusGeometry(Rt, tH * 0.5, 12, 72); tyre.scale(1, 1, (tyreW * 0.0254) / tH); tyre.translate(cx, cy, 0);
    add(node, 'rubber', tyre);
    if (c.knobs) {
      const n = Math.round(Rt * 2 * Math.PI / 0.022), ko = Rt + tH * 0.5;
      const knobs = [];
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2;
        for (const z of (i % 2 ? [-0.36, 0.36] : [0, -0.62, 0.62])) {
          const g = new THREE.BoxGeometry(0.008, 0.011, 0.01);
          g.translate(ko - (Math.abs(z) > 0.5 ? 0.006 : 0.001), 0, z * tyreW * 0.0254 * 0.5);
          if (Math.abs(z) > 0.5) g.rotateY(0);
          g.rotateZ(a); g.translate(cx, cy, 0); knobs.push(g);
        }
      }
      add(node, 'rubber', mergeGeometries(knobs.map(prep)));
    }
    const rim = new THREE.TorusGeometry(rimR - 0.004, 0.011, 8, 72); rim.scale(1, 1, 1.25); rim.translate(cx, cy, 0);
    add(node, 'rim', rim);
    add(node, 'chrome', axleCyl(cx, cy, -0.05, 0.05, 0.017, 16));
    const spokes = [], ns = c.type === 'bmx' ? 36 : 32;
    for (let i = 0; i < ns; i++) {
      const side = i % 2 ? 1 : -1, a0 = (i / ns) * Math.PI * 2, a1 = a0 + side * 0.35;
      const h = new THREE.Vector3(cx + Math.cos(a0) * 0.026, cy + Math.sin(a0) * 0.026, side * 0.032);
      const r = new THREE.Vector3(cx + Math.cos(a1) * (rimR - 0.012), cy + Math.sin(a1) * (rimR - 0.012), side * 0.004);
      spokes.push(prep(tube(h, r, 0.0011, 0.0011, 3)));
    }
    add(node, 'chrome', mergeGeometries(spokes));
    if (c.discs) { const d = ring(0.05, isFront ? 0.1 : 0.09, 0.002, 40); d.translate(cx, cy, -0.05); add(node, 'chrome', d); }
  };
  wheel('wheel_front', F.x, F.y, c.wheelF, c.tyreF, true);
  wheel('wheel_rear', A.x, A.y, c.wheelR, c.tyreR, false);
  const rearMount = full ? 'seatstay' : 'frame';
  add(rearMount, 'black', axleCyl(A.x, A.y, -0.078, 0.078, 0.007));
  if (c.discs) {   // calipers
    const cr = A.clone().add(new THREE.Vector2(0.06, 0.055));
    add(rearMount, 'black', box(cr.x, cr.y, -0.06, 0.05, 0.03, 0.025, 0.6));
    const cf = F.clone().addScaledVector(axis, 0.07).addScaledVector(fwd, -0.035);
    add(lowerNode, 'black', box(cf.x, cf.y, -0.062, 0.05, 0.03, 0.025, Math.atan2(axis.y, axis.x)));
  }
  if (c.pegs) {
    add('frame', 'chrome', axleCyl(A.x, A.y, -0.19, -0.075, 0.019), axleCyl(A.x, A.y, 0.075, 0.19, 0.019));
    add(lowerNode, 'chrome', axleCyl(F.x, F.y, -0.18, -0.06, 0.019), axleCyl(F.x, F.y, 0.06, 0.18, 0.019));
  }

  // ---- drivetrain ----
  const chainZ = 0.05;
  const ringG = gear(c.ring, 0.03, 0.004); ringG.g.translate(BB.x, BB.y, chainZ); add('crank', 'black', ringG.g);
  const cogs = c.type === 'bmx' || c.type === 'dj' ? [c.cog] : [c.cog, Math.round(c.cog * 0.75), Math.round(c.cog * 0.55), Math.round(c.cog * 0.4), 11];
  let cogR = 0;
  cogs.forEach((t, i) => {
    const gg = gear(Math.max(9, t), 0.012, 0.0025, 0.003); gg.g.translate(A.x, A.y, chainZ + i * 0.0045);
    add('wheel_rear', 'chrome', gg.g); if (!i) cogR = gg.r;
  });
  {   // chain: outer tangents between chainring and the big cog
    const r1 = ringG.r, r2 = cogR, d = A.distanceTo(BB), b = Math.atan2(A.y - BB.y, A.x - BB.x);
    const al = Math.acos(Math.max(-1, Math.min(1, (r1 - r2) / d)));
    const pts = [], arc = (cx, cy, r, a0, a1, n) => { for (let i = 0; i <= n; i++) { const a = a0 + (a1 - a0) * i / n; pts.push(new THREE.Vector3(cx + Math.cos(a) * r, cy + Math.sin(a) * r, chainZ)); } };
    let s0 = b + al, s1 = b - al; while (s1 < s0) s1 += Math.PI * 2;
    arc(BB.x, BB.y, r1, s0, s1, 24);                       // round the front of the chainring
    let t0 = b - al, t1 = b + al; while (t1 < t0) t1 += Math.PI * 2;
    arc(A.x, A.y, r2, t0, t1, 12);                          // round the back of the cog
    add(full ? 'swing' : 'frame', 'chain', curve(pts, 0.0032, 140, 5, true));
  }
  const Lc = c.crank / 1000;
  add('crank', 'black', axleCyl(BB.x, BB.y, -0.075, 0.075, 0.011));
  for (const z of [-1, 1]) {
    const a = z > 0 ? -Math.PI / 2 - 0.5 : Math.PI / 2 - 0.5;   // right arm and left arm opposite
    const end = new THREE.Vector2(BB.x + Math.cos(a) * Lc, BB.y + Math.sin(a) * Lc);
    add('crank', 'black', tube(v(BB, z * 0.072), v(end, z * 0.078), 0.012, 0.009, 8));
    const pedal = new THREE.BoxGeometry(0.1, 0.018, 0.1); pedal.translate(end.x, end.y, z * 0.135);
    add('crank', 'plastic', pedal);
  }

  // ---- nodes ----
  const pivots = {
    frame: new THREE.Vector3(), steer: v(htMid), fork_lower: v(F), wheel_front: v(F), wheel_rear: v(A), crank: v(BB),
  };
  const parent = { fork_lower: 'steer', wheel_front: c.fork === 'rigid' ? 'steer' : 'fork_lower', wheel_rear: full ? 'seatstay' : null, shock_spring: 'shock_body' };
  if (full) Object.assign(pivots, { swing: v(p.link.G1), seatstay: v(p.link.C1), rocker: v(p.link.G2), shock_body: v(p.link.FE), shock_spring: v(p.spring.seat), shock_shaft: v(p.link.D) });
  const order = ['frame', 'steer', 'fork_lower', 'wheel_front', 'swing', 'seatstay', 'wheel_rear', 'rocker', 'shock_body', 'shock_spring', 'shock_shaft', 'crank']
    .filter(n => pivots[n] && (n !== 'fork_lower' || c.fork !== 'rigid'));
  const root = new THREE.Group(); root.name = rootName;
  const nodes = {};
  let tris = 0;
  for (const name of order) {
    const g = new THREE.Group(); g.name = name; nodes[name] = g;
    for (const [mat, list] of Object.entries(parts[name] || {})) {
      const geo = mergeGeometries(list);
      if (name !== 'shock_spring') geo.translate(-pivots[name].x, -pivots[name].y, -pivots[name].z);
      geo.computeBoundingSphere();
      const mesh = new THREE.Mesh(geo, mats[mat]); mesh.name = `${name}_${mat}`;
      tris += geo.index.count / 3;
      g.add(mesh);
    }
  }
  for (const name of order) {
    const par = parent[name] && nodes[parent[name]] ? parent[name] : null;
    nodes[name].position.copy(pivots[name]).sub(par ? pivots[par] : new THREE.Vector3());
    if (name === 'shock_spring') nodes[name].rotation.z = p.spring.ang;
    (par ? nodes[par] : root).add(nodes[name]);
  }
  const ax = [axis.x, axis.y, 0];
  root.userData = {
    steerAxis: ax, wheelRadius: F.y, wheelRadiusRear: A.y, wheelbase: F.x - A.x, bbToRearAxle: BB.x - A.x,
    dims: p.dims, tris, config: c,
  };
  if (c.fork !== 'rigid' || full) {
    root.userData.suspension = {
      fork: c.fork !== 'rigid' ? { travel: travel, sag: 0.2 } : null,
      rear: full ? { travel: c.rearTravel / 1000, sag: 0.3, springLen: p.spring.len,
        ...Object.fromEntries(['G1', 'G2', 'C1', 'C2', 'A', 'D', 'FE'].map(k => [k, [p.link[k].x, p.link[k].y]])) } : null,
    };
  }
  return root;
}

// ride feel for a built bike: 0 = BMX (nimble), 1 = DH (planted). Interpolates the DH ride / pose multipliers
export const STYLE_K = { bmx: 0, dj: 0.25, trail: 0.6, dh: 1 };

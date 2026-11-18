import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Low-poly garden/trail sheds. Each design is one merged, vertex-coloured, flat-shaded geometry
// (walls, battens, roof, door, window, foundation, a few props), so a chunk draws all of its sheds
// of one design with a single InstancedMesh. Local frame: door faces +z, floor at y = 0.2,
// the foundation reaches down to y = -0.7 so it hides any slope under the footprint.

export const MAT_SHED = new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.85 });

const C = (h) => new THREE.Color(h);
function paint(g, col) {
  g = g.index ? g.toNonIndexed() : g;
  g.deleteAttribute('uv');
  const n = g.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = col.r; a[i * 3 + 1] = col.g; a[i * 3 + 2] = col.b; }
  g.setAttribute('color', new THREE.BufferAttribute(a, 3));
  return g;
}
const box = (w, h, d, x, y, z, col, rx = 0, ry = 0, rz = 0) => {
  const g = new THREE.BoxGeometry(w, h, d);
  if (rx) g.rotateX(rx); if (ry) g.rotateY(ry); if (rz) g.rotateZ(rz);
  return paint(g.translate(x, y, z), col);
};
const cyl = (r, h, x, y, z, col, seg = 6, axis = 'y') => {
  const g = new THREE.CylinderGeometry(r, r, h, seg);
  if (axis === 'x') g.rotateZ(Math.PI / 2); if (axis === 'z') g.rotateX(Math.PI / 2);
  return paint(g.translate(x, y, z), col);
};
// closed prism: a 2D polygon in the (a, y) plane swept along `axis` ('z' -> a is x, 'x' -> a is z)
function prism(pts, from, to, axis, col) {
  const s = new THREE.Shape(pts.map(([a, y]) => new THREE.Vector2(a, y)));
  const g = new THREE.ExtrudeGeometry(s, { depth: to - from, bevelEnabled: false });
  g.translate(0, 0, from);
  if (axis === 'x') g.rotateY(-Math.PI / 2);   // a -> z, sweep -> -x (sweeps are symmetric)
  g.computeVertexNormals();
  return paint(g, col);
}

// vertical board-and-batten strips along one wall: from (x0,z0) to (x1,z1), facing out by `n`
function battens(out, x0, z0, x1, z1, nx, nz, y0, y1, col, step = 0.42) {
  const len = Math.hypot(x1 - x0, z1 - z0), k = Math.max(1, Math.round(len / step));
  for (let i = 1; i < k; i++) {
    const t = i / k, x = x0 + (x1 - x0) * t + nx * 0.03, z = z0 + (z1 - z0) * t + nz * 0.03;
    const top = typeof y1 === 'function' ? y1(x, z) : y1;
    out.push(box(nx ? 0.04 : 0.06, top - y0, nx ? 0.06 : 0.04, x, (y0 + top) / 2, z, col));
  }
}

function door(out, x, z, w, h, y0, wood, trim, metal) {
  out.push(box(w + 0.14, h + 0.08, 0.05, x, y0 + (h + 0.08) / 2, z + 0.02, trim));   // frame
  out.push(box(w, h, 0.06, x, y0 + h / 2, z + 0.05, wood));
  for (const yy of [0.22, h - 0.22]) out.push(box(w - 0.04, 0.1, 0.03, x, y0 + yy, z + 0.09, trim));
  const diag = Math.atan2(h - 0.44, w - 0.1);
  out.push(box(Math.hypot(w - 0.1, h - 0.44), 0.09, 0.03, x, y0 + h / 2, z + 0.09, trim, 0, 0, diag));
  out.push(box(0.05, 0.05, 0.06, x + w / 2 - 0.12, y0 + h * 0.5, z + 0.12, metal));   // handle
}
function windowSide(out, x, z, w, h, yc, frame, glass) {   // on a wall facing +x
  out.push(box(0.05, h + 0.12, w + 0.12, x + 0.02, yc, z, frame));
  out.push(box(0.04, h, w, x + 0.04, yc, z, glass));
  out.push(box(0.03, h, 0.05, x + 0.07, yc, z, frame));
  out.push(box(0.03, 0.05, w, x + 0.07, yc, z, frame));
  out.push(box(0.16, 0.05, w + 0.2, x + 0.08, yc - h / 2 - 0.08, z, frame));         // sill
  out.push(box(0.12, 0.2, w + 0.08, x + 0.1, yc - h / 2 - 0.2, z, C(0x7a4a2a)));     // flower box
  for (const dz of [-0.2, 0, 0.2]) out.push(box(0.1, 0.1, 0.1, x + 0.12, yc - h / 2 - 0.05, z + dz * w * 1.6, C(dz ? 0xff5d73 : 0xffd23f), 0.5, 0.5, 0));
}

const STONE = C(0x8d8a84), STONE_D = C(0x6e6b66), GLASS = C(0x2c3d4a), METAL = C(0x3a3a3a);

// classic gable shed: door in the front gable, window on the side, rain barrel by the corner
function gable(p) {
  const W = 2.6, D = 3.2, F = 0.2, E = 2.05, R = 3.0, o = [];
  const hw = W / 2, hd = D / 2;
  o.push(box(W + 0.24, 0.9, D + 0.24, 0, F - 0.45, 0, STONE));
  o.push(box(0.9, 0.12, 0.45, 0, F - 0.06, hd + 0.3, STONE_D));                       // step
  o.push(box(W, E - F, D, 0, (E + F) / 2, 0, p.wall));
  o.push(prism([[-hw, E], [hw, E], [0, R]], -hd, hd, 'z', p.wall));                    // gable fill
  const roofY = (x) => E + (R - E) * (1 - Math.abs(x) / hw);
  battens(o, -hw, hd, hw, hd, 0, 1, F, (x) => roofY(x) - 0.05, p.batten);
  battens(o, -hw, -hd, hw, -hd, 0, -1, F, (x) => roofY(x) - 0.05, p.batten);
  battens(o, hw, -hd, hw, hd, 1, 0, F, E, p.batten);
  battens(o, -hw, -hd, -hw, hd, -1, 0, F, E, p.batten);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) o.push(box(0.12, E - F, 0.12, sx * (hw + 0.01), (E + F) / 2, sz * (hd + 0.01), p.trim));
  // roof: two panels with an overhang, ridge cap, fascia boards on the gables
  const pitch = Math.atan2(R - E, hw), ov = 0.32, sl = Math.hypot(hw, R - E) + ov, T = 0.09;
  for (const s of [-1, 1]) {
    const cx = s * (hw + ov * Math.cos(pitch) - sl * Math.cos(pitch) / 2) , cy = R - (sl / 2 - 0) * Math.sin(pitch) + T * 0.6;
    o.push(box(sl, T, D + 0.6, cx, cy, 0, p.roof, 0, 0, -s * pitch));
    // a couple of raised seams so the roof catches the light
    for (const f of [0.3, 0.62]) {
      const along = sl * (f - 0.5);
      o.push(box(0.05, 0.04, D + 0.6, cx + s * along * Math.cos(pitch), cy - along * Math.sin(pitch) + T * 0.55, 0, p.roofD, 0, 0, -s * pitch));
    }
    for (const zz of [-1, 1]) o.push(box(sl, 0.16, 0.05, cx, cy - 0.06, zz * (hd + 0.3), p.trim, 0, 0, -s * pitch));
  }
  o.push(box(0.2, 0.12, D + 0.66, 0, R + T + 0.02, 0, p.roofD, 0, Math.PI / 4 * 0, 0));
  door(o, 0, hd, 0.95, 1.8, F, p.door, p.trim, METAL);
  o.push(box(0.36, 0.36, 0.05, 0, E + 0.38, hd + 0.04, p.trim, 0, 0, Math.PI / 4));   // gable vent
  o.push(box(0.24, 0.24, 0.05, 0, E + 0.38, hd + 0.07, GLASS, 0, 0, Math.PI / 4));
  windowSide(o, hw, -0.2, 0.8, 0.6, 1.35, p.trim, GLASS);
  // rain barrel at the front corner + a short gutter pipe
  o.push(cyl(0.3, 0.75, hw + 0.42, F + 0.37, hd - 0.4, C(0x4d6b8a), 8));
  for (const yy of [0.2, 0.55]) o.push(cyl(0.315, 0.05, hw + 0.42, F + yy, hd - 0.4, METAL, 8));
  o.push(cyl(0.04, E - 0.85, hw + 0.36, (E + 0.9) / 2, hd - 0.4, C(0x9aa0a4), 5));
  return mergeGeometries(o);
}

// lean-to shed: mono-pitch roof, double doors, a firewood pile stacked under the side eave
function leanTo(p) {
  const W = 2.4, D = 1.9, F = 0.2, Hf = 2.25, Hb = 1.75, o = [];
  const hw = W / 2, hd = D / 2;
  o.push(box(W + 0.24, 0.9, D + 0.24, 0, F - 0.45, 0, STONE));
  o.push(box(W, Hb - F, D, 0, (Hb + F) / 2, 0, p.wall));
  o.push(prism([[-hd, Hb], [hd, Hb], [hd, Hf]], -hw, hw, 'x', p.wall));             // wedge, tall at the front
  const topY = (z) => Hb + (Hf - Hb) * (z + hd) / D - 0.04;
  battens(o, -hw, hd, hw, hd, 0, 1, F, Hf - 0.04, p.batten, 0.36);
  battens(o, -hw, -hd, hw, -hd, 0, -1, F, Hb - 0.04, p.batten, 0.36);
  battens(o, hw, -hd, hw, hd, 1, 0, F, (x, z) => topY(z), p.batten, 0.36);
  battens(o, -hw, -hd, -hw, hd, -1, 0, F, (x, z) => topY(z), p.batten, 0.36);
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const top = sz > 0 ? Hf : Hb;
    o.push(box(0.12, top - F, 0.12, sx * (hw + 0.01), (top + F) / 2, sz * (hd + 0.01), p.trim));
  }
  const pitch = Math.atan2(Hf - Hb, D), ov = 0.35, sl = Math.hypot(D, Hf - Hb) + ov * 2, T = 0.09;
  const ry = (Hf + Hb) / 2 + T * 0.7;
  o.push(box(W + 0.7, T, sl, 0, ry, 0, p.roof, -pitch, 0, 0));
  for (const f of [-0.33, 0, 0.33]) o.push(box(0.05, 0.04, sl, f * W, ry + T * 0.55, 0, p.roofD, -pitch, 0, 0));
  o.push(box(W + 0.74, 0.16, 0.05, 0, Hf + 0.04 + ov * Math.sin(pitch), hd + ov, p.trim));   // fascia
  for (const s of [-1, 1]) door(o, s * 0.42, hd, 0.8, 1.75, F, p.door, p.trim, METAL);
  // firewood under the eave on the +x side: rows of short logs, end-grain facing out
  const LOG = C(0x8a5a34), END = C(0xd9b27c);
  for (let r = 0; r < 4; r++) for (let i = 0; i < 6 - (r > 2 ? 1 : 0); i++) {
    const z = -hd + 0.2 + i * 0.27 + (r & 1) * 0.13, y = F + 0.12 + r * 0.22;
    o.push(cyl(0.11, 0.5, hw + 0.33, y, z, LOG, 6, 'x'));
    o.push(cyl(0.095, 0.02, hw + 0.59, y, z, END, 6, 'x'));
  }
  // chopping block with an axe
  o.push(cyl(0.22, 0.42, -hw - 0.5, F + 0.0, hd + 0.2, LOG, 7));
  o.push(cyl(0.2, 0.02, -hw - 0.5, F + 0.22, hd + 0.2, END, 7));
  o.push(box(0.04, 0.55, 0.04, -hw - 0.5, F + 0.48, hd + 0.2, C(0xb08955), 0, 0, 0.35));
  o.push(box(0.03, 0.12, 0.16, -hw - 0.58, F + 0.27, hd + 0.2, METAL, 0, 0, 0.35));
  return mergeGeometries(o);
}

const PALETTES = [
  { wall: C(0xb5462f), batten: C(0x9a3a27), trim: C(0xf0e6d0), roof: C(0x4a4440), roofD: C(0x3a3532), door: C(0xa63f2a) },   // barn red
  { wall: C(0x6f948d), batten: C(0x5e817b), trim: C(0xf1ede2), roof: C(0x8a3b2e), roofD: C(0x6e2e24), door: C(0x3f6b73) },   // sage + terracotta
  { wall: C(0xa8743f), batten: C(0x8c5e31), trim: C(0x6b4528), roof: C(0x8d949a), roofD: C(0x6f767c), door: C(0x7c5230) },   // natural wood, tin roof
  { wall: C(0xe4d6b0), batten: C(0xd3c39a), trim: C(0x5a6e48), roof: C(0x5a6e48), roofD: C(0x46583a), door: C(0x6f8a52) },   // cream + moss green
];

// footprint (local, metres) and wall outline for colliders, per design
const SHAPES = {
  gable: { build: gable, hw: 1.3, hd: 1.6, extra: [[1.72, 1.2, 0.35]] },        // barrel
  leanTo: { build: leanTo, hw: 1.2, hd: 0.95, extra: [[1.55, -0.4, 0.3], [1.55, 0.4, 0.3], [-1.7, 1.15, 0.25]] },   // logs, block
};
export const SHED_DESIGNS = [];
for (const [name, s] of Object.entries(SHAPES)) PALETTES.forEach((p, i) => SHED_DESIGNS.push({ name, pal: i, s, geo: null }));
export function shedGeo(d) { return d.geo || (d.geo = d.s.build(PALETTES[d.pal])); }

// solid colliders (circles, no `top`: you can't ride over a shed) along the walls, in world space
export function shedColliders(d, x, z, yaw, out) {
  const { hw, hd, extra } = d.s, c = Math.cos(yaw), s = Math.sin(yaw), r = 0.38;
  const add = (lx, lz, rr) => out.push({ x: x + lx * c + lz * s, z: z - lx * s + lz * c, r: rr });
  for (const [ax, az, bx, bz] of [[-hw, -hd, hw, -hd], [hw, -hd, hw, hd], [hw, hd, -hw, hd], [-hw, hd, -hw, -hd]]) {
    const n = Math.ceil(Math.hypot(bx - ax, bz - az) / 0.5);
    for (let i = 0; i < n; i++) add(ax + (bx - ax) * i / n, az + (bz - az) * i / n, r);
  }
  for (const [lx, lz, rr] of extra) add(lx, lz, rr);
}

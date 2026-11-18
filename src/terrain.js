import * as THREE from 'three';
import { ImprovedNoise } from 'three/addons/math/ImprovedNoise.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { PROFILES, FEATURE_TYPES, ROUTE_TYPES, WOOD, DIG } from './features.js';
import { MAT_SHED, SHED_DESIGNS, shedGeo, shedColliders } from './sheds.js';
import { FENCE_MAT, FENCE_GEO, SPAN, buildFence, bindFences } from './fences.js';
import { buildTape } from './tape.js';

const perlin = new ImprovedNoise();
export const WATER = -2.2;

const JC = 34;
// the start: a long ridge you roll down from spawn along +x, with a main trail down its spine
const HILL_TOP = 58, HILL_LEN = 520, ROUTE_END = HILL_LEN + 90, ROUTE_GAP = 46;   // one trail feature per JC x JC metre cell (most cells)
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const smoother = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * t * (t * (6 * t - 15) + 10); };
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------- shared low-poly decoration geometry ----------
// smooth, natural boulder: subdivided sphere pushed around by layered 3D noise, flat-ish base,
// darker in the crevices, a touch lighter/mossy on top (vertex colours multiply the instance colour)
function makeBoulder(seed) {
  const g = new THREE.IcosahedronGeometry(1, 4);
  const p = g.attributes.position, v = new THREE.Vector3();
  const h3 = (x, y, z) => { const n = Math.sin(x * 127.1 + y * 311.7 + z * 74.7 + seed * 13.1) * 43758.5453; return n - Math.floor(n); };
  const vn = (x, y, z) => {   // smooth 3D value noise
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), xf = x - xi, yf = y - yi, zf = z - zi;
    const u = xf * xf * (3 - 2 * xf), w = yf * yf * (3 - 2 * yf), t = zf * zf * (3 - 2 * zf);
    const L = (a, b, k) => a + (b - a) * k;
    return L(L(L(h3(xi, yi, zi), h3(xi + 1, yi, zi), u), L(h3(xi, yi + 1, zi), h3(xi + 1, yi + 1, zi), u), w),
             L(L(h3(xi, yi, zi + 1), h3(xi + 1, yi, zi + 1), u), L(h3(xi, yi + 1, zi + 1), h3(xi + 1, yi + 1, zi + 1), u), w), t);
  };
  const fbm = (x, y, z) => vn(x, y, z) * 0.55 + vn(x * 2.1, y * 2.1, z * 2.1) * 0.28 + vn(x * 4.3, y * 4.3, z * 4.3) * 0.12 + vn(x * 9, y * 9, z * 9) * 0.05;
  const rad = new Float32Array(p.count);
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    let r = 0.78 + fbm(v.x * 1.4 + 5, v.y * 1.4, v.z * 1.4 - 3) * 0.55;
    // a couple of broad facets so it reads as stone, not a potato
    r *= 1 - 0.12 * Math.max(0, v.dot(new THREE.Vector3(0.6, 0.5, 0.62).normalize()) - 0.55) * 3;
    v.multiplyScalar(r);
    if (v.y < -0.25) v.y = -0.25 + (v.y + 0.25) * 0.25;   // sits flat in the ground
    v.y *= 0.82;
    p.setXYZ(i, v.x, v.y, v.z); rad[i] = r;
  }
  g.computeVertexNormals();
  const col = new Float32Array(p.count * 3);
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const ny = g.attributes.normal.getY(i);
    const cav = Math.min(1, Math.max(0, (rad[i] - 0.8) / 0.45));          // low spots = crevices
    const speck = 0.9 + h3(v.x * 40, v.y * 40, v.z * 40) * 0.2;
    let c = (0.62 + cav * 0.45) * speck;
    const moss = Math.max(0, ny - 0.55) * 1.6 * (0.5 + 0.5 * vn(v.x * 3, v.y * 3, v.z * 3));
    col[i * 3] = c * (1 - moss * 0.35); col[i * 3 + 1] = c * (1 + moss * 0.05); col[i * 3 + 2] = c * (1 - moss * 0.45);
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return g;
}

function jitter(geo, amt, seed) {
  const r = mulberry32(seed), p = geo.attributes.position;
  const map = new Map();
  for (let i = 0; i < p.count; i++) {
    const k = `${p.getX(i).toFixed(3)},${p.getY(i).toFixed(3)},${p.getZ(i).toFixed(3)}`;
    if (!map.has(k)) map.set(k, [(r() - .5) * amt, (r() - .5) * amt, (r() - .5) * amt]);
    const d = map.get(k);
    p.setXYZ(i, p.getX(i) + d[0], p.getY(i) + d[1], p.getZ(i) + d[2]);
  }
  geo.computeVertexNormals();
  return geo;
}
const GEO = {
  trunk: new THREE.CylinderGeometry(0.1, 0.16, 1, 5).translate(0, 0.5, 0),
  blob: jitter(new THREE.IcosahedronGeometry(1, 0), 0.35, 7),
  pine: mergeGeometries([
    new THREE.ConeGeometry(1, 1.6, 6).translate(0, 0.8, 0),
    new THREE.ConeGeometry(0.75, 1.3, 6).translate(0, 1.6, 0),
    new THREE.ConeGeometry(0.45, 1.0, 6).translate(0, 2.3, 0),
  ]),
  rock: makeBoulder(3),
  box: new THREE.BoxGeometry(1, 1, 1),
  cactus: mergeGeometries([
    new THREE.CylinderGeometry(0.16, 0.18, 1.6, 6).translate(0, 0.8, 0),
    new THREE.CylinderGeometry(0.1, 0.1, 0.5, 6).rotateZ(Math.PI / 2).translate(0.3, 0.75, 0),
    new THREE.CylinderGeometry(0.1, 0.1, 0.55, 6).translate(0.5, 1.0, 0),
    new THREE.CylinderGeometry(0.09, 0.09, 0.4, 6).rotateZ(Math.PI / 2).translate(-0.25, 1.05, 0),
    new THREE.CylinderGeometry(0.09, 0.09, 0.45, 6).translate(-0.42, 1.25, 0),
  ].map(g => { g.deleteAttribute('uv'); return g; })),
  tuft: mergeGeometries([0, 1, 2].map(i => {
    const g = new THREE.ConeGeometry(0.05, 0.32, 3);
    g.translate(0, 0.16, 0); g.rotateZ(0.35); g.rotateY(i * 2.1);
    return g;
  })),
  flower: mergeGeometries([
    new THREE.CylinderGeometry(0.008, 0.008, 0.22, 3).translate(0, 0.11, 0).toNonIndexed(),
    new THREE.IcosahedronGeometry(0.05, 0).translate(0, 0.23, 0),
  ].map(g => { g.deleteAttribute('uv'); return g; })),
};
export const MAT = {
  terrain: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95 }),
  wood: new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.85, flatShading: true }),
  trunk: new THREE.MeshStandardMaterial({ color: 0x7a5233, flatShading: true, roughness: 0.9 }),
  leaf: new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.8 }),
  rock: new THREE.MeshStandardMaterial({ color: 0xa8a39a, vertexColors: true, roughness: 0.82, metalness: 0.02 }),
  tuft: new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.9 }),
  flower: new THREE.MeshStandardMaterial({ color: 0xffffff, flatShading: true, roughness: 0.6 }),
};
const C = (h) => new THREE.Color(h);
const COL = {
  grassA: C(0x83c44e), grassB: C(0x5fa83c), meadow: C(0xb5cf5c), dirt: C(0xc98d55), dirtDark: C(0xa56d3e),
  sand: C(0xe6d39a), bed: C(0xb3a06c), rock: C(0x8f8a80), snowish: C(0xd9dcc8),
  // biomes
  dryGrass: C(0xc9b45a), dune: C(0xedc98a), duneDark: C(0xd9aa66), desertDirt: C(0xd49a5c),
  red: C(0xc2603a), redLight: C(0xe38c55), redDark: C(0x8f4029), cream: C(0xf0d3a2),
  tuftGreen: C(0x5e9e37), tuftDry: C(0xb59a4a),
  grey: C(0x8d8a86), greyDark: C(0x5f5d5c), greyLight: C(0xb4b0a8), snow: C(0xf4f7f8), alpine: C(0x6f9a4a),
};
const _c = new THREE.Color(), _c2 = new THREE.Color(), _c3 = new THREE.Color();
const RED_BANDS = [COL.red, COL.redLight, COL.redDark, COL.cream, COL.red, COL.redLight];
const GREY_BANDS = [COL.grey, COL.greyDark, COL.greyLight, COL.grey, COL.greyDark];
const LEAVES = [0x4f9a3a, 0x6cb544, 0x3f8a3f, 0x86c24a, 0x9bc94a, 0xe0a43a].map(C);
const PINES = [0x2f6e45, 0x3b7d4b, 0x2a5f44].map(C);
const PLANKS = [0xb98a55, 0xa87a48, 0xc49663, 0x9e6f40, 0xb0814e].map(C), BEAM = C(0x7a5332);
const _Y = new THREE.Vector3(0, 1, 0), _Z = new THREE.Vector3(0, 0, 1);
const CACTI = [0x4f8a3c, 0x5c9a45, 0x6b9e4a].map(C);
const FLOWERS = [0xff5d73, 0xffd23f, 0xffffff, 0x9b6bff, 0xff8f3f].map(C);

export class Terrain {
  constructor(scene, seed) {
    this.scene = scene;
    this.size = 48; this.seg = 128; this.radius = 3;
    this.chunks = new Map();
    this.setSeed(seed);
  }
  setSeed(seed) {
    this.seed = seed;
    this.sz = (seed % 1000) * 0.7311 + 0.37;
    for (const c of this.chunks.values()) this.disposeChunk(c);
    this.chunks.clear();
    this.job = null;
    this.jumpCache = new Map();
    const r = mulberry32(seed * 7919 + 13);
    this.rp = [r() * 6.28, r() * 6.28, r() < 0.5 ? 1 : -1];
    // steep pitches on the way down: [centre x, length, share of the total drop]
    this.pitches = [];
    for (let x = 90 + r() * 30, k = 0; k < 4 && x < HILL_LEN - 40; k++) {
      const len = 22 + r() * 16;
      this.pitches.push([x, len, 0.1 + r() * 0.04]);
      x += len + 55 + r() * 60;
    }
    // S-bend sections: tighter corners with banked berms
    this.bends = [];
    for (let x = 60 + r() * 60, k = 0; k < 2 && x < HILL_LEN - 120; k++) {
      const len = 80 + r() * 30;
      this.bends.push([x, x + len, r() * 6.28]);
      x += len + 110 + r() * 80;
    }
    this.routeFeats = null;   // built lazily (needs base(), which needs the route)
  }
  feat(x, z, dx, dz, type, b0, b1) {
    const prof = PROFILES[type];
    return { x, z, dx, dz, len: prof.len, prof, b0, b1, type, wood: WOOD[type], dig: DIG[type],
      half: type === 'rhythm' || type === 'flow' ? 2.3 : type === 'bridge' ? 2.4 : type === 'skinny' ? 1.4 : 1.9 };
  }
  // ---------- main downhill route ----------
  routeZ(x) {
    const [a, b, sg] = this.rp;
    let z = sg * (22 * (Math.sin(x / 80 + a) - Math.sin(a)) + 5 * (Math.sin(x / 37 + b) - Math.sin(b)));
    for (const [b0, b1, ph] of this.bends) if (x > b0 && x < b1) z += 5 * Math.sin((x - b0) / 16 + ph) * smoother(b0, b0 + 30, x) * (1 - smoother(b1 - 30, b1, x));   // C2 fade: no curvature kinks
    return z;
  }
  routeDist(x, z) {   // ~perpendicular distance to the route centreline (Infinity off its ends)
    if (x < -40 || x > ROUTE_END + 40) return Infinity;
    const d = (this.routeZ(x + 0.5) - this.routeZ(x - 0.5));
    return Math.abs(z - this.routeZ(x)) / Math.sqrt(1 + d * d);
  }
  routeOn(x) { return smooth(-40, -12, x) * (1 - smooth(ROUTE_END - 30, ROUTE_END, x)); }
  hill(x, z) {   // big ridge: flat top behind spawn, then a long steady descent along +x
    // gentle base grade plus a few short steep pitches (shares sum to ~0.6 of the drop)
    let steep = 0, share = 0;
    for (const [c, len, sh] of this.pitches) { steep += sh * smooth(c - len / 2, c + len / 2, x); share += sh; }
    const lin = Math.min(1, Math.max(0, x / HILL_LEN));
    const along = (1 - steep - (1 - share) * (0.6 * smooth(-10, HILL_LEN, x) + 0.4 * lin)) * smooth(-170, -70, x);
    if (along <= 0) return 0;
    const d = Math.abs(z - this.routeZ(Math.max(-40, Math.min(ROUTE_END, x))));
    return HILL_TOP * along * (1 - smooth(55, 150, d));
  }
  buildRoute() {
    const r = mulberry32(this.seed * 104729 + 7), list = [];
    for (let x = 34; x < ROUTE_END - 40; x += ROUTE_GAP + r() * 22) {
      const type = ROUTE_TYPES[(r() * ROUTE_TYPES.length) | 0], prof = PROFILES[type], len = prof.len;
      // keep jumps off the steep pitches and their run-outs (too fast to land them nicely)
      const clash = this.pitches.find(([c, pl]) => x < c + pl / 2 + 30 && x + len > c - pl / 2 - 6);
      if (clash) { x = clash[0] + clash[1] / 2 + 30 - ROUTE_GAP + 2; continue; }
      const bend = this.bends.find(([b0, b1]) => x < b1 && x + len > b0);
      if (bend) { x = bend[1] - ROUTE_GAP + 2; continue; }
      const z = this.routeZ(x), x2 = x + len, z2 = this.routeZ(x2), l = Math.hypot(x2 - x, z2 - z);
      const dx = (x2 - x) / l, dz = (z2 - z) / l;
      const b0 = this.base(x, z), b1 = this.base(x + dx * len, z + dz * len);
      list.push(this.feat(x, z, dx, dz, type, b0, b1));
      x += len;
    }
    this.routeFeats = list;
  }
  n(x, z, s) { return perlin.noise(x * s, z * s, this.sz); }

  trail(x, z) {
    const p = Math.abs(this.n(x + 211.3, z - 97.1, 1 / 42));
    const main = (1 - smooth(1.9, 3.1, this.routeDist(x, z))) * this.routeOn(x);
    return Math.max(1 - smooth(0.03, 0.075, p), main);
  }
  // ---------- berms: the outside of tighter corners is banked up so you can rail them ----------
  bermShape(o, tan) {   // o = metres towards the outside of the turn from the trail centre
    if (o < -1.6) return 0;
    const edge = 2.7;
    if (o < 0) return tan * (o + 1.6) * (o + 1.6) / 3.2;          // eases in: no crease on the inside
    const om = edge - Math.log(1 + Math.exp(2 * (edge - o))) / 2;   // soft min(o, edge): rounded lip
    return tan * (om + 0.8) * (1 - smooth(edge - 0.5, edge + 6.5, o));   // long soft back
  }
  bermOn(x, z) {   // only the odd corner gets banked: a slow noise picks them (roughly 1 in 6)
    return smooth(0.2, 0.36, this.n(x + 777, z - 333, 1 / 55));
  }
  berm(x, z) {
    let h = 0;
    // main route: curvature straight from the centreline
    let win = 0;
    for (const [b0, b1] of this.bends) win = Math.max(win, smooth(b0 - 5, b0 + 22, x) * (1 - smooth(b1 - 22, b1 + 5, x)));
    if (win > 0 && this.routeOn(x) > 0) {
      const z0 = this.routeZ(x), zp = this.routeZ(x + 1), zm = this.routeZ(x - 1);
      const z1 = (zp - zm) / 2, z2 = zp - 2 * z0 + zm, k = 1 + z1 * z1;
      const kap = z2 / (k * Math.sqrt(k)), s = (z - z0) / Math.sqrt(k);
      if (Math.abs(s) < 8) h = Math.max(h, this.bermShape(-s * Math.sign(kap), Math.min(0.6, 17 * Math.abs(kap))) * this.routeOn(x) * win * this.bermOn(x, z0));
    }
    // trails: curvature of the path contour, measured at the trail CENTRE so each berm is one clean surface
    const P = (a, b) => this.n(a + 211.3, b - 97.1, 1 / 42);
    const p = P(x, z);
    if (Math.abs(p) < 0.2) {
      const gx0 = P(x + 0.5, z) - P(x - 0.5, z), gz0 = P(x, z + 0.5) - P(x, z - 0.5), g0 = Math.max(Math.hypot(gx0, gz0), 1e-6);
      const s = p / g0, cx = x - s * gx0 / g0, cz = z - s * gz0 / g0;   // nearest point on the centreline
      const e = 2, pc = P(cx, cz), pe = P(cx + e, cz), pw = P(cx - e, cz), pn = P(cx, cz + e), ps = P(cx, cz - e);
      const px = (pe - pw) / (2 * e), pz = (pn - ps) / (2 * e);
      const pxx = (pe - 2 * pc + pw) / (e * e), pzz = (pn - 2 * pc + ps) / (e * e);
      const pxz = (P(cx + e, cz + e) - P(cx + e, cz - e) - P(cx - e, cz + e) + P(cx - e, cz - e)) / (4 * e * e);
      const g = Math.hypot(px, pz) || 1e-6;
      const kap = (pxx * pz * pz - 2 * pxz * px * pz + pzz * px * px) / (g * g * g);
      // only on real, well-defined trail bends (noise saddles give garbage curvature) and never on the main route
      const ok = smooth(0.012, 0.02, g) * smooth(12, 22, this.routeDist(cx, cz)) * (1 - smooth(0.12, 0.2, Math.abs(p)));
      const tan = Math.min(0.55, 17 * Math.abs(kap)) * smooth(0.012, 0.03, Math.abs(kap)) * (1 - smooth(0.07, 0.1, Math.abs(kap))) * ok;
      if (tan > 0 && Math.abs(s) < 10) h = Math.max(h, this.bermShape(s * Math.sign(kap), tan) * this.bermOn(cx, cz));
    }
    return h;
  }
  // ---------- designed dirt features (tables, doubles, kickers, whoops) laid along the trails ----------
  // the ground under a feature is flattened to a straight plane, so the shapes ride exactly as designed
  // the big shapes of the land (hills, mountains, rock bands, the start ridge) without small detail
  landform(x, z) {
    // calm the hills along the main route so it is a steady downhill with no climbs
    const calm = 1 - 0.85 * (1 - smooth(8, 45, this.routeDist(x, z))) * this.routeOn(x);
    // some regions are much steeper and hillier than others
    const relief = 1 + 1.3 * smooth(0.0, 0.35, this.n(x + 5000, z - 800, 1 / 260));
    let h = (this.n(x, z, 1 / 90) * 10 * relief + this.n(x + 31.7, z - 17.2, 1 / 28) * 3.2 * (0.6 + 0.4 * relief)) * calm + this.hill(x, z);
    return h + this.wild(x, z) * this.wildMask(x, z);   // trails roll over the hills, only rock bands are cut back
  }
  base(x, z) {
    const t = this.trail(x, z);
    let h = this.landform(x, z);
    // distance to the trail centreline (noise value / its local slope; exact enough near the trail)
    const P = (a, b) => this.n(a + 211.3, b - 97.1, 1 / 42);
    const p = P(x, z);
    let dist = 99;
    if (Math.abs(p) < 0.25) {
      const gx = (P(x + 0.5, z) - P(x - 0.5, z)), gz = (P(x, z + 0.5) - P(x, z - 0.5)), g = Math.max(Math.hypot(gx, gz), 0.012);
      dist = Math.abs(p) / g;
      // trails are benched into the hillside: level across, like a real cut path, with soft shoulders
      const bench = (1 - smooth(3, 9.5, dist)) * smooth(6, 16, this.routeDist(x, z)) * (1 - smooth(0.15, 0.25, Math.abs(p)));   // not where trails cross the main route
      if (bench > 0) {
        const sd = p / g, cx = x - sd * gx / g, cz = z - sd * gz / g;
        // cut / fill is capped (~1 m) so steep sidehills keep a little tilt instead of getting carved walls
        const d = (this.landform(cx, cz) - h) * bench;
        h += d / (1 + Math.abs(d) / 1.1);
      }
    }
    // small lumps only well away from the trail, faded in gently so the edges stay clean
    h += this.n(x - 5.3, z + 9.1, 1 / 8) * 0.5 * Math.max(smooth(2.5, 7, dist), smooth(0.15, 0.25, Math.abs(p))) * (1 - t);
    h -= 0.15 * t;                                         // trail sits slightly sunk in, smooth
    // never let a trail run into a lake: raise it on a dirt causeway with sloped banks
    const dry = WATER + 0.5;
    if (h < dry) {
      const p = Math.abs(this.n(x + 211.3, z - 97.1, 1 / 42));
      const bank = Math.max(1 - smooth(0.05, 0.14, p), (1 - smooth(2.6, 7, this.routeDist(x, z))) * this.routeOn(x));
      h += (dry - h) * bank;
    }
    return h;
  }
  // ---------- biomes: grassy hills <-> rocky mountains & cliffs <-> dunes & red mesas ----------
  biome(x, z) {   // -> [dry 0..1, rugged 0..1]
    const wx = x + this.n(x, z + 500, 1 / 160) * 60, wz = z + this.n(x - 500, z, 1 / 160) * 60;
    return [smooth(-0.12, 0.16, this.n(wx + 3000, wz - 1200, 1 / 380)), smooth(-0.08, 0.2, this.n(wx - 700, wz + 2200, 1 / 300))];
  }
  biomeName(x, z) {
    const [dry, rug] = this.biome(x, z);
    if (dry > 0.6) return rug > 0.5 ? 'Red Canyons' : 'Dune Sea';
    if (dry > 0.35) return 'Dry Plains';
    return rug > 0.5 ? 'Rocky Mountains' : 'Green Hills';
  }
  wildMask(x, z) {   // keep the big stuff off trails, the main route and the spawn
    const route = 1 - (1 - smooth(22, 60, this.routeDist(x, z))) * this.routeOn(x);
    return route * smooth(45, 90, Math.hypot(x, z));
  }
  trailMetres(x, z) {   // approx. distance to the nearest trail in metres (noise value / its slope)
    const P = (a, b) => this.n(a + 211.3, b - 97.1, 1 / 42);
    return Math.abs(P(x, z)) / 0.022;   // fixed typical slope: smooth & steady (no blow-ups at noise saddles)
  }
  passMask(x, z) {   // trails cross hills through wide, gentle passes
    return 0.3 + 0.7 * smooth(3, 32, this.trailMetres(x, z));
  }
  rockMask(x, z) {   // rock bands fade out gradually towards a trail, so trails pass through a gentle gap
    return smooth(5, 24, this.trailMetres(x, z));
  }
  // natural rock bands: a scree slope leading up to a short steep face, height varying along the edge
  tiers(f, steps, vary) {
    let h = 0;
    for (const [t, sh] of steps) {
      const k = sh * vary;
      h += k * (0.35 * smooth(t - 0.14, t, f) + 0.65 * smooth(t, t + 0.06, f));
    }
    return h;
  }
  wild(x, z) {
    const [dry, rug] = this.biome(x, z);
    let h = 0;
    const tm = this.trailMetres(x, z);
    // wobbly edges so cliffs are not perfectly smooth curves
    const ex = x + this.n(x, z - 77, 1 / 23) * 7 + this.n(x, z + 31, 1 / 7) * 1.5, ez = z + this.n(x + 77, z, 1 / 23) * 7 + this.n(x - 31, z, 1 / 7) * 1.5;
    if (rug > 0) {
      // rocky: rounded mountains with the odd outcrop, and rock bands that fade in and out
      const r = smooth(0.15, 1, 1 - Math.abs(this.n(x + 1300, z - 40, 1 / 95)));   // rounded, no knife-edge ridges
      const peaks = r * 13 + this.n(x - 90, z + 400, 1 / 40) * 3;   // gentle enough to ride over
      const f = this.n(ex + 900, ez - 400, 1 / 115);
      const vary = smooth(-0.25, 0.3, this.n(x + 55, z - 210, 1 / 45));   // 0 = the cliff melts into a slope
      const rm = smooth(6, 30, tm);
      const cliffs = this.tiers(f, [[0.0, 5.5], [0.22, 4.5]], vary * rm);
      const mesas = this.tiers(f, [[0.05, 6.5], [0.27, 4]], (0.4 + 0.6 * vary) * rm);
      h += rug * ((1 - dry) * (peaks + cliffs) + dry * mesas);
    }
    if (dry > 0) {
      // dunes: long wind-blown ridges, gentler where the canyons take over
      const dx = x * 0.8 + z * 0.6, dz = -x * 0.6 + z * 0.8;
      const d = 1 - Math.abs(this.n(dx / 1.0 + this.n(x, z, 1 / 60) * 20, dz * 0.35, 1 / 26));
      h += dry * (1 - rug * 0.7) * (d * d * 3.6 * (0.45 + 0.55 * smooth(3, 25, tm)) + this.n(x + 40, z, 1 / 60) * 3);
    }
    return h;
  }
  jumpAt(cx, cz) {
    const key = cx * 1048576 + cz;   // numeric key: this runs ~9x per height() sample, no string garbage
    const hit = this.jumpCache.get(key);
    if (hit !== undefined) return hit;
    // results are deterministic, so a long ride can simply drop the cache instead of growing forever
    if (this.jumpCache.size > 4096) this.jumpCache.clear();
    const C = JC, rnd = mulberry32((cx * 92837111) ^ (cz * 689287499) ^ (this.seed * 2654435761));
    let best = null;
    if (rnd() < 0.85) {
      let bestV = 0.02;
      for (let i = 0; i < 24; i++) {
        const x = (cx + 0.2 + rnd() * 0.6) * C, z = (cz + 0.2 + rnd() * 0.6) * C;
        const pv = Math.abs(this.n(x + 211.3, z - 97.1, 1 / 42));
        if (pv < bestV && Math.hypot(x, z) > 20 && this.routeDist(x, z) > 14) { bestV = pv; best = { x, z }; }
      }
      if (best) {   // runs ALONG the trail (perpendicular to the path-noise gradient)
        const type = FEATURE_TYPES[(rnd() * FEATURE_TYPES.length) | 0], prof = PROFILES[type], len = prof.len;
        const P = (a, b) => this.n(a + 211.3, b - 97.1, 1 / 42);
        const gx = P(best.x + 0.5, best.z) - P(best.x - 0.5, best.z), gz = P(best.x, best.z + 0.5) - P(best.x, best.z - 0.5);
        const l = Math.hypot(gx, gz) || 1;
        let dx = -gz / l, dz = gx / l;
        let b0 = this.base(best.x - dx * len / 2, best.z - dz * len / 2), b1 = this.base(best.x + dx * len / 2, best.z + dz * len / 2);
        if (b1 > b0) { dx = -dx; dz = -dz; [b0, b1] = [b1, b0]; }   // always build it riding downhill
        const sx = best.x - dx * len / 2, sz = best.z - dz * len / 2;
        let ok = Math.abs(b1 - b0) / len < 0.14;
        for (let k = 0; ok && k <= 10; k++) {   // no causeways over lakes or trenches through hills
          const f = k / 10, b = this.base(sx + dx * len * f, sz + dz * len * f), pl = b0 + (b1 - b0) * f;
          if (pl < WATER + 0.6 || Math.abs(b - pl) > 1.8 || this.routeDist(sx + dx * len * f, sz + dz * len * f) < 12) ok = false;
        }
        best = ok && Math.hypot(sx, sz) > 34 ? this.feat(sx, sz, dx, dz, type, b0, b1) : null;
      }
    }
    this.jumpCache.set(key, best);
    return best;
  }
  // one feature's contribution at (x, z) -> accumulates into o = { h, m, plane, dig, wood }
  featAt(j, x, z, o) {
    const rx = x - j.x, rz = z - j.z, u = rx * j.dx + rz * j.dz;
    if (u < -6 || u > j.len + 6) return;
    const w = Math.abs(-rx * j.dz + rz * j.dx);
    if (w > j.half + 2.5) return;
    const across = 1 - smooth(j.half, j.half + 1.2, w);              // crisp built-up sides
    const ph = j.prof(u) * across;
    if (ph > o.h) o.h = ph;
    if (j.dig) { const dh = j.dig(u) * across; if (dh < o.dig) o.dig = dh; }
    const pl = j.b0 + (j.b1 - j.b0) * clamp01(u / j.len);
    const mk = (1 - smooth(j.half + 0.6, j.half + 2.5, w)) * smooth(-6, -1, u) * (1 - smooth(j.len + 1, j.len + 6, u));
    if (mk > o.m) { o.m = mk; o.plane = pl; }
    if (j.wood && u >= j.wood.u0 && u <= j.wood.u1 && w <= j.wood.half) {
      const top = pl + j.wood.top(u);
      if (o.wood === null || top > o.wood) o.wood = top;
    }
  }
  jump(x, z) {   // -> [feature height, mask, flattened ground height, dug depth, wood deck top or null]
    const cx = Math.floor(x / JC), cz = Math.floor(z / JC);
    const o = this._fo || (this._fo = {});
    o.h = 0; o.m = 0; o.plane = 0; o.dig = 0; o.wood = null;
    for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
      const j = this.jumpAt(cx + dx, cz + dz); if (j) this.featAt(j, x, z, o);
    }
    if (!this.routeFeats) this.buildRoute();
    if (this.routeDist(x, z) < 12) for (const j of this.routeFeats) {
      if (x < j.x - 8 || x > j.x + j.len + 8) continue;
      this.featAt(j, x, z, o);
    }
    return [o.h, o.m, o.plane, o.dig, o.wood];
  }
  // ground() is the dirt/rock surface (what the terrain mesh shows);
  // height() is what you ride on: the ground, or a wooden deck where there is one
  height(x, z) { const g = this.ground(x, z); return this._wood !== null && this._wood > g ? this._wood : g; }
  ground(x, z) {
    let h = this.base(x, z);
    const [jh, jm, jp, jd, jw] = this.jump(x, z);
    if (jm > 0) h += (jp - h) * jm;
    h += jh + jd;
    h += this.berm(x, z) * (1 - jm);
    this._wood = jw;
    const d = Math.hypot(x, z), f = smooth(5, 28, d);
    h = h * f + (1 - f) * (0.8 + this.hill(x, z));
    const bed = WATER - 0.35;
    if (h < bed) h = bed + (h - bed) * 0.08;
    return h;
  }
  surface(x, z) {   // 0 grass, 1 trail, 2 water, 3 sand (beaches, dunes)
    const h = this.height(x, z);
    if (h < WATER - 0.05) return 2;
    if (this.trail(x, z) > 0.5) return 1;
    if (h < WATER + 0.45 || this.biome(x, z)[0] > 0.7) return 3;
    return 0;
  }
  color(x, z, h, ny, out) {
    const v = this.n(x + 50, z + 50, 1 / 6) * 0.5 + 0.5;
    const [dry, rug] = this.biome(x, z);
    out.copy(COL.grassA).lerp(COL.grassB, v);
    out.lerp(COL.meadow, smooth(3.5, 8, h) * 0.8 * (1 - rug));
    out.lerp(COL.alpine, rug * (1 - dry) * 0.6);
    out.lerp(COL.dryGrass, smooth(0.15, 0.55, dry));
    out.lerp(_c.copy(COL.dune).lerp(COL.duneDark, v), smooth(0.5, 0.85, dry));
    out.lerp(COL.snow, smooth(11, 19, h - this.hill(x, z) + this.n(x, z, 1 / 9) * 3) * rug * (1 - dry) * smooth(0.75, 0.9, ny));
    const t = Math.max(this.trail(x, z), this.jump(x, z)[1]);
    if (t > 0) {
      const d = _c.copy(COL.dirt).lerp(COL.dirtDark, smooth(-0.4, 0.4, this.n(x, z, 1 / 7)) * 0.7).lerp(COL.desertDirt, dry * 0.6);
      out.lerp(d, t);
    }
    // steep faces: layered strata, red sandstone in the desert, grey rock elsewhere
    const steep = smooth(0.86, 0.6, ny) * (1 - t);
    if (steep > 0) {
      const bh = h * 0.3 + this.n(x, z, 1 / 40) * 0.5, bi = Math.floor(bh), bf = bh - bi;
      const pick = (B, o) => o.copy(B[((bi % B.length) + B.length) % B.length]).lerp(B[(((bi + 1) % B.length) + B.length) % B.length], smooth(0.75, 1, bf));
      const rock = pick(GREY_BANDS, _c2).lerp(pick(RED_BANDS, _c3), smooth(0.35, 0.65, dry));
      out.lerp(rock, steep);
    }
    if (h < WATER + 0.7) out.lerp(COL.sand, smooth(WATER + 0.7, WATER + 0.2, h) * (1 - t));   // causeways stay dirt
    if (h < WATER) out.lerp(COL.bed, 0.6);
    return out;
  }

  // Streams chunks in around the player. Building a chunk is expensive (~35k noise-heavy samples),
  // so it runs as a resumable generator and only gets `ms` milliseconds of work per call:
  // no single frame ever has to build a whole chunk. ms = Infinity builds everything now (startup).
  update(px, pz, ms = 4) {
    const S = this.size, ccx = Math.round(px / S), ccz = Math.round(pz / S), R = this.radius;
    for (const [k, c] of this.chunks) {
      if (Math.abs(c.cx - ccx) > R + 1 || Math.abs(c.cz - ccz) > R + 1) { this.disposeChunk(c); this.chunks.delete(k); }
    }
    if (this.job && (Math.abs(this.job.cx - ccx) > R + 1 || Math.abs(this.job.cz - ccz) > R + 1)) this.job = null;   // left behind
    const t0 = performance.now();
    let deadline = t0 + ms;
    for (;;) {
      if (!this.job) {
        // nearest missing chunk first
        let best = null, bd = Infinity;
        for (let dz = -R; dz <= R; dz++) for (let dx = -R; dx <= R; dx++) {
          const d = dx * dx + dz * dz;
          if (d < bd && !this.chunks.has((ccx + dx) + ',' + (ccz + dz))) { bd = d; best = [ccx + dx, ccz + dz]; }
        }
        if (!best) break;
        this.job = { cx: best[0], cz: best[1], it: this.buildGen(best[0], best[1]) };
        this.job.urgent = bd <= 2;
      }
      // a chunk right next to the rider is missing: allow a bigger slice so it never stays a hole
      if (this.job.urgent) deadline = Math.max(deadline, t0 + ms * 3);
      this._deadline = deadline;
      const r = this.job.it.next();
      if (r.done) {
        const c = r.value;
        for (const o of c.objects) this.scene.add(o);
        this.chunks.set(c.cx + ',' + c.cz, c);
        this.job = null;
      }
      if (performance.now() >= deadline) break;
    }
  }
  disposeChunk(c) {
    for (const o of c.objects) { this.scene.remove(o); if (o.isInstancedMesh) o.dispose(); else o.geometry.dispose(); }
  }
  _late() { return performance.now() >= this._deadline; }

  *buildGen(cx, cz) {
    const S = this.size, N = this.seg, ox = cx * S, oz = cz * S;
    const geo = new THREE.PlaneGeometry(S, S, N, N); geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    const nrmA = new Float32Array(pos.count * 3), d = S / N, W = N + 3;
    // sample the height field once on a grid with a 1-cell border; normals from neighbours -> no seams
    const G = new Float32Array(W * W);
    for (let iz = -1; iz <= N + 1; iz++) {
      for (let ix = -1; ix <= N + 1; ix++) G[(iz + 1) * W + ix + 1] = this.ground(ox - S / 2 + ix * d, oz - S / 2 + iz * d);   // wood is drawn as models
      if (this._late()) yield;
    }
    for (let i = 0; i < pos.count; i++) {
      const ix = Math.round((pos.getX(i) + S / 2) / d), iz = Math.round((pos.getZ(i) + S / 2) / d), k = (iz + 1) * W + ix + 1;
      pos.setY(i, G[k]);
      const nx = G[k - 1] - G[k + 1], nz = G[k - W] - G[k + W], ny = 2 * d;
      const l = Math.hypot(nx, ny, nz);
      nrmA[i * 3] = nx / l; nrmA[i * 3 + 1] = ny / l; nrmA[i * 3 + 2] = nz / l;
    }
    geo.setAttribute('normal', new THREE.BufferAttribute(nrmA, 3));
    const nrm = geo.attributes.normal, cols = new Float32Array(pos.count * 3), c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      this.color(pos.getX(i) + ox, pos.getZ(i) + oz, pos.getY(i), nrm.getY(i), c);
      cols[i * 3] = c.r; cols[i * 3 + 1] = c.g; cols[i * 3 + 2] = c.b;
      if ((i & 63) === 63 && this._late()) yield;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
    const mesh = new THREE.Mesh(geo, MAT.terrain);
    mesh.position.set(ox, 0, oz); mesh.receiveShadow = true;

    // decorations
    const rnd = mulberry32((cx * 73856093) ^ (cz * 19349663) ^ (this.seed * 83492791));
    const lists = { trunk: [], blob: [], pine: [], rock: [], tuft: [], flower: [], cactus: [] };
    const colliders = [];
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const put = (list, x, y, z, sx, sy, sz, yaw, col, tilt = 0) => {
      e.set(tilt * (rnd() - .5), yaw, tilt * (rnd() - .5)); q.setFromEuler(e);
      list.push({ m: m4.compose(p.set(x, y, z), q, s.set(sx, sy, sz)).clone(), col });
    };
    const okSpot = (x, z, minH = WATER + 0.6) => {
      const h = this.height(x, z);
      if (h < minH || Math.hypot(x, z) < 9) return null;
      const sl = Math.abs(this.height(x + 0.8, z) - h) + Math.abs(this.height(x, z + 0.8) - h);
      return sl > 0.7 ? null : h;
    };
    // ---- man-made bits: a shed now and then, wooden fences along the trails ----
    // own random streams, so adding these never reshuffles the trees and rocks of a seed
    const rs = mulberry32((cx * 19349663) ^ (cz * 83492791) ^ (this.seed * 73856093) ^ 0x5bd1e995);
    const blocked = [];   // keep-out circles for the scatter below
    const isBlocked = (x, z, pad = 0) => blocked.some((b) => Math.hypot(x - b.x, z - b.z) < b.r + pad);
    const shedLists = SHED_DESIGNS.map(() => []);
    if (rs() < 0.32) for (let tries = 0; tries < 8; tries++) {
      const x = ox + (rs() - .5) * S * 0.8, z = oz + (rs() - .5) * S * 0.8;
      if (Math.hypot(x, z) < 30 || this.routeDist(x, z) < 9) continue;
      const tm = this.trailMetres(x, z), rd = this.routeDist(x, z) * (this.routeOn(x) > 0.5 ? 1 : Infinity);
      if (!((tm > 6 && tm < 16) || (rd > 9 && rd < 20)) && tries < 6) continue;   // sheds sit where you ride past them
      const di = (rs() * SHED_DESIGNS.length) | 0, d = SHED_DESIGNS[di], R = Math.hypot(d.s.hw, d.s.hd) + 0.6;
      // face the door roughly towards the nearest trail
      const P = (a, b) => Math.abs(this.n(a + 211.3, b - 97.1, 1 / 42));
      const gx = P(x - 1, z) - P(x + 1, z), gz = P(x, z - 1) - P(x, z + 1);
      const yaw = Math.atan2(gx, gz) + (rs() - .5) * 0.8;
      let lo = Infinity, hi = -Infinity, ok = true;
      for (let k = 0; k < 9 && ok; k++) {
        const a = k * 0.785, rr = k === 8 ? 0 : R, px = x + Math.cos(a) * rr, pz = z + Math.sin(a) * rr, h = this.height(px, pz);
        if (h < WATER + 0.8 || this.trail(px, pz) > 0.02 || this.jump(px, pz)[1] > 0) ok = false;
        lo = Math.min(lo, h); hi = Math.max(hi, h);
      }
      if (!ok || hi - lo > 0.7) continue;
      m4.compose(p.set(x, lo - 0.05, z), q.setFromEuler(e.set(0, yaw, 0)), s.set(1, 1, 1));
      shedLists[di].push({ m: m4.clone() });
      shedColliders(d, x, z, yaw, colliders);
      blocked.push({ x, z, r: R + 0.4 });
      break;
    }
    const fl = { post: [], rail: [], picket: [], panels: [] };
    const postOk = (x, z, pad = 0) => {
      const h = this.height(x, z);
      if (h < WATER + 0.3 || Math.hypot(x, z) < 14 || this.trail(x, z) > 0.15 || this.jump(x, z)[1] > 0.02 || isBlocked(x, z, 0.5)) return null;
      return h;
    };
    const runFence = (pts, style) => {   // split the post line wherever a post can't stand, build each piece
      let cur = [];
      const flush = () => { if (cur.length >= 3) buildFence(cur, style, rs, fl, colliders); cur = []; };
      for (const [x, z] of pts) {
        const h = postOk(x, z);
        if (h === null || (cur.length && Math.abs(h - cur[cur.length - 1].h) > 0.9)) { flush(); if (h === null) continue; }
        cur.push({ x, z, h });
      }
      flush();
    };
    // fences that follow a trail at a fixed offset (projected back onto that offset after every step)
    if (rs() < 0.55) {
      const P = (a, b) => this.n(a + 211.3, b - 97.1, 1 / 42);
      const D = (4.2 + rs() * 1.5) * 0.022;
      let x = ox + (rs() - .5) * S, z = oz + (rs() - .5) * S, pts = [];
      const project = () => {
        for (let it = 0; it < 4; it++) {
          const v = P(x, z), gx = (P(x + 0.5, z) - P(x - 0.5, z)), gz = (P(x, z + 0.5) - P(x, z - 0.5)), g2 = gx * gx + gz * gz;
          if (g2 < 1e-10) return false;
          const want = Math.sign(v || 1) * D, k = (want - v) / g2;
          x += gx * k; z += gz * k;
        }
        return Math.abs(Math.abs(P(x, z)) - D) < 0.004;
      };
      if (project()) {
        const n = 4 + ((rs() * 7) | 0);
        let dir = null;
        for (let i = 0; i < n; i++) {
          pts.push([x, z]);
          const gx = (P(x + 0.5, z) - P(x - 0.5, z)), gz = (P(x, z + 0.5) - P(x, z - 0.5)), gl = Math.hypot(gx, gz);
          let tx = -gz / gl, tz = gx / gl;
          if (dir && tx * dir[0] + tz * dir[1] < 0) { tx = -tx; tz = -tz; }
          dir = [tx, tz];
          const px = x, pz = z;
          x += tx * SPAN; z += tz * SPAN;
          if (!project()) break;
          const l = Math.hypot(x - px, z - pz);   // keep panels at their real length
          x = px + (x - px) / l * SPAN; z = pz + (z - pz) / l * SPAN;
        }
        runFence(pts, rs() < 0.35 ? 'picket' : 'ranch');
      }
    }
    // fences lining the main downhill route here and there
    if (this.routeOn(ox) > 0.5 && rs() < 0.6) {
      const side = rs() < 0.5 ? -1 : 1, off = 5.6 + rs() * 1.2, pts = [];
      let x = ox + (rs() - .5) * S * 0.6;
      const n = 5 + ((rs() * 8) | 0);
      for (let i = 0; i < n; i++) {
        const zc = this.routeZ(x), d = (this.routeZ(x + 0.5) - this.routeZ(x - 0.5)), l = Math.sqrt(1 + d * d);
        const px = x - side * off * d / l, pz = zc + side * off / l;
        if (Math.abs(pz - oz) < S / 2 + 10) pts.push([px, pz]);
        x += SPAN / l;
      }
      runFence(pts, 'ranch');
    }
    for (const pnl of fl.panels) blocked.push({ x: pnl.cx, z: pnl.cz, r: 1.6 });
    // race tape on stakes along both sides of the main downhill (keep trees out of its line)
    const tapeObjs = buildTape(this, cx, cz, S, colliders);
    for (const k of colliders) if (k.tape) blocked.push({ x: k.x, z: k.z, r: 0.9 });

    for (let i = 0; i < 90; i++) {
      if ((i & 7) === 7 && this._late()) yield;
      const x = ox + (rnd() - .5) * S, z = oz + (rnd() - .5) * S;
      const forest = this.n(x + 400, z, 1 / 38);
      if (rnd() > smooth(-0.25, 0.25, forest) * 0.9 + 0.05) continue;
      if (this.trail(x, z) > 0.02 || Math.abs(this.n(x + 211.3, z - 97.1, 1 / 42)) < 0.1 || this.jump(x, z)[1] > 0 || isBlocked(x, z, 0.8)) continue;
      const h = okSpot(x, z); if (h === null) continue;
      const sc = 0.7 + rnd() * 0.8, yaw = rnd() * 6.28;
      const [dry, rug] = this.biome(x, z);
      if (rnd() < dry) {   // desert: sparse cacti instead of trees
        if (rnd() < 0.35) {
          const cy = sc * (0.8 + rnd() * 0.6);
          put(lists.cactus, x, h - 0.05, z, sc, cy, sc, yaw, CACTI[(rnd() * CACTI.length) | 0], 0.15);
          colliders.push({ x, z, r: 0.17 * sc, ceil: h - 0.05 + 1.6 * cy, cactus: { i: lists.cactus.length - 1, broken: false, im: null } });   // trunk radius at the base; real height; breakable
        }
        continue;
      }
      let ceil;
      if (h > 4 || rnd() < 0.3 + rug * 0.6) {
        put(lists.trunk, x, h - 0.1, z, sc, sc * 0.9, sc, yaw);
        const py = sc * (1.1 + rnd() * 0.4);
        put(lists.pine, x, h + sc * 0.6, z, sc * 1.1, py, sc * 1.1, yaw, PINES[(rnd() * PINES.length) | 0]);
        ceil = h + sc * 0.6 + 2.8 * py;
      } else {
        const th = sc * (1.1 + rnd() * 0.6);
        ceil = h + th + sc * 1.8;
        put(lists.trunk, x, h - 0.1, z, sc, th + 0.3, sc, yaw);
        put(lists.blob, x, h + th + sc * 0.7, z, sc * 1.2, sc * 1.05, sc * 1.2, yaw, LEAVES[(rnd() * LEAVES.length) | 0], 0.6);
        if (rnd() < 0.5) put(lists.blob, x + (rnd() - .5) * sc, h + th + sc * 1.4, z + (rnd() - .5) * sc, sc * .8, sc * .75, sc * .8, yaw, LEAVES[(rnd() * LEAVES.length) | 0], 0.6);
      }
      colliders.push({ x, z, r: 0.16 * sc + 0.02, ceil });   // visible trunk radius at the base; tree height
    }
    for (let i = 0; i < 40; i++) {
      if ((i & 7) === 7 && this._late()) yield;
      const x = ox + (rnd() - .5) * S, z = oz + (rnd() - .5) * S;
      if (i >= 22 && rnd() > this.biome(x, z)[1]) continue;   // boulder fields in the rocky lands
      if (this.trail(x, z) > 0.02 || this.jump(x, z)[1] > 0 || isBlocked(x, z, 0.5)) continue;
      const h = this.height(x, z); if (Math.hypot(x, z) < 9) continue;
      const sc = 0.2 + rnd() ** 3 * 1.3, sx = sc * (1 + rnd() * .5);
      const sy = sc * (0.6 + rnd() * .4);
      put(lists.rock, x, h - sc * 0.25, z, sx, sy, sc, rnd() * 6.28, null, 0.5);
      colliders.push({ x, z, r: (sx + sc) * 0.45, top: h - sc * 0.25 + sy * 0.9 });   // rocks have a top: jump over them
    }
    for (let i = 0; i < 260; i++) {
      if ((i & 15) === 15 && this._late()) yield;
      const x = ox + (rnd() - .5) * S, z = oz + (rnd() - .5) * S;
      if (this.trail(x, z) > 0.1 || this.jump(x, z)[1] > 0.3 || blocked.some((b) => b.r > 2 && Math.hypot(x - b.x, z - b.z) < b.r - 0.6)) continue;
      const h = this.height(x, z); if (h < WATER + 0.4) continue;
      const [dry, rug] = this.biome(x, z);
      if (rnd() < dry * 0.85 || rnd() < rug * 0.3) continue;   // bare sand and rock
      const tc = _c.copy(COL.tuftGreen).lerp(COL.tuftDry, smooth(0.1, 0.6, dry)).clone();
      if (rnd() < 0.22 * (1 - dry)) put(lists.flower, x, h - 0.02, z, 1, 0.7 + rnd() * 0.6, 1, rnd() * 6.28, FLOWERS[(rnd() * FLOWERS.length) | 0], 0.4);
      else put(lists.tuft, x, h - 0.03, z, 1 + rnd(), 0.7 + rnd() * 0.8, 1 + rnd(), rnd() * 6.28, tc);
    }
    const objects = [mesh];
    const mk = (geo, mat, list, cast) => {
      if (!list.length) return;
      const im = new THREE.InstancedMesh(geo, mat, list.length);
      list.forEach((it, i) => { im.setMatrixAt(i, it.m); if (it.col) im.setColorAt(i, it.col); });
      im.castShadow = cast; im.receiveShadow = true;
      im.computeBoundingSphere();
      objects.push(im);   // added to the scene by update() once the whole chunk is done
    };
    mk(GEO.trunk, MAT.trunk, lists.trunk, true);
    mk(GEO.blob, MAT.leaf, lists.blob, true);
    mk(GEO.pine, MAT.leaf, lists.pine, true);
    mk(GEO.rock, MAT.rock, lists.rock, true);
    mk(GEO.tuft, MAT.tuft, lists.tuft, false);
    mk(GEO.flower, MAT.flower, lists.flower, false);
    mk(GEO.cactus, MAT.leaf, lists.cactus, true);
    if (lists.cactus.length) { const im = objects[objects.length - 1]; for (const k of colliders) if (k.cactus) k.cactus.im = im; }
    SHED_DESIGNS.forEach((d, i) => mk(shedGeo(d), MAT_SHED, shedLists[i], true));
    const fm = {};
    for (const k of ['post', 'rail', 'picket']) { mk(FENCE_GEO[k], FENCE_MAT, fl[k], true); if (fl[k].length) fm[k] = objects[objects.length - 1]; }
    bindFences(fl.panels, fm);
    objects.push(...tapeObjs);
    // wooden ramps / skinnies / bridges whose start lies in this chunk
    const wl = { plank: [], beam: [] }, x0 = ox - S / 2, z0 = oz - S / 2, woodF = [];
    for (let gz = Math.floor(z0 / JC) - 1; gz <= Math.floor((z0 + S) / JC); gz++)
      for (let gx = Math.floor(x0 / JC) - 1; gx <= Math.floor((x0 + S) / JC); gx++) { const j = this.jumpAt(gx, gz); if (j && j.wood) woodF.push(j); }
    if (!this.routeFeats) this.buildRoute();
    for (const j of this.routeFeats) if (j.wood) woodF.push(j);
    for (const j of woodF) if (j.x >= x0 && j.x < x0 + S && j.z >= z0 && j.z < z0 + S) this.woodModel(j, wl);
    mk(GEO.box, MAT.wood, wl.plank, true);
    mk(GEO.box, MAT.wood, wl.beam, true);
    return { cx, cz, objects, colliders };
  }

  woodModel(j, wl) {
    const W = j.wood, qy = new THREE.Quaternion().setFromAxisAngle(_Y, Math.atan2(-j.dz, j.dx)), qp = new THREE.Quaternion(), q = new THREE.Quaternion();
    const m = new THREE.Matrix4(), P = new THREE.Vector3(), Sc = new THREE.Vector3();
    const top = (u) => j.b0 + (j.b1 - j.b0) * clamp01(u / j.len) + W.top(u);
    const at = (u, w) => [j.x + j.dx * u - j.dz * w, j.z + j.dz * u + j.dx * w];
    const put = (list, u, w, y, sx, sy, sz, pitch, col) => {
      const [x, z] = at(u, w);
      qp.setFromAxisAngle(_Z, pitch); q.copy(qy).multiply(qp);
      list.push({ m: m.compose(P.set(x, y, z), q, Sc.set(sx, sy, sz)).clone(), col });
    };
    const r = mulberry32(((j.x * 1000) | 0) ^ ((j.z * 7919) | 0));
    // deck planks laid across the riding line
    for (let u = W.u0 + 0.13; u < W.u1; u += 0.27) {
      const sl = (top(Math.min(W.u1, u + 0.06)) - top(Math.max(W.u0, u - 0.06))) / 0.12;
      put(wl.plank, u, 0, top(u) - 0.035, 0.23, 0.07, W.half * 2 + 0.08, Math.atan(sl), PLANKS[(r() * PLANKS.length) | 0]);
    }
    for (const side of [-1, 1]) {
      const w = side * (W.half - 0.08);
      // stringers under the plank ends
      for (let u = W.u0; u < W.u1 - 0.05; u += 1.2) {
        const u2 = Math.min(W.u1, u + 1.2), t1 = top(u), t2 = top(u2);
        put(wl.beam, (u + u2) / 2, w, (t1 + t2) / 2 - 0.14, Math.hypot(u2 - u, t2 - t1), 0.14, 0.1, Math.atan2(t2 - t1, u2 - u), BEAM);
      }
      // posts down to the ground
      for (let u = W.u0 + 0.7; u <= W.u1 - 0.3; u += 1.5) {
        const t = top(u) - 0.2, [x, z] = at(u, w), g = this.ground(x, z) - 0.1;
        if (t - g > 0.12) put(wl.beam, u, w, (t + g) / 2, 0.11, t - g, 0.11, 0, BEAM);
      }
    }
    if (W.backWall) {   // open-backed kicker: a plank wall closing the back
      const [x, z] = at(W.u1, 0), t = top(W.u1), g = this.ground(x, z) - 0.1;
      put(wl.beam, W.u1 - 0.05, 0, (t + g) / 2, 0.08, t - g, W.half * 2, 0, BEAM);
    }
  }

  collidersNear(x, z) {
    const S = this.size, ccx = Math.round(x / S), ccz = Math.round(z / S), out = [];
    for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
      const c = this.chunks.get((ccx + dx) + ',' + (ccz + dz));
      if (c) for (const k of c.colliders) if (Math.abs(k.x - x) < 3 && Math.abs(k.z - z) < 3 && !(k.fence && k.fence.broken) && !(k.tape && k.tape.broken) && !(k.cactus && k.cactus.broken)) out.push(k);
    }
    return out;
  }
}

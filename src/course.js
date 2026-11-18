// THE COURSE: a long, hand-built-looking downhill laid out like a real trail crew would.
// A turtle walks down a big mountain slope and emits a centreline every STEP metres:
//   - long ROAD stretches (wide gravel double-track, big sweeping curves, fenced pasture-style)
//   - where the slope steepens (a "pitch"), a TECHNICAL section: tight switchbacks with banked
//     hairpins, a rock-garden chute straight down the fall line, or a run of esses
//   - on the gentle ground in between, now and then a JUMP LINE (straight, built features)
// Every sample remembers its kind, width, curvature and the ground height the crew benched it to.
// Terrain asks it "how far am I from the course, which side, how high should the ground be here"
// through query(); fences and tape are planned here too, so they follow the same logic.

export const STEP = 2;            // m between centreline samples
export const K = { START: 0, ROAD: 1, SWITCH: 2, ESSES: 3, ROCKS: 4, JUMP: 5, FINISH: 6 };
const WIDTH = [3.0, 2.7, 1.35, 1.45, 1.7, 2.5, 3.0];   // half-width of the riding surface per kind
const BERM = [0, 0.45, 1, 0.9, 0.3, 0, 0];             // how hard the crew banks corners per kind
const CELL = 16, QR = 19;         // spatial hash cell; query radius
const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const D2R = Math.PI / 180;

export class Course {
  // M: the mountain the course runs down: { L, zc(x), pitches: [[centre, len, share]], land(x, z), corridor }
  constructor(rnd, M) {
    this.M = M;
    this.build(rnd);
    this.finish();
    this.slots = [{ d: Infinity, x: NaN, z: NaN }, { d: Infinity, x: NaN, z: NaN }]; this.lru = 0;
    this.planMarking(rnd);
  }

  // ---------------- layout ----------------
  build(r) {
    const M = this.M, X = [], Z = [], KD = [];
    let x = -36, z = 0, h = 0;
    const cells = new Map();   // incremental hash of committed points, for self-avoidance
    const key = (gx, gz) => gx * 100003 + gz;
    const commit = (from) => {
      for (let i = from; i < X.length; i++) {
        const k = key(Math.floor(X[i] / CELL), Math.floor(Z[i] / CELL));
        let l = cells.get(k); if (!l) cells.set(k, l = []); l.push(i);
      }
    };
    // does the stretch from index `from` come closer than `gap` m to course laid more than 70 m earlier?
    const clashes = (from, gap = 19) => {
      for (let i = from; i < X.length; i++) {
        const gx = Math.floor(X[i] / CELL), gz = Math.floor(Z[i] / CELL);
        for (let a = -2; a <= 2; a++) for (let b = -2; b <= 2; b++) {
          const l = cells.get(key(gx + a, gz + b)); if (!l) continue;
          for (const j of l) if ((i - j) * STEP > 70 && Math.hypot(X[i] - X[j], Z[i] - Z[j]) < gap) return true;
        }
        if (Math.abs(Z[i] - M.zc(X[i])) > M.corridor + 15) return true;
      }
      return false;
    };
    const emit = (kind) => { x += Math.cos(h) * STEP; z += Math.sin(h) * STEP; X.push(x); Z.push(z); KD.push(kind); };
    const straight = (len, kind, wob = 0) => {
      const n = Math.max(1, Math.round(len / STEP)), ph = r() * 6.28;
      for (let i = 0; i < n; i++) { h += wob * Math.cos(ph + i * 0.35) * 0.06; emit(kind); }
    };
    const arc = (ang, R, kind) => {   // ang signed: + turns towards +z
      const n = Math.max(1, Math.round(Math.abs(ang) * R / STEP)), dh = ang / n;
      for (let i = 0; i < n; i++) { h += dh / 2; emit(kind); h += dh / 2; }
    };
    const turnTo = (target, R, kind) => arc(wrap(target - h), R, kind);
    const off = () => z - M.zc(x);                           // lateral offset from the mountain's spine
    const nextPitch = () => M.pitches.find(([c, l]) => c + l / 2 > x);
    const snap = () => ({ x, z, h, n: X.length });
    const undo = (s) => { x = s.x; z = s.z; h = s.h; X.length = KD.length = Z.length = s.n; };

    // try a few takes of a section; keep the first that does not run into the course or off the mountain
    const attempt = (fns) => {
      for (let t = 0; t < 6; t++) {
        const s = snap();
        fns[t % fns.length]();
        if (!clashes(s.n)) { commit(s.n); return true; }
        undo(s);
      }
      const s = snap();   // fallback: straight down the fall line
      turnTo(0, 30, K.ROAD); straight(24, K.ROAD);
      commit(s.n);
      return false;
    };

    // --- the pieces ---
    const road = (maxLen) => {   // long fast stretch: big sweepers, never sharper than ~R 55 m
      const len = Math.min(maxLen, 90 + r() * 150);
      let done = 0;
      while (done < len) {
        const o = off(), lim = M.corridor - 30;
        let tgt = (r() * 2 - 1) * 32 * D2R;
        if (Math.abs(o) > lim * 0.55) tgt = -Math.sign(o) * (10 + r() * 22) * D2R;   // drift back to the middle
        const seg = Math.min(len - done, 40 + r() * 60), R = 55 + r() * 90;
        const n0 = X.length;
        turnTo(tgt, R, K.ROAD);
        const used = (X.length - n0) * STEP;
        if (used < seg) straight(seg - used, K.ROAD);
        done += Math.max(seg, used);
        if (x > M.L - 70) break;
      }
    };
    const switchbacks = (endX) => {   // across the slope, hairpin, across the other way... till below endX
      const first = off() > 0 ? -1 : 1, alpha = (12 + r() * 10) * D2R, R = 7 + r() * 2.5;
      let dir = first, n = 0;
      turnTo(dir * (Math.PI / 2 - alpha), 11 + r() * 4, K.SWITCH);
      while (n < 6) {
        const room = (M.corridor - 12 - dir * off()) / Math.cos(alpha);
        straight(Math.max(14, Math.min(26 + r() * 20, room)), K.SWITCH, 0.4);
        if (x > endX && n >= 2) break;
        dir = -dir; n++;
        turnTo(dir * (Math.PI / 2 - alpha), R, K.SWITCH);   // the hairpin: ~140 deg through the fall line
      }
      turnTo(0, 12 + r() * 4, K.SWITCH);
      straight(8, K.SWITCH);
    };
    const esses = (endX, kind = K.ESSES) => {   // linked turns, alternating, each banked
      let dir = r() < 0.5 ? 1 : -1, n = 0;
      if (Math.abs(off()) > 30) dir = -Math.sign(off());
      while (n < 9) {
        const ang = (38 + r() * 34) * D2R, R = 10 + r() * 8;
        turnTo(dir * ang, R, kind);
        straight(3 + r() * 6, kind);
        dir = -dir; n++;
        if (x > endX && n >= 3) break;
      }
      turnTo(0, 14, kind);
    };
    const chute = (endX) => {   // rock garden straight down the steep: pick your line
      turnTo((r() - .5) * 16 * D2R, 18, K.ROCKS);
      straight(Math.max(26, endX - x + 6), K.ROCKS, 0.25);
    };
    const jumpLine = () => {
      turnTo((r() - .5) * 14 * D2R, 40, K.ROAD);
      straight(10, K.ROAD);
      straight(80 + r() * 50, K.JUMP);   // dead straight: the features are built on it later
      straight(8, K.ROAD);
    };

    // --- the course ---
    straight(76, K.START);   // start ramp: spawn sits on it, 36 m in
    commit(0);
    let guard = 0;
    while (x < M.L - 80 && guard++ < 60 && X.length < 4000) {
      const p = nextPitch(), toPitch = p ? p[0] - p[1] / 2 - x : Infinity;
      if (toPitch < 30) {
        // the slope steepens: the crew built something technical to get down it
        const endX = p[0] + p[1] / 2 + 6, pick = r();
        attempt(pick < 0.45 ? [() => switchbacks(endX), () => esses(endX), () => chute(endX)]
          : pick < 0.75 ? [() => chute(endX), () => esses(endX), () => switchbacks(endX)]
          : [() => esses(endX), () => switchbacks(endX), () => chute(endX)]);
        continue;
      }
      // gentle ground: a long road, often with a jump line or a set of esses before the next pitch
      const room = Math.min(toPitch, M.L - 80 - x), pick = r();
      if (room > 230 && pick < 0.7) { attempt([() => road(Math.max(50, room - 190))]); attempt([jumpLine]); }
      else if (room > 150 && pick < 0.85) { attempt([() => road(Math.max(50, room - 110))]); attempt([() => esses(x + 50)]); }
      else attempt([() => road(Math.max(40, toPitch - 20))]);
    }
    const s = snap(); turnTo(0, 40, K.FINISH); straight(56, K.FINISH); commit(s.n);
    this.X = X; this.Z = Z; this.KD = KD; this.n = X.length;
  }

  // ---------------- derived data: tangents, curvature, width, bench height ----------------
  finish() {
    const n = this.n, X = this.X, Z = this.Z, M = this.M;
    const avg = (src, rad) => {   // moving average along the course
      const out = new Float32Array(n);
      for (let i = 0; i < n; i++) {
        let s = 0, c = 0;
        for (let k = Math.max(0, i - rad); k <= Math.min(n - 1, i + rad); k++) { s += src[k]; c++; }
        out[i] = s / c;
      }
      return out;
    };
    this.TX = new Float32Array(n); this.TZ = new Float32Array(n);
    const th = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const a = Math.max(0, i - 1), b = Math.min(n - 1, i + 1), dx = X[b] - X[a], dz = Z[b] - Z[a], l = Math.hypot(dx, dz) || 1;
      this.TX[i] = dx / l; this.TZ[i] = dz / l; th[i] = Math.atan2(dz, dx);
    }
    const kap = new Float32Array(n);
    for (let i = 1; i < n - 1; i++) kap[i] = wrap(th[i + 1] - th[i - 1]) / (2 * STEP);
    this.KAP = avg(kap, 2);
    this.W = avg(Float32Array.from(this.KD, (k) => WIDTH[k]), 5);
    // how much bank each corner gets: tighter corners and technical kinds more, eased in and out
    this.BT = avg(Float32Array.from(this.KAP, (k, i) => Math.min(0.6, 17 * Math.abs(k)) * smooth(0.012, 0.03, Math.abs(k)) * BERM[this.KD[i]]), 3);
    // ground height along the course: the land, smoothed, never climbing, never in a lake
    const raw = new Float32Array(n);
    for (let i = 0; i < n; i++) raw[i] = Math.max(M.water + 0.7, M.land(X[i], Z[i]));
    const sm = avg(raw, 5);
    for (let i = 1; i < n; i++) sm[i] = Math.min(sm[i], sm[i - 1]);
    this.E = avg(sm, 2);
    // surface: gravel double-track on the roads, rocky on the chutes (eased between kinds)
    this.RD = avg(Float32Array.from(this.KD, (k) => k === K.ROAD || k === K.START || k === K.FINISH ? 1 : 0), 4);
    this.RK = avg(Float32Array.from(this.KD, (k) => k === K.ROCKS ? 1 : 0), 4);
    this.len = (n - 1) * STEP;
    // spatial hash of segments (i -> i+1) by midpoint
    this.cells = new Map();
    for (let i = 0; i < n - 1; i++) {
      const k = Math.floor((X[i] + X[i + 1]) / 2 / CELL) * 100003 + Math.floor((Z[i] + Z[i + 1]) / 2 / CELL);
      let l = this.cells.get(k); if (!l) this.cells.set(k, l = []); l.push(i);
    }
    this._cand = [];
  }

  // ---------------- the question terrain keeps asking ----------------
  // -> q: d (m from the centreline), a (signed m across: + = left of the riding direction), i/t (segment),
  //    w (half-width), kind, k (curvature, + = bending left), bt (bank), bench (ground height the crew
  //    benched to, blended between nearby legs so switchbacks never leave a step), mask (0..1 bench weight)
  query(x, z) {
    // two cached answers: terrain tends to ask about a point, wander off to another, and come back
    const s0 = this.slots[0], s1 = this.slots[1];
    if (x === s0.x && z === s0.z) { this.lru = 1; return s0; }
    if (x === s1.x && z === s1.z) { this.lru = 0; return s1; }
    const q = this.slots[this.lru]; this.lru ^= 1;
    q.x = x; q.z = z;
    const X = this.X, Z = this.Z, c = this._cand;
    q.d = Infinity; q.mask = 0; c.length = 0;
    const g0x = Math.floor((x - QR) / CELL), g1x = Math.floor((x + QR) / CELL), g0z = Math.floor((z - QR) / CELL), g1z = Math.floor((z + QR) / CELL);
    for (let gx = g0x; gx <= g1x; gx++) for (let gz = g0z; gz <= g1z; gz++) {
      const l = this.cells.get(gx * 100003 + gz); if (l) for (const i of l) c.push(i);
    }
    if (!c.length) return q;
    c.sort((a, b) => a - b);
    let sw = 0, se = 0, legD = Infinity, legI = 0, legT = 0, prev = -9;
    const close = () => {   // one contiguous leg of the course: fold its nearest point into the blend
      if (legD === Infinity) return;
      legD = Math.sqrt(legD);
      const i = legI, t = legT, wl = this.W[i] + (this.W[i + 1] - this.W[i]) * t, e = this.E[i] + (this.E[i + 1] - this.E[i]) * t;
      const wt = 1 / ((legD * legD + 1) * (legD * legD + 1));
      sw += wt; se += wt * e;
      const m = 1 - smooth(wl + 1.5, wl + 8, legD);
      if (m > q.mask) q.mask = m;
      if (legD < q.d) {
        q.d = legD; q.i = i; q.t = t; q.w = wl;
        const px = X[i] + (X[i + 1] - X[i]) * t, pz = Z[i] + (Z[i + 1] - Z[i]) * t;
        const tx = this.TX[i], tz = this.TZ[i];
        // signed TRUE distance: projecting on the vertex tangent jumps where the nearest point moves from
        // one segment to the next (outside of bends), which left a step in every berm every 2 m
        q.a = (-(x - px) * tz + (z - pz) * tx < 0 ? -1 : 1) * legD;
        q.kind = this.KD[t < 0.5 ? i : i + 1];
        q.k = this.KAP[i] + (this.KAP[i + 1] - this.KAP[i]) * t;
        q.bt = this.BT[i] + (this.BT[i + 1] - this.BT[i]) * t;
        q.s = (i + t) * STEP;
        q.rd = this.RD[i] + (this.RD[i + 1] - this.RD[i]) * t;
        q.rk = this.RK[i] + (this.RK[i + 1] - this.RK[i]) * t;
      }
      legD = Infinity;
    };
    for (const i of c) {
      if (i - prev > 2) close();
      prev = i;
      const ax = X[i], az = Z[i], bx = X[i + 1] - ax, bz = Z[i + 1] - az;
      let t = ((x - ax) * bx + (z - az) * bz) / (bx * bx + bz * bz);
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      const ex = x - ax - bx * t, ez = z - az - bz * t, d2 = ex * ex + ez * ez;
      if (d2 < legD) { legD = d2; legI = i; legT = t; }
    }
    close();
    if (q.d > QR) { q.d = Infinity; q.mask = 0; return q; }
    q.bench = se / sw;
    return q;
  }
  at(s) {   // point on the centreline at arc length s -> [x, z, tx, tz, i]
    const f = Math.min(this.n - 1.001, Math.max(0, s / STEP)), i = Math.floor(f), t = f - i;
    return [this.X[i] + (this.X[i + 1] - this.X[i]) * t, this.Z[i] + (this.Z[i + 1] - this.Z[i]) * t, this.TX[i], this.TZ[i], i];
  }
  // contiguous runs of one kind: [[i0, i1, kind], ...]
  runs() {
    const out = []; let s = 0;
    for (let i = 1; i <= this.n; i++) if (i === this.n || this.KD[i] !== this.KD[s]) { out.push([s, i - 1, this.KD[s]]); s = i; }
    return out;
  }

  // ---------------- fences and tape, planned like a course builder would ----------------
  planMarking(r) {
    const n = this.n, KD = this.KD, runs = this.runs();
    // TAPE: both sides wherever it's technical, a jump line, or the start/finish; on the roads only
    // where it funnels you in/out of a section and on the outside of the tighter sweepers.
    // Caution (yellow/black) on rock gardens and switchbacks, and the last metres before them.
    const tapeSide = [new Uint8Array(n), new Uint8Array(n)], caution = new Uint8Array(n);
    const lead = Math.round(22 / STEP);
    for (const [i0, i1, k] of runs) {
      for (let i = i0; i <= i1; i++) {
        const tech = k !== K.ROAD;
        if (tech) { tapeSide[0][i] = tapeSide[1][i] = 1; }
        else {
          const nearEnd = i - i0 < lead || i1 - i < lead;
          if (nearEnd) tapeSide[0][i] = tapeSide[1][i] = 1;
          else if (Math.abs(this.KAP[i]) > 1 / 75) tapeSide[this.KAP[i] > 0 ? 1 : 0][i] = 1;   // outside of the bend
        }
        if (k === K.ROCKS || k === K.SWITCH) caution[i] = 1;
      }
      if (k === K.ROCKS || k === K.SWITCH) for (let i = Math.max(0, i0 - lead); i < i0; i++) caution[i] = 1;
    }
    // FENCES: road stretches run between pasture fences (one side, sometimes both), with gates every
    // so often; side trails crossing the road open their own gaps (terrain drops posts on trails)
    const fenceSide = [new Uint8Array(n), new Uint8Array(n)];
    this.fences = [];
    for (const [i0, i1, k] of runs) {
      if (k !== K.ROAD || (i1 - i0) * STEP < 50 || r() < 0.2) continue;
      const sides = r() < 0.35 ? [0, 1] : [r() < 0.5 ? 0 : 1];
      for (const sd of sides) {
        const sgn = sd ? -1 : 1, posts = [];
        let s = (i0 + lead + 2) * STEP, gateIn = 8 + ((r() * 16) | 0);
        const sEnd = (i1 - lead - 2) * STEP;
        while (s < sEnd) {
          const [x, z, tx, tz, i] = this.at(s), o = this.W[i] + 2.8;
          posts.push([x - tz * o * sgn, z + tx * o * sgn]);
          for (let j = Math.max(0, i - 1); j <= Math.min(n - 1, i + 1); j++) fenceSide[sd][j] = 1;
          // keep panels near their real length on curves: step the centreline less on the inside
          const kk = this.KAP[i] * sgn;
          s += 2.4 / Math.max(0.6, 1 - kk * o);
          if (--gateIn <= 0) {   // a gate: one or two panels left out
            if (posts.length >= 3) this.fences.push({ posts: posts.splice(0), style: 'ranch' });
            else posts.length = 0;
            s += 2.4 * (1 + ((r() * 2) | 0));
            gateIn = 8 + ((r() * 18) | 0);
          }
        }
        if (posts.length >= 3) this.fences.push({ posts, style: 'ranch' });
      }
    }
    // a white picket corral round the start and finish
    for (const [i0, i1, k] of runs) {
      if (k !== K.START && k !== K.FINISH) continue;
      for (const sgn of [1, -1]) {
        const posts = [];
        for (let s = i0 * STEP + (k === K.START ? 4 : 10); s < i1 * STEP - 4; s += 2.4) {
          const [x, z, tx, tz, i] = this.at(s), o = this.W[i] + 3.2;
          posts.push([x - tz * o * sgn, z + tx * o * sgn]);
        }
        if (posts.length >= 3) this.fences.push({ posts, style: 'picket' });
      }
    }
    // stakes: denser on corners so the tape follows them; none on the inside of a hairpin
    this.stakes = [];
    for (const sd of [0, 1]) {
      const sgn = sd ? -1 : 1;
      let s = 0, last = null;
      while (s < this.len) {
        const [x, z, tx, tz, i] = this.at(s), k = this.KAP[i], o = this.W[i] + 1.7;
        const inside = k * sgn > 0, R = 1 / Math.max(1e-4, Math.abs(k));
        const want = tapeSide[sd][i] && !(fenceSide[sd][i] && KD[i] === K.ROAD) && !(inside && R < o + 2.2);
        if (want) {
          const st = { x: x - tz * o * sgn, z: z + tx * o * sgn, s, side: sgn, caution: !!caution[i], prev: null };
          // join to the previous stake if it was the one just before (no gap) and the chord stays off the trail
          if (last && s - last.s < 9) {
            const mx = (st.x + last.x) / 2, mz = (st.z + last.z) / 2, qq = this.query(mx, mz);
            if (qq.d > qq.w + 0.4) st.prev = last;
          }
          this.stakes.push(st); last = st;
        } else last = null;
        s += Math.min(7.5, Math.max(3, 0.32 / Math.max(1e-4, Math.abs(k))));
      }
    }
    this.slots[0].x = this.slots[1].x = NaN;
  }
}

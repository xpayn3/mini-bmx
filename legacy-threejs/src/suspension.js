// Visual suspension for a bike exported with tools/export_dh.py: a fork that slides along the
// steer axis and a Horst-link four-bar rear end (chainstay G1-C1, seatstay C1-C2 carrying the
// axle A, rocker G2-C2-D, shock FE-D). Each end is a damped spring in metres of WHEEL travel,
// measured from sag (+ = deeper into the travel). The sprung part of the bike (everything that
// is not a wheel) is moved so both tyres stay where the ride physics put them.
import * as THREE from 'three';

const V = (p) => new THREE.Vector2(p[0], p[1]);
const rot = (v, a) => new THREE.Vector2(v.x * Math.cos(a) - v.y * Math.sin(a), v.x * Math.sin(a) + v.y * Math.cos(a));
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

export class Suspension {
  constructor(bike, data) {
    const s = data.suspension;
    const part = (n) => bike.getObjectByName(n);
    this.bike = bike;
    this.n = Object.fromEntries(['fork_lower', 'swing', 'seatstay', 'rocker', 'shock_body', 'shock_spring', 'shock_shaft']
      .map(k => [k, part(k)]));
    this.axis = new THREE.Vector3(...data.steerAxis).normalize();
    // either end may be rigid (a hardtail, a rigid fork): it then just stays at 0
    const f = s.fork, r = s.rear;
    this.hasF = !!(f && this.n.fork_lower); this.hasR = !!(r && this.n.swing);
    if (this.hasF) this.lower0 = this.n.fork_lower.position.clone();
    this.F = this.hasF ? { min: -f.sag * f.travel, max: (1 - f.sag) * f.travel } : { min: 0, max: 0 };
    this.R = this.hasR ? { min: -r.sag * r.travel, max: (1 - r.sag) * r.travel } : { min: 0, max: 0 };
    const pos = (name) => { const o = part(name); o.updateWorldMatrix(true, false); const w = bike.worldToLocal(o.getWorldPosition(new THREE.Vector3())); return new THREE.Vector2(w.x, w.y); };
    this.xF = 0; this.vF = 0; this.xR = 0; this.vR = 0;
    this.fax0 = pos('wheel_front');
    if (!this.hasR) {
      this.k = { A: pos('wheel_rear') };
      this.slope0 = Math.atan2(this.fax0.y - this.k.A.y, this.fax0.x - this.k.A.x);
      return;
    }
    // ---- four-bar, rest pose ----
    const k = this.k = { G1: V(r.G1), G2: V(r.G2), C1: V(r.C1), C2: V(r.C2), A: V(r.A), D: V(r.D), FE: V(r.FE) };
    k.lCS = k.C1.distanceTo(k.G1); k.lR = k.C2.distanceTo(k.G2); k.lSS = k.C2.distanceTo(k.C1);
    k.phi0 = Math.atan2(k.C1.y - k.G1.y, k.C1.x - k.G1.x);
    k.ss0 = Math.atan2(k.C2.y - k.C1.y, k.C2.x - k.C1.x);
    k.rk0 = Math.atan2(k.C2.y - k.G2.y, k.C2.x - k.G2.x);
    k.sh0 = Math.atan2(k.D.y - k.FE.y, k.D.x - k.FE.x);
    k.L0 = k.D.distanceTo(k.FE);
    this.springLen = r.springLen;
    // table: chainstay angle -> axle rise (relative to the frame). Walk both ways from rest.
    const rows = [];
    for (const dir of [-1, 1]) {
      let c2 = k.C2.clone();
      for (let i = dir < 0 ? 1 : 0; i < 400; i++) {
        const phi = k.phi0 + dir * i * 0.002;
        const p = this.solve(phi, c2);
        if (!p) break;
        c2 = p.C2;
        rows.push({ phi, rise: p.A.y - k.A.y });
      }
    }
    rows.sort((a, b) => a.rise - b.rise);
    this.table = rows;
    this.slope0 = Math.atan2(this.fax0.y - k.A.y, this.fax0.x - k.A.x);
    this.prevC2 = k.C2.clone();
  }

  // the linkage at chainstay angle phi (prev: last C2, picks the branch of the circle intersection)
  solve(phi, prev) {
    const k = this.k;
    const C1 = new THREE.Vector2(k.G1.x + k.lCS * Math.cos(phi), k.G1.y + k.lCS * Math.sin(phi));
    const d = C1.distanceTo(k.G2);
    if (d > k.lR + k.lSS || d < Math.abs(k.lR - k.lSS)) return null;
    const a = (k.lR * k.lR - k.lSS * k.lSS + d * d) / (2 * d), h = Math.sqrt(Math.max(0, k.lR * k.lR - a * a));
    const ex = (C1.x - k.G2.x) / d, ey = (C1.y - k.G2.y) / d;
    const mx = k.G2.x + a * ex, my = k.G2.y + a * ey;
    const s1 = new THREE.Vector2(mx - h * ey, my + h * ex), s2 = new THREE.Vector2(mx + h * ey, my - h * ex);
    const C2 = s1.distanceToSquared(prev) < s2.distanceToSquared(prev) ? s1 : s2;
    const ss = Math.atan2(C2.y - C1.y, C2.x - C1.x), rk = Math.atan2(C2.y - k.G2.y, C2.x - k.G2.x);
    const A = C1.clone().add(rot(k.A.clone().sub(k.C1), ss - k.ss0));
    const D = k.G2.clone().add(rot(k.D.clone().sub(k.G2), rk - k.rk0));
    return { C1, C2, A, D, ss, rk };
  }

  phiFor(rise) {   // invert the table (monotonic in the working range)
    const t = this.table;
    if (rise <= t[0].rise) return t[0].phi;
    if (rise >= t[t.length - 1].rise) return t[t.length - 1].phi;
    let lo = 0, hi = t.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (t[m].rise < rise) lo = m; else hi = m; }
    const u = (rise - t[lo].rise) / (t[hi].rise - t[lo].rise);
    return t[lo].phi + (t[hi].phi - t[lo].phi) * u;
  }

  // landing: v = how fast the bike came down (m/s), shared between the ends by which one touched
  land(v, frontAir, rearAir) {
    if (!Number.isFinite(v)) return;
    const kF = rearAir ? 1.2 : frontAir ? 0.3 : 0.9, kR = frontAir ? 1.2 : rearAir ? 0.3 : 1;
    this.vF += v * 1.15 * kF; this.vR += v * 0.95 * kR;   // a 1 m drop to flat uses ~70-80 % of the travel
  }

  // inp: air, load (0..1 crouch / pump), brake (0/1), bumpF / bumpR (m the ground under each
  // tyre sits above where the bike body expects it)
  update(dt, inp) {
    const step = (x, v, lim, tgt, hz, zeta) => {
      const w = 2 * Math.PI * hz;
      // rebound damped harder than compression, like a real damper
      const z = v < 0 ? zeta * 1.6 : zeta;
      v += (w * w * (tgt - x) - 2 * z * w * v) * dt;
      x += v * dt;
      if (x > lim.max) { x = lim.max; v = Math.min(0, v); }
      if (x < lim.min) { x = lim.min; v = Math.max(0, v); }
      return [x, v];
    };
    const fin = (v) => (Number.isFinite(v) ? v : 0);   // inputs not set up yet (just spawned) count as 0
    if (!Number.isFinite(this.xF + this.vF + this.xR + this.vR)) this.xF = this.vF = this.xR = this.vR = 0;
    let tF, tR;
    if (inp.air) { tF = this.F.min; tR = this.R.min; }   // topped out in the air
    else {
      tF = 0.03 * fin(inp.load) + 0.035 * fin(inp.brake) + clamp(fin(inp.bumpF), -0.06, 0.12);
      tR = 0.035 * fin(inp.load) - 0.01 * fin(inp.brake) + clamp(fin(inp.bumpR), -0.06, 0.12);
    }
    [this.xF, this.vF] = step(this.xF, this.vF, this.F, tF, 2.4, 0.5);
    [this.xR, this.vR] = step(this.xR, this.vR, this.R, tR, 2.1, 0.5);
  }

  apply() {
    const n = this.n, k = this.k;
    // fork: the lowers (and the wheel on them) slide up the steer axis
    if (this.hasF) n.fork_lower.position.copy(this.lower0).addScaledVector(this.axis, this.xF);
    const p = this.hasR ? this.poseRear() : { A: k.A };
    // keep both tyres where they were: rotate + shift the whole bike so its axles land back on
    // their rest heights (the wheels then sit on the ground the physics put them on)
    const pF = new THREE.Vector2(this.fax0.x + this.axis.x * this.xF, this.fax0.y + this.axis.y * this.xF);
    const th = this.slope0 - Math.atan2(pF.y - p.A.y, pF.x - p.A.x);
    const rA = rot(p.A, th);
    this.bike.rotation.z = th;
    this.bike.position.set(k.A.x - rA.x, k.A.y - rA.y, 0);
  }

  poseRear() {   // four-bar at the angle that lifts the axle by xR
    const n = this.n, k = this.k;
    const p = this.solve(this.phiFor(this.xR), this.prevC2) || this.solve(k.phi0, k.C2);
    this.prevC2.copy(p.C2);
    const phi = Math.atan2(p.C1.y - k.G1.y, p.C1.x - k.G1.x);
    n.swing.rotation.z = phi - k.phi0;
    n.seatstay.position.set(p.C1.x, p.C1.y, 0);
    n.seatstay.rotation.z = p.ss - k.ss0;
    n.rocker.rotation.z = p.rk - k.rk0;
    const sh = Math.atan2(p.D.y - k.FE.y, p.D.x - k.FE.x);
    n.shock_body.rotation.z = sh - k.sh0;
    n.shock_shaft.position.set(p.D.x, p.D.y, 0);
    n.shock_shaft.rotation.z = sh - k.sh0;
    n.shock_spring.scale.y = Math.max(0.3, (this.springLen - (k.L0 - p.D.distanceTo(k.FE))) / this.springLen);
    return p;
  }

  // shock stroke used at the rear's full travel (for checking the export)
  stroke() {
    if (!this.hasR) return 0;
    const p = this.solve(this.phiFor(this.R.max), this.k.C2);
    return this.k.L0 - p.D.distanceTo(this.k.FE);
  }
}

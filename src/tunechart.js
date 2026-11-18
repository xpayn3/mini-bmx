// Live chart for the tune panel: shows what the slider group you're touching actually does to the ride,
// your values (solid yellow) against the defaults (dashed). The curves use the same formulas as the
// physics in main.js, simplified to flat hard-pack where the ground matters.

const G = 9.81, WB = 1.0;   // gravity, wheelbase (m)
// (curves are for hard-pack dirt; grass and sand grip less -- see Grip & slides)
const sm = (x) => { const t = Math.min(1, Math.max(0, x)); return t * t * (3 - 2 * t); };
const span = (a, b, n = 80) => Array.from({ length: n + 1 }, (_, i) => a + (b - a) * i / n);
const DEG = 180 / Math.PI;

// damped spring step response (same integrator shape as the lean / leg springs)
function spring(k, damp, x0, target, dur, n = 160) {
  let x = x0, v = 0; const dt = dur / n, pts = [[0, x]];
  for (let i = 1; i <= n; i++) { v += ((target - x) * k - v * 2 * Math.sqrt(k) * damp) * dt; x += v * dt; pts.push([i * dt, x]); }
  return pts;
}
// tightest turn at speed v (m) on hard-pack, optionally while carving. asked = what the bars ask for;
// past the tyres' grip the real turn is wider (and a plain turn slides its rear out instead)
function radius(t, v, carve, asked = false) {
  const cf = carve ? sm((v - 4) / 4) : 0;
  const a = Math.max(1.2, t('turnSlow') + sm(v / 14) * (t('turnFast') - t('turnSlow')) + cf * t('carveBite'));
  const lock = t('steerMax') + Math.max(0, t('slowSteer') - t('steerMax')) * (1 - sm(v / Math.max(0.5, t('slowSteerFade'))));
  const r = Math.max(Math.min(v * v / a, v / t('turnFloor')), WB / Math.tan(lock));   // the bars (main.js dMax)
  return asked ? r : Math.max(r, v * v / (0.95 * t('grip') * G * (1 + t('carveGrip') * cf)));      // what the tyres can hold
}
const hopV = (t, charge) => 1.4 + t('popPower') * (0.4 + 0.6 * charge) + t('chargePop') * charge;
function speedCurve(t) {
  let v = 0; const pts = [[0, 0]], dt = 0.05;
  for (let s = dt; s <= 14 + 1e-9; s += dt) {
    const drive = Math.min(t('pedalLaunch'), t('pedalPower') / Math.max(v, 0.5)) * Math.min(1, Math.max(0, (t('pedalTop') - v) / 2.5));
    v = Math.max(0, v + (drive - 0.1 - t('airDrag') * v * v) * dt);
    pts.push([s, v * 3.6]);
  }
  return pts;
}

const CHARTS = {
  'Steering': {
    title: 'Tightest turn at each speed', x: 'speed km/h', y: 'turn radius m',
    lines: (t) => [{ pts: span(0.5, 15, 100).map((v) => [v * 3.6, radius(t, v, false, true)]), dot: true, alt: true, label: 'bars ask' },
                   { pts: span(0.5, 15, 100).map((v) => [v * 3.6, radius(t, v, false)]), label: 'tyres hold' }],
    note: (t) => `Where "bars ask" dips below "tyres hold", a plain turn slides. Full lock in ${(1 / t('steerRate')).toFixed(2)} s`,
  },
  'Momentum': {
    title: 'Coasting from 30 km/h on grass, no pedalling', x: 'time s', y: 'km/h',
    lines: (t) => [0, 5].map((f) => {
      let v = 30 / 3.6; const carry = 1 - t('flowCarry') * f / 5;
      return { pts: span(0, 20, 100).map((s, i) => { if (i) for (let j = 0; j < 4; j++) v = Math.max(0, v - (0.32 * t('rollRes') * Math.min(1, v * 4) + t('airDrag') * v * v) * carry * 0.05); return [s, v * 3.6]; }),
               alt: !f, label: f ? 'full flow' : 'no flow' };
    }),
    note: (t) => `Turns build up / unwind over ~${t('turnWeight').toFixed(2)} s at speed · flow fades ${t('flowTime')} s after your last jump, pump or carve`,
  },
  'Carving': {
    title: 'Turn radius: plain turn vs held carve', x: 'speed km/h', y: 'turn radius m',
    lines: (t) => [{ pts: span(1, 15).map((v) => [v * 3.6, radius(t, v, false)]), alt: true, label: 'plain' },
                   { pts: span(1, 15).map((v) => [v * 3.6, radius(t, v, true)]), label: 'carve' }],
    note: (t) => `Clean carve exit: up to +${Math.round(t('carveBoost') * 3.6)} km/h on a berm, +${Math.round(t('carveBoost') * 1.8)} on flat`,
  },
  'Grip & slides': {
    title: 'A slide being caught (wash-out line dotted)', x: 'time s', y: 'slide angle °',
    lines: (t) => [{ pts: span(0, 1.2).map((s) => [s, 35 * Math.exp(-t('slipRecover') * 0.75 * s)]) },
                   { pts: [[0, t('slipMax') * DEG], [1.2, t('slipMax') * DEG]], dot: true }],
    note: (t) => `Corner grip: hard-pack ${(0.95 * t('grip')).toFixed(2)} g · grass ${(0.72 * t('grip')).toFixed(2)} g · sand ${(0.5 * t('grip')).toFixed(2)} g`,
  },
  'Air': {
    title: 'Holding A/D in the air', x: 'time s', y: 'bike twist °',
    lines: (t) => { let r = 0, a = 0; return [{ pts: span(0, 1.2).map((s, i) => { if (i) { r += (t('airTurn') - r) * Math.min(1, 0.015 * 4); a = Math.min(t('airTwist'), a + r * 0.015); } return [s, a * DEG]; }) }]; },
    note: (t) => `Twist stops at ${Math.round(t('airTwist') * DEG)}° · whatever is left at touchdown must be caught by the tyres`,
  },
  'Wheels & pump': {
    title: 'Bike after hitting a bump', x: 'time s', y: 'spring mm',
    lines: (t) => [{ pts: spring((2 * Math.PI * t('tyreHz')) ** 2, t('tyreDamp'), t('travel') * 1000, 0, 1.5) }],
    note: (t) => `Bounces ${t('tyreHz').toFixed(1)} times a second · legs press ${t('legPress').toFixed(2)} g · pump strength ${t('pumpGain')}`,
  },
  'Lean': {
    title: 'Lean into a full turn, then let go', x: 'time s', y: 'lean °',
    lines: (t) => {
      const inn = spring(t('leanIn'), t('leanDamp'), 0, t('leanMax'), 0.6, 80);
      const out = spring(t('leanOut'), t('leanDamp'), inn[inn.length - 1][1], 0, 0.6, 80).map(([s, x]) => [s + 0.6, x]);
      return [{ pts: inn.concat(out).map(([s, x]) => [s, x * DEG]) }];
    },
    note: (t) => `Max lean ${Math.round(t('leanMax') * DEG)}° · bike leans ${t('bikeLeanMul').toFixed(2)}× the rider`,
  },
  'Legs & body': {
    title: 'Rider’s body after a 10 cm drop', x: 'time s', y: 'body offset cm',
    lines: (t) => [{ pts: spring(t('legStiff'), t('legDamp'), 10, 0, 1.6) }],
    note: (t) => `Legs bend ${Math.round(t('legComp') * 100)} cm, extend ${Math.round(t('legExt') * 100)} cm · ${Math.round(t('riderMass') * 100)}% of the weight rides on them`,
  },
  'Jumping': {
    title: 'Bunny hop at 25 km/h: tap vs full bar', x: 'distance m', y: 'height m',
    lines: (t) => [0, 1].map((c) => {
      const vy = hopV(t, c), tt = 2 * vy / G;
      return { pts: span(0, tt, 40).map((s) => [7 * s, vy * s - G * s * s / 2]), alt: !c, label: c ? 'full' : 'tap' };
    }),
    note: (t) => `Tap ${(hopV(t, 0) ** 2 / 2 / G).toFixed(2)} m · full bar ${(hopV(t, 1) ** 2 / 2 / G).toFixed(2)} m after ${t('chargeTime').toFixed(1)} s hold`,
  },
  'Speed': {
    title: 'Pedalling from a standstill on the flat', x: 'time s', y: 'km/h',
    lines: (t) => [{ pts: speedCurve(t) }],
    note: (t) => `Brakes stop you from 30 km/h in ${((30 / 3.6) ** 2 / 2 / Math.min(t('brakeForce'), 0.85 * 0.95 * G)).toFixed(1)} m`,
  },
};

export function chartFor(group) { return CHARTS[group] ? group : null; }

// cur / def: (key) => value, already scaled for the bike being ridden
export function drawChart(canvas, group, cur, def) {
  const spec = CHARTS[group]; if (!spec) return '';
  const dpr = Math.min(2, window.devicePixelRatio || 1), W = canvas.clientWidth || 272, H = canvas.clientHeight || 130;
  if (canvas.width !== Math.round(W * dpr)) { canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr); }
  const c = canvas.getContext('2d'); c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, W, H);
  const mine = spec.lines(cur), base = spec.lines(def);
  // shared axes over both sets so a change is visible as a shift
  let x0 = Infinity, x1 = -Infinity, y0 = 0, y1 = -Infinity;
  for (const s of mine.concat(base)) for (const [x, y] of s.pts) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  y1 = y1 + (y1 - y0) * 0.08 || 1;
  const L = 34, R = 8, T = 6, B = 18, px = (x) => L + (x - x0) / (x1 - x0 || 1) * (W - L - R), py = (y) => H - B - (y - y0) / (y1 - y0) * (H - T - B);
  // grid + labels
  c.font = '10px ui-rounded, "Segoe UI", system-ui, sans-serif'; c.fillStyle = 'rgba(238,244,246,.55)'; c.strokeStyle = 'rgba(255,255,255,.1)'; c.lineWidth = 1;
  const nice = (a, b) => { const st = 10 ** Math.floor(Math.log10((b - a) / 3 || 1)); const k = (b - a) / st > 15 ? 5 : (b - a) / st > 6 ? 2 : 1; return st * k; };
  const ys = nice(y0, y1), xs = nice(x0, x1);
  c.textAlign = 'right'; c.textBaseline = 'middle';
  for (let v = Math.ceil(y0 / ys) * ys; v <= y1; v += ys) { c.beginPath(); c.moveTo(L, py(v)); c.lineTo(W - R, py(v)); c.stroke(); c.fillText(+v.toFixed(2), L - 4, py(v)); }
  c.textAlign = 'center'; c.textBaseline = 'top';
  for (let v = Math.ceil(x0 / xs) * xs; v <= x1 + 1e-9; v += xs) c.fillText(+v.toFixed(2), px(v), H - B + 4);
  c.textAlign = 'left'; c.fillText(spec.y, L + 4, T); c.textAlign = 'right'; c.fillText(spec.x, W - R, H - B - 12);
  const line = (s, style, width, dash) => {
    c.beginPath(); s.pts.forEach(([x, y], i) => (i ? c.lineTo(px(x), py(y)) : c.moveTo(px(x), py(y))));
    c.strokeStyle = style; c.lineWidth = width; c.setLineDash(dash); c.stroke(); c.setLineDash([]);
  };
  for (const s of base) line(s, 'rgba(255,255,255,.35)', 1.5, [4, 3]);   // defaults
  for (const s of mine) line(s, s.alt ? 'rgba(255,255,255,.75)' : '#ffd21f', s.alt ? 1.5 : 2.2, s.dot ? [1.5, 3] : []);
  c.textAlign = 'left'; c.textBaseline = 'middle';
  for (const s of mine) if (s.label) { const [x, y] = s.pts[Math.floor(s.pts.length * (s.alt ? 0.3 : 0.75))]; c.fillStyle = s.alt ? 'rgba(255,255,255,.8)' : '#ffd21f'; c.fillText(s.label, px(x) + 4, py(y) - 8); }
  return spec.note(cur);
}

export const chartTitle = (group) => CHARTS[group]?.title || '';

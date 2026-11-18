// Hand-shaped trail features. Each profile is a list of knots [u, h, slopeIn, slopeOut?]
// joined by cubic Hermite curves, so every face is smooth and only the lips have a crisp edge.
// u runs along the trail in metres (riding direction), h is metres above the flattened ground.
// No imports here so tools/ can simulate these profiles in plain node.

function hermite(knots) {
  const end = knots[knots.length - 1][0];
  const f = (u) => {
    if (u <= 0 || u >= end) return 0;
    let i = 0;
    while (knots[i + 1][0] < u) i++;
    const [u0, h0, , so0 = knots[i][2]] = knots[i];
    const [u1, h1, si1] = knots[i + 1];
    const d = u1 - u0, t = (u - u0) / d, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * d * so0 + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * d * si1;
  };
  f.len = end;
  return f;
}

// tabletop: roll it slowly, or boost the table and touch down on the landing
const TABLE = [
  [0, 0, 0], [5.5, 1.25, 0.5, 0], [9.5, 1.25, 0, 0],
  [11.5, 0.95, -0.36], [17, 0.18, -0.2], [21, 0, 0],
];
// double: proper gap, needs some speed (pedal in!) but the landing is long and forgiving
const DOUBLE = [
  [0, 0, 0], [5, 1.35, 0.58, -1.6], [6.0, 0.35, 0, 0], [7.5, 0.35, 0, 1.4],
  [9.2, 1.2, 0, 0], [10.2, 1.2, 0, 0], [12.5, 0.85, -0.34], [19, 0.15, -0.16], [23, 0, 0],
];
// small kicker into a long down-slope: easy air for everyone
const KICKER = [
  [0, 0, 0], [3.2, 0.7, 0.42, 0], [4.0, 0.7, 0, 0],
  [6.5, 0.48, -0.2], [14, 0, 0],
];
// rhythm: a run of rounded whoops, gentle in front and a longer back side to land on
const WHOOP = [[0, 0, 0], [1.6, 0.3, 0.3], [2.6, 0.48, 0], [8.6, 0.08, -0.09], [10, 0, 0]];
function rollers(n, amp) {
  const w = hermite(WHOOP.map(([u, h, a, b]) => [u, h * amp / 0.48, a * amp / 0.48, b === undefined ? b : b * amp / 0.48]));
  const f = (u) => (u <= 0 || u >= n * w.len) ? 0 : w(u % w.len);
  f.len = n * w.len;
  return f;
}

// combine pieces back to back with flat run-outs between them
function line(...parts) {
  const segs = []; let at = 0;
  for (const p of parts) { if (typeof p === 'number') { at += p; continue; } segs.push([at, p]); at += p.len; }
  const f = (u) => { for (const [s, p] of segs) if (u > s && u < s + p.len) return p(u - s); return 0; };
  f.len = at;
  return f;
}

const table = hermite(TABLE), double = hermite(DOUBLE), kicker = hermite(KICKER);
export const PROFILES = {
  table, double, kicker,
  rhythm: rollers(4, 0.5),
  tableLine: line(table, 3, kicker),
  flow: line(kicker, 3, rollers(3, 0.45)),
  doubleLine: line(double, 3, kicker),
};

// ---------- wooden features ----------
// The wood is rideable (part of terrain.height) but drawn as plank models, not as ground mesh.
// top(u): deck height above the flattened ground; only exists for u0 <= u <= u1 and |w| <= half.
const ramp = (u0, u1, h0, h1) => (u) => h0 + (h1 - h0) * Math.min(1, Math.max(0, (u - u0) / (u1 - u0)));
// wooden kicker: curved plank ramp with an open back, then a long dirt landing
const WOOD_KICK = hermite([[0, 0, 0.1], [3.8, 0.95, 0.4]]);
const kickLanding = hermite([[0, 0, 0], [4.6, 0, 0], [6.4, 0.9, 0.1, 0], [7.4, 0.9, 0, 0], [10, 0.72, -0.17], [20, 0.14, -0.08], [26, 0, 0]]);
// skinny: north-shore plank path, up a ramp, along a narrow deck, down a ramp
const skinUp = hermite([[0, 0.02, 0.05], [2, 0.42, 0.3], [4, 0.85, 0]]);
const skinnyTop = (u) => u < 4 ? skinUp(u) : u < 15 ? 0.85 : skinUp(Math.max(0.001, 19 - u));
// bridge: wider deck across a dug-out ditch -- miss it and you are in the ditch
const bridgeTop = (u) => u < 2 ? ramp(0, 2, 0.02, 0.45)(u) : u < 13 ? 0.45 : ramp(13, 15, 0.45, 0.02)(u);
const ditch = hermite([[0, 0, 0], [1.6, 0, 0], [3.4, -1.9, 0], [11.6, -1.9, 0], [13.4, 0, 0], [15, 0, 0]]);
const flat = (len) => { const f = () => 0; f.len = len; return f; };

export const WOOD = {
  woodKicker: { top: (u) => u >= 3.8 ? 0.95 : WOOD_KICK(u), u0: 0, u1: 3.8, half: 0.85, backWall: true },
  skinny: { top: skinnyTop, u0: 0, u1: 19, half: 0.33 },
  bridge: { top: bridgeTop, u0: 0, u1: 15, half: 0.8 },
};
export const DIG = { bridge: ditch };   // ground carved below the flattened plane
PROFILES.woodKicker = kickLanding;
PROFILES.skinny = flat(19);
PROFILES.bridge = flat(15);

export const FEATURE_TYPES = ['table', 'table', 'double', 'kicker', 'rhythm', 'tableLine', 'flow', 'doubleLine',
  'woodKicker', 'woodKicker', 'skinny', 'bridge'];
// the main downhill route skips gaps and skinnies: you can coast it without pedalling and never case anything
export const ROUTE_TYPES = ['table', 'table', 'kicker', 'rhythm', 'tableLine', 'flow', 'woodKicker', 'bridge'];
export const _raw = { TABLE, DOUBLE, KICKER };

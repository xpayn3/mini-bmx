// Live driving-style tuning: every value the ride feel depends on, with a slider panel (P to toggle).
// Values persist in localStorage; "Copy" puts the current set on the clipboard as JSON so it can be
// pasted back here as new defaults.

const DEFS = [
  ['Steering', [
    ['steerRate',    'Steer build-up',       9,     1,    25,   0.5,  '/s'],
    ['steerRelease', 'Steer release',        7,     1,    25,   0.5,  '/s'],
    ['steerCurve',   'Soft centre',          0.25,  0,    1,    0.05, ''],
    ['turnSlow',     'Turn force (slow)',    4.6,   1,    12,   0.1,  'm/s²'],
    ['turnFast',     'Turn force (fast)',    7,     1,    14,   0.1,  'm/s²'],
    ['turnFloor',    'Min turn rate',        1.7,   0.3,  3.5,  0.05, 'rad/s'],
    ['steerMax',     'Max bar angle',        0.55,  0.2,  0.9,  0.01, 'rad'],
    ['barSpeed',     'Bar speed',            18,    3,    40,   1,    '/s'],
    ['counter',      'Countersteer flick',   0.2,   0,    0.8,  0.02, ''],
  ]],
  ['Grip & slides', [
    ['grip',         'Tyre grip',            1,     0.4,  1.6,  0.02, '×'],
    ['oversteer',    'Rear steps out',       0.35,  0,    1,    0.05, ''],
    ['slipRecover',  'Slide catch',          5,     0.5,  15,   0.5,  '/s'],
    ['slipMax',      'Wash-out angle',       0.85,  0.4,  1.4,  0.05, 'rad'],
  ]],
  ['Air', [
    ['airTurn',      'Air twist speed',      0.7,   0,    3,    0.05, 'rad/s'],
    ['airTwist',     'Max air twist',        0.45,  0,    1.4,  0.05, 'rad'],
  ]],
  ['Wheels & pump', [
    ['tyreHz',       'Bounce frequency',     3.2,   1.2,  7,    0.1,  'Hz'],
    ['tyreDamp',     'Bounce damping',       0.3,   0.05, 1,    0.01, ''],
    ['travel',       'Spring travel',        0.07,  0.02, 0.25, 0.005,'m'],
    ['legPress',     'Legs press bike down', 0.5,   0,    2,    0.05, 'g'],
    ['riderBalance', 'Rider balance (1 wheel)',0.7, 0,    1.5,  0.05, ''],
    ['crestCap',     'Max throw off a crest', 2.0,  0.5,  5,    0.1,  'm/s'],
    ['noseDive',     'Nose-dive crash angle',0.6,   0.3,  1.2,  0.05, 'rad'],
    ['pumpGain',     'Pump strength',        9,     0,    25,   0.5,  ''],
  ]],
  ['Lean', [
    ['leanMax',      'Max lean',             0.65,  0.15, 1.1,  0.01, 'rad'],
    ['leanIn',       'Roll-in stiffness',    75,    8,    200,  1,    ''],
    ['leanOut',      'Roll-out stiffness',   55,    8,    200,  1,    ''],
    ['leanDamp',     'Lean damping',         0.88,  0.3,  1.6,  0.02, ''],
    ['bikeLeanMul',  'Bike leans extra',     1.15,  0.7,  1.8,  0.01, '×'],
    ['bikeLeanCap',  'Bike lean soft cap',   0.75,  0.3,  1.2,  0.01, 'rad'],
  ]],
  ['Legs & body', [
    ['legStiff',     'Leg spring',           30,    4,    150,  1,    ''],
    ['legDamp',      'Leg damping',          0.75,  0.15, 1.6,  0.01, ''],
    ['legComp',      'Leg bend travel',      0.2,   0.03, 0.4,  0.01, 'm'],
    ['legExt',       'Leg extend travel',    0.13,  0.02, 0.3,  0.01, 'm'],
    ['bodyLevel',    'Keep body level',      0.85,  0,    1,    0.05, ''],
    ['attackDrop',   'Get low on descents',  0.18,  0,    0.45, 0.01, 'm'],
    ['riderMass',    'Body weight on legs',  0.45,  0,    0.7,  0.05, ''],
    ['weightShift',  'Weight shift reach',   0.12,  0,    0.25, 0.01, 'm'],
    ['loadHeight',   'Weight transfer height',0.25, 0,    1,    0.05, 'm'],
  ]],
  ['Jumping', [
    ['prepTime',     'Spot lip ahead',       0.55,  0.1,  1.2,  0.05, 's'],
    ['prepDepth',    'Crouch into lip',      0.16,  0,    0.3,  0.01, 'm'],
    ['popKick',      'Pump extension',       1.5,   0,    4,    0.1,  'm/s'],
    ['autoPop',      'Lip pop height',       1.2,  0,    3,    0.05, 'm/s'],
    ['landPrepTime', 'Reach for landing',    0.35,  0.05, 1,    0.05, 's'],
    ['landSoak',     'Landing absorb',       0.3,   0,    1.5,  0.05, ''],
  ]],
  ['Speed', [
    ['pedalLaunch',  'Launch push',          8,     2,    16,   0.5,  'm/s²'],
    ['pedalPower',   'Pedal power',          21,    5,    50,   1,    ''],
    ['pedalTop',     'Pedal top speed',      11.8,  4,    22,   0.2,  'm/s'],
    ['airDrag',      'Air drag',             0.0036,0,    0.012,0.0002,''],
    ['brakeForce',   'Brake',                7.5,   2,    15,   0.5,  'm/s²'],
    ['popPower',     'Pump pop',             2.4,   0.5,  6,    0.1,  'm/s'],
  ]],
];

const KEY = 'bmx-tune-v1';
const RETIRED = { autoPop: 0.5 };   // key -> previous default (autoPop raised to 1.2 with round-wheel contact)
export const DEFAULTS = {};
for (const [, rows] of DEFS) for (const [k, , d] of rows) DEFAULTS[k] = d;

export const TUNE = { ...DEFAULTS };
try {
  const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
  for (const k in saved) if (k in DEFAULTS && Number.isFinite(saved[k])) TUNE[k] = saved[k];
  // defaults that changed: a saved value still sitting on the OLD default was never chosen by the player
  // (save() stores every slider), so it moves to the new one
  for (const [k, old] of Object.entries(RETIRED)) if (saved[k] === old) TUNE[k] = DEFAULTS[k];
} catch { /* storage blocked: just use defaults */ }
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(TUNE)); } catch { /* ignore */ } };

const fmt = (v, step) => {
  const dec = step >= 1 ? 0 : Math.min(4, Math.ceil(-Math.log10(step)));
  return v.toFixed(dec);
};

export function buildTunePanel() {
  const css = document.createElement('style');
  css.textContent = `
  #tune { position: fixed; top: 80px; left: 12px; bottom: 56px; width: 300px; max-width: calc(100vw - 24px); overflow-y: auto;
    background: rgba(16,26,34,.82); backdrop-filter: blur(8px); color: #eef4f6; border-radius: 14px; padding: 10px 14px 14px;
    font: 12px/1.3 ui-rounded, "Segoe UI", system-ui, sans-serif; z-index: 20; box-shadow: 0 8px 30px rgba(0,0,0,.35); display: none; }
  #tune.open { display: block; }
  #tune h3 { margin: 12px 0 6px; font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: #ffd21f; }
  #tune .head { display: flex; align-items: center; gap: 6px; position: sticky; top: -10px; background: inherit; padding: 4px 0 6px; }
  #tune .head strong { flex: 1; font-size: 15px; }
  #tune button { background: rgba(255,255,255,.14); color: #fff; border: 0; border-radius: 7px; padding: 5px 9px; font: inherit; font-weight: 700; cursor: pointer; }
  #tune button:hover { background: rgba(255,255,255,.26); }
  #tune .row { display: grid; grid-template-columns: 1fr auto; gap: 1px 8px; margin: 5px 0; }
  #tune .row label { opacity: .9; }
  #tune .row .val { font-variant-numeric: tabular-nums; font-weight: 700; cursor: pointer; }
  #tune .row .val.changed { color: #ffd21f; }
  #tune .row input { grid-column: 1 / -1; width: 100%; margin: 0; accent-color: #ffd21f; }
  #tuneBtn { position: fixed; right: 22px; top: 54px; z-index: 19; background: rgba(20,40,50,.45); color: #fff; border: 0; border-radius: 999px;
    padding: 6px 12px; font: 800 13px ui-rounded, "Segoe UI", system-ui, sans-serif; cursor: pointer; backdrop-filter: blur(6px); }
  `;
  document.head.appendChild(css);

  const panel = document.createElement('div');
  panel.id = 'tune';
  panel.innerHTML = `<div class="head"><strong>Ride tuning</strong><button data-a="copy" title="Copy values as JSON">Copy</button><button data-a="reset">Reset</button><button data-a="close">✕</button></div>`;
  const rows = {};
  for (const [group, list] of DEFS) {
    const h = document.createElement('h3'); h.textContent = group; panel.appendChild(h);
    for (const [k, label, , min, max, step, unit] of list) {
      const row = document.createElement('div'); row.className = 'row';
      row.innerHTML = `<label for="t_${k}">${label}</label><span class="val" title="Click to reset"></span><input id="t_${k}" type="range" min="${min}" max="${max}" step="${step}">`;
      const input = row.querySelector('input'), val = row.querySelector('.val');
      const show = () => { val.textContent = fmt(TUNE[k], step) + (unit ? ' ' + unit : ''); val.classList.toggle('changed', TUNE[k] !== DEFAULTS[k]); };
      input.value = TUNE[k]; show();
      input.addEventListener('input', () => { TUNE[k] = +input.value; show(); save(); });
      // don't let the slider keep focus, or A/D and arrows would move it while riding
      input.addEventListener('pointerup', () => input.blur());
      input.addEventListener('keydown', (e) => e.preventDefault());
      val.addEventListener('click', () => { TUNE[k] = DEFAULTS[k]; input.value = TUNE[k]; show(); save(); });
      rows[k] = { input, show };
      panel.appendChild(row);
    }
  }
  document.body.appendChild(panel);

  const btn = document.createElement('button');
  btn.id = 'tuneBtn'; btn.textContent = '⚙ Tune (P)';
  document.body.appendChild(btn);

  const toggle = () => { panel.classList.toggle('open'); btn.style.display = panel.classList.contains('open') ? 'none' : ''; btn.blur(); };
  btn.addEventListener('click', toggle);
  addEventListener('keydown', (e) => { if (e.code === 'KeyP' && !e.repeat) toggle(); });
  panel.addEventListener('pointerdown', (e) => e.stopPropagation());
  panel.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });
  panel.addEventListener('click', async (e) => {
    const a = e.target.dataset && e.target.dataset.a;
    if (!a) return;
    e.target.blur();
    if (a === 'close') toggle();
    if (a === 'reset') { Object.assign(TUNE, DEFAULTS); for (const k in rows) { rows[k].input.value = TUNE[k]; rows[k].show(); } save(); }
    if (a === 'copy') {
      const txt = JSON.stringify(TUNE, null, 2);
      try { await navigator.clipboard.writeText(txt); e.target.textContent = 'Copied!'; }
      catch { console.log(txt); e.target.textContent = 'In console'; }
      setTimeout(() => { e.target.textContent = 'Copy'; }, 1200);
    }
  });
}

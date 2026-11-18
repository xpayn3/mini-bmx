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
  #tune { position: fixed; top: 16px; left: 16px; bottom: 16px; width: 320px; max-width: calc(100vw - 32px); z-index: 31;
    display: flex; flex-direction: column; overflow: hidden; color: #eef4f6; border-radius: 18px;
    font: 600 12.5px/1.3 ui-rounded, "Segoe UI", system-ui, sans-serif; text-shadow: none;
    background: rgba(14,24,31,.86); backdrop-filter: blur(14px) saturate(1.2);
    box-shadow: 0 18px 40px rgba(0,0,0,.35), inset 0 0 0 1px rgba(255,255,255,.08);
    opacity: 0; transform: translateX(-12px); pointer-events: none; transition: opacity .18s ease, transform .18s ease; }
  #tune.open { opacity: 1; transform: none; pointer-events: auto; }
  /* header stays put; only the list scrolls under it */
  #tune .head { flex: none; padding: 14px 14px 10px; border-bottom: 1px solid rgba(255,255,255,.07); }
  #tune .title { display: flex; align-items: center; gap: 8px; }
  #tune .title strong { flex: 1; font-size: 15px; font-weight: 800; letter-spacing: .2px; }
  #tune .title kbd { font: 800 10px/1 ui-monospace, Consolas, monospace; padding: 3px 5px; border-radius: 5px; color: rgba(255,255,255,.6);
    background: rgba(255,255,255,.1); }
  #tune .tools { display: flex; gap: 6px; margin-top: 10px; }
  #tune .search { flex: 1; min-width: 0; padding: 8px 10px; border: 0; border-radius: 10px; outline: none; color: #fff;
    font: 600 12.5px ui-rounded, "Segoe UI", system-ui, sans-serif; background: rgba(255,255,255,.08); }
  #tune .search::placeholder { color: rgba(255,255,255,.4); }
  #tune .search::-webkit-search-cancel-button { -webkit-appearance: none; display: none; }   /* Esc clears */
  #tune .search:focus { background: rgba(255,255,255,.13); box-shadow: inset 0 0 0 1px rgba(255,210,31,.5); }
  #tune button { border: 0; border-radius: 10px; padding: 7px 10px; cursor: pointer; color: #fff; background: rgba(255,255,255,.09);
    font: 700 12px ui-rounded, "Segoe UI", system-ui, sans-serif; transition: background .15s; }
  #tune button:hover { background: rgba(255,255,255,.18); }
  #tune .x { width: 30px; height: 30px; padding: 0; border-radius: 9px; font-size: 14px; }
  #tune .body { flex: 1; overflow-y: auto; padding: 4px 14px 14px; scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.18) transparent; }
  #tune .body::-webkit-scrollbar { width: 8px; }
  #tune .body::-webkit-scrollbar-thumb { background: rgba(255,255,255,.16); border-radius: 4px; border: 2px solid transparent; background-clip: padding-box; }
  /* sections */
  #tune details { border-bottom: 1px solid rgba(255,255,255,.06); }
  #tune summary { list-style: none; cursor: pointer; display: flex; align-items: center; gap: 8px; padding: 12px 0 8px; user-select: none;
    font-size: 10.5px; font-weight: 800; letter-spacing: 1.3px; text-transform: uppercase; color: rgba(255,255,255,.55); }
  #tune summary::-webkit-details-marker { display: none; }
  #tune summary .n { flex: 1; }
  #tune summary .badge { display: none; padding: 2px 6px; border-radius: 6px; font-size: 9.5px; letter-spacing: .4px; color: #1d2b64; background: #ffd21f; }
  #tune summary .badge.on { display: inline-block; }
  #tune summary::after { content: ''; width: 6px; height: 6px; margin-right: 3px; border-right: 2px solid currentColor; border-bottom: 2px solid currentColor;
    transform: rotate(45deg) translate(-2px, -2px); transition: transform .15s; }
  #tune details:not([open]) summary::after { transform: rotate(-45deg); }
  /* rows */
  #tune .row { padding: 6px 0 8px; }
  #tune .row.hide { display: none; }
  #tune .row .top { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 6px; }
  #tune .row label { color: rgba(255,255,255,.88); }
  #tune .val { font-variant-numeric: tabular-nums; font-weight: 800; font-size: 12px; padding: 3px 7px; border-radius: 7px;
    background: rgba(255,255,255,.07); cursor: default; white-space: nowrap; }
  #tune .val.changed { color: #ffd21f; background: rgba(255,210,31,.14); cursor: pointer; }
  #tune .val.changed::before { content: '↺ '; opacity: .8; }
  #tune .val.changed:hover { background: rgba(255,210,31,.24); }
  /* slider: thin filled track, white thumb, tick at the default value */
  #tune .trk { position: relative; }
  #tune .trk::after { content: ''; position: absolute; left: calc(7px + (100% - 14px) * var(--d)); top: 4px; width: 2px; height: 10px;
    margin-left: -1px; border-radius: 1px; background: rgba(255,255,255,.35); pointer-events: none; }
  #tune input[type=range] { -webkit-appearance: none; appearance: none; display: block; width: 100%; height: 18px; margin: 0; background: transparent; cursor: pointer; }
  #tune input[type=range]::-webkit-slider-runnable-track { height: 4px; border-radius: 2px;
    background: linear-gradient(90deg, #ffd21f calc(var(--p) * 100%), rgba(255,255,255,.14) calc(var(--p) * 100%)); }
  #tune input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; position: relative; z-index: 1; width: 14px; height: 14px; margin-top: -5px;
    border-radius: 50%; background: #fff; box-shadow: 0 1px 4px rgba(0,0,0,.45); transition: transform .1s; }
  #tune input[type=range]:hover::-webkit-slider-thumb { transform: scale(1.15); }
  #tune input[type=range]::-moz-range-track { height: 4px; border-radius: 2px; background: rgba(255,255,255,.14); }
  #tune input[type=range]::-moz-range-progress { height: 4px; border-radius: 2px; background: #ffd21f; }
  #tune input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border: 0; border-radius: 50%; background: #fff; box-shadow: 0 1px 4px rgba(0,0,0,.45); }
  #tune .empty { display: none; padding: 24px 0; text-align: center; color: rgba(255,255,255,.45); }
  #tune .foot { flex: none; padding: 9px 14px 11px; border-top: 1px solid rgba(255,255,255,.07); font-size: 11px; color: rgba(255,255,255,.45); }
  #tuneBtn { position: fixed; right: 22px; top: 54px; z-index: 19; background: rgba(20,40,50,.45); color: #fff; border: 0; border-radius: 999px;
    padding: 6px 12px; font: 800 13px ui-rounded, "Segoe UI", system-ui, sans-serif; cursor: pointer; backdrop-filter: blur(6px); }
  html.touch #tune { top: calc(10px + env(safe-area-inset-top)); bottom: calc(10px + env(safe-area-inset-bottom)); left: calc(10px + env(safe-area-inset-left)); }
  `;
  document.head.appendChild(css);

  const panel = document.createElement('div');
  panel.id = 'tune';
  panel.innerHTML = `
    <div class="head">
      <div class="title"><strong>Ride tuning</strong><kbd>P</kbd><button class="x" data-a="close" title="Close (P)">✕</button></div>
      <div class="tools"><input class="search" type="search" placeholder="Search settings…" spellcheck="false">
        <button data-a="copy" title="Copy values as JSON">Copy</button><button data-a="reset" title="Reset everything to defaults">Reset all</button></div>
    </div>
    <div class="body"><div class="empty">No settings match</div></div>
    <div class="foot">Click a yellow value to reset it · the tick marks the default</div>`;
  const body = panel.querySelector('.body');
  const rows = {}, sections = [];
  for (const [group, list] of DEFS) {
    const sec = document.createElement('details'); sec.open = true;
    sec.innerHTML = `<summary><span class="n">${group}</span><span class="badge"></span></summary>`;
    const badge = sec.querySelector('.badge'), keys = [];
    for (const [k, label, , min, max, step, unit] of list) {
      const row = document.createElement('div'); row.className = 'row'; row.dataset.label = label.toLowerCase();
      row.innerHTML = `<div class="top"><label for="t_${k}">${label}</label><span class="val"></span></div>
        <div class="trk"><input id="t_${k}" type="range" min="${min}" max="${max}" step="${step}"></div>`;
      const input = row.querySelector('input'), val = row.querySelector('.val'), trk = row.querySelector('.trk');
      const frac = (v) => Math.min(1, Math.max(0, (v - min) / (max - min)));
      trk.style.setProperty('--d', frac(DEFAULTS[k]));
      const show = () => {
        val.textContent = fmt(TUNE[k], step) + (unit ? ' ' + unit : '');
        const ch = TUNE[k] !== DEFAULTS[k];
        val.classList.toggle('changed', ch);
        val.title = ch ? `Reset to ${fmt(DEFAULTS[k], step)}${unit ? ' ' + unit : ''}` : 'Default';
        input.style.setProperty('--p', frac(TUNE[k]));
        updateBadge();
      };
      input.value = TUNE[k];
      input.addEventListener('input', () => { TUNE[k] = +input.value; show(); save(); });
      // don't let the slider keep focus, or A/D and arrows would move it while riding
      input.addEventListener('pointerup', () => input.blur());
      input.addEventListener('keydown', (e) => e.preventDefault());
      val.addEventListener('click', () => { if (TUNE[k] === DEFAULTS[k]) return; TUNE[k] = DEFAULTS[k]; input.value = TUNE[k]; show(); save(); });
      rows[k] = { input, show, row };
      keys.push(k);
      sec.appendChild(row);
    }
    const updateBadge = () => { const n = keys.filter((k) => TUNE[k] !== DEFAULTS[k]).length; badge.textContent = `${n} changed`; badge.classList.toggle('on', n > 0); };
    sections.push({ sec, keys });
    const sum = sec.querySelector('summary');   // never keep focus: Space must keep pumping the bike
    sum.addEventListener('click', () => setTimeout(() => sum.blur(), 0));
    sum.addEventListener('keydown', (e) => { e.preventDefault(); sum.blur(); });
    body.appendChild(sec);
    for (const k of keys) rows[k].show();
  }
  // search: typing must not drive the bike, so keys stop here
  const search = panel.querySelector('.search'), empty = panel.querySelector('.empty');
  for (const ev of ['keydown', 'keyup']) search.addEventListener(ev, (e) => { e.stopPropagation(); if (e.key === 'Escape') { search.value = ''; filter(); search.blur(); } });
  const filter = () => {
    const q = search.value.trim().toLowerCase(); let any = false;
    for (const { sec, keys } of sections) {
      let vis = 0;
      for (const k of keys) { const hit = !q || rows[k].row.dataset.label.includes(q) || sec.querySelector('.n').textContent.toLowerCase().includes(q); rows[k].row.classList.toggle('hide', !hit); vis += hit; }
      sec.style.display = vis ? '' : 'none'; if (q && vis) sec.open = true; any ||= vis > 0;
    }
    empty.style.display = any ? 'none' : 'block';
  };
  search.addEventListener('input', filter);
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

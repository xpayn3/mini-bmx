// Rider pose panel (K to toggle): sliders for where the rider sits on the bike and how they move.
// Saved per bike in localStorage, so the BMX and the downhill bike each keep their own setup.
// "Reset" goes back to that bike's built-in pose; "Copy" puts the values on the clipboard as JSON
// (paste them into BIKES[...].pose in main.js to make them the new default).

const DEFS = [
  ['Body position', [
    ['hipX',       'Hips forward / back',  -0.25, 0.25, 0.005, 'm'],
    ['hipY',       'Hips up / down',       -0.2,  0.2,  0.005, 'm'],
    ['lean',       'Chest lean forward',   -0.4,  0.7,  0.01,  'rad'],
    ['torso',      'Torso length',          0.36, 0.56, 0.005, 'm'],
  ]],
  ['Arms & legs', [
    // each range is centred on the downhill bike's default (main.js BIKES.dh.pose): its knob starts in the middle
    ['elbowsOut',  'Elbows out',           -1,    1,     0.05,  ''],
    ['shoulders',  'Shoulder width',        0.095, 0.235, 0.005, 'm'],
    ['kneesOut',   'Knees out',            -0.3,  0.7,   0.05,  ''],
    ['stance',     'Hip width',            -0.09, 0.04,  0.005, 'm'],
  ]],
  ['Head', [
    ['headTilt',   'Head tilt (+ looks down)', -0.5, 0.5, 0.01, 'rad'],
    ['lookAhead',  'Head forward',         -0.08, 0.12, 0.005, 'm'],
    ['headTurn',   'Look into turns',       0,    2,    0.05,  '×'],
  ]],
  ['Movement', [
    ['crouch',     'Crouch depth',          0,    2,    0.05,  '×'],
    ['standPedal', 'Stand up to pedal',     0,    2,    0.05,  '×'],
    ['sway',       'Body sway',             0,    2,    0.05,  '×'],
    ['bikeRock',   'Bike rock (sprint)',    0,    2,    0.05,  '×'],
    ['upright',    'Torso stays upright',   0,    1,    0.05,  ''],
    ['hipSway',    'Hip sway',              0,    0.12, 0.005, 'm'],
  ]],
];
// neutral values (the rider's original pose) for anything a bike's pose doesn't set
export const NEUTRAL = { hipX: 0, hipY: 0, lean: 0, elbowsOut: 0, kneesOut: 0, stance: 0, seatFloor: false,
  crouch: 1, standPedal: 1, sway: 1, bikeRock: 1, upright: 1, hipSway: 0.015, torso: 0.46, shoulders: 0.2, headTilt: 0, headTurn: 1, lookAhead: 0 };

const fmt = (v, step) => v.toFixed(step >= 1 ? 0 : Math.min(4, Math.ceil(-Math.log10(step))));

export function buildPosePanel({ bikeId, bikeLabel, defaults, apply, sideView }) {
  const KEY = 'bmx-pose-v1-' + bikeId;
  const DEF = { ...NEUTRAL, ...defaults };
  const pose = { ...DEF };
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
    for (const k in saved) if (k in NEUTRAL && (typeof saved[k] === typeof NEUTRAL[k]) && (typeof saved[k] !== 'number' || Number.isFinite(saved[k]))) pose[k] = saved[k];
  } catch { /* storage blocked: defaults */ }
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(pose)); } catch { /* ignore */ } };
  apply({ ...pose });

  const css = document.createElement('style');
  css.textContent = `
  #pose { position: fixed; top: 80px; right: 12px; bottom: 56px; width: 290px; max-width: calc(100vw - 24px); overflow-y: auto;
    background: rgba(16,26,34,.82); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); color: #eef4f6; border-radius: 14px;
    padding: 10px 14px 14px; font: 12px/1.3 ui-rounded, "Segoe UI", system-ui, sans-serif; z-index: 20;
    box-shadow: 0 8px 30px rgba(0,0,0,.35); display: none; }
  #pose.open { display: block; }
  #pose h3 { margin: 12px 0 6px; font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: #ffd21f; }
  #pose .head { display: flex; align-items: center; gap: 6px; position: sticky; top: -10px; background: inherit; padding: 4px 0 6px; z-index: 1; }
  #pose .head strong { flex: 1; font-size: 15px; }
  #pose .head small { display: block; font-weight: 600; opacity: .65; font-size: 11px; }
  #pose button { background: rgba(255,255,255,.14); color: #fff; border: 0; border-radius: 7px; padding: 5px 9px; font: inherit; font-weight: 700; cursor: pointer; }
  #pose button:hover { background: rgba(255,255,255,.26); }
  #pose .row { display: grid; grid-template-columns: 1fr auto; gap: 1px 8px; margin: 5px 0; }
  #pose .row label { opacity: .9; }
  #pose .row .val { font-variant-numeric: tabular-nums; font-weight: 700; cursor: pointer; }
  #pose .row .val.changed { color: #ffd21f; }
  #pose .row input[type=range] { grid-column: 1 / -1; width: 100%; margin: 0; accent-color: #ffd21f; }
  #pose .check { display: flex; align-items: center; gap: 8px; margin: 8px 0 2px; cursor: pointer; }
  #pose .check input { accent-color: #ffd21f; width: 16px; height: 16px; margin: 0; }
  #poseBtn { position: fixed; right: 22px; top: 88px; z-index: 19; background: rgba(20,40,50,.45); color: #fff; border: 0; border-radius: 999px;
    padding: 6px 12px; font: 800 13px ui-rounded, "Segoe UI", system-ui, sans-serif; cursor: pointer; backdrop-filter: blur(6px); }
  html.touch #poseBtn { top: calc(78px + env(safe-area-inset-top)); right: calc(12px + env(safe-area-inset-right)); }
  `;
  document.head.appendChild(css);

  const panel = document.createElement('div');
  panel.id = 'pose';
  panel.innerHTML = `<div class="head"><strong>Rider position<small>${bikeLabel}</small></strong>
    <button data-a="side" title="Switch to the side camera to see the pose">Side view</button>
    <button data-a="copy" title="Copy values as JSON">Copy</button><button data-a="reset" title="Back to this bike's default pose">Reset</button>
    <button data-a="close">✕</button></div>`;
  const rows = {};
  for (const [group, list] of DEFS) {
    const h = document.createElement('h3'); h.textContent = group; panel.appendChild(h);
    for (const [k, label, min, max, step, unit] of list) {
      const row = document.createElement('div'); row.className = 'row';
      row.innerHTML = `<label for="p_${k}">${label}</label><span class="val" title="Click to reset"></span><input id="p_${k}" type="range" min="${min}" max="${max}" step="${step}">`;
      const input = row.querySelector('input'), val = row.querySelector('.val');
      const show = () => { val.textContent = fmt(pose[k], step) + (unit ? ' ' + unit : ''); val.classList.toggle('changed', Math.abs(pose[k] - DEF[k]) > 1e-9); };
      input.value = pose[k]; show();
      input.addEventListener('input', () => { pose[k] = +input.value; show(); apply({ ...pose }); save(); });
      // never keep focus: A/D and the arrows must keep steering the bike
      input.addEventListener('pointerup', () => input.blur());
      input.addEventListener('keydown', (e) => e.preventDefault());
      val.addEventListener('click', () => { pose[k] = DEF[k]; input.value = pose[k]; show(); apply({ ...pose }); save(); });
      rows[k] = { input, show };
      panel.appendChild(row);
    }
    if (group === 'Body position') {   // the downhill "stay on top of the saddle" rule, as a switch
      const lab = document.createElement('label'); lab.className = 'check';
      lab.innerHTML = `<input type="checkbox"> Keep hips above the saddle`;
      const cb = lab.querySelector('input'); cb.checked = !!pose.seatFloor;
      cb.addEventListener('change', () => { pose.seatFloor = cb.checked; apply({ ...pose }); save(); cb.blur(); });
      rows.seatFloor = { input: cb, show: () => { cb.checked = !!pose.seatFloor; } };
      panel.appendChild(lab);
    }
  }
  document.body.appendChild(panel);

  const btn = document.createElement('button');
  btn.id = 'poseBtn'; btn.textContent = '🧍 Rider (K)';
  document.body.appendChild(btn);

  const toggle = () => { panel.classList.toggle('open'); btn.style.display = panel.classList.contains('open') ? 'none' : ''; btn.blur(); };
  btn.addEventListener('click', toggle);
  addEventListener('keydown', (e) => { if (e.code === 'KeyK' && !e.repeat) toggle(); });
  panel.addEventListener('pointerdown', (e) => e.stopPropagation());
  panel.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });
  panel.addEventListener('click', async (e) => {
    const a = e.target.dataset && e.target.dataset.a;
    if (!a) return;
    e.target.blur();
    if (a === 'close') toggle();
    if (a === 'side') sideView();
    if (a === 'reset') {
      Object.assign(pose, DEF);
      for (const k in rows) { if (k !== 'seatFloor') rows[k].input.value = pose[k]; rows[k].show(); }
      apply({ ...pose }); save();
    }
    if (a === 'copy') {
      const txt = JSON.stringify(pose);
      try { await navigator.clipboard.writeText(txt); e.target.textContent = 'Copied!'; }
      catch { console.log(txt); e.target.textContent = 'In console'; }
      setTimeout(() => { e.target.textContent = 'Copy'; }, 1200);
    }
  });
}

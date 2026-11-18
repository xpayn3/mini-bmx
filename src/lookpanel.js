// Rider look panel (L to toggle, or Menu > Look): colours for the helmet, goggles, kit and shoes.
// Ready-made kits up top, then one row per part: preset swatches plus a custom colour picker.
// Saved in localStorage (same look on every bike).

export const DEFAULT_LOOK = {
  shell: '#16171a', peak: '#ececec',
  goggleFrame: '#f2f2ee', lens: '#ff7a2a', strap: '#ff6a4d',
  jersey: '#ff6a4d', pants: '#1d2b64', gloves: '#ffd21f',
  shoes: '#26292f', shoeAccent: '#d8232a',
};

const KITS = [
  ['Classic', DEFAULT_LOOK],
  ['Stealth', { shell: '#0c0d0f', peak: '#1a1b1e', goggleFrame: '#18191c', lens: '#8a96a8', strap: '#2a2c30',
    jersey: '#2b2e33', pants: '#111215', gloves: '#3a3d42', shoes: '#141518', shoeAccent: '#3a3d42' }],
  ['Race white', { shell: '#f4f4f0', peak: '#e8231f', goggleFrame: '#e8231f', lens: '#3fb6ff', strap: '#e8231f',
    jersey: '#f4f4f0', pants: '#202227', gloves: '#e8231f', shoes: '#f4f4f0', shoeAccent: '#e8231f' }],
  ['Monster', { shell: '#7ed321', peak: '#111214', goggleFrame: '#111214', lens: '#7ed321', strap: '#7ed321',
    jersey: '#111214', pants: '#2c2f33', gloves: '#7ed321', shoes: '#111214', shoeAccent: '#7ed321' }],
  ['Ocean', { shell: '#1478d4', peak: '#f4f4f0', goggleFrame: '#f4f4f0', lens: '#ff9f2e', strap: '#1478d4',
    jersey: '#11b3c9', pants: '#0d2847', gloves: '#f4f4f0', shoes: '#0d2847', shoeAccent: '#11b3c9' }],
  ['Sunset', { shell: '#ff7a1a', peak: '#6a1b9a', goggleFrame: '#6a1b9a', lens: '#ffd21f', strap: '#ff7a1a',
    jersey: '#6a1b9a', pants: '#2a2140', gloves: '#ff7a1a', shoes: '#2a2140', shoeAccent: '#ff7a1a' }],
];

const SW = ['#f4f4f0', '#16171a', '#e8231f', '#ff7a1a', '#ffd21f', '#7ed321', '#11b3c9', '#1478d4', '#6a1b9a', '#ff5fa2'];
const LENS = ['#ff7a2a', '#ffd21f', '#3fb6ff', '#7ed321', '#ff5fa2', '#8a96a8', '#d0d4da'];

const ROWS = [
  ['Helmet', [['shell', 'Shell', SW], ['peak', 'Peak', SW]]],
  ['Goggles', [['lens', 'Lens tint', LENS], ['goggleFrame', 'Frame', SW], ['strap', 'Strap', SW]]],
  ['Kit', [['jersey', 'Jersey', SW], ['pants', 'Pants', SW], ['gloves', 'Gloves', SW]]],
  ['Shoes', [['shoes', 'Upper', SW], ['shoeAccent', 'Toe & collar', SW]]],
];

const KEY = 'bmx-look-v1';
const isHex = (v) => typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v);

export function buildLookPanel({ apply, view }) {
  const look = { ...DEFAULT_LOOK };
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || '{}');
    for (const k in saved) if (k in DEFAULT_LOOK && isHex(saved[k])) look[k] = saved[k];
  } catch { /* storage blocked: defaults */ }
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(look)); } catch { /* ignore */ } };
  apply({ ...look });

  const css = document.createElement('style');
  css.textContent = `
  #look { position: fixed; top: 80px; right: 12px; bottom: 56px; width: 300px; max-width: calc(100vw - 24px); overflow-y: auto;
    background: rgba(16,26,34,.84); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); color: #eef4f6; border-radius: 16px;
    padding: 10px 14px 14px; font: 12px/1.3 ui-rounded, "Segoe UI", system-ui, sans-serif; z-index: 21;
    box-shadow: 0 8px 30px rgba(0,0,0,.35); display: none; scrollbar-width: thin; }
  #look.open { display: block; }
  #look .head { display: flex; align-items: center; gap: 6px; position: sticky; top: -10px; background: inherit; padding: 4px 0 6px; z-index: 1; }
  #look .head strong { flex: 1; font-size: 15px; }
  #look button.b { background: rgba(255,255,255,.14); color: #fff; border: 0; border-radius: 7px; padding: 5px 9px; font: inherit; font-weight: 700; cursor: pointer; }
  #look button.b:hover { background: rgba(255,255,255,.26); }
  #look h3 { margin: 14px 0 6px; font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; color: #ffd21f; }
  #look .kits { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
  #look .kit { display: flex; flex-direction: column; align-items: center; gap: 5px; padding: 8px 4px 7px; border: 0; border-radius: 11px; cursor: pointer;
    color: #fff; background: rgba(255,255,255,.08); font: 700 11.5px ui-rounded, "Segoe UI", system-ui, sans-serif; }
  #look .kit:hover { background: rgba(255,255,255,.16); }
  #look .kit .dots { display: flex; }
  #look .kit .dots i { width: 13px; height: 13px; border-radius: 50%; margin-left: -3px; box-shadow: 0 0 0 1.5px rgba(16,26,34,.9); }
  #look .row { margin: 7px 0 9px; }
  #look .row .lab { display: flex; justify-content: space-between; margin-bottom: 5px; opacity: .92; }
  #look .row .lab code { font: 700 10.5px ui-monospace, Consolas, monospace; opacity: .55; text-transform: uppercase; }
  #look .sws { display: flex; flex-wrap: wrap; gap: 5px; align-items: center; }
  #look .sw { width: 21px; height: 21px; border-radius: 50%; border: 0; padding: 0; cursor: pointer;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,.25); transition: transform .1s; }
  #look .sw:hover { transform: scale(1.12); }
  #look .sw.on { box-shadow: 0 0 0 2px rgba(16,26,34,1), 0 0 0 4px #ffd21f; }
  #look .pick { position: relative; width: 21px; height: 21px; border-radius: 50%; overflow: hidden; cursor: pointer;
    background: conic-gradient(#f33, #ff3, #3f3, #3ff, #33f, #f3f, #f33); box-shadow: inset 0 0 0 1px rgba(255,255,255,.25); }
  #look .pick.on { box-shadow: 0 0 0 2px rgba(16,26,34,1), 0 0 0 4px #ffd21f; }
  #look .pick input { position: absolute; inset: -6px; width: 34px; height: 34px; opacity: 0; cursor: pointer; border: 0; padding: 0; }
  html.touch #look { top: calc(70px + env(safe-area-inset-top)); bottom: 130px; }
  `;
  document.head.appendChild(css);

  const panel = document.createElement('div');
  panel.id = 'look';
  panel.innerHTML = `<div class="head"><strong>Rider look</strong>
    <button class="b" data-a="view" title="Camera on the rider">View</button>
    <button class="b" data-a="reset" title="Back to the default colours">Reset</button>
    <button class="b" data-a="close">✕</button></div>
    <h3>Kits</h3><div class="kits">${KITS.map(([n, k], i) => `<button class="kit" data-kit="${i}"><span class="dots">${
      [k.shell, k.jersey, k.pants, k.lens].map((c) => `<i style="background:${c}"></i>`).join('')}</span>${n}</button>`).join('')}</div>`;
  const rows = [];
  for (const [group, list] of ROWS) {
    const h = document.createElement('h3'); h.textContent = group; panel.appendChild(h);
    for (const [k, label, sw] of list) {
      const row = document.createElement('div'); row.className = 'row';
      row.innerHTML = `<div class="lab"><span>${label}</span><code></code></div><div class="sws">${
        sw.map((c) => `<button class="sw" data-k="${k}" data-c="${c}" style="background:${c}" title="${c}"></button>`).join('')
      }<label class="pick" title="Custom colour"><input type="color" data-k="${k}"></label></div>`;
      panel.appendChild(row);
      const input = row.querySelector('input'), code = row.querySelector('code'), pick = row.querySelector('.pick');
      const show = () => {
        code.textContent = look[k]; input.value = look[k];
        let preset = false;
        row.querySelectorAll('.sw').forEach((b) => { const on = b.dataset.c.toLowerCase() === look[k].toLowerCase(); b.classList.toggle('on', on); preset ||= on; });
        pick.classList.toggle('on', !preset);
      };
      input.addEventListener('input', () => set({ [k]: input.value }));
      input.addEventListener('change', () => input.blur());
      rows.push(show); show();
    }
  }
  document.body.appendChild(panel);

  function set(part) {
    Object.assign(look, part);
    apply({ ...look }); save();
    rows.forEach((f) => f());
  }

  const toggle = (o = !panel.classList.contains('open')) => { panel.classList.toggle('open', o); };
  addEventListener('keydown', (e) => {
    if (e.code === 'KeyL' && !e.repeat && !(e.target instanceof HTMLInputElement)) toggle();
    if (e.code === 'Escape') toggle(false);
  });
  panel.addEventListener('pointerdown', (e) => e.stopPropagation());
  panel.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });
  panel.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    b.blur();   // Space / WASD keep driving the bike
    if (b.dataset.c) set({ [b.dataset.k]: b.dataset.c });
    if (b.dataset.kit) set({ ...KITS[+b.dataset.kit][1] });
    if (b.dataset.a === 'reset') set({ ...DEFAULT_LOOK });
    if (b.dataset.a === 'close') toggle(false);
    if (b.dataset.a === 'view') view?.();
  });
}

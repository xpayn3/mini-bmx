// One dropdown control panel (top-right) that gathers the scattered HUD controls:
// FPS, bike picker, camera, display toggles, world / tune / rider actions and the key list.
// Existing elements (#fps, #bikes, #cam, #keys) are MOVED in, so the code that drives them keeps working.
// Action buttons fire the same key events as the keyboard shortcuts, so phones get them too.

const css = `
#ctlBtn { position: fixed; top: 14px; right: 16px; z-index: 30; width: 42px; height: 42px; border: 0; border-radius: 14px; cursor: pointer;
  display: grid; place-items: center; color: #fff; background: rgba(18,30,38,.55); backdrop-filter: blur(10px);
  box-shadow: 0 4px 14px rgba(0,0,0,.22), inset 0 0 0 1px rgba(255,255,255,.12); transition: background .15s, transform .15s; }
#ctlBtn:hover { background: rgba(18,30,38,.72); }
#ctlBtn:active { transform: scale(.95); }
#ctlBtn svg { width: 20px; height: 20px; transition: transform .25s; }
#ctlBtn.open svg { transform: rotate(90deg); }
#ctl { position: fixed; top: 64px; right: 16px; z-index: 30; width: 286px; max-height: calc(100vh - 84px); overflow-y: auto;
  padding: 6px 14px 14px; border-radius: 18px; color: #eef4f6; text-shadow: none;
  font: 600 13px/1.25 ui-rounded, "Segoe UI", system-ui, sans-serif;
  background: rgba(14,24,31,.84); backdrop-filter: blur(14px) saturate(1.2);
  box-shadow: 0 18px 40px rgba(0,0,0,.35), inset 0 0 0 1px rgba(255,255,255,.08);
  opacity: 0; transform: translateY(-8px) scale(.98); transform-origin: top right; pointer-events: none;
  transition: opacity .18s ease, transform .18s ease; scrollbar-width: thin; }
#ctl.open { opacity: 1; transform: none; pointer-events: auto; }
#ctl .hd { display: flex; align-items: center; justify-content: space-between; padding: 8px 0 4px; }
#ctl .hd strong { font-size: 15px; font-weight: 800; letter-spacing: .2px; }
#ctl h4 { margin: 14px 0 7px; font-size: 10.5px; font-weight: 800; letter-spacing: 1.3px; text-transform: uppercase; color: rgba(255,255,255,.5); }
#ctl kbd { font: 800 10px/1 ui-monospace, Consolas, monospace; padding: 3px 5px; border-radius: 5px; color: rgba(255,255,255,.7);
  background: rgba(255,255,255,.1); box-shadow: inset 0 -1px 0 rgba(0,0,0,.35); }
/* moved-in elements: drop their old floating positions */
#ctl .hd { flex-wrap: wrap; row-gap: 6px; }
#ctl .fpsSlot { width: 100%; }
#ctl #fps { position: static !important; display: block; margin: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-size: 10.5px; }
#ctl #bikes { position: static !important; display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; gap: 4px; padding: 4px;
  border-radius: 12px; background: rgba(255,255,255,.07); backdrop-filter: none; }
#ctl #bikes button { padding: 9px 8px; border-radius: 9px; font-size: 13px; }
#ctl .sel { position: relative; }
#ctl .sel::after { content: ''; position: absolute; right: 13px; top: 50%; width: 7px; height: 7px; margin-top: -6px; pointer-events: none;
  border-right: 2px solid rgba(255,255,255,.7); border-bottom: 2px solid rgba(255,255,255,.7); transform: rotate(45deg); }
#ctl #cam { width: 100%; appearance: none; -webkit-appearance: none; padding: 10px 34px 10px 12px; border: 0; border-radius: 11px; cursor: pointer;
  font: 700 13px ui-rounded, "Segoe UI", system-ui, sans-serif; color: #fff; background: rgba(255,255,255,.09); }
#ctl #cam:hover { background: rgba(255,255,255,.14); }
#ctl #cam option, #ctl #cam optgroup { color: #111; background: #fff; }
#ctl .tog { display: flex; align-items: center; gap: 10px; width: 100%; padding: 8px 2px; border: 0; background: none; color: inherit;
  font: inherit; cursor: pointer; text-align: left; }
#ctl .tog span { flex: 1; }
#ctl .sw { position: relative; width: 34px; height: 20px; border-radius: 10px; background: rgba(255,255,255,.18); transition: background .15s; }
#ctl .sw::after { content: ''; position: absolute; left: 2px; top: 2px; width: 16px; height: 16px; border-radius: 50%; background: #fff;
  box-shadow: 0 1px 3px rgba(0,0,0,.35); transition: transform .15s; }
#ctl .tog.on .sw { background: #ffd21f; }
#ctl .tog.on .sw::after { transform: translateX(14px); }
#ctl .qv { padding: 4px 9px; border-radius: 8px; background: rgba(255,255,255,.1); font-weight: 800; font-size: 12px; }
#ctl .acts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
#ctl .act { display: flex; flex-direction: column; align-items: center; gap: 5px; padding: 10px 4px 8px; border: 0; border-radius: 12px; cursor: pointer;
  color: #fff; background: rgba(255,255,255,.08); font: 700 12px ui-rounded, "Segoe UI", system-ui, sans-serif; transition: background .15s; }
#ctl .act:hover { background: rgba(255,255,255,.16); }
#ctl .act .ic { font-size: 18px; line-height: 1; }
#ctl details { margin-top: 12px; border-top: 1px solid rgba(255,255,255,.08); padding-top: 4px; }
#ctl summary { list-style: none; cursor: pointer; display: flex; justify-content: space-between; align-items: center;
  font-size: 10.5px; font-weight: 800; letter-spacing: 1.3px; text-transform: uppercase; color: rgba(255,255,255,.5); padding: 8px 0; }
#ctl summary::-webkit-details-marker { display: none; }
#ctl summary::after { content: '+'; font-size: 15px; letter-spacing: 0; }
#ctl details[open] summary::after { content: '–'; }
#ctl #keys { position: static !important; display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; min-width: 0; padding: 4px 0 2px;
  background: none; box-shadow: none; backdrop-filter: none; font-size: 12.5px; white-space: normal; }
#ctl #keys b { font: 800 10px/1 ui-monospace, Consolas, monospace; padding: 3px 5px; border-radius: 5px; background: rgba(255,255,255,.12); }
/* the old floating copies are replaced by the panel */
#camwrap, #tuneBtn, #poseBtn { display: none !important; }
html.touch #ctlBtn { top: calc(10px + env(safe-area-inset-top)); right: calc(12px + env(safe-area-inset-right)); }
html.touch #ctl { top: calc(60px + env(safe-area-inset-top)); right: calc(12px + env(safe-area-inset-right)); max-height: calc(100vh - 140px); }
html.touch #ctl .keysec { display: none; }
`;

const ICON = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round">
  <path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2.2"/><circle cx="10" cy="17" r="2.2"/></svg>`;

const press = (code) => {   // reuse the game's own keyboard handlers
  dispatchEvent(new KeyboardEvent('keydown', { code, bubbles: true }));
  dispatchEvent(new KeyboardEvent('keyup', { code, bubbles: true }));
};

function build() {
  const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);
  const touch = document.documentElement.classList.contains('touch') || matchMedia('(pointer: coarse)').matches;

  const btn = document.createElement('button');
  btn.id = 'ctlBtn'; btn.title = 'Menu (M)'; btn.setAttribute('aria-label', 'Menu'); btn.innerHTML = ICON;
  const panel = document.createElement('div');
  panel.id = 'ctl';
  panel.innerHTML = `
    <div class="hd"><strong>Settings</strong><span class="fpsSlot"></span></div>
    <h4>Bike</h4><div class="bikeSlot"></div>
    <h4>Camera</h4><div class="sel camSlot"></div>
    <h4>Display</h4>
    <button class="tog" data-k="KeyT"><span>Tilt-shift</span><kbd>T</kbd><i class="sw"></i></button>
    <button class="tog" data-k="KeyO"><span>Ambient occlusion</span><kbd>O</kbd><i class="sw"></i></button>
    <button class="tog q" data-k="KeyG"><span>Quality</span><kbd>G</kbd><b class="qv">Auto</b></button>
    <h4>Ride</h4>
    <div class="acts">
      <button class="act" data-k="KeyR"><span class="ic">🌍</span>New world</button>
      <button class="act" data-k="KeyP"><span class="ic">⚙️</span>Tune</button>
      <button class="act" data-k="KeyK"><span class="ic">🧍</span>Rider</button>
    </div>
    <details class="keysec"><summary>Keyboard controls</summary><div class="keysSlot"></div></details>`;
  document.body.append(btn, panel);

  // move the existing controls in
  const move = (id, slot) => { const el = document.getElementById(id); if (el) panel.querySelector(slot).appendChild(el); };
  move('fps', '.fpsSlot'); move('bikes', '.bikeSlot'); move('cam', '.camSlot'); move('keys', '.keysSlot');
  document.getElementById('camwrap')?.remove();

  // display toggle state mirrors the game's defaults and follows the real key presses
  const tog = { KeyT: true, KeyO: !touch };
  const showTog = () => panel.querySelectorAll('.tog[data-k="KeyT"], .tog[data-k="KeyO"]').forEach((b) => b.classList.toggle('on', tog[b.dataset.k]));
  showTog();
  addEventListener('keydown', (e) => {
    if (e.repeat) return;
    if (e.code in tog) { tog[e.code] = !tog[e.code]; showTog(); }
    if (e.code === 'KeyM') setOpen(!panel.classList.contains('open'));
    if (e.code === 'Escape') setOpen(false);
  });
  // quality level is shown in the FPS readout ("Q2 auto"); mirror it
  const qv = panel.querySelector('.qv'), fps = document.getElementById('fps');
  const showQ = () => { const m = /Q(\d)\s*(auto)?/.exec(fps?.textContent || ''); if (m) qv.textContent = `${['Ultra', 'High', 'Medium', 'Low'][+m[1]] || 'Q' + m[1]}${m[2] ? ' · auto' : ''}`; };
  if (fps) new MutationObserver(showQ).observe(fps, { childList: true, characterData: true, subtree: true });

  const setOpen = (o) => { panel.classList.toggle('open', o); btn.classList.toggle('open', o); };
  btn.addEventListener('click', () => { setOpen(!panel.classList.contains('open')); btn.blur(); });
  panel.addEventListener('click', (e) => {
    const b = e.target.closest('[data-k]');
    if (b) { press(b.dataset.k); if (['KeyP', 'KeyK', 'KeyR'].includes(b.dataset.k)) setOpen(false); }
    // never keep focus: Space / WASD must keep driving the bike
    setTimeout(() => { if (document.activeElement !== document.getElementById('cam')) document.activeElement?.blur?.(); }, 0);
  });
  panel.querySelector('summary').addEventListener('keydown', (e) => { e.preventDefault(); e.target.blur(); });
  document.getElementById('cam')?.addEventListener('change', (e) => e.target.blur());
  panel.addEventListener('pointerdown', (e) => e.stopPropagation());
  panel.addEventListener('wheel', (e) => e.stopPropagation(), { passive: true });
  addEventListener('pointerdown', (e) => { if (!panel.contains(e.target) && !btn.contains(e.target)) setOpen(false); });
}

if (document.readyState === 'loading') addEventListener('DOMContentLoaded', build); else build();

// On-screen touch controls for phones/tablets. Each button fakes the matching keyboard key,
// so all game logic stays in the existing keydown/keyup handlers.
// a touch-screen laptop / pen tablet with a mouse or trackpad reports touch points too, but its
// primary pointer is fine: only treat it as touch if the touch screen is all there is
export const IS_TOUCH = matchMedia('(pointer: coarse)').matches
  || (navigator.maxTouchPoints > 0 && !matchMedia('(any-pointer: fine)').matches);

const send = (type, code, repeat = false) => dispatchEvent(new KeyboardEvent(type, { code, repeat, bubbles: true, cancelable: true }));

export function buildTouchControls() {
  if (!IS_TOUCH) return;
  document.documentElement.classList.add('touch');

  const css = document.createElement('style');
  css.textContent = `
  #touch { position: fixed; inset: 0; pointer-events: none; z-index: 15; user-select: none; -webkit-user-select: none; -webkit-touch-callout: none; }
  #touch .pad { position: absolute; bottom: calc(14px + env(safe-area-inset-bottom)); display: flex; gap: 12px; align-items: flex-end; pointer-events: none; }
  #touch .l { left: calc(14px + env(safe-area-inset-left)); }
  #touch .r { right: calc(14px + env(safe-area-inset-right)); }
  #touch .col { display: flex; flex-direction: column; gap: 12px; }
  #touch .tb { pointer-events: auto; touch-action: none; width: 74px; height: 74px; border-radius: 50%;
    display: grid; place-items: center; color: #fff; font: 900 15px/1 ui-rounded, system-ui, sans-serif; letter-spacing: .5px;
    background: rgba(20,40,50,.38); border: 2px solid rgba(255,255,255,.55); backdrop-filter: blur(6px); -webkit-backdrop-filter: blur(6px);
    text-shadow: 0 1px 3px rgba(0,0,0,.4); transition: transform .06s, background .06s; }
  #touch .tb.big { width: 96px; height: 96px; font-size: 17px; }
  #touch .tb.on { background: #ffd21f; color: #1d2b64; border-color: #ffd21f; text-shadow: none; transform: scale(.93); }
  #touch .tb svg { width: 32px; height: 32px; fill: currentColor; }
  #touch .top { position: absolute; top: calc(118px + env(safe-area-inset-top)); right: calc(12px + env(safe-area-inset-right));
    display: flex; flex-direction: column; gap: 8px; pointer-events: none; }
  #touch .sm { pointer-events: auto; touch-action: manipulation; font: 800 12px/1 ui-rounded, system-ui, sans-serif; color: #fff;
    background: rgba(20,40,50,.4); border: 0; border-radius: 999px; padding: 9px 12px; backdrop-filter: blur(6px); -webkit-backdrop-filter: blur(6px); }
  #touch .sm:active { background: #ffd21f; color: #1d2b64; }
  @media (orientation: portrait) and (max-width: 500px) {
    #touch .pad { gap: 10px; } #touch .col { gap: 10px; }
    #touch .tb { width: 64px; height: 64px; font-size: 13px; } #touch .tb.big { width: 82px; height: 82px; font-size: 16px; }
  }
  @media (orientation: landscape) and (max-height: 500px) {
    #touch .tb { width: 64px; height: 64px; } #touch .tb.big { width: 84px; height: 84px; }
    #touch .top { top: calc(12px + env(safe-area-inset-top)); flex-direction: row; right: auto; left: 50%; transform: translateX(-50%); margin-top: 44px; }
  }
  `;
  document.head.appendChild(css);

  const arrow = (rot) => `<svg viewBox="0 0 24 24" style="transform:rotate(${rot}deg)"><path d="M15.5 4 7 12l8.5 8 1.9-2L11 12l6.4-6z"/></svg>`;
  const root = document.createElement('div');
  root.id = 'touch';
  root.innerHTML = `
    <div class="pad l"><div class="tb" data-k="KeyA">${arrow(0)}</div><div class="tb" data-k="KeyD">${arrow(180)}</div></div>
    <div class="pad r">
      <div class="tb big" data-k="Space">POP</div>
      <div class="col"><div class="tb" data-k="KeyW">GO</div><div class="tb" data-k="KeyS">BRAKE</div></div>
    </div>
    <div class="top">
      <button class="sm" data-tap="KeyF">Bail</button>
      <button class="sm" data-tap="KeyR">New world</button>
      <button class="sm" data-tap="KeyC">Camera</button>
    </div>`;
  document.body.appendChild(root);

  // hold buttons: multi-touch safe, each pointer owns the button it went down on
  for (const el of root.querySelectorAll('[data-k]')) {
    const code = el.dataset.k;
    const held = new Set();   // pointer ids currently pressing this button
    const down = (e) => { e.preventDefault(); try { el.setPointerCapture(e.pointerId); } catch {} held.add(e.pointerId); if (held.size === 1) { el.classList.add('on'); send('keydown', code); navigator.vibrate?.(8); } };
    const up = (e) => { if (!held.delete(e.pointerId)) return; e.preventDefault(); if (held.size === 0) { el.classList.remove('on'); send('keyup', code); } };
    el.addEventListener('pointerdown', down);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('lostpointercapture', up);   // only releases the pointer that lost capture
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  }
  for (const el of root.querySelectorAll('[data-tap]')) {
    el.addEventListener('click', () => { send('keydown', el.dataset.tap); send('keyup', el.dataset.tap); el.blur(); });
  }

  // getup prompt: point at the POP button instead of the space bar
  const gk = document.querySelector('#getup .key span');
  if (gk) gk.textContent = 'POP';

  // stop iOS page bounce / pinch-zoom of the whole page
  document.addEventListener('gesturestart', (e) => e.preventDefault());
  document.addEventListener('touchmove', (e) => { if (e.touches.length > 1 || e.target.closest?.('#touch')) e.preventDefault(); }, { passive: false });
}

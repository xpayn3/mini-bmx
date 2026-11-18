// HUD overlay styled like a GPS bike computer: rubber bezel, reflective LCD, seven-segment digits.
// Fields: clock / signal / battery, SPEED, SLOPE (deg), GRADE (%), and an elevation profile with ELEV.
// Self-contained: builds its own DOM and styles. Call gauge.update(kmh, slopeDeg, inAir, dt, elev) each frame.

const FONT = 'https://cdn.jsdelivr.net/npm/dseg@0.46.0/fonts';
const HIST = 120, HIST_DT = 0.25;            // elevation profile: last 30 s
const GW = 110, GH = 40;                     // profile graph size (svg units)

const css = `
@font-face { font-family: 'DSEG7'; src: url('${FONT}/DSEG7-Classic/DSEG7Classic-Bold.woff2') format('woff2'); font-display: block; }
@font-face { font-family: 'DSEG7Mini'; src: url('${FONT}/DSEG7-Classic-MINI/DSEG7ClassicMini-Bold.woff2') format('woff2'); font-display: block; }
/* compact portrait bike computer: black body, bright transflective colour screen, two face buttons */
#gauge { --ink: #111417; --ghost: rgba(17,20,23,.06); --rule: rgba(17,20,23,.22); --grade: #2fb34a;
  position: absolute; left: 20px; bottom: 20px; width: 126px; padding: 9px 7px 19px; border-radius: 16px 16px 20px 20px;
  background: linear-gradient(175deg, #2e3135 0%, #18191b 40%, #0e0f10 100%);
  box-shadow: 0 12px 24px rgba(0,0,0,.4), 0 2px 5px rgba(0,0,0,.3), inset 0 1px 0 rgba(255,255,255,.14), inset 0 -2px 0 rgba(0,0,0,.6);
  pointer-events: none; text-shadow: none; user-select: none; }
#gauge::before, #gauge::after { content: ''; position: absolute; width: 3px; height: 20px; top: 34px; border-radius: 2px; background: #3a3d41; }
#gauge::before { left: -2px; }
#gauge::after { right: -2px; }
#gauge .scr { position: relative; overflow: hidden; border-radius: 5px; padding: 3px 6px 4px; color: var(--ink);
  background: linear-gradient(170deg, #f7f8f5 0%, #eceee8 60%, #e1e4dc 100%);
  box-shadow: inset 0 1px 4px rgba(0,0,0,.55), 0 0 0 1px #050506; }
#gauge .scr::after { content: ''; position: absolute; inset: 0; pointer-events: none;
  background: linear-gradient(118deg, rgba(255,255,255,.35) 0%, rgba(255,255,255,.05) 30%, transparent 31%); }
#gauge .lbl { font: 800 7px/1 "Segoe UI", system-ui, sans-serif; letter-spacing: .8px; text-transform: uppercase; opacity: .62; }
#gauge .unit { font: 800 8px/1 "Segoe UI", system-ui, sans-serif; opacity: .7; }
#gauge .seg { position: relative; display: inline-block; font-family: 'DSEG7', monospace; white-space: pre; }
#gauge .seg .gh { color: var(--ghost); }
#gauge .seg .v { position: absolute; right: 0; top: 0; }
#gauge .row { display: flex; align-items: center; justify-content: space-between; }
#gauge .status { margin: 0 -6px 2px; padding: 2px 6px 2px; background: var(--ink); color: #f2f3ef; }
#gauge .clock { font: 8px/1 'DSEG7Mini', monospace; }
#gauge .clock .gh { color: rgba(255,255,255,.08); }
#gauge .icons { display: flex; align-items: flex-end; gap: 4px; }
#gauge .bars { display: flex; align-items: flex-end; gap: 1px; height: 7px; }
#gauge .bars i { width: 2px; background: #f2f3ef; }
#gauge .batt { position: relative; width: 13px; height: 6px; border: 1px solid #f2f3ef; border-radius: 1.5px; box-sizing: border-box; }
#gauge .batt::after { content: ''; position: absolute; right: -3px; top: 1px; width: 1.5px; height: 2px; background: #f2f3ef; }
#gauge .batt i { position: absolute; left: 1px; top: 1px; bottom: 1px; width: 70%; background: #3ccf5a; }
#gauge .speed { padding: 3px 0 5px; border-bottom: 1px solid var(--rule); flex-direction: column; align-items: stretch; }
#gauge .speed .top { display: flex; justify-content: space-between; margin-bottom: 2px; }
#gauge .speed .seg { font-size: 29px; line-height: 1; align-self: flex-end; }
#gauge .pair { display: grid; grid-template-columns: 1fr 1fr; border-bottom: 1px solid var(--rule); }
#gauge .pair > div { padding: 4px 0 5px; }
#gauge .pair > div + div { border-left: 1px solid var(--rule); padding-left: 5px; }
#gauge .pair .seg { font-size: 14px; line-height: 1; }
#gauge .fv { display: flex; align-items: flex-end; justify-content: flex-end; gap: 2px; margin-top: 3px; padding-right: 3px; }
#gauge .arrow { width: 0; height: 0; border-left: 4px solid transparent; border-right: 4px solid transparent; margin: 0 auto 3px 0; }
#gauge .arrow.up { border-bottom: 6px solid var(--grade); }
#gauge .arrow.dn { border-top: 6px solid var(--grade); }
#gauge .arrow.flat { width: 8px; height: 2px; border: 0; background: var(--grade); margin-bottom: 5px; }
#gauge .elev { padding-top: 4px; }
#gauge .elev svg { display: block; width: 100%; height: ${GH}px; margin-top: 2px; }
#gauge .elev .seg { font-family: 'DSEG7Mini', monospace; font-size: 9px; }
#gauge .area { fill: var(--grade); opacity: .55; transition: fill .3s; }
#gauge .air-tag { opacity: 0; font: 900 7px/1 "Segoe UI", system-ui, sans-serif; letter-spacing: .8px; padding: 1px 3px; border-radius: 2px;
  background: #ffd21f; color: #111; }
#gauge.air .air-tag { opacity: 1; }
#gauge .face { position: absolute; left: 0; right: 0; bottom: 5px; display: flex; justify-content: space-between; padding: 0 20px; }
#gauge .face i { width: 22px; height: 5px; border-radius: 3px; background: linear-gradient(#2c2f33, #1a1b1d); box-shadow: 0 1px 0 rgba(255,255,255,.08), inset 0 1px 1px rgba(0,0,0,.6); }
html.touch #gauge { left: calc(12px + env(safe-area-inset-left)); bottom: auto; top: calc(12px + env(safe-area-inset-top));
                    transform: scale(.85); transform-origin: top left; }
`;

// a seven-segment field: faint "8888" ghost behind, live value right-aligned on top
const seg = (cls, ghost) => `<span class="seg ${cls}"><span class="gh">${ghost}</span><span class="v"></span></span>`;

const html = `
<div class="scr">
  <div class="row status">
    <span class="clock">${seg('clk', '88:88')}</span>
    <span class="air-tag">AIR</span>
    <span class="icons"><span class="bars"><i style="height:3px"></i><i style="height:5px"></i><i style="height:7px"></i><i style="height:9px"></i></span><span class="batt"><i></i></span></span>
  </div>
  <div class="row speed">
    <div class="top"><span class="lbl">Speed</span><span class="unit">km/h</span></div>
    ${seg('spd', '88.8')}
  </div>
  <div class="pair">
    <div><div class="lbl">Slope</div><div class="fv"><span class="arrow sl-a flat"></span>${seg('sl', '88')}<span class="unit">°</span></div></div>
    <div><div class="lbl">Grade</div><div class="fv">${seg('gr', '888')}<span class="unit">%</span></div></div>
  </div>
  <div class="elev">
    <div class="row"><span class="lbl">Elevation</span><span>${seg('el', '-888')}<span class="unit">m</span></span></div>
    <svg viewBox="0 0 ${GW} ${GH}" preserveAspectRatio="none">
      <path class="area"/><path class="line" fill="none" stroke="#111417" stroke-width="1.4" vector-effect="non-scaling-stroke"/>
      <circle class="dot" r="2" fill="#111417"/>
    </svg>
  </div>
</div>
<div class="face"><i></i><i></i></div>`;

// DSEG renders '!' as a blank cell the width of a digit, so values stay right-aligned like a real LCD
const pad = (s, n) => (s.length >= n ? s : '!'.repeat(n - s.length) + s);

export class Gauge {
  constructor(parent = document.getElementById('hud') || document.body) {
    const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);
    this.el = document.createElement('div'); this.el.id = 'gauge'; this.el.innerHTML = html;
    parent.appendChild(this.el);
    const q = (s) => this.el.querySelector(s);
    this.f = { clk: q('.clk .v'), spd: q('.spd .v'), sl: q('.sl .v'), gr: q('.gr .v'), el: q('.el .v') };
    this.arrow = q('.sl-a'); this.area = q('.area'); this.line = q('.line'); this.dot = q('.dot');
    this.sDeg = 0; this.sKmh = 0; this.last = {};
    this.hist = []; this.histT = 0;
  }
  set(key, v, fn) { if (this.last[key] !== v) { this.last[key] = v; fn(v); } }
  txt(key, v) { this.set(key, v, (s) => { this.f[key].textContent = s; }); }

  update(kmh, slopeDeg, inAir, dt = 1 / 60, elev = 0) {
    // clock (real time, like the device would)
    const now = new Date();
    this.txt('clk', `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`);
    this.set('air', !!inAir, (v) => this.el.classList.toggle('air', v));

    // speed, lightly smoothed so the tenths don't flicker
    this.sKmh += (kmh - this.sKmh) * Math.min(1, dt * 10);
    this.txt('spd', pad(Math.min(99.9, this.sKmh).toFixed(1), 3));

    // slope / grade along the direction of travel
    this.sDeg += (slopeDeg - this.sDeg) * Math.min(1, dt * 8);
    const deg = Math.round(this.sDeg), grade = Math.round(Math.tan(this.sDeg * Math.PI / 180) * 100);
    this.txt('sl', pad(String(Math.min(99, Math.abs(deg))), 2));
    this.txt('gr', pad(String(Math.max(-99, Math.min(999, grade))), 3));
    const ag = Math.abs(grade);
    this.set('gcol', ag < 4 ? '#2fb34a' : ag < 8 ? '#e8c21a' : ag < 13 ? '#f08a1c' : '#e0352b', (c) => this.el.style.setProperty('--grade', c));
    this.set('dir', deg > 0 ? 'up' : deg < 0 ? 'dn' : 'flat', (v) => { this.arrow.className = `arrow sl-a ${v}`; });

    // elevation readout + rolling profile
    this.txt('el', pad(String(Math.round(elev)), 4));
    this.histT += dt;
    if (this.histT >= HIST_DT || !this.hist.length) {
      this.histT = 0;
      this.hist.push(elev); if (this.hist.length > HIST) this.hist.shift();
      this.drawProfile();
    }
  }

  drawProfile() {
    const h = this.hist, n = h.length;
    let lo = Infinity, hi = -Infinity;
    for (const v of h) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
    const mid = (lo + hi) / 2, span = Math.max(hi - lo, 4);   // at least 4 m tall so flat ground stays flat
    const x = (i) => GW - (n - 1 - i) * (GW / (HIST - 1));
    const y = (v) => GH - 3 - ((v - (mid - span / 2)) / span) * (GH - 6);
    let d = '';
    for (let i = 0; i < n; i++) d += `${i ? 'L' : 'M'}${x(i).toFixed(1)} ${y(h[i]).toFixed(1)}`;
    this.line.setAttribute('d', d);
    this.area.setAttribute('d', `${d}L${GW} ${GH}L${x(0).toFixed(1)} ${GH}Z`);
    this.dot.setAttribute('cx', GW - 1.5); this.dot.setAttribute('cy', y(h[n - 1]).toFixed(1));
  }
}

// Live jump counter + high scores.
//  - In the air: a card counts the distance from the take-off point live (metres), with height and air
//    time, and draws the flight path as you fly.
//  - On landing: the final numbers hold for a moment; a new record turns the card gold with a ribbon and
//    confetti. Crashing mid-air marks it BAILED and it doesn't count.
//  - Records (longest / highest jump, longest air, top speed, top 5 jumps) persist in localStorage and
//    show on a trophy chip (top-left) and a records card (click the chip, press H, or Menu > Records).
// Call hud.update(st, dt, crashed) once per frame.

const KEY = 'bmx-records-v1';
const MIN_AIR = 0.25;       // s: shorter hops (spring bounces) don't count as jumps
const SHOW_AFTER = 0.2;     // s in the air before the live card appears
const HOLD = 2.2;           // s the result stays up after landing

const css = `
/* the page styles every <b> as a key cap: not here */
#airCard b, #trophy b, #records b { background: none; padding: 0; border-radius: 0; }
#airCard { position: fixed; top: 14px; left: 50%; z-index: 25; width: 200px; margin-left: -100px; padding: 8px 12px 8px;
  border-radius: 18px; color: #fff; text-shadow: none; pointer-events: none; user-select: none;
  font: 700 12px/1.2 ui-rounded, "Segoe UI", system-ui, sans-serif;
  background: rgba(14,24,31,.72); backdrop-filter: blur(12px);
  box-shadow: 0 14px 30px rgba(0,0,0,.28), inset 0 0 0 1px rgba(255,255,255,.1);
  opacity: 0; transform: translateY(-14px) scale(.92); transition: opacity .18s ease, transform .22s cubic-bezier(.2,1.4,.4,1); }
#airCard.show { opacity: 1; transform: none; }
#airCard .tag { display: flex; justify-content: space-between; align-items: center; font-size: 10px; letter-spacing: 1.4px; color: rgba(255,255,255,.6); }
#airCard .tag b { font-weight: 900; }
#airCard .dist { display: flex; align-items: baseline; justify-content: center; gap: 4px; margin: 2px 0 0; }
#airCard .dist .n { font-size: 38px; font-weight: 900; letter-spacing: -1px; font-variant-numeric: tabular-nums; }
#airCard .dist .u { font-size: 18px; font-weight: 800; opacity: .75; }
#airCard svg { display: block; width: 100%; height: 22px; margin: 0 0 5px; overflow: visible; }
#airCard .path { fill: none; stroke: #ffd21f; stroke-width: 2.5; stroke-linecap: round; stroke-linejoin: round; }
#airCard .ghost { fill: none; stroke: rgba(255,255,255,.22); stroke-width: 1.5; stroke-dasharray: 3 4; }
#airCard .dot { fill: #fff; }
#airCard .meta { display: flex; justify-content: space-between; gap: 8px; font-size: 11.5px; font-variant-numeric: tabular-nums; white-space: nowrap; }
#airCard .meta b { font-weight: 900; }
#airCard .best { color: rgba(255,255,255,.55); white-space: nowrap; }
#airCard .ribbon { position: absolute; left: 50%; top: -11px; transform: translateX(-50%) scale(0); padding: 4px 12px; border-radius: 999px;
  font-size: 10.5px; font-weight: 900; letter-spacing: 1.5px; color: #3a2400; white-space: nowrap;
  background: linear-gradient(180deg, #ffe680, #ffb820); box-shadow: 0 4px 12px rgba(255,170,0,.45); transition: transform .3s cubic-bezier(.2,1.6,.4,1); }
/* new record: gold card */
#airCard.record { background: linear-gradient(160deg, rgba(120,80,0,.82), rgba(60,36,0,.82)); box-shadow: 0 0 0 2px #ffcf3a, 0 14px 34px rgba(255,170,0,.45); }
#airCard.record .ribbon { transform: translateX(-50%) scale(1); }
#airCard.record .dist .n { background: linear-gradient(180deg, #fff6c8, #ffc21a); -webkit-background-clip: text; background-clip: text; color: transparent; }
/* bailed */
#airCard.bailed { background: rgba(80,14,14,.78); box-shadow: 0 0 0 2px rgba(255,80,70,.8), 0 14px 30px rgba(0,0,0,.3); }
#airCard.bailed .path { stroke: #ff6a5a; }
.confetti { position: fixed; z-index: 26; width: 7px; height: 11px; border-radius: 2px; pointer-events: none;
  animation: confetti-fall 1.4s cubic-bezier(.2,.6,.4,1) forwards; }
@keyframes confetti-fall { 0% { transform: translate(0,0) rotate(0deg); opacity: 1; }
  100% { transform: translate(var(--dx), var(--dy)) rotate(var(--r)); opacity: 0; } }

/* trophy chip */
#trophy { position: fixed; top: 14px; left: 16px; z-index: 24; display: flex; align-items: center; gap: 8px; height: 42px; padding: 0 14px 0 8px;
  border: 0; border-radius: 14px; cursor: pointer; color: #fff; text-shadow: none;
  font: 800 13px ui-rounded, "Segoe UI", system-ui, sans-serif; background: rgba(18,30,38,.55); backdrop-filter: blur(10px);
  box-shadow: 0 4px 14px rgba(0,0,0,.22), inset 0 0 0 1px rgba(255,255,255,.12); transition: background .15s, transform .15s; }
#trophy:hover { background: rgba(18,30,38,.72); }
#trophy:active { transform: scale(.96); }
#trophy svg { width: 26px; height: 26px; }
#trophy small { display: block; font-size: 9.5px; letter-spacing: 1.2px; color: rgba(255,255,255,.55); }
#trophy b { font-size: 14px; font-variant-numeric: tabular-nums; }
#trophy.bump { animation: trophy-bump .6s cubic-bezier(.2,1.6,.4,1); }
@keyframes trophy-bump { 0% { transform: scale(1); } 40% { transform: scale(1.18); } 100% { transform: scale(1); } }

/* records card */
#records { position: fixed; top: 64px; left: 16px; z-index: 30; width: 300px; max-width: calc(100vw - 32px); padding: 14px; border-radius: 18px;
  color: #eef4f6; text-shadow: none; font: 600 12.5px/1.3 ui-rounded, "Segoe UI", system-ui, sans-serif;
  background: rgba(14,24,31,.88); backdrop-filter: blur(14px); box-shadow: 0 18px 40px rgba(0,0,0,.35), inset 0 0 0 1px rgba(255,255,255,.08);
  opacity: 0; transform: translateY(-8px) scale(.98); transform-origin: top left; pointer-events: none; transition: opacity .18s, transform .18s; }
#records.open { opacity: 1; transform: none; pointer-events: auto; }
#records .hd { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }
#records .hd strong { font-size: 15px; font-weight: 800; }
#records .hd button { border: 0; border-radius: 9px; padding: 6px 9px; cursor: pointer; color: #fff; background: rgba(255,255,255,.09);
  font: 700 11.5px ui-rounded, "Segoe UI", system-ui, sans-serif; }
#records .hd button:hover { background: rgba(255,255,255,.18); }
#records .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
#records .medal { position: relative; padding: 10px 10px 9px; border-radius: 14px; overflow: hidden;
  background: linear-gradient(160deg, rgba(255,255,255,.1), rgba(255,255,255,.03)); box-shadow: inset 0 0 0 1px rgba(255,255,255,.07); }
#records .medal .ic { font-size: 18px; }
#records .medal span { display: block; margin-top: 4px; font-size: 9.5px; letter-spacing: 1.1px; text-transform: uppercase; color: rgba(255,255,255,.55); }
#records .medal b { display: block; margin-top: 2px; font-size: 20px; font-weight: 900; font-variant-numeric: tabular-nums; }
#records .medal b small { font-size: 12px; opacity: .7; margin-left: 2px; }
#records .medal.gold { background: linear-gradient(160deg, rgba(255,200,40,.32), rgba(255,160,0,.08)); box-shadow: inset 0 0 0 1px rgba(255,200,60,.35); }
#records h4 { margin: 14px 0 6px; font-size: 10.5px; font-weight: 800; letter-spacing: 1.3px; text-transform: uppercase; color: rgba(255,255,255,.5); }
#records ol { list-style: none; margin: 0; padding: 0; }
#records li { display: grid; grid-template-columns: 26px 1fr auto; align-items: center; gap: 8px; padding: 6px 0; border-top: 1px solid rgba(255,255,255,.06); }
#records li .rk { width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center; font-size: 11px; font-weight: 900; color: #1d2b64; background: rgba(255,255,255,.7); }
#records li:nth-child(1) .rk { background: linear-gradient(180deg, #ffe680, #ffb820); }
#records li:nth-child(2) .rk { background: linear-gradient(180deg, #f2f4f7, #b9c0c9); }
#records li:nth-child(3) .rk { background: linear-gradient(180deg, #ffcf9e, #d28a4a); }
#records li .m { font-weight: 900; font-size: 14px; font-variant-numeric: tabular-nums; }
#records li .sub { color: rgba(255,255,255,.5); font-size: 11px; text-align: right; }
#records .empty { padding: 8px 0; color: rgba(255,255,255,.45); }
html.touch #trophy { top: calc(10px + env(safe-area-inset-top)); left: calc(130px + env(safe-area-inset-left)); }   /* beside the bike computer */
html.touch #records { top: calc(60px + env(safe-area-inset-top)); }
html.touch #airCard { top: calc(10px + env(safe-area-inset-top)); transform-origin: top center; }
`;

const TROPHY = `<svg viewBox="0 0 32 32"><defs><linearGradient id="tg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe680"/><stop offset="1" stop-color="#ffb21a"/></linearGradient></defs>
  <path d="M10 5h12v6a6 6 0 0 1-12 0z" fill="url(#tg)"/><path d="M10 7H6.5a3.5 3.5 0 0 0 4.2 5.4M22 7h3.5a3.5 3.5 0 0 1-4.2 5.4" fill="none" stroke="url(#tg)" stroke-width="2"/>
  <path d="M14.5 17h3v4h-3z" fill="#e3a412"/><path d="M11 22h10l1 4H10z" fill="url(#tg)"/><path d="M13 8l1 2.3 2.5.2-1.9 1.6.6 2.4-2.2-1.3" fill="#fff8d0" opacity=".85"/></svg>`;

const load = () => { try { return { dist: 0, height: 0, air: 0, speed: 0, top: [], ...JSON.parse(localStorage.getItem(KEY) || '{}') }; } catch { return { dist: 0, height: 0, air: 0, speed: 0, top: [] }; } };
const fmt = (v) => v.toFixed(1);

export class AirHud {
  constructor() {
    const style = document.createElement('style'); style.textContent = css; document.head.appendChild(style);
    this.rec = load();

    this.card = document.createElement('div'); this.card.id = 'airCard';
    this.card.innerHTML = `<div class="ribbon">★ NEW RECORD ★</div>
      <div class="tag"><span class="state">AIR</span><b class="t">0.00 s</b></div>
      <div class="dist"><span class="n">0.0</span><span class="u">m</span></div>
      <svg viewBox="0 0 200 22" preserveAspectRatio="none"><path class="ghost"/><path class="path"/><circle class="dot" r="2.5"/></svg>
      <div class="meta"><span>▲ <b class="h">0.0 m</b> · <b class="s">0 km/h</b></span><span class="best"></span></div>`;
    document.body.appendChild(this.card);
    const q = (s) => this.card.querySelector(s);
    this.el = { state: q('.state'), t: q('.t'), n: q('.n'), h: q('.h'), s: q('.s'), best: q('.best'), path: q('.path'), ghost: q('.ghost'), dot: q('.dot') };

    this.chip = document.createElement('button'); this.chip.id = 'trophy'; this.chip.title = 'Records (H)';
    this.chip.innerHTML = `${TROPHY}<span><small>BEST JUMP</small><b class="cb"></b></span>`;
    document.body.appendChild(this.chip);
    this.board = document.createElement('div'); this.board.id = 'records';
    document.body.appendChild(this.board);
    this.chip.addEventListener('click', () => { this.toggleBoard(); this.chip.blur(); });
    this.board.addEventListener('pointerdown', (e) => e.stopPropagation());
    this.board.addEventListener('click', (e) => {
      const a = e.target.closest('[data-a]')?.dataset.a; if (!a) return; e.target.blur();
      if (a === 'close') this.toggleBoard(false);
      if (a === 'clear' && confirm('Clear all records?')) { this.rec = { dist: 0, height: 0, air: 0, speed: 0, top: [] }; this.save(); this.renderBoard(); this.renderChip(); }
    });
    addEventListener('keydown', (e) => { if (e.code === 'KeyH' && !e.repeat && e.target.tagName !== 'INPUT') this.toggleBoard(); });
    addEventListener('pointerdown', (e) => { if (!this.board.contains(e.target) && !this.chip.contains(e.target)) this.toggleBoard(false); });

    this.jump = null; this.holdT = 0; this.wasAir = false;
    this.renderChip(); this.renderBoard();
  }

  save() { try { localStorage.setItem(KEY, JSON.stringify(this.rec)); } catch { /* private mode */ } }
  renderChip() { this.chip.querySelector('.cb').textContent = this.rec.dist > 0 ? `${fmt(this.rec.dist)} m` : '—'; }
  toggleBoard(open) {
    const o = open ?? !this.board.classList.contains('open');
    if (o) this.renderBoard();
    this.board.classList.toggle('open', o);
  }
  renderBoard() {
    const r = this.rec, medal = (ic, label, v, unit, gold) =>
      `<div class="medal${gold ? ' gold' : ''}"><div class="ic">${ic}</div><span>${label}</span><b>${v}<small>${unit}</small></b></div>`;
    const top = r.top.length ? `<ol>${r.top.map((j) => `<li><span class="rk"></span><span class="m">${fmt(j.dist)} m</span>
      <span class="sub">${fmt(j.height)} m high · ${j.air.toFixed(2)} s</span></li>`).join('')}</ol>` : '<div class="empty">No jumps yet — find a lip and send it!</div>';
    this.board.innerHTML = `<div class="hd"><strong>🏆 Records</strong><span><button data-a="clear">Clear</button> <button data-a="close">✕</button></span></div>
      <div class="grid">
        ${medal('📏', 'Longest jump', fmt(r.dist), 'm', r.dist > 0)}
        ${medal('⛰️', 'Highest jump', fmt(r.height), 'm', r.height > 0)}
        ${medal('⏱️', 'Longest air', r.air.toFixed(2), 's', r.air > 0)}
        ${medal('⚡', 'Top speed', Math.round(r.speed), 'km/h', r.speed > 0)}
      </div>
      <h4>Top jumps</h4>${top}`;
    this.board.querySelectorAll('.rk').forEach((el, i) => { el.textContent = i + 1; });
  }

  // flight path sparkline: x = distance, y = height, scaled to fit; the best jump as a dashed ghost
  drawPath() {
    const j = this.jump, pts = j.pts, W = 200, H = 22;
    const maxD = Math.max(j.dist, this.rec.dist, 4), maxH = Math.max(j.peak, 0.8);
    const xy = (d, h) => `${(d / maxD * W).toFixed(1)} ${(H - 3 - Math.max(0, h) / maxH * (H - 6)).toFixed(1)}`;
    this.el.path.setAttribute('d', pts.length ? 'M' + pts.map(([d, h]) => xy(d, h)).join('L') : '');
    const last = pts[pts.length - 1] || [0, 0], [cx, cy] = xy(last[0], last[1]).split(' ');
    this.el.dot.setAttribute('cx', cx); this.el.dot.setAttribute('cy', cy);
    if (this.rec.dist > 0) { const bd = this.rec.dist; this.el.ghost.setAttribute('d', `M0 ${H - 3}Q${(bd / maxD * W / 2).toFixed(1)} ${(H - 3 - (H - 6) * 1.6).toFixed(1)} ${(bd / maxD * W).toFixed(1)} ${H - 3}`); }
  }

  confetti() {
    const r = this.card.getBoundingClientRect(), cols = ['#ffd21f', '#ff6a5a', '#4fd1ff', '#7dff8a', '#ffffff', '#ff9ff3'];
    for (let i = 0; i < 46; i++) {
      const c = document.createElement('i'); c.className = 'confetti';
      c.style.left = `${r.left + r.width / 2 + (Math.random() - 0.5) * r.width * 0.6}px`; c.style.top = `${r.top + r.height * 0.4}px`;
      c.style.background = cols[i % cols.length];
      c.style.setProperty('--dx', `${(Math.random() - 0.5) * 420}px`);
      c.style.setProperty('--dy', `${120 + Math.random() * 260}px`);
      c.style.setProperty('--r', `${(Math.random() - 0.5) * 900}deg`);
      c.style.animationDelay = `${Math.random() * 0.12}s`;
      document.body.appendChild(c); setTimeout(() => c.remove(), 1700);
    }
  }

  finish(j, bailed) {
    j.done = true;
    if (j.t < MIN_AIR) { if (this.jump === j) { this.jump = null; this.card.classList.remove('show'); } return; }
    this.card.classList.add('show');
    if (bailed) {
      this.card.classList.remove('record'); this.card.classList.add('bailed');
      this.el.state.textContent = 'BAILED'; this.el.best.textContent = 'not counted';
    } else {
      const r = this.rec, isRec = j.dist > r.dist + 0.05;
      if (j.dist > r.dist) r.dist = j.dist;
      if (j.peak > r.height) r.height = j.peak;
      if (j.t > r.air) r.air = j.t;
      r.top.push({ dist: j.dist, height: Math.max(0, j.peak), air: j.t });
      r.top.sort((x, y) => y.dist - x.dist); r.top = r.top.slice(0, 5);
      this.save(); this.renderChip(); if (this.board.classList.contains('open')) this.renderBoard();
      this.el.state.textContent = 'LANDED';
      this.el.best.textContent = isRec ? '' : `best ${fmt(r.dist)} m`;
      if (isRec) { this.card.classList.add('record'); this.confetti(); this.chip.classList.remove('bump'); void this.chip.offsetWidth; this.chip.classList.add('bump'); }
    }
    this.holdT = HOLD;
  }

  update(st, dt, crashed) {
    const kmh = Math.abs(st.v) * 3.6;
    if (!crashed && kmh > this.rec.speed + 0.5 && kmh < 150) { this.rec.speed = kmh; this.speedDirty = true; }
    let j = this.jump;
    const air = st.air && !crashed;

    // take-off (a landed jump still being judged is settled first: a bounce right after doesn't erase it)
    if (air && !this.wasAir) {
      if (j && j.landed && !j.done) this.finish(j, false);
      if (!j || j.done || j.landed) {
        j = this.jump = { x0: st.x, z0: st.z, y0: st.y, dist: 0, peak: 0, t: 0, pts: [[0, 0]], landed: false, landT: 0, done: false };
        this.holdT = 0; this.card.classList.remove('record', 'bailed');
      }
    }
    if (j && !j.done) {
      if (air && !j.landed) {
        j.t = st.airTime;
        j.dist = Math.hypot(st.x - j.x0, st.z - j.z0);
        const h = st.y - j.y0; j.peak = Math.max(j.peak, h);
        const lp = j.pts[j.pts.length - 1];
        if (j.dist - lp[0] > 0.08) j.pts.push([j.dist, h]);
        if (j.t > SHOW_AFTER) {
          this.card.classList.add('show');
          this.el.state.textContent = 'AIR';
          this.el.t.textContent = `${j.t.toFixed(2)} s`;
          this.el.n.textContent = fmt(j.dist);
          this.el.h.textContent = `${fmt(Math.max(0, j.peak))} m`;
          this.el.s.textContent = `${Math.round(kmh)} km/h`;
          const toBeat = this.rec.dist;
          this.el.best.textContent = toBeat > 0 ? (j.dist > toBeat ? '★ past your best!' : `best ${fmt(toBeat)} m`) : '';
          this.drawPath();
        }
      }
      if (crashed) this.finish(j, true);                                  // bailed in the air or slammed the landing
      else if (!air && !j.landed) { j.landed = true; j.landT = 0; if (j.t >= MIN_AIR) this.el.state.textContent = 'LANDED'; }
      else if (j.landed && (j.landT += dt) > 0.25) this.finish(j, false);  // rode it out: counts
    }
    if (this.holdT > 0) { this.holdT -= dt; if (this.holdT <= 0) { this.card.classList.remove('show'); if (this.jump && this.jump.done) this.jump = null; } }
    if (this.speedDirty && !st.air) { this.speedDirty = false; this.save(); }
    this.wasAir = air;
  }
}

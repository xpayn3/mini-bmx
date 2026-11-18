import * as THREE from 'three';

// Riding effects: soft dust smoke, tyre tracks drawn into the ground, and flying dirt/rock chunks.
// All pools are fixed-size ring buffers, nothing is allocated per frame.

const DUST_MAX = 700, CHUNK_MAX = 180, SEG_MAX = 14000;   // ~1 km of track per wheel, kept until recycled

// ---------- dust smoke: textured, rotating, sun-lit soft particles that erode into wisps ----------
const dustVS = /* glsl */`
  attribute float size; attribute float alpha; attribute vec3 tint; attribute float rot; attribute float cell; attribute float life;
  uniform float uScale;
  varying float vA; varying vec3 vC; varying float vRot; varying float vCell; varying float vK;
  void main() {
    vA = alpha; vC = tint; vRot = rot; vCell = cell; vK = life;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_PointSize = size * uScale / -mv.z;
    gl_Position = projectionMatrix * mv;
  }`;
const dustFS = /* glsl */`
  uniform sampler2D uTex;
  uniform vec3 uSun;     // sun colour (linear)
  uniform vec3 uSky;     // ambient colour (linear)
  varying float vA; varying vec3 vC; varying float vRot; varying float vCell; varying float vK;
  void main() {
    vec2 p = gl_PointCoord - 0.5;
    float c = cos(vRot), s = sin(vRot);
    vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
    if (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) discard;
    vec2 cell = vec2(mod(vCell, 2.0), floor(vCell / 2.0));
    vec4 t = texture2D(uTex, (q * 0.98 + 0.01 + cell) * 0.5);
    // density erodes from the thin parts first as the puff ages -> wisps that tear apart
    float er = vK * 0.75;
    float dens = t.r * smoothstep(er, er + 0.35, t.g);
    float a = dens * vA;
    if (a < 0.003) discard;
    // cheap volume lighting: top of the puff faces the sun, underside is self-shadowed
    float up = 0.5 - gl_PointCoord.y;
    float light = clamp(0.55 + up * 0.9 + (t.b - 0.5) * 0.35, 0.0, 1.2);
    vec3 col = vC * (uSky * 0.55 + uSun * light * 0.6);
    gl_FragColor = vec4(clamp(col, 0.0, 4.0), clamp(a, 0.0, 1.0));
  }`;

// 2x2 atlas of soft noise puffs: R = density, G = erosion noise, B = lighting detail
function makeSmokeTexture() {
  const N = 128, W = N * 2;
  const data = new Uint8Array(W * W * 4);
  let seed = 1337;
  const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const G = 32, grid = Array.from({ length: 4 }, () => Array.from({ length: (G + 1) * (G + 1) }, rand));
  const vnoise = (g, x, y) => {   // tileable-ish value noise on a GxG lattice
    const xi = Math.floor(x) % G, yi = Math.floor(y) % G, xf = x - Math.floor(x), yf = y - Math.floor(y);
    const sx = xf * xf * (3 - 2 * xf), sy = yf * yf * (3 - 2 * yf);
    const at = (a, b) => g[((b + G) % G) * (G + 1) + ((a + G) % G)];
    const a = at(xi, yi), b = at(xi + 1, yi), c = at(xi, yi + 1), d = at(xi + 1, yi + 1);
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  };
  const fbm = (g, x, y, oct) => { let v = 0, amp = 0.5, f = 1; for (let o = 0; o < oct; o++) { v += vnoise(g, x * f, y * f) * amp; f *= 2; amp *= 0.5; } return v; };
  for (let cell = 0; cell < 4; cell++) {
    const g = grid[cell], ox = (cell % 2) * N, oy = Math.floor(cell / 2) * N, off = cell * 7.3;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const u = x / N - 0.5, v = y / N - 0.5;
      // warp the radius with noise so edges are billowy, not round
      const warp = fbm(g, x / 22 + off, y / 22 + off, 3);
      const r = Math.hypot(u, v) * 2 * (0.75 + warp * 0.5);
      const fall = Math.max(0, 1 - r); const soft = fall * fall * (3 - 2 * fall);
      const n1 = fbm(g, x / 14 + off * 2, y / 14, 5);
      const n2 = fbm(g, x / 7 + 3.1, y / 7 + off, 4);
      const k = ((oy + y) * W + ox + x) * 4;
      data[k] = Math.round(255 * Math.min(1, soft * (0.45 + n1 * 0.9)));
      data[k + 1] = Math.round(255 * Math.min(1, n2 * 0.6 + soft * 0.55));
      data[k + 2] = Math.round(255 * n1);
      data[k + 3] = 255;
    }
  }
  const tex = new THREE.DataTexture(data, W, W, THREE.RGBAFormat);
  tex.magFilter = tex.minFilter = THREE.LinearFilter;
  tex.needsUpdate = true;
  return tex;
}

export class FX {
  constructor(scene, terrain) {
    this.terrain = terrain;
    this.t = 0;

    // dust
    this.dustPos = new Float32Array(DUST_MAX * 3);
    this.dustSize = new Float32Array(DUST_MAX);
    this.dustAlpha = new Float32Array(DUST_MAX);
    this.dustTint = new Float32Array(DUST_MAX * 3);
    this.dust = Array.from({ length: DUST_MAX }, () => ({ age: 1, life: 1, v: new THREE.Vector3(), s0: 0.3, a0: 0.5, ph: 0, grow: 4, spin: 0 }));
    this.dustRot = new Float32Array(DUST_MAX); this.dustCell = new Float32Array(DUST_MAX); this.dustK = new Float32Array(DUST_MAX);
    this.dustNext = 0;
    const dg = new THREE.BufferGeometry();
    dg.setAttribute('position', new THREE.BufferAttribute(this.dustPos, 3));
    dg.setAttribute('size', new THREE.BufferAttribute(this.dustSize, 1));
    dg.setAttribute('alpha', new THREE.BufferAttribute(this.dustAlpha, 1));
    dg.setAttribute('tint', new THREE.BufferAttribute(this.dustTint, 3));
    dg.setAttribute('rot', new THREE.BufferAttribute(this.dustRot, 1));
    dg.setAttribute('cell', new THREE.BufferAttribute(this.dustCell, 1));
    dg.setAttribute('life', new THREE.BufferAttribute(this.dustK, 1));
    this.dustMat = new THREE.ShaderMaterial({
      uniforms: { uScale: { value: 800 }, uTex: { value: makeSmokeTexture() },
        uSun: { value: new THREE.Color(0xffe2b8).multiplyScalar(1.6) }, uSky: { value: new THREE.Color(0xcfe6ff) } },
      vertexShader: dustVS, fragmentShader: dustFS,
      transparent: true, depthWrite: false,
    });
    this.dustPoints = new THREE.Points(dg, this.dustMat);
    this.dustPoints.frustumCulled = false;
    this.dustPoints.renderOrder = 2;
    scene.add(this.dustPoints);

    // flying chunks of dirt and rock
    this.chunkMesh = new THREE.InstancedMesh(
      new THREE.TetrahedronGeometry(1, 0),
      new THREE.MeshStandardMaterial({ flatShading: true, roughness: 0.9 }),
      CHUNK_MAX);
    this.chunkMesh.castShadow = true;
    this.chunkMesh.frustumCulled = false;
    this.chunks = Array.from({ length: CHUNK_MAX }, () => ({
      age: 9, life: 1, p: new THREE.Vector3(), v: new THREE.Vector3(),
      r: new THREE.Euler(), w: new THREE.Vector3(), s: 0.03, rest: false }));
    this.chunkNext = 0;
    const black = new THREE.Color(0, 0, 0);
    for (let i = 0; i < CHUNK_MAX; i++) { this.chunkMesh.setMatrixAt(i, new THREE.Matrix4().makeScale(0, 0, 0)); this.chunkMesh.setColorAt(i, black); }
    scene.add(this.chunkMesh);

    // tyre tracks: two ribbons (front, rear) in one ring-buffer mesh
    this.segPos = new Float32Array(SEG_MAX * 6 * 3);
    this.segCol = new Float32Array(SEG_MAX * 6 * 4);
    this.segBirth = new Float32Array(SEG_MAX).fill(-1e9);
        this.segNext = 0;
    const tg = new THREE.BufferGeometry();
    tg.setAttribute('position', new THREE.BufferAttribute(this.segPos, 3));
    tg.setAttribute('color', new THREE.BufferAttribute(this.segCol, 4));
    tg.attributes.position.setUsage(THREE.DynamicDrawUsage); tg.attributes.color.setUsage(THREE.DynamicDrawUsage);
    this.trackMesh = new THREE.Mesh(tg, new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }));
    this.trackMesh.frustumCulled = false;
    this.trackMesh.renderOrder = 1;
    scene.add(this.trackMesh);
    this.wheelLast = [null, null];   // last laid point per wheel (Vector3) or null after a break

    this._m = new THREE.Matrix4(); this._q = new THREE.Quaternion(); this._s = new THREE.Vector3();
    this._c = new THREE.Color(); this._a = new THREE.Vector3(); this._b = new THREE.Vector3();
  }

  // ---------- emitters ----------
  puff(pos, vel, color, size = 0.35, life = 1.4, alpha = 0.5) {
    const i = this.dustNext; this.dustNext = (i + 1) % DUST_MAX;
    const d = this.dust[i];
    d.age = 0; d.life = life * (0.8 + Math.random() * 0.4); d.s0 = size * (0.8 + Math.random() * 0.4); d.a0 = alpha;
    d.v.copy(vel);
    d.ph = Math.random() * 100; d.grow = 2.6 + Math.random() * 1.6; d.spin = (Math.random() - .5) * 1.2;
    this.dustRot[i] = Math.random() * 6.283; this.dustCell[i] = (Math.random() * 4) | 0;
    this.dustPos[i * 3] = pos.x + (Math.random() - .5) * 0.1;
    this.dustPos[i * 3 + 1] = pos.y;
    this.dustPos[i * 3 + 2] = pos.z + (Math.random() - .5) * 0.1;
    const k = 0.9 + Math.random() * 0.2;
    this.dustTint[i * 3] = color.r * k; this.dustTint[i * 3 + 1] = color.g * k; this.dustTint[i * 3 + 2] = color.b * k;
  }
  chunk(pos, vel, color, size = 0.03, life = 2.2) {
    const i = this.chunkNext; this.chunkNext = (i + 1) % CHUNK_MAX;
    const c = this.chunks[i];
    c.age = 0; c.life = life * (0.7 + Math.random() * 0.6); c.rest = false;
    c.p.copy(pos); c.v.copy(vel);
    c.r.set(Math.random() * 6, Math.random() * 6, Math.random() * 6);
    c.w.set((Math.random() - .5) * 25, (Math.random() - .5) * 25, (Math.random() - .5) * 25);
    c.s = size * (0.6 + Math.random() * 0.9);
    this._c.copy(color).multiplyScalar(0.75 + Math.random() * 0.4);
    this.chunkMesh.setColorAt(i, this._c);
    this.chunkMesh.instanceColor.needsUpdate = true;
  }
  // lay tyre track. wheel 0 = front, 1 = rear. strength 0 = break the track.
  track(wheel, contact, dir, strength, color, width = 0.055) {
    const last = this.wheelLast[wheel];
    if (strength <= 0) { this.wheelLast[wheel] = null; return; }
    const p = this._a.set(contact.x, this.terrain.height(contact.x, contact.z) + 0.035, contact.z);
    if (!last) { this.wheelLast[wheel] = p.clone(); return; }
    const dx = p.x - last.x, dz = p.z - last.z, d2 = dx * dx + dz * dz;
    if (d2 < 0.14 * 0.14) return;
    if (d2 > 1.5 * 1.5) { last.copy(p); return; }   // teleport / respawn
    const i = this.segNext; this.segNext = (i + 1) % SEG_MAX;
    const len = Math.sqrt(d2), nx = -dz / len * width * 0.5, nz = dx / len * width * 0.5;
    const P = this.segPos, o = i * 18;
    // two triangles: last-left, last-right, p-right / last-left, p-right, p-left
    const v = [
      last.x + nx, last.y, last.z + nz,  last.x - nx, last.y, last.z - nz,  p.x - nx, p.y, p.z - nz,
      last.x + nx, last.y, last.z + nz,  p.x - nx, p.y, p.z - nz,  p.x + nx, p.y, p.z + nz,
    ];
    for (let k = 0; k < 18; k++) P[o + k] = v[k];
    this.segBirth[i] = this.t;
    // colour is written once; tracks don't fade with time, they're only recycled when the buffer wraps
    const C = this.segCol, oc = i * 24;
    for (let k = 0; k < 6; k++) { C[oc + k * 4] = color.r; C[oc + k * 4 + 1] = color.g; C[oc + k * 4 + 2] = color.b; C[oc + k * 4 + 3] = strength; }
    // upload just this segment instead of the whole buffer
    const ga = this.trackMesh.geometry.attributes;
    ga.position.addUpdateRange(o, 18); ga.position.needsUpdate = true;
    ga.color.addUpdateRange(oc, 24); ga.color.needsUpdate = true;
    last.copy(p);
  }

  // ---------- simulation ----------
  update(dt, camera, renderer) {
    this.t += dt;
    const h = renderer.domElement.height;
    this.dustMat.uniforms.uScale.value = h / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2));

    // dust: drift, slow down, rise a little, grow and fade
    for (let i = 0; i < DUST_MAX; i++) {
      const d = this.dust[i];
      if (d.age >= d.life) { this.dustAlpha[i] = 0; this.dustSize[i] = 0; continue; }
      d.age += dt;
      const k = d.age / d.life;
      d.v.multiplyScalar(Math.exp(-dt * 1.8));
      // turbulence: slow rolling swirl per puff, plus a light breeze; warm dust lifts then hangs
      const sw = this.t * 0.9 + d.ph, px = this.dustPos[i * 3], pz = this.dustPos[i * 3 + 2];
      d.v.x += (Math.sin(sw + pz * 1.3) * 0.55 + 0.12) * dt;
      d.v.z += Math.cos(sw * 1.1 + px * 1.3) * 0.55 * dt;
      d.v.y += (0.22 + 0.12 * Math.sin(sw * 0.7)) * dt * (1 - k);
      this.dustPos[i * 3] += d.v.x * dt; this.dustPos[i * 3 + 1] += d.v.y * dt; this.dustPos[i * 3 + 2] += d.v.z * dt;
      this.dustRot[i] += d.spin * dt * (1 - k * 0.7);
      this.dustK[i] = k;
      this.dustSize[i] = d.s0 * (1 + d.grow * (1 - Math.pow(1 - k, 1.8)));      // expands quickly, then slowly
      this.dustAlpha[i] = d.a0 * Math.min(1, d.age * 6) * Math.pow(1 - k, 0.9);
    }
    const dg = this.dustPoints.geometry.attributes;
    dg.position.needsUpdate = dg.size.needsUpdate = dg.alpha.needsUpdate = dg.tint.needsUpdate = dg.rot.needsUpdate = dg.cell.needsUpdate = dg.life.needsUpdate = true;

    // chunks: ballistic, spin, bounce on the terrain, then settle and shrink away
    for (let i = 0; i < CHUNK_MAX; i++) {
      const c = this.chunks[i];
      if (c.age >= c.life) continue;
      c.age += dt;
      if (!c.rest) {
        c.v.y -= 9.81 * dt;
        c.p.addScaledVector(c.v, dt);
        c.r.x += c.w.x * dt; c.r.y += c.w.y * dt; c.r.z += c.w.z * dt;
        const g = this.terrain.height(c.p.x, c.p.z) + c.s * 0.5;
        if (c.p.y < g) {
          c.p.y = g;
          if (Math.abs(c.v.y) < 0.6) { c.rest = true; }
          c.v.y *= -0.35; c.v.x *= 0.55; c.v.z *= 0.55; c.w.multiplyScalar(0.5);
        }
      }
      const fade = c.age > c.life - 0.4 ? Math.max(0, (c.life - c.age) / 0.4) : 1;
      const s = c.s * fade;
      this._q.setFromEuler(c.r);
      this._m.compose(c.p, this._q, this._s.set(s, s * 0.8, s));
      this.chunkMesh.setMatrixAt(i, this._m);
      if (c.age >= c.life) { this._m.makeScale(0, 0, 0); this.chunkMesh.setMatrixAt(i, this._m); }
    }
    this.chunkMesh.instanceMatrix.needsUpdate = true;

  }

  clearTracks() {
    this.wheelLast = [null, null]; this.segBirth.fill(-1e9); this.segCol.fill(0);
    const ga = this.trackMesh.geometry.attributes; ga.color.clearUpdateRanges(); ga.color.needsUpdate = true;   // full re-upload
  }
}

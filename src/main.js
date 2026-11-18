import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { HorizontalTiltShiftShader } from 'three/addons/shaders/HorizontalTiltShiftShader.js';
import { VerticalTiltShiftShader } from 'three/addons/shaders/VerticalTiltShiftShader.js';
import { Terrain, WATER, MAT, FLOWER_TIME } from './terrain.js';
import { addSandDetail } from './sand.js';
import { Gauge } from './gauge.js';
import { Rider } from './rider.js';
import { Suspension } from './suspension.js';
import { buildBike, STYLE_K } from './bikegen.js';
import { listBikes, gameId, storeId } from './bikestore.js';
import { FX } from './fx.js';
import { Debris } from './debris.js';
import { breakFence } from './fences.js';
import { TapeSim } from './tape.js';
import { breakCactus } from './cactus.js';
import { Water } from './water.js';
import { Ragdoll, J } from './ragdoll.js';
import { TUNE, buildTunePanel } from './tune.js';
import { buildPosePanel } from './posepanel.js';
import { IS_TOUCH, buildTouchControls } from './touch.js';

// ---------------- renderer / scene ----------------
const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.95;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const SKY = new THREE.Color(0xa9d6ea);
scene.background = SKY;
scene.fog = new THREE.Fog(SKY, 38, 85);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.3;

const camera = new THREE.PerspectiveCamera(30, innerWidth / innerHeight, 0.1, 250);

const hemi = new THREE.HemisphereLight(0xcfe6ff, 0x5a4a30, 0.55);
scene.add(hemi);
const sunDir = new THREE.Vector3(-0.55, 1, 0.42).normalize();
const sun = new THREE.DirectionalLight(0xffdcae, 3.6);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -16, right: 16, top: 16, bottom: -16, near: 1, far: 90 });
sun.shadow.bias = -0.0002;
sun.shadow.normalBias = 0.025;
scene.add(sun, sun.target);

// water (custom tropical shader, see water.js) -- created once the terrain exists
let water;

// ---------------- post processing (miniature look) ----------------
const rt = new THREE.WebGLRenderTarget(innerWidth, innerHeight, { type: THREE.HalfFloatType, samples: 4 });
const composer = new EffectComposer(renderer, rt);
composer.setPixelRatio(renderer.getPixelRatio());
composer.addPass(new RenderPass(scene, camera));
const gtao = new GTAOPass(scene, camera, innerWidth, innerHeight);
try { gtao.updateGtaoMaterial({ radius: 0.6, distanceExponent: 1.5, thickness: 1.5, scale: 1.2, samples: 8 }); } catch (e) { /* older api */ }
gtao.blendIntensity = 0.9;
// AO at half resolution: its own scene render (normals + depth) and the AO itself were the single
// most expensive part of the frame; soft contact shadows look the same at half res once blurred
{ const setSize = gtao.setSize.bind(gtao); gtao.setSize = (w, h) => setSize(Math.max(1, Math.round(w / 2)), Math.max(1, Math.round(h / 2))); }
composer.addPass(gtao);
const bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth / 2, innerHeight / 2), 0.2, 0.5, 0.92);
composer.addPass(bloom);
const tiltH = new ShaderPass(HorizontalTiltShiftShader);
const tiltV = new ShaderPass(VerticalTiltShiftShader);
composer.addPass(tiltH); composer.addPass(tiltV);
composer.addPass(new OutputPass());
const grade = new ShaderPass({
  uniforms: { tDiffuse: { value: null } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; varying vec2 vUv;
    void main(){ vec4 c = texture2D(tDiffuse, vUv);
      float l = dot(c.rgb, vec3(0.299,0.587,0.114));
      c.rgb = mix(vec3(l), c.rgb, 1.16);
      vec2 d = vUv - 0.5; c.rgb *= 1.0 - dot(d,d) * 0.6;
      gl_FragColor = c; }`,
});
composer.addPass(grade);
let tiltOn = true, aoWanted = true;
function sizeTilt() {
  const k = tiltOn ? 3.2 : 0;
  tiltH.uniforms.h.value = k / innerWidth; tiltV.uniforms.v.value = k / innerHeight;
  tiltH.uniforms.r.value = tiltV.uniforms.r.value = 0.5;
}
sizeTilt();

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
  // composer.setSize resizes every pass (GTAO included) at the device pixel ratio
  renderer.setSize(innerWidth, innerHeight); composer.setSize(innerWidth, innerHeight);
  sizeTilt();
});

// ---------------- world ----------------
// ---------------- bike choice (URL ?bike=, else last pick) ----------------
const BIKES = {
  bmx: { file: 'assets/bmx.glb', root: 'bmx', label: 'BMX' },
  dh: {
    file: 'assets/dh.glb', root: 'dh', label: 'Downhill',
    // ATTACK POSITION: standing over a slammed saddle, hips back above its tail, chest down over
    // the bars, elbows and knees out, feet wide -- the stance a downhill rider holds the whole run.
    // hipY is + because this bike's saddle (top 0.83) sits far higher than the BMX's (0.65);
    // seatFloor keeps the hips clear of it on climbs and landings
    pose: { hipX: -0.07, hipY: 0.075, lean: 0.22, elbowsOut: 0.8, kneesOut: 0.7, stance: 0.03, seatFloor: true },
    // RIDE STYLE, as multipliers on the tune panel (so its sliders still work on either bike):
    // a heavy, slack, long bike on big knobby tyres and 200 mm of travel -- slow to get going but
    // a tall top gear, calm steering that holds a line, more grip at speed, deep soft legs that
    // swallow drops, and a rider who drops low on every descent
    ride: {
      steerRate: 0.75, steerRelease: 0.8, barSpeed: 0.75, steerMax: 0.85, counter: 0.6,
      turnSlow: 0.9, turnFast: 1.15,
      leanMax: 1.1, leanIn: 0.8, leanOut: 0.8, leanDamp: 1.2,
      legStiff: 0.6, legDamp: 1.2, legComp: 1.3, legExt: 1.3, attackDrop: 1.3,
      pedalLaunch: 0.75, pedalPower: 0.85, pedalTop: 1.35, airDrag: 0.85, brakeForce: 1.3, popPower: 0.7,
      grip: 1.15, oversteer: 0.7,   // big knobbies bite harder and the rear lets go less
      tyreHz: 0.75, tyreDamp: 1.3, travel: 2.2,   // 200 mm of plush travel: lower, softer bounce, soaks more
    },
    land: 1.45,   // landings feel this much softer: SLAM! takes a drop ~1.45x as hard, less speed scrubbed
  },
};
// bikes made in the builder (+ Build / U). Their ride feel sits between the BMX (k = 0) and the
// downhill bike (k = 1): the DH ride multipliers and pose, scaled by k
for (const cfg of listBikes()) {
  const k = STYLE_K[cfg.style] ?? 0, dh = BIKES.dh;
  const ride = Object.fromEntries(Object.entries(dh.ride).map(([n, v]) => [n, 1 + (v - 1) * k]));
  const pose = Object.fromEntries(Object.entries(dh.pose).filter(([n]) => n !== 'seatFloor').map(([n, v]) => [n, v * k]));
  pose.seatFloor = k >= 0.5;
  BIKES[gameId(cfg.id)] = { label: cfg.name || 'Bike', cfg, ride, pose, land: 1 + (dh.land - 1) * k };
}
const url = new URL(location.href);
const store = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
                set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } } };
const isBike = (id) => id != null && Object.hasOwn(BIKES, id);   // not 'constructor' & co.
const bikeId = isBike(url.searchParams.get('bike')) ? url.searchParams.get('bike') : isBike(store.get('bike')) ? store.get('bike') : 'bmx';
const urlSeed = parseInt(url.searchParams.get('seed'), 10);
let seed = Number.isFinite(urlSeed) ? urlSeed : (Math.random() * 1e6) | 0;
const RIDE = BIKES[bikeId].ride || {}, LAND = BIKES[bikeId].land || 1;
const T = new Proxy(TUNE, { get: (o, k) => o[k] * (RIDE[k] ?? 1) });   // TUNE, scaled for this bike
function openBikeBuilder() {   // edits the bike being ridden if it is a built one
  import('./builder.js').then(({ openBuilder }) => openBuilder({ editId: storeId(bikeId), onRide: (id) => {
    store.set('bike', id); url.searchParams.set('bike', id); url.searchParams.set('seed', seed); location.replace(url.href);
  } }));
}
function selectBike(id) {   // the rig is built once at load, so a switch reloads into the same world
  if (!isBike(id) || id === bikeId) return;
  store.set('bike', id);
  url.searchParams.set('bike', id); url.searchParams.set('seed', seed);
  location.replace(url.href);
}
{
  const el = document.getElementById('bikes');
  for (const [id, b] of Object.entries(BIKES)) {
    const btn = document.createElement('button');
    btn.textContent = b.label; btn.className = id === bikeId ? 'on' : '';
    btn.addEventListener('click', () => selectBike(id));
    el.appendChild(btn);
  }
  const bb = document.createElement('button');
  bb.textContent = '+ Build'; bb.title = 'U: bike builder';
  bb.addEventListener('click', () => { bb.blur(); openBikeBuilder(); });
  el.appendChild(bb);
  document.getElementById('loading').textContent = `Loading ${BIKES[bikeId].label}…`;
}
const terrain = new Terrain(scene, seed);
terrain.update(0, 0, Infinity);
const debris = new Debris(scene, terrain);
const tapes = new TapeSim(scene, terrain);
water = new Water(terrain, WATER, sunDir);
addSandDetail(MAT.terrain, sunDir, WATER);
scene.add(water.mesh);

// ---------------- bike ----------------
const G = 9.81;
const HOP_PUSH = 0.09;   // s the legs spend straightening before the tyres leave the ground on a bunny hop
const bikeRoot = new THREE.Group(), pitchG = new THREE.Group(), leanG = new THREE.Group();
bikeRoot.add(pitchG); pitchG.add(leanG); scene.add(bikeRoot);

const bike = BIKES[bikeId].cfg ? buildBike(BIKES[bikeId].cfg, 'custom')   // built in the builder
  : (await new GLTFLoader().loadAsync(BIKES[bikeId].file)).scene.getObjectByName(BIKES[bikeId].root);
// wheelbase, wheel radii and BB position from the export (fallbacks: the BMX's)
const bd = bike.userData;
const L = bd.wheelbase || 0.8985, RWF = bd.wheelRadius || 0.261, RWR = bd.wheelRadiusRear || RWF,
  BB_REAR = bd.bbToRearAxle || 0.3331;
leanG.add(bike);
const part = (n) => bike.getObjectByName(n);
const steerN = part('steer'), wheelF = part('wheel_front'), wheelR = part('wheel_rear'), crankN = part('crank');
const steerAxis = new THREE.Vector3(...(bike.userData.steerAxis || [-0.2546, 0.967, 0])).normalize();
// full-suspension bikes (dh.glb): fork + four-bar rear, posed every frame
const susp = bd.suspension ? new Suspension(bike, bd) : null;

const paint = new THREE.MeshPhysicalMaterial({ color: 0xe8432e, metalness: 0.25, roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.06 });
bike.traverse((o) => {
  if (!o.isMesh) return;
  o.castShadow = true; o.receiveShadow = true;
  if (o.material.name === 'paint' && !BIKES[bikeId].cfg) o.material = paint;   // built bikes bring their own colour
  if (o.material.name === 'chrome') { o.material.envMapIntensity = 1.6; }
});

// grips: steer rubber mesh, split by side
const gripL = new THREE.Vector3(), gripR = new THREE.Vector3();
{
  const m = steerN.children.find(o => o.isMesh && o.material.name === 'rubber') || steerN.getObjectsByProperty('isMesh', true).find(o => o.material.name === 'rubber');
  const p = m.geometry.attributes.position; let nl = 0, nr = 0;
  for (let i = 0; i < p.count; i++) {
    const z = p.getZ(i);
    if (z > 0) { gripR.x += p.getX(i); gripR.y += p.getY(i); gripR.z += z; nr++; }
    else { gripL.x += p.getX(i); gripL.y += p.getY(i); gripL.z += z; nl++; }
  }
  gripL.divideScalar(nl); gripR.divideScalar(nr);
}
// pedals: crank plastic mesh -> two level pedal pivots
const pedalPivots = [];
{
  const m = crankN.getObjectsByProperty('isMesh', true).find(o => o.material.name === 'plastic');
  const g = m.geometry, p = g.attributes.position, idx = g.index.array;
  for (const side of [-1, 1]) {
    const list = [], c = new THREE.Vector3(); let n = 0;
    for (let t = 0; t < idx.length; t += 3) {
      const z = (p.getZ(idx[t]) + p.getZ(idx[t + 1]) + p.getZ(idx[t + 2])) / 3;
      if (Math.sign(z) === side) { list.push(idx[t], idx[t + 1], idx[t + 2]); for (let k = 0; k < 3; k++) { c.x += p.getX(idx[t + k]); c.y += p.getY(idx[t + k]); c.z += p.getZ(idx[t + k]); n++; } }
    }
    c.divideScalar(n);
    const sg = new THREE.BufferGeometry();
    sg.setAttribute('position', p); sg.setAttribute('normal', g.attributes.normal);
    sg.setIndex(list);
    const mesh = new THREE.Mesh(sg, m.material); mesh.castShadow = true;
    mesh.position.copy(c).multiplyScalar(-1);
    const pivot = new THREE.Group(); pivot.position.copy(c).add(m.position); pivot.add(mesh);
    crankN.add(pivot); pedalPivots.push(pivot);
    pivot.userData.a0 = Math.atan2(pivot.position.y, pivot.position.x);   // pedal angle at crank = 0
  }
  m.visible = false;
}

const rider = new Rider();
rider.setStyle(BIKES[bikeId].pose || {});
{ // the saddle (frame's plastic mesh): hips stay above it while over it, if the pose asks
  const m = part('frame').getObjectsByProperty('isMesh', true).find(o => o.material.name === 'plastic');
  if (m) { m.geometry.computeBoundingBox(); const b = m.geometry.boundingBox; rider.seat = { top: b.max.y, rear: b.min.x, front: b.max.x }; }
}
leanG.add(rider.group);
{ // the rider's poses are tuned on the BMX (grips at 0.4388 / 0.9646, BB 0.297 up): move the hips
  // by half of how far this bike's grips and BB sit from those
  const grip = gripL.clone().add(gripR).multiplyScalar(0.5).add(steerN.position);
  rider.fit.set((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (crankN.position.y - 0.297)) * 0.5, 0);
}
const ragdoll = new Ragdoll(terrain);

// ---------------- effects: dust smoke, tyre tracks, flying dirt & rock chunks ----------------
const fx = new FX(scene, terrain);
const DUST = new THREE.Color(0xe2d0b4), DUST_DARK = new THREE.Color(0xc9b294), SPLASH = new THREE.Color(0xeef6fa),
  GRASS_DUST = new THREE.Color(0xd2cdb4), DIRT_CHUNK = new THREE.Color(0x7a5534), ROCK_CHUNK = new THREE.Color(0x8d8a84),
  GRASS_CHUNK = new THREE.Color(0x4f8a2e), TRACK_DIRT = new THREE.Color(0x4a3220), TRACK_GRASS = new THREE.Color(0x3d5a22);
const _ev = new THREE.Vector3(), _ep = new THREE.Vector3();
// dust takes the colour of the ground it was kicked up from (paler, since it's airborne powder)
const _gdc = new THREE.Color(), _bdc = new THREE.Color(), _pc = new THREE.Color(), _tc = new THREE.Color(), WHITE = new THREE.Color(1, 1, 1);
function groundDust(x, z, surf, out) {
  if (surf === 2) return out.copy(SPLASH);
  terrain.color(x, z, terrain.height(x, z), 1, out);
  return out.lerp(WHITE, surf === 0 ? 0.42 : 0.28);
}
function emit(pos, vel, col, life = 0.8) { fx.puff(pos, vel, col, 0.3, life * 1.6, 0.45); }
function burst(pos, n, surf, power) {   // landing / crash: ring of smoke + chunks
  if (surf === 2) return;   // water: no dust cloud, no dirt
  const dc = groundDust(pos.x, pos.z, surf, _bdc);
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, r = (0.6 + Math.random()) * power;
    fx.puff(_ep.copy(pos).add(_ev.set(Math.cos(a) * 0.15, 0.05, Math.sin(a) * 0.15)), _ev.set(Math.cos(a) * r, 0.25 + Math.random() * 0.6, Math.sin(a) * r),
      dc, 0.6, 3.4, surf === 1 ? 0.6 : surf === 3 ? 0.5 : 0.3);
    if (i % 2 === 0) fx.chunk(_ep.copy(pos).setY(pos.y + 0.05), _ev.set(Math.cos(a) * r * 0.9, 1.2 + Math.random() * 1.8 * power, Math.sin(a) * r * 0.9),
      surf === 1 ? DIRT_CHUNK : surf === 3 ? _pc.copy(dc).multiplyScalar(0.8) : Math.random() < 0.5 ? GRASS_CHUNK : ROCK_CHUNK, 0.028);
  }
}

// ---------------- input ----------------
const keys = {};
addEventListener('keydown', (e) => {
  keys[e.code] = true;
  if (e.code === 'Space') e.preventDefault();
  if (e.repeat) return;   // held keys auto-repeat: toggles and the world rebuild fire once per press
  if (e.code === 'KeyR') respawn(true);
  if (e.code === 'KeyF' && !crash.on) crash.pending = 'BAIL!';
  // hold Space for half a second to get up; only a press that starts after the crash counts
  if (crash.on && e.code === 'Space') crash.armed = true;
  if (e.code === 'KeyT') { tiltOn = !tiltOn; sizeTilt(); }
  if (e.code === 'KeyU') openBikeBuilder();
  if (e.code === 'KeyB') { const ids = Object.keys(BIKES); selectBike(ids[(ids.indexOf(bikeId) + 1) % ids.length]); }
  if (e.code === 'KeyO') { aoWanted = !aoWanted; gtao.enabled = aoWanted && perf.level < 1; }
});
addEventListener('keyup', (e) => { keys[e.code] = false; });
// window lost focus while a key was held -> the keyup never arrives; release everything
addEventListener('blur', () => { for (const k in keys) keys[k] = false; });
document.addEventListener('visibilitychange', () => { for (const k in keys) keys[k] = false; });
let camDist = 38;   // default view: zoomed-out diorama
// camera orbit: Q/E snap 45 deg, mouse drag = free orbit + tilt
let orbit = 0, orbitT = 0, camPitch = 46, camPitchT = 46, dragging = false, lastX = 0, lastY = 0;
addEventListener('keydown', (e) => {
  if (e.code === 'KeyQ') orbitT -= Math.PI / 4;
  if (e.code === 'KeyE') orbitT += Math.PI / 4;
});
// one pointer = orbit/tilt; two touches = pinch zoom
const touchPts = new Map(); let pinchD = 0;
const pinchDist = () => { const [a, b] = [...touchPts.values()]; return Math.hypot(a.x - b.x, a.y - b.y); };
renderer.domElement.style.touchAction = 'none';
renderer.domElement.addEventListener('pointerdown', (e) => {
  touchPts.set(e.pointerId, { x: e.clientX, y: e.clientY });
  dragging = touchPts.size === 1; lastX = e.clientX; lastY = e.clientY; renderer.domElement.setPointerCapture(e.pointerId);
  if (touchPts.size === 2) pinchD = pinchDist();
});
const ptrEnd = (e) => { touchPts.delete(e.pointerId); dragging = false; if (touchPts.size === 1) { const p = [...touchPts.values()][0]; lastX = p.x; lastY = p.y; dragging = true; } };
renderer.domElement.addEventListener('pointerup', ptrEnd);
renderer.domElement.addEventListener('pointercancel', ptrEnd);
renderer.domElement.addEventListener('pointermove', (e) => {
  if (touchPts.has(e.pointerId)) touchPts.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (touchPts.size === 2) {
    const d = pinchDist();
    if (pinchD > 0 && d > 0) camDist = THREE.MathUtils.clamp(camDist * pinchD / d, 5, 70);
    pinchD = d; return;
  }
  if (!dragging) return;
  orbitT += (e.clientX - lastX) * 0.008;
  camPitchT = THREE.MathUtils.clamp(camPitchT + (e.clientY - lastY) * 0.25, 12, 85);
  lastX = e.clientX; lastY = e.clientY;
});
renderer.domElement.addEventListener('contextmenu', (e) => e.preventDefault());
addEventListener('wheel', (e) => { camDist = THREE.MathUtils.clamp(camDist * (1 + Math.sign(e.deltaY) * 0.1), 5, 70); }, { passive: true });
// ---- camera presets (top dropdown, or C to cycle) ----
const CAM_PRESETS = {
  diorama:   { label: 'Diorama',    dist: 38, pitch: 46, follow: true, fov: 30 },
  close:     { label: 'Close',      dist: 16, pitch: 40, follow: true, fov: 30 },
  chase:     { label: 'Chase',      dist: 7,  pitch: 16, follow: true, fov: 42, rate: 3.2 },
  side:      { label: 'Side',       dist: 14, pitch: 10, follow: true, fov: 28, orbit: Math.PI / 2, rate: 2.5 },
  iso:       { label: 'Isometric',  dist: 34, pitch: 35, follow: false, fov: 28, orbit: Math.PI / 4 },
  top:       { label: 'Top-down',   dist: 34, pitch: 84, follow: false, fov: 30 },
  orbitcam:  { label: 'Slow orbit', dist: 12, pitch: 20, follow: true, fov: 32, spin: 0.2, cine: true },
  drone:     { label: 'Drone',      dist: 22, pitch: 36, follow: true, fov: 34, rate: 0.55, lag: 1.4, drift: true, cine: true },
  trackside: { label: 'Trackside',  mode: 'trackside', fov: 14, cine: true },
  dolly:     { label: 'Low dolly',  dist: 5, pitch: 5, follow: true, fov: 24, orbit: Math.PI * 0.42, rate: 2.8, cine: true },
};
let camMode = 'diorama', camFov = 30, trackPos = null;
function setCam(mode) {
  const P = CAM_PRESETS[mode]; if (!P) return;
  camMode = mode; trackPos = null;
  if (P.mode !== 'trackside') { camDist = P.dist; camPitchT = P.pitch; orbitT = orbit = P.orbit || 0; }
  if (!P.follow && P.mode !== 'trackside') camYaw = 0;           // world-fixed views line up with the map
  const sel = document.getElementById('cam'); if (sel && sel.value !== mode) sel.value = mode;
}
{
  const sel = document.getElementById('cam');
  if (sel) {
    const grp = (label, cine) => {
      const g = document.createElement('optgroup'); g.label = label;
      for (const [k, P] of Object.entries(CAM_PRESETS)) if (!!P.cine === cine) { const o = document.createElement('option'); o.value = k; o.textContent = P.label; g.appendChild(o); }
      sel.appendChild(g);
    };
    grp('Views', false); grp('Cinematic', true);
    sel.value = camMode;
    sel.addEventListener('change', () => { setCam(sel.value); sel.blur(); });
  }
  addEventListener('keydown', (e) => {
    if (e.code !== 'KeyC' || e.repeat || e.target.tagName === 'SELECT') return;
    const ks = Object.keys(CAM_PRESETS); setCam(ks[(ks.indexOf(camMode) + 1) % ks.length]);
    flash(CAM_PRESETS[camMode].label);
  });
}

// ---------------- state ----------------
const st = { x: 0, z: 0, y: 0, vy: 0, heading: 0, v: 0, steer: 0, lean: 0, rock: 0, pitch: 0, hopNose: 0,
  air: false, airTime: 0, airK: 0, compressV: 0, load: 0, leanV: 0, bikeLean: 0, counter: 0, bodyY: 0, wheelF: 0, wheelR: 0, crank: 0, pedal: 0, compress: 0, yawRate: 0, shake: 0 };
// ---------------- crash / ragdoll ----------------
const crash = { on: false, t: 0, pending: null, side: 1, rest: 0, bvy: 0, fallV: 0, armed: false, hold: 0 };
const GETUP_HOLD = 0.5;   // seconds of holding Space to get back on the bike
const bodyVel = new THREE.Vector3(), spinV = new THREE.Vector3();
function startCrash(reason) {
  crash.pending = null;
  if (crash.on) return;
  crash.on = true; crash.t = 0; crash.rest = 0; crash.armed = false; crash.hold = 0;
  // the bike falls to the side it was already leaning (or a random one)
  crash.side = Math.abs(st.bikeLean) > 0.05 ? Math.sign(st.bikeLean) : (Math.random() < 0.5 ? -1 : 1);
  crash.fallV = crash.side * 1.5;
  crash.bvy = st.air ? st.vy : Math.min(st.vy, 0.5);   // grounded: slope speed is not a launch
  const pts = rider.jointsWorld();
  fwd.set(Math.cos(st.heading), 0, -Math.sin(st.heading));
  bodyVel.copy(fwd).multiplyScalar(st.v).add(tmp.set(0, Math.min(Math.max(st.vy, 0), st.air ? 6 : 1) + 1.2, 0));
  // pitched over the bars: upper body gets thrown forward harder than the hips
  spinV.copy(fwd).multiplyScalar(2.2 + Math.abs(st.v) * 0.25);
  // detach the rider into world space
  scene.attach(rider.group);
  rider.group.position.set(0, 0, 0); rider.group.quaternion.identity(); rider.group.scale.set(1, 1, 1);
  ragdoll.start(pts, bodyVel, spinV, 1 / 60);
  rider.poseRagdoll(ragdoll.p);
  st.air = false; st.pedal = 0; st.load = 0; st.shake = 0.45;
  burst(tmp.set(st.x, st.y + 0.05, st.z), 30, terrain.surface(st.x, st.z), 1.5);
  flash(reason);
}
const getupEl = document.getElementById('getup'), getupFill = getupEl.querySelector('.fill');
function getupUI(show, holding, k) {
  getupEl.classList.toggle('show', show);
  getupEl.classList.toggle('holding', holding);
  getupFill.style.transform = `scaleX(${Math.min(1, k)})`;
}
function getUp() {
  crash.on = false; ragdoll.active = false; crash.hold = 0; crash.armed = false;
  getupUI(false, false, 0);
  // pick the bike up where it lies, keep facing the same way
  Object.assign(st, { v: 0, vy: 0, lean: 0, leanV: 0, bikeLean: 0, counter: 0, steer: 0, steerIn: 0, yawRate: 0, air: false,
    pitch: 0, compress: 0, compressV: 0, hopNose: 0, hopT: 0, load: 0,
    slip: 0, wInit: false, frontAir: false, rearAir: false, pumpAcc: 0, pitchV: 0, cF: true, cR: true });
  st.course = st.heading;
  st.hopBlock = true;   // the Space press that got us up must not also pump-pop on release
  st.y = terrain.height(st.x, st.z); st.bodyY = st.y; st.bodyV = 0;
  leanG.add(rider.group);
  rider.group.position.set(0, 0, 0); rider.group.quaternion.identity();
  rider.resetPose();
}
// bike on its own: slides, tips onto its side and comes to rest; the rider tumbles as a ragdoll
function crashPhysics(dt) {
  crash.t += dt;
  fwd.set(Math.cos(st.heading), 0, -Math.sin(st.heading));
  st.v *= Math.exp(-dt * 2.2); if (Math.abs(st.v) < 0.05) st.v = 0;
  st.yawRate *= Math.exp(-dt * 3); st.heading += st.yawRate * dt;
  st.x += fwd.x * st.v * dt; st.z += fwd.z * st.v * dt;
  for (const c of terrain.collidersNear(st.x, st.z)) {
    if (c.top !== undefined && c.top < st.y + 0.45) continue;   // low rock: the bike slides over it
    if (c.tape) continue;   // tape only tears when you ride through it; a sliding bike passes under
    if (c.fence && Math.abs(st.v) > 2 && Math.hypot(st.x - c.x, st.z - c.z) < c.r + 0.35) { smashFence(c, fwd.x * st.v, 0, fwd.z * st.v, st.x, st.y, st.z); continue; }
    const dx = st.x - c.x, dz = st.z - c.z, d = Math.hypot(dx, dz), min = (c.top !== undefined ? c.r : c.r - 0.1) + 0.25;
    if (d < min && d > 1e-4) { st.x = c.x + dx / d * min; st.z = c.z + dz / d * min; st.v *= -0.2; }
  }
  // topple: gravity tips it faster the further it leans; the ground stops it at ~85 deg
  const lim = 1.48;
  crash.fallV += Math.sin(st.bikeLean || crash.side * 0.05) * 14 * dt;
  st.bikeLean += crash.fallV * dt;
  if (Math.abs(st.bikeLean) > lim) { st.bikeLean = Math.sign(st.bikeLean) * lim; crash.fallV *= -0.25; }
  st.counter = 0; st.rock = 0; st.pedal = 0;
  st.steer += (crash.side * 0.5 - st.steer) * Math.min(1, dt * 4);
  const ground = terrain.height(st.x, st.z) + 0.24 * Math.abs(Math.sin(st.bikeLean));
  crash.bvy -= G * dt; st.y += crash.bvy * dt;
  if (st.y < ground) { st.y = ground; crash.bvy = crash.bvy < -2 ? -crash.bvy * 0.25 : 0; }
  const hr = terrain.height(st.x - fwd.x * BB_REAR, st.z - fwd.z * BB_REAR);
  const hf = terrain.height(st.x + fwd.x * (L - BB_REAR), st.z + fwd.z * (L - BB_REAR));
  st.pitch += (Math.atan2(hf - hr, L) - st.pitch) * Math.min(1, dt * 6);
  st.hopNose *= Math.exp(-dt * 4);
  st.wheelF += st.v / RWF * dt; st.wheelR += st.v / RWR * dt;
  st.bodyY = st.y; st.bodyV = 0;
  const P = ragdoll.p[J.PELVIS];
  for (const c of terrain.collidersNear(P.x, P.z)) {   // a tumbling rider goes straight through a fence
    if (c.tape) continue;   // tape only tears when you ride through it
    if (!c.fence || ragdoll.speed < 2.5 || Math.hypot(P.x - c.x, P.z - c.z) > c.r + 0.3 || P.y > terrain.height(P.x, P.z) + 1.4) continue;
    smashFence(c, (P.x - ragdoll.q[J.PELVIS].x) / dt * 3, 0, (P.z - ragdoll.q[J.PELVIS].z) / dt * 3, P.x, P.y - 0.4, P.z);
  }
  ragdoll.step(dt, terrain.collidersNear(P.x, P.z));
  rider.poseRagdoll(ragdoll.p);
  crash.rest = ragdoll.speed < 0.6 ? crash.rest + dt : 0;
  // hold Space to get up; the body stays down until you do
  const holding = crash.armed && keys.Space;
  if (holding) crash.hold += dt; else { crash.armed = false; crash.hold = Math.max(0, crash.hold - dt * 3); }   // let go: bar drains
  getupUI(crash.t > 0.6, holding, crash.hold / GETUP_HOLD);
  if (crash.hold >= GETUP_HOLD) getUp();
}

function respawn(newWorld) {
  if (crash.on) getUp();
  if (newWorld) { seed = (Math.random() * 1e6) | 0; debris.clear(); tapes.clear(); terrain.setSeed(seed); terrain.update(0, 0, Infinity); water.rebake(0, 0, true); }
  fx.clearTracks();
  Object.assign(st, { x: 0, z: 0, v: 0, vy: 0, heading: 0, steer: 0, steerIn: 0, lean: 0, leanV: 0, pitch: 0, air: false,
    bikeLean: 0, counter: 0, rock: 0, yawRate: 0, hopNose: 0, hopT: 0, airTime: 0, airK: 0, load: 0, compress: 0, compressV: 0,
    prep: 0, landPrep: 0, popFired: false, spunOut: false, shake: 0,
    course: 0, slip: 0, wInit: false, frontAir: false, rearAir: false, pumpAcc: 0, sinceLand: 1, pitchV: 0, cF: true, cR: true });
  delete st.gPitch;
  st.y = terrain.height(0, 0); st.bodyY = st.y; st.bodyV = 0;
  rider.resetPose();   // drop the hip / chest spring momentum from before the teleport
}
respawn(false);
window.bmxStep = (dt = 1 / 120) => physics(dt);   // debug: advance the ride physics by hand (tests)
window.renderer = renderer; window.composer = composer; window.gtao = gtao; window.scene = scene; window.bmx = st; window.terrain = terrain; window.bmxKeys = keys; window.rider = rider; window.crash = crash; window.ragdoll = ragdoll; window.fx = fx; window.debris = debris; window.tapes = tapes;   // debug handles

const hud = { msg: document.getElementById('msg') };
const gauge = new Gauge();
let msgT = 0, bestAir = 0;
let biomeT = 0, biomeCur = 'Green Hills', biomeNext = '', biomeHold = 0;
// smash a fence panel: wood splinters, a puff of dust, and the planks become rigid-body debris
const WOOD_CHUNK = new THREE.Color(0xc9a06a), WOOD_DUST = new THREE.Color(0xcdb894);
function smashFence(c, vx, vy, vz, x, y, z) {
  if (!breakFence(c.fence, debris, vx, vy, vz, x, z)) return false;
  const sp = Math.hypot(vx, vz);
  for (let k = 0; k < 10 + sp * 2; k++) fx.chunk(tmp.set(c.x, y + 0.3 + Math.random() * 0.6, c.z),
    tmp2.set(vx * 0.4 + (Math.random() - .5) * 3, 1 + Math.random() * 2.5, vz * 0.4 + (Math.random() - .5) * 3), WOOD_CHUNK, 0.025);
  for (let k = 0; k < 4; k++) fx.puff(tmp.set(c.x, y + 0.4, c.z), tmp2.set((Math.random() - .5) * 1.5, 0.4 + Math.random() * 0.5, (Math.random() - .5) * 1.5), WOOD_DUST, 0.35, 1.4, 0.4);
  return true;
}
// tear through course tape: no real resistance, just a snap and a few shreds
const TAPE_FLECK = new THREE.Color(0xe8322b);
function snapTape(c, vx, vy, vz, x, z, y) {
  if (!tapes.snap(c.tape, x, z, vx, vy, vz)) return false;
  for (let k = 0; k < 5; k++) fx.chunk(tmp.set(c.x, y, c.z), tmp2.set(vx * 0.3 + (Math.random() - .5) * 2, 0.8 + Math.random(), vz * 0.3 + (Math.random() - .5) * 2), k & 1 ? TAPE_FLECK : WOOD_DUST, 0.02, 1.2);
  return true;
}
// smash a cactus: it breaks into its trunk sections and arms, with a spray of green pulp
const CACTUS_PULP = new THREE.Color(0x8fc25a), CACTUS_DUST = new THREE.Color(0xd9c08a);
function smashCactus(c, vx, vy, vz) {
  if (!breakCactus(c.cactus, debris, MAT.leaf, vx, vy, vz)) return false;
  const y = terrain.height(c.x, c.z);
  for (let k = 0; k < 14; k++) fx.chunk(tmp.set(c.x, y + 0.3 + Math.random() * 1.2, c.z),
    tmp2.set(vx * 0.35 + (Math.random() - .5) * 3, 1 + Math.random() * 2.5, vz * 0.35 + (Math.random() - .5) * 3), CACTUS_PULP, 0.028);
  for (let k = 0; k < 3; k++) fx.puff(tmp.set(c.x, y + 0.3, c.z), tmp2.set((Math.random() - .5) * 1.2, 0.4 + Math.random() * 0.4, (Math.random() - .5) * 1.2), CACTUS_DUST, 0.35, 1.3, 0.4);
  return true;
}
function flash(text) { hud.msg.textContent = text; hud.msg.style.opacity = 1; msgT = 1.4; }

const clamp = THREE.MathUtils.clamp;
const smooth01 = (x) => { const t = Math.min(1, Math.max(0, x)); return t * t * (3 - 2 * t); };
const fwd = new THREE.Vector3(), tmp = new THREE.Vector3(), tmp2 = new THREE.Vector3();
const _rear = new THREE.Vector3(), _front = new THREE.Vector3(), _side = new THREE.Vector3(), _g = { y: 0, pitch: 0 };
const footL = new THREE.Vector3(), footR = new THREE.Vector3(), handL = new THREE.Vector3(), handR = new THREE.Vector3();
const camTarget = new THREE.Vector3(0, 0, 0);
let camYaw = 0, t = 0;
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));

function physics(dt) {
  if (crash.pending) startCrash(crash.pending);
  if (crash.on) { crashPhysics(dt); return; }
  const throttle = keys.KeyW || keys.ArrowUp ? 1 : 0;
  const brake = keys.KeyS || keys.ArrowDown ? 1 : 0;
  const steerIn = (keys.KeyA || keys.ArrowLeft ? 1 : 0) - (keys.KeyD || keys.ArrowRight ? 1 : 0);
  fwd.set(Math.cos(st.heading), 0, -Math.sin(st.heading));

  const sample = () => {
    const hr = terrain.height(st.x - fwd.x * BB_REAR, st.z - fwd.z * BB_REAR);
    const hf = terrain.height(st.x + fwd.x * (L - BB_REAR), st.z + fwd.z * (L - BB_REAR));
    _g.hr = hr; _g.hf = hf;
    _g.y = hr + (hf - hr) * (BB_REAR / L); _g.pitch = Math.atan2(hf - hr, L);
    return _g;
  };
  let g = sample();
  const surf = terrain.surface(st.x, st.z);
  const inWater = surf === 2;
  if (st.course === undefined) { st.course = st.heading; st.slip = 0; }
  st.sinceLand = (st.sinceLand ?? 1) + dt;
  // slope the bike sits on: with a wheel off the ground that's the bike's own angle, not the ground's
  const slope = !st.air && (st.frontAir || st.rearAir) ? (st.pitchW ?? g.pitch) : g.pitch;
  const rearDown = !st.air && !st.rearAir;   // the rear tyre is what pedals and brakes
  const skid = brake && st.v > 0.5 && rearDown;
  let aLong = 0;   // how much of the tyres' grip the pedals / brake are using (friction circle)

  // --- longitudinal ---
  if (!st.air) {
    // pedalling like a real rider: strong push from a standstill, then constant POWER (force = P / v),
    // so climbs settle at a decent speed; spinning out above ~38 km/h limits the top speed on the flat
    const vp = Math.max(st.v, 0.5);
    let a = (rearDown ? throttle : 0) * Math.min(T.pedalLaunch, T.pedalPower / vp) * clamp((T.pedalTop - st.v) / 2.5, 0, 1);
    aLong = Math.abs(a);
    a -= G * Math.sin(slope);
    if (brake && rearDown && st.v > 0.3) { a -= T.brakeForce; aLong += T.brakeForce; }
    // PUMPING: legs that extend push the bike into the ground. On a down-slope (the back of a
    // roller, a landing) part of that push points forward = free speed; folding the legs to soak
    // up an up-slope unweights the bike, so the face steals less speed. On the flat it does nothing.
    const pumpOK = !st.frontAir && !st.rearAir && !(st.hopT > 0) && (st.sinceLand ?? 1) > 0.25 && (st.prep || 0) < 0.1 && st.v > 1;
    const aPump = pumpOK ? T.pumpGain * clamp(st.compressV, -2, 2) * -Math.sin(slope) : 0;
    a += aPump;
    if (st.compressV > 0.15 && pumpOK) st.pumpAcc = (st.pumpAcc || 0) + aPump * dt;
    else if (st.compressV <= 0.05) {
      if ((st.pumpAcc || 0) > 0.35 && msgT <= 0) flash(`PUMP +${Math.round(st.pumpAcc * 3.6)} km/h`);
      st.pumpAcc = 0;
    }
    // real cycling losses: small constant rolling resistance (more on grass) + air drag ~ v^2.
    // Pedalling tops out around 37 km/h on the flat, but gravity downhill keeps adding speed.
    const roll = (surf === 0 ? 0.32 : surf === 3 ? 0.42 : 0.1) * Math.sign(st.v) * Math.min(1, Math.abs(st.v) * 4);
    a -= roll + T.airDrag * st.v * Math.abs(st.v);
    if (inWater) a -= 2.5 * st.v;
    st.v = clamp(st.v + a * dt, -3, 24);
    if (brake && st.v <= 0.3) st.v += (-1.3 - st.v) * Math.min(1, dt * 3);   // walk it backwards
    if (!throttle && !brake && Math.abs(st.v) < 0.05 && Math.abs(g.pitch) < 0.03) st.v = 0;
  }
  // spin-out: past the pedal top speed no human can turn the cranks fast enough, so the rider
  // stops pedalling and coasts (pedals level). Picks it back up once the bike slows a bit.
  if (st.v > T.pedalTop + 0.3) st.spunOut = true;
  else if (st.v < T.pedalTop - 0.8) st.spunOut = false;
  st.pedal += ((throttle && !st.air && !st.spunOut ? 1 : 0) - st.pedal) * Math.min(1, dt * 6);

  // --- steering, countersteer and lean ---
  const va = Math.abs(st.v);
  const spdK = smooth01(va / 14);   // 0 = walking pace, 1 = ~50 km/h
  // analog steering input: keys ramp the "stick" in/out instead of slamming it.
  // Snappy (~0.1 s to full) at every speed; letting go recentres fast.
  const inRate = (steerIn !== 0 && Math.sign(steerIn) !== Math.sign(st.steerIn || 0)) ? T.steerRate * 1.5 : T.steerRate;
  const rate = steerIn ? inRate : T.steerRelease;
  st.steerIn = (st.steerIn || 0) + clamp(steerIn - (st.steerIn || 0), -rate * dt, rate * dt);
  const sIn = st.steerIn * (1 - T.steerCurve + T.steerCurve * Math.abs(st.steerIn));   // slightly soft centre, full lock at the end
  // speed-aware turn limit: gentle near-upright turns when slow, up to ~0.7 g (~35 deg lean) when fast
  const aLat = T.turnSlow + spdK * (T.turnFast - T.turnSlow);
  const dMax = Math.min(T.steerMax, Math.max(Math.atan(aLat * L / Math.max(va * va, 0.01)), Math.atan(T.turnFloor * L / Math.max(va, 0.1))));
  const cmd = sIn * dMax;
  const leanNeed = clamp(Math.atan(st.v * (st.v * Math.tan(cmd) / L) / G), -T.leanMax, T.leanMax);
  // gentle countersteer only while tipping INTO a turn; released -> bars centre and the bike stands up
  const tippingIn = steerIn !== 0 && Math.abs(leanNeed) > Math.abs(st.lean) && Math.sign(leanNeed) === steerIn;
  const cMax = Math.abs(cmd) * T.counter;
  // fades out at speed so the bars never hold back a fast turn
  const counter = tippingIn ? clamp((leanNeed - st.lean) * T.counter, -cMax, cMax) * Math.min(1, va / 4) * (1 - spdK) : 0;
  const steerTarget = cmd - counter;
  st.steer += (steerTarget - st.steer) * (1 - Math.exp(-dt * T.barSpeed));
  // --- tyre grip: the bars only turn the bike as hard as the tyres can hold ---
  // course = the direction the bike actually travels; heading = where it points. They differ by the
  // slip angle when a tyre lets go. Grip depends on the surface and on how much of it the pedals or
  // brake are already using; a locked rear (skid) lets the back end come round.
  const muG = (surf === 1 ? 0.95 : surf === 3 ? 0.5 : surf === 2 ? 0.45 : 0.72) * T.grip * G;
  const aGrip = muG * Math.sqrt(Math.max(0.05, 1 - (aLong / muG) ** 2)) * (skid ? 0.75 : 1);
  if (!st.air) {
    const yawCmd = st.frontAir ? 0 : st.v * Math.tan(st.steer) / L;   // front wheel in the air: no steering
    const aLat = clamp(st.v * yawCmd, -aGrip, aGrip);                  // what the tyres actually deliver
    const courseRate = Math.abs(st.v) > 0.3 ? aLat / st.v : yawCmd;
    const excess = yawCmd - courseRate;                                 // rotation the tyres couldn't hold
    const share = skid ? 1 : T.oversteer;                               // rear steps out vs. front pushes wide
    const margin = 1 - Math.min(1, Math.abs(aLat) / aGrip);
    // grip left over pulls the slide back in; steering into the slide (countersteer) catches it faster
    const catchK = T.slipRecover * (0.25 + margin) + Math.max(0, -Math.sign(st.slip) * st.steer) * 8;
    const slipRate = excess * share - st.slip * catchK;
    st.slip = clamp(st.slip + slipRate * dt, -1.5, 1.5);
    st.course += courseRate * dt;
    // nearly stopped: whatever slide is left just becomes the way the bike is pointing (no swivelling on the spot)
    if (Math.abs(st.v) < 1.2) { const k = Math.min(1, dt * 6); st.course += st.slip * k; st.slip -= st.slip * k; }
    st.heading = st.course + st.slip;
    st.yawRate = courseRate + slipRate;
    st.latA = aLat;
    // a sideways tyre scrubs speed; a front tyre pushing wide bleeds a little too
    const scrub = muG * Math.abs(Math.sin(st.slip)) * 0.9 + Math.abs(excess) * (1 - share) * Math.abs(st.v) * 0.15;
    st.v -= Math.sign(st.v) * Math.min(Math.abs(st.v), scrub * dt);
    if (Math.abs(st.slip) > T.slipMax && va > 3) crash.pending = 'WASHED OUT!';
  } else {
    // IN THE AIR there is nothing to push against: the flight path (course) can't change at all.
    // Steering only twists the bike a little relative to it (a slight turn-down / whip), and with
    // the keys released the rider lines it back up with the direction of travel. Whatever angle is
    // left at touchdown becomes slip, so the tyres have to catch it (or it washes out).
    const yawT = steerIn ? steerIn * T.airTurn : -st.slip * 2.5;
    st.yawRate += (yawT - st.yawRate) * Math.min(1, dt * 4);
    st.slip = clamp(st.slip + st.yawRate * dt, -T.airTwist, T.airTwist);
    st.heading = st.course + st.slip;
    st.latA = 0;
  }
  // lean follows the actual cornering force, so it scales with speed: almost upright when slow
  const leanT = st.air ? st.lean * 0.98 : clamp(Math.atan(st.latA / G), -T.leanMax, T.leanMax);
  // near-critically damped spring: quick roll-in/out with a hint of settle
  const kL = steerIn ? T.leanIn : T.leanOut;
  st.leanV += ((leanT - st.lean) * kL - st.leanV * 2 * Math.sqrt(kL) * T.leanDamp) * dt;
  st.lean += st.leanV * dt;
  // lean the BIKE a touch more than the rider; soft-limit so it never flops past ~40 deg
  const bl = st.lean * T.bikeLeanMul;
  st.bikeLean = T.bikeLeanCap * Math.tanh(bl / T.bikeLeanCap);
  st.counter = st.bikeLean - st.lean * 0.85;
  st.rock = Math.sin(st.crank) * 0.065 * st.pedal * Math.min(1, va / 2 + 0.3);

  // --- move ---
  fwd.set(Math.cos(st.heading), 0, -Math.sin(st.heading));
  const px = st.x, pz = st.z, gPrev = terrain.height(px, pz);
  st.x += Math.cos(st.course) * st.v * dt; st.z -= Math.sin(st.course) * st.v * dt;   // along the course, not the heading

  // --- cliff walls: the bike cannot climb a near-vertical face ---
  {
    const step = Math.max(Math.abs(st.v) * dt, 1e-3), gNew = terrain.height(st.x, st.z);
    const wall = st.air ? gNew > st.y + 0.35 : (gNew - gPrev) / step > 1.6 && gNew - gPrev > 0.05;
    if (wall) {
      st.x = px; st.z = pz;
      if (Math.abs(st.v) > 6) crash.pending = 'SMACK! Hit the cliff';
      else { if (Math.abs(st.v) > 1.5) { st.shake = 0.3; flash('BONK!'); } st.v *= -0.25; }
    }
  }

  // --- obstacles ---
  // Collisions are tested where the bike really is: the FRONT TYRE (tight, it hits things first)
  // and the bike's MIDDLE (a slim margin for brushing past side-on). Sizes match what you see.
  const FRONT = L - BB_REAR;
  for (const c of terrain.collidersNear(st.x, st.z)) {
    const fx0 = st.x + fwd.x * FRONT, fz0 = st.z + fwd.z * FRONT;
    const fdx = fx0 - c.x, fdz = fz0 - c.z, fd = Math.hypot(fdx, fdz);
    const cdx = st.x - c.x, cdz = st.z - c.z, cd = Math.hypot(cdx, cdz);
    const fMin = c.r + 0.05, cMin = c.r + 0.16;
    const hitF = fd < fMin, hitC = cd < cMin;
    if (!hitF && !hitC) continue;
    // use whichever point is touching (front tyre first)
    const dx = hitF ? fdx : cdx, dz = hitF ? fdz : cdz, d = Math.max(1e-4, hitF ? fd : cd), min = hitF ? fMin : cMin;
    if (c.cactus && Math.abs(st.v) > 2.5 && !(st.air && st.y > c.ceil)) {   // cacti snap apart at speed (and sting a bit)
      if (smashCactus(c, fwd.x * st.v, st.vy, fwd.z * st.v)) { st.v *= 0.8; st.shake = Math.max(st.shake, 0.35); flash('OUCH! CACTUS!'); }
      continue;
    }
    if (c.tape) {   // course tape: sail over it if high enough, otherwise it snaps (barely slows you)
      if (st.y > c.ceil - 0.25) continue;
      if (snapTape(c, fwd.x * st.v, st.vy, fwd.z * st.v, st.x, st.z, c.ceil - 0.1)) { st.v *= 0.97; if (Math.abs(st.v) > 3) flash('SNAP!'); }
      continue;
    }
    // wooden fences: ride into one with some speed (or land on it) and it smashes -- costs a bit of speed
    if (c.fence && (Math.abs(st.v) > 2.2 || (st.air && st.vy < -2)) && !(st.air && st.y > terrain.height(c.x, c.z) + 1.2)) {
      if (smashFence(c, fwd.x * st.v, st.vy, fwd.z * st.v, st.x, st.y, st.z)) {
        st.v *= 0.86; st.shake = Math.max(st.shake, 0.3); flash(c.fence.style === 'picket' ? 'CRUNCH!' : 'SMASH!');
      }
      continue;
    }
    // rocks never stop you: you ride over them. The wheel rides up the rock and the bike gets
    // bumped up by its height (big rocks cost more speed). Trees and cacti (no height) still block.
    if (c.top !== undefined) {
      const clear = c.top - st.y;                       // how far the rock sticks up above the wheels
      if (clear < 0.04 || st.air) continue;             // already above it / flying over it
      if ((fwd.x * dx + fwd.z * dz) / d >= 0) continue;   // rolling off the back of it
      if (Math.abs(st.v) > 0.3) {
        st.air = true; st.airTime = 0;
        st.vy = Math.max(st.vy, Math.sqrt(2 * G * (clear + 0.05)) + 0.2); st.kickT = 0.3;
        st.hopNose = 0.1 + Math.min(0.35, clear * 0.5);
        st.v *= 1 - Math.min(0.35, clear * 0.3);
        st.shake = Math.max(st.shake, Math.min(0.2, clear * 0.25));
        for (let k = 0; k < 3 + clear * 8; k++) fx.chunk(tmp.set(c.x, c.top, c.z), tmp2.set((Math.random() - .5) * 2, 1 + Math.random(), (Math.random() - .5) * 2), ROCK_CHUNK, 0.02);
      }
      continue;
    }
    // flying higher than the obstacle: sail over it. Trees and cacti carry their real height (ceil);
    // anything else gets a sensible default from the ground under it (fences ~1.2 m, sheds etc ~3.2 m)
    if (st.air) {
      const ceil = c.ceil !== undefined ? c.ceil : terrain.height(c.x, c.z) + (c.fence ? 1.2 : 3.2);
      if (st.y > ceil) continue;
    }
    // push the bike back just far enough that the touching point sits on the trunk's surface
    const push = (min - d) / d;
    st.x += dx * push; st.z += dz * push;
    // over the bars only on a real head-on hit: closing speed toward the trunk > 6 m/s (~22 km/h)
    // and within ~40 deg of dead ahead -- clipping a tree while carving past it just glances off
    if ((fwd.x * dx + fwd.z * dz) / d < -0.77 && -st.v * (fwd.x * dx + fwd.z * dz) / d > 6) { crash.pending = 'BONK! Over the bars'; }
    else if ((fwd.x * dx + fwd.z * dz) / d < -0.3 && st.v > 1.5) { burst(tmp.set(fx0, st.y + 0.3, fz0), 16, 0, 1.2); st.v *= -0.25; st.shake = 0.35; flash('BONK!'); }
    else st.v *= 0.97;
  }

  // --- vertical + pitch: SPRING PHYSICS ---
  // Bike + rider are one rigid body in the travel plane: height y (at the BB, on the line through
  // the tyre contacts), pitch, and both their velocities. Each tyre sits on a spring-damper (tyre,
  // fork / frame and the give in the rider's arms) that can only PUSH. Roll over a bump and it
  // compresses, then gives that energy back: at speed the bike skips off sharp bumps and rebounds a
  // little on landings. The ground falling away faster than gravity can follow lifts a wheel off on
  // its own -- no special take-off rules. Past the end of travel a spring bottoms out (a dead stop),
  // so big landings are soaked, not trampolined.
  g = sample();
  {
    // running into a steeper slope (a concave corner) bleeds speed into the face
    const dP = g.pitch - (st.gPitch ?? g.pitch);
    if (!st.air && dP > 0.02 && st.v > 0) st.v *= Math.cos(Math.min(dP, 1.2));
    st.gPitch = g.pitch;
    const natural = terrain.jump(st.x, st.z)[1] < 0.05;   // not on a built jump
    // a face steeper than ~37 deg ridden just before (a step, a ledge) is rolled up and over: small pop at most
    st.faceMax = Math.max(Math.tan(clamp(g.pitch, -1.4, 1.4)), (st.faceMax ?? 0) * Math.exp(-dt * 3));
    const isStep = st.faceMax > 0.75;
    // hills are noise, not ramps: a natural crest may throw you this hard at most (built jumps: their face)
    const launchCap = natural ? T.crestCap : isStep ? 2 : Math.abs(st.v) * 0.62 + 0.3;
    // fastest the ground under a rolling tyre can really rise: a ~42 deg face at this speed. A step 30 cm
    // high in one frame is NOT 37 m/s upward -- that is what used to shoot the bike skyward off ledges
    const climbMax = Math.abs(st.v) * 0.9 + 0.3;
    if (!st.wInit || st.hfPrev === undefined) { st.hfPrev = g.hf; st.hrPrev = g.hr; st.pitchV = 0; st.wInit = true; }
    const hfP = st.hfPrev, hrP = st.hrPrev;
    const vgF = Math.min((g.hf - hfP) / dt, climbMax), vgR = Math.min((g.hr - hrP) / dt, climbMax);
    st.hfPrev = g.hf; st.hrPrev = g.hr;

    const XF = L - BB_REAR, XR = -BB_REAR, shF = BB_REAR / L, shR = XF / L;   // weight split by lever arms
    const K = (2 * Math.PI * T.tyreHz) ** 2, C = 2 * T.tyreDamp * Math.sqrt(K);  // per unit mass: heave at tyreHz
    const IK = 0.22;                                  // pitch inertia / mass (m^2): bike + rider about the BB
    // the rider keeps a little weight pressed into natural ground (not on jumps, not while hopping)
    const press = natural && !(st.hopT > 0) ? T.legPress * G : 0;
    const s0 = (G + press) / K;                       // static sag: at rest the contact line sits on the ground
    const TRAVEL = T.travel;
    const balMax = T.riderBalance * G * BB_REAR / IK; // how hard the rider can shift weight to hold a wheelie / nose
    const wasAir = st.air, vyIn = st.vy, wasF = st.cF ?? true, wasR = st.cR ?? true;
    let cF = false, cR = false;
    const N = 4, h = dt / N;
    for (let i = 1; i <= N; i++) {
      const u = i / N, gF = hfP + (g.hf - hfP) * u, gR = hrP + (g.hr - hrP) * u;
      const cs = Math.cos(st.pitch), sn = Math.sin(st.pitch);
      const dF = gF - (st.y + XF * sn) + s0, dR = gR - (st.y + XR * sn) + s0;   // spring compression
      const pvF = st.vy + XF * cs * st.pitchV, pvR = st.vy + XR * cs * st.pitchV;
      cF = dF > 0; cR = dR > 0;
      const FF = cF ? Math.max(0, shF * (K * dF + C * (vgF - pvF))) : 0;   // springs only push
      const FR = cR ? Math.max(0, shR * (K * dR + C * (vgR - pvR))) : 0;
      let alpha = (FF * XF + FR * XR) * cs / IK;
      if (cF !== cR) {
        // one wheel down: the rider shifts weight to hold the bike near the slope it was on
        const ref = st.noseRef ?? g.pitch;
        alpha += clamp(30 * (ref - st.pitch) - 9 * st.pitchV, -balMax, balMax);
      } else if (!cF) {
        // flying: follow the flight path, then bring the bike in to match the landing slope
        const flight = 0.6 * Math.atan2(st.vy, Math.max(st.v, 1));
        const near = 1 - smooth01((st.y - g.y) / 0.7);
        const pT = flight + (g.pitch - flight) * near * (st.vy < 0 ? 1 : 0);
        alpha += 20 * (pT - st.pitch) - 7 * st.pitchV;
      }
      st.vy += (FF + FR - G - (cF || cR ? press : 0)) * h;
      st.pitchV += alpha * h;
      st.y += st.vy * h; st.pitch += st.pitchV * h;
      // BOTTOM-OUT: the end of travel is a hard stop (inelastic contact on that wheel)
      for (const [x, gg, vg] of [[XF, gF, vgF], [XR, gR, vgR]]) {
        const c2 = Math.cos(st.pitch), d = gg - (st.y + x * Math.sin(st.pitch)) - TRAVEL;   // compression past s0 + TRAVEL
        if (d <= 0) continue;
        const lx = x * c2, mInv = 1 + lx * lx / IK;
        const dq = d / mInv; st.y += dq; st.pitch += dq * lx / IK;
        const vp = st.vy + lx * st.pitchV;
        if (vp < vg) { const j = (vg - vp) / mInv; st.vy += j; st.pitchV += j * lx / IK; }
        if (x === XF) cF = true; else cR = true;
      }
    }
    const air = !cF && !cR;
    st.frontAir = !air && !cF; st.rearAir = !air && !cR;
    // the slope we were riding when the front went over a ledge / the rear came up
    if (!air && (st.frontAir || st.rearAir) && wasF && wasR) st.noseRef = g.pitch - dP;
    if (st.frontAir && st.pitch - (st.noseRef ?? g.pitch) < -T.noseDive) crash.pending = 'NOSE DIVE!';
    // where each tyre is (for the suspension rig): on its ground when touching
    const snN = Math.sin(st.pitch);
    st.wF = cF ? g.hf : st.y + XF * snN; st.wR = cR ? g.hr : st.y + XR * snN;
    st.pitchW = st.pitch;
    // WHERE TO DRAW THE FRAME. A rigid BMX is drawn with its tyres on the ground (the springs are the tyres
    // and the rider's arms and legs: the body shows the give, see absorb). The downhill bike's frame rides
    // at its physical height and its fork / linkage rig pushes the wheels down onto the ground.
    if (susp) { st.yDraw = st.y; st.pitchDraw = st.pitch; }
    else { st.yDraw = st.wR + (st.wF - st.wR) * (BB_REAR / L); st.pitchDraw = Math.atan2(st.wF - st.wR, L); }
    // front tyre slapping back down after a ledge / manual
    if (!wasAir && !air && !wasF && cF) {
      const slap = Math.max(0, vgF - (vyIn + XF * Math.cos(st.pitch) * st.pitchV));
      if (slap > 2) {
        st.shake = Math.max(st.shake, Math.min(0.25, slap * 0.05)); st.compressV -= Math.min(1.5, slap * 0.25);
        if (slap > 3.5) burst(tmp.set(st.x + fwd.x * XF, g.hf + 0.03, st.z + fwd.z * XF), 10, surf, 0.8);
      }
    }
    st.cF = cF; st.cR = cR;
    if (air && !wasAir) {   // TAKE-OFF
      st.air = true; st.airTime = 0;
      if (!(st.kickT > 0)) st.vy = Math.min(st.vy, launchCap);
      if (!natural && !isStep) st.vy += T.autoPop * (st.prep || 0);   // the rider pumped the face: extra pop off the lip
    } else if (!air && wasAir) {   // TOUCH-DOWN: the springs take it from here; judge how hard it was
      // impact = how much of our fall the landing slope doesn't "catch" (smooth on a down-ramp, harsh on flat)
      const vySurf = st.v * Math.tan(g.pitch);
      const impact = Math.max(0, vySurf - vyIn) * Math.cos(g.pitch) / (LAND * (1 + T.landSoak * (st.landPrep || 0)));
      const airTime = st.airTime;
      // a drop too big for the legs to absorb throws you off
      if (airTime > 0.3 && impact > 10.5) crash.pending = 'SLAM!';
      st.air = false; st.sinceLand = 0;
      st.bodyV = vyIn;   // hips are still falling: the extended legs now absorb it
      st.noseRef = g.pitch;
      if (impact > 3) st.v *= 1 - Math.min(0.45, (impact - 3) * 0.08);   // cased it / flat landing scrubs speed
      if (impact > 5 && airTime > 0.3) flash('OOF!');
      st.compressV -= Math.min(2.2, impact * 0.35);
      if (susp) susp.land(Math.max(0, -vyIn) * Math.cos(g.pitch) * 0.5 + impact * 0.4, st.frontAir, st.rearAir);
      if (airTime > 0.15) st.shake = Math.max(st.shake, Math.min(0.2, impact * 0.025));
      if (airTime > 0.15) burst(tmp.set(st.x, st.y + 0.03, st.z), Math.round(10 + Math.min(30, impact * 6)), surf, 0.8 + Math.min(1.5, impact * 0.25));
      if (airTime > 0.45) { bestAir = Math.max(bestAir, airTime); flash(`AIR ${airTime.toFixed(2)}s${airTime >= bestAir ? '  ★ best' : ''}`); }
    }
    if (st.air) st.airTime += dt;
    st.kickT = Math.max(0, (st.kickT || 0) - dt);
  }
  // PUMP: hold Space to load (crouch), release to pop. Pop at the lip = big air.
  if (st.hopBlock && !keys.Space) st.hopBlock = false;
  const space = keys.Space && !st.hopBlock;
  if (!st.air && space) st.load = Math.min(1, st.load + dt * 3.5);
  // the hop happens in two beats like a real one: first the rider explodes up out of the crouch
  // with the tyres still on the ground (legs straighten, nose starts to lift), THEN the bike is
  // yanked off the ground and tucked up under the body.
  // letting go on the BACK of a built roller / landing is a pump (legs push the bike down the slope,
  // see PUMPING above), not a hop -- so a rhythm section can be pumped with Space alone
  const backside = !st.air && g.pitch < -0.06 && terrain.jump(st.x, st.z)[1] > 0.05;
  if (!space && st._hopHeld && !st.air && st.load > 0.15 && !(st.hopT > 0) && !backside) {
    st.hopT = HOP_PUSH; st.hopLoad = st.load;
    st.compressV = Math.max(st.compressV, (0.05 - st.compress) / HOP_PUSH);   // straighten out of the crouch
    st.bodyV = st.vy + (T.legExt - Math.min(0, (st.bodyY ?? st.y) - st.y)) / HOP_PUSH;   // hips drive up first
  }
  if (st.hopT > 0) {
    st.hopT -= dt;
    const k = 1 - Math.max(0, st.hopT) / HOP_PUSH;
    st.hopNose = Math.max(st.hopNose, (0.22 + 0.15 * st.hopLoad) * 0.6 * k);   // front wheel comes up as the arms pull
    if (st.hopT <= 0 || st.air) {   // legs are straight (or a lip already threw us): bike leaves the ground
      st.hopT = 0;
      st.vy = Math.max(st.vy, 0) + 1.4 + T.popPower * st.hopLoad;   // the springs unload and the tyres leave on their own
      st.kickT = 0.3;   // a rider's hop is not a crest launch: no cap
      st.hopNose = 0.22 + 0.15 * st.hopLoad;
    }
  }
  if (!space || st.air) st.load = Math.max(0, st.load - dt * 6);
  st._hopHeld = space;
  st.hopNose *= Math.exp(-dt * 3.5);
  // --- rider reads the trail like a real one: spots a lip ahead, sinks into the transition,
  // pumps up the face and pops at the top; in the air tucks, then reaches the bike down
  // for the landing so the legs have their full travel to soak it up ---
  let lipT = Infinity;
  if (!st.air && st.v > 3) {
    const step = 0.3, n = Math.min(36, Math.ceil(st.v * (T.prepTime + 0.1) / step));
    let hPrev = terrain.height(st.x, st.z), sPrev = null;
    for (let i = 1; i <= n; i++) {
      const d = i * step, x = st.x + fwd.x * d, z = st.z + fwd.z * d, h = terrain.height(x, z);
      const sl = (h - hPrev) / step;
      // a crest sharp enough to throw us at this speed, on a built jump
      if (sPrev !== null && sPrev > 0.15 && (sPrev - sl) * st.v * st.v / step > 2.5 * G && terrain.jump(x, z)[1] > 0.05) { lipT = (d - step) / st.v; break; }
      sPrev = sl; hPrev = h;
    }
  }
  const prepT = lipT < T.prepTime ? smooth01(1 - lipT / T.prepTime) : 0;
  st.prep = st.air ? Math.max(0, (st.prep || 0) - dt * 4) : (st.prep || 0) + (prepT - (st.prep || 0)) * Math.min(1, dt * 8);
  const popping = lipT < 0.14;                    // last instant before the lip: extend hard
  if (popping && !st.popFired) { st.popFired = true; st.bodyV = (st.bodyV ?? 0) + T.popKick * st.prep; st.compressV += 2.5 * st.prep; }
  if (!st.air && lipT === Infinity) st.popFired = false;
  // in the air: time to touchdown -> landing prep 0..1
  let landPrep = 0, tuck = 0;
  if (st.air) {
    const h = Math.max(0, st.y - g.y);
    const tg = (st.vy + Math.sqrt(st.vy * st.vy + 2 * G * h)) / G;
    landPrep = st.vy < 0 ? smooth01(1 - tg / T.landPrepTime) : 0;
    tuck = smooth01((st.airTime - 0.08) / 0.2) * (1 - landPrep);
  }
  st.landPrep = landPrep;
  // damped spring for the crouch: pump-loading, approach crouch, air tuck; landing dip comes from impact
  const cT = st.air ? -0.12 * tuck : popping || st.hopT > 0 ? 0.05 : -0.17 * st.load - T.prepDepth * st.prep;
  st.compressV += ((cT - st.compress) * 120 - st.compressV * 14) * dt;
  st.compress = clamp(st.compress + st.compressV * dt, -0.28, 0.05);
  st.airK += ((st.air && st.airTime > 0.12 ? 1 : 0) - st.airK) * Math.min(1, dt * 6);
  // --- suspension: soaks the ground under each tyre that the body line misses ---
  if (susp) {
    const sp = Math.sin(st.pitch);
    susp.update(dt, { air: st.air, load: Math.max(st.load, -st.compress * 2.5), brake: brake && !st.air ? 1 : 0,
      bumpF: st.air ? 0 : st.wF - (st.y + (L - BB_REAR) * sp), bumpR: st.air ? 0 : st.wR - (st.y - BB_REAR * sp) });
  }

  // --- wheels / cranks ---
  const w = st.v / RWF;
  st.wheelF += w * dt;
  if (!skid) st.wheelR += st.v / RWR * dt;
  if (st.pedal > 0.05) st.crank += Math.max(w / 2.78, 3.5) * st.pedal * dt;
  else if (!st.air) {
    // coasting: outside pedal down in a turn, level pedals on the straight
    const aL = pedalPivots[0].userData.a0, aR = pedalPivots[1].userData.a0;
    let tgt, period = Math.PI * 2;
    if (st.lean > 0.12) tgt = aR + Math.PI / 2;          // turning left -> right (outside) foot down
    else if (st.lean < -0.12) tgt = aL + Math.PI / 2;    // turning right -> left foot down
    else { tgt = aL; period = Math.PI; }                 // level
    tgt += period * Math.round((st.crank - tgt) / period);
    st.crank += (tgt - st.crank) * Math.min(1, dt * 3.5);
  }
  // springy legs: the hips are a mass on a soft, under-damped spring (the legs). The bike
  // chatters up and down underneath while the hips float on their own momentum; legs
  // compress/extend to make up the difference and bottom out at the end of their travel.
  if (st.air) {   // flying: body rides with the bike; legs extend to reach for the landing
    // body height relative to the bike as it was LAST frame (measuring against this frame's y made
    // the hips lag the bike on take-off, so the legs folded up as if the bike floated out from under them)
    const relT = T.legExt * landPrep;
    const rel = (st.bodyY ?? st.y) - (st.yPrev ?? st.y);
    st.bodyY = st.y + rel + (relT - rel) * (1 - Math.exp(-dt * 12)); st.bodyV = st.vy;
  }
  else {
    const kB = T.legStiff, cB = 2 * Math.sqrt(kB) * T.legDamp;   // default ~0.9 Hz, soft with a little bounce
    st.bodyV = (st.bodyV ?? st.vy) + ((st.y - st.bodyY) * kB - ((st.bodyV ?? st.vy) - st.vy) * cB) * dt;
    st.bodyY += st.bodyV * dt;
    const rel = st.bodyY - st.y, LEG_COMP = T.legComp, LEG_EXT = T.legExt;                    // + = legs extended above ride height, - = compressed
    if (rel < -LEG_COMP) { st.bodyY = st.y - LEG_COMP; st.bodyV = Math.max(st.bodyV, st.vy); }   // bottomed out
    else if (rel > LEG_EXT) { st.bodyY = st.y + LEG_EXT; st.bodyV = Math.min(st.bodyV, st.vy); }  // legs straight
  }
  st.yPrev = st.y;

  // --- dust smoke, flying dirt, tyre tracks ---
  const rear = _rear.set(st.x - fwd.x * BB_REAR, st.y + 0.03, st.z - fwd.z * BB_REAR);
  const front = _front.set(st.x + fwd.x * (L - BB_REAR), st.y + 0.03, st.z + fwd.z * (L - BB_REAR));
  const dcol = groundDust(rear.x, rear.z, surf, _gdc), sand = surf === 3;
  const skidFx = skid || (!st.air && Math.abs(st.slip) > 0.1 && va > 1.5);   // locked rear OR a tyre sliding sideways
  if (!st.air && va > 0.6) {
    const dirt = surf === 1, side = _side.set(-fwd.z, 0, fwd.x);   // rider's right
    // cornering: lateral acceleration (v * yaw rate) decides how hard the tyre throws dirt to the OUTSIDE
    const latA = Math.abs(st.v * st.yawRate), turnDir = Math.sign(st.yawRate);   // +1 left turn -> throw right
    const carveK = clamp((latA - 1.5) / 6, 0, 1);
    const carve = carveK > 0.05;
    // smoke: always a little on dirt, lots when skidding, carving or sprinting
    st.dustAcc = (st.dustAcc || 0) + dt * (inWater ? 0 : dirt ? 6 + va * 2.2 + (skidFx ? 50 : 0) + carveK * 60 + st.pedal * (va < 7 ? 10 : 0)   // water: no smoke at all
                                                       : sand ? 4 + va * 1.8 + (skidFx ? 40 : 0) + carveK * 45 + st.pedal * (va < 7 ? 6 : 0)
                                                       : (skidFx ? 14 : 0) + va * 0.8 + carveK * 12);
    while (st.dustAcc > 1) {
      st.dustAcc -= 1;
      // in a turn the cloud is flung sideways, out of the corner; on the straight it fans out behind
      const out = turnDir * carveK * (2 + Math.random() * 3);
      const fan = (Math.random() - .5) * (1.6 + va * 0.18) * (1 - carveK * 0.6);
      const back = va * 0.3 * (1 - carveK * 0.55);
      _ev.set(-fwd.x * back + side.x * (out + fan), 0.35 + Math.random() * 0.7 + carveK * 0.4,
              -fwd.z * back + side.z * (out + fan));
      fx.puff(rear, _ev, _pc.copy(dcol).multiplyScalar(Math.random() < 0.3 ? 0.86 : 1),
        skidFx ? 0.5 : 0.4, 3.2, dirt ? (skidFx ? 0.62 : 0.45) : sand ? (skidFx ? 0.55 : 0.4) : 0.26);
    }
    // roost: dirt and little rocks flicked off the back wheel
    if (!inWater) {
      st.chunkAcc = (st.chunkAcc || 0) + dt * (dirt ? (skidFx ? 30 : 0) + carveK * 28 + st.pedal * (va < 8 ? 9 : 2)
                                             : sand ? (skidFx ? 18 : 0) + carveK * 16 + st.pedal * (va < 8 ? 4 : 1) : skidFx ? 6 : 0);
      while (st.chunkAcc > 1) {
        st.chunkAcc -= 1;
        const out = carve ? turnDir * carveK * (2.5 + Math.random() * 3.5) : (Math.random() - .5) * 1.2;
        const back = (1.5 + va * 0.35) * (1 - carveK * 0.6);
        _ev.set(-fwd.x * back + side.x * out, 1 + Math.random() * 2.2, -fwd.z * back + side.z * out);
        fx.chunk(rear, _ev, dirt ? (Math.random() < 0.7 ? DIRT_CHUNK : ROCK_CHUNK) : sand ? _pc.copy(dcol).multiplyScalar(0.8) : GRASS_CHUNK, 0.022);
      }
    }
  }
  // tyre tracks (break in the air and in water); darker when the rear wheel is locked
  const onGround = !st.air && !inWater && va > 0.2;
  const tc = surf === 1 ? TRACK_DIRT : sand ? _tc.copy(dcol).multiplyScalar(0.6) : TRACK_GRASS, ta = surf === 1 ? 0.6 : sand ? 0.5 : 0.3;
  fx.track(0, front, fwd, onGround ? ta : 0, tc, 0.06);
  fx.track(1, rear, fwd, onGround ? (skidFx ? Math.min(0.85, ta + 0.35) : ta) : 0, tc, skidFx ? 0.08 : 0.065);
}

function place() {
  const yDraw = crash.on ? st.y : st.yDraw ?? st.y, pDraw = crash.on ? st.pitch : st.pitchDraw ?? st.pitch;
  bikeRoot.position.set(st.x, yDraw, st.z);
  bikeRoot.rotation.y = st.heading;
  pitchG.rotation.z = pDraw + st.hopNose;
  const wobble = Math.sin(t * 2.3) * 0.025 * Math.max(0, 1 - Math.abs(st.v) / 2);
  leanG.rotation.x = -(st.bikeLean + st.rock + wobble);
  steerN.quaternion.setFromAxisAngle(steerAxis, st.steer + wobble * -1.5);
  wheelF.rotation.z = -st.wheelF;
  wheelR.rotation.z = -st.wheelR;
  crankN.rotation.z = -st.crank;
  for (const p of pedalPivots) p.rotation.z = st.crank;
  if (susp) susp.apply();
  bikeRoot.updateMatrixWorld(true);

  const toLean = (obj, v, out) => leanG.worldToLocal(obj.localToWorld(out.copy(v)));
  toLean(steerN, gripL, handL); toLean(steerN, gripR, handR);
  pedalPivots[0].getWorldPosition(footL); leanG.worldToLocal(footL);
  pedalPivots[1].getWorldPosition(footR); leanG.worldToLocal(footR);
}

function updateCamera(dt) {
  const P = CAM_PRESETS[camMode];
  fwd.set(Math.cos(st.heading), 0, -Math.sin(st.heading));
  const want = crash.on ? tmp.copy(ragdoll.p[J.PELVIS]).lerp(tmp2.set(st.x, st.y, st.z), 0.3).add(tmp2.set(0, 0.3, 0))
    : tmp.set(st.x, st.y + 0.5, st.z).addScaledVector(fwd, clamp(st.v, -1, 10) * (P.mode === 'trackside' ? 0.05 : 0.25));
  camTarget.lerp(want, Math.min(1, dt * (P.lag || 5)));
  let fovT = P.fov;
  if (P.mode === 'trackside') {
    // broadcast-style: a long lens planted beside the track ahead; pan as the rider passes, then cut
    const side = tmp2.set(-fwd.z, 0, fwd.x);
    const rel = trackPos ? (st.x - trackPos.x) * fwd.x + (st.z - trackPos.z) * fwd.z : 0;
    const far = trackPos ? Math.hypot(st.x - trackPos.x, st.z - trackPos.z) : 1e9;
    if (!trackPos || rel > 9 || far > 38) {
      const sgn = Math.random() < 0.5 ? -1 : 1, ahead = 18 + Math.random() * 8, off = 5 + Math.random() * 5;
      const x = st.x + fwd.x * ahead + side.x * off * sgn, z = st.z + fwd.z * ahead + side.z * off * sgn;
      trackPos = new THREE.Vector3(x, terrain.height(x, z) + 1.2 + Math.random() * 1.6, z);
    }
    camera.position.copy(trackPos);
    const d = camera.position.distanceTo(camTarget);
    fovT = clamp(THREE.MathUtils.radToDeg(2 * Math.atan(2.2 / d)), 7, 40);   // keep the rider framed the same size
    camDist = d;
  } else {
    // follow your turning: swing round behind the bike (lazily, so turns still read)
    if (P.follow && Math.abs(st.v) > 0.5) camYaw += angDiff(st.heading, camYaw) * Math.min(1, dt * (P.rate || 1.4) * Math.min(1, Math.abs(st.v) / 4));
    if (P.spin) orbitT += P.spin * dt;
    orbit += (orbitT - orbit) * Math.min(1, dt * 8);
    camPitch += (camPitchT - camPitch) * Math.min(1, dt * 8);
    let yaw = camYaw + orbit, pit = camPitch;
    if (P.drift) { yaw += Math.sin(t * 0.13) * 0.35; pit += Math.sin(t * 0.09) * 5; }   // drone sway
    const pitch = THREE.MathUtils.degToRad(pit);
    const back = tmp2.set(Math.cos(yaw), 0, -Math.sin(yaw));
    camera.position.copy(camTarget)
      .addScaledVector(back, -camDist * Math.cos(pitch))
      .add(tmp.set(0, camDist * Math.sin(pitch), 0));
    // never dip under the ground on low shots
    const gh = terrain.height(camera.position.x, camera.position.z) + 0.35;
    if (camera.position.y < gh) camera.position.y = gh;
  }
  camFov += (fovT - camFov) * Math.min(1, dt * (P.mode === 'trackside' ? 6 : 3));
  if (Math.abs(camera.fov - camFov) > 0.01) { camera.fov = camFov; camera.updateProjectionMatrix(); }
  if (st.shake > 0) {
    camera.position.x += Math.sin(t * 37) * st.shake * 0.12;
    camera.position.y += Math.sin(t * 29 + 1) * st.shake * 0.12;
    st.shake = Math.max(0, st.shake - dt * 1.2);
  }
  camera.lookAt(camTarget);
  // keep fog and the shadow box sized to the zoom level
  scene.fog.near = camDist + 26; scene.fog.far = camDist * 1.6 + 70;
  const sh = THREE.MathUtils.clamp(camDist * 1.3, 16, 60), sc = sun.shadow.camera;
  if (sc.right !== sh) { sc.left = sc.bottom = -sh; sc.right = sc.top = sh; sc.updateProjectionMatrix(); }
  // sun & shadow follow the rider (snapped to texels to stop shimmering)
  const step = (sun.shadow.camera.right * 2) / sun.shadow.mapSize.x;
  const sx = Math.round(st.x / step) * step, sz = Math.round(st.z / step) * step;
  sun.target.position.set(sx, st.y, sz);
  sun.position.set(sx, st.y, sz).addScaledVector(sunDir, 45);
  water.update(st.x, st.z, t);
}

const lastGood = { ...st };   // the spawn state, so even a first-frame blow-up has something to restore
const clock = new THREE.Clock();
document.getElementById('loading').remove();
buildTunePanel();
buildPosePanel({ bikeId, bikeLabel: BIKES[bikeId].label, defaults: BIKES[bikeId].pose || {},   // K: rider position sliders
  apply: (s) => rider.setStyle(s), sideView: () => { setCam('side'); flash('Side view'); } });
buildTouchControls();
// ---------------- FPS meter + automatic quality fallback ----------------
const fpsEl = document.getElementById('fps');
const perf = { frames: 0, acc: 0, worst: 0, last: performance.now(), bad: 0, level: 0, warm: 3 };
// quality levels: 0 full, 1 no AO, 2 + 1x pixel ratio, 3 + no bloom / hard shadows.
// Auto mode only ever steps down; G cycles levels by hand (and turns auto off).
const MAX_Q = 3, DPR = Math.min(devicePixelRatio, 2);
let autoQ = true;
function applyQuality(l) {
  perf.level = l;
  gtao.enabled = l < 1 && aoWanted;
  const pr = l < 2 ? DPR : 1;
  if (renderer.getPixelRatio() !== pr) { renderer.setPixelRatio(pr); composer.setPixelRatio(pr); composer.setSize(innerWidth, innerHeight); }
  bloom.enabled = l < 3;
  const sm = l < 3 ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;
  if (renderer.shadowMap.type !== sm) { renderer.shadowMap.type = sm; renderer.shadowMap.needsUpdate = true; }
}
// phones: start without AO; auto-fallback can still step further down
if (IS_TOUCH) applyQuality(1);
addEventListener('keydown', (e) => { if (e.code === 'KeyG' && !e.repeat) { autoQ = false; applyQuality((perf.level + 1) % (MAX_Q + 1)); perf.acc = 1e9; } });
function meter(now) {
  const ms = now - perf.last; perf.last = now;
  if (ms > 250 || document.hidden) return;   // tab was hidden / debugger pause: don't count it
  perf.frames++; perf.acc += ms; if (ms > perf.worst) perf.worst = ms;
  if (perf.acc < 500) return;
  if (perf.acc > 1e8) { perf.acc = ms; perf.frames = 1; }   // forced refresh after a manual change
  const fps = perf.frames * 1000 / perf.acc;
  fpsEl.textContent = `${fps.toFixed(0)} FPS · ${(perf.acc / perf.frames).toFixed(1)} ms · max ${perf.worst.toFixed(0)} · Q${MAX_Q - perf.level}${autoQ ? ' auto' : ''}`;
  fpsEl.style.color = fps >= 55 ? '#b9ffb0' : fps >= 40 ? '#ffe38a' : '#ff9a8a';
  // sustained low frame rate (~3 s, after the warm-up) -> drop one quality step
  if (perf.warm > 0) perf.warm -= perf.acc / 1000;
  else if (autoQ && fps < 45 && perf.level < MAX_Q) { if (++perf.bad >= 6) { applyQuality(perf.level + 1); perf.bad = 0; perf.warm = 3; } }
  else perf.bad = 0;
  perf.frames = 0; perf.acc = 0; perf.worst = 0;
}

function frame(now) {
  requestAnimationFrame(frame);
  meter(now ?? performance.now());
  const dt = Math.min(clock.getDelta(), 1 / 30);
  t += dt; FLOWER_TIME.value = t;
  if (dt > 1e-4) physics(dt);
  // safety net: if anything went non-finite, restore the last good state (and say so)
  let bad = false;
  for (const k in st) if (typeof st[k] === 'number' && !Number.isFinite(st[k])) { bad = true; break; }
  if (bad) {
    console.warn('physics went non-finite:', Object.keys(st).filter(k => typeof st[k] === 'number' && !Number.isFinite(st[k])).join(','), JSON.stringify(lastGood));
    Object.assign(st, lastGood, { vy: 0, v: 0, air: false, leanV: 0, compressV: 0, bodyV: 0, bodyY: lastGood.y, pitchV: 0, wInit: false });
  } else for (const k in st) lastGood[k] = st[k];
  place();
  if (!crash.on) rider.update(dt, { footL, footR, handL, handR, v: st.v, lean: st.bikeLean + st.rock, steer: st.steer, yawRate: st.yawRate,
    counter: st.counter + st.rock * 0.6, headRoll: st.bikeLean * 0.85, absorb: clamp(st.bodyY - (crash.on ? st.y : st.yDraw ?? st.y), -T.legComp, T.legExt), pitch: crash.on ? st.pitch : st.pitchDraw ?? st.pitch, bodyLevel: T.bodyLevel, attackDrop: T.attackDrop,
    pedal: st.pedal, crank: st.crank, air: st.airK, compress: Math.max(0, -st.compress), t });
  terrain.update(st.x, st.z, 4);   // time-sliced chunk streaming (ms per frame)
  // announce the landscape as it changes under you
  biomeT -= dt;
  if (biomeT <= 0) {
    biomeT = 0.5;
    const b = terrain.biomeName(st.x, st.z);
    if (b !== biomeCur) { biomeHold = b === biomeNext ? biomeHold + 1 : 0; biomeNext = b; if (biomeHold >= 3) { biomeCur = b; if (msgT <= 0) flash(b); } }
  }
  updateCamera(dt);
  debris.update(dt);
  tapes.update(dt, st.x, st.z);
  if (!crash.on) debris.kick(st.x, st.y, st.z, Math.cos(st.heading) * st.v, -Math.sin(st.heading) * st.v);
  else { const Pp = ragdoll.p[J.PELVIS], Pq = ragdoll.q[J.PELVIS]; debris.kick(Pp.x, Pp.y, Pp.z, (Pp.x - Pq.x) * 180, (Pp.z - Pq.z) * 180, 0.6); }
  fx.update(dt, camera, renderer);
  {  // terrain slope along the direction of travel: + uphill, - downhill
    const dir = st.v < -0.1 ? -1 : 1, hx = Math.cos(st.heading) * 0.6 * dir, hz = -Math.sin(st.heading) * 0.6 * dir;
    const slope = Math.atan2(terrain.height(st.x + hx, st.z + hz) - terrain.height(st.x - hx, st.z - hz), 1.2);
    gauge.update(Math.abs(st.v) * 3.6, THREE.MathUtils.radToDeg(slope), st.air, dt, st.y);
  }
  if (msgT > 0) { msgT -= dt; if (msgT <= 0) hud.msg.style.opacity = 0; }
  composer.render();
}
frame();

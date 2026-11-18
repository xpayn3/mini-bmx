import * as THREE from 'three';

// Low-poly cartoon BMX rider. Local frame: +X forward, +Y up, +Z rider's right.

const UP = new THREE.Vector3(0, 1, 0);
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

// reusable temporaries
const _d = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _pp = new THREE.Vector3();
const _pole = new THREE.Vector3();
const _pelvis = new THREE.Vector3();
const _chest = new THREE.Vector3();
const _hip = new THREE.Vector3();
const _sh = new THREE.Vector3();
const _joint = new THREE.Vector3();
const _end = new THREE.Vector3();
const _ankle = new THREE.Vector3();
const _neck = new THREE.Vector3();
const _headP = new THREE.Vector3();
const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();

function mat(color, extra) {
  return new THREE.MeshStandardMaterial(Object.assign({ color, flatShading: true, roughness: 0.75, metalness: 0.0 }, extra));
}

// Orient a unit-height (along +Y) cylinder between a and b.
function setLimb(mesh, a, b) {
  _d.subVectors(b, a);
  const len = _d.length();
  mesh.position.copy(a).addScaledVector(_d, 0.5);
  if (len < 1e-5) { mesh.scale.set(1, 1e-4, 1); return; }
  mesh.scale.set(1, len, 1);
  _d.multiplyScalar(1 / len);
  mesh.quaternion.setFromUnitVectors(UP, _d);
}

// Analytic two-bone IK. Writes mid joint into outJoint and reachable end into outEnd.
function solveIK(root, target, l1, l2, pole, outJoint, outEnd) {
  _d.subVectors(target, root);
  let dist = _d.length();
  if (dist < 1e-5) { _d.set(0, -1, 0); dist = 1e-5; } else _d.multiplyScalar(1 / dist);
  _dir.copy(_d);
  const maxR = (l1 + l2) * 0.9995;
  const minR = Math.abs(l1 - l2) + 0.01;
  dist = clamp(dist, minR, maxR);
  const a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
  const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
  _pp.copy(pole).addScaledVector(_dir, -pole.dot(_dir));
  if (_pp.lengthSq() < 1e-8) _pp.set(0, 0, 1).addScaledVector(_dir, -_dir.z);
  _pp.normalize();
  outJoint.copy(root).addScaledVector(_dir, a).addScaledVector(_pp, h);
  outEnd.copy(root).addScaledVector(_dir, dist);
}

export class Rider {
  constructor() {
    this.group = new THREE.Group();
    this.group.name = 'Rider';

    const mCoral = mat(0xff6a4d);
    const mCoralDark = mat(0xe04e34);
    const mNavy = mat(0x1d2b64);
    const mNavyLight = mat(0x3a4c9a);
    const mWhite = mat(0xf8f8f8);
    const mRed = mat(0xd8232a);
    const mYellow = mat(0xffd21f);
    const mTeal = mat(0x12d6c4, { roughness: 0.45 });
    const mTealDark = mat(0x0a9a8e);
    const mSkin = mat(0xffc8a0);
    const mBlack = mat(0x111111, { roughness: 0.3 });

    const g = this.group;
    const cyl = (rt, rb, m, seg = 6) => {
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, 1, seg), m);
      g.add(mesh);
      return mesh;
    };
    const sph = (r, m, parent, ws = 7, hs = 5) => {
      const mesh = new THREE.Mesh(new THREE.SphereGeometry(r, ws, hs), m);
      (parent || g).add(mesh);
      return mesh;
    };

    // torso + hips
    this.torso = cyl(0.175, 0.14, mCoral, 7);
    this.hoodHem = cyl(0.15, 0.15, mCoralDark, 7); // reused as belly band (short)
    this.pelvisMesh = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.15, 0.3), mNavy);
    g.add(this.pelvisMesh);
    this.hood = sph(0.11, mCoralDark);
    this.shoulderSph = [sph(0.075, mCoral), sph(0.075, mCoral)];

    // legs (index 0 = left, 1 = right)
    this.thigh = [cyl(0.075, 0.062, mNavy), cyl(0.075, 0.062, mNavy)];
    this.shin = [cyl(0.062, 0.05, mNavy), cyl(0.062, 0.05, mNavy)];
    this.knee = [sph(0.07, mNavyLight), sph(0.07, mNavyLight)];
    this.shoe = [];
    for (let i = 0; i < 2; i++) {
      const s = new THREE.Group();
      const sole = new THREE.Mesh(new THREE.BoxGeometry(0.29, 0.025, 0.115), mRed);
      sole.position.set(0.03, 0.0125, 0);
      const upper = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.07, 0.105), mWhite);
      upper.position.set(0.035, 0.06, 0);
      const toe = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.05, 0.11), mWhite);
      toe.position.set(0.15, 0.048, 0);
      s.add(sole, upper, toe);
      g.add(s);
      this.shoe.push(s);
    }

    // arms
    this.upperArm = [cyl(0.055, 0.047, mCoral), cyl(0.055, 0.047, mCoral)];
    this.foreArm = [cyl(0.047, 0.04, mCoral), cyl(0.047, 0.04, mCoral)];
    this.elbow = [sph(0.055, mCoralDark), sph(0.055, mCoralDark)];
    this.glove = [sph(0.058, mYellow, null, 6, 5), sph(0.058, mYellow, null, 6, 5)];

    // head
    this.head = new THREE.Group();
    this.head.rotation.order = 'XYZ';
    g.add(this.head);
    const H = this.head;
    // ---- full-face downhill helmet: no cartoon face, just helmet, goggles and a dark face opening ----
    // faceted like the rest of the rider; white shell, coral stripe + visor (matches the jersey)
    const shellMat = new THREE.MeshPhysicalMaterial({ color: 0xf1f1ec, flatShading: true, roughness: 0.35, clearcoat: 1, clearcoatRoughness: 0.15 });
    const accentMat = new THREE.MeshPhysicalMaterial({ color: 0xff6a4d, flatShading: true, roughness: 0.4, clearcoat: 1, clearcoatRoughness: 0.2 });
    const chinMat = new THREE.MeshStandardMaterial({ color: 0x30353d, flatShading: true, roughness: 0.55 });
    const innerMat = new THREE.MeshStandardMaterial({ color: 0x14171c, roughness: 0.9 });          // liner / face in shadow
    const ventMat = new THREE.MeshStandardMaterial({ color: 0x0d0f12, roughness: 0.6 });
    const frameMat = new THREE.MeshStandardMaterial({ color: 0x1a1d22, flatShading: true, roughness: 0.5 });
    const lensMat = new THREE.MeshPhysicalMaterial({ color: 0x3a3226, metalness: 0.7, roughness: 0.08, clearcoat: 1,
      iridescence: 0.8, iridescenceIOR: 1.7, emissive: 0x3a1806, emissiveIntensity: 0.5 });
    const R = 0.185;
    const hel = new THREE.Group();
    hel.position.set(-0.005, 0.02, 0);
    hel.rotation.z = 0.05;                     // tipped forward a touch, like it's worn
    hel.scale.set(1.14, 0.96, 0.9);            // longer than it is wide or tall
    H.add(hel);
    // dark inside: whatever shows through the face opening is liner in shadow
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R * 0.92, 10, 8), innerMat));
    // shell: closed crown + sides/back with an opening at the face (+X is phi = PI here)
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R, 12, 4, 0, Math.PI * 2, 0, Math.PI * 0.3), shellMat));
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R, 12, 6, Math.PI + 0.7, Math.PI * 2 - 1.4, Math.PI * 0.3, Math.PI * 0.48), shellMat));
    // one bold stripe over the top: back of the neck to the visor
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R * 1.012, 3, 8, -0.14, 0.28, 0.02, Math.PI * 0.62), accentMat));
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R * 1.012, 3, 4, Math.PI - 0.14, 0.28, 0.02, Math.PI * 0.27), accentMat));
    // a coral band round the sides and back, and a charcoal trim on the bottom edge
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R * 1.025, 12, 1, Math.PI + 0.7, Math.PI * 2 - 1.4, Math.PI * 0.5, Math.PI * 0.07), accentMat));
    hel.add(new THREE.Mesh(new THREE.SphereGeometry(R * 1.025, 12, 1, Math.PI + 0.7, Math.PI * 2 - 1.4, Math.PI * 0.72, Math.PI * 0.06), chinMat));
    // visor: a curved brim following the shell above the face opening, tipped up
    const brim = new THREE.Mesh(new THREE.SphereGeometry(R * 1.1, 8, 2, Math.PI - 0.62, 1.24, Math.PI * 0.27, Math.PI * 0.07), accentMat);
    brim.material = accentMat; brim.geometry.computeVertexNormals();
    const brimG = new THREE.Group(); brimG.add(brim); brimG.position.set(0.012, 0.012, 0); brimG.rotation.z = 0.12;
    hel.add(brimG);
    const brimUnder = new THREE.Mesh(brim.geometry, new THREE.MeshStandardMaterial({ color: 0xc94a33, side: THREE.BackSide, flatShading: true }));
    brimG.add(brimUnder);
    // chin bar: a slim charcoal bar across the jaw, close to the face, with vents
    const chinGeo = new THREE.TorusGeometry(R * 0.97, 0.026, 4, 10, 1.95);
    chinGeo.rotateX(Math.PI / 2); chinGeo.rotateY(0.975);   // arc centred on the front (+X)
    const chin = new THREE.Mesh(chinGeo, chinMat);
    chin.position.set(0.006, -0.088, 0); chin.scale.set(1.05, 1.6, 1.02);
    hel.add(chin);
    const chinVent = new THREE.Mesh(new THREE.BoxGeometry(0.014, 0.026, 0.05), ventMat);
    chinVent.position.set(R * 1.0 + 0.032, -0.088, 0);
    hel.add(chinVent);
    for (const sz of [-1, 1]) {              // side vents on the chin bar
      const v = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.016, 0.01), ventMat);
      v.position.set(R * 0.8 + 0.012, -0.088, sz * R * 0.62); v.rotation.y = sz * 0.8;
      hel.add(v);
    }
    // top vents
    for (const z of [-0.045, 0.045]) {
      const v = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.01, 0.014), ventMat);
      v.position.set(0.02, R * 0.99, z); v.rotation.z = -0.15;
      hel.add(v);
    }
    // goggles over the eyes, sitting in the face opening; the strap shows only where it meets the shell
    const gog = new THREE.Group();
    gog.position.set(R * 0.86, 0.022, 0);
    hel.add(gog);
    const gFrame = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.062, 0.19), frameMat);
    gog.add(gFrame);
    const gLens = new THREE.Mesh(new THREE.BoxGeometry(0.01, 0.048, 0.17), lensMat);
    gLens.position.x = 0.021;
    gog.add(gLens);
    for (const sz of [-1, 1]) {
      const tab = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.03, 0.012), frameMat);
      tab.position.set(-0.03, 0, sz * 0.1); tab.rotation.y = sz * 0.5;
      gog.add(tab);
    }
    g.traverse((o) => { if (o.isMesh) o.castShadow = true; });

    // constants
    this.L_THIGH = 0.44;
    this.L_SHIN = 0.44;
    this.L_UARM = 0.31;
    this.L_FARM = 0.29;
    this.smShiftZ = 0;
    this.fit = new THREE.Vector3();   // pelvis offset for bikes bigger / smaller than the BMX
    this.setStyle({});
    // springs that give the hips and chest weight and follow-through
    this.pelS = new THREE.Vector3(); this.pelV = new THREE.Vector3();
    this.chS = new THREE.Vector3(); this.chV = new THREE.Vector3();
    this.springInit = false;
    // joint positions in the rider's local frame, refreshed every update() (ragdoll hand-off)
    this.J = Array.from({ length: 15 }, () => new THREE.Vector3());
  }

  // riding position (BMX = all zero). hipX/hipY move the hips (m, + forward / up), lean tips the
  // chest forward (rad), elbowsOut / kneesOut 0..1 swing the elbows and knees wide, stance widens
  // the hips (m per side)
  // The rest are multipliers / offsets for the rider-pose panel (all neutral = the original pose):
  // crouch (how deep the legs fold), standPedal (how far the rider rises to pedal), sway (pedalling
  // sway + idle fidget), torso (chest length, m), shoulders (half shoulder width, m), headTilt (rad,
  // + looks down), headTurn (how much the head looks into turns), lookAhead (head forward offset, m)
  setStyle({ hipX = 0, hipY = 0, lean = 0, elbowsOut = 0, kneesOut = 0, stance = 0, seatFloor = false,
    crouch = 1, standPedal = 1, sway = 1, torso = 0.46, shoulders = 0.2, headTilt = 0, headTurn = 1, lookAhead = 0 }) {
    this.style = { hipX, hipY, lean, stance, seatFloor, crouch, standPedal, sway, torso, shoulders, headTilt, headTurn, lookAhead };
    // knees track forward over the pedals (just a hint outward); kneesOut widens them for a DH stance
    this.polesLeg = [-1, 1].map(s => new THREE.Vector3(1, 0.1, s * (0.1 + 0.3 * kneesOut)).normalize());
    this.polesArm = [-1, 1].map(s => new THREE.Vector3(-0.4 + 0.25 * elbowsOut, -0.5 + 0.4 * elbowsOut, s).normalize());
  }

  // world positions of the 15 ragdoll joints (order: see ragdoll.js J)
  jointsWorld() {
    this.group.updateMatrixWorld(true);
    return this.J.map((v) => this.group.localToWorld(v.clone()));
  }

  // drive the meshes from world-space ragdoll points (group must sit at the world origin)
  poseRagdoll(P) {
    const [hd, ch, pe, shL, elL, haL, shR, elR, haR, hpL, knL, ftL, hpR, knR, ftR] = P;
    const basis = (up, right, out) => {
      const u = _d.copy(up).normalize();
      const r = _dir.copy(right).addScaledVector(u, -right.dot(u)).normalize();
      const f = _pp.crossVectors(u, r);
      return out.setFromRotationMatrix(_m4.makeBasis(f, u, r));
    };
    const bodyUp = _pole.subVectors(ch, pe), bodyR = _neck.subVectors(hpR, hpL);
    basis(bodyUp, bodyR, _q);
    this.pelvisMesh.position.copy(pe); this.pelvisMesh.quaternion.copy(_q);
    _hip.copy(pe).addScaledVector(_d, 0.02);
    setLimb(this.torso, _hip, ch);
    _end.lerpVectors(_hip, ch, 0.2);
    setLimb(this.hoodHem, _hip, _end);
    this.hood.position.copy(ch);
    basis(_pole.subVectors(hd, ch), _neck.subVectors(shR, shL), this.head.quaternion);
    this.head.position.copy(hd);
    const sh = [shL, shR], el = [elL, elR], ha = [haL, haR], hp = [hpL, hpR], kn = [knL, knR], ft = [ftL, ftR];
    for (let i = 0; i < 2; i++) {
      this.shoulderSph[i].position.copy(sh[i]);
      setLimb(this.upperArm[i], sh[i], el[i]); setLimb(this.foreArm[i], el[i], ha[i]);
      this.elbow[i].position.copy(el[i]); this.glove[i].position.copy(ha[i]);
      setLimb(this.thigh[i], hp[i], kn[i]); setLimb(this.shin[i], kn[i], ft[i]);
      this.knee[i].position.copy(kn[i]);
      basis(_pole.subVectors(kn[i], ft[i]), _neck.subVectors(hpR, hpL), this.shoe[i].quaternion);
      this.shoe[i].position.copy(ft[i]).addScaledVector(_d, -0.08);
    }
  }

  // back on the bike: clear the ragdoll orientations the normal update doesn't set
  resetPose() {
    this.pelvisMesh.quaternion.identity();
    this.head.quaternion.identity(); this.head.rotation.set(0, 0, 0, 'XYZ');
    for (const s of this.shoe) s.quaternion.identity();
    this.springInit = false; this.pelV.set(0, 0, 0); this.chV.set(0, 0, 0);
  }

  update(dt, p) {
    const v = p.v || 0;
    const pedal = clamp(p.pedal || 0, 0, 1);
    const t = p.t || 0;
    const lowSpeed = 1 - clamp(Math.abs(v) / 6, 0, 1);

    // lateral shift while turning (riders stay upright at low speed)
    const targetShift = p.counter !== undefined ? 0 : (p.lean || 0) * lowSpeed;   // main.js now counter-rolls the body instead
    const k = 1 - Math.exp(-10 * Math.min(dt, 0.1));
    this.smShiftZ += (targetShift - this.smShiftZ) * k;
    const shift = clamp(this.smShiftZ, -0.6, 0.6);

    const sty = this.style;
    const sway = Math.sin(p.crank || 0) * pedal * sty.sway;
    const bob = Math.sin((p.crank || 0) * 2) * pedal * sty.sway;
    const wig = clamp(1 - Math.abs(v) / 3, 0, 1) * sty.sway;
    const air = typeof p.air === 'number' ? p.air : (p.air ? 1 : 0);
    const comp = (p.compress || 0) * sty.crouch;

    // pelvis
    _pelvis.set(
      -0.16 - 0.07 * air + 0.06 * pedal * sty.standPedal - comp * 0.25,
      0.80 - 0.07 * air - comp + 0.15 * pedal * sty.standPedal + 0.035 * bob,      // stand up out of the crouch to pedal
      sway * 0.09 + shift * 0.3 + Math.sin(t * 2.1) * 0.02 * wig
    ).add(this.fit);
    _pelvis.x += sty.hipX * (1 - 0.5 * pedal); _pelvis.y += sty.hipY * (1 - 0.6 * pedal);   // pedalling stands up out of it

    // chest
    const ang = 0.72 - 0.14 * pedal + 0.15 * (comp / 0.3) + 0.08 * air + sty.lean * (1 - 0.5 * pedal);   // more upright when standing
    const L = sty.torso;
    _chest.set(
      _pelvis.x + Math.sin(ang) * L + 0.03 * pedal * (0.5 + 0.5 * bob),
      _pelvis.y + Math.cos(ang) * L,
      _pelvis.z + shift * 0.3 - sway * 0.04 + Math.sin(t * 1.7 + 1.0) * 0.02 * wig
    );

    // legs absorb terrain: body glides while the bike goes up and down under it
    const absorb = p.absorb || 0;
    _pelvis.y += absorb; _chest.y += absorb * 0.9;
    // weight shift (main.js moves the hips' mass fore / aft over the bike): the body goes with it
    const hs = p.hipShift || 0;
    _pelvis.x += hs; _chest.x += hs * 0.6;
    // keep the body level while the bike pitches under it: counter-rotate hips and chest about
    // the pedals, so on a descent the hips slide back and the chest stays up (downhill attack
    // position), and on a climb the rider leans forward over the bars.
    // Descents: counter-rotate almost fully (attack position). Climbs: only a little -- keeping the body
    // world-level on a climb leaves the rider leaning back over the rear wheel with the arms stretched
    // to the bars. A climbing rider does the opposite (below): hips to the saddle nose, chest low.
    const pitch0 = p.pitch || 0;
    const pit = pitch0 * (pitch0 > 0 ? 0.2 : (p.bodyLevel ?? 0.85));
    if (pit) {
      const c = Math.cos(-pit), sn = Math.sin(-pit), y0 = 0.3;
      for (const q of [_pelvis, _chest]) {
        const dx = q.x, dy = q.y - y0;
        q.x = dx * c - dy * sn; q.y = y0 + dx * sn + dy * c;
      }
      const down = Math.max(0, -(p.pitch || 0));
      const drop = p.attackDrop ?? 0.18;
      _pelvis.y -= down * drop; _pelvis.x -= down * drop * 0.45;   // drop the hips and get low on steep stuff
    }
    // CLIMBING: weight forward so the front wheel stays down -- hips slide to the nose of the saddle,
    // chest drops low over the bars, elbows bend (the arms follow the chest)
    const climb = clamp(pitch0, 0, 0.6);
    if (climb > 0) {
      _pelvis.x += climb * 0.22; _pelvis.y -= climb * 0.04;
      _chest.x += climb * 0.42; _chest.y -= climb * 0.24;
    }
    // lean the BIKE, not the body: roll the body back toward upright about the pedals
    const cr = p.counter || 0;
    if (cr) {
      const c = Math.cos(cr), sn = Math.sin(cr), y0 = 0.3;
      for (const q of [_pelvis, _chest]) {
        const dy = q.y - y0, dz = q.z;
        q.y = y0 + dy * c - dz * sn; q.z = dy * sn + dz * c;
      }
      // weight drops onto the outside foot
      _pelvis.y -= Math.abs(cr) * 0.12; _chest.x += Math.abs(cr) * 0.05;
    }
    // never sit INTO the saddle: over it, the pelvis box (0.075 half height) stays on top of it.
    // Behind its tail the hips may still drop (hips-behind-the-seat on steep descents)
    const seat = this.seat;
    if (sty.seatFloor && seat) {
      // 0 once the whole pelvis box (0.1 half length) is past the tail .. 1 while any of it is over it
      const over = clamp((_pelvis.x - (seat.rear - 0.18)) / 0.08, 0, 1);
      const floor = seat.top + 0.085;
      if (_pelvis.y < floor) _pelvis.y += (floor - _pelvis.y) * over;
      if (_chest.y < _pelvis.y + 0.15) _chest.y = _pelvis.y + 0.15;
    }
    // critically-damped-ish springs -> fluid follow-through
    if (!this.springInit) { this.pelS.copy(_pelvis); this.chS.copy(_chest); this.springInit = true; }
    const h = Math.min(dt, 0.05);
    for (const [S, V, T, k] of [[this.pelS, this.pelV, _pelvis, 260], [this.chS, this.chV, _chest, 200]]) {
      const d = 2 * Math.sqrt(k) * 0.85;
      V.x += ((T.x - S.x) * k - V.x * d) * h; V.y += ((T.y - S.y) * k - V.y * d) * h; V.z += ((T.z - S.z) * k - V.z * d) * h;
      S.addScaledVector(V, h);
      T.copy(S);
    }
    // arms can only reach so far: if the bars are out of comfortable reach (weight far back on a
    // descent, a long downhill cockpit...), the torso follows the hands so the elbows keep a bend
    if (p.handL && p.handR) {
      const reach = (this.L_UARM + this.L_FARM) * 0.9;
      let worst = 0;
      for (const [side, hand] of [[-1, p.handL], [1, p.handR]]) {
        _sh.set(_chest.x - 0.03, _chest.y - 0.04, _chest.z + side * sty.shoulders);
        const over = _sh.distanceTo(hand) - reach;
        if (over > worst) worst = over;
      }
      if (worst > 0) {
        // move toward the middle of the two grips
        _d.set((p.handL.x + p.handR.x) * 0.5, (p.handL.y + p.handR.y) * 0.5, (p.handL.z + p.handR.z) * 0.5)
          .sub(_sh.set(_chest.x - 0.03, _chest.y - 0.04, _chest.z));
        const len = _d.length();
        if (len > 1e-4) {
          _d.multiplyScalar(Math.min(worst + 0.01, len * 0.6) / len);
          _chest.add(_d);
          _pelvis.addScaledVector(_d, 0.35);   // hips come along a bit so the back doesn't stretch
        }
      }
    }

    // torso mesh from pelvis to chest
    _hip.set(_pelvis.x, _pelvis.y + 0.02, _pelvis.z);
    _sh.set(_chest.x, _chest.y, _chest.z);
    setLimb(this.torso, _hip, _sh);
    this.pelvisMesh.position.copy(_pelvis);
    this.pelvisMesh.rotation.z = -(ang * 0.3);
    // belly band
    _joint.set(_pelvis.x, _pelvis.y + 0.04, _pelvis.z);
    _end.lerpVectors(_hip, _sh, 0.2);
    setLimb(this.hoodHem, _joint, _end);

    // neck / head
    _neck.lerpVectors(_hip, _sh, 1.0);
    this.hood.position.set(_neck.x - 0.03, _neck.y + 0.0, _neck.z);
    _headP.set(_neck.x + 0.05 + sty.lookAhead, _neck.y + 0.2, _neck.z);
    this.head.position.copy(_headP);
    this.J[0].copy(_headP); this.J[1].copy(_chest); this.J[2].copy(_pelvis);
    const yaw = clamp(((p.steer || 0) * 1.2 + (p.yawRate || 0) * 0.15) * sty.headTurn, -1.0, 1.0);
    this.head.rotation.x = p.headRoll !== undefined ? p.headRoll : (p.lean || 0) * 0.6;
    this.head.rotation.y = yaw;
    this.head.rotation.z = -0.12 * (ang - 0.72) + 0.04 * Math.sin(t * 3.3) * wig - sty.headTilt;


    for (let i = 0; i < 2; i++) {
      const side = i === 0 ? -1 : 1; // left = -Z, right = +Z
      const foot = i === 0 ? p.footL : p.footR;
      const hand = i === 0 ? p.handL : p.handR;

      // leg
      _hip.set(_pelvis.x, _pelvis.y - 0.02, _pelvis.z + side * (0.11 + sty.stance));
      _ankle.set(foot.x - 0.04, foot.y + 0.12, foot.z);
      solveIK(_hip, _ankle, this.L_THIGH, this.L_SHIN, this.polesLeg[i], _joint, _end);
      setLimb(this.thigh[i], _hip, _joint);
      setLimb(this.shin[i], _joint, _end);
      this.knee[i].position.copy(_joint);
      this.shoe[i].position.set(foot.x, foot.y + 0.03, foot.z);
      this.J[9 + i * 3].copy(_hip); this.J[10 + i * 3].copy(_joint); this.J[11 + i * 3].set(foot.x, foot.y + 0.08, foot.z);

      // arm
      _sh.set(_chest.x - 0.03, _chest.y - 0.04, _chest.z + side * sty.shoulders);
      this.shoulderSph[i].position.copy(_sh);
      solveIK(_sh, hand, this.L_UARM, this.L_FARM, this.polesArm[i], _joint, _end);
      setLimb(this.upperArm[i], _sh, _joint);
      setLimb(this.foreArm[i], _joint, _end);
      this.elbow[i].position.copy(_joint);
      this.glove[i].position.copy(hand);
      this.J[3 + i * 3].copy(_sh); this.J[4 + i * 3].copy(_joint); this.J[5 + i * 3].copy(hand);
    }
  }
}

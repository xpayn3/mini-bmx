# Rider animation: what the research says, and what to change (2026-11-22)

A review of the SIGGRAPH / GDC literature on physics-based characters, motion matching and blending, plus cycling
biomechanics, set against our procedural rider (`scripts/rider/rider.gd` `update_pose`). PDFs kept locally live in
`C:\Users\Luka\Documents\GameResearch\` (index in its README). Sources marked "gated" were members-only (GDC Vault)
and only their summaries were seen.

## How our rider works today (for reference)

`update_pose` builds two points, **pelvis** and **chest**, from dozens of additive offsets (pedal, sprint, preload,
pop, squash, landing fold, tuck, stick, climb, wheelie, lean...), each input first eased with its own `exp` smoother.
Then: pelvis and chest each ride a spring (body mass, `pel_s` / `ch_s`, kicked by the frame's vertical acceleration
`_facc`); then a stack of **hard limits** (hips box, bar clearance push, rear wheel, torso angle, torso length, saddle /
tyre floor) and finally a **motion cap** (`TORSO_VMAX`) that hides the steps those limits make. The head is placed at a
fixed offset from the chest, turned in the bike's frame. Limbs: 2-bone IK to grips and pedals, joint limits, swing
clearance. Feet keep one fixed angle (`footAngle`).

## What the literature agrees on

1. **Target, then tracking, then limits on the target.** DReCon (Ubisoft La Forge, SIGGRAPH Asia 2019), DeepMimic
   (Peng 2018) and SIMBICON (Yin 2007) all split "where the body should be" (kinematic target) from "where it is"
   (a damped tracker, PD control). Limits belong on the target; the tracker then can't step. Ours limits *after*
   the springs, so every limit that switches on is a step, and the motion cap is a patch over it.
2. **The body is a low-pass cascade from the contact points up.** MTB vibration studies (Transference of 3D
   accelerations during XC MTB, PubMed 24735505) measure the acceleration dropping from bike to lower back to head,
   most on descents; arms, legs and soft tissue each damp it, stiffer when the muscles work (downhill riders: more
   triceps). Hands and feet go with the bike, hips lag, chest lags more, head least affected and near world-stable.
   Ours: hips and chest get the same kick on similar springs, the head is glued to the chest -> "moves as one stiff unit".
3. **Arms take the front, legs take the rear.** Coaching lore (not found in a readable paper), consistent with the
   above: the front wheel's hit goes into the elbows / shoulders, the rear's into knees / hips. Ours feeds one mixed
   frame acceleration (85 % frame, 15 % wheels) to the whole body.
4. **Transitions by inertialization, not by switching.** Bollo, *Inertialization* (Gears of War, GDC 2018, gated;
   SIGGRAPH 2017 talk), Holden *Spring-It-On* and *Dead Blending* (theorangeduck.com, free): at a state change store
   offset = old pose - new pose (and its velocity) and decay it to zero (quintic or critical spring, ~0.15-0.3 s);
   or extrapolate the old pose with decaying velocity and cross-fade. Pose and velocity stay continuous, nothing pops.
   Ours: each input eases at its own rate, so a state change (take-off, landing, get-up, manual on / off, dab) arrives
   as several overlapping ramps plus whatever the limits do.
5. **Soft limits.** Holden *Joint Limits*: project into the allowed range, then give back tanh(falloff x d) x radius
   so the boundary is approached smoothly; swing-twist split; unroll quaternions (no +-180 flips). Ours: `clampf`.
6. **Feedback on targets (SIMBICON / Tan 2014).** *Learning Bicycle Stunts* (Tan, Gu, Liu, Turk, SIGGRAPH 2014) does
   wheelies, endos, hops as a few body-shift targets (hip fore / aft, height, arm reach) modulated by feedback on the
   bike's pitch and pitch rate; SIMBICON: target += c_d x offset + c_v x velocity, low gain. We already do much of this
   (`body_x`, `hip_shift`, `man_a`), but the jump / landing poses are time-shaped (preload -> extend -> fold) rather
   than fed back.
7. **Pedalling kinematics** (Gregor 2000, *Road Cycling* handbook ch. 2; Faria 2005, *Science of Cycling* pt 2,
   both in the library): per crank turn the hip moves ~45 deg, the knee ~75 deg, the **ankle ~20 deg**
   (heel drops through the downstroke, toes point down through the bottom and recovery); standing adds plantar
   flexion and a bigger hip range, and the bike sways sideways. Ours: knee / hip come out of the IK correctly; the
   ankle never moves.
8. **Not for us:** motion matching (Clavet, GDC 2016, gated), Learned Motion Matching (Holden 2020), PFNN / MANN /
   Neural State Machine / DeepPhase, AMP / ASE / SuperTrack / RL controllers: all need hours of motion capture of the
   activity (bike riding) or a training pipeline. Riders Republic (Ubisoft) used Xsens mocap for tricks plus a physics
   layer per frame, not a procedural rider. The one idea that carries over is "motion-matching lite": a handful of
   authored key poses blended by feature distance (speed, slope, lip, air, stick); our pose sliders already are that.

## Suggested changes, ranked (value for effort)

| # | Change | Fixes | Effort |
|---|---|---|---|
| 1 | **Head stabilisation**: the head keeps a world-steady attitude (pitch / roll heavily damped vs the chest, ~0.3 s halflife; yaw at a look-ahead point on the trail), its position follows the chest through its own soft spring (neck). | Head shake over rocks, the stiff look; reads instantly as "a rider" | small |
| 2 | **Ankling**: foot pitch = footAngle + ~10 deg x f(crank) (heel down on the downstroke, toe down at the bottom / recovery), more toe-down standing / sprinting; heels drop into landings and braking. | Feet look bolted on | small |
| 3 | **Bump cascade, front vs rear**: drive the arms' bend from the front wheel (`vw_f`), the legs' from the rear (`vw_r`); hips ~1.5 Hz, chest ~1 Hz on its own lag, head per #1. Stiffness up with effort (landing braced, coasting loose). | "Whole body moves as one unit"; rider looks like he works the bike | medium |
| 4 | **Limits on the target, then one tracker**: move the bar / wheel / saddle / torso limits *before* the pelvis / chest springs (soft, tanh-style), so the springs follow a target that never steps; the motion cap then rarely acts. | Snaps when a limit engages, clipping fixes that jump | medium (needs the BODYCLIP / BARCLEAR / jitter probes before and after) |
| 5 | **Inertialization at state changes**: on take-off, landing, get-up -> bike, manual on / off, dab on / off, store the drawn pelvis / chest / head (and hands' reach) offset vs the new target with its velocity, decay it on a critical spring (~0.2 s). One helper, called from the few places a mode flips. | Pops at take-off / landing / get-up | small-medium |
| 6 | **Closed-form halflife springs** (Holden): rewrite the body / roll springs with the exact critical (and a controlled underdamped) form, every rate as a halflife in seconds. Frame-rate independent by construction (today: explicit steps, `h` capped at 0.05 s). | Any leftover 30 / 60 / 144 fps difference | small, low risk; do with #3-#5 |
| 7 | **Ragdoll hand-off**: carry the drawn body's per-point velocity into the ragdoll (clamped), start stiff and ease to the tone over ~0.3 s; dead-blend the ragdoll pose into the get-up clip. | Crash start looking limp / launching; get-up seam | small |
| 8 | **Pose error probe** (DeepMimic's four terms): log target vs drawn pose, velocity, hands / feet and centre of mass per frame in the ride log, so "unnatural at lips" becomes a number. | Lets us measure 3-5 | small |
| 9 | Jump poses fed back from pitch / pitch rate (Tan 2014) instead of time-shaped; ground look-ahead (~0.5 s) as a pose input. | Lip poses that fit the actual lip | larger; later |

**Done 2026-11-22: 1 (head stabilisation) and 2 (ankling)**, see HANDOFF "Head stabilisation + ankling". Head world
angular speed on the rocks lane: pitch -43 %, roll -95 %, yaw -14 %. Same day: the shoe on the pedal (ball of the foot
over the axle, sole on the pedal's top).

**Done 2026-11-22: 8, 4, 6, and the measured parts of 5 and 3** (HANDOFF "Pose order: limits on the target"). What the
probe showed changed the plan: the pops were not transitions in general but (a) the corrections after the springs and
(b) the pitch-kick hold mistaking a jump face for a bump; both fixed. Inertialization as a separate layer was not needed:
with the limits on the target and exact springs, the get-up blend already velocity-continuous, nothing popped in the
scenarios except the first frames of a run and the real ~0.1 s pop at a lip. For 3, the kick hold already makes the
arms take the front and the legs the rear (the bike pitches under a held body); the cascade was the missing part (chest
softer than hips). 7: already mostly there (stiff start, startle, no eject). Open: per-limb speed into the ragdoll; the
head is still a touch rougher than the hips in the world (its lever arm over the bike's pitch); 9 (jump poses fed back).

Suggested order: **1 + 2** (cheap, visible), then **8** (measure), then **5 + 6**, then **3 + 4** (the big ones,
checked with the probes and `BMX_JITTER_ALL` at 60 fps), then 7.

## Sources

Read (free): Holden, *Spring-It-On*, *Dead Blending*, *Code vs Data Driven Displacement*, *Joint Limits*
(theorangeduck.com); Tan et al. *Learning Bicycle Stunts* project page (faculty.cc.gatech.edu/~turk); DeepMimic
(arxiv 1804.02717); SIMBICON page (cs.ubc.ca/~van); DReCon and SuperTrack summaries (Ubisoft La Forge site); Wobbledoll
(80.lv); GRAIL skateboarder devlog (itch.io, upakai); Gibbon physics animation (gamedeveloper.com); Gregor 2000 ch. 2
and Faria 2005 (local).
Seen only as summaries: Bollo GDC 2018, Clavet GDC 2016, Rosen GDC 2014, Bereznyak GDC 2016 (GDC Vault, gated);
Coros 2010 (GBWC); AMP; MTB vibration studies (PubMed 24735505, JSSM 12:512).

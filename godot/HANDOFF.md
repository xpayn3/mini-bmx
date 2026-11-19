# Mini BMX (Godot) — project handoff

Everything a new chat needs to carry on with the game. The repo root `CLAUDE.md` points here, so Claude Code
loads it into every chat.

State as of **2026-11-18**. Repo `github.com/xpayn3/mini-bmx`, checkout `C:\Users\Luka\Documents\gamecycling`,
branch `main`, folder `godot/`. The repo holds **only the Godot game** (`godot/`) and its Houdini exporters
(`tools/`). The old three.js web prototype was moved out to `C:\Users\Luka\Documents\mini-bmx-web-archive`
(not developed; still in git history before the removal commit).

---

## 1. What the game is

A native **PC downhill / BMX riding game** in **Godot 4.7 (.NET edition)**: endless procedural trails
(jumps, berms, rollers, rocks, fences, tape, water, biomes), physics-driven bike with suspension, a
procedural rider with ragdoll crashes, mud / wet / dust / tyre tracks, and a **garage** to build and
paint the downhill bike. It started as a 1:1 port of an older three.js web prototype (archived outside the
repo, see above — never develop it).

- Main bike: **GLORY DH** (downhill frame `assets/dh.glb`), the player starts on it every launch.
  A BMX also exists (`B` cycles bikes). The web version's **bike builder is intentionally left out**.
- Single player, keyboard + gamepad, fully rebindable.

## 2. Install / run

| What | Where |
|---|---|
| Godot 4.7.2 **.NET** (use this one) | `C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe` (+ `_console.exe` for logs/tests) |
| Plain Godot 4.7.2 (no C#) | `C:\Users\Luka\Downloads\Godot_v4.7.2-stable_win64.exe\` (a folder) — runs, but terrain falls back to slow GDScript and some C# features are off |
| .NET SDK | 8.0.428 |
| No MCP is used | Godot is driven from the command line |

```powershell
# editor
& "C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe" --path godot -e
# play (title screen) / straight into a ride / straight into the garage
& "...mono_win64.exe" --path godot
& "...mono_win64.exe" --path godot -- --ride
& "...mono_win64.exe" --path godot -- --garage
# build C# after editing .cs files (the editor also builds on run)
dotnet build   # in godot/
```

Standalone export: install export templates once (Editor → Manage Export Templates), then
`..._console.exe --headless --path godot --export-release "Windows Desktop" build/windows/MiniBMX.exe`.

Player data: `%APPDATA%\Godot\app_userdata\Mini BMX\` — `settings.cfg`, `tune.cfg`, `save.cfg`,
`rider.cfg`, `garage.json`, `logos/`, `screenshots/` (F12).

## 3. Controls (defaults, all rebindable in Settings → Controls)

W/↑ pedal · S/↓ brake · A/D steer · **Space** hop/pump (hold to charge; **in the air: tuck the bike up**) ·
**S/W pressed fresh as you leave a lip: throw a back/front flip** · **W/S in the air: tilt the bike nose down/up (limited, body shift)** · **A/D in the air: lean the bike left/right (no spins)** · **brake + A/D when slow: pivot (pirouette)** · Shift sprint (stamina) · Q/E shift gears · F bail · Backspace back to
start · R new world · B next bike · C next camera · Z/X rotate camera · +/- zoom · mouse drag orbit ·
H records · **P / K / L** the tuning card on its Ride / Rider / Look tab · O photo mode · F1 hide HUD ·
F12 screenshot · Esc pause. Gamepad (Xbox): triggers pedal/brake, left stick steer, A hop, X sprint, bumpers gears, Y camera,
**right stick = the rider's body, all the time**: up / down shifts the weight forward over the bars / back (pulled well back
rolling = a **manual**, yanked fresh at a lip = a flip throw, in the air = nose down / up), left / right throws the bike over under
the body (leaning alone turns, leaning with the steer turns harder + grips more, a quick **flick** whips the bike round; in the
air it leans the bike). Numpad 8/5/4/6 do the same on keys. The camera no longer uses the right stick.
**Settings › Controller** (`ui/pad_map.gd`): the Xbox photo (`assets/ui/xbox_pad.png`, cut out by root `tools/cut_pad.py`;
without it a drawn pad) with what every button does, click to remap (sticks pick Steer / Rider body / Camera / Nothing and
swap), live button test, vibration on / off + strength. `Settings.pad_active` follows the last device used: prompts show
Xbox names (`Settings.prompt(action)`), and on a pad the triggers don't tilt or throw the bike in the air (only a real
right-stick yank from centre throws at a lip; a held lean never does).
In the air the right stick is a **360° attitude control** (`air_stick`): y tilts the nose on top of the landing aim
(`stickAirTilt`), x lays the bike over (`stickAirRoll`); only the very edge (> 0.88) keeps it turning over (flips). Test:
`BMX_BODY=circle` circles the stick mid-air (`AIRSTICK` lines). Test runs ignore real controllers (`Settings._test_run`).
Arcade-style feel: the stick is eased (`stickAirEase`), the tilt / lean springs go soft while it's used, and held at
an **edge** it spins: top / bottom = flips (`edge_s` → `flip_in`), left / right = **flat spins** (`stick_yaw` on top of
`air_yaw`, `stickYawRate`). Both build up gently (`stickSpinBuild`) and get faster the longer they're held
(`stickSpinGrow`, up to 1.5 s); let go and they ease out. Near the landing a spin within ~57° of straight is twisted
the rest of the way. Landed tricks are named "360", "720", "360 BACKFLIP"... In the air the rider's body drives it:
counter-leans against the bike (`stickBodyCounter`) and stays steady while the bike tilts under it (`stickBodyTilt`).
Tests: `BMX_BODY=holdback` (`SPIN` lines), `BMX_BODY=spin360` (`YAW` lines).

## 4. Project layout (`godot/`)

| Path | What |
|---|---|
| `project.godot` | Forward+, 1600×900 canvas_items stretch, **physics 120 Hz**, MSAA 2×, shader globals (`atm_wind`, `atm_pusher`, grime…) |
| `scenes/main.tscn` + `scripts/main.gd` | title menu, ride, garage, pause, settings, controls card, all test flags |
| `scripts/core/` | autoloads: **Settings** (graphics/display/audio/controls/rebinding, presets Low–Ultra), **Tune** (ride feel × bike multipliers, pins for the Quick tune card), **GameState** (bikes, seed, records, `bike_config()` merges the garage build) |
| `scripts/bike/` | `bike_physics.gd` (the ride, fixed 120 Hz, 1:1 port of web `physics()` + new body model), `bike_rig.gd` (model, pose, pedals, grips, limb targets), `suspension.gd`, `bike_build.gd` (garage data: paint finishes, logos, wheels, suspension, cassettes, ride mods, stats), `wheel_gen.gd` (procedural wheels/tyres), `decals.gd`, `bike_fx.gd`, `grime.gd` (mud/wet overlay passes) |
| `scripts/rider/` | `rider.gd` (procedural rider posed every frame; **skinned spine** with 5 bones), `rider_gear.gd` (helmet, goggles, torso geometry), `rider_geo.gd`, `ragdoll.gd` |
| `scripts/world/` | `terrain.gd` (chunk streaming, LOD ground with skirts, decorations, water, debris, tape), `terrain_field.gd` (GDScript reference height field) + **`TerrainFieldCs.cs` / `TerrainFeatCs.cs` / `TerrainWoodCs.cs`** (C# port, must match exactly), `terrain_chunk_builder.gd` (worker-thread chunk build), `trail_course.gd`, `trail_features.gd`, `terrain_water.gd`, `terrain_debris.gd`, `tape_sim.gd` (torn tape ribbons), `atmos.gd` (wind, cloud shadows), shaders |
| `scripts/game/` | `game.gd` (one ride: interpolated drawing between physics states, crash/ragdoll, fx feeding), `camera_rig.gd` (**trail** = default: high, a little from the side, turns with the trail ahead; diorama/close/chase/side/iso/top/orbit/drone/trackside/dolly), `ride_audio.gd` (procedural sound) + `FreewheelSynth.cs` (freehub clicks: modal resonances fitted to a real hub recording, click rate = wheel speed × 24, tone never pitch-shifted) + `GravelSynth.cs` (tyre roll: ~500 pebble knocks per metre, damped rings around 650 Hz + cracks + casing rumble, fitted to a tyres-on-gravel recording within ~2 dB per band; tone per surface) |
| `scripts/garage/garage.gd` | the garage scene (room, open roller door with the real world outside, rollers, standing rider, all tabs) |
| `scripts/ui/` | `hud.gd`, `settings_menu.gd`, `tune_card.gd` (the one tuning card: Ride / Rider / Look / Sound tabs, each with category tabs), `quick_tune.gd`, `rider_panels.gd` (`POSE_DEFS`, `KITS`, `LOOK_ROWS` + saving), `ui_theme.gd` |
| `scripts/fx/` | `fx.gd` (dust puffs, dirt chunks, **tyre tracks**), `ride_dust.gd` (GPU dust trail, FogVolume clouds) |
| `shaders/` | `sky_hdri.gdshader`, `grade.gdshader`, `grime_mud/wet`, **`tyre_track.gdshader`** |
| `assets/` | `dh.glb`, `helmet.glb`, BMX model, decals (Fox, Cinelli, Glory, Maxxis…), `hdri/` (Poly Haven **Kloofendal 4K**), `textures/painted_concrete_02` (garage floor), `textures/broken_brick_wall`, `fonts/Doto.ttf` (Google Fonts dot-matrix, OFL — the HUD bike computer via `UITheme.lcd_font()`) |
| `tools/*.gd` | one-off headless test / measure scripts (`terrain_cs_cmp.gd` is the important one) |
| `docs/GRAPHICS.md` | quality presets, frame times, features, what was left out and why |
| repo root `tools/` | Houdini exporters `export_dh.py`, `export_bmx.py`, `export_helmet.py` → write into `godot/assets/` |

## 5. Systems — how they work

### Ride physics (`bike_physics.gd`)
- Fixed **120 Hz** `_physics_process`; `game.gd` draws **interpolated** between the last two states.
- Two-wheel contact with tyre springs, pitch, lean/countersteer, slip/skid, carving, flow speed, sprint
  stamina, gears (`gear_k()`: ungeared bikes = ratio 1, the DH uses the garage cassette + chainring).
- **Rider body as its own mass**: vertical leg spring (`body_y`, `riderMass`, `legStiff`…) with lip reading
  (crouch before a lip, pop, reach for the landing), **fore/aft body spring** (`body_x`, `hip_shift`: braking
  and landings throw the body forward, drive sits it back), **air control** (Space tucks the bike up about the
  shared centre of mass, W/S lean the nose; keys held at take-off count only once pressed again).
- **Sprint from slow** (`sprintKick`, `BikePhysics.slowness`): the slower the rider, the harder a sprint pushes (0–25 km/h 1.5 s vs 2.7 s pedalling), legs spin up, the bike is thrown side to side and the rider stands tall over the bars (`effort` in `rider.gd`). Stamping from below ~12 km/h pulls a **wheelie** (`sprintLift`); held, it climbs (`wheelieClimb`) until it loops out (~2 s); let go of sprint and it is set down (`wheelie_up`).
- **Body stick** (gamepad right stick, `body_fwd/back/left/right` actions → `inp.body_fwd`, `inp.body_lean`): fore / aft adds to
  `body_x` / `hip_shift` (reach `stickShift` × `weightShift`); past `manualFrom` pulled back it holds a manual (`manual_up` feeds
  `wheelie_up`, up to `manualAngle`); fresh at a lip it adds to `throw_in` (`lock_sb` / `lock_sf` like the keys); in the air it adds
  to W / S. Side lean: `flick` adds to the bike lean (`flickLean`), to the steer (`flickSteer`), extra turn / grip when it agrees
  with the steer (`flickTurn`, `flickGrip`), and an outward stick flick gives a yaw kick (`flick_kick`, `flickKick`). Sliders: Ride › Body.
- Every tuning value lives in `Tune` (tuning card, Ride tab + Rider › Physics); bikes multiply them (`BIKES.*.ride` + garage mods).
- **Air + landing are momentum physics, no scripted caps / assists**: on the ground `v` is the speed
  along the slope (it splits into horizontal `v` + climb `vy` at take-off and joins again at landing:
  the velocity into the slope is lost, along it kept). Take-off uses the rider + bike centre of mass
  (`PHI*body_v + mB*vy`). In the air the shared spin `air_w` is conserved (tuck = less inertia = faster,
  `tuckSpin`); the rider can only tilt the bike against their body (`air_tilt` ≤ `airTilt`, hands off it
  aims at the landing) and twist it at the hips (`air_tw` ≤ `airTwist`); yaw carried off a lip keeps
  turning. Flips start only from a **lip throw** (`throw_v`, `flipAccel`/`flipRate`: S/W pressed fresh
  while a jump is spotted ahead or one wheel is off; S there doesn't brake). Landing crashes come from the
  ground physics (nose-dive, loop-out, wash-out) plus **SLAM** when the legs bottom out with the body still
  moving into the bike faster than `slamJolt × land` (legs brace for 0.35 s after touch-down); only a bike
  turned > 83° from the slope (rider / bars hit first) or > 2.2 rad sideways is judged on contact.
  Consequence: at 70+ km/h rollers and bumps really launch you (the old `crestCap` hid that).
- **Tyres follow the ground, the frame floats (drawn)**: the frame is drawn where the physics put the body;
  each frame `BikeRig.fit_wheels` slides the fork / swings the rear (`Suspension.wheels_follow`) so each tyre
  just touches the ground within its travel (topped out in the air). Then the safety net: the physics tyres are soft and follow the smooth field,
  the drawn ground is a 0.5 m triangle mesh (higher in hollows) with rocks / decks. After posing, every
  frame `BikeRig.unclip_tyres(terrain.top_height)` samples each tyre (lower half, or all round when it
  lies over; 3 points across the round casing, `tyre_hw`) against `Terrain.top_height` = max(exact mesh
  triangles `mesh_height`, `height` with domes / decks) and lifts / tilts the drawn bike until clear
  (the physics isn't touched). ~1–2 % frame time. Rock meshes are only as exact as their domes.
- **Arcade air tilt** (`airArcade` 1 = on, 0 = pure physics): in the air W / S spin the bike at `airSpinRate`
  (eased by `airSpinResp`, stops at `airSpinStop` when let go), like old side-on bike games; the flight arc stays real.
- **Pump**: hold Space into a lip: the legs drive off it (`popKick` into body_v, and `pump_lift` added to the
  take-off vy as the ground pushing back); alone the rider only gives `autoPump` of it. After take-off he lifts
  the bike into the body (`airLift`, about the shared centre of mass), then reaches it down for the landing.
- **Springy rider**: the body rides soft legs (~1.5 Hz up / down) and feels the frame + wheel motion
  (`bumpAbsorb`, `bodyBounce` in Rider › Motion). `BMX_POSE=` now also works in a ride; `BMX_PUMP=1`,
  `BMX_LIP_SHOT=prefix` for tests; `BOUNCE body_rms` in the `BMX_CLIP_PROBE` output.
- **Rider › Style** sliders (pose keys): `hipSteady` (up / down leg spring), `standHeight`, `standBack`, `pedalChest`,
  `turnLow`, `turnTwist`, `turnHips`, `slowWobble`, `airCrouch`; Motion has `bodyBob` (pedalling up / down).
- Safety net: `is_sane()` / `reset_body()` — a non-finite step restores the last good state.

### Terrain
- Infinite world of 48 m chunks streamed around the rider on worker threads; ground as LOD grids
  (step 2/4/8 chosen by measured error) with skirts — no cracks; decorations are MultiMeshes with
  visibility-range fades (`VIS_RANGE` × the view-distance setting).
- Height field in **C#** (`TerrainFieldCs`), ~10× faster than GDScript (1.4–3.8 µs per height). The
  GDScript `TerrainField` is the reference: `tools/terrain_cs_cmp.gd` must report **EXACT** (≈736k
  comparisons, 0 mismatches). Switch: `Terrain.USE_CS`, env `BMX_TERRAIN_GD=1` forces GDScript.
- `Terrain.new(seed)` — pass the seed to the constructor (calling `set_seed` after builds the world twice).
- **Endless trail** (`trail_course.gd`): the mountain descent (1.4 km), then the trail runs on through the
  hills for ever, twisting (tight road bends, esses, switchbacks, rock chutes, jump lines), its height
  following the smoothed land. `TerrainField.COURSE_LEN` (4 km) is laid out at setup; when the rider is within
  `Terrain.GROW_AHEAD` (2 km), a worker grows it by `GROW_STEP` (3 km) into a NEW `TrailCourse` on a fork
  (`grow_course`, ~0.1–0.4 s), the main thread swaps it in (`adopt_course` + C# `rebind_course`, ~1 ms).
  Already laid-out trail, marking and route features never change (marking has its own RNG; stakes are
  stored in course order). Chunks read rocks / stakes / fences from per-chunk buckets, route features are
  binary-searched — nothing scans the whole course. `tools/trail_grow_probe.gd` checks all of it.

### Rider
- Procedural meshes posed every frame from the bike's grips/pedals with 2-bone IK; style dictionary
  (`Rider.NEUTRAL`) with a slider per bone: hips, **spine (hunch/arch, side curve, bend low/high, twist)**,
  **pelvis (tilt, roll/hip drop, turn)**, chest, head, shoulders, elbows, wrists, knees, heels, feet.
  Pose saved per bike in `rider.cfg`; edited in the garage Rider tab and the tuning card's Rider tab.
- The torso is **skinned to 5 spine bones** (Skeleton3D "Spine", identity binds) so it bends; its
  `custom_aabb` follows the body (needed in crashes when the rider node sits at the world origin).
- **Foot down at a stop** (`Game._update_dab` / `_dab_foot`, drawn only): nearly stopped, not pedalling, on the ground
  -> the foot on the lower pedal (level cranks: the side the bike leans to, else left) goes to `Terrain.top_height`
  beside the bike, the bike leans `DAB_LEAN` onto it, the body stays upright (rider `dab` input). Eases in 0.5 s, out
  0.4 s on pedalling or backing up (held brake). The physics is untouched (on a slope the bike may still creep).
- **Riding style** (matched to a reference clip of real downhill technique): rolling, the rider stands in
  the attack position (`stand` in `update_pose`, not only while pedalling); in turns the bike lays over
  well past the body (`bikeLeanMul` 1.55, cap 1.3 rad; the body leans ~70 % of the rider + bike lean,
  `counter` in `bike_physics.gd`: bike ~45–60°, body ~20–25° more upright) and the inside knee opens;
  pedalling out of the saddle swings the bike ~±6° (±10° sprinting) under a steady body; elbows bend
  back and down, only a little out (the arm IK pole's sideways part scales with `elbowsOut`). Saved poses migrate once (`RiderPanels.POSE_VER` / `POSE_RETUNED`: only values still
  at the old default change). `BMX_LEAN_SHOT=prefix` saves shots of the first deep leans.
- **Posture is the player's**: neutral (stick centred) is an upright attack position (torso ~30 deg from vertical);
  the right stick forward folds the rider down into the full tuck (`aero` in `rider.gd`, nothing tucks by itself at
  speed any more), back sits up tall and back.
- **Skeleton safety limits** (`rider.gd`, just before the torso length clamp): hips in a box over the bike, the
  torso bends only -26..80 deg forward and +-34 deg sideways from the bike's up; body counter-roll capped at ~50 deg.
  Whatever stacks up (tuck, spin, lean, landing, sliders) the body can't be mangled.
- **Air spin pose**: spinning in the air the rider sits tall and compact (knees in), head + shoulders lead.
- **Style points** (`bike_physics._style_points` -> `hud.StylePop`): air time, 360s, flips, tweak, x1.5 clean landing,
  combos (landings within 4 s chain and multiply); banked after 0.7 s, a crash before that = BAILED.
- **Brake to a stop holds** (`brake_stop`): no creeping, even on slopes; a fresh brake press from a standstill backs up
  (`brake_back`). Rolling backwards the cranks turn back with the wheel. Test: `BMX_HOLD_BRAKE=secs` (`HOLD` lines).
- **Wheelie / manual pose** (`rider.gd`, `slope` from the physics): the front up on the ground is not a climb; the
  rider sits back, upright, arms long (leaning into the raised bars mangled the arms). Climbs use the ground slope.
- **Joint limits** (`Rider.limb_ik`): elbows / knees are hinges that bend between `ELBOW_MIN`–`ELBOW_MAX` (12–150°) / `KNEE_MIN`–`KNEE_MAX` (4–160°); where a limb lines up with its pole the bend blends to a second pole (elbows: out + down, knees: up) instead of flipping, and the bend may swing round the limb at most `BEND_RATE` (6 rad/s). The slope body-levelling follows the bike pitch at most `PITCH_LEVEL_RATE` (it used to whip the torso mid-flip).
- Ragdoll on crashes (`ragdoll.gd`), then get up with Space. Ground friction is sliding (Coulomb `SLIDE_MU` once per
  substep, after the solver passes) so a fast fall slides a few metres. **Neutral body posture** (`NEUTRAL`, after
  NASA's microgravity studies: head ~24° forward, arms forward with elbows ~90°, hips + knees ~50°): inside `DEAD`
  (~15°) of neutral nothing pulls; past it a loose tension (`TONE`) pulls the part back, growing steeply past the soft
  limit (`LIMIT` ~35°, `LIMIT_K`), damped (`TONE_DAMP`). The pull is equal and opposite on part + parent (an
  uneven split used to launch the body). `BMX_RAGDOLL_PROBE=1` prints the mean offset from neutral + pelvis height,
  `BMX_RAGDOLL_TONE=k` scales the tension (0 = limp; also turns off everything below).
  **Still alive**: the first ~1.4 s the joints are held firmer (`ALIVE_K` 1.8x, smaller dead zone) so the body falls
  with bent joints; startle reflex: the arms fly up (`REFLEX` dirs for `REFLEX_T`, `HAND_FLING`), the feet kick a
  little up + forward (`FEET_KICK`); `SQUIRM`: a small wandering chest / pelvis twist, stronger on the ground.
  **Self-preservation** (`agency`, fades over `AGENCY_T`, only while the pelvis is well off the ground): a righting
  twist turns the spine upright (`RIGHT_ACC`), the legs reach down to land on the feet (`LEG_REACH`), the arms brace
  down + ahead after the startle (`ARM_BRACE`). Measured with `BMX_BLOOD_PROBE` (first `BLOOD hit i=` = first part
  down): 5 / 5 test bails land feet or hands first. Too firm (`ALIVE_K` 3+) made him pitch over head first.
  **No ejecting**: the crash start adds no upward pop (only the bike's own climb in the air), a mild forward spin;
  joint pulls never press a part that's on the ground into it, the twists are balanced, and reaching stops once a
  foot / knee / hand is down (all three used to launch the body). `BMX_RAGDOLL_PROBE` prints `rise` / `vup` (how
  high / fast the centre of mass went up from the crash start; now ~0.01 m) and `RAGSTART` (buried parts, start v).
  Ground friction `SLIDE_MU` 1.1 + `SLIDE_DRAG` 0.97.
- **Blood** (`fx/blood.gd`, Settings › Gameplay › Blood): bleeding ragdoll parts that slide drag smears
  (`shaders/blood_streak.gdshader`, one MultiMesh ring of 1500 flat quads, world-space noise so pieces join; fresh
  = dark glossy red, dries matt in 45 s), hard touch-downs leave splats + droplets (`fx.chunk`). No blood on the
  rider (the user didn't want it). A respawn fades all of it out over `WIPE` (4 s; shader `wipe_t`).
  **Torn-off limbs**: a crash > `SEVER_SPEED` (16 m/s) tears off the first limb hitting hard (> 3), any limb hit >
  `SEVER_HIT` too, at most `SEVER_MAX` (2) per crash; hand / foot hit = at the elbow / knee, elbow / knee hit = at the
  shoulder / hip. `Ragdoll.sever(a)` drops bone a-b and gives the free piece its own root point (appended to `p`,
  `cut[b]` = its index); `Rider.pose_ragdoll(P, roots)` draws that segment from the root. Dark red caps on both
  ends, the stump spurts in pulses for 2.5 s. The head never comes off (the user didn't want it). Getting up
  restores the body. Tests: `BMX_BLOOD_PROBE=1` (hits / smears / severs), `BMX_SEVER=1` forces one.
- **WASTED** (`fx/wasted.gd`, Settings › Gameplay › Crash slow motion): on a crash time drops to 0.22× (sound pitched down via
  `AudioServer.playback_speed_scale`) for ~2.4 s real time, then eases back; the screen goes grey + vignette, the word
  WASTED shows at once for 1.5 s then fades (the rider + bike drawn in front of it via a silhouette mask), flat red, squeezed narrow to fill the screen (no band, no stroke), the crash reason small below. Fades on getting up or after 5 s. Off in autotests unless `BMX_WASTED=1`.
- Look: kits + a colour per part (helmet shell/peak, goggles, jersey, pants, gloves, shoes).

### Ride light (time of day)
- **Default: golden hour** (19:20, sun ~10° up). Everything comes from the clock: `Game._apply_light(hour, LightSettings.current)`
  sets the sun (or the **moon** at night, opposite it), sun colour / strength, shadow bias + softness, the sky mode
  (`sky_hdri.gdshader`: `sunny` by day, `golden` low, `night` = stars + moon + dark clouds), ambient, fog colour,
  haze, exposure, saturation / contrast. Sun height `Game.sun_elev_deg(h)`: up 6:00, 62° at 13:00, down 20:00;
  16:00 = the old clear-afternoon look. The HDRI is turned so its photographed sun follows ours.
- Tuning card **Light** tab (`scripts/core/light_settings.gd`, `user://light.cfg`): Time (preset, live clock, time
  slider, day / night cycle switch, day length, sun direction) and Light (sun, warmth, sky fill, moonlight,
  exposure, haze, shadow softness, saturation, contrast). Presets: Golden hour, Sunrise, Morning, Noon, Afternoon,
  Dusk, Night, Day / night cycle + the player's own. With the cycle on, Game runs the clock and re-applies 10× / s.
  Tests: `BMX_LIGHT_PRESET=Night`, `BMX_LIGHT=time=12,haze=2`, `BMX_PANEL=light`.

### Title screen (golden hour lookout)
- `Game.set_scenic(true)` while the menu is up: a low warm sun ahead-right of the view, golden sky mode in
  `sky_hdri.gdshader` (`golden`: warm gradient + sun glow, the HDRI's clouds re-lit), warm long fog.
- Camera `vista` mode (`CameraRig.VISTA`, not in the C cycle): behind/above the rider facing `_best_view()`
  (clear near eye line + hills far off), slow sway, drag turns it.
- `FarHills` (`scripts/world/far_hills.gd`): coarse ground + far trees out to 2.6 km, built on a worker
  thread; past ~450 m it adds rolling ridges (title screen only) so every seed has a hilly skyline.
  Freed and the normal light restored when the ride starts. `BMX_SEED` now also fixes the menu world.

### Garage (`--garage` or from the menu)
- Brick room, painted-concrete floor, **open roller door straight behind the bike** with the real
  procedural world outside (a Terrain rotated 90° and sunk under the floor), front wall closing the room,
  warm shed lights + HDRI sky, SDFGI, volumetric fog. The door rolls up on the first visit each session.
- Camera: subtle **handheld** front view, drag to orbit, wheel to zoom, **always kept inside the room**.
- Tabs: Paint (parts × colour × NFS-style finishes: gloss/metallic/pearl/candy/satin/matte/chrome/anodized),
  Logos (spots, built-in logos, import your own PNG, tyre lettering, rim decals: lettering or any logo,
  1–4 per side), Wheels (26/27.5/29; **tyre models** Maxxis/Schwalbe/Michelin/Continental/Specialized →
  tread pattern + round/square casing + brand on the sidewall; **rim models** DT/Mavic/Race Face/Spank/
  Stan's/e13/We Are One/Reserve/Crankbrothers/Zipp → profile hooked/hookless/box/deep V/round, alloy or
  carbon weave, brand on the rim; spokes, lacing, gauge, colours), Bars (`handlebar.gd`: width 740–820,
  rise 0–50 mm, alloy / carbon; reshapes the dh.glb steer mesh, grips + levers follow), Shocks, Gears
  (chainring, cassettes), Rider (rider on **training rollers**, preview situations, every bone slider),
  Kit (rider standing beside the bike).
- Compact UI drawn at `UI_SCALE` 0.82 with a fixed-width card; long labels ellipsize.
- Bike height is placed from the **real tyre size and real axle positions** (no tyre clipping into the floor
  or the roller drums; verified with `BMX_TYRE_PROBE`).
- Saved in `garage.json`; `GameState.bike_config()` applies it to the ride.

### Effects
- **Dust = a real 3D smoke simulation** (`fx/smoke_sim.gd` + compute shaders `shaders/smoke/*.glsl`): a
  128×32×128 grid (0.2 m voxels, 25.6×6.4×25.6 m) of air on the GPU that follows the rider (moves in
  0.8 m steps, ahead along the heading) and follows the ground (voxel height is measured from a
  terrain heightmap). Each frame: advect (velocity + dust, settling, wind, sources) → curl-noise
  turbulence → vorticity confinement → pressure solve (red-black GS) → project → sun/sky light volume →
  occupancy bricks. Drawn by raymarching (`smoke_render.gdshader`, empty-space skipping via the bricks,
  3-octave noise erosion for wisps/billows). Sources: rear-wheel roost (pulsed + jittered, `RideDust.feed`),
  dust from the tyre contact patches only (rear + a third at the front, gusty spray), landing dust squeezed
  out from under both tyres (`landing_dust`), crash dust under the ragdoll and the sliding bike (`Game._crash_dust`), skid
  clouds (`cloud`), `burst()` / smashes (`puff_burst`), the bike's wake; faster riding = more turbulence
  and quicker spreading. Stops when
  the air is clear. Dust carries its own colour (colour-mass textures, sources pass their ground
  colour); the bike's wheels (spinning), frame and rider are solids the air flows round (`Game._body_parts`);
  the render darkens the ground / bike under the dust with the light volume (dust shadows) and uses a
  3-octave multiple-scattering approximation. **Grit** (`fx/grit.gd`, `shaders/smoke/grit*.gdshader`):
  GPU particles (grains 5 mm–3 cm) carried by the sim's air velocity texture, sunlit + glints, land and fade.
  **Drawn by `fx/smoke_compositor.gd`** (a CompositorEffect on the ride camera): half-res raymarch
  (`smoke_march.glsl`) → temporal blend with reprojection + neighbourhood clamp (`smoke_taa.glsl`) →
  depth-aware upsample + composite over the scene (`smoke_comp.glsl`). `sd.get_cam_projection()` is already
  Godot's RD projection (reversed depth, y flipped): use it with ndc = (uv*2-1, depth). `BMX_SMOKE_BOX=1`
  forces the old box-mesh renderer (`smoke_render.gdshader`, the fallback).
  `.glsl` files need an import (`--headless --import`) after editing. Falls back to the
  old sprites / FogVolumes without a RenderingDevice; `BMX_SPRITE_DUST=1` forces the sprites.
- **Dust tab** in the tuning card (Tune groups `Dust look` / `Dust trail` / `Dust spray`, keys `dust*`, read live every frame by `SmokeSim._read_tune` and `RideDust`): thickness, wispy edges, rise, swirl, curls, grit; fade speed, spread, wind, room ahead of the rider (the sim box trails behind: `ahead` 3 m = ~22 m of trail); rear / front amount, spray width, sideways, kick-up, throw, gusts, landing clouds. Ride presets leave `dust*` alone; Reset puts them back to the defaults. Test: `BMX_PANEL=dust`, `BMX_TUNE=dustOpacity=2`.
- Dirt chunks, **tyre tracks**: one ring-buffer ArrayMesh
  (14 000 segments ≈ 1 km/wheel, one draw call, each segment uploads only its own bytes) drawn by
  `tyre_track.gdshader` — lit, knob-tread dimples bump-mapped, soft edges + soil lip, skid streaks, distance fade.
- Grime: mud builds up (slow: `Grime.MUD_RATE` 0.25) and washes off in water; wet gloss + drips. Passes
  are removed from shared materials when a ride ends.
- **Cacti** (`world/cactus_geo.gd`): five kinds (saguaro, tall saguaro with blossoms, barrel with a flower
  crown, organ pipe, prickly pear with fruit), each its own MultiMesh list `cactus0..4`. Built from ribbed tubes
  swept along splines (arms bend out of the trunk and up as one tube, flared at the root), spine clusters on
  every rib, own-colour parts via `tint` (UV.x) + `deco.gdshader` `tint_own`. Smashing one breaks it along a
  **Voronoi fracture** precomputed per kind on a worker thread (`CactusGeo.fracture`: closed-mesh plane clipping +
  capped cuts in flesh colour, seeds denser at bike height); chunks get convex hulls, collide with each other,
  and are flung by their distance from the hit (`TerrainDebris.smash_cactus`). Check: `tools/cactus_probe.gd`
  (every body / piece closed, piece volumes = whole, must say `PASS`).
- Torn race tape as cloth-like ribbons, wind over the grass, drifting cloud shadows, speed blur / FOV.

### HUD bike computer (`hud.gd` `GaugeView`)
- Garmin-style computer bottom-left; six pages flipped with the ◀ ▶ bezel buttons under the screen (mouse):
  **RIDE** speed, slope / grade, gear (the shifter: n/N, cassette, teeth; flashes on a shift; Settings › Gear
  shifter hides the row) · **TRIP** ride time, distance, avg / max, odometer (`records.distance`, now counted) ·
  **EFFORT** heart rate (made up from power, sprint, stamina; beating heart, zone), cadence (from `crank`),
  power (from `a_drive`), stamina, gear ratio · **AIR** last jump, height, air time, best, jumps, tricks
  (`BikePhysics._land_trick` → `game.on_trick` → `hud.on_trick`) · **ELEV** elevation, ascent / descent, the last
  30 s + the next 400 m of trail coloured by steepness (from `course.E`) · **MAP** (`MapView`) heading-up 2D topo,
  170 m across: contours (5 m, every 25 m bolder; marching squares over a 6 m height grid, 4 rows a frame,
  rebuilt after 40 m), trail centreline, the last 90 s ridden in magenta, north dial, 50 m scale.
- **Alerts** (`hud._trail_scan`): the next bend (`course.KAP`, > 0 = right; LEFT / SHARP / HAIRPIN by the total
  turn), route feature (`route_feats`: tabletop, kicker, rollers, bridge…) or rock garden within 120 m; a banner
  pops up over any page when a new one appears, then stays from 40 m in. Off the trail (> 15 m) or riding it
  backwards: no alerts. `BMX_ALERT_PROBE=1` walks 2.4 km of trail and prints every alert.
- Piezo sounds (`ui/garmin_beep.gd`, rendered once into AudioStreamWAVs): a rising power-on chime 0.35 s after the
  HUD shows (ride start), a short key beep on the ◀ ▶ bezel buttons.
- Small touches: "acquiring satellites" for the first 3 s of a ride, battery icon (drains 60 %/h of riding),
  backlight for 3 s on a button press or a new alert.

### Settings & tuning
- Settings: display (mode, resolution, vsync, UI scale, FPS cap), graphics presets Low/Medium/High/Ultra
  + every option, audio buses, controls (rebind keys + pad), gameplay. Sliders apply on release.
  Controls page starts with CAMERA: default camera, FOV, wider view at speed, distance, height, side offset,
  look ahead, follow speed, shake, mouse, re-centre after a drag, keep the rider in view (`_keep_rider_in_view`),
  fade things at the lens (`deco.gdshader` dithers trees / rocks within ~3 m of the camera; globals `cam_see` / `cam_eye`).
- One tuning card (`TuneCard`): tabs Ride (Steering, Lean, Grip, Speed, Suspension, Jumps), Rider (Body, Spine,
  Head, Arms, Legs, Motion, Physics) Look (Kits, Helmet, Clothes) and **Sound › Freewheel** (every `FreewheelSynth` knob: volume, engagement, pitch, ring, brightness, snap, detune, pawl unevenness, wobble…; built-in hub presets + the player's own named presets with Save as / Delete, saved in `user://freewheel.cfg` by `scripts/core/freewheel_sound.gd`; Preview spins the wheel while standing). Skids play the gravel synth louder and grittier (no separate hiss). P / K / L open it on Ride / Rider / Look,
  **Ride presets** sit on top of every Ride / Rider › Physics category (`scripts/core/tune_presets.gd`: built-ins Default, Flowy, Grippy, Drifty, Floaty air, Fast + the player's own via Save as / Delete, in `user://tune_presets.cfg`; an own preset follows its sliders). Reset puts the category back to the active preset's values. Quick tune card keeps the pinned (☆) sliders. Test: `BMX_PANEL=ride|rider|look|sound`
  + `BMX_PANEL_CAT=<n>`.

## 6. Testing (the game drives itself — use these, don't ask the user to check)

Run with the **console** exe so prints show. Every test run quits by itself.

| Flag / env | What |
|---|---|
| `-- --autotest=N` | rides N s unattended, prints `AUTOTEST frames= fps= pos= v= crash= sane=` |
| `-- --shot=path.png@secs` | screenshot after secs (works with `--garage`) |
| `--bench=<dir> [--quality=N] [--set=key=value]` | frame times + screenshots per preset |
| `--showcase=<dir>` | forces each effect on and saves screenshots |
| `--hitch=<secs>` (+ `BMX_HITCH_CSV`) | hunts frame spikes and explains them |
| `BMX_SEED=4242` | fixed world (4242 is the usual test seed) |
| `BMX_CAM=chase` / `BMX_CAM_ORBIT=rad` | camera mode / angle for autotest shots |
| `BMX_SHOT=file.png` | screenshot at the end of an autotest |
| `BMX_STRAIGHT=1` | autotest rides straight (no steering/hops) — good for track shots |
| `BMX_IDLE=1`, `BMX_NOVSYNC=1`, `BMX_LOD=`, `BMX_NOLOD=1`, `BMX_PANEL=`, `BMX_PAUSE=`, `BMX_TAB=` | misc |
| `BMX_BODY_PROBE=1`, `BMX_AIRPULL=1` | prints the rider-body numbers / tucks in every jump |
| `BMX_GARAGE_TAB=paint…kit`, `BMX_GARAGE_RIDER=coast/pedal/sprint/descend/air` | garage tab / rider preview |
| `BMX_GARAGE_CAM=orbit,pitch,dist`, `BMX_POSE=key=val,...` | garage camera / pose override |
| `BMX_GARMIN_PAGE=0…5` | bike computer opens on that page (ride, trip, effort, air, elev, map) |
| `BMX_ALERT_PROBE=1` | prints every Garmin trail alert along the first 2.4 km of trail |
| `BMX_TRICK=back/front/side/manual/none` | autotest throws back / front at every lip (fresh S / W press) and keeps leaning in the air; none = hands off (side alternates A / D; manual holds the nose up at `BMX_MANUAL_PITCH` rad for back-wheel landings) and prints `TRICK` / `LAND` / `BOUNCE` / `CRASH` |
| `BMX_FOLLOW=1` (+ `BMX_TRICK=…`) | autotest steers along the trail centreline and gets up (back on the trail) 2 s after a crash; prints `TAKEOFF` / `JOLT` too — the way to get many jumps |
| `BMX_CLIP_PROBE=1` (+ `BMX_NOUNCLIP=1`, `BMX_CLIP_SHOT=file.png`) | measures how deep the drawn tyres go into the ground; prints `CLIP … frames_inside=` (must be 0). NOUNCLIP turns the fix off for comparison; CLIP_SHOT saves a screenshot when a tyre was 12+ cm in |
| `BMX_STEER=1` / `-1` (+ `BMX_STRAIGHT=1`) | autotest holds a steady left / right turn after 2 s (lean / leg-clearance shots) |
| `BMX_AIRSHOT=dir/prefix` | autotest saves up to 8 screenshots mid-air |
| `BMX_LIMB_PROBE=1` (+ `BMX_FOLLOW=1 BMX_TRICK=back BMX_BIGAIR=1`) | per elbow / knee: fastest bend swing per frame (`turn_max`), biggest joint move, `flips` = frames a bent limb swung 25+° (should be ~0; worst frames printed as `LIMBW`) |
| `BMX_KNEE_PROBE=1` | prints the biggest knee / hip move per frame and the torso stretch range, and logs (`KNEE …`) frames where a knee jumps |
| `BMX_TUNE=topSpeed=1.6,grip=1.1` | overrides tuning values for a test run (not saved) |
| `BMX_LAUNCH=pedal/sprint` (+ `BMX_LAUNCH_HOLD=secs`, `BMX_LAUNCH_SHOTS=dir/prefix`) | autotest stops at 3 s and pedals / sprints away: prints 0–15/25/35 km/h times, nose-up angle, wheelie time, loop-out; HOLD lets go of sprint after secs |
| `BMX_VMAX=1` | autotest prints the top ground speed reached (`vmax_kmh`) |
| `BMX_BIGAIR=1` (+ `BMX_TRICK=front/back`) | autotest launches every jump high (1.4 s air) so full flips happen |
| `BMX_PITCH_POSE=rad` / `sweep` | draws the bike at a fixed pitch (or spinning through flips) for rider-pose shots |
| `BMX_TYRE_PROBE=1` | measures tyre-to-floor / tyre-to-drum gaps for 12 wheel setups, then quits |
| `BMX_BUILD=wheels.rim_model=deemax;bars.width=820;logos.rims.count=4` | overrides the garage build for a test run (not saved unless you touch a control) |
| `-s res://tools/terrain_cs_cmp.gd --headless` | C# vs GDScript terrain must be EXACT |
| `-s res://tools/trail_grow_probe.gd --headless` | grows the endless trail 6×: old trail unchanged, C# = GDScript, timings; must say `PASS` |
| `-s res://tools/cactus_probe.gd --headless` | cactus kinds + Voronoi fracture: closed pieces, volumes add up; must say `PASS` |
| `-s res://tools/wood_edge_probe.gd --headless` | drives angled lines onto every wooden ramp; must report `walls=0` |
| `BMX_FW_PRESET=<name>`, `BMX_FW=pitch=1.3,poe=60`, `BMX_FW_PREVIEW=<m/s>` | freewheel preset / values / Preview for a test run (not saved) |
| `BMX_FLOW_DEMO=1` | HUD flow meter: adds a flow level every 0.9 s from 3 s up to MAX, then lets it drain (pair with `BMX_DUST_SHOTS` for screenshots) |
| `BMX_GETUP_K=0.6` | draws the get-up prompt as if the key were held that far (with `BMX_BAIL`) |
| `BMX_AUDIO_PROBE=1` | prints the freewheel's click rate / volume / output peak and the gravel surface / level twice a second |
| `-s res://tools/gravel_render.gd --headless -- out.wav [speed=8 tone=650 crack=0.3 …]` | renders the gravel synth alone to a WAV (compare with a recording) |
| `BMX_PAD=1` | as if the player were on a gamepad (`Settings.pad_active`: Xbox prompts, triggers don't tilt / throw in the air); `BMX_TRICK=hold` keeps pedalling through the air |
| `BMX_BODY=manual/fwd/lightfwd/lean/flick` (+ `BMX_BODY_PRINT=1`) | autotest works the body stick from 3 s (right stick) and prints `BODY` lines: stick, flick, manual angle, pitch, bike lean, yaw |
| `BMX_STOP_AT=a,b` / `BMX_IDLE_FOR=secs` | autotest brakes to a stop from a s and rides off at b s / stands still, then pedals |
| `BMX_DAB_PROBE=1` | foot-down probe: `DAB` lines with dab level, foot side, shoe speed on the bike in / out of the dab vs pedalling, sole gap to the ground |
| `BMX_WATER_SPAWN=1` | autotest starts 9 m from the nearest lake, facing it (water shots; seed 4242 → a desert lake) |
| `BMX_COAST=1` | autotest alternates 3 s pedalling / 3 s coasting (freewheel tests) |
| `BMX_REC=file.wav` | records the game's own sound output during an autotest |
| `BMX_SKID=secs` / `BMX_DUST_SHOTS=dir/prefix` (+ `BMX_DUST_T0`) | autotest locks the rear wheel from secs / a screenshot every 0.5 s (dust tests; `BMX_CAM=side` avoids the tilt-shift blur) |
| `BMX_WASTED=1` (+ `BMX_BAIL`, `BMX_DUST_SHOTS`) | crash slow-mo / WASTED screen in an autotest (off there by default) |
| `BMX_LAND_TEST=secs` / `BMX_BAIL=secs` | autotest fakes a hard landing (landing dust) / bails (crash dust) at that time |
| `BMX_DEBRIS_PROBE=1` | fence / cactus debris: moving / resting counts and the lowest piece (none may fall through the ground) |
| `BMX_SPRITE_DUST=1`, `BMX_SMOKE_PROBE=1` | old sprite dust for comparison / smoke-sim timing prints |
| `BMX_FENCE=dir/prefix` (+ `BMX_FENCE_STYLE=ranch/picket`) | autotest rides into the nearest fence, screenshots before / after the smash |

Typical check after a change: build C# → `--autotest=10` with `BMX_SEED=4242` (sane=true, no SCRIPT ERROR)
→ a `--shot` of what changed → look at the PNG. Frame rate reference: ~46–58 fps at 1600×900 with vsync
and other GPU apps open; uncapped ~430 fps on an RTX 3090 after the C# terrain.

## 7. Lessons learned (Godot 4.7 / C# gotchas)

- **C#**: packed arrays are `Vector3[]` / `float[]` (no `PackedVector3Array` type). Code using the
  `Godot.Vector3` struct in hot loops ran ~4× slower than plain float arrays — use SoA float arrays.
- GDScript → C# calls cost; batch work into one call per frame / per piece.
- A script run with `-s` (SceneTree `_init`) hangs when it builds the garage; use `--garage` + `--shot` instead.
- Build heavy scenes *before* the first frame or behind the fade (first frame gets a huge `dt` — clamp it).
- `ButtonGroup` tabs: set `button_pressed`, not just a style, so one tab stays lit.
- `Control` added to a page's parent instead of the page → empty settings tabs.
- Skinned meshes: the culling box is in mesh space — give a `custom_aabb` and move it with the body.
- Shared materials (glb imports, caches) are shared across rides: undo any `next_pass` you add.
- `FogMaterial.height_falloff` is world-height based (keep 0); a `FogVolume` hidden before entering the tree
  never shows again; shader `#define` doesn't continue across lines; `light()` built-ins can't be used in helpers.
- Coplanar faces flicker (door rails vs wall): offset parts off shared faces.
- `GPUParticles3D.emit_particle()` didn't draw in 4.7 tests → drive a continuously emitting node instead.
- `Engine.time_scale = 0` (photo mode) must be undone when leaving to menus/pause.
- Every `WorkerThreadPool` task must be waited for before quitting (`_exit_tree`), static ones too: the cactus
  fracture task (`CactusGeo.join()`, called from `Terrain._exit_tree`) still running at exit crashed every quit
  (0xC0000005 in ntdll, exit code 139 in bash, no Godot backtrace). Check test exit codes, not only the output.
- PowerShell `Get-Content`/`WriteAllText` can change line endings — prefer the Edit tool for code edits.
- Light through a doorway straight at the camera = glare; keep the sun high and to the side in the garage.

- Tyres are never drawn in the ground: see "Tyres follow the ground" in section 5 (`BikeRig.fit_wheels` / `unclip_tyres`). Smashed-fence / cactus debris is held above the terrain every physics
  tick (thin pieces used to tunnel through the chunk collision and vanish).

## 8. Decisions & the user's preferences (follow these)

- **Godot only.** All work in `godot/`; the repo holds nothing else but the Houdini exporters. No web version,
  no browser/WebGL constraints.
- Leave the bike builder out. DH is the main bike. Garage changes must **not reset the camera**.
- Garage: bike centred, open door straight behind it with the landscape outside, shed-like light, handheld
  front camera (subtle, not spinning), the room closed on all sides.
- Floor: Poly Haven "Painted Concrete 02" — plain, not grimy (the user disliked stains/dirt).
- Cloth sim and shoulder pads were tried and **removed** at the user's request — don't bring them back.
- Mud should build slowly. Tyre tracks: bold, with visible knob dimples.
- Garage UI: compact, sleek, narrow card that doesn't cover the bike.
- **Windows:** test runs must quit on their own; when opening the game for the user, close earlier windows
  first so exactly one is open, running the latest code. Don't close the one the user is using mid-test.
- Ask before downloading anything (say filename, source, size). Free assets from Poly Haven etc. are fine.
- Commit only when asked; ask before merging other branches. Commit messages end with the
  `Co-Authored-By` line the session gives.
- The user writes short, often typo'd messages (e.g. "merhe" = merge) — read intent, act, show screenshots.
- Prefer doing and verifying (screenshots, autotests) over asking the user to check.

## 9. Status & open items

Recently done (most recent first): dust is a real GPU smoke simulation (no sprites); bolder tread tyre tracks; no tyre clipping in the garage; compact garage
UI; door/flicker/glare fixes; closed front wall + camera kept in the room; ride-camera drag direction
matches the garage; slower mud; review fixes (crash torso culling, NaN freeze, BMX gearing, leftover mud,
photo mode, controls card, view distance, double world build, water re-bake, settings slider drag, garage
rebuild hitch); rider body physics (fore/aft + air tuck/lean); bending spine + pelvis sliders.

All of it is on `main` (the Godot branch was merged, the web version removed). Work continues in this repo.

Known, not fixed (lower priority from the code review):
- Records: "distance ridden" always 0; top speed lost if the window is closed instead of quitting.
- Camera ignores rebound gamepad/camera keys (reads the right stick directly); `cam_up/down` unused.
- Quick tune card sliders can show stale values after a reset (the tuning card re-reads on every tab).
- HUD hotkeys (P/K/L/H) work on the title screen.
- Rebinding: no conflict detection; pad rebind can't be cancelled.
- Garage: test env `BMX_POSE` values get saved if you then touch a slider; config written on every slider tick.
- Stale code: `set_torso` (unused), `hood_hem`, `_grid_indices`, `_time`, some one-off `tools/*.gd`
  (`fork_measure`, `wheel_measure(2)`, `inspect_glb`, `hdri_sun`).
- Perf ideas: ragdoll terrain sampling, HUD stylebox allocations per frame, fx dust buffer upload when idle,
  `terrain.jump()` array allocation per physics step.

Ideas offered, not started:
- Tyre tracks option **B**: a painted top-down "track map" the ground shader reads → real ruts in mud/sand.
- A skinned rider model, ground PBR textures, dense grass, time of day + weather, chain animation,
  garage props, loading screen, an art-style decision.
- Rider solvers: terrain look-ahead (pump / pre-jump anticipation) and a balance/centre-of-mass solver.

## 10. Setting up on a fresh checkout or machine

1. Clone the repo; the game is `godot/`, the Houdini exporters are root `tools/`. The root `CLAUDE.md`
   already loads this guide into every chat.
2. Install Godot 4.7.2 .NET and the .NET 8 SDK (section 2).
3. Open with the .NET Godot once (imports assets, builds C#), or run `dotnet build` in `godot/`.
4. Smoke test: `BMX_SEED=4242` + `--autotest=10` → `sane=true`; `tools/terrain_cs_cmp.gd` → EXACT.
5. Recreate the two memory notes if wanted: "Godot only" and "one game window, tests quit themselves".

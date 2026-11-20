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
- **More downhill frames** (B / the ride setup page cycle them, the garage builds whichever is selected; flag `garage` in `GameState.BIKES`):
  **YT Tues** (`assets/tues.glb`, from a full-bike FBX by `tools/export_tues.py`, Blender: frame, its own fork / bars / brakes / cranks,
  Horst-style linkage mapped onto the game's four-bar `Suspension`; wheels, tyres, shock paint etc. are the garage build) and **Goat DH**
  (`assets/dhframe.glb`, Sketchfab "DH bike frame" by Once_a_goat_death, **CC-BY 4.0: credit needed wherever the game is shared**, text in
  `assets/dhframe_LICENSE.txt`; `tools/export_dhframe.py`: its frame, single-pivot swingarm and coil shock on our fork / bars / cranks;
  the solver gets G1 = G2 so the swingarm turns rigidly about its pivot; its link bars stay on the frame). Both ride the normal pipeline; the Tues
  carries `noBarMod` / `noDecals` in its extras (own bars, logo slots are placed for GLORY). Extracted Tues parts for reuse:
  `assets/parts/tues_fork.glb`, `tues_cranks.glb`, `tues_cockpit.glb`, `tues_brakes.glb` (not wired into the garage yet). Test: `BMX_BIKE=tues|goat|dh`.
  **NS Fuzz** (`assets/fuzz.glb`, `tools/export_fuzz.py`, same recipe as the Tues: own fork / bars / brakes / cranks / derailleur, coil shock with a
  `shock_spring` node, parts in `assets/parts/fuzz_*.glb`). Both the Tues and Fuzz (and Goat) draw the chain + derailleur pulleys with `BikeChain`
  (`scripts/bike/bike_chain.gd`, enabled by `chain` in the glb extras; the Goat uses the Tues derailleur and pedals). `tools/bike_glb.py` = shared glb writer.
  Not done: swapping the Tues fork onto the GLORY as a fork model.
  **Stickers on every frame**: the logo slots (down / top tube, chainstay, fork legs) carry a `slot` name; frames flagged `noDecals` (Tues, Goat, Fuzz) get them placed by `BikeDecals.fit_label` from the model's own vertices (crank = bottom bracket, steer = head tube, tube direction found by vertex density, fork leg by a line fit), then the same flat projection as the GLORY bakes them into a mesh. New frames need no hand-set numbers.

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
& "...mono_win64.exe" --path godot -- --rider    # the rider room
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
H records · **M trail map** (pad: Share) · **P / K / L** the tuning card on its Ride / Rider / Look tab · **O photo mode** (free camera, see section 5) · F1 hide HUD ·
F12 screenshot · **F11 / the small button bottom right: fullscreen on / off** (`ui/fullscreen_button.gd`, on every screen,
saves Settings › window mode; in the garage it sits above Save / Save & ride) · Esc pause. Gamepad (Xbox): triggers pedal/brake, left stick steer, X hop (jump), A sprint, bumpers gears, Y camera, D-pad left / right rotate the camera,
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
| `scripts/game/` | `game.gd` (one ride: interpolated drawing between physics states, crash/ragdoll, fx feeding), `camera_rig.gd` (**trail** = default: high, a little from the side, turns with the trail ahead; C / pad Y cycle: trail, **helmet** (POV from the action cam on the helmet, `Rider.action_cam` built by `rider/action_cam.gd`, lightly stabilised, chase view while crashed; in a crash the camera body snaps off its hinge and tumbles away, `fx/flying_cam.gd`, a new one is on after getting up), chase, **drone** (banks into turns, noses down with speed, hovers in gusts, prop buzz + `ui/drone_osd.gd` REC / height / distance overlay), side, dolly, close, diorama, trackside, orbit, iso, top), `ride_audio.gd` (procedural sound) + `FreewheelSynth.cs` (freehub clicks: modal resonances fitted to a real hub recording, click rate = wheel speed × 24, tone never pitch-shifted) + `GravelSynth.cs` (tyre roll: ~500 pebble knocks per metre, damped rings around 650 Hz + cracks + casing rumble, fitted to a tyres-on-gravel recording within ~2 dB per band; tone per surface) |
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
- **Graded landing zone** (`LAND_CONE` 1.05 rad ~60 deg): heading within the cone of the travel = normal landing. Past it the tyres grab the
  nearer axis instead of a wash-out crash: < 90 deg = forward "SKETCHY!", > 90 deg = backwards "FAKIE!". The travel is dragged round to within
  0.9 x `slipMax` of the heading, speed scaled by cos(angle dragged), the rest decays as a slide. `BMX_FAKIE=<deg>` forces the angle.
- **Fakie (backward landing)**: `_land_trick` sets `_land_fix` / `_rev_land`, the touch-down makes `v = -v` (reverse speed may exceed 3 m/s via `rev_cap`, which shrinks back; braking works in reverse, pedalling
  doesn't drive while `rev_cap > 3`). Rolling back (v < -0.5) with **both sticks towards the pad's centre** (left stick right + right stick
  left, held 0.1 s) flips the travel (`course += PI`, `v = -v`, "SWITCH!") and the drawn heading swings round via `turn_off`. Test:
  `BMX_FOLLOW=1 BMX_FAKIE=1` (`FAKIE` lines).
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
- **Tyre grip sim** (`BikePhysics._grip_step`, Ride › Grip › *Tyre grip sim*): the slip (heading vs travel) is a second-order
  motion `slip_w`: the rear tyre's sideways grip `grip_r` (friction circle after braking / driving × rear load × the loose patch
  under it, `loose` from a noise field per surface) pulls it back, the front tyre pushes it round, the rider catches it
  (`gripCatch`, drawn countersteer `bar_catch`). Locked rear = fishtail (`gripRearLock`), wheelspin in a turn steps out
  (`gripPower`), pedal stamps / bumps (`gripBumps`) / chatter nudge it, tyres run a few degrees of slip angle in turns
  (`gripSquirm`), the rear swings round the front (`gripPivot`). Probe: `BMX_GRIP_PROBE=1` (`GRIP` lines).
- **Right-stick lean is filtered** (so both sticks together don't glitch): `Game._read_input` fades the off axis near an axis
  (a side lean within ~15-35 deg of sideways carries no fore / aft: no accidental manual / tuck) + a 0.1 round deadzone; the
  physics follows the stick on a critically damped spring (`flickSpeed`, top speed `FLICK_VMAX`); the lean-with-steer bonus
  (`agree`) is continuous; the flick yaw kick fires only for a deliberate throw centre -> edge within `FLICK_WINDOW`, once.
  (The old raw-derivative kick fired on ~47 % of frames with a real thumb.) Test: `BMX_PAD=1 BMX_BODY=thumb` (+ `BMX_FOLLOW`).
- **Bank and lean room ignore rocks / logs** (`terrain.deck_height`): a rock under or beside a wheel used to read as a 30 deg
  berm / a wall and snap the lean. Bank is read across both axles, +-0.5 m. The wheels still ride over the rocks.
- **Physics overlay** (F3, `BMX_DEBUG_DRAW=1`, `scripts/game/debug_overlay.gd`, addon `addons/debug_draw_3d` = Debug Draw 3D
  1.7.3, MIT, Windows libs only): travel vs heading, front wheel aim, turn force, rear grip bar, loose ground, flight path.
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

- **Sponsor props** (`TrailCourse.chunk_gates` / `chunk_boards`, fixed spacing by centreline index so growing never moves them): a huge steel gantry with a sponsor banner over the trail every 300 m (`TrailGate.build`, made-up brands in `TrailGate.SPONSORS`, no collision, skipped on jumps) and breakable wooden roadside billboards every ~80 m (fence-style panel in `TerrainChunkBuilder._boards`, so the bike smashes them; the Label3D text is freed on smash). Probe: `BMX_GATE_PROBE=1`.

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
- **Lean feel** (2026-11-20): back to the old snappy response at the user's request, but tunable: the steer input follows
  the keys / stick on a critically damped spring (`steerEase` 30, Ride › Steering; lower = gentler build-up), the lean's roll
  speed saturates at `leanRate` (6 rad/s, Ride › Lean; ~2.8 felt too slow, 3.6 still too slow), `leanIn` 40 / `leanOut` 30,
  `flickSpeed` 14 (the old values; Tune VER 13 resets them).
  The rider's body is its own mass: in `rider.gd` the hips (`ROLL_HIP_W/Z`) and chest (`ROLL_CHEST_W/Z`) follow the target
  roll (bike lean - counter) on springs (12 / 10 rad/s), so the bike goes over first and the body follows through with a little overshoot;
  through a crossover the legs extend (`ROLL_UNWEIGHT`); the inside knee follows a smoothed lean. Sliders (Rider › Motion,
  pose keys): `leanFollow` (how quickly), `leanSwing` (overshoot), `leanUnweight` (legs extend). Test: `BMX_FLIPFLOP=2.4`
  (+ `BMX_STRAIGHT=1`) swaps full left / right every 1.2 s and prints `LEANFF` lines (steer, lat, bike / hip / chest roll, peak roll rate).
- **Corner life** (Rider › Motion › Corner life, `leanLively` master + `leanBalance` / `leanBumps` / `leanLoad`): leaned over, the body roll gets a slow uneven balance sway
  (~1-2 deg), bumps under the leaned bike nudge it, and the turn's load (`latG` from game.gd) presses the rider a few cm
  down into the attack position. Hip / chest roll springs ring a touch more (`ROLL_*_Z` 0.52 / 0.44).
- **Corner whip / drift** (`bike_physics.gd` `whip`, Ride › Body › `whip*`): both sticks hard the same way (steer + body
  lean, > 0.6) above `whipMinSpeed` = the bike is thrown further over (`whipLean`) and the rear swings out to `whipDrift`
  (~0.42 rad) at `whipSnap`, held while both stay there, speed mostly kept (`whipCarry` cuts the slide scrub); "WHIP!" after
  0.3 s. Sticks must pass `whipTrigger` and stay there 0.12 s (`_whip_arm`); the ride log has `whip`, `whip_hold`, `raw_right_x`, `raw_left_x` columns; `whip_hold` keeps control `whipCatch` s after letting go so the drift is caught (without it the rear spun out to the
  wash-out angle). Test: `BMX_WHIP=secs` (+ `BMX_WHIP_T0`, `BMX_STRAIGHT=1`) prints `WHIP` lines.
- **Aerodynamics** (`aero_k` in `bike_physics.gd`): the air drag scales with the body: right stick forward on the ground = a race tuck
  (chest folded over the bars, hips back, knees bent) cuts drag by `tuckDrag` (0.42; half that while pedalling), stick back = sat up,
  `upDrag` more (an air brake). Straight test: 65.9 → 68.3 km/h in 20 s.
- **Posture is the player's**: neutral (stick centred) is an upright attack position (torso ~30 deg from vertical);
  the right stick forward folds the rider down into the full tuck (`aero` in `rider.gd`, nothing tucks by itself at
  speed any more), back sits up tall and back.
- **Full-body leans** (right stick, `rider.gd`): forward = hips forward and up (legs extend), chest out over the bars,
  chin forward, elbows up and out; back = hips behind and down, chest over the hips, arms long, elbows in; side
  (`bodyLat` = `flick` on the ground / `air_stick.x` in the air) = the hips go to the outside of the leaning bike; in
  the air a side lean is a tabletop (hips turn with the bike, shoulders back against it, hips drop so the feet stay
  on the pedals). Test shots: `BMX_BODY=air:x,y` holds the stick mid-air.
- **Rear-wheel clearance** (always on, in the safety limits, `wheelR` / `wheelRR` from game.gd): the hips may go below
  the saddle but never inside the rear wheel's circle + 16 cm - the legs used to go into the wheel in the air.
- **Skeleton safety limits** (`rider.gd`, just before the torso length clamp): hips in a box over the bike, the
  torso bends only -26..80 deg forward and +-34 deg sideways from the bike's up; body counter-roll capped at ~50 deg.
  Whatever stacks up (tuck, spin, lean, landing, sliders) the body can't be mangled.
- **Air spin pose**: spinning in the air the rider sits tall and compact (knees in), head + shoulders lead.
- **Style points** (`bike_physics._style_points` -> `hud.StylePop`): air time, 360s, flips, tweak, x1.5 clean landing,
  combos (landings within 4 s chain and multiply); banked after 0.7 s, a crash before that = BAILED.
- **Stick wheelie**: right stick pulled back while pedalling = a wheelie from walking pace (`stickWheelie`, height by
  how far back), coasting = a manual (`manualAngle`); held > 1 s scores style points (WHEELIE / MANUAL x s).
- **Pad steering curve** (`Settings.pad_expo`, Settings › Controller): the left stick's first travel tips the bike in
  gently, full lock at the edge (keys unaffected).
- **Pose memory resets on get-up** (`Rider.reset_pose`: wheelie / tuck / effort / turn smoothing) - a crash left a
  "wheelie" behind that snapped the body about; the torso limit treats a chest below the hips as folded forward
  (no flip-flop). Test: `BMX_BRAKETURN=secs` (sprint, then hard brake + full lock) prints `JITTER` / `JUMP` lines.
- **Tune migrations**: `Tune.RETUNED_AT` lists keys whose defaults changed per version (only those reset).
- **Tests run minimised**: `BMX_MIN=1` (they still render, screenshots work).
- **Ride log** (`game/ride_log.gd`): the last 60 s of every physics step (bike physics, body, drawn-bike lift,
  rider joints, all inputs) kept in a ring buffer; **R3 / F8** (`save_log`) writes it to
  `%APPDATA%/Godot/app_userdata/Mini BMX/ridelogs/ride_<date>.csv` (last row = the press, `before_press` column).
  The way to find a glitch the player saw. Test: `BMX_SAVELOG=secs`.
- **Lean vs terrain**: the lean only changes as fast as the tyres are loaded (`kL *= load`): over a crest / edge the
  bike carries its lean instead of snapping upright. The bank the bike feels changes at most 3 rad/s. The lean is
  limited against the ground where the leaned tyre swings to (0.3 / 0.5 m to the lean side at both wheels,
  `lean_room`, `groundLeanMax`): a deep lean toward rising ground beside the trail put the tyre into it and the
  drawn bike was shoved up. Probe: `BMX_BANK_PROBE=1` (+ `BMX_FOLLOW=1 BMX_WEAVE=3.5` weaves over trail edges):
  `BANKDROP`, `LIFT`, `BASEBIN` lines.
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
  **No self-spinning**: the muscles (tension, reaching, squirm) bend the body but can't spin it — each substep the
  whole-body angular momentum they add is taken back (`_keep_ang_mom`; only the ground / things hit turn it; the
  joint pulls weren't collinear and used to spin the body up). Everything tuned per substep (damping, drag, tension)
  is scaled to the substep length (`H0` = 1/360 s) so crash slow motion (time scale 0.22) behaves like normal time
  (it was ~20x stiffer and spun the body 2.5 turns). `BMX_SPIN_PROBE=1` prints torso spin (rad/s, turns);
  `BMX_NO_LKEEP=1` turns the spin fix off for comparison.
- **Blood** (`fx/blood.gd`, Settings › Gameplay › Blood): bleeding ragdoll parts that slide drag smears
  (`shaders/blood_streak.gdshader`, one MultiMesh ring of 1500 flat quads, world-space noise so pieces join; fresh
  = dark glossy red, dries matt in 45 s), hard touch-downs leave splats + droplets (`fx.chunk`). No blood on the
  rider (the user didn't want it). A respawn fades all of it out over `WIPE` (4 s; shader `wipe_t`).
  **Torn-off limbs**: a crash > `SEVER_SPEED` (16 m/s) tears off the first limb hitting hard (> 3), any limb hit >
  `SEVER_HIT` too, at most `SEVER_MAX` (2) per crash; hand / foot hit = at the elbow / knee, elbow / knee hit = at the
  shoulder / hip. `Ragdoll.sever(a)` drops bone a-b and gives the free piece its own root point (appended to `p`,
  `cut[b]` = its index); `Rider.pose_ragdoll(P, roots)` draws that segment from the root. Dark red caps on both
  ends; the stump pumps an **arterial jet** with every heartbeat (`JET_T` 9 s, `HEART_HZ` 2, `JET_SPEED`; drops in their own MultiMesh drawn stretched along their flight by `shaders/blood_jet.gdshader` so they join into one stream, pooling where they land), the torn-off piece pours out of its end. Smears start as a faint narrow trace and build up over the first metre of a slide (`_slid`), fade in as they're laid (shader `soak`), drawn as a thin see-through film with drag streaks (pooled = deep red, dried = brown). **Fatal crash** (> `FATAL_SPEED` 12 m/s or a limb torn off; `BMX_FATAL=1` forces it): once the body lies still a pool spreads from under the chest (+ each stump) to `POOL_R` over ~`POOL_T` s; it is a small real liquid simulation that follows the ground (`fx/blood_pool.gd` + C# `BloodPoolSim.cs`: 256x256 cells of 4 cm = 10.24 m; ground sampled every 16 cm (the draped mesh uses the same samples) via `top_height` + mm bumps; each cell passes blood to lower neighbours by the surface difference but keeps a thin film, so it runs downhill in rivulets, fills dips, spreads unevenly and stops by itself; a film thinner than 4.5 mm soaks into the dirt, whatever reaches the border drains (never a straight cut); a second pass `shaders/blood_halo.gdshader` darkens the soaked dirt round it (wet halo, creeps out over 20 s); the depth texture drives `shaders/blood_pool.gdshader`: opaque cut-out with MSAA alpha-to-coverage edge, mirror gloss / sky + SSR reflections, meniscus from the depth slope, small domed bubbles that pop, dries brown from the rim); it stays until a respawn. Hit splats are projected **Decals** (`Blood._decal`; 8 textures made once by `BloodSplatTex.cs`: merged random lobes, warped outline, droplets) that only paint the ground: terrain ground meshes carry an extra render layer `Terrain.GROUND_LAYER` (bit 10) and the decals' cull mask is that layer, so they hug every bump, never clip / flicker and never paint the rider or bike; they soak in, dry darker over 45 s, fade on a respawn. All blood decals sit 3 cm up (lifted further until no corner is under `top_height`) and are pulled toward the camera more with distance (no z-fighting / clipping). `BMX_NOGRIT=1` turns off crash grit (tests). **Broken bones** (`Blood._break`, crash > `BREAK_SPEED` 9 m/s, a hand / forearm / foot / shin hit > `BREAK_HIT`; `BMX_BREAK=1` forces): `Ragdoll.break_joint` drops that elbow / knee's tension + fold limit (it flops, thrown the wrong way), a procedural crunch sound, a plain bone-coloured capsule (2.2 cm thick) poking out of the outside of the bend at an angle, mostly inside the limb, in a bloody wound; torn-off limbs show bone in both stumps. **Bloody tyre tracks**: `Blood.tyre_color` (game.gd's tracks) prints red after a tyre rolled through a pool / splat (`Blood.blood_at`), fading over ~10 m. The C# + pool shaders are warmed up when the ride loads (their first use cost ~0.14 s mid-crash). The head never comes off (the user didn't want it). Getting up
  restores the body. Tests: `BMX_BLOOD_PROBE=1` (hits / smears / severs), `BMX_SEVER=1` forces one.
- **WASTED** (`fx/wasted.gd`, Settings › Gameplay › Crash slow motion): on a crash time drops to 0.22× (sound pitched down via
  `AudioServer.playback_speed_scale`) for ~2.4 s real time, then eases back; the screen goes grey + vignette, the word
  WASTED (BAIL for a bail on purpose, F) shows at once for 1.5 s then fades (the rider + bike drawn in front of it via a silhouette mask), flat red, squeezed narrow to fill the screen (no band, no stroke), the crash reason small below. Fades on getting up or after 5 s. Off in autotests unless `BMX_WASTED=1`.
- **New area banner** (`fx/area_title.gd`, `Game.area_title`): when the biome changes (and 1.6 s into a ride) the name shows
  top centre (the jump card is top left) in the WASTED type (same red condensed face, same squeeze, ~8.5 % of the screen tall), small "ENTERING" above.
  Letters stamp down one after another from 2.4x with an overshoot, white-hot cooling to red; a red rule draws out from
  the middle; out they drift apart and fade (~4 s). Real time; hidden with the HUD. Test: `BMX_AREA_AT=secs` freezes it.
- **Fork models for the stock frame** (garage Shocks tab: "Tues fork", "Fuzz fork", `BikeBuild.FORK_MODELS.*.glb`): the Tues / Fuzz forks fitted to dh.glb by
  `tools/make_forks.py` (reads `assets/parts/<id>_fork.glb` from the frame exporters, writes `assets/forks/<id>.glb` + `forks/dh_cockpit.glb` = dh's steer mesh without
  its crowns / stanchions, found as connected components). `BikeRig._swap_fork` swaps the steer mesh, adds the crowns + stanchions as a `fork_crown` child of the steer node,
  replaces the `fork_lower` mesh (lowers + the model's front brake caliper) and moves its node to the fork's own axle offset (extras.wheelbase follows; physics reads it). The
  fork starts at dh's axle position, so the glb's `travel` (room before the lowers hit the crown, 0.18 / 0.17 m) caps the fork travel; the stock fork-leg decal slot is dropped.
  Frames with their own cockpit + fork (Tues, Fuzz) ignore the fork pick; the Goat (dh steer + fork) takes it. Test: `BMX_BUILD="suspension.fork_model=tues_fork"`.
  Not done: swapping the REAR caliper (it is merged into dh's seatstay mesh); the new frames' own rear calipers are in `assets/parts/*_brakes.glb`.
- **Helmet models** (`look.helmet`, `Rider.HELMETS`, picked in the garage Kit tab and the tuning card Look > Helmet; `Rider.use_helmet(id)`):
  GLORY = the stock recolourable helmet + our goggles; **6D ATR-2** (black / silver skin) and **TLD SE5** (`assets/helmets/helmet_*.glb`, from the user's FBXs by
  `tools/export_helmets.py` + `tools/prep_helmet_textures.py`) are textured models that always wear their own goggles + strap (our goggles don't fit them):
  each glb has two nodes, `helmet` (shell, material `tex_shell`) and `helmet_goggles` (`tex_goggles`, the Oakley Airbrake maps: they fit both models' goggle UVs; the
  "6dgoggles" maps from the download are not used). Neither is recoloured: the Shell / Peak / Goggles colour rows are hidden for them. `Rider.HELMET_FITS` = where each sits
  (scale 1.12, a little back + low; the dark face sphere is smaller for them); test override `BMX_HELMET_FIT=x,y,scale,tilt`. Real brand logos on the textures (6D, TLD,
  FXR, Oakley): check before sharing the game.
  **The rider always wears a helmet (no bare head, user decision):** `Rider.set_look` forces helmet on; hair only shows as the tuft / tail coming out under the back
  of the helmet (`Hair.HELMET_STYLES`: none = short, long, ponytail, braid; `hair.gd` braid = the ponytail tie, stiffer). Menus: title-menu Character > HELMET tab (models, hair style,
  hair colour), garage Kit tab + tuning card Look > Helmet (same pickers + hair colour row). Old saved `helmetOn = 0` is ignored.
- Look: kits + a colour per part (helmet shell/peak, goggles, jersey, pants, gloves, shoes, knee pads).
- **Knee pads** (`rider/knee_pad.gd` + `shaders/knee_cap.gdshader`, one `KneePad` per leg (`KneePad.new(side)`, -1 =
  left), posed in `update_pose` and `pose_ragdoll`): articulated so no part ever spans the bend: the cap sits on the
  bisector of thigh / shin, facing out of the bend, and wraps the knee as a sphere shell; plates / guards + fabric sleeves
  are rigid to the thigh and to the shin; a fabric ball closes the joint. Near straight the front eases onto the IK pole
  (ride) / body forward (ragdoll), and stays on the anatomical front when a broken knee bends backwards; a shin torn off
  at the knee takes its half, the cap goes. All pad materials are double sided (open shells: no see-through gaps).
  **Designs** (`look.padStyle`, Kit › Knee pads design in the garage + tuning card Look › Clothes, `RiderPanels.PAD_STYLES`):
  `enduro` (hard cap with chevron / vents / rivets, quilted foam plates, shin insert), `race` (hinged brace: striped cap,
  ribbed hard guards, side bars + metal hinge discs on the bend axis), `trail` (soft honeycomb foam cap, slim sleeve with
  accent bands), `none` (plain knee). **Straps**: velcro bands round the back of the leg with a buckle tab on the outer
  back (`STRAPS`); the loose end flaps like the goggle strap (`rider/strap_tail.gd`, streams back with speed, hangs when
  slow, kept out of the leg). **Logos**: a made-up brand per design (`LOGOS`: DIRTLAB / NITRO / TERRA) baked once into
  a texture (`KneePad.LogoBaker`) and printed by the shell shader (`logo_*`). Colours: Kit › Knee pads (`look.pads`),
  accent (chevron, stripes, straps) = the gloves colour. Tests: `BMX_LOOK=padStyle=race,pads=#f4f4f0` overrides the
  look for a run (not saved); every bend without the game: `..._console.exe --path godot -s res://tools/kneepad_gallery.gd
  -- out.png [cam=close yaw=-0.6] [design=race]`.

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
- Menu (`main._show_menu`): two pages in one column under the title. Main: RIDE, GARAGE, world seed + NEW WORLD,
  Settings / Controls / Quit. RIDE opens the **ride setup** page (`_menu_page_setup`): bike (Downhill / BMX) +
  time of day (the `LightSettings.BUILTIN` presets), then GO. Test: `BMX_MENU_PAGE=setup`.
- **Design tokens** (`scripts/ui/tokens.gd`, class `Tokens`): every colour, gap, corner, border and type size the
  menus use. Look = flat, Metro-like: white paper cards, **no outlines, no drop shadows**, 1–3 px corners; the
  selected / focused thing is shown by a fill or a coloured bar (`Tokens.MARK`), never an outline. Components in
  `UITheme` are built only from tokens: `paper_theme()` (whole screens), `card_style()`, `marked()`, `btn_box()`,
  `make_button(text, cb, kind)` / `style_button` (kinds primary / secondary / chip / link / tab), `display()`,
  `caption()`, `text()`, `heading()`, `key_cap()`, `spacer()`. The title menu, the garage and the Settings / Controls
  windows (`MenuBase`) use them; write new UI with them, no literal numbers or colours. The dark in-ride theme
  (`get_theme()`, HUD) is not tokenised yet.
- Display type: `UITheme.display_font(weight, slant)` = Bahnschrift (ships with Windows), condensed, optional
  forward slant; used by the menu and the garage. Keep source files UTF-8: a 🎲 once got saved double-encoded
  and showed as "ðŸŽ²" on the Random button.

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
- **Split (2026-11-19)**: the garage (`Garage.mode = "bike"`, menu GARAGE / `--garage`) is bike only: Paint, Logos, Wheels,
  Bars, Shocks, Gears; no rider, no rollers, the build card + Stock / Randomise / Save. The **rider room**
  (`mode = "rider"`, menu RIDER / `--rider`, same room) has POSITION (rider always on the rollers, preview, presets, every
  bone slider) and KIT (rider standing beside the bike); changes save as they're made, bottom bar = Back / Ride.
  `BMX_GARAGE_TAB=rider|kit` or `BMX_GARAGE_RIDER` open the rider room.
- Compact UI drawn at `UI_SCALE` 0.82 with a fixed-width card; long labels ellipsize. Racing-game shop look on
  flat white cards (tokens above): header card with the category bar (click or **Q / E**), every option list is a
  ◀ VALUE ▶ stepper with a dot per option (`_choice`), segmented stat meters (`StatBar`), key-hint pill at the bottom.
- **Part cards** (`_cards`): Bars (`Handlebar.MODELS`: Renthal, Race Face, Deity, Chromag, Spank, OneUp, ENVE…),
  Shocks › Fork (`BikeBuild.FORK_MODELS`: Fox 40, BoXXer, Öhlins DH38, Bomber 58, DVO Onyx, Dorado, EXT Era; sets
  travel + paints lowers / stanchions), Wheels › Tyres / Rims (the existing models). Each card shows a picture of the
  part alone, rendered by `PartThumbs` (`scripts/garage/part_thumbs.gd`: an off-screen studio SubViewport, one part
  per frame, cached by key; bars / forks are cut out of dh.glb's steer + fork_lower meshes, wheels from
  `WheelGen`), brand, name and a spec line. Touching width / rise / material / travel makes the model "custom".
- The **Coasting** rider preview is the showcase pose: sat on the saddle, sitting up (`relax` input to
  `Rider.update_pose`: straighter back, chest up, chin up, whatever the saved riding pose).
- Light: little volumetric haze (0.004), exposure 1.0, contrast 1.16 / saturation 1.18, depth fog from 90 m.
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
- **Race tape stretches before it snaps** (`TapeSim.grab`): riding into a span hands it to the sim pinned at both stakes, its
  hit point carried on the bike's front (`Terrain.tape_push`, set by `Game` every frame). It pulls straight, stretches, and tears
  only past `SNAP_STRAIN` (17 %); the halves whip back towards their stakes. Stop / back off / slide off its end / crash before
  that and it springs back (`SETTLE` 1.3 s) and is whole again (`Terrain.restore_tape`). Strips are drawn through a Catmull-Rom
  spline (`SUBD` 4 pieces per sim segment): smooth when floating, no extra sim cost. Test: `BMX_TAPE=dir/prefix` (or `1`),
  `BMX_TAPE_SPEED`, `BMX_TAPE_STOP=secs` (`TAPE` lines: state, strain).
- Torn race tape as cloth-like ribbons, wind over the grass, drifting cloud shadows, speed blur / FOV.

### Photo mode (O, `scripts/game/photo_mode.gd`)
- Time freezes (`Engine.time_scale = 0`), HUD hidden, the camera comes loose: `Game._process` calls `PhotoMode.update(real dt)`
  instead of the ride; `CameraRig` / `hud` ignore input while `game.photo`; Esc / O / pad B / the card's ✕ leave.
- Camera: right drag look (mouse captured), left drag orbit the rider (`pivot()`: the bike +1 m, the ragdoll's centre
  after a crash), middle / shift + left drag pan, wheel dolly, ctrl + wheel zoom; WASD fly, Q / E down / up, Shift ×4,
  Alt ×¼, arrows look, Z / X roll, - / = zoom, R back to the start view. Pad: sticks fly / look, LT / RT down / up,
  LB / RB roll, D-pad zoom, A shoot, X grid, Y hide the card. Kept within `RANGE` (70 m) of the rider and 15 cm above
  `Terrain.top_height`.
- Card (right, Tab / H hides it): **Camera** (fly speed, FOV, roll, look sensitivity, smoothing), **Focus** (DoF, auto focus
  on the rider = yellow brackets, F = focus under the cursor, aperture, in-focus depth, foreground blur, bokeh shape;
  DoF quality forced high while open), **Light** (time, sun direction / strength, exposure, haze: a copy of
  `LightSettings.current` through `Game._apply_light`, never saved; the ride's light comes back on leaving), **Look**
  (filters, saturation / contrast / brightness on the env, temperature, tint, fade, vignette, grain, lens fringing in
  `grade.gdshader`'s `photo` / `p_*` uniforms), **Frame** (aspect bars, composition grid, hide rider / bike).
- Enter / F12 / pad A / the button: UI hidden for two frames, the shot is cropped to the frame and saved as
  `user://screenshots/photo_<date>.png`, shutter flash. Look / focus / frame prefs persist in `user://photo.cfg`
  (not in test runs).
- Tests: `BMX_PHOTO=secs` (+ `BMX_PHOTO_CLOSE=secs`, `BMX_PHOTO_SET=key=val,...`, `BMX_PHOTO_FLY=dx,dy,dz,yaw,pitch`,
  `BMX_PHOTO_ORBIT=px`, `BMX_PHOTO_TAB=Look`, `BMX_PHOTO_SNAP=1` prints `PHOTO <path> WxH`).

### Paper: trail map (M) + pause leaflet (Esc) — and future paper menus
- **`PaperSheet`** (`scripts/ui/paper_sheet.gd`, a CanvasLayer, layer 7): a folded sheet that comes up in front of the
  camera and unfolds like a real map: up it comes cover first, the accordion is pulled open like bellows (every crease
  together, soft paper springs), then (rows = 2) the bottom half - folded up over the map face in every column - flips down once
  every panel has come to rest; the creases relax into their few degrees only after that (bent creases opened
  slits while it swung). Folding away runs it backwards. The held point follows the paper's middle smoothly. Its own small 3D world
  (SubViewport: own light + shadows in the folds, no fog / DOF / time of day) drawn over the game, which is blurred +
  darkened behind it. Every move is an underdamped **spring** (`Spring`: lift, half fold, one per crease) fired on a
  timeline (`_drive`): quick, overshoots ~10 % and wobbles to rest; closing is firmer and bounces shut. Real time
  (works at `Engine.time_scale = 0`). What's printed is any Control in `content` (a SubViewport page): `live = false`
  -> `await bake()` prints once with mipmaps; `live = true` -> re-rendered every frame and **mouse / keys / pad go to
  it** (clicks are ray-traced onto the panels as they lie, `page_point`). `unfold = false` keeps it folded (a
  leaflet). cols even for unfolding (the outer panel's back = the cover, a strip under the page); odd cols only folded.
  `close_actions` / `close_requested` / `auto_close`, `opened` / `closed`, `tempo` (< 1 slower; the map 0.4),
  `sound_stream` (a recording played in random faded slices; the map: `assets/audio/map_unfold_gravel.ogg`). Paper = ambientCG **Paper003** (CC0) scan in
  `assets/textures/paper/` × the print, creases worn (`shaders/paper_sheet.gdshader`). Sound: only the user's recording (`sound_stream`; the map and the pause leaflet use `map_unfold_gravel.ogg`), no stream = silent - never synthesised paper sounds.
- **Trail map** (`PaperMap`, `scripts/ui/paper_map.gd`; `Game.open_map` / `exit_map`): 4×2 panels (0.84 × 0.525 m),
  two layers. **World** (`World`, `set_content`): one 3.2 × 2 km print around you (2 px/m, heights every 10 m,
  colours every 20 m, hill shade, 5 m / 25 m contours, shore, 100 m grid with numbers, trail in red dashes, route
  features, the last 90 s ridden, YOU ARE HERE), **printed while the map unfolds** - the map face is covered by the
  folded-over bottom half until the flap drops, and the flap waits for the print (`hold_flap`). You then pan freely
  inside it (no reloading; it stops at the edge). **Frame** (`Frame`, the page, printed with alpha over it): margin,
  neat lines, title block with the scale, legend, scale bar, north arrow, the cover.
  Controls (`handheld`, hint at the bottom): left stick / WASD / drag = travel (`TRAVEL` m/s), RT / LT / Q / E / wheel
  = zoom the print 0.25–2.5× (the paper always stays fully in view; the frame is reprinted when the zoom settles so
  scale bar + "1 : n" follow), right stick / numpad = tilt the sheet ±0.3 rad.
  Printing: terrain sampled on the main thread with **batched C# calls** (`TerrainFieldCs.map_heights` /
  `map_colors`, a few rows per call, ≤ 10 ms a frame, ~0.4 s); land image + contours on a WorkerThreadPool task from
  that plain data; the one-frame GPU steps (draw, read back, upload, ~200 ms together) wait until the paper is still.
  **Never call the C# field per point from GDScript in bulk, or hand C# forks to workers**: both left C# objects
  for the garbage collector that got finalized after shutdown and crashed the quit (exit 132 / 139). The world
  viewport is 2×2 except while printing (a 100 MB render target). Reused if you're within 60 m.
  Ride frozen + HUD hidden while it's up; M / Esc / bail fold it away. Unfolds like a real map at `tempo` 0.36: the
  cover comes up, the accordion opens like bellows (every crease together), then the bottom half drops; the user's
  gravel-crunch recording plays. The screen fades (`main.fade`) run on real time, or a map opened during one froze it.
- **Pause leaflet** (`PausePamphlet`, `scripts/ui/pause_pamphlet.gd`, built in `main._pause`): a DL tri-fold (3 × 99 ×
  210 mm), **letter-folded** (`fold_style = "letter"`: the middle panel stays, the right flap folds in, the cover flap
  over it). Cover = the back of the cover flap: a photo of the spot you paused at (the ride's last frame, centre crop),
  "DOWNHILL PARK / MINI BMX / <biome> · TRAIL GUIDE", the menu printed below as live buttons (highlighter on hover /
  focus). **Settings / Controls open the leaflet** (`open_inside`, from `main._open_settings` / `_show_controls`):
  the flaps swing open and the menu (`MenuBase` with `paper = true`: no card, `UITheme.paper_theme()` - ink outlines,
  fill-in-line fields, printed tab headings with a red rule, red-ink sliders) is printed live across the three inside
  panels (drawn ×1.3). "Fold up", Esc or B shuts it back to the cover (`fold_inside`); Esc / B on the cover resumes.
  `PaperSheet.set_unfolded()` opens / shuts any sheet while it's up; the camera eases between the shut and open fit.
  **Turn it over** (right stick / numpad 4·6 while shut; `spin`, settles face or back when let go): the back of
  the middle panel (`back_col`, the cover strip's second slot) carries hand-drawn **ride tips** (`TipsBack`: wobbly
  pen sketches, Ink Free handwriting, the button icons for the device in use). Every sheet keeps a strip at the
  bottom of the screen for its controls row (`HINT_RESERVE`): the paper is fitted above it, never over it; the row
  has no pill. Tests: `BMX_LEAFLET_SPIN=3.14`.

### Goggles, strap, quit
- **Goggles = the user's ski-goggle model** (`assets/goggles/ski_goggle.obj` + textures, `SOURCE.txt`): the frame,
  foam and lens only (its own strap was cut off: faces behind z -14 or on the strap's texture band); placed by
  `RiderGear.build_goggles` when `goggle_mats.model_mesh` is set (scale 0.0082, quarter turn so its +z faces +X),
  else the built goggles. Lens alpha baked into the albedo, floored at 0.6 so the mirrored tint shows. **Our strap**
  goes round the helmet (GIANT print, thin white edge lines `_add_strap_edges`); its loose tail is ~13 cm.
- **Quit crash after using the map** (exit 132 / 139, "Fatal error ... GodotObject.Finalize / DisposablesTracker"):
  **fixed**. Cause: `TerrainFieldCs` reproduces GDScript's sin / exp / log exactly, and on rare near-ties asks the
  engine through an `Expression` (+ a Godot Array per call). Sampling 125 000 map points hit those ties by the
  thousands; some of those engine objects outlived the engine at quit. The map's batches (`map_heights` /
  `map_colors`) now set `_approx` (keep the x87 result on a tie: the map doesn't need bit-exactness; physics and
  chunks stay exact, `terrain_cs_cmp` still EXACT). Also kept: `GameState.quit()` (C# GC before quitting, `CsGc`),
  `TerrainFieldCs` frees its feature wrappers / Expressions on delete. Hunted with `BMX_FREEZE=a,b` (time frozen,
  no map: clean) vs the map with / without printing / C# sampling; 14 / 14 clean after the fix.

### Xbox menu navigation (`scripts/ui/pad_nav.gd`, class `PadNav`)
- Every menu works without a mouse, console style: `PadNav.attach(root, {tab_container | tabs, back, first, style})`.
  D-pad / left stick move focus (Godot's built-in neighbours; held = repeats after 0.38 s every 75 ms), A presses,
  B = `back`, LB / RB = tabs (a TabContainer, or a `tabs(dir)` callable). Left / right on a row's control change it
  in place: sliders 1/20 of their range, dropdowns step options, toggles off / on, a custom stepper via meta
  `nav_step` (the garage's ◀ VALUE ▶; A steps it too). Dropdowns still open on A, take the stick, close on A / B.
- Focus marker: a container with meta `nav_row` (MenuBase / garage / tune card / photo rows) gets a wash + a bar
  on its left when its control has focus (`style` "paper" highlighter + red, "card" yellow tokens, "dark" in-ride).
- Every ScrollContainer under the root follows focus. On a pad, focus lands on the page's first control when a menu
  opens / a tab changes; a page rebuilt after a change (garage, preset, rebind) gets focus back at the same tree
  position (`_refocus`); a window closing hands focus back to where it was (title SETTINGS). Only the newest
  visible PadNav in a viewport is active (Settings over the title menu).
- Paper sheets push pad / keys into their page: `PaperSheet._page_busy()` keeps B for an open dropdown or a
  control waiting for a key (group `nav_modal`: Controls rebinding) instead of folding the sheet.
- Where: title menu (B on ride setup = back), Settings / Controls (window or leaflet; type is bigger on the
  leaflet, `MenuBase.fs` 1.45), pause leaflet (now also **Tuning** and **Photo mode** lines: the tuning card
  over the paused ride, B closes it and rides on), garage / rider room (LB / RB categories, B back, right stick
  orbits, LT / RT zoom), tuning card (only while paused: riding, nothing on it keeps focus), photo mode (**Menu**
  = edit the card, B / Menu back to the camera), Settings › Controller pad picture (D-pad between callouts, A =
  the picker), trail map (B closes).
- Test: `BMX_PADSEQ="w8000,esc,d,d,a,rb,D700,lsd,k:O,shot:<png>,b"` (+ `BMX_PAD=1 BMX_OFFSCREEN=1`) drives a
  synthetic pad, prints `PADSEQ <step> focus=<control>` and quits; such runs never write any save file. Wait ~8 s
  before quitting from a fresh `--ride`: quitting within ~3 s of start can crash in C# (exit 132, an old
  Expression / worker-thread quit issue, not the menus).

### Button icons (`scripts/ui/pad_glyph.gd`)
- `PadGlyph.draw(ci, name, centre, h)` draws Xbox Series–style icons in code: glossy dark face buttons with the
  letter in its colour (A green, B red, X blue, Y yellow), LB / RB, LT / RT, LS / RS / L3 / R3, D-pad (arm lit),
  VIEW / MENU / SHARE, MOUSE / WHEEL, and key caps (`"K:<text>"`). `glyph_for(action)` = the icon for the device in
  use (falls back to the default pad binding; test runs install none). `PadGlyph.PromptBar` = a centred row of
  [icons, label] on a dark pill (the map's and the leaflet's bottom bar, `PaperSheet.prompt_items()`).
  Used by: those bars, the get-up prompt (`hud.gd` `GetUpPrompt`), the controls menu bindings (`GlyphButton`).

### HUD bike computer (`hud.gd` `GaugeView`)
- Garmin-style computer bottom-left (made-up brand **CHARMIN** on the bezel between the ◀ ▶ buttons; which page = a segmented bar along the screen's bottom edge, `_page_bar`); six pages flipped with the ◀ ▶ bezel buttons under the screen (mouse):
  **RIDE** speed, slope / grade, gear (the shifter: n/N, cassette, teeth; flashes on a shift; Settings › Gear
  shifter hides the row) · **TRIP** ride time, distance, avg / max, odometer (`records.distance`, now counted) ·
  **EFFORT** heart rate (made up from power, sprint, stamina; beating heart, zone), cadence (from `crank`),
  power (from `a_drive`), stamina, gear ratio · **AIR** last jump, height, air time, best, jumps, tricks
  (`BikePhysics._land_trick` → `game.on_trick` → `hud.on_trick`) · **ELEV** elevation, ascent / descent, the last
  30 s + the next 400 m of trail coloured by steepness (from `course.E`) · **MAP** (`MapView`) heading-up 2D topo,
  170 m across: contours (5 m, every 25 m bolder; marching squares over a 6 m height grid, 4 rows a frame,
  rebuilt after 40 m), trail centreline, the last 90 s ridden in magenta, north dial, 50 m scale.
  · **SYSTEM** (`SYS_PAGE`): frame rate, frame-time graph of the last 120 frames (60 / 30 fps lines), avg / worst ms;
  while it's up the Debug Draw 3D physics overlay (F3) is on (its text block sits top left under the jump card).
  FPS is no longer in a screen corner.
- **Alerts** (`hud._trail_scan`): the next bend (`course.KAP`, > 0 = right; LEFT / SHARP / HAIRPIN by the total
  turn), route feature (`route_feats`: tabletop, kicker, rollers, bridge…) or rock garden within 120 m; a banner
  pops up over any page when a new one appears, then stays from 40 m in. Off the trail (> 15 m) or riding it
  backwards: no alerts. `BMX_ALERT_PROBE=1` walks 2.4 km of trail and prints every alert.
- **Screen layout** (`hud.gd`): `StylePop` (STYLE total, trick + points: points
  roll up, the banked "+N" flies into the total, which counts up gold with sparks + a ring, combo "xN" punches in);
  top centre the area banner, top left the jump card (`AirCard`); bottom right, small and right-aligned over the fullscreen button: biome + ride info (`_corner_label`); top right the **life bar** (red, heart) over
  stamina, and under them `StylePop` (right-aligned). Flash messages (`hud.flash` -> `MsgView`): an achievement pop in the
  WASTED face (all-caps text punches in white-hot with gold side streaks; a "+N" part in gold; mixed-case info lines quieter),
  at 25 % height, under the area banner. Test: `BMX_FLASH="BERM +2 km/h"` (+ `BMX_MSG_AT=secs`). The trail alert fills the bike computer's lower screen under the speed (`GaugeView.draw_alert`: icon,
  distance big in yellow, name below); `BMX_ALERT_DEMO=HR|SR|J|K` forces one for screenshots.
- **Life** (`hud.life`): a crash takes 12–95 % by body speed (`on_crash(speed)`), heals 1.2 %/s from 4 s after it.
  At zero the get-up prompt says KNOCKED OUT / hold hop 1.2 s to **revive** (`REVIVE_HOLD`, back with 50 %) or
  Backspace back to start (full life, `on_respawn`). `BikePhysics.getup_need` is the hold time. Tests: `BMX_LIFE=0.1`
  (start life), `BMX_LIFE_PROBE=1` (`LIFE` lines).
- Piezo sounds (`ui/garmin_beep.gd`, rendered once into AudioStreamWAVs): a rising power-on chime 0.35 s after the
  HUD shows (ride start), a short key beep on the ◀ ▶ bezel buttons.
- Small touches: "acquiring satellites" for the first 3 s of a ride, battery icon (full to empty in 30 min of riding, `BAT_LIFE`; blinks under 10 %). Back to start / new world (`hud.on_respawn`) restarts the computer: ride timer,
  trip (distance, avg, max), battery, GPS fix and power-on chime; test `BMX_RESPAWN=secs` presses Backspace then,
  backlight for 3 s on a button press or a new alert.

### Bike computer models (ride setup page, right card)
- `ComputerUnits` (`scripts/ui/computer_units.gd`): EDGE 840 (large, nav, 6 pages), CLASSIC 540 (medium, nav, 6), SPORT 130 (small, **no
  navigation**, 5 pages), MINI 20 (tiny, no navigation, RIDE + TRIP). `scale` = HUD size, `nav` = trail alerts + MAP page, `order` = the pages.
  The pick is `GameState.computer_id` (saved in save.cfg, used for every ride; `hud.set_computer()` mounts it, also live behind the menu).
- RIDE → the right card shows a **3D close-up** (`ComputerPreview`, `scripts/ui/computer_preview.gd`) on a handlebar: drag to turn, wheel to
  zoom, double click to reset; the screen is a live 2D face (RIDE / TRIP / MAP) in a texture. Test: `BMX_COMPUTER=mini` mounts a unit,
  `BMX_MENU_PAGE=setup` + `--shot=..@12` (the menu needs ~10 s to load before the preview animates).

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
| `BMX_GOPRO_PROBE=1` (+ `BMX_BAIL=secs`) | prints the torn-off GoPro's flight (`GOPRO` lines), gets up 2.5 s after the bail and checks a new one is mounted |
| `BMX_CAM_CYCLE=1` | autotest presses C (next camera) every 0.6 s and prints `CAMCYCLE i mode` |
| `BMX_GARAGE_HEAD=1` (+ `BMX_GARAGE_TAB=kit BMX_GARAGE_CAM=1.9,22,0.75`) | garage camera frames the standing rider's helmet (action cam close-ups) |
| `BMX_SHOT=file.png` | screenshot at the end of an autotest |
| `BMX_STRAIGHT=1` | autotest rides straight (no steering/hops) — good for track shots |
| `BMX_IDLE=1`, `BMX_NOVSYNC=1`, `BMX_LOD=`, `BMX_NOLOD=1`, `BMX_PANEL=`, `BMX_PAUSE=`, `BMX_TAB=` | misc |
| `BMX_BODY_PROBE=1`, `BMX_AIRPULL=1` | prints the rider-body numbers / tucks in every jump |
| `BMX_GARAGE_TAB=paint…kit`, `BMX_GARAGE_RIDER=coast/pedal/sprint/descend/air` | garage tab / rider preview |
| `BMX_GARAGE_CAM=orbit,pitch,dist`, `BMX_POSE=key=val,...` | garage camera / pose override |
| `BMX_GARMIN_PAGE=0…5` | bike computer opens on that page (ride, trip, effort, air, elev, map) |
| `BMX_ALERT_PROBE=1` | prints every Garmin trail alert along the first 2.4 km of trail |
| `BMX_TRICK=back/front/side/manual/none/spin` | spin = a flat spin in every jump, prints `SPIN … cam_yaw` (must hold still); the others: autotest throws back / front at every lip (fresh S / W press) and keeps leaning in the air; none = hands off (side alternates A / D; manual holds the nose up at `BMX_MANUAL_PITCH` rad for back-wheel landings) and prints `TRICK` / `LAND` / `BOUNCE` / `CRASH` |
| `BMX_FOLLOW=1` (+ `BMX_TRICK=…`) | autotest steers along the trail centreline and gets up (back on the trail) 2 s after a crash; prints `TAKEOFF` / `JOLT` too — the way to get many jumps |
| `BMX_CLIP_PROBE=1` (+ `BMX_NOUNCLIP=1`, `BMX_CLIP_SHOT=file.png`) | measures how deep the drawn tyres go into the ground; prints `CLIP … frames_inside=` (must be 0). NOUNCLIP turns the fix off for comparison; CLIP_SHOT saves a screenshot when a tyre was 12+ cm in |
| `BMX_STEER=1` / `-1` (+ `BMX_STRAIGHT=1`) | autotest holds a steady left / right turn after 2 s (lean / leg-clearance shots) |
| `BMX_AIRSHOT=dir/prefix` | autotest saves up to 8 screenshots mid-air |
| `BMX_LIMB_PROBE=1` (+ `BMX_FOLLOW=1 BMX_TRICK=back BMX_BIGAIR=1`) | per elbow / knee: fastest bend swing per frame (`turn_max`), biggest joint move, `flips` = frames a bent limb swung 25+° (should be ~0; worst frames printed as `LIMBW`) |
| `BMX_KNEE_PROBE=1` | prints the biggest knee / hip move per frame and the torso stretch range, and logs (`KNEE …`) frames where a knee jumps |
| `BMX_TUNE=topSpeed=1.6,grip=1.1` | overrides tuning values for a test run (not saved) |
| `BMX_LAUNCH=pedal/sprint` (+ `BMX_LAUNCH_HOLD=secs`, `BMX_LAUNCH_SHOTS=dir/prefix`) | autotest stops at 3 s and pedals / sprints away: prints 0–15/25/35 km/h times, nose-up angle, wheelie time, loop-out; HOLD lets go of sprint after secs |
| `BMX_CAM_PROBE=1` | prints `CAMPROBE` at the end: camera rattle (2nd difference of its offset from the rider, mm), aim jitter (mrad), frames with camera shake, all at > 29 km/h on the ground |
| `BMX_GRIP_PROBE=1` | tyre grip sim: `GRIP` lines 4× / s (slip, slip_w, rear grip, loose, squirm, drawn countersteer); try with `BMX_SKID=11 BMX_STRAIGHT=1` |
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
| `BMX_FENCE=dir/prefix` (+ `BMX_FENCE_STYLE=ranch/picket`, `BMX_FENCE_SPEED=m/s`, `BMX_FENCE_ANGLE=deg`) | autotest rides into the nearest fence, screenshots before / after the smash; with `BMX_DEBRIS_PROBE=1` every piece prints how far it landed from the hit and its gap to the drawn ground |
| `BMX_MAP=secs` (+ `BMX_MAP_CLOSE=secs`, `BMX_MAP_TILT=x,y` holds the right stick, `BMX_MAP_SCROLL=x,y` the left stick, `BMX_MAP_ZOOM=z`) | autotest opens the trail map (presses M again); prints `AUTOTEST map: open= time_scale= hud=` |
| `BMX_MAP_SHOTS=dir/prefix` | saves the paper sheet's own render every 0.1 s while it unfolds (`PAPERSHOT`) |
| `BMX_PAPER_AT=secs` | freezes every paper sheet's animation at that time (pair with `BMX_SHOT` for a frame mid-unfold) |
| `BMX_PAUSE=1` (+ `BMX_PAUSE_HOVER=0.62`) | pause leaflet at the end of an autotest; HOVER moves the mouse to that screen height and prints where it lands on the page; `BMX_PAUSE=settings` / `controls` opens the leaflet on that menu |
| `BMX_OFFSCREEN=1` | a normal window parked off the screens instead of `BMX_MIN`: **minimised windows draw late**, so timed screenshots of animations come out stale — use this for those |
| `BMX_PHOTO=secs` (+ `BMX_PHOTO_CLOSE`, `_SET`, `_FLY`, `_ORBIT`, `_TAB`, `_SNAP`) | autotest opens photo mode, sets card values, moves the camera, saves a photo; prints `AUTOTEST photo:` |
| `BMX_FENCE_ALL=1` | smashes every fence within 70 m at random 4–18 m/s, 7 s later counts pieces buried / invisible / freed (all must be 0) |

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

- Minimised test windows (`BMX_MIN`) render late / irregularly: frame-timed screenshots of an animation all come out
  the same. Use `BMX_OFFSCREEN=1` (or freeze the animation, `BMX_PAPER_AT`) for those.
- Packed arrays are values: `var dst := minor; dst.append(..)` does NOT append to `minor`.

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

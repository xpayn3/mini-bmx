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
  (`scripts/bike/bike_chain.gd`, enabled by `chain` in the glb extras; the Goat uses the Tues derailleur and pedals). **Every geared frame has the drawn chain now** (2026-11-20): real links (outer plates + pins / inner plates + rollers, two MultiMeshes, laid pin to pin so it's a polygon round the sprockets), driven by the cranks, eased onto the new cog's size and cassette plane (`WheelGen.cog_z`) in 0.12 s on a shift (`BikeChain.set_gear`, from `game.gd`); on our crank (`ring_teeth` in the chain data) the ring's tooth band and the chain follow the build's chainring teeth. The stock RUNOUT DH's fixed chain mesh (on its swingarm) is cut out by `BikeChain.adopt_stock` (pulley spots measured off its cage, `BikeChain.STOCK`); `GameState.BIKES.<id>.chain` overrides glb chain data (the Goat's said a 92 mm ring, it rides our 34T crank). **Our fork on another frame** (the Goat: its head tube is 67.3 deg, 4.5 deg steeper than the RUNOUT's, and ~4 cm further back; the exporter had just slid our fork over at the RUNOUT angle): `GameState.BIKES.goat.head` = its head tube ends (measured off the mesh: the end faces' normals + centres), `BikeRig._seat_head` puts steer + fork + wheel under a "head" node turned onto it (upper crown on its top; the 2 cm longer tube slides the lower crown down the stanchions, `_slide_crown`). Steering / fork travel still work in that node's space; model-space users go through `BikeRig.steer_rest()`. `tools/bike_glb.py` = shared glb writer.
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

Player data: `%APPDATA%\Mini BMX\` (custom user dir) — `crashlogs/` (see Crash logs), `settings.cfg`, `tune.cfg`, `save.cfg`,
`rider.cfg`, `garage.json`, `logos/`, `screenshots/` (F12).

## 3. Controls (defaults, all rebindable in Settings → Controls)

W/↑ pedal · S/↓ brake (both levers, with feel) · **Ctrl front brake only · Alt rear brake only (bare levers: they lock)** · A/D steer · **Space** hop/pump (hold to charge; **in the air: tuck the bike up**) ·
**S/W pressed fresh as you leave a lip: throw a back/front flip** · **W/S in the air: tilt the bike nose down/up (limited, body shift)** · **A/D in the air: lean the bike left/right (no spins)** · **brake + A/D when slow: pivot (pirouette)** · Shift sprint (stamina) · Q/E shift gears · F bail · Backspace back to
start · R new world · B next bike · C next camera · Z/X rotate camera · +/- zoom · mouse drag orbit ·
H records · **F4 ride diagnostics** (test playground only, section 5) · **M trail map** (pad: Share) · **P / K / L** the tuning card on its Ride / Rider / Look tab · **O photo mode** (free camera, see section 5) · F1 hide HUD ·
F12 screenshot · **F11 / the small button bottom right: fullscreen on / off** (`ui/fullscreen_button.gd`, on every screen,
saves Settings › window mode; in the garage it sits above Save / Save & ride) · Esc pause. Gamepad (Xbox): triggers pedal/brake, left stick steer, X hop (jump), A sprint, bumpers gears, Y camera, D-pad left / right rotate the camera,
**right stick = the rider's body, all the time**: up / down shifts the weight forward over the bars / back (pulled well back
rolling = a **manual**, yanked fresh at a lip = a flip throw, in the air = nose down / up), left / right throws the bike over under
the body (leaning alone turns, leaning with the steer turns harder + grips more, a quick **flick** whips the bike round; in the
air it leans the bike). Numpad 8/5/4/6 do the same on keys. The camera no longer uses the right stick.
**Settings › Controller** (`ui/pad_map.gd`): the Xbox photo (`assets/ui/xbox_pad.png`, cut out by root `tools/cut_pad.py`;
without it a drawn pad) with what every button does, click to remap (sticks pick Steer / Rider body / Camera / Nothing and
swap), live button test, vibration: on / off, motors and a strength per effect (see "Controller rumble" in section 5). `Settings.pad_active` follows the last device used: prompts show
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
| `scripts/game/` | `game.gd` (one ride: interpolated drawing between physics states, crash/ragdoll, fx feeding), `camera_rig.gd` (**trail** = default: high, a little from the side, turns with the trail ahead; C / pad Y cycle: trail, **helmet** (POV from the action cam on the helmet, `Rider.action_cam` built by `rider/action_cam.gd`, lightly stabilised, chase view while crashed; in a crash the camera body snaps off its hinge and tumbles away, `fx/flying_cam.gd`, a new one is on after getting up), chase, **drone** (banks into turns, noses down with speed, hovers in gusts, prop buzz + `ui/drone_osd.gd` REC / height / distance overlay), side, trackside, bike POV when a bike cam is mounted; Low dolly, Close, Diorama, Slow orbit, Isometric, Top-down were removed 2026-11-20 as near-duplicates), `ride_audio.gd` (procedural sound) + `FreewheelSynth.cs` (freehub clicks: modal resonances fitted to a real hub recording, click rate = wheel speed × 24, tone never pitch-shifted) + `GravelSynth.cs` (tyre roll: ~500 pebble knocks per metre, damped rings around 650 Hz + cracks + casing rumble, fitted to a tyres-on-gravel recording within ~2 dB per band; tone per surface) |
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
- **The ride step is 11 stage functions** (2026-11-21; it was one 1,514-line function). `_ride_step` is the short driver; the
  stages, in order: `_step_controls` (levers, body stick, air inputs, lip throw; returns the brake level), `_step_ground`
  (heights, surface, grip per tyre), `_step_sprint`, `_step_loads` (weight on each tyre -> `n_rear` / `n_front` / `n_load`),
  `_step_drive` (pedalling, brakes, pump, drag; sets `skid`, returns `a_long`), `_step_steer` (steering, lean, balance, turn,
  grip sim, soft crash meters; returns `va`), `_step_move` (move + everything it can hit), `_step_vertical` (springs, legs,
  manual / nose balance, air, take-off, landing), `_step_hop`, `_step_lip` (lip spotting, pop, leg compression),
  `_step_wheels`. What stages share is passed as parameters / those three members; everything else is the bike's own state.
  The split changed no numbers: `slope_stress.tscn -- verbose=1 trace=1`, `feel=1`, `sim=1` and `compare=1` outputs were
  identical line for line before and after (that diff is the way to check any future "no behaviour change" refactor).
- Fixed **120 Hz** `_physics_process`; `game.gd` draws **interpolated** between the last two states.
- Two-wheel contact with tyre springs, pitch, lean/countersteer, slip/skid, carving, flow speed, sprint
  stamina, gears (`gear_k()`: ungeared bikes = ratio 1, the DH uses the garage cassette + chainring).
- **Rider body as its own mass**: vertical leg spring (`body_y`, `riderMass`, `legStiff`…) with lip reading
  (crouch before a lip, pop, reach for the landing), **fore/aft body spring** (`body_x`, `hip_shift`: braking
  and landings throw the body forward, drive sits it back), **air control** (Space tucks the bike up about the
  shared centre of mass, W/S lean the nose; keys held at take-off count only once pressed again).
- **Sprint from slow** (`sprintKick`, `BikePhysics.slowness`): the slower the rider, the harder a sprint pushes (0–25 km/h 1.5 s vs 2.7 s pedalling), legs spin up, the bike is thrown side to side and the rider stands tall over the bars (`effort` in `rider.gd`). Stamping from below ~12 km/h lifts the front into the balance manual (`manSprintLift`), balanced from there like any manual.
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
- **Slope physics review (2026-11-20, `tools/slope_stress.tscn`)**: on a slope only g cos(slope) presses the tyres
  (grip / brakes / drive use `n_cos`), and the slope moves load between the tyres (`SLOPE_TRANSFER` 0.7 = CoM height /
  wheelbase: climbs load the rear, descents the front; the rider's auto shift up / down a grade works against it).
  Before, climbing 15 deg unloaded the rear completely (wheelspin, WASHED OUT going straight). Other fixes: `nose_ref`
  at wheel lift-off = last step's two-wheel slope (`_gpc_last`; it came out ~1 rad nose up off any ledge = instant
  NOSE DIVE); spawn / get-up set the pitch to the slope; the brake hold only holds where the tyres can (past the
  friction angle the bike slides; rolling back with the brake held brakes); a steep edge is a wall only if it rises
  more than half a wheel radius (12 cm curbs used to BONK / SMACK); air drag in flight; a hard compression on the
  ground (steep chute into flat) is judged like a landing (`g_jolt` vs `slamJolt` -> SLAM / OOF); the first ~1 deg of
  slip doesn't scrub (the chatter wobble added ~15 % rolling resistance). One collider lookup per step, not two.
- **Controller rumble** (`game/pad_rumble.gd`, `Game.rumble`, updated every physics step after `phys.step`): effects mixed as
  1-(1-a)(1-b) onto the two Xbox motors (strong = left heavy thump, weak = right fast buzz), one Settings key each
  (`PadRumble.EFFECTS`, default 1.0): GROUND `rumble_road` (grain by surface + speed), `rumble_bumps` (each wheel's vertical
  acceleration `vw_f` / `vw_r`; front in the light motor, rear in the heavy), `rumble_bottom`, `rumble_water`; TYRES `rumble_slip`
  (`slip`, rear `grip_r` x `slip_w`, `whip`: on / off chatter, rate rises with speed), `rumble_spin`, `rumble_brake`,
  `rumble_skid` (`skid_fx` + brake); RIDER `rumble_pedal` (a push per stroke sprinting), `rumble_takeoff`, `rumble_land`;
  HITS `rumble_smash` (via `shake`), `rumble_crash`, `rumble_tumble` (ragdoll slams + slide). Nothing in the air. Motors:
  `rumble_strength`, `rumble_heavy`, `rumble_light`, `rumble_floor` (lowest motor speed, 0.06), `rumble_chatter` (slip pulse
  rate); refreshed at 60 Hz with a 0.12 s hold (stop by themselves when paused), stopped in photo mode / the map / menus.
  **Settings › Controller › VIBRATION** has every one of these as a slider (+ Reset vibration); changing one plays that
  effect on the pad (`PadRumble.preview(tree, key)`, a canned ~1.2 s pattern per effect, real time, works while paused).
  Probe: `BMX_RUMBLE_PROBE=1` (`RUMBLE` lines 4x / s per effect, `RUMBLESUM` at the end, `RUMBLE preview` lines); works without
  a pad. `BMX_PAUSE=settings BMX_TAB=5 BMX_VIB_SCROLL=<key> [BMX_VIB_DY=px]` scrolls to the section and plays a preview.

### Terrain
- Infinite world of 48 m chunks streamed around the rider on worker threads; ground as LOD grids
  (step 2/4/8 chosen by measured error) with skirts — no cracks; decorations are MultiMeshes with
  visibility-range fades (`VIS_RANGE` × the view-distance setting).
  **Far decoration shadows** (`Terrain._update_far_shadows`, 2026-11-22): a chunk's trees / rocks cast only if their
  shadows can land in the shadow-mapped disc round the camera (`shadow_eye` / `shadow_sun` / `shadow_reach`, set by `Game`
  every frame): the disc swept towards the sun by `CASTER_H` / tan(sun height), + margin and hysteresis. It used to be
  "2+ chunks from the rider = no shadow": at golden hour the 100+ m tree shadows across the trail blinked off / on at every
  chunk line (user: "as if a light were switched off"). Probe `BMX_SHADOW_PROBE=1` (`SHADOWFLIP` = a change, with its
  distance vs the reach; `SHADOWOLD` = where the old rule would have flipped a chunk that does reach the view).
  **No pop-in (2026-11-22)**: streamed decorations dissolve by their OWN distance from the rider
  (`shaders/deco_fade.gdshaderinc`, global `deco_fade` set by `Game`: `DECO_FADE_IN` 100 .. `DECO_FADE_OUT` 124 m; instance
  uniform `fade_mode` 1 = trees / rocks / wood / sheds, 2 = small clutter 30 .. 44 m), and `FarHills`' backdrop trees
  dissolve in over the same band (they were hidden by the streamed chunk square, which jumped 48 m at every chunk line).
  Chunks load >= 144 m out, so a chunk arriving is never seen. The big decorations lost their chunk-centre
  `VIS_RANGE`s (whole chunks popped at the load edge). The reflection probe only reflects onto the rider + bike
  (`reflection_mask = RIM_LAYER`): its 160 m box lit near trees / ground with gloss that popped as it jumped 30 m.
  Foliage `specular` 0.1. Shadow range follows the zoom you set, not the speed dolly (cascades re-fitted every frame).
  Trees ~30 % fewer (`TREE_TRIES` 100). Test `BMX_DECO_FADE=20,30` pulls the band in to see it work.
  **Sun shadows** (`Game._shadow_fit`): reach fixed by quality (`SHADOW_REACH` 100 / 140 / 170 / 200 m, fade from 75 %),
  never with the speed dolly; the 4 cascades end at zoom + 6 / + 22 / + 55 m (the sharp one covers the rider, not the
  empty air in front of the camera; it used to be fixed 6 / 18 / 45 % of an 80 m reach: shadows stopped ~70 m out and
  the rider sat in a coarse cascade). Golden hour bias 0.05 / normal bias 2.0 / blur 1.2 (was 0.08 / 3.0 / 2.0: mushy).
  Ultra atlas 8192 again. In the shadow pass trees keep casting to `DECO_FADE_OUT` + 20 m (low-sun shadows are long).
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

- **Mountains for ever + technical sections** (2026-11-21, user: "add mountains ... some gentle climbs ... missing nice tight
  turns for slow speed, more technical parts"). `TerrainField.range_at(x)` (mirrored in `TerrainFieldCs`, integer hash of slot +
  seed, no table): from `RANGE_X0` 2100 m one mountain every `RANGE_P` 2800 m on the trail's corridor: a climb averaging
  `RANGE_UP` 4.2 % (40-54 m of height, ~1-1.3 km), a short level top, a descent averaging `RANGE_DOWN` 7.5 %; `hill()` adds it,
  `mtn()` masks it like the first mountain (calm land, no wild terrain / side paths on it). The trail follows it by itself (its
  height past the first mountain is the smoothed land). `TrailCourse._tech` (section code 6, kind SWITCH): a stack of tight
  hairpins, 5-6.5 m radius, 8-17 m legs, now and then a left-right flick in a leg; picked for ~40 % of sections on a mountain's
  descent (`rg_down`), ~13 % elsewhere; no jump lines up a climb. The first 1.3 km of every seed is unchanged, everything
  after is laid out differently than before. Measured on seed 4242 over 13 km: tops at 43-54 m, steepest 100 m of trail +10.6 %
  / -13.3 % (the rolling dips ride on top of the mean grades). Tests: `BMX_TRAIL_FEAT=x<metres>` starts that far along x
  (`x2800` = the foot of the second mountain; within the 4 km laid out at start), `BMX_TRAIL_FEAT=tech` 40 m before the first
  hairpin stack past the first mountain. Not done: the hairpin legs sit ~10-14 m apart, so their dirt nearly joins.

- **Livelier trail** (`TrailCourse._shape_profile`, `trail_arch.gd`): roads bend more often and tighter; past the mountain the trail height gets rolling dips (~60 m); **ridge-and-cliff drops** (`drops`, ~1 per 3 km: the trail climbs ~4 % onto a ridge above the land, a short level run, then falls 3-6 m, and 2 % of slots 12-22 m: rare "gem" cliffs; route features skip them) and **rock tunnels / overhangs** (`chunk_arches`, merged blob-rock mesh, visual only, no collision). All deterministic by slot hash + seed, nothing near the laid-out end changes when the trail grows. **Gorge bridges** (route feature `gorge`, rare on straight road: a 36 m wooden bridge, deck on stilts, over a 9 m deep crevasse ~6.4 m wide; Wood kind 2 now takes its end from `u1`; mirrored in `TerrainFieldCs.cs`, `terrain_cs_cmp` must stay EXACT; HUD alert GORGE BRIDGE). Test: `BMX_TRAIL_FEAT=gorge` (try `BMX_SEED=5`), `BMX_TRAIL_FEAT=arch|<n>` spawns 80 m before the first arch / the n-th drop; `BMX_GATE_PROBE=1` prints `ARCHES` lines; `trail_grow_probe` prints `STATS`.

- **Rope bridges** (route feature `rope`, `world/rope_bridge.gd` + C# `world/RopeBridgeSim.cs`): a 46 m feature, a swinging rope
  bridge tied round four big pines (two each end, 2.3 m apart: ride between them) over a **canyon cut across the land**
  (`TerrainField.canyon_rims` / `canyon_dig`, mirrored in `TerrainFieldCs._canyon_dig`: polynomials + integer hashes only, exact):
  16 m deep where the trail crosses (rims exactly at 4.2 / len - 4.2 within 4 m of the trail), the rims wandering (value noise along w),
  the canyon narrowing, shallowing and ending `CANYON_W` (42 m) to each side. It is looked up by place, not by the nearest trail
  (`_canyons`: 64 m cells, `_index_canyons()` whenever `route_feats` changes; per nearest-trail it ended in a vertical seam wherever
  another trail bend was closer). `_canyon_clear` only places one where the trail within 300 m never runs into it. The walls are faced
  with flattened boulders stacked down them in sandstone bands (`RopeBridge._build_cliffs`, one merged mesh, visual only) plus fallen
  rocks on the floor. About one per 2-3 km of road (`_build_route`: a hash of the slot, < 0.12, not in the first 400 m). The deck
  is not in the height field: `Terrain` keeps a `RopeBridge` for every rope feature within 220 m (`_update_ropes`, needs C#) and its
  live deck is part of `height()` / `deck_height()` (`_rope_deck`; a deck more than 1.5 m above `rope_ref_y` = the bike's y is
  ignored, so down in the crevasse you stay down there). Sim: 4 ropes x 40 segments (2 deck ropes 1.1 m apart, 2 hand ropes),
  plank ties, soft pull-only hangers, Verlet + PBD (4 substeps x 10 iterations at 120 Hz), no plank diagonals (they made it rigid
  sideways). `Game._rope_tick` each physics step: the rider's weight (95 kg x `n_load`, so landings bounce it) + sideways push
  (the turn's `lat_a` + every pedal stroke, `ROPE_STROKE`) go into the deck, then the deck steps (wind x 1.6, gusts), then its
  sideways move under the bike carries the bike (`RopeBridge.carry`). ~0.4 m sway in a 10 m/s crosswind, ~0.4 m dip under the rider.
  Fall off the side = crash into the crevasse; getting up (or the bail tap) puts you back on the nearer rim (`Game._out_of_crevasse`).
  Planks drawn by a MultiMesh, ropes / hangers as tubes rebuilt every frame in C#, both interpolated between physics ticks. A few
  planks missing / snapped in half (visual: a tyre rolls over a one-plank gap). HUD alert ROPE BRIDGE. No C# = no rope bridges.
  Tests: `BMX_TRAIL_FEAT=rope` (6 m before the trees, on its axis; seed 4242 has one at 3.2 km) + `BMX_START_V=3 BMX_STRAIGHT=1`,
  `BMX_ROPE_PROBE=1` (`ROPE` lines 4x/s: u, w, on deck, deck height, mid point, crash reason), `BMX_FEAT_BACK=n` (n trail steps back
  instead), `-s res://tools/rope_sim_probe.gd` (sim alone: sag, wind sway, a walk across), `-s res://tools/rope_find.gd` (rope /
  gorge features of a few seeds + every rope canyon C# vs GDScript and trail clearance; must say `PASS`).
  **Riding fixes (2026-11-20)**: deck pinned at the canyon lip (`DECK_IN` = `CANYON_RIM` - 0.05; it used to start 1.1 m
  early, sag under the rim's ground and drop / kick the bike); `LANDING` 6 segments at each end pinned on a Hermite ramp
  from the ground's slope (`EndSlope0/1`) into the hanging curve; `SAG` 0.8; deck bending stiffness (`BendK`) + Catmull-Rom
  deck surface (no corner per node); the rider's weight goes in through both tyre contacts; trail eased onto the bridge's
  plane over `Feat.ramp` = `ROPE_RAMP` 22 m (was 6: a 17 deg kicker at the rim; mirrored in C#, `rope_find` now compares
  the ramps too); a wheel off the plank edge = "OFF THE BRIDGE!" at once (it hung on the edge at an ~85 deg "slope");
  get-up on a deck = middle of the planks, lined up with the bridge; no dust / tracks on planks; `Terrain.rope_aim` =
  the bridge's own line for the demo pilot / `BMX_FOLLOW` (the trail centreline bows ~2 m off it). Bridges build in
  slices (`Terrain._build_ropes`, 3 ms a frame, finished at once within 90 m; materials pre-made by `RopeBridge.warm`):
  was a 0.24 s freeze. Tests: `BMX_ROPE_PROBE=tick` (`RTICK` every physics step), `BMX_ROPE_SHOT=prefix` (shots by place
  on the deck), `BMX_ROPE_STOP=u,secs`, `BMX_ROPE_BAIL=u` (by place: wall-clock test timers misfire at low fps),
  `BMX_ROPE_SAG/LAND/BEND/ANCHOR` overrides. Photo tests:
  `BMX_PHOTO_AT=x,y,z,lx,ly,lz` puts the photo camera at a world point looking at another (FEATSPAWN prints the feature's `at` / `dir`).

- **Trail surface = procedural mask layers** (2026-11-21, `world/ground.gdshader`; the four-scan version was rejected the same
  day: "weird, tiled, cut off with an ugly straight edge"). Colour is the baked biome trail colour x small procedural steps; the
  scans are only fine relief (normals + roughness of `brown_mud_02` packed dirt at two sizes / turns + `gravelly_sand` where
  loose; `Terrain.trail_textures()`, `assets/textures/trail/`; the colour scans + the other two were deleted). Each chunk bakes
  the trail's own frame (`TerrainChunkBuilder.ground_stage` / C# `build_ground`, keys `TR` / `T2`): `trail_tex` RGBAF = metres
  across, the ridden line's place, metres along, a run-off skid's place; `trail2_tex` RGBA8 = road, dry biome, built jump,
  skid strength. Masks in the shader: `m_driven` (nine riders' own narrow lines, tables `LG` / `LD` / `LW`: four within a few cm on the racing line = the most worn core, the rest a bit tighter / wider, one cutting corners near the middle, one running wide, the outer ones wandering and coming and going (user: "majority on the perfect line, some more outside, some more inside, don't just make one thick line") + jumps: smoother, tighter,
  less relief), `m_loose` (grit beside the line / at the edges), `m_tracks` (three riders' tyre prints inside the line),
  `m_stray` (six single faint tyre lines running down the trail anywhere across it, each wandering and coming and going on its own; user: "too clean, some random down-the-road lines to make it look alive, more faint"), `m_play` (people messing about, user: "completely random, doing circles, joking around": in ~a third of the 26 m stretches one faint mark in the trail's own frame: a donut of a few laps, a figure of eight, a slalom, or a skid arc; uniform `trail_play`, test `BMX_TRAIL_PLAY=1` = every stretch), `m_skid`, `m_wet` / `m_puddle` (roads only, in the worn line, level ground, not dry biomes, in stretches; mirror-smooth,
  no grip change; the tyre dust knows them: `TrailPuddle` (`world/trail_puddle.gd`) = the shader's puddle formula on the CPU from a per-chunk table (`rec.pud`, only chunks with wet road), `Terrain.puddle_at`; water = no dust / clods / skid cloud + muddy drops, damp = less dust, ~15 us a step; probe `BMX_PUDDLE_PROBE=1`. Puddle shading: roughness 0.075 -> 0.22 with the pixel footprint, AA edge, specular AA, relief derivatives outside the branch (flicker fix)). **Bikes only: never two parallel wheel ruts** (user; `line()` lost its road ruts
  in both fields). **The line is a racing line** (user: "a perfect line, not random"): `TrailCourse._racing_line` -> `LN` =
  short average of the curvature minus a long one (inside at the apex, outside before / after), read by `line_off(x, z)` in
  both fields (the 3.5 cm worn dip + the baked darkening follow it). **Run-offs** (`RO` / `ROS`): at ~40 % of sharp corners
  (|KAP| peak > 0.035) a skid leaves the line a few metres before the apex and goes straight on off the outside, cut into
  the grass. Tests: `BMX_TRAIL_DEBUG=1` shows the masks (red driven, green loose, blue puddle, white prints, yellow skids, magenta stray lines, cyan playful marks),
  `BMX_TRAIL_PUDDLES=0|2` (none / on every wet road). **Lines stop at a lip** (user: "people are jumping over them"): `TrailFeatures.AIR` = per feature type the stretches riders fly over (lip to about where they land; mirrored in `TerrainFieldCs.AIR`), `_feat_at` -> `fo_air` in both fields, baked as `trail3_tex` (R8); every ridden line, print, stray line and playful mark is x (1 - air), soft over the last ~2 m so they pick up again down the landing. **Relief** (user: "nice in colour but all just smooth"): the masks also make a height `thgt` (lines = grooves to 3 cm, prints / skids pressed in, grit + pebbles proud, lumpy between the lines) turned into the surface normal from its screen-space gradient; lighting only, the 37 cm ground mesh can't carry it. Uniforms `trail_fx`, `trail_bump`, `trail_relief` (x the depth), `trail_puddles`. Playground / vista
  ground don't use it.

- **Grass carpet** (2026-11-20, `world/grass_field.gd` `GrassField` + `shaders/grass_field.gdshader`, made by `Game._ready`): a
  Zelda-style field of blades over the whole land round the camera, built on the GPU; nothing stored per blade. Each chunk bakes
  `grass_img` (land colour sRGB + density in alpha: none on trail / jumps, rock faces, below / near water, dunes (`DRY`, now also
  returned by `build_ground` in C# + GDScript), snow, sheds / stakes / boards via `blocked`) and `grass_h` (its ground heights) on the
  worker; GrassField blits the 5 x 5 chunks round the camera into two 481² window textures when the chunk or the loaded set changes
  (`Terrain.chunk_serial`, ~1 ms). Blades are tiles of a fixed lattice in two MultiMeshes: NEAR (3-part curved blades) and MID
  (one wide triangle facing the camera), cross-faded with ragged edges; the mid ring shrinks into the ground at its edge, which has
  the blades' own colour, so the land keeps reading as grass. Each blade's lattice cell is a whole number -> its hash (size, lean,
  colour, grows or not) never changes as tiles move. The rings centre on `ring_centre` = up to ~20 m ahead of a high camera (trail /
  drone see the dense ring), round a low one. Blades widen when looked at steeply from above (no slivers from the drone). Tiles out of
  view are skipped every frame. Colour: ground colour, darker root, greener / sun-dried patches. Wind + the bike parting it via
  `wind_bend`. No shadows cast. Settings › Graphics › Grass (`grass` 0 off .. 3 high, presets Low 1 / Medium 2 / High 2 / Ultra 3;
  `GrassField.QUALITY`). Medium ~240k blades in view (2026-11-21: rings 22 / 90 m, was 16 / 52; denser too), High more.
  Tests: `BMX_GRASS=0..3`, `BMX_GRASS_PROBE=1` (`GRASS window` / `GRASS tiles near= mid= blades=` lines, `TRAMPLE` lines).
  **Look (2026-11-21)**: blade roots = the floor under the grass: `ground.gdshader` reads the grass window through the shader
  globals `grass_win` / `grass_win_info` (set by `GrassField._set_ground_info`) and tints the floor x (0.66, 0.76, 0.56) where
  grass grows, fading out at the ring's edge; blades are a touch more saturated. **Backlit tips** (`light()`: looking towards the
  sun the top of each blade glows in its own colour). **Wind waves**: `wind_gust` lightens the bent blades, so gust fronts roll
  across as paler bands. **Trampled trail** (`GrassField.trample(id, p, dir, r)`, from `Game.ride_fx` per tyre and
  `_crash_dust` per ragdoll part): a 192² RGBAF window (0.25 m texels, follows the rider in 8 m steps) storing the time pressed,
  the direction and how hard; the shader lays those blades down along the travel (pale, sheeny) and lets them stand up again
  over `trample_hold` 2.5 s .. `trample_back` 28 s (per blade). Cleared on respawn.

- **Sponsor props** (`TrailCourse.chunk_gates` / `chunk_boards`, fixed spacing by centreline index so growing never moves them): a huge steel gantry with a sponsor banner over the trail every 300 m (`TrailGate.build`, made-up brands in `TrailGate.SPONSORS`, no collision, skipped on jumps) and breakable wooden roadside billboards every ~80 m (fence-style panel in `TerrainChunkBuilder._boards`, so the bike smashes them; the Label3D text is freed on smash). Probe: `BMX_GATE_PROBE=1`.

- **Health packs** (`world/health_pack.gd`): a GTA-style floating, spinning red backpack with a white cross and a glow ring, one outside the door of each roadside shed (`TerrainChunkBuilder._sheds` -> `out["packs"]`, made in `Terrain._finalize`). Ride within 1.6 m (`Terrain.take_pack`, called from `Game._process`) and `hud.on_health_pack` gives back `HealthPack.HEAL` (45 %); full-health riders leave it. Taken ones stay gone until a new seed. Tests: `BMX_PACK_PROBE=1` (`PACK at` lines), `BMX_PACK_SPAWN=x,z` (start 9 m before a pack), `BMX_LIFE=0.3 BMX_LIFE_PROBE=1`.

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
  **Smarter + calmer (2026-11-20)**: slowing to a stop (< 1.8 m/s, decelerating) brings the foot out early; which foot
  (`_pick_dab_side`): on a side slope the uphill foot (shorter reach), never onto a rock / bank > 35 cm higher (steps to
  the open side), else the lower pedal. Foot goes down `DAB_FWD` 10 cm ahead of the BB, `DAB_OUT` 36 cm out. The bike
  settles onto it with a stylish `DAB_LEAN` 0.24 rad (~14 deg, more when the foot's ground is lower) plus a slow breathing
  sway (`_dab_lean_s`); the body sits up relaxed (`relax` = 0.85 x dab) and, after 0.6 s, looks round (`_idle_look`:
  ahead, off to a side, back up the trail over the shoulder, down at the foot, up at the hills, 1.4-3.6 s each, through
  `lookYaw` / `lookPitch`). Test: `BMX_STRAIGHT=1 BMX_STOP_AT=3,30 BMX_CAM=chase BMX_CAM_ORBIT=3.0 BMX_DUST_SHOTS=…`.
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
- **Ground sim** (2026-11-20, `bike_physics.gd`; sliders Ride › Steering / Tyres / Ground / Brakes / Body, Tune groups
  Balance, Front tyre, Brakes, Ground). The user asked for "the best sim, but fun"; all parts work off one shared idea, the
  friction the tyres need against the ground's own tilt (`_fric(a_lat, cos bank, sin bank)`):
  - **Side slopes**: the grip sim (`_grip_step(dt, va, mu, nR, u_lat)`) gets the tyre use measured against the tilt, so
    riding straight across a camber loads the tyres (loose ground / bumps move the rear downhill); `camberPull` drifts the
    travel down the fall line (front falling to the low side), ~9 deg / 5 s hands-off on 5 deg. Berms: the bank bonus to the
    turn now works at any speed. `cornerLoad`: the turn presses down through the bike (`corner_g` = sqrt(g²+a²)-g into the
    vertical step: legs + shock sink, pop back out); the springs' extra load is taken back out for grip (`n_cos` x g/(g+corner_g)).
  - **Balance** (`balanceSim` 0.4, `bal_k`): rolling, the rider leans to what the steer asks (`lean_need`, capped at what the
    grip held last step `_amax/_amin`) and the bars follow the lean (`steer_lean`), with countersteer at speed. Leaned past
    what the tyres can hold at all (not just past this moment's turn: a swap always leans ahead) it falls in (`balanceFall`)
    and past `lowsideAngle` for 0.3 s = LOWSIDE. `gyroStable` slows the roll a little at speed. 0.7 made turn-in 0.4-0.5 s
    at 25 km/h (too slow), 0.4 keeps it 0.10-0.23 s.
  - **Front tyre**: `front_use` = its share of the turn on its current load and friction circle (front brake);
    > 1 pushes wide (`front_push`, heading follows the travel), past `frontWashAt` for `frontWashTime` = FRONT WASHED OUT.
    The old rough "light front = less grip" factor in `a_grip` is gone.
  - **Two brakes**: `inp.brake` (S / LT) = both levers with feel (rear kept a touch past locking = light skid, eased off
    the moment the rear steps out; front just under its limit); new actions `brake_front` (Ctrl) / `brake_rear` (Alt) =
    bare levers. Each limited by its tyre (`cap = mu x load`), locked = 80 % (`rear_lock` / `front_lock`); `skid` = rear
    locked (it used to be any brake press). Braking moves load forward (`_b_prev` x `SLOPE_TRANSFER`); a front grab that
    would take the rear below nothing for 0.25 s = OVER THE BARS. The rear's friction circle counts only its own brake /
    drive (`_a_rear`) and the front only swings a locked rear round with grip it has left (`_circ_f`): both together stay
    straight. 40 km/h stops: front 7.5 m, rear 9.5 m (locks), both 7.1 m.
  - **Knocks**: `groundKnock` = the side slope under the front tyre (`top_height` +-12 cm across) minus the land's tilt
    turns the travel (rocks kick, ruts hold), `knock` rad/s.
  - **Weight in the turn / right stick**: `weight_in` = side lean x the way the tyres push (`_f_prev`: into a turn, or uphill
    across a slope) - with = more grip (`flickGrip`) and a steadier rear over bumps (`weightSteady`), against = hanging inside,
    less grip (`weightInside`) and it no longer halves the steer (`fs_k`).
  - **Berms + tilted ground look** (user: "takes them too straight up, he must lean into it"): steering into a bank's low
    side, `bermAssist` raises the turn to at least the bank's own (G tan(bank), `berm_k`), so the lean matches the bank and the
    tyres need no side grip; `bankLean` (0.6) draws rider + bike leaning into any tilt, part of the way square to it
    (`bank_lean`, also in `counter` so the body follows); `bodyLean` 0.7 -> 0.8 (Tune VER 15). Real trail banks are only
    ~4-10 deg (`BMX_BERM_SHOT=prefix [BMX_BERM_MIN=rad]` + `BMX_DEMO=1`: `BERMSHOT` lines + shots on banks).
  - **Body with the bike on banks** (2026-11-20, user: "too straight up on an angled surface" with both sticks; drawn only):
    (1) the lean-room probe (`lean_room`, `groundLeanMax`) looked to the wrong side (+ lean = left = `(f.z, -f.x)`), so a
    berm's own face stood the bike up (60 deg of lean drawn as 38 on a 21 deg bank) - fixed; ground falling away on the
    lean side gives half of it as extra room, at most `bermLeanRoom` 0.15 rad (Ride › Ground; all of it = 77 deg, nearly
    flat). (1b) `counter` took the ABSOLUTE difference bike lean - body target: whenever the ground limit / soft cap held
    the bike more upright than the body's target the body was mirrored to the upright side (bike 31, body wanted 55 ->
    drawn 7 deg, or the wrong way); now signed, the body stays 20 % inside the bike there. (2) `bank_sq` (0 flat ..
    `bankBody` 0.7 from ~8.5 deg of bank toward the lean, Ride › Ground): the body goes that share into line with the bike
    (`counter` -> 0.2 x bike lean) and `Game` fades the stick's hips-to-the-outside shift by it; flat corners keep "bike
    under the body". Test: `BMX_FOLLOW=1 BMX_PAD=1 BMX_BODY=both BMX_BERM_SHOT=prefix BMX_BERM_MIN=0.09 BMX_BERM_STICK=1`
    (shots after 0.5 s settled in a bank with the stick into it; `BERMBODY` lines: body without / with, hips, chest).
    Same day, from a code review: reverse braking loads the rear, only the rear brake drops a manual, no body jolt from the
    landing's speed bookkeeping (`v_last`), `reset_body` clears `slip_w` / `steer_in`. Review findings fixed after (2026-11-21): the pitch clamp (1.45) no longer runs on the touch-down step, so a flip landed upside down reads UNDER- / OVER-ROTATED (it was clamped first and came out as NOSE DIVE); no lip window while a balance manual is held (on keys a fresh S / W in a manual was a flip throw and S didn't brake); the brakes are gated on any tyre down (`not air`), not on the rear (with the rear bounced up the front brake did nothing); a held manual's `nose_ref` eases to the ground slope it rolls onto (6 /s).
  - **Surfaces per tyre**: `surf_f` / `surf_r` (contact points), grip `SURF_MU` eased over ~0.1 s (`_mu_f` / `_mu_r`);
    front tyre + front brake use the front's, rear brake / drive / grip sim / loose patches the rear's, rolling drag both.
  - **Jumps**: the ground-only drawn lean (stick, slow steer, bank, whip: `_gx_lean` + `bank_lean`) is carried into the air
    and eased out (it snapped at take-off), eased back in on landing. Take-off off a tilted lip: the legs' pop
    (`pump_lift`) goes along the surface normal, part of it sideways to the low side. Landing: the tilt is read fresh at
    touch-down (`_bank_at`; the reading drifted to flat in the air), the hit is x cos(tilt) and the rest slides you towards
    the low side (`landSlide`, the tyres catch it); no falling in / lowside for the first ~0.4 s after landing.
  - **Smoothing, not changing the feel** (user: "jitter and rough animation", worst in bank-to-bank swaps on rough
    ground). Only what the bike READS from the ground is filtered: `knock` eases (~0.08 s, ripples < 0.08 ignored), the
    bank reading is a critically damped spring (~0.15 s, `bank_v`), `berm_k` eases 4/s, the tyres' load for grip
    (`_load_s`) and the front's share (`_share_f`) ease ~0.04 s (tyre relaxation), `_amax/_amin` (what the rider leans to)
    ~0.12 s, `corner_g` ~0.1 s, the front push blends in over the first 15 % past its limit. Measured with
    `BMX_JITTER_ALL=1` (+ `BMX_FOLLOW=1 BMX_PAD=1` or `BMX_FLIPFLOP=1.2`): lat_a step spikes 13 -> 1.6 m/s², bike lean
    0.17 -> 0.02 rad, knock / bank flips 42 / 35 -> 0. Turn response (`feel=1` yaw63) unchanged.
  - **Motion caps (drawn only)**: `Game.MCAP` / `_mcap` = every physics value the drawing uses (bike lean, bars, body
    counter, head roll, lat g, hip shift, leg absorb, body stick) follows on a stiff spring with a top speed + acceleration
    a body / bike can reach; `Rider.TORSO_VMAX` (2.5 m/s) caps the hips / chest per frame right after the skeleton safety
    limits (whose clamps snapped the chest), before the limbs are fitted. Head jumps > 8 cm in a frame on the trail: 3-4 -> 0.
    `_mcap` integrates in sub-steps of <= 1/240 s: one step per drawn frame (w = 60) was unstable at 60 fps and the legs
    buzzed every frame even standing still ("violently vibrating"). **Test frame-rate-dependent drawing at 60 fps**:
    `BMX_FPS=60` (also 30 / 144) + `BMX_JITTER_ALL=1 BMX_JITTER_FINE=1` (0.3 mm thresholds, `d_*` = drawn values).
  - **Rider + bike = two masses** (user: "the whole rider leans as one"): bike and body lean were both fixed multiples of
    the one `lean`, so they moved in lockstep. Now the drawn bike runs ahead while the lean changes (`bikeLead` s x roll
    speed, `_bike_lead`, up to 20 deg; the body's target excludes it) and the body follows on slower springs
    (`ROLL_HIP_W` 12 -> 8, `ROLL_CHEST_W` 10 -> 6.5): in a swap the bike crosses under a body that arrives ~0.2 s later.
  - **Crash judge** (user: "prone to crash too much", "crash logic must be intelligent"): the soft failures are no
    longer trip-wires. `_danger(reason, sev, dt[, t_build])`: sev = how far past the line (rear slide past `slipMax`
    /0.25 rad, front past `frontWashAt` /0.6 x (1 + 2 front_lock), lean past the grip by `lowsideAngle` /0.25 rad, the
    rear lifting under the front brake /0.25 g) fills that reason's meter over `crashTime` (0.4 s at sev 1, faster the
    further past; front: `frontWashTime`), it drains at `riderSave` /s once back under; a full meter = the crash, sev >=
    `CRASH_HARD` (3) = at once; below 2.5 m/s nothing soft crashes. `risk` = the fullest meter; reflexes scale with it
    (`riderSkill`): brakes eased (front 60 %, rear 40 %), lean asked of the tyres down 30 %, slide catch up to x2.5. A scare
    over 0.5 fought back to clear = SAVED! (+ style). Impacts stay instant, but BONK over the bars is graded by the rock's
    height against the wheel: `throw_v` 6 m/s (boulder) .. 12 m/s (just past rolling height), never with the front in the
    air. Ride › Tyres › Crashing. Test: `BMX_CRASH_LOG=1` (`CRASH reason | state` and `SAVED peak=` lines).
    The front only washes out LOADED and LEANED (sev x front share / static share x lean): a light front just doesn't steer
    (half of all test crashes were a near-weightless front after landings). `frontWeight`: leaned over the rider moves
    0.12 g onto the front (more while it's in trouble) - the AI rider washed out at one bend every run without it.
    Every number of this work is a slider: Crashing (`crashHard`, `reflexBrake`, `reflexStandUp`, `reflexCatch`,
    `frontWeight`, `bonkBoulder`, `bonkSmall`), Jumps (`whipReturn`) and a **Ride › Smoothing** page (`bankSmooth`,
    `knockSmooth`, `tyreRelax`, `cornerSmooth`, `bankLeanRate`, `motionCap` x the `MCAP` speeds, `torsoMaxSpeed` passed
    to the rider as pose input `torsoVmax`). 60 s test rides (trail, AI rider, whips, swaps): ~0-1 crash each, all real hits.
  - **Air whips** (two masses in the air): the right stick to the side, short of its spin edge (|x| < 0.8), sets the
    hip twist target (`air_tw`, the bike's yaw against the body) to `airWhip` (1.1 rad) x stick / 0.8, past the old
    `airTwist` limit, plus extra lay-over (roll + 0.3 x the whip); `land_prep` eases 70 % of it back for the landing.
    The rider counter-turns in its pose (`airWhip` input = smoothed `air_tw`: hips -0.4, shoulders -0.85, head -0.95 of
    it) so the body keeps facing the flight. Landed straight (< 20 deg) after > 35 deg: "WHIP" / "BIG WHIP" (> 55 deg),
    +500..650 style. Test: `BMX_FOLLOW=1 BMX_TRICK=whip BMX_BIGAIR=1` (`WHIPA` lines, + `BMX_AIRSHOT=prefix`).
  - **Pro flow** (Rider › Motion: `flowBend` spine bows through lean changes as the chest lags the hips, `flowLead`
    shoulders + eyes turn into the turn the body is rolling towards, `flowSink` hips / chest sink into the new turn after
    a quick roll). Test shots: `BMX_TSHOTS=prefix@t1,t2,...` (game clock, ~3 s behind the autotest clock).
  - Measure: `slope_stress.tscn -- sim=1` (`SIM` lines: cambers, flat vs berm turn, `SIM BERM`, `SIM LAND`, brakes, braking in a turn, knocks) and
    `feel=1`; ride log columns `in_brake_f ... balance`; rumble: front push in Tyre slip, either lock in Skids.
- **Tuning card, Ride tab redesigned** (2026-11-20): pages by what you're doing (`ui/ride_layout.gd` `RideLayout.PAGES`:
  Feel, Steering, Tyres, Ground, Brakes, Speed, Body, Suspension, Jumps, Demo; Rider › Physics moved into Ride › Body), each
  row with a plain hint and end words, "*" rows in Simple view, All shows every slider (`TuneCard.ride_all`); any Tune key not
  placed lands in Body › More (`RideLayout.pages()`). Own slider widget `ui/tune_slider.gd` `TuneSlider` (drawn track, tick =
  the preset's value, fill from tick to value, end words either side, double-click / ↺ = preset; an HSlider underneath so the
  pad works). **Feel** page = 8 macro sliders (`Tune.MACROS`, keys `feel*`, 0.5..1.5): each multiplies a set of detail values
  by m^exp in `Tune._rebuild` (clamped to that slider's range), so the detail sliders keep their own settings; a detail row
  shows "Feel x1.2" when one moves it. Test: `BMX_PANEL=ride BMX_PANEL_CAT=<n> [BMX_RIDE_ALL=1]`.
- **Slow-speed feel** (2026-11-20, Ride › Lean: `leanLead`, `slowRoll`, `slowLean`, all fading out with `spd_k`, gone by ~30 km/h):
  slow, the lean target moves towards the lean the asked-for turn needs (`lean_need`) instead of waiting for the turn, the roll
  stiffness is up to 2x, and the steer throws the bike under the upright body (`slowLean` rad); the right-stick bike throw
  (`flickLean`) is full from 1.5 m/s. Measured (`slope_stress.tscn -- feel=1`): lean 63 % in 0.30 s (was 0.58) at 8-25 km/h,
  left / right swap 0.53 s (was 0.88) at 8 km/h; 50 km/h unchanged. The user found slow riding "stiff, not responsive".
- **Corner whip / drift** (`bike_physics.gd` `whip`, Ride › Body › `whip*`): starts ONLY from a deliberate throw of the right
  stick (centre -> edge within `FLICK_WINDOW`, `flick_thrown`) with the steer held the same way past `whipTrigger`, above
  `whipMinSpeed` (2026-11-20: it used to start whenever both sticks passed 0.6, so leaning into a corner with the stick
  slid 20-25 deg: "we slide weird when leaning"). Then the bike is thrown further over (`whipLean`) and the rear swings out to `whipDrift`
  (~0.42 rad) at `whipSnap`, held while both stay there, speed mostly kept (`whipCarry` cuts the slide scrub); "WHIP!" after
  0.3 s (`_whip_arm` = 0.25 s grace after the throw); the ride log has `whip`, `whip_hold`, `raw_right_x`, `raw_left_x` columns; `whip_hold` keeps control `whipCatch` s after letting go so the drift is caught (without it the rear spun out to the
  wash-out angle). Test: `BMX_WHIP=secs` (+ `BMX_WHIP_T0`, `BMX_STRAIGHT=1`) prints `WHIP` lines.
- **Balance manual / downhill pump / perfect landing** (2026-11-20, side-on BMX game feel; Tune group `Balance & pump`,
  tuning card Ride › Balance): the manual / wheelie is a **tipping balance** (`BikePhysics._balance_step`, `man_a` / `man_w`):
  below `manBalance` the front falls, past it the bike tips over backwards faster and faster; the body stick back pulls it up
  (`manLift`), pedalling while pulling helps (`manPedal`), the rear brake (`manBrake`) / leaning forward drop it. Past
  `manBalance + manLoop` = LOOPED OUT (speed x0.72, front thrown down, no crash). In the sweet spot (`manZone`) a small speed
  push (`manBoost`). The old self-holding manual and its sliders (`manBalanceOn`, `manualAngle`, `stickWheelie`, `sprintLift`, `wheelieAngle`, `wheelieClimb`) were removed 2026-11-20; frame character (`BikeBuild.frame_mods`, chainstay) now scales `manLift` / `manGravity` / `manSprintLift`. While a balance manual is held (`_balancing()`, +
  0.5 s `_man_grace` after) nothing judges it as a crash: the ground LOOPED OUT / NOSE DIVE checks skip, a slide sets the
  front down instead of WASHED OUT (`manSlideCatch`), feathering into a lip never throws a flip, the take-off doesn't carry
  the hold's swing into the air spin; it steers on the back wheel (`manTurn`; with the front up the steer used to be 0, so a
  manual went straight on in any bend into the trees). The sprint stamp from slow lifts the front through the balance
  (`manSprintLift`) instead of the old climb that always looped out. HUD: the balance bar shows the moment the stick is
  pulled back (`man_pull`), the pump bar whenever hop is held on the ground (`pump_on`).
  **The right stick pumps too (the pro way, user decision: it's the universal body stick)**: forward = push the bike into
  the ground (how far = how hard, `pumpStick` x the button), eased back up a face = unweight (`pumpUnweight`, a little speed
  carried, no cost), pulled past `manualFrom` = the manual. The hop button is the easy on / off pump. Test
  `BMX_FOLLOW=1 BMX_PUMPRIDE=stick`. **Hop held with both wheels down pumps**: + `pumpHold` x g
  x slope on a down slope, - `pumpHoldUp` on an up slope (`pump_push`, `pump_gain`); a press spent pumping a downhill
  doesn't hop when let go (unless a lip is right there). A jump (> 0.45 s air) landed within `landPerfect` of the slope =
  PERFECT LANDING + `landBoost` m/s. **HUD bars** (bottom centre, `hud.gd` `SlimBar` look: 4 px track, caption left, value
  right): `HopBar` (hop / pop charge in the ride accent, full mark, flash on release), `PumpBar` (centre-zero: green = gaining,
  red = losing, km/h won this rhythm), `BalanceMeter` (sweet spot green, loop-out end red, marker = the front's angle, time).
  The bars' round badges and the balance knob are anti-aliased and on the pixel grid (`SlimBar.badge` / `SlimBar.disc`:
  plain `draw_circle` / `draw_colored_polygon` are not anti-aliased and looked jagged); `BMX_BAR_DEMO=pump|man` holds that
  bar on screen for a shot (they sit ~96 px above the bottom edge, the POP bar lower).
  Tests: `BMX_BODY=balance|overpull` (+ `BMX_STRAIGHT=1 BMX_MAN_PROBE=1`, `MAN` lines), `BMX_FOLLOW=1 BMX_PUMPRIDE=down|all|off`
  (`PUMPRIDE` lines), `BMX_TRICK=…` prints `LANDERR`.
- **One balance, one hop** (2026-11-21, `bike_physics.gd`; sliders Ride › Manual & pump, Tune group `Balance & pump`). The
  manual, the nose manual and every kind of hop share their code; don't add a second path beside them.
  - **Balance, both ends** (`_balance_step` -> `_tip` / `_tip_over`): one tipping-balance integrator for the manual / wheelie
    (`man_a`, on the back wheel) and the **nose manual / stoppie** (`nose_a`, on the front wheel; `noseBalance`, `noseGravity`,
    `noseLift` (0 = off), `noseBrake`, `noseLoop`, `noseFrom`). Only one can be up. Nose: front brake (LT counts) + stick forward
    past `noseFrom` above 2.5 m/s tips the rear up; then stick forward = further over, back = down, the brake tips it on, and the
    brake can be let go (a rolling nose manual). Too far, either end = `_tip_over` (wheel thrown back down, speed x `manLoopKeep`,
    "LOOPED OUT!" / "TOO FAR!", no crash). The pitch hold in the vertical step is shared (`w_up` / `e_up`); on the front wheel
    the fork's levering torque is taken out (the rider's weight is over the front axle; without it the bike only dived on its
    fork). While the rear is up: no OVER THE BARS / NOSE DIVE / WASHED OUT verdicts, no lip window, the rear trails the front (slip
    eased to 0). Style: STOPPIE / NOSE MANUAL x s after 0.8 s; the HUD `BalanceMeter` shows either end (`nose`). `manual_up` /
    `endo_up` are gone (they were copies of `man_a` / `nose_a`); `wheelie_up` = `man_a` set down no faster than `wheelieDrop`.
  - **The hop** (`_hop_begin` -> `_hop_pop`, power from `_hop_power(_charge_k, _scoop_k)`): started by letting go of hop, by the
    **stick hop** (right stick back past 0.5, then snapped forward past 0.3 within 0.22 s) or both. Power = the better of the
    button's charge and the **scoop** (the front already up when it starts: out of a manual, or the stick's own pull; best ~0.3 rad
    .. the balance point, weak hauled to the loop-out; x `stickHop`, 0 = no stick hop / scoop) + a quarter of the other, up to 1.25.
    So: a tap of hop out of a manual = a full hop (~1.1 m), a stick tap ~0.5 m, a well-timed stick hop ~1 m, charge + scoop more.
    A hop let go with the front up is never eaten as a "pump press". `gest_hop` (0.4 s after a stick hop) keeps the forward snap
    from being a flip throw / a nose manual. Near a lip stick back is still a flip throw.
  - **Forgiveness** (`inputForgive` 0.12 s, 0 = off): hop let go up to that long after the wheels left a lip still pops (coyote
    time, `_gl` / `_gc`); a hop tapped in the air just before touch-down hops on landing (`_hop_buf`); a lip pump pressed late gets
    90 % of what it missed (`_pop_miss`); a flip throw (S / W, stick) pressed up to 1.5x that before the lip window opens still
    throws (`_tw_t` / `_ts_t` / `_sb_t` / `_sf_t` = time held). The stick throw only counts inside the lip window (`yb` / `yf`).
  - Tests (with `BMX_STRAIGHT=1 BMX_PAD=1`): `BMX_BODY=bhop` (+ `BMX_BHOP_HOLD=secs`), `BMX_BODY=manhop` (hop out of a manual),
    `BMX_FORGIVE_PROBE=1` (`STICKHOP`, `SCOOPHOP`, `FORGIVE`, `BHOP` lines), `BMX_BODY=stoppie` + `BMX_NOSE_PROBE=1` (`NOSE` lines).
- **Jumps = one push of the legs (2026-11-22, user: "we jump too much, unhuman", then "build MX vs ATV with the stick pump
  to jump, realistic, one nice package, the animation mint")**. `bike_physics.gd`; sliders Ride > Jumps > Take-off.
  **Supersedes the hop / pump numbers in the notes above** (`chargeTime` / `chargePop`, the 2 s charge, the late-pump top-up,
  `pump_lift` and the body kick are gone; the triggers, scoop, coyote time and buffered hop stay).
  - **One budget** (`_leg_dv(power)` = `popPower` x power x a g-out factor): the most speed one push adds to rider + bike.
    `popKick` 2.4 m/s (Tune VER 22; ~2.3 x body weight over the 33 cm leg stroke, 75 kg rider + 17 kg bike); the DH's own
    share is `popPower` 0.9 (was 0.7) = 2.16 m/s. The hop and the pop off a lip both draw on it; `_pop_used` = what this
    take-off has had (a late pop only gets the rest). Pressed into the ground (`_n_grd` = tyre load / resting load) the legs
    have up to 45 % less.
  - **It leaves along the ground's normal** (`_pop_apply`: square to the bike's velocity), so it adds dv^2 / 2 and nothing
    else. It used to be added straight up (+ dv x the climb speed: ~20 J/kg at a lip).
  - **Preload** (`crouch` 0..1, `crouch_t`, `rebound`): hop held OR the right stick pulled back bends the legs over
    `crouchTime` 0.25 s. Power = sqrt(crouch) x (1 - `popRebound` 0.18 x (1 - rebound)): all of it only 0.15-0.5 s after the
    crouch began (the rebound), a crouch held still gives 82 %. A stick held back > 0.9 s stops being a crouch (weight back).
    HUD bar PRELOAD (`hud.gd` `HopBar`, `hop_bar` = the power now: it peaks, then sags; "NOW!" on the rebound, "POP n%").
  - **Pop** (`_pop_now`): let go of hop, or snap the stick forward. Within `popWindow` 0.24 s of a lip (or with the front
    wheel already off its edge, `_lip_ago`) it waits for the edge (`pop_wait`) and goes at take-off, timing 1.0 inside the
    last 0.12 s down to 0.6 at the window's start ("PERFECT POP"). Earlier = a hop off the face, now (worse than hands
    off). In the air within `inputForgive` = late: 75 % of the budget less what was used. Never let go: `popAssist` 0.6 of
    it, timed for you. Hands off: `autoPump` x 0.6 x prep (~0.15).
  - **Squash** (`squash`, `squashPower`): stick held forward for 0.25 s+ into a lip (a fresh push at a lip is still the
    front flip throw): at take-off up to 0.7 x popPower (at most 45 %) of the climb is taken out, speed kept (the velocity
    turns): low and fast, "SQUASH". No auto pop on a squashed lip.
  - **Stick vs flips / manual**: a pull back with a lip in sight (`lip_state` 2) never arms the manual; the forward snap
    zeroes `throw_v` (the pull was the preload). Back and HELD through the lip is still the back flip throw.
  - **Wheel height vs centre of mass**: after a pop the bike is pulled up under the rider (`air_pull` from `pop_fx`, the
    tuck moves the bike by `TUCK_SHARE` 0.75 of the leg travel, was riderMass 0.45). A hop out of a manual no longer keeps
    the frame's rise as climb speed (it added ~0.9 m/s).
  - **Take-off energy fix** (the playground's open findings 1 and 3): the speed along the lip was split with
    cos(the slope under both axles); with the front past the lip that is ~flat or the backside, so the bike kept all its
    speed AND got the climb on top (table_1.5 at 34 km/h left at 29.5 km/h, now 24.8: what climbing 1.5 m costs). Now
    cos(asin(vy / v)). A tyre brushing the lip within 0.2 s of take-off while still going up is not a landing (`_graze`).
    **Every jump flies shorter hands off than before** (table_1.5 @ 34: 7.5 -> 4.5 m, lands on the knuckle); the trail's
    jumps were not re-checked for the speeds they need.
  - **Measured** (test rider, table_1.5 at 34 km/h, peak over the lip): hands off 1.00 m (before 1.07), well-timed pop
    1.72 m (hop held: before 2.75), held and let go late 1.47, popped 0.4 s early 0.57, squash 0.38. Flat hop, full: 0.39 m
    (before 1.0-1.2). Suite baseline re-saved; `slope_stress` 51 / 51.
  - **Rider** (`rider.gd` `update_pose`, inputs `preload`, `extend`, `popFx`, `squash`, `lipK` from `game.gd`): preload =
    sunk between the wheels, chest down over the bars (the stick's lean-back pose gives way to it); through the lip the
    legs drive straight, hips up and forward, back straight, arms long; then the tuck; a squash hangs him back and low
    behind the bars with long arms; on a jump face he stays centred (the climb pose is faded by `lipK`). Pose keys `jumpPreload` / `jumpExtend` /
    `jumpSquash` (no sliders yet).
  - Tests: test rider techniques `BMX_PG_PILOT_TECH=pop|early|hold|squash|hop` (+ `BMX_PG_PILOT_REL=secs` before the lip
    the stick snaps, `BMX_PG_PILOT=feature BMX_PG_AT=...`); `BMX_FORGIVE_PROBE=1` prints `STICKHOP`, `POP lip in`, `HOP
    power= dv= n= legs=`, `LANDED air= peak=`; `BMX_TRICK=none` prints `POP auto`, `SQUASH`; `BMX_LIP_SHOT=prefix`
    (+ `BMX_LIP_PREP`, `BMX_LIP_STEP`) for the poses. Don't start more than 2-3 test windows at once (Vulkan device lost).
  - Not done: the pump for speed on rollers / backsides is still the old push (`pumpHold`), not the leg model; the
    suspension's own rebound is not simulated into the pop (the timing window stands in for it); not ridden by the user yet.
- **Landings (2026-11-22, user: "make our landing better ... does suspension and body react realistically, big jumps,
  landing at a slight corner", "suspension never past its end", "body reacts realistically, no clipping")**.
  `bike_physics.gd`; sliders Ride > Jumps > Landing. Measured before: 43 deg sideways at 47 km/h cost nothing; a flat
  landing from 2.4 m rode on with no reaction; suspension at 102-114 % of its travel, tyres squashed 5-6.6 cm.
  - **Travel is a hard end** (`trF` / `trR` in `_step_vertical`): each end's travel = min(`T.travel`, sag + the DRAWN
    fork's / rear end's room to its stop, `Suspension.F/R["max"]`), so the physics can never press an end further than
    the model shows (the drawn bike was then lifted by the tyre unclip). The last fifth is a bump stop (rate to 7x, only
    while being squeezed: as a plain spring it threw a bike set down deep in its travel into the air); on the stop the
    tyre's push goes straight into the frame; the wheel is clamped at 100 %. Tyres stiffen with squash and sit on the
    rim at `TYRE_MAX` 4.5 cm. Suite: max travel 100 % everywhere (was up to 123 %). The graphs read both ends on the
    front's travel (`dg_travel` = `trF`, `dg_xR` rescaled).
  - **The verdict = what got through** (0.4 s after touch-down): `hit` = sqrt(legs^2 + (1.3 x rim)^2), legs =
    `land_jolt` (the body's speed into the bike when the legs ran out), rim = `_rim_hit` (the speed the whole bike lost
    against the ground with suspension and tyres on their stops). > `slamJolt` x LAND = SLAM!; from `landHeavy` 0.45 of
    that = a heavy landing (`land_heavy` 0..1): up to 22 % of the speed gone, `_stun` 0.25-0.85 s without power, "OOF!"
    / "HEAVY LANDING". Measured: 1 m drop 2.3 of 8.7 (clean); table_1.5 popped onto its landing 5.5 (heavy 0.3);
    overshot to flat 5.6-6.4 (0.4-0.5); the same with the tuck held into the ground 7.8 (0.8).
  - **Clean landings forgiven (2026-11-22, user: "slam too easily on big jumps ... realism but must be fun")**: like the
    arcade bike games the angle decides, the drop mostly costs flow. Landed square to the ground (`_land_pe` = pitch vs
    ground at touch-down; full under 0.18 rad, none past 0.6) the crash line is `slamJolt` x (1 + `landForgive` 1.0),
    i.e. twice the hit; heavy landing still starts at `landHeavy` x the plain limit and runs up to the forgiven one. The
    biggest hit of a landing is kept through its little bounces (`_land_hit`; a bounce cleared it, so forgiven hits
    read as nothing). The user's 7 m to flat at 63 km/h: SLAM -> heavy 0.4 / OOF, rides on. Slider Ride > Jumps > Landing.
  - **Lip launch cap (2026-11-22, F8 log: "lip shot me up 50 m")**: 59 km/h into a ~43 deg natural face, the front left,
    the frame tipped to 83 deg on the rear and the rear spring pumped the climb to 16.4 m/s (> the 15.4 the bike had):
    off at 72 deg, 15 m up. At take-off the climb is held to `v` x sin(lip + `LIP_SPARE` 0.15) (lip = the steeper of the
    last two-wheel slope and the rear's ground; floor 2.5 m/s), and where cut the frame leaves along the flight. Same
    spot now ~5 m high. Probe `BMX_LIP_PROBE=1` (`LIPCAP` lines). Root (the rear probe swinging up the face as the frame
    tips, `_wheel_ground` with cos(pitch)) not changed. Repro: `BMX_SEED=89158 BMX_BIKE=tues BMX_PACK_SPAWN=2382,-11.6
    BMX_START_V=16.4 BMX_STRAIGHT=1 BMX_TRICK=none`.
  - **Sideways** (in the touch-down block): the speed across the tyres has to be stopped by their grip. `landYawFree`
    0.12 rad costs nothing; of the rest the tyres catch mu x (0.8 x impact + 2.5) x `landYawGrip` m/s at once (speed
    gone, `land_yaw`, "SKETCHY!" / "SIDEWAYS!"), what is left is a slide for the ground sim; more than `landYawCrash`
    5.5 m/s caught at once = HIGHSIDE!. At 26 km/h: 15 deg 7.3 -> 7.2 m/s, 30 deg -> 6.7, 45 deg -> 5.7; at 47 km/h
    30 deg+ is a highside. (Past `LAND_CONE` 60 deg the old SKETCHY / FAKIE rule still runs first.)
  - **Drops**: rolling off level ground at speed the rider holds the bike level (`edge_k`: the balance torque x3.5 and
    its gain x6, only with the front well clear of ground that falls away AND the rear on level ground: over a crest
    or off a lip it stays out). drop_1 at 24 km/h: 40 -> 27 deg nose down; drop_2 at 28: NOSE DIVE crash -> clean.
    Rolling on the rear wheel alone, the hill the drive feels is the ground under that wheel (it was the frame's
    pitch: nose-high down a bump's back side it "climbed" and stalled).
  - **Tuck held into the ground** (`_tuck_in`): the legs' reach for the landing is cut to a quarter, so they bottom.
  - **Perfect landing**: the boost is pumped out of a downslope (`landBoost` x how steep x how hard, none on the
    flat); it was a flat +6 km/h from nowhere.
  - **Rider** (`rider.gd`, inputs `landFold`, `landReach`): reaches for the ground (hips up, back straighter), the hit
    folds him (hips down and back, chest down; `land_fold` from the impact, kept down longer by a heavy one), then he
    comes up (0.45-2 s). `BMX_BODY_CLIP` over the landing runs: 0 clips.
  - Tests: `BMX_PG_PILOT_YAW=<deg>` / `BMX_PG_PILOT_TUCK=1` (test rider lands turned / tucked), `BMX_LAND_PROBE=1`
    (`HIT legs= rim= hit= of heavy=`, `YAWLAND angle= side= caught= left=`; also with `BMX_TRICK`), `BMX_LAND_SHOT=prefix`
    (12 frames through a touch-down). Suite baseline re-saved; `slope_stress` 51 / 51.
  - Open: on the trail the auto rider's first jump measured a hit of 8.3 of 8.7 with the 1.5x rim weight (now 1.3x):
    slams may be common at trail speeds, tune `slamJolt`; a rim strike still stops the frame in one step (50-67 g);
    rollers show energy gains of ~0.5 J/kg at crests (the rear-wheel slope reading); drop_2 still lands 50-60 deg nose
    down; high-speed compression damping is weak (the shock's blow-off), so big hits reach the rim; not ridden by the
    user yet.
- **Trail jumps resized to the speed riders arrive at (2026-11-22, found testing the landings on the trail)**.
  Measured with `BMX_JUMP_PROBE=1` (`JUMPLAND SHORT | LANDING | LONG | NATURAL v_off= dist= height= impact= slope=`:
  where on a built jump it came down, from `TerrainField.fo_air` / `fo_m`): the built jumps suited ~30-35 km/h; at the
  48-60 km/h riders really carry, every one was overshot onto the flat past its landing (21-24 m out) or into the
  next jump's face. With landings judged, that was a heavy landing on every jump and the demo rider slammed on a
  jump line. Now `TrailFeatures.TABLE / DOUBLE / KICKER` (+ `AIR`) are 1.6x in every length and height (same lip and
  landing angles; mirrored in `TerrainFieldCs.cs`), for the jumps ON THE TRAIL (`route_feats`). The free-ride jumps
  out in the land (`jump_at`, found through 34 m cells, close to each other and to wooden features) keep the old
  size: `TABLE_S / DOUBLE_S / KICKER_S / AIR_S`, `TerrainField.small`, `make_feat(..., old_size)` (bigger, they
  overlapped: `wood_edge_probe` walls=4). Bigger jumps take more of each straight, so there are fewer route features
  (12 worlds x 4 km: 166, was 222) and bridges were getting rare: gorge chance 0.06 -> 0.13, rope hash 0.12 -> 0.3
  (7 bridges in those worlds, was 8). **Every world's trail features past the first are laid out differently than
  before**; seed 4242 no longer has a rope bridge in its first 4 km (seed 12 has one at 2.26 km: `BMX_SEED=12
  BMX_TRAIL_FEAT=rope`). Heavy landings also cost less: `landHeavy` 0.45 -> 0.6 (Tune VER 24), speed lost 22 -> 12 %,
  stun 0.15-0.6 s. After, 150 s rides: the demo rider (35-47 km/h) lands every built jump on its downslope, no heavy
  landing, no crash, no body clipping; flat out (54-63 km/h) one heavy 0.77 on the first jump, the rest light, no
  crash. `terrain_cs_cmp` EXACT, `trail_grow_probe` / `rope_find` / `cactus_probe` PASS, `wood_edge_probe` walls=0,
  suite 0 of 24 changed, stress 56 / 56. New `tools/route_count.gd` (-s: route features per type over 12 worlds).
- **Suspension = parts with a setup (2026-11-22, user: "should behave realistically like on bikes ... comprehensive:
  later riders tune shocks, buy another one, some hydraulic, some spring")**. New `scripts/bike/susp_setup.gd`
  (`SuspSetup`): a FORK and a REAR SHOCK, each a unit of plain data: spring `air` | `coil`, travel (mm), sag (%),
  tokens (volume spacers / bottom-out bumper, 0-4), damper clicks `lsc` / `hsc` / `reb` (0-10, 5 = middle), `adj`
  (which adjusters that damper has: a basic shock is rebound only), kg. `SuspSetup.unit(...)` turns one into the
  physics' numbers, `resolve(build)` does a whole garage build -> `{f, r, psi_f, psi_r}`; `SHOCK_MODELS` = the rear
  shocks (made-up brands; coil / air / one with a hydraulic bottom-out); forks stay `BikeBuild.FORK_MODELS` (their
  `spring` Air / Coil is used; an optional `adj` list limits the adjusters). **A shop / rider tuning only has to write
  the build's keys** (`suspension.fork_sag / fork_tokens / fork_lsc / fork_hsc / fork_reb / shock_model / shock_sag /
  shock_tokens / shock_lsc / shock_hsc / shock_reb`, `wheels.psi_f / psi_r`; `SuspSetup.val` gives a key's value, old
  saves' 3-step spring / rebound choices are carried over) or add a model to a catalogue.
  - **Physics** (`_step_vertical`, per end): travel `tr`; spring F = k x (1 + pg (x / tr)^2) with k set so that end
    rests at its sag under its share of the weight (air pg 0.4 + 0.22 / spacer, coil 0.04 + 0.03 / step; the rear adds
    the frame's linkage: `FRAME_PROG` 0.35 x `shockProg`, from `BikeBuild.frame_mods`' progression); compression
    damping zc (0.16-0.54 of critical) up to the knee `damperKnee`, past it `hs` of it (0.22-0.77; `damperBlow`
    default 0.2 -> 0.4, Tune VER 23); rebound its own zr (0.25-0.85); seal friction (air 0.05 g, coil 0.018 g of that
    end's load); bump stop strength by tokens; the tyre's stiffness from its pressure (`PSI_REF` 25). `press`
    (legPress) is cut to 35 % on a bike with a setup. A bike with no setup (the BMX) keeps the one simple spring
    (`sus` empty; `BMX_NO_SUS=1` forces that for comparison). The drawn fork / rear end get the same sag
    (`Suspension.set_sag`) and the physics travel is never more than the drawn one.
  - **Ride sliders on top of the setup** (Ride > Suspension): `tyreHz` (spring rate, 2.4 = as set up), `tyreDamp`
    (all damping, 0.39 = as set up), new `suspSag`, `suspRebound`, `suspProg` (x). The garage no longer multiplies
    `tyreHz` / `tyreDamp`; tyre pressure also moves grip (+0.6 % per psi softer) and rolling drag (+1.2 %).
  - **Garage > Shocks** (`_susp_page`): per end travel, sag, spacers / bumper, LS / HS compression, rebound (only the
    adjusters the unit has), the shock picker, tyre pressures, a line describing each end. The Landing stat bar
    reads the setup (`BikeBuild._land_k`). Shock weight is in `bike_kg`.
  - **Measured** (test rider, drop_1 at 24 km/h, speed lost at the rim): stock 0.44 m/s; sag 36 / 38 % 1.61; sag 20 /
    22 % 0; spacers 4 0.03; spacers 0 1.03; compression all 10 clicks 0; all 0 clicks 1.56; air shock 0; tyres 15 psi
    1.77. Suite vs the old single spring: jumps within tolerance, fork use on landings 72-93 % (was 96-100 %),
    hard front braking 45 % of the fork. Sag on the graphs: 28 % on built ground, 32 % on natural (the rest of `press`).
  - Tests: `BMX_BUILD="suspension.fork_sag=36;suspension.shock_model=air_dh;wheels.psi_f=15"` (setup keys work even
    when a build doesn't hold them yet), `BMX_GARAGE_TAB=suspension`, `BMX_DIAG_PROBE=1` (`DIAG SUSP ... sag= travel=`).
  - **Geometry: brake dive, anti-squat, anti-rise** (same day, user: "do this now"; `dvF` / `dvR` in
    `_step_vertical`, only on a bike with a setup, on the ground): the extra push on each spring from where its wheel
    moves as it compresses. Fork: it slides along the steering axis (`Suspension.axis`: tan 0.51 on the RUNOUT, 63 deg
    head angle), so the front brake's force presses it in by brake x tan(tilt). Rear: `antiSquat` (Tune follower,
    0.9 x the frame via `frame_mods`: 0.4 + its anti_squat figure) x drive x loadHeight / L holds it up under power,
    `ANTI_RISE` 0.6 x the rear brake sits it down. Applied as equal and opposite forces on frame and wheel, so the
    tyres' loads (grip, stopping distance) don't change: only how far the spring is pressed (`sumF` / `sumR` take it
    back out). Slider Ride > Suspension `suspGeo` (0 = off). Measured: front brake at 0.75 g: fork 62 % of its travel
    (41 % without), 4.23 m either way; rear brake: shock 33-34 % (31 %); sprint: shock 45-49 % (49-52 %).
    Probe `BMX_GEO_PROBE=1` (`GEO v= brake f= r= drive= tan= AS= dive= rear= fork=% shock=%`).
  - **Review for stability + speed (same day, user asked for it)**. Found and fixed: (1) nothing limited what the
    explicit step (dt / 4) can integrate: a wheel is a small mass between the tyre and the suspension spring, and a
    light wheel (`wheelMass` 0.01) with a firm setup, 4 spacers, `suspProg` 2.5 and rock-hard tyres came to stiffness
    x step^2 / mass ~ 24 (limit ~4), rebound wound in to damping x step / mass ~ 17 (limit 2). Now `k_cap` / `c_cap`
    in `_step_vertical` hold spring + tyre stiffness and every damping rate inside what the step can take (the stock
    setup is at ~35 % / ~30 % of them, so nothing changes there: suite compare 0 of 24 changed). (2) The tyre's
    re-seat on the rim could push a wheel past its travel when no wheel position can reach the ground (hung on the
    stress test's 9 m wall: 374 %): the travel limit now has the last word. (3) The step read ~25 dictionary values
    and ran two pow loops every step: the units' numbers are cached as floats (`_su`, `_sus_cache`), `SuspSetup.rest`
    has no pow. Step cost (slope_stress, headless): 99 us before the suspension work, 117 after it, 108 now.
    `slope_stress` grew: 5 "susp:" torture checks (drops of 5 / 9 m, a 25 cm square edge at 16 m/s, 15 cm washboard at
    20 m/s, 1.2 m rollers) and a `SUSP travel max= tyre squash max= slowest step= blown-up rides=` line; every ride in
    it tracks the most travel used. Run it on a setup with `BMX_BUILD="..."` + `tune=k=v,...`. Twelve setups tried
    (stock, softest, firmest, air, hydraulic stop, 160 / 220 mm, three sets of sliders at their ends, the BMX, the old
    single spring): 0 non-finite states, travel max 100.0 %, tyre 4.6 cm. Behaviour checks fail only on absurd
    slider sets (everything rigid: it bounces off washboard) and the chaotic "brake grade -35 deg" one.
  - **Rim strikes on rocks (found testing the merge on the trail)**: with the real, shorter travel a rock or kerb met
    mid-corner at trail speed put an end on its rim, and the frame was then thrown up at the edge's whole rise (up to
    12 m/s): the legs bottomed and it read SLAM! (2 in a 74 s ride; in the F8-style ride log `v` goes negative for a
    moment: that is the crash's throw, not riding backwards). `RIM_CLIMB` 4 m/s now caps the upward speed a rim strike
    on a rising edge gives (the position is still carried over the edge; landings are untouched). 3 trail rides
    after: no SLAM. Suite 0 of 24 changed, stress 56 / 56.
  - Open: the wheelbase and head angle don't change as the fork dives (the ride geometry is fixed), no pedal kickback
    / bob with each stroke, the rear axle's path doesn't soak up square edges differently. No shop / prices for
    shocks yet, shock models have no 3D model or card picture. Not ridden by the user yet. (`slope_stress` is 51 / 51
    again; its "brake grade -35 deg" check is a chaotic slide at the friction angle and flips with small changes.)
- **Direct manual (2026-11-22, user: "too stiff, locks us in, going too far stops us, make it more manual"; then "fall if we pull too far", "turn
  less, with body lean")**. `manDirect` 1 (Ride > Manual & pump; 0 = the old tipping balance, they blend): **the stick is the front's height**.
  `_balance_step`: target = pull x (`manBalance` + `manLoop` + 0.08), `man_a` follows on a soft spring (`manFollow` 40, ~0.3 s), so it never runs
  away from the stick. `manualFrom` 0.4 -> 0.25 (Tune VER 18): a light pull lifts a little, ~65-70 % stick sits on the balance point (sweet spot,
  boost), the edge is past the loop-out. Held past it 0.2 s = **falls off the back** (crash LOOPED OUT!; `manFall` 0 = floats at the top instead).
  No lock-out, no speed cut in direct mode (`_tip_over` only in the old mode). Rear brake / stick forward lower the target; a sprint stamp raises it.
  Nose manual: same spring, tops out at `noseBalance` + 0.12, never throws him over. `wheelieDrop` x4 in direct mode. **Turning on the back wheel**:
  the turn and the lean asked are capped at what `manLean` (0.42 rad) gives at that speed (G tan / v: ~21 m radius at 36 km/h, tighter slower), x
  `manTurn`; no FRONT WASHED OUT verdict while balancing. The drawn pitch sits ~0.13-0.17 rad under `man_a`. Tests: `BMX_BODY=pull:<0..1>`
  (+ `BMX_STRAIGHT=1 BMX_PAD=1 BMX_MAN_PROBE=1 BMX_CRASH_LOG=1`): 0.5 -> a 0.28, 0.7 -> 0.59 steady in the zone, 1.0 -> falls after ~0.6 s. The old
  **It starts from a quick pull, not from how far the stick is** (user: the manual "overrode our leaning", leaning back / forward on the track
  changes the cornering): `_man_armed` is set when the stick goes centre -> back past 0.5 within `manPullTime` (0.25 s, `_pull_age`; 0 = any pull),
  stays while the stick is back past 0.12, and without it `pull` = 0: a slow lean back, even to the edge, only shifts the weight. `manBothSticks`
  (default ON since 2026-11-22, Tune VER 19: with the quick pull alone the user still "triggered a lot"): on a pad the left stick must be pulled back too
  (`inp.left_back` = raw left stick Y from `Game._read_input`, test `BMX_LEFT_BACK=1`) to arm; after that only the right stick holds it.
  Tests: `BMX_BODY=slowback:1.0` (ramps over 1 s once rolling: must stay `armed=false`), `pull:0.7` (armed), MAN probe prints `stick= armed= age=`.
  **Corner gate + power wheelie (same day; user: "still trigger a lot", then "add corner gate and make it behave like in MX vs ATV")**:
  `manBothSticks` is back to off (Tune VER 20). `manGate` (0.2 rad): the quick pull only arms when the bike is leaned less than that; leaned into
  a corner, weight back never lifts the front (once up it stays up). `manPower` (1) / `manPowerSpeed` (9 m/s): weight back + pedalling lifts the
  front with no pull (`_man_pw`, eased; all of it slow, none by 9 m/s; at most to the balance point, only a pull can go over the back); stop
  pedalling and it comes down. Tests: `BMX_BODY=slowback:1.0` (pedalling: lifts slow, fades by ~10 m/s), `cornerpull:0.8` + `BMX_STEER=1`
  (must stay `armed=false`), MAN probe prints `armed= pw= lean=`.
  **Front wash-outs made rare (user: "a lot of times I fall front wash, make the rider more skilled")**: `frontWashAt` 1.35 -> 1.7,
  `frontWashTime` 0.35 -> 0.7 (VER 21), the front's severity is capped under `crashHard` (never an instant wash-out), and the rider's weight-
  forward reflex in trouble is x(1 + 3.5 x the meter) (was 1.5). Same trail test rides with weight back: the wash-out became a SAVED.
  `BMX_BODY=balance|overpull|stoppie` controllers were written for the tipping balance (use `BMX_TUNE=manDirect=0` with them). Not yet confirmed by the user riding.
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
- **Never through the handlebar** (2026-11-22, user: "head and upper body clip into the handlebar a lot", then of a
  squash shot "completely insane unnatural pose"; `rider.gd`, first of the safety limits, right after the hips box):
  seen from the side the chest joint stays `BAR_CHEST` 0.32 m and the head's centre `BAR_HEAD` 0.31 m from the middle
  of the two grips. Inside that the WHOLE upper body is moved out, mostly back and a little up (hips 85 % with it): the
  arms get longer, the back keeps its angle, the hips go behind the saddle. Pushing only the chest (first version) stood
  him bolt upright with his elbows folded under his chin; pushing mostly up did the same. The rear-wheel / torso limits
  after it still apply. The crouches no longer stack past 20 cm (`deep_c`: lip crouch + preload + legs pressed in by a
  transition came to 35 cm). The squash pose = hips back and down, arms pushing the bars away (not folded over them).
  Before: on a 40 s trail ride the chest came within 1.5 cm of the bar's middle and the helmet 6.5 cm; it now holds him
  out in ~14 % of frames, the joints' frame-to-frame steps about as before (chest 81 vs 74 direction flips).
  Probe: `BMX_BAR_PROBE=1` (`BARCLEAR deepest_cm= held_frames= least_chest_cm= least_head_cm=`), `BMX_NO_BARLIMIT=1`
  measures without holding. **Judge rider poses on enlarged side-view crops of every frame through a lip
  (`BMX_LIP_SHOT`), not on one frame.**
- **Head stabilisation + ankling (2026-11-22, from the research review `docs/research/rider_animation.md`; papers in
  `C:\Users\Luka\Documents\GameResearch\`)**. `rider.gd`: the head's pitch follows a critically damped copy of the bike's
  pitch (`_hp_s`, `HEAD_PITCH_HL` 0.16 s, Holden's exact spring `Rider.crit_spring`) and holds against the quick part
  (`head_kick`, +-0.45 rad, faded mid-flip); quick yaw twitches (yaw rate minus its slow average) are held against and let
  go (`_hy`, `HEAD_YAW_HL`); the pedalling rock is taken out of its roll (`rockRoll`); its position rides a short neck spring
  on the chest (`NECK_W` 15, max `NECK_MAX` 2.5 / 3.5 / 1.2 cm). Ankling (Gregor 2000: ~20 deg of ankle per crank turn):
  the foot pitches about the pedal axle with the stroke (`ANKLE_SWING` 0.17 rad, heel lowest `ANKLE_PHASE` past the front),
  toes down sprinting, heels down coasting in the attack position / soaking a hit / reaching for a landing; the ankle (IK
  end) turns with it and `Game` turns the pedal pivots by `rider.foot_pitch` (flat pedals tip under the shoe). Pose keys
  (Rider > Head / Legs & feet): `headSteady`, `ankling`, `heelsDown` (0 = the old behaviour). Measured on the rocks lane
  (`BMX_LEVEL=playground BMX_PG_PILOT=lane BMX_PG_AT=rocks BMX_PG_PILOT_KMH=30 BMX_PG_PILOT_PUMP=0 BMX_HEAD_PROBE=1`, repeatable
  to ~1 %): head world angular speed rms pitch 0.30 -> 0.17, roll 0.26 -> 0.014, yaw 0.097 -> 0.083 rad/s; bar clearance,
  jitter counts unchanged. `BMX_HEAD_PROBE` (`HEADPROBE` lines; its acc_rms is frame-timing noise, ignore). BMX_FOLLOW trail
  runs are NOT repeatable enough to compare small changes: use the playground pilot.
  **Shoe on the pedal (same day, user: "gap between foot and pedal, they float; riders have the pedal under the ball of
  the foot")**: the sole used to sit a fixed 3 cm over the pedal's pivot (= the pedal mesh's middle) with the shoe's
  middle (arch) over the axle: 13 / 6 / 18 mm of air on the stock / Tusk / Fizz pedals. Now the ball of the foot
  (`Rider.BALL_X` 8 cm forward of the shoe's origin, ~70 % heel to toe) is over the axle and the sole rests on the pedal's
  measured top (`BikeRig.pedal_top` = the pedal mesh's top above its pivot, per model, `pedal_top_in(rider)` -> pose input
  `pedalTop`); the ankle hangs off the shoe (`ANKLE_UP` 9 cm, 4 cm behind its origin). The pedals turn with the foot's
  whole pitch (footAngle + ankling, `rider.foot_pitch`) in the ride and on the rider room's rollers. Standing riders keep
  the old placement. Probe `BMX_PEDAL_PROBE=1` (`PEDALPROBE gap max/min mm, ball off axle mm, sole vs pedal deg`): 0.0 mm
  on all three pedal models; `-s res://tools/pedal_size_probe.gd --headless` prints each pedal model's size.
- **Pose order: limits on the target, then the springs (2026-11-22, research points 4 / 5 / 6 / 3 of
  `docs/research/rider_animation.md`)**. Measured first with the new probe `BMX_POSE_PROBE=1` (`rider.gd`: per correction
  step - arm reach, hips box, bar, rear wheel, torso angle / length, saddle / tyre floor, motion cap - how often / how far it
  moves hips + chest; per joint the frame-to-frame 2nd difference in the bike's frame and, `W*`, in the world; `POSEJUMP`
  lines for single-frame hip steps > 4 cm with the jump / landing state). Found: the corrections ran AFTER the body springs
  and moved the torso by up to 37-73 cm (arm reach) / 42 cm (bar), on and off frame to frame. Now:
  (1) `Rider._constrain()` = the whole correction chain, run on the TARGET before the springs, again on the springs' result
  with the correction written back into the spring state and the velocity into the limit removed (position-based dynamics:
  no spring pushing into a limit every frame), and a last pass after the view-only turns (pedalling rock, pitch kick).
  (2) Body + roll springs step exactly (`Rider.spring_exact`, Holden's closed form, under / critical / over-damped, with the
  bump push; `BMX_EULER_BODY=1` = the old Euler steps). The fps difference that is left comes from the bump input measured per
  frame, not the springs. (3) The pitch-kick hold read a jump face as a bump and leaned the whole body back up to ~20 deg up
  every lip (+ a step as it switched off at take-off): it now measures against the land's slope on a rising jump face
  (`face_k` from `lipK`), eases out in the air, soft limit (tanh). Curbs / ledges / rocks are still held against.
  (4) The chest rides the hips softer up / down (`CHEST_KY` 0.6 x the legs, `CHEST_PUSH` 0.6 of the bump; 0.4 was worse).
  Result vs before (playground lanes, 60 fps, world rms hips / chest / head): rocks -2..-5 %, drops -3 %, bumps -20 %,
  tables hips +13 % (the jump moves now shown, not clipped) chest / head -4 %; knees 25-45 % smoother; the corrections
  after the springs 4-9x smaller; no body clipping (`BMX_BODY_CLIP`), bar clearance unchanged. `BMX_OLD_LIMITS=1` = the old
  order. **Check any pose change with `bash tools/pose_suite.sh <tag> [ENV=..]`** (rocks, tables, drops, bumps lanes + a
  trail lean-swap run, 2 windows at a time; the trail one is not repeatable). Not done: per-limb speed into the ragdoll
  (point 7: the stiff-then-tone start, startle and no-eject are already there).
- **Body never through itself or the bike** (2026-11-22, user: "we need smart limits or our body will clip"; `rider.gd`).
  Measured first, then limited: `BMX_BODY_CLIP=1` (`Rider._clip_probe`, `BODYCLIP <pair> frames= % deepest= cm` at the end
  of a test run) takes the drawn body as capsules (head, torso, thighs, shins, upper arms, forearms) against the bar, the
  saddle, both wheels and each other, every frame. Found over 12 scenarios (trail, flips, pop, squash, drop, tuck,
  manual, hop, sprint, lean, air stick, brake + turn): knees in the chest (to 11 cm; 90 % of frames in the tuck),
  forearms in the thigh / shin (to 7 cm in leans), hips in the saddle (to 10 cm), hips in the rear tyre (rare). Limits:
  `_swing_clear` (a knee / elbow swings about its root-tip line, out to its own side, by the smallest angle that clears:
  knees round the torso `LIMB_TORSO` 0.18 m, elbows round the leg on their side `LIMB_LIMB` 0.105 m; hands and feet
  stay put) and a last saddle / rear-tyre floor for the hips after the bar limit and torso clamp moved them. After: all
  of those 0 in all 12; left: hips / thigh in the rear tyre in 0.2-0.3 % of frames in flips, a shin in it in 0.9 % of
  the brake + turn test. Run it after any change to the rider's pose: `. /tmp`-style loop = each scenario with
  `BMX_BODY_CLIP=1`, two windows at a time.
- **Skeleton safety limits** (`rider.gd`, just before the torso length clamp): hips in a box over the bike, the
  torso bends only -26..80 deg forward and +-34 deg sideways from the bike's up; body counter-roll capped at ~50 deg.
  Whatever stacks up (tuck, spin, lean, landing, sliders) the body can't be mangled.
- **Air spin pose**: spinning in the air the rider sits tall and compact (knees in), head + shoulders lead.
- **Style points** (`bike_physics._style_points` -> `hud.StylePop`): air time, 360s, flips, tweak, x1.5 clean landing,
  combos (landings within 4 s chain and multiply); banked after 0.7 s, a crash before that = BAILED.
- **Stick wheelie / manual**: right stick pulled back past `manualFrom` = the balance manual (pedalling = a wheelie);
  held > 1 s scores style points (WHEELIE / MANUAL x s).
- **Pad steering curve** (`Settings.pad_expo`, Settings › Controller): the left stick's first travel tips the bike in
  gently, full lock at the edge (keys unaffected).
- **Pose memory resets on get-up** (`Rider.reset_pose`: wheelie / tuck / effort / turn smoothing) - a crash left a
  "wheelie" behind that snapped the body about; the torso limit treats a chest below the hips as folded forward
  (no flip-flop). Test: `BMX_BRAKETURN=secs` (sprint, then hard brake + full lock) prints `JITTER` / `JUMP` lines.
- **Tune migrations**: `Tune.RETUNED_AT` lists keys whose defaults changed per version (only those reset).
- **Tests run minimised**: `BMX_MIN=1` (they still render, screenshots work).
- **Ride log** (`game/ride_log.gd`): the last 60 s of every physics step (bike physics, body, drawn-bike lift,
  rider joints, all inputs) kept in a ring buffer; **R3 / F8** (`save_log`) writes it to
  a `crashlogs/manual_<date>/` report (`ride_log.csv` + the recent log + context, via `CrashLog.report`; last row = the press, `before_press` column).
  The way to find a glitch the player saw. Test: `BMX_SAVELOG=secs`.
- **Lean limit shiver (2026-11-21)**: `lean_room` (the ground slope 0.3 / 0.5 m beside the tyres that limits the lean) was only
  rate limited (3 rad/s), so every ripple went into `lean_lim`: laid on the limit at the top of a berm the bike, `counter` and
  with them the whole rider shivered ~+-1 deg at ~7 Hz (the user: "vibration in corners"; pedalling or not). Now also eased
  (6 /s, ~0.17 s). Found from an F8 ride log (`bike_lean` wobbling while `lean` was smooth); the synthetic test riders never sit
  on that limit, so it did not show in `BMX_JITTER_ALL`. Replayed on that log: 0.40 -> 0.06 deg rms (estimate). `BMX_JDUMP=file.csv`
  (+ `BMX_JITTER_ALL=1`) writes every drawn frame's rider joints. Playground graphs (Body tab) now also draw the nose manual
  angle and the rider's own hip / chest roll (`Rider.roll_p` / `roll_c`) beside the bike's lean.
- **Berm shake = `BikeRig.fit_wheels` flip-flop (2026-11-21, the real cause of "the rider shakes at the top of berms")**: the fit
  assumed a metre of travel gives `up_f` / `up_r` (>= 0.4) of clearance. Laid right over (>= ~57 deg) on banked ground the wheel moves
  mostly sideways as it compresses, toward ground that falls away: real gain ~0.85, so each pass overshot by more than it corrected, and
  since the travel carries over between frames the wheels flipped between two answers on alternate frames; `unclip_tyres` then lifted
  the bike 0 / 8 cm frame by frame and the rider (hips / chest feel the frame) with it. Now the gain is measured from the last pass
  (secant, clamped), up to 6 passes. Seen in the F8 ride log as `tyre_lift` zigzagging 0.00 / 0.08 at `bike_lean` 1.2 (162 zigzags in
  60 s; none below 0.8 rad). Test riders rarely lean that far on a bank, so no autotest shows it: check with an F8 log from a real ride
  (`tyre_lift`, `drawn_y`, `pelvis_y` columns). F8 / R3 now pops "LOG SAVED · CRASHLOGS/<folder>" in the loud all-caps style.
- **Rocks (2026-11-21, user: "rocks shake the whole rider, he rocks back and forth as one stiff unit, some we crash on though we could ride over")**:
  - Playground lane **ROCKS** (z = -24; `Lane.rock_row` / `rock_garden`, `PlaygroundCourse.rocks`, `height_rocks`, `rocks_near`): the world's own rock meshes
    + colliders + domes: rows of one size (`rock_3` .. `rock_22` cm, `rock_34` = too tall), `garden_line` (the trail's recipe, with its clean
    line) and `garden_full` (rocks everywhere). Ride it with `BMX_PG_PILOT=lane BMX_PG_AT=rocks BMX_PG_PILOT_KMH=36 BMX_PG_PILOT_PUMP=0` (the lane
    rider steers; `BMX_STRAIGHT` gets knocked off line by the 6 cm row). Lanes start at x = -30 (`X0`): feature u = x + 30.
  - Rideable rock shape = the stone's visible cap (`Terrain.dome_h(base, top, sink, q)`, collider key `sink` = how far the middle is under the
    ground, mirrored in `TerrainFieldCs.height`; logs / stumps have no sink = the old half dome). The half dome met the ground as a vertical wall.
    Only ~10 % calmer in numbers: the hit is mostly the rock's height against the spring rate.
  - Rider holds their line against quick pitch kicks (`rider.gd` `bump_pitch` = the bike's pitch minus its ~0.35 s average, x pose input
    `bumpPitch` 0.85, turned back out of hips + chest AFTER the body springs: through them it came ~60 ms late and made it worse). A rock is no
    longer a wheelie / climb to the rider: pose input `slope` is the land's (deck_height, no domes) and the wheelie pose needs `frontUp`
    (`wheelie_up`). Torso swing in the world on rock_20 at 35 km/h: 16 -> 11 deg, rock_14: 9.3 -> 7.2. Probe: `BMX_KICK_PROBE=1` (`KICK` lines).
  - The body isn't thrown fore / aft by a rock's edge any more (`proj_dv`: the speed lost to a ground kink is left out of `a_body`).
  - The drawn tyre-unclip lift is eased (`Game.LIFT_UP` 2.4 m/s, `LIFT_DOWN` 0.6 m/s, `_lift_s`) and kept out of the rider's bump spring (pose
    input `frameY` = the physics frame height). A tyre may now dip into a rock for a frame (CLIP probe: 1 frame, 1.5 cm in a 45 s ride).
  - Wall check measures a rock against its own ground too (`min(top - y, top - base)`): on a climb / bank / leaned, a 15 cm stone read as a
    wall (BONK, thrown backwards; seen in an F8 log as v 9.2 -> -2.6 m/s with a 23 cm lift).
  - Still open: big rocks (>= 20 cm) pitch the bike 13-16 deg and throw it into the air at 35 km/h (spring rate, not shape); the pose changes
    between pedalling and coasting move the hips ~10 cm; not yet confirmed by the user riding.
- **Air control, arcade-smooth (2026-11-21, user: "can't trigger it right away, spinning left / right is weird, the landing assistance nags"; wants old motocross / BMX game feel)**:
  the stick is followed quicker (`stickAirEase` 3.5 -> 8, Tune VER 17; tilt spring 22 -> 50, lean 45 -> 80; spin answers at 11 /s and stops at 10 /s,
  edge lets go at 10 /s; `stickSpinGrow` 0.8 -> 0.4). **A flat spin turns rider + bike as one**: the hip twist / whip (`tw_t`) and most of the lay-over
  fade out with `stick_yaw` (the hips used to hold the bike on the travel line: it snapped out ~60 deg, hung, then jumped ~130 deg in 0.1 s when
  `sys_slip` wrapped). **The player's stick always wins**: `_air_own` (1 while any air control is used, fades 0.4 s after) and `air_help` =
  `airAssist` (new slider, Ride > Jumps > Landing, 0.6) x hands off scale the landing tilt aim, the yaw straighten (now within 1.2 rad) and the whip
  return. A steer held off the lip counts in the air once moved 0.35 (not only after re-centring). Measured with `BMX_FOLLOW=1 BMX_PAD=1
  BMX_BODY=spin360 BMX_BODY_PRINT=1 BMX_BIGAIR=1`: let go at 300 deg -> lands 362 (was 450, with the lurch). Not yet confirmed by the user riding.
- **Cameras ride the bike's height without its bumps (2026-11-21, user: "side cam reacts harshly on bumps, exaggerates impacts, looks glitchy")**:
  `CameraRig._smooth_y` (two low-passes of `Y_TAU` 0.28 s read as 2 x first - second: no lag on slopes / jumps, a rock's kick or a landing's
  compression at about a sixth) feeds every follow camera's aim and anchor (side, chase, trail, drone, the playground's). The view-blocked check
  (`_blocked`) looks at the land only (`deck_height`: rocks tripped it), uses the smoothed height and has a 0.2 m margin (on flat ground it was
  razor-thin: a 1 cm suspension dip flipped it and the camera hopped a few cm a frame). Impact shake amplitude halved. Measured on the rocks lane
  (`BMX_CAM_PROBE=1`, new `world_y_jerk_mm` = the camera's own height, 2nd difference per frame): side 5.9 -> 1.7 mm, chase 1.1 mm.
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
  ends; the stump pumps an **arterial jet** with every heartbeat (`JET_T` 9 s, `HEART_HZ` 2, `JET_SPEED`; drops in their own MultiMesh drawn stretched along their flight by `shaders/blood_jet.gdshader` so they join into one stream, pooling where they land), the torn-off piece pours out of its end. Smears start as a faint narrow trace and build up over the first metre of a slide (`_slid`), fade in as they're laid (shader `soak`), drawn as a thin see-through film with drag streaks (pooled = deep red, dried = brown). **Fatal crash** (> `FATAL_SPEED` 12 m/s or a limb torn off; `BMX_FATAL=1` forces it): once the body lies still a pool spreads from under the chest (+ each stump) to `POOL_R` over ~`POOL_T` s; it is a small real liquid simulation that follows the ground (`fx/blood_pool.gd` + C# `BloodPoolSim.cs`: 256x256 cells of 4 cm = 10.24 m; ground sampled every 16 cm (the draped mesh uses the same samples) via `top_height` + mm bumps; each cell passes blood to lower neighbours by the surface difference but keeps a thin film, so it runs downhill in rivulets, fills dips, spreads unevenly and stops by itself; a film thinner than 4.5 mm soaks into the dirt, whatever reaches the border drains (never a straight cut); a second pass `shaders/blood_halo.gdshader` darkens the soaked dirt round it (wet halo, creeps out over 20 s); the depth texture drives `shaders/blood_pool.gdshader`: opaque cut-out with MSAA alpha-to-coverage edge, mirror gloss / sky + SSR reflections, meniscus from the depth slope, bubbles in two sizes that swell, breathe and pop with a ripple (`bubbles()`: one per cell, always inside it, nothing switches in a frame); drying goes by thickness, thin first (`DRY_THIN` 50 s .. `DRY_DEEP` 240 s): clots maroon + satin, a film dries matt rust brown with a darker edge line, a thick layer near-black with a dull sheen (plain on purpose: the user found patchy noise + cracks too noisy); smears / splats dry the same way in `blood_streak.gdshader`; test `BMX_POOL_AGE=secs` starts the pool that much older); it stays until a respawn. Hit splats are projected **Decals** (`Blood._decal`; 8 textures made once by `BloodSplatTex.cs`: merged random lobes, warped outline, droplets) that only paint the ground: terrain ground meshes carry an extra render layer `Terrain.GROUND_LAYER` (bit 10) and the decals' cull mask is that layer, so they hug every bump, never clip / flicker and never paint the rider or bike; they soak in, dry darker over 45 s, fade on a respawn. All blood decals sit 3 cm up (lifted further until no corner is under `top_height`) and are pulled toward the camera more with distance (no z-fighting / clipping). `BMX_NOGRIT=1` turns off crash grit (tests). **Broken bones** (`Blood._break`, crash > `BREAK_SPEED` 9 m/s, a hand / forearm / foot / shin hit > `BREAK_HIT`; `BMX_BREAK=1` forces): `Ragdoll.break_joint` drops that elbow / knee's tension + fold limit (it flops, thrown the wrong way), a procedural crunch sound, a plain bone-coloured capsule (2.2 cm thick) poking out of the outside of the bend at an angle, mostly inside the limb, in a bloody wound; torn-off limbs show bone in both stumps. **Bloody tyre tracks**: `Blood.tyre_color` (game.gd's tracks) prints red after a tyre rolled through a pool / splat (`Blood.blood_at`), fading over ~10 m. The C# + pool shaders are warmed up when the ride loads (their first use cost ~0.14 s mid-crash). The head never comes off (the user didn't want it). Getting up
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
  **Saddles + dropper post** (garage Bars tab, SEAT; `build.seat = {model, post, post_h}`, `BikeBuild.SADDLES` / `POSTS`): the stock frame's saddle is a set of components in its frame mesh, cut by
  `make_forks.py` into `assets/seats/dh_frame.glb` (frame without saddle; extras: stock saddle origin, seat tube top + direction) + `seats/saddle_dh.glb`; `seats/saddle_<id>.glb` are the Tues / Fuzz saddles
  (from `parts/<id>_saddle.glb`, levelled). `BikeRig._swap_seat` rebuilds the frame mesh with the saddle as extra surfaces (so `_saddle()` / the rider's seat, paint by surface name and decals keep
  working), raised along the seat tube by `post_h` with a generated post tube + collar when the post is "dropper". Test: `BMX_BUILD="seat.model=fuzz;seat.post=dropper;seat.post_h=0.15"`.
  **Brake levers** (garage BRAKES tab, "Brake levers"; `build.bars.levers` stock / tues / fuzz, `BikeBuild.LEVERS`): `make_forks.py` cuts dh's levers (chrome blades + plastic bodies) out of the steer mesh
  (`forks/dh_steer_nl.glb` whole, `dh_cockpit_nl.glb` fork-less) and places the models' levers (`parts/<id>_levers.glb`, Tues Brakes parts 16..51, Fuzz `Brake_levers`) so their grips' axis matches dh's bar axis and the clamp end sits
  where dh's did (`forks/levers_<id>.glb`, written as plastic / chrome so `Handlebar.apply` moves them with width / rise); `BikeRig._swap_levers` adds them as surfaces of the steer mesh (hoses stay dh's). Test: `BMX_BUILD="bars.levers=fuzz"`.
  **Stems** (garage Bars tab, "Stem"; `build.bars.stem` stock / tues / fuzz, `BikeBuild.STEMS`): `make_forks.py` writes `forks/stem_<id>.glb` = the model's direct-mount stem
  (pieces of `parts/<id>_cockpit.glb` within 4.5 cm of the middle, not the headset spacers) on dh's steering axis, crowns' middle on dh's. Extras: `seats` (how far up the axis each
  fork's stem sits: dh / tues / fuzz), `shift` (the bar's middle moves into the new clamp), and dh's stem / bar furniture / hose as triangle middles. `BikeRig._swap_stem` drops dh's
  stem from whatever steer mesh is in use (matched within 0.4 mm), slides the stem onto the seat of the fork in use (`BikeRig.fork_model`), moves bar + grips + levers (model levers
  too) by the shift and bends the hose top along. Stock frame only. Test: `BMX_BUILD="bars.stem=fuzz;suspension.fork_model=fuzz_fork"`.
  **Model bars** (`Handlebar.MODELS` `tues_bar` / `fuzz_bar`, cards in the Bars tab; key `glb`): `forks/bar_<id>.glb` (nodes `bar` + `grips` with lock rings / end caps,
  relative to the bar's middle) from the cockpit glbs. `_swap_cockpit(stem, bar)` (one pass, stem + bar together) cuts dh's bar + grips (`barcut`), puts the model's at
  `dhMid` + the stem's shift (the tube as surface "bar": the Material pick still works, `Handlebar.apply` skips the width / rise reshape for them) and moves the levers
  (dh's or a model's) by `leverShift[side]` so they sit against the new grips. Width / rise rows are hidden for these bars. Test: `BMX_BUILD="bars.model=tues_bar;bars.stem=tues"`.
  **Disc brakes** (garage BRAKES tab, `_brakes_page`: DISC BRAKES + LEVERS): `suspension.rotor` ("stock" / "tues" / "fuzz", `BikeBuild.ROTORS`; `assets/forks/rotor_<id>.glb` from
  `tools/export_rotors.py`: disc + carrier + bolts, relative to the axle, moved onto the stock rotors' planes) replaces the mesh of the wheels' split-off "rotor"
  (`BikeRig._swap_rotors`, keeps the heat-glow material; works on every frame). `suspension.rear_caliper` ("stock" / "tues" / "fuzz", `BikeBuild.REAR_CALIPERS`): on the stock frame
  `_swap_rear_caliper` uses `forks/dh_seatstay.glb` (seatstay without its caliper, cut by `make_forks.py` as components) + `forks/caliper_<id>.glb` (the frame's rear caliper
  turned about the axle to the stock caliper's angle on the rotor). Test: `BMX_BUILD="suspension.rotor=fuzz;suspension.rear_caliper=tues"`, `BMX_GARAGE_AIM=x,y,z` aims the garage camera.
- **Helmet models** (`look.helmet`, `Rider.HELMETS`, picked in the garage Kit tab and the tuning card Look > Helmet; `Rider.use_helmet(id)`):
  GLORY = the stock recolourable helmet + our goggles; **6D ATR-2** (black / silver skin) and **TLD SE5** (`assets/helmets/helmet_*.glb`, from the user's FBXs by
  `tools/export_helmets.py` + `tools/prep_helmet_textures.py`) are textured models that always wear their own goggles + strap (our goggles don't fit them):
  the dark inside sphere (`helmet_fill`) is squashed so its front stays `FILL_GAP` behind the model goggles' lens (`Rider._fit_fill`; it showed through the lens);
  each glb has two nodes, `helmet` (shell, material `tex_shell`) and `helmet_goggles` (`tex_goggles`, the Oakley Airbrake maps: they fit both models' goggle UVs; the
  "6dgoggles" maps from the download are not used). Neither is recoloured: the Shell / Peak / Goggles colour rows are hidden for them. `Rider.HELMET_FITS` = where each sits
  (scale 1.12, a little back + low; the dark face sphere is smaller for them); test override `BMX_HELMET_FIT=x,y,scale,tilt`. Real brand logos on the textures (6D, TLD,
  FXR, Oakley): check before sharing the game.
  **The rider always wears a helmet (no bare head, user decision):** `Rider.set_look` forces helmet on; hair only shows as the tuft / tail coming out under the back
  of the helmet (`Hair.HELMET_STYLES`: none = short, long, ponytail, braid; `hair.gd` braid = the ponytail tie, stiffer). Menus: title-menu Character > HELMET tab (models, hair style,
  hair colour), garage Kit tab + tuning card Look > Helmet (same pickers + hair colour row). Old saved `helmetOn = 0` is ignored.
- **Action cams (GoPro-style, `rider/action_cam.gd`)**: one on the helmet (`look.camMount`, `ActionCam.HELMET_MOUNTS`: top / side /
  chin bar / none; picked in the rider room Kit tab, tuning card Look › Helmet, title-menu Character › HEAD) and one on the bike
  (`build.camera.mount`, `ActionCam.BIKE_MOUNTS`: none / handlebar / fork leg; garage Bars tab › ACTION CAM). `ActionCam.build("top")`
  = the buckle + hinge; `build_arm(normal, body_at)` = pad + extension arm (side, chin); `build_clamp(axis, r, out, body_at)` = a tube
  clamp + arm (bars, fork). The camera is always upright (lens +X) and always the `Body` child (the crash tear-off uses it).
  Helmet spots are measured from the shell triangles (`Rider.cam_spots`: top = crown, side = left of the shell 7.5 cm under it, chin
  = the lowest shell point well forward + 4.5 cm); bike spots from the meshes (`BikeRig._tube_at`: the bar a third of the way to the
  right grip; `_leg_band`: the right fork lower, the caliper side is left), so new frames / bars / forks need no numbers.
  **Camera models + add-ons** ("gear", `ActionCam.MODELS` / `GEAR_ROWS`, procedural shapes, no logos): camera GoPro HERO13 / GoPro MAX
  (front + back fisheyes, rear screen) / DJI Osmo Action 5 (round lens, big front screen) / Insta360 X4 (tall 360 stick) / Insta360 GO 3S
  (white pill); lens stock / Max Lens Mod (dome, POV +14 deg: the lens marker carries meta `fov`, `CameraRig._helmet` uses it) / ND / clear
  guard; housing none / frame / silicone sleeve / dive housing; mic none / Media Mod (cage + 2 cold shoes) / shotgun (foam) / furry
  windshield (shell fur, `_fur_shader`); top accessory none / Light Mod (a real SpotLight3D) / Display Mod (flip screen with the REC time).
  Helmet cam: look keys `camModel camLens camHousing camMic camAcc` (`ActionCam.GEAR_LOOK`, not touched by kits), picked in the rider room
  Kit tab › ACTION CAM and tuning card Look › Action cam; bike cam: `build.camera.{model,lens,housing,mic,acc}`, garage Bars › ACTION CAM.
  Tests: `BMX_LOOK=camModel=x4,camMic=deadcat`, `BMX_BUILD="camera.mount=bars;camera.model=osmo;camera.acc=light"`.
  Camera plastics are real scans (`bike/plastic_finish.gd` `PlasticFinish.dress(mat, kind)`, ambientCG Plastic012A / 018A / 006, CC0,
  4K in `assets/textures/plastic`, triplanar like `MetalFinish`, colour / roughness kept on average): body `textured`, mounts `mount`,
  sleeve `silicone`, bezel / trim / button `gloss`.
  Every camera is "recording": red LEDs (front corner + top) blink 0.3 s of every second with a soft halo (shader, `ActionCam._led_shader` /
  `_glow_shader`, all cameras in step); the front LCD shows a red "● REC" over the recording time in the bike computer's Doto font
  (`UITheme.lcd_font()`, `rider/cam_rec_label.gd`: game time since the camera was built, so a new camera after a crash starts at 0:00).
  Camera views: Helmet (`helmet`) and **Bike** (`bikecam`, `src: bike`) look out of the lens; C skips whichever has no camera.
  Probe: `BMX_CAMMOUNT_PROBE=1` (`CAMMOUNT` lines); tests `BMX_LOOK=camMount=side`, `BMX_BUILD="camera.mount=fork" BMX_CAM=bikecam`.
- **Skeleton** (`rider/rider_skeleton.gd`, `RiderSkeleton`, `Rider.skeleton`): a real `Skeleton3D` with **Godot's humanoid
  profile** (`SkeletonProfileHumanoid`: Root, Hips, Spine, Chest, UpperChest, Neck, Head, Left/RightShoulder / UpperArm /
  LowerArm / Hand + all fingers, UpperLeg / LowerLeg / Foot / Toes, eyes, jaw; same names, parents and rest axes, the
  node turned a quarter so the profile's +Z forward = the rider's +X). The rider is still drawn by its procedural parts;
  after every pose (`update_pose`, `pose_ragdoll`, `pose_points`) `Rider._sync_skeleton` sets the body bones from them
  (`follow`: joints + spine bones + head / glove / shoe transforms; fingers / eyes / jaw keep their rest under the hand /
  head). So `BoneAttachment3D`, retargeted animations, an imported humanoid mesh skinned to it etc. all work, riding
  and in a crash. `bone_rider(name)` = a bone in rider space. Tests: `BMX_SKEL_DRAW=1` draws the bones on top (yellow
  to the parent, rgb axes), `BMX_SKEL_PROBE=1` prints `SKEL worst_m=` (bone vs joint, must be ~0) 1x / s.
- **Getting up after a crash** (`rider/get_up_anim.gd`, `GetUpAnim`; `Game.begin_getup` when the hold-to-get-up completes):
  instead of snapping onto the bike, the rider climbs up where the ragdoll lies (~1.75 s): ragdoll pose -> hands and knees
  (0.5 s) -> one foot forward (1.05 s) -> standing (1.6 s), facing the way the body lay. Keys are body targets (pelvis,
  chest, head, hands, feet, knee / elbow poles) over the ground under each point (`top_height`, slopes ok), limbs solved
  with `Rider.limb_ik` (own lengths + joint limits). The ragdoll stops while it plays; its points are kept on the drawn
  body (camera, photo mode); the get-up prompt hides. Then `get_up()` puts them on the bike and the standing body blends
  into the riding pose over `STAND_BLEND` (0.35 s, `Game._stand_to_bike`). A torn-off limb, a respawn / Backspace, or
  `BMX_GETUP_ANIM=0` = the old instant get-up. Test: `BMX_BAIL=4 BMX_GETUP_PROBE=1` (gets up 2.5 s after the bail,
  `GETUP start / stood up` lines; + `BMX_DUST_SHOTS=dir/prefix BMX_DUST_T0=6.3` for frames). The bike stays where it fell
  (they don't walk to it yet).
  **Clip get-up + dizzy (2026-11-20, `rider/clip_get_up.gd`, `ClipGetUp`)**: with Mixamo clips in `assets/anim/getup/`
  (4 now: face down / back / side starts) the clip whose first frame lies most like the ragdoll (`_lie`: the body's
  front.y + right.y) plays where the body lies, turned to its head end, each point over `top_height`, blended from the
  ragdoll pose over 0.45 s, at 1.4x speed. Standing, it loops `assets/anim/dizzy/` until a fresh hop press (HUD: "PRESS
  [hop] TO RIDE ON") or Backspace; then onto the bike as before. **Fatal crashes (> 12 m/s, `Game.crash_fatal`) and torn-off
  limbs never get up this way** (instant back on, user decision). `GetUpAnim` is the fallback (no clips, or
  `BMX_GETUP_ANIM=proc`). Clips load on a worker at ride start (`ClipGetUp.warm`). Tests: `BMX_DIZZY_SECS=n` (released
  after n s dizzy), `BMX_GETUP_CLIP=<part of a name>`; probe prints `GETUP clip= lie= scores=`.
- **Fingers (2026-11-20, `rider/glove_fingers.gd`, `GloveFingers`)**: 5 low-poly (hexagonal, flat-shaded) gloved fingers
  per hand, one skinned mesh per hand on the skeleton's finger bones (children of `RiderSkeleton`, identity binds, vertices
  in bone space). `curl` per hand (`RiderSkeleton.curls`): 1 = wrapped round the grip (every joint on a circle of
  `GRIP_R` round the bar, thumb under it the other way), 0.4 relaxed (standing, crash, clips; `pose_points` orient
  `curl0` / `curl1` override), 0 open. The glove node (`RiderGear.build_hand`) keeps palm block, knuckle strip, cuff; the
  forearm tube now ends at the wrist (`Rider._wrist`) so it doesn't poke out between the fingers. Check:
  `..._console.exe --path godot res://tools/hand_gallery.tscn -- out.png` (curls 0 / 0.4 / 0.7 / 1 round a grip).
- **Animation clips / Mixamo** (`rider/rider_anim.gd`, `RiderAnim`, `Rider.animate(dt)`): FBX / glb clips with Mixamo bone
  names in `assets/anim/mixamo/` (README there: FBX, "Without Skin") play on the menus' standing rider (garage rider
  room KIT tab `_pose_stand_rider`, ride setup turntable `BikeTurntable._process`); none = the old procedural stand.
  Each clip plays on its own hidden skeleton; its joints are retargeted **by direction** (the clip says where each limb
  points, the rider keeps its bone lengths / torso / shoulders; hands, feet, head take the clip's turn from its T-pose;
  the lower ankle is kept as high over the floor as the clip's), then `Rider.pose_points(P, orient)` draws it. Clips
  play in turn (~7 s, whole loops, 0.45 s crossfade), one named "idle" between the others. Tests: `BMX_ANIM_DIR=res://tools/anim_test/`
  (a fake waving clip made by `-s res://tools/make_test_clip.gd`), `BMX_ANIM=<part of a name>`, `BMX_ANIM_PROBE=1` (`ANIM clips=`).
- **Race number on the back** (`rider/back_number.gd`, `BackNumber`, look `bibOn / bibNumber / bibText`): a 6 x 5 Verlet paper.
  Simulated in the back's own frame (built each frame from the four pin spots), drawn in rider space as a normal child (not
  top_level): the pins are exact and nothing trails behind at speed / in turns / crashes (2026-11-20; the old world-space sim
  pulled it towards 40 % of the rider's speed, so it lagged and snapped against its clamps). The ride's motion comes in only as
  a bounded inertial push (-0.35 x acceleration, max 40 m/s^2) + the speed flap; the back surface is read with 5 bone reads a frame.
- Look: kits + a colour per part (helmet shell/peak, goggles, jersey, pants, gloves, shoes, knee pads).
- **Belt** (`rider/belt.gd`, class `Belt`, a child of the pelvis mesh): hides where the jersey meets the trousers. The torso's bottom spine bone is locked to the hips (`Rider.set_spine(..., base)`) and the hem sits at `Belt.HEM_Y` inside the band, so leaning / tucking never makes jersey and trousers cross (they used to poke out one under the other). Styles (`look.beltStyle`, Kit › Belt in the rider room and tuning card Look › Clothes): webbing (cam buckle), leather (stitched, frame buckle, keeper, holes), ratchet (teeth, plastic buckle), elastic waistband (two stripes, label at the back); colours `look.belt` + `look.buckle` (buckle / stripe). Band textures (albedo + normal) are baked per style + colours and cached. Test: `BMX_LOOK=beltStyle=leather`, `BMX_GARAGE_HEAD=waist` frames the waist in the garage / rider room.
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
- **Night (2026-11-20)**: auto exposure is **off at night** (it lifted the night ~5x into a grey day). Moonlight 0.3, cold and
  low (15 deg, long shadows), exposure 1.9 with the sky's view `energy` 0.55 so the sky stays a moonlit blue, ambient x0.3,
  saturation x0.42 (night vision), no ambient haze inject (only lamps light the fog), dark blue-black distance fog, the smoke
  sim's sky light dimmed (`dust.sim.amb_col`). A real moon in `sky_hdri.gdshader` (`moon_disc`: maria, craters, limb
  darkening, halo; clouds pass over it) where the moon light is. `BMX_MOON_PROBE=1` prints its direction.
- **Sunrise / sunset (2026-11-20)**: `golden_sky` in `sky_hdri.gdshader` is a full twilight sky from the true sun (`sun_vec`, also
  under the horizon): blue -> indigo zenith, peach / magenta band, horizon orange-red under the sun and pink opposite (belt of Venus
  over the earth shadow), a big aureole + a flattened disc, clouds lit from below with a silver lining; night (`n`) now starts at
  -3.5..-11 deg so the afterglow shows (`tw` = twilight: lavender ambient, exposure up). A low sun lit the volumetric haze (and the
  dust) into a white veil when facing it: haze density x0.25 and dust `sun_gain` 0.2 at golden (`g`), auto exposure can't lift
  warm light. Presets: Sunrise 6.55 haze 0.85, Dusk 20.1 haze 1.1.
- **Cinematic light (2026-11-20)**: **AgX** tonemapper (`env.tonemap_mode`, `AGX_CONTRAST`, exposures `AGX_EXP_DAY/GOLD/NIGHT`;
  `BMX_ACES=1` = the old ACES for comparison). **Rim light** (`Game.rim`, a DirectionalLight3D with `light_cull_mask = RIM_LAYER`
  (layer 12); `_rim_update` tags every rider / bike mesh with that layer twice a second and aims it from behind-side of the rider
  as the camera sees it, on the sun's side; warm + strong at golden hour, cold at night; `sky_mode` light-only so LIGHT0 in the sky
  shader stays the sun / moon; `BMX_NO_RIM=1`, `BMX_RIM_E=` test). **Morning mist** (`_mist_update`: height fog, strong 5-9 h, a little at dusk / small hours; `MIST_DENSITY`,
  `BMX_MIST=k` forces it). Since 2026-11-21 it is a pool with a level fixed in the world, never tied to the rider's height
  (that made the whole fog level sink away in front of the bike on descents): the level = the 2nd lowest of 13 land heights
  round the spot ~4 s ahead (70 / 150 m rings) + `MIST_DEEP` 2 m (lakes count as their surface), scanned every 0.3 s. It only drifts
  `MIST_DRIFT` 0.3 m/s in view. **The rider is never in it** (user: "a lot of times I ride in the fog, can't see
  anything"): it is only there while the rider is above its top, full from `MIST_CLEAR_FULL` 8 m over it, gone by
  `MIST_CLEAR_NONE` 3 m (goes at once, comes back over 4 s), so it burns off as you ride down to it. A burnt-off pool, or
  one the rider has climbed `MIST_LEFT` 8 m away from, moves while nothing shows; the new one fades in over `MIST_FADE_IN` 6 s.
  The distance haze starts 20 m further out too (`fog_depth_begin` = cam.dist + 75).
  `BMX_MIST_PROBE=1` (`MIST level= want= deep= fade= thin=` lines 2x / s).
- **Rider light match (2026-11-21, user: "the rider doesn't look part of the environment light, pops out too much")**: at a
  low sun anything facing it gets ~1 / sin(elevation) (golden hour: ~6-15x) the light of the ground the exposure is set by, and
  the kit's near-pure colours burnt out to flat cream (not the rim, not bloom, not dust: checked each). `Game._match` (0..1: full
  under 8 deg of sun, gone by 35 deg, 0 at night / on the title screen; Light tab › "Rider in the scene's light (low sun)",
  `rider_match`) -> `Grime.trim` -> global `rider_trim`: the wet pass (`grime_wet.gdshader`, the last next_pass on every rider /
  bike material, now also attached while trim > 0) reads the lit pixel from the screen texture and rolls off what is above
  `TRIM_KNEE` 0.45 scene-linear (`TRIM_SOFT` 0.5); dark parts and anything in shade stay as they are. It only draws on the
  surface that is seen (depth texture compare, 1 mm): the pass is pulled towards the lens, so joint balls under the sleeves
  drew it twice = dark discs on elbows / shoulders. Tests: `BMX_NO_MATCH=1` = off, `BMX_LIGHT=rider_match=0..2`.
- **Backlit foliage + dappled shade** (`deco.gdshader` / `flower.gdshader` uniforms set per material in `world/terrain_geo.gd`):
  `scatter` = leaves / grass / bushes glow in their own colour when a low sun is behind them (shadowed glow stays dark; a quarter at
  noon), `scatter_rim` = outline only (cacti); `dapple` / `dapple_size` = holes cut in the canopy only in the sun's shadow pass (the
  only orthographic camera), fixed to the leaves before wind sway, so tree shadows have sun flecks that move with the crowns.
  Trunks, rocks, wood, sheds: 0. No extra draw calls (~0.1 ms, in the noise).
- **Goggle lenses = LUTs** (`scripts/rider/goggle_lens.gd`, preloaded, no class_name): Clear (neutral, default, no LUT), Ember, Rosé,
  Smoke, Glacier, Dusk Yellow, Moss; `GoggleLens.lut(id)` = a cached 48^3 Texture3D for `env.adjustment_color_correction` (applied
  after tonemap). Picked on the ride setup page (GOGGLES · LENS cards, live preview on the bike), `GameState.goggle_lens` (save.cfg
  `[game] lens`), `BMX_LENS=<id>` for tests; `Game._update_light` follows a change. Probe: `-s res://tools/lens_lut_probe.gd -- <dir>`.
  Lens cards show the newest helmets' own goggle model (`GoggleLens.make_goggles`: `helmet_goggles` of helmet_tld.glb, its
  magenta lens texels recoloured by `shaders/goggle_lens.gdshader`), rendered by `bike_thumbs`; `BMX_GOG_VIEW=x,y,z` turns the view.
- **RACE step preview** (`ui/lens_scene.gd`, preloaded, a SubViewportContainer with its own World3D on the left of the RACE
  step instead of the bike): a made-up vista from riding height on a ridge-top trail (ruts, roots, a puddle, white rocks, grass),
  the land dropping ~260 m into a valley with a lake, ~9000 pines, valley walls, snowy peaks 3-5 km out (`G(x, z)`). Lit by the
  slider's hour with the ride's own environment + formulas (condensed `Game._apply_light`, AgX, grade.gdshader, bloom levels,
  auto exposure, haze, a bike lamp at night, the glare guard) and graded by the picked lens. The land + tree buffers are worked out
  on a WorkerThreadPool task once per session (`LensScene.prewarm()` from `main._prebuild_behind`, `join()` on quit / exit), ~0.75 s
  off the main thread; making the nodes ~3 ms (first time ~90 ms: GPU upload / shaders). Probe: `BMX_SETUP_PROBE=1` (`LENSSCENE`).
- **Time-of-day slider** (`ui/time_slider.gd`, preloaded, RACE step): the day as a sky strip with the sun's arc (`elev()` =
  `Game.sun_elev_deg`), sunrise / sunset marks, golden-hour bands, sun / moon handle with the time + part of day; drag / click /
  wheel, pad left / right = 15 min (`nav_step`), snaps to 5 min; saves `LightSettings` "time" on release. Quick chips + a
  DAY / NIGHT CYCLE toggle under it replace the old preset cards (`TimeIcon` still draws the sky colours).
- **Glare guard** (`Game._glare_guard`, every frame): the camera facing a sun under ~30 deg eases off the sun's haze light,
  sun scatter, bloom, sky brightness and the dust's sun light (up to -80 / -100 / -65 / -38 / -60 %), smoothed over ~0.3 s, so a
  descent straight into the sunrise / sunset stays readable. `BMX_GLARE_OFF=1` compares, `BMX_GLARE_PROBE=1` prints `GLARE` lines.
- **Bike lights** (`bike/bike_light.gd`, `BikeLight`; `build.lights.model`, garage Bars tab › LIGHTS, cards with lumens):
  Glint 150 (pod) / Luma 800 (can, default incl. old saves) / Nocta 1800 (finned) / Duskbane 4000 (twin) / Sundowner 6500 (LED bar
  over the stem) + a red tail light under the saddle. `BikeRig.mount_lights` puts the lamp on the left third of the bar (`_tube_at`,
  the cam takes the right), a SpotLight3D (shadows, lights the haze) + a small spill omni; `set_lights_on` (Game, when night > 0.35)
  shows the lights + lens glow. Test: `BMX_BUILD="lights.model=sundowner"`, `BMX_BIKELIGHT_ON=1` forces them on by day.

### Boot intro + the start TV (CRT)
- The boot splash is plain black (`boot_splash/show_image=false`); a plain launch (no command-line args, or `BMX_INTRO=1`)
  plays `CrtIntro` (`scripts/ui/crt_intro.gd`, layer 60, its own 3D world in a SubViewport, ~14.3 s, any key / click / pad
  button skips): a dark room at night, moonlight through broken blinds into volumetric fog, an old CRT on a low cabinet,
  a silhouette in the half-open doorway. It **holds on black** (only the TV's red standby LED) while main builds the ride
  world (below), then: TV on at 1.8 s, slow **Vertigo dolly zoom** over the whole intro (moves in while the FOV widens
  so the frame at the TV goes 0.80 -> 0.40 m, from 4 m off the glass: the TV stays put, the room stretches away), a tear at 5.6 s (the figure is
  gone after it), the signal drops out at 8.4 s, a second tear at 10.3 s (for a moment the figure stands inside the
  room), at 12.6 s the TV **switches off the classic way** (`CrtTv.power_off(_, true)`, ~1.4 s): the picture burns white
  as it squeezes to a glowing line (`OFF_LINE`), the line hangs (`OFF_HOLD`), pulls in from both ends to a dot
  (`OFF_DOT`), the dot shrinks and fades (`OFF_GLOW`); shader uniforms `whiten` / `off_glow` / `dot_k`, the line's
  edge is anti-aliased and never under ~1.5 px (it flickered between pixels). The room dims with it, the haze stays on
  until the dot is gone, then black (`T_END` 14.3) and the menu fades in over 3.5 s. The film grain overlay is fine
  per-pixel dark specks at 3.5 % (2 x 2-pixel white specks at 6 % read as a noisy pattern over the dark room).
  Test frames: `BMX_INTRO_SHOT_FROM=12.55 BMX_INTRO_SHOT_STEP=0.03` (named with 2 decimals).
  **2026-11-22**: the room's SubViewport is hidden for its first 3 frames (sized up front, drawn while hidden): its first
  frame was uninitialised GPU memory and once flashed the TV's texture atlas full-screen. While the intro covers the screen
  (TV on .. `T_OFF` + 1.45 s) the game's own 3D (title world) is not drawn (`root.disable_3d`, `_world_3d`): ~4.7 -> ~1 ms
  GPU a frame; restored on skip / end / `_exit_tree`. Studio / mature cards: less standing snow, ghost and colour split
  (`card_color` in `crt_screen.gdshader`) so the small print reads. `INTROSHOT` lines print `gpu_ms room= game=`.
  **Settings › Gameplay › Intro at start** (`boot_intro`) off = a still frame of it (`CrtIntro.still`: the room at
  9.6 s, TV on and settled, silent, frozen after 8 frames) while the ride loads, ~2.2 s, then the menu.
  `BMX_INTRO=still` forces that; `BMX_INTRO_SHOT_FROM` / `BMX_INTRO_SHOT_STEP` = when / how often test frames are saved.
- **Ride built during the intro** (`main._prebuild_behind` / `_take_prebuilt`): while the intro holds on black, the
  player's own ride `Game` (seed, bike, garage build, rider) is built in a never-drawn SubViewport with its own World3D
  (`_ride_park`, process disabled). RIDE moves it into the scene (`reparent`) and frees the title backdrop: ~13 ms
  instead of ~1.2-1.5 s. If the seed / bike / build / rider look or pose changed in the menus since (`_ride_sig_now`),
  it's dropped and RIDE builds the normal way. Moving a Game fires `_exit_tree` on all its nodes: never tear down
  state there that a living node still needs (`ride_audio` frees its C# synths on PREDELETE for that reason).
  `BMX_NO_PREBUILD=1` = the old way.
- **`CrtTv`** (`scripts/world/crt_tv.gd`): the user's TV model (`assets/tv/tv.fbx` + `tv_albedo.jpg`, `tv_normal.png`,
  `tv_orm.png` made from the download's TGA maps: Unity MaskMap R metal / G AO / A smoothness -> ORM), ~38 cm wide, origin
  on the floor, glass +Z. `shaders/crt_screen.gdshader` draws the model's maps and, on the glass UV island (rotated in the
  UVs: UV.y = left -> right, UV.x = bottom -> top), live TV static (re-rolled every frame, drifting bands, streaks, rolling
  bar) with the RUNOUT lettering (drawn once with the display font into a texture and baked with mipmaps) wobbling,
  slipping sync, jumping and splitting colour; scanlines, shadow mask, ghost. `power_on(delay)` (white line opens up,
  snow, vertical roll settles), `power_off()` (instant), `glitch(secs, amount)`, small random blips while on. Front panel
  power LED (`LED_AT`): red standby, blinking amber warming up, green on. A small light in front of the glass glows with
  the picture (no specular: it put a hot spot on the glass). `gain` = screen brightness (5 outdoors).
- **Sound** = the user's recording `assets/audio/tv_static.mp3` (old TV static + channel changes) with its near-silent
  stretches never played: only its four loud bursts (`STATIC_CUTS`) are used, chopped into 0.3-0.6 s slices fired every
  0.07-0.16 s on 6 voices (3-5 overlap: one dense hiss that never repeats), loudness following the picture; tears /
  power on / off play a louder slice on top. World TVs are 3D sound (`positional`) and are muted while the intro plays
  (`CrtTv.mute_world`); the intro's TV plays flat.
- **Start TV** (`Game.place_start_tv`, from `respawn`): the same TV at `START_TV_SCALE` 2.5 (~0.95 m wide), 10 m ahead /
  5.5 m to the side of every start (any world), tilted to the slope, glass towards the camera, switches on 1.4 s in.
  Visual only (no collision). `BMX_NO_TV=1` leaves it out.
- The texture has a Magnavox logo and anime stickers on it: check before sharing the game.
- Tests: `BMX_INTRO_SHOTS=dir/prefix` saves a frame every 0.5 s (+ `static_voices` / `hiss` lines) and one of the menu
  after, then quits; `+ BMX_INTRO_RIDE=1` then presses RIDE (`INTRO ride start ms=`) and saves `_ride.png`;
  `BMX_INTRO_AT=secs` freezes the intro there.

### Title screen (golden hour lookout)
- `Game.set_scenic(true)` while the menu is up: a low warm sun ahead-right of the view, golden sky mode in
  `sky_hdri.gdshader` (`golden`: warm gradient + sun glow, the HDRI's clouds re-lit), warm long fog.
- Camera `vista` mode (`CameraRig.VISTA`, not in the C cycle): behind/above the rider facing `_title_heading` (the hand-picked `TITLE_SPOT`)
  (clear near eye line + hills far off), slow sway, drag turns it.
- The rider's head follows the mouse (`Game._update_look`); on a pad (`Settings.pad_active`) it looks at the focused
  menu control instead. Probe: `BMX_LOOK_PROBE=1` (`LOOK yaw= pitch= focus=` lines).
- `FarHills` (`scripts/world/far_hills.gd`): coarse ground + far trees out to 2.6 km, built on a worker
  thread; past ~450 m it adds rolling ridges (title screen only) so every seed has a hilly skyline.
  Freed and the normal light restored when the ride starts. `BMX_SEED` now also fixes the menu world.
- Menu (`main._show_menu`): two pages in one column under the title. Main: RIDE, GARAGE, world seed + NEW WORLD,
  SETTINGS (its last tabs are Controls = key / pad bindings and Camera: `settings_menu.gd` extends `controls_menu.gd`;
  no separate Controls entry on the title menu or the pause leaflet any more; SETTINGS is a gear button, `ui/gear_icon.gd`, left
  of QUIT; the version number is small bottom right beside the fullscreen button). The menu card fills the height (menu centred
  under the logo); under it a small **stats card** (`main._stats_card`): this week's distance + rides, the Zwift-style weekly
  streak (weeks in a row with a ride) and the lifetime total. Data: `GameState.days` (day number -> [metres, rides], save.cfg
  `[days]`, kept 800 days), fed by `GameState.add_distance` from the HUD; a ride counts once it passes `ACTIVITY_M` (200 m),
  only between `begin_ride` (RIDE) and `end_ride` (menu, demo); test runs never log.
  **Ride setup speed (2026-11-20)**: the page opens in ~20 ms (was ~0.6 s + seven 0.3-0.45 s frame stalls). The
  `BikeTurntable` (bike + standing rider) is built during the intro prebuild and kept across the setup steps (only the
  page round it is rebuilt), it keeps every bike it showed (`_built`), its studio HDRI is made once; bike-card
  pictures are cached on disk (`user://cache/thumbs`, key `PartThumbs.bike_key(id)` = hash of the full bike config,
  bump `THUMB_VER` when bikes look different); `BikeDecals.project` caches projected geometry by a hash of the
  surface + projector, and lettering textures are baked once per text / size / colours (`BikeDecals._baked`): every
  bike build (garage clicks, ride start) gets faster. Probes: `BMX_SETUP_PROBE=1` (`SETUP step= build_ms=`,
  `SETUPFRAME worst_ms=`), `BMX_GARAGE_PROBE=1` (`GARAGE <step> ms=`, `GARAGE open / close total ms=`).
  **Garage speed**: menu -> garage ~0.65 s (was ~2 s), back ~0.6 s (was ~1.75 s). The world out of the door builds
  only its 3 x 3 near chunks up front (`Terrain.update_stream(x, z, INF, sync_r)`), the outer ring streams in
  `Garage._process` (done ~1.6-3.6 s in, behind the closed door on the first visit, past the fog after).
  The title world's terrain + far hills (always `TITLE_SEED`) wait out of the tree while the garage is open
  (`Game.take_world()` -> `main._title_keep` -> `Game.reuse`) instead of being rebuilt (~0.9 s); SAVE & RIDE frees them.
  Garage -> SAVE & RIDE still builds the player's world (~1.3 s). **QUIT** is a button top right
  (`menu_quit`, main page only) that asks first (`_confirm_quit`: CANCEL / QUIT, B or a click beside it cancels).
  Tests: `BMX_PADSEQ` has `click:x:y` (a left click). RIDE opens the **ride setup** page (`_menu_page_setup`): bike (Downhill / BMX) +
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
- **Paint tab** (2026-11-20): a big material ball of the picked part (`PartThumbs.make_ball`: sphere + `BikeBuild.paint_material`
  + a close key light so finishes read apart), parts as a strip of pictures of each part alone (`PartThumbs.make_paint_part`: the bike with every other surface
  hidden), an 8-column grid of colour squares (picked = a dot), custom colour, finishes as a 4 x 2 grid of balls in the current colour. "Apply to whole frame" on the front / rear triangle.
- **Showroom first** (2026-11-20): the garage opens minimal: GARAGE, the bike centred and turned a little (still camera, `VIEWS.show`, longer lens `SHOW_FOV`), a strip of big frame
  pictures (pick = switch frame) and BACK / EDIT / SAVE & RIDE. EDIT (`_set_edit(true)`) shows the customizer (tabs, options card,
  build card, Stock / Randomise / Save); its BACK / Esc / pad B returns to the showroom (`_back`). The frame row left the Paint tab.
  `BMX_GARAGE_TAB=<tab>` opens straight in the customizer.
- **Picture strips everywhere** (2026-11-20): every part / look option is a big picture card in one slidable row (`ui/pic_strip.gd`
  `PicStrip`: drag, wheel, pad focus; `guard(cb)` so a drag never picks). Garage `_cards` / `_pic_cards`, title menu `_pic_chip`.
  `PartThumbs` also renders close-ups on the whole bike (`make_bike_spot`: stem, levers, rotor, caliper, bike cam mounts), saddles,
  action cams with their gear (`make_cam`), wheelsets as a product shot (`make_wheelset`) and the rider's head (`make_head`: helmet,
  helmet cam, hair; a Rider posed until the hair settles). Tests: `BMX_TUNE_CAT=wheels` opens the ride setup's Wheels & tyres.
- **Braid** = its own low-poly plait mesh (`Hair._plait_mesh`, rebuilt each frame along the tail guides' mean line, so it swings
  like the ponytail): alternating tilted lobes, a band at the tie, a flared tuft at the end.
- The **Coasting** rider preview is the showcase pose: sat on the saddle, sitting up (`relax` input to
  `Rider.update_pose`: straighter back, chest up, chin up, whatever the saved riding pose).
- Light: little volumetric haze (0.004), exposure 1.0, contrast 1.16 / saturation 1.18, depth fog from 90 m.
  **Homely sun shaft** (2026-11-20): the sun (`SUN`) is late-afternoon gold, ~30 deg up behind the door and 45 deg to the left, so a
  slanted shaft comes through the doorway and lands on the floor right of the bike (clear of the menu card; above the door top from
  the camera, no glare). An indoor-only `FogVolume` (density 0.02) makes the shaft show (sun `light_volumetric_fog_energy` 12; the
  room lights barely light the fog); `_build_sun_shaft` also adds ~7000 fine dust motes (GPUParticles3D, turbulence drift) drawn by
  `shaders/sun_motes.gdshader`, which lights only the motes whose line to the sun passes through the open part of the door
  (`_place_slats` updates it as the door rolls up). The motes vary per speck (size: mostly fine, a rare big flake; brightness; warm / pale tint), sparkle irregularly (two unrelated waves multiplied), thin out in slowly drifting clumps (world value noise) and go soft and big within `bokeh_near` (1.6 m) of the camera (out of focus); the air has wider-ranging turbulence + random lifetimes. Room lights (tubes, bench strip, key, rim, ambient) are warm white.
- **Roller door** (`scripts/garage/roller_door.gd`, `RollerDoor.build`, 2026-11-20): 10 cm insulated slats (extruded profile, domed
  face, V groove at each joint) in white powder coat (RAL 9016 look) with clear coat and light real grime (ambientCG
  SurfaceImperfections008, CC0, `assets/textures/grime`: its map baked into a soft grey multiply map `grime_dirt.jpg` + its normals;
  each slat samples its own patch, lower slats a touch dustier), closed box hood with a rounded nose + brushed
  aluminium end plates, guide channels with black brush seals, brushed aluminium bottom bar + rubber bulb seal, wall key
  switch (green LED) with conduit into the hood. Metal parts use the ambientCG Metal009 / Rubber004 scans.
  Sound: the user's recording `assets/audio/garage_door_open.mp3` (Pixabay, ~12 s motor then a stop clunk): the motor plays from
  the hood as the door starts, fades out when it is up and the clunk (`DOOR_CLUNK_AT` 12.3 s) plays (`Garage._door_sound` / `_door_stop`).
  The door rolls up in `DOOR_TIME` 8 s.
  **Showroom bike switch** (`Garage._swap_step`): parked bikes lean `PARK_LEAN` with the bars at `PARK_STEER`; the one on show
  stands up, straightens its bars and pedals off (cranks turn through `SWAP_GEAR`), the new one rolls in straight, brakes with
  a nose dip + rebound, then leans over and swings its bars (small overshoot). Bike cards: gold stars a size up; card
  pictures get soft contact shadows (`PartThumbs._ground_shadow`) and an AgX studio light; every part picture sits on an invisible tabletop (`_place_table`: a shadow catcher on render layer 20 that only the soft-shadowed key light reaches + a contact blob under its footprint) (bump `PartThumbs.THUMB_VER`).
  **Spare parts wall** (`garage/workshop_props.gd`, `WorkshopProps.build_async`, built a piece a frame after the garage
  shows, glbs loaded on a thread): hand tools on the pegboard (holes texture), chainrings, cassette, rotor, tubes, chain; our
  parts on the bench (fork, cranks, saddle, derailleur, rotor); painted framesets hung beside the door + one right of it;
  three wheels above the pegboard. **Neon sign** right of the door: the made-up shop **GNARWHAL CYCLES**, all bent tube
  (`WorkshopProps._neon`): a wheel logo, the name in blue + "cycles · est. 2026" in pink, built by `garage/neon_text.gd`
  (`NeonText.build`: a stroke font, each stroke smoothed + swept as a round tube, dark electrode caps at the ends; add
  glyphs to `_glyph` for new text), blue wall light, an occasional flicker.
  **Showcase quality** (`Garage._showcase_quality`): the garage renders at top quality whatever the preset (4x MSAA + TAA,
  full res, 16x aniso, full LOD, 8K soft-ultra shadows, ultra SSAO / SSIL, 128 GI rays); leaving restores Settings.
  **Garage speed**: the customizer page is built on EDIT, not in the showroom; saved pictures decode ~4 ms a frame (`_disk_queue`).
  **Card pictures ship with the game**: every picture a fresh install shows (ride setup, garage, rider room: stock builds,
  factory paint, default rider) is baked by `godot/tools/bake_thumbs.ps1` (runs the game 3x with `BMX_BAKE_THUMBS=<dir>` on an
  empty temp APPDATA; menu pass `main._bake_menu_thumbs`, garage / rider room `Garage._bake_thumbs`) into `assets/thumbs/<md5>.thumb`
  (PNG bytes; `.thumb` so Godot doesn't import them; the export preset includes `assets/thumbs/*.thumb`). Lookup: memory ->
  shipped -> `user://cache/thumbs` -> render (then cached there, `DISK_MAX` 3000). Keys carry `THUMB_VER`, not the game version:
  **bump `PartThumbs.THUMB_VER` and re-run the bake whenever anything pictured looks different.** `steam/upload.ps1` bakes before
  every export. `BMX_GARAGE_PROBE=1` also prints `GARAGESLOW` frames > 40 ms with the tab. `RollerDoor.extrude` = a reusable profile-along-x mesh builder. Test:
  `BMX_GARAGE_DOOR=0.45` holds the door that far open (+ `BMX_GARAGE_CAM=0,4,5.5 BMX_GARAGE_AIM=0,1.9,-4`).
- Bike height is placed from the **real tyre size and real axle positions** (no tyre clipping into the floor
  or the roller drums; verified with `BMX_TYRE_PROBE`).
- Saved in `garage.json`; `GameState.bike_config()` applies it to the ride.
- **Bike character** (2026-11-20, `BikeBuild.FRAMES` / `CLASSES` / `frame_mods` / `bike_kg`): every garage frame rides
  differently from what it is: geometry measured off its glb (`tools/frame_geo_probe.gd`: wheelbase, head angle, chainstay,
  BB drop), frame weight, suspension design (progression, anti-squat, stiffness) and a class, slow -> fast: Nexo Fizz
  FREERIDE ★★, RUNOUT DH ALL-ROUND ★★★, Yonder Tusk RACE ★★★★, Goat DH SPEED ★★★★★. `frame_mods` turns that into Tune
  multipliers (applied in `GameState.bike_config_for` after the parts' `ride_mods`); the RUNOUT DH with stock parts is the
  reference (all 1). New in the sim: the bike's weight (`bike_kg`: frame + wheels, tyres, fork, cassette, pedals; vs. a
  75 kg rider): heavier keeps speed (less drag decel), accelerates / brakes / pops slower, gets knocked about less.
  The turn itself was already real (yaw = v tan(steer) / L): a long bike turns wider when slow; at speed the radius is
  grip-limited (v^2 / a), so a long bike shows as slower to tip in (flick). Garage: POP bar, "★★★★☆ · ALL-ROUND · 17.4 KG"
  under the bars (`Garage._bike_line`). Measure: `slope_stress.tscn -- bike=<id> compare=1` prints a COMPARE line (coast
  speed on 12 deg, 0-25 km/h, braking from 50, turn radius at 20 / 40, flick time, roller pop air, washboard); the stress
  test now rides each bike's real config + geometry (the BMX fails 5 checks, already on main before this).
  **Showroom editions** (`BikeBuild.EDITIONS`, fun made-up names, each a frame + colours + parts + a riding style,
  `STYLES`: park / freeride / all-round / race / speed = wheels, travel, springs, gearing); cards: your builds first, then
  the editions, slow -> fast, with stars / class / weight. Picking one loads it as the build (saved on SAVE).
  **Factory colours**: each frame keeps its own paint (garage.json `paints`); a frame never painted gets a random plain
  colourway, the same every launch (`BikeBuild._factory_look`, fixed `FACTORY_SEED`; `FACTORY_COLORS` / `FINISHES` / `ACCENTS`, no two frames alike) and
  black or tan-wall tyres. An old file's untouched stock red counts as unpainted. Some editions ride tan walls.
  **Pedals** (`build.drive.pedals`, `BikeBuild.PEDALS`, Gears tab cards): any model's pedal pair (`BikeRig.pedal_set`, cut
  out of its crank's "plastic" surface) on any frame's own pedal spots, in this frame's pedal material.
- **Materials at photo quality** (2026-11-20): car paint (`BikeFX.CAR_PAINT_SHADER`) = round metal flakes 0.15–0.3 mm (per finish,
  `FINISHES.*.flake`), in metres whatever the model scale; LOD keeps every flake ≥ ~2 px and turns the ones that can't be resolved
  into gloss spread (no pixel mosaic, no shimmer). Bare metal (`chrome`, `black`, `chain`, `gold`, wheel `hub` / `spokes`) gets the
  ambientCG **Metal009** brushed scan (`MetalFinish`, `assets/textures/brushed_metal`, CC0) triplanar, 16 cm a tile, normalised so each
  part keeps its tuned colour / roughness; rotors get it as grinding rings. Every 3D texture import must have mipmaps (rubber / goggles
  had none); logo PNGs are 4x upscaled, text decals bake at 2048 px, carbon weave 512 px.

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
- **Dust tab** in the tuning card (Tune groups `Dust look` / `Dust trail` / `Dust spray`, keys `dust*`, read live every frame by `SmokeSim._read_tune` and `RideDust`): thickness, wispy edges, rise, swirl, curls, grit; fade speed, spread, wind, room ahead of the rider (the sim box trails behind: `ahead` 3 m = ~22 m of trail); rear / front amount, spray cone at the tyre (`dustWidth`, degrees: the spray starts tyre-wide and widens behind like a funnel), sideways, kick-up, throw, gusts, landing clouds; **Grit** (`dustGrit*`): amount, grain size (2 mm-1.2 cm at 1x, shader `grain_k`), scatter, thrown back, kicked up, speed it starts at. Dust casts no shadow (`SmokeSim.SHADOW_K` 0). Ride presets leave `dust*` alone; Reset puts them back to the defaults. Test: `BMX_PANEL=dust`, `BMX_TUNE=dustOpacity=2`.
- **Contact shadows** (`fx/contact_shadow.gd`, `Game.contact`): the sun's shadow bias (big at golden hour) lifts the
  shadow off the tyres, so the bike looked like it floated. Three soft black Decals on `Terrain.GROUND_LAYER` only: a tight
  one under each tyre + a faint wide one under the bike (the ragdoll's pelvis in a crash), lying on the ground's slope,
  fading as the tyre / bike lifts off. Kept subtle (the user found a strong one a "black splotch"). `BMX_NO_CONTACT=1` = off.
- **Baked bike AO** (`bike/bike_ao.gd` + C# `bike/AoBake.cs`, called at the end of `BikeRig.load_bike` before decals /
  cam / lights): per-vertex AO from nearby surface (discs, Bunnell-style, `RADIUS` 5 cm) in three groups (front wheel, rear
  wheel, the rest); long edges are split to 2 cm first (`AoBake.Subdivide`, frame group only) or a low-poly tube smeared a
  joint's darkness half way along. Stored in the vertex colour: BaseMaterial3D surfaces get a copy with
  `vertex_color_use_as_albedo` (wheels already use vertex colour: multiplied in), the car paint + rotor shaders read `COLOR`
  (+ `AO`). Cached by mesh content (memory + `user://cache/ao`, bump `VER`): first bake of a bike ~0.6 s, then ~60-200 ms.
  `BMX_NO_AO=1` off, `BMX_AO_PROBE=1` timings + histogram, `BMX_AO_SHOW=1` draws the AO alone. The rider is not baked
  (procedural, posed every frame): it gets SSAO only.
- **Pants fabric + patterns** (`rider/pants_look.gd` `PantsLook`, `shaders/pants_fabric.gdshader`): pelvis / thighs /
  shins / knees use one ShaderMaterial: a Poly Haven fabric scan (CC0, `assets/textures/<id>/`: the colour map turned into a
  grey weave normalised to mean 0.88 (`*_grey_2k.jpg`, made with PIL from `*_diff_2k.jpg`), normal, roughness, AO) at
  about its real size, wrapped round each tube (whole tiles round = no seam) and dyed the pants colour; then a procedural
  print in a second colour (3D noise in the mesh's metric object space: camo, digital camo, tiger, zebra, leopard, checker,
  tie-dye, flames, lightning). Look keys `pantsFabric` / `pantsPattern` / `pantsPrint` (kept when a kit is picked:
  `RiderPanels.NON_KIT`). Picked in the ride setup CHARACTER step's PANTS tab, the rider room Kit tab and the tuning
  card Look > Kit. Test: `BMX_LOOK=pantsFabric=corduroy,pantsPattern=tiger,pantsPrint=#111215`, `BMX_CHAR_TAB=pants`.
- Dirt chunks, **tyre tracks**: one ring-buffer ArrayMesh
  (14 000 segments ≈ 1 km/wheel, one draw call, each segment uploads only its own bytes) drawn by
  `tyre_track.gdshader` — lit, knob-tread dimples bump-mapped, soft edges + soil lip, skid streaks, distance fade.
- Grime: mud builds up (slow: `Grime.MUD_RATE` 0.25) and washes off in water; wet gloss + drips. **Dust first** (2026-11-20): riding dirt / sand
  lays a see-through film of the ground's colour (`Grime.dust`, global `grime_dust`, ~30 s to full, thickest low down, drawn by the
  same `grime_mud` pass, now a transparent pass); mud only piles up once the bike is dusty (`smoothstep(0.4, 0.95, dust)`) or
  wet. **Colours = the ground ridden on** (2026-11-21, user: bike looked pale / bright, "make dirt and dust the same colour as
  the ground"): the dust film is the ground colour itself, mud the same colour x 0.68 (sand 0.8); both keep following the
  ground while riding it (`Grime.GROUND_FOLLOW` 6 s, mud 2.5x). `grime_dust` is a plain vec4 global, so it must be sent
  linear (`srgb_to_linear`): sRGB numbers read as linear were the chalky white film. Mud is raised (screen-space bump from a lumpy height field in the pass: no UVs
  needed); thick middles dark, edges drying lighter. **Dirt map** (where it gathers, `grime_mud.gdshader`): low down;
  the spray band round each tyre (globals `grime_wf` / `grime_wr` = axle + radius in bike-root space; fork arch / lowers,
  down tube, stays, shins); crevices from a baked 3D map of the bike (`Grime._cav_work` on a worker, ~250 ms, 2.5 cm
  occupancy grid box-blurred, sampled 7 cm off the surface so only *other* geometry nearby counts; spokes left out);
  undersides + forward faces (mud), top faces (dust). Every bike part is pinned like the rider's (`_pin_rows`: its rest
  transform as `grime_r0` / `grime_hrow` / `grime_r2`), so nothing slides with steering / suspension / a spinning rim.
  `BMX_GRIME_MAP=1` shows the map (r spray, g crevice, b under / front), `BMX_GRIME_PROBE=1` prints the bake.
  Wheel parts (rim / hub / spokes / rotor, `wheel` flag) skip the map: mud in clumps by angle, heavier toward the bead;
  tyre sidewalls get the same clumps, the tread fills first. **Stickers get dirty too**: each decal material gets its
  own mud + blood pass (`Grime._decal_mud`, masked by the sticker's alpha, render priority 2 / 3 after the decal's 1;
  wet 4); blood is now drawn see-through for that. Tyre lettering: `logos.tyres.lift` (0 at the rim .. 1 at the knobs,
  default 0.1), scale, turn and colour are now used (garage Logos > Tyre walls > Placement: "Height on sidewall").
  **Drying + flaking**: `Grime.dry` (0 fresh .. 1 crust, `DRY_T` 90 s without fresh mud, not while wet; fresh mud
  and water make it wet again) and `Grime.flake` (crust knocked off: landings, wheel rattle from `vw_f` / `vw_r`, speed;
  fresh mud fills it back) go to the shader as global `grime_age`. Per splotch: thin edges and random plates dry first,
  dried = pale / matte, thick crust cracks into ~2 cm Voronoi plates (`gr_cells`), flaked plates vanish along the cracks
  leaving a stain. Knocked-off crust flies as `fx.chunk`s (`Grime.take_shed`, spawned in `Game.ride_fx`).
  Tests: `BMX_MUD_COAT` (start, not held), `BMX_MUD_DRY`, `BMX_MUD_FLAKE`; `BMX_GRIME_PROBE=1` prints `GRIME t=` lines.
  Test: `BMX_DUST_COAT=0.8` (+ `BMX_MUD`, `BMX_BLOOD_COAT`). Mud / blood on rider limbs stay put: `Rider.set_limb` takes the
  limb's twist from the sideways axis (the shortest turn from +Y spun shins / forearms round as they pointed down, so the
  pattern slid round the leg); glove fingers carry their bone-space shape in CUSTOM0 (`grime_pin` 2). Passes
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
  `BMX_TAPE_SPEED`, `BMX_TAPE_STOP=secs`, `BMX_TAPE_OFF=m` (aim along the span) (`TAPE` lines: state, strain).
  The hit is a **swept test** (`bike_physics.gd`: the front tyre's leading edge this step vs each span's line), so no speed
  slips through; skipped only when the wheels are above the tape. While held, the span is **posed exactly** each frame
  (`TapeSim._pose_held`: straight once taut, parabola sag while slack) on the drawn front tyre (`Game` passes
  `rig.wheel_f`), not simulated, so it never trails the bike. Strips draw as one ArrayMesh from packed arrays (no
  per-vertex calls), ground heights are cached per point, the strip shader is warmed at ride start.
- **Tape stakes take damage** (`Terrain.stake_yank`, event-driven, no per-frame cost while nothing is loose): a snap yanks
  both stakes toward the pull with severity ~ speed / 11 m/s x how hard it was stretched (random 0.55-1.45): < 0.2 nothing,
  then it **leans** (accumulates up to 43 deg, a leaning stake gives way sooner), past 0.8 it **snaps at the ground** (stub
  left, `stake_stub`), past ~1.25 (or 25 % of the time) it **pulls out whole** (earth on its foot). Riding straight into a
  stake (tape hit within `STAKE_HIT` 0.3 m of it) hits the stake itself (severity speed / 6). Flying pieces are
  `TerrainDebris.fling` bodies; tape tied to them follows (`TapeSim` `pb` / `pb2` ends, `_follow`), the intact span on the
  stake's other side drops / hangs from it (`TapeSim.hang`), and a tape tied at both ends that runs out of length catches the
  stake (impulse) or the knot slips off at 135 %. Respawn (`clear_dynamic`) stands them back up. `BMX_TAPE` prints `STAKE` lines.
- Torn race tape as cloth-like ribbons, wind over the grass, drifting cloud shadows, speed blur / FOV.

### Test playground (LEVELS > TEST PLAYGROUND, `scripts/levels/`) - for testing the riding code, not part of the game
- A flat plane (y = 0, grass) with straight test lanes along +x, each a row of measured features with flat run-ins between,
  every lane starting with the same roll-in (4 m deck, 14 deg down, ~30 km/h at the bottom): **TABLES** 0.6..3 m, **GAPS**
  3..12 m, **HOPS & ROLLERS** (hops 0.25..0.8 m, rollers 0.3 / 0.6 / 1 m, a pump section), **DROPS & STEP-UPS** (drops
  0.5..3 m to flat, step-ups 1 / 1.6 m), **BUMPS & EDGES** (curbs 10..45 cm, potholes, washboard, rough ground), **SLOPES**
  5..40 deg up and down, **CAMBER** 5..35 deg side slopes; north of them four **berm bowls** (banked rings 20 / 30 / 45 / 60
  deg, ride in through the gap on the west side); open flat everywhere else (turns, brakes, sprints). Lanes are 18-24 m apart.
- `PlaygroundCourse` (pure data): each lane is a 1D profile sampled every 5 cm, laid out by a turtle (`flat`, `line`,
  `bend(deg, R)` = a circular transition, `line_to`, `descend`, `wall_to`); feature builders `table`, `gap`, `hop`, `drop`,
  `step_up`, `rollers`, `curb`, `pothole`, `washboard`, `chatter`, `slope`, `tilt`. Built dirt has 1:1 side batters. Feature ids
  = `<kind>_<size>` (`table_1.5`, `gap_7`, `drop_2`, `roller_0.6`, `slope_20`, `berm_45`...): printed on the sign at each feature.
  Add a feature = one call in `_build()`.
- `PlaygroundTerrain extends Terrain`: answers the ride's whole terrain API (height / deck / top / mesh height = the exact
  profile, surface: dirt on built ground, jump_mask on jump / pump features, biome = "Playground · <lane>" so the area banner
  names the lane) and keeps an EMPTY `TrailCourse` in its field, so trail alerts / the trail camera / the demo pilot find no
  trail. Ground drawn once (~1.5 s): lane strips at 0.1 m where the profile isn't flat, bowls at 0.4 m, the rest a 4 m-cell
  plane out to 2.4 km; `shaders/playground_ground.gdshader` draws a measuring grid (1 m / bold 5 m lines) and height contours
  every 0.25 m (bold 1 m) on built ground. Signs: name, numbers and id per feature, a short post at each lip, 50 m marks.
  No far hills, sheep, start TV, trees, water. New world (R / pause) does nothing there; the bail tap = "Again": back 25 m
  before the feature you're at; Backspace = the start.
- `PlaygroundProbe` (Game.level_probe): measures every jump (> 0.12 s air): speed into the feature and off the lip, take-off
  angle, air time, distance, peak over the lip / over the ground, where it landed (flat / deck / landing / knuckle / upslope),
  bike pitch against the ground at touch-down, jolt, and the end (CLEAN / PERFECT / CRASH <reason>). On screen top left
  (LAST JUMP) + `PG JUMP` lines. Hooks: `pre_step` / `post_step` around `phys.step` in `Game._physics_process`, `on_crash`
  from `Game.start_crash`.
- Wiring: `GameState.level` ("" / "playground", not saved; reset on the title's main page), `Game.level`, main `_new_game`
  passes it; `--level=playground`, `BMX_LEVEL=playground`. A level never uses the intro's pre-built ride.
- **Test runs** (with `BMX_LEVEL=playground BMX_STRAIGHT=1 --autotest=N`): `BMX_PG_AT=<feature or lane id>` starts 25 m before
  it (`BMX_PG_BACK=m`); `BMX_PG_SPEED=<km/h>` = cruise control: holds that speed on every run-in and goes hands off 1 m before
  each feature (also in the air: the autotest's held pedal is W = nose down there); `BMX_PG_SPEEDS=18,24,30 BMX_PG_AT=gap_7
  [BMX_PG_TRIES=n]` rides that one feature once per speed, prints `PGSUM try= kmh= lip= result= dist= air= land=` and quits
  by itself (give `--autotest` plenty of seconds); `BMX_PG_TRACE=1` prints every physics step on jump features / in the air
  (`PGTRACE u y gy v vy pitch gp air cf cr ...`). `-s res://tools/playground_probe.gd --headless` lists every feature and checks
  no built feature digs below the plane (must say `PASS`).
- Light: clear midday (the Noon preset, haze 0.3) whatever the player's light setting, until the light is changed in the
  ride (`Game._level_light_ver`); golden-hour haze made reference shots unreadable. `BMX_LIGHT*` env overrides still work.
- **Use it first for any riding / jump physics change**: sweep the features it touches (`BMX_PG_SPEEDS`) before and after.
- **Found with it on day one (2026-11-21), not fixed yet**: (1) off a kicker the rear tyre keeps contact ~0.2 m past the lip
  down the 50 deg backside, and the take-off reads the backside's slope: gap_7 at 36 km/h left at 7.7 m/s @ 42 deg from a
  9.2 m/s @ 32 deg run up the lip (trace with `BMX_PG_TRACE`); (2) fast into a big kicker the bike leaves early off the
  transition (gap_9 at 40 km/h: 4.9 deg, no air off the lip, into the gap); (3) speed at the lip is often not lower than the
  run-in after climbing the kicker (table_1.5 at 42 km/h: lip 42, drop_1.5 run-up: lip = cruise speed): the pop / pump adds it.
- **Found by the lab / suite (2026-11-22), not fixed yet** (the baseline `tools/pg_baseline.json` holds them as they are):
  (4) the take-off depends on state left from earlier riding (smoothed grip / tyre loads / crash meters...): the same
  run at the same speed left gap_5 at 41.5 deg from a clean state but at 84 deg (16 km/h, landed 0.5 m out) after other
  features; stepdown_1.8 at 37-39 km/h left at 90 deg twice in lane mode (one LOOPED OUT), hop_0.8 at 30 km/h at 65 deg.
  The suite now starts every run clean (`PlaygroundLab.fresh`), so it won't show this: ride a lane in lane mode to see it;
  (5) drop_2 at 28 km/h
  = NOSE DIVE; (6) landings stop all the downward speed in one physics step: 60-86 g "in one step" on flat landings
  from ~1.5 m up, tyres squashed 5-7 cm (rim strike); (7) the pump at a lip adds ~21 J/kg (as much as climbing 2 m),
  without it the take-off loses energy as it should; (8) brakes: 0.8-0.85 g on dirt / grass / sand alike (29 km/h: 4.1 m),
  a real bike on loose dirt is nearer 0.6-0.7 g, and the surfaces barely differ; the wet strip (the game's water surface)
  stops at ~0.97 g, harder than dirt (its drag adds to the brakes).

### Developer view of the test playground (`scripts/levels/ride_diag.gd`) - telemetry + sliders for riding code
- **Only in the test playground** (user decision 2026-11-21: developer tools live in that level, normal rides have none).
  **Layout (2026-11-22, user: "tidy, compact, nothing covering")**: a slim **tuning column** on the left (the TuneCard,
  every slider, scaled `DEV_CARD_SCALE` 0.84 with the graphs' flat dark panel: `hud.card_left` -> `hud._dock_card`), the
  **graphs in a band along the bottom** (`RideDiag.BAND` 46 % of the height; a page's rows split over two columns when
  the band is wide: `DiagView.rows` on the page body), one compact header over it (DEV, page tabs, keys, CAM pick; the
  RIDER and LAB rows side by side, small flat buttons from `RideDiag._dev_theme`), the ride above the band
  (`ride_rect`; `_frame_bike` slides the camera with `h_offset` / `v_offset` so the bike sits in its middle, never moving
  the camera under the ground). The game HUD's big pieces are hidden there (`hud.dev_mode`: computer, jump card,
  life / stamina, STYLE, corner lines, achievement pops, quick tune; plus the area banner, the WASTED slow motion
  (`Game._wasted_on`) and the fullscreen button; F11 still works); the hop / pump / balance bars and the get-up prompt
  move up over the band (`hud.dev_bars`). The playground readout is a small block at the ride's top left. ✕ / P closes /
  opens the tuning column, F4 cycles band -> full screen (graphs beside the column) -> off. `BMX_DEV_CARD=0` starts
  without the column. Try a slider, ride the feature again, read the graphs: that's the loop.
- **Test rider** (`levels/playground_pilot.gd`, `PlaygroundPilot extends DemoPilot`; F2 there, or the RIDER bar under the
  graph tabs / along the bottom right with the graphs off): pick a feature or a whole lane in the dropdown and he rides it on
  repeat until STOP: holds the lane centre, pedals / brakes to the set speed (- / + km/h) on the run-in, hands off from 1.5 m
  before the feature (no fresh press near a lip = no accidental flip), pumps the lips if "pump" is ticked, then (feature mode)
  is put back 30 m before the feature already at speed, or (lane mode) back to the lane start; after a crash 2 s, then again.
  Every run is the same ride, so a slider change is the only difference: tune between his runs, read the graphs.
  `Game.set_demo` makes a PlaygroundPilot on the playground (`diag.pilot_changed` keeps the bar in step). Tests:
  `BMX_PG_PILOT=feature|lane BMX_PG_AT=<feature / lane id> [BMX_PG_PILOT_KMH=30] [BMX_PG_PILOT_PUMP=0] [BMX_PG_PILOT_AUTO=0]` + `--autotest=N`
  (a `PG JUMP` line per run; the probe's run-in speed resets whenever the bike is put back).
- **AUTO speed** (bar checkbox, default on; `BMX_PG_PILOT_AUTO=0` off): tables / gaps / step-ups carry their landing
  (`land0` .. `land1` in the feature dict, set by the builders) and `lip_deg`; the rider aims for 35 % down the landing.
  First run: estimated from the shape (`PlaygroundPilot.estimate`: projectile from the lip at its angle + the climb).
  After every jump `_learn` moves that jump's speed (`auto_v`) by where it landed (`u_land` from the probe): proportional
  at first, then bracketing (secant between a short and a long run). `PG AUTO` lines. gap_7 lands on the spot from the
  first run (39.6 km/h); table_2.5 settles within 0.5 m after ~7 runs (38 km/h). The bar shows the speed in use.
  Seen while building it (2026-11-21): on table_2.5, 39 km/h landed further than 41.9 km/h (the early take-off at speed,
  open item (2) of the playground findings), and landings come in nose-up 30-50 deg against the landing slope yet CLEAN.
- **Cameras**: the playground starts in `pg_side` (`CameraRig.LEVEL_PRESETS`: Side, Side wide, Side low, Front 3/4; all
  locked square to the lanes, not following the heading; only in levels, never saved to Settings), the normal views after
  them. Dropdown CAM in the dev view header (C still cycles). `RideDiag._frame_bike` slides the camera (`h_offset`) so the
  bike sits in the middle of the free space between the sliders and the graphs.
- **Debug Draw 3D overlay** (F3, `game/debug_overlay.gd`) is on from the start here, text block off (the graphs have it),
  plus playground extras: the drawn bike's axes (RGB), the rider's body mass ball, the path really flown (yellow, vs the
  magenta prediction), the lip of the jump ahead (orange post), its landing (green line) and sweet spot (green ball).
- The probe no longer lets a bounce off a landing replace the jump that's still settling (it used to log the 0.2 s
  bounce instead of the real jump, or nothing), and skips airs < 0.3 s within 1.2 s of a landing.
- **Lab** (`levels/playground_lab.gd`, `PlaygroundLab`, made by RideDiag; the LAB row under the RIDER bar, keys work with
  the graphs off too):
  - **Energy check**: E = ½ speed² (+ the climb speed in the air) + g height per kg, from the last reset (ENERGY page:
    E, ½v², the inputs that add energy, COASTING / AIR flags). With nothing putting energy in (pedal, sprint, hop / pump,
    body stick; each counts for 0.35 s after it's let go, the pump's push comes at the release) a rise over 0.5 J/kg
    within 0.25 s is a check (`energy_gain`, with "take-off" / "air" / "ground").
  - **Physics checks** (things a real bike can't do; counted, an event line on every graph, the list on the ENERGY page,
    `PG CHECK <kind> ... | <feature> u= v= air=` lines, `PG CHECKS` summary with `BMX_LAB_PROBE=1`): `energy_gain`,
    `rim_strike` (tyre squashed past 5 cm), `accel` (> 50 g in one step), `sunk` (under the ground by more than the
    travel + 0.15 m), `jump_step` (height jumped > 0.3 m in a step), `non_finite`.
  - **Time**: G pause / run the physics (the drawn bike holds: `Game` calls `lab.hold_physics()` first and snaps the
    interpolation), N one physics step (1/120 s, pauses if running), T slow motion 1 / ½ / ¼ / ⅒ (`Engine.time_scale`,
    only while nobody else owns it: crash slow-mo, photo mode). `BMX_PG_SLOW=0.25` for tests.
  - **Record / replay**: V records the next run (resets to 25 m before the feature you're at, or the test rider's next
    run) until the next reset / V / 60 s: the inputs the physics got each step (`IN_KEYS`), the path, every graph
    channel, the Tune values; saved to `user://playground/last_run.dat` (survives a restart: record, change the code,
    restart, replay). J replays it from the same start (+ grip noise reseeded, stamina full) with the same inputs
    (`Game._read_input` takes `lab.replay_input()` first); a white wireframe ghost bike (Debug Draw) rides the recorded
    path and every graph draws the recording faint under the live lines. `PG REPLAY feat= steps= end_moved= tune_changed:`.
    Replays are exact: the same code replays to 0.000 m. Tests: `BMX_PG_REC=1` (records the test rider's first run, with
    `BMX_PG_PILOT`), `BMX_PG_REPLAY=1`.
- **Overlay extras** (F3, `DebugOverlay._tyres`): a white arrow at each tyre = the ground's push (1 m = the whole weight)
  and a ring per tyre lying on the ground with a dot = its grip in use (along: brake / drive, across: turn / slide),
  green inside, red past it.
- **More features** (2026-11-22): lane **STEP-DOWNS, DROPS & HIPS** (z -48: `step_down`, `drop_land` onto a 30-34 deg
  landing, `hip` = a table turned 20 / 35 deg to the lane: `Lane.skews` slides its shape along u with v (`skew_u`), so
  ridden straight you take off and land across its faces) and **BRAKES, SURFACES & SLALOM** (z -72: `brake_strip` on
  dirt (both / front only / rear only), grass, wet, sand (`Lane.surfs` -> `course.surface_at` -> `Terrain.surface`, ground
  colour `SURF_COL`); a post at the brake line (`f.lip`); `slalom` cones 8 / 6 m apart). The test rider brakes at the
  line with the lever the strip tests until stopped, and weaves the slalom (aims `SLALOM_OFF` beside each cone,
  alternate sides). The probe prints `PG BRAKE feat= v= dist= time= decel= lock_f= lock_r= slip=` and `PG SLALOM
  feat= time= v_in= v_min= v_out= ok= miss= lean=`. Main added a ROCKS lane (z -24, the game's own rock colliders).
- **Repeatable runs**: before the test rider's every restart, a recording and a replay, `PlaygroundLab.fresh(phys)` copies
  every plain value of a brand-new `BikePhysics` into the ride's (not the build / gearing / Tune: `KEEP`), the gear back to
  the start gear, the grip randomness reseeded. Without it the same run came out different after other riding. Same
  feature, same speed, from clean: identical to the centimetre (the first run after the level loads differs a little).
- **Mouse wheel** (2026-11-22, the user moved sliders by accident while trying to scroll): no slider in the game takes the
  wheel any more (`scrollable = false`: tune card / TuneSlider, quick tune, settings, garage); over the tuning card the
  wheel scrolls its list (`TuneCard._input` -> `SmoothScroll.wheel`) and never reaches the camera zoom; over the graph
  band / bars it's eaten too. Autotest / bench runs never save `tune.cfg` (`Tune.save`), like PADSEQ runs.
  Test: `BMX_CARD_WHEEL=n` (n notches into the card's list, `CARDWHEEL scroll=` 1 s later; a minimised window has no
  mouse position, so `mw:` steps can't test it).
- **Baseline suite** (`levels/playground_suite.gd`): `BMX_PG_SUITE=save` rides 24 fixed runs (tables, gaps, hops, drops,
  step-up, rollers, pump, curb, slope, camber, step-down, drop to landing, hip, five brake strips, slalom; the test
  rider at fixed speeds, pump and AUTO off) and writes every result to `godot/tools/pg_baseline.json` (keep it in git);
  `BMX_PG_SUITE=compare` rides them again and prints every number that moved past its tolerance (`PGBASE <run> metric
  old -> new`, ⚠ on a result that got worse, more bottom-outs or more checks) and `PGBASE SUMMARY runs= changed= worse=`.
  **Run it before and after every riding-physics change** (~3 min, minimised):
  `BMX_MIN=1 BMX_LEVEL=playground BMX_STRAIGHT=1 BMX_PG_SUITE=compare` + `--autotest=400`; save a new baseline only
  when the change is wanted. `BMX_PG_SUITE_ONLY=<part of an id>`.
- `RideDiag` (CanvasLayer, made by `Game._ready` only for a `PlaygroundTerrain`): records **every physics step**
  (`Game._physics_process` -> `diag.record(dt, inp)` after `phys.step`; `inp` = what the physics got, after cruise control /
  test injection) into a 20 s ring (one flat `PackedFloat32Array`, `buf[sample * C + channel]`, channels in `RideDiag.CH`).
  Records all the time from the start (stats + histograms cover the whole ride).
- Physics exposes its suspension for it: `BikePhysics.dg_*` (last substep of the step): `dg_xF / dg_xR` shock compression
  from topped out (m; / `dg_travel` = travel %), `dg_vF / dg_vR` shock speed (+ = compressing), `dg_fF / dg_fR` spring +
  damper force, `dg_tyF / dg_tyR` tyre force, `dg_sqF / dg_sqR` tyre squash, `dg_botF / R` bottomed out this step,
  `dg_blowF / R` damper past its blow-off knee (`dg_knee` = `damperKnee`), `dg_sag` (static sag), `dg_leg` / `dg_leg_f` the
  rider's legs (body - bike, their push), `dg_cF / dg_cR` contact. Forces are per unit mass: / 9.81 = share of the whole weight.
  The physics has ONE travel for both ends (`T.travel`, x the bike); the drawn linkage (`Suspension`: fork lowers, four-bar,
  `last_stroke`) is shown beside it (grey lines, "drawn" %, shock stroke mm), it follows the ground (`wheels_follow`).
- Pages: **OVERVIEW** (speed, state, both ends, tyre loads, steer, lean, both sticks), **SUSPENSION** (fork / shock gauges:
  fill = travel now, dash = sag, yellow O-ring = deepest since reset, bottom-outs, blow-offs; legs gauge; graphs travel %,
  shock speed with the knee, force, tyre squash, legs; in full screen also travel-use + shock-speed histograms, like real
  suspension telemetry), **INPUT** (left / right stick from the first connected pad raw (white dot + 1 s trail) vs what the
  game used (coloured; deadzone ring, the axis-fade bands of `Game._read_input`), LT / RT raw vs used, the steer curve with
  the current point, every riding action lit, graphs of steer / body stick / pedal + brakes / raw triggers; no pad = the keys
  as a stick), **TYRES** (loads + contact, rear grip / front use vs the limit, slide, turn force, brakes + locks, the crash
  judge's trouble meters `_risk`), **BODY** (lean asked / bike / counter, bars, pitch vs ground, body fore / aft, legs, manual
  angle vs `manBalance`), **AIR** (side view of the last jump: the ground along the take-off line, the bike drawn every
  0.1 s; height, vy, pitch vs slope, spin, stick). Event lines on every graph: take-off, landing, bottom-out, crash.
- Keys: **F4** band -> full screen -> off; F5 / Shift+F5 page (or click a tab); F6 freeze; F7 window 3 / 6 / 12 / 20 s; F9 reset the stats.
  Mouse over any graph = every graph reads that moment (line + legends). Draw ~2 ms a frame while shown, nothing hidden.
- Tests: `BMX_DIAG=<page name / prefix / number>` opens it (`BMX_DIAG_FULL=1` full screen) + `BMX_SHOT`;
  `BMX_DIAG_PROBE=1` prints at the end `DIAG SUSP` (max / avg travel, bottom-outs, blow-offs, shock speed range per end,
  sag, travel), `DIAG LEGS`, `DIAG HIST F/R` (% of ground time per 5 % travel band), `DIAG PAD`, `DIAG DRAW` (ms).
- Seen with it on day one: on the trail at ~70 km/h both ends chatter fast (several strokes a second) through the whole travel band with blow-offs
  every few strokes (25 / 17 in 16 s), and a 1.5 m table landed flat uses 115-125 % (bottom-out); not looked into yet.

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
  `sound_stream` (a recording played in random faded slices; the map: `assets/audio/paper_unfold.mp3`). Paper = ambientCG **Paper003** (CC0) scan in
  `assets/textures/paper/` × the print, creases worn (`shaders/paper_sheet.gdshader`). Sound: only the user's recording (`sound_stream`; the map and the pause leaflet use `paper_unfold.mp3`, the user's crumpling paper recording), no stream = silent - never synthesised paper sounds.
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
- **One cursor, console style** (2026-11-20): the focused control is the only highlight (`UITheme.FOCUS_WASH` yellow wash + ink bar on every button kind; title-menu / ride-setup lines are kind `menu`: grey, solid yellow when focused). Inside a PadNav menu hovering a button with the mouse moves the focus there and the button's own hover look is turned off (no second highlight). D-pad / stick onto an option of a ButtonGroup (bike, kit, time of day, garage part...) **picks it at once** (`_follow_pick`, only for real direction moves); meta `nav_accept` = what A does on it (ride setup: next step). Ride setup: the cursor starts on the picked card, A = next, B = previous step (step 1 -> main page), LB / RB = steps. A with nothing focused lands the cursor. Tooltips no longer count as open popups (they froze PadNav / the leaflet's B). B cancels a key rebind. Pausing closes a side card (it stole the cursor from the leaflet); pause > Tuning never toggles it shut.
- **On-screen keyboard** (`ui/pad_keyboard.gd`, `PadKeyboard.open(line_edit)`): A on a text box with the pad (seed, race plate, bike / preset names) opens it in the field's own viewport: A types, X deletes, Y space, Menu / DONE = accept (fires `text_submitted`), B = cancel (old text back); group `nav_modal` so a paper sheet keeps B. Garage colour pickers (`_color`) are pad steppers through `SWATCHES` (shift colour, outline, spokes, nipples, hubs). Pad B with a side card up while riding closes it (not a bail tap). `Game.swallow_held()`: A / X / Space still held from resume / RACE don't sprint / hop until let go.
- Focus marker: a container with meta `nav_row` (MenuBase / garage / tune card / photo rows) gets a wash + a bar
  on its left when its control has focus (`style` "paper" highlighter + red, "card" yellow tokens, "dark" in-ride).
- **Smooth scrolling** (`ui/smooth_scroll.gd`, `SmoothScroll.attach(sc)`, also done by `PadNav` for every list it manages): the wheel / touchpad move a target and the list glides to it (eased, real time, notches pile up), follow-focus jumps glide too, dragging the bar stays 1:1. Test: `BMX_SCROLL_PROBE=1` + `BMX_PADSEQ="w6000,mw:200:500:3"` (`SCROLL` lines).
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
- Piezo sounds (`ui/garmin_beep.gd`, `TONES`, rendered once into AudioStreamWAVs, `beep.tone(name)`; Settings of the unit can mute them):
  power-on chime 0.35 s after the HUD shows, key beep on the ◀ ▶ buttons, **gps** (satellites found, at `FIX_T`), **pause / resume**
  (auto-pause after `AUTO_PAUSE` 2 s standing still: falling / rising two-note), **lap** (three even beeps every `LAP_M` 1 km),
  **turn** (nav prompt, once per bend as it comes within 100 m) / **feature** (double beep: jump, rocks), **battery** (90 % of
  `BAT_LIFE`), **record** (a new best air time today, fanfare), **gear_end** (shifted into the easiest / hardest cog: high double blip), **gear_none** (a shift with no gear left that way, or a single speed: low buzz; `Game._shift` -> `hud.gear_changed(at_end)` / `gear_blocked`), **incident** (knocked out: alarm after the slow motion).
  All driven from `hud._computer_tones` / `_trail_scan`. Test: `BMX_BEEP_PROBE=1` prints `BEEP <name>`.
- **Gear shift sound** (`game/shift_sound.gd`, `ShiftSound`): the user's own shifter recording, cut into six shifts
  (`assets/audio/shifter/shift_0..5.ogg`, lever in + spring back), one at random per shift (not the same twice in a row).
  Three synthesised versions were rejected ("an empty bottle", "clipped on high pitch"): use the recording.
  Test: `BMX_SHIFT=secs` (shifts every 0.7 s, `SHIFT` lines; `BMX_SHIFT_RUN=12` = 12 each way, runs into both ends; add `BMX_REC=file.wav`).
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
  Head, Arms, Legs, Motion, Physics) Look (Kits, Helmet, Clothes) and **Sound › Freewheel** (every `FreewheelSynth` knob: volume, engagement, pitch, ring, brightness, snap, detune, pawl unevenness, wobble…; built-in hub presets + the player's own named presets with Save as / Delete, saved in `user://freewheel.cfg` by `scripts/core/freewheel_sound.gd`; Preview spins the wheel while standing; since 2026-11-21 also the wheel's turn + speed: `warble` = loudness / brightness swell once per wheel turn (default only 0.04: at 0.25 the user heard a wobbly wheel), `repeat` = share of the timing / strength pattern that comes back every turn, and above `sp_from`..`sp_full` km/h the clicks go higher / brighter / shorter, `sp_pitch` / `sp_bright` / `sp_ring`, and the snap gets quieter + rounder, `sp_soft` (without it ~240 full-band snaps a second put half the energy above 14 kHz: the user heard it as distortion; measure with numpy band energies on the render tool's WAVs), applied per click via `FreewheelSynth.SetSpeedParams` + `Render(.., fast)`, never by resampling; all 0 = the old speed-blind sound. Render it alone: `-s res://tools/freewheel_render.gd --headless -- out.wav kmh=60 [sweep=1 secs=10 <key>=v]`). Skids play the gravel synth louder and grittier (no separate hiss). P / K / L open it on Ride / Rider / Look,
  **Ride presets** sit on top of every Ride / Rider › Physics category (`scripts/core/tune_presets.gd`: built-ins Default, Flowy, Grippy, Drifty, Floaty air, Fast + the player's own via Save as / Delete, in `user://tune_presets.cfg`; an own preset follows its sliders). Reset puts the category back to the active preset's values. Quick tune card keeps the pinned (☆) sliders. Test: `BMX_PANEL=ride|rider|look|sound`
  + `BMX_PANEL_CAT=<n>`.

### Crash logs (`core/crash_log.gd`, autoload `CrashLog`, loaded first; + C# `core/CrashHook.cs`)
- Everything the session prints / warns / errors goes to `user://crashlogs/run_<pid>.log` (a Godot `Logger` via `OS.add_logger`,
  flushed on errors + twice a second) beside `run_<pid>.lock`, which only a clean quit removes (autoload PREDELETE).
- **Next launch finds a lock whose process is gone** -> `crashlogs/crash_<date>/`: `report.txt`, `session.log`, `godot.log` (Godot's own
  rotated log of that run: native + GDScript backtrace of an engine crash), `csharp.txt` (an unhandled C# exception on any thread,
  written straight to disk by `CrashHook`). The title menu shows "The game closed unexpectedly last time" + OPEN FOLDER (`CrashLog.notice`).
- **Script / engine error while running** -> `crashlogs/error_<date>/` (`report.txt`: the error + its script backtrace, seed, bike, ride
  state, the last 400 log lines; `ride_log.csv` = last 60 s). Max 3 per session, one per file:line.
- **F8 / R3** -> `crashlogs/manual_<date>/` (same contents). A watchdog thread writes `HANG?` into the log when the main thread hasn't
  finished a frame for 10 s. `crashlogs/sessions/` keeps the last 20 clean sessions; 20 of each report kind are kept.
- Test runs (autotest, shots, PADSEQ, BMX_MIN / OFFSCREEN, headless, `-s`) use `crashlogs/tests/` so they never push out the player's.
- **When the user says "it crashed"**: read the newest `%APPDATA%\Mini BMX\crashlogs\crash_*` / `error_*` folder.
- `CrashLog.note(s)` adds a line to the log; `CrashLog.cs_new(path)` makes a C# object (null without C#). **C# `[GlobalClass]`es are
  script classes: `ClassDB.class_exists("X")` never finds them** (that is why `GameState.cs_gc()` never ran before 2026-11-20).
- Tests: `BMX_CRASHTEST=error|hard|cs|hang[@secs]` (a script error / `OS.crash` / a C# thread exception / a 12 s freeze), then any run
  prints `CRASHLOG previous session crashed: <dir>`; `BMX_CRASH_NOTICE=1` shows the title notice in a test run.

### Steam release (2026-11-20)
- **Release kit + checklist: repo root `steam/README.md`** (App ID steps, achievements to create, Steam Cloud paths, store
  art sizes, assets still to fix). `steam/upload.ps1` exports to `build/steam/windows/Runout.exe` and uploads with steamcmd.
- `Steam` autoload (`scripts/core/steam.gd` + `SteamService.cs`, Steamworks.NET 2024.8.0 NuGet, native DLL in
  `addons/steamworks/`, copied next to the assemblies by the csproj and found by a DllImport resolver). `APP_ID` is 480
  (Spacewar) until the real one exists, and **Steam stays off while it is 480**: on Spacewar Steam Input took the Xbox pad
  (0 buttons / sticks reached the game, measured). Off in test runs too (`BMX_STEAM=1` forces it), headless and `-s` runs; without Steam
  every call is a no-op. `Steam.ACHIEVEMENTS` (records polled 1x/s, `Steam.trick()` from `hud.on_trick`, `Steam.event()`
  from crash / revive / health pack / garage save / photo / ride start), `Steam.presence()`.
- **No real brands in anything a player sees** (user decision for the paid release): every bike, part, tyre, rim, fork,
  helmet, sponsor, computer name is made up (GLORY DH -> RUNOUT DH, Maxxis -> GRIPWELL, YT Tues -> Yonder Tusk, NS Fuzz
  -> Nexo Fizz...). Internal ids / save keys unchanged; `BikeBuild.rebrand()` converts old saved lettering. New content
  must use made-up names too. The TV texture's logos were painted out (front says VIDAVOX).
- Title menu CREDITS (`ui/credits_menu.gd`): credits, licence texts, Godot + its components. Add attribution there for new
  CC-BY / MIT / OFL assets. Version: `application/config/version` (shown under the menu). Exe icon `icon.ico`
  (`tools/make_icon.gd` renders `icon.svg`).

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
| `BMX_PERF=1` (+ `--autotest=N`, `BMX_NOVSYNC=1`) | main-thread ms per frame for every part of `Game._process` / `_physics_process` (`PERF` lines every 5 s, biggest first) — the way to find what to make lighter |
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
| `-s res://tools/far_hills_probe.gd --headless [-- seed]` | the title / ride backdrop grid: C# batch vs GDScript per point (must match), far tree count; must say `PASS` |
| `-s res://tools/wood_edge_probe.gd --headless` | drives angled lines onto every wooden ramp; must report `walls=0` |
| `BMX_LEVEL=playground BMX_STRAIGHT=1 BMX_PG_AT=table_1.5 BMX_PG_SPEEDS=20,25,30,35` + `--autotest=150` | the test playground: ride one feature at each speed, `PGSUM` per try (see "Test playground" in section 5) |
| `BMX_DIAG=susp [BMX_DIAG_FULL=1] BMX_DIAG_PROBE=1` (+ `BMX_SHOT`) | ride diagnostics panel on a page (overview / susp / input / tyres / body / air); `DIAG` summary lines at the end (see "Ride diagnostics" in section 5) |
| `BMX_LEVEL=playground BMX_STRAIGHT=1 BMX_PG_SUITE=compare` (or `save`) + `--autotest=400` | the playground baseline suite: 24 fixed runs vs `tools/pg_baseline.json`, `PGBASE` lines; run before / after any riding change |
| `BMX_PG_REC=1` / `BMX_PG_REPLAY=1`, `BMX_LAB_PROBE=1`, `BMX_PG_SLOW=0.25` | playground lab: record the test rider's run / replay the saved run (`PG REPLAY end_moved=`), `PG CHECK` summary, slow motion |
| `-s res://tools/playground_probe.gd --headless` | the playground's features (spans, heights, lips); must say `PASS` |
| `--headless res://tools/slope_stress.tscn [-- verbose=1 trace=1 only=<substr> bike=dh]` | ride physics on synthetic ground (no world): coast speed vs the closed form on -45..+15 deg grades (within 3 %), braking / holding vs the friction angle, climbs, cambers to 45 deg, crests (air only past v^2 = g R), rollers, washboard, curbs / ledges / drops, chute compressions, full-lock turns on grades, 4 x 60 s random rides; must say `SLOPE_STRESS PASS` (exit code = failures). A scene, not `-s`: the physics needs the Tune autoload |
| `--headless res://tools/slope_stress.tscn -- sweep=1` | slider audit: every ride slider (not Dust / Demo) at its min and max, from the defaults, through 33 short standard rides (turns at full / half lock, swaps, braking, a side slope, a berm, landings, a manual, pumping, a rock garden...); `SWEEP key group max change % (metric)`. ~10 min. 0 % = dead OR only acts where the rides don't go (air tricks, whips, crashes, drawing): check the code before removing. 2026-11-20 it found `turnSlow` / `turnFast` / `carveBite` / `flickTurn` dead (`turnFloor` always wins the bar limit, the grip decides) - removed, their old defaults are constants in `a_lat_lim` |
| (slider merge, 2026-11-20) | overlapping groups folded: 26 sliders became **followers** (`Tune.FOLLOW`: default x (leader / its default)^exp x the bike's multiplier x Feel; no slider, the physics reads `T.key` as before): `steerRate` / `steerRelease` / `barSpeed` follow `steerEase`; `gripCatch` follows `slipRecover`; `leanIn` / `leanOut` follow `leanRate`; `popPower` follows `popKick`; `pumpHoldUp` follows `pumpHold`; `pumpUnweight` follows `pumpStick`; `airSpinResp` / `airSpinStop` follow `airSpinRate`; `stickSpinBuild` follows `stickAirEase`; `whipSnap` / `whipLean` follow `whipDrift`; fixed: `brakeForce`, `reflexBrake` / `reflexStandUp` / `reflexCatch` (riderSkill scales them), `gyroStable`, `pumpCentred`, `pumpMinSpeed`, `stickSpinGrow`, `stickSpinMax`, `whipCarry`, `whipCatch`, `whipMinSpeed`. Ride unchanged at the defaults (feel / sim / stress identical). 171 ride sliders left |
| `--headless res://tools/slope_stress.tscn -- sim=1` | the ground sim in numbers: `SIM CAMBER` (hands-off drift across 5-30 deg), `SIM TURN` flat vs berm, `SIM BRAKE` front / rear / both from 40 km/h, `SIM TURNBRAKE`, `SIM KNOCK` |
| `--headless res://tools/slope_stress.tscn -- feel=1 [tune=k=v,k=v]` | steering feel on synthetic ground: `FEEL STEER` (time to 63 % yaw / lean, radius, left-right swap) per speed, `FEEL LEAN` (steer / right stick / both / thrown: slip, whip, speed kept) on flat + bumpy ground; `tune=` overrides values (works for every slope_stress mode) |
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
| `BMX_OFFSCREEN=1` | a normal window parked off the screens. **Don't use it** (user, 2026-11-21): tests run with `BMX_MIN=1`, minimised in the taskbar so the user can open one to watch. Minimised windows draw late, so for a frame of an animation freeze it (`BMX_PAPER_AT`, `BMX_INTRO_AT`, `BMX_AREA_AT`) |
| `BMX_PHOTO=secs` (+ `BMX_PHOTO_CLOSE`, `_SET`, `_FLY`, `_ORBIT`, `_TAB`, `_SNAP`) | autotest opens photo mode, sets card values, moves the camera, saves a photo; prints `AUTOTEST photo:` |
| `BMX_CRASHTEST=error\|hard\|cs\|hang[@secs]` | forces a script error / hard crash / C# crash / 12 s freeze; reports land in `%APPDATA%\Mini BMX\crashlogs\tests\` (see Crash logs) |
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
  the same. Freeze the animation (`BMX_PAPER_AT` etc.) for those; stay minimised (the user opens the window from the taskbar to watch).
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
- Riding / jump code: test it on the test playground (LEVELS, `BMX_LEVEL=playground`, section 5) before the trail; the user
  built it for exactly that.

## 9. Status & open items

Recently done (most recent first): dust is a real GPU smoke simulation (no sprites); bolder tread tyre tracks; no tyre clipping in the garage; compact garage
UI; door/flicker/glare fixes; closed front wall + camera kept in the room; ride-camera drag direction
matches the garage; slower mud; review fixes (crash torso culling, NaN freeze, BMX gearing, leftover mud,
photo mode, controls card, view distance, double world build, water re-bake, settings slider drag, garage
rebuild hitch); rider body physics (fore/aft + air tuck/lean); bending spine + pelvis sliders.

All of it is on `main` (the Godot branch was merged, the web version removed). Work continues in this repo.

Known, not fixed (lower priority from the code review):
- Quit warnings: with SSIL on (GI setting 1, the default preset) Godot reports "7 RIDs of type Texture were leaked" at
  exit (gone with `--set=gi=0`; a bare SSIL scene doesn't do it, not found which of our viewports / features adds it;
  harmless, the OS frees it). "2 ObjectDB instances leaked" (ref count 0, C# side) also at exit; even an empty
  `--quit` reports 5. The big leak (89 objects + 3 scripts "still in use") was `field.course` <-> `course._M`, fixed.
- Records: "distance ridden" always 0; top speed lost if the window is closed instead of quitting.
- Camera ignores rebound gamepad/camera keys (reads the right stick directly); `cam_up/down` unused.
- Quick tune card sliders can show stale values after a reset (the tuning card re-reads on every tab).
- HUD hotkeys (P/K/L/H) work on the title screen.
- Rebinding: no conflict detection; pad rebind can't be cancelled.
- Garage: test env `BMX_POSE` values get saved if you then touch a slider; config written on every slider tick.
- Stale code: `_time`. (`hood_hem` and the one-off `fork_measure`, `wheel_measure(2)`, `inspect_glb` tools were removed 2026-11-20;
  `tools/hdri_sun.gd` stays: it measured `Game.HDRI_SUN_U`.)
- Perf (done 2026-11-20): ragdoll ground sampled once per substep, HUD boxes cached (`UITheme.draw_box`), fx dust /
  chunk buffers skip work when idle, `jump_mask` instead of `jump()` per step, wind / splash bed in C# (`RideBedSynth.cs`),
  test flags cached (`Env.s`), torn tape drawn from packed arrays, rider pose inputs in one reused dictionary
  (`Game._pose_in`), ride log = one flat buffer, FarHills grid via batched C# (`far_ground` / `far_colors`), sticker
  fits cached per frame + label (`BikeRig._fit_cache`), chain draws only its links in use.
- Perf (2026-11-20, measured with `BMX_PERF`): the water sheet is hidden and not baked when no loaded chunk dips below
  the water level (`Terrain.water_near`, chunk `gmin`); terrain streaming does nothing when no chunk is missing and sets
  clutter visibility only on a chunk change; tyre unclip caches ground heights per frame on a 1 mm grid
  (`BikeRig._ground_cache`); standing sheep reuse their ground reading. Game scripts ~3.9 -> ~2.7 ms a frame. Still the
  biggest cost: rendering (~5.6M triangles, ~2000 draw calls a frame).
- Frame rate (2026-11-20, RTX 3090, 1600×900, the user's Custom settings, nothing else on the GPU): 118–201 fps by camera
  (`--bench`), ride median ~6.5 ms, ~6 of 3700 frames over 16.7 ms. Fixed then: the start TV is hidden + frozen past
  `START_TV_CULL` 80 m (it cost ~1.5 ms GPU all ride), the fullscreen button no longer re-asks the OS / redraws every frame (~1 ms).
  Then the hitches (worst frame in a ride with crashes 55–100 ms -> 15–21 ms):
  - **MSDF display text** (`UITheme.punch_font`, shared by WASTED, the area banner, the achievement pops): each glyph's
    distance field is made on the CPU on first use (~2.5 ms a letter); the first pop ~4 s in cost ~47 ms in a `_draw`.
    `UITheme.warm_punch_step()` (from `hud.update_hud`) makes one glyph a frame from the start. Don't give these views
    their own SystemFont again (each had its own cache).
  - **WASTED mask** (its own unshaded, no-MSAA, transparent viewport over every rider / bike surface): ~40 render pipelines
    compiled in the first crash frame (~55 ms). `Wasted.warm()` renders the mask a few frames after the ride starts.
  - **Blood**: `Blood.warm_draw(cam)` draws every blood piece once, sub-pixel in front of the camera, and keeps the 8
    splat decals (hidden) so their textures stay in the decal atlas; the bone crunch is built then too. Fatal-crash
    pools (`blood_pool.gd`) set up in stages (ground rows, the C# sim in row chunks `SetupBegin` / `SetupRows`, mesh,
    material), one pool per frame (was ~85 ms when 3 started at once).
  - How they were found: `RenderingServer.get_rendering_info(RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)` counts pipelines
    compiled while drawing (a stall; should stay 0 in a ride); time spent outside every `_process` is often a `_draw`
    (deferred, runs in the message-queue flush). A frame-phase probe (`RenderingServer.frame_pre/post_draw`,
    `SceneTree.physics_frame/process_frame`, priority ±1e5 nodes) splits a slow frame into its parts.
- **Measuring perf**: other GPU programs (an open game window takes ~32 % of the 3090, other sessions' tests) cut the fps in
  half and make GPU spikes; check `nvidia-smi pmon -c 1` first. `TIME_PHYSICS_PROCESS` / `TIME_PROCESS` are the slowest
  single tick of the last second, not averages (our physics tick is ~0.3–0.7 ms). Don't print per slow frame while
  measuring: console prints through a pipe cost tens of ms and make more slow frames.

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

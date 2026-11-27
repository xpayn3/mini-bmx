# Mini BMX (Godot) — project handoff

Everything a new chat needs to carry on with the game. The repo root `CLAUDE.md` points here, so Claude Code
loads it into every chat.

State as of **2026-11-24**. Repo `github.com/xpayn3/mini-bmx`, checkout `C:\Users\Luka\Documents\gamecycling`,
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

Standalone export: install export templates once (Editor → Manage Export Templates). **Build only when the user asks.**

**Release builds carry NO developer tools (user rule, 2026-11-26).** How it works (the industry "shipping build" split):
- Every dev-only script lives in **`godot/dev/`**: tuning cards (`dev/tune/`: P / K / L, quick tune, pause > Tuning),
  Pose Lab, Style Inspector, Anim Studio, frame profiler, physics overlay, render probe, demo AI, the test playground
  (`dev/playground/`: course, terrain, probe, pilot, lab, suite, ramp editor, ride diag) and the **test harness**
  (`dev/main_dev.gd` extends `scripts/main.gd` with `_autotest`, `_bench`, `_showcase`, `_hitch`, `_pad_seq`, `_shot`...).
- Game code never names a dev class: it goes through **`Dev`** (`scripts/core/dev.gd`): `Dev.on`, `Dev.make("pose_lab.gd",
  [args])`, `Dev.script(...)`, `Dev.overlay()`; dev objects sit in untyped vars and are null-checked. `Dev.on` = editor
  binary or the `dev` feature tag (`BMX_DEV=0` = off in the editor, to see a release). New dev tools go in `dev/` the same way.
- `run/main_scene.editor` / `.dev` = `res://dev/main_dev.tscn` (main + test harness); a release runs `scenes/main.tscn`.
  Unknown command-line switches go to `main._dev_cmd` (empty in release).
- Test flags are dead in release: `Env.s` / `Env.raw` (GDScript) and `DevFlags.Env` (C#) return "" / null when off. Read
  BMX_* flags only through them (never `OS.get_environment` directly).
- Export presets: **"Windows Desktop"** = release (excludes `dev/*`, `tools/*`, `docs/*`, `addons/debug_draw_3d/*`,
  `addons/land_lab/*`, `addons/level_builder/*`; the csproj drops `addons/debug_draw_3d/**` + `dev/**` from ExportRelease
  C#); **"Windows Dev"** = feature `dev`, tools in (`--export-debug "Windows Dev" ../build/dev/windows/Runout.exe`).
- `steam/upload.ps1 -ExportOnly` = bake card pictures, export release, then **`steam/check_release.py`** reads the pack inside
  the exe and fails the build if any dev file / the overlay dll is in it (`--list` prints every packed file).

Player data: `%APPDATA%\Mini BMX\` (custom user dir) — `crashlogs/` (see Crash logs), `settings.cfg`, `tune.cfg`, `save.cfg`,
`rider.cfg`, `garage.json`, `logos/`, `screenshots/` (F12).

## 3. Controls (defaults, all rebindable in Settings → Controls)

**Keyboard = MX vs ATV on PC (2026-11-24): WASD is the bike, the arrow keys are the rider's body (the pad's right stick).**
W pedal · S brake (both levers, with feel) · **Ctrl front brake only · Alt rear brake only (bare levers: they lock)** · A/D steer · **Space** hop/pump (hold to charge; **in the air: tuck the bike up**) ·
**↓ rolling = manual** (a held key sits on the balance point, `BikePhysics.kb_back_cap()`; full back only at a lip / in the air) ·
**↓ / ↑ held into a lip = back / front flip, held in the air keeps it turning** · **← / → = lean, flick, whip; in the air lay the bike over / tabletop** (keys give `Game.KB_SIDE` 0.75: no flat spins from a key held into a lip, the stick's spin edge stays the pad's) ·
W / S no longer tilt the bike in the air or throw flips (like the pad's triggers: braking through a bump used to loop you out, held S = nose up); **Settings › Controls › Classic keys** (`kb_ws_air`, input `ws_air`) brings that back. Old saves: `Settings._move_arrows_to_body` (`kb_layout` 1) takes the old arrow defaults off pedal / brake / steer. Test tricks (`BMX_TRICK=back|front|manual`) press the body keys now.
**A/D in the air: lean the bike left/right (no spins)** · **brake + A/D when slow: pivot (pirouette)** · Shift sprint (stamina) · Q/E shift gears · F bail · Backspace back to
start · R new world · B next bike · C next camera · Z/X rotate camera · +/- zoom · mouse drag orbit ·
H records · **I instant replay** (pad L3; whole ride, savable: section 5) · **F4 ride diagnostics** (test playground only, section 5) · **F10 frame profiler** (section 9, Perf) · **M trail map** (pad: Share) · **P / K / L** the tuning card on its Ride / Rider / Look tab · **O photo mode** (free camera, see section 5) · F1 hide HUD ·
F12 screenshot · **F11 / the small button bottom right: fullscreen on / off** (`ui/fullscreen_button.gd`, on every screen,
saves Settings › window mode; in the garage it sits above Save / Save & ride) · Esc pause. Gamepad (Xbox): triggers pedal/brake, left stick steer, X hop (jump), A sprint, bumpers gears, Y camera, D-pad left / right rotate the camera,
**right stick = the rider's body, all the time**: up / down shifts the weight forward over the bars / back (pulled well back
rolling = a **manual**, yanked fresh at a lip = a flip throw, in the air = nose down / up), left / right throws the bike over under
the body (leaning alone turns, leaning with the steer turns harder + grips more, a quick **flick** whips the bike round; in the
air it leans the bike). The arrow keys (and numpad 8/5/4/6) do the same on keys. The camera no longer uses the right stick.
**Settings › Controller** (`ui/pad_map.gd`): the Xbox photo (`assets/ui/xbox_pad.png`, cut out by root `tools/cut_pad.py`;
without it a drawn pad) with what every button does, click to remap (sticks pick Steer / Rider body / Camera / Nothing and
swap), live button test, vibration: on / off, motors and a strength per effect (see "Controller rumble" in section 5). `Settings.pad_active` follows the last device used: prompts show
Xbox names (`Settings.prompt(action)`), and on a pad the triggers don't tilt or throw the bike in the air (only a real
right-stick yank from centre throws at a lip; a held lean never does). **Superseded 2026-11-24**: a stick held back
(forward) into a lip, however early, throws the back (front) flip, like other games; see "Spins and flips carved / thrown
at the lip" in section 5.
In the air the right stick is a **360° attitude control** (`air_stick`): y tilts the nose on top of the landing aim
(`stickAirTilt`), x lays the bike over (`stickAirRoll`); only the very edge (> 0.88) keeps it turning over (flips). Test:
`BMX_BODY=circle` circles the stick mid-air (`AIRSTICK` lines). Test runs ignore real controllers (`Settings._test_run`).
Arcade-style feel: the stick is eased (`stickAirEase`), the tilt / lean springs go soft while it's used, and held at
an **edge** it spins: top / bottom = flips (`edge_s` → `flip_in`), left / right = **flat spins** (`stick_yaw` on top of
`air_yaw`, `stickYawRate`). **Since 2026-11-24 both get their rotation at the lip** (spin: stick to its side edge
into the lip; flip: held back / forward into it); from the air alone only ~35 % of the rate. Both build up gently (`stickSpinBuild`) and get faster the longer they're held
(`stickSpinGrow`, up to 1.5 s); let go and they ease out. Near the landing a spin within ~57° of straight is twisted
the rest of the way. Landed tricks are named "360", "720", "360 BACKFLIP"... In the air the rider's body drives it:
counter-leans against the bike (`stickBodyCounter`) and stays steady while the bike tilts under it (`stickBodyTilt`).
Tests: `BMX_BODY=holdback` (`SPIN` lines), `BMX_BODY=spin360` (`YAW` lines; air-only now: comes round only part way),
`BMX_BODY=spinlip|fliplip` (wound up / thrown at the lip).

## 4. Project layout (`godot/`)

| Path | What |
|---|---|
| `project.godot` | Forward+, 1600×900 canvas_items stretch, **physics 120 Hz**, MSAA 2×, shader globals (`atm_wind`, `atm_pusher`, grime…) |
| `scenes/main.tscn` + `scripts/main.gd` | title menu, ride, garage, pause, settings, controls card, all test flags |
| `scripts/core/` | autoloads: **Settings** (graphics/display/audio/controls/rebinding, presets Low–Ultra), **Tune** (ride feel × bike multipliers, pins for the Quick tune card), **GameState** (bikes, seed, records, `bike_config()` merges the garage build) |
| `scripts/bike/` | `bike_physics.gd` (the ride, fixed 120 Hz, 1:1 port of web `physics()` + new body model), `bike_rig.gd` (model, pose, pedals, grips, limb targets), `suspension.gd`, `bike_build.gd` (garage data: paint finishes, logos, wheels, suspension, cassettes, ride mods, stats), `wheel_gen.gd` (procedural wheels/tyres), `decals.gd`, `bike_fx.gd`, `grime.gd` (mud/wet overlay passes) |
| `scripts/rider/` | `rider.gd` (procedural rider posed every frame; **skinned spine** with 5 bones), `rider_gear.gd` (helmet, goggles, torso geometry), `rider_geo.gd`, `ragdoll.gd` |
| `scripts/world/` | `terrain.gd` (chunk streaming, LOD ground with skirts, decorations, water, debris, tape), `terrain_field.gd` (GDScript reference height field) + **`TerrainFieldCs.cs` / `TerrainFeatCs.cs` / `TerrainWoodCs.cs`** (C# port, must match exactly), `terrain_chunk_builder.gd` (worker-thread chunk build), `trail_course.gd`, `trail_features.gd`, `terrain_water.gd`, `terrain_debris.gd`, `tape_sim.gd` (torn tape ribbons), `atmos.gd` (wind, cloud shadows), shaders |
| `scripts/game/` | `game.gd` (one ride: interpolated drawing between physics states, crash/ragdoll, fx feeding), `camera_rig.gd` (**trail** = default: behind and above, frames the trail ahead and the landing (TrailView); C / pad Y cycle: trail, **helmet** (POV from the action cam on the helmet, `Rider.action_cam` built by `rider/action_cam.gd`, lightly stabilised, chase view while crashed; in a crash the camera body snaps off its hinge and tumbles away, `fx/flying_cam.gd`, a new one is on after getting up), chase, **drone** (banks into turns, noses down with speed, hovers in gusts, prop buzz + `ui/drone_osd.gd` REC / height / distance overlay), side, trackside, bike POV when a bike cam is mounted; Low dolly, Close, Diorama, Slow orbit, Isometric, Top-down were removed 2026-11-20 as near-duplicates), `ride_audio.gd` (procedural sound) + `FreewheelSynth.cs` (freehub clicks: modal resonances fitted to a real hub recording, click rate = wheel speed × 24, tone never pitch-shifted) + `GravelSynth.cs` (tyre roll: ~500 pebble knocks per metre, damped rings around 650 Hz + cracks + casing rumble, fitted to a tyres-on-gravel recording within ~2 dB per band; tone per surface) |
| `scripts/garage/garage.gd` | the garage scene (room, open roller door with the real world outside, rollers, standing rider, all tabs) |
| `scripts/ui/` | `hud.gd`, `settings_menu.gd`, `tune_card.gd` (the one tuning card: Ride / Rider / Look / Sound tabs, each with category tabs), `quick_tune.gd`, `rider_panels.gd` (`POSE_DEFS`, `KITS`, `LOOK_ROWS` + saving), `ui_theme.gd` |
| `scripts/fx/` | `fx.gd` (dust puffs, dirt chunks, **tyre tracks**), `ride_dust.gd` (GPU dust trail, FogVolume clouds) |
| `shaders/` | `sky_hdri.gdshader`, `grade.gdshader`, `grime_mud/wet`, `ruts.gdshaderinc` (ruts + tyre prints) |
| `assets/` | `dh.glb`, `helmet.glb`, BMX model, `hdri/` (Poly Haven **Kloofendal 4K**), `textures/painted_concrete_02` (garage floor), `textures/broken_brick_wall`, `fonts/Doto.ttf` (Google Fonts dot-matrix, OFL — the HUD bike computer via `UITheme.lcd_font()`) |
| `dev/` | **developer tools only, never in a release export** (see "Release builds" in section 2); older notes below may still say `scripts/ui/tune_card.gd`, `scripts/levels/playground_*.gd`, `scripts/game/frame_profiler.gd` etc.: they are in `dev/` now |
| `tools/*.gd` | one-off headless test / measure scripts (`terrain_cs_cmp.gd` is the important one) |
| `docs/GRAPHICS.md` | quality presets, frame times, features, what was left out and why |
| repo root `tools/` | Houdini exporters `export_dh.py`, `export_bmx.py`, `export_helmet.py` → write into `godot/assets/` |

## 5. Systems — how they work

### Ride physics (`bike_physics.gd`)
- **Energy account (2026-11-22, `BMX_ENERGY_PROBE=1`)**: every 5 s an `ENERGY` line, J/kg since the start: the drive
  stage's terms (pedal, brakes, pump, rolling, air, grade, manual), the change across each other stage (`S_steer` slides,
  `S_move` hits, `S_vertical` springs / landings, `S_lip`, ...) and `height` (g x height change). First result (seed 4242,
  demo AI): the brakes take as much as all the pedalling (-692 vs +660 J/kg, braking 18 % of the time) - the trail's
  bends don't fit the speed its descents give. See `docs/research/ride_feel.md` (research + ranked changes).
- **Ride the berm + banks sized to speed (2026-11-22, `ride_feel.md` change 1)**. Measured first (`tools/bend_probe.gd`,
  `tools/berm_probe.gd`, -s headless): the course's berms were already 20 deg on average (switchbacks 31) and the ground
  matched (`berm_shape` rises from ~1.6 m inside the centreline outwards), but the racing line (`LN`: the worn ground,
  the demo AI's aim) cut ~2 m to the flat INSIDE at the apex, so the bike felt 4-10 deg and the AI braked 18 % of the
  time. Now: (1) `TrailCourse._racing_line` blends the line up onto the berm face (`BERM_LINE` 0.9 m out, from |BT| >
  `BERM_LINE_FROM`); the demo pilot aims there too and plans a bend with its bank (`A_LAT + G x |BT|`, Tune `demoBerm`).
  (2) `TrailCourse.VA` = the speed a good rider arrives at (gravity down E, rolling `VA_ROLL` + air `VA_DRAG` as measured,
  pedalling when slow, capped by each bend's radius + bank: forward only, so growing never changes it); `_bank_need`
  raises the bank of bends that carry berms (ROAD / SWITCH / ESSES) to what the free-rolling speed into them needs, up to
  `BANK_MAX` 0.70 (35 deg), never below the old shape. E is now built before BT (`_shape_profile` doesn't read BT). Banks
  and the line are course arrays C# copies: `terrain_cs_cmp` EXACT, `trail_grow_probe` PASS. Every world's berms / line
  changed. Demo AI, 85 s: seed 4242 42.0 -> 46.2 km/h avg, braking 18 -> 15 %, brake energy -16 %; seed 5 43.0 -> 46.9,
  braking 16 -> 12 %, brake energy -23 %; 0 crashes; more slide scrub (`S_steer` -40 -> -140 J/kg: faster corners).
  `BMX_OLD_LINE=1` / `BMX_OLD_BANK=1` = the old line / banks. Left: ~7 % of bends too tight to hold at 35 deg (layout,
  change not made); the demo AI still slows to 32 km/h for every rock garden (`ROCK_V`).
- **Berms pay back, rollers pump, jump lines in rhythm (2026-11-23, `ride_feel.md` changes 2-4)**.
  (2) `bermPump` (Ride > Pumping, 0.12): the pump held (hop or stick forward) while a berm carries the turn (`berm_k`,
  `corner_g` > 0.3) pushes the bike on by bermPump x corner load: ~+75-100 J/kg on a 90 s demo ride (a tenth of the
  pedalling), none hands off. The demo AI pumps berms with the stick (held hop crouched and popped off the berm top:
  slower) and only below its target speed (pumped while too fast it went OVER THE BARS braking for the next bend).
  (3) `slope_stress.tscn -- rollpump=1 [only=h0.30L6k35hop_back trace=1]` (`ROLLPUMP` lines: energy per roller vs hands
  off, 8 sine rollers, hands off / held / hop on the backsides / stick on the backsides). Found: the downhill pump needed
  BOTH wheels down, and over a roller's crest the front leaves the ground for most of the backside, so the hop button
  never pumped a roller (and its release hopped). Now one wheel down is enough (`ground_ok`), and a press that spent
  over half its time (>= 0.08 s) pumping is let go without a hop (`pumped`). Button on the backsides now +0.5..+2.2
  J/kg per 0.3 m roller (was -0.2..-2.2), stick +1..+7, held all the way ~0. The trail's roller shape (10 m, 0.48 m)
  stays: at 45 km/h it is ridden on the ground; 6 m ones (research size for pump-track speeds) are jumped there.
  **Same day, later: the pump is now the legs' stroke** (`_step_drive`, supersedes `pumpHold` / `pumpHoldUp` /
  `pumpUnweight` / `pumpGain` and the old hidden `compress_v` x slope pump, which also worked hands off: all gone).
  `pleg` = the legs' stroke, -1 bent (hop held / stick back: `_bend_in`) .. +1 straight (stick forward), `PUMP_STROKE`
  0.3 m end to end, at most a whole stroke in `PUMP_STROKE_T` 0.16 s. Moving it does work against the ground's push:
  dE = rider share x (n - 1) x g x stroke moved, n - 1 = v^2 x the ground's curve under the bike over +-`PUMP_SPAN`
  0.6 m (`deck_height`; NOT the tyre loads: over a crest the front leaves the ground and the springs ring, which put the
  timing a quarter roller out), capped -1..+1.5. So: bend over a crest (light) and straighten into the dip (heavy) =
  gain; the other way round = loss; held still or hands off = nothing; a straight slope, however steep, = nothing (the
  old downhill push is gone). Button cue: press going over the top, let go at the bottom of the dip (a pumping press
  let go straightens the legs at once, `_cr_rel`, no pop). Slider `pumpLegs` (1, Ride > Jumps > Pumping; bikes x
  `frame_mods` progression, Flowy preset 1.5, Feel > Flow). Measured, ROLLPUMP ridden on the ground (no flights): hands
  off identical to before; button done right +0.5..+1.3 J/kg per roller, stick done right +0.5..+1.4, stick the wrong
  way -0.5..-1.1, held 0. Demo AI 130 s seed 4242: 46.7 km/h, 0 crashes. Suite: 5 of 24 moved by the hidden pump's
  removal (table_1.5@34 lands on the knuckle edge, stepdown_1@30 rolls back after its upslope landing, two runs +1
  landing check); baseline re-saved. Stress 55 / 56 (the chaotic "brake grade -35 deg").
  (4) `TerrainField._build_route`: jump sections follow `RHYTHM` beats (build: rollers -> release: a jump / table line
  -> rest: a bridge or plain trail), the next lip one roll-out after the landing (`VA` x 0.75 s, 6-14 m, + 12 m after a
  rest); jump sections draw from their own random stream. **Every world's features after its first jump section are
  laid out differently than before** (12 worlds x 4 km: 170 features, was 166; bridges 9, was 18; rollers 50, was 31).
  `BMX_OLD_RHYTHM=1` = the old layout. C# copies `route_feats`: `terrain_cs_cmp` EXACT, `trail_grow_probe` /
  `rope_find` PASS, `wood_edge_probe` walls=0. Demo AI, 130 s, seeds 4242 / 5: 46.0 / 46.6 km/h, 0 crashes, every
  built jump landed on its landing. Stress 56 / 56, suite 1 of 24 changed (hop_0.8 take-off 2.5 deg flatter).
  Changes 5 (forgiving sideways landings) and 6 (graded pop) were already in (landings / jumps work of 2026-11-22):
  a sideways landing under ~20 deg can't highside below ~86 km/h; the pop is graded by snap speed, lip timing, rebound.
- **Skipping off the ground (2026-11-23, user: "bike behaviour over terrain is kinda off")**. Measured with the new
  `BMX_SKIP_PROBE=1` (trail) and `slope_stress.tscn -- skip=1` (repeatable: hands off down a synthetic rough descent,
  crests / dips 4-23 m, 35-65 km/h; `trace=1` dumps the steps before a flight). Trail runs vary 5-9 skips/km between
  identical runs (the follow rider never rides the same line): judge changes on `skip=1`. Found + fixed: after a crest
  the bike rode 10 m on the front wheel with the rear up, because every little bounce of the front was a take-off and a
  take-off seeds the flight's spin from the body's smoothed spin (`body_pw`): it handed back the nose-down rotation at
  each bounce, until the front met a dip on a bottomed fork (46 g in a step) and the bike was thrown off. Now a take-off
  from ONE wheel flies on with the gentler of the bike's own spin and the body's (the bike's alone nose-dived the 0.8 m
  stress rollers). `BMX_OLD_BOUNCE=1` = before. Dip kicks on the trail got short (0.07-0.4 s, were 0.4-1.7). The user
  rode it: "feels better". **Auto-absorb** (`autoAbsorb`, Ride > Body > Legs, default 0 = off, Tune VER 25): hands off
  the legs bend ahead of a crest the bike would fly (the leg spring's rest, `rel_t`, `_ab_bend`), no speed from it.
  On `skip=1`: air time -7..-14 %, flights not fewer, and the short 3 m stress rollers nose-dive with it, so it is off.
  Tried and dropped: bending AT the crest (body on a smoothed line: lighter just where it needed weight, more flights),
  an active push off the crest with the legs' damper let off, more leg travel (`legExt` 0.2 / 0.25: ~no change), stiffer
  legs (`legStiff` 60: +40 % flights). Left: on ground that rough at 55-65 km/h most flights are real (crests past -1 g),
  and about half the rest are the soft legs (0.9 Hz) letting the body lag, reaching full extension and jerking the bike
  up (inelastic merge at `legExt`); not changed.
- **Off the trail the rear holds unless asked (2026-11-23, user: "some are sliding too much", riding off the trail;
  "the outside must be enjoyable too")**. Measured with the new `slope_stress.tscn -- slide=1 [verbose=1 trace=1]`
  (free riding on grass / trail / sand, flat and bumpy: weaves, half lock, full lock held, pedalling in a turn, keys
  left / right; `SLIDE` = time the rear is past its slip angle with nothing asking). Trail: never out. Grass bumpy:
  6 % of the time past 8 deg, holding a turn the rear grew to 25-60 deg and the speed died; sand to 80 deg + WASHED
  OUT. Cause: over bumpy ground the rear's load swung 2..17 m/s^2 every few steps; each light moment the pedalling
  emptied its friction circle (sideways grip 0) and the slide ratcheted out, the catch (x grip^2) never got it back.
  Fix: (1) the rear tyre's grip follows its load over ~0.08 s (`_nR_s`, tyre relaxation; grip sim + drive cap);
  (2) `slideHold` (6 /s, Ride > Tyres): a slide nobody asked for (no locked rear, whip or sprint spin) past ~4..11 deg
  is caught back by the rider. Now: grass max 7-9 deg, sand 10, no crashes, speed kept; whips (24-25 deg) and rear
  skids unchanged, rear-brake stop 9.7 -> 10.2 m. Tried and dropped: the rider feathering the pedals in a turn
  (lost speed, sat sideways more). `BMX_OLD_GRIP=1` = before. MX vs ATV-style: the bike slides when you ask.
- **Brakes limited by the tyres, per surface (2026-11-23, `docs/research/papers_review_2026-11-23.md` #1)**. The levers used
  to run out first (front 7.5 x 0.75 = 5.6 m/s^2 vs a front tyre good for 7-15), so every surface stopped at ~0.84 g. Now
  `BRAKE_MU` (braking grip per surface: ground / grass 0.62, trail 0.78, water 0.5, sand 0.45, eased per tyre `_bmu_f/_r`,
  x new slider `brakeGrip`, Ride > Brakes) caps each brake and `brakeForce` is 13 (levers can lock either wheel). The
  hips-back brace while braking only counts a quarter for the load split (`xb` in `_step_loads`): it put +0.36 g on the
  rear and a locked front then stopped at 0.14 g. Playground @30 km/h: dirt 0.80 g (was 0.86), sand 0.49 (0.73), front
  lever only locks 0.53 (never locked), rear only locks 0.46 (0.68). `sim=1` SIM BRAKE now per surface. `BMX_OLD_BRAKE=1`
  = before. Lateral grip (`SURF_MU` x `grip`) unchanged.
- **Research review follow-ups (2026-11-23, `docs/research/papers_review_2026-11-23.md`)**. #2 off-trail "flow ground":
  measured first (`-s res://tools/offtrail_probe.gd`: crests that throw the bike at 20/30/40 km/h, slopes): only ~1 % of
  the open land throws at 30 km/h, 2.7 % at 40; removing the 8 m bumps, ridge creases, 28 m hills and rugged cliffs all
  together only took 40 km/h to 1.6 %. Not the problem: not changed. #3 trees: `-s res://tools/deco_probe.gd` (real
  chunks: trees / ha, trunk spacing, free ride from an open spot): a 2.6 m trunk gap rule removed the clumps (17 % -> 1 %
  under 1.5 m) but the free ride stayed the same (~20 % of directions hit a tree within 10 m) and cost ~18 % of the trees:
  not kept. Kept: rocks are added to `blocked`, so the grass carpet / tufts no longer grow over (and hide) them. #4 crash
  shake (`camera_rig.gd`): trauma = physics shake / 0.45, shake = trauma^2, ROTATION only (yaw / pitch 1.5 deg, roll 2.5
  deg on smooth noise, `SHAKE_*`), no camera move (Eiserloh GDC 2016); `BMX_OLD_SHAKE=1`. #5 drawn bars (`Game._bar_draw`,
  drawing only): head-angle + lean correction (atan(tan steer cos lean / cos 27 deg)), countersteer flick from the roll
  rate (`BAR_CS_K`, ~3-4 deg in swaps), a 7 Hz damped kick from front-wheel hits (`BAR_HIT_*`, 1-4 deg on the rocks lane,
  0 on smooth ground), bars flop into a dab; `BMX_OLD_BARS=1`, probe `BMX_BAR_PROBE=1` (`BARS` lines).
- **Tyre batch (2026-11-23, review #6-8)**. (a) Relaxation is a distance (`_relax_t`: the lag at `RELAX_V` 6 m/s, x 6 / v,
  0.015-0.12 s) for `_load_s`, `_share_f` (`tyreRelax`) and the rear `_nR_s` (0.08 s at 6 m/s); `BMX_OLD_RELAX=1`. Feel
  unchanged, slide wobble flips 184 -> 148 / biggest 0.40 -> 0.17 (`BMX_JITTER_ALL`). (b) Load sensitivity (`_ls`,
  -`LOAD_SENS` 0.15 per 100 % over the resting load, 0.75-1.15) on the brake caps, drive cap and the front tyre's grip
  (the turn limit already had load^0.7); `BMX_OLD_LOADSENS=1`. Brake key, 40 km/h: trail 0.81 -> 0.73 g, grass 0.72 ->
  0.62, sand 0.53 -> 0.49 (the research targets); playground dirt 0.70 g. (c) Tried, dropped: a Magic Formula-style
  peak-then-fall rear force curve per surface: no measurable change (whips are driven to their own angle, unasked slides
  stay under the peak, a locked rear has almost no side grip anyway): `slide=1` now also prints `SKIDTURN` (rear lever
  locked through a turn on grass / trail / sand). Stress: the brake-hold check accepts either result within 10 % of the
  friction limit (56 / 56).
- **Stick spring-back is not a pop; bad landings bog, not stop (2026-11-25, F8 seed 642455: "jump when I hit some bump was
  very weird")**. Ride log: right stick held back into a natural crest at 68 km/h, let go just before it: the thumbstick
  sprang past centre to +0.30..0.35 for 0.07 s, which passed the stick-hop's "snapped forward past 0.3" test, so a pop was
  queued for the lip (+1.6 m/s up in one step, 1.5 m high, and as the player's own pop it got the pro nose-up pull); the
  stick back again in the air took it to 40 deg; the landing on flat at 34 deg nose up lost 16 km/h in ONE step. Now:
  the snap must pass `STICK_POP_FWD` 0.6 (`BMX_OLD_STICKPOP=1` = 0.3); the landing-angle cost (`landAngleCost`) is
  x lerp(`BOG_SOFT` 0.35, 1, impact / 4 m/s) and taken off over `BOG_T` 0.4 s (`_bog`; `BMX_OLD_BOG=1` = whole, at once).
  Test `BMX_PAD=1 BMX_STRAIGHT=1 BMX_BODY=springback[:x] BMX_FORGIVE_PROBE=1` (held back, then a 0.07 s overshoot of x,
  default 0.35, every 2.5 s): 0.45 -> 7 STICKHOPs old, 0 new; 0.9 still pops. A limit on how fast the front falls after a
  back-wheel landing was tried and dropped (user: "awful"). Note: `BMX_PG_PILOT_PITCH` snaps the pitch in one frame
  in the air (a test aid: looks like a glitch in the window).
  **Touch-down pop of the drawn bike (same day, user: "weird frame jump before landing")**: `Game`'s AIR_SHARE offset
  (the bike moving against the rider's hips in the air) had its downward part clamped off on the touch-down frame, so
  the drawn bike popped 7-8 cm up against its fall in one frame on every landing. It now eases to the clamped value
  over `AIR_SHARE_EASE` 0.08 s (`_air_dlt`; `BMX_OLD_AIRSHARE_SNAP=1` = the clamp). Measured with `BMX_JITTER_ALL=1
  BMX_JDUMP=file.csv` (rows now end with the drawn bike's world x y z, pitch, air, physics pitch / y, physics frame,
  drawn pitch, pitch_draw): touch-down excess 0.066-0.082 m -> ~0.01. User: "now its super smooth".
  **Open: twitch while loading a lip** (user: "the only twitchiness is on jump, before he pops"). `BMX_POSE_PROBE=1` now
  prints `POSETWITCH` (chest 2nd difference > 1 cm in a frame + which limits moved it): during the preload the bar
  and rear-wheel limits shove the chest 1-2.6 cm in single frames, and right after the pop the stand-tall moves it
  3-5 cm a frame (no limit involved: the face / stand-tall pose blend). An acceleration cap on hips + chest (45 m/s^2)
  only took 76 -> 67 such frames on dtable_36: tried and removed. Not fixed.
  **Reset after a crash: one crumpled frame (same day, F8 seed 799751)**: the race number (`BackNumber`) kept the
  ragdoll's crumple for the first frame back on the bike. `Rider.reset_pose` now calls `BackNumber.restart()` (laid
  flat, no carried-over speed). Tests: `BMX_BAIL=14 BMX_TAP_RESET=17 BMX_TAP_INPUT=1 BMX_TAP_SHOTS=prefix` (the bail
  tap sent as a real input; 16 consecutive frames at 0.15x kept in memory, `SSHOT` lines with the camera; without
  `BMX_TAP_INPUT` the reset runs mid-frame after the camera update and the first shot is a mix: not a game bug),
  `BMX_CRASH_SHOTS=prefix` (the same from a crash's start), `BMX_RESET_DUMP=1`, `BMX_RAGSTART_DUMP=1` (ragdoll head /
  chest / pelvis vs the bike, first 0.25 s). The F8 ride log now records the ragdoll's head / chest / pelvis
  (relative to the bike's point, world axes) in the pelvis_* / chest_* / head_* columns while crashed (they held the
  last riding pose). **Open: the user saw the whole upper body drawn offset in some fast hard crashes**; not
  reproduced (a plain bail draws the ragdoll smoothly): press F8 right after one.
- **One ground -> air blend for the drawn body (2026-11-26, F8 seed 34229: "on a right berm the whole rider wobbled, like an assist
  aligning it to something")**. At 63-70 km/h onto a berm face the bike skipped off the ground 4 times in 0.35 s (0.07-0.11 s each);
  every drawn part that read the raw `air` flag flipped with it: the in-air body counter-lean (stick to the side, counter = 1.25 x
  bike lean) vs the berm pose (counter = 0.2 x bike lean), so the body swung ~30 deg at ~8 Hz, and the bank read for the drawing fell
  toward flat in each skip. Now `BikePhysics._air_blend` sets `air_k` (the rider's "air" input already used it) = 1 only for a real
  flight (predicted whole flight `air_time + _land_t` >= `airBodyMin` 0.25 s; no prediction: 0.15 s of air), eased in over `airBodyIn`
  0.18 s, out over `airBodyOut` 0.12 s after touch-down (the counter snapped back in one tick before). The counter-lean, the body
  lining up with a bank (`bank_sq`), the bike's lead (`_bike_lead`) and the drawn ground lean (`_gx_lean`, `bank_lean`) use it
  (`gnd` = 1 - air_k); through a skip the drawing keeps the last ground bank (`_bank_hold`). Sliders Ride > Jumps > Landing.
  `BMX_OLD_AIRBLEND=1` = before. Same berms, test rider: counter steps > 0.1 rad a tick 29 -> 13 (the rest: the zero-crossing flip
  below, a crash). Playground suite identical with / without. Not fully drawing-only: the physics reads `bike_lean` in 3 places.
  **Open**: `counter` jumps ~0.25 rad when `bike_lean` crosses 0 (sign of the max() flips). Test spawn: `BMX_SPAWN_AT=x,z,heading`
  (from an F8 log; Backspace returns there), e.g. `BMX_SEED=34229 BMX_SPAWN_AT=360.98,-28.99,-0.6224 BMX_START_V=17`.
- **Forest berms, roots, smooth drawn lean, arms, back-wheel hops (2026-11-26, F8 seed 876814 + a pro's Red Bull downhill video,
  `Documents/GameResearch/You-ve-never-seen-Downhill-Riding-like-this_003_1080p.mp4`)**. (1) Narrow trails' berms (`berm_style`, GD + C#,
  half-width 0.35..0.85 only): rim ~1.7 m out (was 1.1), face curving up, no scoop dug into the face; trees in tight forest bends from
  W + 2.4 m. It was: leaned ~45 deg a little wide, the tyres hit the crest and the bike floated over (`BMX_OLD_NARROWBERM=1`). (2) Roots
  real size (0.28-0.4 x the trunk, 6-13 cm; were trunk-thick since the real-size trees), light bark (`BMX_OLD_ROOTS=1`). (3) The physics
  lean is as smooth as the pro's (top ~2.5 rad/s); the DRAWN one jumped: `counter`'s 80 % clamp flipped sides as the bike crossed
  upright (one-tick body jumps of 0.1-0.3 rad, the open item above): now faded in over the first 0.3 rad; `cap_bank` eased
  (`BMX_OLD_LEANDRAW=1`). Drawn pose inputs that read the raw air flag (`_atilt_s`, `_blat_s`, `_aspin_s`, `_awhip_s`, `_turn_s`,
  preload, landFold, inAir) follow `air_k` (`BMX_OLD_AIRBLEND=1`). (4) Shoulder twist into turns halved (cap 0.3 rad on the ground,
  `BMX_OLD_TWIST=1`). (5) Arms: elbow pole mostly out + a little back / down (was back + down: "rowing"), `armBend` default 0.6
  (~100 deg elbows; RiderPanels POSE_VER 4 moves saves still at 0), sprint elbows a touch lower (`BMX_OLD_ARMS=1`). (6) Back-wheel
  hops: the drawn rig pitches about its origin with the rear axle 0.44 m behind / 0.45 m above it, the physics with it 0.33 m behind
  and level: on the back wheel the drawn tyre sank up to ~25 cm and the unclip lift shoved the bike up then snapped down off the
  lip. `Game` moves the drawn bike so the carrying axle is where the physics has it (`_piv_c`), and the lift eases down in the air
  (`LIFT_AIR` 1.5 m/s) (`BMX_OLD_PIVOT=1`). Left: the physics rear compresses further than the drawn swingarm shows (part of the
  lift stays); the torso still rides rock hits stiffly (needs its own world-space path). The user rode it: "smooth".
  Then (same day, F8: "a weird jolt of the rider's lean on the last landing"): the stick pushed sideways just before touch-down
  snapped the air counter-lean in at once and the landing took it out in 0.12 s (hips 18 cm sideways): `_air_wl` follows the
  stick at 4 /s (`BMX_OLD_LEANDRAW=1`), `airBodyOut` 0.12 -> 0.25 s (Tune VER 32). Camera: in the air it leans into a STEERED
  turn (slip fading out past ~0.5 rad and while a spin is held), so the landing carve no longer swings the view ~19 deg in 0.1 s;
  its rate cap eases in (`BMX_OLD_CAMHEAD=1`). Test rider, stick sideways in the air: worst hip jump sideways 19 -> 0.6 cm.
  Later (same day): **slow riding** (`BMX_OLD_SLOW=1`): `slowSteer` 1.2 -> 0.85 rad (Tune VER 33; bars ~49 deg stopped, was 69), hold
  the brake 1 s at a stop on ground flatter than `REV_SLOPE` 0.14 rad = reverse (steers like a bike; `rev_on_hold`, off in the
  slope_stress brake checks), the pirouette only rolling forward (> 0.5 m/s). Small unasked slip (< ~0.1-0.2 rad, no whip / locked
  rear) is drawn 80 % along the travel (`Game._slip_k`, `BMX_OLD_SLIPDRAW=1`): hands off across a 30 deg slope it crabbed 5 deg.
  **Berm lock-in** (`bankLock` 0.6, Ride > Ground, `BMX_OLD_BANKLOCK=1`): leaned WITH tilted ground (any berm / bank / slope),
  the pull down it (camberPull 0.22) gets + bankLock: research (banked-turn physics, MTB berm technique) + a new test
  `slope_stress.tscn -- bermwhip=1` (round 10 m bowl, 20 / 35 deg, design speed and 1.2x, whip thrown / held / steer let go,
  `BERMWHIP climbed= over_rim=`): at 1.2x on 35 deg the bike climbed 9.4 m and left over the rim with a light steer; now 0.9 m
  (1.2 was too sticky). The whip itself was not what threw riders out. sim=1: side slopes ridden straight unchanged, a light steer
  into a berm turns ~45 % more. **Project X corners** (Mash Games; videos in GameResearch, frames analysed): in a deep turn the bike
  goes out to ~65 deg under a rider at ~30-35 deg, crouched; in berms the body is square to the FACE. `counter`: body share 80 % ->
  50 % from 0.5 to 1.1 rad of bike lean, on banks the body leans as far as the bank (>= half the bike, <= 80 %); rider.gd crouches
  hips -7 / chest -12 cm (+5 cm forward) as the bike goes out (`BMX_OLD_CORNERBODY=1`). Forest berms: bike 69 deg -> body 54 deg
  before, 34 now. **Chase camera** = Project X framing (dist 4.2, pitch 17, FOV 50 vertical ~78 horizontal, rate 4.5; was 7 / 16 /
  42 / 3.2). **Chase follows the slope** (2026-11-26, user: "descents / ascents we can't see in front"; `CameraRig._ground_slope`,
  `SLOPE_*`): its pitch was from the horizon, so down a 33 deg slope it sat inside the ground behind, the occlusion lift took
  it to ~63 deg and it looked straight down. Now (like Descenders / Lonely Mountains) a descent puts it `SLOPE_CLEAR` 8 deg
  above the ground behind and lifts the aim 0.4 x the slope (looks down the trail); a climb drops it 0.65 x the slope and
  tips the view up 0.75 x it. Flat ground unchanged. `BMX_OLD_CHASE=1` = before. Plan next (agreed with the user): step 2 = the bike weaving under a still head on straights (also the rock twitch),
  step 3 = pull the bike up in the air on every jump (physics: more clearance = more air time), lip prep.
  Sliders: `cornerBody` (Ride > Body, deep-turn body share, 0.5) and `cornerCrouch` (Rider > Motion). **Step 2, weave**
  (`weave` 1, Ride > Body, `BMX_OLD_WEAVE=1`): a bike-only roll `_weave` (like `_bike_lead`, the body target never sees it) =
  0.22 rad x three slow sines (0.9 / 1.7 / 2.9 Hz) + 0.5 x the front-wheel knock, x speed (3 -> 10 m/s), fading past ~0.15-0.55
  rad of lean and in the air. Straight run: bike lean spread 2.0 -> 4.6 deg (peaks ~10 deg), body 1.6 -> 1.8, head roll rate
  0.04 -> 0.07 rad/s. Stress 56/56.
  **Weave removed again** (user: "the whole rider pivots, seasick, even not pedalling"): as a drawn bike roll it rocked the body
  too (the body rules read the total bike lean; then pivoting the drawn bike about the hips slid the tyres sideways over the
  ground). Off for good: only `BMX_WEAVE=1` turns the code on (no slider: a saved `weave` in tune.cfg kept it on after its
  default went to 0). A real weave needs the bike to steer along a snaking line. Hands-off straight coast now: bike lean spread
  1.6 deg (the pedal rock), head sideways 1.9 cm (`BMX_SWAY_PROBE=1`: `SWAY head_sd hips_sd`). **Berm lock-in** only while
  steering into the tilt, held `LOCK_HOLD` 1 s after letting go (`_lock_hold`): hands off down a hillside it fed a slalom.
  **Step 3, air tuck** (`tuckPull` 0.32 m, Ride > Jumps; `BMX_OLD_TUCK=1` = before): hop held in the air pulls the bike up into
  the body by `tuckPull` (was `legComp` x 0.85, ~0.25 m) on ANY jump, and the drawn tuck (`airPull` pose input) shows for a held
  tuck too (it was only after a timed pop). Measured, dtable_43 at 43 km/h: legs pulled 36 cm at the peak, wheels clear the
  ground 2-5 cm more than hands off (7 cm more than the old tuck); air time the same (+0.01 s): pulling the bike up can't
  change the shared centre of mass's flight, only clearance. Test rider `BMX_PG_PILOT_AIRTUCK=1` holds hop in the air.
  Stress 56 / 56. Not ridden by the user yet.
  **The tuck is normal jump behaviour** (same day, user: "no special move", Project X frames: their rider holds the bike up
  under him all flight, knees bent, pushes it down for the landing): every real flight (`air_k`) tucks by itself to
  `autoTuck` 0.7 of the full tuck, held, let down with `land_prep`; right stick back = all of it, forward = none (bike pushed
  away); hop held = all of it. `air_pull` follows a critically damped spring (SmoothDamp, exact step, half-life `tuckEase`
  0.09 s; was a plain lag with a speed jump at each change). Sliders Ride > Jumps: Tuck on every jump, Tuck smoothness.
  `BMX_OLD_AUTOTUCK=1` = before. dtable_43 hands off at 43 km/h: clearance 1.07 -> 1.18 m, air 0.88 -> 0.91 s, legs pulled
  19 cm at the peak; the tuck curve is one smooth bell (accel <= 26 /s^2). Body clip on a trail ride as before.
  **Visible preload into a lip** (same day, user: "I can't see the rider preloading with legs and hips"; `BMX_OLD_PRELOAD=1`
  = before): the drawn hips were held 8.5 cm over the saddle (saddle floor) whatever the preload, only 35 % of the legs'
  sink was drawn on any jump face (`FACE_SINK`, meant for slow steep dirt-jump lips: now only there, `fs_k`), and hands off
  the preload was cut the moment the auto pop waited for the edge (the deepest moment). Now: preload hips -0.17 m / -0.06 m,
  chest folded +0.22 rad, the saddle floor drops 0.14 x preload, all handing over to the drive as the legs extend (`j_ext`).
  dtable_43 hands off: crouch into the transition, stand tall off the lip, tuck in the air (`BMX_LIP_SHOT`). Body clip on
  a 50 s trail ride the same as before.
  **Body check (2026-11-27)**: `BMX_LIMBLEN=1` prints every 2 s each limb's drawn length vs its own (thigh, shin, upper arm,
  forearm, torso) and how far a hand / foot is off its grip / pedal. Limbs never changed length; the torso was let stretch to
  108 % (4 cm in every flight): now capped at 100 % (it only shortens as the back bends). In-air lay-over: the hips stay on
  the bike (counter x `AIR_HIP_SHARE` 0.3), the upper body turns about the hips (cap `AIR_CHEST_CAP`; the chest pivot put the
  hips ~0.4 m off the bike, legs straight; `BMX_OLD_AIRTILT=1`), stick lay-over `stickAirRoll` 1.25 -> 0.8 rad (Tune VER 34).
  Proportions vs a ~1.79 m adult: legs / shoulders were right, arms ~6 cm short, torso ~3 cm: `L_UARM` 0.31 -> 0.32, `L_FARM`
  0.29 -> 0.32, DH pose torso 0.5 -> 0.52 (RiderPanels POSE_VER 5 moves saves still at 0.5); `BMX_OLD_BODYSIZE=1`. Limbs are
  shaped tubes (`Rider.limb_mesh`, profiles `THIGH_PROF` / `SHIN_PROF` (calf at the back) / `UARM_PROF` / `FARM_PROF`), not
  cones; `BMX_OLD_LIMBSHAPE=1`. Not done: checking reach / stack against each frame's geometry.
- **Curbs / ledges: the rear rolls up, the tyres don't shiver at the edge (2026-11-24, user: "the rear always gets
  stuck on a curb")**. (1) `_step_move`'s edge check (at the bottom bracket) read the rise per physics step, so whether a
  curb was a wall at all depended on speed: at 6 km/h it never saw one (rolled up 30 cm), at 15 km/h a 20 cm curb was
  a dead stop + BONK, at 25 a SMACK crash. Now read over at least `EDGE_BASE` 6 cm, and once the front is up on top an
  edge up to `REAR_ROLL` 0.65 x the rear radius (~23 cm) is the rear wheel's to climb (the vertical step does it; too slow,
  it rolls back), taller is a wall as before. (2) `_wheel_ground` read the ground at 11 points 7 cm apart, so a square
  edge's corner jumped from point to point (rear tyre ground steps of 3.7 cm then flat): where the ground bends > `WG_EDGE`
  8 mm over three points it searches finer (+10 reads). `BMX_OLD_CURB=1` = both as before. Probe `BMX_PG_EDGE=1` (`PG EDGE
  feat= v_in v_min v_out stopped`, 2 = every step with the wheels' ground `hf` / `hr`), `BMX_PG_PILOT_RUNUP=m` (the test
  rider's run-up; curbs are 20 m apart, 30 m rides the one before). Suite vs `BMX_OLD_CURB=1`: drop_1 +1 energy check
  (+0.7 J/kg off the edge), gap_5 one bottom-out, curb_0.2 rear travel 81 -> 92 %; the baseline was already 7 runs stale.
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
  **The fit reads what is drawn (2026-11-25, user: "looks like we are floating a bit", manual on a bank)**: near the
  trail the drawn ground is the 0.25 m mesh with `micro_detail` (grain, potholes, ragged edge, rills), but the fit read
  the chunk's 0.5 m grid `G` and took max(smooth field, grid): the bike hovered over every drawn dip. Now the chunk
  keeps the fine heights (`fine_ground` returns `H` -> chunk `MG` / `MN`, `mesh_add` gets them) and `top_height` =
  the drawn mesh, even under the smooth field; a rock / log / deck sticking up out of the plain ground (height() >
  ground() + 1 mm) still counts. Same in C# `tyre_worst`. The physics still rides the smooth field. `drawn_height`
  = the same, whatever the switch; `BMX_OLD_TOPFIT=1` = before. Probe `BMX_GAP_PROBE=1` (`GAP <bank> <manual> <wheel>`
  lines: air under each grounded tyre vs the drawn ground). Seed 4242, follow rider holding a manual: rear tyre gaps
  > 1 cm 19 % -> 0 % of frames, worst 2.6 -> 1.1 cm (on banks too). Left: right after landings / rocks the lift eases
  down at `LIFT_DOWN` 0.6 m/s, so the tyre can hang a few cm for a moment.
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
- **Right stick side = the body, not the bike (2026-11-26, user: "leaning the stick also leans the bike, a double effect, it
  swings violently into the next corner", "make it like MX vs ATV")**. On the ground the side lean no longer steers
  (`flickSteer` 0, was 0.5 = half lock), no longer tips the drawn bike (`flickLean` 0, was 0.35 rad) and a flick no longer
  kicks the yaw (`flickKick` 0, was 0.16); Tune VER 31 resets those three in old saves (sliders still there, Ride > Body).
  It is a modifier of the left stick's turn: with it = tighter + grippier (`agree`, `flickGrip`), against it = wider
  (new `flickWide` 3 m/s^2 off the turn limit) + looser (`weightInside`). The deliberate throw + steer still starts the
  corner whip. Drawn (`rider.gd` `LAT_HIP` 0.06 / `LAT_CHEST` 0.22 / `LAT_DROP`): the rider's hips + upper body lean to the
  stick's side over the upright bike, also on banks (no `bank_sq` fade). The air is unchanged (stick lays the bike over /
  whips / spins against the body, as MX vs ATV). `feel=1` FEEL LEAN: stick alone yaw 0.66-1.1 -> 0.0; with the steer
  unchanged; against at 50 km/h 1.04 -> 0.85. `BMX_OLD_STICKBIKE=1` = before. Stress 56 / 56; demo AI 60 s no crash.
  Not ridden by the user yet.
- **Whip on the straight (2026-11-26, user: "whip on the straight whenever we want, for style points, glide over bumps, flowy")**.
  A deliberate throw of the right stick (centre -> edge within `FLICK_WINDOW`) with the steer centred starts the whip too
  (`_whip_straight`): the rear swings out to the stick's side (~16-20 deg, same `whipDrift` / slipMax cap), the bike tips
  ~12 deg, the travel stays on its line (course drift < 1 deg in 1.6 s). Held while the stick stays out (steer centred or the
  same way); eased in at `whipFlowIn` 2.5 /s and out at `whipFlowOut` 1.8 /s (flowy; the corner whip keeps 4 / 3). Held
  through skips under 0.3 s; held off any take-off (natural bumps too) it becomes an air whip (`whip_load` = 0.8 x whip:
  table_1.5 -> 60 deg in the air). While held the grip sim's bump nudges are x (1 - `whipGlide` 0.6 x whip_hold). Brought
  back straight after > 0.45 s and > ~9 deg: style "WHIP n°" / "BIG WHIP" (> 28 deg), 160 x time x angle x `whipStyle`.
  Size: `whipStraight` (x the drift and the whip's tip, 0 = off). Sliders Ride > Body > Corner whip. Test `BMX_PAD=1 BMX_BODY=swhip [BMX_SWHIP_HOLD=secs] BMX_TRICK=none` (`SWHIP`, `STYLE`
  lines). `BMX_OLD_STRAIGHTWHIP=1` = corners only. Playground washboard / rough / rollers at 35 km/h: no crash. Stress 56 / 56.
  Seen: a stick held through a whole flight lands sideways (the landing carve turns the travel ~36 deg) and, as the stick
  reaches the ground again, starts a new ground whip at once. Not ridden by the user yet.
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
  **Best shadows (2026-11-26, user: "a blurry shadow turns crisp right in front of the bike", "a long golden-hour tree
  shadow shows up at once", "fix all, make best shadows")**. Supersedes the cascade notes below. (1) High and Ultra get 4
  cascades (Low / Medium 2), each about 2.6x the one before: sharp to zoom + 18 m, then zoom + 47, zoom + 97, then the
  reach (`_shadow_fit`; `BMX_SHADOW_S1=m` scales them), blended. (2) High's atlas 4096 -> 8192
  (`Settings.apply_render_quality`; with 4 cascades in 4096 each got a 2048 quarter, softer than the old 2-cascade near map):
  the rider's shadow is now sharper than before (legs apart). (3) Far trees keep their shadow: the far backdrop's tree
  impostors (`FarHills` IMPOSTOR_SHADER) cast too, the card turned to the sun in the shadow pass, folded away past
  `deco_shadow.w` (shadow reach + how far CASTER_H throws a shadow at this sun height + the camera's offset + 30 m;
  set every frame by `Game`). The streamed trees' casters now hand over in the SAME 100-124 m band as the drawn ones
  (they cast 20 m further before), so each tree casts the shadow of the version you see, at any distance. Global
  `deco_shadow` (project.godot) in `shaders/deco_fade.gdshaderinc`. Cost (seed 4242 start, standing): primitives 6.3 M ->
  8.4 M, draws 1.14 k -> 1.54 k (all of it the 4 cascades; the impostor casters add ~0); GPU not measured cleanly (another
  game window was on the GPU), earlier quieter runs +0.3 ms. `BMX_OLD_SHADOWS=1` = all of it as before, `BMX_FAR_SHADOW=0`
  = no backdrop casters. Test aids: `BMX_ROUTE_BIOME=0..4` overrides the saved route biome (the user's route.cfg pins
  DUNE SEA: no trees), `BMX_PROF_AVG=1` now also prints GPU / RCPU / DRAWS_k / PRIMS_k. Not ridden by the user yet.
  **2 cascades at every quality (2026-11-24, `Game._two_splits`)**: with 4, everything near the camera (the rider + bike:
  409 of the 889 shadow draws) was drawn into 3-4 cascade maps. Now 2, the near one still ending zoom + 6 m (Low: + 12):
  shadow draws 887 -> 539, render CPU -0.15 ms, GPU -0.13 ms at the start, the 30 s follow ride 141 -> 156 fps; the
  rider's own shadow as sharp, mid-distance tree shadows a touch softer. `BMX_SHADOW_SPLITS=4` = before (what follows
  describes the 4-cascade fit), `BMX_SHADOW_S1=m` the near cascade's end. (Merging rider / bike meshes was looked at the
  same day, `BMX_MERGE_SCAN=1`: rider 73 -> 36 surfaces only by baking colours, bike 58 -> 50; ~0.1-0.2 ms for reworking
  the per-part grime pins and live kit colours: not done.)
  **Bike triangles (`BMX_TRI_SCAN=1`, `TRISCAN` lines)**: the DH bike is ~336k triangles and effectively has NO LODs: the
  glbs import with `generate_lods`, but `BikeRig` rebuilds the meshes from surface arrays (AO bake, decals, part swaps)
  and that drops them (only the helmet keeps its LODs). Biggest: frame 68k, steer 41k, rear wheel 23k, seatstay 20k,
  front wheel 18k, chain 33k (108 links x 304), fork lower 16k, rotors 9.6k each, cranks 9k. Rider ~30k.
  **Chain LODs (2026-11-24, `BikeChain._set_lod`)**: by the camera's distance to the chainring (as seen through a 75 deg
  lens): under `LOD_NEAR` 4.5 m the full links, to `LOD_FAR` 12 m light links (plates 4 segments, pins 4-5 sides, ~1/3
  of the triangles), past it one swept box-section band through the pins (~8 triangles a link, the chain ~33k -> ~0.9k).
  `BMX_CHAIN_LOD=0|1|2` forces one. The user models LODs for the frames / parts (plan: `<part>_lod1` / `_lod2` siblings
  in the glb, same pivots + surface names, an optional `frame_shadow` cast-only proxy); the wheels are code (WheelGen).
  **Sun shadows** (`Game._shadow_fit`): reach fixed by quality (`SHADOW_REACH` 100 / 140 / 170 / 200 m, fade from 75 %),
  never with the speed dolly; the 4 cascades end at zoom + 6 / + 22 / + 55 m (the sharp one covers the rider, not the
  empty air in front of the camera; it used to be fixed 6 / 18 / 45 % of an 80 m reach: shadows stopped ~70 m out and
  the rider sat in a coarse cascade). Golden hour bias 0.05 / normal bias 2.0 / blur 1.2 (was 0.08 / 3.0 / 2.0: mushy).
  Ultra atlas 8192 again. In the shadow pass trees keep casting to `DECO_FADE_OUT` + 20 m (low-sun shadows are long).
  **Rider / bike gloss that came and went (2026-11-23)**: (1) the rim light picked its side with `signf()`: with the sun
  near the view line every bend flipped it across the rider in one frame; now a smooth -1..1 and the direction eases
  (`_rim_dir`, slerp 2.5 /s). (2) the reflection probe re-captured every 30 m / 6 s and the paint / chrome / visor then
  reflected a different world at once: off in rides (`BMX_REFL_PROBE=1` brings it back); the sky's reflections stay.
  **Water** (`Grime`): `wet` = how high the water has got, drawn from the ground up by `grime_wet.gdshader` (ground =
  `grime_wf` axle - radius, top 1.95 m; dries top down), builds over ~3-5 s with speed; wet film roughness 0.32 / 0.1;
  washing is slow (mud ~10 s, dust ~4 s at 30 km/h); a wet bike collects no dust and mud no faster than a dusty one; no
  flying drips (`drips` never emits).
  **Dirt / water stay on the limbs (2026-11-23, user: "dirt sliding on limbs, water also")**: the wet pass now uses the
  mud pass's pinning (`grime_pin` / `grime_hrow` / `grime_r0` / `grime_r2`: where the point sat in the riding pose), so
  the water line and the drop columns stay on the leg / fork lower as it moves (they were worked out from where it is
  now and slid over the pedalling legs). Pinned parts measure the tyre spray and the ground line against the axles at
  pin time (globals `grime_wf0` / `grime_wr0`, `Grime._set_rest_axles`), not the live ones that move with the fork /
  swingarm. Parts rebuilt every frame (race number, strap tails, helmet flap, hair, braid: `Grime._is_flap`) get
  `grime_pin` 3: a cheap blotch mask from UV + `VERTEX_ID`, no dirt map. Test `BMX_WET_HOLD=0.45` keeps the bike that wet.
  **Blur while riding (2026-11-23, user: "it blurs stuff in front of our view ... only on the side, like NFS")**: the
  tilt-shift depth of field in rides now only softens the distance (far blur from 60 m, full by ~150 m, over the
  100-124 m decoration hand-over; distance haze from cam.dist + 55, density 0.7; no near blur; the title
  screen keeps its diorama focus), and the speed blur in `grade.gdshader` is only on the left / right sides of the
  frame (it was an ellipse round the rider that reached the trail ahead).
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
  stored in course order). **But the land can** (2026-11-26, F8 seed 13249: crashed rider "clipped through the world"):
  the relief layers fade in by the distance from the WHOLE trail (`trail_far`), so a grown trail changed the ground
  under chunks already built (one was drawn ~30 m above the physics ground). After adopting, `_restale_after_grow`
  restarts chunk jobs that read the old trail and queues every loaded chunk for `_land_check_step` (4 a frame: its
  0.5 m grid vs `ground()` at 7 x 7 nodes, > `LAND_REDO_TOL` 0.15 m = rebuilt; `_finalize` swaps the old chunk out).
  Normal rides: 0 rebuilt (seeds 4242 / 5 / 13249). `BMX_GROW_PROBE=1` prints it, `BMX_OLD_GROWLAND=1` = before. Chunks read rocks / stakes / fences from per-chunk buckets, route features are
  binary-searched — nothing scans the whole course. `tools/trail_grow_probe.gd` checks all of it.

- **Route spine: the world runs any way, not along +x (2026-11-25, user: "use the landscape, really wavy, we have a square
  map, sometimes go back, not uniform")**. `world/route_spine.gd` (`RouteSpine`): a 2D polyline every 20 m that the whole
  world is laid out along. Everything that was x / `|z - zc(x)|` is now s (along the spine) / |d| (across it): the first
  mountain, its pitches, the later ranges (`range_at(s)`), `mtn`, `hill` (`hill_top(s)` = the height on the spine's middle),
  the trail's corridor (`TrailCourse._off/_rel/_sp`), the course length `_L`, `end_s()`, section ends, and growth
  (`Terrain._update_grow` reads the rider's spine s via `TerrainField.spine_near`). Walker (GDScript only, C# copies the
  arrays): straight +x from s -636 to 150 (s = x there: the start / title spot unchanged), then it heads for random
  waypoints 1.2-4 km away (up to ~112 deg off its heading, inside |z| < `ZMAX` 7 km, at most 3.5 km back west of its
  furthest east, a straight line to it clear of its own legs, the most open of 24 tries), with a random-walk wobble
  (+-0.8 rad); each step picks of 9 headings (1.5 deg notches) the one that fits the BARE land best (`TerrainField.bare`:
  landform without mtn / hill): not climbing into hills, not straight down a steep fall line, not over cliffs / into lakes,
  >= `GAP` 1.1 km from its own legs older than 1.6 km. Grown with the walker's saved state (`grown`), built `SPINE_AHEAD`
  4 km past the course. Land query `spine_sd(x, z)` -> `r_s`, `r_ad`: bilinear over an 8 m lattice of exact nodes; a node's
  s is a weighted blend of every segment within `R` 450 m (w = (1 - d^2/R^2)^2 / (d^2 + 25)), so s never jumps on the
  inside of a bend; |d| is the true distance (nodes cached per field instance, cleared in `_reset_caches`). Mirrored in
  `TerrainFieldCs.spine_sd/_sp_node` (same op order): `terrain_cs_cmp` heights EXACT (only the C#-only fine-mesh chunk
  arrays differ, as before). Measured over 16 km of course: seeds 4242 / 5 / 12 cover 11 x 7, 10.6 x 7.5, 15.5 x 8.5 km,
  heading -x 11-35 % of the way, legs >= 1.04 km apart; 40 m stretches over 15 % grade 2.6 % (old 1.9 %), steepest the
  same (drops apart). Demo AI 120 s on 4242 / 5: no crash, 135-145 fps. `BMX_OLD_ROUTE=1` = the old straight corridor.
  Map: `-s res://tools/trail_map.gd -- out.png [seed] [course m] [m/px]`. Tests `BMX_TRAIL_FEAT=s<m>` (was x<m>) = that
  far along the trail. Not changed yet: `biome_probe`, `land_probe`, `route_grade_probe` still sample round the old zc.
- **No ledges between sections, the ridden line worn smooth (2026-11-26, user: "little steps / ledges on the road ruin our flow",
  "the perfect line must be smooth, the mesh is wavy in banks", "more randomness in the bumpiness and the groove depth")**.
  (1) `TrailCourse._shape_profile`: the rolling dips (ROAD only, up to +-1.8 m) and grade reversals (+-0.6 m, not on jump /
  rocks / start / finish) were switched per 2 m point by section kind: a 0.5-1 m step wherever the kind changed. Now their
  weight is `_fade_mask` (0 / 1 mask shrunk then averaged over 6 points: still 0 on every excluded point, ramps over ~24 m).
  `BMX_OLD_LEDGES=1` = before. Probe `-s res://tools/road_step_probe.gd -- [seed] [m]` (`STEP` = slope change > 0.25 in
  0.5 m along the centreline, `BANKUP` = trail > 3 m above the land 14-28 m out on both sides, `ROADSUM`): off-jump kinks on
  seeds 4242 / 5 / 12: 3 / 9 / 2 -> 0 (what's left is jump lips). (2) `base()` (GD + C#, physics too): the 1.5 / 3.4 m trail
  bumps are x (1 - 0.8 wear) (`wear` = 1 within 0.35 m of the ridden line, 0 by 1.5 m; they used to be BIGGER on the line), x a
  60 m noise `rf` 0.25..1.75 along the route; the worn groove's depth 1.5..6.5 cm by a 95 m noise (was 3.5 cm everywhere).
  `micro_detail` (drawn mesh): grain + bank rills x (1 - 0.85 / 0.9 wear) x rf, potholes x (1 - 0.6 wear). Off the line
  unchanged. `BMX_OLD_WEAR=1` = before. Probe `-s res://tools/wear_probe.gd -- [seed] [m]` (bumps along the line vs 1.2 m beside
  it, jumps left out; ~4.5 mm of it is the probe's chord over curved berms, not bumps): line 6.1 -> 4.9 mm (4242), 6.0 -> 4.5
  (5), the smoothest 10 % of 50 m stretches 1.3 -> 0.9 mm. terrain_cs_cmp heights EXACT, trail_grow_probe PASS, demo AI no
  crash. Tried and dropped: Catmull-Rom between the 2 m course points (smooths the whole trail, user: only the line; no gain).
  **Raised road fixed (same day, user: "a road 10 m higher than the land with a fall each side")**: `road_step_probe`
  BANKUP showed every raised stretch was a ridge-and-cliff drop (`TrailCourse.drops`): only the trail was lifted 3-6 m, the
  land beside stayed (a causeway; its side drawn as a grey rock wall). Elsewhere the trail sits on the land (seed 4242 0.1 %).
  Now `TrailCourse.DL` = each point's lift, the field keeps `cDL` + `c_drops` (first / last point + bbox per drop, built in
  `_bind_course`, copied to C#), and `base()` adds `_spur(x, z)` before the bench: the nearest drop point's lift x (1 -
  sm(3, SPUR_R 36 m x (1 +- 0.25 noise), distance)): the land rises into a spur you ride along and drop off the end of.
  BANKUP 2.7-4.2 % -> 0 on seeds 5 / 12 / 2. GD + C# identical (`-s res://tools/spur_cmp.gd -- seed`: 46k points over the
  spurs, 0 mismatches), terrain_cs_cmp heights EXACT, trail_grow / rope_find PASS, wood walls=0. `BMX_OLD_SPUR=1` = before.
  Not done: the general cut / fill cap (the trail's 120 m smoothing has no limit, but measured it doesn't leave the land >3 m
  outside drops), a cut through a crest (trench) isn't measured. Seen: seed 12 s ~2230-2300 is a jump line climbing ~8 m out
  of a lake-level flat; the demo AI crawls up it at ~5 m/s and with the new ground sometimes stops on it (chaotic, the
  ground there is the same to 2 cm): a layout issue (uphill jump lines), not fixed. `tools/profile_probe.gd -- seed s0 s1 ds`
  prints the centreline ground.
- **Jumps only where builders would put them (2026-11-26, user: "no jumps uphill, check what other rules riders have when
  laying tracks")**. `TerrainField._build_route` skips a built jump slot (it slides on 10 m and tries again) unless: the trail
  from 15 m before the lip to the landing's end climbs <= `UPHILL_MAX` 1 %, riders arrive at >= `SLOW_K` 0.85 x the smallest
  size's design speed, no bend tighter than `JUMP_STRAIGHT_R` 60 m in the `RUNIN_T` 1.5 s before the lip or the `RUNOUT_T` 1 s
  after the landing, no crest over the sight line in the 25 m before the lip (`BLIND_H` 0.5 m) (`AIR_TYPES`, `_jump_site_why`,
  `REJECTS` counts them; `BMX_REJ_PRINT=1` lists uphill skips). Layout (`TrailCourse`): `RUNIN` 20 m / `RUNOUT` 16 m straight
  round jump runs (were 4-10 / 6-8), jump lines not laid where `_land_rises_ahead()` (land 120 / 240 m along the heading climbs
  > 0.5 %) in both pickers, past the mountain a jump line is picked a bit more often on falling land (0.45, was 0.3), road
  jump slots tried every 45-105 m (were 70-160). `BMX_OLD_UPHILL=1` + `BMX_OLD_RUNIN=1` = before. Every world's route features
  change. Measured, 5 seeds (`-s res://tools/uphill_jump_probe.gd`, `-s res://tools/trail_rules_probe.gd`): before 44 jumps, 14
  of them on climbs (up to 14 %, riders arriving at 10 km/h), 4 with a bend in the run-in, 6 landing into a bend, 5 blind lips;
  **Jump zones** (same day): `TrailCourse._fall_heading()` = of headings within +-`FALL_SPREAD` 0.7 rad (and 1 rad of the spine)
  the one the land falls most along over 150 m (never rising > 0.6 m between 50 m samples, >= 0.45 m in all; NAN = none);
  `_jump_line` turns onto it and runs 110-170 m (was 80-130); both pickers lay a jump line only when one exists; on a
  mountain's descent jump lines are ~22 % of the sections (were 8 %); short jump runs (< 120 m: flow trails) start on the
  release beat (rollers left no room). Skinnies only where riders arrive under `SKINNY_VMAX` 8 m/s and `SKINNY_GAP` 25 m after
  the last feature (one 10 m after a kicker's landing: the demo AI hit it, seed 31). Now 30 jumps on 5 seeds, every rule met
  (seeds 5 / 12 climb the second mountain most of their first 4.5 km: few jumps, correctly). Demo AI seeds 31 / 4242 / 2: no
  crash. The crash note in the session log now ends `at=x,y,z`. Probes: `jumprun_probe.gd -- seed` (each jump run: grades,
  what was built), `spot_probe.gd -- seed x z` (what is on the trail near a spot). Other rules measured, not done: hard
  braking zones (~1.2 per km, e.g. 48 -> 10 km/h in 30 m before hairpin stacks), ~17 % of the trail steeper than 8 % and than
  half the hillside (IMBA half rule), ~450 m in 20 km steeper than 15 % over 50 m, no outslope on straights, trail can run at
  lake level (wet flats), no clear zone checked on the outside of fast bends / landings.
- **Flow rules in the trail's layout (2026-11-25, Phase B, `trail_course.gd`)**. While laying out, the turtle keeps an
  estimate of a rider's speed (`_v`: the land's fall in, rolling + air drag out, pedalling when slow, capped by every bend
  at `A_BEND` 9.4 m/s^2; `_emit` reads `landform` per point). (1) Road bends never tighter than v^2 / A_BEND (a tight one
  waits for a slow stretch). (2) Every arc of 4+ steps eases in / out: its curvature ramps over m = 25 % of it (max
  `CLO_MAX` 6 steps = 12 m) and m steps are added so the peak radius stays R (clothoid-like: no straight-to-arc corner).
  (3) Road bends alternate side (75 %, `_lt`) and the next one comes 1.5-3 s on at `_v` (15-70 m). (4) Grade reversals:
  on descents steeper than ~3-7 % a 0.3-0.6 m dip-and-rise every 25-45 m (`_shape_profile`, phase summed from the start:
  growing never changes it). (5) Switchbacks / hairpin stacks only where the hillside across the trail is steeper than
  10 % (`_side_slope`), else plain road. `_snap` / `_undo` / `grown` carry `_v`, `_hv`, `_lt`. `BMX_OLD_FLOW=1` = before.
  Probe `-s res://tools/flow_probe.gd -- [len] [seeds]` (old vs new: `FLOWBRAKE` bend braking / climbing per km, curvature
  steps, alternation, dips per km). Measured 10 km: curvature steps (99th pct) 40-45 -> 15-19, bend braking 2.2-3.5 ->
  1.7-2.4 m/s per km, dips 9 -> 12 per km. Demo AI 125 s seed 4242: braking 15 -> 13 % of the time, slide scrub -206 ->
  -95 J/kg, avg 46.4 -> 46.9 km/h, max 59 -> 63, no crash. Grow / rope / wood / C# probes pass. Not ridden by the user yet.
- **Forest singletrack + tall forest (2026-11-25, Phase C part 1, user reference shots: a narrow trail cut into a wooded
  hillside with tight high berms; a big berm wrapping round a tall trunk; "taller trunks, leaves start later, don't cover
  the cam")**. New kind `TrailCourse.FOREST` = 7 (`WIDTH` 0.35 half-width = a ~0.7 m trail (user: "could be even narrower"), `BERM` 1.8; FOREST counts as "not road" for RD,
  drops, billboards, arches). Section code 7 `_forest(end_s)`: alternating 70-140 deg turns at 6-10 m radius, 5-14 m legs.
  Picked past the first mountain where `_forest_here()`: `b_forest` > 0.45, the hillside across > 3 %, 250 m+ after the
  last one, 70 % by a hash of s (seeds 4242 / 12 get some in 12 km, seed 5 none). No tape along it. Berm rim close in for
  narrow trails: `berm_style` `bs_F` floor min(2.0, w + 0.75) (GD + C#; every other trail kind unchanged). Bend trees
  (`TrailCourse._plan_bend_trees` -> `bend_trees` / `chunk_btrees`; `TerrainChunkBuilder._bend_trees`): a big old pine on
  the inside of local curvature peaks under 22 m radius on FOREST (75 %) and on road / esses bends in pine forest (35 %),
  W + 1.6..2.8 m in (at most 0.7 x the radius). Trees beside a forest singletrack (`fe`: within QR of a FOREST point):
  density 95 %, trunks allowed from W + 0.9 (~1.25 m from the line: at W + 0.55 the demo AI clipped trunks), always pines, crowns overhang. **Tall forest pines** (`fe` or `b_forest` >
  0.5): bare trunk to `TALL_CROWN` 6.5 m+ (sc x 3.2, + 0-3 m), crown up there, 15 % bigger; bend trees 8.5 m+.
  Test `BMX_TRAIL_FEAT=forest` (30 m before the first FOREST point; seed 12 has one at x 3544). Demo AI rides through it at
  ~45 km/h, no crash. Not ridden by the user yet. Narrow trails look narrow: `trail()`'s dirt fade is min(1.2, 0.35 + q_w) m (GD + C#; 1.2 for every trail >= 0.85 m half-width, as before), and the chunk bake writes how narrow the trail is (`T5` = clamp(1.6 - q_w): trail3_tex B, now RGBA8; level terrains' RG8 reads 0), which scales the ground shader's and the road-detail bake's ragged-edge wander (x 0.2) and fade (x 0.35..1). Big bend trees get 4 stones round their roots on the side away from the trail.
- **Flow jump trails, grown tree roots, tidy roadside boards (2026-11-25, Phase C part 2)**.
  (1) Flow jump trail (`TrailCourse._flow_trail`, section code 8, via `_jump_pick`: half the jump-line picks past the first
  mountain, by a hash of s): bermed ESSES turns (16-24 m) linked by 36-60 m JUMP runs, which `_build_route` fills with its
  rhythm beats (rollers / a speed-sized table or kicker / rest). `flow_starts` = where each starts; test
  `BMX_TRAIL_FEAT=flowtrail` (seed 12, 4242 have one). Demo AI lands the built jumps on their landings.
  (2) Roots across forest singletracks, grown (user: "spread splines along the terrain with root math, a simple sweep that
  follows the terrain, a smart rooting system", "no poking"). `TrailCourse.roots` = spots every 6-13 m of FOREST
  (`chunk_roots`); `TerrainChunkBuilder._root_system`: a pine 2.6-3.8 m off the trail (outside of tight bends, +1 m
  there), 4-6 main roots out of its foot (2-3 across the trail, long enough to reach the far side), each a random walk with
  a smoothly wandering curvature (`_grow_root`, 12 cm steps), tapering, branching (prob 4.5 % a step, two levels);
  `_sweep` = a 7-sided tube along each path with every ring ON the ground under it (turned to the ground's slope, top
  0.4-0.75 x its radius proud, flaring at the trunk, + 3.5 cm for the drawn ground's micro detail). All roots of a chunk
  are one mesh (`out["roots"]` -> `Terrain._finalize`, material `root_world` = bark_pine along the root via UV:
  `deco.gdshader` `bark_uv`). Where a root crosses the trail: low domes (<= 7 cm, r 0.2) the tyres feel. Earlier instanced
  root meshes (`TerrainGeo._root_mesh`, list `root`) are still built but unused. Trees / stumps / logs beside a FOREST
  trail keep `_forest_clear()` = W + 1.3 m (W + 1.6 in bends tighter than 25 m; the check was inverted at first and the
  narrower dirt fade let trunks in at ~1 m: the demo AI went over the bars). 5 seeds' singletracks: no crash.
  (3) Billboards / distance signs (user: "overlap with signs and fences, boards on slopes clipped"): `_sign_spot_ok` /
  `_sign_spot_why` checks 5 points along the board's width: dry, off jumps, off the trail and >= W + 2.4 m out (the tape
  line), >= 0.9 m from any fence / tape collider, not in `blocked`, ground within 0.45 m along it and 0.5 m front to back.
  Planks sit over the highest ground under them; each board / sign reserves its spot in `blocked`. Seed 4242's first 6
  boards: 4 placed (2 had no clear spot). `BMX_GATE_PROBE=1` prints `SIGNSPOT no: <why>`.
- **Wooden drop + skinny in jump lines (2026-11-25, Phase C part 3)**: Wood kind 4 `woodDrop` (GD `TrailFeatures.Wood.top`,
  C# `TfWood.top`): a plank ramp eased up over 5 m to a 1 m deck, deck to u1 9 m, square end (`back_wall`), you drop onto
  the ground (profile `Flat` 14 m; `AIR` 9 .. 12.5). `TerrainField.RHYTHM`: release beats can be a woodDrop, rest beats
  a north-shore `skinny` (19 m, 0.66 m wide, 0.85 m up; it rarely fits a rest beat: 0 in 12 worlds x 4 km, woodDrop 3).
  Demo AI speeds `DemoPilot.FEAT_V` woodDrop 7, skinny 5.5 m/s. `BMX_TRAIL_FEAT=woodDrop` (seeds 2, 31, 123; also
  `skinny` / `woodKicker` / `bridge`). C# compare / wood_edge_probe unchanged. Not done: wooden berms, a wallride
  (the height-field physics can't ride a vertical wall), line choices + difficulty colours.
- **A / B line choices (2026-11-25, Phase C part 4)**. `TerrainField._build_alts` (end of `_build_route`): about 70 % of
  big built features (`ALT_TYPES`: table, kicker, tableLine, woodDrop, double, doubleLine, flow, woodKicker; by a hash of
  s) get an easier B-line: it leaves the trail `ALT_IN` 22 m before the feature, swings out (half + 4.2..7.2 m, smoothstep
  over 12 m at each end) to one side and joins again `ALT_OUT` 18 m after, at the trail's own height `cE` (no jump).
  Flat arrays `alt_pts` (x, z, height) / `alt_lines` (first, count, bbox + `ALT_REACH`, side) / `alt_feats`
  ([route feature, line]); `alt_near` / `alt_dist`. `base()` levels the ground to it (x (1 - q_mask): the main bench
  wins), `trail()` makes it dirt (half-width `ALT_W` 0.9). Mirrored exactly in `TerrainFieldCs` (`alt_near`,
  `alt_dist`; `alt_feats` public for the chunk builder, which may run on the C# fork): terrain_cs_cmp unchanged,
  trail_grow_probe PASS. Chunk builder: tape stakes and course fence posts within 1.2 / 1.6 m of a B-line are left out (a
  gap where it leaves / joins); `_line_signs` puts two table signs 6 m before the split, beside the trail past the tape on
  the B-line's side: black A LINE + the feature (TABLE / KICKER / DROP / JUMP LINE), blue B LINE EASIER (`_table_sign`,
  the distance sign's build). 5-11 B-lines per 4.5 km (seeds 4242 / 5 / 12 / 2). `BMX_OLD_LINES=1` = none. Not done:
  difficulty colours per trail section, a HUD alert at the split, B-lines round drops off cliffs / gorges, the demo AI
  never takes the B-line. Wooden features' planks now use the fences' material + ranch colours (user).
- **Bark scans on standing trunks (2026-11-25, user: "good light trunk texture, realistic", "use all")**: three CC0 scans
  in `assets/textures/bark/` (1K colour / OpenGL normal / roughness, VRAM-compressed with mipmaps; `SOURCE.txt`):
  `bark_light` (ambientCG Bark004, light grey-tan), `bark_pale` (ambientCG Bark007, birch-like), `bark_pine` (Poly Haven
  Pine Bark, reddish). `deco.gdshader` `bark` path: u round the trunk in whole tiles (count from the instance's girth:
  no seam), v up it, `bark_tile` 0.8 m, gradients from whichever cut is away from the pixel (no mip line at atan's
  jump), normal map in a world round/up frame (`bark_relief`). Materials `TerrainGeo._bark_mat`: `trunk` = light,
  `trunk_pale`, `trunk_pine` (lists in `Terrain.LIST_SPEC` / `TerrainChunkBuilder.LIST_NAMES`); logs and sticks lie down,
  so they keep the plain `trunk_plain`. Which: pines 45 % pine bark / 55 % light, broadleaf 60 % pale / 40 % light, snags
  pale, savanna + bend trees light. Not measured: GPU cost of the extra 3 samples on trunks (two more draw lists a chunk).

- **Start on a big peak, ride down (2026-11-26, user: Riders Republic screenshots, "very steep mountains, vast", "we always start
  on peaks", "and descend, this game is downhill")**. `TerrainField` (C# mirrored, `BMX_OLD_PEAK=1` = the 105 m / 1.4 km
  mountain): `HILL_TOP` 450 m, `HILL_LEN` 2.8 km, `PITCH_N` 9 pitches x `PITCH_K` (5-8 m each), the descent profile concave
  (0.65 linear + 0.35 (1 - (1 - t)^2): ~22 % from the start easing to ~10 %), `RANGE_X0` 3.5 km. The peak is a **massif round
  its ridge line** (`_massif`): ridge points every 40 m of the spine from s 0 to `HILL_LEN` + 150 (its own nodes), each a cone:
  `MASSIF_CREST` 45 m flat, then a concave fall top x (1 - t)^1.5 over 150 + 2.2 x top m (+-25 % by a noise along the ridge:
  spurs, gullies); the land is the highest cone. (A first version read the spine's s per point and spread the flank to ~1.4 km:
  past `RouteSpine.R` 450 m s jumps between legs: 260 m walls in one 20 m step, and growth changed built land.) Later ranges
  as before. Snowline `SNOW_H` 280 m in `color_post` (+-25 m noise, patches that join toward the summit, not on > ~40 deg,
  none on dry land). Peaks of the relief layer: rounded crests (smooth |n|) + the fine octave 0.45 -> `RIDGE_K2` 0.2
  (`BMX_OLD_RIDGE=1`): the user saw wall-like faces (main, seed 34229 x1873): > 50 deg cells in a 3 km square 20 -> 6.
  Bridges / rope bridges / skinnies only on trail flatter than `FLAT_MAX` 8 % (a gorge bridge on 25 %: "hit the cliff").
  Fence gates: each side of a run has its own random stream (`plan_marking`): drawn from one, the first side's gates used as
  many numbers as the run is long, so growing the open last run moved the other side's fence (`trail_grow_probe` FAIL).
  Measured (`tools/peak_probe.gd -- seed`: summit, trail height every 200 m, steepest 50 m, flanks; `tools/wall_probe.gd -- seed
  x z r`: > 50 deg cells and which layer): trail 449 m -> ~40 m over 3.2 km; > 25 % 50-370 m per run; walls round the start
  seed 12: 648 -> 0. terrain_cs_cmp EXACT, trail_grow / rope_find PASS, wood walls=0, spur_cmp 0.
  **Land Lab knobs (same day, user: "keep the previous mountain, adjust from this to our previous in the world editor")**:
  group **Start peak** at the top of Land Lab (`LandParams` `start_peak` 0..1, `start_top` 105..800 m, `start_len` 1.4..4.5 km):
  0 = the previous mountain exactly (same numbers as `BMX_OLD_PEAK=1`), 1 = the big peak, between = a blend (`hill()` mixes the
  old cross-section with the massif, `hill_top` the two descent profiles, `HILL_TOP` / `HILL_LEN` / `RANGE_X0` / pitches
  lerped; `START_K` + those three handed to C# through `land_get`). Saved in `data/land_params.json` like every knob;
  `BMX_LAND=start_peak=0.5,start_top=600` for tests. terrain_cs_cmp EXACT (also `BMX_MESH_K=1`) with default and a blend.
  **Open**: (1) speed: the trail's design speed (`TrailCourse.VA`, which sizes the jumps) is free rolling, ~80 km/h on these
  grades; the demo AI goes over the bars at 70 km/h where a flat stretch drops into 33 % (seed 4242 s 538) and slams out of a
  berm (s 890): riders must brake on big descents (cap VA, demo AI braking, brake zones before steep pitches). (2) From the
  summit the far land's end shows as a flat band on the horizon (`FarHills` ~2.6 km): push the far rings out. (3) After the
  bottom the world still climbs the next ranges (4.2 %): the user's call (a lift to the next peak? endless descent?).
  (4) Snow reads uniform white on the summit plateau. Not ridden by the user yet.
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

- **Land shaping v3 + climate biomes + smart siting (2026-11-25, `docs/research/terrain_generation.md`)**. Research first (4 researchers: stateless
  noise, hydrology / simulation, industry talks, biomes): simulation erosion (stream power, tile erosion) breaks the per-point contract, so the land
  stays a pure function and gets smarter in place. `TerrainField.landform` (mirrored in `TerrainFieldCs.landform`, `terrain_cs_cmp` EXACT):
  (1) **macro controls**: two 2.6 / 1.8 km noises through `spl()` (piecewise smoothstep knots) scale the detail amplitude (plains .. rough) and the
  big-relief weights (regions you can tell apart); (2) **domain warp** of the 28 / 90 / 240 m octaves + the ridge term by a 170 m noise (`LAND_WARP`
  38 m x calm); (3) **gradient-damped detail** (Quilez): `noise_d` (value + analytic gradient in `_ndx` / `_ndy`, matches finite differences to
  6e-9, same lattice as `noise`) gives the slope of the 240 m octave + ridge term and the 90 m octave, which damp the detail (`LAND_DETAIL_S`,
  `LAND_FINE_S`) and soften the steepest relief (`LAND_TALUS`); (4) **valley floors** from a 420 m control noise (`LAND_VALLEY_*`); (5) **strata**
  in the rugged biome on sloping ground away from the trail (`LAND_STRATA*`: height pulled toward smooth 3.2 m steps). `BMX_OLD_LAND=1` = the
  original land. Every world's trail / lakes past the first section are laid out differently. Probes: `tools/land_probe.gd` (slope / height stats old
  vs new), `tools/land_map.gd` (shaded-relief map old | new), `tools/noise_d_probe.gd`. Measured: >25 deg ground -25 % on seed 4242, flats +2..6
  points, results vary by seed (the regions differ). Not measured: height-call cost (a few extra noise reads), ridden feel.
  **Climate biomes** (`TerrainField.biome()`, C# mirror; probe `tools/biome_probe.gd`, C# vs GD EXACT + shares per name): the old `b_dry` / `b_rug`
  axes are unchanged; five new 0..1 weights from altitude-proxy / moisture / forest / patch noises (never the real height: the land is shaped by
  the biome, a height-driven biome would be circular): `b_cold` (Alpine Peaks), `b_wet` (Wetlands), `b_forest` (Pine Forest), `b_sav` (Savanna),
  `b_ash` (Ash Fields); a pinned RouteStyle biome keeps the old axes only. Shares over 6 seeds: alpine 8 %, forest 14 %, wet 6 %, ash 3.5 %,
  savanna 4 %. Ground colours (`color_pre` / `color_post`, palette `needle marsh savanna frost ash ashLight`; `color_post` takes `cold` / `ash`,
  `pre_b` has stride 4), snow lower with `b_cold`, no grass on ash (`DRY`). Decorations (GDScript `terrain_chunk_builder.gd`, not mirrored): dense pines
  (forest), thin trees (alpine / wet / savanna / ash), flat-crowned savanna trees (`SAV_LEAVES`), reed tufts (`REEDS`), golden grass clumps, dead
  snags + dark rubble on ash, more rock on alpine / ash. Not done: biome-specific height shaping (wetland flats, volcanic craters), wet / mud surface
  grip, new meshes (acacia, reeds are the existing grass mesh scaled), area-banner art per biome.
  **Smart siting** (user: "tables clip next to a steep hill"): measured with `tools/feat_site_probe.gd` (ground beside each jump's footprint vs its
  plane): trail route jumps were fine (rise max 1.3 m: the trail bench), the **free-ride jumps out in the land** (`jump_at`) had 10 % with a
  hill wall > 2 m (max 5 m). `jump_at` (GD + C# `_jump_at`) now skips a site whose ground at half + `SITE_SIDE` 3 m from the axis rises > `SITE_RISE`
  1.3 m or falls > `SITE_DROP` 1.8 m against the plane, either side, at 11 spots: 3272 -> 2296 candidate sites, max rise 1.36 m.
  `BMX_OLD_SITING=1` = no check.
  **Fence + tape no longer side by side (2026-11-25, user: "fence and tape both beside the road look weird")**. Measured with `tools/tape_fence_probe.gd`
  (stakes within 4 m of a course fence post: ~18 a seed, 110 over 6 seeds): the start / finish picket fences were not counted as fenced for the
  tape (`plan_marking` only marked the ranch fences, and only on ROAD runs), and a ranch fence's gate gap let a short piece of tape in. Now picket
  fences mark their side too, the gate gaps are marked, and any fenced side gets no tape (`TrailCourse.OLD_MARKING`, `BMX_OLD_MARKING=1` = before):
  110 -> 1. The random **wild fences** along side paths (`_trail_fence` -> `_run_fence(.., wild)`) keep `WILD_FENCE_CLEAR` 6.5 m off the road's edge
  (`_post_ok`), where the tape and course fences are. `trail_grow_probe` PASS (marks unchanged by growing). Not measured: how many wild fences
  that removes (they are built per chunk).
  **Berm v2 (2026-11-25, user: pebbles / rock on the edges, a grass lip, hollows worn into the lip by whips, tilted vs curved styles, "a good formula")**.
  `TerrainField.berm_shape2` + `berm_style` (C# mirror, plain + * / - `sm()` only, no exp / log; `terrain_cs_cmp` EXACT; `BMX_OLD_BERM=1` = old). Cross-section
  by the distance o from the centreline: entry (slope 0 -> tn = tan(bank), unchanged), FACE with slope tn to 0.9 m (so the racing line rides exactly the bank the
  course asked for: `berm_probe` asked 22.4 deg, on the line 22.1 deg, old 21.7) then steepening by up to (1 + c) x tn to the rim at F (c 0 = tilted plane ..
  0.75 = curved bowl: riders pick their height by speed, the physics bank = banked-turn tan(bank) = v^2 / (g R) as `TrailCourse._bank_need`), a rounded CAP of width
  cw (crisp 0.3 tilted .. 0.8 bowl), a back slope falling to the ground over clamp(rim / 0.6, 2, 5) m (the old shape faded over 6 m with no defined rim), a LIP roll
  on the rim (`bs_lip` up to 0.18 m on some berms: it sits at the trail's own width + 0..0.8 m, where the dirt fades to grass: the grass lip) and SCOOPS (`bs_scoop` up to
  0.5 m, short stretches of some berms: the hollow worn into the lip). Style per arc length `q_s` from noises (period 70 / 45 / 90 / 130 / 11 m), side-path berms
  from position. Rim pebbles / the odd rock: `_berm_clutter` (chunk builder, GDScript, `berm_style` gives the rim). Seen: relief maps `tools/berm_map.gd` (old | new: a
  defined rim and back slope, contours); NOT seen cleanly in game (the follow rider leaves the trail at spawn, photo mode was blurred), lip / scoop / pebbles are
  unchecked by eye. Demo AI 100 s seeds 4242 / 5: no crashes, same distance as old. Constants are the tuning knobs (`berm_style`, `berm_shape2`).
  **Finer ground mesh near the trail + micro detail (2026-11-25, user: "too low poly, peaks smoother", "finer around tracks where we have peaks", "more details and
  imperfections")**. The chunk's texture grid stays N = 96 (0.5 m; `GrassField.SEG`, textures, `G` for the tyre fit all keep it), but chunks within `MESH_NEAR` 60 m of the
  trail (`route_dist`) get a **0.25 m base mesh** (`TerrainFieldCs.fine_ground`, `TerrainChunkBuilder.MESH_K` 2, `BMX_MESH_K=1` = as before; needs the C# field): the old 0.5 m
  grid is its first LOD (`_ground_lods(.., n, mk)` keys 2 / 4 / 8 / 16 by real error), so flat or far chunks cost what they did. Measured once (stationary rider, seed
  4242 x3150): triangles / frame 4.45M -> 5.19M (+17 %), fps in the noise; the LODs may not drop early enough (tuning left). **Micro detail** (`micro_detail`, DRAWN ONLY, a few cm,
  fine mesh only, `BMX_NO_MICRO=1` = off): 0.3 / 1 m grain near the trail (the 0.75 m washboard ripples in bends were removed 2026-11-25:
  finer than the 0.25 m mesh, they aliased into ~2 m stripes across the trail; detail under ~1 m belongs in the shader's normal, not the mesh), a pothole / washout on the road in some 37 m
  stretches (hash), ragged dirt edge, rills down banked faces. The physics + tyre fit read the smooth ground, so a tyre can sit up to ~3 cm off the drawn surface. Berm rim
  rounded too (cap 0.8..1.4 m, lip 1.1 m half-width, back slope 2.5..6 m). Not re-checked: C# vs GD EXACT after the rim rounding, the rim's shadow edge up close.
- **Baked road detail, racing-game style (2026-11-25, user: "racing games' roads look so nice, ours fades in a lot")**.
  `world/road_detail.gd` (`RoadDetail`, made by `Game` for rides + built levels, not the title / playground) + compute
  `shaders/road_detail_bake.glsl` / `road_detail_mip.glsl`. The trail's marks (ridden lines, prints, stray lines,
  playful marks, skids, damp / puddle masks, grit, the worn relief) were per-pixel maths in ground.gdshader, switched off
  by pixel size (`gpx`) before they aliased: a ring of detail followed the camera. Now they are baked once per texel
  into a **clipmap**: 4 camera-following windows (cells 1.25 / 2.5 / 7.5 / 18.75 cm = 12.8 / 25.6 / 77 / 192 m at 1024²),
  world-aligned + toroidal (sampled with repeat; moving a window only bakes the 64² tiles that came in), each tile
  supersampled (2² / 3² samples) with every mark filtered to the sample spacing (`lineaa`), its own mips (64 -> 1). The
  ground shader (`vt` path) reads the finest level that holds the pixel with anisotropic `textureGrad`, coarser levels
  fill the rest; tiles not baked yet / mips past a tile's own read C.r = 0 and hand over. Layout (Texture2DArrayRD
  globals `road_a/b/c`, `road_info0..3` = window min x z, cell, n): A rgba8 = k/2, prints (+ skids), damp, water;
  B rgba16f = relief slope x z, mean squared slope, pebbles; C rgba8 = baked flag, ridden lines, loose grit, **edge
  stones** (new layer, user: "more pebbles on edges": gravel + a few bigger stones on the drawn ragged edge and loose
  shoulders, stone-coloured over dirt and grass, with relief). Racing-game tricks in it: virtual-texture clipmap with
  mips, prefiltered marks, slopes that average in mips + the lost bumpiness as roughness (Toksvig / LEAN-style) and as
  cavity darkening (`road_cavity`), a darker worn groove (`groove`), height-blended dirt edge (the baked pebbles), grit
  swept off the packed line. **Extending**: bake knobs = `RoadDetail.PARAMS` (storage buffer, `set_param` re-bakes;
  `BMX_ROAD_SET="edge_stones=2,stray=1.5"`); a new layer = a `layer_x()` in the bake shader (its header says how).
  Settings › Graphics › Road detail (`road_detail` 0 off = the old per-pixel path, 1 low 512² ~22 MB, 2 high ~85 MB;
  presets Low / Medium 1, High / Ultra 2); `BMX_ROAD=0|1|2`, `BMX_OLD_ROAD=1`, probe `BMX_ROAD_PROBE=1` (`ROAD baked=
  cleared= pending= cpu_ms=` per second). Debug `BMX_TRAIL_DEBUG=2` lines / grit / prints, `3` slope + stones, `4` which
  level, `5` colour multiplier, `6` prints (1 = the old per-pixel masks). Chunk records keep `mat` (the bake reads its
  trail textures). Seen: far down the trail the lines / playful marks stay as soft marks (were plain dirt); from straight
  above the thinnest stray lines are softer than the old per-pixel ones (their 1-3 cm groove walls average out in the
  mips: the colour now carries them, raise `stray` / `prints` if wanted). Not measured cleanly: GPU saving (another
  program held the GPU), main-thread cost ~0.2-0.4 ms a frame riding fast (tile scheduling). `trail_puddle.gd` (CPU
  puddle mirror) unchanged. Not done: stamping live marks (real tyre tracks, skids, blood) into the clipmap.
  **Footprints** (same day, user: "add some footprints", then "random, more faint, random people over time", not
  walkers in lines): bake layer `layer_footprints` (param `footprints`): shoe soles (ball + waist + heel, ~26 cm)
  scattered in a jittered 0.55 m grid in the trail's frame (~22 % of cells at 1), each its own direction (mostly along
  the trail either way +-35 deg, one in five any way) and age (fresh 0.75 .. old 0.12 strength), pressed up to 1 cm and
  16 % darker, worn off the riders' line (x 1 - 0.7 line), none on built jumps / where riders fly.
  `BMX_ROAD_SET=footprints=4` for lots, `BMX_TRAIL_DEBUG=5` shows them in the colour multiplier. Not done: the rider's own footprints
  (a foot down at a stop, walking after a crash) as live stamps. **Built jumps less smoothed** (user: "jumps and rollers
  have more blurred textures"): on `jm` the scan relief was x0.2 and the jump also counts as ridden line (~8 % left),
  colour variation x0.45, grit / pebbles / scuffs / lumps off; now relief ~x0.65 x (1 - 0.6 x 0.4 ridden), colour x0.8,
  grit x0.4, scuffs / lumps x0.5 / x0.6, in ground.gdshader and the bake alike.
- **Land Lab: the land's knobs in the Godot editor (2026-11-25, user: "an editor for the procedural generation so I can
  tweak it easily with you"; user: not in the game, in the editor)**. Plugin `addons/land_lab` (enabled in project.godot):
  a main-screen tab **Land Lab** in the editor's top bar (next to 2D / 3D / Script). Left: seed, area (300 m .. 4.8 km),
  centre x / z, Detail (256 / 512 / 1024 points across, default 512 = 2.3 m a point over 1.2 km; the game's ground
  is 0.5 m, so use a small area + 1024 for close detail), then one slider per knob of `LandParams` (`scripts/world/land_params.gd` `DEFS`: overall height, rolling
  hills / ridges height + size, region size, 90 m / small bumps, rough patches, swirl (domain warp), steepness limits
  (talus, detail / fine damping), plains vs rough region sizes, valleys, rock bands; orange value = changed, R = back to
  default). Right: a shaded map (game ground colours, contours every 5 / 10 m, the trail in red) or 3D (left drag turns,
  wheel zooms, "3D height x" view-only exaggeration); map: drag pans, wheel = area size. A / B (hold) = the default land
  for the same seed / area. Numbers under it: height range, mean slope, % flat / > 15 / 25 / 35 deg, % under water.
  SAVE writes `res://data/land_params.json` (only the changed values; **the file Claude reads / edits to tweak the land**);
  the game reads it at the first field setup (`TerrainField.setup` -> `LandParams.ensure()`), so every world uses it.
  RIDE HERE starts the game on that seed at the area's x with the current values (env `BMX_LAND`, nothing saved).
  SNAPSHOT writes the view + values + numbers to `%APPDATA%\Mini BMX\landlab\snap_<date>.png/.txt` (to show Claude).
  How it works: the generator isn't @tool, so the tab runs a background headless Godot (`tools/land_lab_render.gd --
  --serve <user://landlab_worker/<editor pid>>`, the tab's log in `panel.log` there: rebuilds on every new job.json, ~0.7 s; quits 15 s after the editor stops touching
  `alive`; the tab is a plain Control placing its halves itself, height cut to the window: as a container the editor
  gave it 8348 px) with the real `TerrainField` + `TerrainFieldCs` (trail, berms, lakes, biomes all included) and samples
  `map_heights` / `map_colors`. The knobs are static vars in `TerrainField` (`LAND_*`, `L_A*` heights, `L_I*` periods)
  mirrored in `TerrainFieldCs` (`_land_from`, handed over in `setup_from` via `land_get`); defaults = the old constants,
  so with no file nothing changes: `terrain_cs_cmp` EXACT with defaults and with tweaked values (`BMX_LAND=...` +
  `BMX_MESH_K=1`: the 0.25 m near-trail mesh is C#-only, so its chunk.verts / lods / norms always differ there, before
  this too). Tests: `BMX_LAND="land_scale=1.8,warp=80"` (any ride / tool), `BMX_LAND_FILE=0` ignores the file,
  `--path godot -s res://tools/land_lab_shot.gd -- out.png [3d] [key=v ...]` (the tab in a plain window, shot after its
  first build). `BMX_OLD_LAND=1` still = the original land (`_landform_old`, never reads the knobs). Not done: knobs for
  the mountains (`RANGE_*`, `HILL_TOP`), biomes, wild terrain, lakes, trail shape; a changed land moves the whole
  trail's heights (it follows the smoothed land), so jump / berm checks (`route_checks`, demo AI) should be re-run
  after saving big changes.
- **Relief layers: mountains, erosion, valleys (2026-11-25, user: "a really good landscape generator like Houdini / World
  Creator", picked: generator (not hand sculpting), erosion look + bigger mountains + rivers / valleys)**. `TerrainField._relief`
  (mirrored `TerrainFieldCs._relief`, `terrain_cs_cmp` EXACT) is added to the land in `base()`, NOT in `landform()`: the
  course's heights (`TrailCourse` E = smoothed `landform` along the trail), berms, jumps and route features are untouched; every
  layer fades in away from the course (`trail_far`: a 32 m coarse distance map of the course, chamfer distance transform,
  capped 640 m, built in `_bind_course` -> `_build_far`, copied to C# in `_course_from`, follows the trail when it grows) and
  away from the side paths (`trail_metres`) and the spawn / first mountain (`wild_mask`). (1) **Mountains**: ridged noise (two
  octaves, analytic gradient) in regions (~70 % of the land, `PK_RI` 3 km), rising from `PK_NEAR` 60 m to full `PK_H` 140 m
  at `PK_FAR` 300 m from the trail: real ranges on the skyline (seed 4242 over 4.8 km: -4 .. 189 m). (2) **Erosion**
  (`_gully`, own implementation from the published idea of the Johansen erosion filter, NO code copied: its code is MPL /
  CC BY-NC-SA): stripes running down the slope (the land's + the mountains' gradient, `_lf_gx` / `_lf_gz` left by
  `landform`), laid by a 3 x 3 neighbourhood of grid cells with hashed pivots (`_cell_hash`), bump kernel radius = 1 cell
  (1.5 made seams), a parabola across each stripe (rounded gullies, sharp crests), two octaves (48 m, 21 m; the small ones
  sit on the big ridges), depth `ER_H` 6 m on faces steeper than ~22 deg, from 12-40 m off the trail. (3) **Valleys**:
  long winding channels where a domain-warped noise crosses zero (distance = |n| / |grad n|), `VL_D` 10 m deep, `VL_W` 45 m
  half wide, ~1.1 km apart, with a riverbed `VL_BD` 1.2 m x `VL_BW` 4 m in the floor; where the land is low they fill
  with the world's water (no flowing rivers: there is one water level). All are Land Lab sliders (groups Mountains /
  Erosion / Valleys & rivers; 0 = off). Cost: a C# ground height 2.6 -> 2.9 us (`-s res://tools/relief_cost.gd`, with
  `BMX_LAND=peak_h=0,eros_h=0,valley_d=0` for the old cost). `-s res://tools/relief_probe.gd -- [seed x0 z0 size]` = the
  relief's range + how far the area is from the trail. EXACTNESS LESSON: write long decimal constants as divisions
  (`0.02 / 3.0`): GDScript read `0.006666666666666667` one rounding step off C# (68 mismatches of 1e-14). Every world's land
  away from the trail changed; `trail_grow_probe` / `rope_find` PASS, `wood_edge_probe` walls=0, follow ride sane.
  Not done: river colours (gravel bed / water flowing downhill), cliff / scree colours on the new steep faces, erosion
  on the mountains' own fine detail, gullies feeding the valleys.
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
  `BMX_ROPE_SAG/LAND/BEND/ANCHOR` overrides.
  **Wider + fenced (2026-11-23, user: "we crash on it a lot, riding to the rope left / right crashes at once")**: the
  deck is twice as wide (`DECK_HALF` 1.1, hand ropes `HAND_HALF` 1.6, trees `TREE_W` 2.0). The hangers + hand ropes
  are a fence (`Game._rope_rail`, before the OFF THE BRIDGE check): a tyre reaching `ROPE_RAIL` 0.15 m inside a deck
  rope (where the rope is NOW: `RopeBridgeSim.Edges(u)`, the deck sways up to ~0.4 m under the rider) is held inside,
  the travel is turned along the bridge, speed x (1 - 0.55 sin angle), the rope takes the push; only > 60 deg into it
  above 7 m/s = INTO THE ROPES! crash (`RopeBridge.fenced` / `axis_angle`). Test: `BMX_STEER_AT_ROPE=12 BMX_STEER=1|-1`
  (+ `BMX_STRAIGHT=1`) holds full lock from 12 m along the first bridge; `ROPE rail` lines with `BMX_ROPE_PROBE=1`.
  Same day, user: "turning feels weird, the sway messes with our riding" + "the camera on the bridge is weird":
  the physics reads the deck level across (`RopeBridgeSim.HeightLevel`: its roll read as a bank / camber to the
  steering), only `ROPE_TURN_PUSH` 0.3 of the turn's reaction shoves the deck and only `ROPE_CARRY` 0.4 of the deck's
  sideways swing moves the bike. Trail camera: looks along the bridge (`Terrain.rope_aim` in `CameraRig._look_dir`)
  and its look point never drops more than 3 m under the rider (it aimed at the canyon floor beside the deck).
  Not done: a roadside billboard stands in the canyon under seed 12's bridge (`chunk_boards` doesn't skip ropes). Photo tests:
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
  `BMX_TRAIL_PUDDLES=0|2` (none / on every wet road). **Lines stop at a lip** (user: "people are jumping over them"): `TrailFeatures.AIR` = per feature type the stretches riders fly over (lip to about where they land; mirrored in `TerrainFieldCs.AIR`), `_feat_at` -> `fo_air` in both fields, baked as `trail3_tex` (R8); every ridden line, print, stray line and playful mark is x (1 - air), soft over the last ~2 m so they pick up again down the landing. **Relief** (user: "nice in colour but all just smooth"): the masks also make a height `thgt` (lines = grooves to 3 cm, prints / skids pressed in, grit + pebbles proud, lumpy between the lines) turned into the surface normal from its screen-space gradient; lighting only, the 37 cm ground mesh can't carry it. Uniforms `trail_fx`, `trail_bump`, `trail_relief` (x the depth), `trail_puddles`. **Side-path junctions** (2026-11-22, user screenshot: a zigzag band of aliased noise where a side path joins): the baked frame is the course's (arc length, offset) within `q_w + 2.6` of it and a side path's (signed distance, `0.6x + 0.8z`) beyond, so the texture filter blended two unrelated frames over one 0.5 m texel and every frame-drawn mark aliased along the texel grid. The shader reads the four texels it blends (`texelFetch`) and fades the frame's marks (`tfk`) where they differ by more than ~2 m; the bakes are unchanged. `-s res://tools/junction_probe.gd -- [seed]` lists junction spots (seed 4242: x 1487, z -54). Playground / vista
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
  **Look from the research (2026-11-24, `docs/research/grass.md`: Ghost of Tsushima GDC 2021, Jahrmann & Wimmer, AMD,
  2Retr0 GodotGrass)**: Voronoi clumps (`CLUMP` 1.15 m: shared height / shade, near blades lean out of the middle),
  normals rounded across the width (near, faded with distance), self-shadow down in the grass (faded from 8 m),
  edge-on near blades turned towards the camera, wrapped diffuse. Uniform `look_v2` (`BMX_GRASS_OLD=1` = 0 = before).
  GPU 0.59 -> 0.64 ms. Tile placement is C# (`world/GrassPlaceCs.cs`, `BMX_GRASS_GD=1` = the GDScript `_place`).
  **Photographed blades (2026-11-25, user: "realistic texture for grass")**: near blades read one of 16 real grass blades
  (`assets/textures/grass_blade/blades.png`, a Texture2DArray 1 x 16 slices of 64 x 512, BC7; made by root
  `tools/make_grass_blades.py` from ambientCG Foliage001 + Foliage006, CC0: each blade straightened along its centre line):
  r = brightness detail, g = dry / brown, b = inside the photo, a = across slope (veins). Detail only: the colour stays the
  biome's; no alpha cut-out (the blade geometry is the outline, so no extra overdraw). Fades out from 55 % of the near ring.
  Uniforms `blade_photo`, `blade_contrast` 1.7. `BMX_GRASS_PHOTO=0` = without. Cost, `BMX_GRASS_AB=1` (switches it every
  30 frames, `GRASSAB off_ms= on_ms= diff_ms=`): camera down in the grass +0.25..0.34 ms GPU, riding view ~0 (measured with
  other programs on the GPU). Not done: flowers / weeds from the other scans, the mid ring (too small to show).

- **Grass to the trail's edge, a raised verge, grass under jumps (2026-11-26, user: "grass more to the edge of the road like in
  real life, a grass edge and then a depressed road; on longer jumps grass under it")**. (1) `TerrainChunkBuilder` grass density
  = 1 - sm(0.62, 0.9, TW) (was sm(0.04, 0.4): grass stopped ~0.75 m past the dirt, where its fade only began): now half density
  0.25 m past the trail edge, full by ~0.5 m. (2) Under a built jump where riders fly (`T3` = `fo_air`, 0 at lip / landing)
  the dirt weight is taken down (x 1 - 0.9 sm(0.35, 0.85, air)) so grass grows over the gap / deck middle (drawing only; the
  ground colour stays dirt under it). (3) `TerrainFieldCs.micro_detail` (drawn fine mesh only, physics untouched) lifts a 3.5-7 cm
  grass verge just outside the trail (w + 0.05..0.3 x the dirt fade, back to the land over ~1.5 m, none on built jumps): the
  trail reads as ridden down into the land. `BMX_OLD_VERGE=1` = before. Probe `-s res://tools/verge_probe.gd -- seed [n]` (first n
  jumps in green land: mean grass by distance past the trail edge, grass + air along the jump); seed 4242 kicker s=514: grass at
  0.25 / 0.5 m past the edge 0.00 / 0.09 -> 0.49 / 0.91, over its 12 m flight 0 -> 1. **Tests on the user's machine: their
  `route.cfg` pins the Dune Sea biome (no grass anywhere); run tests with `APPDATA=<temp dir>`.** `BMX_TRAIL_FEAT` also takes
  table / kicker / tableLine / flow / double now. Not seen in game: grass under a jump (no green jump found in a test ride), the
  verge lip up close.
- **Trees by nature's rules (2026-11-26, user: "trees and bushes seem random, make rules like other world builders, follow
  nature's rules, if we miss a vegetation type make it"; research `docs/research/vegetation.md`, from recall, links unchecked)**.
  `TerrainChunkBuilder._trees` (`BMX_OLD_PLACE=1` = the old 100 random throws, `_trees_old`): one candidate per `ECO_CELL`
  3.6 m world cell, jittered `ECO_JIT` 0.34 (natural minimum spacing, no chunk seams; Horizon Zero Dawn-style density
  placement; own `WorldRng` per cell), kept with probability (`_eco_tree`): stands + clearings (38 m forest noise + 115 m
  grove noise), slope (thinning 25 -> 38 deg; on cliffs a 3 % stunted tree), hollows (`_eco_land`: height vs the ring 12 m
  round: wetter, denser, broadleaf) vs ridges (sparser, shorter, wind-leaning pines), shaded north-facing slopes (denser,
  more pines), the shore (`_shore`: < 3 m above the water AND water within 16 m: willow / alder `kind 3`, pale lobed crowns),
  biome as before, x `ECO_K` 0.47 (= the old count). Stand edges grow smaller trees; mature trees seed 1-3 saplings 3-8 m
  round (30 %); the cold biome stunts (to 0.4x) and leans them (krummholz); forests have 3 % standing dead trees. `_put_tree`
  = one tree of a kind (0 pine, 1 broadleaf, 2 savanna, 3 willow). `_nature` adds: reeds with cattail heads (`spike` mesh,
  `CATTAIL` browns) at the water's edge, willow-green shrubs a little higher, alpine heather / dwarf shrub mats (`bush1`,
  `HEATHER`), a shrub belt where stands thin into meadow. Measured (`deco_probe.gd`, which now picks its chunks before the
  ride test: it used to measure different chunks whenever the trees changed): trees/ha 79 -> 80, trunks < 1.5 m apart
  19 % -> 9 %, < 2.5 m 44 -> 25 %, free ride in forest 31 -> 35 m. Chunk build 101 -> 104 ms (`tools/chunk_cost.gd`).
  LESSON: `f.q_*` (trail lookup state) is overwritten by any height / land read: take a trail verdict right after `trail()`
  (the forest clearance read late let a trunk 1 m off a singletrack: BONK on seed 12). Seen from above (seeds 4242, 12);
  NOT seen: cattails, heather, willows on a green-biome shore, the treeline krummholz.
- **Rocks: generated shapes per biome, scan textures, LODs (2026-11-26, user: "realistic rock textures, desert rock and
  mossy where forest / green", "realistic shapes, different types by biome, nice LODs")**. `world/rock_gen.gd` (`RockGen`):
  each rock = a convex block (soft p-norm minimum of N random fracture planes: p small = weathered round, large = crisp
  frost-split) + per-type weathering + fbm along the normal + a few concave dents, sunk foot, normalised to the old rock's
  size (colliders / domes unchanged). Types: **granite** (rounded joint blocks; green land / forest), **desert**
  (sandstone: flat top, bedding ledges, undercut foot, tafoni pits), **tundra** (frost-shattered slabs / blocks, sharp),
  **basalt** (hex column cut by a tilted fracture, vesicles; ash fields); 2 variants each. Surface = star-shaped function
  of direction, so every LOD is the same rock on a finer / coarser icosphere: LOD0 3380 tris (list `rock_<type><v>_lod0`,
  deco_fade mode 4, near the rider), LOD1 500 tris (the list itself, mode 3 elsewhere + the shadow caster), pebbles 320
  (`pebble_<type>`). Meshes cached on disk (`user://cache/rocks`, bump `RockGen.VER` when shapes change; ~0.6 s to build).
  The chunk builder's `put("rock" | "pebble")` is rerouted in `_push` -> `_rock_type(x, z)` (biome weights, hash-mixed at
  borders; saves / restores `f.b_*`), custom data rgb = brightness, a = moss (forest / wet / a little on green land, none
  on ash / desert, less when cold). Shader `shaders/rock.gdshader`: Poly Haven CC0 scans (`assets/textures/rock`, 1K,
  `SOURCE.txt`: desert rock_boulder_cracked, granite rock_face greyed (`saturation` 0.18), tundra lichen_rock, basalt
  dark_rock_02, moss mossy_rock) triplanar in world metres with whiteout normal blending, a per-rock offset into the scan,
  moss scan on up-facing faces in patches by the moss amount. Project setting `global_shader_variables/buffer_size`
  65536 -> 131072 (the extra rock MultiMeshes ran out of instance-uniform slots). Title land re-baked. Gallery:
  `res://tools/rock_gallery.tscn -- out.png [dist= yaw= h= sun= wire=1]`. `BMX_OLD_ROCKS=1` = the old icosphere boulders.
  Seed 4242 desert lake: triangles 4.26M -> 4.71M a frame, draw calls 792 -> 856 (fps in the noise with other GPU apps).
  Same day: the dry biomes' "weed" blob (a flat-shaded 80-triangle ball, half of every desert shrub: user "why do I still
  see low poly bushes") is gone, every one is the leaf-card `bushdry` now (`BMX_OLD_WEED=1` = before; the tumbleweeds have
  their own twig mesh, the title's wind puffs find `bushdry` too). Not done: sandstone ledges are subtle;
  the rope-bridge canyon rocks and arches still use the old blob.
- **Bushy roadsides (2026-11-27, user: "make it more bushy along the road only")**. `TerrainChunkBuilder._roadside`: clumps of
  1-3 bushes `ROADSIDE_IN` 0.9 .. `ROADSIDE_OUT` 6.5 m past the trail's half-width, both sides, thickest ~2.5 m out, smaller at the
  dirt, in denser / thinner stretches; none on the forest singletrack, jumps, signs / fences (`blocked`) or ash; dry = `bushdry`,
  cold = heather, else leaf bushes; no colliders. It runs last (put() draws from the shared `rnd`: nothing else moves).
  `BMX_OLD_ROADSIDE=1` = without. `route_dist` only sees `QR` 19 m: the chunk check samples nine spots. Seed 4242 Dune Sea:
  ~+2 % triangles a frame; fps not measured cleanly. Title land not re-baked.
- **Leaf-card bushes (2026-11-25, user: "could we add Megascans bushes, or too heavy?" -> prototype from a procedural texture)**: bushes are no
  longer the lumpy blob. `world/card_bush.gd` (`CardBush`): ~30-46 upright quads (each folded in the middle, turned at random about the vertical, front
  facing away from the bush's middle: tilted cards looked wrong, user) on a dome, each with a leaf-cluster texture drawn in code (`texture("leaf" | "dry")`,
  256 px, alpha cut-out, mipmaps; no downloaded asset), normals bent toward the dome, baked "inside is darker" vertex-colour AO, ~120-180 triangles
  (the blob was 320). Shader `world/deco_cards.gdshader` (cull off, alpha scissor, deco_fade + sway + flutter + backlit scatter like `deco.gdshader`;
  materials `MAT["leafCard"]` / `["leafCardDry"]`). Variants = list names: `bush` (round), `bush1` (low + wide), `bush2` (tall + loose), picked from the
  yaw (`TerrainChunkBuilder._bush_kind`, uses no random numbers: other decorations didn't move), and `bushdry` (small grey leaves + twigs, tinted with
  the SCRUB colours) which replaces every other weed blob in the dry biomes. Anything else that draws `MESH["bush"]` must use the `leafCard` material
  (`level_visuals.gd`, `lens_scene.gd` do). `BMX_OLD_BUSH=1` = the old blobs. Preview: `res://tools/bush_gallery.tscn -- out.png [dist=m yaw=deg sun=deg]` (old blobs
  at the back, the four variants in front). Seen: close-ups + two rides (seeds 4242, 80019), no script errors; NOT measured: frame time with many bushes in
  view, the wind sway, how distant leaves thin out (mip alpha). Poly Haven's `searsia_burchellii` (1.4M polygons, ~35 MB glTF) was looked at as a scan source
  and not used: it would have to be decimated + baked to cards first.
- **Card trees (2026-11-26, user: "same trick as the bushes for trees", "no low poly trees, make LODs from our new ones",
  "far LOD as a baked PNG billboard", "roots flare at the bottom, branches for the leafy ones", "leaves too big, realistic
  scales, trunk thickness and height, can vary")**: `world/card_tree.gd` (`CardTree`). `BMX_OLD_TREES=1` = the old small
  solid trees. **Sizes** = `CardTree.dims(kind, r1..r4, tall, shrink)` (one place, used by the world chunks, levels via
  `dims_at(kind, x, z)`, the far backdrop, the bake): pines 9-22 m (tall forest 18-30, crown in the top ~45 %), leafy
  (beech-like) 10-20 m, young trees 4-8 m, savanna 5-9 m flat-topped, snags 6-14 m; trunk radius ~1.1-2 % of the height;
  bend-tree giants 26-34 m with 1.35x trunks. Colliders follow (`rt`, ceil = top). `Terrain.CASTER_H` 32 m.
  **LODs**, all from the same instance buffer, swapped per pixel by one dither (`shaders/deco_fade.gdshaderinc`):
  | LOD | what | distance | fade_mode |
  |---|---|---|---|
  | 0 | `pineCard` (~80 branches x 3-6 needle tufts) / `blobCard` (130 small cards in 6 lobes) | to 36, gone by 48 m | 4 |
  | 1 | `pineCardLod1` (the same branches, 2 bigger tufts each) / `blobCardLod1` (48 cards) = TerrainGeo "pine" / "blob" | 48 .. 72-88 m | 3 |
  | 2 | crown billboard (`tree_billboard.gdshader`, crown-only cells 4-7 of `impostors.png`) | 72-88 .. 124 m | 5 |
  | 3 | backdrop billboard (`FarHills` `IMPOSTOR_SHADER`, whole-tree cells 0-3) | 100 m .. 1.9 km | -1 |
  **Trees are GROWN with the user's own tree app's logic** (2026-11-26, `Downloads/webgpu-tree` growth-engine.js, Weber-Penn
  style; user: "we did this app, take its logic for trees"): `world/tree_grower.gd` (`TreeGrower`: trunk walk, LEVELS of
  children spawned along their parent with angle / spiral roll / length ratio x crown shape x apical dominance, each walked
  in kink steps with noise distortion + curve-back + phototropism + floor avoidance, conifer prune ellipsoid, Weber-Penn
  top-down radii, root flare, cumulative gravity sag; presets "pine" (Pine / ScotsPine mix: bare trunk, conical crown in
  the upper ~55 %) and "leafy" (Beech, its 4th level left to the leaf cards); own seeded RNG, not bit-identical to the app).
  `world/grown_tree.gd` (`GrownTree`): each species grown once, NORMALISED (root at 0, top at 1): `pineCards0/1`,
  `leafyCards0/1` (LOD0 = a needle tuft / leaf cluster at every twig, LOD1 = bigger ones along the limbs), `*Wood0/1`
  (bark tubes along the chains: LOD0 trunk + limbs + twigs, LOD1 trunk + main limbs; buttress roots at the trunk's foot;
  bark UVs), `*Proxy` (shadow stand-in: trunk + a blob per main limb). So a tree is ONE instance from the ground, scale
  `CardTree.dims(...).scale` = (H x k, H, H x k) (savanna = the leafy tree squat and wide); `dims` also gives R / rt / cb
  for colliders, levels, the backdrop. Placement (chunk builder, levels, ride-setup scene, gallery, bake) uses that; the
  separate trunk list is only snags now. Billboard cells are the same normalised trees (crown cells squeezed by A, json
  y0 / h / w). Wood material = bark with `bark_uv` (CardTree "wood_pine" / "wood_leafy"); foliage and wood share `SWAY`.
  Tune a species in `TreeGrower.SPECIES`, then re-run the impostor bake.
  `CardTree.add_twin` (from `Terrain._finalize`, `LevelVisuals._trees`) adds LOD0, the trunk / branches inside the crown
  (`add_spire`: `pineSpire`, `blobLimbs`, mode 1), the LOD2 billboard (`add_billboard`) and the
  **shadow stand-in** (`add_shadow_proxy`: the old solid crown, `SHADOWS_ONLY`, with its dapple holes; no card casts a
  shadow: real-size card crowns in the cascades cost ~4-5 ms GPU; Terrain's far-shadow switch flips the stand-in, meta
  `cast_on`). Every trunk is `trunkFlare` (5 buttress roots over the lowest 10 % of its height). **Leaves at real size**:
  needle card 2048 x 1024 = a ~2-3 m branch (needles ~5 cm); leafy crowns repeat a seamless ~0.8 m foliage patch across each
  card (`deco_cards` `tile_m` = `LEAF_TILE_M`, card size in COLOR.a x the instance scale, ragged oval outline); bushes keep a
  single clump card. **Textures** (`assets/textures/tree_cards/`, all BC7 + mipmaps): `needle_branch`, `leaf_cluster` /
  `leaf_tile` (ambientCG CC0) and, preferred when present, `leaf_beech` / `leaf_beech_n` / `leaf_beech_tile` /
  `leaf_beech_tile_n` (Textures.com European Beech atlas: albedo + normal (RGB) + translucency (A); **gitignored**: the
  licence forbids redistributing the files and the repo is public; make them with root `tools/make_tree_cards.py
  <PineNeedles001 dir> <LeafSet005 dir> godot/assets/textures/tree_cards <...Downloads/TCom_Leaves_EuropeanBeech01_2K_>`,
  then `--import` and set the new .import files to `compress/mode=2`). `deco_cards`: `use_nrm` / `nrm_tex` (normal map +
  translucency into the backlight / scatter; card meshes have tangents), `volume_normals`. `impostors.png` + `.json` baked by
  `res://tools/bake_tree_impostors.tscn` (re-run, then `--import`, after any card-tree change; its camera is a 1 deg
  perspective lens: an orthographic one reads as the shadow pass). Level bakes `LevelBake.VER` 2 (re-baked). Gallery:
  `res://tools/tree_gallery.tscn -- out.png [dist= yaw= h= look= sun= at=x,z]` (back row LOD1, front LOD0). **Cost: not
  measured cleanly** (the user's own game window held 74-95 % of the GPU during every run): under that load real-size trees
  were ~+2 ms GPU vs the old small trees; measure again with no other Godot window open (seed 4242 x2100, `BMX_RENDER_PROBE`).
  Not done: the LOD bands show as a stipple, billboards have two baked angles, BMX_OLD_TREES=1 still draws the new trunks /
  sizes only partly (old crowns on real-size placements).
- **Ground crossfade + middle ring (2026-11-25, user: "the mountains pop really late and bad", "a lot of popping, a nice crossfade like big games")**.
  Before: the real chunk ground ended at a hard edge (the loaded square, 144-168 m, jumping 48 m at each chunk line) and the 20 m backdrop (`FarHills`)
  sat 5 m UNDER it, which showed as a step; past it the backdrop is smooth, pale, has no lakes. (Its heights are the field's own: `tools/far_vs_ground.gd`
  says 0.00 m; the problem was the sink + the missing detail, not the height.) Now (`BMX_GROUND_FADE=in,out`, default 105,144, `0,0` = the old hard edge;
  `Game._ground_band`, global `ground_fade` = rider xz + band, `FarHills.ground_crossfade`): the real ground (`shaders/ground`) dissolves out over the band with
  the same screen-door pattern as the decorations, and **every pixel is drawn by exactly one of three surfaces**: chunk ground (`n1 < k`), the new **middle
  ring** (`n1 >= k`, second pattern `n2 < km`), the 20 m backdrop (the rest), `km` = 1 - smoothstep(`MID_BAND_IN` 560, `MID_BAND_OUT` 620, d). None casts
  shadows (the far meshes never did; the ground's shadow pass is not dithered), so no sink is needed in this mode. Middle ring = a second grid in `FarHills`
  (`_rings`: `MID_HALF` 880, `MID_STEP` 8 m = the chunks' own coarsest LOD, rebuilt every `MID_REBUILD` 200 m on a worker, ~49k vertices, same
  C# `far_ground` / `far_colors`, same ridge uplift via a shared 20 m ridge-clear map sampled bilinearly, no trees); only exists while the crossfade is on (the
  title screen keeps the old single backdrop + sink). **Lakes continue past the chunks** in both rings: cells under `Terrain.WATER` are flat `WATER_COL`, 0.3 m
  under the water sheet (which only exists inside the loaded chunks). `FarHills._run(job)` now takes its job (half, step, trees, ring); `far_hills_probe.gd`
  (C# = GDScript, PASS) was updated. Seen: photo from 55 m up over seed 4242 x2150 (`BMX_PHOTO_AT=2150,55,36,2290,20,36 BMX_PHOTO_SET=dof=0,fov=70`): no cliff,
  lakes carry on, real hills where there was a flat plain. 40 s follow ride seed 80019: no errors, fps unchanged. NOT done: the band is a visible stipple
  from above (TAA / blue noise would soften it), the middle ring's colour is still vertex colour at 8 m (no road / trail detail, flatter than the chunks), no
  decorations in it (the far trees are the backdrop's, fading in at ~124 m), the water sheet itself still ends hard at the chunk edge (z-ordered over the
  ring's water), a third ring to push the 20 m backdrop further out, geomorphing instead of dithering, not measured on a slow GPU.
- **Sponsor props** (`TrailCourse.chunk_gates` / `chunk_boards`, fixed spacing by centreline index so growing never moves them): a huge steel gantry with a sponsor banner over the trail every 300 m (`TrailGate.build`, made-up brands in `TrailGate.SPONSORS`, no collision, skipped on jumps) and breakable wooden roadside billboards every ~80 m (fence-style panel in `TerrainChunkBuilder._boards`, so the bike smashes them; the Label3D text is freed on smash). Probe: `BMX_GATE_PROBE=1`.

- **Printed signs** (`world/sign_tex.gd` `SignTex`, `shaders/sign_board.gdshader`; 2026-11-25). Every sign face is printed once per look
  into a SubViewport, read back, mipmapped and DXT1-compressed, cached (`SignTex.material(km)`, `billboard(sp, size, planks)`,
  `banner(sp, size)`, `for_plate(dict)`): no Label3D text, the print is lit with the board. One shader weathers them all per sign
  (seeded by place): real scans for the paint (grime_dirt / grime_normal = ambientCG SurfaceImperfections008, lens_dirt.png R =
  Smear004 smears, G = SurfaceImperfections001 scuffs), sun fade, chipped edges, a dent, mud flung up from the bottom (`mud_amt`);
  `wood_mix` 1 = paint on wooden planks (Wood049 grain, `planks` seams, bare wood in chips, paint x0.5 so pure sponsor colours
  don't bleach); retroreflection in its `light()` (`retro`, distance plates only: a bike lamp at night makes them blaze, NOT yet
  checked in a night shot); a low sun's direct light on it is capped at `sun_cap` x the ground's. In a golden-hour view toward
  the sun the boards still wash out pink like everything that way (the scene's haze), at noon they read as painted wood.
  - **Distance signs** (`TerrainChunkBuilder._dist_signs`, at 1 km then every 5 km, smashable): a square wooden stick (`pole`,
    `shaders/sign_pole.gdshader`, ambientCG Wood035 in `assets/textures/wood_post`) with a 0.8 m plate on its front, the Figma
    "table sign" layout (file qDRfS2eOv3e3e9wO1u8W5e, node 39:74): blue field + number in Barlow Condensed Black, white strip with
    DISTANCE in tracked-out Barlow Black. Seed 4242's 1 km sign: x 767, z 70.5 (`BMX_TRAIL_FEAT=x740 BMX_PHOTO=7
    BMX_PHOTO_AT=765.6,43,70.5,766.99,43,70.54`).
  - **Roadside billboards** (`_boards`): two posts + one 3.6 x 1.5 m painted plank board, sponsor on both sides; smashed off in one
    piece. Seed 4242: x 85.2, z 2.3 (`BMX_TRAIL_FEAT=x72 BMX_PHOTO_AT=78.5,104.2,5.5,85.2,103.6,2.27`).
  - **Gantry banners** (`TrailGate.build`): printed panel, weathered, no mud (`wear` 0.7). Not looked at in game yet.
  - The plate is its own MeshInstance per sign (`Terrain._panel_labels`, `panel["plate"]`, part kind `signboard` with `i` -1);
    `BMX_SIGN_DUMP=<dir>` writes each print as PNG, `BMX_SIGN_RAW=1` skips the runtime compression.
- **Wooden fences** (`shaders/wood_fence.gdshader`, materials `fenceRail` / `fencePost`): ambientCG Wood049 (`assets/textures/wood_plank`,
  clean sawn-plank grain) box-mapped in metres, grain along the rails / up posts and pickets; the instance colour picks the finish
  (brown = bare wood at that tone, near white = painted pickets worn through to grey wood in grime-scan patches). Debris pieces
  fly in plain colour (the shader reads its tint from the MultiMesh).
- **Texture compression (2026-11-25)**: the 3D scans that were stored uncompressed are BC7 high quality + mipmaps (normals keep all
  three channels: `compress/normal_map=2`, some shaders read .b), the 5 other HDRI skies BC6H like the main one, the plastic scans
  capped at 1024 (`process/size_limit`: 7-16 cm tiles on camera bodies). ~1 GB of possible GPU memory -> ~0.25 GB. New 3D
  textures: set `compress/mode=2` (+ mipmaps) in their .import; 2D / UI pictures stay lossless.

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
  **The right stick pumps too (the pro way, user decision: it's the universal body stick)**: back = legs bent, forward =
  pushed straight, pulled past `manualFrom` quickly = the manual. The hop button is the easy pump. (2026-11-23: both are
  now the legs' stroke against the ground's curve, see "Berms pay back, rollers pump" above; the old `pumpHold` downhill
  push is gone.) A pumping press doesn't hop when let go (unless a lip is right there). A jump (> 0.45 s air) landed within `landPerfect` of the slope =
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
  - Not done (the pump for speed is the leg model since 2026-11-23); the
    suspension's own rebound is not simulated into the pop (the timing window stands in for it); not ridden by the user yet.
- **Back-wheel landings + leaning back over rollers (2026-11-23, user F8: "landed on rear tire leaned back", "rider should
  be able to land that", "crashed on small rollers when holding back lean")**. `bike_physics.gd`. (1) A landing's crash
  limit is doubled only when square to the ground (`landForgive`, `_land_pe`); nose up (back wheel first, `_land_up`) now
  keeps most of it to ~30 deg and loses it by ~55 deg (nose first stays strict). Test rider `BMX_PG_PILOT_PITCH=<deg>`
  (+ `BMX_PG_PILOT_VY=<m/s>`): drop_3 at 45 km/h, 35 deg nose up, 9.5 m/s down: SLAM -> heavy landing 0.64; 50 deg still
  SLAM. `BMX_OLD_LANDUP=1`. (2) In the air the game hands the right stick to air control, so a stick held back read as
  released and came back on landing as a fresh quick pull: it armed the direct manual, full back = past its edge = fell
  off the back (LOOPED OUT) on every little roller. `_pull_age` / the arming now hold through the air (`MANARM` line with
  `BMX_MAN_PROBE`). (3) The ground loop-out check, with weight held back on purpose (stick back or the power wheelie), throws
  the front down and costs speed (`manLoopKeep`) instead of crashing. `BMX_OLD_LOOPOUT=1` = both as before. Repro:
  `BMX_LEVEL=playground BMX_STRAIGHT=1 BMX_PAD=1 BMX_PG_AT=roller_0.3 BMX_PG_SPEED=25 BMX_BODY=slowback:1.0`. Every crash
  now writes `CRASH <reason> v= vy= pitch= ground= ... stick= man= armed= pw=` into the session log (so F8 / crash reports
  say why). Suite identical with / without (the suite rides hands off), stress 56 / 56.
- **Landing body soaks the hit (2026-11-23, user: "when we land the whole body is stiff", "all jumps look small")**.
  Drawing only (`rider.gd`, `game.gd`), physics unchanged. The physics legs (`body_y - y`) already compressed 17-26 cm,
  but the drawn hips dipped 0-10 cm, the same on every jump. Found with the new probe `BMX_LANDBODY=1` (`LANDBODY` per
  landing: pelvis height at touch-down / lowest / settled, peak fold, the physics legs' deepest): (1) the air pose (tuck,
  air crouch, no attack stance, all x `air_k`) faded over ~0.5 s after touch-down and lifted the hips right through the
  hit; now reaching for the landing (`sm_reach`) straightens it out and on the ground it is gone at once (`sm_airst`,
  pose input `inAir`); (2) two saddle floors (`update_pose` "never sit INTO the saddle", `_constrain` `hip_lift`) held
  the hips at ~90 cm: while the legs are bent past 4 cm (`_sink`) the hips go back (0.45 x) and the floors drop 0.3 x it;
  (3) the bent part of the legs (past 3-10 cm, `_abs_p` / `_abs_c`) goes past the drawn body springs (they filtered the
  dip twice: late and shallow), little bumps still go through them; (4) MCAP `absorb` 2.5 m/s / 60 m/s^2 -> 5 / 220;
  (5) the crouch cap `deep_c` allows +10 cm with a landing fold, the fold sinks the hips 13 cm (was 9), the chest 5 cm
  more. Dip from touch-down (test rider): table_0.6 0 -> 16 cm, drop_1 1 -> 15, table_1.5 4 -> 18, table_3 ~7 -> 19.
  Rocks lane hips 2nd-diff rms 4.3 -> 3.2 mm. `BMX_OLD_LANDPOSE=1` = the old pose. Research: drop-landing studies:
  soft landings = more knee / hip bend, more energy taken, lower peak force; MTB drops 29-67 cm measured 6-9 x the
  weight at the tyres (Sports Med Open 2016); the library papers have nothing on landings. Left: the physics legs take
  ~0.3 s to their deepest (leg spring tuning, not changed).
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
  - **Crashed bike stops at walls (2026-11-23, F8 log: "shot up 1 km")**: fell 15 m into a rope-bridge canyon, and `_crash_step` set y to the ground under the sliding bike every tick, so it climbed the canyon wall 14 m in 0.2 s (drawn bike / camera / ragdoll with it). Now ground > `CRASH_WALL` 0.6 m above the bike = a wall: move reverted, speed x -0.2. Not reproduced in a test yet (the fall itself: seed 80019, canyon at s=547).
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
  - **Brake fade, dive steering, pedal bob + kickback (2026-11-25, `bike_physics.gd`, sliders Ride > Brakes / Suspension)**:
    (1) `brake_heat` (the rotor glow's number) now cools in the physics (`HEAT_TAU` 3.5 s; Game no longer decays it) and
    past `FADE_FROM` 3 up to `FADE_FULL` 10 the braking force that gets through is cut by up to `brakeFade` 0.35 (the
    levers had far more than the tyres hold, so cutting the lever did nothing: it is taken off the delivered force).
    Normal riding peaks ~1.5, so only sustained hard braking fades; "BRAKES FADING" flashes. Fully hot, 40 km/h both
    brakes: 8.6 -> 11.9 m. (2) Fork dive (`dive`, from `dg_xF` past the sag) shortens the wheelbase the bars' yaw reads
    by `DIVE_L` 0.12 x `diveSteer`: quicker turn-in under the front brake; the lean / grip limits don't read it.
    (3) Pedal bob: a zero-mean push on the shock from the stroke (`stroke` x drive x (1.1 - 0.7 AS) x `BOB_K`, `pedalBob`).
    (4) Kickback: the rear's shock speed x `CHAIN_GROWTH` 0.2 / `CRANK_ARM` 0.17 turns the cranks back (the other way on
    the rebound) while pedalling, and costs up to `KICK_LOSS` 25 % of the stroke (`pedalKick`). Per part, for modular
    bikes: dive needs a sprung fork (`_sprung_fork`: a setup + the frame's `has_f`), bob and kickback a rear shock
    (`_rear_shock`: a setup + `has_r`); a rigid fork, a hardtail or no setup (the BMX) gets none of that end's effect
    (brake fade needs no suspension). Bob goes through the shock's own spring and damper, so its settings move it
    (`BMX_BOB_PROBE=1`, `BOB shock_rms`: LSC 0 -> 10 18 -> 15.6 mm, sag 20 -> 40 % 12.7 -> 19.8 mm). `BMX_OLD_FADE=1` / `BMX_OLD_SUSPFX=1` = before; `BMX_FADE_PROBE=1` prints `FADE` lines (heat, fade, dive,
    kick), `BMX_HEAT=n` holds the brakes that hot. Stress 56 / 56; suite vs the stale baseline: 13 changed with, 12
    without (the rest is old drift). Not ridden by the user yet.
  - **Short flights aim sooner, OFF by default (2026-11-25, slider `shortAim` Ride > Jumps, default 0: the user rode it at 1
    and found it aligns the bike too much on short bumps; `BMX_OLD_SHORTAIM=1` also forces it off)** (`bike_physics.gd`, the hands-off landing aim): it held the take-off attitude for
    `airAimDelay` 1 s before levelling, so short flights landed nose-up. Now the whole flight (`air_time` + `_land_t`) under
    `SHORT_TO` 1.3 s pulls the delay down to `SHORT_DELAY` x flight, the ramp to `SHORT_RAMP` x flight, the assist up to
    `SHORT_HELP` 0.9 and the aim speed to `SHORT_SPEED` 40 (full at under `SHORT_FROM` 0.7 s; longer flights as before; a
    player's stick still wins: x `1 - _air_own`). Suite vs the old aim (`BMX_OLD_SHORTAIM=1`): landing pitch error
    table_1.5 9.3 -> -0.2, stepup_1 15.9 -> 5.9, hip_20 14.8 -> 3.8, drop_2 -42 -> -4; 7 runs CLEAN -> PERFECT. The lab's
    energy checks rise on some (the perfect-landing boost is speed) and fork / shock use is a little higher on matched
    landings (table_1.5 72 -> 81 / 90 -> 98 %). Stress 56 / 56. Not ridden by the user yet.
  - Open: the rear axle's path doesn't soak up square edges differently; the drawn head angle: the fork slides along the axis
    and the frame pitches, only the steering geometry change isn't drawn. No shop / prices for
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
- **Speed tuck (2026-11-26, user: a downhill speed-record rider's pose)**: `BikePhysics.speed_tuck` (0..1, `_speed_tuck_step`)
  = by itself coasting fast (`speedTuckFrom` 11 .. `speedTuckFull` 18 m/s, x `speedTuck`; pedalling, stick forward, a
  manual cancel it) or a LIGHT pull back on the right stick (0.05-0.3 in, gives way over 0.55-0.95 to the weight-back /
  sit-up pose; the manual still arms from a quick pull). Drag (`_aero_update`, now also in flight): the stick's tuck cuts
  `tuckDrag` fully, the automatic one `speedTuckDrag` 0.5 of it; the air brake (`upDrag`) only from ~0.55 back. Pose
  (`rider.gd`, input `speedTuck`, style `speedTuckPose`): back to `TUCK_ANG` 1.2 rad, hips `TUCK_HIP_BACK` 0.16 m back /
  `TUCK_HIP_DOWN` 0.10 down, head `TUCK_HEAD` forward + low; jump / landing / spin / flip poses fade it out. Sliders Ride >
  Speed > Pedalling. `BMX_OLD_SPEEDTUCK=1` = before. Not ridden by the user; playground suite not re-run.
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
- **Trail camera director (2026-11-27, `game/trail_view.gd` `TrailView`; user: "see ok on a 180 turn", "see where we land when
  jumping or falling")**. The old trail view looked at ONE point 10-26 m up the trail at a fixed low angle (a hairpin put it
  behind you; lips and drops hid the landing). Now it frames what must be SEEN: points 5 .. 39 m up the trail (more at speed,
  x Settings look ahead) + in a flight the ballistic landing spot (own predictor: `_landing_slope` writes physics state). Yaw =
  the middle of them, at most 1.3 rad off the travel, a critically damped spring (max 2.4 rad/s); height = raised (at most
  +30 deg) until the ground doesn't hide them or the rider (`_need_height`), + 9 deg in a sharp bend; distance x1 .. 1.6
  (bend, big flight, things not fitting); aim = rider ~1/3 under the middle, tipping / turning so trail + landing are in
  frame. A mouse drag still orbits (the sideways aim fades out). In a flight the camera also swings 0.22 rad to the side
  (`AIR_SIDE`) so the rider doesn't cover the landing (landing seen, cliff / kicker: old camera 46 / 58 %, first version
  without the swing 48 / 42 %, with it 92 / 86 %). `BMX_OLD_TRAILCAM=1` = before. Probe `BMX_CAMVIEW=1`
  (`dev/cam_view_probe.gd`, judges any camera from outside: share of trail points 6 .. 35 m seen / in bends / in the air /
  over drops, share of each flight that showed the real touch-down spot, view turn rate, rider's height in the frame;
  `CAMVIEWSHOT=prefix` shots). Run with `BMX_DEMO=1 BMX_CAM=trail BMX_TRAIL_FEAT=tech|table|kicker|woodDrop`.
  **Floaty (same day, user: "shaky, abrupt shakes on small bumps")**: the trail view follows a smoothed rider
  (`CameraRig._float_follow`, frame-time independent), turns on a spring (`_soft_look`), springs the blocked-view lift and
  the points' heights, and ignores small impact shake (`SHAKE_FLOOR`). `CAMVIEW shake` line (headless, `--fixed-fps 60`):
  turn acceleration max 1300-2300 -> ~100 deg/s2, rms 31-67 -> 27; the camera's vertical jolt p99 14 -> 9 m/s2.
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
  **Contacts without launches (2026-11-24, user: "weird ejection force, flies too much", "slides on the floor too
  much")**: measured with the new `BMX_RAGCOL_PROBE=1` (`RAGCOL t= com_v= up= pelvis_h= slide= kick= rise=` every 0.5 s
  of a fall + a `RAGCOL rest` line; `kick` = the biggest upward speed a ground contact left a part with). Found: (1) a
  part pushed out of the ground / a rock kept the push-out as speed (Verlet), ~7 m/s up from a 2 cm overlap; (2) HEAD
  HIT crashes upside down in a flip started with up to 12 joints 0.83 m in the ground: `kick` 68-90 m/s, the body
  thrown 6-14 m up; (3) the startle reflex added ~0.7 m/s up to the whole body. Now (`ragdoll.gd` CONTACT): the
  push-out moves the part only and its speed into the ground (along the ground's normal, `_gn`, read again only after
  the part moved 10 cm) is taken out, a hit over `BOUNCE_MIN` 3 m/s keeps `BOUNCE` 0.12 of it; friction is Coulomb on
  the normal speed really taken out (`_jn`: g h at rest, the whole hit on a slam), `ROUGH_MU` 1.6 (more grip);
  rocks / trunks the same (`_surface_v`, `ROCK_SLIDE`); buried joints at the crash start are set on the ground and the
  bones settled round them with no speed (`_unbury`); the startle's net push is taken back out; every part capped at
  `MAX_V` 40 m/s; a non-finite step falls back to the last good state; only shapes the body can reach are tested
  (`_near`). Same flip crashes: rise 14.4 -> 0.0-1.2 m (the rest is the body tumbling over itself); an 18 m/s bail
  at rest in 1.45 s (was 3.1); crash physics ~0.2 ms a frame cheaper. `BMX_OLD_RAGCOL=1` = the old contacts. Test:
  `BMX_SEED=4242 BMX_FOLLOW=1 BMX_BIGAIR=1 BMX_TRICK=back BMX_RAGCOL_PROBE=1 BMX_RAGDOLL_PROBE=1 --autotest=70`.
  **Solver in C# (2026-11-24)**: the 6 solver passes per substep (bones, limits, ground + rock / trunk contacts) run in
  `rider/RagdollSolverCs.cs` (`Solve`; ragdoll.gd `_solver_cs` builds the constraint list once per substep, torn-off /
  broken joints left out, and keeps the friction, muscles, spin fix and probes). Made + run once when the ragdoll is
  built (its first load / JIT was a 2.8 ms frame on the first crash). Per crashed frame: solver 0.27 -> 0.11 ms, worst
  frame 0.55-0.7 ms; the whole ragdoll ~0.35 ms. `BMX_RAG_GD=1` = the GDScript passes (also used with `BMX_OLD_RAGCOL`);
  `BMX_RAG_CMP=1` runs both from the same state every substep (`RAGCMP max_diff_mm=`: 0.03-0.6 mm, float rounding,
  with and without rocks near). The frame profiler times its phases (`rag.*`) and `BMX_PROF_AVG=1` prints each
  section's mean over riding vs crashed frames (`PROF AVG`).
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
- **Realistic light (2026-11-26, user: "overblown at some times of day, use realistic values"; research + numbers in
  `docs/research/lighting.md`)**. Supersedes the energies / exposures / AE bands / ambient colours below. The light comes
  from physics: `world/sun_sky.gd` (`SunSky.state(el, L)`): the sun's direct light + colour per RGB channel through the air
  (Kasten-Young airmass x optical depths: a low sun is DIMMER and redder; the old code made it brighter), the clear sky's
  light (IES fit; ~10x per 2.6 deg of twilight), moon 0.15 lux + stars, exposure from that illuminance (Ghost of Tsushima)
  with full adaptation by day, darker toward sunset and ~4 stops under at night, folded into the light energies so
  `env.tonemap_exposure` is one constant (`Game.RIDE_EXPOSURE` 1.2; no auto exposure in rides). The sky's brightness is
  measured: `world/sky_meter.gd` (`SkyMeter`, a 2 x 1 px view in its own world, a white card lit by the same sky material)
  and `light_energy` = `energy` (one sky for view, ambient, reflections, fog) set so its light is what SunSky says
  (`Game._sky_level` / `_sky_meter_*`; runs only on a light change, every 2 s with the cycle). Ambient = the sky alone
  (contribution 1), fog colour from the sky (aerial perspective 1), haze lit 1x the sun (was 2.6-3x), volumetric ambient
  0.2, bloom = 4 % mix with no threshold (was softlight), grade neutral, AgX contrast 1.25. The painted sunset sky only
  under ~10 deg. Light tab defaults: rim 0, rider match 0, glare 0.5, saturation / contrast 1 (old saves reset once,
  `LightSettings.VER` 2). Bike beams x2.75 (`BikeLight.BEAM_GAIN`). The RACE-step preview (`ui/lens_scene.gd`) uses the
  same model + its own meter. The title screen keeps its old look. Tests: `BMX_LIGHT_SWEEP=1|h1,h2..`
  (+ `BMX_LIGHT_SWEEP_SHOTS=dir/prefix`, `BMX_IDLE=1`, `--autotest=` ~3.5 s an hour; `game/light_sweep.gd`: `LSWEEP` frame /
  rider mean, p98, % clipped / crushed, the light's numbers), `BMX_LIGHT_PROBE=1` (`SKYMETER` lines), `-s
  res://tools/sky_meter_probe.gd` (needs a window: the card must follow the sky 1:1). Not done: cloud cover / weather in
  the model (clear sky only), the title screen, a per-HDRI sun-clamp review.
- **Light Lab (DEV ONLY, same day, user: "sliders so we can adjust ... strictly developer stuff")**: `core/light_lab.gd`
  (`LightLab.v(key)`), tuning card Light > **Lab**: exposure (base 1.2, EV of full adaptation, dusk / night darkening),
  sun + sky (air haziness = aerosol turbidity, sky vs sun, moon lux, painted-sunset cut-off), haze (sun in haze, sky light
  in haze, density, glow round the sun, aerial perspective), tone (AgX contrast / white, bloom mix, night colour), lens
  grade strength. Live; SAVE writes `res://data/light_lab.json` (only changed values; the game reads it at start, so
  saved values ship as the defaults; players have no way to change them). Tests: `BMX_LIGHT_LAB="k=v,..."`,
  `BMX_LIGHT_LAB_FILE=0`, `BMX_PANEL=light BMX_PANEL_CAT=2`. Belongs with the dev tools for the release pack check.
- **Dusty atmosphere, warm photo white balance, lens fringes, real motion blur (same day, user: a Riders Republic shot:
  "far fog like that to hide distant low-poly mountains", "nice warm light like a photo", "chromatic aberration",
  "no fixed side blur, just motion blur from the environment")**. All Light Lab knobs. (1) The sky toward the horizon
  turns the haze colour (`sky_hdri.gdshader` `haze_amt` / `haze_col` / `haze_height` / `haze_lum`) at exactly the
  distance fog's brightness, so far hills melt into the sky with no edge; the fog is lit by the model
  (`Game.haze_light`: sky light x1.3 + a share of the sun, x `haze_bright`; `Game.hazy_colour`), not the blurred sky
  (aerial perspective alone made them dark grey silhouettes); fog full at `fog_far` 450 m, falloff `fog_curve` 0.85,
  thickness `far_fog` 0.97. (2) `wb_warm` 0.18: a camera white balance in the lens LUT (also with the Clear lens).
  (3) `lens_ca` 0.22: corner colour fringes in `grade.gdshader`. (4) `fx/motion_blur.gd` (`MotionBlur`, compositor
  effect, `shaders/post/motion_copy.glsl` + `motion_blur.glsl`): each pixel smeared along Godot's motion vectors
  (shutter `motion_blur` 0.35, max `motion_max` 32 px, 12 taps, pixels under 1.5 px and slow samples left sharp: the
  rider), off in photo mode / replays, `BMX_MBLUR=0` = none. The old fixed side blur is `blur_amount` 0 now. Not measured:
  the motion blur's GPU cost (other programs held the GPU); the haze is the same in every biome.
- **Goggle lenses = film grades (same day, user: "like the artsy downhill films")**: `rider/goggle_lens.gd` grades have a
  matte black, pivoted S-curve, hue bands (`bands`: hue / width / shift / sat / val), film saturation fall-off
  (`sat_fall`), split toning, shoulder; 33^3 LUT. New lens Red Line (`cine`); every lens regraded (see the research doc).
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
- **Main menu from a ride is a swap (2026-11-26, user: "main menu sometimes takes a long time, it should be instant")**:
  RIDE no longer frees the title backdrop Game: it is parked whole (`main._park_title`: its own never-drawn SubViewport,
  process disabled, its sounds paused). Pause > Main menu (`_menu_from_ride`) parks the ride the same way as
  `ride_ready` (`_park_ride`) and moves the title world back in (`_unpark_title`); RIDE then takes the ride back via
  `_take_prebuilt` (rebuilt if seed / bike / build / rider changed). Before: the menu moved the rider to `TITLE_SPOT` on
  the ride's own world and built every chunk there in one frame (`_to_hilltop`, 0.7-2 s, longer the further you had
  ridden). Also: `FarHills` joined its backdrop build on `_exit_tree`, so every move of a world between viewports
  waited for it (~0.85 s); it now joins on PREDELETE. Now: Main menu ~19 ms, RIDE again ~19 ms, RIDE from the title
  ~47 ms. Cost: the other world stays in memory (not measured). `BMX_NO_TITLE_PARK=1` = the old way. Test:
  `BMX_SEED=4242 [BMX_INTRO=still] BMX_MENU_LOOP=ride,menu,ride_again,quit (seconds) [BMX_MENU_LOOP_SHOT=prefix]`
  + `-- --shot=x.png@999` (title launch): `MENULOOP <step> ms= ... reused=` and frames drawn after each step;
  `BMX_MENU_AT=secs` with `--ride` = Main menu only.
- **The title is a fixed place loaded from a file (2026-11-26, user: "in my menu no random chunk generation, a small
  specific level, the same all the time, fast load, ultra light"; the sign behind the rider stays)**. `world/title_terrain.gd`
  (`TitleTerrain extends Terrain`, like the playground's): loads `assets/title/title_land.bin` (zstd `store_var`: the 7 x 7
  chunks round `Game.TITLE_SPOT` of `TITLE_SEED` exactly as the chunk builder made them + the far hills' 20 m ring arrays) and
  turns them into nodes once (`Terrain._finalize_out`, split out of `_finalize`). No `TerrainField.setup` (an empty field
  with an empty trail), no chunk building / streaming / worker threads, no rebuilding far hills (`FarHills.load_baked`,
  `baked`), no sheep. Heights = the saved drawn grids + rock domes. Made by `res://tools/bake_title.tscn` (a scene, not
  `-s`: Terrain needs the autoloads); **re-bake when the chunk builder / terrain field / far hills change** (it prints the
  biggest parts of the data). Measured: title build 6.0 -> 2.9 s (land 4.1 -> 0.75 s: file 0.5 s, nodes 0.2 s), menu
  step 0.64 -> 0.13 s; frame time, draw calls, triangles about the same (4.5 ms, ~620 draws, 3.4M triangles). Left: the
  player's bike is now the biggest part (~1.2 s); the file is 30 MB (most of it the full-detail ground mesh: the
  narrow menu lens sees far chunks large, so coarser LODs were not tried); the title still runs the ride's other
  systems (HUD, dust sim, blood, replay: ~0.4 s). `BMX_TITLE_PROC=1` = the old generated title. Export includes
  `assets/title/*.bin`. Probe: `BMX_TITLE_PROBE=1 [BMX_TITLE_PROBE_SHOT=png]` + `-- --shot=x.png@99` (`TITLEPROBE build
  game= menu=` and frame time / draws / memory, then quits).
- **The RUNOUT sign is back in view (same day, user: "where is our runout sign?", "hand placed level, make it perfect")**:
  the 2026-11-25 land work (mountains / erosion) raised a ridge 58 m high 120 m in front of the old title view, and the
  sign (170 m out, feet at eye + 7 m) stood inside it; the old generated title had it too. A survey of every direction from
  the lookout (land drops 70-110 m almost everywhere except that ridge) picked 260 deg: `TITLE_SPOT` heading 1.4399 ->
  4.0379 (camera, rider, sun and sign turn together). Sign placed by eye: `SIGN_D` 80 m, `SIGN_SIDE` 0.06, `SIGN_H` 0.058,
  `SIGN_UP` 8.2 m (letters clear above the helmet, beam behind it, between the menu card and the top-right buttons); its
  materials ignore fog and the letters glow a clean white (`title_sign.gd`: haze had washed them into the sky). Check:
  `BMX_SIGN_PROBE=1` (ground along the view to the sign vs its feet), `BMX_SIGN=d,side,h,up` / `BMX_TITLE_SPOT=x,z,heading`
  to try others. The land bake doesn't depend on the heading (no re-bake needed).
- **Pause leaflet opens instantly (same day, user: "the pause menu pamphlet was heavy")**: one `PausePamphlet` for the
  session (`main._leaflet_get`), built when a ride starts (`_leaflet_warm`), refilled per pause (`PausePamphlet.prepare`:
  photo, place, menu lines), put away instead of freed. Its cover photo is drawn from the whole frame with a source rect
  (the GPU scales it; the CPU Lanczos crop + resize was ~11 ms). Before: every Esc built it (first ~107 ms + a 72 ms frame,
  later ~17 ms + a 20-55 ms frame). Now: ~4-12 ms on the press (the frame readback is most of it), first Esc of a ride one
  25 ms frame (paper shaders), later worst 7-11 ms. Drawing its render targets once at ride start was tried: paused frames
  went 6 -> 14 ms, not done. Probe `BMX_PAUSE_PROBE=1` (+ `--ride --autotest=24`): Esc every 4 s, `PAUSEPROBE` lines.
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

- **Fonts: all embedded, nothing from the OS (2026-11-24, user: "all users must see the same font", "light and performance oriented")**.
  No `SystemFont` anywhere (grep must stay empty); every font is a FontFile in `assets/fonts/` with `allow_system_fallback` off (import files + set
  again in `UITheme.file`), so a player's installed fonts never change the look. Subset to Latin + the symbols the UI draws, hinting stripped
  (`pyftsubset`; ~323 KB for all 8 files, Doto 457 -> 131 KB): Barlow Bold / Black = UI (`UITheme.font(black)`), Barlow Condensed Bold / Black =
  display (`display_font(weight, slant)`), Anton = the WASTED / banner / pops MSDF face (`punch_font`), Caveat Bold = handwriting (`hand_font()`),
  Symbols = merged Noto Sans Symbols + Symbols 2 (stars, arrows, triangles, check marks, trophy) as the fallback of every UI font, Doto = the bike
  computer. Project default font = Barlow Bold (`gui/theme/custom_font`). Glyphs not in the set: add them to the subset (`↺ ━ ⅒ ▮` were replaced in
  text). Never write a font name in code: go through `UITheme`. Specimen sheet of every face: `res://tools/font_specimen.tscn -- out.png`.
  Metrics differ from Bahnschrift: place display text by cap height (the title logo does), not by ascent. Credits lists all four OFL families.

### Rider profile, wallet, goals, badges, cards (2026-11-25, user: "Strava / Zwift-like profile ... game logic that brings players back")
- **Title menu**: the RIDER line and the RUNOUT logo are gone from the card. Top right: wallet chip (`Shop.fmt(GameState.money)`) + avatar button
  (`ui/profile_icon.gd`, red dot = something to claim) + gear + QUIT; both open the profile. The game's name is a big white **hillside-style sign
  behind the rider** (`world/title_sign.gd`, made by `Game._make_title_sign`: letters on a gantry at rider height, `BMX_NO_SIGN=1` off).
- **Profile** (`ui/profile_page.gd`, `ProfilePage`, full screen, dark, `BMX_MENU_PAGE=profile BMX_PROFILE_TAB=0..4`): left = the rider as a magazine
  hero shot (`BikeTurntable.hero_stage`: low close camera, wide lens, rim lights, standing idle), level ring + name (click to rename) on top,
  CUSTOMIZE RIDER (opens the rider room) + XP bar at the bottom; wallet top right. Tabs: OVERVIEW (week ring, streaks, claimable, stats, 12 weeks),
  GOALS, BADGES, CARDS, WALLET (ledger). Numbers count up / rings fill / cards fade in. LB / RB change tab on a pad.
- **Money** (`GameState.earn / spend / wallet_log`, 60-entry ledger, `records.earned`): rides pay `RIDE_RATE` $0.03 / m as you go (one growing "Ride"
  line), the day's first activity pays a **daily bonus** ($50 + $25 x streak day, max 10), goals + badges + cards pay on collecting; `buy()` logs
  shop spends. Prices are the shop's ($6k-23k bikes), so a long ride is ~$300.
- **Goals** (`core/goals.gd`): weekly (distance = 10 % over the last 4 weeks' average, 3 rides, 3 active days) and monthly (4x distance, 12 days,
  20 rides), progress read from `GameState.days`; pay only when CLAIMED in the profile (`GameState.claimed`). `Goals.claimable()` drives the dot.
- **Badges** = performance milestones (`Steam.ACHIEVEMENTS`, 20; now recorded locally in `GameState.achieved` whether or not Steam runs, each pays
  `Steam.REWARDS`): drawn as medals (`Collection.badge_tier/colour/glyph`: bronze .. platinum by reward), click one -> 3D metal medal you drag to spin
  (`ui/collect_stage.gd` `show_badge`). Badges are saved in save.cfg (`achieved`); tricks landed (`tricks_seen`) feed the STYLE rating.
- Not done: card pack / reveal animation, sound for claiming, per-biome cards, mouse tilt of the grid thumbnails, tests with a real mouse
  (the tilt was checked by the shader's static look only), cloud save.

- **3D badges after CycleIQ (2026-11-25; the holo CARDS and the rider card were built and then removed on request: "only keep 3d badges")**. Source of the
  look: `C:\Users\Luka\Downloads\CyclingHub\js\badges3d.js` (`BADGE_PROCEDURAL`: a shape + colour per badge). BADGES tab: a grid of badges each drawn as its own
  shape (`Collection.badge_look`: circle / hexagon / diamond / star / shield, by what it is for) in tier metal; click one and `ui/collect_stage.gd` `show_badge`
  shows it in 3D: the shape extruded, an enamel inset in its colour, its symbol raised on both faces, reflecting CycleIQ's rainbow environment map
  (`_rainbow_tex`); drag to spin, it carries on and settles into a slow turn. Not ported: the Half Year portal, GLB badge models, the card views.

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
- **Hair sim moves with the head (2026-11-24, user: "the braid flaps really bad when speeding, almost glitches")**:
  `hair.gd` was a world-space Verlet stepped at a fixed 1/60 s (max 2 a frame): above 60 fps a third of the frames drew
  no step, so at speed the locks were left ~20 cm behind the head and snapped back; the drawn head's bob / bump shake
  went in undamped too. Now the guide points are offsets from the head (world axes), stepped every drawn frame in
  sub-steps of <= 1/120 s (head turn slerped across them); the ride comes in only as forces: air streaming past
  (`STREAM_K` x speed, max `STREAM_MAX`), a push from the head's acceleration smoothed over `A_EASE` 0.15 s
  (x `INERTIA` 0.5, max `ACC_MAX` 7 m/s^2), flutter x up to 2 with speed; per-step pulls rescaled to the step
  (`_rate`). The plait's width axis is carried down it by parallel transport (it flipped where the plait swung
  sideways). Probe `BMX_HAIR_PROBE=1` (+ `BMX_LOOK=hairStyle=braid BMX_STRAIGHT=1 BMX_START_V=16 BMX_FPS=60|144`):
  `HAIRPROBE jerk_rms_mm` (the tail's mid / tip 2nd difference per frame in the head's frame), `stale`, `wflip`,
  `tip_back_deg`. ~60 km/h: 144 fps 210-330 -> 4-10 mm rms, 60 fps 18-53 (max 275) -> 7-13 (max ~50).
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

### HQ still + bike edges (2026-11-24)
- **HQ still** (`fx/hq_still.gd` + `fx/hq_accum_effect.gd` + `shaders/hq_accum.glsl`): in the garage showroom (bike mode)
  and photo mode, once the camera rests (garage: 1 s without camera input, the handheld sway then holds still), every
  frame is rendered again shifted by a fraction of a pixel (tent filter ~1.6 px, via a frustum projection equal to
  the camera's) with each shadow-casting light wobbled a little, and averaged on the GPU before glow / tonemap
  (128 samples, ~1 s in the garage). TAA is off while it samples. Any camera / light move, or `hq.reset()` (garage
  part / paint change), starts again. Photo mode's shot waits for it. Costs nothing while moving. Tests:
  `BMX_HQ=0` off, `BMX_HQ_SAMPLES=n`, `BMX_HQ_PROBE=1`.
- **Edges**: `AoBake.Edges` bakes sharp convex edges per vertex beside the AO (bike_ao.gd, cached, VER 5) into
  COLOR.a as 1 - edge; the car paint bends the normal there towards the eye (`bevel` 0.35: a rounded edge's
  catch-light). Paint chips (`wear`) are in the shader but OFF: the user wants every bike mint; for a used-bike
  look later. Tests `BMX_BEVEL=0`, `BMX_WEAR=0.6`.
- **Stanchions are never black** (user): always a coating, `BikeBuild.STANCHION_COATS` silver chrome / gold / bronze
  (any colour snaps to the nearest, black -> bronze), the whole tube from the top crown to the lowers like real DH
  forks (user, 2026-11-24; a version with only the sliding part coated was tried and dropped).
- **Stickers wrap round tubes** (`BikeDecals._wrap_uvs`): flat projection stretched a sticker's edges ~3x on a
  3.3 cm tube; the patch's tube is fitted (centre + radius from points + normals) and the sticker is laid out by
  distance round it, like vinyl (fitted twice: the points off the first circle, a fork's brake mount / arch, are dropped). Flat where the fit fails / r > 25 cm. `BMX_DECAL_FLAT=1` = old, `BMX_DECAL_PROBE=1`.
- **Garage outside, cheaper** (`Garage._build_outside`): only the chunks seen through the door are built (a 70 deg
  wedge out of the door, `Terrain.stream_filter`): 26 of 49, near build 327 -> 223 ms (`BMX_GARAGE_ALL_CHUNKS=1` =
  all). And it is kept between visits: the garage parks it out of the tree when freed (static `_kept`, per seed),
  the next garage of the session takes it back (outside ~2 ms instead of ~590, garage open 2.0 -> 1.2 s); main
  frees it on quit (`Garage.free_kept(true)`). `BMX_GARAGE_NO_KEEP=1` = rebuild every time, test
  `BMX_GARAGE_REOPEN=secs` (back to the menu after secs and into the garage again).

- **Studio set for the shop** (`garage/studio_set.gd`, `StudioSet`, not used anywhere yet): cyclorama, softboxes seen
  only in reflections (`PANEL_LAYER`, keep it off the camera), strip lights, top scrim, backdrop glow, reflection
  probe, its own `env`. User decision: the garage stays the personal workshop for owned bikes; a future SHOP shows
  bikes for sale in this showroom look (with the HQ still). **The shop = the showroom store**: everything is bought
  there, whole bikes down to single components (forks, shocks, wheels, tyres, bars, brakes...), each shown in the studio.

- **Prices = today's market** (`core/shop.gd`, 2026-11-24, user: "top bikes cost 25k like a car"): frames by class
  $1.6k / 2.9k / 4.6k / 9.5k, plus a `kit` per class for the parts with no card (drivetrain, brakes, cockpit:
  $1.5k / 2.6k / 4k / 7k), forks $1.4-2.8k, rear shocks priced now ($450-1,350), built wheels alloy $300 /
  carbon $1,500 each, bars alloy $120 / carbon $220. Showroom bikes come out $6.3k (Midnight Owl) .. $23.2k
  (Rusty Nail); a fully maxed build goes past $25k.

### Shop (2026-11-24, user: "a major part of our game: buying stuff and customizing it")
- Title menu SHOP / `--shop`: the garage scene in mode "shop" (`Garage.mode`), the StudioSet instead of the room,
  `garage/store_page.gd` (`StorePage`) runs it. Tabs (`Catalog.TABS`): BIKES, FRAMES, SUSPENSION, WHEELS, COCKPIT,
  BRAKES, DRIVE, SEAT, LIGHTS; cards worst -> best (`Catalog.TIER_NAMES` BUDGET / SPORT / EXPERT / PRO / FACTORY,
  price tag, green OWNED badge); the left card = the product (tier, spec, what it does on the trail, price, your
  cash -> after, BUY / OWNED / NEED $x MORE, FIT TO MY <BIKE> for owned parts). Bikes / framesets roll in onto the
  stand; parts are shown fitted to YOUR bike (its saved build) with the camera on them (`StorePage.VIEW`). Looking
  never saves anything; the garage keeps `GameState.bike_id` (the shop's frame on show is `Garage._shop_frame`).
- `core/catalog.gd` (`Catalog`): every product. Kinds with several models already (complete bikes = editions,
  frames, forks, shocks, rims as built wheelsets, tyres as a pair, bars, cassettes, lights) sell those, tiers from
  the existing part scores / price rank. The small parts (rotors, calipers, levers, stems, saddles, posts, pedals)
  are `VARIANTS`: 5 brands / tiers each on the 2-3 existing looks; `build.sku[kind]` = the product, and
  `Catalog.ride_perf` (via `BikeBuild.ride_mods`) gives a tier step a few % on brakeGrip / steerRate / popPower.
- Wallet: `GameState.money` (new save `STARTING_MONEY` $15,000), `GameState.owned` ("kind:id"), save.cfg [shop]; a
  new player owns the stock RUNOUT DH's parts + `Catalog.STARTER`. Nothing earns money yet; `Shop.UNLOCK_ALL` still
  lets the garage use every part. Test `BMX_MONEY=n`.
- Buying = a reveal (`garage/store_purchase.gd`, `StorePurchase`), not a dialog / confetti (user): the UI slides
  away, cinema bars, the studio goes dark and its lamps come back one by one with a fluorescent flicker
  (`StudioSet.lamps` / `set_lamp`), the camera pushes in, the name stamps on letter by letter (white-hot -> yellow,
  a glint sweeps across), stars pop in, PAID + cash ticking down, then FIT TO MY BIKE / CONTINUE. Silent until the
  user gives a recording. Studio: no bloom (it hazed the clearcoat white), softbox panels glow ~2x.
- Tests: `--shop`, `BMX_GARAGE_TAB=<store tab>`, `BMX_SHOP_PICK=<kind:id>`, `BMX_SHOP_BUY=1` (buys the pick 2 s in),
  `BMX_SHOP_POP_AT=secs` (freezes the reveal), `BMX_SHOP_PROBE=1`.
- Not done: earning money, the garage only offering owned parts (flip `Shop.UNLOCK_ALL`), owned complete bikes as
  separate garage bikes, parts' own 3D looks for every variant (they share 2-3 looks), a purchase sound.

### Effects
- **Water + mud on the lens (2026-11-24, `fx/lens_fx.gd` `LensFx` node + C# `fx/LensDropsCs.cs`, Settings › Gameplay ›
  Water + mud on lens `lens_fx`)**. Research: Nakata / Kakimoto / Nishita "Real-Time Animation of Droplets on a
  Hydrophobic Windshield" (drops = mass points, contact-angle pinning, gravity, air drag) + Kaneda et al. 1993
  (meandering rivulets, water left behind). Each drop: pinning ~ r (varies over the glass: stop-and-go, meander),
  gravity ~ r^3, the air ~ r^2 x airspeed^2. Moving forward the air streams the water DOWN the glass, fanning out a
  little at the sides (`FAN`); a camera turning throws it to the outside (its acceleration): slow = drops crawl down,
  fast = big drops let go first and stream down and off, small beads stay. (Tried and dropped: a radial flow out of the
  view's middle, "like a Star Wars hyperspace portal"; up the glass like a car windshield, "inverted".) Rivulets dry `RIVULET_LIFE` 1 s behind a
  drop (faster in the wind). Drop size: `LensDropsCs.SIZE` 1.215 (forces scaled with it).
  Running drops leave beads + a rivulet and swallow what they hit (merge, volume kept). Drawn into a half-res lens
  NORMAL MAP: rivulet SubViewport (never cleared, HDR, dried by `lens_dry.gdshader` blend_mul) under a drop SubViewport
  (`lens_drop.gdshader`, premultiplied rg slope / b height / a cover); `grade.gdshader` refracts the scene through it
  (`shaders/lens_fx.gdshaderinc`: flipped + out-of-focus view inside drops, dark rim, highlights tilted by the curved
  front element, squeezed toward the rim). The air comes from the CAMERA's motion (`LensFx.update`: its velocity /
  acceleration in its own frame), so the side cam's water runs sideways, a still trackside cam has none. Shown on the
  default trail camera only (user). **Dust** (mud splats were tried: "very ugly", removed): one level `lens.dust`
  0..1, built riding fast through dry dirt / sand dust (+ a bump on a crash there), washed off by water, cleared on
  respawn; drawn from `assets/textures/lens/lens_dirt.png` (4096 x 2304, `tools/make_lens_dirt.py`: R ambientCG
  Smear004 roughness, G SurfaceImperfections001 opacity, both CC0, B generated specks / fibres; no round blobs /
  water rings: the user disliked the circles), each layer fading in from its own threshold, only toward the corners
  (old-CRT rounded falloff), its own colour (smears / smudges = the ground's dust colour, specks paler, slow warm /
  cool drift), softening the view and glowing where light comes through; water on the glass cuts clean paths in it.
  `lens.rain` is ready for a weather system. Clean glass = viewports stopped, shader skips it. No C# = dust only.
  **Spray drops, sim-style (2026-11-25, user: "a drop stays half a sec then runs away, irregular, like the PlayStation racing sims")**:
  each drop has an age + a hold (`_hold`: splash 0.3-0.5 s, rain 0.1-0.35 s) during which its pinning is x41, easing off over
  `HOLD_EASE` 0.3 s, so a splash drop lands, clings ~0.5 s, sags toward the push as it nears letting go (`_load`, drawn as a
  teardrop), then runs. Running drops wander: their own random-walk heading (`WANDER` 0.75 rad, `WANDER_RATE`) + a time noise
  on top of the glass pattern, and stick-slip speed (`STUTTER` 0.8: catch, let go). A splash drop lands as a flat splat that rings
  into its bead (~0.3 s, drawn in `Buffer`), big ones throw a ring of fine mist beads. Shading: a caustic spot low inside each
  drop, a thin meniscus ring inside the dark rim (`lens_fx.gdshaderinc`), faint colour dispersion where a drop sits
  (`grade.gdshader`, only lwet > 0.3: faint drying rivulets drew fringes everywhere). Probe `-s res://tools/lens_drop_probe.gd
  [-- wind=0.8]` (`DROP n starts_moving= heading_change_sum=`); `BMX_LENS_SPLASH_EVERY=secs[,k]` splashes on a timer.
  Tests: `BMX_LENS_RAIN=0..1`, `BMX_LENS_SPLASH=k`, `BMX_LENS_DUST=0..1`, `BMX_LENS_WIND=0..1` (else the camera's
  speed), `BMX_LENS_DUMP=file.png` (the normal map + `LENS ... flow=` line, 10 s in).
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
- Dirt chunks. **Tyre tracks** are in the ground since 2026-11-25 (stamped into the rut field, drawn by the ground
  shaders: see "Tyre prints in the ground" under Ruts); the old ring-buffer mesh + `tyre_track.gdshader` are gone.
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
  **In C# (2026-11-23, user: "low fps sometimes")**: `world/TapeStripCs.cs` does each strip's Verlet step (`Step`, one
  call per strip per frame, float arrays inside) and builds every ribbon + the mesh in one call (`Draw`: indexed, vertices
  shared within each stripe colour, smooth normals; a strip's ribbon is rebuilt only when it moved, `redo`); `Warm()` at
  ride start JIT-compiles it. Strips over `LOD_NEAR` 30 m from the rider step every `LOD_EVERY` 3rd frame with the time
  added up. GDScript `_step` / `_ribbon` stay as the fallback (no C#, or `BMX_TAPE_GD=1`). Measured, 3 torn strips: ~0.34 ms
  a frame vs ~0.83 ms GDScript. The game's wind never drops below ~3 m/s, which keeps lifting the foil, so strips never come
  to rest (a sleep rule was tried: it never triggered). The "19 ms snap frame" first seen was the test's own `STAKE` print;
  the real snap frame is ~1.5-3 ms (stake debris, fresh ground reads). Probe `BMX_TAPE_PERF=1` (`TAPEPERF strips= avg_us=
  max_us=` per second; mutes the `STAKE` prints). Measure with no other game window open: another instance doubled the times.
  **Stretch fixes (same day, user: "stretch glitchy, don't stretch so much, sometimes ignores it")**: (1) the tyre keeps the
  spot of tape it first hit (`grab` index picked once): the grab used to be re-projected every frame, so riding across at a
  shallow angle slid it to the span's end, where it let go and the tape sprang back (every weaving crossing in a
  `BMX_FOLLOW=1 BMX_WEAVE=4.5` ride did that); now only backing out (`d < -0.35`) or a crash releases it, otherwise it
  stretches and snaps. (2) The slack side's sag (~sqrt(slack)) snapped the middle up in a frame or two as it pulled taut:
  eased (`SAG_EASE` 22/s). (3) Held spans re-read the ground every 5 cm, not 20. (4) `SNAP_STRAIN` 0.17 -> 0.07.
  Probe `BMX_TAPE_PROBE=1`: `TAPECROSS su= v=` (a hit), `TAPESKIP` (wheels over it), `TAPEREL` (let go), `TAPESNAP age=
  acc_median= acc_max=` (held points' acceleration in m/s^2: worst frames 280-1700 before, 40-130 after on the square-on
  test). `BMX_TAPE=dir/prefix` now also saves a shot every sample while the tape is stretched.
  **Then (user: "stretch kinda weird", "flickering when it snaps")**: (1) the tape catches where it would at its
  height: on the tyre's front below the tyre's top, else on the front of the fork (`TapeSim._contact`; `Game` passes
  `push_at` = {axle, fwd, axis (steering axis in world), r}); it used to wrap the tyre's leading edge moved up to 85 cm,
  a corner in mid-air half a metre ahead of the bars. The tyre's edge finds the hit first, so the tape stays as it hung
  until the fork reaches it (`d0`: backing out from there lets go). (2) The tape slides over the fork: both sides get
  their share of its length by distance (`ra` = length x la / (la + lb)) and the points are laid by length along it,
  the corner between two points (no fixed grab point: that stretched one side's stripes long). (3) **Flicker = the
  twist**: the ribbon's drift term was the ride's whole wind clock x the twist's 0..1 ramp after a tear, so minutes
  into a ride a torn half spun ~13 turns / s for half a second (a strobe); now the time since the strip was made
  (`tb`). (4) Torn halves keep their real piece lengths (`segs`; a uniform span / 30 is shorter and yanked them into
  loops) and whip back at `RECOIL` 3.5 m/s (was 7). (5) The ribbon's width direction is carried along the strip
  (parallel transport) and from last frame at its first point (no jump where the tape points straight up / down).
  "SNAP!" pops when it tears (`TapeSim.torn` -> `Game._on_tape_torn`). Tests: `BMX_TAPE_FRAMES=n` (+ `BMX_TAPE=dir/
  prefix`) = time at 0.15x from the hit and n frames kept in memory, written after (a png a frame dropped it to 4 fps);
  `BMX_WIND_T0=300` starts the wind clock 5 minutes in (the strobe only showed late in a ride).
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

### Jumps from the formula (2026-11-23, `scripts/world/jump_design.gd`, `JumpDesign`)
- One recipe for every built jump (after trailism.com/jump-design + the research folder's "MTB jump design considerations"
  sheet): clothoid take-off whose tightest radius is v^2 / (lip_g g) (1.5 g), a STRAIGHT lip `lip_t` s long (0.15-0.25 s:
  both wheels leave on one line, no kicky pitch), table deck / gap / kicker-to-flat, landing knuckle + straight + bottom
  transition (land_g); auto deck = as long as the flight at the design speed (`aim` down the landing), auto landing angle =
  the flight's angle there - 3 deg. `JumpDesign.predict` = point-mass flight + EFH for any run-in speed. Kinds: table | gap
  (`fill`) | kicker. Probe: `-s res://tools/jump_design_probe.gd -- v=12 lip_deg=26 ...`.
- **Trail jumps** TABLE / KICKER are baked from it: `tools/bake_jumps.gd` (designs in TRAIL_JUMPS) piped into
  `tools/bake_jumps.py` writes the knots + AIR spans into trail_features.gd AND TerrainFieldCs.cs (never hand-edit them).
  Designed for ~60 km/h real (the physics loses ~7 % more on a face than the formula): slower riders case the deck
  (EFH < 1 m). (DOUBLE / DOUBLE_S and TABLE_S / KICKER_S are baked from it
  too since 2026-11-24; `TAKEOFF_EXTRA` is 0 since then: hands off rides with the lip.) RHYTHM release beats have more kickers.
- **Trail drops** (`TrailCourse._drop_shape`): the face follows the flight of a rider at DROP_V 16 m/s (max 35 deg, a
  22 m bottom transition); was a smoothstep over 5 + 0.4 h m (42-51 deg, launched riders onto the flat).
  `BMX_OLD_DROPS=1` = old. Probe `-s res://tools/drop_probe.gd -- <seed>` (its landing column is not right yet).
- **Playground**: lane DESIGNED JUMPS (z -96, ids `dtable_<kmh>` / `dgap_<kmh>`; the test rider's auto speed starts at
  the design speed). **Ramp editor** (dev view, LAB row > RAMPS, `levels/ramp_editor.gd`): + ADD / DEL / MOVE (mouse; wheel
  turns; click drops) / RIDE (test rider on repeat), kind TABLE / GAP / KICKER, build DIRT / WOOD (slats + plywood sides,
  square edges), a slider for every number, side view with the flights at 85 / 100 / 115 % and EFH. Placed ramps
  (`PlaygroundCourse.PlacedRamp`, their own axis; `course.u_for` / `feat_point` / `ramp_zone` give the probe, pilot and
  overlay their frame) are saved in `user://playground/ramps.json` (not in tests; the suite never loads them).
  Tests: `BMX_PG_RAMP_ADD=1 BMX_PG_RAMP_SET=kind=kicker,build=wood,v=28 BMX_PG_RAMP_RIDE=1`, `BMX_PG_RAMPS=0`.
- `-s` tools that build terrain (terrain_cs_cmp, rope_find) run again (tape_sim no longer names the CrashLog autoload).

### Skilled hands-off jumping (2026-11-23, from research/jump: a lab study of a pro off a lip + its slow motion)
- Rider ~6x the bike: what he does at a lip decides the jump. Doing nothing = low (the old game: hands off popped ~0.15 of a
  push, no wind-up pose: "dead"). Now hands off he winds up into the transition (`prepTime` 0.8 s, `prepDepth` 0.22 m) and
  drives the legs straight LATE, in the last 0.1 s of the lip ("press later": the lab's +7 cm) at `autoPump` 0.75 of a
  full push (Tune VER 26). A player's well-timed pop is still more (1.0). `BMX_OLD_AUTOPOP=1` = the old one.
  Drawn: preload = max(the player's crouch, prep x autoPump), hips -8 cm in the preload / +13 cm in the extension (were -2 / +6).
- Measured hands off: dtable_36 peak 0.61 -> 0.96 m, dtable_43 0.99 -> 1.37 (timed pop 1.79), table_1.5 0.50 -> 0.75.
  Suite (not re-saved): jumps +0.1-0.2 s air; table_2 / gap_7 / drop_2 one more bottom-out; landings ~10 deg more nose up.
  Open: the stand-tall at the lip's edge is still muted by the pose limits; the lab's energy check counts the auto pop as
  an energy gain.

### Stand tall at the lip, tuck, smooth air control (2026-11-23, the whole research/jump video gone through)
- Pose (rider.gd, drawing only): `j_tall` = the extension through the lip + popFx just after: the air crouch held off,
  hips +10 cm, chest up (torso upright in the world while the bike points up); then `j_tuck` = the physics' `air_pull`
  (new pose input `airPull`): hips -15 cm, chest folded over the bars, the bike tucked under him; it goes as he reaches
  for the landing. Style key `airTuck` (no slider). `BMX_OLD_LANDPOSE=1` also turns these off.
- Air control was jagged with both sticks: (1) `Game._read_input`'s axis fade (a ground anti-manual filter) also ran in
  the air, snapping the off axis 0 -> full over 20 deg of stick (`BMX_OLD_AIRFADE=1`); (2) the in-air lean switched its
  target at |roll| 0.03 and its spring between leanIn / leanOut / 80 at stick 0.01 / 0.02: now blended, `AIR_LEAN_K` 36
  critically damped (a moment to get turning, `BMX_OLD_AIRLEAN=1`). Probe `BMX_AIRJERK=1` (+ `BMX_FOLLOW=1 BMX_BIGAIR=1
  BMX_PAD=1 BMX_BODY=circle2`: both sticks circling in the air), per flight: lean step jerk mean worst 1.35 -> 0.49,
  rms 0.215 -> 0.107; pitch / yaw unchanged.
- Test runs are forced windowed (`Settings._test_run`; `BMX_FULLSCREEN=1` overrides). The user wants test windows
  visible: don't use BMX_MIN any more. BMX_FOLLOW never brakes: it runs wide in later tight corners (test rider only).

### The pro move only after YOUR pump; the bike moves in the air, not the rider (2026-11-23)
- `pro_pop` / `pro_flight` (bike_physics.gd): a pop the player timed (`_pop_now` at a lip) or a crouch he held into it is
  his pump; the rider's own hands-off pop is not. Only a pro flight gets: the nose-up pull off the lip (`air_tilt` target
  + `AIR_PULL_UP` 0.4 rad x pop power, quick spring, held `PULL_HOLD` 0.4 s, then he levels it for the landing himself;
  the lip's nose-down kick soaked: air_w >= -0.15), the pull-up of the bike into the body (`air_pull`, airLift), and the
  drawn stand-tall / tuck (`popFx`, `airPull` pose inputs). Hands off: a plain jump. dtable_43 pumped: pitch 21 -> 34 deg
  at 0.45 s, then level; landings CLEAN on 4 features. `BMX_OLD_PULLUP=1` = before; probe `BMX_PULL_PROBE=1` (PULLP lines).
- In the air the rider's hip moves against the bike move the BIKE (`Rider.body_off` = hips vs take-off, Game moves the
  drawn rig `AIR_SHARE` 0.8 of it the other way, faded by land_prep, never down into the ground on landing): tucking pulls
  the bike up to him, standing tall pushes it away; his body stays on its arc. `BMX_OLD_AIRSHARE=1` = off. CLIP 0 frames.
- **AIR** (dev view LAB row, `PlaygroundLab.toggle_air_hold`, test `BMX_PG_AIRHOLD=1` prints `AIRHOLD` lines): the bike held
  `HOLD_H` 4 m up, gravity cancelled after every physics step (frame, wheels, body mass moved together), drifting at
  `HOLD_V` 1.5 m/s: try the air controls / rotation as long as you like; off = set down from 0.7 m. The lab's checks
  pause while held. Try `BMX_PAD=1 BMX_BODY=circle2` with it.
- Playground side cameras (pg_side / pg_wide / pg_low, `square`): a FIXED 8 deg (low: 4) down angle (dead level hid the wheels behind the jumps' side batters), no
  tilt / bank / shake / speed zoom: true side reference shots. Front 3/4 unchanged.

### Small bumps soaked up at speed; small free-ride jumps from the formula (2026-11-23, F8: "mini bumps propelled me a lot")
- The F8: two free-ride jumps out in the land (old `KICKER_S` / `TABLE_S`, kicky lips) hands off at 41-54 km/h threw him
  2.0 / 4.8 m up (49 deg nose up off the second). Two fixes:
- `TABLE_S` / `KICKER_S` baked from JumpDesign (tools/bake_jumps.gd `table_s` 1.1 m / 20 deg / 11 m/s, `kicker_s` 0.56 m /
  16 deg / 9.5 m/s, within their old footprints), `AIR_S` too. terrain_cs_cmp EXACT, wood_edge_probe walls=0.
- Hands off the rider reads the lip (`lip_h`, measured when first spotted): a small one (fully under `ABSORB_SMALL` 0.9 m,
  none past `ABSORB_BIG` 1.3 m) taken faster than it needs (`ABSORB_V0` 6 + `ABSORB_VH` 5 x height, m/s) he soaks up
  (`auto_absorb`, the faster the more: MX vs ATV style skimming): no pop, and once BOTH wheels are off up to 60 % of the
  climb taken out, speed kept (`_absorb_k`; at the first take-off step the rear is still on the face and its spring gave a
  velocity change straight back - that is why the old squash did little). Your own pump / crouch always pops. Drawn as the
  squash pose. hop_0.4 @ 45 km/h peak 0.59 -> 0.09 m, hop_0.6 @ 40: 1.07 -> 0.36, hop_0.8 @ 50: 2.31 -> 1.11 (lands at 42 km/h,
  was 26); tables unchanged. `BMX_OLD_ABSORB=1` = off. Probe `BMX_PULL_PROBE=1` prints `ABSORB` / `TAKEOFF` lines.
  `tools/feat_at_probe.gd -- <seed> x,z ...` names the route feature at a spot (grows the trail there).

### Air step 1: the rider stays upright and facing the flight while the bike twists / lays over (2026-11-23)
- Research (docs in chat; sources: coaching guides, Tan 2014 in the library, MX vs ATV / Descenders): whips are carved in
  at the lip; in the air the rider only moves the bike against his body (pitch ~80 % bike, yaw ~55 %, roll easy); the
  shoulders / eyes stay on the trail. The physics already twisted (air_tw) and laid the bike (56 deg, 57 deg whip) but the
  DRAWN rider went with it: torso 60-66 deg from vertical (measured off the skeleton: `BMX_BODYUP=1` prints the torso's
  tilt from vertical, which way it faces vs the flight, the head's side offset; `BMX_ROLL_PROBE=1` the body roll terms).
- Causes + fixes (rider.gd, drawing only, only in the air, `BMX_OLD_AIRBODY=1` = before): (1) the ground caps (counter
  0.85, hips 0.85 / chest 0.95 rad, hips box z 0.22 m, torso sideways 0.6 rad) open to AIR_COUNTER 1.4 / AIR_HIP_ROLL 1.05 /
  AIR_HIP_SIDE 0.5 m / AIR_SIDE 1.2 with the air blend; (2) the roll pivoted about the pedals, swinging the chest 0.5 m from
  the bars - the arm-reach limit pulled it straight back: in the air it pivots about the chest (hands / chest stay at the
  bars, hips and legs swing out, knees over); (3) in a whip the torso's lean turns back against the bike's yaw (AIR_FACE
  0.7; more and the arms can't reach the grips: the shoulder twist does the rest); (4) knees keep LIMB_BAR clear of the bar,
  elbows clear of the OTHER leg (last frame's) in the air. Held whip (air:0.75,0): torso 66 -> 30 deg from vertical, faces
  73 -> 48 deg off the flight; whips on trail jumps: no body clipping beyond the old 0.1 % rear-wheel touch.
- **Step 2 (done): whips carved in at the lip.** The right stick held to the side in the last `WHIP_WINDOW` 0.35 s before a
  lip winds the whip up (`whip_load`, signed, full in `WHIP_WIND` 0.2 s); off the lip the bike swings out (`WHIP_KICK` 3
  rad/s x load) and the whip may go to `airWhip` (now 1.5 rad ~86 deg, Tune VER 27) x load; from the air alone only
  `WHIP_AIR_ONLY` 0.4 rad (taking off straight and throwing the stick does little, like the real thing). Holding the stick
  holds it; let go it unwinds over ~0.4 s (softer spring, critically damped), hands-off the landing help still straightens
  it. dtable_43, stick 0.7: from the air 20 deg; carved in 61 deg, back to 51 by touch-down. dtable_60 / 66 (new, end of
  the DESIGNED lane: 1.4-1.6 s of air): out to 62-64 deg, unwound to ~25 by touch-down, CLEAN. `BMX_OLD_WHIP=1` = before.
  Tests: `BMX_BODY=whiplip[:x]` (stick held from the lip spotted + in the air) / `whipair[:x]` (air only), `WHIPT` lines
  with `BMX_BODY_PRINT=1`; a scripted BMX_BODY stick now rides along with the test rider.
- **Jumps clear at their design speed (same day, user: "doesn't clear the jump")**: measured on the designed tables, the
  bike loses more on the face than the climb (`JumpDesign.FACE_LOSS` 0.39: v_lip^2 = v^2 - 2gH - 0.39 H v, +-10 % on six
  tables) and leaves `TAKEOFF_EXTRA` 8 deg (0 since 2026-11-24) steeper than the lip (the hands-off pop, the rear lifting): both now size the
  deck / landing (trail jumps re-baked: table deck 14.7 m, landing 30 deg). Gaps: the backside / landing face squeezed to
  70 deg when the gap is short (they pushed the landing mound out: the design speed came down in the gap / on its face).
  Auto landing angle capped at 35 deg (`LAND_MAX_DEG`), designs aim 20 % down the landing. `airAssist` stays 0.6 for the player (Tune VER 29
  put it back); only the playground's test rider gets 0.85 (`BikePhysics.test_rider` / `TEST_ASSIST`). The hands-off landing tilt aims at the slope where the flight comes down (`_landing_slope`,
  `_land_pitch`), not the ground under the bike (over a table: the flat deck). `BMX_OLD_LANDAIM=1`. Playground, speed
  learning on: every designed table and gap lands on its landing, CLEAN. Still open: they come down 25-40 deg nose-up vs
  the landing - the tilt the rider can give (airTilt 26 deg) can't turn the bike from +35 to -35; the shared spin is damped
  to 0 hands-off (arcade). Tried and reverted: a take-off spin / an eased in-flight spin to the arc: still rotating at
  touch-down = NOSE DIVE verdicts. Needs a proper look (the touch-down judge vs the spin, how much spin a lip should give).
- **Step 3 (done): tabletop + scrub.** Tabletop = the right stick to the side in the air: `stickAirRoll` is now the
  lay-over at 0.8 of stick (1.25 rad, Tune VER 30; it was x times the stick, ~50 deg max short of the spin edge): 51 deg at
  half stick, 66 deg near the edge; the drawn bars turn against the lay-over (`Game.BAR_TABLE` 0.4, `BMX_OLD_TABLETOP=1`).
  Scrub = the stick diagonal (forward + side) into the lip: the absorb + the whip's wind-up + the lay-over fall out of the
  existing pieces: dtable_49 @ 50 km/h take-off 34 -> 22 deg, peak 1.8 -> 0.8 m, laid 55 deg, lands PERFECT. Style:
  "SCRUB" (+400: soaked take-off with lay-over / whip), "TABLETOP" / "BIG TABLETOP" (laid > 52 / 66 deg, back up for the
  landing). Test `BMX_BODY=scrub`. Shoulders in the air are placed on the TORSO's frame (`Rider.shoulder_at`; on the bike's
  axes a rolled torso put a shoulder above the chest: "the shoulder pops off"), and the whip / tabletop shoulder twist is
  held to what both arms can still reach the grips from. `BMX_SKEL_PROBE` worst 0.000 m. Open: the held tabletop looks
  like he hangs off the high side (head ~1 m out) - user to judge.
- **Step 4 (done): landing legs by the impact.** In the air `land_vn` = the predicted speed into the landing square to
  its slope (at `_land_pitch` / `_land_t`, the predicted touch-down; else the ground below), `land_reach` = 0.35..1 of
  `legExt` (full from ~4 m/s), and a hard one starts reaching up to 1.4x earlier (`landPrepTime` scaled). The drawn reach
  (`landReach`) follows it. Drops to flat (vn 4.4-6.3): full reach earlier, hit 0.56 -> 0.29, 2.06 -> 1.67; a matched
  landing (table_1.5, vn 2.2): 59 % reach, stays in his stance. `BMX_OLD_LANDLEGS=1`; `BMX_LAND_PROBE=1` HIT lines now
  print `vn= reach=`. Suite: nothing new.
- **Step 5 (done): the landing angle decides the speed (MX vs ATV All Out).** At touch-down after a jump (air >
  `landPerfectAir`), a bike pitched off the landing slope loses speed: none within `LAND_ANGLE_FREE` 0.26 rad (~15 deg),
  smoothly up to `landAngleCost` (0.25, new slider Ride > Jumps > Landing) x the speed at 35 deg+; "BAD LANDING -n km/h"
  when it is more than ~4 km/h. The PERFECT LANDING boost (< `landPerfect`) is unchanged, so: matched = boost, a bit
  off = nothing, way off = slow. Hands-off test rider (22-29 deg nose up): -2..-5 km/h, all CLEAN. `BMX_OLD_LANDSPEED=1`
  = off; `BMX_LAND_PROBE=1` prints `LANDANGLE err= cut=`. Suite baseline re-saved (it predated the whole jump / brake
  work of the day).

### Steer in the air + landing carve (2026-11-25, user: "come out of a berm, pump, turn in the air to land square and ready for the opposite turn")
- A / D / the left stick (`roll_keys`, same lock rule as before: a steer held from the ground counts once moved) now YAW the bike in the air by up
  to `airSteer` 0.6 rad off the travel (`_air_steer_s`, added to the whip's hip-twist target `tw_t`; eased in over `AIR_STEER_RAMP` after
  `AIR_STEER_DELAY` 0.04 s, less while spinning flat; hip spring `AIR_STEER_K` 190 while steering, so a 0.3 s hop gets ~30 deg). The bike banks
  into it (`airPrelean` 0.5 x the offset, on top of `airRoll`). The right stick is untouched (tilt, lay over, whip, spin, flip).
- **Landing carve** (`landCarve` 0.8, touch-down block before the sideways rule): a heading within `CARVE_MAX` 0.7 rad of the travel, on the side
  you steered, swings the travel round to it (course += heading offset x landCarve), `CARVE_COST` 0.15 x sin(turn) of the speed lost; what is
  left goes through the old landYaw rule. Hands off = steer 0 = nothing changes (playground suite identical with / without).
- Sliders: Ride > Jumps > "Steer in the air". `BMX_OLD_AIRSTEER=1` = off, `BMX_AIRSTEER_PROBE=1` (`AIRSTEER` 10x/s in the air, `CARVE` at touch-down).
  Test: `BMX_FOLLOW=1 BMX_TRICK=side` (alternates A / D). Not ridden by the user yet.
- **A steer held from the ground counts in a short hop** (user F8, 2026-11-25: keyboard, D held through a 0.1 s bump = "locked, no lean"): `roll_keys` was 0 for the whole
  flight when the key was held at take-off (`air_lock_a`). Now it counts in full up to `AIR_LOCK_FROM` 0.3 s of air and fades out over `AIR_LOCK_FADE` 0.3 s (a held key
  into a real lip is the old lock again). `BMX_OLD_AIRSTEER=1` = the old lock.
- **Next-bend aim** (`airAim` 0.6, 0 = off): hands off (no steer, no stick, not spinning) the bike is pointed at the trail's direction ~6 m past the predicted touch-down
  (`Game._aim_update` -> `phys.aim_off`, same sign as `slip`, only on the trail and only when the trail runs within ~70 deg of the travel; capped `AIM_MAX` 0.5 rad x airAim;
  `_air_aim_s` added to the hip-twist target next to the steer, banks with `airPrelean`, counts for the landing carve). The player's steer / stick takes over at once.
  Playground / levels without a course: no aim (the suite is unchanged). **Carve reward** (`carveStyle` 1, 0 = none): a carve of >= `CARVE_REWARD_MIN` 7 deg pays
  ~120 x carveStyle points ("CARVE") + a notch of flow. **Bars** (`barCarve` 0.5, 0 = straight, drawing only, `Game._bar_draw`): turn a little into the steered / aimed
  turn in the air and bite in at the carve (`phys.carve_now`, decays 4.5 /s). Probe `BMX_AIRSTEER_PROBE=1` prints `aim_want` / `aim`.
- **Landing swap rate** (`landSwapRate` 7 rad/s, Ride > Jumps > Steer in the air; `BMX_OLD_LANDSWAP=1` = old): for the first 0.35 s after touch-down the drawn lean (stick / slow
  steer / bank) moved at 3 rad/s and the bank part at `bankLeanRate` 1.5, which made a berm-to-berm swap out of a hop heavy; both now follow `landSwapRate` in that window.
  Drawing only (`_gx_lean` / `bank_lean`). Follow ride 60 s seed 4242: 0 crashes, 0 jitter flips, same as before.
- **Camera snap at touch-down** (user: "landing at an angle aligns us weirdly, snaps"): measured from an F8-style ride log: the drawn heading is steady through a carve, but
  `course` jumps 7-34 deg in ONE physics step (the carve), and `CameraRig` follows `course` in the air and `heading` on the ground, so the view swung by the whole slip
  (now up to ~35 deg with air steer). The view's heading (`_hd_s`) now turns at most `camHeadingRate` 3 rad/s (Ride > Jumps > Steer in the air; 0 = old; > ~90 deg
  jumps are taken at once). Probe `BMX_CAMYAW_PROBE=1` (`CAMYAW max_step_deg` per second, final camera yaw): chase cam worst frame 2.1 -> 1.0 deg at rate 3.
  Not eased: the travel direction itself still turns in one step at the carve (nothing drawn follows it but the camera).
- **Slider layout (same day)**: Ride > Jumps > "Steer in the air" = `airSteer*`, `airAim*`, `airPrelean`, `landCarve`, `carveStyle`, `barCarve` (* = Simple view);
  Landing page has `landSwapRate*` and `camHeadingRate`. Feel page has a 9th macro **Air flow** (`feelAirFlow`, 0.5..1.5) scaling `airSteer` / `airAim` x m^0.8,
  `landSwapRate` x m^0.8, `airPrelean` x m^0.5, `landCarve` x m^0.4, `camHeadingRate` x m^0.3 (air offset in a follow ride: 0.5 -> 20 deg, 1.0 -> 34, 1.5 -> 48).

### Jump technique matched to video 2 (2026-11-24, research/jump "The MTB Jumping Technique That Changed Everything")
- His model: load the lip, then direct the energy: squash = forward through the lip (low), neutral = with the lip (mid),
  pop = straight up (high). Side views 13:24-14:38 compared frame by frame with ours: playground lane DESIGNED JUMPS now
  starts with **VIDEO DIRT JUMP** (`dj_video`: his jump measured off the frames with the wheel as the scale: 1.45 m
  42 deg lip, R 1.5 m, step-up landing 1.5 m). Shots: `BMX_DIAG=off BMX_LIP_SHOT=prefix BMX_LIP_N=14 BMX_LIP_STEP=0.1`
  + `BMX_PG_PILOT_TECH=none|pop|squash`. (The clip with the car behind is on his hardtail; the big dirt jump on a
  full-suspension e-bike.)
- Found + fixed (`bike_physics.gd`): (1) hands off the rider's own pop pushed square to the lip; on a slow steep lip that
  takes forward speed away: left at 61 deg off a 42 deg lip and landed at 11 km/h. Now it goes along the travel, same leg
  energy (`_pop_along`); the player's pop still pushes off the face (`BMX_OLD_POPDIR=1`). (2) The front left a tight face
  early and the bike tipped up on its back wheel: hands off he now loads the lip, the bike held to the face under the rear
  wheel (`lip_hold`, `BMX_OLD_LIPLOAD=1`), and leaves within `LIP_SPARE_OWN` 0.05 rad of the lip (the player's pop / crouch
  keeps `LIP_SPARE` 0.15). Hands off now leaves -1.2..+1.3 deg off the lip on five designed jumps, so
  `JumpDesign.TAKEOFF_EXTRA` 8 -> 0 and the trail jumps were re-baked (`terrain_cs_cmp` EXACT, `wood_edge_probe` walls=0).
  (3) NOSE DIVE on a back-wheel landing: on the touch-down step the check compared with the take-off lip's slope
  (`nose_ref`), so popped jumps landed rear first crashed: now the landing ground (`BMX_OLD_NOSEREF=1`). (4) The stick
  snapped forward to pop, still forward just after the take-off, read as "nose down" and levelled the bike at once: held
  as the pop until the stick comes back (`_pop_latch`, `BMX_OLD_POPSNAP=1`); a popped flight's stand-tall lasts 0.65 s.
- Poses (`rider.gd`, `BMX_OLD_JUMPPOSE=1`): load on the face 15 cm deep, chest low; squash = hips well back and low,
  chest folded over the bars; popped = stands up behind the steep bike (hips back and up, torso upright) before the tuck.
- dj_video at 28 km/h: neutral 41 deg / 0.6 m / CLEAN, squash 20 deg / 0.2 m, pop 56 deg / 1.7 m / CLEAN-PERFECT; the
  popped bike pulls up to ~42 deg and holds ~0.5 s (his ~55 deg). Old hand-built playground jumps take off ~11 deg flatter
  hands off (suite re-saved); trail demo 150 s seeds 4242 / 5: no crashes, short landings soft.
- **The front comes up off the lip** (user: "the bike is not tilted, the front wheel isn't pushed up"; in the video the
  bike is ~55-60 deg at the edge of a ~42 deg lip even ridden neutral): the lip hold now keeps it `LIP_NOSE` 0.25 rad over
  the face hands off, `LIP_NOSE_POP` 0.4 popping (+ `POP_FRONT_LIFT` 1.6 rad/s as a pop goes in on the face: the arms lift
  the front, his J-hop), a squash pushes it down to the face; the take-off cap leaves that much room for the pitch while
  the flight itself still leaves with the lip. Hands off he may scoop the nose `SCOOP_TILT` 0.4 rad further down for the
  landing ("curl the toes, level out the bike"). dj_video: bike ~55-65 deg just off the edge, neutral flight 40 deg.
- **Overlaid frame by frame** (user: "overlay the pictures, you'll see how much you miss"): `scratchpad overlay.py`-style
  similarity transform matching both wheel centres, then 50 % blend. Measured from the crank centre: on a steep face his
  hips are ~0.45 m behind / 0.6-0.7 m above it IN THE WORLD, torso upright in the world, arms nearly straight; ours squatted
  0.25 m lower with the torso folded 60 deg and the head 0.55 m low. Fixed in `rider.gd` (`BMX_OLD_JUMPPOSE=1` = before):
  the deep preload pose is lighter; on a jump face / just popped the body is put at the measured pose (`FACE_HIP` world
  offset from the cranks, torso `FACE_TORSO` off upright, blended `FACE_POSE`, set last before the limits so the climb lean
  etc. don't undo it), arms may reach `FACE_REACH` 0.96 of their length (the usual elbow bend folded the chest onto the
  bars), the pelvis tilts with the torso as it stands and the spine curve is off (no bowed lower back), only `FACE_SINK`
  of the legs' sink is drawn, the flip fade of the body levelling starts later on a face. **Dynamic** (user: "this is for
  this jump and speed; faster = less front lift, less upright, more forward"): the stand-up fades with the bike's pitch
  (0.25-0.55 rad) and the speed (6.5-9.5 m/s); the front's lift over the lip (`nose_k` in `bike_physics.gd`) with the
  face's slope (0.4-0.75 rad) and the speed (9-15 m/s). dj_video: head ~0.2 m under his (was 0.55); the 43 km/h table:
  forward attack position, no nose lift. `BMX_JPOSE=1` prints the pose on a face (pre / after the limits / end).
- Open: hands-off landings still come in nose-up on short flights; the big designed tables are knife-edge at their
  design speed (dtable_60 at 96 % of it lands on the deck).

### Spins and flips carved / thrown at the lip (2026-11-24)
- Like the whip (air step 2), a spin or a flip gets its rotation at the lip; from the air alone the stick only turns it a
  little. **Spin**: the right stick pushed to its left / right EDGE (|x| >= `SPIN_EDGE` 0.85) in the last `WHIP_WINDOW` s
  before a lip winds up `spin_load` (short of the edge it stays a whip); off the lip rider + bike leave turning
  (`stick_yaw` = stickYawRate x load), the stick held at the edge keeps it going, let go it eases out over ~0.3 s
  (`SPIN_OPEN`, opening up), the landing help twists it the rest of the way straight. Without a wind-up the edge spin is
  `SPIN_AIR_ONLY` 0.35 of the rate. **Flip**: the lip throw (S / W fresh at a lip, stick yanked back / forward in the lip
  window: `throw_v`) is kept as `_flip_in`; in the air the stick at its top / bottom edge drives the flip at the full rate
  only that way, else `FLIP_AIR_ONLY` 0.35. Both turn faster tucked (/ air_inertia). `BMX_OLD_SPIN=1` = the old free
  air spins / flips.
- dtable_66 at 66 km/h (1.3-1.6 s air), test rider + `BMX_BODY=spinlip|spinair|fliplip|flipair` (stick held from the lip /
  only in the air, let go ~300 deg round; `SPINT` lines with `BMX_BODY_PRINT=1`): spin wound up 385 deg CLEAN (a 360),
  from the air 134-144 deg (lands FAKIE / HIGHSIDE); flip thrown 320-330 deg CLEAN (BACKFLIP), from the air 122 deg
  LOOPED OUT. Whips unchanged (whiplip 0.7: 67 deg, CLEAN).
- **Held lean = back flip** (user: "I can't do it" + "a held lean should turn into a back flip like other games"): the stick
  pulled back however long before the lip still throws it as it leaves the lip (`FLIP_PULL_EARLY`; it was locked out
  unless pulled fresh inside the short lip window). Snapped forward at the lip it is still a pop; a balanced manual into
  a lip stays a manual. A thrown flip held at the stick's edge turns fast enough to come round before the predicted
  touch-down (`_land_t`, up to `FLIP_RATE_MAX` 9 rad/s): stick held from 3 s before, tables at 36 / 43 / 66 km/h (1.1-1.6 s
  air) all 318-325 deg CLEAN; a stick pop stays a pop; the demo rider never flips (2 trail seeds). `BMX_OLD_FLIPPULL=1`.
  `BMX_FLIP_EARLY=s` = how early the test stick (`BMX_BODY=fliplip`) pulls.
- **Flip body** (research/jump: GMBN "How to backflip like a pro" side views 4:48, Hardline 97 ft short): thrown at the lip
  he drives the legs straight (no load crouch) with the head back; in the air by how far round the flip is: head back
  first, tucked tight through the middle, from half way the head and shoulders turn to spot the landing over the
  shoulder (`flipTwist`), the last quarter he opens up and reaches down for the landing. Big jumps: a slow flip spread
  over the whole flight (Hardline ~2.5 s for one turn). `BMX_OLD_FLIPPOSE=1`. User, same day: "he also arches the back"
  and "upside down his body is a lot more extended, ours is tucked": throwing it he lies back `FLIP_LEAN` 0.7 rad with the
  spine arched (`flipArch`, `FLIP_ARCH`), legs and arms straight; from ~a tenth round he hangs LONG off the bike (no tuck:
  `flipExt` = legs reaching, arms `FACE_REACH`, the air "spin style" compact pose off) to the landing.

### Route jumps sized to the speed riders arrive at (2026-11-24, from the level builder's checks)
- The level builder's checks ported to the world: `-s res://tools/route_checks.gd -- [seeds]` (`ROUTECHECK` per built jump:
  flown from its lip at the rider's speed over the real ground (its plane b0 -> b1, the land past it), where it comes down
  vs where its shape is meant to be landed on (AIR end - 2 m), EFH; `ROUTESUM` per type).
- **Rider speed = `TrailCourse.VA` x `TerrainField.RIDER_K` 1.4**: VA is free rolling (pedals only below ~30 km/h); the
  demo AI leaves the big jumps' lips at 38-46 km/h where VA says ~30-35. (A first version sized from VA alone made the
  jumps too small for real riders: the AI then crashed off a small kicker; sizing from VA is wrong.)
- `tools/bake_jumps.gd` also bakes the route's table + kicker at `SIZE_V` 8.5 / 11 / 13.5 m/s (size 3 = the 15.5 / 15
  design); `bake_jumps.py` writes them as two generated files, `scripts/world/trail_jump_sizes.gd` (TrailJumpSizes) and
  `TrailJumpSizesCs.cs` (TfSizes) (`godot -s res://tools/bake_jumps.gd | python tools/bake_jumps.py .`).
  `TrailFeatures.make_set()["sized"]` / `TfSet.SIZED`: table, kicker, tableLine, flow per size; `sized_air` / `SizedAir`.
  `TerrainField._build_route` picks the smallest size designed for >= 97 % of the rider speed ~12 m in (a bit big =
  they case / land early: safe; a bit small = past the landing: hard). `Feat.size` goes to C# with the feature
  (`_course_from`), so the pick can't differ. `BMX_OLD_JUMPSIZE=1` = always the big one. 5 seeds: 7 / 3 / 12 / 6 jumps
  at sizes 0 .. 3; kickers mean 0.0 m from the aim (old -2.9), hard landings 3 (old 6); tables -2.6 m (old -9.3).
  **Every world's route features change after its first jump section.** terrain_cs_cmp EXACT, trail_grow_probe /
  rope_find PASS, wood_edge_probe walls=0. Demo AI 120 s, seeds 4242 / 5 / 12: every built jump on its landing.
- **Gorge / plain bridges eased on and off (same day)**: the deck (`TrailFeatures.Wood.top` kind 2, C# `TfWood.top`) rose
  over a 2 m ramp ending in a 12 deg kink: at ~45 km/h it threw the rider ~9.5 m along the narrow (2.8 m) deck, and over a
  gorge a little drift in that flight dropped him in (seed 4242, s=1419: the demo AI crashed there every run). Now the
  ramps are smoothstep over min(9 m, half the bridge - 1 m): no corner, the crest's v^2 x 6 h / L^2 stays under g to
  ~63 km/h on the gorge's 36 m deck. Demo AI and the follow rider (64 km/h) now cross it on the deck; `BMX_OLD_BRIDGE=1`
  = the old ramps (the follow rider launched at x=1128 and fell in). terrain_cs_cmp EXACT, probes PASS, walls=0.
- `Feat.v` / `Feat.vmin` = a sized jump's design speed x the type's share (`TerrainField.SIZE_V_K`; kickers at their full
  design speed, never under 90 %: slower the AI rolled off a small kicker's open back nose first): the demo AI plans each
  jump at its own speed (DemoPilot reads `v` / `vmin` since the level builder).
- Side-path junctions were checked for a seam like the level builder's alt lines had (`-s res://tools/junction_step_probe.gd
  -- seed`: steepest 0.25 m step round junctions vs plain trail): the same (4242: 1.80 vs 1.63, seed 5: 1.27 vs 1.55);
  the world's side paths fade their bench / berms out 6-22 m from the course, no change needed.

### Doubles from the formula too (2026-11-24)
- `TrailFeatures.DOUBLE` / `DOUBLE_S` (and their `AIR` / `AIR_S` "double" / "doubleLine" spans) are baked from JumpDesign
  like the tables and kickers (`tools/bake_jumps.gd` "double" / "double_s", kind gap; `bake_jumps.py` writes both files).
  The gap's floor is raised to ~85 % of the lip (`fill`), so a rider short of it drops a little onto a dip, never into
  the landing's face (plain gaps: a 2.4 m equivalent fall at 80-90 % of the design speed). The trail's route never
  builds doubles; the small one is the free-ride jump out in the land (now 18 m, was 23: within its footprint), the big
  one is unused but ready. Small one in the playground: DESIGNED JUMPS lane, `double_s` (FREE-RIDE DOUBLE): hands off
  26 / 30 / 38 / 44 km/h all CLEAN (short onto the floor, on the landing at 38, past it at 44), popped at 38 PERFECT.
  `terrain_cs_cmp` EXACT, `wood_edge_probe` walls=0, `trail_grow_probe` PASS.

### Ruts (2026-11-24, MX vs ATV-style; rides + the test playground, Settings › Gameplay › Ruts)
- The ground dug in where tyres roll, deeper each pass, and felt: `Terrain.height` / `deck_height` / `top_height`
  (and the playground's) subtract `rut_at(x, z)`, so a wheel drops into the groove, its walls tilt the ground under the
  tyre and the existing side-slope knock steers the bike along it / kicks it crossing one (no new steering code).
- `world/RutFieldCs.cs`: sparse 8 m tiles of 5 cm cells (made only where tyres rolled, oldest dropped past 96 tiles ~10
  MB); `Stamp` digs a tyre's stretch since the last tick only (each point once per pass; standing still digs nothing):
  a rounded groove `HALF_W` 4.5 cm + a lip of pushed-up dirt (`LIP` 0.4 of the dig); `Depth` bilinear; `TileRH` for the
  shader. `world/ruts.gd` (made by `Game._make_ruts`, deferred): both grounded tyres stamp every physics tick
  (`DIG` per surface: grass 4 mm / pass max 3.5 cm, dirt 7 / 7, wet 12 / 9, sand 20 / 11; x the tyre's load 0.3..3,
  x2 under a locked rear); keeps a 40 m (5 x 5 tiles) RH texture window round the rider for the ground shader (only dug
  tiles re-copied, 10 Hz), globals `rut_tex` / `rut_win` (project.godot). `shaders/ruts.gdshaderinc`: `rut_depth`,
  `rut_normal` (the groove's walls shaded from the depth's slope), `rut_colour` (packed darker bottom, lighter lip);
  used by `playground_ground.gdshader` (not the world's ground yet). Cost: stamping ~0.02 ms a tick, the node below
  measurement; the depth reads are one bounds check outside the dug area.
- Measured (playground `brake_sand`, test rider at 25 km/h): 2-3 mm the first pass, 1.5-3 cm after a few, 6-9 cm where
  the rear skids to a stop; riding down its own rut no side kick; slalom over its ruts on dirt: no crashes, same speeds.
- Tests: `BMX_RUTS_PROBE=1` (`RUTS tiles= stamp_us= under_rear= under_front= knock=`), `BMX_RUTS=0` off,
  `BMX_NO_TRACKS=1` hides the drawn tyre tracks (to see the ruts alone).
- In rides too (same day): `ground.gdshader` draws them (`rut_depth` / `rut_colour` / `rut_normal` on the world
  position `P`), the C# tyre fit sinks the drawn tyres into them (`TerrainFieldCs.set_ruts` + `tyre_worst`), the
  terrain reads them only within `READ_R` 20 m of the bike (`Ruts._publish` clips `rut_box`), up to 256 tiles (~26
  MB, ~2 km of ride); they stay when you go back to the start (Backspace), a new world clears them. A trail pass on
  dirt leaves ~2-10 mm (skids / landings more). Seed 4242 follow ride: 130.7 fps off / 129.5 on, the same crash either
  way. Setting `ruts` (from the next ride), `BMX_RUTS=0|1` overrides.
- Not done: drying / filling in over time, ruts from AI riders / ghosts.
- **Tyre prints in the ground (2026-11-25, user: "industry standard, tidier")**: the tyre tracks were a mesh ribbon
  laid over the ground (fx.gd, 14 000 segments, `tyre_track.gdshader`, faded 55-110 m). They are now stamped into the
  rut field like off-road games do (SnowRunner / Dirt Rally / MX vs ATV: tyres mark a world-space layer the terrain
  shader reads). `RutFieldCs.StampTrack(wheel, x, z, halfW, strength, smear, blood)` (per drawn frame from
  `Game.ride_fx` -> `Ruts.track`): per 5 cm cell E = signed distance to the prints' edge (m, < 0 inside, `NO_E` 9 =
  none) kept as the UNION of all prints (min): a signed distance field, so the edge interpolates crisply from bilinear
  cells even where front and rear prints overlap (cells 2 beside a print are written too); strength, skid smear 0..1,
  blood (`Blood.tyre_blood`), direction as a doubled angle (cos 2a, sin 2a): every stored value is one that BLENDS
  between cells; the across position for the tread is worked out from E in the shader (`au = 1 + E / 4.5 cm`). Half
  floats, ~300 KB a tile, the newest print wins inside its band (E stays the union). (Two earlier versions the same
  day, from user screenshots: one print's SIGNED offset per cell drew saw-toothed edges + a false zigzag line where
  front / rear prints overlapped; then |offset| + a negative strength for skids punched holes where + and - met and
  drew the tread in 5 cm blocks where a skid crossed a print.) **The knobs come from a mipmapped tread texture**
  (`Ruts.tread_texture()`, 64 x 128 R8, global `rut_tread_tex`, `textureGrad` with the pixel's size): crisp as far as
  a pixel resolves them, their average beyond, no shimmer (procedural knobs had to be faded out early and the tread was
  lost: user, same day). The tread is SYMMETRIC along the print, and the noises read |v| / |across|: the direction comes
  from a doubled angle whose half flips sign between neighbouring cells where a print runs along world z, which drew
  the knobs (and the print's blotch noise) as a zigzag. **Nothing in a print is drawn per pixel unfiltered** (user,
  repeatedly: "shimmer"): the knobs' colour AND relief come from the mipmapped tread texture (the relief = its slope
  along the print from two filtered samples a pixel apart, `rut_prints(.., out kslope)` -> ground.gdshader's `rsl`; a
  per-pixel screen-space bump flickered, without any bump the knobs looked flat: user), the pushed-out soil at the edge is
  a broad soft band (a 1 cm lip line flickered), colours as the old mesh tracks (pressed soil x0.62, dimples darker,
  lip lighter). A skid = a plain pressed-in band, no knobs (user: "when skidding we don't leave knob marks, just a
  depression"); the knobs fade out as a skid comes in (sine stripes, then drag-line noise were tried: they swam). The
  near window is read with a bilinear blend in the shader (`rut_bilerp`, four texelFetch, toroidal): through the GPU
  sampler the print's distance field drew a staircase of 5 cm cells. `BMX_TRAIL_DEBUG=7` print cover / knobs / lip,
  `8` the edge distance as contours. Skid close-up test: `BMX_SEED=4242 BMX_STRAIGHT=1 BMX_SKID=10 BMX_PHOTO=13
  BMX_PHOTO_AT=21.5,105.2,1.6,22.5,103.5,0 BMX_PHOTO_SNAP=1 --autotest=16` (where the bike stops varies run to run,
  photo mode's focus may blur it). Not confirmed shimmer-free by the user yet. **The near window is a toroidal GPU texture now** (11 x 11 tiles = 88 m,
  `shaders/rut_upload.glsl` copies only the tiles that come in or changed, `TilePack` = 4 half pairs a cell, budget 24
  a 10 Hz update; globals `rut_tex` rgba16f depth / edge distance / strength / blood + `rut_dir_tex` rgba8 |u| / 2 +
  direction, `rut_win` = its place);
  near fade 26-34 m from the rider (was 12-20), the far layer (`TileRGFar`, RGH: deepest cell + prints' cover) to 75-90
  m. `ruts.gdshaderinc` `rut_prints(xz, px)` = the old tread (two alternating knob rows along `dot(xz, dir)`, skid
  streaks, noise), knobs fade to their average below a pixel, a print narrower than the pixel is drawn wider and fainter
  (no shimmer); `rut_print_colour` = the ground's own colour pressed darker (no fixed track colours), blood red; the
  dimples go into ground.gdshader's relief height (`hh`). Both ground shaders draw them. **Ruts and prints are one
  system**: `Game._make_ruts` always makes the field (C# needed); Settings › Gameplay › Ruts now switches only the
  digging (`Ruts.dig`); prints are always on (`BMX_NO_TRACKS=1` hides them). They stay on Backspace like the ruts (were
  cleared), a new world clears them. Removed: fx.gd's track ring buffer, `tyre_track.gdshader`, the replay's
  hide-newer-tracks trick (`_tracks*`: prints laid after the replayed moment now show in the replay). Cost (seed 4242
  follow ride): stamping 22 us a physics tick, the window's upkeep ~0.18 ms a frame on average (one ~4.5 ms frame
  filling the empty window at the start), RAM up to ~90 MB at 256 tiles. Not done: per-dirty-rect uploads (a printed
  tile re-copies all of its 160 x 160 cells), prints of AI riders / ghosts, a print lying down in a deep rut's walls.

### Level builder in the Godot editor (2026-11-24, step 1 of 4: `addons/level_builder`, `scripts/levels/editor/`)
- Developer-side level editor for hand-built downhill levels (plan: 1 slope + trail + ride from the editor, 2 pieces:
  jumps / drops / rocks / bridges / gates, 3 bake + test-rider checks, 4 publish to an in-game LEVELS list).
- A level = a scene in `res://levels/` whose root is a `BmxLevel` (Node3D, @tool: the slope's length / width / drop /
  steepness / side rise / bumps) with a `BmxTrail` child (Path3D: draw the line with the curve tools; only x, z are
  used, its height is the land's smoothed along it). `LevelField` (pure data, used by the editor AND the ride) bakes it:
  the trail resampled every 1 m, its curvature, the speed a rider carries (gravity, rolling + air drag, capped by each
  bend, braking room backwards), the bank each bend needs for that speed (up to `bank_max_deg`), then a height grid
  (0.5 m in the ride, 1 m preview) with the trail's banked cross-section blended into the land over `blend` m.
  ~0.3 s for the 537 m demo. Physics reads the grid (bilinear); the drawn ground is the same grid at 1 m.
- Editor: the plugin's dock (right, "Level Builder"): New level, Snap trail to ground, Rebuild preview, **Ride this
  level** (saves, runs the game with `-- --level=<path>`). The preview (internal nodes, never saved) shows the ground,
  the trail line coloured by speed (blue .. red), bank ticks (white flat .. yellow steep), start (green) / end posts.
- Game: `--level=res://levels/x.tscn` (kept for the session: `main._cmdline_level`; it used to be cleared by the
  title menu, also for `--level=playground`) -> `LevelTerrain` (Terrain API from the LevelField). The field's
  TrailCourse is the level's trail (`LevelField.to_course`), so the demo AI (F2 / `BMX_DEMO=1`), the follow rider,
  trail camera, bend alerts and the bail tap work. Demo: `levels/demo_descent.tscn` (`-s res://tools/make_demo_level.gd`
  rewrites it). Test: `BMX_DEMO=1 BMX_CAM=chase -- --level=res://levels/demo_descent.tscn --autotest=40` (rides it all,
  no crash). Note: very short `--autotest` (< ~12 s) runs only drew 2 frames here.
- **Step 2 (pieces, same day)**: `BmxPiece` (base: `follow_trail` = snapped onto the nearest trail point facing down it,
  `standalone` = a ramp on the ground as it is: its own mesh + collision, the ground not levelled / blended) with
  `BmxJump` (every JumpDesign control in the Inspector + `auto_speed` = designed for the speed riders carry there,
  `speed_scale`), `BmxDrop` (climb onto a deck, optional square edge, landing face following a flight at the design speed,
  bottom bend), `BmxRocks` (a rock garden: the world's rock meshes + dome colliders; clean line, density, sizes, spread),
  `BmxGate` (start = the spawn, checkpoint, finish; visual, timing comes with publishing). `LevelField._structure` levels a
  structure's footprint to the ground's grade (unless standalone) and stamps it; `height()` is the structure's EXACT shape
  on its footprint (the drawn grid is tucked 14 cm under it, `struct_mesh` draws it at 0.1 m). JumpDesign sizes for flat
  ground, so on a grade the auto deck / gap is fitted by bisection and the auto landing angle from the flight over the
  real ground (`_flight`, `_trial`); the editor prints per jump where 85 / 100 / 115 % land + EFH and draws the arcs.
  Measured: every auto jump on both demos lands on its landing at design speed, EFH 0.0-0.1 m. Route features (`lf.route`,
  dictionaries with their own `v` / `vmin`: `DemoPilot` uses them) + rock runs in the TrailCourse (KD ROCKS).
  `BmxLevel.flat_ground` = flat (a park; bumps only if rough > 0). Editor: PLACE mode (dock: Jump / Drop / Rocks / Gate:
  a ghost follows the mouse, snapped to the grid, Q / E turn it, click drops one, right click / Esc ends), DRAG any piece
  on the ground (snapped; Alt + drag turns; one undo step), snap on / off, grid size (drawn on the preview ground:
  `grid_cell` in `playground_ground.gdshader`), rotation step, Shift = free. `BmxLevel` polls a signature of all inputs
  (0.3 s), so inspector edits, gizmo drags and undo all rebuild the preview. Demos: `demo_descent.tscn` (start gate,
  table, rocks, gap, finish on its straights), `demo_park.tscn` (flat, no trail, standalone dirt table / wood kicker /
  gap / wood drop); both from `tools/make_demo_level.gd`. Ridden: the demo AI down the descent, 45 s, no crash; straight
  through the park, no crash.
- **The world's look on levels (same day)**: `LevelTerrain._build_chunks` makes real 48 m chunks over the level's grid
  with the textures a world chunk bakes (`land_tex` + trail weight, `dirt_tex` + rock weight, `trail_tex` = metres
  across / along the trail from `LevelField.TSA` / `TAL`, `trail2` built-jump flag, `trail3` air from each jump's lip to
  where the design speed lands + corner load from `TKC`), drawn by `world/ground.gdshader` (worn lines, prints, grit),
  and `grass_img` / `grass_h` in `chunks[k]`, so `GrassField` grows its carpet (none on the trail, structures, rocks).
  ~2 s to build for the 520 x 200 m demo (step 3's bake will cache it). Trees: `LevelField._bake_trees` (jittered grid,
  clumps, `trees` density, `tree_clear` from the trail's edge, none on pieces / steep rock; pines / leafy / bushes,
  the world's TerrainGeo meshes + deco materials via `LevelVisuals._trees`, trunk colliders in the rock lookup; editor
  preview too). The world's water sheet is removed on levels (their ground is below its -2.2 m sea level: the level
  was flooded white), and the morning mist's floor is the level's own ground (it clamped to that sea level). ~140 fps.
- **Race timing** (`levels/level_race.gd`, made by `Game` on a LevelTerrain): the start gate starts the clock (the spawn
  is 3 m behind it), checkpoints flash a split vs the best run's, the finish stops it and keeps the best time + splits per
  level + bike in `user://level_times.cfg` (not in test runs); a timer top centre; Backspace resets the run, the bail
  tap doesn't. `BMX_RACE_PROBE=1` prints `RACE` lines. Demo AI on the descent: start 0, checkpoint 18.2 s, finish 34.2 s.
- `jump_mask` covers a structure's whole footprint (run-out included), as the world's features. The wooden kicker's
  square back gives a zero-impact rear "landing" at the lip in the BMX_TRICK prints: the physics' `_graze` rule
  already treats it as a brush with the lip (speed kept), nothing to fix.
- **Step 3, bake (same day)**: dock **Bake level** (or `-s res://tools/bake_level.gd -- res://levels/x.tscn ...`) writes
  `levels/<name>.bake` (zstd `store_var`): `LevelField.state()` (grid, trail, pieces, rocks, trees), every chunk's
  `LevelChunkData` (the world chunk textures + `light`) and the baked light: `LevelShadeBake.cs` ([Tool]) marches
  each 1 m cell towards the sun at the level's `hour` / `sun_turn` (BmxLevel > Light) through the heights and tree crowns
  (soft edge from the closest miss), and samples the horizon in 8 directions for sky openness. `ground.gdshader`
  `bake_tex` / `bake_on` / `bake_near`: past `bake_near` the sun's shadow is the baked one (x 0.42 in shadow), the sky term
  darkens hollows everywhere. On a baked level the real-time sun shadow reaches only `LevelTerrain.RT_SHADOW` 45 m
  (`Game._shadow_fit`), and the level's own time of day / sun are used (`Game` light override). LevelTerrain loads the bake
  when `LevelBake.signature(lvl)` matches the scene (else works it out live; `BMX_LEVEL_LIVE=1` forces live). Godot's
  LightmapGI was not used: its bake is editor-toolbar only and needs the meshes in the scene. Demo descent: bake 1.7 s,
  4.0 MB; load 0.3 s (live 1.5 s). The bake runs the level's checks (`LevelBake.checks`): jumps not landing on their
  landing at design speed, EFH > 1.5 m, a 15 % slow rider dropping into a gap, overlapping pieces, no start / finish, hard
  braking zones, the trail leaving the ground. Not done: reflection probes, trees darkened by baked shadow far off.
- **Step 4, sculpt / paint / import a world trail (same day)**: `LevelLayers` (Resource, `levels/<name>_layers.res`,
  binary, saved with the scene via `_save_external_data`): `import_h` (an imported land: replaces the slope), `sculpt`
  (m added, 1 m grid over the level's ground), `paint` (1 dirt / 2 sand / 3 rock: into `S` as 1 / 3 / 4: sand rides as
  the world's sand, rock = rock weight). `LevelField.base` = `land` (import, flat or slope) + sculpt. Dock **Sculpt mode**:
  Raise / Lower / Smooth / Flatten / Paint dirt / sand / rock / Erase paint / Erase sculpt, radius + strength, a brush ring
  on the ground, one undo step per stroke, the preview rebuilt at the stroke's end. **Import world trail** (seed, start m,
  length m): runs `tools/import_world.gd` as its own headless Godot (`OS.execute`: the world's generator isn't a @tool
  script) which cuts that stretch of the world's trail out, turns it to run down +x, keeps a few Bezier points (RDP
  1.2 m) and samples the world's land at 1 m; the level takes its size, land and trail (undoable). Edit the spline
  (Path3D handles) and the trail regenerates over the real land. Seed 4242, 600 m from 300 m: 301 -> 44 points, 3.3 s.
  `tools/make_world_level.gd -- <import file>` makes `levels/world_cut.tscn` the same way (+ a sculpted mound, painted sand)
  and bakes it; demo AI rides it, no crash.
- **Step 5, editor comfort (same day)**: `LevelBake.marks(field)` = every check with where it is: drawn in the preview as
  a red (fix it) / yellow (a note) post + words, live; `checks()` is its text. Dock: **Fit all jumps to trail speed**
  (auto speed on, deck / gap / landing angle auto, one undo), **Ride from selected** (`--level-at=x,z`: starts 30 m up
  the trail from the selected piece; `LevelRace.practice`: "PRACTICE", no timing / bests), a **minimap** (land shaded,
  trail red, structures yellow, sand / rock, piece dots, the editor camera; click a dot = select it). `BmxJumpLine`
  (extends BmxJump: every jump control + `count`, `rollout` s): jumps down the trail, each sized for its spot's speed,
  the next one's START at least one roll-out (6-14 m) past the last landing (a faster jump's longer run-in is pushed on).
- **Step 6, several lines (same day)**: the first `BmxTrail` is the main line (AI, timing, rock gardens, jump lines
  follow it); every other one is an alternative line (`LevelField.alts_in` -> `ALT`): baked the same way, its speed
  starts from the main line's where it branches off, its height eases onto the main line's over 15 m at each end
  within 8 m of it, all lines are cut into the ground together (the nearest wins: junctions are one surface). Jumps /
  drops / gates snap to the nearest line (on an alt line: its own speed for auto speed, no AI / timing index). Dock
  **+ Alt line** (the main line's middle third pushed out 12 m, joining again). NOTE: Godot 4 packed arrays are shared
  by reference: `_bake_alts` keeps `.duplicate()`s (it lost the main line otherwise).
- Rocks in rides: the deco material tints by instance custom data, so rock MultiMeshes set it white (they were black).
- **Review fixes (same day)**: a jump line's rejected try is undone in the grid too (it left a phantom ramp); the editor
  snaps follow-trail pieces to the nearest line incl. alt lines (as the bake does); the race takes any later gate (a
  skipped checkpoint no longer blocks the finish: "N checkpoints missed", no best time); two quick Ride clicks no longer
  leave `--level=` stuck in the editor's run args; `--level=` stays for the session only for `.tscn` levels (the
  playground resets on the title again); the import passes the seed to `Terrain.new`; ground drag: an unselected piece,
  or Ctrl + drag on a selected one (its gizmo works otherwise); PRACTICE shows without gates; an unsaved level can't
  sculpt (no shared untitled layers file). Alt lines take the main line's height + bank sample by sample over their
  last 20 m at each junction (a step there threw the demo AI at 234 m).
- **Publishing (same day)**: `BmxLevel` > Publish group (`published`, `description`, `difficulty`, `medal_gold / silver
  / bronze`, 0 = worked out). Dock **Publish** (needs an up-to-date bake; `LevelPublish.publish`): medal times from the
  speed profile between the start and finish gates (`ideal_time` = sum of DS / TV; gold x1.02, silver x1.15 of gold,
  bronze x1.35; a level with no trail: gate to gate at 8 m/s), difficulty 1-5 from the biggest structure, top speed,
  steepest 10 m and braking bends, a picture `levels/<name>_map.png` (`LevelPublish.picture`), all into the registry
  `res://levels/levels.cfg` (section = scene path). **Unpublish** takes it out. `-s res://tools/publish_level.gd -- ...`
  does it headless. Title > LEVELS lists them under TEST PLAYGROUND as cards (map, stars, length / drop / jumps, G / S / B
  times, your best with this bike + its medal; a scrolling list), `BMX_MENU_PAGE=levels`. The finish flashes the medal
  ("SILVER!  0:35.52  NEW BEST"); `LevelTerrain.medals` come from the registry. Ghosts ride on built levels too (key
  `level_<name>_<bike>`). Demo AI on the demo descent: 35.5 s = SILVER (gold 33.9). LevelPublish keeps its own time
  formatter: anything the editor runs must not reference scripts that use the game's autoloads (LevelRace, Game).

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

### Instant replay + saved replays (I / pad L3 / pause > Replay, title > REPLAYS, `scripts/game/replay.gd`, 2026-11-24)
- Records what is DRAWN, not the inputs: `ReplayMode.capture(t)` (end of the ride part of `Game._process`, real rides only:
  not the title backdrop, 30 Hz of ride time). A "segment" = one node list (bike rig, the rider as his own root kept in
  world space, the torn-off action cam; a node added / removed under them starts a new one): every node's transform +
  visibility at its start is the `base`; per sample only the nodes that have moved since (`moving`, append-only) are
  stored (~45 of ~170), then every bone's whole pose (`BW` 12 floats: the spine bones carry the torso's length + a skew,
  position + rotation alone stretched the body). The whole ride up to `SECS` 6 min (~7.5 MB a minute in memory,
  ~0.15 ms a sample); cleared on respawn / new world. Samples are blended only inside one segment and when the bike didn't
  jump > 4 m. The chain isn't stored: it redraws itself from the replayed parts (the replay sets `rig.crank_angle`).
- Playback (`Game.open_replay` / `exit_replay`, `game.replay_on`): time frozen (time_scale 0 like photo mode), its own
  Camera3D (copies the ride camera's environment / attributes / compositor), HUD / WASTED / contact shadows / drone OSD
  hidden, speed blur off, render quality up (`Garage.showcase_quality(vp, on, heavy=false)`: full res, 4x MSAA + TAA, full
  LOD, 16x aniso; not the garage's 8K shadows / 128-ray GI), terrain streams round the replayed rider (3x3 chunks built at
  once on open). Leaving puts the live state back (`_live` / `_restore`). The cloth sims (race number, hair, helmet flap,
  strap tails: `SIM_SCRIPTS`) see dt 0 while frozen, so the replay steps their `_process` with its own time step.
- Controls: Space / A play-pause, A D / arrows / D-pad / left stick: tap = a step (paused: one sample), held = rewind /
  forward from 3x doubling every 0.6 s to 48x, Q E / LB RB speed 0.1-2x, C / Y camera: TV (trackside cuts placed ahead of
  where the rider WILL be, zoomed on him), Chase, Side, Orbit, Detail (round the bike itself, in to ~40 cm), Drone, Free
  (an editor fly camera like Unity / Unreal's scene view, paused or playing: right mouse held = mouselook, WASD flies
  where it looks, Q / E down / up, Shift x3, wheel with right held = fly speed; middle drag pan; Alt + left drag orbit the
  rider; wheel dolly, Ctrl + wheel lens; Z / X or LB / RB tilt (roll); F frames the rider; pad: sticks fly / look,
  triggers down / up, D-pad up / down = speed; rewind on arrows / D-pad left / right; up to 600 m from the rider, the
  world streams round the camera; `BMX_REPLAY_FLYTEST=1` flies it in a test). Mouse drag / right stick look, wheel / triggers zoom, R / R3 reset, H / X hide the bar,
  S / pad View save, I / B / Esc back. Timeline: drag to scrub; airs gold, crashes red (`_marks`, kept as recorded).
- Saved replays (`save()`): `%APPDATA%\Mini BMX\replays\ride_<date>.replay` (test runs: `replays/tests/`), zstd, ~4 MB a
eplays
ide_<date>.replay` (test runs: `replays/tests/`), zstd, ~4 MB a
  minute. Header (`read_header`): seed, bike id + its build, rider look + pose, level, light + time of day, length; then
  segments (node paths, bases, moving lists) + samples. Node paths are one step per level from the root: a real name, or
  `#Class:k` = the k-th unnamed sibling of that class (generated "@Mesh@123" names differ every run). Title > REPLAYS lists
  them (`main._menu_page_replays`); watching one (`_watch_replay`) sets `GameState.view` (= the header: `bike_config_for`
  uses its build, `Game._ready` its look / pose), builds that world + bike + rider, `replay.load_saved` resolves the paths,
  plays; leaving (`_replay_view_done`) restores seed / bike and comes back to the REPLAYS page.
- **Sound**: `RideAudio` reads `src` (a `ReplayMode.AudioState`: speed, air, crashed, surface, skid, pedal key, pedal,
  cranks: the per-sample row `AROW`) instead of the physics while a replay plays forwards, and every one-shot it played
  while riding (`_rec`: landing, landing_bad, crash, thud, crunch, wood_crash, shift) is kept in `aev` and played as the
  playhead crosses it. Slow motion = `AudioServer.playback_speed_scale` = the rate (0.35..1.5, like WASTED); paused /
  rewinding = quiet.
- **Dust**: `RideDust.feed` / `feed_front` (a state per sample, `DROW`), `grit_burst` and `SmokeSim.burst` (events in
  `dev`) are recorded through their `recorder` (= the replay) and called again in playback; the sim is stepped with the
  replay's own time (paused = the cloud hangs still), reset on a jump back / open / close. Crash slide sources
  (`add_source` from `_crash_dust`) aren't recorded. **Tyre tracks**: the segments laid after the replayed moment
  (`fx.seg_birth` vs the sample's `fx.t`) get their colour bytes zeroed (newest first in the ring, binary search), the
  whole attribute buffer is put back on close (`_tracks_open` / `_tracks_close`); not in a saved replay.
- **Photo mode on a replay frame** (O): `Game.toggle_photo` works in a replay: `replay.photo_begin` puts the ride camera
  where the replay camera is; photo mode's pivot is the replayed rider; leaving returns to the replay (`photo_end`).
- **Highlights** (G / pad R3, `toggle_highlights`): windows round airs over `HL_AIR` 0.45 s (from 1.3 s before to 1 s
  after) and crashes (2.2 s before .. 3.2 s after), merged; plays only those on the TV camera, airs at 0.55x, a crash
  at 0.35x round its moment (`_hl_rate`); blue bands under the timeline.
- **Clip export** ([ / ] in / out, Del clears, V exports; `export_clip`): the replay is stepped at an even `EX_FPS` 30
  video frames a second (at the chosen speed: slow-motion clips), the bar / hint / fullscreen button hidden, master bus
  muted; every frame a JPEG (`EX_Q` 0.9) into a Motion-JPEG AVI (`game/avi_writer.gd` `AviWriter`, RIFF + idx1) in
  `%APPDATA%\Mini BMX\videos\` (tests: `videos/tests/`). ~220 KB a frame at 1600x900. No sound in the file. No in /
  out: the 10 s from the playhead (or the highlights' span). Esc stops it, keeping what's done.
- **Ride from here** (Enter / pad X, `ride_from_here`): every physics value of `BikePhysics` (its script variables,
  `SNAP_KEEP` left out, like `PlaygroundLab.fresh`) is kept 4x a second for the last 2 min (`phys_snap`, from
  `Game._physics_process`); the newest one at or before the playhead that isn't in a crash is put back (crashed now:
  `_end_crash` first), the replay closes and the ride carries on; the recording after it is dropped and new samples
  continue from that moment (`_t_off`). The world (torn tape, smashed fences) stays.
- Opens on the last `OPEN_BACK` 10 s (Home = the start of the ride).
- Not replayed (stay as now): mud / blood, the world (torn tape, smashed fences), the crash slide's dust. A saved
  replay's world is fresh (tape whole, no tracks).
- Tests: `BMX_REPLAY=secs` opens it (+ `BMX_REPLAY_SET=cam=Free,speed=0.5,at=-6|6,pause=1,ui=0,hl=1,in=-8,out=-5,export=1,ride=1` (at < 0 from the end,
  > 0 from the start), `BMX_REPLAY_SHOTS=dir/prefix` (a shot every 0.5 s, fps printed), `BMX_REPLAY_CLOSE=secs`,
  `BMX_REPLAY_SAVE=secs`, `BMX_REPLAY_PROBE=1`: `REPLAY frames= moving= mem= MB/min capture_us= apply_us=`, on load
  `missing` paths + `static differs` = parts matched wrong), `BMX_REPLAY_LOWQ=1` (no quality boost).
  `BMX_REPLAY_WATCH=<file> [BMX_REPLAY_WATCH_SHOT=png] BMX_REPLAY_NSHOTS=n` + `-- --noop`: watch a saved file from the
  title, back after n shots, then quit. PADSEQ `k:I` works too.
- Not done: sound in exported clips, deleting saves in the game (OPEN FOLDER on the page), ghosts, camera keyframes.

### Landing slam sound (2026-11-24, from the user's bike-slam recording)
- `scripts/game/SlamSynth.cs` = the user's recording (hit B of a YouTube MTB sound clip, kept raw in `assets/audio/biking_raw/`, not imported) rebuilt procedurally,
  matched by WAVEFORM: 30 damped sines for the ~100 ms body + noise in 3 bands under the recording's own 1 ms envelope (first 20 ms waveform corr 0.92, 5 ms envelope 0.93).
  `Render(seed, vary, peak, size, side, kind)`: size 0 small .. 1 big (pitch / decay / rattle / sub thump), side = sideways landing (rear tyre lands late + rubber scrub),
  kind 1 = the bad-landing layer (second bounce + short metallic ticks). ~4-10 ms a render, so `RideAudio.landing(impact, yaw)` makes a fresh one every landing; `landing_bad(sev)`
  is called from `bike_physics` on HEAVY / SLAM (`Game.on_bad_landing`). No C#: the recorded `bike_slam_1..10.ogg` play. Hit A (messy multi-bounce) fitted badly and is not used.
  Test: `-s res://tools/slam_render.gd -- <dir>` writes every type to WAV; `BMX_LAND_TEST=5` fakes a hard landing.

### Ghost rider (2026-11-24, `scripts/game/ghost_rider.gd`, made by `Game._ready` in rides of a world, not levels)
- Your best run on this world (seed + bike) rides with you as a see-through glowing rider + bike; the HUD shows the gap
  to it ("GHOST +1.2 s" red = behind, green = ahead; "GHOST: AHEAD OF IT" past where it got to, "GHOST FINISHED").
- Recording: 30 samples / s of 68 floats: time, trail distance `s` (nearest point of the course polyline, searched
  round the last one; kept as the furthest so far), the rider's 15 joints (Ragdoll order, `rider.J` in world space; in
  a crash `ragdoll.p`, so falls replay), 6 bike points (rear axle, crank, saddle, steering pivot, bar middle, front
  axle) and the wheel axle direction. ~7 KB / s zstd. A run starts at every start of a world (`Game.respawn` and the ride
  start call `start_run`), ends at the next one / `Game._exit_tree` (`end_run`); it replaces the saved ghost when it got
  further down the trail by the time the shorter of the two ended (runs under 15 s don't count). Files:
  `user://ghosts/<seed>_<bike>.ghost` (u32 raw size + zstd; tests: `ghosts/tests/`).
- Drawing: not a copy of the rider / bike: one MultiMesh of a low-poly capsule (14 limb / torso bones, a ball helmet, 7
  frame tubes) + one of 2 torus wheels, world-space instances, one unshaded rim-glow shader (drifting band), no shadows,
  no depth writes; fades where it overlaps the real bike (`player`) and near the camera, dims once its run is over.
  2 draw calls, ~4k triangles, no measurable GPU / CPU change (render probe); script < 0.1 ms.
- Settings › Gameplay › Ghost rider (`ghost`). Tests: `BMX_GHOST_PROBE=1` (`GHOST start / end / t= my_s= gap=`),
  `BMX_GHOST=0` = no ghost node. Record with one test run (e.g. `BMX_FOLLOW=1 --autotest=30`), then
  `BMX_FOLLOW=1 BMX_IDLE_FOR=0.5 BMX_CAM=side BMX_SHOT=...` shows it beside you.
- Not done: ghosts from other players / a leaderboard (Steam), choosing which ghost (last / best), start / finish gates.

### Pose Lab (2026-11-24, Insert; `ui/pose_lab.gd` + `rider/pose_keys.gd`; STYLE ONLY, the physics is untouched)
- User ask: "pause mid air and correct it", pose the rider's skeleton on parts of a jump, "play back with our corrected poses,
  automatically morphing between our set keyframes", a timeline UI, "a separate game mode / dev pose mode", saved so the rider
  rides / leans / jumps with it everywhere. **No physics change** (user: "only style").
- **Pause** = `Game.pose_hold` (the physics step is simply not run, like the playground's G; `pose_steps` = ticks to run
  from STEP); `_process` keeps posing every frame, so the sliders show at once. Works mid-air in any ride / the playground.
  In the instant replay: rewind to the moment, **Insert** = `ReplayMode._pose_from_here` (ride from here + Lab open, paused).
- **Keys** (`PoseKeys`): on a normalised JUMP TIMELINE 0..1, not seconds (APPROACH 0, LOAD .12, POP .30, AIR .40, REACH .80,
  LAND .90): `Game._pose_phase` reads it from the physics state (preload / popFx / flight share via `_land_t` / land_reach /
  land_fold), so one set of keys fits every jump. A key = every channel (`PoseKeys.CH`: bike nose-up / lay-over UNDER the body,
  hips x y z, torso pitch / roll / yaw, head nod / turn, elbows / knees out). Between keys: Cardinal cubic per channel; the
  ends ease to neutral at 0 and 1. `amount` scales them, `enabled` switches them. Saved `res://data/pose_keys.json`
  (commit it; user:// only when res:// can't be written; test runs never save).
- **Where they act** (`Rider.update_pose`, after the final `_constrain`): hips offset carries pelvis + chest; the torso tilt
  turns the chest about the pelvis, so head, shoulders and (by IK) arms follow; then `_constrain` runs again, so a key can't
  push him through the bars or out of reach. Head / shoulder yaw, elbow / knee poles use `_pk_*`. Hands / feet stay on the
  grips / pedals. "Bike under body" turns the RIDER NODE about the bottom bracket (`Game._pose_keys_apply`) and gives the
  limb targets in that turned space: arms and legs follow the bike, nothing in the bike / physics moves.
- **UI** (`PoseLab`, CanvasLayer 30): left = transport (PAUSE / RESUME, STEP, PLAY KEYS = the morph played over the frozen
  moment, LIVE = playhead follows the ride), KEYS ON + amount, + KEY / DEL KEY / ZERO KEY / SAVE / RELOAD, sliders by group;
  bottom = timeline (phase bands, key diamonds, morph-size curve, white line = the ride's moment, orange = your playhead; drag
  playhead / key, right click a key = delete, double click = new key). Moving a slider auto-keys at the playhead. Closing saves.
- Tests: `BMX_POSELAB=air|<secs>` opens it paused (first flight / after n s), `BMX_POSELAB_SET="0.55:hip_y=0.1,torso_pitch=0.3;0.7:..."`
  (raw radians / metres), `BMX_POSELAB_PLAY=1`; with `BMX_FOLLOW=1 BMX_BIGAIR=1`, `BMX_SHOT`.
- **3D handles** (same day, user: "a skeleton interactable we can click on joints and drag, also bike, spin the handlebar"):
  the skeleton (`Rider.J`) is drawn over the ride with orange joint handles; click + drag in the 3D view (a ray against the
  plane through the joint facing the camera, the move taken into the bike's frame): hips -> hip xyz, chest -> torso lean
  (angle about the hips), head -> nod / turn, elbows / knees -> out / in, front / rear wheel (green squares) -> bike nose
  up / down under the body, bar centre -> bike lay over, grips -> the handlebar turns (`bar_steer`, + = right; the rig's own
  steer is + = left, so `Game._pk_bar` negates it; added to the drawn steer in `Game`, hands follow because the limb targets
  are read after). Hands / feet are grey dots (pinned). A drag edits the key at the playhead (auto-key). Tests:
  `BMX_POSELAB_DRAG="hips:0.05,0.05,0;..."` (metres, bike frame), `BMX_POSELAB_MOUSE="hips:60,-40"` (pixels, the real ray path).
  "Bike under body" turns the RIDER about the bottom bracket, so a dragged bike handle stays put and the rider moves
  (relative pose is right, the cursor does not follow the bike point).
- **Clip library** (same day, user: "predefined poses library for different tricks ... clips we fade into when the rider triggers
  them, industry standard"). Layered additive animation like production games: the live procedural pose (physics + IK) stays
  underneath; authored clips fade in on top. A clip (`PoseKeys.clips`, JSON v2 `res://data/pose_keys.json`; a v1 file becomes the
  "Jump style" clip): name, **trigger**, **time source** (`jump` = the jump timeline, `clip` = seconds since it fired, over
  `length`), fade in / out, strength, mirror, enabled, keys. `Game._clip_signal` reads the trigger from the physics state
  (read only; `PoseKeys.TRIGGERS`: jump, whip, tabletop, scrub, back / front flip, spin, manual, stoppie, corner, sprint, air,
  ground, always, never = preview only) as (amount 0..1, side +-1); `Game._clips_mix` ramps each clip's weight by its fade
  times, reads its timeline, mirrors it by the side it fired on (`PoseKeys.MIRROR`: roll, bars, hips z, torso roll / yaw, head
  yaw), and SUMS the weighted offsets x `amount`; the rider's limits still run after. Starter clips (first guesses, tweak
  them): Jump style, Whip, Tabletop, Scrub, Back / Front flip tuck, Manual, Stoppie, Attack stance (off). Pose Lab: CLIP
  LIBRARY block (pick / NEW / DUP / DEL / rename, trigger, time source, length, fades, strength, ON, MIRROR, SOLO). SOLO (default)
  plays only the clip being edited at the playhead; off = the whole library as in a ride. Timeline shows jump phases or the
  clip's seconds. Tests: `BMX_POSELAB_CLIP=<name|n>`, `BMX_POSELAB_SOLO=0`, `BMX_CLIP_PROBE=1` (`CLIPS` lines: active clips).
  Not possible: hands-off / feet-off tricks (no-hander, superman): hands and feet are pinned to the bike.
- Not done: easing choice per key, undo, hands / feet are not movable, per-bike libraries, importing / exporting a single clip.

### Ride the line again (2026-11-24, replay **L**, Pose Lab RESTART LINE; `Game._line_*`, `ReplayMode.reride_from_here`)
- User ask: "the rider that rides that line can then be tweaked". Every physics step's input (all keys of the input
  dictionary, bools kept as bools) + where the bike was is kept (`Game._line_record`, up to 6 min; cleared on respawn). In a
  replay, L at the playhead = `reride_from_here`: the nearest snapshot (4x a second, `ReplayMode.snaps`, now with the step index
  as `[3]`) is put back (`ride_from_snap`, shared with ride from here) and `line_input` feeds the recorded inputs in LIVE, so the
  rider rides the same line with whatever style is set now (Pose Lab clips / keys, Anim Studio). Style only: the physics is
  the same code on the same inputs. When the inputs run out the player has the bike (flash "LINE FINISHED" + drift).
- **Pose Lab**: RESTART LINE = back to where the re-ride started, ride it again (so: pause mid-air, tweak, RESTART, watch);
  STOP LINE; the header shows `LINE t / total  drift`. The recording / replay carry on from the restored moment as in ride from here.
- **Drift** (the re-ride's bike vs the recorded one at the same step, `line_play.drift`): 0.3-0.6 m after 9-16 s at ~17 m/s (the
  grip noise isn't restored, nor torn tape / fences). Test: `BMX_LINE_PROBE=1` (`LINE start / finished ... drift_max`),
  `BMX_REPLAY=20 BMX_REPLAY_SET="at=-9,reride=1"`, `BMX_POSELAB_RESTART=1`.
- Not done: old saved replay files have no inputs (re-ride only works for the session's own recording); saving the line with a
  replay file; a gizmo to nudge the line itself (the line is the recorded inputs, not editable).

### Style Inspector (2026-11-24, T in the instant replay / a saved replay; `ui/style_inspector.gd`)
- User ask: drive a line, replay it, "see what our skeleton did, what animation did he use, when did we trigger different
  animations, everything I would need so I could tweak and change our riding style", also on the recorded rides.
- **Recorded**: every replay sample now carries a style row (`Game._style_fill`, names in `Game.style_names`, rebuilt when
  `PoseKeys.rev` changes): `pose|t` (jump timeline), per Pose Lab clip `clip|<name>|w` (fade weight) / `|sig` (its trigger's
  signal) / `|t` (its own timeline), the summed channels applied (`ch|..`), the physics signals the triggers read (`sig|..`: km/h,
  air, bike lean, whip, flip, yaw rate, manual, nose, pop, squash, prep, land fold, air pull) and the procedural pose's inputs
  (`drv|..`: preload, extend, popFx, squash, landFold, landReach, airPull, bodyStick, hipShift, flip*, lipK, bodyLat, airWhip,
  lean, steer, pitch). Frames `[11]` = row, `[12]` = names. Saved replays keep them (`sty_sets` in the body, frame index 10 / 11
  of a saved frame; VER unchanged, older files just show "no style data").
- **Panel** (T; Y = window 3 / 6 / 12 s): CLIP LAYERS (one lane per clip that took part: fill = weight, white line = trigger signal,
  click a lane label = pick the clip, click the axis = go there), FIRED / LET GO events with times relative to now, POSE CHANNELS
  as curves with the value now, RIDER STATE NOW. **Insert** in a replay = Pose Lab here (ride from here, paused) with the picked clip
  selected and its playhead at the clip time of that moment, so: ride -> replay -> see which clip fired and how hard -> edit it.
- Not recorded: the skeleton's own joint angles (the drawn bones are already in the replay; the channels show what the clips
  added), the live ride has no inspector (use the replay: I).
- Test: `BMX_REPLAY=<secs> BMX_REPLAY_SET="cam=Side,at=-14,pause=1,style=1,pick=<clip>,win=6" BMX_REPLAY_SHOTS=<prefix>`.

### Anim Studio (2026-11-24, `--anim`, or Insert in the rider room; `ui/anim_studio.gd`, `rider/anim_lib.gd`)
- User ask: "modify our main menu stuff where the driver stands and idles", "import Mixamo and retarget automatically",
  "blend and use them". `RiderAnim` (see "Animation clips / Mixamo" above) already retargeted + crossfaded clips on the menus'
  standing rider (rider room KIT tab, ride setup CHARACTER step); the Studio adds the tools around it.
- **Import at run time**: IMPORT... (native file dialog, multi select) copies a Mixamo FBX / glb to
  `user://anim/mixamo/` (`AnimLib.import_file`) and loads it with `FBXDocument` + **`FBXState`** (GLTFState gives "state.is_null()"),
  no editor import; `RiderAnim.clip_files` lists them with the project's `assets/anim/mixamo/` clips; REMOVE deletes an imported one.
  Retargeting = the existing direction-based `RiderAnim._retarget` (any Mixamo character / skin; lengths stay the rider's).
- **Per clip settings** (`AnimLib.cfg`, `res://data/anim_library.json`, user:// when res:// is read-only): ON, IDLE (the clip the
  menu returns to between the others; a name with "idle" still counts), speed, pick weight, hold seconds, fade-in, and
  **offsets** (hips xyz, torso pitch / roll / yaw, head nod / turn, elbows / knees out): `AnimLib.offset_pose` moves the upper body
  as one chain, solves arms and legs again by IK (feet stay planted, nothing stretches). `RiderAnim.step` uses all of them, so
  every menu that shows the standing rider follows the library.
- **Modes**: PLAYLIST (exactly what the menus play), CLIP (loop one, scrub, pause), BLEND (A + B by a slider, B phase-locked to A
  or free; `RiderAnim.blend_poses`).
- **BAKE -> RIDE CLIP**: `AnimLib.bake` samples a clip (14 keys, relative to its first frame) into a Pose Lab clip on the hips /
  torso / head / elbows / knees channels (trigger "never"); set its trigger in the Pose Lab and it plays in rides. A standing
  clip's motion is small and the rider has no feet off the bike: it suits idle-like / body moves, not full-body tricks.
- Tests: `--anim` with `BMX_ANIM_IMPORT=file`, `BMX_ANIM_SEL=name`, `BMX_ANIM_MODE=0|1|2`, `BMX_ANIM_MIX=0..1`,
  `BMX_ANIM_OFF="hip_y=-0.05,torso_pitch=0.3"`, `BMX_ANIM_BAKE=1`, `BMX_ANIM_SHOT=png` (+ quits); `-s res://tools/fbx_runtime_probe.gd`.
  A test import writes into the player's `user://anim/mixamo/` (delete it after).
- Not done: a button on the title menu itself (use `--anim` / Insert in the rider room), blending several clips as layers,
  root motion, retargeting to the riding pose (clips are standing only).

### Photo mode (O, `scripts/game/photo_mode.gd`)
- Time freezes (`Engine.time_scale = 0`), HUD hidden, the camera comes loose: `Game._process` calls `PhotoMode.update(real dt)`
  instead of the ride; `CameraRig` / `hud` ignore input while `game.photo`; Esc / O / pad B / the card's ✕ leave.
- Camera: right drag look (mouse captured), left drag orbit the rider (`pivot()`: the bike +1 m, the ragdoll's centre
  after a crash), middle / shift + left drag pan, wheel dolly, ctrl + wheel zoom; WASD fly, Q / E down / up, Shift ×4,
  Alt ×¼, arrows look, Z / X roll, - / = zoom, R back to the start view. Pad: sticks fly / look, LT / RT down / up,
  LB / RB roll, D-pad zoom, A shoot, X grid, Y hide the card. Kept within `RANGE` (70 m) of the rider and 15 cm above
  `Terrain.top_height`.
- **Top shadow quality while open (2026-11-24, `PhotoMode._shadow_boost`)**: 4 cascades fitted round the subject (the
  ride uses 2), an 8192 atlas with the softest filter, every mesh at full detail (LOD threshold 0); closing puts back
  the settings' (`Settings.apply_render_quality`) and the ride's cascades (`Game._apply_settings`). Test: `BMX_PHOTO=8
  BMX_PHOTO_SNAP=1 BMX_PHOTO_CLOSE=14` prints `PHOTOSHADOW` lines (splits on open, the ride's mode after close).
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
- **Sound mixer (2026-11-24, Settings › Audio, `settings_menu.gd` `_audio`)**: master switch (`mute_all`), `volume` (Master bus),
  `sfx_volume` (SFX bus = all game sounds), then five channel buses under SFX made by `Settings.apply()` from `Settings.MIX`
  (`Wind` tyres / wind / water bed in `ride_audio.gd`'s main stream, `Bike` freewheel + chain + shifts, `Impacts` landing slam
  pool + bone crunch, `World` TVs + garage door, `UI` computer beeps + paper): each has `vol_<key>` (0..1.5) and `on_<key>`.
  Every audio player picks its bus with `Settings.bus_for("Name")` (falls back to SFX / Master): use that for new sounds, never
  a literal bus name. Output device = `audio_device` (`AudioServer.output_device`). Focus-in restores the master mute to `mute_all`.
  Crash / wood-smash one-shots are mixed into the Wind stream (they don't have their own player), so they follow Wind, not Impacts.
- The title menu no longer has the WORLD seed box / NEW WORLD button (user, 2026-11-24); R / the pause menu still make a new world.
- **Fresh worktree setup**: a new `claude/*` worktree has no import cache or C# build: run `godot --headless --import` then `dotnet build`
  in `godot/` before any test (otherwise `Tokens` / `UITheme` "not declared" and `CSharpScript.new` errors). The import also rewrites
  many `.import` files: don't commit those, `git add godot/scripts` only.
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
| `BMX_SKIP_PROBE=1` (+ `BMX_DEMO=1` or `BMX_FOLLOW=1 BMX_TRICK=none`) | every time the wheels leave the ground, sorted: built jump / hop or pop / crash / **skip** (the ground threw the bike off by itself); `SKIP` lines (speed, air, height, slope, v^2 x the ground's curve in g: < -1 = a crest it must fly over, > 0 = thrown out of a dip by the springs), `SKIPSUM` every 10 s (per km, one-wheel lifts). 2026-11-23, seed 4242, 120 s: demo AI 1.9 skips/km (all < 0.15 s); follow rider (52-62 km/h, no braking) 5.4/km, 6 s in the air, 3 of 9 thrown out of a dip |
| `--headless res://tools/slope_stress.tscn -- slide=1 [verbose=1]` | free riding off the trail (grass / sand, flat / bumpy) vs on it: how much of the time the rear is out with nothing asking for it (`SLIDE` lines); must stay ~0 past 15 deg |
| `--headless res://tools/slope_stress.tscn -- skip=1 [trace=1] [tune=...]` | hands off down a synthetic rough descent at 35-65 km/h: flights per 100 m sorted by the ground's curve at take-off (dip / crest / other), air time, time on the front wheel; repeatable, use it (not trail runs) to judge how the bike follows the ground |
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
  BUT a packed array stored in a Dictionary / Array and the member it came from share their data until one is
  re-assigned: the level builder kept `{"TX": TX}`, then `TX.clear()` emptied the dictionary's copy too (it lost the
  main line). Store `.duplicate()` when the original will be cleared / refilled in place.

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
- **Bike parts are individual pieces; merged only for riding** (user, 2026-11-24). In the garage and the shop every
  part (frame, rear end, linkage, shock, fork crowns / stanchions / lowers, stem, bar, grips, levers, calipers,
  rotors, cranks, pedals, saddle, post, chainring, cassette...) is its own node + mesh: swapped, shown alone on a
  shop card, painted and priced on its own. Only a ride merges each rigid group (what moves together: frame, rear
  end, steer, each wheel...) into a few meshes for draw calls (`MeshMerge`, as the action cams already are). The
  current glbs still bake many parts into one mesh (dh.glb's steer = stem + bars + grips + levers + crowns +
  stanchions; the seatstay holds the rear caliper), which is why the shop cuts stock parts out of meshes
  (`PartThumbs.make_part_alone`): the user will deliver properly split models; new models must come split.
- Riding / jump code: test it on the test playground (LEVELS, `BMX_LEVEL=playground`, section 5) before the trail; the user
  built it for exactly that.

## 9. Status & open items

Recently done (most recent first): dust is a real GPU smoke simulation (no sprites); bolder tread tyre tracks; no tyre clipping in the garage; compact garage
UI; door/flicker/glare fixes; closed front wall + camera kept in the room; ride-camera drag direction
matches the garage; slower mud; review fixes (crash torso culling, NaN freeze, BMX gearing, leftover mud,
photo mode, controls card, view distance, double world build, water re-bake, settings slider drag, garage
rebuild hitch); rider body physics (fore/aft + air tuck/lean); bending spine + pelvis sliders.

All of it is on `main` (the Godot branch was merged, the web version removed). Work continues in this repo.

**Ride code review (2026-11-27)**: physics / game loop / camera / rider / ragdoll / rig / tune read in full. Fixed:
a saved replay's viewer Game was parked as the player's next ride (`main._unpark_title`; `_take_prebuilt` now also
calls `Tune.set_ride`); a body-point hit on a fence / cactus was pushed out with the frame's radius (pulled a slow bike
INTO it, `b_min`); `_graze` never expired (ate the pop of a later take-off; cleared 0.25 s after touch-down);
`_land_hit` carried a judged landing into the next (cleared at the verdict); the head / chest ground check read
`air_lean` (fore / aft input) as roll; `_hop_pop` floored the descent rate at 0 (hops on a descent flew 2-3x high);
tyre prints / grass trample / blood per wheel (`front_air` / `rear_air`); `CameraRig.snap_to` also resets the view's yaw
(`_yaw_snap`), heading, slope, occlusion, and ride-from-here snaps the camera; the camera re-centre runs while riding
(it was an `elif` of the follow branch); `_reset_draw_state` also clears the lift / pivot / air offset / bar kick / dab;
`Rider.reset_pose` clears `_spr_arm` / `body_off`; the bar kick is measured per physics tick (`Game._bar_tick`); the
rider room's air preview passes `inAir`; the ghost records one sample per 1/30 s slot; `_shadow_fit` uses `cam.dist`
as is; the UpperArm bone's twist. Stress 56 / 56, playground suite identical before / after (it rides hands off).
Second pass, same day: `_step_drive` only records a brake that was applied (`braked`: backing up on purpose holds the
key with no brake on, and the lever force still went into the load split / friction circles); `a_pedal` = `a_drive`
without a brake applied rolling backwards (pedal-stamp kicks, body-back shift, HUD power, dust `g_long` read it; the
pitch torque keeps `a_drive`); the load split's clamp no longer runs with min > max; a touch-down turned > 83 deg off
the slope is left to `_land_trick` (UNDER- / OVER-ROTATED, not NOSE DIVE / LOOPED OUT when one wheel touched first);
`tune_presets.cfg` has a `ver` and custom presets drop `RETUNED_AT` keys from the NEXT retune on (older files are only
stamped: when their presets were saved isn't known); `_snap_prev` clears `_jw_prev` (no false JUMP note); the camera's
`dragging` is cleared while paused / photo / replay; `PlaygroundLab.KEEP` + `ReplayMode.SNAP_KEEP` hold `test_rider`
and `prof` (the suite's test rider used to lose TEST_ASSIST 0.85 after its first restart: **suite numbers moved, the
baseline needs re-saving**); the title sign's upright struts no longer warn in `look_at`.
Left: "Reset ride tuning" doesn't switch the active custom preset; `_rope_rail` returns instead of `continue` with two
bridges loaded; the brake-hold slide check (~line 1190) ignores `BRAKE_MU`; `_line_keys` fixed from the first input.

Known, not fixed (lower priority from the code review):
- Quit warnings: with SSIL on (GI setting 1, the default preset) Godot reports "7 RIDs of type Texture were leaked" at
  exit (gone with `--set=gi=0`; a bare SSIL scene doesn't do it, not found which of our viewports / features adds it;
  harmless, the OS frees it). "2 ObjectDB instances leaked" (ref count 0, C# side) also at exit; even an empty
  `--quit` reports 5. The big leak (89 objects + 3 scripts "still in use") was `field.course` <-> `course._M`, fixed.
- Records: top speed is lost if the window is closed instead of quitting. (Distance ridden works: `GameState.add_distance`.)
- Camera ignores rebound gamepad/camera keys (reads the right stick directly); `cam_up/down` unused.
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
- Perf (2026-11-23, `BMX_PERF` + the new `BMX_RENDER_PROBE`). Same follow ride, seed 4242: 88.6 -> 104 fps.
  (1) The drawn tyres' ground fit (`BikeRig.tyre_depth`, up to ~22 calls a frame x 33-48 points, each a GDScript ->
  C# height call + a GDScript `mesh_height`) is one C# call per tyre: `TerrainFieldCs.tyre_worst` (same points, the
  chunks' height grids registered with `mesh_add` / `mesh_remove` from `_finalize` / `_unload`), via
  `Terrain.tyre_worst` (null = the GDScript loop: no C#, a rope bridge loaded, or the playground: `cs_tyres` false;
  `BMX_TYRE_GD=1` forces it). tyre_unclip 0.46-0.67 -> 0.25-0.34 ms; CLIP probe unchanged.
  (2) **Sheep are C#** (`world/SheepHerdCs.cs`; `sheep_herd.gd` deleted; no C# = no sheep): all sheep drawn by 4
  MultiMeshes (was ~32 MeshInstances a sheep), the instance buffers filled once a frame, the C# field read directly,
  far calm flocks stepped every 4th frame, a failed placement waits 0.5 s (it searched 24 spots every frame). Smarter:
  they keep apart, lift their heads and watch an approaching bike (ears up), bolt out of its path rather than straight
  away, and run as a flock. `BMX_SHEEP_PROBE=1` (`SHEEP` lines with position), `BMX_SHEEP_NEAR=1`. 0.2-0.34 -> ~0.02-0.18 ms.
  (3) Rider / bike parts under `Game.SMALL_SHADOW` 10 cm across and the stickers cast no sun shadow (`Game._shadow_size`,
  with the rim tagging): shadow pass 1050 -> ~840 draw calls. `BMX_ALL_SHADOWS=1` = all.
  **`BMX_RENDER_PROBE=1`** (+ `BMX_IDLE=1 BMX_NOVSYNC=1 --autotest=45`, `game/render_probe.gd`): turns one part of the
  picture off at a time and prints GPU / render-CPU ms saved, draws and primitives (`RPROBE`), plus `RPARTS` (rider /
  bike mesh counts). At golden hour standing at the start: GPU 3.8 ms, render CPU 1.1 ms; sun shadows 1.0 GPU + 0.35
  CPU, half resolution 1.4, MSAA 0.55, decorations 0.5 + 0.29 CPU, ground 0.46, grass 0.37, rider + bike 0.32 GPU +
  0.54 CPU (245 meshes); smoke / SSAO / SSIL / SDFGI / fog / glow / SSR / DOF ~0 each.
  (4) **Rigid groups baked into one mesh** (`core/mesh_merge.gd`, `MeshMerge.merge(parent, sources, flat, keep, skip)`):
  plain opaque parts become one surface with their colour in the vertices and one material (roughness / metal
  averaged; parts this small don't show the plastic scans), emissive / see-through / `keep` materials one surface each,
  ShaderMaterial parts (blinking LED, halo, fur) left as they are; the merged mesh casts a shadow only if one of its
  pieces would have. Used on: every action cam (`ActionCam.merged`: the mount = one mesh, the Body = one mesh, so the
  crash tear-off still works; 22 meshes -> ~4 draws), the bike lamp + tail light (lens kept: it's switched on / off),
  the rocker's pivot bolts (15 -> 1). With the bar cam: 608 -> 518 draw calls in view, render CPU 1.18 -> 1.11 ms.
  The wheels were already one mesh each (+ rotor + rim stickers). `BMX_NO_MERGE=1` = as built. Garage part pictures
  (`PartThumbs`) still use the unmerged cam. The torn-off camera's box collider (`FlyingCam`) is now fitted to the
  model's own bounds (HERO 4.6 x 6.4 x 7.2 cm, X4 6.9 x 13.6 x 4.6), `GOPRO` lines print it.
  Left: the rider's kit (shoes 7, hands 5, knee pads ~11 meshes each) is recoloured live from the look, so it isn't
  merged; the physics step / rider pose (~0.3-0.4 ms each, thousands of lines of GDScript).
  The terrain is already C# for every query in a ride; the GDScript `TerrainField` only sets up and grows the trail
  (worker) and is the reference. `-s res://tools/terrain_cs_cmp.gd` doesn't start (tape_sim.gd needs the `CrashLog`
  autoload, which `-s` scripts don't load), found 2026-11-23, not fixed.
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
- **Frame profiler (F10, 2026-11-24, `game/frame_profiler.gd`, `FrameProfiler`, made by `Game.toggle_profiler` on first use;
  rebindable action `profiler`)**: compact (graph) -> full (graph + table) -> off. Every drawn frame: wall time, each
  `Game._perf` section (the same ones `BMX_PERF` prints; physics `p_*` included, filled only while it is open:
  `Game._prof_rec`), GPU + render-CPU time of the main viewport, draw calls, primitives, physics ticks, pipelines
  compiled while drawing (pink tick on the graph = a shader stall), and the ENGINE PHASES (`eng.*`, marker nodes at
  process / physics priority -/+100000 under the root + `RenderingServer.frame_pre/post_draw`): all `_process` (ours
  included), all physics ticks, the render, and "gaps" (present, waiting on the GPU, input). Graph: per frame our top 8
  sections coloured, the rest of our code grey, render CPU light grey, the rest of the frame (other nodes, GPU wait)
  faint; GPU = white dots; 120 / 60 / 30 fps lines; fixed 40 ms scale. It is an Image painted one column a frame
  (`_paint`) and drawn as one texture; the header + table refresh 4x / s (the first version drew 600 x 8 rects and
  recomputed everything each frame: the ride ran ~53 fps with it open, ~100 without; now ~96 vs ~101). Mouse over
  the graph = that one frame in the table.
  Shift+F10 freezes, Ctrl+F10 saves the 600-frame ring as CSV. A spike (> 25 ms or 2.2x the median, after the first
  second) is red and is written by itself with 60 frames before / 30 after to `%APPDATA%\Mini BMX\profiles\`
  (`spike_<ms>ms_<date>.csv`, max one per 5 s / 20 a session; tests: `profiles/tests/`). Reading a spike: one section
  jumping = that system; every section 3-10x slower at once = the whole process was starved (another GPU / CPU program,
  OS), not our code. Test: `BMX_PROF=1|2` opens it (+ `BMX_SHOT`); test runs print `PROF WORST` at exit (each section's
  worst single frame, after the first second). To add a section: `_pk = _perf("name", _pk)` in `Game._process` /
  `_physics_process` (only Game's own code is timed; other nodes' `_process` land in "engine"). A key with a dot is a
  SUB-section (not summed, not stacked; the table lists the top 3 `p_step.*` under `p_bike_step`): `BikePhysics.prof`
  (= the profiler's dict while it records) times every ride stage (`p_step.controls` .. `wheels`, `start_crash`,
  `crash_step`, inside `_step_vertical`: `v_sample`, `v_substeps`, `v_nose_checks`, `v_crash_checks`, the landing's
  `land_*`), `Game.get_up` its parts (`getup.*`), `Game.flash` (`msg.flash`).
  **Found and fixed with it the same day** (seed 4242 follow rides, worst single frame): (1) every get-up rebuilt the
  helmet action cam (`ActionCam.build` + `merged`): 91 ms -> ~1 ms, `Rider._cam_tpl` keeps a built copy per mount + gear
  and remounts duplicate it (`BMX_CAM_NOCACHE=1` = the old way); (2) `CrashLog.note` printed to stdout: 7-14 ms inside
  the physics step on every crash through a console pipe; it now writes straight into the session log (`_Sink._put`, no
  print); (3) the landing slam was rendered on the landing step (`SlamSynth.Render` + a per-sample GDScript WAV loop,
  5-10 ms): `SlamSynth.StartBank` pre-renders every size x sideways bucket (+ the bad-landing layer), 2 variants each, as
  16-bit PCM on .NET pool threads at ride start; `Take` hands one out (~0.05 ms) and re-renders that slot in the
  background (never the same twice). Worst physics step 18-30 ms -> 3-3.6 ms. (4) the first switch to the speed-blur
  grade shader (`_grade_sh_mip`, ~25 km/h) compiled it mid-ride, 8 ms: it is now set once while the ride loads.
  (5) `hud.warm_font` (one punch-font glyph a frame, up to ~7 ms) only shows in `--ride` test launches: a normal launch
  builds them all on the title backdrop during the intro / menu. `grime.*`, `hud.*` sub-sections are timed too.
  **Where a frame goes (seed 4242 follow ride, RTX 3090, 1600x900, the user's settings: vsync off, no cap, Ultra)**:
  ~100 fps, ~10-11 ms a frame, CPU-bound on the main thread (GPU ~30 % busy, main view ~4-5 ms): all `_process` ~6.4 ms
  (our timed sections ~3 ms, the other ~3.4 ms other nodes' scripts), render CPU ~2.5, physics ticks ~0.8, gaps ~1.7.
  **Other nodes' scripts** (`BMX_PROF_NODES=1` + `BMX_PROF=1 BMX_IDLE=1 --autotest=55`: every node running `_process`
  grouped by script, each group switched off for 110 frames, `PROFNODES group= nodes= ms=` = how much the whole _process
  phase shrank; use BMX_IDLE, a moving ride drifts too much): the hair was 2.1-2.5 ms. Its guide-lock step is now C#
  (`rider/HairSimCs.cs` `Step`, same maths; `Setup` on a style change, `SetState` on a reset, `GetP` once a frame) and
  the braid's mesh too (`PlaitFromSim` refills one ArrayMesh in place; it was rebuilt through GDScript lambdas every
  frame, ~1.4 ms): hair 2.45 -> 0.87 ms. `BMX_HAIR_GD=1` = the GDScript step + plait; `BMX_HAIR_PERF=1` (`HAIRPERF` /
  `HAIRUP` lines: the parts of a hair frame), `BMX_HAIR_CMP=1` (`HAIRCMP`: C# braid vs GDScript, same 3636 vertices
  within 0.07 mm). The same 30 s follow ride: ~101 -> ~133 fps; all _process 4.5 -> 2.9 ms. The grass carpet's
  per-frame tile placement (~950 tiles through a 6-plane view test) is C# too: `world/GrassPlaceCs.cs` (`SetHeights`
  when the height window changes, `Place` per ring, `Buf` only when the visible tiles changed; same tiles as the
  GDScript `_place`, `BMX_GRASS_GD=1` = that): 0.6 -> < 0.1 ms; all _process 2.4 ms. Left: `back_number.gd` (race
  number cloth) ~0.3-0.5 ms, the rest ~0.1-0.2 each. 1 % high ~16 ms.
- **Measuring perf**: other GPU programs (an open game window takes ~32 % of the 3090, other sessions' tests) cut the fps in
  half and make GPU spikes; check `nvidia-smi pmon -c 1` first. `TIME_PHYSICS_PROCESS` / `TIME_PROCESS` are the slowest
  single tick of the last second, not averages (our physics tick is ~0.3–0.7 ms). Don't print per slow frame while
  measuring: console prints through a pipe cost tens of ms and make more slow frames.
- **HITCH / MEM lines in every ride's session log (2026-11-27)** (`Game._hitch_watch`, F8 reports carry them): a drawn frame
  over 80 ms writes `HITCH frame_ms= phys_ticks= ... focus= | <top 5 of our _perf sections this frame> rest=<ms none of
  them covered> | gc_ms=<C# collector pause inside it> gc_runs=+g0/+g1/+g2 | at=<clock> sys_mem=<% of RAM in use>
  other_godot=<other Godot processes> proc= static= vram= objects= ... cs_heap= ...`; every 30 s of ride a `MEM t=` line
  with the same memory part (`CsGc.stats` / `counters`). Found with them: the user's 1-3.5 s freezes (F8, seed 61298) did
  NOT happen in a lone test ride (15 min, worst ~130 ms, memory flat at ~7.7 GB after the first minutes); each game
  process holds ~7-7.7 GB private (Godot's own static 0.6 GB, C# ~0.25 GB, the rest outside Godot's counters: driver /
  Vulkan, not looked into), and other sessions start ~1 test window a minute on the same PC. Read `rest`, `sys_mem` and
  `other_godot` of the next real freeze before changing code. C# allocates ~30-40 MB/s of garbage while riding (mostly
  chunk builds on workers), a collection every ~0.5 s, pauses ~1-2 ms each.

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

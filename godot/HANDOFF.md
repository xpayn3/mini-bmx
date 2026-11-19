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
**W/S in the air: lean back/forward (keep leaning → back/front flip)** · **A/D in the air: lean the bike left/right (no spins)** · **brake + A/D when slow: pivot (pirouette)** · Shift sprint (stamina) · Q/E shift gears · F bail · Backspace back to
start · R new world · B next bike · C next camera · Z/X rotate camera · +/- zoom · mouse drag orbit ·
H records · **P / K / L** the tuning card on its Ride / Rider / Look tab · O photo mode · F1 hide HUD ·
F12 screenshot · Esc pause. Gamepad: triggers pedal/brake, left stick steer, A hop, X sprint, bumpers gears.

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
| `scripts/ui/` | `hud.gd`, `settings_menu.gd`, `tune_card.gd` (the one tuning card: Ride / Rider / Look tabs, each with category tabs), `quick_tune.gd`, `rider_panels.gd` (`POSE_DEFS`, `KITS`, `LOOK_ROWS` + saving), `ui_theme.gd` |
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
- Every tuning value lives in `Tune` (tuning card, Ride tab + Rider › Physics); bikes multiply them (`BIKES.*.ride` + garage mods).
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
- Ragdoll on crashes (`ragdoll.gd`), then get up with Space.
- Look: kits + a colour per part (helmet shell/peak, goggles, jersey, pants, gloves, shoes).

### Ride light
- Clear afternoon: `Game.RIDE_SUN` / `RIDE_SUN_COL` / `RIDE_FOG`, sky fill 80% sky + 20% flat cool blue
  (`ambient_light_color`) so shade reads as sky light, thin volumetric haze (low ambient inject), cloud
  shadows `Atmos.CLOUD_DEPTH` 0.3. Bright greens go yellow through ACES if sun/exposure are pushed higher.

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
  the air is clear. `.glsl` files need an import (`--headless --import`) after editing. Falls back to the
  old sprites / FogVolumes without a RenderingDevice; `BMX_SPRITE_DUST=1` forces the sprites.
- Dirt chunks, **tyre tracks**: one ring-buffer ArrayMesh
  (14 000 segments ≈ 1 km/wheel, one draw call, each segment uploads only its own bytes) drawn by
  `tyre_track.gdshader` — lit, knob-tread dimples bump-mapped, soft edges + soil lip, skid streaks, distance fade.
- Grime: mud builds up (slow: `Grime.MUD_RATE` 0.25) and washes off in water; wet gloss + drips. Passes
  are removed from shared materials when a ride ends.
- Torn race tape as cloth-like ribbons, wind over the grass, drifting cloud shadows, speed blur / FOV.

### HUD bike computer (`hud.gd` `GaugeView`)
- Garmin-style computer bottom-left, three pages flipped with the ◀ ▶ bezel buttons under the screen:
  page 1 speed, slope / grade, **gear** (the shifter: gear n/N, side-on cassette, teeth; digit flashes on a shift;
  Settings › Gear shifter hides the row); page 2 elevation (`st.y`), ascent / descent this ride, 30 s profile.
  Page 3 **map** (`MapView`): heading-up 2D topo, 170 m across: contour lines (5 m, every 25 m bolder; marching
  squares over a 6 m height grid, 4 rows sampled per frame, rebuilt after 40 m), the trail centreline, the last 90 s
  ridden in magenta, north dial, 50 m scale bar.

### Settings & tuning
- Settings: display (mode, resolution, vsync, UI scale, FPS cap), graphics presets Low/Medium/High/Ultra
  + every option, audio buses, controls (rebind keys + pad), gameplay. Sliders apply on release.
- One tuning card (`TuneCard`): tabs Ride (Steering, Lean, Grip, Speed, Suspension, Jumps), Rider (Body, Spine,
  Head, Arms, Legs, Motion, Physics) and Look (Kits, Helmet, Clothes); P / K / L open it on Ride / Rider / Look,
  Reset resets the category shown. Quick tune card keeps the pinned (☆) sliders. Test: `BMX_PANEL=ride|rider|look`
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
| `BMX_GARMIN_PAGE=0/1/2` | bike computer opens on page 1 (speed / slope / gear), 2 (elevation) or 3 (map) |
| `BMX_TRICK=back/front/side/manual` | autotest leans that way in every jump (side alternates A / D; manual holds the nose up at `BMX_MANUAL_PITCH` rad for back-wheel landings) and prints `TRICK` / `LAND` / `BOUNCE` / `CRASH` |
| `BMX_STEER=1` / `-1` (+ `BMX_STRAIGHT=1`) | autotest holds a steady left / right turn after 2 s (lean / leg-clearance shots) |
| `BMX_AIRSHOT=dir/prefix` | autotest saves up to 8 screenshots mid-air |
| `BMX_KNEE_PROBE=1` | prints the biggest knee / hip move per frame and the torso stretch range, and logs (`KNEE …`) frames where a knee jumps |
| `BMX_TUNE=topSpeed=1.6,grip=1.1` | overrides tuning values for a test run (not saved) |
| `BMX_VMAX=1` | autotest prints the top ground speed reached (`vmax_kmh`) |
| `BMX_BIGAIR=1` (+ `BMX_TRICK=front/back`) | autotest launches every jump high (1.4 s air) so full flips happen |
| `BMX_PITCH_POSE=rad` / `sweep` | draws the bike at a fixed pitch (or spinning through flips) for rider-pose shots |
| `BMX_TYRE_PROBE=1` | measures tyre-to-floor / tyre-to-drum gaps for 12 wheel setups, then quits |
| `BMX_BUILD=wheels.rim_model=deemax;bars.width=820;logos.rims.count=4` | overrides the garage build for a test run (not saved unless you touch a control) |
| `-s res://tools/terrain_cs_cmp.gd --headless` | C# vs GDScript terrain must be EXACT |
| `-s res://tools/trail_grow_probe.gd --headless` | grows the endless trail 6×: old trail unchanged, C# = GDScript, timings; must say `PASS` |
| `-s res://tools/wood_edge_probe.gd --headless` | drives angled lines onto every wooden ramp; must report `walls=0` |
| `BMX_AUDIO_PROBE=1` | prints the freewheel's click rate / volume / output peak and the gravel surface / level twice a second |
| `-s res://tools/gravel_render.gd --headless -- out.wav [speed=8 tone=650 crack=0.3 …]` | renders the gravel synth alone to a WAV (compare with a recording) |
| `BMX_COAST=1` | autotest alternates 3 s pedalling / 3 s coasting (freewheel tests) |
| `BMX_REC=file.wav` | records the game's own sound output during an autotest |
| `BMX_SKID=secs` / `BMX_DUST_SHOTS=dir/prefix` (+ `BMX_DUST_T0`) | autotest locks the rear wheel from secs / a screenshot every 0.5 s (dust tests; `BMX_CAM=side` avoids the tilt-shift blur) |
| `BMX_LAND_TEST=secs` / `BMX_BAIL=secs` | autotest fakes a hard landing (landing dust) / bails (crash dust) at that time |
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
- PowerShell `Get-Content`/`WriteAllText` can change line endings — prefer the Edit tool for code edits.
- Light through a doorway straight at the camera = glare; keep the sun high and to the side in the garage.

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

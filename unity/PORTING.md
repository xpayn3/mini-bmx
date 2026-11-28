# Runout: Godot -> Unity port

State as of **2026-11-28**. Unity project = `unity/` (this folder). Working checkout: **`D:\Runout`** (a git worktree of
this repo on branch `unity`; open `D:\Runout\unity` in Unity Hub). The main checkout on C: keeps the Godot work. The Godot game in `godot/` stays the reference and
keeps running; port from it. `godot/HANDOFF.md` describes how every system works.

## The rules (user, 2026-11-28)
- **The soul is ours.** Bike physics, rider body, pose solver, ragdoll, crashed bike, terrain field: our own C#. Not PhysX
  vehicles, WheelColliders, Unity ragdoll joints or a bought controller. Unity's suspension (WheelCollider) is a car
  spring + damper: ours (air / coil, progression, spacers, LS / HS damping, bump stop, tyre pressure, anti-squat, dive,
  bob) is better, and its rate is ours (120 Hz steps x `suspSubsteps`, 4 = 480 Hz; 4 / 8 / 16 ride the same in Godot).
- **One physics source.** The ride is `godot/sim/` (engine-free C#, `namespace Runout.Sim`, bit for bit what the Godot
  game rides). Unity loads that folder as the local package `com.runout.sim` (`Packages/manifest.json`:
  `"file:../../godot/sim"`). Fix the physics there, once; never copy it into `unity/`. Nothing in it may reference an
  engine (`godot/tools/sim_purity.ps1`) and it must stay C# 9 (Unity's compiler; `SimTests` builds it with LangVersion 9).
- **Unity tech where it helps and is better**: skeletons (Humanoid avatar), animation, rendering, input, cameras,
  editor tooling. Our code drives them; they never decide how the bike rides. **Don't change the ride feel while
  porting**: port as it is, tune later.
- **The rider is a Unity Humanoid** (Mecanim avatar, standard bone map), so any Humanoid character model, Mixamo clip
  or Unity animation tool plugs in. Our rider code outputs targets / bone rotations for that skeleton.

## Layout
| Path | What |
|---|---|
| `../godot/sim/` (package `com.runout.sim`) | **The ride physics** (`BikeSim`, contracts `IGround` / `IRideHost` / `RideInput` / `RideParams` / `SusSetup`, Godot-exact maths / RNG / noise). Shared with Godot. |
| `Assets/Runout/Config/` | **Runout.Config** (engine-free): `Tune` (the 290 ride values from `TuneDefs.g.cs`, generated from `godot/scripts/core/tune.gd` by `Tools/gen_tune_defs.py`; player value x bike multiplier x Feel macros + followers -> `RideParams`), `SuspSetup` (fork / shock parts + clicks -> `SusSetup`), `FixedStepper` (120 Hz + interpolation). |
| `Assets/Runout/Game/` | **Runout.Game**: Unity adapters. `SimHost` (steps the ride on its own clock, draws interpolated), `BikeSimStep`, `RideHost` (IRideHost), `TerrainGround` (IGround over a Unity Terrain, test scenes only), `InputReader` (Input System -> RideInput), `BikeView` (axis bridge), `RideBootstrap` (builds the DH ride), `ChaseCamera` (stand-in). |
| `Assets/Runout/Editor/` | `ProjectBootstrap` (menu Runout > Bootstrap Project, re-runnable): HDRP, linear colour, Input System, 120 Hz fixed step, the Ride scene wired. |
| `Assets/Runout/Levels/` | **Runout.Levels** (engine-free): the test playground course + JumpDesign (ported from Godot, checked by SimTests), PlacedFeature (lane features placed anywhere). |
| `Assets/Runout/Game/Playground/` | PlaygroundWorld (course -> IGround + meshes, live in the editor), PlaygroundFeature (a placeable feature); Inspector: Ride from here. Scene `Scenes/Playground.unity`. |
| `Assets/Runout/Tests/PlayMode/` | play-mode tests (Unity Test Framework): the Ride scene rides under our physics. |
| `Assets/Runout/Art/` | assets copied from `godot/assets`. `Art/Plants` + beech leaf cards are licensed scans: gitignored, copied from the main checkout. |
| `SimTests/` | dotnet console project: builds `godot/sim` + Config with C# 9 and runs the checks, incl. **the Godot reference traces** (`SimTests/ref`, written by `godot/tools/port_trace.tscn`: 14 scripted runs; all match step for step). `dotnet run --project unity/SimTests`, exit code = failures. |

## Axis bridge
The sim keeps the Godot convention: right-handed, y up, forward = (cos h, 0, -sin h), + pitch nose up, + lean / steer
left. Unity: `BikeView.ToUnity(x, y, z) = (x, y, -z)`; yaw and steer change sign, pitch and lean don't. Only adapters
convert.

## Godot tools -> Unity editor
| Godot | Unity |
|---|---|
| Tuning card (P / K / L) | Editor window generated from `TuneDefs` (same groups / sliders, live in Play mode, saved in the project) |
| Pose Lab, pose morph keys, Anim Studio | No custom app: additive clips on the Humanoid in Unity's **Animation window** / Animator / Timeline; our code sets each clip's time (the jump phase 0..1) and weight (its trigger) |
| Level builder plugin | Native scene editing: **Splines** for trails, our jump / drop / rock pieces as components with gizmos, bake / checks as menu items |
| Land Lab | Editor window with the land knobs + Scene-view preview |
| Controls / rebinding | Input System action asset + in-game rebinding |
| Ride diagnostics graphs, playground test rider, physics checks | Ours (they read the sim): editor window + dev-only overlay (`Runout.Dev`, out of release builds) |
| F10 frame profiler | Unity Profiler |

## Unity tech map
HDRP (physical sky + sun, volumetric fog, SSR, contact shadows, decals) · Humanoid + Mecanim + **Animation Rigging**
(IK fed our targets) · Input System · Cinemachine 3 (camera brain; our TrailView logic decides the framing) · Burst +
Jobs (chunk builds; the height field stays exact C#) · VFX Graph (particles; the smoke sim stays our compute) · Shader
Graph / HLSL · glTFast (`.glb`) · Splines · Timeline · Test Framework · Steamworks.NET.

## Port order
1. ~~Bike physics~~: **done** (`godot/sim`, shared). Still to bring into Unity: the crashed-bike body (`CrashBikeCs`) and
   ragdoll (`RagdollRbCs`) behind `IRideHost.crash_body_step` (step 5), the drawn suspension (`ISusp`, step 3).
2. **Terrain field**: `TerrainFieldCs.cs` + trail course -> engine-free C# (like `godot/sim`, shared), implementing
   `IGround`; chunk meshing as Burst jobs in Unity.
3. **Ride scene**: the bike model (dh.glb) + BikeRig (wheels, fork, linkage, fit to ground), `ISusp`, the trail camera, HUD.
4. **Rider**: Humanoid rig + Animation Rigging fed by the ported pose solver (`rider.gd`).
5. **Ragdoll + crash bike** (already C# in Godot: make them engine-free and share like `godot/sim`). Hybrid (user,
   2026-11-28): our solver + behaviours (tuck, brace, pain, windmill, holds) and our crashed-bike body stay ours;
   Unity does the Humanoid skeleton (driven from the ragdoll like the riding pose), collision against the scene's
   colliders (physics queries), and getting up (Mecanim clips blended out of the ragdoll pose). Not PhysX joints.
   **Rider, Unity-style (2026-11-28)**: our solver gives points + frames only (pelvis, spine, head, grips, shoes, where
   elbows / knees point); each Humanoid bone is turned from the model's own rest axes, arms / legs are two-bone IK on its
   own bones, fingers are Humanoid muscles (ours decides grip / lever / squeeze), joints held in the human range. No
   Godot bone conversion (it twisted shoulders / hands on a different skeleton).
6. **Look**: ground / grass / trees / water, mud / dust / blood, smoke sim, ruts / prints.
7. **Game shell**: menus, garage, shop, replay, photo mode, ghost, sound (our C# synths via `OnAudioFilterRead`), Steam, saves.
8. **Dev tools** in `Runout.Dev`, excluded from release builds.

## Status
- [x] Unity 6000.3.10f1 (6.3 LTS) + HDRP, installed via Unity Hub 4 (C:\Program Files\Unity\Hub\Editor).
- [x] Project, assemblies, packages (pruned), bootstrap, Ride scene; assets copied.
- [x] Ride physics = `godot/sim` as a package; SimTests: all 14 Godot reference runs match.
- [x] Play mode: the Ride scene rides under our physics (test `RideTests.PedallingMovesTheBike`).
- [x] Test playground: `Scenes/Playground.unity` (reference lanes + bowls from Runout.Levels, exact vs Godot) and
      **PlaygroundFeature**: place any lane feature in the scene, set its numbers, press Play / Ride from here.
- [x] Gears, chain, effort (`Game/RideGears.cs`, `Game/Bike/BikeChain.cs`, `Game/Rider/RiderEffort.cs`): Q / E, LB / RB
      shift into `BikeSim.shift` (the sim's cassette, real drive ratio, spin-out, chain skip under load; shifter
      recordings play). **Drivetrain = the bike HDA's derailleur / chain solve, ported** (`Game/Bike/RearDerailleur.cs`,
      engine-free): the SRAM Force eTap AXS model from the HDA (`tools/export_rd_sram.py` -> `Art/Models/Bikes/rd_sram.glb`
      + `rd_sram.extras.txt`: 6 rigid parts + the kinematics the HDA measured), B-tension set once on the biggest cog,
      slant parallelogram to each cog plane, cage on the top pulley's axle solved to close a FIXED chain (big-big + 2
      links), sprung cage + clutch + the runs as strings (bow, chainstay slap), chain climbs onto a new cog only as it
      travels. Checked against a Houdini cook: B-tension 0.5749 rad, 108 links, cage 252.03 / 270.33 / 296.02 deg in
      gears 1 / 4 / 7 (C# 252.03 / 270.32 / 296.02). Any ring / cassette is solved (modular), but this mech can't
      reach big cogs (gap < 0 from ~32T, as the real road Force AXS): `BikeChain.Problem` says so. So the Unity DH rides
      the cassette drawn on its wheel (`dh.ride.txt` cogs 10-24 7-speed, was 9-50). dh.glb's frozen chain (swingarm)
      and frozen derailleur (seatstay) are cut out at load. F7 = close-up camera on the drivetrain. Robust: the
      dynamics' step follows the stiffest spring (cage vs chain, the runs at their highest tension, the chainstay),
      a frame over 1/30 s just loses the time, nothing non-finite is ever drawn (falls back to the last good pose);
      stress test 20k frames with 0.3 s hitches / 400 m/s2 hits / NaN inputs: 0 bad. Light: ~14 us a frame (solve
      3, dynamics 8, path 3), no dynamics at the far LOD (the swept band, as Godot), the mech decimated to 7k
      triangles (RD_REDUCE_PCT). Heart rate / power /
      cadence = hud.gd's model, fed to the pose (breathing, fatigue). Stand-in OnGUI readout until the HUD is ported.
      Not done: a long-cage (Eagle-class) mech for 10-52+ cassettes (the HDA's "built" rd_type 0 is the way), a
      procedural cassette per build (the wheel's is fixed), the ring mesh for other chainrings, the physics changing
      gear before the chain has climbed (it switches at once), shift clips + the mech load only in the editor.
- Note: keep the project on a short path (D:\Runout): deep paths hit Windows' 260-character limit in HDRP's import.

## Commands
```powershell
# open the project
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -projectPath D:\Runout\unity
# bootstrap / compile check, headless
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -batchmode -projectPath unity -executeMethod Runout.EditorTools.ProjectBootstrap.Run -quit -logFile unity/Logs/bootstrap.log
# play-mode tests, headless
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -batchmode -projectPath unity -runTests -testPlatform PlayMode -testResults unity/Logs/playmode.xml -logFile unity/Logs/playmode.log
# physics checks (no Unity needed): C# 9 build of godot/sim + the Godot reference traces
dotnet run --project unity/SimTests
# new reference traces from Godot (after a physics change on purpose)
& "C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path godot res://tools/port_trace.tscn -- out=<repo>/unity/SimTests/ref
```

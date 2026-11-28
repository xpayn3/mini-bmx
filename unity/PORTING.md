# Runout: Godot -> Unity port

State as of **2026-11-28**. Unity project = `unity/` (this folder). The Godot game in `godot/` stays the reference and
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
5. **Ragdoll + crash bike** (already C# in Godot: make them engine-free and share like `godot/sim`).
6. **Look**: ground / grass / trees / water, mud / dust / blood, smoke sim, ruts / prints.
7. **Game shell**: menus, garage, shop, replay, photo mode, ghost, sound (our C# synths via `OnAudioFilterRead`), Steam, saves.
8. **Dev tools** in `Runout.Dev`, excluded from release builds.

## Status
- [x] Unity 6000.3.10f1 (6.3 LTS) + HDRP, installed via Unity Hub 4 (C:\Program Files\Unity\Hub\Editor).
- [x] Project, assemblies, packages (pruned), bootstrap, Ride scene; assets copied.
- [x] Ride physics = `godot/sim` as a package; SimTests: all 14 Godot reference runs match.
- [x] Play mode: the Ride scene rides under our physics (test `RideTests.PedallingMovesTheBike`).
- [ ] Note: in a deep worktree path a few HDRP files hit Windows' 260-character limit on import; the normal checkout
      (`Documents\gamecycling\unity`) is short enough.

## Commands
```powershell
# open the project
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -projectPath D:RunoutNity
# bootstrap / compile check, headless
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -batchmode -projectPath unity -executeMethod Runout.EditorTools.ProjectBootstrap.Run -quit -logFile unity/Logs/bootstrap.log
# play-mode tests, headless
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -batchmode -projectPath unity -runTests -testPlatform PlayMode -testResults unity/Logs/playmode.xml -logFile unity/Logs/playmode.log
# physics checks (no Unity needed): C# 9 build of godot/sim + the Godot reference traces
dotnet run --project unity/SimTests
# new reference traces from Godot (after a physics change on purpose)
& "C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path godot res://tools/port_trace.tscn -- out=<repo>/unity/SimTests/ref
```

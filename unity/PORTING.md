# Runout: Godot -> Unity port

State as of **2026-11-28**. Unity project = `unity/` (this folder). The Godot game in `godot/` is the reference
until the port rides as well as it does; keep it runnable and don't develop features there any more.
`godot/HANDOFF.md` still describes how every system works: port from it.

## The rule (user, 2026-11-28)
- **The soul is ours.** Bike physics, the rider's body, the pose solver, the ragdoll, the crashed bike and the terrain
  field are our own C# code, ported from the Godot game. Not PhysX vehicles, not WheelColliders, not
  ragdoll joints from Unity, not a bought controller.
- **Unity tech where it helps and is better**: skeletons / Humanoid avatars, animation, rendering, input, cameras,
  tooling. Our code drives them; they don't decide how the bike rides.

## Layout
| Path | What |
|---|---|
| `Assets/Runout/Sim/` | **Runout.Sim**: the engine plug. Pure C#, `noEngineReferences` (no UnityEngine), C# 9. Bike, rider body, ragdoll, crash bike, terrain field, trail, tune. Talks to the world only through `IGround` / `IRideEvents`, takes `RideInput`, gives `SimPose`. |
| `Assets/Runout/Game/` | **Runout.Game**: Unity adapters. `SimHost` (steps the sim at 120 Hz on its own accumulator, draws interpolated), `InputReader` (Input System -> RideInput), `BikeView` (sim pose -> transforms, axis bridge), `TerrainGround` (IGround over a Unity Terrain, test scenes only). |
| `Assets/Runout/Editor/` | `ProjectBootstrap` (menu Runout > Bootstrap Project): HDRP asset, linear colour, Input System, 120 Hz fixed step, the Ride scene. Re-runnable. |
| `Assets/Runout/Art/` | Assets copied from `godot/assets` (models, textures, HDRIs, audio, anims, fonts, UI). `Art/Plants` and the beech leaf cards are licensed scans: gitignored, copied from the main checkout. |
| `SimTests/` | dotnet console project compiling `Assets/Runout/Sim` outside Unity: `dotnet run --project unity/SimTests`. The Godot `slope_stress` / playground-suite checks move here as they're ported. Exit code = failures. |

## Axis bridge (sim <-> Unity)
The sim keeps the Godot convention so the port is line for line: right-handed, y up, forward = (cos h, 0, -sin h),
+ pitch = nose up, + lean / + steer = left. Unity is left-handed: `BikeView.ToUnity(x, y, z) = (x, y, -z)`;
yaw and steer change sign, pitch and lean don't (see `BikeView.Apply`). Only adapters convert, never the sim.

## Unity tech we use (and for what)
| Unity | Replaces in Godot | Notes |
|---|---|---|
| **HDRP** | Forward+, our sky shader, volumetric fog, SDFGI / SSIL | Physically based sky + sun, volumetric fog / sun shafts, SSR, contact shadows, decals (blood, prints), area lights in the garage. Our light model (`sun_sky.gd`) becomes HDRP sky + exposure settings. |
| **Humanoid avatar + Mecanim** | `RiderSkeleton` (Godot humanoid profile), `RiderAnim` direction retargeting | The rider gets a real Humanoid skeleton; Mixamo clips (get-up, dizzy, menus) retarget natively. A real skinned rider model can drop in later. |
| **Animation Rigging** (TwoBoneIK, MultiAim, Override) | `Rider.limb_ik`, head aim | IK solving only. The TARGETS (hands on grips, feet on pedals, hips / chest / poles, the whole style pose, limits) come from our rider pose code in Runout.Sim. |
| **Input System** | Godot InputMap + `Settings` rebinding | Keyboard + Xbox pad, rebinding via `InputActionRebindingExtensions`, rumble via `Gamepad.SetMotorSpeeds` (PadRumble port). |
| **Cinemachine 3** | `CameraRig` follow modes | Use as the camera brain / blends / impulse; our TrailView director logic stays ours (it decides what to frame). |
| **Burst + Jobs + Mathematics** | worker-thread chunk builds, C# terrain field | Chunk ground / decoration builds as Burst jobs; the height field stays exact pure C# (it's what the physics reads). |
| **VFX Graph** | GPU dust particles, grit, sparks | The 3D smoke simulation itself stays our compute shaders (port GLSL -> HLSL compute). |
| **Shader Graph / HLSL** | `.gdshader` files | Ground, grass, paint, mud / grime passes. HLSL for the heavy ones. |
| **glTFast** | Godot glb import | All bike / part / helmet `.glb` files import as-is. |
| **Splines** | Path3D in the level builder | Level builder trails. |
| **Timeline** | intro (CRT) sequencing | Optional. |
| **Unity Test Framework** | autotest flags | Play-mode tests in Unity; pure sim tests stay in `SimTests` (faster). |
| **Steamworks.NET** | same | Already C#, drops in. |

## Port order (each step ends riding / visible, measured against Godot)
1. **Bike physics**: `bike_physics.gd` (4.4k lines) + `suspension`, `susp_setup`, `tune.gd`, `tune_presets` -> `Runout.Sim.Bike`.
   Hot `T.get` keys become cached fields. Port the 11 ride stages as they are (`_step_controls` .. `_step_wheels`).
   Check: port `slope_stress` checks into SimTests and match Godot's numbers (coast speed, brake g, turn radius,
   jump air / height) within a few %.
2. **Terrain field**: `TerrainFieldCs.cs` (already C#, drop Godot types) + `trail_course`, `route_spine`, `trail_features`
   -> `Runout.Sim.World`, implementing `IGround`. Check: same heights as Godot for the same seed (dump a grid from
   Godot, compare in SimTests). Then chunk meshing as Burst jobs in Runout.Game.
3. **Ride scene**: bike model (dh.glb), `BikeRig` (wheels, fork, linkage, fit to ground), chase / trail camera, HUD speed.
   First ride on the ported world.
4. **Rider**: pose solver (`rider.gd` 3.2k lines) -> Runout.Sim (pure maths: joint targets) + Unity Humanoid rig with
   Animation Rigging constraints fed from it; gear (helmet, goggles, shoes, pads) as meshes on bones.
5. **Ragdoll + crash bike**: `RagdollRbCs.cs` (XPBD rigid bodies) and `CrashBikeCs.cs`: already C#, move into
   Runout.Sim, draw on the Humanoid bones.
6. **Look**: ground / grass / trees / rocks / water shaders, mud + dust + blood, dust smoke sim, tyre prints / ruts.
7. **Game shell**: menus, garage, shop, replay, photo mode, ghost, sound (freewheel / gravel / slam synths are C#:
   feed them via `OnAudioFilterRead`), Steam, settings, saves.
8. **Dev tools** (`godot/dev` equivalents) in a separate `Runout.Dev` assembly, excluded from release builds.

## Status
- [x] Unity 6.3 LTS (6000.3.10f1) + HDRP chosen; editor installed via Unity Hub (C:\Program Files\Unity\Hub\Editor).
- [x] Project skeleton, assemblies, packages, bootstrap, Ride scene.
- [x] Engine plug interfaces + fixed 120 Hz stepper; SimTests builds with dotnet and passes.
- [x] Assets copied (~1.2 GB incl. local-only plants).
- [ ] Step 1: bike physics.

## Commands
```powershell
# open the project
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -projectPath unity
# bootstrap / compile check, headless
& "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe" -batchmode -projectPath unity -executeMethod Runout.EditorTools.ProjectBootstrap.Run -quit -logFile unity/Logs/bootstrap.log
# sim tests (no Unity needed)
dotnet run --project unity/SimTests
```

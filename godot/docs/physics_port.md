# Ride physics in C# (2026-11-28)

**The ride physics is C# only.** Edit `godot/sim/BikeSim.cs` (+ `BikeSim.Manual.cs`). `scripts/bike/bike_physics.gd` is
only its GDScript face (state + calls handed over); never add physics there (user, 2026-11-28: "C# only so we don't
write two versions").

How it got here: the GDScript ride was translated to C# by a script (gd2cs.py), checked bit for bit against the GDScript
every tick, made the default, merged, and then the GDScript ride and the translator were deleted (all in git history,
commits "Physics port step 1..5" and "C# only").

## Goals
1. **Portable**: the ride core (`godot/sim/`) is plain C#, no engine reference: drop it into Unity, a console / Switch /
   mobile build or a server. Only a thin adapter knows Godot. `dev/port/simcheck/` builds it with no Godot at all.
2. **Deterministic everywhere**: its own math (SimMath), random numbers (Pcg32) and noise (Noise2S): the same answers on
   x64 / ARM / any compiler.
3. **Any terrain**: the physics only asks the world through IGround (below).

## Layout
```
godot/sim/                  engine-free core, namespace Runout.Sim (tools/sim_purity.ps1: no engine reference)
  BikeSim.cs                THE RIDE: one 1/120 s step and everything it calls (hand-edited source)
  BikeSim.Manual.cs         the constructor, setup(), the crash step's core, is_sane, the energy / jolt probes
  SimMath.cs                sin cos tan atan atan2 asin acos exp log tanh pow exactly as Godot computes them on PC
  Gd.cs                     GDScript's global functions with Godot's edge cases (maxf, clampf, move_toward, wrapf,
                            smoothstep, roundi, % formatting...) + V2 / V3 = Godot's float32 Vector2 / Vector3
  Pcg32.cs, Noise.cs        Godot's RandomNumberGenerator / FastNoiseLite (simplex smooth, FBm), bit for bit
  Contracts.cs              IGround (what it asks the world), IRideHost (what it tells the game), ISusp, RideParams
                            (Tune values: T.f("key")), RideInput, GdDict, SusSetup, SuspMath, Env (test switches)
godot/scripts/bike/
  bike_physics.gd           BikePhysics, the ride's GDScript face: the state as members, each call handed to C#.
                            The member list + _cs_out / _cs_in at its end are GENERATED (dev/port/gen_shell.py)
  BikePhysicsCs.cs          the hand-over (Step, Setup, Run, the statics) + the crashed bike / ragdoll step
  BikePhysicsCs.gen.cs      the same array slots on the C# side (generated)
  RideBridge.cs             Godot glue: GodotGround (Terrain), GodotRideHost (Game), GodotSusp, engine math, conversions
godot/dev/port/
  gen_shell.py              writes bike_physics.gd's members + mirror and BikePhysicsCs.gen.cs from BikeSim's fields
  simcheck/                 builds godot/sim alone, no Godot reference (portability check)
```

## Changing the physics
- Edit `sim/BikeSim.cs`. It still reads like GDScript (it was translated from it): snake_case names, `Gd.*` helpers,
  `T.f("tuneKey")` for Tune values (new Tune keys need nothing else), `GdDict` dictionaries, `Env.raw("BMX_X")` test
  flags (`static` fields). Math through SimMath / Gd (not `Math.*`) so results match the engine.
- **Added / removed / renamed a field** -> `python godot/dev/port/gen_shell.py`, then `dotnet build`. The game reads a
  field as `phys.name` only after that (a field the game never reads needs nothing). A stale shell stops at the first
  ride with "run gen_shell.py".
- **A new call from the game** -> one line in bike_physics.gd (`func x() -> void: _cs.Run(self, "x", [])`) + a `case` in
  `BikePhysicsCs.Run`.
- **A constant other scripts read** (`BikePhysics.G`, `FLOW_MAX`, `BRAKE_MU`, `SPIN_EDGE`...) is a copy at the top of
  bike_physics.gd; `_check_consts` compares the copies with the C# at the first ride.
- Check a change: the playground suite (HANDOFF section 5), `tools/slope_stress.tscn` (headless, rides the C#), rides.
- `cd godot/dev/port/simcheck && dotnet build` must stay at 0 errors (the core can't use Godot).

## How the game uses it
The game holds the GDScript `BikePhysics` (typed; everything reads it at full GDScript speed: the rider pose, audio, HUD,
ride log, replay snapshots, the playground's reset). Every call hands over to `BikePhysicsCs`: the 443 number / bool /
int values cross in one packed array, the C# ride works, they cross back (+ `crash_pending`, `_risk`, `_cb_hit`, the
crashed-bike body; `cogs` after setup; the Tune values when Tune changes and at setup / resets). Before each of the game's
callbacks inside a step (effects every tick, events) the state is mirrored to GDScript first and read back after, so the
game sees the mid-step values. Read-only questions (gear_k, drive_ratio, is_sane) answer from the C# state without a copy.
A new BikePhysics gets its starting values from the C# (`Defaults`). The static helpers (start_gear, crank_rate,
slowness, pedal_rock...) call the C# too, with the Tune autoload's values outside a ride.
(The C# object can't be the game's `phys` directly: every GDScript read would cross into C#, ~0.75 ms a frame.)

## Any terrain
The physics never knows what made the ground; IGround is the whole contract, metres, Y up: `height`, `deck_height`
(no rock / log bumps), `top_height` (drawn), `surface` (0 ground / 1 trail / 2 water / 3 sand), `jump_mask`,
`colliders_near` (plain dictionaries), and `cast(origin, dir, max)` -> RayHit. Any generator can answer these (Unity
Terrain, a mesh + raycasts, voxels). Limit: one height per spot, as today.
**Wallrides / overhangs later**: `cast()` is the general contact query; riding walls means a contact model on `cast` +
the surface normal (the bike's "up" from the ground instead of world +Y). The interface won't change.
**Unity / another engine**: copy `godot/sim/`, write an IGround + IRideHost (and an ISusp if the drawn suspension
limits travel), feed RideInput each fixed step, read the BikeSim fields to draw.

## How it was checked before the GDScript ride was deleted
- `tools/sim_math_probe.gd` / `tools/sim_rng_probe.gd`: 400k inputs per math function, 5 seeds x 200k random draws, 4
  noise configs x 200k: 0 mismatches.
- Lockstep (each tick the C# twin set to the GDScript ride's state, both stepped, all ~600 members compared bit for bit):
  0 mismatches over ~64k ticks (demo AI, flips, gamepad whips carved at the lip, manuals, stoppies, the whole playground
  suite), again after merging main's later physics changes.
- `tools/slope_stress.tscn` (default, sim=1, feel=1): every number identical GDScript vs C#; 56 / 56 checks.
- Playground suite: identical line for line (bar `brake_dirt_front`, which varies run to run in GDScript too).
- And after the GDScript ride was replaced by the shell: stress / feel / ground-sim output and the suite identical to
  the C# runs before it.

| function | Godot on PC | SimMath | mismatches / 400k |
|---|---|---|---|
| sin cos exp log atan2 | x87 (64-bit mantissa, then double; sin / cos reduced with the x87's 66-bit pi) | double-double rounded the x87 way; near-ties (~0.2 %) asked of the engine | 0 |
| pow | x87 (fyl2x / f2xm1) | same; a 256-ulp band (~19 % of calls) asked of the engine | 0 |
| atan asin acos tanh | the same CRT as .NET's Math on Windows | `Platform` hook = .NET Math | 0 |
| tan | neither model | `Platform` hook: the engine | 0 |
Without the engine hook (another platform) SimMath gives its own double-double answers: deterministic, within the last
bit of Godot's.

## Speed (seed 4242 follow ride, RTX 3090, no vsync)
`p_bike_step` per frame: GDScript 0.80 ms, C# 0.59 ms; slope_stress 151 -> 121 us a step. Inside a C# step: the ride
~90-135 us, ground queries ~70-125 us (straight to TerrainFieldCs / RutFieldCs), the mirror ~40 us, the game's own
callbacks ~120-150 us (`ride_fx`: GDScript). `BMX_CSPERF=1` prints where it goes.

## Not done / next
- The crashed bike / ragdoll step (`BikePhysicsCs.GameHost.crash_body_step`) drives engine objects (CrashBikeCs, the
  ragdoll): not part of the portable core.
- The plain (non-.NET) Godot can't ride any more.
- Tidy-ups now possible (the code no longer has to match a GDScript twin): typed fields instead of GdDict / T.f lookups,
  the generated-looking parts made idiomatic C#, the rider pose / ragdoll moved into the core too.

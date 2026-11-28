# Ride physics: GDScript -> portable C# (plan, 2026-11-28)

Branch `claude/physics-porting-c-39765e`. `bike_physics.gd` (4255 lines, ~445 members, 77 functions) stays in the
game and stays the default until the C# version matches it. Nothing on `main` changes until the user says so.

## Goals
1. **Identical**: same inputs -> same numbers as `bike_physics.gd`, checked step by step, not by feel.
2. **Portable**: the physics core is plain C# with **no `using Godot`**: it can be dropped into Unity, a console /
   Switch / mobile Godot build, or a server, unchanged. Only a thin adapter knows about Godot.
3. **Deterministic everywhere**: the core uses its own math (below), so it gives the same answer on x64, ARM
   (Switch, phones) and any compiler. GDScript's `sin` on ARM would not even match GDScript on PC.
4. Faster (the step is ~0.3-0.7 ms of GDScript a tick today).

## Layout
```
godot/sim/                 engine-free core (namespace Runout.Sim, no Godot references, checked by tools/sim_purity.ps1)
  SimMath.cs               sin / cos / tan / atan / atan2 / asin / exp / log / pow / tanh / sqrt exactly as GDScript
                           computes them on PC (x87 rounding, rebuilt in double-double), + GDScript helpers
                           (clampf, lerpf, move_toward, wrapf, smoothstep, signf...) with the same edge cases
  V3f.cs, V2f.cs           float32 vectors (Godot's Vector3 / Vector2 are 32-bit floats: same rounding)
  Pcg32.cs                 Godot's RandomNumberGenerator (PCG32) bit for bit
  Noise.cs                 the FastNoiseLite subset the physics uses (simplex smooth + fractal), bit for bit
  IGround.cs               what the physics asks the world: height, deck_height, top_height, surface, jump_mask,
                           colliders_near, ...
  IRideHost.cs             what it tells the game: flash, burst, smash, start_crash, on_landing, ... (events)
  RideParams.cs            the Tune values (by key, read once per step like `T`)
  BikeSim.cs (+ partials)  the ride step, one file per stage like the GDScript (_step_controls ... _step_wheels)
godot/scripts/bike/
  BikeSimGodot.cs          adapter: wraps Terrain / Game / Tune in IGround / IRideHost / RideParams, exposes the
                           state to GDScript under the same names
  bike_physics.gd          unchanged; BMX_PHYS=cs|gd|cmp picks which runs (gd = default until switched)
```
For Unity: copy `godot/sim/`, write a Unity adapter (terrain heights + events). Nothing else.

## Any terrain (user, 2026-11-28: "works on other terrains, e.g. other terrain generators in Unity")
The physics never knows what made the ground. `IGround` is the whole contract, metres, Y up:
- `Height(x, z)`: the ridden surface, rocks / logs / decks included
- `DeckHeight(x, z)`: the same without rock / log bumps (banks, slopes, lean room read it)
- `TopHeight(x, z)`: the drawn surface (tyres kept out of it)
- `Surface(x, z)`: 0 ground, 1 trail, 2 water, 3 sand (grip / braking tables)
- `JumpMask(x, z)`: 0..1 on built jumps (lip spotting, pump)
- `CollidersNear(x, z, r)`: posts / trunks / rocks / fences / tape (circles + boxes, plain structs)
Any generator can answer these: a Unity Terrain heightmap, a mesh with a downward raycast, voxels, a store-bought
generator. One without surfaces returns 0, one without jumps 0. Limit: one height per spot (no overhangs, tunnels to
ride through, wallrides), the same as today; a raycast adapter takes the highest surface under the bike.
Rope bridges / snow / ruts stay on the host side: they only change what these calls return.

**Ready for wallrides / overhangs (user, 2026-11-28)**: `IGround` also has
`Cast(origin, dir, maxDist) -> Hit { point, normal, surface, kind, hit }`, the general contact query. A height
field answers downward casts (the default implementation is built from `Height`); a mesh / collider world (Unity
raycasts, voxels) answers any direction, so walls, overhangs and tunnels are visible to the physics. The ported step
keeps asking for heights (identical results); a later wallride / overhang feature moves the contact model onto
`Cast` + the surface normal (the bike's "up" from the ground under it instead of world +Y). That is a physics
feature after the port, not part of it: the interface just won't need to change.

## How "identical" is checked
- **Math probe** (`tools/sim_math_probe.gd`): ~1M inputs per function, GDScript result vs SimMath, bit for bit.
- **Lockstep** (`BMX_PHYS=cmp`): every physics tick both run from the SAME state (C# is re-synced from GDScript
  before each step), then every member is compared; any difference prints the member, both values and the stage.
  Re-syncing each tick means a difference shows where it is made, instead of growing for seconds first.
- **Stage by stage**: stages are ported in order; the harness can run the GDScript step with chosen stages taken
  from C#, so each stage is proven alone before the next.
- **Free run**: both run side by side without re-syncing (how long they stay together; a chaotic ride amplifies
  even a last-bit difference, so this is a report, the lockstep is the proof).
- Then the usual: `slope_stress` (56 / 56 and line-for-line identical output in its modes), the playground suite
  (`compare` = 0 changed), demo AI rides, `BMX_LOG_INPUT` replays of the user's F8 logs.

## Step 1 result (2026-11-28): `tools/sim_math_probe.gd`, 400k inputs per function, ride ranges + wider
| function | how GDScript computes it on PC | SimMath | mismatches |
|---|---|---|---|
| sin cos exp log atan2 | x87 (64-bit mantissa, then double; sin / cos reduce with the x87's 66-bit pi) | double-double, rounded the x87 way; near-ties (~0.2 %) asked of the engine | 0 |
| pow | x87 (fyl2x / f2xm1) | same; the x87's own error is wider, so a 256-ulp band (~19 % of calls) is asked of the engine | 0 |
| atan asin acos tanh | the same CRT function as .NET's Math on Windows | `Platform` hook = .NET Math | 0 |
| tan | neither model (2-4 % off both) | `Platform` hook: the Godot adapter asks the engine | 0 |
`.NET`'s own Math would differ in 0.06-2.5 % of calls. On another platform (no engine hook) SimMath gives its own
double-double answers: deterministic, within the last bit of GDScript. `tools/sim_purity.ps1` = no engine reference
in `godot/sim/`.

## Steps
1. SimMath + math probe (no game change). DONE
2. V3f / Pcg32 / Noise + their probes. `tools/sim_rng_probe.gd`: **Pcg32 = Godot's RandomNumberGenerator bit for bit**
   (rand / randf / randfn, 5 seeds x 200k: randf's exponent comes from the first draw's LEADING zeros; randfn does
   cos and log in float, the rest in double). **Noise2S NOT matching yet** (written from memory: 15-50 % of points
   differ from Godot's FastNoiseLite): to be ported from FastNoiseLite's own source (MIT), then V3f.
3. IGround / IRideHost / RideParams + adapter; state mirror (C# <-> GDScript by member name); lockstep harness
   with an empty C# step (only reports the differences).
4. Port the stages in order: helpers, `_step_controls`, `_step_ground`, `_step_sprint`, `_step_loads`,
   `_step_drive`, `_step_steer`, `_step_move`, `_step_vertical`, `_step_hop`, `_step_lip`, `_step_wheels`, then the
   crash step and the rest. Each: lockstep clean on stress + suite + a ride before the next.
5. Default to C#, keep `BMX_PHYS=gd` for a while, measure speed, update HANDOFF.
Each step is its own commit on this branch.

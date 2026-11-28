# Porting rules: GDScript -> Runout.Sim (C#)

How Godot code moves into the engine plug (`unity/Assets/Runout/Sim`). The goal is a **line-for-line port** that can be
diffed against the Godot source by eye, behaves the same, and drops only test scaffolding.

## Files
- `bike_physics.gd` becomes `public sealed partial class BikePhysics` (namespace `Runout.Sim`), one file per group:
  `Assets/Runout/Sim/Bike/BikePhysics.<Group>.cs`. Start each file with `using System; using System.Collections.Generic;
  using static Runout.Sim.Gd;`.
- **Every field and constant already exists** in `BikePhysics.Fields.cs` (generated from every top-level `var` / `const`).
  Don't declare them again, don't edit that file or another group's file. A field missing or typed wrong: say so in your
  report (exact name + the type it needs); don't work round it.
- Your stubs are in `Stub.<Group>.cs`. Port each function there with **exactly that signature** (other groups call
  them), then delete `Stub.<Group>.cs` (and its `.meta` if present).
- Shared already (in `BikePhysics.cs`): `fwd()`, `_sample(f)`, `_wheel_ground(...)`, `smooth01`, `ang_diff`, `_or`,
  `slowness`, `pedal_rock`, `crank_rate`, `ratio_for`, `drive_ratio()`, `gear_k()`, `kb_back_cap`, `randf()`,
  `colliders_near(x, z)`, `_rear_shock()`, `_sprung_fork()`, `_g_y` / `_g_pitch` / `_g_hr` / `_g_hf` (fields).

## Types and names
- Keep every GDScript name (fields, locals, functions, constants). GDScript `float` = `double` (64-bit, same results);
  `int` = `int`; `bool` = `bool`; `Vector3` = `V3`; `Vector2` = `V2` (lower-case members: `.x`, `.dot()`, `.length()`,
  `.normalized()`, `.limit_length()`, `.lerp()`, `.angle()`); `String` = `string`.
- Godot globals have the same names in `Gd` (`clampf`, `minf`, `maxf`, `absf`, `signf`, `lerpf`, `smoothstep`,
  `move_toward`, `exp`, `sqrt`, `pow`, `atan2`, `wrapf`, `fposmod`, `is_nan`, `is_finite`, `deg_to_rad`, `roundi`,
  `angle_difference`, `lerp_angle`, `PI`, `TAU`, `INF`, `NAN`...). Untyped GDScript `max(a, b)` / `min` / `clamp` on floats
  = `maxf` / `minf` / `clampf`. `a % b` on floats = `fmod(a, b)`; on ints `%` (GDScript keeps the sign like C#).
- A local declared with `:=` from an int literal is an int in GDScript (`var n := 0` then `n += 0.5` truncates!): keep
  int where GDScript has int, double where it has float.
- `x if c else y` = `c ? x : y`; `and` / `or` / `not` = `&&` / `||` / `!`; `range(a, b)` = `for (int i = a; i < b; i++)`;
  `for e in ["a", "b"]` = `foreach (var e in new[] {"a", "b"})`.
- A function returning a GDScript array of two numbers returns `V2` (callers read `.x` / `.y`).

## Godot APIs -> plug
| GDScript | C# |
|---|---|
| `T.get("k", d)` | `T.get("k", d)` |
| `T.k` / `T["k"]` | `T["k"]` |
| `inp.throttle`, `inp.get("body_fwd", 0.0)`, `inp.hop` | `inp.throttle`, `inp.body_fwd`, `inp.hop` (`RideInput` fields, Godot key names) |
| `host.terrain` / `terrain.height(x, z)` etc. | `host.terrain.height(x, z)`, `deck_height`, `top_height`, `surface`, `jump_mask` |
| `terrain.colliders_near(x, z)` | `colliders_near(x, z)` (a SHARED list: `.ToArray()` it if you query again while looping) |
| collider dict `c.x`, `c.r`, `c.get("tape", false)`, `c.has("top")`, `c.top`, `c.get("base", d)`, `c.has("sink")`, `c.get("fence_style", "")`, `c.has("ceil")` | `c.x`, `c.r`, `c.tape`, `c.has_top`, `c.top`, `c.has_base ? c.@base : d`, `c.has_sink`, `c.fence_style`, `c.has_ceil` / `c.ceil` |
| `host.susp` (may be null) | `host.susp`: `has_f`, `has_r`, `front_max` (= `F["max"]`), `rear_max` (= `R["max"]`), `axis_tan`, `set_sag(f, r)`. Anything else it reads: port the maths, report what you needed |
| `host.flash(s)`, `msg_idle()`, `smash(c, vel, pos)`, `rock_chips(c)`, `burst(pos, n, surf, power)`, `start_crash(r)`, `on_style(pts, name)`, `on_trick(name)`, `on_takeoff()`, `on_landing(at, impact)`, `on_bad_landing(sev)`, `flow_up()`, `ride_fx(dt, f, va, in_water)`, `pedal_a0[0]` / `[1]` | same names on `IBikeHost` (`pedal_a0_left` / `pedal_a0_right`); `host.has_method(..)` checks go: just call |
| `"%d km/h" % [x]` | `$"{x} km/h"` / `string.Format` (same text) |
| `randf()` | `randf()`; `_grip_rng.randfn(0.0, 1.0)` |
| `FastNoiseLite.new()` + settings | `new Noise(seed) { frequency = .., fractal_octaves = .. }` |
| `Time.get_ticks_usec()`, `Engine.get_physics_frames()` | only used by probes: drop with the probe |

## What to drop
- Every `_OLD_*` switch: port only the branch taken when it is false (the current behaviour); delete the old branch.
- Test probes and prints: `*_PROBE`, `print(...)`, `Env.s(...)` / `Env.raw(...)` reads, `prof` timing, `CrashLog`, the
  energy probe (`_EPROBE`, `_e_*`), `bank_probe`, `_crash_log` prints. A test switch that changes behaviour (e.g.
  `BMX_HEAT`, `BMX_NO_SUS`): assume it is NOT set.
- Keep comments that explain the physics (shorten if you like); drop history notes about old versions.

## Done means
- `dotnet build unity/SimTests` shows **no errors in your files** (another group may be mid-port: ignore errors only in
  their files). Don't run Unity.
- Your report lists: functions ported, anything left out and why, field fixes you need, places you weren't sure the
  port matches GDScript semantics.

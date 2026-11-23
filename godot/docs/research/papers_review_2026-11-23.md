# New papers vs the game: what to improve (2026-11-23)

Read against the code by four reviews (bike dynamics, tyres, off-trail terrain, camera / animation / sky). Papers in
`C:\Users\Luka\Documents\GameResearch\` (index in its README). Nothing changed yet; this is the plan.

## Ranked (value for effort)

| # | What | Source | Where | Effort | Risk |
|---|---|---|---|---|---|
| 1 | **Brakes stop the same on every surface: the lever, not the tyre, is the limit.** Front lever max 7.5 x 0.75 = 5.6 m/s^2, the front tyre's cap is 7-15, so mu never matters (playground finding 8). Raise the levers (front ~12, rear ~8), let the S-key feel cap do the limiting; target trail ~0.75 g, grass 0.6, wet 0.5, sand 0.45 | MF D = mu Fz (Schmeitz sl. 7-9) | `_step_drive` brakes | S | more OTB on bare front lever; re-save suite |
| 2 | **Off-trail "flow ground"**: `base()` adds 0.5 m bumps every 8 m (crest radius a few m: skips from ~25 km/h, nothing to pump). Replace with 0.15-0.25 m rollers at 10-16 m, stretched across the fall line, density varied by a slow noise (build / rest); soften the `abs(noise)` ridge creases (sqrt(n^2+e)) | physics v^2 A k^2 < g; Smith 2009 rhythm | `terrain_field.gd` `base()` / `landform()` + C# | S | changes every world; `terrain_cs_cmp` EXACT |
| 3 | **Trees / rocks with rideable gaps**: one candidate per jittered 3.5-4 m hash cell (min spacing ~2.5-3 m) instead of 100 random tries; density by distance to a path (0 in the corridor, lined 3-8 m, forest beyond); clearings; rocks in gardens, out of corridors, added to `blocked` | WorldBrush §4 (rdf, distance-to-path histograms) | `terrain_chunk_builder.gd` `_trees` / `_rocks` | S-M | look of every world; no C# mirror |
| 4 | **Crash shake = trauma^2, rotation only, Perlin noise** (ours: two sines moving the camera position, which read as a glitch); trauma accumulates from hits, camera stops decaying the physics' `shake` (rumble reads it) | Eiserloh p. 9-16, 27 | `camera_rig.gd` `update_cam` | S | low |
| 5 | **Drawn bars**: (a) a short countersteer flick at turn-in / exit above ~15 km/h; (b) head angle + lean in the drawn steer (atan(tan d cos lean / cos lambda)) and flop into the dab; (c) a 7 Hz damped bar kick from rocks (no self-shimmy: DH geometry is stable). Drawing only | Limebeer & Sharp figs 16-19, Meijaard App. A | `game.gd` bar drawing | S | very low |
| 6 | **Tyre force peaks then falls off** (MF curve, peak ~0.12-0.15 rad, tail ~0.85) instead of sin(slip) rising to 90 deg; per-surface shape (trail: sharp peak; sand / loose: low wide plateau = long controllable drifts) | MF (Schmeitz sl. 7), brush (Romano §3) | `_grip_step` | M | spin-outs, whip interplay |
| 7 | **Relaxation is a distance**: tau = sigma / v (sigma ~0.25 m load / share, ~0.5 m rear `_nR_s`), clamped 0.015-0.12 s; ours are fixed times (too long at speed, too short slow) | Schmeitz sl. 22-25, Limebeer eq. 31 | `_load_s`, `_share_f`, `_nR_s` | S | jitter can come back: check slide=1, JITTER_ALL |
| 8 | **Load sensitivity everywhere** (one helper mu x (1 - 0.15 (N/N0 - 1))): turn limit has it, brake caps / drive cap / front use are linear | MF pD2 | 5 places in bike_physics | S | brake distances move |
| 9 | **Camber thrust**: leaned tyres make most of the turn force; slip need = (tan phi_CoM - Cc phi_bike) / Cs. Throwing the bike under the body then really buys grip (replaces the flat `flickGrip` / `weightInside`) | Limebeer eq. 31, table 2 | `_step_steer` | M | `counter` is partly for looks |
| 10 | **Locked tyre pulls along its own slide** (mu_d N split sin / cos of slip, not a constant 0.12 sideways): skids swing out then hold an angle | Romano eq. 28 | `_grip_step` | S-M | fishtail feel changes |
| 11 | **Camera frames the landing** in the air (predicted touch-down as a point of interest, rider stays the hard limit) | Eiserloh p. 29-32 | `camera_rig.gd` trail cam | M | low-medium |
| 12 | **Side paths follow the contours** (path field = tri(a L + noise): grade <= ~8 %) instead of running straight up / down 25 deg faces | IMBA half rule, NZ grades | `pathN` both fields | M | every world; mirror |
| 13 | Rider tricks: forward preload before a pull = bigger manual / hop; stoppie height trimmed by the front brake, needs speed | Tan 2014 §6 | `_balance_step` | S | low |
| 14 | Get-up clip + start frame by pose matching (hands, feet, pelvis); slope: one smoothed ground under the hips, IK hands / feet, toe lock; spring inertialization for every pose switch | Clavet p. 38-95 | `clip_get_up.gd`, `rider.gd` | S-M | low |
| 15 | Sun / fog / ambient colour from one analytic transmittance (Rayleigh + Mie + ozone) so sky, light and haze agree at golden hour | Hillaire §4 | `game.gd _apply_light` | S-M | tuned look |
| 16 | Low-speed balance: weak fall-over below ~3.5 m/s caught by an auto rider correction (visible bar corrections), optional TRACK STAND trick | Meijaard §6b, Kooijman SOM | `_step_steer` | M | twitchy; gate behind a slider |
| 17 | Big ones for later: Galin A* alternate lines off the main trail (as course arrays, so C# copies them); hydrology-lite gullies (natural banks / halfpipes); rhythm-grouped free-ride spots | Galin 2010, Génevaux 2013 | grow worker, both fields | L | |

Not worth it: motion matching (no riding mocap; procedural rider), a full Hillaire LUT sky (possible via SubViewport LUTs,
~0.2 ms, only if twilight becomes a priority), frame-flex wobble models.

Small things noticed: camera follows use `lerp(min(1, dt k))` (frame-rate dependent at k 12-18: use 1 - exp(-k dt));
speed FOV can reach +56 % (cap in degrees); rocks are not in the grass `blocked` mask (hidden hits).

## Already right (the papers back it)
Lean follows the steady-turn relation; self-steer blend ramps in near sqrt(gL); falling in past the grip; body lean steers
(no-hands mechanism); friction circles per tyre; locked = 80 % (mu_d); load-lag relaxation exists; turn limit has load
sensitivity; per-tyre surfaces; asked vs unasked slides; camera height smoothing, asymmetric easing, real-time crash
camera, rider always in view, fading small occluders, manual camera input wins; wheelie by pedalling + lean; scoop-then-pop hop.

## Suggested order
1 (brakes, a real bug) -> 2 + 3 (off-trail fun, the user's ask) -> 4 + 5 (cheap, visible) -> 6 + 7 + 8 (tyre feel, one
batch, measured with slide=1 / feel=1 / sim=1 / suite) -> the rest as wanted.

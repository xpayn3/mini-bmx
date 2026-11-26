# Realistic outdoor light + exposure (research, 2026-11-26)

User: "bulletproof the whole lighting system. Rider and levels at some times of day are totally overblown. Use realistic
values, realistic super nice light." Then: "lenses that mimic colour grading, like the artsy downhill films".
What was found and what the game now does (`scripts/world/sun_sky.gd`, `scripts/world/sky_meter.gd`, `Game._apply_light`).

## Why it was overblown (measured, `BMX_LIGHT_SWEEP`)
- The old code **raised** the sun at low elevation (energy 1.8 -> 2.2) and raised the exposure (0.7 -> 0.9), while the
  auto exposure's band slid to 40..95 ISO at golden hour: its factor was 3.4-8x (noon 2.3-4x). Sunlit faces at golden
  hour were ~2.5-3x brighter on screen than at noon. Reality is the reverse: a 10 deg sun is ~0.39 of the noon sun.
- At dusk (sun already set) the exposure kept climbing (+0.75 x twilight) and the scene showed as a flat pink day.
- On top: a rim light on the rider, softlight bloom (a post-tonemap grade), saturation 1.22 / contrast 1.12, ambient
  colours set by hand, fog / volumetric haze lit 2.6-3x the sun.

## Real values (clear sky)
Direct normal E = 127.5 klux x exp(-0.21 m), m = Kasten-Young airmass (NIST/IES 1984 NBSIR 84-2859). Sky on flat ground
(IES clear-sky fit) 0.8 + 15.5 sqrt(sin h) klux; 400-800 lux at sunrise, 3.4 at -6 deg, ~0.01 at -12; full moon 0.25 lux,
starlight + airglow 0.002 (Wikipedia Daylight / Unity HDRP physical light units / Frostbite PBR 2014).

| sun el | direct normal | sky (flat) | shade : sun on flat ground |
|---|---|---|---|
| 60 | ~100k | ~15k | 1 : 6.7 (~2.7 stops) |
| 30 | ~84k | ~12k | 1 : 4.5 |
| 15 | ~57k | ~8.7k | 1 : 2.7 |
| 10 | ~39k | ~7.3k | 1 : 1.9 |
| 5 | ~15k | ~5.4k | 1 : 1.2 |

Colour per channel: T = exp(-m tau), tau (zenith) R 0.153 / G 0.224 / B 0.355 (Rayleigh Hansen-Travis + aerosol AOD 0.1,
Angstrom 1.3 + ozone 300 DU). 10 deg -> (1, 0.68, 0.33), 5 deg -> (1, 0.49, 0.13). The colour and the dimming are one thing.

## Exposure
- Ghost of Tsushima (Patry, Advances 2021): exposure from **illuminance**, not from what the camera sees (bright / dark
  albedos fed back into a metered exposure). EV100 = log2(E / 2.5) for an incident meter.
- Partial adaptation: full over the day, a little darker toward sunset, night 3-5 stops under (Purkinje: colour fades).
- Godot's auto exposure averages max(R,G,B) linearly (the sky dominates); off in rides now.

## Practice
- Bloom = lens scatter: mix ~4 %, no threshold, wide levels (CoD AW / learnopengl physically based bloom). Softlight glow
  is applied after the tonemapper in Godot = a grade, not light.
- Grade neutral (sat / contrast 1), AgX contrast ~1.25, white 10-16. Looks belong in a LUT on top (the goggle lenses).
- No fake fill / rim; ambient = the sky (sky contribution 1); fog colour from the sky (aerial perspective 1); haze lit by
  what lights it (sun fog energy 1); one sky for the view, the ambient, the reflections.

## What the game does now
- `SunSky.state(el, L)`: sun lux + colour (per-channel transmittance), sky lux, moon + stars, a meter illuminance (flat
  ground + upright things at any heading), EV, adaptation (`adapt_stops`: 0 above EV 12, 0.2 stop / EV to sunset, 0.25 / EV
  under), and `scale` = engine units per lux with the adaptation folded in, so the **tonemap exposure is one constant**
  (`Game.RIDE_EXPOSURE` 1.2) and lamps / LEDs / screens keep their tuned brightness. Noon sun energy ~2.2, sky ~0.31.
- `SkyMeter`: the sky shader's brightness has no scale (photos, a painted sunset, a night sky), so a 2 x 1 px view in its
  own world measures a white card lit by the same sky material; `light_energy = energy = target / f`. Converges in 2
  reads; only runs on a light change (every 2 s with the day / night cycle). f measured: day photo ~0.44-0.49, low-sun
  photo ~0.22, painted sunset ~0.17, night ~0.05. Check: `-s res://tools/sky_meter_probe.gd` (card follows the sky 1:1).
- The painted sunset sky only below ~10 deg (it tinted all shade pink from 30 deg); its warm band hugs the horizon.
- Bike lamp beams x2.75 (`BikeLight.BEAM_GAIN`): the old night exposure was 3.3.
- Light tab defaults: rim 0, rider match 0 (the hacks the overblow needed), glare guard 0.5, saturation / contrast 1.
  Old saves' look sliders reset once (`LightSettings.VER` 2).

## Lenses = film grades (`scripts/rider/goggle_lens.gd`)
Action-sport edits: filmic S-curve with matte (lifted) blacks and a soft shoulder, hue-selective moves (greens -> olive /
emerald, skies -> teal, earth / skin kept warm so the rider pops), saturation falling off in deep shade + highlights,
split toning (cool shade / warm light). 33^3 LUT, ~80 ms to build, cached. Lenses: Clear (none), Red Line (the edit look),
Ember (golden orange-teal), Rosé (pastel), Smoke (bleach bypass), Glacier (cold teal), Dusk Yellow (faded 16 mm), Moss
(deep forest). `-s res://tools/lens_lut_probe.gd -- <dir> [shot.png]` grades a shot with each + checks GPU vs CPU.

## Measured (seed 4242, standing at the start, `BMX_LIGHT_SWEEP=1`)
Frame mean / clipped: before 7:00 0.50 with an orange blow-out round the sun, 20:00 0.35 lifted flat pink, 21:30 0.11
with 30 % crushed; after noon 0.55-0.57 (same as before), 18-19:30 0.45-0.54 with real shadows, 20:30 0.37, night 0.15-0.18
(moonlit, readable with the lamp), < 0.6 % clipped everywhere.

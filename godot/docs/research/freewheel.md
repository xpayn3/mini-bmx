# Freewheel (freehub) sound: how hubs work, how they sound, and how our synth compares

2026-11-28. A review of `scripts/game/FreewheelSynth.cs`, `ride_audio.gd` (`_hub_overrun`, the click rate / loudness),
`core/freewheel_sound.gd` (sliders + presets), plus measurements against the recording the synth was built from
(`Downloads/freesound_community-bicycle-forward-movement-31186.mp3`).

## 1. How the mechanisms are built

| Type | Parts | Clicks per wheel turn | Sound character |
|---|---|---|---|
| **Pawl** (Shimano, Hope, I9, most hubs) | 2-6 spring-loaded pawls on the freehub body, a toothed ring cut into the hub shell | teeth x pawl phases. Pawls all in phase = one click per tooth; pawls offset (e.g. 2 sets half a tooth apart) = teeth x 2 | each pawl rides up a tooth's ramp, falls off the tip and hits the next valley: a short metal tick. Shimano (3 pawls, ~16-18) quiet; Hope 4-pawl 44 loud; I9 6-pawl 120 a high buzz |
| **Star ratchet** (DT Swiss 18 / 36 / 54, DEG 90) | two face-toothed rings pressed together by a coil spring; coasting, the teeth slide up each other and the ring snaps back axially | = tooth count | the whole ring snaps at once: a heavier, more "zing" metallic buzz; DEG 90 a bit quieter + higher than 54 |
| **Ring drive** (Chris King 45 / 72) | helical splines push a toothed ring axially against a ring in the shell | = tooth count | famous loud "angry bees" buzz |
| **Sprag** (Onyx) | rollers / sprags wedge on a smooth race | 0 | silent |

What makes one louder (manufacturers / magazines): more teeth, a stronger spring (harder drop), sharp pawl tips
(rounded tips are quieter), little / thin grease, hard materials, the shell's thickness and air space, and the
**wheel as a soundboard**: stiff light (carbon) rims carry and amplify the hub's vibration (DT Swiss / hub patents
say the wheel "forms an optimum acoustic body"). Coasting speed changes it too.

## 2. Speed: what really changes (the physics)

- **Click rate** = wheel turns/s x clicks per turn. 24 clicks at 30 km/h (0.35 m rear radius) = 91 /s, a DT 54 at
  30 km/h ~ 200 /s. Teeth are CNC-cut, so the clicks are **almost perfectly evenly spaced** and the positions don't
  drift. Once the rate passes ~25-30 /s the ear hears it as a **pitch** (periodicity pitch = the click rate): the
  rising "zzzZZZ" buzz IS this pitch. The shell's own ring frequencies do not move with speed.
- **Per-click strength** depends on how far the pawl / ring falls, set by its spring, not by speed. It only starts
  to drop once the tooth passes faster than the pawl can fall (pawl ~1 mm travel, a few hundred m/s^2 from the
  spring: ~2 ms). Above ~300-500 clicks/s the pawl no longer reaches the valley bottom ("floats"): softer, smoother
  buzz. That depends on the CLICK RATE (so on teeth x speed), not on km/h: a 102-tooth hub floats at a third of the
  speed of a 24-tooth one.
- **Total loudness rises with speed**: same energy per click, more clicks a second = about +3 dB per doubling of
  speed until the pawls float.
- Once per wheel turn: the ring is never dead true and one tooth may be worn / tight, so a small loudness / timing
  pattern repeats every turn. Exactly every turn (it's the same teeth), not drifting.
- Between clicks: the pawl tip scraping up the ramp is a faint noise, and with several pawls not quite in phase each
  click is a 2-4-tick flam within ~0.1-0.5 ms (a "thicker" click).

## 3. Measured: our synth vs the recording

Renders: `tools/freewheel_render.gd` (Stock), analysed per band (share of energy, dB). Recording: its steady
coasting parts.

| | 2-8 kHz | 10-12.5 kHz | 12.5-20 kHz | centre | loudness 15 -> 80 km/h | periodicity at the click rate |
|---|---|---|---|---|---|---|
| recording | ~-1 dB (almost all of it) | -17 | < -50 | 5.3-6 kHz | rises ~12 dB as it speeds up | 0.40-0.44 (clear) |
| synth Stock | -2 .. -5 | -10 | **-3 .. -10** | 7-12 kHz | **flat (+1.4 dB)** | **0.10-0.23** |
| synth, uneven=0 jitter=0 | same | | | | | 0.67-0.84 |

(The mp3 may cut the very top itself, but not by 40-60 dB.)

## 4. Findings in the code (all fixed 2026-11-28, see section 5)

1. **Too much energy at the very top.** The snap is differentiated white noise up to Nyquist (+6 dB/octave) and the
   9.8 / 11.2 kHz modes are strong: half the synth's energy sits above 12.5 kHz where the real hub has almost none.
   This is the "fizz / distortion" heard at speed; `sp_soft` only patches it at speed. Fix: low-pass the snap at
   ~8-10 kHz always, lower the top two modes; then `sp_soft` can go to ~0.
2. **No regular tooth rhythm.** Every interval gets random `jitter` (6 %) and the 4-step `PAWL` pattern
   (0.62 / 1.05 / 1.12 / 1.21, +-38 %), and intervals are chained (`_ph -= _next`), so timing errors pile up like a
   random walk. Result: the buzz has no clear pitch (periodicity 0.1-0.2), and the strongest rhythm is every 4th
   click, a pitch two octaves under the real one. Fix: fire a click when the wheel angle passes each tooth's fixed
   place (`_rev x poe` crossing an integer) + a small fixed offset per tooth (the per-turn pattern) + a tiny random
   part; uneven pawls only as a 2-step A/B offset for phased hubs.
3. **Loudness doesn't follow speed.** `sp_soft` (snap -60 %) and `sp_ring` (ring -30 %) from 12 km/h cancel the extra
   clicks, so 15 -> 80 km/h is +1.4 dB (recording ~+12). With (1) fixed they can mostly go.
4. **Speed effects keyed to km/h, not to the click rate.** `sp_from` / `sp_full` (12 / 60 km/h) are the same for a
   24- and a 102-click hub. Physically the float / softening should follow clicks/s (tooth pass time vs pawl drop
   time).
5. **`sp_pitch` has no physical basis** (shell modes don't rise with speed; the rising pitch is the click rate,
   which (2) currently blurs). Set to 0 once (2) is in.
6. **Slow ticks are faded out.** `fw_amp` = smoothstep(0.1, 1.0 m/s) of the overrun: at 0.4 m/s (4-5 clicks/s, the
   classic "tick, tick" of slowing legs or a walked bike) the clicks are at ~25 %. A real click is as loud at walking
   pace. Fix: a short ramp (0.02-0.1 m/s) only to avoid a hiccup.
7. Minor: `Fire` retunes each 2-pole resonator while it still rings (detune +-3.5 %), a ~4-5 % amplitude step per
   click; a rotating (coupled-form) resonator retunes without it. Inaudible next to the rest.
8. Missing, optional: a little low "body" (the recording has ~10 dB more at 0.5-1 kHz; the rim / spokes as the
   soundboard, could follow the garage rim: carbon louder + more body), the pawl flam, the faint scrape between
   clicks, hub presets named by mechanism (pawl 3 in phase ~18, Hope-like 44, I9-like 120, star 36 / 54 / 90, ring
   drive 72, sprag = silent).

Checked and fine: `_hub_overrun` (rear wheel spin minus the cranks x the drive ratio, the same ratio the physics
uses to spin the wheel from the legs), locked rear / pedalling = silent, back-pedalling = more clicks, rolling
backwards = silent, knocks only while freewheeling, shake never touches the timing, replay fallback v / RWR.

Sources: [BikeRadar: loud freehubs](https://www.bikeradar.com/features/opinion/loud-freehubs-are-a-crime-against-good-manners),
[Gear Patrol: freehub sound explained](https://www.gearpatrol.com/outdoors/bicycle-free-hub-sound-explained/),
[bike-magazin: how noisy may a freewheel be](https://www.bike-magazin.de/en/components/bike-wheels/pros-and-cons-how-noisy-is-an-mtb-freewheel-allowed-to-be-two-types-two-opinions/),
[Hunt: freehub noise](https://help.huntbikewheels.com/support/solutions/articles/43000490666-freehub-noise),
[Cyclingnews: pawl vs ratchet](https://www.cyclingnews.com/features/road-bike-hubs/),
[Escape Collective: DT 240 DEG 90T](https://escapecollective.com/dt-swiss-240-deg-rear-hub-review-expanding-the-ratchet-to-90t/),
[Pinkbike: I9 Hydra 690](https://www.pinkbike.com/news/review-industry-nines-690-point-engagement-hydra-hubs.html),
[Singletracks: high engagement hubs](https://www.singletracks.com/mtb-gear/are-high-engagement-hubs-better-its-complicated/),
[Bikerumor: silent hubs](https://bikerumor.com/are-silent-hubs-better),
[US patent 7562755 (freewheel resonance damping)](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/7562755),
[US patent 10421316 (wheel as acoustic body)](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10421316).
No measured scientific paper on hub click spectra was found; the pawl drop time / float numbers are estimates.

## 5. After the fix (2026-11-28)

| | 2-8 kHz | 10-12.5 kHz | centre | loudness 15 -> 80 km/h | periodicity |
|---|---|---|---|---|---|
| recording | ~-1 dB | -17 | 5.3-6 kHz | ~+12 dB | 0.40-0.44 |
| new synth Stock | -0.9 | -16 | 5.4 kHz | +7.6 dB | 0.45-0.53 |

Left: 12.5-20 kHz is -17 dB vs < -50 in the mp3 (the mp3 itself cuts there, so the real figure is unknown);
the rim-as-soundboard isn't linked to the garage's rim yet (carbon = louder); the pawl scrape between clicks is
not modelled. `BMX_OLD_FWSYNTH=1` = the synth before.

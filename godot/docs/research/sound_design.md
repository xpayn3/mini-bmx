# Ride sound design: what we have, what racing games do, what we miss (2026-11-27)

## What the ride plays now (`scripts/game/ride_audio.gd`, ~400 lines)
All sound is flat 2D: there is no AudioStreamPlayer3D, no reverb, no ducking and no camera-dependent mix.

| Layer | How | Bus |
|---|---|---|
| Wind roar + whistle | synth (`RideBedSynth.cs`), louder / brighter with speed | Wind |
| Tyre roll | `GravelSynth.cs`, a tone per surface; skids = the same, louder | Wind |
| Water splash | synth in the bed | Wind |
| Freewheel clicks | `FreewheelSynth.cs`, fitted to a real hub | Bike |
| Chain rub | recording loop `chain_rub.ogg`, rate = crank speed | Bike |
| Gear shift | the user's recording (6 cuts) | Bike |
| Landing slam | `SlamSynth.cs` fitted to recorded hit B, sized by impact; bad-landing layer | Impacts |
| Crash thud / crunch, wood smash | small synth one-shots in `_mix_shots` | Wind (mixed into the bed) |
| Bone crunch | procedural (`Blood`) | Impacts |
| Garmin beeps, TV, paper, garage door | UI / world | UI / World |

**Recorded but never used**: `assets/audio/biking_raw/` has 16 landings, 8 rough-terrain clips, 8 tight-turn
clips and 5 slams from the user's MTB clip. Only slam B is used (as the SlamSynth fit).

**State the game has but sound ignores**: stamina / tired, the HUD heart rate (`hud.hr`, 68-185 bpm from
power, sprint, stamina), sprint, suspension travel / bottom-outs (`dg_botF/R`), brake heat / fade, front / rear
lock, rocks / roots under the tyre, berm load (`corner_g`), air time, near trees / rocks / fences, camera mode,
biome, time of day, tunnels / arches / canyons, rope bridge, race tape snap, crowd at gates.

## What racing / riding games do
- **Layers per wheel and per surface** (DiRT 4 recorded rolling surface, gravel kick-up, spring + damper
  compression, impacts, weather and ambience as separate categories). Stones hitting the frame and the
  suspension knocking are their own layers, driven by the physics.
- **Pass-bys / whooshes**: trackside objects (trees, posts, rocks, signs, gantries) play a short air whoosh
  when the vehicle passes close, panned and pitched by speed and distance (NFS, Forza, DiRT; also bikes in
  Descenders / Riders Republic). It is the main "speed" cue besides wind.
- **Camera-aware mix**: helmet / cockpit cam = close, bassy, the body (breath, chain, frame) loud; chase =
  wider, more tyres; trackside / replay = 3D with doppler (Codemasters: sound reacts to cockpit, chase,
  trackside).
- **The rider's body**: Lonely Mountains: Downhill is almost silent apart from the derailleur and heavy
  breathing; breathing is the effort cue. Riding / skate games add grunts on hops, landings and crashes.
- **Heartbeat**: used in slow-motion / near-death moments (NFS-style slow-mo, our WASTED is a natural fit),
  and on low health. Not as a constant layer.
- **Environment**: ambience beds per biome (forest birds, wind in pines, desert wind, water), reverb zones
  (tunnels, canyons, forest), the HDR / ducking idea: a big hit briefly lowers everything else.
- **Slow motion**: pitch down + low-pass + reverb tail (we only pitch down).

## What we miss, ranked (cost / gain)
1. **Close pass whoosh** (trees, rocks, posts, sign / fence posts, gantries, bridge trees): we already know the
   decorations per chunk; a cheap query of the nearest ones each frame, one short whoosh per object, louder
   with speed, closer = louder, panned to the side it passes. Needs a recording (several air whooshes).
2. **Breathing**: from effort (pedal / sprint power, stamina): calm nose breaths when coasting, mouth breaths
   pedalling, heavy gasping when tired / after a sprint, a held breath in the air, an exhale on landing.
   Rate follows `hud.hr`. Louder on the helmet cam. Needs recordings (breath loops at 3-4 effort levels +
   single inhales / exhales).
3. **Heartbeat**: only when it means something: life low, tired, and in the WASTED slow motion (under the
   pitched-down mix). Rate = `hud.hr`. Needs a heartbeat recording.
4. **Use the unused recordings**: rough_terrain clips for rock gardens / roots, tight_turns for berm scrub /
   skids, the 16 landings as variation for small landings.
5. **Suspension + frame**: fork / shock knock on bottom-out, chain slap over rough ground, stones kicked up
   under the frame. Recordings needed (chain slap, rattle).
6. **Rider grunts**: hop / pop effort, big landing, crash (an "oof"). Recordings needed.
7. **Ambience per biome + reverb zones** (forest, canyon, tunnel / arch, under a gantry).
8. **Camera-aware mix** (helmet cam vs chase) + ducking on big hits + low-pass in slow motion.
9. Brake squeal when hot / wet, tape snap, crowd at start / finish gates.

Rule for this game: new sounds are the user's recordings (memory "Recorded sounds only"). Every row above
that says "needs a recording" stays silent until one is given; the code that drives it can be written first.

## Done since (2026-11-27)
- Close-pass whoosh off trees / rocks / posts (recorded layer `whoosh`, silent until clips are given).
- **Gate whoosh, procedural** (`PassBySynth.cs`): how racing games do trackside pass-bys: synthesised from the
  pass's geometry (Doppler, distance, reflections off the structure overhead) rather than a recording, so it fits every
  speed and line. The user asked for it to be procedural and approved the sound.
- **Open-landscape ambience, procedural** (`VastAirSynth.cs`), louder the more open / high the view.

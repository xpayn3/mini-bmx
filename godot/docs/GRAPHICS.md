# Graphics & performance (Godot 4.7, Forward+)

What the PC version renders, what each quality preset turns on, and why some options were left out.
Measured on an RTX 3090 at 1600×900, vsync off.

## Quality presets

Settings › Graphics › Quality preset, or `--quality=0..3` on the command line. Changing any single
option switches the label to **Custom**.

| | Low | Medium | High (default) | Ultra |
|---|---|---|---|---|
| 3D resolution / upscaler | 75 % FSR 1 | 100 % | 100 % | 100 % |
| Anti-aliasing | FXAA | MSAA 2× | MSAA 4× | MSAA 4× + TAA |
| Sun shadows | 2 cascades, 2k atlas | 4 cascades | 4 blended cascades | 4 blended + soft contact-hardening (PCSS), 8k atlas |
| Ambient occlusion | – | SSAO | SSAO | SSAO |
| Global illumination | – | – | SSIL | SDFGI + SSIL |
| Volumetric fog + FogVolume dust clouds | – | – | ✓ | ✓ |
| Screen-space reflections | – | – | – | ✓ |
| View distance / mesh LOD | 0.7× / 2.0 | 1× / 1.0 | 1× / 1.0 | 1.4× / 0.75 |
| Texture filtering | 2× | 4× | 8× | 16× |
| Dust & dirt amount | 0.6× | 1× | 1× | 1.2× |
| Wind, cloud shadows, mud/wet, speed effects, bloom | ✓ | ✓ | ✓ | ✓ |

## Frame times

`--bench=<dir>`: fixed world (seed 7), scripted ride, 7 s per camera; average and 1 % low
frame time plus GPU time. "Before" is commit 8502aef with its default settings.
Two runs; the machine had other load during run 2, which shows in the "before" drone number.

| run 1 | drone | chase | diorama | GPU (drone) |
|---|---|---|---|---|
| before | 2.33 ms (1 % low 4.58) | 2.00 ms | 2.55 ms | 1.60 ms |
| Low | 1.84 ms (3.87) | 1.55 ms | 1.96 ms | 0.90 ms |
| Medium | 2.24 ms (3.46) | 2.04 ms | 2.46 ms | 1.70 ms |
| High | 2.88 ms (4.20) | 2.80 ms | 2.80 ms | 2.46 ms |
| Ultra | 4.16 ms (5.97) | 4.87 ms | 4.31 ms | 3.74 ms |

| run 2 | drone | chase | diorama | GPU (drone) |
|---|---|---|---|---|
| before | 4.32 ms (13.97) | 1.77 ms | 2.04 ms | 2.64 ms |
| Low | 1.60 ms (2.94) | 1.34 ms | 1.67 ms | 0.68 ms |
| Medium | 2.29 ms (3.74) | 2.05 ms | 2.42 ms | 1.69 ms |
| High | 2.88 ms (4.16) | 2.76 ms | 3.16 ms | 2.45 ms |
| Ultra | 4.19 ms (6.12) | 5.40 ms | 9.72 ms* | 3.77 ms |

\* Ultra/diorama in run 2 included SDFGI re-converging after a crash cut the camera; run 1 is the typical number.

Every preset stays far above 144 fps on this GPU. High costs about 0.6–0.9 ms more than the old default (SSIL,
volumetric fog, 4 shadow cascades), and Low is cheaper than the old default.

Screenshots: `docs/img/presets_drone.jpg`, `presets_chase.jpg`, `presets_diorama.jpg` (before / Low / High /
Ultra), `docs/img/effects.jpg` (riding, mud, wet, dust cloud, speed blur, photo mode). Riding diverges between
runs, so the frames aren't pixel-identical.

## Features

### Lighting & image
- **Sun shadows**: 4 PSSM cascades (splits 6 / 18 / 45 %), blended, fade-out, pancaking, distance sized to the
  camera zoom; 16-bit atlas. Low drops to 2 cascades; Ultra adds 0.6° angular size (contact-hardening soft shadows).
- **GI**: SSIL on High; SDFGI (4 cascades, occlusion, sky light) on Ultra, with the flat ambient lowered so
  valleys can go dark. SDFGI follows the camera, so it works with the streamed procedural world.
- **Volumetric fog**: a thin haze with forward scattering (`light_volumetric_fog_energy` 1.4) so the sun shines
  through it, temporal reprojection on. The existing depth fog still does the distance fade.
- **SSAO** with a little light-affect for contact shadow under the bike; **SSR** on Ultra; **glow** in soft-light
  mode over levels 1–4.
- **Colour grade + vignette** (the web version's split tone) stays in the post pass it already had, now shared
  with the speed blur (one screen copy for both).
- **Depth of field**: the tilt-shift miniature look in play, and **photo mode (O)**: time stops, HUD hides, the
  camera keeps orbiting (drag, wheel), DoF focuses on the rider with stronger bokeh (circle, high quality). F12 saves.

### Effects ported from the three.js prototype
- **Wind** (`shaders/atmos.gdshaderinc`, `scripts/world/atmos.gd`): gust fronts roll downwind across the land
  as waves; grass, flowers and ferns bend in world space, tree crowns, bushes and weeds sway by height. The bike
  pushes grass aside as it rides through. Everything is driven by global shader uniforms (`atm_wind`, `atm_pusher`).
- **Cloud shadows**: drifting ~30 m clouds that dim only the sun. The sun light follows the shade at the rider,
  using the same integer-hash noise in GDScript and GLSL, so bike and rider go into shade with the ground. World
  shaders apply shade(here) / shade(rider) in their `light()`; water glints fade under cloud.
- **Mud & wet** (`scripts/bike/grime.gd`, `shaders/grime_*.gdshader`): mud builds up on dirt and sand (faster
  when skidding, carving, landing, or riding wet), starts low and creeps upward, takes the colour of the ground,
  and washes off in water. Afterwards the bike and rider are darker and glossy with running beads and dripping
  water for a few seconds. Done as `next_pass` overlays so it works on imported, car-paint and rider materials,
  and only attached while there's mud or water.
- **Speed feel**: FOV grows with speed (up to +9° on the drone camera, scaled per camera) and the screen edges
  streak radially; the centre stays sharp.
- **Dust**: the rear-wheel trail is a `GPUParticles3D` emitter fed every physics step (rate, throw direction,
  colour, opacity), drawn as sun-lit soft billboards: a spherical normal, wrap lighting, forward scattering,
  proximity fade against the ground and a near-camera fade. Big skids, landings and crashes add `FogVolume` dust
  clouds inside the volumetric fog. The CPU burst puffs got the same soft fade.

### Performance
- Decorations were already MultiMesh-instanced with visibility ranges and the ground already had distance LOD; that's unchanged.
- **Occlusion culling**: every chunk gets a coarse `ArrayOccluder3D` (4 m grid sunk 0.6 m under the ground).
  It's an option and off by default: with the high cameras this game uses, it removed 7–15 % of triangles but
  didn't lower frame time and made 1 % lows worse (the raster costs CPU). It may help low cameras on slower GPUs.
- **Shader hitches**: pipeline cache + shader cache on (Godot 4.7 also has ubershaders), and the new effect
  pipelines (mud, wet, drips, dust, fog puffs, chunks) are drawn once behind the opening fade.
- **Physics**: already a fixed 120 Hz tick with the bike drawn between the last two states; unchanged.
- **FPS counter** (with ms) in the top left, Settings › Interface › Show FPS.

## Left out, and why
- **VoxelGI / LightmapGI**: both need a bake; the world is procedural and streams in, so SDFGI is the fit.
- **Light projector for cloud shadows**: Godot doesn't support projector textures on DirectionalLight3D, so cloud
  shadows go through the shared shader uniform instead.
- **`GPUParticles3D.emit_particle()` per puff**: in 4.7 manually emitted particles didn't draw in testing, so the
  dust trail is a continuously emitting particle node whose rate and direction are driven every step.
- **Separate HLOD meshes**: the far ground already uses coarse LOD grids and decorations fade out by range, so
  merged far-chunk proxies wouldn't save much.
- **LUT colour grading**: the existing split tone already runs in the post pass the speed blur needs, so there was no reason to change it.

## Gotchas found
- `FogMaterial.height_falloff` is in world height: the trails are ~100 m up, so any falloff makes a puff
  invisible. It's 0.
- A `FogVolume` set `visible = false` before entering the tree never shows again when made visible. The puffs stay
  visible and idle at density 0.
- Godot shader `#define` doesn't continue across lines, and the `light()` built-ins can't be used inside helper
  functions; `atmos_diffuse()` takes them as arguments.

## Testing
- `--bench=<dir> [--quality=N] [--set=key=value]`: frame times + screenshots (above).
- `--showcase=<dir>`: forces each effect on and saves a screenshot (mud, wet, dust cloud, speed blur, photo mode).
- `--autotest=N`: the existing unattended smoke test.

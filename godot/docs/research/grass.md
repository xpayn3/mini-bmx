# Grass rendering: research notes (2026-11-24)

What games and papers do for big grass fields that look good and stay cheap, and what our grass carpet
(`scripts/world/grass_field.gd`, `shaders/grass_field.gdshader`) took from it. Sources were read on the web (secondary
write-ups where the original slides / PDFs weren't reachable: marked).

## Sources

- **Ghost of Tsushima**, E. Wohllaib, "Procedural Grass in Ghost of Tsushima", GDC 2021 (gdcvault.com/play/1027214;
  video only). Read through write-ups: tigerabrodi.blog ("what we can learn from grass in Ghost of Tsushima"),
  cainrademan.github.io/Unity-Grass (a Unity reimplementation), gist.ly summary, publish.obsidian.md/xybre notes.
  Blades = cubic Bezier (height, width, tilt, bend), Voronoi clumps (shared height / facing / colour / bend, pull to
  the clump middle), normals tilted out across the width (looks rounded), blended to a shared normal with distance
  (no shimmer), edge-on blades pushed sideways in view space, 2D noise wind on the tip / middle control points,
  LOD 15 -> 7 verts with a morph, far tiles half the density at twice the width, root AO fading with distance,
  distant terrain coloured like the grass tops, no shadow casting (height-field / screen-space shadows instead).
  Quoted budget ~83k blades for ~2.5 ms (unverified).
- **Jahrmann & Wimmer**, "Responsive Real-Time Grass Rendering for General 3D Scenes" (I3D 2017) and the 2013
  tessellation paper: quadratic Bezier blade (root / guide / tip), tip forces gravity + recovery + wind, culling by
  orientation (|view . blade| > 0.9), frustum (3 points) and distance buckets. A student reimplementation
  (github.com/JChunX/Vulkan-Grass-Rendering) measured frustum culling as the biggest win (2^18 blades 100 -> 250 fps
  with all culling).
- **AMD GPUOpen, mesh-shader procedural grass**: blade count by distance with the width scaled up to keep coverage,
  the last blade faded by its fraction (no pop), normals blended towards up, fake self-shadow pow(h, 1.5).
- **2Retr0 GodotGrass** (a Godot 4 grass shader, raw source read): view-space thickening, normal rotated across UV.x,
  normal faded to up with distance, wrapped diffuse pow(4, N.L) / 4, SSS from -V.L, AO = albedo x mix(0.1, 1, h^2).
- **Horizon Zero Dawn** (Guerrilla, GDC 2018 vegetation): shadow maps only in the near cascades, a height-field shadow
  far, fixed shadow LOD per cascade (no popping). Outerra blog (2012): canopy height mask drives blades + far terrain
  colour, density stepped down at 8 / 16 m. Production foliage slides: opaque / alpha-test, never blended, no depth
  writes from the pixel shader, vegetation ~10-20 % of the triangle budget.
- Breath of the Wild: nothing published by Nintendo (only fan recreations).

## What we did (2026-11-24)

Already in ours before: lattice blades with hashed size / lean, colour from the ground (roots melt into the floor),
patches, tip colour, gust bands, backlit tips, trampling, no blending, no shadow casting, per-tile frustum culling,
3-segment near blades / one triangle far, widened when seen from above.

Added (all scaled by the shader uniform `look_v2`; `BMX_GRASS_OLD=1` sets it to 0 = the old look):
1. **Clumps** (GoT): the nearest of the 3 x 3 jittered clump centres (`CLUMP` 1.15 m); per clump a height 0.75-1.25,
   tallest in its middle, its own shade, and near blades lean out of its middle: the field reads as tufts.
2. **Rounded normals** (GoT / 2Retr0): the normal tilts towards each edge across the width (`v_side * v_u`), near
   blades only, faded out from 6 m to the near ring's edge (no far shimmer).
3. **Self-shadow down in the grass** (AMD / 2Retr0): albedo x mix(0.58, 1, t^1.5), faded out from 8 m.
4. **Edge-on blades turn to the camera** (near ring): up to 60 % of the way, by pow(edge-on, 4).
5. **Wrapped diffuse**: (N.L + 0.35) / 1.35 + a smaller back term, so thin blades have no flat dark backs.

Cost: GPU 0.59 -> 0.64 ms for the whole grass (render probe, seed 4242 start, Ultra, 1600 x 900, RTX 3090). The CPU
side was cut the same day (tile placement in C#, `GrassPlaceCs`): 0.25 -> 0.02 ms of render CPU, ~0.6 -> < 0.1 ms of
script time.

Not done (candidates): wind on the Bezier control points with per-blade stiffness (ours bends via `wind_bend`),
gloss stretched along the blade, density-by-distance with width compensation inside the near ring, a far height-field
shadow for grass, a vertex LOD morph between the rings.

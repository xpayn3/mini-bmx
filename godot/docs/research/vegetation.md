# Vegetation placement rules and type checklist (2026-11-26)

Gathered for "trees and bushes look random, follow nature's rules / what world builders do".
**Caveat:** written from recall (no live web check). Numbers marked (A) = approximate from the sources, (T) = tuning
suggestions. Open the URLs before citing them anywhere public.

## Placement rules, most visual impact first

1. **Density = product of per-species suitability masks**, not one biome density: slope curve x altitude curve x moisture
   x biome weight x (1 - trail mask), drawn against probabilistically. Horizon Zero Dawn (GDC 2017 "GPU-based procedural
   placement"), Unreal PCG, Houdini Heightfield Scatter, Hammes 2001. Trees full to ~25 deg, gone by 35-40 deg; shrubs to
   ~35 deg; bare rock past ~40 deg (A/T).
2. **Per-species Poisson-disk spacing from crown radius, big plants first (competition)**. Unreal Procedural Foliage
   (collision radius, shade radius / tolerance, generations). Trunks 3-6 m apart in mature forest, 2.5-3 m dense pine,
   6-15 m alpine, 15-40 m savanna (A). Understory rejected inside a bigger plant's radius; grass x (1 - canopy).
3. **Groves and seed dispersal**: a 40-120 m grove noise with soft threshold (stands 30-80 m, clearings); 2-8 saplings
   3-10 m round a mother tree, smaller further out. Cordonnier et al. 2017, Gain et al. 2017 (EcoBrush).
4. **Forest edge ecotone**: density falls over 10-25 m, edge trees smaller / younger (0.6-0.9), a 2-6 m shrub belt, saplings
   5-15 m into the meadow at 5-15 % density (T). Far Cry 5 (GDC 2018), Ghost of Tsushima (GDC 2021).
5. **Treeline / krummholz**: trees shrink to 0.3-0.5x and lean near it, above it only dwarf shrubs, sedges, cushion
   plants, rock. Here: driven by the cold biome weight (the biome must not read the real height).
6. **Moisture: hollows wet, ridges dry** (curvature: height vs the mean 8-20 m round). Hollows: broadleaf, alder, ferns,
   dense undergrowth. Ridges: sparse pine, grass, wind-shaped trees. Gaea / World Creator flow and wetness maps.
7. **Riparian band**: reeds / sedges in the shallows (patches of 3-10), willow / alder + shrubs to ~8 m from the shore, moist
   meadow fading out by 20-30 m (T).
8. **Aspect**: north-facing (shaded) slopes wetter: denser conifers; south-facing drier: grass, scrub, open woodland.
   Bias suitability +-0.15-0.3 by slope direction vs the sun.
9. **Rock / scree / cliffs**: past ~35-40 deg no trees; 3-10 m of bare scree at a cliff foot; on 30-45 deg slopes a 1-3 %
   chance of a lone gnarled tree in a crack. Rocks in groups (one big, 3-6 medium, small ones).
10. **Trail**: trunk clearance (exists), then bushes / tall grass at the dirt edge, an irregular first tree row, sight
    lines kept on the outside of bends (3-5 m, T), overhanging branches only >= 2.5 m up.
11. **Understory, deadfall, snags**: ferns + saplings in shade and hollows; logs 1-3 % of forest trees lying downslope
    +-30 deg with a stump near; snags 2-5 % (more on ash).
12. **Wind**: on ridges and convex shoulders trees x0.7-0.85, leaning 5-12 deg downwind, density -20-30 %.

## Types per biome (shares of instances, A/T)

| Biome | Trees | Young / shrubs | Ground cover | Dead / rock |
|---|---|---|---|---|
| Pine / spruce forest | pine/spruce ~70 %, birch/aspen on edges + wet hollows; 15 % saplings, 25 % young | juniper, berry shrubs | ferns in hollows, moss, needle litter, thin grass | snags 3 %, logs 2 %, stumps, mossy rocks |
| Alpine | sparse krummholz below the line, none above | dwarf shrubs (heather, dwarf willow) | cushion plants, sedge tussocks, small flowers | scree, lichen boulders |
| Wetland | alder, willow, birch, sparse, leaning | willow shrubs | reeds, cattails, sedges (~50 %), marsh flowers | logs in water, bleached snags |
| Savanna | flat-crowned trees 1 per 15-40 m, clumps of 2-4 | thorn scrub round rocks | tall golden grass clumps | dead trees 3-5 %, rocks |
| Volcanic ash | burnt snags, odd survivor pine | pioneer shrubs / tufts | moss, lichen, tiny grass at edges | charred stumps, black boulders |
| Dry / desert scrub | very few | sage / creosote-like scrub 3-8 m apart | cacti, succulents, dry tufts | dead branches, bleached rocks |
| Temperate meadow / hills | single trees + clumps of 3-7, tree lines along streams | hazel / hawthorn clumps | grass, wildflower patches (3-8 m) | stumps, field-stone piles |

## Sources (unverified links)
- Cordonnier et al. 2017, Authoring landscapes by combining ecosystem and terrain erosion simulation: https://hal.science/hal-01518967
- Gain et al. 2017, EcoBrush: https://dl.acm.org/doi/10.1145/3072959.3073703
- Hammes 2001, Modeling of ecosystems as a data source for real-time terrain rendering: https://link.springer.com/chapter/10.1007/3-540-45651-1_29
- GDC Vault: GPU-Based Procedural Placement in Horizon Zero Dawn (2017); Procedural World Generation of Far Cry 5 (2018); Ghost of Tsushima (2021): https://gdcvault.com
- Unreal Procedural Foliage tool: https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-foliage-tool-in-unreal-engine

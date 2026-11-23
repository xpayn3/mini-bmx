# Ride feel: why it doesn't flow, what research says, what to change (2026-11-22)

User: "our driving is not fun and fluid like MX vs ATV". Two research passes (game feel / arcade handling talks;
terrain, trail design and pumping physics) plus a measurement of where our ride's energy actually goes.

## 1. Measured: where the speed goes (new probe `BMX_ENERGY_PROBE=1`, `bike_physics.gd`)

An energy account per kg every 5 s: the drive stage's own terms (pedal, brakes, pump, rolling drag, air drag, the
grade's pull, manual boost), the change across every other ride stage (steer = slides / scrub, move = hits, vertical =
springs / landings, lip = take-offs), and `height` = g x the height change (the grade's energy changing form).
Seed 4242, the trail:

| ride | km/h avg / max | braking | in air | where the energy went (J/kg) |
|---|---|---|---|---|
| demo AI, 85 s, 991 m | 42 / 60 | **18 %** | 6 % | **brakes -692**, height -660, air drag -378, rolling -80, steer -36, landings -35; grade +599, **pedal +660** |
| follow test rider, 50 s, 622 m | 45 / 70 | 0 % | 7 % | height -416, air drag -321, landings -63, rolling -42; grade +367, pedal +493 |

What it says:
- **The brakes eat as much as all the pedalling.** The demo AI brakes for bends it plans at 0.7 g of grip. The
  descents carry 50-60 km/h; a bend at that speed needs ~40 m radius, and the trail is full of road bends, esses and
  5-6.5 m hairpins (allow ~20 km/h). So it is: gain speed downhill, throw it away at the next bend, pedal back up. That
  is the opposite of flow, and the player meets the same trail.
- Air drag (-0.5 N/kg at 45 km/h, an upright DH rider's real CdA) and rolling drag (Crr ~0.007, hardpack) are
  realistic. Landings cost little (-35 / -63). Slides cost little.
- 9-12 % of the height lost never shows up as grade speed (height -660 vs grade +599). Most likely the drops: height
  lost falling off lips / ledges becomes falling speed that the landing absorbs. Not split out yet (open).

## 2. What the research says

Terrain and riding (sources read):
- **Pumping** (Luginbuhl et al., "Identification of Optimal Movement Patterns for Energy Pumping", Sports 2023, open
  access): a 75 kg rider on 6 m / 0.2 m sine rollers; the optimum is a short hard push (bang-bang, up to 2 g) timed just
  before the crest, unweighted / flying over it, landing on the down-slope; ~0.38 s per roller (wavelength ~0.4 x v).
  Needs >= 1.2-1.3 g of peak push or pumping gains nothing; speed gain grows with roller height up to ~0.5 m, then the
  rider can't absorb it and loses speed. Timing gets harder the faster you go.
- **Berms are pump sources** (Golembiewski et al., "The Dynamics of a Bicycle on a Pump Track", arXiv 2311.07251,
  validated on a real track; full text now in the library): the rider's upper body moving up / down against the bike
  through a steep banked corner drives it forward with no pedalling - extended entering the curve, shortening through it
  (their Fig. 8; the real test rider did the same, Fig. 5); the pumped lap was "significantly" faster. (A secondary
  write-up quotes ~18 %; that number is not in the paper.)
- **Trail flow** (IMBA "Trail Flow"; adaptive-MTB standard): long sightlines, sweeping turns and smooth tread make speed;
  tight turns and rough tread take it. Roller spacing / height set by the speed riders arrive at; berms 6-7.5 m radius
  on slow trails; in-sloped turns before tight sections so riders slow gradually, not by a brake stab.
- **Bank angle** (physics): no side grip needed when tan(bank) = v^2 / (g r). At 10 m/s on an 8 m radius that is ~52 deg.
  Flow-trail berms are 25-45 deg; our trail's banks measured 4-10 deg (HANDOFF).
- **Rhythm-based generation** (Smith et al., "Rhythm-Based Level Generation for 2D Platformers", FDG 2009, + Smith's
  Launchpad thesis): first generate a rhythm (the beats of player actions), then geometry that fits it. For us: features
  spaced as beat period x the speed the rider arrives at.

Game feel and handling (sources read; GDC Vault talks themselves were behind the paywall):
- **MX vs ATV** (Rainbow): "the player controls the rider, the rider controls the bike" (two sticks, our model too); the
  Legends 1.17 patch, after the game felt "wooden": higher side-slip limit, more traction landing slightly sideways,
  higher wheelie thresholds, looser rider - aimed at fewer wrecks "for seemingly no reason". The feel people remember
  is direct response + forgiveness.
- **Trials** (RedLynx): simple controls on a deep physics model, no scripted actions, failure you can read.
- **Descenders** (RageSquid): physics took months; procedural tracks code a level designer's steps from three dials
  (steepness, curves, stunts); reviewers' complaint was features the generated terrain made impossible.
- **Skate** (EA, Blackwood): stick gestures read at 120 Hz and graded continuously (speed, accuracy 1-5 each) instead of
  pass / fail; tuned for a year in a text prototype before graphics.
- **Mario Kart drift**: committing to a clean carve charges a small speed reward paid on the exit - speed as the reward
  currency. (Real riders do gain speed pumping berms, so a plausible version exists: see 2nd point above.)

## 3. Suggested changes, ranked (measure each with the energy probe + the playground suite)

| # | Change | Why | Measure |
|---|---|---|---|
| 1 | **Corners fit the speed**: the generator sizes each bend from the speed a rider arrives at (radius from v^2 / (a tan-bank)), banks fast bends as berms (25-45 deg, linear), puts tight hairpins after a slowing section (climb, in-slope), not at the bottom of a fast descent | the brakes eat as much as all the pedalling | demo + player rides: braking time 18 % -> under ~8 %, brake energy < 1/3 of now, avg speed up |
| 2 | **Berms pay back**: extended entering a banked turn, compressing through it (stick or hop) gives forward speed, like the rollers | Golembiewski: pumped laps significantly faster, model + real rider | 4-berm section exit vs entry speed, pumped vs not |
| 3 | **Rollers pump with the leg model**: push just before the crest (short, hard), unweight over it; rollers sized ~0.4 x v wavelength, <= 0.5 m high | Luginbuhl; HANDOFF: rollers still use the old `pumpHold` push | energy per roller pumped / hands off / mistimed; hands off must not gain |
| 4 | **Rhythm layer in the generator**: build (3-5 rollers / small features) -> release (table / double) -> rest (sweeper, berm); the next lip one roll-out after a clean landing, never on the knuckle | Smith; Descenders | speed at each lip vs the previous over 20 features, ridden clean: no net loss |
| 5 | **Forgiveness, MX vs ATV-style**: more traction landing a bit sideways, sideways impact costs speed before it crashes, every crash shows its cause | Legends patch; Trials | crashes per 10 km for the demo rider, all with a cause on screen |
| 6 | **Graded pop**: pop power from how quick / well-timed the stick snap is, continuous, not one threshold | Skate | pop height spread for lazy vs crisp snaps |
| 7 | Find the 9-12 % of descent energy that never becomes speed (drops? the grade read from the wheels?) | free speed if it's a leak | `height` vs `grade` after splitting falls / landings |
| 8 | Speed sense (FOV, wind sound, rumble) only after 1-4 | the feel is in the trail and physics first | - |

**Change 1 done (2026-11-22)**, see HANDOFF "Ride the berm". The finding changed it: the berms were mostly big enough
(20 deg average, ground matching) but the racing line ran on the flat inside of them. Riding the berm + speed-sized
banks: demo AI +9 % average speed, a sixth to a quarter less braking, on two worlds.

**Changes 2-4 done (2026-11-23)**, see HANDOFF "Berms pay back, rollers pump". 2: berm pump, +75-100 J/kg a ride.
3: the measurement found the hop button could never pump a roller (the front leaves the ground over the crest, the
pump needed both wheels down): fixed; the trail's rollers kept their size (at trail speed the research size is jumped).
Later the same day 3 went the whole way: the pump is the legs' stroke against the ground's curve (bend over a crest,
straighten into the dip; nothing on a straight slope, nothing hands off), the old downhill push removed.
4: jump sections in build / release / rest beats, the next lip one roll-out after the landing. 5 and 6 were already in
(the landings and jumps work); 7 needed nothing. 8 (speed sense) is left until the user has ridden 1-4.

Not for us: Rocket League's grip / downforce numbers (unverified, against our momentum rule), arcade boosts far beyond
plausibility, any MX vs ATV internals (nothing public found).

## Sources
Read: Luginbuhl et al. 2023 (pmc.ncbi.nlm.nih.gov/articles/PMC9964864); Golembiewski et al. 2023 abstract
(arxiv.org/abs/2311.07251) + a secondary explainer; IMBA Canada "Trail Flow"; Skate interviews (Game Developer, Blackwood);
MX vs ATV (Xbox Wire, Traxion on the Legends 1.17 patch); Trials HD interview (MCV); Descenders interview (Red Bull);
Mario Kart drift (Kotaku); Rocket League speed doc (community). Snippets only: Smith et al. FDG 2009; adaptive MTB
standard (Vermont / KASA); Rocket League GDC 2018; Swink "Game Feel"; Lonely Mountains press kit.

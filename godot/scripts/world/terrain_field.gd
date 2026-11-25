class_name TerrainField
extends RefCounted
## The pure height / surface / colour functions of terrain.js (no scene, no rock domes).
## One instance per thread: the immutable seed data (noise table, course, route features) is shared
## between forks, the little result caches (course query, jump cells, memos) are per instance.

const WATER := -2.2
const JC := 34.0
const HILL_TOP := 105.0
const HILL_LEN := 1400.0
## the trail never ends: it runs on through the hills after the mountain. The first COURSE_LEN m are laid
## out at setup; Terrain grows it (grow_course) on a worker thread well before the rider gets near the end.
const COURSE_LEN := 4000.0
const MTN_W := 150.0
const QR := 19.0
const CELL := 16.0
const CSTEP := 2.0

# noise scales (same doubles as the JS 1 / k)
const I42 := 1.0 / 42.0
const I23 := 1.0 / 23.0
const I55 := 1.0 / 55.0
const I260 := 1.0 / 260.0
const I90 := 1.0 / 90.0
const I240 := 1.0 / 240.0
const I150 := 1.0 / 150.0
const I700 := 1.0 / 700.0

## Land shaping v3 (2026-11-25, docs/research/terrain_generation.md items 2-6; mirrored in TerrainFieldCs.landform,
## terrain_cs_cmp must stay EXACT). BMX_OLD_LAND=1 = the old land (tests). Measure: -s res://tools/land_probe.gd.
##  - macro controls: two very large noises (LAND_CR 2.6 km, LAND_CM 1.8 km) go through splines (`spl`) to a detail
##    amplitude (flat plains .. rough country) and a macro strength (low .. big hills / ridges): regions you can tell apart.
##  - domain warp: the 28 / 90 / 240 m octaves and the ridge term are sampled at a position pushed by a 170 m noise
##    (up to ~LAND_WARP m, less on the mountain).
##  - gradient-damped detail (Quilez): the 240 m octave and the ridge term come with analytic gradients (noise_d); the
##    90 m octave is damped by the big-scale slope, 1 / (1 + (s / LAND_DETAIL_S)^2), the 28 m octave by the slope of
##    big + 90 m (LAND_FINE_S): bumpy flats, smooth faces. The big relief is also softened on steep ground (LAND_TALUS).
##  - valleys: a 420 m control noise marks broad valleys; detail fades (LAND_VALLEY_FLAT), big relief flattens (LAND_VALLEY_MACRO).
##  - strata: in the rugged biome on sloping ground away from the trail the height is pulled towards stepped bands
##    (LAND_STRATA_STEP m, amount LAND_STRATA): caprock ledges and rock bands.
const LAND_WARP := 38.0
const LAND_TALUS := 0.30
const LAND_DETAIL_S := 0.30
const LAND_FINE_S := 0.55
const LAND_VALLEY_FLAT := 0.65
const LAND_VALLEY_MACRO := 0.40
const LAND_VI := 1.0 / 420.0
const LAND_CR := 1.0 / 2600.0
const LAND_CM := 1.0 / 1800.0
const LAND_STRATA_STEP := 3.2
const LAND_STRATA := 0.7
## biome climate noises (periods in m): altitude proxy, moisture, forest, ash patches (they never read the real height: the
## land is shaped by the biome, a height-driven biome would be circular)
const BIO_A := 1.0 / 1300.0
const BIO_M := 1.0 / 1700.0
const BIO_F := 1.0 / 900.0
const BIO_S := 1.0 / 2200.0
static var OLD_LAND := OS.get_environment("BMX_OLD_LAND") != ""
const I28 := 1.0 / 28.0
const I8 := 1.0 / 8.0
const I1_5 := 1.0 / 1.5
const I3_4 := 1.0 / 3.4
const I160 := 1.0 / 160.0
const I380 := 1.0 / 380.0
const I300 := 1.0 / 300.0
const I7 := 1.0 / 7.0
const I95 := 1.0 / 95.0
const I40 := 1.0 / 40.0
const I115 := 1.0 / 115.0
const I45 := 1.0 / 45.0
const I60 := 1.0 / 60.0
const I26 := 1.0 / 26.0
const I170 := 1.0 / 170.0
const I6 := 1.0 / 6.0
const I38 := 1.0 / 38.0
const I5 := 1.0 / 5.0
const I2_3 := 1.0 / 2.3
const I9 := 1.0 / 9.0
const I0_9 := 1.0 / 0.9
const I2 := 1.0 / 2.0
const I1_3 := 1.0 / 1.3

# Ken Perlin's reference permutation (three.js ImprovedNoise)
const PERM := [151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142,
	8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
	57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77,
	146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25,
	63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109,
	198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227,
	47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167,
	43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34,
	242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199,
	106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243,
	141, 128, 195, 78, 66, 215, 61, 156, 180]


class Feat:
	extends RefCounted
	var x: float
	var z: float
	var dx: float
	var dz: float
	var len: float
	var prof: TrailFeatures.Profile
	var b0: float
	var b1: float
	var type: String
	var wood: TrailFeatures.Wood
	var dig: TrailFeatures.Profile
	var half: float
	var s: float = 0.0
	var air := PackedFloat64Array()   # TrailFeatures.AIR of its type: the stretches riders fly over
	var size := 3   # a route jump's speed size (TrailJumpSizes, 0 .. 3 = the big one), picked from TrailCourse.VA
	var v = null    # the speed it is designed for, as the demo AI plans it (null = DemoPilot.FEAT_V by type)
	var vmin = null
	var canyon := false   # rope bridge: a canyon cut across the land (canyon_rims), not a dig along the trail
	## how far before / after the feature the trail is eased onto its plane (b0 .. b1). A rope bridge's plane can sit
	## a metre or two off the trail: eased in over 5 m that was a kicker right before the rim (launched into the deck)
	var ramp := 6.0


# ---------------- shared seed data ----------------
var seed_value: int = 0
var sz: float = 0.0
var NT := PackedFloat64Array()   # 256x256 lattice: (Cx, Cy, C0) per corner, the constant 3rd noise axis folded in
var rp_a: float = 0.0
var rp_sg: float = 1.0
var pitches := PackedFloat64Array()   # [centre, len, share] * k
var pitch_share: float = 0.0
var course: TrailCourse
var route_feats: Array = []
# course arrays (local refs for speed)
var cX := PackedFloat64Array()
var cZ := PackedFloat64Array()
var cKD := PackedInt32Array()
var cTX := PackedFloat32Array()
var cTZ := PackedFloat32Array()
var cKAP := PackedFloat32Array()
var cW := PackedFloat32Array()
var cBT := PackedFloat32Array()
var cE := PackedFloat32Array()
var cRD := PackedFloat32Array()
var cRK := PackedFloat32Array()
var cLN := PackedFloat32Array()    # the racing line (TrailCourse.LN)
var cRO := PackedFloat32Array()    # run-off skids (TrailCourse.RO / ROS)
var cROS := PackedFloat32Array()
var c_gx0: int = 0
var c_gz0: int = 0
var c_gnx: int = 0
var c_gnz: int = 0
var c_start := PackedInt32Array()
var c_items := PackedInt32Array()
# per segment i -> i+1: (bx, bz, bx*bx + bz*bz, midpoint x, midpoint z, skip radius^2)
var c_seg := PackedFloat64Array()
# per cell: runs of consecutive segment indices, packed as start * 256 + (end - start)
var c_run_start := PackedInt32Array()
var c_runs := PackedInt32Array()

# ---------------- per-instance state ----------------
# course query result (the JS q object)
var q_x: float = NAN
var q_z: float = NAN
var q_d: float = INF
var q_a: float = 0.0
var q_i: int = 0
var q_t: float = 0.0
var q_w: float = NAN
var q_kind: int = 0
var q_k: float = 0.0
var q_bt: float = 0.0
var q_s: float = 0.0
var q_rd: float = 0.0
var q_rk: float = 0.0
var q_bench: float = 0.0
var q_mask: float = 0.0
var _qp := PackedFloat64Array()   # the second cache slot
var _cand := PackedInt32Array()
# jump() accumulator (the JS o object)
var fo_h: float = 0.0
var fo_m: float = 0.0
var fo_plane: float = 0.0
var fo_dig: float = 0.0
var fo_wood: float = 0.0
var fo_has_wood: bool = false
var fo_air: float = 0.0   # 0..1: riders are in the air over this spot of a jump (no ridden lines drawn)
var _fo_x: float = NAN
var _fo_z: float = NAN
# wooden deck under the last ground() sample
var wood: float = 0.0
var has_wood: bool = false
var _jc := {}
# memos (exact: same input -> same output)
var _pn_x: float = NAN
var _pn_z: float = NAN
var _pn_v: float = 0.0
var _mt_x: float = NAN
var _mt_z: float = NAN
var _mt_v: float = 0.0
var _zc_x: float = NAN
var _zc_v: float = 0.0
var b_dry: float = 0.0
var b_rug: float = 0.0
## climate biomes (2026-11-25, on top of the dry / rugged axes, which stay as they were): 0..1 weights, see biome()
var b_cold: float = 0.0     # alpine: high + cold
var b_wet: float = 0.0      # wetland: low + moist
var b_forest: float = 0.0   # pine forest: moist, mild
var b_sav: float = 0.0      # savanna: the semi-dry band between green land and desert
var b_ash: float = 0.0      # ash fields: rare dark volcanic patches
var _bi_x: float = NAN
var _bi_z: float = NAN
var _g_x: float = NAN
var _g_z: float = NAN
var _g_v: float = 0.0
var _g_wood: float = 0.0
var _g_has_wood: bool = false
# colorLayers outputs
var cl_g := Color()
var cl_d := Color()
var cl_steep: float = 0.0

var col := {}            # per-instance copies (no shared refcounts between threads)
var red_bands := PackedColorArray()
var grey_bands := PackedColorArray()
var profiles := {}
var sized := {}   # TrailFeatures.make_set()["sized"]: type -> [profile per speed size]
## (2026-11-24) route jumps sized to the speed riders arrive at (TrailCourse.VA); BMX_OLD_JUMPSIZE=1 = always the big one
static var OLD_JUMPSIZE := OS.get_environment("BMX_OLD_JUMPSIZE") != ""
## the AI's planned speed / least speed as a share of a size's design speed, per type (DemoPilot.FEAT_V / FEAT_MIN at size 3)
## (a smaller kicker at its full design speed, never under 90 % of it: slower, the AI rolled off its open back nose first)
const SIZE_V_K := {"table": [0.9, 0.8], "tableLine": [0.9, 0.8], "kicker": [1.0, 0.9], "flow": [0.93, 0.0]}
## riders arrive faster than TrailCourse.VA (free rolling: pedals only below ~30 km/h): measured, the demo AI leaves the
## big jumps' lips at 38-46 km/h where VA says ~30-35, i.e. ~1.4x. Sizes are picked for VA x this
const RIDER_K := 1.4
var small := {}   # the old-size jump profiles, for the free-ride jumps out in the land (TrailFeatures.TABLE_S ...)
var woods := {}
var digs := {}
static var COL := {}
static var RED_BANDS: Array = []
static var GREY_BANDS: Array = []


static func lin(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xFF).srgb_to_linear()


static func _ensure_colors() -> void:
	if not COL.is_empty():
		return
	var d := {
		"grassA": 0x83c44e, "grassB": 0x5fa83c, "meadow": 0xb5cf5c, "dirt": 0xc98d55, "dirtDark": 0xa56d3e,
		"sand": 0xe6d39a, "bed": 0xb3a06c, "rock": 0x8f8a80, "snowish": 0xd9dcc8,
		"dryGrass": 0xc9b45a, "dune": 0xedc98a, "duneDark": 0xd9aa66, "desertDirt": 0xd49a5c,
		"red": 0xc2603a, "redLight": 0xe38c55, "redDark": 0x8f4029, "cream": 0xf0d3a2,
		"tuftGreen": 0x5e9e37, "tuftDry": 0xb59a4a,
		"litter": 0x77703a, "clover": 0x4d9a3a, "gravel": 0xb9a98c,
		"grey": 0x8d8a86, "greyDark": 0x5f5d5c, "greyLight": 0xb4b0a8, "snow": 0xf4f7f8, "alpine": 0x6f9a4a,
		"needle": 0x5a5a32, "marsh": 0x6b8a3c, "savanna": 0xcdb056, "frost": 0x9db09c, "ash": 0x3b3937, "ashLight": 0x5a5652,
	}
	var c := {}
	for k in d:
		c[k] = lin(d[k])
	RED_BANDS = [c["red"], c["redLight"], c["redDark"], c["cream"], c["red"], c["redLight"]]
	GREY_BANDS = [c["grey"], c["greyDark"], c["greyLight"], c["grey"], c["greyDark"]]
	COL = c


static func sm(a: float, b: float, x: float) -> float:
	var t := (x - a) / (b - a)
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	return t * t * (3.0 - 2.0 * t)


# ======================================================================
# setup
# ======================================================================
## style: the trail's character (RouteStyle keys); empty = what the player picked (RouteStyle.current)
var style: Dictionary = {}
var biome_dry: float = 0.0   # RouteStyle.biome: added to the dry / rugged noise (+-2 pins the biome, 0 = the seed's own mix)
var biome_rug: float = 0.0
var grade_k: float = 1.0   # RouteStyle.grade: the mountains' height x this (their lengths stay), so every fall is this much steeper (1 = as before)

func setup(seed_in: int, style_in: Dictionary = {}) -> void:
	style = style_in.duplicate() if not style_in.is_empty() else RouteStyle.snapshot()
	grade_k = clampf(float(style.get("grade", 1.0)), 0.5, 1.7)
	var pick: Array = RouteStyle.BIOMES[clampi(roundi(float(style.get("biome", 0.0))), 0, RouteStyle.BIOMES.size() - 1)]
	biome_dry = float(pick[1]); biome_rug = float(pick[2])
	TrailFeatures.ensure()
	_ensure_colors()
	_local_tables()
	seed_value = seed_in
	sz = (seed_in % 1000) * 0.7311 + 0.37
	_build_noise()
	var r := WorldRng.new(seed_in * 7919 + 13)
	rp_a = r.next() * 6.28
	r.next()
	rp_sg = 1.0 if r.next() < 0.5 else -1.0
	pitches = PackedFloat64Array()
	pitch_share = 0.0
	var x := 170 + r.next() * 80
	var k := 0
	while k < 5 and x < HILL_LEN - 140:
		var len := 34 + r.next() * 24
		var sh := 0.06 + r.next() * 0.03
		pitches.append(x); pitches.append(len); pitches.append(sh)
		pitch_share += sh
		x += len + 190 + r.next() * 170
		k += 1
	_reset_caches()
	var crng := WorldRng.new(seed_in * 31337 + 5)
	course = TrailCourse.make(crng, self, HILL_LEN, MTN_W - 40, COURSE_LEN, seed_in * 6151 + 3)
	_bind_course()
	course.plan_marking(self)
	_reset_caches()
	_build_route()


## (worker thread, on a fork) lay the course out on to to_x: this fork gets the grown course, its
## query tables, marking and route features; the main field takes them over with adopt_course()
func grow_course(to_x: float) -> void:
	course = course.grown(self, to_x)
	_reset_caches()
	_bind_course()
	course.plan_marking(self)
	_reset_caches()
	_build_route()
	_reset_caches()


## (main thread) take over a course grown on a fork by grow_course()
func adopt_course(g: TerrainField) -> void:
	course = g.course
	cX = g.cX; cZ = g.cZ; cKD = g.cKD; cTX = g.cTX; cTZ = g.cTZ; cKAP = g.cKAP; cW = g.cW; cBT = g.cBT; cE = g.cE
	cRD = g.cRD; cRK = g.cRK; cLN = g.cLN; cRO = g.cRO; cROS = g.cROS
	c_gx0 = g.c_gx0; c_gz0 = g.c_gz0; c_gnx = g.c_gnx; c_gnz = g.c_gnz; c_start = g.c_start; c_items = g.c_items
	c_seg = g.c_seg; c_run_start = g.c_run_start; c_runs = g.c_runs
	route_feats = g.route_feats
	_index_canyons()
	_reset_caches()


func _local_tables() -> void:
	col = COL.duplicate()
	red_bands = PackedColorArray(RED_BANDS)
	grey_bands = PackedColorArray(GREY_BANDS)
	var st := TrailFeatures.make_set()
	profiles = st["profiles"]; woods = st["wood"]; digs = st["dig"]; small = st["small"]; sized = st["sized"]


func fork() -> TerrainField:
	var f := TerrainField.new()
	f._local_tables()
	f.style = style.duplicate()
	f.grade_k = grade_k
	f.biome_dry = biome_dry; f.biome_rug = biome_rug
	f.seed_value = seed_value; f.sz = sz; f.NT = NT.duplicate()   # private copies: no shared refcounts across threads
	f.rp_a = rp_a; f.rp_sg = rp_sg; f.pitches = pitches.duplicate(); f.pitch_share = pitch_share
	f.course = course
	f._bind_course(true)
	f.route_feats = []
	for j in route_feats:
		var c: Feat = f.make_feat(j.x, j.z, j.dx, j.dz, j.type, j.b0, j.b1, false, j.size)
		c.s = j.s
		f.route_feats.append(c)
	f._index_canyons()
	return f


func _bind_course(private: bool = false) -> void:
	var c := course
	cX = c.X; cZ = c.Z; cKD = c.KD; cTX = c.TX; cTZ = c.TZ; cKAP = c.KAP; cW = c.W; cBT = c.BT; cE = c.E
	cRD = c.RD; cRK = c.RK; cLN = c.LN; cRO = c.RO; cROS = c.ROS
	c_gx0 = c.gx0; c_gz0 = c.gz0; c_gnx = c.gnx; c_gnz = c.gnz; c_start = c.cell_start; c_items = c.cell_items
	c_seg = PackedFloat64Array()
	c_seg.resize(maxi(0, c.n - 1) * 6)
	for i in c.n - 1:
		var bx: float = cX[i + 1] - cX[i]
		var bz: float = cZ[i + 1] - cZ[i]
		var hl := sqrt(bx * bx + bz * bz) * 0.5
		c_seg[i * 6] = bx
		c_seg[i * 6 + 1] = bz
		c_seg[i * 6 + 2] = bx * bx + bz * bz
		c_seg[i * 6 + 3] = (cX[i] + cX[i + 1]) * 0.5
		c_seg[i * 6 + 4] = (cZ[i] + cZ[i + 1]) * 0.5
		var rr := QR + 0.01 + hl + 0.001
		c_seg[i * 6 + 5] = rr * rr
	c_run_start = PackedInt32Array()
	c_run_start.resize(c_start.size())
	c_runs = PackedInt32Array()
	for ci in c_start.size() - 1:
		c_run_start[ci] = c_runs.size()
		var a := -1
		var b := -1
		for k in range(c_start[ci], c_start[ci + 1]):
			var it: int = c_items[k]
			if a >= 0 and it == b + 1 and it - a < 255:
				b = it
			else:
				if a >= 0:
					c_runs.append(a * 256 + (b - a))
				a = it
				b = it
		if a >= 0:
			c_runs.append(a * 256 + (b - a))
	c_run_start[c_start.size() - 1] = c_runs.size()
	if private:
		cX = cX.duplicate(); cZ = cZ.duplicate(); cKD = cKD.duplicate(); cTX = cTX.duplicate(); cTZ = cTZ.duplicate()
		cKAP = cKAP.duplicate(); cW = cW.duplicate(); cBT = cBT.duplicate(); cE = cE.duplicate(); cRD = cRD.duplicate()
		cRK = cRK.duplicate(); cLN = cLN.duplicate(); cRO = cRO.duplicate(); cROS = cROS.duplicate(); c_start = c_start.duplicate(); c_items = c_items.duplicate()
	_qp.resize(15)
	_qp[0] = NAN; _qp[1] = NAN; _qp[2] = INF


func _reset_caches() -> void:
	_jc = {}
	q_x = NAN; q_z = NAN; q_d = INF
	_qp.resize(15); _qp[0] = NAN; _qp[1] = NAN; _qp[2] = INF
	_fo_x = NAN; _gr_x = NAN; _pn_x = NAN; _mt_x = NAN; _zc_x = NAN; _bi_x = NAN; _g_x = NAN; _rg_x = NAN


# ---------------- Perlin (three.js ImprovedNoise, z fixed at sz) ----------------
static func _grad(h: int) -> Vector3i:
	h &= 15
	var u := 0 if h < 8 else 1   # 0 = x, 1 = y
	var v := 1 if h < 4 else (0 if (h == 12 or h == 14) else 2)
	var c := Vector3i.ZERO
	var su := -1 if (h & 1) != 0 else 1
	var sv := -1 if (h & 2) != 0 else 1
	c[u] += su
	c[v] += sv
	return c


func _build_noise() -> void:
	var p := PackedInt32Array()
	p.resize(512)
	for i in 256:
		p[i] = PERM[i]
		p[256 + i] = PERM[i]
	var fz := floorf(sz)
	var Zi := int(fz) & 255
	var zf := sz - fz
	var w := zf * zf * zf * (zf * (zf * 6 - 15) + 10)
	NT = PackedFloat64Array()
	NT.resize(65536 * 3)
	for X in 256:
		for Y in 256:
			var AA: int = p[p[X] + Y] + Zi
			var g0 := _grad(p[AA])
			var g1 := _grad(p[AA + 1])
			var o := ((X << 8) | Y) * 3
			NT[o] = g0.x + w * (g1.x - g0.x)
			NT[o + 1] = g0.y + w * (g1.y - g0.y)
			NT[o + 2] = g0.z * zf + w * (g1.z * (zf - 1.0) - g0.z * zf)


func noise(x: float, y: float) -> float:
	var fx := floorf(x)
	var fy := floorf(y)
	var X := int(fx) & 255
	var Y := int(fy) & 255
	x -= fx
	y -= fy
	var u := x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
	var v := y * y * y * (y * (y * 6.0 - 15.0) + 10.0)
	var X1 := (X + 1) & 255
	var Y1 := (Y + 1) & 255
	var i00 := ((X << 8) | Y) * 3
	var i10 := ((X1 << 8) | Y) * 3
	var i01 := ((X << 8) | Y1) * 3
	var i11 := ((X1 << 8) | Y1) * 3
	var x1 := x - 1.0
	var y1 := y - 1.0
	var c00: float = NT[i00] * x + NT[i00 + 1] * y + NT[i00 + 2]
	var c10: float = NT[i10] * x1 + NT[i10 + 1] * y + NT[i10 + 2]
	var c01: float = NT[i01] * x + NT[i01 + 1] * y1 + NT[i01 + 2]
	var c11: float = NT[i11] * x1 + NT[i11 + 1] * y1 + NT[i11 + 2]
	var a := c00 + u * (c10 - c00)
	return a + v * (c01 + u * (c11 - c01) - a)


## noise() with its gradient: returns the value, the d/dx and d/dy (of the arguments) are left in _ndx / _ndy. Same lattice,
## same operations as noise() (the value is identical); mirrored in TerrainFieldCs.noise_d.
var _ndx := 0.0
var _ndy := 0.0
func noise_d(x: float, y: float) -> float:
	var fx := floorf(x)
	var fy := floorf(y)
	var X := int(fx) & 255
	var Y := int(fy) & 255
	x -= fx
	y -= fy
	var u := x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
	var v := y * y * y * (y * (y * 6.0 - 15.0) + 10.0)
	var X1 := (X + 1) & 255
	var Y1 := (Y + 1) & 255
	var i00 := ((X << 8) | Y) * 3
	var i10 := ((X1 << 8) | Y) * 3
	var i01 := ((X << 8) | Y1) * 3
	var i11 := ((X1 << 8) | Y1) * 3
	var x1 := x - 1.0
	var y1 := y - 1.0
	var c00: float = NT[i00] * x + NT[i00 + 1] * y + NT[i00 + 2]
	var c10: float = NT[i10] * x1 + NT[i10 + 1] * y + NT[i10 + 2]
	var c01: float = NT[i01] * x + NT[i01 + 1] * y1 + NT[i01 + 2]
	var c11: float = NT[i11] * x1 + NT[i11 + 1] * y1 + NT[i11 + 2]
	var du := 30.0 * x * x * x1 * x1
	var dv := 30.0 * y * y * y1 * y1
	var a := c00 + u * (c10 - c00)
	var b := c01 + u * (c11 - c01)
	var dax: float = NT[i00] + u * (NT[i10] - NT[i00]) + du * (c10 - c00)
	var dbx: float = NT[i01] + u * (NT[i11] - NT[i01]) + du * (c11 - c01)
	var day: float = NT[i00 + 1] + u * (NT[i10 + 1] - NT[i00 + 1])
	var dby: float = NT[i01 + 1] + u * (NT[i11 + 1] - NT[i01 + 1])
	_ndx = dax + v * (dbx - dax)
	_ndy = day + v * (dby - day) + dv * (b - a)
	return a + v * (b - a)


func n(x: float, z: float, s: float) -> float:
	return noise(x * s, z * s)


# ======================================================================
# the mountain
# ======================================================================
func zc(x: float) -> float:
	if x == _zc_x:
		return _zc_v
	_zc_x = x
	_zc_v = rp_sg * 40.0 * (sin(x / 260.0 + rp_a) - sin(rp_a))
	return _zc_v


# ---------------- the mountains after the first: one every RANGE_P m, for ever ----------------
## Each is a gentle climb (about 4 % on average) up the back of a ridge that follows the trail's corridor, a short
## level top, then the descent (about 7.5 %). Height, lengths and where it sits in its slot come from an integer
## hash of the slot + seed (no table: any x can be asked, the trail can grow for ever). Mirrored in TerrainFieldCs.
const RANGE_X0 := 2100.0    # the first one's slot starts here (the first mountain ends at HILL_LEN)
const RANGE_P := 2800.0
const RANGE_UP := 0.042     # mean grade of the climb
const RANGE_DOWN := 0.075   # ... of the descent
var _rg_x: float = NAN
var _rg_h: float = 0.0      # height along the ridge line at x (m)
var _rg_m: float = 0.0      # 0..1: on a mountain (calms the land's own bumps like the first mountain does)
var rg_down: float = 0.0    # 0..1: on a descent (TrailCourse puts its tight technical sections there)


func _range_hash(k: int, ch: int) -> float:
	return float(((k * 73856093) ^ (ch * 19349663) ^ (seed_value * 2654435761)) & 0xffff) / 65536.0


func range_at(x: float) -> void:
	if x == _rg_x:
		return
	_rg_x = x
	_rg_h = 0.0; _rg_m = 0.0; rg_down = 0.0
	if x <= RANGE_X0:
		return
	var k := floori((x - RANGE_X0) / RANGE_P)
	var u := x - RANGE_X0 - k * RANGE_P
	var hh0 := 40.0 + 14.0 * _range_hash(k, 1)   # (the mountain's height at grade 1: its lengths come from this)
	var hh := hh0 * grade_k
	var a0 := 120.0 + 260.0 * _range_hash(k, 2)
	var lc := hh0 / RANGE_UP
	var lp := 50.0 + 40.0 * _range_hash(k, 3)
	var ld := hh0 / RANGE_DOWN
	var e := a0 + lc + lp + ld
	if u <= a0 - 140.0 or u >= e + 140.0:
		return
	var up := sm(a0, a0 + lc, u)
	var dn := sm(a0 + lc + lp, e, u)
	_rg_h = hh * up * (1.0 - dn)
	_rg_m = sm(a0 - 140.0, a0, u) * (1.0 - sm(e, e + 140.0, u))
	rg_down = sm(a0 + lc + lp - 30.0, a0 + lc + lp + 20.0, u) * (1.0 - sm(e - 40.0, e + 20.0, u))


func mtn(x: float, z: float) -> float:
	if x == _mt_x and z == _mt_z:
		return _mt_v
	var v := 0.0
	if x > RANGE_X0:
		range_at(x)
		if _rg_m > 0.0:
			v = _rg_m * (1.0 - sm(MTN_W - 20, MTN_W + 90, absf(z - zc(x))))
	if x > -300.0 and x < HILL_LEN + 150:
		# (1 - sm(MTN_W - 20, MTN_W + 90, |z - zc|)) * sm(-300, -170, x) * (1 - sm(HILL_LEN, HILL_LEN + 150, x))
		var t := (absf(z - zc(x)) - (MTN_W - 20)) / ((MTN_W + 90) - (MTN_W - 20))
		if t < 1.0:
			t = 0.0 if t < 0.0 else t
			var a := 1.0 - t * t * (3.0 - 2.0 * t)
			t = (x - -300.0) / (-170.0 - -300.0)
			t = 1.0 if t > 1.0 else t
			a *= t * t * (3.0 - 2.0 * t)
			t = (x - HILL_LEN) / ((HILL_LEN + 150) - HILL_LEN)
			t = 0.0 if t < 0.0 else t
			v = a * (1.0 - t * t * (3.0 - 2.0 * t))
	_mt_x = x; _mt_z = z; _mt_v = v
	return v


func hill(x: float, z: float) -> float:
	if x <= -330.0:
		return 0.0
	var steep := 0.0
	var t := 0.0
	for k in range(0, pitches.size(), 3):
		var c: float = pitches[k]
		var l: float = pitches[k + 1]
		var a := c - l / 2
		if x <= a:
			continue   # sm(...) = 0, adds sh * 0
		var b := c + l / 2
		t = (x - a) / (b - a)
		t = 1.0 if t > 1.0 else t
		steep += pitches[k + 2] * (t * t * (3.0 - 2.0 * t))
	var lin_ := minf(1.0, maxf(0.0, x / HILL_LEN))
	t = (x - -10.0) / (HILL_LEN - -10.0)
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	var s1 := t * t * (3.0 - 2.0 * t)
	t = (x - -330.0) / (-90.0 - -330.0)
	t = 1.0 if t > 1.0 else t
	var along := (1.0 - steep - (1.0 - pitch_share) * (0.6 * s1 + 0.4 * lin_)) * (t * t * (3.0 - 2.0 * t))
	var top := HILL_TOP * along * grade_k if along > 0.0 else 0.0
	if x > RANGE_X0:
		range_at(x)
		top += _rg_h
	if top <= 0.0:
		return 0.0
	return top * (1.0 - sm(MTN_W, MTN_W + 260, absf(z - zc(x))))


func route_dist(x: float, z: float) -> float:
	query(x, z)
	return q_d


func pathN(x: float, z: float) -> float:
	if x == _pn_x and z == _pn_z:
		return _pn_v
	var v := noise((x + 211.3) * I42, (z - 97.1) * I42)
	var t := (mtn(x, z) - 0.3) / (0.75 - 0.3)
	if t > 0.0:
		t = 1.0 if t > 1.0 else t
		var o := 0.3 * (t * t * (3.0 - 2.0 * t))
		v = v - o if v < 0.0 else v + o
	_pn_x = x; _pn_z = z; _pn_v = v
	return v


## path-noise gradient (central differences, 0.5 m) at (x, z) -> _gx, _gz (memoised)
var _gr_x: float = NAN
var _gr_z: float = NAN
var _gx: float = 0.0
var _gz: float = 0.0
func _grad_at(x: float, z: float) -> void:
	if x == _gr_x and z == _gr_z:
		return
	_gx = pathN(x + 0.5, z) - pathN(x - 0.5, z)
	_gz = pathN(x, z + 0.5) - pathN(x, z - 0.5)
	_gr_x = x; _gr_z = z


func trail(x: float, z: float) -> float:
	var p := absf(pathN(x, z))
	query(x, z)
	var main := (1.0 - sm(q_w, q_w + 1.2, q_d)) if q_d < 12.0 else 0.0
	var t := (p - 0.03) / (0.075 - 0.03)
	if t >= 1.0:
		return maxf(0.0, main)
	t = 0.0 if t < 0.0 else t
	return maxf(1.0 - t * t * (3.0 - 2.0 * t), main)


func across(x: float, z: float) -> float:
	query(x, z)
	if q_d < q_w + 2.6:
		return q_a
	_grad_at(x, z)
	return pathN(x, z) / maxf(sqrt(_gx * _gx + _gz * _gz), 0.012)


## where the ridden line sits across the trail (m): on the course the racing line (TrailCourse.LN) with a small
## wander, on the wild side paths a slow wander
## how hard riders press the ground at a point of the trail, 0 on a straight .. 1 in a tight bend (mirrored in
## TerrainFieldCs.corner_load). They arrive fast and the bend turns them, so the lateral force grows with the
## curvature k (1 / radius, 1 / m): nothing below ~80 m radius, full from ~14 m. The ground shader sinks the
## ridden line and the tyre prints deeper with it.
const CORNER_K0 := 0.0125
const CORNER_K1 := 0.07
static func corner_load(k: float) -> float:
	return smoothstep(CORNER_K0, CORNER_K1, absf(k))


func line_off(x: float, z: float) -> float:
	var wob := noise((x + 91.7) * I23, (z - 13.3) * I23)
	query(x, z)
	if q_d < q_w + 2.6:
		return cLN[q_i] + (cLN[q_i + 1] - cLN[q_i]) * q_t + wob * 0.18
	return wob * 1.5


func line(x: float, z: float) -> float:
	var off := line_off(x, z)
	var a := across(x, z)
	# one ridden line everywhere: only bikes use these trails, so a road has no pair of wheel ruts
	return 1.0 - sm(0.25, 0.7, absf(a - off))


# ---------------- berms ----------------
func berm_shape(o: float, tn: float) -> float:
	if o < -1.6:
		return 0.0
	var edge := 2.7
	if o < 0.0:
		return tn * (o + 1.6) * (o + 1.6) / 3.2
	var om := edge - log(1.0 + exp(2.0 * (edge - o))) / 2.0
	return tn * (om + 0.8) * (1.0 - sm(edge - 0.5, edge + 6.5, o))


## Berm v2 (2026-11-25, user: "make our berms more realistic: rocks / pebbles on the edges, a little grass lip, a deep depression in the
## lip from riders whipping, tilted vs curved styles; find a good formula"). Cross-section by the distance o from the centreline on the
## berm's side (o = -1.6 where it starts): an entry that eases into the bank (slope 0 -> tn = tan(bank), as before: the racing line at
## ~0.9 m rides a face of exactly the bank the course asked for), then the FACE whose slope stays tn to 0.9 m and then steepens by up to
## (1 + c) x tn towards the rim at F (c = 0 a tilted plane, c ~ 0.75 a curved bowl: riders pick their height by speed), a rounded CAP
## of width cw where the slope eases to 0 (a defined rim), a back slope (the outside of the dirt) that falls to the ground over
## clamp(rim / 0.6, 2, 5) m. On top: a small LIP roll along the rim (`bs_lip` m, only on some berms: the grass lip) and SCOOPS (`bs_scoop`
## m deep, in short stretches of some berms: the hollow riders wear into the lip taking it fast / whipping it). Style per arc length from
## noises (`berm_style`), so a berm differs from the next: tilted .. curved, rim at the trail's own width + 0 .. 0.8 m, lip or none,
## scoop or none. Only + * / - sm() here (no exp / log): C# mirrors it exactly. BMX_OLD_BERM=1 = the old shape.
static var OLD_BERM := OS.get_environment("BMX_OLD_BERM") != ""
var bs_c := 0.0
var bs_F := 2.7
var bs_cw := 0.5
var bs_lip := 0.0
var bs_scoop := 0.0


func berm_style(a: float, b: float, w: float) -> void:
	var n1 := noise(a / 70.0 + 11.0, b / 70.0 + 5.3)
	var n2 := noise(a / 45.0 - 3.1, b / 45.0 + 7.7)
	var n3 := noise(a / 90.0 + 41.0, b / 90.0 - 9.0)
	var g := sm(0.05, 0.4, noise(a / 130.0 + 71.0, b / 130.0 - 12.5))
	var wn := sm(0.30, 0.55, noise(a / 11.0 - 5.0, b / 11.0 + 19.0))
	bs_c = 0.75 * sm(-0.25, 0.3, n1)
	bs_F = clampf(w + 0.1 + 0.8 * sm(-0.3, 0.3, n2), 2.0, 3.5)
	bs_cw = 0.3 + 0.5 * (bs_c / 0.75)
	bs_lip = 0.18 * sm(0.0, 0.35, n3)
	bs_scoop = 0.5 * g * wn


func berm_shape2(o: float, tn: float) -> float:
	if o < -1.6:
		return 0.0
	if o < 0.0:
		return tn * (o + 1.6) * (o + 1.6) / 3.2
	var F := bs_F
	var c := bs_c
	var cw := bs_cw
	var h0 := tn * 0.8
	var fo := minf(o, F)
	var g := 0.0
	if fo > 0.9:
		var t := (fo - 0.9) / (F - 0.9)
		g = (F - 0.9) * (t * t * t - t * t * t * t * 0.5)
	var hF := h0 + tn * (F + c * (F - 0.9) * 0.5)
	var slope_f := tn * (1.0 + c)
	var hrim := hF + slope_f * cw * 0.5
	var h: float
	if o <= F:
		h = h0 + tn * (fo + c * g)
	else:
		var d := o - F
		if d <= cw:
			var tc := d / cw
			h = hF + slope_f * (d - cw * (tc * tc * tc - tc * tc * tc * tc * 0.5))
		else:
			var lb := clampf(hrim / 0.6, 2.0, 5.0)
			var t2 := sm(0.0, lb, d - cw)
			h = hrim * (1.0 - t2)
	# the lip roll on the rim
	if bs_lip > 0.0:
		h += bs_lip * (1.0 - sm(0.0, 0.7, absf(o - (F + cw * 0.6))))
	# worn hollows in the lip
	if bs_scoop > 0.0:
		h -= bs_scoop * sm(F - 1.4, F, o) * (1.0 - sm(F + cw, F + cw + 1.2, o))
	return maxf(h, 0.0)


func berm(x: float, z: float) -> float:
	var h := 0.0
	query(x, z)
	# q_bt is signed (> 0 left berm, < 0 right) and already smooth along the course
	var bt := absf(q_bt) - 0.004
	if q_d < 12.0 and bt > 0.0:
		if OLD_BERM:
			h = maxf(h, berm_shape(-q_a, bt) if q_bt > 0.0 else berm_shape(q_a, bt))
		else:
			berm_style(q_s, 0.0, q_w)
			h = maxf(h, berm_shape2(-q_a if q_bt > 0.0 else q_a, bt))
	var p := pathN(x, z)
	if absf(p) < 0.2:
		_grad_at(x, z)
		var gx0 := _gx
		var gz0 := _gz
		var g0 := maxf(sqrt(gx0 * gx0 + gz0 * gz0), 1e-6)
		var s := p / g0
		var cx := x - s * gx0 / g0
		var cz := z - s * gz0 / g0
		var e := 2.0
		var pc := pathN(cx, cz)
		var pe := pathN(cx + e, cz)
		var pw := pathN(cx - e, cz)
		var pn := pathN(cx, cz + e)
		var ps := pathN(cx, cz - e)
		var px := (pe - pw) / (2 * e)
		var pz := (pn - ps) / (2 * e)
		var pxx := (pe - 2 * pc + pw) / (e * e)
		var pzz := (pn - 2 * pc + ps) / (e * e)
		var pxz := (pathN(cx + e, cz + e) - pathN(cx + e, cz - e) - pathN(cx - e, cz + e) + pathN(cx - e, cz - e)) / (4 * e * e)
		var g := sqrt(px * px + pz * pz)
		if g == 0.0:
			g = 1e-6
		var kap := (pxx * pz * pz - 2 * pxz * px * pz + pzz * px * px) / (g * g * g)
		var ak := absf(kap)
		var ok := sm(0.012, 0.02, g) * sm(12, 22, route_dist(cx, cz)) * (1.0 - sm(0.12, 0.2, absf(p)))
		var tn := minf(0.55, 17 * ak) * sm(0.012, 0.03, ak) * (1.0 - sm(0.07, 0.1, ak)) * ok
		if tn > 0.0 and absf(s) < 10.0:
			var bon := sm(0.2, 0.36, noise((cx + 777) * I55, (cz - 333) * I55))
			if OLD_BERM:
				h = maxf(h, berm_shape(s * signf(kap), tn) * bon)
			else:
				berm_style(cx, cz, 1.9)
				h = maxf(h, berm_shape2(s * signf(kap), tn) * bon)
	return h


# ---------------- the land ----------------
func landform(x: float, z: float) -> float:
	var calm := 1.0 - 0.85 * mtn(x, z)
	var relief := 1.0 + 1.3 * sm(0.0, 0.35, noise((x + 5000) * I260, (z - 800) * I260))
	# big rolling hills (~240 m) in some regions, open flats in others: the land changes character as you ride
	var big := sm(-0.15, 0.3, noise((x + 2600) * I700, (z - 3100) * I700))
	# sharp ridgelines with long crests in other regions (ridged noise, mean taken out so the land doesn't rise)
	var rdg := sm(0.05, 0.35, noise((x - 4100) * I700, (z + 1500) * I700))
	var h: float
	var slt := 0.0
	if OLD_LAND:
		var rr := 1.0 - absf(noise((x + 820) * I150, (z - 2300) * I150))
		h = (noise(x * I90, z * I90) * 10 * relief + noise((x + 31.7) * I28, (z - 17.2) * I28) * 3.2 * (0.6 + 0.4 * relief)
			+ noise((x - 1700) * I240, (z + 900) * I240) * 16 * big + (rr * rr - 0.45) * 14 * rdg) * calm + hill(x, z)
	else:
		# macro controls: plains .. rough country (detail), low .. big hills / ridges (macro)
		var kd := spl(noise((x + 4400.0) * LAND_CR, (z - 3700.0) * LAND_CR), -0.45, 0.45, -0.1, 0.75, 0.15, 1.0, 0.45, 1.4)
		var km := spl(noise((x - 1300.0) * LAND_CM, (z + 2900.0) * LAND_CM), -0.4, 0.55, 0.0, 1.0, 0.2, 1.25, 0.45, 1.6)
		big *= km
		rdg *= km
		var wk := LAND_WARP * calm
		var wx := x + noise((x + 1900.0) * I170, (z - 640.0) * I170) * wk
		var wz := z + noise((x - 2300.0) * I170, (z + 1100.0) * I170) * wk
		# the big relief with its gradient (240 m octave + ridge term)
		var n240 := noise_d((wx - 1700) * I240, (wz + 900) * I240)
		var g240x := _ndx * I240
		var g240z := _ndy * I240
		var n150 := noise_d((wx + 820) * I150, (wz - 2300) * I150)
		var g150x := _ndx * I150
		var g150z := _ndy * I150
		var rr := 1.0 - absf(n150)
		var m0 := n240 * 16 * big + (rr * rr - 0.45) * 14 * rdg
		var sg := signf(n150)
		var mx := g240x * 16 * big - 2.0 * rr * sg * g150x * 14 * rdg
		var mz := g240z * 16 * big - 2.0 * rr * sg * g150z * 14 * rdg
		var sl := sqrt(mx * mx + mz * mz) * calm
		var vk := sm(0.10, 0.40, -noise((x + 7100.0) * LAND_VI, (z - 2600.0) * LAND_VI))
		var tk := (1.0 - LAND_VALLEY_MACRO * vk) / sqrt(1.0 + (sl / LAND_TALUS) * (sl / LAND_TALUS))
		var ds := sl / LAND_DETAIL_S
		var dk := (1.0 - LAND_VALLEY_FLAT * vk) / (1.0 + ds * ds)
		var a90 := 10 * relief * kd * dk
		var n90 := noise_d(wx * I90, wz * I90)
		var g90x := _ndx * I90
		var g90z := _ndy * I90
		var tx := (mx * tk + g90x * a90) * calm
		var tz := (mz * tk + g90z * a90) * calm
		slt = sqrt(tx * tx + tz * tz)
		var fs := slt / LAND_FINE_S
		var a28 := 3.2 * (0.6 + 0.4 * relief) * kd * dk / (1.0 + fs * fs)
		h = (n90 * a90 + noise((wx + 31.7) * I28, (wz - 17.2) * I28) * a28) * calm + m0 * tk * calm + hill(x, z)
	var wm := wild_mask(x, z)
	if wm == 0.0:
		return h
	h += wild(x, z) * wm
	if not OLD_LAND:
		var rug := b_rug
		var sk := rug * sm(0.10, 0.35, slt) * sm(6.0, 30.0, trail_metres(x, z)) * LAND_STRATA
		if sk > 0.0:
			var ph := h / LAND_STRATA_STEP + noise((x + 3.3) * I60, (z - 8.1) * I60) * 0.4
			var fl := floorf(ph)
			var st := fl + sm(0.35, 0.65, ph - fl)
			h += sk * LAND_STRATA_STEP * (st - ph)
	return h


## piecewise smoothstep through four (t, value) knots, flat outside: a spline control for the macro noises
static func spl(t: float, a0: float, b0: float, a1: float, b1: float, a2: float, b2: float, a3: float, b3: float) -> float:
	if t <= a0:
		return b0
	if t >= a3:
		return b3
	if t < a1:
		return b0 + (b1 - b0) * sm(a0, a1, t)
	if t < a2:
		return b1 + (b2 - b1) * sm(a1, a2, t)
	return b2 + (b3 - b2) * sm(a2, a3, t)


## the big-scale relief of the land (240 m octave + ridge term), before calm / talus / floor
func _macro(wx: float, wz: float, big: float, rdg: float) -> float:
	var rr := 1.0 - absf(noise((wx + 820) * I150, (wz - 2300) * I150))
	return noise((wx - 1700) * I240, (wz + 900) * I240) * 16 * big + (rr * rr - 0.45) * 14 * rdg


func base(x: float, z: float) -> float:
	var t := trail(x, z)
	var h := landform(x, z)
	var p := pathN(x, z)
	var ap := absf(p)
	var dist := 99.0
	if ap < 0.25:
		_grad_at(x, z)
		var gx := _gx
		var gz := _gz
		var g := maxf(sqrt(gx * gx + gz * gz), 0.012)
		dist = ap / g
		var bench := (1.0 - sm(3, 9.5, dist)) * sm(6, 16, route_dist(x, z)) * (1.0 - sm(0.15, 0.25, ap))
		if bench > 0.0:
			var sd := p / g
			var cx := x - sd * gx / g
			var cz := z - sd * gz / g
			var d := (landform(cx, cz) - h) * bench
			h += d / (1.0 + absf(d) / 1.1)
	query(x, z)
	if q_mask > 0.0:
		h += (q_bench - h) * q_mask
	h += noise((x - 5.3) * I8, (z + 9.1) * I8) * 0.5 * maxf(sm(2.5, 7, dist), sm(0.15, 0.25, ap)) * (1.0 - t)
	h -= 0.15 * t
	if t > 0.0:
		var ln := line(x, z)
		h += t * (noise((x + 7.1) * I1_5, (z + 3.3) * I1_5) * 0.028 + noise((x - 2.9) * I3_4, (z + 8.4) * I3_4) * 0.04 * (0.6 + 0.6 * ln) - 0.035 * ln)
	var dry := WATER + 0.5
	if h < dry:
		query(x, z)
		var bank := maxf(1.0 - sm(0.05, 0.14, ap), (1.0 - sm(q_w, q_w + 4.5, q_d)) if q_d < 20.0 else 0.0)
		h += (dry - h) * bank
	return h


# ---------------- biomes ----------------
func biome(x: float, z: float) -> void:
	if x == _bi_x and z == _bi_z:
		return
	var wx := x + noise(x * I160, (z + 500) * I160) * 60
	var wz := z + noise((x - 500) * I160, z * I160) * 60
	b_dry = sm(-0.12, 0.16, noise((wx + 3000) * I380, (wz - 1200) * I380) + biome_dry)
	b_rug = sm(-0.08, 0.2, noise((wx - 700) * I300, (wz + 2200) * I300) + biome_rug)
	# climate: a Whittaker-style mix of an altitude proxy, moisture and forest noise with the two old axes, as weights
	# (borders blend over a few hundred metres). A pinned biome (RouteStyle) keeps the old axes only.
	var an := noise((wx + 1700.0) * BIO_A, (wz - 3100.0) * BIO_A)
	var mn := noise((wx - 2500.0) * BIO_M, (wz + 900.0) * BIO_M)
	var fn := noise((wx + 600.0) * BIO_F, (wz - 1400.0) * BIO_F)
	var sn := noise((wx - 4300.0) * BIO_S, (wz + 2600.0) * BIO_S)
	var pin := 1.0 if (biome_dry != 0.0 or biome_rug != 0.0) else 0.0
	var a := an * 0.7 + b_rug * 0.45 - b_dry * 0.5
	b_cold = sm(0.25, 0.55, a) * (1.0 - pin)
	var w := mn * 0.8 - an * 0.5 - b_dry * 0.9 - b_rug * 0.5
	b_wet = sm(0.10, 0.36, w) * (1.0 - b_cold) * (1.0 - pin)
	var fo := fn * 0.7 + mn * 0.3 - b_dry * 1.0 - b_rug * 0.3
	b_forest = sm(-0.30, 0.0, fo) * (1.0 - b_cold) * (1.0 - b_wet) * (1.0 - pin)
	b_sav = sm(0.15, 0.3, b_dry) * (1.0 - sm(0.45, 0.65, b_dry)) * (1.0 - b_rug) * (1.0 - pin)
	b_ash = sm(0.27, 0.39, sn) * (1.0 - b_dry * 0.7) * (1.0 - pin)
	_bi_x = x; _bi_z = z


func biome_name(x: float, z: float) -> String:
	biome(x, z)
	if b_ash > 0.5:
		return "Ash Fields"
	if b_dry > 0.6:
		return "Red Canyons" if b_rug > 0.5 else "Dune Sea"
	if b_cold > 0.5:
		return "Alpine Peaks"
	if b_wet > 0.5:
		return "Wetlands"
	if b_forest > 0.5:
		return "Pine Forest"
	if b_sav > 0.5:
		return "Savanna"
	if b_dry > 0.35:
		return "Dry Plains"
	return "Rocky Mountains" if b_rug > 0.5 else "Green Hills"


func wild_mask(x: float, z: float) -> float:
	return (1.0 - mtn(x, z)) * sm(45, 90, sqrt(x * x + z * z))


static func trail_metres_of(path_n: float) -> float:
	return absf(path_n) / 0.022


func trail_metres(x: float, z: float) -> float:
	return absf(pathN(x, z)) / 0.022


func _tier(f: float, t: float, k: float) -> float:
	return k * (0.35 * sm(t - 0.14, t, f) + 0.65 * sm(t, t + 0.06, f))


func wild(x: float, z: float) -> float:
	biome(x, z)
	var dry := b_dry
	var rug := b_rug
	var h := 0.0
	var tm := trail_metres(x, z)
	if rug > 0.0:
		var ex := x + noise(x * I23, (z - 77) * I23) * 7 + noise(x * I7, (z + 31) * I7) * 1.5
		var ez := z + noise((x + 77) * I23, z * I23) * 7 + noise((x - 31) * I7, z * I7) * 1.5
		var r := sm(0.15, 1, 1.0 - absf(noise((x + 1300) * I95, (z - 40) * I95)))
		var peaks := r * 13 + noise((x - 90) * I40, (z + 400) * I40) * 3
		var f := noise((ex + 900) * I115, (ez - 400) * I115)
		var vary := sm(-0.25, 0.3, noise((x + 55) * I45, (z - 210) * I45))
		var rm := sm(6, 30, tm)
		var kc := vary * rm
		var cliffs := _tier(f, 0.0, 5.5 * kc) + _tier(f, 0.22, 4.5 * kc)
		var km := (0.4 + 0.6 * vary) * rm
		var mesas := _tier(f, 0.05, 6.5 * km) + _tier(f, 0.27, 4 * km)
		h += rug * ((1.0 - dry) * (peaks + cliffs) + dry * mesas)
	if dry > 0.0:
		var dx := x * 0.8 + z * 0.6
		var dz := -x * 0.6 + z * 0.8
		var d := 1.0 - absf(noise((dx / 1.0 + noise(x * I60, z * I60) * 20) * I26, (dz * 0.35) * I26))
		h += dry * (1.0 - rug * 0.7) * (d * d * 3.6 * (0.45 + 0.55 * sm(3, 25, tm)) + noise((x + 40) * I60, z * I60) * 3)
	return h


# ======================================================================
# designed features
# ======================================================================
func make_feat(x: float, z: float, dx: float, dz: float, type: String, b0: float, b1: float, old_size := false, size := 3) -> Feat:
	var f := Feat.new()
	var prof: TrailFeatures.Profile = small[type] if (old_size and small.has(type)) else profiles[type]
	if not old_size and size < 3 and sized.has(type): prof = sized[type][size]
	f.x = x; f.z = z; f.dx = dx; f.dz = dz; f.len = prof.length; f.prof = prof; f.b0 = b0; f.b1 = b1; f.type = type
	f.wood = woods.get(type)
	if type == "bridge" and posmod(int(floorf(x)) * 7 + int(floorf(z)) * 13, 3) == 0:
		f.wood = woods["bridgeW"]   # every third bridge or so is wavy
	f.dig = digs.get(type)
	f.canyon = type == "rope"
	f.air = PackedFloat64Array((TrailFeatures.AIR_S if (old_size and small.has(type)) else TrailFeatures.AIR).get(type, []))
	if not old_size and size < 3 and sized.has(type):
		f.size = size
		f.air = PackedFloat64Array(TrailFeatures.sized_air(type, size))
		var vk: Array = SIZE_V_K.get(type, [0.9, 0.0])
		f.v = float(TrailJumpSizes.V[size]) * vk[0]
		f.vmin = float(TrailJumpSizes.V[size]) * vk[1] if vk[1] > 0.0 else 0.0
	f.ramp = ROPE_RAMP if type == "rope" else 6.0
	if type == "rhythm" or type == "flow":
		f.half = 2.3
	elif type == "bridge":
		f.half = 2.4
	elif type == "gorge":
		f.half = 3.2
	elif type == "rope":
		f.half = 3.0
	elif type == "skinny":
		f.half = 1.4
	else:
		f.half = 1.9
	return f


## the beats of a jump line, in order (each a pick list): build up speed and timing on rollers, a jump (or a table
## line) to release it, then a rest (a bridge or plain trail) before the next build. BMX_OLD_RHYTHM=1 = the old random picks (tests)
## ("" = plain trail for that beat). Jump lines draw from their own random stream (seeded by where they start), so the
## road features after them are laid out exactly as before
const RHYTHM := [["rhythm", "flow", "rhythm"], ["kicker", "table", "kicker", "tableLine", "kicker", "flow", "woodKicker"], ["bridge", "bridge", ""]]   # (more kickers: 2026-11-23, user)
static var OLD_RHYTHM := OS.get_environment("BMX_OLD_RHYTHM") != ""
func _build_route() -> void:
	var C := course
	var r := WorldRng.new(seed_value * 104729 + 7)
	var list: Array = []
	var jf := clampf(float(style.get("jumps", 1.0)), 0.25, 2.5)   # RouteStyle.jumps: closer / further apart on the road
	for run in C.runs():
		var i0: int = run[0]
		var i1: int = run[1]
		var k: int = run[2]
		var jmp := k == TrailCourse.JUMP
		if not jmp and k != TrailCourse.ROAD:
			continue
		var s := i0 * CSTEP + (4.0 if jmp else 30.0)
		var s_end := i1 * CSTEP - (2.0 if jmp else 30.0)
		if not jmp:
			s += r.next() * 60
		var beat := 0   # jump lines in rhythm (Smith et al. 2009): build (rollers) -> release, release -> rest, again
		var rr: WorldRng = WorldRng.new(seed_value * 15485863 + i0 * 7919 + 3) if jmp and not OLD_RHYTHM else r
		while s < s_end:
			var in_drop := false
			for dr in C.drops:
				if s + 40 > dr[0] * CSTEP - 30 and s < dr[1] * CSTEP + 30:
					in_drop = true
					break
			if in_drop:
				s += 12
				continue
			var types: Array = TrailFeatures.ROUTE_TYPES if jmp else ["rhythm", "kicker", "table", "kicker"]
			if jmp and not OLD_RHYTHM: types = RHYTHM[beat % RHYTHM.size()]
			var type: String = types[int(rr.next() * types.size())]
			if type == "":   # a rest beat on plain trail
				s += 10.0 + rr.next() * 6.0; beat += 1
				continue
			# now and then (rare) a gorge: a deep crevasse crossed by a long wooden bridge
			# (0.06 / 0.12 before the jumps grew 1.6x: they take more of each straight, so there are fewer slots)
			if not jmp and r.next() < 0.13:
				type = "gorge"
			# or (by a hash of the slot: no extra draw from r) a swinging rope bridge high over a deeper crevasse
			elif not jmp and s > 400.0 and float(((int(s * 8.0) * 73856093) ^ (seed_value * 19349663)) & 0xffff) / 65536.0 < 0.3:
				type = "rope"
			# a jump sized for the speed riders really arrive at here (VA ~12 m in, at the lip; TrailJumpSizes.V, the big one
			# only where they carry ~56 km/h)
			var size := 3
			if sized.has(type) and not OLD_JUMPSIZE:
				var va: float = C.VA[clampi(int((s + 12.0) / CSTEP), 0, C.n - 1)] * RIDER_K
				# the smallest size designed for at least ~their speed: a bit big is the safe side (they case the deck /
				# land early on the landing), a bit small throws them past the landing onto the flat
				size = 3
				for q in range(3, -1, -1):
					if float(TrailJumpSizes.V[q]) >= va * 0.97: size = q
			var len: float = (sized[type][size] if size < 3 else profiles[type]).length
			if s + len > s_end:
				break
			var p0 := C.at(s)
			var p1 := C.at(s + len)
			var x: float = p0[0]
			var z: float = p0[1]
			var ddx: float = p1[0] - x
			var ddz: float = p1[1] - z
			var l := sqrt(ddx * ddx + ddz * ddz)
			if l < len * 0.995:
				s += 8
				continue
			var dx := ddx / l
			var dz := ddz / l
			if type == "rope" and not _canyon_clear(x, z, dx, dz, s, len):
				s += 8   # its canyon would cut the trail elsewhere (a bend, a switchback): not here
				continue
			var f := make_feat(x, z, dx, dz, type, base(x, z), base(x + dx * len, z + dz * len), false, size)
			f.s = s
			list.append(f)
			var rv := rr.next()
			if jmp and not OLD_RHYTHM:
				# the next lip one roll-out after a clean landing: ~0.75 s at the speed riders arrive at here (VA), so
				# there is time to land, settle and load the legs, never on the knuckle; a rest beat gets a longer run
				var ie := clampi(int((s + len) / CSTEP), 0, C.n - 1)
				var gap := clampf(C.VA[ie] * 0.75, 6.0, 14.0) + rv * 3.0
				if beat % RHYTHM.size() == RHYTHM.size() - 1: gap += 12.0
				s += len + gap
				beat += 1
			else:
				s += len + ((5 + rv * 8) if jmp else (70 + rv * 90) / jf)
	route_feats = list
	_index_canyons()


## free-ride jumps out in the land: the natural ground beside the footprint (half + SITE_SIDE m from the axis) may rise at most
## SITE_RISE / fall at most SITE_DROP m against the jump's plane, or the site is skipped (a table under a hillside clipped
## into it). Mirrored in TerrainFieldCs._jump_at. BMX_OLD_SITING=1 = no check. Probe: tools/feat_site_probe.gd
const SITE_SIDE := 3.0
const SITE_RISE := 1.3
const SITE_DROP := 1.8
static var OLD_SITING := OS.get_environment("BMX_OLD_SITING") != ""


func jump_at(cx: int, cz: int) -> Feat:
	var key := cx * 1048576 + cz
	if _jc.has(key):
		return _jc[key]
	if _jc.size() > 4096:
		_jc.clear()
	var rnd := WorldRng.new(WorldRng.i32(cx * 92837111) ^ WorldRng.i32(cz * 689287499) ^ WorldRng.i32(seed_value * 2654435761))
	var best: Feat = null
	if rnd.next() < 0.85:
		var best_v := 0.02
		var found := false
		var bx := 0.0
		var bz := 0.0
		for i in 24:
			var x := (cx + 0.2 + rnd.next() * 0.6) * JC
			var z := (cz + 0.2 + rnd.next() * 0.6) * JC
			var pv := absf(pathN(x, z))
			if pv < best_v and sqrt(x * x + z * z) > 20 and route_dist(x, z) > 14:
				best_v = pv; bx = x; bz = z; found = true
		if found:
			var types := TrailFeatures.FEATURE_TYPES
			var type: String = types[int(rnd.next() * types.size())]
			var len: float = (small[type] if small.has(type) else profiles[type]).length   # (old-size jumps out here)
			var gx := pathN(bx + 0.5, bz) - pathN(bx - 0.5, bz)
			var gz := pathN(bx, bz + 0.5) - pathN(bx, bz - 0.5)
			var l := sqrt(gx * gx + gz * gz)
			if l == 0.0:
				l = 1.0
			var dx := -gz / l
			var dz := gx / l
			var b0 := base(bx - dx * len / 2, bz - dz * len / 2)
			var b1 := base(bx + dx * len / 2, bz + dz * len / 2)
			if b1 > b0:
				dx = -dx; dz = -dz
				var tmp := b0
				b0 = b1; b1 = tmp
			var sx := bx - dx * len / 2
			var szz := bz - dz * len / 2
			var ok := absf(b1 - b0) / len < 0.14
			var cand := make_feat(sx, szz, dx, dz, type, b0, b1, true)
			var k := 0
			while ok and k <= 10:
				var f := k / 10.0
				var px := sx + dx * len * f
				var pz := szz + dz * len * f
				var b := base(px, pz)
				var pl := b0 + (b1 - b0) * f
				if pl < WATER + 0.6 or absf(b - pl) > 1.8 or route_dist(px, pz) < 12:
					ok = false
				# smart siting (2026-11-25, "tables clip next to a steep hill"): beside the footprint the natural ground may
				# neither rise into a wall (SITE_RISE) nor fall away (SITE_DROP) against the jump's plane, both sides
				if ok and not OLD_SITING:
					var sw := cand.half + SITE_SIDE
					var d1 := base(px - dz * sw, pz + dx * sw) - pl
					var d2 := base(px + dz * sw, pz - dx * sw) - pl
					if d1 > SITE_RISE or d2 > SITE_RISE or -d1 > SITE_DROP or -d2 > SITE_DROP:
						ok = false
				k += 1
			if ok and sqrt(sx * sx + szz * szz) > 34:
				best = cand
	_jc[key] = best
	return best


# ---------------- rope bridge canyons ----------------
## A canyon across the land under a rope bridge: two rock walls CANYON_D deep where the trail crosses, the
## rims wandering (value noise along w) and the canyon narrowing, shallowing and ending CANYON_W m to each side.
## Within 4 m of the trail the rims sit exactly at CANYON_RIM / len - CANYON_RIM (the bridge's anchors).
## Mirrored exactly in TerrainFieldCs.cs (polynomials + integer hashes only: no sin / exp).
const CANYON_W := 90.0
const CANYON_CELL := 64.0
var _canyons := {}   # 64 m cell key -> the rope canyons reaching into it


## index the rope canyons by place (call whenever route_feats changes)
func _index_canyons() -> void:
	_canyons = {}
	for j in route_feats:
		if not j.canyon:
			continue
		var mx: float = j.x + j.dx * j.len * 0.5
		var mz: float = j.z + j.dz * j.len * 0.5
		var r: float = j.len * 0.5 + CANYON_W + 8.0
		for cx in range(floori((mx - r) / CANYON_CELL), floori((mx + r) / CANYON_CELL) + 1):
			for cz in range(floori((mz - r) / CANYON_CELL), floori((mz + r) / CANYON_CELL) + 1):
				var key := cx * 1048576 + cz
				if not _canyons.has(key):
					_canyons[key] = []
				_canyons[key].append(j)
const CANYON_D := 20.0
const CANYON_RIM := 4.2
const ROPE_RAMP := 22.0   # Feat.ramp of a rope bridge (mirrored in TerrainFieldCs)


## value noise in -1..1 along t, channel ch, for feature key k
func _canyon_n(k: int, ch: int, t: float) -> float:
	var i := floori(t)
	var f := t - i
	var h0 := float(((k * 73856093) ^ (ch * 19349663) ^ (i * 83492791) ^ (seed_value * 2654435761)) & 0xffff) / 32768.0 - 1.0
	var h1 := float(((k * 73856093) ^ (ch * 19349663) ^ ((i + 1) * 83492791) ^ (seed_value * 2654435761)) & 0xffff) / 32768.0 - 1.0
	return h0 + (h1 - h0) * (f * f * (3.0 - 2.0 * f))


## at signed w across: [near rim u, far rim u, wall width, depth] of the canyon of a feature at course s, length len
func canyon_rims(s: float, len: float, ws: float) -> PackedFloat64Array:
	var k := int(s * 8.0)
	var aw := absf(ws)
	var sd := 0 if ws < 0.0 else 3
	var amp := sm(4.0, 22.0, aw)
	var cen := len * 0.5 + amp * 6.0 * _canyon_n(k, sd, aw / 16.0)
	var hw := (len * 0.5 - CANYON_RIM) * (1.0 - 0.6 * sm(8.0, CANYON_W, aw))
	var a := cen - hw + amp * 3.0 * _canyon_n(k, sd + 1, aw / 7.0)
	var b := cen + hw - amp * 3.0 * _canyon_n(k, sd + 2, aw / 7.0)
	var ww := 30.0 + amp * 10.0   # a wide sloping valley side, not a cliff
	var dep := CANYON_D * (1.0 - sm(CANYON_W - 50.0, CANYON_W, aw)) * (1.0 + 0.2 * amp * _canyon_n(k, 6, aw / 11.0))
	return PackedFloat64Array([a, b, ww, dep])


## the canyon's dig (<= 0) at (u, signed w) of feature j
func canyon_dig(s: float, len: float, u: float, ws: float) -> float:
	if absf(ws) >= CANYON_W:
		return 0.0
	var r := canyon_rims(s, len, ws)
	var v := minf(sm(r[0], r[0] + r[2], u), 1.0 - sm(r[1] - r[2], r[1], u))
	return -r[3] * v if v > 0.0 else 0.0


## a rope canyon here would cut no other part of the trail (the trail within 300 m of it, but not over it)
func _canyon_clear(x: float, z: float, dx: float, dz: float, s: float, len: float) -> bool:
	var C := course
	var i0 := maxi(0, int((s - 300.0) / CSTEP))
	var i1 := mini(C.n - 1, int((s + len + 300.0) / CSTEP))
	for i in range(i0, i1 + 1):
		var si := i * CSTEP
		if si > s - 2.0 and si < s + len + 2.0:
			continue
		var rx: float = C.X[i] - x
		var rz: float = C.Z[i] - z
		var u := rx * dx + rz * dz
		var ws := -rx * dz + rz * dx
		if u < -8.0 or u > len + 8.0 or absf(ws) > CANYON_W + 6.0:
			continue
		# the trail's own width too: its edges must stay out of the canyon
		for o in [-4.0, 0.0, 4.0]:
			if canyon_dig(s, len, u, ws + o) < -0.2:
				return false
	return true


func _feat_at(j: Feat, x: float, z: float) -> void:
	var rx := x - j.x
	var rz := z - j.z
	var u := rx * j.dx + rz * j.dz
	if u < -j.ramp or u > j.len + j.ramp:
		return
	var w := absf(-rx * j.dz + rz * j.dx)
	if w > j.half + 2.5:
		return
	var acr := 1.0 - sm(j.half, j.half + 1.2, w)
	var ph := j.prof.ev(u) * acr
	if ph > fo_h:
		fo_h = ph
	for k in range(0, j.air.size(), 2):
		var av := sm(j.air[k], j.air[k] + 0.35, u) * (1.0 - sm(j.air[k + 1] - 0.9, j.air[k + 1] + 0.9, u)) * acr
		if av > fo_air:
			fo_air = av
	if j.dig != null:
		var dh := j.dig.ev(u) * acr
		if dh < fo_dig:
			fo_dig = dh
	var cu := u / j.len
	cu = 0.0 if cu < 0.0 else (1.0 if cu > 1.0 else cu)
	var pl := j.b0 + (j.b1 - j.b0) * cu
	var mk := (1.0 - sm(j.half + 0.6, j.half + 2.5, w)) * sm(-j.ramp, -1, u) * (1.0 - sm(j.len + 1, j.len + j.ramp, u))
	if mk > fo_m:
		fo_m = mk
		fo_plane = pl
	var wd := j.wood
	if wd != null and u >= wd.u0 and u <= wd.u1:
		# a tyre's grace past the plank ends, then (on the low ramp parts only) a soft bevel down to the
		# dirt, so rolling onto a ramp at an angle climbs it instead of hitting a wall
		var wt := wd.top(u)
		var over := w - wd.half - TrailFeatures.WOOD_EDGE
		if over > 0.0 and (wt >= TrailFeatures.WOOD_BEVEL_MAX or over * TrailFeatures.WOOD_BEVEL >= wt):
			return
		var top := pl + wt - maxf(0.0, over) * TrailFeatures.WOOD_BEVEL
		if not fo_has_wood or top > fo_wood:
			fo_wood = top
			fo_has_wood = true


## fills fo_h, fo_m, fo_plane, fo_dig, fo_wood/fo_has_wood
func jump_eval(x: float, z: float) -> void:
	if x == _fo_x and z == _fo_z:
		return
	var cx := floori(x / JC)
	var cz := floori(z / JC)
	fo_h = 0.0; fo_m = 0.0; fo_plane = 0.0; fo_dig = 0.0; fo_wood = 0.0; fo_has_wood = false; fo_air = 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) * 1048576 + cz + dz
			var jv = _jc.get(key, false)
			if jv is bool:
				jv = jump_at(cx + dx, cz + dz)
			if jv == null:
				continue
			var j: Feat = jv
			var rx := x - j.x
			var rz := z - j.z
			var u := rx * j.dx + rz * j.dz
			if u < -j.ramp or u > j.len + j.ramp:
				continue
			_feat_at(j, x, z)
	query(x, z)
	if q_d < 12.0:
		var s := q_s
		# route_feats are in course order and don't overlap: binary search the first one that ends past s
		var lo := 0
		var hi := route_feats.size()
		while lo < hi:
			var mid := (lo + hi) >> 1
			var fm: Feat = route_feats[mid]
			if fm.s + fm.len + fm.ramp + 4.0 > s:
				hi = mid
			else:
				lo = mid + 1
		for k in range(lo, route_feats.size()):
			var f: Feat = route_feats[k]
			if f.s - f.ramp - 4.0 >= s:
				break
			if s > f.s - f.ramp - 4.0 and s < f.s + f.len + f.ramp + 4.0:
				_feat_at(f, x, z)
	# rope canyons: looked up by place (their arms reach far from the trail, wherever the nearest trail is)
	if not _canyons.is_empty():
		var cl = _canyons.get(floori(x / CANYON_CELL) * 1048576 + floori(z / CANYON_CELL))
		if cl != null:
			for j in cl:
				var u: float = (x - j.x) * j.dx + (z - j.z) * j.dz
				if u > -6.0 and u < j.len + 6.0:
					var cd := canyon_dig(j.s, j.len, u, -(x - j.x) * j.dz + (z - j.z) * j.dx)
					if cd < fo_dig:
						fo_dig = cd
	_fo_x = x; _fo_z = z


func jump(x: float, z: float) -> Array:
	jump_eval(x, z)
	return [fo_h, fo_m, fo_plane, fo_dig, fo_wood if fo_has_wood else null]


func jump_mask(x: float, z: float) -> float:
	jump_eval(x, z)
	return fo_m


# ======================================================================
# ground / deck
# ======================================================================
func ground(x: float, z: float) -> float:
	if x == _g_x and z == _g_z:
		wood = _g_wood; has_wood = _g_has_wood
		return _g_v
	var h := base(x, z)
	jump_eval(x, z)
	var jm := fo_m
	if jm > 0.0:
		h += (fo_plane - h) * jm
	h += fo_h + fo_dig
	var w := fo_wood
	var hw := fo_has_wood
	if jm < 1.0:
		h += berm(x, z) * (1.0 - jm)
	var f := sm(5, 28, sqrt(x * x + z * z))
	if f < 1.0:
		h = h * f + (1.0 - f) * (0.8 + hill(x, z))
	var flo := WATER + 0.75
	if h < flo:
		var dry_up := 1.0 - sm(-0.05, 0.2, noise((x - 911.3) * I170, (z + 613.7) * I170))
		if dry_up > 0.0:
			h += (flo - h) * dry_up * 0.92
	var bed := WATER - 0.35
	if h < bed:
		h = bed + (h - bed) * 0.08
	wood = w; has_wood = hw
	_g_x = x; _g_z = z; _g_v = h; _g_wood = w; _g_has_wood = hw
	return h


## ground or a wooden deck where there is one (JS's shadowed surface(): no rock / log domes)
func deck(x: float, z: float) -> float:
	var g := ground(x, z)
	return wood if has_wood and wood > g else g


# ======================================================================
# colour
# ======================================================================
# colorLayers, split in two so the chunk builder can run the expensive, normal-independent half right
# after ground() at the same point (warm memos) and finish once the normal is known. Same arithmetic,
# same order as the JS.
var cp_dry: float = 0.0
var cp_rug: float = 0.0
var cp_cold: float = 0.0
var cp_ash: float = 0.0


## part 1 (no normal needed): land colour up to the dunes -> cl_g, trail dirt -> cl_d (before the lake-bed tint); returns t
func color_pre(x: float, z: float) -> float:
	var C := col
	var v := noise((x + 50) * I6, (z + 50) * I6) * 0.5 + 0.5
	biome(x, z)
	var dry := b_dry
	var rug := b_rug
	cp_dry = dry
	cp_rug = rug
	cp_cold = b_cold
	cp_ash = b_ash
	var g: Color = C["grassA"].lerp(C["grassB"], v)
	var hh := _cp_h
	g = g.lerp(C["meadow"], sm(3.5, 8, hh) * 0.8 * (1.0 - rug))
	g = g.lerp(C["alpine"], rug * (1.0 - dry) * 0.6)
	g = g.lerp(C["needle"], b_forest * 0.55)
	g = g.lerp(C["marsh"], b_wet * 0.7)
	g = g.lerp(C["savanna"], b_sav * 0.65)
	g = g.lerp(C["frost"], b_cold * 0.55)
	g = g.lerp(C["dryGrass"], sm(0.15, 0.55, dry))
	var wd := sm(0.0, 0.35, noise((x + 400) * I38, z * I38)) * (1.0 - dry)
	g = g.lerp(C["litter"], wd * 0.38 * (1.0 - rug * 0.5))
	g = g.lerp(C["clover"], sm(0.25, 0.5, noise((x - 71) * I5, (z + 23) * I5)) * 0.35 * (1.0 - dry) * (1.0 - wd))
	g = g * (1.0 + noise((x + 17) * I2_3, (z - 29) * I2_3) * 0.08)
	var dune: Color = C["dune"].lerp(C["duneDark"], v)
	g = g.lerp(dune, sm(0.5, 0.85, dry))
	g = g.lerp(C["ash"].lerp(C["ashLight"], sm(-0.2, 0.5, noise((x + 7.7) * I9, (z - 3.1) * I9))), b_ash * 0.92)
	var tr := trail(x, z)
	var t := maxf(tr, jump_mask(x, z))
	var d: Color = C["dirt"].lerp(C["dirtDark"], sm(-0.4, 0.4, noise(x * I7, z * I7)) * 0.7).lerp(C["desertDirt"], dry * 0.6)
	if t > 0.0:
		var ln := line(x, z) * tr
		var grit := noise((x + 13.7) * I0_9, (z - 4.1) * I0_9)
		d = d * ((1.0 - 0.2 * ln) * (1.0 + (1.0 - ln) * (0.07 + grit * 0.09)))
	query(x, z)
	if q_d < q_w + 3.0:
		if q_rd > 0.0:
			var gv: Color = C["gravel"].lerp(C["desertDirt"], dry * 0.4)
			d = d.lerp(gv, q_rd * 0.6 * (0.85 + 0.15 * noise(x * 3 * I2, z * 3 * I2)))
		if q_rk > 0.0:
			d = d.lerp(C["greyDark"], q_rk * 0.45 * (0.6 + 0.4 * sm(-0.3, 0.3, noise((x - 9) * I1_3, (z + 4) * I1_3))))
	cl_g = g
	cl_d = d
	return t


var _cp_h: float = 0.0


## part 2: snow, rock faces, beach sand, lake bed (needs h and the normal's y)
func color_post(x: float, z: float, h: float, ny: float, dry: float, rug: float, cold := 0.0, ash := 0.0) -> void:
	var C := col
	var g := cl_g
	var snow_k := maxf(rug, cold)
	if snow_k > 0.0 and dry < 1.0:
		var lo := 11.0 - 7.0 * cold
		g = g.lerp(C["snow"], sm(lo, lo + 8.0, h - hill(x, z) + noise(x * I9, z * I9) * 3) * snow_k * (1.0 - dry) * sm(0.75, 0.9, ny))
	var steep := sm(0.86, 0.6, ny)
	if steep > 0.0:
		var bh := h * 0.3 + noise(x * I40, z * I40) * 0.5
		var bi := floori(bh)
		var bf := bh - bi
		var k := sm(0.75, 1, bf)
		var gb: Color = grey_bands[posmod(bi, 5)].lerp(grey_bands[posmod(bi + 1, 5)], k)
		var rb: Color = red_bands[posmod(bi, 6)].lerp(red_bands[posmod(bi + 1, 6)], k)
		g = g.lerp(gb.lerp(rb, sm(0.35, 0.65, dry)), steep)
	cl_steep = steep
	if h < WATER + 0.7:
		g = g.lerp(C["sand"], sm(WATER + 0.7, WATER + 0.2, h))
	if h < WATER:
		g = g.lerp(C["bed"], 0.6)
		cl_d = cl_d.lerp(C["bed"], 0.6)
	cl_g = g


## terrain.js colorLayers: cl_g = land, cl_d = trail dirt, cl_steep = rock-face weight; returns the dirt weight
func color_layers(x: float, z: float, h: float, ny: float) -> float:
	_cp_h = h
	var t := color_pre(x, z)
	color_post(x, z, h, ny, cp_dry, cp_rug, cp_cold, cp_ash)
	return t


## the two layers flattened (linear colour, like JS color())
func color(x: float, z: float, h: float, ny: float) -> Color:
	var t := color_layers(x, z, h, ny)
	var c := cl_g.lerp(cl_d, t)
	c.a = 1.0
	return c


# ======================================================================
# the course query (course.js query(), here so each thread has its own cache)
# ======================================================================
func _save_slot(arr: PackedFloat64Array) -> void:
	arr[0] = q_x; arr[1] = q_z; arr[2] = q_d; arr[3] = q_a; arr[4] = q_i; arr[5] = q_t; arr[6] = q_w
	arr[7] = q_kind; arr[8] = q_k; arr[9] = q_bt; arr[10] = q_s; arr[11] = q_rd; arr[12] = q_rk
	arr[13] = q_bench; arr[14] = q_mask


func _load_slot(arr: PackedFloat64Array) -> void:
	q_x = arr[0]; q_z = arr[1]; q_d = arr[2]; q_a = arr[3]; q_i = int(arr[4]); q_t = arr[5]; q_w = arr[6]
	q_kind = int(arr[7]); q_k = arr[8]; q_bt = arr[9]; q_s = arr[10]; q_rd = arr[11]; q_rk = arr[12]
	q_bench = arr[13]; q_mask = arr[14]


func query(x: float, z: float) -> void:
	if x == q_x and z == q_z:
		return
	if x == _qp[0] and z == _qp[1]:
		var tmp := PackedFloat64Array()
		tmp.resize(15)
		_save_slot(tmp)
		_load_slot(_qp)
		_qp = tmp
		return
	_save_slot(_qp)
	q_x = x; q_z = z
	q_d = INF; q_mask = 0.0
	var g0x := maxi(floori((x - QR) / CELL), c_gx0)
	var g1x := mini(floori((x + QR) / CELL), c_gx0 + c_gnx - 1)
	var g0z := maxi(floori((z - QR) / CELL), c_gz0)
	var g1z := mini(floori((z + QR) / CELL), c_gz0 + c_gnz - 1)
	if g1x < g0x or g1z < g0z:
		return
	_cand.resize(0)
	for gx in range(g0x, g1x + 1):
		var row := (gx - c_gx0) * c_gnz - c_gz0
		for gz in range(g0z, g1z + 1):
			var ci := row + gz
			for k in range(c_run_start[ci], c_run_start[ci + 1]):
				_cand.append(c_runs[k])
	if _cand.is_empty():
		return
	_cand.sort()
	var sw := 0.0
	var se := 0.0
	var sk := 0.0
	var sb := 0.0
	var leg_d := INF
	var leg_i := 0
	var leg_t := 0.0
	var prev := -9
	var skip_r := QR + 1.03   # segments are STEP = 2 m long: half length 1 (+ margin)
	for run in _cand:
		var i: int = run >> 8
		var i_end: int = i + (run & 0xFF)
		if i - prev > 2:
			if leg_d != INF:
				_q_close(leg_d, leg_i, leg_t, x, z)
			leg_d = INF
		while i <= i_end:
			var o := i * 6
			var mdx := x - c_seg[o + 3]
			var mdz := z - c_seg[o + 4]
			var m2 := mdx * mdx + mdz * mdz
			if m2 > c_seg[o + 5]:
				# provably > QR away: cannot change d, mask or the bench weights; nor can the next few
				# (each segment's midpoint is at most 2 m further along)
				var kk := floori((sqrt(m2) - skip_r) / 2.002)
				i += 1 + maxi(0, kk)
				continue
			var ax := cX[i]
			var az := cZ[i]
			var bx: float = c_seg[o]
			var bz: float = c_seg[o + 1]
			var t := ((x - ax) * bx + (z - az) * bz) / c_seg[o + 2]
			t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
			var ex := x - ax - bx * t
			var ez := z - az - bz * t
			var d2 := ex * ex + ez * ez
			var sd := sqrt(d2)
			var tt := (sd - (QR - 9)) / ((QR - 2) - (QR - 9))
			if tt < 1.0:
				tt = 0.0 if tt < 0.0 else tt
				var wt := (1.0 - tt * tt * (3.0 - 2.0 * tt)) / ((d2 + 1) * (d2 + 1))
				if wt > 0.0:
					sw += wt
					se += wt * (cE[i] + (cE[i + 1] - cE[i]) * t)
					sk += wt * (cKAP[i] + (cKAP[i + 1] - cKAP[i]) * t)
					sb += wt * (cBT[i] + (cBT[i + 1] - cBT[i]) * t)
			if d2 < leg_d:
				leg_d = d2; leg_i = i; leg_t = t
			i += 1
		prev = i_end
	if leg_d != INF:
		_q_close(leg_d, leg_i, leg_t, x, z)
	if q_d > QR:
		q_d = INF; q_mask = 0.0
		return
	if sw > 0.0:
		q_bench = se / sw
		q_k = sk / sw
		q_bt = sb / sw
	else:
		q_bench = cE[q_i] + (cE[q_i + 1] - cE[q_i]) * q_t


func _q_close(leg_d2: float, i: int, t: float, x: float, z: float) -> void:
	var ld := sqrt(leg_d2)
	var wl: float = cW[i] + (cW[i + 1] - cW[i]) * t
	var m := 1.0 - sm(wl + 1.5, wl + 8, ld)
	if m > q_mask:
		q_mask = m
	if ld < q_d:
		q_d = ld; q_i = i; q_t = t; q_w = wl
		var px := cX[i] + (cX[i + 1] - cX[i]) * t
		var pz := cZ[i] + (cZ[i + 1] - cZ[i]) * t
		var tx: float = cTX[i]
		var tz: float = cTZ[i]
		q_a = (-1.0 if -(x - px) * tz + (z - pz) * tx < 0.0 else 1.0) * ld
		q_kind = cKD[i if t < 0.5 else i + 1]
		q_k = cKAP[i] + (cKAP[i + 1] - cKAP[i]) * t
		q_bt = cBT[i] + (cBT[i + 1] - cBT[i]) * t
		q_s = (i + t) * CSTEP
		q_rd = cRD[i] + (cRD[i + 1] - cRD[i]) * t
		q_rk = cRK[i] + (cRK[i + 1] - cRK[i]) * t

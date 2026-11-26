class_name RockGen
extends RefCounted
## Procedural rocks by type (2026-11-26, user: "realistic rock shapes, different types depending on the biome, nice LODs").
##
## How (the usual recipe of rock generators, e.g. Houdini / World Creator / the "cut a sphere with planes" talks):
##  1. the BLOCK: a convex polyhedron = the intersection of N random half-spaces (joints / fracture planes). Along a
##     direction d the surface sits at the nearest plane, t_i = dist_i / (d . n_i); their p-norm soft minimum
##     (sum t_i^-p)^(-1/p) rounds the edges: p small = an old weathered boulder (spheroidal weathering), p large = a
##     fresh frost-shattered block with crisp arrises.
##  2. WEATHERING per rock type: sandstone gets bedding ledges + a wind-cut undercut + tafoni pits, granite rounded
##     lumps, frost-shattered (tundra) stone flat bedding slabs and fine sharp chips, basalt a hexagonal column cut
##     across by a tilted fracture + vesicle pits.
##  3. fractal noise along the normal (low amplitude: the planes give the silhouette, the noise the surface).
##  4. sunk base (the rock sits in the ground), normalised to the old rock's size so the colliders / domes still fit:
##     horizontal radius 1, top 0.9 (scaled per instance).
## Vertex colour = baked cavity AO (concave = darker, the foot darker): the scan texture (shaders/rock.gdshader) does
## the rest. The surface is a star-shaped function of direction, so every LOD is the same rock sampled on a finer /
## coarser icosphere: LOD0 near, LOD1 everywhere else and as the shadow caster (deco_fade modes 4 / 3).

const TYPES := ["granite", "desert", "tundra", "basalt"]
const VARIANTS := 2
const VER := 1   # the disk cache of the meshes
## icosphere subdivisions (three.js style: 20 (d+1)^2 triangles): LOD0 3380, LOD1 500, pebbles 320
const DETAIL := {0: 12, 1: 4, "pebble": 3}

static var _cache := {}


## list name of a rock of this type / variant ("rock_granite0"); pebbles: "pebble_granite"
static func list_name(type: String, variant: int) -> String:
	return "rock_%s%d" % [type, variant]


static func all_lists() -> Array:
	var out := []
	for t in TYPES:
		for v in VARIANTS:
			out.append(list_name(t, v))
		out.append("pebble_" + t)
	return out


## lod 0 / 1, or -1 = the pebble mesh
static func mesh(type: String, variant: int, lod: int) -> ArrayMesh:
	var key := "%s%d_%d" % [type, variant, lod]
	if _cache.has(key):
		return _cache[key]
	var d: int = DETAIL["pebble"] if lod < 0 else DETAIL[lod]
	# built once per machine (~0.6 s for all of them), then read back (user://cache/rocks): bump VER when shapes change
	var path := "user://cache/rocks/v%d_%s_d%d.res" % [VER, key, d]
	var m: ArrayMesh = null
	if FileAccess.file_exists(path):
		m = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if m == null:
		m = build(type, variant, d).to_mesh(true)
		DirAccess.make_dir_recursive_absolute("user://cache/rocks")
		ResourceSaver.save(m, path)
	_cache[key] = m
	return m


# ---------------- noise ----------------
static func _h3(x: float, y: float, z: float, sd: float) -> float:
	var nn := sin(x * 127.1 + y * 311.7 + z * 74.7 + sd * 13.1) * 43758.5453
	return nn - floorf(nn)


static func _vn(p: Vector3, sd: float) -> float:
	var xi := floorf(p.x); var yi := floorf(p.y); var zi := floorf(p.z)
	var xf := p.x - xi; var yf := p.y - yi; var zf := p.z - zi
	var u := xf * xf * (3 - 2 * xf); var w := yf * yf * (3 - 2 * yf); var t := zf * zf * (3 - 2 * zf)
	var a := lerpf(lerpf(_h3(xi, yi, zi, sd), _h3(xi + 1, yi, zi, sd), u), lerpf(_h3(xi, yi + 1, zi, sd), _h3(xi + 1, yi + 1, zi, sd), u), w)
	var b := lerpf(lerpf(_h3(xi, yi, zi + 1, sd), _h3(xi + 1, yi, zi + 1, sd), u), lerpf(_h3(xi, yi + 1, zi + 1, sd), _h3(xi + 1, yi + 1, zi + 1, sd), u), w)
	return lerpf(a, b, t) * 2.0 - 1.0   # -1..1


static func _fbm(p: Vector3, sd: float, oct: int) -> float:
	var s := 0.0; var a := 0.5; var q := p
	for i in oct:
		s += _vn(q, sd + i * 7.0) * a
		q = q * 2.03 + Vector3(1.7, -3.1, 2.3)
		a *= 0.5
	return s


## ridged: sharp creases (chipped / frost-split stone)
static func _ridged(p: Vector3, sd: float, oct: int) -> float:
	var s := 0.0; var a := 0.5; var q := p
	for i in oct:
		s += (1.0 - absf(_vn(q, sd + i * 5.0))) * a
		q = q * 2.1 + Vector3(-2.3, 1.1, 0.7)
		a *= 0.5
	return s


## cellular pits (tafoni in sandstone, vesicles in basalt): 0 in a pit's middle .. 1 outside it
static func _pits(p: Vector3, sd: float) -> float:
	var c := p.floor()
	var best := 9.0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var cc := c + Vector3(dx, dy, dz)
				var j := Vector3(_h3(cc.x, cc.y, cc.z, sd), _h3(cc.x, cc.y, cc.z, sd + 3.3), _h3(cc.x, cc.y, cc.z, sd + 6.1))
				var r := _h3(cc.x, cc.y, cc.z, sd + 9.7)
				var dd := (cc + j).distance_to(p) / (0.35 + 0.4 * r)
				best = minf(best, dd)
	return clampf(best, 0.0, 1.0)


# ---------------- the shape ----------------
class Spec:
	var planes: Array = []   # [Vector3 normal, float dist]
	var p := 6.0             # soft-min sharpness
	var aspect := Vector3.ONE
	var frame := Basis()     # the block's own axes (lying columns, tilted beds)
	var amp := 0.08          # fbm along the normal
	var freq := 1.3
	var fine := 0.02         # fine detail (ridged for sharp types)
	var ridged := false
	var strata := 0.0        # bedding ledges (sandstone, slate)
	var strata_f := 5.0
	var undercut := 0.0      # wind / water cut foot (desert)
	var pits := 0.0          # tafoni / vesicles
	var pit_f := 4.0
	var dents: Array = []    # [direction, cos of its radius, depth]: concave hollows / spalled flakes (no rock is convex)
	var seed := 0.0


static func _spec(type: String, variant: int) -> Spec:
	var s := Spec.new()
	s.seed = float(TYPES.find(type) * 17 + variant * 5 + 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.seed * 1000) + 77
	match type:
		"granite":   # rounded joint blocks, weathered on every edge (spheroidal weathering); green land, forests (moss)
			_random_planes(s, rng, 7 if variant == 0 else 8, 0.72, 1.0)
			s.p = 9.0 if variant == 0 else 12.0
			s.aspect = Vector3(1.2, 0.85, 0.95) if variant == 0 else Vector3(1.4, 0.72, 0.85)
			s.frame = Basis(Vector3(0.3, 1, -0.2).normalized(), rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			s.amp = 0.06; s.freq = 1.3; s.fine = 0.02
			_random_dents(s, rng, 3, 0.1)
		"desert":    # sandstone: flat-bedded, ledges, an undercut foot, honeycomb pits
			_random_planes(s, rng, 7, 0.82, 1.0)
			s.planes.append([Vector3.UP, 0.55 if variant == 0 else 0.4])   # the flat top of the bed
			s.p = 7.0
			s.aspect = Vector3(1.2, 0.8, 1.05) if variant == 0 else Vector3(1.35, 0.6, 1.2)
			s.amp = 0.05; s.freq = 1.1; s.fine = 0.012
			s.strata = 0.16; s.strata_f = 3.2 if variant == 0 else 4.2
			s.undercut = 0.2 if variant == 0 else 0.12
			s.pits = 0.05; s.pit_f = 3.0
			_random_dents(s, rng, 2, 0.07)
		"tundra":    # frost-shattered: angular slabs / blocks split along bedding, crisp arrises, lichen
			_random_planes(s, rng, 15 if variant == 0 else 12, 0.7, 1.0)
			if variant == 0:   # a slab: two near-parallel bedding planes
				var bn := Vector3(0.12, 1.0, -0.08).normalized()
				s.planes.append([bn, 0.42]); s.planes.append([-bn, 0.55])
			s.p = 26.0 if variant == 0 else 20.0
			s.aspect = Vector3(1.35, 0.75, 1.0) if variant == 0 else Vector3(1.0, 1.0, 0.85)
			s.amp = 0.025; s.freq = 1.8; s.fine = 0.03; s.ridged = true
			s.strata = 0.03; s.strata_f = 5.0
			_random_dents(s, rng, 2, 0.08)
		"basalt":    # columnar basalt: a hexagonal column cut across by a tilted fracture, vesicles
			var j := rng.randf() * TAU
			for k in 6:
				var a := j + k * TAU / 6.0
				s.planes.append([Vector3(cos(a), 0, sin(a)), 0.78 + rng.randf_range(-0.04, 0.04)])
			s.planes.append([Vector3(0.25, 1.0, 0.1).normalized(), 0.75])
			s.planes.append([Vector3(-0.2, -1.0, 0.15).normalized(), 0.8])
			for k in 3:   # a few chipped corners
				s.planes.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized(), 0.88])
			s.p = 24.0
			if variant == 1:   # a broken column lying on its side
				s.frame = Basis(Vector3(0, 0, 1), PI / 2 - 0.15)
				s.aspect = Vector3(1.0, 0.85, 0.9)
			else:
				s.aspect = Vector3(1.0, 1.05, 1.0)
			s.amp = 0.02; s.freq = 1.6; s.fine = 0.015; s.ridged = true
			s.pits = 0.03; s.pit_f = 9.0
	return s


## N fracture planes spread over the sphere (jittered Fibonacci), at random depths
static func _random_planes(s: Spec, rng: RandomNumberGenerator, n: int, dmin: float, dmax: float) -> void:
	var off := rng.randf()
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var a := TAU * (i * 0.618034 + off)
		var nn := Vector3(cos(a) * r, y, sin(a) * r)
		nn = (nn + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))).normalized()
		s.planes.append([nn, rng.randf_range(dmin, dmax)])


## spalled flakes / hollows: a few soft dents (sides more than the top)
static func _random_dents(s: Spec, rng: RandomNumberGenerator, n: int, depth: float) -> void:
	for i in n:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.7), rng.randf_range(-1, 1)).normalized()
		s.dents.append([d, cos(rng.randf_range(0.35, 0.7)), depth * rng.randf_range(0.6, 1.2)])


## the block's radius along direction d (in its own frame): soft minimum of the planes' distances
static func _block_r(s: Spec, d: Vector3) -> float:
	var acc := pow(1.4, -s.p)   # (a bounding sphere: no direction runs off to infinity)
	for pl in s.planes:
		var dn: float = d.dot(pl[0])
		if dn > 1e-3:
			acc += pow(float(pl[1]) / dn, -s.p)
	return pow(acc, -1.0 / s.p)


## one rock's surface point for a unit direction, and its cavity (-1 concave .. +1 convex)
static func _point(s: Spec, dir: Vector3) -> Array:
	var d := s.frame.inverse() * dir
	var r := _block_r(s, d)
	var p := s.frame * (d * r) * s.aspect
	var nrm := p.normalized()
	var q := p * s.freq
	var disp := _fbm(q, s.seed, 4) * s.amp
	if s.ridged:
		disp += (_ridged(q * 3.0, s.seed + 2.0, 3) - 0.6) * s.fine
	else:
		disp += _fbm(q * 4.5, s.seed + 2.0, 3) * s.fine
	if s.strata > 0.0:   # ledges: a sawtooth across the beds (soft step out, sharp step in), wavy beds
		var ph := p.y * s.strata_f + _fbm(p * 1.2, s.seed + 5.0, 2) * 0.8
		var saw := ph - floorf(ph)
		var side := 1.0 - absf(nrm.y)   # on the sides, not on the bed tops
		disp -= s.strata * pow(saw, 2.5) * side   # (recedes up each bed, then the next bed's lip sticks out)
	if s.undercut > 0.0:   # wind / sand cut the foot back
		disp -= s.undercut * smoothstep(0.15, -0.3, p.y) * (1.0 - absf(nrm.y) * 0.5) * (0.7 + 0.3 * _fbm(p * 2.0, s.seed + 8.0, 2))
	if s.pits > 0.0:
		var pv := 1.0 - _pits(p * s.pit_f, s.seed + 11.0)
		disp -= s.pits * pv * pv * (1.0 - smoothstep(0.6, 0.95, nrm.y))
	for dn in s.dents:
		var k := smoothstep(float(dn[1]), 1.0, dir.dot(dn[0]))
		disp -= float(dn[2]) * k * (2.0 - k)
	p += nrm * disp
	return [p, clampf(disp / maxf(s.amp + s.strata + s.undercut + s.pits, 0.02) * 1.5, -1.0, 1.0)]


static func build(type: String, variant: int, detail: int) -> GeoBuf:
	var s := _spec(type, variant)
	var g := GeoBuf.ico(1, detail)
	var memo := {}
	var cav := PackedFloat32Array()
	cav.resize(g.pos.size())
	for i in g.pos.size():
		var key := Vector3i(roundi(g.pos[i].x * 100000), roundi(g.pos[i].y * 100000), roundi(g.pos[i].z * 100000))
		if not memo.has(key):
			memo[key] = _point(s, g.pos[i].normalized())
		var pc: Array = memo[key]
		g.pos[i] = pc[0]
		cav[i] = pc[1]
	# the foot: squashed into the ground; then the old rock's size (horizontal radius 1, top 0.9)
	var lo := INF; var hi := -INF; var hr := 0.0
	for v in g.pos:
		lo = minf(lo, v.y); hi = maxf(hi, v.y)
	var foot := lerpf(lo, hi, 0.22)
	for i in g.pos.size():
		var v := g.pos[i]
		if v.y < foot:
			v.y = foot + (v.y - foot) * 0.2
		g.pos[i] = v
		hr = maxf(hr, Vector2(v.x, v.z).length())
	lo = INF; hi = -INF
	for v in g.pos:
		lo = minf(lo, v.y); hi = maxf(hi, v.y)
	var ys := 0.9 / maxf(hi, 0.05)
	var xs := 1.0 / maxf(hr, 0.05)
	for i in g.pos.size():
		var v := g.pos[i]
		g.pos[i] = Vector3(v.x * xs, v.y * ys, v.z * xs)
	# baked AO: cavities darker, the foot darker (ground contact)
	var bot := lo * ys
	for i in g.pos.size():
		var v := g.pos[i]
		var a := 0.82 + 0.18 * cav[i]
		a *= lerpf(0.55, 1.0, smoothstep(bot, bot + 0.45, v.y))
		g.col[i] = Color(a, a, a)
	return g

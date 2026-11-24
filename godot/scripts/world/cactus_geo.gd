class_name CactusGeo
extends RefCounted
## Procedural cacti: five kinds built from ribbed tubes swept along curved paths (an arm bends out of the
## trunk and up in one piece, no seams), spine clusters on every rib, flowers / fruit. Each kind also has a
## precomputed **Voronoi fracture** (built on a worker thread): the cactus solids are cut by the bisector
## planes between random seeds (denser low down, where a bike hits), each cut capped with pale flesh, so a
## smashed cactus breaks into real chunks that fit together. Spines / flowers ride with the chunk they sit on.
##
## Vertex colour: skin = shade (x the per-instance green), tint 1 = own colour (spines, flowers, flesh);
## the "cactus" material (deco.gdshader, tint_own) reads the tint from UV.x.

const KINDS := 5   # 0 saguaro, 1 tall saguaro, 2 barrel, 3 organ pipe, 4 prickly pear
const NAMES := ["saguaro", "saguaro tall", "barrel", "organ pipe", "prickly pear"]
const HIT_R := [0.19, 0.21, 0.3, 0.32, 0.4]     # collider radius (unscaled)
const HEIGHT := [2.05, 2.65, 0.62, 1.85, 1.05]   # top (unscaled)
const WEIGHT := [0.28, 0.14, 0.2, 0.16, 0.22]    # how often each kind grows
const CELLS := [17, 21, 8, 18, 15]               # Voronoi pieces per kind
const FLESH := Color(0.42, 0.52, 0.2)            # linear: cut faces
const DOWN := -0.15                              # bodies reach this far into the ground

static var MESHES: Array = []       # kind -> ArrayMesh (the whole cactus)
static var _frac: Array = []        # kind -> [{g, n, at, size, pts}] (worker thread)
static var _frac_meshes: Array = [] # kind -> [{mesh, at, size, pts}] (main thread, lazily)
static var _task := -1
static var fails := [0, 0]   # cap loops: broken chain, failed triangulation (probe stats)


static func lin(hex: int) -> Color:
	return TerrainField.lin(hex)


## pick a kind from a 0..1 random number
static func pick(r: float) -> int:
	var acc := 0.0
	for k in KINDS:
		acc += WEIGHT[k]
		if r < acc:
			return k
	return 0


static func ensure() -> void:
	if not MESHES.is_empty():
		return
	var datas := []
	for k in KINDS:
		var d := build(k)
		datas.append(d)
		MESHES.append(whole_mesh(d))
	_frac.resize(KINDS)
	_frac_meshes.resize(KINDS)
	_task = WorkerThreadPool.add_task(func(): _fracture_all(datas), false, "cactus fracture")


static func _fracture_all(datas: Array) -> void:
	for k in KINDS:
		_frac[k] = structured(datas[k], k)


## wait for the background fracture. Must run before the game quits: a task still cutting cacti while
## the engine tears down its scripts crashed every exit (access violation in ntdll)
static func join() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## the pieces of a smashed cactus of this kind: [{mesh, at, size, pts}] in the unscaled cactus space
## variant "arms": the arms / pads / pipes come off, the trunk stays in one piece; "half": the trunk (or each pipe) is
## also broken across. A piece flagged "stump" is the rooted lower part.
static func pieces(kind: int, variant := "arms") -> Array:
	join()
	if _frac_meshes[kind] == null:
		_frac_meshes[kind] = {}
	var cache: Dictionary = _frac_meshes[kind]
	if not cache.has(variant):
		var out := []
		for p in (_frac[kind] as Dictionary)[variant]:
			var g: GeoBuf = p["g"]
			out.append({"mesh": g.to_mesh(false, p["n"].duplicate()), "at": p["at"], "size": p["size"], "pts": p["pts"], "stump": p.get("stump", false)})
		cache[variant] = out
	return cache[variant]


## cactus tubes break like plant stems, not like rock: each arm (saguaro), pad (prickly pear) or pipe (organ pipe) is
## its own piece, snapped off where it meets the trunk and capped with flesh; the trunk is one piece ("arms") or is
## also broken across at `cut` ("half": the rooted lower part is the stump). Returns {"arms": [...], "half": [...]}
static func structured(d: Dictionary, kind: int) -> Dictionary:
	var bodies: Array = d["bodies"]
	var paths: Array = []
	for i in bodies.size():
		if kind == 4:
			paths.append(PackedVector3Array([(d["ellipsoids"][i] as Transform3D).origin]))
		else:
			paths.append(d["tubes"][i][0])
	var parts_a: Array = []   # [[GeoBuf, owner index, stump]]
	var parts_h: Array = []
	var cut_y := 1.0
	match kind:
		0: cut_y = 0.5
		1: cut_y = 0.65
		2: cut_y = 0.2
		3: cut_y = 0.8
	for i in bodies.size():
		var g: GeoBuf = bodies[i]
		var is_trunk := (kind == 0 or kind == 1) and i == 0
		if (kind == 0 or kind == 1) and i > 0:
			# the arm is snapped off at the trunk's skin: keep what is outside 0.9 of the trunk radius, capped
			var pa: PackedVector3Array = paths[i]
			var hd := Vector3(pa[1].x - pa[0].x, 0, pa[1].z - pa[0].z).normalized()
			var R := 0.2 if kind == 1 else 0.175
			g = clip(g, -hd, -R * 0.92)
			if g.pos.is_empty(): g = bodies[i]
			parts_a.append([g, i, false]); parts_h.append([g, i, false])
		elif is_trunk or kind == 2 or (kind == 3 and (i == 0 or i % 2 == 0)):
			parts_a.append([g, i, false])
			var lo := clip(g, Vector3.UP, cut_y + (0.12 * float(i % 3) if kind == 3 else 0.0))
			var hi := clip(g, Vector3.DOWN, -(cut_y + (0.12 * float(i % 3) if kind == 3 else 0.0)))
			if lo.pos.is_empty() or hi.pos.is_empty():
				parts_h.append([g, i, false])
			else:
				parts_h.append([lo, i, true]); parts_h.append([hi, i, false])
		else:
			parts_a.append([g, i, false]); parts_h.append([g, i, false])
	return {"arms": _build_pieces(d, paths, parts_a, cut_y), "half": _build_pieces(d, paths, parts_h, cut_y)}


## closest distance from p to a polyline (a single point = that point)
static func _path_dist(path: PackedVector3Array, p: Vector3) -> float:
	if path.size() == 1: return p.distance_to(path[0])
	var best := 1e9
	for i in path.size() - 1:
		var a := path[i]
		var ab := path[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


static func _build_pieces(d: Dictionary, paths: Array, parts: Array, cut_y: float) -> Array:
	var extra_owner: Array = []   # per extra: index into parts
	for e in d["extras"]:
		var at: Vector3 = e["at"]
		var best_owner := 0
		var bd := 1e9
		for i in paths.size():
			var dd := _path_dist(paths[i], at)
			if dd < bd: bd = dd; best_owner = i
		# among the parts of that body (a trunk cut in two), the one on the side of the extra
		var cand := []
		for pi in parts.size():
			if parts[pi][1] == best_owner: cand.append(pi)
		var pick: int = cand[0] if not cand.is_empty() else 0
		if cand.size() == 2:
			pick = cand[0] if at.y < cut_y + (0.12 * float(best_owner % 3) if d["bodies"].size() == 7 else 0.0) else cand[1]
		extra_owner.append(pick)
	var out := []
	for pi in parts.size():
		var piece: GeoBuf = (parts[pi][0] as GeoBuf).copy()
		var pts := PackedVector3Array()
		var seen := {}
		for p in piece.pos:
			var k := Vector3i(roundi(p.x * 200), roundi(p.y * 200), roundi(p.z * 200))
			if not seen.has(k):
				seen[k] = true; pts.append(p)
		if pts.is_empty(): continue
		var nbody := piece.pos.size()
		for ei in d["extras"].size():
			if extra_owner[ei] == pi: piece.append(d["extras"][ei]["g"].copy())
		var a := AABB(pts[0], Vector3.ZERO)
		for p in pts: a = a.expand(p)
		var c := a.get_center()
		piece.translate(-c.x, -c.y, -c.z)
		var stride := maxi(1, pts.size() / 48)
		var hull := PackedVector3Array()
		for k in range(0, pts.size(), stride):
			hull.append((pts[k] - c) * 0.9)
		out.append({"g": piece, "n": TerrainGeo._soft_normals(piece), "at": c, "size": a.size, "pts": hull, "nbody": nbody, "stump": parts[pi][2]})
	return out


static func whole_mesh(d: Dictionary) -> ArrayMesh:
	var body := GeoBuf.merge(d["bodies"])
	var nr := body.smooth_normals()
	var all := body.copy()
	for e in d["extras"]:
		all.append(e["g"])
		nr.append_array(e["g"].face_normals())
	return all.to_mesh(false, nr)


# ======================================================================
# building blocks
# ======================================================================
## a ribbed tube swept along `path` (radius per point), parallel-transport frames, closed: flat bottom,
## domed top (`dome` = dome height / radius). Ridge areoles every `step` m go into `areoles` as [pos, n, t].
static func tube(path: PackedVector3Array, rad: PackedFloat32Array, ribs: int, depth: float, dome: float,
		areoles: Array, step: float, phase: float = 0.0) -> GeoBuf:
	var n := path.size()
	var m := ribs * 2
	var t0 := (path[1] - path[0]).normalized()
	var ref := Vector3.FORWARD if absf(t0.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var u := t0.cross(ref).normalized()
	var rings := []
	var cens := PackedVector3Array()
	var s_arr := PackedFloat32Array()
	var s := 0.0
	var last_t := t0
	var last_v := Vector3.ZERO
	var last_u := u
	for i in n:
		var t: Vector3
		if i == 0: t = path[1] - path[0]
		elif i == n - 1: t = path[i] - path[i - 1]
		else: t = path[i + 1] - path[i - 1]
		t = t.normalized()
		u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		if i > 0: s += path[i].distance_to(path[i - 1])
		rings.append(_ring(path[i], u, v, rad[i], m, depth, phase))
		cens.append(path[i]); s_arr.append(s)
		last_t = t; last_v = v; last_u = u
	# dome: shrinking rings, the ribs run together at the tip
	var R := rad[n - 1]
	var top := path[n - 1]
	var DOME := 4
	if dome > 0.0:
		for q in range(1, DOME):
			var a := float(q) / DOME * PI * 0.5
			var c := top + last_t * R * dome * sin(a)
			rings.append(_ring(c, last_u, last_v, R * cos(a), m, depth * cos(a), phase))
			s += R * dome * (sin(a) - sin(float(q - 1) / DOME * PI * 0.5)) + R * 0.3
			cens.append(c); s_arr.append(s)
	var apex := top + last_t * R * dome
	var p := PackedVector3Array()
	var shade := PackedFloat32Array()
	for i in rings.size() - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for k in m:
			var k1 := (k + 1) % m
			p.append_array([r0[k], r0[k1], r1[k1], r0[k], r1[k1], r1[k]])
	var rb: PackedVector3Array = rings[0]
	for k in m:
		p.append_array([cens[0], rb[(k + 1) % m], rb[k]])
	var rt: PackedVector3Array = rings[rings.size() - 1]
	for k in m:
		p.append_array([apex, rt[k], rt[(k + 1) % m]])
	var g := GeoBuf.of(p)
	# ridges a little lighter, grooves darker (reads as ribs under any instance green)
	_shade_ribs(g, rings, m)
	# areoles along each ridge
	for r in ribs:
		var k := r * 2
		var sa := step * (0.3 + 0.5 * (r % 2))
		for i in rings.size() - 1:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i + 1][k]
			var seg := s_arr[i + 1] - s_arr[i]
			while sa <= s_arr[i + 1]:
				var f := clampf((sa - s_arr[i]) / maxf(seg, 1e-6), 0.0, 1.0)
				var ps := a.lerp(b, f)
				var cc := cens[i].lerp(cens[i + 1], f)
				if ps.y > 0.02:
					areoles.append([ps, (ps - cc).normalized(), (b - a).normalized()])
				sa += step
	return g


static func _ring(c: Vector3, u: Vector3, v: Vector3, r: float, m: int, depth: float, phase: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in m:
		var ang := float(k) / m * TAU + phase
		var rr := r * (1.0 if k % 2 == 0 else 1.0 - depth)
		out.append(c + (u * cos(ang) + v * sin(ang)) * rr)
	return out


static func _shade_ribs(g: GeoBuf, rings: Array, m: int) -> void:
	var ridge := {}
	for ring in rings:
		for k in range(0, m, 2):
			ridge[_key(ring[k])] = true
	for i in g.pos.size():
		g.col[i] = Color(1.0, 1.0, 0.97) if ridge.has(_key(g.pos[i])) else Color(0.7, 0.73, 0.68)


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 100000), roundi(p.y * 100000), roundi(p.z * 100000))


## spine clusters on areoles: `count` thin needles each, pointing out (+ spread)
static func spines(areoles: Array, count: int, length: float, spread: float, col: Color, rng: RandomNumberGenerator, out: Array) -> void:
	for a in areoles:
		var p: Vector3 = a[0]
		var nrm: Vector3 = a[1]
		var tg: Vector3 = a[2]
		var side := nrm.cross(tg)
		var g := GeoBuf.new()
		for k in count:
			var d := (nrm + tg * rng.randf_range(-spread, spread) + side * rng.randf_range(-spread, spread)).normalized()
			var L := length * rng.randf_range(0.6, 1.25)
			g.append(_needle(p - nrm * 0.006, d, L, 0.0035))
		# a little woolly pad where they come out
		g.append(_needle(p - nrm * 0.004, nrm, 0.008, 0.009))
		g.paint(col, 1.0)
		out.append({"g": g, "at": p - nrm * 0.02})


static func _needle(b: Vector3, d: Vector3, L: float, r: float) -> GeoBuf:
	var e1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := d.cross(e1)
	var bs := []
	for k in 3:
		var a := float(k) / 3.0 * TAU
		bs.append(b + (e1 * cos(a) + e2 * sin(a)) * r)
	var tip := b + d * L
	var p := PackedVector3Array()
	for k in 3:
		var b0: Vector3 = bs[k]
		var b1: Vector3 = bs[(k + 1) % 3]
		# outward: (b1 - b0) x (tip - b0)
		if (b1 - b0).cross(tip - b0).dot((b0 + b1) * 0.5 - b) >= 0.0:
			p.append_array([b0, b1, tip])
		else:
			p.append_array([b1, b0, tip])
	return GeoBuf.of(p)


## a small flower: a cup of petals + a yellow heart
static func flower(at: Vector3, up: Vector3, r: float, col: Color, rng: RandomNumberGenerator, out: Array) -> void:
	var e1 := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := up.cross(e1)
	var g := GeoBuf.new()
	var N := 7
	var base := at - up * 0.01
	for k in N:
		var a0 := (float(k) + rng.randf() * 0.2) / N * TAU
		var a1 := a0 + TAU / N * 1.1
		var am := (a0 + a1) * 0.5
		var tip := at + (e1 * cos(am) + e2 * sin(am)) * r + up * r * 0.55
		var p0 := at + (e1 * cos(a0) + e2 * sin(a0)) * r * 0.35 + up * r * 0.1
		var p1 := at + (e1 * cos(a1) + e2 * sin(a1)) * r * 0.35 + up * r * 0.1
		var t := GeoBuf.of(PackedVector3Array([base, p0, tip, base, tip, p1, p0, p1, tip]))
		t.paint(col, 1.0)
		g.append(t)
	var heart := GeoBuf.sphere(r * 0.28, 6, 4, 0, TAU, 0, PI)
	heart.translate(at.x + up.x * r * 0.2, at.y + up.y * r * 0.2, at.z + up.z * r * 0.2)
	heart.paint(lin(0xf2c230), 1.0)
	g.append(heart)
	out.append({"g": g, "at": at - up * 0.03})


## a smooth path through control points (Catmull-Rom), about `step` m apart
static func spline(ctrl: Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in ctrl.size() - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var nseg := maxi(1, ceili(p1.distance_to(p2) / step))
		for s in nseg:
			var t := float(s) / nseg
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out


## inside test shapes for the Voronoi seeds: tubes (path + radius) and ellipsoids (Transform3D of a unit sphere)
static func _inside(d: Dictionary, p: Vector3) -> bool:
	for tb in d["tubes"]:
		var path: PackedVector3Array = tb[0]
		var rad: PackedFloat32Array = tb[1]
		for i in path.size() - 1:
			var a := path[i]
			var ab := path[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			if p.distance_to(a + ab * t) < lerpf(rad[i], rad[i + 1], t) * 0.8:
				return true
	for e in d["ellipsoids"]:
		var xf: Transform3D = e
		if (xf.affine_inverse() * p).length() < 0.8:
			return true
	return false


# ======================================================================
# the five kinds
# ======================================================================
static func build(kind: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + kind * 131
	var d := {"bodies": [], "extras": [], "tubes": [], "ellipsoids": []}
	match kind:
		0, 1: _saguaro(d, kind == 1, rng)
		2: _barrel(d, rng)
		3: _organ(d, rng)
		4: _pear(d, rng)
	return d


static func _add_tube(d: Dictionary, path: PackedVector3Array, rad: PackedFloat32Array, ribs: int, depth: float, dome: float,
		step: float, spine_n: int, spine_len: float, spread: float, spine_col: Color, rng: RandomNumberGenerator) -> Array:
	var ar := []
	d["bodies"].append(tube(path, rad, ribs, depth, dome, ar, step, rng.randf() * TAU))
	d["tubes"].append([path, rad])
	spines(ar, spine_n, spine_len, spread, spine_col, rng, d["extras"])
	return ar


static func _saguaro(d: Dictionary, tall: bool, rng: RandomNumberGenerator) -> void:
	var H := 2.55 if tall else 1.95
	var R := 0.2 if tall else 0.175
	var lean := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
	var ctrl := [Vector3(0, DOWN, 0), Vector3(0, H * 0.35, 0) + lean * 0.3, Vector3(0, H * 0.7, 0) + lean * 0.7, Vector3(0, H, 0) + lean]
	var path := spline(ctrl, 0.15)
	var rad := PackedFloat32Array()
	for p in path:
		var h := clampf((p.y - DOWN) / (H - DOWN), 0, 1)
		rad.append(R * (1.06 - 0.12 * h + 0.03 * sin(h * 9.0)))
	var sc := lin(0xe6dcb8)
	_add_tube(d, path, rad, 14, 0.1, 0.85, 0.14, 2, 0.05, 0.55, sc, rng)
	# arms: out of the trunk, a round bend, then up -- one swept tube, so the bend is all one piece
	var arms := [[0.3, 0.85, 0.3, 0.62, 0.115], [0.3 + PI + 0.25, 1.12, 0.26, 0.5, 0.105]]
	if tall:
		arms = [[0.2, 1.0, 0.32, 0.85, 0.13], [0.2 + 2.35, 1.38, 0.28, 0.72, 0.12], [0.2 + 4.3, 1.7, 0.24, 0.48, 0.105]]
	var tips := [Vector3(0, H, 0) + lean]
	for a in arms:
		var phi: float = a[0]
		var y0: float = a[1]
		var out: float = a[2]
		var up: float = a[3]
		var r: float = a[4]
		var hd := Vector3(cos(phi), 0, sin(phi))
		var bend := 0.13
		var pts := [Vector3(0, y0 - 0.04, 0), hd * (out * 0.45) + Vector3(0, y0, 0), hd * (out - bend * 0.3) + Vector3(0, y0 + bend * 0.25, 0),
			hd * out + Vector3(0, y0 + bend, 0), hd * (out + 0.03) + Vector3(0, y0 + bend + up * 0.5, 0), hd * (out + 0.01) + Vector3(0, y0 + bend + up, 0)]
		var ap := spline(pts, 0.09)
		var ar := PackedFloat32Array()
		var acc := 0.0
		for i in ap.size():
			if i > 0: acc += ap[i].distance_to(ap[i - 1])
			# a flare where it grows out of the trunk
			ar.append(r * (1.0 + 0.35 * exp(-acc / 0.12)))
		_add_tube(d, ap, ar, 11, 0.1, 0.85, 0.13, 2, 0.045, 0.55, sc, rng)
		tips.append(ap[ap.size() - 1])
	if tall:   # white saguaro blossoms on the tips
		for t in tips:
			for k in 3:
				var ang := rng.randf() * TAU
				var o := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.02, 0.09)
				flower(t + o + Vector3(0, 0.1, 0), (Vector3(0, 1, 0) + o * 3.0).normalized(), 0.05, lin(0xfaf6ea), rng, d["extras"])


static func _barrel(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var H := 0.5
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	for i in 10:
		var y := lerpf(DOWN + 0.05, H, float(i) / 9.0)
		path.append(Vector3(0, y, 0))
		var h := (y - DOWN) / (H - DOWN)
		rad.append(0.3 * (0.72 + 0.38 * sin(PI * clampf(h * 0.9 + 0.12, 0, 1))))
	_add_tube(d, path, rad, 18, 0.14, 0.45, 0.085, 3, 0.08, 0.8, lin(0xd99a5c), rng)
	# a crown of yellow-orange flowers
	for k in 8:
		var a := float(k) / 8.0 * TAU + rng.randf() * 0.3
		var o := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.06, 0.11)
		flower(Vector3(0, H + 0.075, 0) + o, (Vector3(0, 1, 0) + o * 2.5).normalized(), 0.045, lin(0xf6a21c) if k % 3 else lin(0xe8462a), rng, d["extras"])


static func _organ(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var N := 7
	for i in N:
		var phi := float(i) / N * TAU + rng.randf_range(-0.3, 0.3)
		var ro := rng.randf_range(0.12, 0.3) if i > 0 else 0.02
		var h := rng.randf_range(1.0, 1.8) if i > 0 else 1.85
		var hd := Vector3(cos(phi), 0, sin(phi))
		var w := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		var pts := [hd * 0.03 + Vector3(0, DOWN, 0), hd * ro * 0.75 + Vector3(0, 0.08, 0), hd * ro + Vector3(0, 0.32, 0),
			hd * (ro + 0.03) + w + Vector3(0, h * 0.65, 0), hd * (ro + 0.04) + w * 1.5 + Vector3(0, h, 0)]
		var path := spline(pts, 0.17)
		var rad := PackedFloat32Array()
		var r := rng.randf_range(0.075, 0.095)
		for p in path:
			rad.append(r * (1.12 - 0.12 * clampf(p.y / h, 0, 1)))
		_add_tube(d, path, rad, 8, 0.12, 0.8, 0.13, 2, 0.04, 0.6, lin(0x9c8c6c), rng)
		if rng.randf() < 0.4:
			flower(path[path.size() - 1] + Vector3(0, r * 0.75, 0), Vector3.UP, 0.04, lin(0xe8a0c8), rng, d["extras"])


static func _pear(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var sc := lin(0xefe2a8)
	var stack := [[Vector3(0, DOWN + 0.02, 0), Vector3.UP, 0, rng.randf() * TAU]]
	var n := 0
	while not stack.is_empty() and n < 9:
		var it: Array = stack.pop_front()
		var base: Vector3 = it[0]
		var up: Vector3 = it[1]
		var depth: int = it[2]
		var yaw: float = it[3]
		var w := rng.randf_range(0.15, 0.2) * (1.0 - depth * 0.12)
		var hh := w * rng.randf_range(1.15, 1.35)
		var th := 0.035
		# pad frame: up = its long axis, face normal from the yaw
		var fn := Vector3(cos(yaw), 0, sin(yaw))
		fn = (fn - up * fn.dot(up)).normalized()
		var side := up.cross(fn)
		var cen := base + up * hh * 0.85
		var xf := Transform3D(Basis(side * w, up * hh, fn * th), cen)
		var g := GeoBuf.sphere(1.0, 14, 10, 0, TAU, 0, PI)
		for i in g.pos.size():
			g.pos[i] = xf * g.pos[i]
		g.col.fill(Color(0.95, 0.97, 0.92))
		d["bodies"].append(g)
		d["ellipsoids"].append(xf)
		n += 1
		# areoles in a diamond grid on both faces, one or two needles each
		var ar := []
		for gy in range(-4, 5):
			for gx in range(-3, 4):
				var lx := (gx + (0.5 if gy % 2 else 0.0)) * 0.32
				var ly := gy * 0.25
				if lx * lx + ly * ly > 0.72: continue
				for sgn in [-1.0, 1.0]:
					var lz: float = sgn * sqrt(maxf(0.0, 1.0 - lx * lx - ly * ly))
					var lp := Vector3(lx, ly, lz)
					var wp := xf * lp
					var nn := (xf.basis.inverse().transposed() * lp).normalized()
					if wp.y > 0.03: ar.append([wp, nn, up])
		spines(ar, 1, 0.035, 0.5, sc, rng, d["extras"])
		# fruit on the top edge of outer pads
		if depth >= 1 and rng.randf() < 0.7:
			for k in rng.randi_range(1, 3):
				var a := rng.randf_range(-0.9, 0.9)
				var fp := cen + (up * cos(a) * hh + side * sin(a) * w) * 0.98
				var fr := GeoBuf.sphere(1.0, 7, 5, 0, TAU, 0, PI)
				var fx := Transform3D(Basis(side * 0.028, (up * cos(a) + side * sin(a)) * 0.042, fn * 0.028), fp)
				for i in fr.pos.size():
					fr.pos[i] = fx * fr.pos[i]
				fr.paint(lin(0xa8164a), 1.0)
				d["extras"].append({"g": fr, "at": fp - up * 0.03})
		# children out of the upper rim
		if depth < 2:
			var kids := 2 if depth == 0 else rng.randi_range(1, 2)
			for k in kids:
				var a := rng.randf_range(-0.85, 0.85) + (0.5 * (k * 2 - 1) if kids == 2 else 0.0)
				var rim := cen + (up * cos(a) * hh + side * sin(a) * w) * 0.8
				var nup := (up * cos(a * 0.8) + side * sin(a * 0.8) + Vector3(0, 0.35, 0)).normalized()
				stack.append([rim - nup * 0.04, nup, depth + 1, yaw + rng.randf_range(-0.8, 0.8)])


# ======================================================================
# Voronoi fracture
# ======================================================================
## cut `d`'s solids into `cells` Voronoi pieces. Returns [{g (centred), n (normals), at, size, pts (hull points)}]
static func fracture(d: Dictionary, cells: int, seed: int, kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bodies: Array = d["bodies"]
	var box := AABB(bodies[0].pos[0], Vector3.ZERO)
	for b in bodies:
		for p in b.pos:
			box = box.expand(p)
	# seeds inside the cactus, denser where a bike hits (0.2 .. 1.1 m), not too close together
	var seeds := PackedVector3Array()
	var dmin := pow(box.size.x * box.size.y * box.size.z / cells, 1.0 / 3.0) * 0.55
	var tries := 0
	while seeds.size() < cells and tries < 40000:
		tries += 1
		var p := box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size
		var wgt := 0.35 + 0.65 * exp(-pow((p.y - 0.6) / 0.5, 2.0))
		if kind == 2 or kind == 4: wgt = 1.0
		if p.y < 0.03 or rng.randf() > wgt or not _inside(d, p):
			continue
		var ok := true
		for s in seeds:
			if s.distance_to(p) < dmin * (1.0 - tries / 40000.0):
				ok = false; break
		if ok: seeds.append(p)
	var out := []
	for i in seeds.size():
		var si := seeds[i]
		var order := []
		for j in seeds.size():
			if j != i: order.append([si.distance_squared_to(seeds[j]), j])
		order.sort_custom(func(a, b): return a[0] < b[0])
		var piece := GeoBuf.new()
		for b in bodies:
			var g: GeoBuf = b
			for o in order:
				var sj := seeds[o[1]]
				var nrm := (sj - si).normalized()
				g = clip(g, nrm, nrm.dot((si + sj) * 0.5))
				if g.pos.is_empty(): break
			if not g.pos.is_empty(): piece.append(g)
		if piece.pos.is_empty():
			continue
		# hull points: the solid part only
		var pts := PackedVector3Array()
		var seen := {}
		for p in piece.pos:
			var k := Vector3i(roundi(p.x * 200), roundi(p.y * 200), roundi(p.z * 200))
			if not seen.has(k):
				seen[k] = true; pts.append(p)
		var nbody := piece.pos.size()
		for e in d["extras"]:
			var at: Vector3 = e["at"]
			var best := 0
			var bd := 1e9
			for j in seeds.size():
				var dd := at.distance_squared_to(seeds[j])
				if dd < bd: bd = dd; best = j
			if best == i: piece.append(e["g"].copy())
		var a := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			a = a.expand(p)
		var c := a.get_center()
		piece.translate(-c.x, -c.y, -c.z)
		var stride := maxi(1, pts.size() / 48)
		var hull := PackedVector3Array()
		for k in range(0, pts.size(), stride):
			hull.append((pts[k] - c) * 0.9)
		# normals: smooth skin, flat cut faces, flat spines
		var nr := TerrainGeo._soft_normals(piece)
		out.append({"g": piece, "n": nr, "at": c, "size": a.size, "pts": hull, "nbody": nbody})
	return out


## keep the part of the closed mesh `g` where dot(p, n) < d; the cut is capped (flesh colour)
static func clip(g: GeoBuf, n: Vector3, d: float) -> GeoBuf:
	var cnt := g.pos.size()
	var sd := PackedFloat32Array()
	sd.resize(cnt)
	var any_out := false
	var any_in := false
	for i in cnt:
		var s := g.pos[i].dot(n) - d
		if absf(s) < 1e-7: s = 1e-7
		sd[i] = s
		if s > 0.0: any_out = true
		else: any_in = true
	if not any_out:
		return g
	var o := GeoBuf.new()
	if not any_in:
		return o
	var segs := {}   # entry key -> [exit key, entry point]
	var pts := {}
	for i in range(0, cnt, 3):
		var s0 := sd[i]; var s1 := sd[i + 1]; var s2 := sd[i + 2]
		if s0 <= 0.0 and s1 <= 0.0 and s2 <= 0.0:
			o.pos.append_array([g.pos[i], g.pos[i + 1], g.pos[i + 2]])
			o.col.append_array([g.col[i], g.col[i + 1], g.col[i + 2]])
			o.tint.append_array([g.tint[i], g.tint[i + 1], g.tint[i + 2]])
			continue
		if s0 > 0.0 and s1 > 0.0 and s2 > 0.0:
			continue
		var poly := []   # [pos, col, tint]
		var entry = null
		var exit = null
		for k in 3:
			var a := i + k
			var b := i + (k + 1) % 3
			var sa := sd[a]; var sb := sd[b]
			if sa <= 0.0:
				poly.append([g.pos[a], g.col[a], g.tint[a]])
			if (sa <= 0.0) != (sb <= 0.0):
				var x := _cut(g.pos[a], g.pos[b], sa, sb)
				var t := sa / (sa - sb)
				poly.append([x, g.col[a].lerp(g.col[b], t), lerpf(g.tint[a], g.tint[b], t)])
				if sa <= 0.0: exit = x
				else: entry = x
		for k in range(1, poly.size() - 1):
			for e in [poly[0], poly[k], poly[k + 1]]:
				o.pos.append(e[0]); o.col.append(e[1]); o.tint.append(e[2])
		if entry != null and exit != null:
			var ke := _key(entry)
			var kx := _key(exit)
			if ke != kx:
				segs[kx] = ke   # the cap runs exit -> entry... reversed below by the normal check
				pts[kx] = exit
				pts[ke] = entry
	# chain the cut segments into loops and cap them
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	while not segs.is_empty():
		var k0 = segs.keys()[0]
		var loop := PackedVector3Array()
		var k = k0
		var ok := false
		for guard in 100000:
			loop.append(pts[k])
			var nx = segs.get(k)
			segs.erase(k)
			if nx == null: break
			if nx == k0:
				ok = true; break
			k = nx
		if not ok or loop.size() < 3:
			if loop.size() >= 3: fails[0] += 1
			continue
		var p2 := PackedVector2Array()
		for p in loop:
			p2.append(Vector2(p.dot(u), p.dot(v)))
		var tri := Geometry2D.triangulate_polygon(p2)
		if tri.is_empty(): fails[1] += 1
		for t in range(0, tri.size(), 3):
			var a := loop[tri[t]]; var b := loop[tri[t + 1]]; var c := loop[tri[t + 2]]
			if (b - a).cross(c - a).dot(n) < 0.0:
				var tmp := b; b = c; c = tmp
			o.pos.append_array([a, b, c])
			o.col.append_array([FLESH, FLESH, FLESH])
			o.tint.append_array([1.0, 1.0, 1.0])
	return o


## the edge / plane crossing, computed the same way from either triangle sharing the edge
static func _cut(a: Vector3, b: Vector3, sa: float, sb: float) -> Vector3:
	if a.x > b.x or (a.x == b.x and (a.y > b.y or (a.y == b.y and a.z > b.z))):
		var tp := a; a = b; b = tp
		var ts := sa; sa = sb; sb = ts
	return a + (b - a) * (sa / (sa - sb))

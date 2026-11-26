class_name GrownTree
extends RefCounted
## Meshes of a grown tree (TreeGrower: the user's tree app's growth logic) for the streamed forest (CardTree's LODs).
## Each species is grown once (fixed seed) and NORMALISED: root at the origin, top at y = 1, so one instance scale
## (H x k, H, H x k) makes any real-size tree (CardTree.dims). Meshes:
##   cards0 / cards1  the foliage: pine = needle tufts (needle_tuft.png fans) at every twig / along every branch;
##                    leafy = leaf-cluster cards (the seamless beech / leaf patch, deco_cards tile_m) at every twig tip /
##                    along every limb. COLOR.a = a card's size (normalised: x the instance scale = metres)
##   wood0 / wood1    bark tubes along the skeleton's chains: LOD0 the trunk + every branch that carries wood (pine: the
##                    main branches, leafy: limbs + their branches), LOD1 trunk + main limbs; the trunk foot spreads into
##                    buttress roots. UV.x round in whole tiles, UV.y = normalised length (deco bark_uv x the scale = m)
##   proxy            the sun-shadow caster: trunk + a solid blob per main limb (shadows only, dappled)
## info(kind): {"width": crown width / height, "rt": trunk radius above the flare / height, "cb": lowest foliage / height}

const SEEDS := {"pine": 1979, "leafy": 4242}
static var _g := {}
static var _info := {}
static var _mesh := {}


static func grown(kind: String) -> TreeGrower:
	if not _g.has(kind):
		var g := TreeGrower.grow(kind, SEEDS[kind])
		_g[kind] = g
		var top := 0.0
		var w := 0.0
		var cb := INF
		for i in g.pos.size():
			if g.pruned[i] == 1: continue
			top = maxf(top, g.pos[i].y)
			w = maxf(w, Vector2(g.pos[i].x, g.pos[i].z).length())
			if g.level[i] >= 0: cb = minf(cb, g.pos[i].y)
		var rt := g.radius[0]
		for i in g.pos.size():
			if g.level[i] < 0 and g.pos[i].y > top * 0.08:
				rt = g.radius[i]
				break
		_info[kind] = {"top": top, "width": 2.0 * w / top, "rt": rt / top, "cb": cb / top}
	return _g[kind]


static func info(kind: String) -> Dictionary:
	grown(kind)
	return _info[kind]


static func mesh(name: String) -> ArrayMesh:
	if _mesh.has(name):
		return _mesh[name]
	var kind := "pine" if name.begins_with("pine") else "leafy"
	var g := grown(kind)
	var m: ArrayMesh
	match name.trim_prefix(kind):
		"Cards0": m = _cards(g, kind, 0)
		"Cards1": m = _cards(g, kind, 1)
		"Wood0": m = _wood(g, kind, 0)
		"Wood1": m = _wood(g, kind, 1)
		"Proxy": m = _proxy(g, kind)
	_mesh[name] = m
	return m


## a chain's live nodes (stops at the first pruned one)
static func _live(g: TreeGrower, ch: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in ch.size():
		if k > 0 and g.pruned[ch[k]] == 1:
			break
		out.append(ch[k])
	return out


## the point t (0..1 by node count) along a chain, and its direction there
static func _along(g: TreeGrower, ch: PackedInt32Array, t: float) -> Array:
	var f := t * (ch.size() - 1)
	var k := clampi(int(floor(f)), 0, ch.size() - 2)
	var a := g.pos[ch[k]]
	var b := g.pos[ch[k + 1]]
	return [a.lerp(b, f - k), (b - a).normalized()]


# ---------------------------------------------------------------- foliage
static func _cards(g: TreeGrower, kind: String, lod: int) -> ArrayMesh:
	var b := CardTree._Buf.new()
	var s := 1.0 / float(_info[kind].top)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + lod
	var deepest: int = g.sp.levels.size() - 1
	for ci in g.chains.size():
		var lv: int = g.chain_level[ci]
		var ch := _live(g, g.chains[ci])
		if ch.size() < 2:
			continue
		var ln: float = g.chain_len[ci] * float(ch.size() - 1) / float(g.chains[ci].size() - 1)
		if kind == "pine":
			if lod == 0 and lv == deepest:     # a tuft on every twig: at its tip and half way
				for t in [1.0, 0.5]:
					var at: Array = _along(g, ch, t)
					var size := clampf(ln * 1.0, 0.4, 0.9)
					_tuft(b, at[0] * s, at[1], size * s, rng)
			elif lod == 1 and lv == 0:         # LOD1: bigger tufts along the main branches
				for t in [1.0, 0.7, 0.45]:
					var at: Array = _along(g, ch, t)
					var size := clampf(ln * 0.55, 0.8, 2.4)
					_tuft(b, at[0] * s, at[1], size * s, rng)
		else:
			if lod == 0 and lv == deepest:     # a leaf cluster at every twig
				var at: Array = _along(g, ch, 0.75)
				var size := clampf(ln * 1.7, 0.8, 1.8)
				_cluster(b, at[0] * s, size * s, rng)
			elif lod == 1 and lv == deepest - 1:   # LOD1: bigger clusters along the limbs' branches
				for t in [1.0, 0.55]:
					var at: Array = _along(g, ch, t)
					var size := clampf(ln * 0.9, 1.4, 3.2)
					_cluster(b, at[0] * s, size * s, rng)
	return b.commit()


## light the foliage as one volume: out from the trunk axis, a little up
static func _vol_normal(p: Vector3, cn: Vector3) -> Vector3:
	var radial := Vector3(p.x, 0, p.z)
	var rl := radial.length()
	return (radial / maxf(rl, 0.0001) * 0.6 + Vector3(0, 0.5, 0) + cn * 0.2).normalized()


static func _ao(p: Vector3) -> float:
	return 0.6 + 0.4 * clampf(Vector2(p.x, p.z).length() * 4.0, 0.0, 1.0)


## a needle tuft: the fan laid along `fwd` (its root at u ~ 0.1), one card lying flat-ish, one upright
static func _tuft(b, at: Vector3, fwd: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	b.set_anchor(at)
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.2: side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(fwd).normalized()
	var roll := rng.randf_range(-0.45, 0.45)
	var flat := (side * cos(roll) + up * sin(roll)).normalized()
	for across in [flat, up]:
		var p0 := at - fwd * size * 0.1
		var p1 := at + fwd * size * 0.9
		var h: Vector3 = across * size * 0.5
		var corners := [p0 - h, p1 - h, p1 + h, p0 + h]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var cn: Vector3 = fwd.cross(across).normalized()
		for e in [0, 2, 1, 0, 3, 2]:
			b.vert(corners[e], _vol_normal(corners[e], cn), _ao(corners[e]), uvs[e], size)


## a leaf cluster: a folded card standing at `at`, facing out from the trunk (turned a little at random)
static func _cluster(b, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	b.set_anchor(at)
	var out := Vector3(at.x, 0, at.z)
	if out.length() < 0.001: out = Vector3(1, 0, 0)
	out = out.normalized().rotated(Vector3.UP, rng.randf_range(-0.9, 0.9))
	var u2 := Vector3.UP.cross(out).normalized()
	var tilt := rng.randf_range(-0.35, 0.35)
	var v2 := (Vector3.UP * cos(tilt) + out * sin(tilt)).normalized()
	var fold := out * size * 0.1
	var vt := []
	for ry in 2:
		var row := []
		for cx in 3:
			row.append(at + u2 * (cx - 1) * 0.5 * size + v2 * (ry - 0.5) * size + fold * (1.0 - absf(cx - 1)))
		vt.append(row)
	for cx in 2:
		for tri in [[Vector2i(cx, 0), Vector2i(cx + 1, 0), Vector2i(cx + 1, 1)], [Vector2i(cx, 0), Vector2i(cx + 1, 1), Vector2i(cx, 1)]]:
			for e in [tri[0], tri[2], tri[1]]:
				var q: Vector3 = vt[e.y][e.x]
				b.vert(q, _vol_normal(q, out), _ao(q), Vector2(e.x * 0.5, 1.0 - e.y), size)


# ---------------------------------------------------------------- wood
## which levels carry wood per LOD, and their tube sides
static func _wood_levels(kind: String, lod: int) -> Dictionary:
	if kind == "pine":
		return {-1: 8, 0: 4, 1: 3} if lod == 0 else {-1: 6, 0: 3}
	return {-1: 8, 0: 5, 1: 3} if lod == 0 else {-1: 6, 0: 3}


static func _wood(g: TreeGrower, kind: String, lod: int) -> ArrayMesh:
	var b := CardTree._Buf.new()
	var s := 1.0 / float(_info[kind].top)
	var lv_sides := _wood_levels(kind, lod)
	var h0: float = _info[kind].top
	for ci in g.chains.size():
		var lv: int = g.chain_level[ci]
		if not lv_sides.has(lv):
			continue
		var ch := _live(g, g.chains[ci])
		if ch.size() < 2:
			continue
		var pts := []
		var radii := []
		for k in ch.size():
			var n: int = ch[k]
			pts.append(g.pos[n] * s)
			# (a branch's first ring sits inside its parent, at the branch's own base radius)
			radii.append((g.radius[ch[1]] if k == 0 and lv >= 0 else g.radius[n]) * s)
			if lv < 0 and k == 0 and ch.size() > 1:
				# the trunk's foot: extra rings low down (0.15 m, 0.5 m) so the root flare is short and curved, not a cone
				var a: Vector3 = g.pos[ch[0]]
				var b2: Vector3 = g.pos[ch[1]]
				for hm in [0.15, 0.5]:
					var t: float = float(hm) / maxf(b2.y - a.y, 0.01)
					if t < 0.9:
						pts.append(a.lerp(b2, t) * s)
						radii.append(lerpf(g.radius[ch[0]], g.radius[ch[1]], t) * s * (1.0 + 0.25 * (1.0 - float(hm))))
		_tube(b, pts, radii, int(lv_sides[lv]), lv < 0, h0)
	return b.commit()


## a tube along pts (bark: u round it in whole tiles of 0.8 m at the tree's grown size, v = normalised length); the trunk's
## lowest rings spread into buttress roots (CardTree.ROOT_LOBES)
static func _tube(b, pts: Array, radii: Array, sides: int, trunk: bool, h0: float) -> void:
	var rings := []
	var v := 0.0
	var vs := []
	var u_tiles := maxf(1.0, round(TAU * float(radii[0]) * h0 / 0.8))
	for i in pts.size():
		if i > 0: v += (pts[i] - pts[i - 1]).length()
		vs.append(v)
		var d: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var a := Vector3.RIGHT if absf(d.dot(Vector3.UP)) > 0.9 else Vector3.UP
		var u := d.cross(a).normalized()
		var w := d.cross(u)
		var ring := []
		for k in sides + 1:
			var th := TAU * k / sides
			var n := u * cos(th) + w * sin(th)
			var r: float = radii[i]
			if trunk and i < 3:   # buttress roots: lobes spreading at the ground
				var f: float = [0.45, 0.14, 0.0][i]
				var lobe := pow(maxf(0.0, cos(CardTree.ROOT_LOBES * th + 0.7)), 2.5)
				r *= 1.0 + f * (0.5 + 1.6 * lobe)
			ring.append([pts[i] + n * r, n])
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			for e in [[i, k], [i + 1, k + 1], [i + 1, k], [i, k], [i, k + 1], [i + 1, k + 1]]:
				var q: Array = rings[e[0]][e[1]]
				var ao := 0.75 + 0.25 * clampf(float(e[0]) / 3.0, 0.0, 1.0) if trunk else 0.85
				b.vert(q[0], q[1], ao, Vector2(float(e[1]) / sides * u_tiles, vs[e[0]]))


# ---------------------------------------------------------------- shadow stand-in
static func _proxy(g: TreeGrower, kind: String) -> ArrayMesh:
	var b := CardTree._Buf.new()
	var s := 1.0 / float(_info[kind].top)
	var trunk := _live(g, g.chains[0])
	var pts := []
	var radii := []
	for n in trunk:
		pts.append(g.pos[n] * s)
		radii.append(g.radius[n] * s)
	_tube(b, pts, radii, 5, false, 1.0)
	for ci in g.chains.size():
		if g.chain_level[ci] != 0:
			continue
		var ch := _live(g, g.chains[ci])
		if ch.size() < 2:
			continue
		var ln: float = g.chain_len[ci]
		var at: Array = _along(g, ch, 0.7 if kind == "pine" else 0.75)
		var r := ln * (0.35 if kind == "pine" else 0.5) * s
		_blob(b, at[0] * s, Vector3(r, r * 0.6, r))
	return b.commit()


## an octahedron (a cheap solid blob)
static func _blob(b, c: Vector3, r: Vector3) -> void:
	var px := c + Vector3(r.x, 0, 0); var nx := c - Vector3(r.x, 0, 0)
	var py := c + Vector3(0, r.y, 0); var ny := c - Vector3(0, r.y, 0)
	var pz := c + Vector3(0, 0, r.z); var nz := c - Vector3(0, 0, r.z)
	for f in [[py, px, pz], [py, pz, nx], [py, nx, nz], [py, nz, px], [ny, pz, px], [ny, nx, pz], [ny, nz, nx], [ny, px, nz]]:
		var n: Vector3 = (f[1] - f[0]).cross(f[2] - f[0]).normalized()
		for p in [f[0], f[2], f[1]]:
			b.vert(p, n, 1.0, Vector2.ZERO)

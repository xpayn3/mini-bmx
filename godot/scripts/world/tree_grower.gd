class_name TreeGrower
extends RefCounted
## Tree skeletons grown the way the user's own tree app grows them (Downloads/webgpu-tree, growth-engine.js
## buildTree: Weber-Penn style; ported 2026-11-26, user: "we did this app, take its logic for trees"):
## a trunk walk, then LEVELS of child branches spawned along their parent (count, angle, roll by phyllotaxis, length
## ratio x crown-shape x apical dominance), each walked in kink steps with noise distortion, kinks, curve modes and
## phototropism; Weber-Penn top-down radii (chain base = parent radius x radiusRatio, (1 - t)^taperExp to the tip),
## root flare, cumulative gravity sag, and for conifers the prune ellipsoid that makes the cone.
## Simplified for a streamed forest (see CardTree): fewer kink steps, no competition / wobble / forks, our own seeded RNG
## (not bit-identical to the app). Output in metres, y up, root at the origin:
##   pos, parent (-1 root), level (-1 trunk, 0.. branch levels), bt (0..1 along its own branch), radius, pruned
##   chains: Array of PackedInt32Array, one polyline of node indices per branch (its first index = the node it grows from)

const GOLDEN := 2.39996   # 137.5 deg
const BRANCH_BASE_LEN := 9.0   # growth-engine.js L1911: level-0 parent length (not tied to the trunk height)

## the species we grow (values from the app's schema.js presets, levels trimmed for the game)
const SPECIES := {
	# schema.js "Pine" / "ScotsPine" mix (conifer: L0 = branches, L1 = twigs; the prune ellipsoid makes the cone):
	# a bare trunk, the crown in the upper ~55 % (user reference: realistic pines)
	"pine": {
		"height": 14.0, "trunk_steps": 10, "jitter": 0.05, "base_radius": 0.3, "tip_radius": 0.01, "taper_exp": 1.6,
		"root_flare": 0.8, "shape": "conical", "base_size": 0.42, "min_len": 0.35, "gravity": 0.2, "stiffness": 0.6,
		"prune": [5.2, 6.8, 10.3],   # ellipsoid radius xz, half height, centre y
		"levels": [
			{"children": 46, "len_ratio": 0.5, "angle": 1.25, "angle_var": 0.15, "start": 0.42, "end": 0.99, "apical": 0.55,
				"apical_inverted": true, "distortion": 0.1, "radius_ratio": 0.32, "kink": 4, "phyllo": "spiral",
				"curve_back": 0.15, "photo": 0.0},
			{"children": 7, "len_ratio": 0.6, "angle": 0.9, "angle_var": 0.25, "start": 0.35, "end": 1.0, "apical": 0.2,
				"distortion": 0.1, "radius_ratio": 0.5, "kink": 2, "phyllo": "spiral", "curve_back": 0.0, "photo": 0.0},
		],
	},
	# schema.js "Beech" (broadleaf; its 4th level is left to the leaf clusters)
	"leafy": {
		"height": 13.0, "trunk_steps": 9, "jitter": 0.06, "base_radius": 0.35, "tip_radius": 0.012, "taper_exp": 1.6,
		"root_flare": 1.0, "shape": "spherical", "base_size": 0.35, "min_len": 0.35, "gravity": 0.35, "stiffness": 0.7,
		"prune": [],
		"levels": [
			{"children": 11, "len_ratio": 0.62, "angle": 1.05, "angle_var": 0.3, "start": 0.35, "end": 1.0, "apical": 0.0,
				"distortion": 0.35, "radius_ratio": 0.6, "kink": 5, "phyllo": "spiral", "curve_back": -0.2, "photo": 0.25},
			{"children": 9, "len_ratio": 0.7, "angle": 0.78, "angle_var": 0.3, "start": 0.0, "end": 1.0, "apical": 0.0,
				"distortion": 0.3, "radius_ratio": 0.6, "kink": 3, "phyllo": "spiral", "curve_back": 0.0, "photo": 0.3},
			{"children": 7, "len_ratio": 0.62, "angle": 0.65, "angle_var": 0.3, "start": 0.0, "end": 1.0, "apical": 0.0,
				"distortion": 0.25, "radius_ratio": 0.6, "kink": 2, "phyllo": "spiral", "curve_back": 0.0, "photo": 0.3},
		],
	},
}

var sp: Dictionary
var rng := RandomNumberGenerator.new()
var pos := PackedVector3Array()
var parent := PackedInt32Array()
var level := PackedInt32Array()
var bt := PackedFloat32Array()
var radius := PackedFloat32Array()
var croot := PackedByteArray()   # 1 = a branch's first node (grows out of its parent's node)
var pruned := PackedByteArray()
var chains: Array = []           # PackedInt32Array per branch: [the parent node, its own nodes...]
var chain_level := PackedInt32Array()
var chain_len := PackedFloat32Array()
var height := 0.0


static func grow(species: String, seed_value: int) -> TreeGrower:
	var g := TreeGrower.new()
	g.sp = SPECIES[species]
	g.rng.seed = seed_value
	g._build()
	return g


## value noise in [-1, 1] (noise.js smoothNoise1D)
static func sn(x: float) -> float:
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	var a := fposmod(sin(i * 127.1) * 43758.5453, 1.0)
	var b := fposmod(sin((i + 1.0) * 127.1) * 43758.5453, 1.0)
	return lerpf(a, b, u) * 2.0 - 1.0


func _add(p: Vector3, par: int, lv: int, t: float, root := false) -> int:
	pos.append(p); parent.append(par); level.append(lv); bt.append(t); radius.append(0.0)
	croot.append(1 if root else 0); pruned.append(0)
	return pos.size() - 1


## crown shape (growth-engine.js L1335-1349): how long a trunk child is at relative height r
func _shape_mul(frac: float) -> float:
	var bs: float = sp.base_size
	var r := clampf((frac - bs) / maxf(1.0 - bs, 0.001), 0.0, 1.0)
	match String(sp.shape):
		"conical": return 0.2 + 0.8 * (1.0 - r)
		"spherical": return 0.2 + 0.8 * sin(PI * r)
		"hemispherical": return 0.2 + 0.8 * cos(PI * r / 2.0)
		"inverse": return 0.2 + 0.8 * r
		"tapered": return 0.5 + 0.5 * (1.0 - r)
	return 1.0


func _build() -> void:
	height = sp.height
	# the trunk: a gently wandering walk up (growth-engine.js L1702-1917, simplified)
	var steps: int = sp.trunk_steps
	var seg: float = height / steps
	var phi := rng.randf() * 1000.0
	var jamp: float = float(sp.jitter) * 6.5
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, 0.06)
	var p := Vector3.ZERO
	var trunk := PackedInt32Array([_add(p, -1, -1, 0.0)])
	for i in steps:
		var tn := (i + 0.5) / steps
		var a := smoothstep(0.0, 0.15, tn)
		var d := Vector3(sn(phi + tn * 3.2) * jamp * 0.15 * a, 1.0, sn(phi + tn * 3.2 + 17.3) * jamp * 0.15 * a) + lean
		p += d.normalized() * seg
		trunk.append(_add(p, trunk[trunk.size() - 1], -1, (i + 1.0) / steps))
	chains.append(trunk); chain_level.append(-1); chain_len.append(height)
	# level 0 along the trunk, then every level along its parents (breadth first)
	var queue: Array = [[0, BRANCH_BASE_LEN, true]]   # [chain index, its length, is trunk]
	var levels: Array = sp.levels
	for lv in levels.size():
		var next: Array = []
		for q in queue:
			for ci in _spawn(q[0], float(q[1]), lv, bool(q[2])):
				next.append([ci, chain_len[ci], false])
		queue = next
	_prune()
	_radii()
	_sag()


## children of chain `ci` at level lv: placed along it, angled / rolled off it, walked out; returns their chain indices
func _spawn(ci: int, parent_len: float, lv: int, on_trunk: bool) -> Array:
	var L: Dictionary = sp.levels[lv]
	var ch: PackedInt32Array = chains[ci]
	var count: int = L.children
	var out := []
	var roll0 := rng.randf() * TAU
	for c in count:
		var frac := lerpf(float(L.start), float(L.end), float(c) / maxf(count - 1, 1))
		frac = clampf(frac + rng.randf_range(-0.12, 0.12) / maxf(count, 1), 0.0, 1.0)
		var k := clampi(int(round(frac * (ch.size() - 1))), 1 if ch.size() > 1 else 0, ch.size() - 1)
		var node: int = ch[k]
		var prevn: int = ch[maxi(k - 1, 0)]
		var d := (pos[node] - pos[prevn]).normalized() if node != prevn else Vector3.UP
		var right := d.cross(Vector3.UP)
		if right.length() < 0.1: right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(d).normalized()
		var apical: float = L.get("apical", 0.0)
		var f_ap := frac if L.get("apical_inverted", false) else 1.0 - frac
		var ang: float = float(L.angle) + apical * f_ap * 0.35 + (rng.randf() - 0.5) * float(L.angle_var)
		var roll := roll0 + GOLDEN * (c + 1) + (rng.randf() - 0.5) * 0.55
		var cd := (d * cos(ang) + (right * cos(roll) + up * sin(roll)) * sin(ang)).normalized()
		var ln := parent_len * float(L.len_ratio) * (1.0 - apical * f_ap * 0.5)
		if on_trunk:
			ln *= _shape_mul(frac)
		ln *= rng.randf_range(0.85, 1.1)
		if ln < float(sp.min_len):
			continue
		out.append(_walk(node, cd, ln, lv))
	return out


## one branch: kink steps from `from` along d, wiggled, curved, bent toward the light (growth-engine.js walkInternode)
func _walk(from: int, d0: Vector3, ln: float, lv: int) -> int:
	var L: Dictionary = sp.levels[lv]
	var steps: int = L.kink
	var seg := ln / steps
	var d := d0
	var p := pos[from]
	var seed := rng.randf() * 137.5
	var stepinv := 8.0 / steps
	var thin := 2.0 if lv == sp.levels.size() - 1 else (1.4 if lv == sp.levels.size() - 2 else 1.0)
	var ch := PackedInt32Array([from])
	var prev := from
	for s in steps:
		var tn := float(s) / steps
		var amp: float = float(L.distortion) * thin * stepinv * 0.12
		var dx := sn(tn * 3.0 + seed) * amp
		var dz := sn(tn * 3.0 + seed + 47.3) * amp
		# curve back (negative lifts the tip, positive droops it)
		var up_bias := -float(L.curve_back) * 0.18 * sin(PI * tn) * stepinv * 0.12
		var right := d.cross(Vector3.UP)
		if right.length() < 0.1: right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(d).normalized()
		d = (d + right * dx + up * (dz + up_bias)).normalized()
		d += Vector3.UP * float(L.photo) * 0.03 * stepinv
		if p.y < 2.0:
			d.y += (1.0 - p.y / 2.0) * (1.0 - p.y / 2.0) * stepinv * 0.1
		d = d.normalized()
		p += d * seg
		p.y = maxf(p.y, 0.03)
		prev = _add(p, prev, lv, (s + 1.0) / steps, s == 0)
		ch.append(prev)
	chains.append(ch); chain_level.append(lv); chain_len.append(ln)
	return chains.size() - 1


## conifers: everything outside the ellipsoid goes (with what grows on it): that cuts the cone (growth-engine.js L1924)
func _prune() -> void:
	var pr: Array = sp.prune
	if pr.is_empty():
		return
	var rxz: float = pr[0]
	var ry: float = pr[1]
	var cy: float = pr[2]
	for i in pos.size():
		if level[i] < 0:
			continue
		var q := pos[i]
		var e := (q.x * q.x + q.z * q.z) / (rxz * rxz) + (q.y - cy) * (q.y - cy) / (ry * ry)
		if (e > 1.0 and q.y > cy - ry) or (parent[i] >= 0 and pruned[parent[i]] == 1 and level[parent[i]] >= 0):
			pruned[i] = 1


## Weber-Penn top-down radii (growth-engine.js L1955-1975) + root flare (L2035-2046)
func _radii() -> void:
	var tip: float = sp.tip_radius
	var base_r: float = float(sp.base_radius) * (height / 10.0)
	var tex: float = sp.taper_exp
	var chain_base := {}
	for ci in chains.size():
		var ch: PackedInt32Array = chains[ci]
		var lv: int = chain_level[ci]
		var cb := base_r
		if lv >= 0:
			cb = maxf(tip, radius[ch[0]] * float(sp.levels[lv].radius_ratio))
		chain_base[ci] = cb
		for k in range(0 if lv < 0 else 1, ch.size()):
			var n: int = ch[k]
			radius[n] = tip + (cb - tip) * pow(1.0 - bt[n], tex)
	var fl: float = sp.root_flare
	var fh := 3.8 * height / 11.0
	for i in pos.size():
		if level[i] < 0 and pos[i].y < fh:
			var u := 1.0 - pos[i].y / fh
			radius[i] *= 1.0 + fl * smoothstep(0.0, 1.0, u) * 0.5


## gravity sag (growth-engine.js applyGravitySag): heavy, horizontal limbs droop, the whole subtree turning with them
func _sag() -> void:
	var g: float = sp.gravity
	if g <= 0.0:
		return
	var n := pos.size()
	var w := PackedFloat32Array(); w.resize(n)
	for i in range(n - 1, 0, -1):
		var par := parent[i]
		var sl := (pos[i] - pos[par]).length()
		w[i] += sl * radius[i] * radius[i]
		w[par] += w[i]
	var rest := pos.duplicate()
	var rot: Array = []
	rot.resize(n)
	rot[0] = Basis()
	for i in range(1, n):
		var par := parent[i]
		var pb: Basis = rot[par]
		var off := rest[i] - rest[par]
		var t := off.normalized()
		var horiz := Vector2(t.x, t.z).length()
		var th := 0.0
		if level[i] >= 0:
			th = minf(horiz * sqrt(w[i]) * g * 0.015 / (1.0 + 4.0 * float(sp.stiffness) * radius[i] / 0.04) * 60.0, 0.5)
		var local := Basis()
		if th > 0.0:
			var axis := Vector3(t.z, 0, -t.x)
			if axis.length() > 0.01:
				local = Basis(axis.normalized(), th)
		rot[i] = local * pb
		pos[i] = pos[par] + pb * off

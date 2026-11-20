class_name TerrainChunkBuilder
extends RefCounted
## Port of Terrain.buildGen (terrain.js) + buildFence (fences.js) + buildTape (tape.js) placement.
## Runs on a WorkerThreadPool thread with its own TerrainField fork and produces only plain data
## (packed arrays, images, collider dictionaries); Terrain turns it into nodes on the main thread.
## Same seed -> same random streams -> same trees, rocks, fences, sheds as the JS.
## (One deviation: placement samples use the ground without the rock / log domes of neighbouring
## chunks, which the JS height() included only if those chunks happened to be loaded already.)

const WATER := TerrainField.WATER
const S := 48.0
const JC := 34.0
const SMALL := ["pebble", "grass", "daisy", "tulip", "spike", "stick", "fern", "mushroom"]
const LIST_NAMES := ["trunk", "blob", "pine", "rock", "pebble", "grass", "daisy", "tulip", "spike", "cactus0", "cactus1", "cactus2", "cactus3", "cactus4",
	"bush", "log", "stick", "fern", "mushroom", "weed", "plank", "beam", "post", "rail", "picket", "stake"]
const SPAN := 2.4
const TAPE_SEG := 30
const TAPE_W := 0.075
const TAPE_H := 0.85

static var LEAVES: Array = []
static var PINES: Array = []
static var PLANKS: Array = []
static var BEAM := Color()
static var CACTI: Array = []
static var BUSHES: Array = []
static var FERNS: Array = []
static var SHROOMS: Array = []
static var SCRUB: Array = []
static var DAISIES: Array = []
static var TULIPS: Array = []
static var SPIKES: Array = []
static var TAPE_COLS: Array = []   # red, white, yellow, black


static func ensure_static() -> void:
	if not LEAVES.is_empty():
		return
	var L := func(a: Array) -> Array:
		var o := []
		for h in a:
			o.append(TerrainField.lin(h))
		return o
	LEAVES = L.call([0x4f9a3a, 0x6cb544, 0x3f8a3f, 0x86c24a, 0x9bc94a, 0xe0a43a])
	PINES = L.call([0x2f6e45, 0x3b7d4b, 0x2a5f44])
	PLANKS = L.call([0xb98a55, 0xa87a48, 0xc49663, 0x9e6f40, 0xb0814e])
	BEAM = TerrainField.lin(0x7a5332)
	CACTI = L.call([0x4f8a3c, 0x5c9a45, 0x6b9e4a])
	BUSHES = L.call([0x3f7f33, 0x4c8c38, 0x5a8f3a, 0x6a9a3e, 0x7a8f3a])
	FERNS = L.call([0x3f8a35, 0x4f9a3c, 0x5ea544, 0x8a9a3a])
	SHROOMS = L.call([0xc8382c, 0xb5652e, 0xd9b27a, 0xe8dcc0, 0x8a5a36])
	SCRUB = L.call([0x9a7a48, 0xb08a52, 0x8c6c3e, 0x7f8a4a])
	DAISIES = L.call([0xffffff, 0xfff6e0, 0xffd84a, 0xff9ec4, 0xf26d9b, 0xffb35c])
	TULIPS = L.call([0xe8384a, 0xff6f61, 0xffc93c, 0xff8fb8, 0xf7f1ff, 0xd94f8c])
	SPIKES = L.call([0x9b7bea, 0x7a8cff, 0xc79bff, 0xf4a6d7, 0xffffff])
	TAPE_COLS = L.call([0xe8322b, 0xf6f5ef, 0xf5c518, 0x26241f])


var f   # TerrainField (GDScript reference) or TerrainFieldCs (C#): the same calls
var cx: int
var cz: int
var N: int
var gen: int
var out := {}
var rnd: WorldRng
var lists := {}       # name -> PackedFloat32Array (16 floats / instance: 3x4 row-major + custom rgba)
var counts := {}      # name -> int
var shed_lists: Array = []
var packs: Array = []   # health pack spots (Vector3, world) beside the sheds
var colliders: Array = []
var blocked: Array = []   # [x, z, r]
var panels: Array = []
var ms_used: float = 0.0
var stage_ms := {}
var _st: int = 0


func _stage(name: String) -> void:
	var t := Time.get_ticks_usec()
	stage_ms[name] = (t - _st) / 1000.0
	_st = t


func _init(field, ccx: int, ccz: int, seg: int, generation: int) -> void:
	f = field
	cx = ccx
	cz = ccz
	N = seg
	gen = generation


func run() -> void:
	var t0 := Time.get_ticks_usec()
	_build()
	ms_used = (Time.get_ticks_usec() - t0) / 1000.0


# ---------------- instance lists ----------------
func _push(name: String, b: Basis, p: Vector3, c: Color) -> int:
	var arr: PackedFloat32Array = lists[name]
	lists[name] = PackedFloat32Array()   # drop the dict's reference so the append grows arr in place (no copy of the whole list)
	arr.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, c.r, c.g, c.b, 1.0])
	lists[name] = arr
	counts[name] += 1
	return counts[name] - 1


static func _scaled(b: Basis, sx: float, sy: float, sz: float) -> Basis:
	return Basis(b.x * sx, b.y * sy, b.z * sz)


static func euler_xyz(ex: float, ey: float, ez: float) -> Basis:
	return Basis(Vector3.RIGHT, ex) * Basis(Vector3.UP, ey) * Basis(Vector3.BACK, ez)


## terrain.js put(): tilt always draws two numbers from the main stream
func put(name: String, x: float, y: float, z: float, sx: float, sy: float, sz: float, yaw: float, col = null, tilt: float = 0.0) -> int:
	var ex := tilt * (rnd.next() - .5)
	var ez := tilt * (rnd.next() - .5)
	var b := _scaled(euler_xyz(ex, yaw, ez), sx, sy, sz)
	return _push(name, b, Vector3(x, y, z), col if col != null else Color(1, 1, 1))


func height(x: float, z: float) -> float:
	return f.deck(x, z)


func ok_spot(x: float, z: float, min_h: float = WATER + 0.6) -> float:
	var h := height(x, z)
	if h < min_h or sqrt(x * x + z * z) < 9:
		return NAN
	var sl := absf(height(x + 0.8, z) - h) + absf(height(x, z + 0.8) - h)
	return NAN if sl > 0.7 else h


func is_blocked(x: float, z: float, pad: float = 0.0) -> bool:
	for b in blocked:
		var dx: float = x - b[0]
		var dz: float = z - b[1]
		if sqrt(dx * dx + dz * dz) < b[2] + pad:
			return true
	return false


func sm(a: float, b: float, x: float) -> float:
	var t := (x - a) / (b - a)
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	return t * t * (3.0 - 2.0 * t)


# ---------------- the build ----------------
func _build() -> void:
	ensure_static()
	_st = Time.get_ticks_usec()
	for k in LIST_NAMES:
		lists[k] = PackedFloat32Array()
		counts[k] = 0
	for i in 8:
		shed_lists.append(PackedFloat32Array())
	var ox := cx * S
	var oz := cz * S
	var d := S / N
	var W := N + 3
	var NV := N + 1
	# ---- height field with a 1-cell border, vertices, normals, colour layers ----
	var gs: Dictionary = ground_stage(ox, oz)
	var G: PackedFloat32Array = gs["G"]
	var verts: PackedVector3Array = gs["verts"]
	var norms: PackedVector3Array = gs["norms"]
	var uvs: PackedVector2Array = gs["uvs"]
	var LG: PackedColorArray = gs["LG"]
	var LD: PackedColorArray = gs["LD"]
	var TW: PackedFloat32Array = gs["TW"]
	var SW: PackedFloat32Array = gs["SW"]
	_stage("ground+colour")
	out["G"] = G
	_ground_lods(verts, norms, uvs)   # adds edge skirts to the vertex arrays
	out["verts"] = verts
	out["norms"] = norms
	out["uvs"] = uvs

	rnd = WorldRng.new(WorldRng.i32(cx * 73856093) ^ WorldRng.i32(cz * 19349663) ^ WorldRng.i32(f.seed_value * 83492791))
	var rs := WorldRng.new(WorldRng.i32(cx * 19349663) ^ WorldRng.i32(cz * 83492791) ^ WorldRng.i32(f.seed_value * 73856093) ^ 0x5bd1e995)
	_sheds(rs, ox, oz)
	_trail_fence(rs, ox, oz)
	_course_fences(rs)
	_rock_gardens()
	for p in panels:
		blocked.append([p["cx"], p["cz"], 1.6])
	_gates()
	_tape()
	for k in colliders:
		if k.has("tape"):
			blocked.append([k["x"], k["z"], 0.9])
	_stage("manmade")
	_trees(ox, oz)
	_rocks(ox, oz)
	_stage("trees+rocks")
	_tufts(ox, oz)
	_stage("tufts")
	_trail_clutter(ox, oz)
	_stage("clutter")
	_grass(ox, oz)
	_stage("grass")
	_nature(ox, oz)
	_wood(ox, oz)
	_stage("nature+wood")
	# ---- bake the ground textures with ambient occlusion ----
	var ao := PackedFloat32Array(); ao.resize(NV * NV); ao.fill(1.0)
	var R := maxi(1, WorldRng.jround(1.5 / d))   # JS: 4 texels at 0.375 m
	for iz in NV:
		for ix in NV:
			var h0: float = _gk(G, W, ix, iz)
			var avg := (_gk(G, W, ix - R, iz) + _gk(G, W, ix + R, iz) + _gk(G, W, ix, iz - R) + _gk(G, W, ix, iz + R)) / 4
			ao[iz * NV + ix] = 1 - minf(0.3, maxf(0, (avg - h0) * 0.6))
	for k in colliders:
		if k.has("fence") or k.has("tape"):
			continue
		var rock: bool = k.has("top")
		var r_: float = k["r"]
		var rad := r_ * 1.7 if rock else 1.3
		var inner := r_ * 0.6 if rock else 0.15
		var strn := 0.42 if rock else 0.3
		var fx: float = (k["x"] - ox + S / 2) / d
		var fz: float = (k["z"] - oz + S / 2) / d
		var rr := ceili(rad / d)
		for iz in range(maxi(0, floori(fz - rr)), mini(N, ceili(fz + rr)) + 1):
			for ix in range(maxi(0, floori(fx - rr)), mini(N, ceili(fx + rr)) + 1):
				var dd := Vector2(ix - fx, iz - fz).length() * d
				if dd < rad:
					ao[iz * NV + ix] *= 1 - strn * (1 - sm(inner, rad, dd))
	var pG := PackedByteArray(); pG.resize(NV * NV * 4)
	var pD := PackedByteArray(); pD.resize(NV * NV * 4)
	for o in NV * NV:
		var a: float = ao[o]
		var g: Color = LG[o]
		var dc: Color = LD[o]
		pG[o * 4] = _enc(g.r * a); pG[o * 4 + 1] = _enc(g.g * a); pG[o * 4 + 2] = _enc(g.b * a); pG[o * 4 + 3] = roundi(clampf(TW[o], 0, 1) * 255)
		pD[o * 4] = _enc(dc.r * a); pD[o * 4 + 1] = _enc(dc.g * a); pD[o * 4 + 2] = _enc(dc.b * a); pD[o * 4 + 3] = roundi(clampf(SW[o], 0, 1) * 255)
	var img_g := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pG)
	img_g.generate_mipmaps()
	var img_d := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pD)
	img_d.generate_mipmaps()
	out["land_img"] = img_g
	out["dirt_img"] = img_d
	# ---- debris collision: 49 x 49 heights at 1 m ----
	var hm := PackedFloat32Array(); hm.resize(49 * 49)
	for j in 49:
		for i in 49:
			var gx := i / d + 1.0
			var gz := j / d + 1.0
			var x0 := mini(floori(gx), W - 2)
			var z0 := mini(floori(gz), W - 2)
			var tx := gx - x0
			var tz := gz - z0
			var a := lerpf(G[z0 * W + x0], G[z0 * W + x0 + 1], tx)
			var b := lerpf(G[(z0 + 1) * W + x0], G[(z0 + 1) * W + x0 + 1], tx)
			hm[j * 49 + i] = lerpf(a, b, tz)
	out["hm"] = hm
	_stage("bake")
	out["lists"] = lists
	out["counts"] = counts
	out["sheds"] = shed_lists
	out["packs"] = packs
	out["colliders"] = colliders
	out["panels"] = panels


## the ground + colour stages: G (with a 1-cell border), vertices, normals, uvs, the two colour layers and
## their weights. The C# field does the same loops in one call (TerrainFieldCs.build_ground).
func ground_stage(ox: float, oz: float) -> Dictionary:
	if not (f is TerrainField):
		return f.build_ground(ox, oz, N)
	var d := S / N
	var W := N + 3
	var NV := N + 1
	var G := PackedFloat32Array()
	G.resize(W * W)
	var pre_g := PackedColorArray(); pre_g.resize(NV * NV)
	var pre_d := PackedColorArray(); pre_d.resize(NV * NV)
	var pre_t := PackedFloat32Array(); pre_t.resize(NV * NV)
	var pre_b := PackedFloat64Array(); pre_b.resize(NV * NV * 2)
	for iz in range(-1, N + 2):
		for ix in range(-1, N + 2):
			var x := ox - S / 2 + ix * d
			var z := oz - S / 2 + iz * d
			var h: float = f.ground(x, z)
			G[(iz + 1) * W + ix + 1] = h
			if ix >= 0 and ix <= N and iz >= 0 and iz <= N:
				# the colour's normal-independent half, while this point's memos are warm
				var o := iz * NV + ix
				f._cp_h = float(G[(iz + 1) * W + ix + 1])   # the float32 vertex height, like the JS
				pre_t[o] = f.color_pre(x, z)
				pre_g[o] = f.cl_g
				pre_d[o] = f.cl_d
				pre_b[o * 2] = f.cp_dry
				pre_b[o * 2 + 1] = f.cp_rug
	var verts := PackedVector3Array(); verts.resize(NV * NV)
	var norms := PackedVector3Array(); norms.resize(NV * NV)
	var uvs := PackedVector2Array(); uvs.resize(NV * NV)
	var LG := PackedColorArray(); LG.resize(NV * NV)
	var LD := PackedColorArray(); LD.resize(NV * NV)
	var TW := PackedFloat32Array(); TW.resize(NV * NV)
	var SW := PackedFloat32Array(); SW.resize(NV * NV)
	for iz in NV:
		for ix in NV:
			var k := (iz + 1) * W + ix + 1
			var o := iz * NV + ix
			var lx := -S / 2 + ix * d
			var lz := -S / 2 + iz * d
			var h: float = G[k]
			verts[o] = Vector3(lx, h, lz)
			var nv := Vector3(G[k - 1] - G[k + 1], 2 * d, G[k - W] - G[k + W]).normalized()
			norms[o] = nv
			uvs[o] = Vector2((ix + 0.5) / NV, (iz + 0.5) / NV)
			f.cl_g = pre_g[o]
			f.cl_d = pre_d[o]
			f.color_post(lx + ox, lz + oz, h, nv.y, pre_b[o * 2], pre_b[o * 2 + 1])
			TW[o] = pre_t[o]
			SW[o] = f.cl_steep
			LG[o] = f.cl_g
			LD[o] = f.cl_d
	return {"G": G, "verts": verts, "norms": norms, "uvs": uvs, "LG": LG, "LD": LD, "TW": TW, "SW": SW}


static func _gk(G: PackedFloat32Array, W: int, ix: int, iz: int) -> float:
	var N := W - 3
	return G[(mini(N + 1, maxi(-1, iz)) + 1) * W + mini(N + 1, maxi(-1, ix)) + 1]


static func _enc(v: float) -> int:
	v = minf(1.0, maxf(0.0, v))
	return roundi(255 * (v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1 / 2.4) - 0.055))


# ---------------- sheds ----------------
func _sheds(rs: WorldRng, ox: float, oz: float) -> void:
	var designs := TerrainGeo.shed_designs()
	if not (rs.next() < 0.32):
		return
	for tries in 8:
		var x := ox + (rs.next() - .5) * S * 0.8
		var z := oz + (rs.next() - .5) * S * 0.8
		if sqrt(x * x + z * z) < 30 or f.route_dist(x, z) < 9:
			continue
		var tm: float = f.trail_metres(x, z)
		var rd: float = f.route_dist(x, z)
		if not ((tm > 6 and tm < 16) or (rd > 9 and rd < 20)) and tries < 6:
			continue
		var di := int(rs.next() * designs.size())
		var dsg: Dictionary = designs[di]
		var R := Vector2(dsg["hw"], dsg["hd"]).length() + 0.6
		var gx := absf(f.pathN(x - 1, z)) - absf(f.pathN(x + 1, z))
		var gz := absf(f.pathN(x, z - 1)) - absf(f.pathN(x, z + 1))
		var yaw := atan2(gx, gz) + (rs.next() - .5) * 0.8
		var lo := INF
		var hi := -INF
		var ok := true
		var k := 0
		while k < 9 and ok:
			var a := k * 0.785
			var rr := 0.0 if k == 8 else R
			var px := x + cos(a) * rr
			var pz := z + sin(a) * rr
			var h := height(px, pz)
			if h < WATER + 0.8 or f.trail(px, pz) > 0.02 or f.jump_mask(px, pz) > 0:
				ok = false
			lo = minf(lo, h); hi = maxf(hi, h)
			k += 1
		if not ok or hi - lo > 0.7:
			continue
		var b := Basis(Vector3.UP, yaw)
		var arr: PackedFloat32Array = shed_lists[di]
		shed_lists[di] = PackedFloat32Array()   # no copy-on-write of the whole list
		var p := Vector3(x, lo - 0.05, z)
		arr.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, 1, 1, 1, 1])
		shed_lists[di] = arr
		_shed_colliders(dsg, x, z, yaw)
		blocked.append([x, z, R + 0.4])
		# a health pack just outside the door (local +z), a little to the side of the doorstep
		var hd2: float = dsg["hd"]
		var pc := cos(yaw)
		var ps := sin(yaw)
		var plx := -0.5
		var plz := hd2 + 1.5
		var pkx := x + plx * pc + plz * ps
		var pkz := z - plx * ps + plz * pc
		if height(pkx, pkz) > WATER + 0.3 and f.trail(pkx, pkz) <= 0.02:
			packs.append(Vector3(pkx, height(pkx, pkz), pkz))
		break


func _shed_colliders(dsg: Dictionary, x: float, z: float, yaw: float) -> void:
	var hw: float = dsg["hw"]
	var hd: float = dsg["hd"]
	var c := cos(yaw)
	var s := sin(yaw)
	var add := func(lx: float, lz: float, rr: float) -> void:
		colliders.append({"x": x + lx * c + lz * s, "z": z - lx * s + lz * c, "r": rr})
	for e in [[-hw, -hd, hw, -hd], [hw, -hd, hw, hd], [hw, hd, -hw, hd], [-hw, hd, -hw, -hd]]:
		var n := ceili(Vector2(e[2] - e[0], e[3] - e[1]).length() / 0.5)
		for i in n:
			add.call(e[0] + (e[2] - e[0]) * i / n, e[1] + (e[3] - e[1]) * i / n, 0.38)
	for e in dsg["extra"]:
		add.call(e[0], e[1], e[2])


# ---------------- fences ----------------
func _post_ok(x: float, z: float) -> float:
	var h := height(x, z)
	if h < WATER + 0.3 or sqrt(x * x + z * z) < 14 or f.trail(x, z) > 0.15 or f.jump_mask(x, z) > 0.02 or is_blocked(x, z, 0.5):
		return NAN
	return h


func _run_fence(pts: Array, style: String, rs: WorldRng, mn: int = 3) -> void:
	var cur := []
	for p in pts:
		var x: float = p[0]
		var z: float = p[1]
		var h := _post_ok(x, z)
		if is_nan(h) or (cur.size() > 0 and absf(h - cur[cur.size() - 1][2]) > 0.9):
			if cur.size() >= mn:
				_build_fence(cur, style, rs)
			cur = []
			if is_nan(h):
				continue
		cur.append([x, z, h])
	if cur.size() >= mn:
		_build_fence(cur, style, rs)


func _build_fence(pts: Array, style: String, rs: WorldRng) -> void:
	var st: Dictionary = TerrainGeo.FENCE_STYLES[style]
	var cols: Array = st["cols"]
	var add := func(kind: String, panel: Dictionary, pos: Vector3, b: Basis, scl: Vector3) -> void:
		var c := TerrainField.lin(cols[int(rs.next() * cols.size())]) * (0.92 + rs.next() * 0.16)
		c.a = 1.0
		var bs := _scaled(b, scl.x, scl.y, scl.z)
		var i := _push(kind, bs, pos, c)
		panel["parts"].append({"kind": kind, "i": i, "col": c, "xform": Transform3D(bs, pos), "scale": scl})
	var post := func(panel: Dictionary, a: Array) -> void:
		var ex := (rs.next() - .5) * 0.08
		var ey := rs.next() * 6.28
		var ez := (rs.next() - .5) * 0.08
		add.call("post", panel, Vector3(a[0], a[2] + st["postH"] / 2 - 0.18, a[1]), euler_xyz(ex, ey, ez), Vector3(1, st["postH"], 1))
	for k in range(0, pts.size() - 1):
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		var panel := {"broken": false, "parts": [], "style": style}
		var dx: float = b[0] - a[0]
		var dz: float = b[1] - a[1]
		var L := sqrt(dx * dx + dz * dz)
		var yaw := atan2(-dz, dx)
		var pitch := atan2(b[2] - a[2], L)
		var nx := -dz / L
		var nz := dx / L
		post.call(panel, a)
		if k + 2 == pts.size():
			post.call(panel, b)
		var qr := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
		for rl in st["rails"]:
			var sag := (rs.next() - .5) * 0.04
			add.call("rail", panel, Vector3((a[0] + b[0]) / 2 + nx * st["railOff"], (a[2] + b[2]) / 2 + rl[0] + sag, (a[1] + b[1]) / 2 + nz * st["railOff"]),
				qr, Vector3(L + 0.12, rl[1], rl[2]))
		if st["pickets"] > 0:
			var n := WorldRng.jround(L / st["pickets"])
			for i in range(1, n):
				var t := float(i) / n
				var hy: float = a[2] + (b[2] - a[2]) * t
				var q := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, (rs.next() - .5) * 0.05)
				var hh := 0.92 + (rs.next() - .5) * 0.06
				add.call("picket", panel, Vector3(a[0] + dx * t + nx * 0.02, hy + hh / 2 - 0.08, a[1] + dz * t + nz * 0.02), q, Vector3(1, hh, 1))
		var m := ceili(L / 0.45)
		for i in m + 1:
			colliders.append({"x": a[0] + dx * i / m, "z": a[1] + dz * i / m, "r": 0.22, "fence": panel, "fence_style": style})
		panel["cx"] = (a[0] + b[0]) / 2
		panel["cz"] = (a[1] + b[1]) / 2
		panels.append(panel)


func _trail_fence(rs: WorldRng, ox: float, oz: float) -> void:
	if not (rs.next() < 0.55):
		return
	var D := (4.2 + rs.next() * 1.5) * 0.022
	var st := [ox + (rs.next() - .5) * S, oz + (rs.next() - .5) * S]   # x, z (mutable through project)
	var project := func() -> bool:
		for it in 4:
			var v: float = f.pathN(st[0], st[1])
			var gx: float = f.pathN(st[0] + 0.5, st[1]) - f.pathN(st[0] - 0.5, st[1])
			var gz: float = f.pathN(st[0], st[1] + 0.5) - f.pathN(st[0], st[1] - 0.5)
			var g2 := gx * gx + gz * gz
			if g2 < 1e-10:
				return false
			var sg := signf(v) if v != 0.0 else 1.0
			var kk := (sg * D - v) / g2
			st[0] += gx * kk
			st[1] += gz * kk
		return absf(absf(f.pathN(st[0], st[1])) - D) < 0.004
	if not project.call():
		return
	var n := 4 + int(rs.next() * 7)
	var pts := []
	var has_dir := false
	var dir := Vector2.ZERO
	for i in n:
		var x: float = st[0]
		var z: float = st[1]
		pts.append([x, z])
		var gx: float = f.pathN(x + 0.5, z) - f.pathN(x - 0.5, z)
		var gz: float = f.pathN(x, z + 0.5) - f.pathN(x, z - 0.5)
		var gl := sqrt(gx * gx + gz * gz)
		var tx := -gz / gl
		var tz := gx / gl
		if has_dir and tx * dir.x + tz * dir.y < 0:
			tx = -tx; tz = -tz
		dir = Vector2(tx, tz)
		has_dir = true
		st[0] = x + tx * SPAN
		st[1] = z + tz * SPAN
		if not project.call():
			break
		var l := Vector2(st[0] - x, st[1] - z).length()
		st[0] = x + (st[0] - x) / l * SPAN
		st[1] = z + (st[1] - z) / l * SPAN
	_run_fence(pts, "picket" if rs.next() < 0.35 else "ranch", rs)


func _course_fences(rs: WorldRng) -> void:
	var C: TrailCourse = f.course
	for fi in C.chunk_fences.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var fc: Dictionary = C.fences[fi]
		var P: Array = fc["posts"]
		var cur := []
		for k in P.size():
			if WorldRng.jround(P[k][0] / S) == cx and WorldRng.jround(P[k][1] / S) == cz:
				if cur.is_empty():
					cur.append(P[k])
				if k + 1 < P.size():
					cur.append(P[k + 1])
			elif not cur.is_empty():
				_run_fence(cur, fc["style"], rs, 2)
				cur = []
		if not cur.is_empty():
			_run_fence(cur, fc["style"], rs, 2)


# ---------------- rock gardens ----------------
func _rock_gardens() -> void:
	var C: TrailCourse = f.course
	var rk := WorldRng.new(WorldRng.i32(cx * 83492791) ^ WorldRng.i32(cz * 2654435761) ^ WorldRng.i32(f.seed_value * 40503) ^ 0x1b873593)
	for i in C.chunk_rocks.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var w: float = C.W[i] - 0.15
		var line_a := sin(i * 0.23) * w * 0.55
		for k in 4:
			var a := (rk.next() * 2 - 1) * w
			var u := rk.next() * TrailCourse.STEP
			if absf(a - line_a) < 0.45 and rk.next() < 0.8:
				continue
			var x: float = C.X[i] + tx * u - tz * a
			var z: float = C.Z[i] + tz * u + tx * a
			var h: float = f.ground(x, z)
			var r1 := rk.next()
			var sc := 0.13 + r1 * r1 * 0.34
			var sx := sc * (1 + rk.next() * 0.5)
			var sy := sc * (0.5 + rk.next() * 0.35)
			put("pebble" if sc < 0.2 else "rock", x, h - sc * 0.3, z, sx, sy, sc, rk.next() * 6.28, null, 0.4)
			colliders.append({"x": x, "z": z, "r": (sx + sc) * 0.45, "top": h - sc * 0.3 + sy * 0.9, "base": f.ground(x, z)})


# ---------------- distance gates ----------------
## a distance marker over the trail: two lattice towers of small wooden cross beams either side of the trail
## with a cloth flag hanging between them that says how far down the trail you are. Fence-style panel, so
## riding into a tower smashes it (Terrain adds the flag node and frees it when the panel breaks).
func _gates() -> void:
	var C: TrailCourse = f.course
	var list := []
	for i in C.chunk_gates.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var half: float = C.W[i] + 1.5
		var nx := -tz
		var nz := tx
		var cxp: float = C.X[i]
		var czp: float = C.Z[i]
		if sqrt(cxp * cxp + czp * czp) < 14:
			continue
		var hl := height(cxp - nx * half, czp - nz * half)
		var hr := height(cxp + nx * half, czp + nz * half)
		if hl < WATER + 0.2 or hr < WATER + 0.2 or absf(hl - hr) > 3.0:
			continue
		# not on a jump / ramp / bridge (check the towers and the track between)
		var ok := true
		for s in [-1.0, 0.0, 1.0]:
			for off in [-half, 0.0, half]:
				f.jump_eval(cxp + tx * s * 3.0 + nx * off, czp + tz * s * 3.0 + nz * off)
				if f.fo_h > 0.05:
					ok = false
		if not ok:
			continue
		var top := maxf(hl, hr) + 5.4
		var panel := {"broken": false, "parts": [], "style": "gate", "cx": cxp, "cz": czp}
		var add := func(kind: String, pos: Vector3, b: Basis, scl: Vector3, c: Color) -> void:
			var bs := _scaled(b, scl.x, scl.y, scl.z)
			var k := _push(kind, bs, pos, c)
			panel["parts"].append({"kind": kind, "i": k, "col": c, "xform": Transform3D(bs, pos), "scale": scl})
		var stick := TerrainField.lin(0x7a5a3a)
		var lash := TerrainField.lin(0x5c452e)
		var along := Basis(Vector3.UP, atan2(-tz, tx))    # a beam running along the trail
		var across := Basis(Vector3.UP, atan2(-nz, nx))   # a beam running across it
		var T := Vector3(tx, 0, tz)
		var BAYS := 4
		for s in [-1.0, 1.0]:
			var mx: float = cxp + nx * half * s
			var mz: float = czp + nz * half * s
			var g0 := minf(height(mx - tx * 0.55, mz - tz * 0.55), height(mx + tx * 0.55, mz + tz * 0.55))
			# the two uprights, a little thicker than a fence post
			for q in [-1.0, 1.0]:
				var px: float = mx + tx * 0.55 * q
				var pz: float = mz + tz * 0.55 * q
				var gh := height(px, pz)
				var ph := top - gh + 0.2
				add.call("post", Vector3(px, gh + ph / 2 - 0.18, pz), Basis.IDENTITY, Vector3(1.4, ph, 1.4), stick)
				colliders.append({"x": px, "z": pz, "r": 0.3, "fence": panel, "fence_style": "gate"})
				blocked.append([px, pz, 1.0])
			# small cross beams every bay + an X brace in every other bay
			var y0 := g0 + 0.5
			var dy := (top - y0) / BAYS
			for k in BAYS + 1:
				add.call("rail", Vector3(mx, y0 + dy * k, mz), along, Vector3(1.2, 0.07, 0.07), lash)
			for k in BAYS:
				if k % 2 == 1:
					continue
				var dir := 1.0 if (int(s) + k) % 4 == 0 else -1.0
				var d := Vector3(T.x * 1.1 * dir, dy, T.z * 1.1 * dir)
				var bx := d.normalized()
				var bz := bx.cross(Vector3.UP).normalized()
				add.call("rail", Vector3(mx, y0 + dy * (k + 0.5), mz), Basis(bx, bz.cross(bx), bz), Vector3(d.length(), 0.06, 0.06), lash)
		# the crossbar the flag hangs from, a second above it, and a stick weighting the flag's bottom edge
		var span := half * 2.0 + 0.9
		add.call("rail", Vector3(cxp, top + 0.05, czp), across, Vector3(span, 0.09, 0.09), stick)
		add.call("rail", Vector3(cxp, top - 0.35, czp), across, Vector3(span, 0.07, 0.07), lash)
		var fh := 1.7
		var fw := half * 2.0 - 0.4
		add.call("rail", Vector3(cxp, top - 0.45 - fh, czp), across, Vector3(fw, 0.06, 0.06), lash)
		panel["flag"] = {"at": Vector3(cxp, top - 0.4 - fh / 2, czp), "w": fw, "h": fh,
			"basis": Basis(Vector3(nx, 0, nz), Vector3.UP, Vector3(-tx, 0, -tz)), "dist": i * TrailCourse.STEP, "i": i}
		panels.append(panel)
		list.append(i)
	if OS.get_environment("BMX_GATE_PROBE") != "":
		print("GATES chunk=", cx, ",", cz, " cand=", C.chunk_gates.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()).size(), " placed=", list.size())


# ---------------- race tape ----------------
func _plant(st: Dictionary) -> Array:
	var x: float = st["x"]
	var z: float = st["z"]
	if sqrt(x * x + z * z) < 10:
		return []
	var h := height(x, z)
	f.jump_eval(x, z)
	if h < -1.9 or f.fo_h > 0.05:
		return []
	return [x, z, h]


func _tape() -> void:
	var stakes_all: Array = f.course.stakes
	var spans := []
	var stake_pos := []
	for k in f.course.chunk_stakes.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var st: Dictionary = stakes_all[k]
		var b := _plant(st)
		if b.is_empty():
			continue
		stake_pos.append(b)
		var a := []
		if st["prev"] >= 0:
			a = _plant(stakes_all[st["prev"]])
		if a.is_empty() or absf(b[2] - a[2]) > 2:
			continue
		spans.append({"a": a, "b": b, "k": k, "side": st["side"], "caution": st["caution"]})
	for s in stake_pos:
		var r := sin(s[0] * 12.9 + s[1] * 78.2) * 0.04
		_push("stake", euler_xyz(r, 0, -r), Vector3(s[0], s[2], s[1]), Color(1, 1, 1))
	if spans.is_empty():
		return
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	for sp in spans:
		var a: Array = sp["a"]
		var b: Array = sp["b"]
		var dx: float = b[0] - a[0]
		var dz: float = b[1] - a[1]
		var L := sqrt(dx * dx + dz * dz)
		var sx := -dz / L
		var szz := dx / L
		var ya: float = a[2] + TAPE_H
		var yb: float = b[2] + TAPE_H
		var side: float = sp["side"]
		var kk: int = sp["k"]
		var phase0 := fmod(kk * 1.7 + side, 6.28)
		var hr := func(nn: int) -> float:
			var v := sin(kk * 127.1 + side * 311.7 + nn * 74.7) * 43758.5453
			return v - floorf(v)
		var var_s: float = 0.6 + hr.call(1) * 0.6
		var var_l: float = 0.6 + hr.call(2) * 1.1
		var var_t: float = 0.3 + hr.call(3) * 1.4
		var sag: float = 0.1 + hr.call(4) * 0.08
		var pts := PackedVector3Array()
		for i in TAPE_SEG + 1:
			var t := float(i) / TAPE_SEG
			var x: float = a[0] + dx * t
			var z: float = a[1] + dz * t
			var y := ya + (yb - ya) * t - sin(PI * t) * sag
			y = maxf(y, height(x, z) + 0.35)
			pts.append(Vector3(x, y, z))
		var cols: Array = [TAPE_COLS[2], TAPE_COLS[3]] if sp["caution"] else [TAPE_COLS[0], TAPE_COLS[1]]
		var rec := {"broken": false, "v0": pos.size(), "pts": pts, "cols": cols, "len": L}
		for i in TAPE_SEG:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var c: Color = cols[i & 1]
			var t0 := float(i) / TAPE_SEG
			var t1 := float(i + 1) / TAPE_SEG
			var corner := [[p0, t0, 1.0], [p0, t0, -1.0], [p1, t1, 1.0], [p1, t1, 1.0], [p0, t0, -1.0], [p1, t1, -1.0]]
			for cn in corner:
				var p: Vector3 = cn[0]
				var tt: float = cn[1]
				var edge: float = cn[2]
				pos.append(Vector3(p.x, p.y + edge * TAPE_W / 2, p.z))
				nrm.append(Vector3(sx, 0, szz))
				col.append(c)
				c0.append_array([sin(PI * tt), phase0 + tt * L * 1.6, edge, 1.0])
				c1.append_array([var_s, var_l, var_t, 0.0])
		var n := ceili(L / 0.4)
		for i in n + 1:
			var p := pts[WorldRng.jround(float(i) / n * TAPE_SEG)]
			colliders.append({"x": p.x, "z": p.z, "r": 0.12, "tape": rec, "ceil": p.y + 0.1})
		sp["rec"] = rec
	var recs := []
	for sp in spans:
		recs.append(sp["rec"])
	out["tape"] = {"pos": pos, "nrm": nrm, "col": col, "c0": c0, "c1": c1, "spans": recs}


# ---------------- trees and cacti ----------------
func _trees(ox: float, oz: float) -> void:
	for i in 90:
		var x := ox + (rnd.next() - .5) * S
		var z := oz + (rnd.next() - .5) * S
		var forest: float = f.n(x + 400, z, TerrainField.I38)
		if rnd.next() > sm(-0.25, 0.25, forest) * 0.9 + 0.05:
			continue
		if f.trail(x, z) > 0.02 or absf(f.pathN(x, z)) < 0.1 or f.jump_mask(x, z) > 0 or is_blocked(x, z, 0.8):
			continue
		var h := ok_spot(x, z)
		if is_nan(h):
			continue
		var sc := 0.7 + rnd.next() * 0.8
		var yaw := rnd.next() * 6.28
		f.biome(x, z)
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		if rnd.next() < dry:
			if rnd.next() < 0.35:
				var kind := CactusGeo.pick(rnd.next())
				var cs := 0.75 + (sc - 0.7) * 0.45          # 0.75 .. 1.11: cacti vary less than trees
				var cy := cs * (0.85 + rnd.next() * 0.35)
				var cc: Color = CACTI[int(rnd.next() * CACTI.size())]
				var nm := "cactus%d" % kind
				var idx := put(nm, x, h - 0.03, z, cs, cy, cs, yaw, cc, 0.08)
				colliders.append({"x": x, "z": z, "r": CactusGeo.HIT_R[kind] * cs, "ceil": h - 0.03 + CactusGeo.HEIGHT[kind] * cy,
					"cactus": {"i": idx, "kind": kind, "broken": false, "col": cc, "xform": _last_xform(nm)}})
			continue
		var ceil_h := 0.0
		if h > 4 or rnd.next() < 0.3 + rug * 0.6:
			put("trunk", x, h - 0.1, z, sc, sc * 0.9, sc, yaw)
			var py := sc * (1.1 + rnd.next() * 0.4)
			put("pine", x, h + sc * 0.6, z, sc * 1.1, py, sc * 1.1, yaw, PINES[int(rnd.next() * PINES.size())])
			ceil_h = h + sc * 0.6 + 2.8 * py
		else:
			var th := sc * (1.1 + rnd.next() * 0.6)
			ceil_h = h + th + sc * 1.8
			put("trunk", x, h - 0.1, z, sc, th + 0.3, sc, yaw)
			put("blob", x, h + th + sc * 0.7, z, sc * 1.2, sc * 1.05, sc * 1.2, yaw, LEAVES[int(rnd.next() * LEAVES.size())], 0.6)
			if rnd.next() < 0.5:
				var bx := x + (rnd.next() - .5) * sc
				var bz := z + (rnd.next() - .5) * sc
				put("blob", bx, h + th + sc * 1.4, bz, sc * .8, sc * .75, sc * .8, yaw, LEAVES[int(rnd.next() * LEAVES.size())], 0.6)
		colliders.append({"x": x, "z": z, "r": 0.16 * sc + 0.02, "ceil": ceil_h})


func _last_xform(name: String) -> Transform3D:
	var a: PackedFloat32Array = lists[name]
	var o := a.size() - 16
	return Transform3D(Basis(Vector3(a[o], a[o + 4], a[o + 8]), Vector3(a[o + 1], a[o + 5], a[o + 9]), Vector3(a[o + 2], a[o + 6], a[o + 10])),
		Vector3(a[o + 3], a[o + 7], a[o + 11]))


func _rocks(ox: float, oz: float) -> void:
	for i in 40:
		var x := ox + (rnd.next() - .5) * S
		var z := oz + (rnd.next() - .5) * S
		if i >= 22:
			f.biome(x, z)
			if rnd.next() > f.b_rug:
				continue
		if f.trail(x, z) > 0.02 or f.jump_mask(x, z) > 0 or is_blocked(x, z, 0.5):
			continue
		var h := height(x, z)
		if sqrt(x * x + z * z) < 9:
			continue
		var r1 := rnd.next()
		var sc := 0.2 + r1 * r1 * r1 * 1.3
		var sx := sc * (1 + rnd.next() * .5)
		var sy := sc * (0.6 + rnd.next() * .4)
		put("pebble" if sc < 0.6 else "rock", x, h - sc * 0.25, z, sx, sy, sc, rnd.next() * 6.28, null, 0.5)
		colliders.append({"x": x, "z": z, "r": (sx + sc) * 0.45, "top": h - sc * 0.25 + sy * 0.9, "base": f.ground(x, z)})


func _tuft_col(dry: float) -> Color:
	var C: Dictionary = f.col
	return C["tuftGreen"].lerp(C["tuftDry"], sm(0.1, 0.6, dry))


func _tufts(ox: float, oz: float) -> void:
	for i in 260:
		var x := ox + (rnd.next() - .5) * S
		var z := oz + (rnd.next() - .5) * S
		if f.trail(x, z) > 0.1 or f.jump_mask(x, z) > 0.3:
			continue
		var skip := false
		for b in blocked:
			if b[2] > 2 and Vector2(x - b[0], z - b[1]).length() < b[2] - 0.6:
				skip = true
				break
		if skip:
			continue
		var h := height(x, z)
		if h < WATER + 0.4:
			continue
		f.biome(x, z)
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		if rnd.next() < dry * 0.85 or rnd.next() < rug * 0.3:
			continue
		var tc := _tuft_col(dry)
		if rnd.next() < 0.22 * (1 - dry):
			var kind := rnd.next()
			var list := "daisy" if kind < 0.5 else ("tulip" if kind < 0.78 else "spike")
			var pal: Array = DAISIES if list == "daisy" else (TULIPS if list == "tulip" else SPIKES)
			var colr: Color = pal[int(rnd.next() * pal.size())]
			var n := 2 + int(rnd.next() * 4)
			var sc := 1.35 + rnd.next() * 0.5
			for j in n:
				var a := rnd.next() * 6.28
				var r := (0.1 + rnd.next() * 0.32) if j else 0.0
				var fx := x + cos(a) * r
				var fz := z + sin(a) * r
				if j and f.trail(fx, fz) > 0.1:
					continue
				var s := sc * (0.8 + rnd.next() * 0.35)
				var hh := height(fx, fz) - 0.015
				var sy := s * (0.8 + rnd.next() * 0.45)
				var yw := rnd.next() * 6.28
				var cc := colr * (0.88 + rnd.next() * 0.16)
				put(list, fx, hh, fz, s, sy, s, yw, cc, 0.35)
		else:
			var sx := 1 + rnd.next()
			var sy := 0.7 + rnd.next() * 0.8
			var szz := 1 + rnd.next()
			put("grass", x, h - 0.03, z, sx, sy, szz, rnd.next() * 6.28, tc)


func _trail_clutter(ox: float, oz: float) -> void:
	var rt := WorldRng.new(WorldRng.i32(cx * 2654435761) ^ WorldRng.i32(cz * 40503) ^ WorldRng.i32(f.seed_value * 2246822519) ^ 0x27d4eb2f)
	for i in 420:
		var x := ox + (rt.next() - .5) * S
		var z := oz + (rt.next() - .5) * S
		var t: float = f.trail(x, z)
		if t < 0.04 or f.jump_mask(x, z) > 0.05 or is_blocked(x, z, 0.3):
			continue
		var h := height(x, z)
		if h < WATER + 0.2 or sqrt(x * x + z * z) < 6:
			continue
		var ln: float = f.line(x, z)
		if t > 0.45:
			if ln > 0.25 or rt.next() < 0.35:
				continue
			var r1 := rt.next()
			var sc := 0.035 + r1 * r1 * 0.09
			var sx := sc * (1 + rt.next() * 0.6)
			var sy := sc * (0.5 + rt.next() * 0.4)
			put("pebble", x, h - sc * 0.3, z, sx, sy, sc, rt.next() * 6.28, null, 0.6)
		else:
			f.biome(x, z)
			var dry: float = f.b_dry
			if rt.next() < 0.25:
				var sc := 0.06 + rt.next() * 0.1
				put("pebble", x, h - sc * 0.3, z, sc * 1.3, sc * 0.7, sc, rt.next() * 6.28, null, 0.5)
			elif rt.next() > dry * 0.7:
				var sx := 0.7 + rt.next() * 0.6
				var sy := 0.5 + rt.next() * 0.6
				var szz := 0.7 + rt.next() * 0.6
				put("grass", x, h - 0.03, z, sx, sy, szz, rt.next() * 6.28, _tuft_col(dry))


func _grass(ox: float, oz: float) -> void:
	var rg := WorldRng.new(WorldRng.i32(cx * 668265263) ^ WorldRng.i32(cz * 374761393) ^ WorldRng.i32(f.seed_value * 2654435761) ^ 0x3c6ef372)
	var C: Dictionary = f.col
	for i in 420:
		var x := ox + (rg.next() - .5) * S
		var z := oz + (rg.next() - .5) * S
		if f.trail(x, z) > 0.15 or f.jump_mask(x, z) > 0.1:
			continue
		var h := height(x, z)
		if h < WATER + 0.5:
			continue
		f.biome(x, z)
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		if rg.next() < dry * 0.95 + rug * 0.5:
			continue
		var n := 2 + int(rg.next() * 4)
		var base: Color = C["tuftGreen"].lerp(C["grassB"], rg.next() * 0.6).lerp(C["tuftDry"], sm(0.1, 0.6, dry))
		for k in n:
			var a := rg.next() * 6.28
			var d := (0.15 + rg.next() * 0.45) if k else 0.0
			var gx := x + cos(a) * d
			var gz := z + sin(a) * d
			if k and f.trail(gx, gz) > 0.15:
				continue
			var s2 := 0.9 + rg.next() * 0.9
			var hh := height(gx, gz) - 0.02
			var sy := s2 * (0.8 + rg.next() * 0.5)
			var yw := rg.next() * 6.28
			var cc := base * (0.85 + rg.next() * 0.3)
			put("grass", gx, hh, gz, s2, sy, s2, yw, cc, 0.15)


func _nature(ox: float, oz: float) -> void:
	var rn := WorldRng.new(WorldRng.i32(cx * 374761393) ^ WorldRng.i32(cz * 668265263) ^ WorldRng.i32(f.seed_value * 1274126177) ^ 0x6a09e667)
	var C: Dictionary = f.col
	for i in 220:
		var x := ox + (rn.next() - .5) * S
		var z := oz + (rn.next() - .5) * S
		if f.trail(x, z) > 0.03 or f.jump_mask(x, z) > 0 or is_blocked(x, z, 0.6) or sqrt(x * x + z * z) < 10:
			continue
		var h := ok_spot(x, z, WATER + 0.5)
		if is_nan(h):
			continue
		f.biome(x, z)
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		var wood := sm(-0.05, 0.3, f.n(x + 400, z, TerrainField.I38))
		var r := rn.next()
		var yaw := rn.next() * 6.28
		if dry > 0.55:
			if r < 0.08:
				var sc := 0.25 + rn.next() * 0.25
				put("weed", x, h + sc * 0.75, z, sc, sc * 0.85, sc, yaw, SCRUB[int(rn.next() * SCRUB.size())], 0.6)
			elif r < 0.4:
				var sx := 2 + rn.next() * 1.5
				var sy := 1.4 + rn.next()
				var szz := 2 + rn.next() * 1.5
				put("grass", x, h - 0.03, z, sx, sy, szz, yaw, C["tuftDry"] * (0.8 + rn.next() * 0.3))
			elif r < 0.55 and f.trail_metres(x, z) > 3:
				for k in 3:
					var sc := 0.05 + rn.next() * 0.1
					var a := rn.next() * 6.28
					var d := rn.next() * 0.8
					put("pebble", x + cos(a) * d, h - sc * 0.3, z + sin(a) * d, sc * 1.3, sc * 0.7, sc, rn.next() * 6.28, null, 0.5)
			continue
		if rug > 0.55 and r < 0.35:
			for k in 4:
				var sc := 0.06 + rn.next() * 0.14
				var a := rn.next() * 6.28
				var d := rn.next() * 1.2
				put("pebble", x + cos(a) * d, h - sc * 0.3, z + sin(a) * d, sc * 1.3, sc * 0.75, sc, rn.next() * 6.28, null, 0.6)
			continue
		if wood > 0.3:
			if r < 0.06:
				var len := 1.6 + rn.next() * 2
				var sc := 0.8 + rn.next() * 0.5
				var dx := cos(yaw)
				var dz := -sin(yaw)
				var h2 := minf(height(x + dx * len / 2, z + dz * len / 2), height(x - dx * len / 2, z - dz * len / 2))
				if absf(h - h2) > 0.35 or f.trail(x + dx * len / 2, z + dz * len / 2) > 0.02 or f.trail(x - dx * len / 2, z - dz * len / 2) > 0.02:
					continue
				put("log", x, minf(h, h2) + 0.14 * sc, z, len, sc, sc, yaw, null, 0.08)
				for u in [-0.35, 0.0, 0.35]:
					var lx: float = x + dx * len * u
					var lz: float = z + dz * len * u
					colliders.append({"x": lx, "z": lz, "r": 0.22 * sc, "top": minf(h, h2) + 0.34 * sc, "base": f.ground(lx, lz)})
			elif r < 0.13:
				var sc := 1.3 + rn.next() * 0.9
				put("trunk", x, h - 0.05, z, sc, 0.18 + rn.next() * 0.2, sc, yaw, null, 0.1)
				colliders.append({"x": x, "z": z, "r": 0.16 * sc, "top": h + 0.25, "base": f.ground(x, z)})
			elif r < 0.45:
				var n := 1 + int(rn.next() * 4)
				var colr: Color = FERNS[int(rn.next() * FERNS.size())]
				for k in n:
					var a := rn.next() * 6.28
					var d := (0.3 + rn.next() * 0.5) if k else 0.0
					var fx := x + cos(a) * d
					var fz := z + sin(a) * d
					var s2 := 1 + rn.next() * 0.8
					var hh := height(fx, fz) - 0.02
					var sy := s2 * (0.8 + rn.next() * 0.4)
					put("fern", fx, hh, fz, s2, sy, s2, rn.next() * 6.28, colr, 0.2)
			elif r < 0.62:
				var l := 0.4 + rn.next() * 0.9
				var sy := 0.8 + rn.next() * 0.6
				var szz := 0.8 + rn.next() * 0.6
				put("stick", x, h + 0.015, z, l, sy, szz, yaw, null, 0.15)
			elif r < 0.72:
				var colr: Color = SHROOMS[int(rn.next() * SHROOMS.size())]
				var n := 2 + int(rn.next() * 5)
				for k in n:
					var a := rn.next() * 6.28
					var d := rn.next() * 0.25
					var fx := x + cos(a) * d
					var fz := z + sin(a) * d
					var s2 := 0.7 + rn.next() * 0.9
					var hh := height(fx, fz) - 0.01
					var sy := s2 * (0.8 + rn.next() * 0.5)
					put("mushroom", fx, hh, fz, s2, sy, s2, rn.next() * 6.28, colr, 0.3)
			elif r < 0.85:
				var sc := 0.5 + rn.next() * 0.6
				var sx := sc * (1 + rn.next() * 0.4)
				var sy := sc * (0.8 + rn.next() * 0.5)
				put("bush", x, h - 0.08, z, sx, sy, sc, yaw, BUSHES[int(rn.next() * BUSHES.size())], 0.3)
			continue
		if r < 0.14:
			var n := 1 + int(rn.next() * 3)
			var colr: Color = BUSHES[int(rn.next() * BUSHES.size())]
			for k in n:
				var a := rn.next() * 6.28
				var d := (0.5 + rn.next() * 0.7) if k else 0.0
				var fx := x + cos(a) * d
				var fz := z + sin(a) * d
				var sc := 0.35 + rn.next() * 0.55
				if f.trail(fx, fz) > 0.02:
					continue
				var hh := height(fx, fz) - 0.08
				var sx := sc * (1 + rn.next() * 0.4)
				var sy := sc * (0.7 + rn.next() * 0.5)
				var yw := rn.next() * 6.28
				put("bush", fx, hh, fz, sx, sy, sc, yw, colr * (0.85 + rn.next() * 0.3), 0.3)
		elif r < 0.2:
			var l := 0.3 + rn.next() * 0.6
			put("stick", x, h + 0.015, z, l, 0.8, 0.8, yaw, null, 0.15)


# ---------------- wooden ramps / skinnies / bridges whose start lies in this chunk ----------------
func _wood(ox: float, oz: float) -> void:
	var x0 := ox - S / 2
	var z0 := oz - S / 2
	var feats := []
	# a feature starts up to len / 2 before its cell centre, so the cell past the far edge can still start here
	for gz in range(floori(z0 / JC) - 1, floori((z0 + S) / JC) + 2):
		for gx in range(floori(x0 / JC) - 1, floori((x0 + S) / JC) + 2):
			var j = f.jump_at(gx, gz)
			if j != null and j.wood != null:
				feats.append(j)
	for j in f.route_feats:
		if j.wood != null:
			feats.append(j)
	for j in feats:
		if j.x >= x0 and j.x < x0 + S and j.z >= z0 and j.z < z0 + S:
			_wood_model(j)


func _wood_model(j) -> void:   # TerrainField.Feat or TerrainFeatCs
	var W = j.wood
	var qy := Basis(Vector3.UP, atan2(-j.dz, j.dx))
	var top := func(u: float) -> float:
		return j.b0 + (j.b1 - j.b0) * clampf(u / j.len, 0, 1) + W.top(u)
	var at := func(u: float, w: float) -> Vector2:
		return Vector2(j.x + j.dx * u - j.dz * w, j.z + j.dz * u + j.dx * w)
	var putw := func(list: String, u: float, w: float, y: float, sx: float, sy: float, sz: float, pitch: float, c: Color) -> void:
		var p: Vector2 = at.call(u, w)
		_push(list, _scaled(qy * Basis(Vector3.BACK, pitch), sx, sy, sz), Vector3(p.x, y, p.y), c)
	var r := WorldRng.new(WorldRng.i32f(j.x * 1000) ^ WorldRng.i32f(j.z * 7919))
	var u: float = W.u0 + 0.13
	while u < W.u1:
		var sl: float = (top.call(minf(W.u1, u + 0.06)) - top.call(maxf(W.u0, u - 0.06))) / 0.12
		putw.call("plank", u, 0.0, top.call(u) - 0.035, 0.23, 0.07, W.half * 2 + 0.08, atan(sl), PLANKS[int(r.next() * PLANKS.size())])
		u += 0.27
	for side in [-1.0, 1.0]:
		var w: float = side * (W.half - 0.08)
		u = W.u0
		while u < W.u1 - 0.05:
			var u2 := minf(W.u1, u + 1.2)
			var t1: float = top.call(u)
			var t2: float = top.call(u2)
			putw.call("beam", (u + u2) / 2, w, (t1 + t2) / 2 - 0.14, Vector2(u2 - u, t2 - t1).length(), 0.14, 0.1, atan2(t2 - t1, u2 - u), BEAM)
			u += 1.2
		u = W.u0 + 0.7
		while u <= W.u1 - 0.3:
			var t: float = top.call(u) - 0.2
			var p: Vector2 = at.call(u, w)
			var g: float = f.ground(p.x, p.y) - 0.1
			if t - g > 0.12:
				putw.call("beam", u, w, (t + g) / 2, 0.11, t - g, 0.11, 0.0, BEAM)
			u += 1.5
	if W.back_wall:
		var p: Vector2 = at.call(W.u1, 0.0)
		var t: float = top.call(W.u1)
		var g: float = f.ground(p.x, p.y) - 0.1
		putw.call("beam", W.u1 - 0.05, 0.0, (t + g) / 2, 0.08, t - g, W.half * 2, 0.0, BEAM)


# ----------------------------------------------------------------------------------------------
# GROUND LOD: the full grid plus coarser versions (every 2nd / 4th / 8th point) that Godot swaps
# in by distance. Each level's key is its real geometric error (largest height gap between the
# fine grid and the coarse one), so bumpy chunks (jump lips, rock bands) stay detailed for longer
# and flat meadows drop detail early. A skirt hangs 0.8 m down round the chunk's edge in every
# level, hiding the cracks where a neighbour shows a different level.
const SKIRT := 0.8
const LOD_STEPS := [2, 4, 8]

func _ground_lods(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var n := N
	var nv := n + 1
	# skirt vertices: the 4 edges, walked in order, each point copied SKIRT lower
	var edges := []
	for e in 4:
		var line := PackedInt32Array()
		for i in nv:
			var ix := i if e < 2 else (0 if e == 2 else n)
			var iz := (0 if e == 0 else n) if e < 2 else i
			line.append(iz * nv + ix)
		edges.append(line)
	var skirt_of := {}
	for line in edges:
		for vi in line:
			if skirt_of.has(vi): continue
			skirt_of[vi] = verts.size()
			verts.append(verts[vi] - Vector3(0, SKIRT, 0))
			norms.append(norms[vi])
			uvs.append(uvs[vi])
	out["indices"] = _grid_lod_indices(1, edges, skirt_of)
	var lods := {}
	for s: int in LOD_STEPS:
		if n % s != 0: continue
		var err := 0.0
		for iz in nv:
			var cz0 := (iz / s) * s
			var cz1 := mini(cz0 + s, n)
			var tz := 0.0 if cz1 == cz0 else float(iz - cz0) / (cz1 - cz0)
			for ix in nv:
				var cx0 := (ix / s) * s
				var cx1 := mini(cx0 + s, n)
				var tx := 0.0 if cx1 == cx0 else float(ix - cx0) / (cx1 - cx0)
				var h00 := verts[cz0 * nv + cx0].y
				var h10 := verts[cz0 * nv + cx1].y
				var h01 := verts[cz1 * nv + cx0].y
				var h11 := verts[cz1 * nv + cx1].y
				var hb := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
				err = maxf(err, absf(verts[iz * nv + ix].y - hb))
		lods[maxf(err, 0.02 * s)] = _grid_lod_indices(s, edges, skirt_of)
	out["lods"] = lods

func _grid_lod_indices(s: int, edges: Array, skirt_of: Dictionary) -> PackedInt32Array:
	var n := N
	var nv := n + 1
	var idx := PackedInt32Array()
	var m := n / s
	idx.resize(m * m * 6)
	var o := 0
	for iz in range(0, n, s):
		for ix in range(0, n, s):
			var v00 := iz * nv + ix
			var v10 := v00 + s
			var v01 := v00 + s * nv
			var v11 := v01 + s
			# clockwise seen from above (Godot front faces)
			idx[o] = v00; idx[o + 1] = v10; idx[o + 2] = v01
			idx[o + 3] = v10; idx[o + 4] = v11; idx[o + 5] = v01
			o += 6
	# skirts at this level's spacing, both windings (seen from either side)
	for line in edges:
		var i := 0
		while i + s < line.size():
			var a: int = line[i]
			var b: int = line[i + s]
			var a2: int = skirt_of[a]
			var b2: int = skirt_of[b]
			idx.append_array(PackedInt32Array([a, b, a2, b, b2, a2, a, a2, b, b, a2, b2]))
			i += s
	return idx

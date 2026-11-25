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
const LIST_NAMES := ["trunk", "trunk_pale", "trunk_pine", "blob", "pine", "rock", "pebble", "grass", "daisy", "tulip", "spike", "cactus0", "cactus1", "cactus2", "cactus3", "cactus4",
	"bush", "bush1", "bush2", "bushdry", "log", "root", "stick", "fern", "mushroom", "weed", "plank", "beam", "post", "rail", "picket", "stake", "pole", "signboard"]
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
static var SAV_LEAVES: Array = []   # savanna umbrella trees
static var REEDS: Array = []        # wetland reeds
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
	# the wooden features' planks in the ranch fences' weathered wood (user 2026-11-25: "same wood as the fence planks")
	PLANKS = L.call([0x8b6a4a, 0x9a7650, 0x7d5e40, 0x85704f])
	BEAM = TerrainField.lin(0x6e5236)
	CACTI = L.call([0x4f8a3c, 0x5c9a45, 0x6b9e4a])
	BUSHES = L.call([0x3f7f33, 0x4c8c38, 0x5a8f3a, 0x6a9a3e, 0x7a8f3a])
	FERNS = L.call([0x3f8a35, 0x4f9a3c, 0x5ea544, 0x8a9a3a])
	SHROOMS = L.call([0xc8382c, 0xb5652e, 0xd9b27a, 0xe8dcc0, 0x8a5a36])
	SCRUB = L.call([0x9a7a48, 0xb08a52, 0x8c6c3e, 0x7f8a4a])
	SAV_LEAVES = L.call([0x8a9a3a, 0x9aa844, 0x7a8a34, 0xa8a64a])
	REEDS = L.call([0x7a9a3c, 0x8aa844, 0x6a8a38, 0xa0a850])
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
	var mk := 1
	if MESH_K > 1 and not (f is TerrainField) and f.route_dist(ox, oz) < MESH_NEAR:
		# finer ground mesh (the textures keep N + 1 texels): the nearest chunks draw 0.25 m triangles where the ground has detail,
		# the coarser LODs (the old 0.5 m grid and below) take over by distance / flatness (_ground_lods keys them by real error)
		var fm: Dictionary = f.fine_ground(ox, oz, N, MESH_K)
		verts = fm["verts"]; norms = fm["norms"]; uvs = fm["uvs"]
		mk = MESH_K
		out["GF"] = fm["H"]   # the drawn (fine) heights, for the drawn tyres' fit (Terrain.mesh_height)
		out["MN"] = N * mk
	_ground_lods(verts, norms, uvs, N * mk, mk)   # adds edge skirts to the vertex arrays
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
	_arches()
	_boards()
	_dist_signs()
	_line_signs()
	_tape()
	for k in colliders:
		if k.has("tape"):
			blocked.append([k["x"], k["z"], 0.9])
	_stage("manmade")
	_bend_trees()
	_roots()
	if _root_st != null:
		_root_st.generate_normals()
		_root_st.generate_tangents()
		out["roots"] = _root_st.commit_to_arrays()
		_root_st = null
	_trees(ox, oz)
	_rocks(ox, oz)
	_stage("trees+rocks")
	_tufts(ox, oz)
	_stage("tufts")
	_trail_clutter(ox, oz)
	_berm_clutter(ox, oz)
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
	# the trail's own frame for the ground shader's rider lines / tyre marks / puddles (no mipmaps: plain data)
	var TRa: PackedFloat32Array = gs["TR"]
	var T2a: PackedFloat32Array = gs["T2"]
	out["trail_img"] = Image.create_from_data(NV, NV, false, Image.FORMAT_RGBAF, TRa.to_byte_array())
	var pT := PackedByteArray(); pT.resize(NV * NV * 4)
	for o in NV * NV * 4:
		pT[o] = roundi(clampf(T2a[o], 0, 1) * 255)
	out["trail2_img"] = Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pT)
	var T3a: PackedFloat32Array = gs["T3"]
	var T4a: PackedFloat32Array = gs["T4"]
	var T5a: PackedFloat32Array = gs["T5"]
	var pA := PackedByteArray(); pA.resize(NV * NV * 4)   # R = riders in the air, G = corner load, B = how narrow the trail is
	for o in NV * NV:
		pA[o * 4] = roundi(clampf(T3a[o], 0, 1) * 255)
		pA[o * 4 + 1] = roundi(clampf(T4a[o], 0, 1) * 255)
		pA[o * 4 + 2] = roundi(clampf(T5a[o], 0, 1) * 255)
		pA[o * 4 + 3] = 255
	out["trail3_img"] = Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pA)
	# where puddles can be (world/trail_puddle.gd: tyre dust stops over them); empty for chunks with no wet road
	out["pud"] = TrailPuddle.table(TRa, T2a, TW, norms, NV)
	# ---- grass field data (world/grass_field.gd): the ground's own heights + land colour, density in alpha ----
	var DRY: PackedFloat32Array = gs["DRY"]
	var pK := PackedByteArray(); pK.resize(NV * NV * 4)
	var gh := PackedFloat32Array(); gh.resize(NV * NV)
	for iz in NV:
		for ix in NV:
			var o := iz * NV + ix
			var h: float = G[(iz + 1) * W + ix + 1]
			gh[o] = h
			var g: Color = LG[o]
			var snow := clampf((minf(g.r, minf(g.g, g.b)) - 0.45) * 4.0, 0.0, 1.0)
			var den := (1.0 - sm(0.04, 0.4, TW[o])) * (1.0 - sm(0.1, 0.6, SW[o])) * sm(WATER + 0.25, WATER + 0.8, h)
			den *= (1.0 - sm(0.7, 0.97, DRY[o])) * (1.0 - snow) * (0.55 + 0.45 * ao[o])
			pK[o * 4] = pG[o * 4]; pK[o * 4 + 1] = pG[o * 4 + 1]; pK[o * 4 + 2] = pG[o * 4 + 2]
			pK[o * 4 + 3] = roundi(clampf(den, 0, 1) * 255)
	for sb in blocked:   # sheds, tape stakes, billboards: no grass through their floors / feet
		_grass_hole(pK, NV, d, ox, oz, sb[0], sb[1], minf(float(sb[2]), 3.0))
	out["grass_img"] = Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pK)
	out["grass_h"] = Image.create_from_data(NV, NV, false, Image.FORMAT_RF, gh.to_byte_array())
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
	var pre_b := PackedFloat64Array(); pre_b.resize(NV * NV * 4)
	var TR := PackedFloat32Array(); TR.resize(NV * NV * 4)   # trail frame for ground.gdshader: across, line offset, along, run-off skid's place
	var T2 := PackedFloat32Array(); T2.resize(NV * NV * 4)   # road, dry biome, built jump, run-off skid's strength
	var T3 := PackedFloat32Array(); T3.resize(NV * NV)       # riders in the air over a jump here
	var T4 := PackedFloat32Array(); T4.resize(NV * NV)       # corner load: how hard riders press the line (0 straight .. 1 tight bend)
	var T5 := PackedFloat32Array(); T5.resize(NV * NV)       # how narrow the trail is (0 a road .. 1 a forest singletrack): the drawn edge wanders less
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
				pre_b[o * 4] = f.cp_dry
				pre_b[o * 4 + 1] = f.cp_rug
				pre_b[o * 4 + 2] = f.cp_cold
				pre_b[o * 4 + 3] = f.cp_ash
				var jm: float = f.jump_mask(x, z)
				var ac: float = f.across(x, z)
				f.query(x, z)
				var on: bool = f.q_d < f.q_w + 2.6
				TR[o * 4] = clampf(ac, -20.0, 20.0)
				TR[o * 4 + 1] = f.line_off(x, z)
				TR[o * 4 + 2] = f.q_s if on else x * 0.6 + z * 0.8
				TR[o * 4 + 3] = (f.cRO[f.q_i] + (f.cRO[f.q_i + 1] - f.cRO[f.q_i]) * f.q_t) if on else 0.0
				T2[o * 4] = f.q_rd if on else 0.0
				T2[o * 4 + 1] = f.cp_dry
				T2[o * 4 + 2] = jm
				T3[o] = f.fo_air
				T4[o] = TerrainField.corner_load(f.q_k) if on else 0.0
				T5[o] = clampf(1.6 - f.q_w, 0.0, 1.0) if on else 0.0
				T2[o * 4 + 3] = (f.cROS[f.q_i] + (f.cROS[f.q_i + 1] - f.cROS[f.q_i]) * f.q_t) if on else 0.0
				if on:
					# same as the C# bake: average the distance to the 2 m-piece centreline over ~1 m (no facets in bends)
					var sum := ac * 0.36
					var all_on := true
					for off in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
						var a4: float = f.across(x + off.x, z + off.y)
						all_on = f.q_d < f.q_w + 2.6
						if not all_on:
							break
						sum += a4 * 0.16
					if all_on:
						TR[o * 4] = clampf(sum, -20.0, 20.0)
	var verts := PackedVector3Array(); verts.resize(NV * NV)
	var norms := PackedVector3Array(); norms.resize(NV * NV)
	var uvs := PackedVector2Array(); uvs.resize(NV * NV)
	var LG := PackedColorArray(); LG.resize(NV * NV)
	var LD := PackedColorArray(); LD.resize(NV * NV)
	var TW := PackedFloat32Array(); TW.resize(NV * NV)
	var SW := PackedFloat32Array(); SW.resize(NV * NV)
	var DRY := PackedFloat32Array(); DRY.resize(NV * NV)
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
			f.color_post(lx + ox, lz + oz, h, nv.y, pre_b[o * 4], pre_b[o * 4 + 1], pre_b[o * 4 + 2], pre_b[o * 4 + 3])
			TW[o] = pre_t[o]
			SW[o] = f.cl_steep
			DRY[o] = maxf(pre_b[o * 4], pre_b[o * 4 + 3])   # (no grass on ash)
			LG[o] = f.cl_g
			LD[o] = f.cl_d
	return {"G": G, "verts": verts, "norms": norms, "uvs": uvs, "LG": LG, "LD": LD, "TW": TW, "SW": SW, "DRY": DRY, "TR": TR, "T2": T2, "T3": T3, "T4": T4, "T5": T5}


## clears grass density (alpha of the grass_img bytes) within r of (x, z), soft over the outer 30 %
static func _grass_hole(pK: PackedByteArray, NV: int, d: float, ox: float, oz: float, x: float, z: float, r: float) -> void:
	var fx := (x - ox + S / 2) / d
	var fz := (z - oz + S / 2) / d
	var rr := ceili(r / d)
	for iz in range(maxi(0, floori(fz - rr)), mini(NV - 1, ceili(fz + rr)) + 1):
		for ix in range(maxi(0, floori(fx - rr)), mini(NV - 1, ceili(fx + rr)) + 1):
			var dd := Vector2(ix - fx, iz - fz).length() * d
			if dd < r:
				var o := (iz * NV + ix) * 4 + 3
				pK[o] = roundi(pK[o] * clampf((dd / r - 0.7) / 0.3, 0.0, 1.0))


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
## wild = a fence along a side path (not the course's own): it keeps WILD_FENCE_CLEAR m off the road's edge, where the tape and
## the course fences are (a wild fence running beside the road next to the tape looked wrong). BMX_OLD_MARKING=1 = no such rule.
const WILD_FENCE_CLEAR := 6.5
func _post_ok(x: float, z: float, wild := false) -> float:
	var h := height(x, z)
	if h < WATER + 0.3 or sqrt(x * x + z * z) < 14 or f.trail(x, z) > 0.15 or f.jump_mask(x, z) > 0.02 or is_blocked(x, z, 0.5):
		return NAN
	if wild and not TrailCourse.OLD_MARKING and f.route_dist(x, z) < f.q_w + WILD_FENCE_CLEAR:
		return NAN
	return h


func _run_fence(pts: Array, style: String, rs: WorldRng, mn: int = 3, wild := false) -> void:
	var cur := []
	for p in pts:
		var x: float = p[0]
		var z: float = p[1]
		var h := _post_ok(x, z, wild)
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
	_run_fence(pts, "picket" if rs.next() < 0.35 else "ranch", rs, 3, true)


func _course_fences(rs: WorldRng) -> void:
	var C: TrailCourse = f.course
	for fi in C.chunk_fences.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var fc: Dictionary = C.fences[fi]
		var P: Array = fc["posts"]
		var cur := []
		for k in P.size():
			# a gap where a B-line crosses: the run ends before this post and starts again after it
			if _on_bline(P[k][0], P[k][1], 1.6) or (k + 1 < P.size() and _on_bline((P[k][0] + P[k + 1][0]) * 0.5, (P[k][1] + P[k + 1][1]) * 0.5, 1.6)):
				if cur.size() > 1:
					_run_fence(cur, fc["style"], rs, 2)
				cur = []
				continue
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
			colliders.append({"x": x, "z": z, "r": (sx + sc) * 0.45, "top": h - sc * 0.3 + sy * 0.9, "base": f.ground(x, z), "sink": sc * 0.3})


# ---------------- sponsor gates ----------------
## big gantries over the trail with a banner on top (data only; Terrain builds the nodes)
func _gates() -> void:
	var C: TrailCourse = f.course
	var list := []
	for i in C.chunk_gates.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var half: float = C.W[i] + 1.3
		var nx := -tz
		var nz := tx
		var cxp: float = C.X[i]
		var czp: float = C.Z[i]
		if sqrt(cxp * cxp + czp * czp) < 14:
			continue
		var ok := true
		var hl := height(cxp - nx * half, czp - nz * half)
		var hr := height(cxp + nx * half, czp + nz * half)
		var hc := height(cxp, czp)
		if hl < WATER + 0.2 or hr < WATER + 0.2 or absf(hl - hr) > 3.0:
			continue
		# not on a jump / ramp / bridge (check the posts and the track either side)
		for s in [-1.0, 0.0, 1.0]:
			for off in [-half, 0.0, half]:
				f.jump_eval(cxp + tx * s * 3.0 + nx * off, czp + tz * s * 3.0 + nz * off)
				if f.fo_h > 0.05:
					ok = false
		if not ok:
			continue
		list.append({"x": cxp, "z": czp, "tx": tx, "tz": tz, "half": half, "hl": hl, "hr": hr, "hc": hc, "i": i})
	if not list.is_empty():
		out["gates"] = list
	if OS.get_environment("BMX_GATE_PROBE") != "":
		print("GATES chunk=", cx, ",", cz, " cand=", C.chunk_gates.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()).size(), " placed=", list.size(), " boards_cand=", C.chunk_boards.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()).size())


## rare rock tunnels / cliff overhangs over the trail (data only; Terrain builds the nodes)
func _arches() -> void:
	var C: TrailCourse = f.course
	var list := []
	for code in C.chunk_arches.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var i: int = code >> 1
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var half: float = C.W[i] + 1.3
		var nx := -tz
		var nz := tx
		var cxp: float = C.X[i]
		var czp: float = C.Z[i]
		if sqrt(cxp * cxp + czp * czp) < 30:
			continue
		var hl := height(cxp - nx * half, czp - nz * half)
		var hr := height(cxp + nx * half, czp + nz * half)
		if hl < WATER + 0.2 or hr < WATER + 0.2 or absf(hl - hr) > 4.0:
			continue
		var ok := true
		for s in [-9.0, 0.0, 9.0]:
			f.jump_eval(cxp + tx * s, czp + tz * s)
			if f.fo_h > 0.05:
				ok = false
		if ok:
			list.append({"x": cxp, "z": czp, "tx": tx, "tz": tz, "half": half, "hl": hl, "hr": hr,
				"hc": height(cxp, czp), "i": i, "kind": code & 1})
	if OS.get_environment("BMX_GATE_PROBE") != "":
		print("ARCHES chunk=", cx, ",", cz, " cand=", C.chunk_arches.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()).size(), " placed=", list.size())
	if not list.is_empty():
		out["arches"] = list


## wooden roadside billboards: a fence-style panel (so the bike can smash it) of two posts and
## three painted planks, angled a little towards the trail, with sponsor text added by Terrain
func _boards() -> void:
	var C: TrailCourse = f.course
	for i in C.chunk_boards.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var side0 := 1.0 if (i / TrailCourse.BOARD_EVERY) % 2 == 0 else -1.0
		var side := side0
		var nx := 0.0
		var nz := 0.0
		var bx := 0.0
		var bz := 0.0
		var h := 0.0
		var found := false
		# a clear spot beyond the fences / tape: this side first (near, then further out), then the other
		for cand in [[side0, 3.4], [side0, 5.6], [side0, 8.0], [-side0, 3.4], [-side0, 5.6], [-side0, 8.0]]:
			side = cand[0]
			nx = -tz * side
			nz = tx * side
			bx = C.X[i] + nx * (C.W[i] + cand[1])
			bz = C.Z[i] + nz * (C.W[i] + cand[1])
			if sqrt(bx * bx + bz * bz) < 12:
				continue
			h = height(bx, bz)
			# (the board runs across the trail, turned ~25 deg: the same direction as below)
			var a2 := 0.45 * side
			if _sign_spot_ok(bx, bz, nx * cos(a2) - nz * sin(a2), nx * sin(a2) + nz * cos(a2), 1.9):
				found = true
				break
		if OS.get_environment("BMX_GATE_PROBE") != "":
			print("BOARD i=", i, " found=", found, " at ", bx, ",", bz, " cx=", cx, " cz=", cz)
		if not found:
			continue
		# board direction: across the trail, turned ~25 degrees towards the riders coming
		var ang := 0.45 * side
		var ca := cos(ang)
		var sa := sin(ang)
		var dx := nx * ca - nz * sa
		var dz := nx * sa + nz * ca
		var px := dz
		var pz := -dx
		if px * tx + pz * tz > 0.0:
			px = -px
			pz = -pz   # face normal points back up the trail, at the riders
		var spn := TrailGate.sponsor(i + 5)
		var panel := {"broken": false, "parts": [], "style": "billboard"}
		var W := 3.6
		var add := func(kind: String, pos: Vector3, b: Basis, scl: Vector3, c: Color) -> void:
			var bs := _scaled(b, scl.x, scl.y, scl.z)
			var k := _push(kind, bs, pos, c)
			panel["parts"].append({"kind": kind, "i": k, "col": c, "xform": Transform3D(bs, pos), "scale": scl})
		var yaw := atan2(-dz, dx)
		var rb := Basis(Vector3.UP, yaw)
		var postc := TerrainField.lin(0x6b4a30)
		for s in [-1.0, 1.0]:
			var ppx: float = bx + dx * s * (W / 2 - 0.2) - px * 0.12
			var ppz: float = bz + dz * s * (W / 2 - 0.2) - pz * 0.12
			var gh := height(ppx, ppz)
			add.call("post", Vector3(ppx, gh + 2.5 / 2 - 0.18, ppz), euler_xyz(0, yaw, 0), Vector3(1, 2.5, 1), postc)
		# the face: one painted plank board (3 planks, the sponsor printed on, both sides: SignTex.billboard), its
		# own mesh like the distance sign's plate (Terrain._panel_labels), smashed off in one piece. Over the HIGHEST
		# ground under it (on a slope the centre's height buried one end; user 2026-11-25)
		var hmax := h
		for s2 in [-1.0, -0.5, 0.5, 1.0]:
			hmax = maxf(hmax, height(bx + dx * s2 * W / 2, bz + dz * s2 * W / 2))
		var y0: float = hmax + 0.55
		for s3 in [-1.0, 0.0, 1.0]:   # (nothing else stands here now: signs, other boards)
			blocked.append([bx + dx * s3 * W * 0.4, bz + dz * s3 * W * 0.4, 1.1])
		var plate_x := Transform3D(_scaled(rb, W, 1.5, 0.06), Vector3(bx, y0 + 0.75, bz))
		panel["parts"].append({"kind": "signboard", "i": -1, "col": Color.WHITE, "xform": plate_x, "scale": Vector3(W, 1.5, 0.06)})
		panel["plate"] = {"sp": spn, "size": Vector2(W, 1.5), "planks": 3, "xform": plate_x}
		var m := ceili(W / 0.45)
		for k in m + 1:
			var t := float(k) / m - 0.5
			colliders.append({"x": bx + dx * W * t, "z": bz + dz * W * t, "r": 0.3, "fence": panel, "fence_style": "billboard"})
		panel["cx"] = bx
		panel["cz"] = bz
		panels.append(panel)


## line-choice signs (B-lines, TerrainField.alt_feats): where a B-line leaves the trail, a sign on a post between the two
## lines facing the riders: the A line (the built feature) black, the B line (round it) blue (trail difficulty colours)
func _line_signs() -> void:
	var C: TrailCourse = f.course
	for af in f.alt_feats:
		var rf = f.route_feats[af[0]]
		var o: int = int(af[1]) * 7
		var side: float = f.alt_lines[o + 6]
		var s: float = rf.s - TerrainField.ALT_IN - 6.0   # 6 m before the split, beside the trail past the tape, on the B-line's side
		var p := C.at(s)
		var bx: float = p[0] + float(-p[3]) * side * (float(C.W[int(p[4])]) + 2.4)
		var bz: float = p[1] + float(p[2]) * side * (float(C.W[int(p[4])]) + 2.4)
		if WorldRng.jround(bx / S) != cx or WorldRng.jround(bz / S) != cz:
			continue
		var tx: float = p[2]
		var tz: float = p[3]
		var names := {"table": "TABLE", "kicker": "KICKER", "tableLine": "JUMP LINE", "woodDrop": "DROP", "double": "DOUBLE",
			"doubleLine": "JUMP LINE", "flow": "KICKER", "woodKicker": "WOOD KICKER"}
		_table_sign(bx, height(bx, bz), bz, -tx, -tz, "A LINE", str(names.get(rf.type, "JUMP")), TerrainField.lin(0x111111), -0.35 * side)
		var b2x := bx + float(-p[3]) * side * 0.95
		var b2z := bz + float(p[2]) * side * 0.95
		_table_sign(b2x, height(b2x, b2z), b2z, -tx, -tz, "B LINE", "EASIER", TerrainField.lin(0x0057d8), 0.35 * side)
		blocked.append([bx, bz, 1.2])


## a small table sign on a stick (the distance sign's build): face looking along (px, pz), turned by tw, field colour
## col, big text over a small one
func _table_sign(bx: float, h: float, bz: float, px: float, pz: float, big: String, small_t: String, col: Color, tw: float) -> void:
	var yaw := atan2(px, pz) + tw
	var fx := sin(yaw)
	var fz := cos(yaw)
	var rb := Basis(Vector3.UP, yaw)
	var base := Vector3(bx, h - 0.15, bz)
	var panel := {"broken": false, "parts": [], "style": "billboard"}
	var add := func(kind: String, off: Vector3, scl: Vector3, c: Color) -> void:
		var bs := _scaled(rb, scl.x, scl.y, scl.z)
		var pos: Vector3 = base + off
		var k := _push(kind, bs, pos, c)
		panel["parts"].append({"kind": kind, "i": k, "col": c, "xform": Transform3D(bs, pos), "scale": scl})
	var white_c := TerrainField.lin(0xffffff)
	white_c.a = 1.0
	col.a = 1.0
	add.call("post", Vector3(0, 0.58, 0), Vector3(0.7, 1.1, 0.5), TerrainField.lin(0x6b4a30))
	add.call("rail", Vector3(0, 1.505, 0), Vector3(0.81, 0.81, 0.07), white_c)
	add.call("rail", Vector3(0, 1.596, 0), Vector3(0.81, 0.628, 0.09), col)
	colliders.append({"x": bx, "z": bz, "r": 0.3, "fence": panel, "fence_style": "billboard"})
	var nrm := Vector3(fx, 0, fz)
	var lb := Basis(Vector3(fz, 0, -fx), Vector3.UP, Vector3(fx, 0, fz))
	panel["cx"] = bx
	panel["cz"] = bz
	panel["bb"] = {"text": big, "col": Color.WHITE, "w": 0.74, "h": 0.3, "basis": lb, "at": base + Vector3(0, 1.596, 0), "nrm": nrm}
	panel["bb_more"] = [{"text": small_t, "col": Color.html("#313131"), "w": 0.7, "h": 0.1, "basis": lb, "at": base + Vector3(0, 1.191, 0), "nrm": nrm}]
	panels.append(panel)


## a roadside board / sign fits at (bx, bz) running along (dx, dz) half m each way: dry, off the jumps, clear of fences (their
## colliders), other boards and signs (blocked) and the tape stakes, and on ground level enough that it isn't half buried
## (user 2026-11-25: boards / signs / fences overlapped, boards sat clipped into slopes)
func _sign_spot_ok(bx: float, bz: float, dx: float, dz: float, half: float) -> bool:
	var why := _sign_spot_why(bx, bz, dx, dz, half)
	if why != "" and OS.get_environment("BMX_GATE_PROBE") != "":
		print("SIGNSPOT no: ", why)
	return why == ""


func _sign_spot_why(bx: float, bz: float, dx: float, dz: float, half: float) -> String:
	var hs := []
	for s: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var x: float = bx + dx * s * half
		var z: float = bz + dz * s * half
		var h := height(x, z)
		if h < WATER + 0.4:
			return "water"
		f.jump_eval(x, z)
		if f.fo_h > 0.05:
			return "jump"
		if is_blocked(x, z, -0.6):   # (fence panels reserve a generous 1.6 m: their posts are checked exactly below)
			return "blocked"
		if f.trail(x, z) > 0.05:
			return "trail"
		if f.q_d < f.q_w + 2.4:   # (the race tape runs W + 1.7 out: planted after the boards)
			return "tape line"
		for c in colliders:
			if c.has("fence") or c.has("tape"):
				var ex: float = c.x - x
				var ez: float = c.z - z
				if ex * ex + ez * ez < 0.9 * 0.9:
					return "fence"
		hs.append(h)
	if hs.max() - hs.min() > 0.45:
		return "slope along %.2f" % (hs.max() - hs.min())
	# and not on a steep bank front to back
	var fbx := -dz * 0.7
	var fbz := dx * 0.7
	var fb := absf(height(bx + fbx, bz + fbz) - height(bx - fbx, bz - fbz))
	return "" if fb < 0.5 else "slope across %.2f" % fb

## distance tables: a square printed plate on a plain stick beside the road every 5 km, each leaning
## a little differently (smashable like the billboards)
func _dist_signs() -> void:
	var C: TrailCourse = f.course
	for i in C.chunk_signs.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var tx: float = C.TX[i]
		var tz: float = C.TZ[i]
		var rr := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var rr2 := fposmod(sin(i * 78.233 + 1.7) * 24634.6345, 1.0)
		var side0 := 1.0 if rr > 0.5 else -1.0
		var found := false
		var bx := 0.0
		var bz := 0.0
		var h := 0.0
		var nx := 0.0
		var nz := 0.0
		for cand in [[side0, 2.6], [side0, 4.0], [-side0, 2.6], [-side0, 4.0]]:
			nx = -tz * cand[0]
			nz = tx * cand[0]
			bx = C.X[i] + nx * (C.W[i] + cand[1])
			bz = C.Z[i] + nz * (C.W[i] + cand[1])
			h = height(bx, bz)
			if _sign_spot_ok(bx, bz, tx, tz, 0.45):
				found = true
				break
		if not found:
			continue
		blocked.append([bx, bz, 1.0])
		# the face looks back up the trail at the riders
		var px := -tx
		var pz := -tz
		var yaw := atan2(px, pz) + (rr2 - 0.5) * 0.5
		var fx := sin(yaw)   # face normal (the box's z axis) after the random turn
		var fz := cos(yaw)
		# a little lean in a random direction (up to ~9 deg)
		var lean := 0.06 + 0.1 * fposmod(rr * 91.7, 1.0)
		var la := rr2 * TAU
		var R := Basis(Vector3(cos(la), 0, sin(la)).cross(Vector3.UP).normalized(), -lean)
		var rb := R * Basis(Vector3.UP, yaw)
		var base := Vector3(bx, h - 0.15, bz)
		var panel := {"broken": false, "parts": [], "style": "billboard"}
		var add := func(kind: String, off: Vector3, scl: Vector3, c: Color) -> void:
			var bs := _scaled(rb, scl.x, scl.y, scl.z)
			var pos: Vector3 = base + rb * off   # in the sign's own (yawed + leaning) frame
			var k := _push(kind, bs, pos, c)
			panel["parts"].append({"kind": kind, "i": k, "col": c, "xform": Transform3D(bs, pos), "scale": scl})
		# a plain square stick with a thin printed plate bolted to its front, like a real roadside sign. The plate
		# carries the Figma "table sign" layout, printed per distance by SignTex (number + DISTANCE in the texture)
		var post_c := TerrainField.lin(0x6b4a30)
		const PLATE := 0.8      # m, square
		const PLATE_T := 0.02   # plate thickness
		const POLE := 0.05      # stick cross-section
		const PLATE_Y := 1.45   # plate centre above the ground
		var top := PLATE_Y + PLATE / 2 - 0.04
		add.call("pole", Vector3(0, (top - 0.15) / 2, 0), Vector3(POLE, top + 0.15, POLE), post_c)   # ground (-0.15) .. just under the plate top
		var plate_z := POLE / 2 + PLATE_T / 2 + 0.002
		# the plate is its own mesh (Terrain._panel_labels) with this distance's printed texture (SignTex), not in a list
		var plate_s := Vector3(PLATE, PLATE, PLATE_T)
		var plate_x := Transform3D(_scaled(rb, PLATE, PLATE, PLATE_T), base + rb * Vector3(0, PLATE_Y, plate_z))
		panel["parts"].append({"kind": "signboard", "i": -1, "col": Color.WHITE, "xform": plate_x, "scale": plate_s})
		colliders.append({"x": bx, "z": bz, "r": 0.3, "fence": panel, "fence_style": "billboard"})
		var km := int(round(float(i) * 2.0 / 1000.0))
		panel["cx"] = bx
		panel["cz"] = bz
		panel["plate"] = {"km": km, "xform": plate_x}
		if OS.get_environment("BMX_GATE_PROBE") != "":
			print("DISTSIGN i=", i, " at ", bx, ",", h, ",", bz)
		panels.append(panel)


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
	if _on_bline(x, z, 1.2):   # (a gap in the tape where a B-line leaves / joins)
		return []
	return [x, z, h]


## within r of a B-line (TerrainField.alt_near): tape and fences leave a gap there
func _on_bline(x: float, z: float, r: float) -> bool:
	return f.alt_dist(x, z) < TerrainField.ALT_W + r


func _tape() -> void:
	var stakes_all: Array = f.course.stakes
	var spans := []
	var stake_pos := []
	for k in f.course.chunk_stakes.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var st: Dictionary = stakes_all[k]
		var b := _plant(st)
		if b.is_empty():
			continue
		stake_pos.append([b, k])
		var a := []
		if st["prev"] >= 0:
			a = _plant(stakes_all[st["prev"]])
		if a.is_empty() or absf(b[2] - a[2]) > 2:
			continue
		spans.append({"a": a, "b": b, "k": k, "ka": st["prev"], "side": st["side"], "caution": st["caution"]})
	var stakes := []   # [stake index, instance, x, ground y, z, tilt]: what Terrain.stake_yank needs to knock one over
	for e in stake_pos:
		var s: Array = e[0]
		var r := sin(s[0] * 12.9 + s[1] * 78.2) * 0.04
		stakes.append([e[1], _push("stake", euler_xyz(r, 0, -r), Vector3(s[0], s[2], s[1]), Color(1, 1, 1)), s[0], s[2], s[1], r])
	if not stakes.is_empty():
		out["stakes"] = stakes
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
		var rec := {"broken": false, "v0": pos.size(), "pts": pts, "cols": cols, "len": L, "ka": sp["ka"], "kb": kk}
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
const TREE_TRIES := 100   # placement tries per chunk (90 read thin, 140 too dense: user 2026-11-22)
const TREE_K := 1.4        # every tree this much bigger (they read small next to the rider)
const TALL_CROWN := 6.5    # m: the lowest a tall forest pine's crown starts (over the trail camera)

## a crown of radius r at (x, z) stays clear of the trail and its paths (the trees' own spot check only tests the trunk)
func _crown_clear(x: float, z: float, r: float) -> bool:
	for a in 6:
		var px := x + cos(a * 1.047) * r
		var pz := z + sin(a * 1.047) * r
		if f.trail(px, pz) > 0.02 or absf(f.pathN(px, pz)) < 0.1 or f.jump_mask(px, pz) > 0:
			return false
	return true

## tree roots across a forest singletrack (TrailCourse.roots; user: "spread splines along the terrain with some root math,
## then a simple sweep that follows the terrain, a smart rooting system"). At each spot a pine stands 1.9-3 m off the trail
## and its roots GROW out of its foot: 4-6 main roots (2-3 aimed across the trail, long enough to reach the far side, the
## rest round the tree), each a random walk with a smooth wandering curvature, tapering, branching now and then (two
## levels); every root is then swept as a tube whose rings sit ON the ground under them (_sweep). Where a root crosses the
## trail the tyres feel it (a chain of low domes)
var _root_st: SurfaceTool = null   # this chunk's roots (out["roots"]: Terrain makes one mesh)


func _roots() -> void:
	var C: TrailCourse = f.course
	for i in C.chunk_roots.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		_root_system(C, i)


func _root_system(C: TrailCourse, i: int) -> void:
	var rr := WorldRng.new(f.seed_value * 7919 + i * 104729 + 17)
	var nx: float = -C.TZ[i]
	var nz: float = C.TX[i]
	var k: float = C.KAP[i]
	var side := 1.0 if rr.next() < 0.5 else -1.0
	if absf(k) > 1.0 / 25.0:
		side = -signf(k)   # in a tight bend the tree stands on the outside (riders cut the inside)
	var off: float = C.W[i] + 2.2 + rr.next() * 1.2 + (1.0 if absf(k) > 1.0 / 25.0 else 0.0)   # (closer, riders swinging through the turns hit the trunk)
	var tx: float = C.X[i] + nx * off * side
	var tz: float = C.Z[i] + nz * off * side
	if f.jump_mask(tx, tz) > 0 or is_blocked(tx, tz, 0.6):
		return
	var h := height(tx, tz)
	if h < WATER + 0.6:
		return
	# the tree
	var sc := (1.1 + rr.next() * 0.45) * TREE_K
	var py := sc * (1.6 + rr.next() * 0.6)
	var cb := maxf(TALL_CROWN, sc * 3.2) + rr.next() * 2.5
	var yaw := rr.next() * 6.28
	put("trunk_pine" if rr.next() < 0.45 else "trunk", tx, h - 0.1, tz, sc, cb + 0.2 + py * 0.15, sc, yaw)
	put("pine", tx, h + cb, tz, sc * 0.95, py, sc * 0.95, yaw, PINES[int(rr.next() * PINES.size())])
	var tr := 0.13 * sc   # the trunk's radius at its foot
	colliders.append({"x": tx, "z": tz, "r": tr + 0.03, "ceil": h + cb + 2.8 * py})
	blocked.append([tx, tz, tr + 0.4])
	# its roots
	if _root_st == null:
		_root_st = SurfaceTool.new()
		_root_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tint := Color(0.85 + rr.next() * 0.3, 0.82 + rr.next() * 0.25, 0.8 + rr.next() * 0.2)
	var toward := atan2(-nz * side, -nx * side)   # from the tree across the trail
	var cross := 2 + int(rr.next() * 2.0)
	var count := cross + 2 + int(rr.next() * 2.0)
	for q in count:
		var head: float
		var len: float
		if q < cross:
			head = toward + (rr.next() - 0.5) * 1.1
			len = off + 1.2 + rr.next() * 1.6   # past the far edge of the trail
		else:
			head = toward + PI * (0.35 + rr.next() * 1.3) * (1.0 if rr.next() < 0.5 else -1.0)
			len = 1.0 + rr.next() * 1.4
		var st := Vector2(tx, tz) + Vector2(cos(head), sin(head)) * tr * 0.8
		_grow_root(st, head, len, (0.15 + rr.next() * 0.07) * sc / TREE_K, 0, rr, tint)


func _grow_root(p: Vector2, head: float, len: float, r0: float, depth: int, rr: WorldRng, tint: Color) -> void:
	const STEP := 0.12
	var n := maxi(3, int(len / STEP))
	var path := PackedVector2Array([p])
	var hd := head
	var curv := (rr.next() - 0.5) * 0.3
	for s in n:
		curv = curv * 0.86 + (rr.next() - 0.5) * 0.32   # a smooth wander: roots bend, never kink
		hd += curv * 0.22
		p += Vector2(cos(hd), sin(hd)) * STEP
		path.append(p)
		if depth < 2 and s > n * 0.2 and s < n * 0.8 and rr.next() < 0.045:
			var tb := float(s) / n
			var rb := lerpf(r0, r0 * 0.35, tb) * 0.75
			if rb > 0.015:
				_grow_root(p, hd + (0.45 + rr.next() * 0.6) * (1.0 if rr.next() < 0.5 else -1.0), (len - s * STEP) * (0.35 + rr.next() * 0.35), rb, depth + 1, rr, tint)
	_sweep(path, r0, maxf(0.025, r0 * 0.35), rr.next() * 6.28, tint, depth == 0)


## a tube along a path ON the ground: every ring at the ground's height under it, turned to its slope, its top 0.25-0.6 x
## its radius proud (more at the tree, where it flares); where it crosses the trail, low domes the tyres feel
func _sweep(path: PackedVector2Array, r0: float, r1: float, ph: float, tint: Color, main: bool) -> void:
	const NR := 7
	var m := path.size()
	var rings := []
	var vlen := 0.0
	for i in m:
		var t := float(i) / (m - 1)
		var c2 := path[i]
		var d2 := (path[mini(i + 1, m - 1)] - path[maxi(i - 1, 0)]).normalized()
		if i > 0: vlen += (path[i] - path[i - 1]).length()
		var g := height(c2.x, c2.y)
		var nrm := Vector3(height(c2.x - 0.15, c2.y) - height(c2.x + 0.15, c2.y), 0.3, height(c2.x, c2.y - 0.15) - height(c2.x, c2.y + 0.15)).normalized()
		var flare := 1.0 + 0.7 * maxf(0.0, 1.0 - t * 8.0)   # thick where it leaves the trunk
		var r := lerpf(r0, r1, pow(t, 1.3)) * flare * (1.0 + 0.14 * sin(t * 23.0 + ph) + 0.07 * sin(t * 57.0 + ph))
		var proud := r * (0.4 + 0.3 * (0.5 + 0.5 * sin(t * 7.3 + ph)) + 0.35 * maxf(0.0, 1.0 - t * 6.0))
		# (+3.5 cm: the drawn ground carries a few cm of micro detail over the smooth height it reads; without it the roots
		# sank into it and read as thin cracks)
		var c := Vector3(c2.x, g, c2.y) + nrm * (proud - r * 0.7 + 0.035)
		var sd := Vector3(-d2.y, 0, d2.x)
		sd = (sd - nrm * sd.dot(nrm)).normalized()
		var ring := []
		for k in NR:
			var an := TAU * k / NR
			ring.append(c + sd * cos(an) * r + nrm * sin(an) * r * 0.7)
		rings.append([ring, vlen])
		if main and i % 3 == 1 and f.trail(c2.x, c2.y) > 0.25:
			colliders.append({"x": c2.x, "z": c2.y, "r": 0.2, "top": g + minf(0.07, proud), "base": g, "sink": 0.05})
	var st := _root_st
	for i in m - 1:
		var ra: Array = rings[i][0]; var rb: Array = rings[i + 1][0]
		var va: float = rings[i][1]; var vb: float = rings[i + 1][1]
		for k in NR:
			var k2 := (k + 1) % NR
			var u0 := float(k) / NR
			var u1 := float(k + 1) / NR
			for q in [[ra[k], u0, va], [rb[k], u0, vb], [rb[k2], u1, vb], [ra[k], u0, va], [rb[k2], u1, vb], [ra[k2], u1, va]]:
				st.set_color(tint)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])

## how far from the centreline a tree / stump / log may stand beside a forest singletrack (the last query's point):
## the narrow trail's dirt fades out within ~0.7 m, closer than a rider needs (bars, lean, running wide)
func _forest_clear() -> float:
	return f.q_w + (1.6 if absf(f.q_k) > 1.0 / 25.0 else 1.3)


## a big old pine on the inside of a tight forest bend (TrailCourse.bend_trees): the trail wraps round it
func _bend_trees() -> void:
	var C: TrailCourse = f.course
	for i in C.chunk_btrees.get(TrailCourse.chunk_key(cx, cz), PackedInt32Array()):
		var k: float = C.KAP[i]
		var sg := signf(k)
		var r := 1.0 / absf(k)
		var off := minf(C.W[i] + 1.6 + TrailCourse._hash(i, 71) * 1.2, r * 0.7)
		var x: float = C.X[i] - C.TZ[i] * off * sg
		var z: float = C.Z[i] + C.TX[i] * off * sg
		if f.jump_mask(x, z) > 0 or is_blocked(x, z, 0.5):
			continue
		var h := height(x, z)
		if h < WATER + 0.6:
			continue
		var sc := (1.75 + TrailCourse._hash(i, 72) * 0.55) * TREE_K
		var py := sc * (2.3 + TrailCourse._hash(i, 73) * 0.6)
		var yaw := TrailCourse._hash(i, 74) * 6.28
		var cb := maxf(TALL_CROWN + 2.0, sc * 3.6)   # an old giant: bare trunk high up, the crown over everything
		put("trunk", x, h - 0.15, z, sc, cb + 0.3 + py * 0.2, sc, yaw)
		put("pine", x, h + cb, z, sc * 1.05, py, sc * 1.05, yaw, PINES[int(TrailCourse._hash(i, 75) * PINES.size())])
		colliders.append({"x": x, "z": z, "r": 0.16 * sc + 0.02, "ceil": h + cb + 2.8 * py})
		blocked.append([x, z, 0.16 * sc + 0.4])
		# a few stones round its roots, on the side away from the trail (visual: inside the trunk's own clearance)
		for q in 4:
			var a := atan2(C.TX[i] * sg, -C.TZ[i] * sg) + (TrailCourse._hash(i, 80 + q) - 0.5) * 2.4
			var rr := 0.16 * sc + 0.35 + TrailCourse._hash(i, 90 + q) * 0.5
			var rx := x + cos(a) * rr
			var rz := z + sin(a) * rr
			var rs := 0.12 + TrailCourse._hash(i, 100 + q) * 0.2
			put("rock", rx, height(rx, rz) - rs * 0.3, rz, rs * 1.3, rs * 0.7, rs, TrailCourse._hash(i, 110 + q) * 6.28, null, 0.5)


func _trees(ox: float, oz: float) -> void:
	for i in TREE_TRIES:
		var x := ox + (rnd.next() - .5) * S
		var z := oz + (rnd.next() - .5) * S
		var forest: float = f.n(x + 400, z, TerrainField.I38)
		# beside the trail (within ~14 m) trees grow whatever the forest mask says: the road gets lined now and then
		var roadside: bool = TerrainField.trail_metres_of(f.pathN(x, z)) < 14.0 and f.n(x - 900, z + 300, TerrainField.I38) > -0.1
		# climate biomes (2026-11-25): pine forest is dense, alpine / wetland / savanna thin, ash fields nearly bare
		f.biome(x, z)
		var pf := 0.4 if roadside else sm(-0.25, 0.25, forest) * 0.9 + 0.05
		if not roadside:
			pf = maxf(pf, f.b_forest * 0.85)
		pf *= (1.0 - 0.75 * f.b_cold) * (1.0 - 0.6 * f.b_wet) * (1.0 - 0.5 * f.b_sav) * (1.0 - 0.95 * f.b_ash)
		# beside a forest singletrack the trees stand thick and right up to its edge (precision riding: user reference)
		var tr: float = f.trail(x, z)
		var fe: bool = f.q_d < TerrainField.QR and f.q_kind == TrailCourse.FOREST
		if fe:
			pf = maxf(pf, 0.95)
		if rnd.next() > pf:
			continue
		# (bars + lean need ~1.2 m from the line on straights; in a tight bend riders cut in and lean ~40 deg: there the front
		# wheel met trunks 1.25 m off the line, so 1.6 m more room)
		if fe:   # a trunk needs this much room from the line (1.3: running a metre wide out of a turn met trunks at 0.9)
			tr = 0.0 if f.q_d > _forest_clear() else 1.0
		if tr > 0.02 or absf(f.pathN(x, z)) < 0.1 or f.jump_mask(x, z) > 0 or is_blocked(x, z, 0.8):
			continue
		var h := ok_spot(x, z)
		if is_nan(h):
			continue
		var sc := 0.7 + rnd.next() * 0.8
		var yaw := rnd.next() * 6.28
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		if f.b_ash > 0.4:
			# a dead snag: a bare trunk
			var snag := sc * TREE_K * (0.9 + rnd.next() * 0.8)
			put("trunk_pale", x, h - 0.1, z, snag * 1.0, snag * 1.5, snag * 1.0, yaw)
			colliders.append({"x": x, "z": z, "r": 0.14 * snag + 0.02, "ceil": h + snag * 1.5})
			continue
		if rnd.next() < dry * (1.0 - 0.9 * f.b_sav):
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
		sc *= TREE_K
		if fe or h > 4 or rnd.next() < 0.3 + rug * 0.6 + f.b_forest * 0.65 + f.b_cold * 0.5:
			# pines: tall and slim, the odd one a real giant (up to ~13 m); smaller up in the alpine
			sc *= 1.0 - 0.3 * f.b_cold
			var py := sc * (1.5 + rnd.next() * 0.7 + pow(rnd.next(), 4.0) * 0.9)
			# tall forest (strong pine forest, or beside a forest singletrack): long bare trunks, the crown high up, so riders
			# (and the camera behind them) ride under the canopy, not through the branches (user, 2026-11-25)
			var tall: bool = fe or f.b_forest > 0.5
			var cb := sc * 0.6   # crown base above the ground
			if tall:
				cb = maxf(TALL_CROWN, sc * 3.2) + rnd.next() * 3.0
				sc *= 1.15
			if not fe and not tall and not _crown_clear(x, z, sc * 1.05):
				continue
			if tall and not fe and not _crown_clear(x, z, sc * 0.5):
				continue   # (a tall trunk only needs its trunk off the trail: its crown is overhead)
			put("trunk_pine" if rnd.next() < 0.45 else "trunk", x, h - 0.1, z, sc, cb + 0.2 + py * 0.15, sc, yaw)
			put("pine", x, h + cb, z, sc * (0.95 if tall else 1.1), py, sc * (0.95 if tall else 1.1), yaw, PINES[int(rnd.next() * PINES.size())])
			ceil_h = h + cb + 2.8 * py
		elif f.b_sav > 0.4:
			# savanna: a thin trunk under a wide, flat crown
			if not _crown_clear(x, z, sc * 2.4):
				continue
			var th := sc * (1.5 + rnd.next() * 0.8)
			ceil_h = h + th + sc * 0.9
			put("trunk", x, h - 0.1, z, sc * 0.8, th + 0.3, sc * 0.8, yaw)
			put("blob", x, h + th + sc * 0.25, z, sc * 2.3, sc * 0.55, sc * 2.3, yaw, SAV_LEAVES[int(rnd.next() * SAV_LEAVES.size())], 0.6)
		else:
			if not _crown_clear(x, z, sc * 1.4):
				continue
			var th := sc * (1.1 + rnd.next() * 0.6)
			ceil_h = h + th + sc * 1.8
			put("trunk_pale" if rnd.next() < 0.6 else "trunk", x, h - 0.1, z, sc, th + 0.3, sc, yaw)
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
			if rnd.next() > maxf(f.b_rug, maxf(f.b_cold * 0.8, f.b_ash * 0.9)):
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
		colliders.append({"x": x, "z": z, "r": (sx + sc) * 0.45, "top": h - sc * 0.25 + sy * 0.9, "base": f.ground(x, z), "sink": sc * 0.25})
		blocked.append([x, z, (sx + sc) * 0.45])   # (no grass / tufts growing through a rock, hiding it)


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
		if rnd.next() < dry * 0.85 or rnd.next() < rug * 0.3 or rnd.next() < f.b_ash or rnd.next() < f.b_cold * 0.5:
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


## Berm rims (2026-11-25, "some rock on the edges, small pebbles"): pebbles in loose strips along the rim of a banked bend (where
## `berm_style` puts it: F + the cap), scattered thinner down the back slope, the odd small rock. Not on the road itself.
func _berm_clutter(ox: float, oz: float) -> void:
	if TerrainField.OLD_BERM:
		return
	var rb := WorldRng.new(WorldRng.i32(cx * 1597334677) ^ WorldRng.i32(cz * 3812015801) ^ WorldRng.i32(f.seed_value * 668265263) ^ 0x1f83d9ab)
	for i in 300:
		var x := ox + (rb.next() - .5) * S
		var z := oz + (rb.next() - .5) * S
		f.query(x, z)
		if f.q_d > f.q_w + 8.0 or absf(f.q_bt) < 0.08:
			continue
		var o: float = -f.q_a if f.q_bt > 0.0 else f.q_a
		f.berm_style(f.q_s, 0.0, f.q_w)
		var r: float = o - f.bs_F
		if r < -1.4 or r > 3.0:
			continue
		var peak := 1.0 - sm(0.0, 2.0, absf(r - 0.5))
		if rb.next() > 0.7 * peak + 0.06 or f.jump_mask(x, z) > 0.05 or is_blocked(x, z, 0.3):
			continue
		var h := height(x, z)
		if h < WATER + 0.3:
			continue
		if rb.next() < 0.07 and r > 0.2:
			var sc := 0.14 + rb.next() * 0.16
			put("rock", x, h - sc * 0.25, z, sc * 1.2, sc * 0.7, sc, rb.next() * 6.28, null, 0.5)
		else:
			for k in 2 + int(rb.next() * 4):
				var sc := 0.03 + rb.next() * rb.next() * 0.11
				var a := rb.next() * 6.28
				var d := rb.next() * 0.45
				var px := x + cos(a) * d
				var pz := z + sin(a) * d
				put("pebble", px, height(px, pz) - sc * 0.3, pz, sc * 1.3, sc * 0.7, sc, rb.next() * 6.28, null, 0.5)


func _trail_clutter(ox: float, oz: float) -> void:
	var rt := WorldRng.new(WorldRng.i32(cx * 2654435761) ^ WorldRng.i32(cz * 40503) ^ WorldRng.i32(f.seed_value * 2246822519) ^ 0x27d4eb2f)
	for i in 520:
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
			elif rt.next() < 0.22:
				# 2026-11-25 (realism pass): fallen twigs along the verge, the same MultiMesh list the forest floor uses
				put("stick", x, h + 0.015, z, 0.2 + rt.next() * 0.45, 0.8, 0.8, rt.next() * 6.28, null, 0.15)


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
		if rg.next() < dry * 0.95 + rug * 0.5 + f.b_ash + f.b_cold * 0.4:
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
		if f.q_d < TerrainField.QR and f.q_kind == TrailCourse.FOREST and f.q_d < _forest_clear():
			continue
		var h := ok_spot(x, z, WATER + 0.5)
		if is_nan(h):
			continue
		f.biome(x, z)
		var dry: float = f.b_dry
		var rug: float = f.b_rug
		var wood := maxf(sm(-0.05, 0.3, f.n(x + 400, z, TerrainField.I38)), f.b_forest)
		var r := rn.next()
		var yaw := rn.next() * 6.28
		if f.b_ash > 0.5:
			# ash fields: dark rubble and the odd boulder, nothing grows
			if r < 0.55:
				for k in 5:
					var sc := 0.06 + rn.next() * 0.2
					var a := rn.next() * 6.28
					var d := rn.next() * 1.4
					put("pebble", x + cos(a) * d, h - sc * 0.3, z + sin(a) * d, sc * 1.4, sc * 0.8, sc, rn.next() * 6.28, null, 0.6)
			continue
		if f.b_wet > 0.4 and r < 0.5:
			# wetland: tufts of tall reeds
			var colr: Color = REEDS[int(rn.next() * REEDS.size())]
			for k in 3 + int(rn.next() * 5):
				var a := rn.next() * 6.28
				var d := rn.next() * 0.7
				var fx := x + cos(a) * d
				var fz := z + sin(a) * d
				var s2 := 1.1 + rn.next() * 0.8
				put("grass", fx, height(fx, fz) - 0.03, fz, s2, s2 * (1.9 + rn.next() * 1.2), s2, rn.next() * 6.28, colr * (0.85 + rn.next() * 0.3), 0.2)
			continue
		if f.b_sav > 0.4 and r < 0.4:
			# savanna: clumps of tall golden grass
			var sx := 1.8 + rn.next() * 1.2
			var sy := 1.3 + rn.next() * 1.1
			put("grass", x, h - 0.03, z, sx, sy, sx, yaw, C["savanna"] * (0.8 + rn.next() * 0.3))
			continue
		if dry > 0.55:
			if r < 0.08:
				var sc := 0.25 + rn.next() * 0.25
				var scrub_col: Color = SCRUB[int(rn.next() * SCRUB.size())]
				if int(yaw * 10.0) % 2 == 0 and f.trail(x, z) <= 0.02:
					# every other one is a leaf-card dry shrub (card_bush.gd), the rest stay the little weed blobs
					put("bushdry", x, h - 0.05, z, sc * 1.9, sc * 1.5, sc * 1.9, yaw, scrub_col, 0.4)
				else:
					put("weed", x, h + sc * 0.75, z, sc, sc * 0.85, sc, yaw, scrub_col, 0.6)
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
		if (rug > 0.55 or f.b_cold > 0.5) and r < 0.35:
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
				put(_bush_kind(yaw), x, h - 0.08, z, sx, sy, sc, yaw, BUSHES[int(rn.next() * BUSHES.size())], 0.3)
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
				put(_bush_kind(yw), fx, hh, fz, sx, sy, sc, yw, colr * (0.85 + rn.next() * 0.3), 0.3)
		elif r < 0.2:
			var l := 0.3 + rn.next() * 0.6
			put("stick", x, h + 0.015, z, l, 0.8, 0.8, yaw, null, 0.15)


## which green bush variant (round / low + wide / tall + loose): from the yaw, so no random numbers are used up
static func _bush_kind(yaw: float) -> String:
	return ["bush", "bush1", "bush2"][int(yaw * 10.0) % 3]


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
## ground mesh refinement over the chunk's texture grid (2026-11-25, user: "too low poly, peaks more smooth"): 2 = 0.25 m triangles in the
## base mesh. The old 0.5 m grid is its first LOD, so a flat or distant chunk costs what it did. 1 = as before (BMX_MESH_K=1).
## Needs the C# field (fine_ground); the GDScript field keeps 0.5 m.
## only chunks within MESH_NEAR m of the trail get it (where the berms, jumps and lips are: the rest of the land keeps 0.5 m)
const MESH_NEAR := 60.0
static var MESH_K := maxi(1, int(OS.get_environment("BMX_MESH_K"))) if OS.get_environment("BMX_MESH_K") != "" else 2

func _ground_lods(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, n: int, mk: int = 1) -> void:
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
	out["indices"] = _grid_lod_indices(1, edges, skirt_of, n)
	var lods := {}
	var steps: Array = LOD_STEPS if mk == 1 else [2, 4, 8, 16]
	for s: int in steps:
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
		lods[maxf(err, 0.02 * s / mk)] = _grid_lod_indices(s, edges, skirt_of, n)
	out["lods"] = lods

func _grid_lod_indices(s: int, edges: Array, skirt_of: Dictionary, n: int) -> PackedInt32Array:
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

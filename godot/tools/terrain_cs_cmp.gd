extends SceneTree
## GDScript TerrainField vs C# TerrainFieldCs: the same seed must give the same numbers.
## godot --headless --path godot --script res://tools/terrain_cs_cmp.gd [-- seed ...]
## Per seed: >= 20k points (random within 600 m, along the course, on jump / route features, plus the
## JS-harness points of terrain_cmp_dump.gd) through the Terrain API (height, deck_height, surface, jump,
## jump_mask, trail, biome_name, ground_color) and the field (ground, wood, base, berm, line, pathN,
## colour layers); a few whole chunks built by both (every output array); then both terrains streamed
## round the spawn and height() compared with the rock / log domes in.

var worst := {}     # name -> [max abs diff, x, z]
var bad := {}       # name -> mismatch count (exact compares)
var n_cmp := 0


func _num(name: String, a, b, x: float, z: float) -> void:
	n_cmp += 1
	if a == null or b == null:
		if not (a == null and b == null):
			bad[name] = bad.get(name, 0) + 1
			if not worst.has(name):
				worst[name] = [INF, x, z]
		return
	var d := absf(float(a) - float(b))
	if float(a) == float(b):
		d = 0.0
	elif is_nan(float(a)) != is_nan(float(b)):
		d = INF
	elif is_nan(float(a)):
		d = 0.0
	if not worst.has(name) or d > worst[name][0]:
		worst[name] = [d, x, z]
	if d != 0.0:
		bad[name] = bad.get(name, 0) + 1


func _col(name: String, a: Color, b: Color, x: float, z: float) -> void:
	_num(name + ".r", a.r, b.r, x, z)
	_num(name + ".g", a.g, b.g, x, z)
	_num(name + ".b", a.b, b.b, x, z)


func _eq(name: String, a, b, x: float, z: float) -> void:
	n_cmp += 1
	if not worst.has(name):
		worst[name] = [0.0, x, z]
	if a != b:
		bad[name] = bad.get(name, 0) + 1
		worst[name] = [1.0, x, z]


func _points(f: TerrainField, seed: int) -> Array:
	var pts := []
	# the JS harness points (terrain_cmp_dump.gd)
	var r := WorldRng.new(99)
	for i in 1000:
		pts.append([-600 + r.next() * 2200, -500 + r.next() * 1000])
	var C := f.course
	for i in 1000:
		var p := C.at(r.next() * C.length)
		var a := (r.next() - 0.5) * 16
		pts.append([p[0] - p[3] * a, p[1] + p[2] * a])
	var feats: Array = f.route_feats.duplicate()
	for cx in range(-15, 46):
		for cz in range(-12, 13):
			var j := f.jump_at(cx, cz)
			if j != null:
				feats.append(j)
	for i in 1000:
		var j: TerrainField.Feat = feats[i % feats.size()]
		var u := r.next() * j.len
		var w := (r.next() - 0.5) * 2 * j.half
		pts.append([j.x + j.dx * u - j.dz * w, j.z + j.dz * u + j.dx * w])
	# random within 600 m of the spawn
	r = WorldRng.new(seed + 1)
	for i in 8000:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 600.0
		pts.append([cos(a) * d, sin(a) * d])
	# along the course, across its whole width and the banks
	for i in 6000:
		var p := C.at(r.next() * C.length)
		var a := (r.next() - 0.5) * 30
		pts.append([p[0] - p[3] * a, p[1] + p[2] * a])
	# on jump / route features (lips, landings, decks, digs, their margins)
	for i in 6000:
		var j: TerrainField.Feat = feats[int(r.next() * feats.size())]
		var u := -6.0 + r.next() * (j.len + 12.0)
		var w := (r.next() - 0.5) * 2 * (j.half + 2.5)
		pts.append([j.x + j.dx * u - j.dz * w, j.z + j.dz * u + j.dx * w])
	# a few exact grid / cell corners (floor() edges)
	for i in 200:
		pts.append([float(i * 17 - 1700), float((i % 13) * 34 - 200)])
	return pts


func _cmp_seed(seed: int) -> void:
	var tg := Terrain.new()
	tg.use_cs = false
	tg.set_seed(seed)
	var tc := Terrain.new()
	tc.use_cs = true
	tc.set_seed(seed)
	if tc.fcs == null:
		push_error("C# field not available")
		quit(1)
		return
	var fg: TerrainField = tg.field
	var fc = tc.fcs
	var pts := _points(fg, seed)
	print("CMP seed %d: %d points" % [seed, pts.size()])
	var r := WorldRng.new(seed + 2)
	var t0 := Time.get_ticks_msec()
	for p in pts:
		var x: float = p[0]
		var z: float = p[1]
		# Terrain API
		_num("height", tg.height(x, z), tc.height(x, z), x, z)
		_num("deck_height", tg.deck_height(x, z), tc.deck_height(x, z), x, z)
		_eq("surface", tg.surface(x, z), tc.surface(x, z), x, z)
		var jg: Array = tg.jump(x, z)
		var jc: Array = tc.jump(x, z)
		for k in 5:
			_num("jump[%d]" % k, jg[k], jc[k], x, z)
		_num("jump_mask", tg.jump_mask(x, z), tc.jump_mask(x, z), x, z)
		_num("trail", tg.trail(x, z), tc.trail(x, z), x, z)
		_eq("biome_name", tg.biome_name(x, z), tc.biome_name(x, z), x, z)
		var ny := 0.5 + r.next() * 0.5 if r.next() < 0.5 else 1.0
		_col("ground_color", tg.ground_color(x, z, ny), tc.ground_color(x, z, ny), x, z)
		# field internals
		_num("ground", fg.ground(x, z), fc.ground(x, z), x, z)
		_eq("has_wood", fg.has_wood, fc.has_wood, x, z)
		_num("base", fg.base(x, z), fc.base(x, z), x, z)
		_num("berm", fg.berm(x, z), fc.berm(x, z), x, z)
		_num("line", fg.line(x, z), fc.line(x, z), x, z)
		_num("pathN", fg.pathN(x, z), fc.pathN(x, z), x, z)
		_num("route_dist", fg.route_dist(x, z), fc.route_dist(x, z), x, z)
		fg.biome(x, z)
		fc.biome(x, z)
		_num("b_dry", fg.b_dry, fc.b_dry, x, z)
		_num("b_rug", fg.b_rug, fc.b_rug, x, z)
		var h := fg.ground(x, z) + (r.next() - 0.5) * 6.0
		_num("color_layers", fg.color_layers(x, z, h, ny), fc.color_layers(x, z, h, ny), x, z)
		_col("cl_g", fg.cl_g, fc.cl_g, x, z)
		_col("cl_d", fg.cl_d, fc.cl_d, x, z)
		_num("cl_steep", fg.cl_steep, fc.cl_steep, x, z)
	print("CMP seed %d: points done in %d ms" % [seed, Time.get_ticks_msec() - t0])
	# whole chunks, both builders, every output
	for c in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(5, 1), Vector2i(-3, 3)]:
		var bg := TerrainChunkBuilder.new(fg.fork(), c.x, c.y, tg.seg, 0)
		bg.run()
		var bc := TerrainChunkBuilder.new(fc.fork(), c.x, c.y, tc.seg, 0)
		bc.run()
		for key in ["G", "verts", "norms", "uvs", "hm", "indices"]:
			_eq("chunk." + key, bg.out[key], bc.out[key], c.x, c.y)
		_eq("chunk.land_img", bg.out["land_img"].get_data(), bc.out["land_img"].get_data(), c.x, c.y)
		_eq("chunk.dirt_img", bg.out["dirt_img"].get_data(), bc.out["dirt_img"].get_data(), c.x, c.y)
		_eq("chunk.counts", bg.out["counts"], bc.out["counts"], c.x, c.y)
		for name in bg.out["lists"]:
			_eq("chunk.lists", bg.out["lists"][name], bc.out["lists"][name], c.x, c.y)
		_eq("chunk.sheds", bg.out["sheds"], bc.out["sheds"], c.x, c.y)
		_eq("chunk.lods", bg.out["lods"].keys(), bc.out["lods"].keys(), c.x, c.y)
		_eq("chunk.colliders", bg.out["colliders"].size(), bc.out["colliders"].size(), c.x, c.y)
		for i in mini(bg.out["colliders"].size(), bc.out["colliders"].size()):
			var a: Dictionary = bg.out["colliders"][i]
			var b: Dictionary = bc.out["colliders"][i]
			for k in ["x", "z", "r", "top", "base", "ceil"]:
				if a.has(k) or b.has(k):
					_num("chunk.collider." + k, a.get(k), b.get(k), c.x, c.y)
		_eq("chunk.tape", bg.out.has("tape"), bc.out.has("tape"), c.x, c.y)
		if bg.out.has("tape") and bc.out.has("tape"):
			_eq("chunk.tape.pos", bg.out["tape"]["pos"], bc.out["tape"]["pos"], c.x, c.y)
	# both terrains streamed round the spawn (threaded builders, forks): heights with the domes
	root.add_child(tg)
	root.add_child(tc)
	tg.update_stream(0.0, 0.0, INF)
	tc.update_stream(0.0, 0.0, INF)
	_eq("stream.chunks", tg.chunks.size(), tc.chunks.size(), 0, 0)
	for i in 6000:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 150.0
		var x := cos(a) * d
		var z := sin(a) * d
		_num("height+domes", tg.height(x, z), tc.height(x, z), x, z)
		_eq("surface+domes", tg.surface(x, z), tc.surface(x, z), x, z)
	tg.queue_free()
	tc.queue_free()


func _hex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


## GDScript's libm (x87 on Windows) vs TerrainFieldCs's emulation, over the ranges the field uses
func _libm(fc) -> void:
	var r := WorldRng.new(31)
	var bad := [0, 0, 0]
	var raw := [0, 0, 0]
	var n := 200000
	var e0: int = fc.libm_engine_calls
	for i in n:
		var v := [-1.5 + r.next() * 14.0, -16.0 + r.next() * 22.0, 0.0]   # zc(): x / 260 + rp_a; berm_shape(): exp(..)
		v[2] = 1.0 + exp(v[1])                                            # berm_shape(): log(1 + exp(..))
		for k in 3:
			var x: float = v[k]
			var g: float = sin(x) if k == 0 else (exp(x) if k == 1 else log(x))
			if g != fc.x87_raw(k, x):
				raw[k] += 1
			if g != fc.x87(k, x):
				bad[k] += 1
				if OS.has_environment("CMP_LIBM_DUMP"): print("LIBM ", k, " ", _hex(x), " ", _hex(g), " ", _hex(fc.x87(k, x)))
	print("CMP libm (%d values each): emulation alone differs sin %d, exp %d, log %d; with the engine fallback (%.2f%% of calls) sin %d, exp %d, log %d" % [
		n, raw[0], raw[1], raw[2], 100.0 * (fc.libm_engine_calls - e0) / (3 * n), bad[0], bad[1], bad[2]])


func _init() -> void:
	var seeds := [12345, 4242]
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		seeds = []
		for a in user:
			seeds.append(int(a))
	var t := Terrain.new()
	if t.fcs != null:
		_libm(t.fcs)
	t.free()
	for s in seeds:
		worst = {}
		bad = {}
		n_cmp = 0
		_cmp_seed(s)
		var keys := worst.keys()
		keys.sort()
		var total_bad := 0
		for k in keys:
			var w: Array = worst[k]
			var nb: int = bad.get(k, 0)
			total_bad += nb
			print("CMP seed %d  %-22s max|diff| %-9s mismatches %d%s" % [s, k, String.num_scientific(w[0]), nb, ("" if nb == 0 else "  (worst at %.4f, %.4f)" % [w[1], w[2]])])
		print("CMP seed %d: %d comparisons, %d mismatches -> %s" % [s, n_cmp, total_bad, "EXACT" if total_bad == 0 else "DIFFERENT"])
	quit()

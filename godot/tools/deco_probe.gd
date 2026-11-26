extends SceneTree
## Trees / rocks off the trail: can you ride between them? Builds 3 x 3 blocks of real chunks (TerrainChunkBuilder) and
## measures the middle chunk: trees per hectare, trunk-to-nearest-trunk spacing, and the mean free path = how far a bike
## (0.35 m half width) rides straight from a random open spot before it meets a trunk or rock (cap 60 m), in forest
## (>= 1 tree within 8 m) and overall. Run: --headless -s res://tools/deco_probe.gd [-- seeds=4242,5 blocks=8]
const HALF_W := 0.35

func _init() -> void:
	var seeds := [4242, 5]
	var blocks := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			seeds = []
			for s in a.substr(6).split(","): seeds.append(int(s))
		elif a.begins_with("blocks="): blocks = int(a.substr(7))
	var tot := {"trees": 0, "area": 0.0, "nn": [], "rocks": 0, "mfp": [], "mfp_f": [], "rk_path": 0}
	for sd in seeds:
		var tg := Terrain.new()
		tg.use_cs = false
		tg.set_seed(sd)
		var rng := RandomNumberGenerator.new(); rng.seed = 991 + sd
		var spots := []   # (chosen first: the free-ride test below draws from rng too, so the chunks used to depend on the trees)
		for bi in blocks: spots.append(Vector2i(rng.randi_range(4, 40), rng.randi_range(-12, 12)))
		for bi in blocks:
			var ccx: int = spots[bi].x; var ccz: int = spots[bi].y
			var trees := []; var rocks := []; var mid := []
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var b := TerrainChunkBuilder.new(tg.field.fork(), ccx + dx, ccz + dz, tg.seg, 0)
					b.run()
					for k in b.colliders:
						if k.size() == 4 and k.has("ceil"):
							trees.append(Vector3(k.x, k.z, k.r))
							if dx == 0 and dz == 0: mid.append(Vector3(k.x, k.z, k.r))
						elif k.has("top") and k.has("sink") and not k.has("log"):
							if k.r > 0.4: rocks.append(Vector3(k.x, k.z, k.r))   # (pebbles are ridden over)
							if dx == 0 and dz == 0:
								tot.rocks += 1
								if absf(tg.field.pathN(k.x, k.z)) < 0.06: tot.rk_path += 1
			var S := TerrainChunkBuilder.S if "S" in TerrainChunkBuilder else 48.0
			var ox := ccx * S; var oz := ccz * S
			tot.trees += mid.size(); tot.area += S * S
			for t in mid:
				var best := 1e9
				for u in trees:
					if u == t: continue
					best = minf(best, Vector2(u.x - t.x, u.y - t.y).length())
				tot.nn.append(best)
			var obs := trees + rocks
			for n in 60:
				var px := ox + rng.randf_range(-S / 2, S / 2); var pz := oz + rng.randf_range(-S / 2, S / 2)
				if tg.field.trail(px, pz) > 0.0: continue
				var free := true; var near := false
				for o in obs:
					var d := Vector2(o.x - px, o.y - pz).length()
					if d < o.z + HALF_W: free = false
					if d < 8.0: near = true
				if not free: continue
				var ang := rng.randf() * TAU
				var dx := cos(ang); var dz := sin(ang)
				var hit := 60.0
				for o in obs:
					var rx: float = o.x - px; var rz: float = o.y - pz
					var along := rx * dx + rz * dz
					if along < 0.0 or along > hit: continue
					var side := absf(rx * dz - rz * dx)
					if side < o.z + HALF_W: hit = along
				tot.mfp.append(hit)
				if near: tot.mfp_f.append(hit)
		tg.free()
	var nn: Array = tot.nn; nn.sort()
	var c15 := 0; var c25 := 0
	for d in nn:
		if d < 1.5: c15 += 1
		if d < 2.5: c25 += 1
	var m: Array = tot.mfp; m.sort()
	var mf: Array = tot.mfp_f; mf.sort()
	var med := func(a: Array) -> float: return a[a.size() / 2] if a.size() > 0 else -1.0
	var short := func(a: Array, lim: float) -> float:
		var c := 0
		for d in a: if d < lim: c += 1
		return 100.0 * c / maxf(1, a.size())
	print("DECO trees=%d per_ha=%.0f  nn<1.5m %.0f %%  nn<2.5m %.0f %%  nn median %.1f m | rocks=%d on side paths %d" % [tot.trees, tot.trees / tot.area * 1e4, 100.0 * c15 / maxf(1, nn.size()), 100.0 * c25 / maxf(1, nn.size()), med.call(nn), tot.rocks, tot.rk_path])
	print("DECO free ride: all median %.1f m (< 10 m %.0f %%, n=%d) | in forest median %.1f m (< 10 m %.0f %%, n=%d)" % [med.call(m), short.call(m, 10.0), m.size(), med.call(mf), short.call(mf, 10.0), mf.size()])
	quit(0)

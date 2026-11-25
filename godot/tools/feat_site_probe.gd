extends SceneTree
## Where built jumps sit against the land: for every route feature (and the free-ride jumps found in a stretch of land) the
## biggest rise / drop of the natural ground beside the footprint (at half + SIDE m from the axis) against the jump's plane,
## and along the axis. Big rises = a hill wall next to the table (the bike clips it). -s res://tools/feat_site_probe.gd [-- seed ...]
func _site(f: TerrainField, j: TerrainField.Feat, side_m: float) -> Array:
	var rise := 0.0
	var drop := 0.0
	var cen := 0.0
	var n := 8
	for k in n + 1:
		var u: float = j.len * k / n
		var cx: float = j.x + j.dx * u
		var cz: float = j.z + j.dz * u
		var pl: float = j.b0 + (j.b1 - j.b0) * u / j.len
		cen = maxf(cen, absf(f.base(cx, cz) - pl))
		for sg in [-1.0, 1.0]:
			var w: float = (j.half + side_m) * sg
			var d: float = f.base(cx - j.dz * w, cz + j.dx * w) - pl
			rise = maxf(rise, d)
			drop = maxf(drop, -d)
	return [rise, drop, cen]

func _pct(a: Array, q: float) -> float:
	if a.is_empty(): return 0.0
	a.sort()
	return a[clampi(int(a.size() * q), 0, a.size() - 1)]

func _init() -> void:
	var seeds: Array = [4242, 5, 7, 12, 99, 1, 2, 3]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = []
		for a in args: seeds.append(int(a))
	var rr: Array = []; var dd: Array = []; var cc: Array = []
	var fr: Array = []; var fd: Array = []; var fc: Array = []
	var worst := []
	for sd in seeds:
		var f := TerrainField.new()
		f.setup(sd, {})
		for j in f.route_feats:
			if j.type == "rope" or j.type == "gorge" or j.type == "bridge": continue
			var s := _site(f, j, 3.0)
			rr.append(s[0]); dd.append(s[1]); cc.append(s[2])
			worst.append([s[0], sd, j.type, snappedf(j.x, 1.0), snappedf(j.z, 1.0)])
		# free-ride jumps in the land beside the first 3 km
		for cx in range(-4, 110):
			for cz in range(-12, 12):
				var j: TerrainField.Feat = f.jump_at(cx, cz)
				if j == null: continue
				var s := _site(f, j, 3.0)
				fr.append(s[0]); fd.append(s[1]); fc.append(s[2])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("SITE route n=%d rise p50 %.2f p90 %.2f max %.2f | drop p50 %.2f p90 %.2f max %.2f | centre p90 %.2f max %.2f" % [rr.size(), _pct(rr.duplicate(), 0.5), _pct(rr.duplicate(), 0.9), _pct(rr.duplicate(), 1.0), _pct(dd.duplicate(), 0.5), _pct(dd.duplicate(), 0.9), _pct(dd.duplicate(), 1.0), _pct(cc.duplicate(), 0.9), _pct(cc.duplicate(), 1.0)])
	print("SITE free  n=%d rise p50 %.2f p90 %.2f max %.2f | drop p50 %.2f p90 %.2f max %.2f | centre p90 %.2f max %.2f" % [fr.size(), _pct(fr.duplicate(), 0.5), _pct(fr.duplicate(), 0.9), _pct(fr.duplicate(), 1.0), _pct(fd.duplicate(), 0.5), _pct(fd.duplicate(), 0.9), _pct(fd.duplicate(), 1.0), _pct(fc.duplicate(), 0.9), _pct(fc.duplicate(), 1.0)])
	for i in mini(8, worst.size()): print("SITE worst ", worst[i])
	var over := 0
	for v in rr: if v > 2.0: over += 1
	var over_f := 0
	for v in fr: if v > 2.0: over_f += 1
	print("SITE rise > 2 m: route %d of %d, free %d of %d" % [over, rr.size(), over_f, fr.size()])
	quit()

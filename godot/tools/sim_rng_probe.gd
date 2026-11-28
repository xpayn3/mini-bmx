extends SceneTree
## Pcg32 + Noise2S (godot/sim, engine-free) vs Godot's RandomNumberGenerator / FastNoiseLite: bit for bit.
## godot --headless --path godot --script res://tools/sim_rng_probe.gd [-- n=100000]
func _init() -> void:
	var n := 100000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("n="): n = int(arg.substr(2))
	var p = load("res://dev/sim/SimMathProbeCs.cs").new()
	p.SetEngineTies(true)
	var fails := 0
	for seed in [4711, 0, 1, 913, 123456789]:
		for kind in 4:
			var cs: PackedFloat64Array = p.Rng(seed, kind, n)
			var r := RandomNumberGenerator.new(); r.seed = seed
			var bad := 0; var ex := []
			for i in n:
				var g: float
				match kind:
					0: g = float(r.randi())
					1: g = r.randf()
					2: g = r.randf_range(0.0, 1.0)
					_: g = r.randfn(0.0, 1.0)
				if kind == 2: continue   # (GDScript has no double randd; randf_range is float too)
				if g != cs[i]:
					bad += 1
					if ex.size() < 3: ex.append("  i=%d gd=%s sim=%s" % [i, var_to_str(g), var_to_str(cs[i])])
			if kind == 2: continue
			fails += bad
			print("SIMRNG seed=%d %s mismatch=%d/%d" % [seed, ["rand", "randf", "randd", "randfn"][kind], bad, n])
			for e in ex: print(e)
	# the noises the ride uses (grip 913 / 0.22 / 2, braking 2741 / 0.9 / 2) + a few others
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	for cfg in [[913, 0.22, 2], [2741, 0.9, 2], [1, 0.05, 5], [-7, 3.0, 1]]:
		var xs := PackedFloat64Array(); var ys := PackedFloat64Array()
		for i in n:
			var sc: float = [100.0, 3000.0, 1.0, 1e5][i % 4]
			xs.append((rng.randf() - 0.5) * sc); ys.append((rng.randf() - 0.5) * sc)
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = cfg[0]; fn.frequency = cfg[1]; fn.fractal_octaves = cfg[2]
		var cs: PackedFloat64Array = p.Noise(cfg[0], cfg[1], cfg[2], xs, ys)
		var bad := 0; var ex := []
		for i in n:
			var g := fn.get_noise_2d(xs[i], ys[i])
			if g != cs[i]:
				bad += 1
				if ex.size() < 3: ex.append("  (%s, %s) gd=%s sim=%s" % [var_to_str(xs[i]), var_to_str(ys[i]), var_to_str(g), var_to_str(cs[i])])
		fails += bad
		print("SIMNOISE seed=%d freq=%s oct=%d mismatch=%d/%d" % [cfg[0], str(cfg[1]), cfg[2], bad, n])
		for e in ex: print(e)
	print("SIMRNG ", "PASS" if fails == 0 else "mismatches=%d" % fails)
	quit(0 if fails == 0 else 1)

extends SceneTree
## Debug aid for the Unity world port: the course's first steps in Godot (state after the start straight, the first
## section's picks), to compare with the C# TrailCourse. godot --headless --path godot --script res://tools/course_trace.gd -- [seed]

func _init() -> void:
	var seed := 4242
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int(): seed = int(a)
	var f := TerrainField.new()
	# setup() up to the spine (terrain_field.gd setup, the same lines)
	LandParams.ensure()
	f.style = {"jumps": 1.0, "bends": 1.0, "rolling": 1.0, "grade": 1.0, "biome": 0.0}
	f.grade_k = 1.0
	var pick: Array = RouteStyle.BIOMES[0]
	f.biome_dry = float(pick[1]); f.biome_rug = float(pick[2])
	TrailFeatures.ensure()
	TerrainField._ensure_colors()
	f._local_tables()
	f.seed_value = seed
	f.sz = (seed % 1000) * 0.7311 + 0.37
	f._build_noise()
	var r := WorldRng.new(seed * 7919 + 13)
	f.rp_a = r.next() * 6.28
	r.next()
	f.rp_sg = 1.0 if r.next() < 0.5 else -1.0
	f.pitches = PackedFloat64Array()
	f.pitch_share = 0.0
	var x := 170 + r.next() * 80
	var k := 0
	while k < TerrainField.PITCH_N and x < TerrainField.HILL_LEN - 140:
		var len := 34 + r.next() * 24
		var sh := (0.06 + r.next() * 0.03) * TerrainField.PITCH_K
		f.pitches.append(x); f.pitches.append(len); f.pitches.append(sh)
		f.pitch_share += sh
		x += len + 190 + r.next() * 170
		k += 1
	f._reset_caches()
	f.spine = RouteSpine.make(f, seed, TerrainField.COURSE_LEN + TerrainField.SPINE_AHEAD)
	f._bind_spine()
	f._reset_caches()
	var c := TrailCourse.new()
	c._M = f
	c._r = WorldRng.new(seed * 31337 + 5)
	c._hill = TerrainField.HILL_LEN
	c._L = TerrainField.COURSE_LEN
	c._corr = TerrainField.MTN_W - 40
	c._mark_seed = seed * 6151 + 3
	c._x = -36; c._z = 0; c._h = 0
	c._straight(76, TrailCourse.START)
	print("TRACE after_start x=%.17f z=%.17f h=%.17f v=%.17f hv=%.17f rng=%d" % [c._x, c._z, c._h, c._v, c._hv, c._r.a])
	print("TRACE sp=%.17f pitch=%d P0=%.17f P1=%.17f hill=%.17f" % [c._sp(), c._next_pitch(), f.pitches[0], f.pitches[1], TerrainField.HILL_LEN])
	print("TRACE landform(0,0)=%.17f landform(40,0)=%.17f off=%.17f rel=%.17f" % [f.landform(0, 0), f.landform(40, 0), c._off(), c._rel(0.0)])
	for i in 6:
		print("TRACE rng%d=%.17f" % [i, c._r.next()])
	quit(0)

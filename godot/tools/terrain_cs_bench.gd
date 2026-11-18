extends SceneTree
## Terrain timing: µs per height() call, chunk build ms, spawn (update_stream INF) ms.
## godot --headless --path godot --script res://tools/terrain_cs_bench.gd -- [gd|cs] [seed]
## (gd = the GDScript TerrainField, cs = the C# TerrainFieldCs; default: Terrain.USE_CS)

func _init() -> void:
	var mode := ""
	var seed := 4242
	for a in OS.get_cmdline_user_args():
		if a == "gd" or a == "cs":
			mode = a
		elif a.is_valid_int():
			seed = int(a)
	var t := Terrain.new()
	if mode != "" and "use_cs" in t:
		t.use_cs = mode == "cs"
	var t0 := Time.get_ticks_usec()
	t.set_seed(seed)
	var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cs_on: bool = t.get("fcs") != null
	print("BENCH mode=%s seed=%d set_seed=%.1f ms" % ["cs" if cs_on else "gd", seed, setup_ms])
	# height(): 100k calls at random points within 600 m (no rock domes: nothing streamed yet)
	var r := WorldRng.new(7)
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for i in 100000:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 600.0
		xs.append(cos(a) * d)
		zs.append(sin(a) * d)
	t0 = Time.get_ticks_usec()
	var acc := 0.0
	for i in 100000:
		acc += t.height(xs[i], zs[i])
	var us := float(Time.get_ticks_usec() - t0) / 100000.0
	print("BENCH height() %.3f us/call (100k random, sum %.6f)" % [us, acc])
	# a bike-like pattern: 40 nearby points per step along a line
	t0 = Time.get_ticks_usec()
	var n := 0
	for s in 2500:
		var bx := 10.0 + s * 0.08
		var bz := -5.0 + s * 0.02
		for k in 40:
			acc += t.height(bx + (k % 8) * 0.13, bz + (k / 8) * 0.11)
			n += 1
	print("BENCH height() %.3f us/call (100k clustered, bike-like)" % [float(Time.get_ticks_usec() - t0) / n])
	# surface / jump / trail / ground_color
	t0 = Time.get_ticks_usec()
	for i in 20000:
		acc += t.surface(xs[i], zs[i])
	print("BENCH surface() %.3f us/call" % [float(Time.get_ticks_usec() - t0) / 20000])
	t0 = Time.get_ticks_usec()
	for i in 20000:
		acc += t.jump(xs[i], zs[i])[1]
	print("BENCH jump() %.3f us/call" % [float(Time.get_ticks_usec() - t0) / 20000])
	t0 = Time.get_ticks_usec()
	for i in 20000:
		acc += t.ground_color(xs[i], zs[i]).r
	print("BENCH ground_color() %.3f us/call" % [float(Time.get_ticks_usec() - t0) / 20000])
	# chunk builds, single-threaded, on this thread
	var tot := 0.0
	var cnt := 0
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(3, 1), Vector2i(-2, 2)]:
		var fk = t.get("fcs").fork() if cs_on else t.field.fork()
		var b := TerrainChunkBuilder.new(fk, c.x, c.y, t.seg, 0)
		b.run()
		tot += b.ms_used
		cnt += 1
		print("BENCH chunk %s %.1f ms %s" % [c, b.ms_used, b.stage_ms])
	print("BENCH chunk avg %.1f ms (single thread)" % [tot / cnt])
	# spawn: the whole 7x7 neighbourhood, threaded (update_stream INF)
	root.add_child(t)
	t0 = Time.get_ticks_usec()
	t.update_stream(0.0, 0.0, INF)
	print("BENCH spawn update_stream(INF) %.1f ms, %d chunks" % [(Time.get_ticks_usec() - t0) / 1000.0, t.chunks.size()])
	# rock / log domes: height() (ground + domes) vs deck_height() (ground only) on the same points round the
	# spawn, now that the chunks (and their rocks) are loaded
	var px := PackedFloat64Array()
	var pz := PackedFloat64Array()
	for i in 100000:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 60.0
		px.append(cos(a) * d)
		pz.append(sin(a) * d)
	for pass_ in 2:
		t0 = Time.get_ticks_usec()
		for i in 100000:
			acc += t.deck_height(px[i], pz[i])
		var us_deck := float(Time.get_ticks_usec() - t0) / 100000.0
		t0 = Time.get_ticks_usec()
		for i in 100000:
			acc += t.height(px[i], pz[i])
		var us_h := float(Time.get_ticks_usec() - t0) / 100000.0
		print("BENCH within 60 m, chunks loaded: deck_height() %.3f us, height() (+ domes) %.3f us/call" % [us_deck, us_h])
	if cs_on:
		var fc = t.get("fcs")
		t0 = Time.get_ticks_usec()
		for i in 100000:
			acc += fc.noise(px[i], pz[i])
		print("BENCH GDScript->C# call overhead (noise(), ~20 ns of work) %.3f us/call" % [float(Time.get_ticks_usec() - t0) / 100000.0])
		print("BENCH libm engine fallbacks so far: %d" % fc.libm_engine_calls)
	print("BENCH done ", acc != 0.0)
	t.queue_free()
	quit()

extends SceneTree
## FarHills backdrop build, run synchronously: the C# batched grid (far_ground / far_colors) against the
## GDScript field per point, and how many far trees come out.
## godot --headless --path godot -s res://tools/far_hills_probe.gd [-- seed]

func _build(t: Terrain, f) -> Dictionary:
	var fh := FarHills.new()
	fh.setup(t)
	var job := {"f": f, "cx": 0.0, "cz": 0.0, "half": FarHills.HALF, "step": FarHills.STEP, "trees": true, "ring": 0}
	var t0 := Time.get_ticks_msec()
	fh._run(job)
	var out: Dictionary = job.out
	out["ms"] = Time.get_ticks_msec() - t0
	fh.free()
	return out

func _init() -> void:
	var seed := 4242
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: seed = int(a[0])
	var tc := Terrain.new()
	tc.use_cs = true
	tc.set_seed(seed)
	var tg := Terrain.new()
	tg.use_cs = false
	tg.set_seed(seed)
	if tc.fcs == null:
		push_error("C# field not available"); quit(1); return
	var oc := _build(tc, tc.fcs.fork())
	var og := _build(tg, tg.field.fork())
	var vc: PackedVector3Array = oc.verts
	var vg: PackedVector3Array = og.verts
	var cc: PackedColorArray = oc.cols
	var cg: PackedColorArray = og.cols
	var dh := 0.0
	var dc := 0.0
	for i in vc.size():
		dh = maxf(dh, absf(vc[i].y - vg[i].y))
		dc = maxf(dc, maxf(absf(cc[i].r - cg[i].r), maxf(absf(cc[i].g - cg[i].g), absf(cc[i].b - cg[i].b))))
	var pc := (oc.pines as PackedFloat32Array).size() / 20
	var bc := (oc.blobs as PackedFloat32Array).size() / 20
	var pg := (og.pines as PackedFloat32Array).size() / 20
	var bg := (og.blobs as PackedFloat32Array).size() / 20
	print("FARHILLS seed %d: %d verts, C# %d ms, GDScript %d ms" % [seed, vc.size(), oc.ms, og.ms])
	print("FARHILLS max height diff %.6f m, max colour diff %.6f" % [dh, dc])
	print("FARHILLS trees C#: %d pines %d blobs | GDScript: %d pines %d blobs" % [pc, bc, pg, bg])
	var ok := vc.size() == vg.size() and dh < 0.01 and dc < 0.01 and pc + bc > 0 and pc == pg and bc == bg
	print("FARHILLS PROBE: ", "PASS" if ok else "FAIL")
	# Terrain cleans up in _exit_tree (worker tasks, C# objects): put both in the tree, then free them there
	root.add_child(tc); root.add_child(tg)
	tc.queue_free(); tg.queue_free()
	await process_frame
	quit(0 if ok else 1)

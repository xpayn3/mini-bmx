extends SceneTree
## Land Lab's worker (the editor tab addons/land_lab runs it; the world generator isn't a @tool script, so it can't run
## inside the editor): builds the real world for one seed with the given land values and samples an area.
## -s res://tools/land_lab_render.gd -- <job.json>
## job: {seed, cx, cz, size, n, values: {key: value}, out: "<dir>"}  ->  <out>/h.bin (n*n float32 heights, row = z),
## <out>/c.png (n x n ground colours), <out>/meta.json ({ms, trail: [x0, z0, x1, z1, ...] in grid units, n, step, ox, oz}).
## Exit code 0 = done.
## -- --serve <dir>: stays running (the editor tab's worker, so a rebuild doesn't pay Godot's ~3 s start): runs
## <dir>/job.json whenever it changes and writes <dir>/done.txt = the job's "id"; quits when <dir>/alive hasn't been
## touched for 15 s (the editor closed) or <dir>/stop exists.

var _serve := ""
var _last := 0

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 1 and a[0] == "--serve":
		_serve = a[1]
		print("LANDLAB serving ", _serve)
		return
	var code := 1
	if a.size() > 0:
		code = _run(a[0])
	quit(code)


func _process(_dt: float) -> bool:
	if _serve == "":
		return false
	OS.delay_msec(40)
	var now := int(Time.get_unix_time_from_system())
	var alive := FileAccess.get_modified_time(_serve.path_join("alive"))
	if FileAccess.file_exists(_serve.path_join("stop")) or (alive > 0 and now - alive > 15):
		print("LANDLAB worker stops")
		return true
	var jp := _serve.path_join("job.json")
	if not FileAccess.file_exists(jp):
		return false
	var txt := FileAccess.get_file_as_string(jp)
	var hsh := txt.hash()
	if txt == "" or hsh == _last:
		return false
	_last = hsh
	var j = JSON.parse_string(txt)
	var code := _run(jp)
	var d := FileAccess.open(_serve.path_join("done.txt"), FileAccess.WRITE)
	d.store_string("%d %d" % [int(j.get("id", -1)) if j is Dictionary else -1, code])
	d.close()
	return false


func _run(job_path: String) -> int:
	var t0 := Time.get_ticks_msec()
	var j = JSON.parse_string(FileAccess.get_file_as_string(job_path))
	if not j is Dictionary:
		printerr("LANDLAB bad job ", job_path)
		return 2
	var n := int(j.get("n", 256))
	var size := float(j.get("size", 1200.0))
	var step := size / (n - 1)
	var ox := float(j.get("cx", 0.0)) - size * 0.5
	var oz := float(j.get("cz", 0.0)) - size * 0.5
	LandParams.values = LandParams.defaults()
	var vals: Dictionary = j.get("values", {})
	for k in vals:
		if LandParams.values.has(k):
			LandParams.values[k] = float(vals[k])
	LandParams.apply()
	var field := TerrainField.new()
	field.setup(int(j.get("seed", 4242)))
	var fcs = Terrain._make_cs()
	if fcs == null:
		printerr("LANDLAB no C# field: build C# (dotnet build in godot/)")
		return 3
	fcs.setup_from(field)
	var H := PackedFloat32Array(); H.resize(n * n)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var row := 0
	while row < n:
		var c := mini(32, n - row)
		var h: PackedFloat32Array = fcs.map_heights(ox, oz, step, n, row, c)
		var col: PackedColorArray = fcs.map_colors(ox, oz, step, n, row, c, TerrainField.WATER - 0.05)
		for i in h.size():
			H[row * n + i] = h[i]
			img.set_pixel(i % n, row + i / n, col[i])
		row += c
	var out: String = j.get("out", "user://landlab/job")
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("h.bin"), FileAccess.WRITE)
	f.store_buffer(H.to_byte_array())
	f.close()
	img.save_png(out.path_join("c.png"))
	var tr := []
	var X: PackedFloat64Array = field.course.X
	var Z: PackedFloat64Array = field.course.Z
	for i in range(0, X.size(), 2):
		var gx := (X[i] - ox) / step
		var gz := (Z[i] - oz) / step
		if gx > -2 and gz > -2 and gx < n + 1 and gz < n + 1:
			tr.append(snappedf(gx, 0.01)); tr.append(snappedf(gz, 0.01))
	var meta := {"ms": Time.get_ticks_msec() - t0, "n": n, "step": step, "ox": ox, "oz": oz, "trail": tr}
	var m := FileAccess.open(out.path_join("meta.json"), FileAccess.WRITE)
	m.store_string(JSON.stringify(meta))
	m.close()
	fcs = null
	field = null
	print("LANDLAB done ", out, " ms=", meta.ms)
	return 0

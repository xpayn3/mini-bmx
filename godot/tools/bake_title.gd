extends Node
## Bakes the title screen's fixed land (world/title_terrain.gd): the title world (Game.TITLE_SEED) built once, the
## chunks round the lookout (Game.TITLE_SPOT) and the far hills' backdrop saved into res://assets/title/title_land.bin.
## The title then loads that file: no generator, no streaming, no worker threads. Run again only when the land's
## code changes (chunk builder, terrain field, far hills):
##   ..._console.exe --headless --path godot res://tools/bake_title.tscn

const OUT := "res://assets/title/title_land.bin"
const VER := 1

func _ready() -> void:
	var radius := Terrain.RADIUS
	var t0 := Time.get_ticks_msec()
	var sp: Vector3 = Game.TITLE_SPOT
	var t := Terrain.new(Game.TITLE_SEED)
	t.keep_outs = true
	add_child(t)
	t.update_stream(sp.x, sp.y, INF)
	var t1 := Time.get_ticks_msec()
	var fh := FarHills.new()
	fh.ridge_gain = 1.4   # as Game gives the title
	fh.setup(t)
	var far: Dictionary = fh.build_now(sp.x, sp.y)
	var chunks := {}
	var per := {}
	for k in t.outs:
		chunks[k] = t.outs[k]
		for key in t.outs[k]["o"]:
			per[key] = per.get(key, 0) + var_to_bytes_with_objects(t.outs[k]["o"][key]).size()
	var keys := per.keys()
	keys.sort_custom(func(a, b): return per[a] > per[b])
	for key in keys.slice(0, 10): print("BAKETITLE  %s %.1f MB raw" % [key, per[key] / 1048576.0])
	var data := {"ver": VER, "seed": Game.TITLE_SEED, "spot": sp, "radius": radius, "chunks": chunks, "far": far}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var f := FileAccess.open_compressed(OUT, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var(data, true)
	f.close()
	var sz := FileAccess.get_file_as_bytes(OUT).size()
	print("BAKETITLE chunks=%d radius=%d far_verts=%d build=%d ms far=%d ms file=%.1f MB -> %s" % [chunks.size(), radius,
		(far.verts as PackedVector3Array).size(), t1 - t0, Time.get_ticks_msec() - t1, sz / 1048576.0, OUT])
	fh.free()
	t.queue_free()
	get_tree().quit()

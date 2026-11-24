extends SceneTree
## res://levels/world_cut.tscn (-s, headless): a level from a stretch of the procedural world (what the dock's "Import
## world trail" does), a sculpted mound + painted sand beside the trail (what the brushes do), then baked.
## -- <import file from tools/import_world.gd>
func _init() -> void:
	var src := OS.get_cmdline_user_args()[0]
	var fa := FileAccess.open(src, FileAccess.READ)
	var d: Dictionary = fa.get_var()
	fa.close()
	var lvl := BmxLevel.make_new("World Cut 4242")
	lvl.scene_file_path = "res://levels/world_cut.tscn"
	lvl.apply_import(d)
	var L := lvl.layers
	# a mound 60 m down the trail, 14 m to its side, and a strip of sand beside the start (as the brushes would)
	var f := lvl.make_field(); f.bake(1.0)
	var i := mini(60, f.TX.size() - 1)
	var c := Vector2(f.TX[i], f.TZ[i]) + LevelField._side(Vector2(f.DX[i], f.DZ[i])) * 14.0
	for j in L.grid_nz:
		for q in L.grid_nx:
			var x := L.grid_x0 + q; var z := L.grid_z0 + j
			var r := Vector2(x, z).distance_to(c) / 9.0
			if r < 1.0: L.sculpt[j * L.grid_nx + q] += 3.0 * (1.0 - r * r) * (1.0 - r * r)
			if x > 15.0 and x < 40.0 and absf(z - 8.0) < 3.0: L.paint[j * L.grid_nx + q] = 2
	ResourceSaver.save(L, L.resource_path)
	var ps := PackedScene.new()
	ps.pack(lvl)
	print("MAKEWORLD save=", ResourceSaver.save(ps, "res://levels/world_cut.tscn"), " layers=", L.resource_path)
	var r2 := LevelBake.bake(lvl, "res://levels/world_cut.tscn")
	print("MAKEWORLD bake ok=", r2.ok, " ", r2.field.summary())
	for m in r2.checks: print("  ", m)
	lvl.free()
	quit()

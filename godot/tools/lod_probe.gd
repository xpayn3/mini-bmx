extends SceneTree
## Ground LOD keys per chunk (error in metres) for one seed, to see which levels Godot can pick.
func _init():
	var t = load("res://scripts/world/terrain.gd").new()
	root.add_child(t)
	t.set_seed(12345)
	t.update_stream(0, 0, INF)
	var all := []
	for k in t.chunks:
		var gi: MeshInstance3D = t.chunks[k]["node"].get_child(0)
		var m: ArrayMesh = gi.mesh
		all.append([k, m.surface_get_array_len(0), m.surface_get_array_index_len(0)])
	print("chunks ", all.size(), " sample ", all.slice(0, 3))
	var b := TerrainChunkBuilder.new(t.field.fork(), 2, 1, t.seg, 0)
	b.run()
	print("lod keys chunk(2,1): ", b.out["lods"].keys())
	b = TerrainChunkBuilder.new(t.field.fork(), 0, 0, t.seg, 0)
	b.run()
	print("lod keys chunk(0,0): ", b.out["lods"].keys())
	quit()

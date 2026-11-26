extends SceneTree
## the colliders (trees, stumps, logs, rocks, snags) of the chunk round a spot within r m of it -- seed x z [r]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var x := float(a[1]); var z := float(a[2]); var r := float(a[3]) if a.size() > 3 else 4.0
	var ccx := roundi(x / 48.0); var ccz := roundi(z / 48.0)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var b := TerrainChunkBuilder.new(t.fcs.fork() if t.fcs != null else t.field.fork(), ccx + dx, ccz + dz, t.seg, 0)
			b.run()
			for k in b.colliders:
				var d := Vector2(k.x - x, k.z - z).length()
				if d < r: print("OBST d=%.2f %s" % [d, str(k).left(160)])
	var f: TerrainField = t.field
	f.query(x, z)
	print("OBST trail q_d=%.2f q_w=%.2f kind=%d forest_clear?" % [f.q_d, f.q_w, f.q_kind])
	t.free(); quit()

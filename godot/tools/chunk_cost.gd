extends SceneTree
## chunk build time with the C# field (as in the game): -- seed n ; prints the mean ms per chunk and of the tree / nature stages
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var n := int(a[1]) if a.size() > 1 else 24
	var tot := 0.0; var st := {}
	for i in n:
		var b := TerrainChunkBuilder.new(t.fcs.fork() if t.fcs != null else t.field.fork(), 4 + i % 6, -3 + i / 6, t.seg, 0)
		b.run()
		tot += b.ms_used
		for k in b.stage_ms: st[k] = float(st.get(k, 0.0)) + b.stage_ms[k]
	var line := ""
	for k in st: line += "%s=%.1f " % [k, st[k] / n]
	print("CHUNKCOST seed=%s ms=%.1f per chunk | %s" % [a[0], tot / n, line])
	t.free(); quit()

extends SceneTree
## what is on the trail near a world spot: nearest course point (s, kind), drops, route features within 60 m, and the
## centreline ground from 60 m before to 40 m after. -- seed x z
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var f: TerrainField = t.field
	var C = f.course
	var px := float(a[1]); var pz := float(a[2])
	var bi := 0; var bd := INF
	for i in C.n:
		var d: float = Vector2(C.X[i] - px, C.Z[i] - pz).length()
		if d < bd: bd = d; bi = i
	var s := bi * 2.0
	print("SPOT nearest s=%.0f dist=%.1f kind=%d bank=%.2f kap=%.3f" % [s, bd, C.KD[bi], C.BT[bi], C.KAP[bi]])
	for d in C.drops: print("SPOT drop %.0f..%.0f" % [d[0] * 2.0, d[1] * 2.0])
	for ft in f.route_feats:
		if absf(ft.s - s) < 80: print("SPOT feat %s s=%.0f len=%.0f size=%d" % [ft.type, ft.s, ft.len, ft.size])
	var line := ""
	var q := s - 60.0
	while q <= s + 40.0:
		var p: Array = C.at(q)
		line += "%.0f:%.2f " % [q, f.ground(p[0], p[1])]
		q += 4.0
	print("SPOT ground ", line)
	t.free(); quit()

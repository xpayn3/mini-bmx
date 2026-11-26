extends SceneTree
## the trail centreline's ground height from s0 to s1 every ds (-- seed s0 s1 ds)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var f: TerrainField = t.field
	var C = f.course
	var s := float(a[1])
	var line := ""
	while s <= float(a[2]):
		var p: Array = C.at(s)
		line += "%.0f:%.2f(k%d,j%.1f) " % [s, f.ground(p[0], p[1]), C.KD[p[4]], f.jump_mask(p[0], p[1])]
		s += float(a[3])
	print("PROFILE ", line)
	t.free(); quit()

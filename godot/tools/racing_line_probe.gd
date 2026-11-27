extends SceneTree
## Racing line check: for each sharp bend of the first course (|KAP| peak > 0.03), where the line sits across the
## trail at the apex and ~15 m before it, as a share of the room it has (+1 = all the way to the inside of the bend).
## A good line: apex well inside (> 0.5), entry on the outside (< 0). Old formula: BMX_OLD_LINE2=1.
## Run: godot --headless --path godot -s res://tools/racing_line_probe.gd [-- seed]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var seed := int(a[0]) if a.size() > 0 else 4242
	var f := TerrainField.new()
	f.setup(seed)
	var c: TrailCourse = f.course
	var n_b := 0
	var swing := 0.0; var apex_sum := 0.0; var entry_sum := 0.0; var apex_in := 0; var entry_out := 0
	for i in range(10, c.n - 10):
		var k := absf(c.KAP[i])
		if k < 0.03 or k < absf(c.KAP[i - 1]) or k <= absf(c.KAP[i + 1]):
			continue
		var room := maxf(0.05, c.W[i] - TrailCourse.LINE_MARGIN)
		var side := signf(c.KAP[i])   # LN > 0 = the side KAP > 0 turns to? measured below
		var ap := c.LN[i] * side / room
		var j := maxi(0, i - 7)
		var en := c.LN[j] * side / maxf(0.05, c.W[j] - TrailCourse.LINE_MARGIN)
		n_b += 1; swing += absf(ap - en); apex_sum += ap; entry_sum += en
		if ap > 0.5: apex_in += 1
		if en < 0.0: entry_out += 1
		if n_b <= 12:
			print("BEND i=%d R=%.1f m  W=%.2f  bank=%.2f  apex %+.2f  entry %+.2f" % [i, 1.0 / k, c.W[i], c.BT[i], ap, en])
	print("LINESUM swing=%.2f bends=%d apex_mean=%+.2f apex_inside=%d entry_mean=%+.2f entry_outside=%d" % [swing / maxf(1, n_b), n_b, apex_sum / maxf(1, n_b), apex_in, entry_sum / maxf(1, n_b), entry_out])
	quit()

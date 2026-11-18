extends SceneTree
## Garage close-ups: res://tools/garage_shot.gd -- <out.png> <orbit> <pitch> <dist> <fx> <fy> [tab]
func _init():
	var a := OS.get_cmdline_user_args()
	var g = load("res://scripts/garage/garage.gd").new()
	root.add_child(g)
	await process_frame
	if a.size() > 6: g._set_tab(a[6])
	g.auto_spin = false
	g.orbit = float(a[1]); g.orbit_t = g.orbit; g.pitch = float(a[2]); g.pitch_t = g.pitch
	g.dist = float(a[3]); g.dist_t = g.dist; g.focus = Vector3(float(a[4]), float(a[5]), 0); g.focus_t = g.focus
	for i in 40: await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit()

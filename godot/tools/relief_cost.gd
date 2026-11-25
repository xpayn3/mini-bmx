extends SceneTree
## C# ground-height cost with the relief layers (BMX_LAND to switch them off): us per point over an area by the trail
## and one away from it. -s res://tools/relief_cost.gd
func _init() -> void:
	var f := TerrainField.new()
	f.setup(4242)
	var cs = Terrain._make_cs()
	cs.setup_from(f)
	for area in [[1400.0, -400.0, "by the trail"], [1400.0, 900.0, "off the trail"]]:
		cs.map_heights(area[0], area[1], 2.0, 256, 0, 8)   # warm
		var t0 := Time.get_ticks_usec()
		cs.map_heights(area[0], area[1], 2.0, 256, 0, 256)
		print("RCOST %s: %.2f us a point" % [area[2], float(Time.get_ticks_usec() - t0) / 65536.0])
	cs = null
	quit()

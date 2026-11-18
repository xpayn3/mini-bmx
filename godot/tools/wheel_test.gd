extends SceneTree
## Headless check of WheelGen: builds stock front / rear and a few variants, prints tri counts per
## surface, tyre radius, AABB and build time; checks the cache and the surface names.
## godot --headless --path godot -s res://tools/wheel_test.gd

const VARIANTS := [
	["stock front", {}],
	["stock rear", {"rear": true}],
	["26in 36h radial thick gold", {"bsd_mm": 559, "spokes": 36, "lacing": 0, "spoke_gauge": 2,
		"rim_color": Color(0.85, 0.65, 0.2), "rim_finish": "gloss", "spoke_color": Color(0.85, 0.65, 0.2),
		"nipple_color": Color(0.85, 0.65, 0.2), "hub_color": Color(0.85, 0.65, 0.2)}],
	["29in 24h 3x", {"bsd_mm": 622, "spokes": 24, "lacing": 3}],
	["27.5 rear 28h 2x semi tan", {"rear": true, "spokes": 28, "lacing": 2, "tread": "semi", "sidewall": "tan",
		"tyre_w_in": 2.35, "rim_width_mm": 30.0, "rim_depth_mm": 20.0}],
	["29 slick chrome rim 40mm deep", {"tread": "slick", "rim_finish": "chrome", "rim_depth_mm": 40.0,
		"tyre_w_in": 2.3}],
	["rear 11sp cassette", {"rear": true, "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42]}],
	["front detail 0.5", {"detail": 0.5}],
]

func _initialize() -> void:
	var ok := true
	for v in VARIANTS:
		var spec: Dictionary = v[1]
		WheelGen.clear_cache()
		var t0 := Time.get_ticks_usec()
		var m := WheelGen.build(spec)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var t1 := Time.get_ticks_usec()
		var m2 := WheelGen.build(spec)
		var ms_cached := (Time.get_ticks_usec() - t1) / 1000.0
		var tris := 0
		var parts := []
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var nt: int = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			tris += nt
			parts.append("%s=%d" % [m.surface_get_material(si).resource_name, nt])
		print("%-32s tris=%6d  radius=%.4f  build=%.1f ms  cached=%.3f ms (same=%s)  aabb=%s  [%s]" % [
			v[0], tris, WheelGen.tyre_radius(spec), ms, ms_cached, m == m2, m.get_aabb(), ", ".join(parts)])
		if m.surface_get_material(0).resource_name != "rubber":
			ok = false
		if tris > 25000:
			print("   !! over 25k tris")
	print("tyre_radius 622/2.5 = %.4f (stock 0.3743)   584/2.5 = %.4f (stock 0.3553)" % [
		WheelGen.tyre_radius({"bsd_mm": 622}), WheelGen.tyre_radius({"bsd_mm": 584})])
	print("OK" if ok else "FAIL")
	quit()

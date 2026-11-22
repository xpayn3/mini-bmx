extends SceneTree
## finds side-path junctions: grid points (0.375 m) where the baked trail frame switches between the
## course and a side path while both sides are trail dirt. -s res://tools/junction_probe.gd -- [seed]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 4242
	var tg := Terrain.new()
	tg.use_cs = false
	tg.set_seed(seed)
	var f: TerrainField = tg.field
	var C = f.course
	var found := 0
	var d := 0.375
	var u := 20.0
	while u < 3000.0 and found < 12:
		var pa: Array = C.at(u)
		var p := Vector3(pa[0], 0, pa[1])
		var hit := false
		for ix in range(-40, 41):
			for iz in range(-40, 41):
				var x := snappedf(p.x, d) + ix * d
				var z := snappedf(p.z, d) + iz * d
				f.query(x, z)
				var on: bool = f.q_d < f.q_w + 2.6
				f.query(x + d, z)
				var on2: bool = f.q_d < f.q_w + 2.6
				if on != on2 and f.trail(x, z) > 0.5 and f.trail(x + d, z) > 0.5:
					print("JUNCTION u=%.0f x=%.2f z=%.2f y=%.2f" % [u, x, z, f.ground(x, z)])
					found += 1
					hit = true
					break
			if hit:
				break
		u += 30.0 if not hit else 120.0
	quit()

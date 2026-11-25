extends SceneTree
## Climate biomes: C# vs GDScript weights (must match exactly) and each biome's share of the land beside the first ~9 km of
## trail, per seed. -s res://tools/biome_probe.gd [-- seed ...]
func _init() -> void:
	var seeds: Array = [4242, 5, 7, 12, 99, 1]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = []
		for a in args: seeds.append(int(a))
	var tot := {}
	var n_tot := 0
	var bad := 0
	for sd in seeds:
		var f := TerrainField.new()
		f.setup(sd, {})
		var cs = load("res://scripts/world/TerrainFieldCs.cs").new()
		cs.setup_from(f)
		var cnt := {}
		var n := 0
		var x := -200.0
		while x < 9000.0:
			for dz in [-700.0, -350.0, -120.0, 120.0, 350.0, 700.0]:
				var z: float = f.zc(x) + dz
				f.biome(x, z); cs.biome(x, z)
				if f.b_cold != cs.b_cold or f.b_wet != cs.b_wet or f.b_forest != cs.b_forest or f.b_sav != cs.b_sav or f.b_ash != cs.b_ash or f.b_dry != cs.b_dry or f.b_rug != cs.b_rug: bad += 1
				var nm: String = f.biome_name(x, z)
				if nm != cs.biome_name(x, z): bad += 1
				cnt[nm] = int(cnt.get(nm, 0)) + 1
				tot[nm] = int(tot.get(nm, 0)) + 1
				n += 1; n_tot += 1
			x += 41.0
		var parts := []
		for k in cnt: parts.append("%s %.0f%%" % [k, 100.0 * cnt[k] / n])
		parts.sort()
		print("BIOME seed=%d %s" % [sd, ", ".join(parts)])
	var parts2 := []
	for k in tot: parts2.append("%s %.1f%%" % [k, 100.0 * tot[k] / n_tot])
	parts2.sort()
	print("BIOME ALL %s" % ", ".join(parts2))
	print("BIOME ", "EXACT" if bad == 0 else "MISMATCH %d" % bad)
	quit()

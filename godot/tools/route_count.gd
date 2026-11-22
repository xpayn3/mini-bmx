extends SceneTree
## tests: how many of each route feature the first 4 km of a few worlds have (run after changing feature sizes)
func _init() -> void:
	var tot := {}
	for sd in [4242, 5, 7, 12, 99, 1, 2, 3, 31, 77, 123, 2024]:
		var tg := Terrain.new()
		tg.use_cs = false
		tg.set_seed(sd)
		var c := {}
		for j in tg.field.route_feats:
			c[j.type] = int(c.get(j.type, 0)) + 1
			tot[j.type] = int(tot.get(j.type, 0)) + 1
		print("SEED %d %s" % [sd, c])
		tg.free()
	print("ROUTE TOTAL %s" % [tot])
	quit()

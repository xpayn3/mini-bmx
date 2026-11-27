extends SceneTree
## lists seeds whose first 4 km have a rope bridge (test aid: BMX_SEED=<n> BMX_TRAIL_FEAT=rope)
func _init() -> void:
	for sd in range(1, 60):
		var tg := Terrain.new()
		tg.set_seed(sd)
		for j in tg.field.route_feats:
			if j.type == "rope":
				print("ROPESEED %d s=%d" % [sd, int(j.s)])
		tg.free()
	quit()

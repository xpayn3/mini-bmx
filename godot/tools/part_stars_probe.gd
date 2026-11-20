extends SceneTree
## Prints the star rating + score of every tyre, rim and fork model: godot -s res://tools/part_stars_probe.gd --headless

func _init() -> void:
	for kind in ["tyre", "rim", "fork"]:
		print("== ", kind)
		var models: Dictionary = BikeBuild._part_models(kind)
		for k in models:
			if not models[k].has("brand"): continue
			print("PARTSTARS %s %-12s %s  score=%.3f  price=%d" % [kind, k, BikeBuild.star_text(BikeBuild.part_stars(kind, k)),
				BikeBuild._part_score(kind, k), Shop.price(kind, k)])
	quit()

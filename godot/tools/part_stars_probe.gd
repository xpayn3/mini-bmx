extends Node
## Prints the star rating + score + price of every tyre, rim and fork model (a scene, not -s: it needs the autoloads):
## godot --headless --path godot res://tools/part_stars_probe.tscn

func _ready() -> void:
	for kind in ["tyre", "rim", "fork"]:
		print("== ", kind)
		var models: Dictionary = BikeBuild._part_models(kind)
		for k in models:
			if not models[k].has("brand"): continue
			print("PARTSTARS %s %-12s %s  score=%.3f  price=%d" % [kind, k, BikeBuild.star_text(BikeBuild.part_stars(kind, k)),
				BikeBuild._part_score(kind, k), Shop.price(kind, k)])
	get_tree().quit()

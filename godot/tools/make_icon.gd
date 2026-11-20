extends SceneTree
## Renders icon.svg to icon_256.png (for the Windows .exe icon, built into icon.ico by a Pillow one-liner (see steam/README.md)
## and for the Steam client / store icons). Run:
##   ..._console.exe --headless --path godot -s res://tools/make_icon.gd
func _init() -> void:
	var img := Image.new()
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for s in [256, 184, 32]:
		img.load_svg_from_string(svg, s / 128.0)
		img.save_png(ProjectSettings.globalize_path("res://").path_join("../steam/icons/icon_%d.png" % s))
	print("icon done")
	quit()

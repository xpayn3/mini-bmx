extends SceneTree
## bakes levels headless (-s): -- res://levels/a.tscn [res://levels/b.tscn ...]  (the dock's "Bake level")
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var root = load(p).instantiate()
		var r := LevelBake.bake(root, p)
		print("BAKELEVEL ", p, " ok=", r.ok, " ms=", r.get("ms", 0), " size=", r.get("size", 0))
		for c in r.checks: print("  ", c)
		root.free()
	quit()

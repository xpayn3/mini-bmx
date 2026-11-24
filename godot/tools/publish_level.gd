extends SceneTree
## publishes levels headless (-s, the dock's "Publish"): -- res://levels/a.tscn [...]; saves the scene's published flag
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var root: BmxLevel = load(p).instantiate()
		var r := LevelPublish.publish(root)
		print("PUBLISH ", p, " ok=", r.ok, "\n", r.msg)
		if r.ok:
			var ps := PackedScene.new(); ps.pack(root); ResourceSaver.save(ps, p)
		root.free()
	quit()

@tool
extends EditorPlugin
## Mini BMX level builder: a dock (right side, "Level Builder") to make a new level, keep the trail on the
## ground, and ride the level in the game. The pieces are plain nodes: BmxLevel (the slope, the scene's root)
## and BmxTrail (a Path3D: draw the line with the curve tools). Levels are saved in res://levels/.

const LEVEL_DIR := "res://levels/"
var dock: VBoxContainer
var info: Label
var _lvl: BmxLevel
var _args_back = null


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Level Builder"
	var head := Label.new()
	head.text = "MINI BMX LEVEL BUILDER"
	dock.add_child(head)
	_button("New level", _new_level, "A new scene in res://levels/ with a slope and a winding trail")
	_button("Snap trail to ground", _snap, "Puts every trail point on the land (the handles sit where the trail is)")
	_button("Rebuild preview", _rebuild, "Bakes the ground again now")
	_button("▶  Ride this level", _ride, "Saves the scene and starts the game on it")
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(180, 0)
	info.text = "Open a level (res://levels/) or make a new one."
	dock.add_child(info)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "Trail: select it, use the Path3D tools (add / move points, drag handles). Line colour = speed (blue slow .. red fast), ticks = berm bank (white flat .. yellow steep). Green post = start, white = end."
	dock.add_child(help)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	scene_changed.connect(_on_scene)
	_on_scene(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene): scene_changed.disconnect(_on_scene)
	remove_control_from_docks(dock)
	dock.queue_free()


func _button(text: String, cb: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	dock.add_child(b)


func _on_scene(root: Node) -> void:
	if _lvl and is_instance_valid(_lvl) and _lvl.rebuilt.is_connected(_on_rebuilt): _lvl.rebuilt.disconnect(_on_rebuilt)
	_lvl = root as BmxLevel
	if _lvl:
		_lvl.rebuilt.connect(_on_rebuilt)
		info.text = "%s\n%s" % [_lvl.title, _lvl.field.summary() if _lvl.field else "building preview..."]
	elif info:
		info.text = "This scene is not a level (its root is not a BmxLevel)."


func _on_rebuilt(s: String) -> void:
	if _lvl: info.text = "%s\n%s" % [_lvl.title, s]


func _new_level() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEVEL_DIR))
	var n := 1
	while FileAccess.file_exists(LEVEL_DIR + "level_%d.tscn" % n): n += 1
	var path := LEVEL_DIR + "level_%d.tscn" % n
	var lvl := BmxLevel.make_new("Level %d" % n)
	var ps := PackedScene.new()
	ps.pack(lvl)
	lvl.free()
	var err := ResourceSaver.save(ps, path)
	if err != OK:
		info.text = "Could not save %s (%d)" % [path, err]
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)


func _snap() -> void:
	if _lvl == null: return
	var t := _lvl.trail()
	if t == null: return
	var ur := get_undo_redo()
	ur.create_action("Snap trail to ground")
	ur.add_undo_property(t, "curve", t.curve.duplicate())
	_lvl.snap_trail_to_ground()
	ur.add_do_property(t, "curve", t.curve.duplicate())
	ur.commit_action(false)


func _rebuild() -> void:
	if _lvl: _lvl.rebuild_preview()


func _ride() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not (root is BmxLevel) or root.scene_file_path == "":
		info.text = "Open (and save) a level scene first."
		return
	EditorInterface.save_scene()
	_args_back = ProjectSettings.get_setting("editor/run/main_run_args", "")
	ProjectSettings.set_setting("editor/run/main_run_args", "-- --level=" + root.scene_file_path)
	EditorInterface.play_main_scene()
	get_tree().create_timer(2.0).timeout.connect(func():
		ProjectSettings.set_setting("editor/run/main_run_args", _args_back))

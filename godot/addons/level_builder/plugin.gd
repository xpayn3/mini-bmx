@tool
extends EditorPlugin
## Mini BMX level builder: a dock (right side, "Level Builder") + editing in the 3D view.
##   New level / Snap trail / Rebuild preview / Ride this level.
##   PLACE: pick a piece (Jump, Drop, Rocks, Gate), a ghost follows the mouse on the ground (snapped to the grid);
##          Q / E turn it by the rotation step, click drops one (click again for more), right click / Esc ends.
##   DRAG:  left-drag any piece on the ground to move it (snapped; a piece that follows the trail slides along it),
##          Alt + drag turns it; one undo step per drag. (The usual gizmo still works: grab its arrows.)
##   Snap:  on / off, grid size, rotation step (Shift held = free); the preview ground draws the grid.
## The pieces are plain nodes (BmxLevel root, BmxTrail, BmxJump / BmxDrop / BmxRocks / BmxGate): every number is
## in the Inspector. Levels are saved in res://levels/.

const LEVEL_DIR := "res://levels/"
const PIECES := {"BmxJump": preload("res://scripts/levels/editor/bmx_jump.gd"), "BmxDrop": preload("res://scripts/levels/editor/bmx_drop.gd"),
	"BmxRocks": preload("res://scripts/levels/editor/bmx_rocks.gd"), "BmxGate": preload("res://scripts/levels/editor/bmx_gate.gd")}
## the ghost's size per piece (across, up, along) and where it sits along from the node (a jump's node is its lip)
const GHOST := {"BmxJump": [3.0, 1.2, 14.0, -5.0], "BmxDrop": [3.4, 1.5, 22.0, 9.0], "BmxRocks": [4.0, 0.3, 24.0, 12.0], "BmxGate": [7.0, 3.6, 0.3, 0.0]}

var dock: VBoxContainer
var info: Label
var _lvl: BmxLevel
var _args_back = null

# snapping
var snap_on := true
var grid := 1.0
var rot_step := 15.0

# place mode
var _placing := ""
var _ghost: MeshInstance3D
var _ghost_yaw := 0.0
var _place_btns := {}

# drag
var _drag: BmxPiece = null
var _drag_from: Transform3D
var _drag_off := Vector3.ZERO
var _drag_rot := false
var _drag_x0 := 0.0
var _drag_yaw0 := 0.0


func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "Level Builder"
	var head := Label.new()
	head.text = "MINI BMX LEVEL BUILDER"
	dock.add_child(head)
	_button(dock, "New level", _new_level, "A new scene in res://levels/ with a slope and a winding trail")
	_button(dock, "Snap trail to ground", _snap_trail, "Puts every trail point on the land (the handles sit where the trail is)")
	_button(dock, "Rebuild preview", _rebuild, "Bakes the ground again now")
	_button(dock, "▶  Ride this level", _ride, "Saves the scene and starts the game on it")
	dock.add_child(HSeparator.new())
	var pl := Label.new(); pl.text = "PLACE (click in the 3D view)"
	dock.add_child(pl)
	var row := HFlowContainer.new()
	dock.add_child(row)
	for it in [["Jump", "BmxJump"], ["Drop", "BmxDrop"], ["Rocks", "BmxRocks"], ["Gate", "BmxGate"]]:
		var b := Button.new()
		b.text = it[0]
		b.toggle_mode = true
		b.tooltip_text = "Place %s: a ghost follows the mouse; click to drop one, Q / E turn it, right click / Esc to stop" % it[0].to_lower()
		b.toggled.connect(func(on): _set_placing(it[1] if on else ""))
		row.add_child(b)
		_place_btns[it[1]] = b
	var row2 := HFlowContainer.new()
	dock.add_child(row2)
	for it in [["+ Jump on trail", "BmxJump"], ["+ Rocks on trail", "BmxRocks"]]:
		_button(row2, it[0], _add_on_trail.bind(it[1]), "Adds one on the trail where the editor camera looks, following the trail")
	dock.add_child(HSeparator.new())
	var sn := CheckBox.new(); sn.text = "Snap (Shift = free)"; sn.button_pressed = snap_on
	sn.toggled.connect(func(v): snap_on = v)
	dock.add_child(sn)
	dock.add_child(_spin("Grid (m)", grid, 0.1, 10.0, 0.1, func(v): grid = v; _show_grid()))
	dock.add_child(_spin("Rotation step (°)", rot_step, 1.0, 90.0, 1.0, func(v): rot_step = v))
	dock.add_child(HSeparator.new())
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(180, 0)
	info.text = "Open a level (res://levels/) or make a new one."
	dock.add_child(info)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "Drag a piece on the ground to move it (Alt + drag turns it). Untick follow_trail to place it anywhere; standalone = a ramp on the ground as it is. Flights: blue / green / red = 85 / 100 / 115 % of the design speed, a post where each lands. Trail: the Path3D tools. Line colour = speed (blue .. red), ticks = berm bank (white .. yellow)."
	dock.add_child(help)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	scene_changed.connect(_on_scene)
	_on_scene(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	_set_placing("")
	if scene_changed.is_connected(_on_scene): scene_changed.disconnect(_on_scene)
	remove_control_from_docks(dock)
	dock.queue_free()


func _button(parent: Control, text: String, cb: Callable, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)


func _spin(label: String, val: float, lo: float, hi: float, st: float, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var s := SpinBox.new(); s.min_value = lo; s.max_value = hi; s.step = st; s.value = val
	s.value_changed.connect(cb)
	h.add_child(s)
	return h


func _on_scene(root: Node) -> void:
	_set_placing("")
	if _lvl and is_instance_valid(_lvl) and _lvl.rebuilt.is_connected(_on_rebuilt): _lvl.rebuilt.disconnect(_on_rebuilt)
	_lvl = root as BmxLevel
	if _lvl:
		_lvl.rebuilt.connect(_on_rebuilt)
		info.text = "%s\n%s" % [_lvl.title, _lvl.field.summary() if _lvl.field else "building preview..."]
		_show_grid()
	elif info:
		info.text = "This scene is not a level (its root is not a BmxLevel)."


func _on_rebuilt(s: String) -> void:
	if _lvl:
		info.text = "%s\n%s" % [_lvl.title, s]
		_show_grid()


func _show_grid() -> void:
	if _lvl and is_instance_valid(_lvl): _lvl.show_grid(grid)


# ---- snapping ------------------------------------------------------------------------------------------------
func _snap_pos(p: Vector3) -> Vector3:
	if not snap_on or Input.is_key_pressed(KEY_SHIFT): return p
	return Vector3(snappedf(p.x, grid), p.y, snappedf(p.z, grid))


func _snap_yaw(a: float) -> float:
	if not snap_on or Input.is_key_pressed(KEY_SHIFT): return a
	return deg_to_rad(snappedf(rad_to_deg(a), rot_step))


func _ground_y(p: Vector3) -> float:
	return _lvl.field.grid_height(p.x, p.z) if _lvl.field else p.y


# ---- 3D view input ------------------------------------------------------------------------------------------
func _handles(object: Object) -> bool:
	return object is BmxLevel or object is BmxPiece


func _forward_3d_gui_input(cam: Camera3D, event: InputEvent) -> int:
	if _lvl == null or not is_instance_valid(_lvl) or _lvl.field == null: return AFTER_GUI_INPUT_PASS
	if _placing != "": return _place_input(cam, event)
	return _drag_input(cam, event)


func _hit(cam: Camera3D, pos: Vector2):
	return _lvl.ray_ground(cam.project_ray_origin(pos), cam.project_ray_normal(pos))


func _place_input(cam: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE: _set_placing(""); return AFTER_GUI_INPUT_STOP
			KEY_Q: _ghost_yaw += deg_to_rad(rot_step); _move_ghost(null); return AFTER_GUI_INPUT_STOP
			KEY_E: _ghost_yaw -= deg_to_rad(rot_step); _move_ghost(null); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		var h = _hit(cam, event.position)
		if h != null: _move_ghost(h)
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_set_placing(""); return AFTER_GUI_INPUT_STOP
		if event.button_index == MOUSE_BUTTON_LEFT:
			var h = _hit(cam, event.position)
			if h == null: return AFTER_GUI_INPUT_STOP
			_place(_placing, _snap_pos(h), _snap_yaw(_ghost_yaw))
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


var _ghost_at := Vector3.ZERO
func _move_ghost(h) -> void:
	if _ghost == null: return
	if h != null: _ghost_at = _snap_pos(h)
	var g: Array = GHOST[_placing]
	var yaw := _snap_yaw(_ghost_yaw)
	var b := Basis(Vector3.UP, yaw)
	var c := _ghost_at + b.x * float(g[3]) + Vector3(0, float(g[1]) * 0.5, 0)
	_ghost.global_transform = _lvl.global_transform * Transform3D(b, c)


func _set_placing(cls: String) -> void:
	_placing = cls
	for k in _place_btns: (_place_btns[k] as Button).set_pressed_no_signal(k == cls)
	if _ghost and is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	if cls == "" or _lvl == null or not is_instance_valid(_lvl): return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(_lvl)   # (so the 3D view's input comes to this plugin)
	var g: Array = GHOST[cls]
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(float(g[2]), float(g[1]), float(g[0]))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.9, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = m
	_ghost.mesh = bm
	_lvl.add_child(_ghost, false, Node.INTERNAL_MODE_BACK)
	_ghost.visible = true


## a new piece at p (level space), facing yaw: placed freely (not on the trail), ramps standalone
func _place(cls: String, p: Vector3, yaw: float) -> void:
	var n: BmxPiece = PIECES[cls].new()
	n.name = _free_name(cls)
	n.follow_trail = false
	if n is BmxJump or n is BmxDrop: n.standalone = true
	if n is BmxGate and not _has_gate("start"): n.gate = "start"
	n.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, _ground_y(p), p.z))
	_commit_add(n, "Place " + cls)


func _free_name(cls: String) -> String:
	var base := cls.trim_prefix("Bmx")
	var k := 1
	while _lvl.find_child(base + str(k), true, false) != null: k += 1
	return base + str(k)


func _commit_add(n: Node3D, what: String) -> void:
	var ur := get_undo_redo()
	ur.create_action(what)
	ur.add_do_method(_lvl, "add_child", n, true)
	ur.add_do_method(n, "set_owner", _lvl)
	ur.add_do_reference(n)
	ur.add_undo_method(_lvl, "remove_child", n)
	ur.commit_action()


## left-drag a piece on the ground: moves it (snapped), Alt turns it
func _drag_input(cam: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var h = _hit(cam, event.position)
			if h == null: return AFTER_GUI_INPUT_PASS
			var pc := _piece_at(h)
			if pc == null: return AFTER_GUI_INPUT_PASS
			var lt := pc.level_transform()
			if Vector2(h.x - lt.origin.x, h.z - lt.origin.z).length() < 0.9 and EditorInterface.get_selection().get_selected_nodes().has(pc):
				return AFTER_GUI_INPUT_PASS   # (on its own origin: leave it to the gizmo's arrows)
			_drag = pc
			_drag_from = pc.transform
			_drag_off = lt.origin - h
			_drag_rot = event.alt_pressed
			_drag_x0 = event.position.x
			_drag_yaw0 = lt.basis.get_euler().y
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(pc)
			return AFTER_GUI_INPUT_STOP
		elif _drag != null:
			var to := _drag.transform
			if to != _drag_from:
				var ur := get_undo_redo()
				ur.create_action("Move " + String(_drag.name))
				ur.add_do_property(_drag, "transform", to)
				ur.add_undo_property(_drag, "transform", _drag_from)
				ur.commit_action(false)
			_drag = null
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _drag != null:
		var lt := _drag.level_transform()
		if _drag_rot:
			var yaw := _snap_yaw(_drag_yaw0 - (event.position.x - _drag_x0) * 0.01)
			_set_level_transform(_drag, Transform3D(Basis(Vector3.UP, yaw), lt.origin))
		else:
			var h = _hit(cam, event.position)
			if h != null:
				var p := _snap_pos(h + _drag_off)
				p.y = _ground_y(p)
				_set_level_transform(_drag, Transform3D(lt.basis, p))
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _set_level_transform(pc: BmxPiece, want: Transform3D) -> void:
	var parent_lt := pc.level_transform() * pc.transform.affine_inverse()
	pc.transform = parent_lt.affine_inverse() * want


## the piece under a ground point: inside a jump / drop's footprint, else near a rock garden / gate's line
func _piece_at(h: Vector3) -> BmxPiece:
	var f := _lvl.field
	var best: BmxPiece = null
	var bd := INF
	for pc in _lvl.pieces():
		var lt: Transform3D = pc.level_transform()
		var d := Vector2(h.x - lt.origin.x, h.z - lt.origin.z).length()
		for st in f.structs:
			if st.name == String(pc.name):
				var l: Vector2 = f._local(st, h.x, h.z)
				if l.x > -1.0 and l.x < float(st.L) + 1.0 and absf(l.y) < float(st.reach) + 0.5: d = minf(d, 0.5)
		if pc is BmxRocks:
			var fw := Vector2(lt.basis.x.x, lt.basis.x.z).normalized()
			var q := Vector2(h.x - lt.origin.x, h.z - lt.origin.z)
			var along := q.dot(fw)
			if along > 0.0 and along < pc.length and absf(q.dot(Vector2(-fw.y, fw.x))) < 3.0: d = minf(d, 0.5)
		if d < 4.0 and d < bd: bd = d; best = pc
	return best


# ---- dock buttons --------------------------------------------------------------------------------------------
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


func _add_on_trail(cls: String) -> void:
	if _lvl == null: info.text = "Open a level first."; return
	var n: BmxPiece = PIECES[cls].new()
	n.name = _free_name(cls)
	var at := Vector3(20, 0, 0)
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if cam:
		var fw := -cam.global_transform.basis.z
		at = _lvl.global_transform.affine_inverse() * (cam.global_position + Vector3(fw.x, 0, fw.z).normalized() * 25.0)
	var f := _lvl.field
	if f and f.TX.size() > 1:
		var i := f.nearest(at.x, at.z)
		n.transform = Transform3D(Basis(Vector3.UP, atan2(-f.DZ[i], f.DX[i])), Vector3(f.TX[i], f.TY[i], f.TZ[i]))
	else:
		n.position = at
	_commit_add(n, "Add " + cls)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)


func _has_gate(kind: String) -> bool:
	for pc in _lvl.pieces():
		if pc is BmxGate and pc.gate == kind: return true
	return false


func _snap_trail() -> void:
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

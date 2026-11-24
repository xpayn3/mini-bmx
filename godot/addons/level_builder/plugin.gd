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

# sculpt
const TOOLS := ["Raise", "Lower", "Smooth", "Flatten", "Paint dirt", "Paint sand", "Paint rock", "Erase paint", "Erase sculpt"]
var brush_r := 6.0
var brush_k := 0.5
var _sculpt_btn: CheckButton
var _tool_opt: OptionButton
var _sculpting := false
var _stroke := false
var _stroke_old := {}
var _flat_y := 0.0
var _last_dab := Vector3(INF, 0, 0)
var _ring: MeshInstance3D
var _imp_seed: HBoxContainer
var _imp_start: HBoxContainer
var _imp_len: HBoxContainer

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
	_button(dock, "Rebuild preview", _rebuild, "Works the preview ground out again now")
	_button(dock, "Bake level", _bake, "Writes <level>.bake: the ground, pieces, trees and the light at the level's time of day, worked out once (the game loads it instantly). Runs the level's checks")
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
	var sl := Label.new(); sl.text = "SCULPT + PAINT (drag in the 3D view)"
	dock.add_child(sl)
	_sculpt_btn = CheckButton.new(); _sculpt_btn.text = "Sculpt mode"
	_sculpt_btn.toggled.connect(_set_sculpt)
	dock.add_child(_sculpt_btn)
	_tool_opt = OptionButton.new()
	for nm in TOOLS: _tool_opt.add_item(nm)
	dock.add_child(_tool_opt)
	dock.add_child(_spin("Brush radius (m)", brush_r, 1.0, 40.0, 0.5, func(v): brush_r = v))
	dock.add_child(_spin("Strength", brush_k, 0.05, 2.0, 0.05, func(v): brush_k = v))
	dock.add_child(HSeparator.new())
	var il := Label.new(); il.text = "IMPORT WORLD TRAIL"
	dock.add_child(il)
	_imp_seed = _spin("World seed", 4242, 0, 999999, 1, func(_v): pass)
	_imp_start = _spin("Start (m along)", 300, 0, 3500, 10, func(_v): pass)
	_imp_len = _spin("Length (m)", 600, 100, 2000, 10, func(_v): pass)
	for w in [_imp_seed, _imp_start, _imp_len]: dock.add_child(w)
	_button(dock, "Import into this level", _import_world, "Replaces this level's land and trail with that stretch of the procedural world (the trail as an editable spline). Undo puts it back")
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
	if _sculpting: return _sculpt_input(cam, event)
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


func _bake() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not (root is BmxLevel) or root.scene_file_path == "":
		info.text = "Open (and save) a level scene first."
		return
	EditorInterface.save_scene()
	var r := LevelBake.bake(root, root.scene_file_path)
	if not r.ok:
		info.text = "Bake failed: " + "
".join(r.checks)
		return
	EditorInterface.get_resource_filesystem().scan()
	info.text = "%s
BAKED in %.1f s · %.1f MB · %s

CHECKS
%s" % [root.title, r.ms / 1000.0, r.size / 1048576.0, r.path.get_file(), "
".join(r.checks)]


func _rebuild() -> void:
	if _lvl: _lvl.rebuild_preview()


func _ride() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not (root is BmxLevel) or root.scene_file_path == "":
		info.text = "Open (and save) a level scene first."
		return
	EditorInterface.save_scene()
	if LevelBake.load_bake(root.scene_file_path, LevelBake.signature(root)).is_empty():
		info.text += "
(no up-to-date bake: the game works the level out live, no baked light. Bake level to fix.)"
	_args_back = ProjectSettings.get_setting("editor/run/main_run_args", "")
	ProjectSettings.set_setting("editor/run/main_run_args", "-- --level=" + root.scene_file_path)
	EditorInterface.play_main_scene()
	get_tree().create_timer(2.0).timeout.connect(func():
		ProjectSettings.set_setting("editor/run/main_run_args", _args_back))



# ---- sculpt + paint -------------------------------------------------------------------------------------------
func _set_sculpt(on: bool) -> void:
	_sculpting = on and _lvl != null
	if _sculpting:
		_set_placing("")
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(_lvl)
		if _ring == null or not is_instance_valid(_ring):
			_ring = MeshInstance3D.new()
			_lvl.add_child(_ring, false, Node.INTERNAL_MODE_BACK)
	elif _ring and is_instance_valid(_ring):
		_ring.queue_free(); _ring = null
	if _sculpt_btn: _sculpt_btn.set_pressed_no_signal(_sculpting)


func _sculpt_input(cam: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_sculpt(false); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		var h = _hit(cam, event.position)
		if h != null:
			_draw_ring(h)
			if _stroke and h.distance_to(_last_dab) > brush_r * 0.25: _dab(h)
		return AFTER_GUI_INPUT_STOP if _stroke else AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var h = _hit(cam, event.position)
			if h == null: return AFTER_GUI_INPUT_PASS
			var L := _lvl.ensure_layers()
			_stroke = true
			_stroke_old = {"sculpt": L.sculpt.duplicate(), "paint": L.paint.duplicate()}
			_flat_y = h.y
			_dab(h)
			return AFTER_GUI_INPUT_STOP
		elif _stroke:
			_stroke = false
			_last_dab = Vector3(INF, 0, 0)
			var L := _lvl.layers
			var ur := get_undo_redo()
			ur.create_action("Sculpt / paint")
			ur.add_do_property(L, "sculpt", L.sculpt.duplicate())
			ur.add_do_property(L, "paint", L.paint.duplicate())
			ur.add_undo_property(L, "sculpt", _stroke_old.sculpt)
			ur.add_undo_property(L, "paint", _stroke_old.paint)
			ur.commit_action(false)
			_lvl.rebuild_preview()
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## one dab of the brush at h (level space)
func _dab(h: Vector3) -> void:
	_last_dab = h
	var L := _lvl.layers
	var f := _lvl.field
	var tool: String = TOOLS[_tool_opt.selected]
	var r := brush_r
	var i0 := maxi(0, int(floor(h.x - r - L.grid_x0))); var i1 := mini(L.grid_nx - 1, int(ceil(h.x + r - L.grid_x0)))
	var j0 := maxi(0, int(floor(h.z - r - L.grid_z0))); var j1 := mini(L.grid_nz - 1, int(ceil(h.z + r - L.grid_z0)))
	var sc := L.sculpt
	var pt := L.paint
	var old := sc.duplicate() if tool == "Smooth" else PackedFloat32Array()
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var x := L.grid_x0 + i; var z := L.grid_z0 + j
			var d := Vector2(x - h.x, z - h.z).length() / r
			if d >= 1.0: continue
			var w := (1.0 - d * d) * (1.0 - d * d) * brush_k
			var k := j * L.grid_nx + i
			match tool:
				"Raise": sc[k] += w * 0.35
				"Lower": sc[k] -= w * 0.35
				"Flatten":
					var landh := f.land(x, z) if f else 0.0
					sc[k] = lerpf(sc[k], _flat_y - landh, clampf(w, 0.0, 1.0))
				"Smooth":
					if i > 0 and j > 0 and i < L.grid_nx - 1 and j < L.grid_nz - 1 and f:
						var tot := 0.0
						for q: int in [k - 1, k + 1, k - L.grid_nx, k + L.grid_nx]:
							var qx := L.grid_x0 + (q % L.grid_nx); var qz := L.grid_z0 + int(q / L.grid_nx)
							tot += f.land(qx, qz) + old[q]
						var target := tot * 0.25 - f.land(x, z)
						sc[k] = lerpf(old[k], target, clampf(w, 0.0, 1.0))
				"Erase sculpt": sc[k] = lerpf(sc[k], 0.0, clampf(w, 0.0, 1.0))
				"Paint dirt": if w > 0.15: pt[k] = 1
				"Paint sand": if w > 0.15: pt[k] = 2
				"Paint rock": if w > 0.15: pt[k] = 3
				"Erase paint": if w > 0.15: pt[k] = 0
	L.sculpt = sc
	L.paint = pt
	L.emit_changed()


func _draw_ring(h: Vector3) -> void:
	if _ring == null or not is_instance_valid(_ring) or _lvl.field == null: return
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.2)
	m.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, m)
	for a in 49:
		var t := a * TAU / 48.0
		var x := h.x + cos(t) * brush_r; var z := h.z + sin(t) * brush_r
		im.surface_add_vertex(Vector3(x, _lvl.field.height(x, z) + 0.2, z))
	im.surface_end()
	_ring.mesh = im


## the editor saves the scene: the layers resource (written straight into by the brushes) with it
func _save_external_data() -> void:
	if _lvl and is_instance_valid(_lvl) and _lvl.layers and _lvl.layers.resource_path != "":
		ResourceSaver.save(_lvl.layers, _lvl.layers.resource_path)


# ---- import a stretch of the procedural world -------------------------------------------------------------------
func _import_world() -> void:
	if _lvl == null or _lvl.scene_file_path == "":
		info.text = "Open (and save) a level scene first."; return
	var sd := int((_imp_seed.get_child(1) as SpinBox).value)
	var s0 := (_imp_start.get_child(1) as SpinBox).value
	var ln := (_imp_len.get_child(1) as SpinBox).value
	var tmp := ProjectSettings.globalize_path("user://level_import.var")
	info.text = "Importing seed %d, %.0f m from %.0f m..." % [sd, ln, s0]
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s",
		"res://tools/import_world.gd", "--", str(sd), str(s0), str(ln), tmp], out, true)
	if code != 0 or not FileAccess.file_exists(tmp):
		info.text = "Import failed (%d):\n%s" % [code, "\n".join(out).right(600)]; return
	var fa := FileAccess.open(tmp, FileAccess.READ)
	var d = fa.get_var()
	fa.close()
	if not (d is Dictionary):
		info.text = "Import failed: no data"; return
	var t := _lvl.trail()
	var L := _lvl.ensure_layers()
	var ur := get_undo_redo()
	ur.create_action("Import world trail")
	for prop in ["length", "width", "flat_ground"]: ur.add_undo_property(_lvl, prop, _lvl.get(prop))
	for prop in ["import_h", "import_x0", "import_z0", "import_nx", "import_nz"]: ur.add_undo_property(L, prop, L.get(prop))
	if t:
		ur.add_undo_property(t, "curve", t.curve.duplicate() if t.curve else null)
		ur.add_undo_property(t, "transform", t.transform)
	_lvl.apply_import(d)
	for prop in ["length", "width", "flat_ground"]: ur.add_do_property(_lvl, prop, _lvl.get(prop))
	for prop in ["import_h", "import_x0", "import_z0", "import_nx", "import_nz"]: ur.add_do_property(L, prop, L.get(prop))
	if t:
		ur.add_do_property(t, "curve", t.curve.duplicate())
		ur.add_do_property(t, "transform", t.transform)
	ur.commit_action(false)
	_lvl.rebuild_preview()
	info.text = "Imported seed %d (%.0f m of trail from %.0f m): %d spline points. Edit the trail's points / handles; the trail regenerates." % [sd, ln, s0, (d.pts as PackedVector2Array).size()]

@tool
extends Control
## (a plain Control that places its two halves itself: as a container, inside the editor its height grew without end)
## Land Lab tab (editor): every knob of LandParams (scripts/world/land_params.gd) as a slider; a change rebuilds the
## world's real generator (trail, berms, lakes, biome colours) over the chosen area and shows it as a shaded map or a
## 3D model. The world generator isn't a @tool script, so a background headless Godot builds it
## (tools/land_lab_render.gd --serve): ~0.7 s a rebuild once it's running.
##   SAVE       writes res://data/land_params.json (only what differs from the defaults): the game uses it from the next ride
##   RIDE HERE  starts the game on this seed at the area's centre with the current values (nothing saved)
##   SNAPSHOT   picture + values + numbers into user://landlab/ (to show Claude)
##   A / B      hold: the default land for the same seed and area
## Map: left drag pans, wheel zooms (area size). 3D: left drag turns, wheel zooms.

var N := 512                   # samples across (Detail): 1200 m / 512 = 2.3 m a point; the game's ground is 0.5 m
const DETAILS := [256, 512, 1024]
const SIZES := [300.0, 600.0, 1200.0, 2400.0, 4800.0]
const WATER := -2.2            # TerrainField.WATER
const PANEL_W := 380

var seed_v := 4242
var cx := 2600.0
var cz := -300.0
var size_i := 2
var view_3d := false
var vex := 2.0                 # 3D view only: heights x this (the land is a few dozen m over a km: flat at 1x)

var _sliders := {}
var _vals := {}
var _status: Label
var _stats: Label
var _map: TextureRect
var _vpc: SubViewportContainer
var _vp: SubViewport
var _mesh: MeshInstance3D
var _water: MeshInstance3D
var _cam: Camera3D
var _orbit := Vector2(0.7, 0.55)
var _zoom := 1.0
var _x_box: SpinBox
var _z_box: SpinBox
var _size_opt: OptionButton
var _view_btn: Button
var _ab_btn: Button
var _view_box: Control

var _dir := ""                 # the worker's folder (absolute)
var _pid := -1
var _id := 0
var _wait_id := -1
var _wait_def := false
var _dirty := true
var _dirty_t := 0.3
var _alive_t := 0.0
var _sent_t := 0
var _cur := {}
var _def := {}
var _def_key := ""
var _showing_def := false
var _drag := false
var _built := false
var _overlay: Label
var _sc: ScrollContainer


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _sc:
		_place()


var _placed := Vector2.ZERO

## the halves fill what is visible of the tab: in the editor the main screen handed it an 8348 px tall area
## (most of it below the window), so the height is cut to the window's bottom edge
func _place() -> void:
	var vis := get_viewport_rect().size - global_position
	var h := clampf(minf(size.y, vis.y), 10.0, maxf(size.y, 10.0))
	var w := clampf(minf(size.x, vis.x), 10.0, maxf(size.x, 10.0))
	_placed = Vector2(w, h)
	_sc.position = Vector2.ZERO
	_sc.size = Vector2(PANEL_W, h)
	_view_box.position = Vector2(PANEL_W + 6, 0)
	_view_box.size = Vector2(maxf(w - PANEL_W - 6, 10.0), h)
	_map.position = Vector2.ZERO
	_map.size = _view_box.size
	_vpc.position = Vector2.ZERO
	_vpc.size = _view_box.size


## a line in user://landlab_worker/panel.log + the status line over the view (the editor's Output is easy to miss)
func _log(s: String) -> void:
	if _overlay: _overlay.text = s
	if _dir == "": return
	var p := _dir.path_join("panel.log")
	var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s %s" % [Time.get_time_string_from_system(), s])
		f.close()


func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == null:
		return
	LandParams.load_values()
	_dir = ProjectSettings.globalize_path("user://landlab_worker/%d" % OS.get_process_id())   # one per editor (tests too)
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_ui()
	_place()
	_show_view()


# ---------------- UI ----------------
func _build_ui() -> void:
	clip_contents = true
	var sc := ScrollContainer.new()
	_sc = sc
	sc.custom_minimum_size = Vector2(PANEL_W, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var p := VBoxContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(p)
	var title := Label.new()
	title.text = "LAND LAB"
	title.add_theme_font_size_override("font_size", 22)
	p.add_child(title)
	var g := GridContainer.new()
	g.columns = 4
	p.add_child(g)
	_spin(g, "Seed", 0, 99999, 1, seed_v, func(v): seed_v = int(v); _def_key = ""; _mark())
	g.add_child(_lbl("Area"))
	_size_opt = OptionButton.new()
	for s in SIZES: _size_opt.add_item("%d m" % s)
	_size_opt.selected = size_i
	_size_opt.item_selected.connect(func(i): size_i = i; _mark())
	g.add_child(_size_opt)
	_x_box = _spin(g, "X", -20000, 20000, 10, cx, func(v): cx = v; _mark())
	_z_box = _spin(g, "Z", -20000, 20000, 10, cz, func(v): cz = v; _mark())
	var r := HBoxContainer.new()
	p.add_child(r)
	_view_btn = _btn(r, "3D VIEW", func(): view_3d = not view_3d; _show_view())
	_ab_btn = _btn(r, "A / B (hold)", func(): pass)
	_ab_btn.button_down.connect(func(): _set_ab(true))
	_ab_btn.button_up.connect(func(): _set_ab(false))
	var r2 := HBoxContainer.new()
	p.add_child(r2)
	r2.add_child(_lbl("Detail"))
	var dopt := OptionButton.new()
	for d in DETAILS: dopt.add_item("%d" % d)
	dopt.selected = DETAILS.find(N)
	dopt.tooltip_text = "points across the area (more = finer, slower)"
	dopt.item_selected.connect(func(i): N = DETAILS[i]; _cur = {}; _def = {}; _def_key = ""; _mark())
	r2.add_child(dopt)
	r2.add_child(_lbl("3D height x"))
	var vs := SpinBox.new()
	vs.min_value = 1.0; vs.max_value = 5.0; vs.step = 0.5; vs.value = vex
	vs.value_changed.connect(func(v): vex = v; _remesh())
	r2.add_child(vs)
	_btn(r, "TRAIL START", func(): cx = 300.0; cz = 0.0; _x_box.set_value_no_signal(cx); _z_box.set_value_no_signal(cz); _mark())
	var group := ""
	for e in LandParams.DEFS:
		if e[4] != group:
			group = e[4]
			var gl := Label.new()
			gl.text = group.to_upper()
			gl.modulate = Color(1.0, 0.82, 0.3)
			p.add_child(gl)
		_knob(p, e)
	var a1 := HBoxContainer.new()
	p.add_child(a1)
	_btn(a1, "SAVE", _save)
	_btn(a1, "REVERT", func(): LandParams.load_values(); _sync(); _mark())
	_btn(a1, "DEFAULTS", func(): LandParams.values = LandParams.defaults(); _sync(); _mark())
	var a2 := HBoxContainer.new()
	p.add_child(a2)
	_btn(a2, "RIDE HERE", _ride)
	_btn(a2, "SNAPSHOT", _snapshot)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(_status)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	_stats.modulate = Color(0.75, 0.9, 1.0)
	p.add_child(_stats)
	# the view
	_view_box = Control.new()
	_view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_box.clip_contents = true
	_view_box.gui_input.connect(_view_input)
	add_child(_view_box)
	_map = TextureRect.new()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_box.add_child(_map)
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_box.add_child(_vpc)
	_overlay = Label.new()
	_overlay.position = Vector2(10, 6)
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 4)
	_view_box.add_child(_overlay)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vpc.add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.72)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.62, 0.72, 0.84)
	e.fog_density = 0.00012
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-140), 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 8000.0
	_vp.add_child(sun)
	_mesh = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	_mesh.material_override = m
	_vp.add_child(_mesh)
	_water = MeshInstance3D.new()
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.18, 0.36, 0.52, 0.85)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.1
	_water.material_override = wm
	_vp.add_child(_water)
	_cam = Camera3D.new()
	_cam.far = 20000.0
	_cam.fov = 50.0
	_vp.add_child(_cam)
	_cam.current = true   # in the editor a camera never becomes current by itself


func _knob(p: Control, e: Array) -> void:
	var key: String = e[0]
	var top := HBoxContainer.new()
	top.tooltip_text = "%s (default %s)" % [e[5], str(e[1])]
	p.add_child(top)
	var nl := _lbl(e[5])
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	top.add_child(nl)
	var val := _lbl("")
	top.add_child(val)
	_vals[key] = val
	var rs := Button.new()
	rs.text = "R"
	rs.flat = true
	rs.tooltip_text = "back to the default (%s)" % str(e[1])
	rs.pressed.connect(func(): LandParams.values[key] = float(e[1]); _sync(); _mark())
	top.add_child(rs)
	var s := HSlider.new()
	s.min_value = e[2]
	s.max_value = e[3]
	s.step = (float(e[3]) - float(e[2])) / 400.0
	s.scrollable = false
	s.value = float(LandParams.values[key])
	s.value_changed.connect(func(x): LandParams.values[key] = x; _show_val(key); _mark())
	p.add_child(s)
	_sliders[key] = s
	_show_val(key)


func _show_val(key: String) -> void:
	var x: float = LandParams.values[key]
	var l: Label = _vals[key]
	l.text = ("%.2f" % x) if absf(x) < 10.0 else ("%.0f" % x)
	l.modulate = Color.WHITE if is_equal_approx(x, LandParams.def_of(key)) else Color(1.0, 0.6, 0.3)


func _sync() -> void:
	for k in _sliders:
		(_sliders[k] as HSlider).set_value_no_signal(LandParams.values[k])
		_show_val(k)


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _btn(p: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	p.add_child(b)
	return b


func _spin(p: Control, t: String, lo: float, hi: float, st: float, v: float, cb: Callable) -> SpinBox:
	p.add_child(_lbl(t))
	var s := SpinBox.new()
	s.min_value = lo; s.max_value = hi; s.step = st; s.value = v
	s.value_changed.connect(cb)
	p.add_child(s)
	return s


func _mark() -> void:
	_dirty = true
	_dirty_t = 0.3


func _show_view() -> void:
	_map.visible = not view_3d
	_vpc.visible = view_3d
	_view_btn.text = "MAP VIEW" if view_3d else "3D VIEW"


func _view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
			if not ev.pressed and not view_3d: _mark()
		elif ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var up: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP
			if view_3d:
				_zoom = clampf(_zoom * (0.9 if up else 1.1), 0.15, 3.0)
				_place_cam()
			else:
				size_i = clampi(size_i + (-1 if up else 1), 0, SIZES.size() - 1)
				_size_opt.selected = size_i
				_mark()
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		if view_3d:
			_orbit.x -= ev.relative.x * 0.006
			_orbit.y = clampf(_orbit.y + ev.relative.y * 0.005, 0.08, 1.5)
			_place_cam()
		else:
			var px := minf(_view_box.size.x, _view_box.size.y)
			var mpp: float = SIZES[size_i] / maxf(px, 1.0)
			cx -= ev.relative.x * mpp
			cz -= ev.relative.y * mpp
			_x_box.set_value_no_signal(snappedf(cx, 10)); _z_box.set_value_no_signal(snappedf(cz, 10))
		accept_event()


func _place_cam() -> void:
	var s: float = SIZES[size_i]
	var H: PackedFloat32Array = _cur.get("H", PackedFloat32Array())
	var mid := H[(N / 2) * N + N / 2] * vex if H.size() == N * N else 0.0
	var dir := Vector3(cos(_orbit.y) * sin(_orbit.x), sin(_orbit.y), cos(_orbit.y) * cos(_orbit.x))
	_cam.position = Vector3(0, mid, 0) + dir * s * 1.05 * _zoom
	_cam.look_at(Vector3(0, mid, 0), Vector3.UP)


# ---------------- the worker ----------------
func _process(dt: float) -> void:
	if _dir == "":
		return
	_alive_t -= dt
	if _alive_t <= 0.0 and _pid >= 0:   # the worker keeps running while the editor is open (quits 15 s after it closes)
		_alive_t = 2.0
		var f := FileAccess.open(_dir.path_join("alive"), FileAccess.WRITE)
		if f: f.store_string(str(Time.get_unix_time_from_system())); f.close()
	if not is_visible_in_tree():
		return
	if _sc and (_placed != Vector2(minf(size.x, get_viewport_rect().size.x - global_position.x), minf(size.y, get_viewport_rect().size.y - global_position.y))):
		_place()
	if _pid < 0 or not OS.is_process_running(_pid):
		_start_worker()
	if _wait_id >= 0:
		_poll()
	elif _dirty:
		_dirty_t -= dt
		if _dirty_t <= 0.0:
			_dirty = false
			_send(false)
	elif _showing_def and _def_key != _area_key():
		_send(true)


func _start_worker() -> void:
	DirAccess.remove_absolute(_dir.path_join("stop"))
	var af := FileAccess.open(_dir.path_join("alive"), FileAccess.WRITE)
	if af: af.store_string("start"); af.close()
	DirAccess.remove_absolute(_dir.path_join("job.json"))
	DirAccess.remove_absolute(_dir.path_join("done.txt"))
	_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tools/land_lab_render.gd", "--", "--serve", _dir])
	_wait_id = -1
	_dirty = true
	_dirty_t = 0.0
	if _status: _status.text = "starting the world builder (pid %d)..." % _pid
	_log("starting the world builder (pid %d)" % _pid)


func stop_worker() -> void:
	if _dir == "": return
	var f := FileAccess.open(_dir.path_join("stop"), FileAccess.WRITE)
	if f: f.store_string("1"); f.close()
	_pid = -1


func _send(defaults: bool) -> void:
	_id += 1
	_wait_id = _id
	_wait_def = defaults
	_sent_t = Time.get_ticks_msec()
	var job := {"id": _id, "seed": seed_v, "cx": cx, "cz": cz, "size": SIZES[size_i], "n": N,
		"values": LandParams.defaults() if defaults else LandParams.values, "out": _dir.path_join("out_%d" % (_id % 3))}
	var tmp := _dir.path_join("job.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(job))
	f.close()
	DirAccess.rename_absolute(tmp, _dir.path_join("job.json"))
	_status.text = "building%s..." % (" the default land" if defaults else "")
	_log("job %d sent (%s)" % [_id, "defaults" if defaults else "current values"])


func _poll() -> void:
	var dp := _dir.path_join("done.txt")
	if not FileAccess.file_exists(dp): return
	var d := FileAccess.get_file_as_string(dp).strip_edges().split(" ")
	if d.size() < 2 or int(d[0].to_float()) != _wait_id: return
	_log("job %d done (code %s), loading" % [_wait_id, d[1]])
	var out := _dir.path_join("out_%d" % (_wait_id % 3))
	var ok := int(d[1].to_float()) == 0
	var is_def := _wait_def
	_wait_id = -1
	if not ok:
		_status.text = "build failed (see the Output panel; C# built?)"
		return
	var b := _load(out)
	if b.is_empty():
		_log("job result could not be read: " + out)
		return
	b["def"] = is_def
	if is_def:
		_def = b
		_def_key = _area_key()
	else:
		_cur = b
		_status.text = "built in %d ms  ·  seed %d  ·  %d m  ·  centre %d, %d" % [Time.get_ticks_msec() - _sent_t, seed_v, int(SIZES[size_i]), int(cx), int(cz)]
	_present()


func _remesh() -> void:
	for b in [_cur, _def]:
		if not b.is_empty():
			b["mesh"] = _make_mesh(b)
	_present()


func _area_key() -> String:
	return "%d|%d|%.0f|%.0f" % [seed_v, size_i, cx, cz]


func _set_ab(on: bool) -> void:
	_showing_def = on
	_present()


func _load(out: String) -> Dictionary:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("meta.json")))
	if not meta is Dictionary: return {}
	var H := FileAccess.get_file_as_bytes(out.path_join("h.bin")).to_float32_array()
	var img := Image.load_from_file(out.path_join("c.png"))
	if int(meta.get("n", N)) != N:
		return {}
	if H.size() != N * N or img == null:
		_log("bad result: %d heights, image %s" % [H.size(), str(img)])
		return {}
	var C := PackedColorArray(); C.resize(N * N)
	for j in N:
		for i in N:
			C[j * N + i] = img.get_pixel(i, j)
	var tr := PackedVector2Array()
	var t: Array = meta.trail
	for k in range(0, t.size() - 1, 2):
		tr.append(Vector2(t[k], t[k + 1]))
	var b := {"H": H, "C": C, "step": float(meta.step), "trail": tr}
	b["img"] = _render_map(b)
	b["mesh"] = _make_mesh(b)
	b["stats"] = _measure(b)
	return b


func _present() -> void:
	var b: Dictionary = _def if (_showing_def and _def_key == _area_key()) else _cur
	if b.is_empty(): return
	_map.texture = ImageTexture.create_from_image(b.img)
	_mesh.mesh = b.mesh
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZES[size_i], SIZES[size_i])
	_water.mesh = pm
	_water.position = Vector3(0, WATER * vex, 0)
	_place_cam()
	var is_def: bool = b.get("def", false)
	_log("showing %s · view %s · box %s" % ["the DEFAULT land" if is_def else "your land", "3d" if view_3d else "map", str(_view_box.size)])
	_stats.text = ("DEFAULT LAND\n" if is_def else "") + b.stats
	_ab_btn.modulate = Color(1, 0.8, 0.3) if is_def else Color.WHITE


# ---------------- drawing ----------------
func _render_map(b: Dictionary) -> Image:
	var H: PackedFloat32Array = b.H
	var C: PackedColorArray = b.C
	var st: float = b.step
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var L := Vector3(-0.55, 0.7, -0.45).normalized()
	var cstep := 5.0 if SIZES[size_i] <= 1200.0 else 10.0
	for j in N:
		for i in N:
			var k := j * N + i
			var h := H[k]
			var hr := H[j * N + mini(i + 1, N - 1)]
			var hd := H[mini(j + 1, N - 1) * N + i]
			var hx := (hr - H[j * N + maxi(i - 1, 0)]) / (2.0 * st)
			var hz := (hd - H[maxi(j - 1, 0) * N + i]) / (2.0 * st)
			var n := Vector3(-hx, 1.0, -hz).normalized()
			var col := C[k] * (0.45 + 0.75 * clampf(n.dot(L), 0.0, 1.0))
			if h < WATER:
				col = col.lerp(Color(0.2, 0.38, 0.55), 0.55)
			if floorf(h / cstep) != floorf(hr / cstep) or floorf(h / cstep) != floorf(hd / cstep):
				col = col.darkened(0.22 if int(floorf(maxf(h, maxf(hr, hd)) / cstep)) % 5 == 0 else 0.08)
			col.a = 1.0
			img.set_pixel(i, j, col)
	for q in (b.trail as PackedVector2Array):
		var x := int(q.x); var y := int(q.y)
		if x >= 0 and y >= 0 and x < N and y < N:
			img.set_pixel(x, y, Color(0.85, 0.12, 0.1))
	img.resize(N * 3, N * 3, Image.INTERPOLATE_BILINEAR)
	return img


func _make_mesh(b: Dictionary) -> ArrayMesh:
	var H: PackedFloat32Array = b.H
	var st: float = b.step
	var half := (N - 1) * st * 0.5
	var v := PackedVector3Array(); v.resize(N * N)
	var nrm := PackedVector3Array(); nrm.resize(N * N)
	for j in N:
		for i in N:
			var k := j * N + i
			v[k] = Vector3(i * st - half, H[k] * vex, j * st - half)
			var hx := vex * (H[j * N + mini(i + 1, N - 1)] - H[j * N + maxi(i - 1, 0)]) / (2.0 * st)
			var hz := vex * (H[mini(j + 1, N - 1) * N + i] - H[maxi(j - 1, 0) * N + i]) / (2.0 * st)
			nrm[k] = Vector3(-hx, 1.0, -hz).normalized()
	var col: PackedColorArray = (b.C as PackedColorArray).duplicate()
	for q in (b.trail as PackedVector2Array):
		var x := int(round(q.x)); var y := int(round(q.y))
		if x >= 0 and y >= 0 and x < N and y < N:
			col[y * N + x] = Color(0.8, 0.15, 0.1)
	var idx := PackedInt32Array(); idx.resize((N - 1) * (N - 1) * 6)
	var w := 0
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			idx[w] = a; idx[w + 1] = a + 1; idx[w + 2] = a + N
			idx[w + 3] = a + 1; idx[w + 4] = a + N + 1; idx[w + 5] = a + N
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _measure(b: Dictionary) -> String:
	var H: PackedFloat32Array = b.H
	var st: float = b.step
	var lo := INF; var hi := -INF
	var flat := 0; var s15 := 0; var s25 := 0; var s35 := 0; var wet := 0; var tot := 0
	var sum := 0.0
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var k := j * N + i
			var h := H[k]
			lo = minf(lo, h); hi = maxf(hi, h)
			var hx := (H[k + 1] - H[k - 1]) / (2.0 * st)
			var hz := (H[k + N] - H[k - N]) / (2.0 * st)
			var deg := rad_to_deg(atan(sqrt(hx * hx + hz * hz)))
			sum += deg; tot += 1
			if deg < 5.0: flat += 1
			if deg > 15.0: s15 += 1
			if deg > 25.0: s25 += 1
			if deg > 35.0: s35 += 1
			if h < WATER: wet += 1
	var pc := func(n: int) -> String: return "%.1f %%" % (100.0 * n / maxi(tot, 1))
	return "height %.0f .. %.0f m (%.0f m range)\nslope mean %.1f deg · flat <5: %s · >15: %s\n>25: %s · >35: %s · under water %s" % [
		lo, hi, hi - lo, sum / maxi(tot, 1), pc.call(flat), pc.call(s15), pc.call(s25), pc.call(s35), pc.call(wet)]


# ---------------- actions ----------------
func _save() -> void:
	var path := LandParams.save()
	_status.text = ("saved %s (%d changed): the game uses it from the next ride" % [path, LandParams.changed().size()]) if path != "" else "could not save"
	print("LANDLAB saved ", path, " ", JSON.stringify(LandParams.changed()))
	EditorInterface.get_resource_filesystem().scan()


func _ride() -> void:
	var kv := PackedStringArray()
	for k in LandParams.values:
		kv.append("%s=%s" % [k, str(LandParams.values[k])])
	OS.set_environment("BMX_LAND", ",".join(kv))
	OS.set_environment("BMX_SEED", str(seed_v))
	OS.set_environment("BMX_TRAIL_FEAT", "x%d" % int(maxf(cx, 0.0)))
	var pid := OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--", "--ride"])
	OS.set_environment("BMX_LAND", ""); OS.set_environment("BMX_SEED", ""); OS.set_environment("BMX_TRAIL_FEAT", "")
	_status.text = "riding seed %d from x %d (pid %d) with these values, nothing saved" % [seed_v, int(cx), pid]


func _snapshot() -> void:
	if _cur.is_empty(): return
	var dir := ProjectSettings.globalize_path("user://landlab")
	DirAccess.make_dir_recursive_absolute(dir)
	var base := dir.path_join("snap_" + Time.get_datetime_string_from_system().replace(":", "-"))
	var img: Image = _vp.get_texture().get_image() if view_3d else (_cur.img as Image)
	img.save_png(base + ".png")
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	f.store_string("seed %d  centre %d, %d  area %d m  view %s\nchanged: %s\n%s\n" % [seed_v, int(cx), int(cz), int(SIZES[size_i]),
		"3d" if view_3d else "map", JSON.stringify(LandParams.changed()), _cur.stats])
	f.close()
	_status.text = "snapshot: " + base + ".png"
	print("LANDLAB snapshot ", base, ".png")


func _exit_tree() -> void:
	stop_worker()

class_name FrameProfiler extends CanvasLayer
## F10 in a ride: a live frame profiler (game/frame_profiler.gd, made by Game on first use).
## Every drawn frame: the wall time, the game's own timed sections (Game._perf: the same ones BMX_PERF prints,
## physics ticks "p_*" included), what is left over (engine: render submit, other nodes, physics server, waiting),
## the GPU and render-CPU time of the main viewport, draw calls, primitives and the render pipelines compiled
## while drawing (a hitch). F10 cycles compact -> full -> off; Shift+F10 freezes the graph; Ctrl+F10 saves the
## whole ring (10 s) as CSV. Mouse over the graph = that frame's numbers. A spike (over SPIKE_MS or 2.2x the
## median) is marked red and, open, saved with the 0.5 s before / after it to %APPDATA%\Mini BMX\profiles\.

const N := 600            # frames kept (~10 s at 60 fps)
const MAXK := 64          # timed sections at most
const SPIKE_MS := 25.0
const SPIKE_AFTER := 30   # frames after a spike before it is written (so the file shows the recovery)
const SPIKE_BEFORE := 60
const SPIKE_GAP_MS := 5000
const SPIKE_FILES := 20   # per session
const W_FULL := 560.0
const GRAPH_H := 120.0
const ROWS := 16

var game
var mode := 0              # 0 off, 1 compact, 2 full
var frozen := false

var keys: Array[String] = []
var _kidx := {}
var _sec := PackedFloat32Array()   # N * MAXK, ms
var _wall := PackedFloat32Array()
var _gpu := PackedFloat32Array()
var _rcpu := PackedFloat32Array()
var _draws := PackedFloat32Array()
var _prims := PackedFloat32Array()
var _comp := PackedFloat32Array()
var _ticks := PackedFloat32Array()
var _frame_no := PackedInt64Array()
var head := 0      # next row to write
var count := 0
var _frame := 0
var _last_us := 0
var _comp_last := -1
var _median := 16.7
var _spike_rows: Array[int] = []    # frame numbers marked as spikes (shown red)
var _pending := -1                  # frame number of a spike waiting to be written
var _pending_ms := 0.0
var _last_file_ms := -100000
var _files := 0
var hover := -1                     # ring row under the mouse, -1 none
var acc := {}                       # Game._perf adds microseconds per section here
var ticks := 0                      # physics ticks since the last drawn frame

var _worst := {}   # each section's worst single frame this session (printed at exit in test runs: PROF WORST)

var _marks: Array = []
func _on_pre() -> void: _t_pre = Time.get_ticks_usec()
func _on_post() -> void: _t_post = Time.get_ticks_usec()

func _exit_tree() -> void:
	for m in _marks:
		if is_instance_valid(m): m.queue_free()
	if RenderingServer.frame_pre_draw.is_connected(_on_pre): RenderingServer.frame_pre_draw.disconnect(_on_pre)
	if RenderingServer.frame_post_draw.is_connected(_on_post): RenderingServer.frame_post_draw.disconnect(_on_post)
	if Env.s("BMX_PROF") == "" or _worst.is_empty(): return
	var ks := _worst.keys()
	ks.sort_custom(func(a, b): return _worst[a] > _worst[b])
	var line := "PROF WORST (ms, one frame):"
	for k in ks.slice(0, 20): line += " %s=%.2f" % [k, _worst[k]]
	print(line)

var _view: Control
var _font: Font
var _vp_rid: RID

const COLS := [Color(0.35, 0.62, 1.0), Color(1.0, 0.55, 0.2), Color(0.45, 0.85, 0.45), Color(0.95, 0.35, 0.55),
	Color(0.75, 0.55, 1.0), Color(1.0, 0.85, 0.3), Color(0.3, 0.85, 0.85), Color(0.85, 0.6, 0.45)]
const C_OTHER_GAME := Color(0.55, 0.55, 0.6)
const C_ENGINE := Color(0.32, 0.32, 0.38)
const C_RENDER := Color(0.62, 0.62, 0.7)        # render CPU (engine work)
const C_WAIT := Color(0.55, 0.55, 0.65, 0.16)   # the rest of the frame: other nodes' scripts, physics server, waiting on the GPU / vsync
const C_GPU := Color(1.0, 0.95, 0.95)

func _init(g) -> void:
	game = g
	name = "FrameProfiler"
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100000   # first node of the frame: closes the frame before
	_sec.resize(N * MAXK)
	for a in [_wall, _gpu, _rcpu, _draws, _prims, _comp, _ticks]: a.resize(N)
	_frame_no.resize(N)

## engine phase markers (2026-11-24: "other" was ~10-16 ms a frame with vsync off). Godot's loop per frame: physics ticks,
## then every _process, then the render (frame_pre_draw .. frame_post_draw). These time each phase as a whole, so the
## part outside our own sections is split into: other nodes' _process, all physics ticks, the render, and what's left
## (input, the physics server, swap / present, waiting on the GPU)
class _Mark extends Node:   # a _process-only marker (a script with _physics_process too gets both turned on as it enters the tree)
	var cb: Callable
	func _process(_d: float) -> void: cb.call()
class _PMark extends Node:  # a _physics_process-only marker
	var cb: Callable
	func _physics_process(_d: float) -> void: cb.call()

var _t_proc_end := 0
var _t_pre := 0
var _t_post := 0
var _phys_us := 0
var _phys_t0 := 0

func _ready() -> void:
	var tail := _Mark.new(); tail.process_priority = 100000
	tail.cb = func(): _t_proc_end = Time.get_ticks_usec()
	tail.process_mode = Node.PROCESS_MODE_ALWAYS
	var ph0 := _PMark.new(); ph0.process_physics_priority = -100000; ph0.process_mode = Node.PROCESS_MODE_ALWAYS
	ph0.cb = func(): _phys_t0 = Time.get_ticks_usec()
	var ph1 := _PMark.new(); ph1.process_physics_priority = 100000; ph1.process_mode = Node.PROCESS_MODE_ALWAYS
	ph1.cb = func(): if _phys_t0 > 0: _phys_us += Time.get_ticks_usec() - _phys_t0
	# (they must run first / last in the whole tree: the root's children are walked in order, so the priorities do it)
	get_tree().root.add_child.call_deferred(tail)
	get_tree().root.add_child.call_deferred(ph0)
	get_tree().root.add_child.call_deferred(ph1)
	_marks = [tail, ph0, ph1]
	RenderingServer.frame_pre_draw.connect(_on_pre)
	RenderingServer.frame_post_draw.connect(_on_post)
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_view)
	add_child(_view)
	_setup_graph()
	_vp_rid = get_viewport().get_viewport_rid()
	set_mode(mode)

## is it recording? (Game._perf only fills `acc` while this is true)
func recording() -> bool:
	return mode > 0

func cycle() -> void:
	set_mode((mode + 1) % 3)

func set_mode(m: int) -> void:
	mode = m
	visible = m > 0
	if not is_inside_tree(): return
	RenderingServer.viewport_set_measure_render_time(_vp_rid, m > 0)
	_last_us = 0
	acc.clear(); ticks = 0

func _process(_dt: float) -> void:
	if mode == 0: return
	var now := Time.get_ticks_usec()
	if _last_us > 0 and not frozen:
		# the frame being closed: [last .. now] = its _process pass, its render, then this frame's physics ticks
		if _t_proc_end > _last_us: acc["eng.process_all"] = _t_proc_end - _last_us
		if _t_post > _t_pre and _t_pre > _last_us: acc["eng.render"] = _t_post - _t_pre
		acc["eng.physics_all"] = _phys_us
		var known: int = int(acc.get("eng.process_all", 0)) + int(acc.get("eng.render", 0)) + _phys_us
		acc["eng.gaps"] = maxi(now - _last_us - known, 0)
		_close_frame((now - _last_us) / 1000.0)
	if _NODES and acc.has("eng.process_all"): _nodes_step(float(acc["eng.process_all"]) / 1000.0)
	_phys_us = 0
	acc.clear(); ticks = 0
	var real_dt := (now - _last_us) / 1e6 if _last_us > 0 else 0.016
	_last_us = now
	_hover_update()
	_redraw(real_dt)

var _sub: Array[bool] = []   # "a.b" keys are parts of another section (p_step.* inside p_bike_step): not summed / stacked
func _key(k: String) -> int:
	if _kidx.has(k): return _kidx[k]
	if keys.size() >= MAXK: return -1
	_kidx[k] = keys.size()
	keys.append(k)
	_sub.append(k.contains("."))
	return keys.size() - 1

func _close_frame(wall_ms: float) -> void:
	var r := head
	var base := r * MAXK
	for i in MAXK: _sec[base + i] = 0.0
	for k in acc:
		var i := _key(k)
		if i >= 0:
			_sec[base + i] = acc[k] / 1000.0
			if _frame > 60 and acc[k] / 1000.0 > _worst.get(k, 0.0): _worst[k] = acc[k] / 1000.0
	_wall[r] = wall_ms
	_gpu[r] = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	_rcpu[r] = RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	_draws[r] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_prims[r] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var c := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
	_comp[r] = maxi(c - _comp_last, 0) if _comp_last >= 0 else 0
	_comp_last = c
	_ticks[r] = ticks
	_frame_no[r] = _frame
	head = (head + 1) % N
	count = mini(count + 1, N)
	if _frame % 30 == 0: _median = _median_wall()
	# spikes (not the first second: loading)
	if _frame > 60 and wall_ms > maxf(SPIKE_MS, _median * 2.2):
		_spike_rows.append(_frame)
		if _spike_rows.size() > 64: _spike_rows.pop_front()
		if _pending < 0 and Time.get_ticks_msec() - _last_file_ms > SPIKE_GAP_MS and _files < SPIKE_FILES:
			_pending = _frame; _pending_ms = wall_ms
	if _pending >= 0 and _frame - _pending >= SPIKE_AFTER:
		_save_csv("spike_%dms" % int(_pending_ms), SPIKE_BEFORE + SPIKE_AFTER + 1)
		_last_file_ms = Time.get_ticks_msec(); _files += 1
		_pending = -1
	_paint(r)   # (after the spike check: a spike's column is painted red)
	_frame += 1

func _median_wall() -> float:
	var n := mini(count, 120)
	if n == 0: return 16.7
	var a: Array[float] = []
	for j in n: a.append(_wall[_row(j)])
	a.sort()
	return a[n / 2]

## j frames back from the newest (0 = newest)
func _row(j: int) -> int:
	return posmod(head - 1 - j, N)

# ---------------------------------------------------------------- input

func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo: return
	if k.keycode != KEY_F10 or mode == 0: return   # (plain F10 is the "profiler" action, Game.toggle_profiler)
	if k.ctrl_pressed:
		if count > 0:
			var p := _save_csv("ring", count)
			if game and game.has_method("flash"): game.flash("PROFILE SAVED · " + p.get_file().to_upper())
	elif k.shift_pressed:
		frozen = not frozen
	else: return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- saving

func _dir() -> String:
	var d := OS.get_user_data_dir().path_join("profiles")
	if Settings._test_run: d = d.path_join("tests")
	DirAccess.make_dir_recursive_absolute(d)
	return d

## the last n frames as CSV (oldest first); returns the path
func _save_csv(tag: String, n: int) -> String:
	n = mini(n, count)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := _dir().path_join("%s_%s.csv" % [tag, stamp])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	var head_line := "frame,wall_ms,gpu_ms,render_cpu_ms,game_ms,engine_ms,phys_ticks,draws,primitives,pipelines_compiled"
	for k in keys: head_line += "," + k
	f.store_line(head_line)
	for j in range(n - 1, -1, -1):
		var r := _row(j)
		var g := _game_ms(r)
		var line := "%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%d" % [_frame_no[r], _wall[r], _gpu[r], _rcpu[r], g,
			maxf(_wall[r] - g, 0.0), int(_ticks[r]), int(_draws[r]), int(_prims[r]), int(_comp[r])]
		for i in keys.size(): line += ",%.3f" % _sec[r * MAXK + i]
		f.store_line(line)
	f.close()
	print("PROFILE saved %s (%d frames)" % [path, n])
	CrashLog.note("profile saved: " + path)
	return path

func _game_ms(r: int) -> float:
	var s := 0.0
	var base := r * MAXK
	for i in keys.size():
		if not _sub[i]: s += _sec[base + i]
	return s

# ---------------------------------------------------------------- drawing
# (2026-11-24: the first version drew every bar of 600 frames as rects and recomputed the table every frame: with it open
# the ride ran ~53 fps instead of ~100. Now the graph is an image painted ONE column per frame (one texture draw), and
# the table / header are recomputed and redrawn GRAPH_HZ times a second.)

const GRAPH_MS := 40.0   # ms at the top of the graph (fixed: the columns are painted once)
const TABLE_HZ := 4.0
var _img: Image
var _tex: ImageTexture
var _gview: Control
var _colour := {}        # section index -> its colour (the top ones of the last table refresh)
var _table_t := 0.0
var _last_hover := -2

func _origin() -> Vector2:
	return Vector2(16, 150)

func _graph_rect() -> Rect2:
	var o := _origin() + Vector2(10, 30)
	return Rect2(o, Vector2(W_FULL - 20, GRAPH_H))

func _setup_graph() -> void:
	_img = Image.create(N, int(GRAPH_H), false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	_gview = Control.new()
	_gview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gview.draw.connect(_draw_graph)
	add_child(_gview)

## paint ring row r's column (called once per frame from _close_frame)
func _paint(r: int) -> void:
	if _img == null: return
	var gh := int(GRAPH_H)
	var px := func(ms: float) -> int: return clampi(int(roundf(ms / GRAPH_MS * gh)), 0, gh)
	_img.fill_rect(Rect2i(r, 0, 1, gh), Color(0, 0, 0, 0))
	var y := gh
	var game_ms := 0.0
	var other := 0.0
	for i in keys.size():
		var v := _sec[r * MAXK + i]
		if v <= 0.0 or _sub[i]: continue
		game_ms += v
		if _colour.has(i):
			var h: int = px.call(v)
			if h > 0: _img.fill_rect(Rect2i(r, maxi(y - h, 0), 1, mini(h, y)), _colour[i]); y -= h
		else: other += v
	var h2: int = px.call(other)
	if h2 > 0 and y > 0: _img.fill_rect(Rect2i(r, maxi(y - h2, 0), 1, mini(h2, y)), C_OTHER_GAME); y -= h2
	var rc := minf(_rcpu[r], maxf(_wall[r] - game_ms, 0.0))
	var h3: int = px.call(rc)
	if h3 > 0 and y > 0: _img.fill_rect(Rect2i(r, maxi(y - h3, 0), 1, mini(h3, y)), C_RENDER); y -= h3
	var rest := maxf(_wall[r] - game_ms - rc, 0.0)
	var h4: int = px.call(rest)
	var spike := _spike_rows.size() > 0 and _spike_rows[-1] == _frame_no[r]
	if h4 > 0 and y > 0: _img.fill_rect(Rect2i(r, maxi(y - h4, 0), 1, mini(h4, y)), Color(0.9, 0.15, 0.15, 0.85) if spike else C_WAIT)
	if _comp[r] > 0: _img.fill_rect(Rect2i(r, 0, 1, 4), Color(1, 0.2, 1))
	var gy: int = gh - 1 - px.call(minf(_gpu[r], GRAPH_MS))
	_img.set_pixel(r, clampi(gy, 0, gh - 1), C_GPU)

func _hover_update() -> void:
	hover = -1
	var m := _gview.get_local_mouse_position() if _gview else Vector2(-1, -1)
	var gr := _graph_rect()
	if not gr.has_point(m) or count == 0: return
	var j := int((gr.end.x - m.x) / gr.size.x * N)
	if j < count: hover = _row(j)

## per frame: the graph (one texture + a few lines); the table only TABLE_HZ times a second or when the hover moves
func _redraw(dt: float) -> void:
	if _tex and _img: _tex.update(_img)
	if _gview: _gview.queue_redraw()
	_table_t -= dt
	if _table_t <= 0.0 or hover != _last_hover:
		_table_t = 1.0 / TABLE_HZ
		_last_hover = hover
		_view.queue_redraw()

## stats over the last second (or the hovered frame): {key: [avg, max]}
func _window() -> Array:
	var n := mini(count, maxi(int(1000.0 / maxf(_median, 1.0)), 30))
	var rows: Array[int] = []
	if hover >= 0: rows.append(hover)
	else:
		for j in n: rows.append(_row(j))
	return rows

func _stats(rows: Array[int], get_v: Callable) -> Vector2:
	var s := 0.0; var mx := 0.0
	for r in rows:
		var v: float = get_v.call(r)
		s += v; mx = maxf(mx, v)
	return Vector2(s / maxf(rows.size(), 1), mx)

func _top_keys(rows: Array[int]) -> Array:
	var avg := []
	for i in keys.size():
		if _sub[i]: continue
		var s := 0.0
		for r in rows: s += _sec[r * MAXK + i]
		avg.append([i, s / maxf(rows.size(), 1)])
	avg.sort_custom(func(a, b): return a[1] > b[1])
	return avg

func _draw_graph() -> void:
	if count == 0 or _tex == null: return
	var gr := _graph_rect()
	_gview.draw_rect(gr, Color(0, 0, 0, 0.35))
	# the ring: oldest on the left (rows head..N-1, then 0..head-1), newest at the right edge
	var colw := gr.size.x / N
	var n_old := N - head
	_gview.draw_texture_rect_region(_tex, Rect2(gr.position, Vector2(n_old * colw, gr.size.y)), Rect2(head, 0, n_old, GRAPH_H))
	if head > 0:
		_gview.draw_texture_rect_region(_tex, Rect2(gr.position + Vector2(n_old * colw, 0), Vector2(head * colw, gr.size.y)), Rect2(0, 0, head, GRAPH_H))
	for ln in [[8.33, "120"], [16.67, "60"], [33.33, "30"]]:
		var y: float = gr.end.y - ln[0] / GRAPH_MS * gr.size.y
		_gview.draw_line(Vector2(gr.position.x, y), Vector2(gr.end.x, y), Color(1, 1, 1, 0.18), 1.0)
		_gview.draw_string(_font, Vector2(gr.end.x - 26, y - 2), ln[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	_gview.draw_string(_font, gr.position + Vector2(4, 12), "%d ms" % int(GRAPH_MS), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
	if hover >= 0:
		var jh := posmod(head - 1 - hover, N)
		var hx := gr.end.x - (jh + 0.5) * colw
		_gview.draw_line(Vector2(hx, gr.position.y), Vector2(hx, gr.end.y), Color(1, 1, 0), 1.0)

func _draw_view() -> void:
	if count == 0: return
	var rows := _window()
	var top := _top_keys(rows)
	_colour.clear()
	for c in mini(COLS.size(), top.size()): _colour[top[c][0]] = COLS[c]
	var o := _origin()
	var h := 30.0 + GRAPH_H + 45.0 + ((ROWS + 7) * 17.0 + 70.0 if mode == 2 else 0.0)
	_view.draw_rect(Rect2(o, Vector2(W_FULL, h)), Color(0.06, 0.065, 0.08, 0.86))
	# title line
	var wall := _stats(rows, func(r): return _wall[r])
	var gpu := _stats(rows, func(r): return _gpu[r])
	var t := "FRAME PROFILER  %s%.1f fps  ·  %.2f ms avg  ·  1%% high %.1f ms  ·  GPU %.2f ms" % [
		"FRAME " if hover >= 0 else "", 1000.0 / maxf(wall.x, 0.01), wall.x, _p99(), gpu.x]
	if frozen: t += "  ·  FROZEN"
	_text(o + Vector2(10, 20), t, 14, Color(1, 1, 1))
	# legend
	var lx := o.x + 10
	var ly := _graph_rect().end.y + 18
	for fx in [["GPU", C_GPU, true], ["render CPU", C_RENDER, false], ["other nodes / GPU wait", Color(C_WAIT, 0.5), false]]:
		if fx[2]: _view.draw_line(Vector2(lx, ly - 4), Vector2(lx + 9, ly - 4), fx[1], 2.0)
		else: _view.draw_rect(Rect2(lx, ly - 9, 9, 9), fx[1])
		_text(Vector2(lx + 12, ly), fx[0], 11, Color(0.85, 0.85, 0.9))
		lx += 20 + _font.get_string_size(fx[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8
	ly += 15; lx = o.x + 10
	for c in mini(COLS.size(), top.size()):
		var nm: String = keys[top[c][0]]
		_view.draw_rect(Rect2(lx, ly - 9, 9, 9), COLS[c])
		_text(Vector2(lx + 12, ly), nm, 11, Color(0.85, 0.85, 0.9))
		lx += 16 + _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8
		if lx > o.x + W_FULL - 70: break
	if mode == 2: _draw_table(rows, top, _colour, ly + 14)

func _p99() -> float:
	var n := mini(count, 600)
	var a: Array[float] = []
	for j in n: a.append(_wall[_row(j)])
	a.sort()
	return a[int(n * 0.99)] if n > 0 else 0.0

func _draw_table(rows: Array[int], top: Array, colour: Dictionary, y0: float) -> void:
	var o := _origin()
	var x0 := o.x + 10
	var y := y0
	_text(Vector2(x0, y), "SECTION" + ("  (frame)" if hover >= 0 else "  (last second)"), 11, Color(0.6, 0.65, 0.75))
	_text(Vector2(x0 + 230, y), "AVG ms", 11, Color(0.6, 0.65, 0.75))
	_text(Vector2(x0 + 290, y), "MAX ms", 11, Color(0.6, 0.65, 0.75))
	y += 17
	var wall := _stats(rows, func(r): return _wall[r])
	var gpu := _stats(rows, func(r): return _gpu[r])
	var rcpu := _stats(rows, func(r): return _rcpu[r])
	var gm := _stats(rows, func(r): return _game_ms(r))
	var eng := _stats(rows, func(r): return maxf(_wall[r] - _game_ms(r) - _rcpu[r], 0.0))
	var lines := [["frame (wall)", wall, Color.WHITE], ["GPU (main view)", gpu, C_GPU], ["render CPU", rcpu, Color(0.8, 0.8, 0.85)],
		["game scripts (timed)", gm, Color(0.7, 0.85, 1.0)], ["other nodes + GPU wait", eng, Color(C_WAIT, 0.6)]]
	for l in lines:
		_row_line(x0, y, l[0], l[1], l[2], wall.x); y += 17
	# the engine's phases (each includes our own sections that run in it)
	for ph in [["all _process (incl. ours)", "eng.process_all"], ["all physics ticks (incl. ours)", "eng.physics_all"],
			["render (frame_pre..post_draw)", "eng.render"], ["gaps: present / GPU wait / input", "eng.gaps"]]:
		var ki: int = _kidx.get(ph[1], -1)
		if ki < 0: continue
		_row_line(x0 + 14, y, ph[0], _stats(rows, func(r): return _sec[r * MAXK + ki]), Color(0.6, 0.6, 0.68), wall.x); y += 17
	y += 4
	for c in mini(ROWS - lines.size(), top.size()):
		var i: int = top[c][0]
		var st := _stats(rows, func(r): return _sec[r * MAXK + i])
		if st.y <= 0.0: break
		_row_line(x0 + 8, y, keys[i], st, colour.get(i, C_OTHER_GAME), wall.x); y += 17
		if mode == 2 and keys[i] == "p_bike_step":   # its stages, biggest first, the ones that matter
			var subs := []
			for k2 in keys.size():
				if _sub[k2] and keys[k2].begins_with("p_step."):
					subs.append([k2, _stats(rows, func(r): return _sec[r * MAXK + k2])])
			subs.sort_custom(func(a, b): return a[1].y > b[1].y)
			for sb in subs.slice(0, 3):
				if sb[1].y < 0.05: break
				_row_line(x0 + 22, y, keys[sb[0]].trim_prefix("p_step."), sb[1], colour.get(i, C_OTHER_GAME).darkened(0.35), wall.x); y += 17
	# counters, right column
	var cx := o.x + W_FULL - 170
	var cy := y0
	var dr := _stats(rows, func(r): return _draws[r])
	var pr := _stats(rows, func(r): return _prims[r])
	var tk := _stats(rows, func(r): return _ticks[r])
	var comp := 0.0
	for r in rows: comp += _comp[r]
	var spikes := 0
	for s in _spike_rows: if _frame - s < 600: spikes += 1
	var cl := [["draw calls", "%d" % int(dr.x)], ["primitives", "%.2f M" % (pr.x / 1e6)], ["physics ticks", "%.2f" % tk.x],
		["pipelines compiled", "%d" % int(comp)], ["spikes (10 s)", "%d" % spikes],
		["objects", "%d" % int(Performance.get_monitor(Performance.OBJECT_COUNT))],
		["nodes", "%d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		["VRAM", "%d MB" % int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576)],
		["static mem", "%d MB" % int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576)],
		["median frame", "%.2f ms" % _median]]
	for c in cl:
		_text(Vector2(cx, cy), c[0], 11, Color(0.6, 0.65, 0.75))
		_text(Vector2(cx + 110, cy), c[1], 11, Color(1, 0.4, 1) if c[0] == "pipelines compiled" and comp > 0 else Color.WHITE)
		cy += 17
	_text(Vector2(o.x + 10, o.y + 30 + GRAPH_H + 45 + (ROWS + 7) * 17.0 + 58), "F10 compact/full/off · Shift+F10 freeze · Ctrl+F10 save CSV · hover graph = one frame · red spike, pink = pipeline compile", 10, Color(1, 1, 1, 0.45))

func _row_line(x: float, y: float, nm: String, st: Vector2, c: Color, frame_ms: float) -> void:
	_view.draw_rect(Rect2(x, y - 9, 8, 8), c)
	_text(Vector2(x + 12, y), nm, 12, Color(0.92, 0.92, 0.95))
	_text(Vector2(x + 222, y), "%6.2f" % st.x, 12, Color.WHITE)
	_text(Vector2(x + 282, y), "%6.2f" % st.y, 12, Color(1, 0.6, 0.5) if st.y > SPIKE_MS else Color(0.8, 0.8, 0.85))
	var bw := clampf(st.x / maxf(frame_ms, 0.01), 0.0, 1.0) * 30.0
	_view.draw_rect(Rect2(x + 330, y - 8, bw, 6), c)

func _text(p: Vector2, s: String, size: int, c: Color) -> void:
	_view.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

# ---------------------------------------------------------------- tests: what the untimed _process scripts cost
## BMX_PROF_NODES=1 (+ BMX_PROF=1, --autotest=N): from 8 s in, every node that runs _process is grouped by its script; each
## group in turn is switched off for SETTLE + MEASURE frames and the drop in the whole _process phase (eng.process_all) is
## its cost. Prints `PROFNODES group= nodes= ms=` sorted (Game itself, timed already, and this profiler are left out).
## Switching a group off can change what the others do (e.g. a camera), so read it as an estimate.
var _NODES := Env.s("BMX_PROF_NODES") != ""
var _ns := {"phase": "wait", "t0": 0, "groups": [], "gi": -1, "n": 0, "sum": 0.0, "base": 0.0, "res": []}
const NODES_SETTLE := 20
const NODES_MEASURE := 90

func _nodes_collect() -> Array:
	var by := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n == self or n == game or _marks.has(n) or n == _view or n == _gview: continue
		if not n.is_processing(): continue
		var sc = n.get_script()
		var k: String = sc.resource_path.get_file() if sc and sc.resource_path != "" else ("(inner) " + str(sc.get_global_name()) if sc else n.get_class())
		if k == "" or k.begins_with("(inner) "): k = n.get_class() + (" [" + str(n.get_parent().name) + "]" if n.get_parent() else "")
		if not by.has(k): by[k] = []
		by[k].append(n)
	var out := []
	for k in by: out.append([k, by[k]])
	return out

func _nodes_step(proc_ms: float) -> void:
	var st := _ns
	if st.phase == "wait":
		if st.t0 == 0: st.t0 = Time.get_ticks_msec()
		if Time.get_ticks_msec() - st.t0 > 8000:
			st.groups = _nodes_collect()
			print("PROFNODES groups=%d" % st.groups.size())
			st.phase = "base"; st.n = 0; st.sum = 0.0
		return
	st.n += 1
	if st.n > NODES_SETTLE: st.sum += proc_ms
	if st.n < NODES_SETTLE + NODES_MEASURE: return
	var avg: float = st.sum / NODES_MEASURE
	if st.phase == "base":
		st.base = avg
		print("PROFNODES baseline process_all=%.2f ms" % avg)
	else:
		var g: Array = st.groups[st.gi]
		for nd in g[1]:
			if is_instance_valid(nd): nd.set_process(true)
		st.res.append([g[0], g[1].size(), st.base - avg])
	st.gi += 1
	st.n = 0; st.sum = 0.0
	st.phase = "group"
	if st.gi >= st.groups.size():
		st.res.sort_custom(func(a, b): return a[2] > b[2])
		for r in st.res: print("PROFNODES group=%s nodes=%d ms=%.2f" % [r[0], r[1], r[2]])
		_NODES = false
		return
	for nd in st.groups[st.gi][1]:
		if is_instance_valid(nd): nd.set_process(false)


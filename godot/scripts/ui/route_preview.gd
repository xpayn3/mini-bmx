class_name RoutePreview
extends Control
## The ride setup's ROUTE step: the trail a seed + RouteStyle lays out, seen from straight above. A TerrainField is
## set up on a worker thread (the same code the ride uses, so what you see is what you ride), debounced while a slider
## moves; the first 4 km of trail are cut into rows of ROW_M metres stacked top to bottom (a 4 km trail is a very
## long strip), with the elevation under them. Jumps, rollers and bridges are marked; the line is coloured by what the
## trail is (type) or how steep it is (grade).

signal built(stats: Dictionary)

const ROW_M := 1000.0
const DEBOUNCE := 0.14
const STRIP_H := 118.0
const PAPER := Color(0.97, 0.96, 0.9)      # the pause map's paper
const INK := Color("1d1f22")
const CONTOUR := Color(0.62, 0.40, 0.20)
const WATER_C := Color(0.55, 0.74, 0.86)
const TRAIL_C := Color("d22b25")
const GRID_C := Color(0.25, 0.42, 0.62)
const GRIDM := 10.0      # height samples (m)
const CI := 5.0          # contour interval (m)
const PX_M := 0.25       # land picture: pixels per metre (4 m a pixel)
const KIND_COL := [Color("ffffff"), Color("8fc2ff"), Color("ff9a45"), Color("d78cff"), Color("c9b08a"), Color("ffd21f"), Color("ffffff")]
const KIND_NAME := ["START", "ROAD", "SWITCHBACKS", "ESSES", "ROCKS", "JUMP LINE", "FINISH"]
const JUMP_TYPES := ["table", "double", "kicker", "tableLine", "flow", "doubleLine", "woodKicker"]
const BRIDGE_TYPES := ["bridge", "gorge", "rope", "skinny"]

var color_mode := "type"   # "type" = the paper map (red dashes) | "grade" = coloured by steepness
var data: Dictionary = {}   # the last finished trail (plain arrays)
var busy := false
var zoom := 0.0            # map pixels per metre (0 = fit the whole trail)
var centre := Vector2.ZERO   # world point at the middle of the map
var view: MapView

var _seed := 0
var _style: Dictionary = {}
var _fresh_seed := true
var _want := false           # a newer request is waiting
var _task := -1
var _result: Dictionary = {}
var _mutex := Mutex.new()
var _timer: Timer
var _t0 := 0
var _build_ms := 0.0
static var _hcache := {}   # land heights per 10 m cell for the seed (worker only): the land never depends on the style
static var _hseed := ""


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE
	_timer.timeout.connect(_start)
	add_child(_timer)
	view = MapView.new()
	view.pv = self
	add_child(view)
	_layout()
	resized.connect(_layout)
	TrailFeatures.ensure()   # (its static tables, made here on the main thread, never first on the worker)


func _layout() -> void:
	if view == null: return
	var top := 96.0
	view.position = Vector2(28.0, top)
	view.size = Vector2(maxf(10.0, size.x - 56.0), maxf(10.0, size.y - top - STRIP_H - 84.0))
	if zoom > 0.0: _clamp_view()
	queue_redraw()


## the map opens at a real map scale (about HOME_M metres across) at the start of the trail, land all round it
const HOME_M := 1000.0
func fit() -> void:
	zoom = 0.0
	if data.is_empty() or view == null: return
	zoom = maxf(_fit_zoom(), view.size.x / HOME_M)
	var X: PackedFloat64Array = data["X"]
	var Z: PackedFloat64Array = data["Z"]
	centre = Vector2(float(X[0]) + view.size.x * 0.5 / zoom - 80.0, float(Z[0]))
	_clamp_view()
	view.queue_redraw(); queue_redraw()


## the whole trail in view
func fit_all() -> void:
	if data.is_empty() or view == null: return
	zoom = _fit_zoom()
	var rg: Dictionary = (data["rows"] as Array)[0]
	centre = Vector2(float(rg["x0"]) + float(rg["w"]) * 0.5, float(rg["z0"]) + float(rg["h"]) * 0.5)
	_clamp_view()
	view.queue_redraw(); queue_redraw()


func _fit_zoom() -> float:
	var rg: Dictionary = (data["rows"] as Array)[0]
	return minf(view.size.x / float(rg["w"]), view.size.y / float(rg["h"]))


func _clamp_view() -> void:
	if data.is_empty(): return
	var rg: Dictionary = (data["rows"] as Array)[0]
	zoom = clampf(zoom, _fit_zoom(), 3.0)
	var hx := view.size.x * 0.5 / zoom
	var hz := view.size.y * 0.5 / zoom
	var x0: float = rg["x0"]; var z0: float = rg["z0"]; var w: float = rg["w"]; var h: float = rg["h"]
	centre.x = (x0 + w * 0.5) if hx * 2.0 >= w else clampf(centre.x, x0 + hx, x0 + w - hx)
	centre.y = (z0 + h * 0.5) if hz * 2.0 >= h else clampf(centre.y, z0 + hz, z0 + h - hz)


func zoom_at(screen: Vector2, factor: float) -> void:
	if data.is_empty() or zoom <= 0.0: return
	var before := centre + (screen - view.size * 0.5) / zoom
	zoom = clampf(zoom * factor, _fit_zoom(), 3.0)
	centre = before - (screen - view.size * 0.5) / zoom
	_clamp_view()
	view.queue_redraw(); queue_redraw()


func pan(delta_px: Vector2) -> void:
	if data.is_empty() or zoom <= 0.0: return
	centre -= delta_px / zoom
	_clamp_view()
	view.queue_redraw(); queue_redraw()


func _exit_tree() -> void:
	join()


func join() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## ask for the trail of this seed + style (debounced: the last ask wins)
func request(seed_in: int, style: Dictionary) -> void:
	if seed_in != _seed: _fresh_seed = true
	_seed = seed_in
	_style = style.duplicate()
	_want = true
	busy = true
	if is_inside_tree(): _timer.start()
	queue_redraw()


func _start() -> void:
	if _task >= 0 or not _want: return
	_want = false
	_t0 = Time.get_ticks_usec()
	var s := _seed
	var st := _style.duplicate()
	_task = WorkerThreadPool.add_task(_work.bind(s, st))


func _work(seed_in: int, style: Dictionary) -> void:
	var f := TerrainField.new()
	f.setup(seed_in, style)
	var C: TrailCourse = f.course
	var feats := []
	for ft in f.route_feats:
		feats.append([ft.x, ft.z, ft.dx, ft.dz, String(ft.type), ft.s])
	var out := {
		"seed": seed_in, "style": style, "n": C.n,
		"X": C.X.duplicate(), "Z": C.Z.duplicate(), "KD": C.KD.duplicate(),
		"E": C.E.duplicate(), "KAP": C.KAP.duplicate(), "drops": C.drops.duplicate(true),
		"feats": feats, "step": TrailCourse.STEP,
	}
	out["rows"] = _land_rows(f, C, seed_in)
	_mutex.lock()
	_result = out
	_mutex.unlock()


## worker: the paper map's land for each ROW_M of trail: a shaded picture + contour lines, from the field's land heights
func _land_rows(f: TerrainField, C: TrailCourse, seed_in: int) -> Array:
	var hk := "%d_%.3f" % [seed_in, float(f.grade_k)]   # (the land's shape depends on the grade too)
	if _hseed != hk:
		_hcache = {}
		_hseed = hk
	var n := C.n
	var x_start: float = C.X[0]
	var nrows := 1   # one continuous map of the whole trail
	var zmin := PackedFloat64Array()
	var zmax := PackedFloat64Array()
	for r in nrows:
		zmin.append(1e18); zmax.append(-1e18)
	for i in n:
		var r := 0
		zmin[r] = minf(zmin[r], C.Z[i]); zmax[r] = maxf(zmax[r], C.Z[i])
	var rows := []
	var paper := PAPER
	var light := Vector3(-0.55, 0.62, -0.55).normalized()
	for r in nrows:
		var x0 := floorf((x_start - 260.0) / GRIDM) * GRIDM
		var z0 := floorf((minf(zmin[r], zmax[r] - 100.0) - 420.0) / GRIDM) * GRIDM
		var w := ceilf((C.X[n - 1] - x_start + 520.0) / GRIDM) * GRIDM
		var h := ceilf((maxf(zmax[r], zmin[r] + 100.0) + 420.0 - z0) / GRIDM) * GRIDM
		var nx := int(w / GRIDM) + 1
		var nz := int(h / GRIDM) + 1
		var hh := PackedFloat32Array()
		hh.resize(nx * nz)
		var ix0 := int(round(x0 / GRIDM))
		var iz0 := int(round(z0 / GRIDM))
		var lo := 1e9
		var hi := -1e9
		for j in nz:
			for i in nx:
				var key := (ix0 + i) * 100003 + (iz0 + j)
				var v: float
				if _hcache.has(key): v = _hcache[key]
				else:
					v = f.landform(x0 + i * GRIDM, z0 + j * GRIDM)
					_hcache[key] = v
				hh[j * nx + i] = v
				lo = minf(lo, v); hi = maxf(hi, v)
		# the picture: hypsometric paper tint x hill shade, water flat blue
		var iw := int(w * PX_M)
		var ih := int(h * PX_M)
		var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
		var wl := TerrainField.WATER
		var span := maxf(8.0, hi - lo)
		for py in ih:
			var gz := py / PX_M / GRIDM
			var j0 := mini(int(gz), nz - 2)
			var fz := gz - j0
			for pxi in iw:
				var gx := pxi / PX_M / GRIDM
				var i0 := mini(int(gx), nx - 2)
				var fx := gx - i0
				var a := lerpf(hh[j0 * nx + i0], hh[j0 * nx + i0 + 1], fx)
				var b := lerpf(hh[(j0 + 1) * nx + i0], hh[(j0 + 1) * nx + i0 + 1], fx)
				var hv := lerpf(a, b, fz)
				if hv < wl - 0.05:
					img.set_pixel(pxi, py, WATER_C.lerp(paper, 0.15)); continue
				var gxh := lerpf(hh[j0 * nx + i0 + 1] - hh[j0 * nx + i0], hh[(j0 + 1) * nx + i0 + 1] - hh[(j0 + 1) * nx + i0], fz)
				var gzh := b - a
				var nrm := Vector3(-gxh, GRIDM, -gzh).normalized()
				var sh := clampf(nrm.dot(light), 0.0, 1.0)
				var t := clampf((hv - lo) / span, 0.0, 1.0)
				var base := Color(0.78, 0.86, 0.62).lerp(Color(0.86, 0.78, 0.58), t).lerp(paper, 0.45)
				img.set_pixel(pxi, py, (base * (0.62 + 0.5 * sh)).clamp())
		# contours (marching squares on the 10 m grid)
		var mi := PackedVector2Array()
		var ma := PackedVector2Array()
		for j in nz - 1:
			for i in nx - 1:
				var h0 := hh[j * nx + i]; var h1 := hh[j * nx + i + 1]
				var h2 := hh[(j + 1) * nx + i + 1]; var h3 := hh[(j + 1) * nx + i]
				var clo := minf(minf(h0, h1), minf(h2, h3)); var chi := maxf(maxf(h0, h1), maxf(h2, h3))
				var lv := ceilf(clo / CI) * CI
				while lv < chi:
					if lv >= wl:
						var pts := PackedVector2Array()
						var x := x0 + i * GRIDM; var z := z0 + j * GRIDM
						if (h0 < lv) != (h1 < lv): pts.append(Vector2(x + GRIDM * (lv - h0) / (h1 - h0), z))
						if (h1 < lv) != (h2 < lv): pts.append(Vector2(x + GRIDM, z + GRIDM * (lv - h1) / (h2 - h1)))
						if (h3 < lv) != (h2 < lv): pts.append(Vector2(x + GRIDM * (lv - h3) / (h2 - h3), z + GRIDM))
						if (h0 < lv) != (h3 < lv): pts.append(Vector2(x, z + GRIDM * (lv - h0) / (h3 - h0)))
						if pts.size() >= 2:
							if is_equal_approx(fposmod(lv, CI * 5.0), 0.0): ma.append_array(pts)
							else: mi.append_array(pts)
					lv += CI
		rows.append({"x0": x0, "z0": z0, "w": w, "h": h, "img": img, "minor": mi, "major": ma})
	return rows


func _process(_dt: float) -> void:
	if _task < 0: return
	if not WorkerThreadPool.is_task_completed(_task): return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_mutex.lock()
	var r := _result
	_result = {}
	_mutex.unlock()
	_build_ms = (Time.get_ticks_usec() - _t0) / 1000.0
	if _want:   # asked again meanwhile: build that one, show nothing stale in between
		_start()
		return
	busy = false
	if r.is_empty(): return
	for rw in r["rows"]:
		rw["tex"] = ImageTexture.create_from_image(rw["img"])
		rw.erase("img")
	data = r
	data["stats"] = _stats(r)
	data["grade"] = _grades(r)
	if zoom <= 0.0 or _fresh_seed: fit()
	_fresh_seed = false
	built.emit(data["stats"])
	if view: view.queue_redraw()
	queue_redraw()


# ---------------------------------------------------------------- numbers
func _grades(d: Dictionary) -> PackedFloat32Array:
	# % of fall (+ = downhill) over ~24 m, per centreline point
	var E: PackedFloat32Array = d["E"]
	var n: int = d["n"]
	var st: float = d["step"]
	var out := PackedFloat32Array()
	out.resize(n)
	var k := 6
	for i in n:
		var a := maxi(0, i - k)
		var b := mini(n - 1, i + k)
		out[i] = (E[a] - E[b]) / maxf(0.1, (b - a) * st) * 100.0
	return out


func _stats(d: Dictionary) -> Dictionary:
	var n: int = d["n"]
	var st: float = d["step"]
	var E: PackedFloat32Array = d["E"]
	var KAP: PackedFloat32Array = d["KAP"]
	var KD: PackedInt32Array = d["KD"]
	var len_m := (n - 1) * st
	var fall := E[0] - E[n - 1]
	var steepest := 0.0
	var w := int(100.0 / st)
	for i in range(0, n - w, 5):
		steepest = maxf(steepest, absf(E[i] - E[i + w]))
	var bends := 0
	var tight := 0
	var inb := false
	var peak := 0.0
	for i in n:
		var k := absf(KAP[i])
		if k > 0.02:
			inb = true
			peak = maxf(peak, k)
		elif inb:
			bends += 1
			if peak > 0.06: tight += 1
			inb = false
			peak = 0.0
	var jumps := 0
	var rollers := 0
	var bridges := 0
	for f in d["feats"]:
		var t: String = f[4]
		if t in JUMP_TYPES: jumps += 1
		elif t == "rhythm": rollers += 1
		elif t in BRIDGE_TYPES: bridges += 1
	var kinds := {}
	for i in n: kinds[KD[i]] = int(kinds.get(KD[i], 0)) + 1
	return {"length": len_m, "fall": fall, "avg": fall / maxf(1.0, len_m) * 100.0, "steepest": steepest,
		"bends": bends, "tight": tight, "jumps": jumps, "rollers": rollers, "bridges": bridges,
		"drops": (d["drops"] as Array).size(), "kinds": kinds, "ms": _build_ms}


# ---------------------------------------------------------------- drawing
func _grade_col(g: float) -> Color:
	var a := absf(g)
	if g < -1.0: return Color("6aa8ff")   # climbing
	if a < 4.0: return Color("56d68a").lerp(Color("c8e65a"), a / 4.0)
	if a < 10.0: return Color("c8e65a").lerp(Color("ff9a3c"), (a - 4.0) / 6.0)
	return Color("ff9a3c").lerp(Color("ff3d4a"), clampf((a - 10.0) / 8.0, 0.0, 1.0))


func _dashes(line: PackedVector2Array, dash: float, gap: float, col: Color, w: float) -> void:
	var on := true
	var left := dash
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		var d := 0.0
		while d < seg:
			var take := minf(left, seg - d)
			if on: draw_line(a.lerp(b, d / seg), a.lerp(b, (d + take) / seg), col, w, true)
			d += take
			left -= take
			if left <= 0.001:
				on = not on
				left = dash if on else gap


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), PAPER)
	var font := ThemeDB.fallback_font
	if data.is_empty():
		draw_string(font, Vector2(24, sz.y * 0.5), "BUILDING TRAIL…", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.55))
		return
	var X: PackedFloat64Array = data["X"]
	var Z: PackedFloat64Array = data["Z"]
	var E: PackedFloat32Array = data["E"]
	var G: PackedFloat32Array = data["grade"]
	var n: int = data["n"]
	var m := 28.0
	var first_p := Vector2.ZERO
	# elevation strip
	var ey := sz.y - STRIP_H - 62.0
	var ex0 := m
	var ew := sz.x - m * 2.0
	var emin := 1e18
	var emax := -1e18
	for i in n:
		emin = minf(emin, E[i]); emax = maxf(emax, E[i])
	var er := maxf(20.0, emax - emin)
	draw_rect(Rect2(ex0, ey, ew, STRIP_H), Color(INK, 0.06))
	var xr := float(X[n - 1] - X[0])
	var prev := Vector2.ZERO
	for i in range(0, n, 2):
		var p := Vector2(ex0 + float(X[i] - X[0]) / xr * ew, ey + STRIP_H - 8.0 - (E[i] - emin) / er * (STRIP_H - 26.0))
		var colg := _grade_col(G[i])
		draw_line(Vector2(p.x, p.y), Vector2(p.x, ey + STRIP_H - 2.0), Color(colg.r, colg.g, colg.b, 0.22), 2.5)
		if i > 0: draw_line(prev, p, colg.darkened(0.25), 2.0, true)
		prev = p
	for dr in data["drops"]:
		var xi: float = (float(X[mini(n - 1, dr[1])]) - X[0]) / xr
		draw_line(Vector2(ex0 + xi * ew, ey + 4), Vector2(ex0 + xi * ew, ey + STRIP_H - 2), Color(TRAIL_C, 0.7), 1.5)
	draw_string(font, Vector2(ex0 + 4, ey + 14), "ELEVATION  %d – %d M   (red tick = cliff drop)" % [roundi(emin), roundi(emax)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.7))
	if view != null and view.size.x > 0.0 and zoom > 0.0:   # the part of the trail the map shows now
		var rg: Dictionary = (data["rows"] as Array)[0]
		var vx0: float = centre.x - view.size.x * 0.5 / zoom
		var vx1: float = centre.x + view.size.x * 0.5 / zoom
		var xa2 := clampf((vx0 - float(X[0])) / xr, 0.0, 1.0)
		var xb2 := clampf((vx1 - float(X[0])) / xr, 0.0, 1.0)
		draw_rect(Rect2(ex0 + xa2 * ew, ey, (xb2 - xa2) * ew, STRIP_H), Color(TRAIL_C, 0.1))
		draw_rect(Rect2(ex0 + xa2 * ew, ey, (xb2 - xa2) * ew, STRIP_H), Color(TRAIL_C, 0.6), false, 1.5)
	# legend (top right)
	var lx := sz.x - m
	var ly := 24.0
	if color_mode == "grade":
		for it in [["FLAT", _grade_col(1.0)], ["STEADY", _grade_col(6.0)], ["STEEP", _grade_col(11.0)], ["WALL", _grade_col(18.0)], ["CLIMB", _grade_col(-4.0)]]:
			var tw := font.get_string_size(String(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			lx -= tw + 22.0
			draw_rect(Rect2(lx, ly - 8, 10, 10), it[1])
			draw_string(font, Vector2(lx + 15, ly + 1), String(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
	else:
		_dashes(PackedVector2Array([Vector2(lx - 190, ly - 3), Vector2(lx - 160, ly - 3)]), 9.0, 5.0, TRAIL_C, 3.2)
		draw_string(font, Vector2(lx - 154, ly + 1), "TRAIL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
	var l2 := sz.x - m - 280.0
	draw_colored_polygon(PackedVector2Array([Vector2(l2, ly + 14), Vector2(l2 + 6, ly + 25), Vector2(l2 - 6, ly + 25)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(l2, ly + 18), Vector2(l2 + 3, ly + 24), Vector2(l2 - 3, ly + 24)]), Color(1, 0.85, 0.2))
	draw_string(font, Vector2(l2 + 10, ly + 25), "JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
	draw_circle(Vector2(l2 + 66, ly + 21), 2.4, INK)
	draw_string(font, Vector2(l2 + 74, ly + 25), "ROLLERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
	draw_rect(Rect2(l2 + 140, ly + 17, 7, 7), INK)
	draw_string(font, Vector2(l2 + 152, ly + 25), "BRIDGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
	if busy:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(PAPER, 0.3))
		draw_string(font, Vector2(m, sz.y - 4), "UPDATING…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TRAIL_C)


## the map itself: drag to pan, wheel to zoom, double click (or R) fits the whole trail. Clipped to its own rectangle.
class MapView extends Control:
	var pv: RoutePreview
	var _drag := false

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_CLICK
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _gui_input(e: InputEvent) -> void:
		if pv == null: return
		if e is InputEventMouseButton:
			var b := e as InputEventMouseButton
			if b.button_index == MOUSE_BUTTON_LEFT or b.button_index == MOUSE_BUTTON_MIDDLE:
				_drag = b.pressed
				if b.pressed and b.double_click: pv.fit_all() if pv.zoom > pv._fit_zoom() * 1.05 else pv.fit()
			elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP: pv.zoom_at(b.position, 1.18)
			elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN: pv.zoom_at(b.position, 1.0 / 1.18)
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			pv.pan((e as InputEventMouseMotion).relative)
			accept_event()
		elif e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_R:
			pv.fit()

	func _w(p: Vector2) -> Vector2:   # world (x, z) -> this control
		return size * 0.5 + (p - pv.centre) * pv.zoom

	func _dash(line: PackedVector2Array, dash: float, gap: float, col: Color, w: float) -> void:
		var on := true
		var left := dash
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.001: continue
			var d := 0.0
			while d < seg:
				var take := minf(left, seg - d)
				if on: draw_line(a.lerp(b, d / seg), a.lerp(b, (d + take) / seg), col, w, true)
				d += take
				left -= take
				if left <= 0.001:
					on = not on
					left = dash if on else gap

	func _draw() -> void:
		if pv == null or pv.data.is_empty() or pv.zoom <= 0.0: return
		var data: Dictionary = pv.data
		var z := pv.zoom
		var rw: Dictionary = (data["rows"] as Array)[0]
		var x0: float = rw["x0"]; var z0: float = rw["z0"]; var w: float = rw["w"]; var h: float = rw["h"]
		var tr := Rect2(_w(Vector2(x0, z0)), Vector2(w, h) * z)
		draw_rect(Rect2(Vector2.ZERO, size), RoutePreview.PAPER.darkened(0.04))
		if rw.has("tex"): draw_texture_rect(rw["tex"], tr, false)
		var org := _w(Vector2(x0, z0))
		for kind in ["minor", "major"]:
			var src: PackedVector2Array = rw[kind]
			if src.size() < 2: continue
			var pts := PackedVector2Array()
			pts.resize(src.size())
			for q in src.size(): pts[q] = org + (src[q] - Vector2(x0, z0)) * z
			draw_multiline(pts, Color(RoutePreview.CONTOUR, 0.5 if kind == "minor" else 0.85), 0.8 if kind == "minor" else 1.5, true)
		var font := ThemeDB.fallback_font
		# 100 m grid, numbered every 500 m
		var gx := ceilf(maxf(x0, pv.centre.x - size.x * 0.5 / z) / 100.0) * 100.0
		var gx1 := minf(x0 + w, pv.centre.x + size.x * 0.5 / z)
		while gx < gx1:
			var px := _w(Vector2(gx, 0)).x
			draw_line(Vector2(px, 0), Vector2(px, size.y), Color(RoutePreview.GRID_C, 0.2), 1.0)
			if int(gx) % 500 == 0: draw_string(font, Vector2(px + 3, size.y - 5), "%d M" % int(gx), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(RoutePreview.GRID_C, 0.9))
			gx += 100.0
		var X: PackedFloat64Array = data["X"]
		var Z: PackedFloat64Array = data["Z"]
		var G: PackedFloat32Array = data["grade"]
		var n: int = data["n"]
		var line := PackedVector2Array()
		var lines: Array = []
		var vx0 := pv.centre.x - size.x * 0.5 / z - 10.0
		var vx1 := pv.centre.x + size.x * 0.5 / z + 10.0
		for i in n:
			var px := float(X[i])
			if px < vx0 or px > vx1:
				if line.size() > 1: lines.append(line)
				line = PackedVector2Array()
				continue
			line.append(_w(Vector2(px, float(Z[i]))))
		if line.size() > 1: lines.append(line)
		var cw := clampf(z * 5.0, 5.0, 9.0)
		for ln in lines: draw_polyline(ln, Color(1, 1, 1, 0.95), cw, true)
		if pv.color_mode == "type":
			for ln in lines:
				draw_polyline(ln, Color(RoutePreview.TRAIL_C, 0.35), cw * 0.35, true)
				_dash(ln, cw * 1.6, cw * 0.9, RoutePreview.TRAIL_C, cw * 0.55)
		else:
			var pts := PackedVector2Array()
			var col_prev := Color.WHITE
			var kprev := -999
			for i in n:
				var px := float(X[i])
				if px < vx0 or px > vx1:
					if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.6, true)
					pts = PackedVector2Array(); kprev = -999
					continue
				var gq := roundi(G[i])
				var p := _w(Vector2(px, float(Z[i])))
				if gq != kprev and pts.size() > 0:
					pts.append(p)
					if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.6, true)
					pts = PackedVector2Array([p])
				else: pts.append(p)
				col_prev = pv._grade_col(float(gq)); kprev = gq
			if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.6, true)
		var k := clampf(z * 1.4, 0.9, 2.2)   # marker size grows a little with the zoom
		for f in data["feats"]:
			var fp := _w(Vector2(float(f[0]), float(f[1])))
			if fp.x < -20 or fp.x > size.x + 20: continue
			var t: String = f[4]
			if t in RoutePreview.JUMP_TYPES:
				draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -7) * k, fp + Vector2(6, 4.5) * k, fp + Vector2(-6, 4.5) * k]), RoutePreview.INK)
				draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -3) * k, fp + Vector2(3, 2.5) * k, fp + Vector2(-3, 2.5) * k]), Color(1, 0.85, 0.2))
				if z > 1.3: draw_string(font, fp + Vector2(9, 4) * k, t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RoutePreview.INK)
			elif t == "rhythm":
				draw_circle(fp, 2.4 * k, RoutePreview.INK)
			elif t in RoutePreview.BRIDGE_TYPES:
				draw_rect(Rect2(fp - Vector2(3.5, 3.5) * k, Vector2(7, 7) * k), RoutePreview.INK)
		var sp := _w(Vector2(float(X[0]), float(Z[0])))
		draw_circle(sp, 6.0, Color("2f9e58"))
		draw_circle(sp, 6.0, Color.WHITE, false, 1.5)
		draw_string(font, sp + Vector2(10, -8), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RoutePreview.INK)
		draw_rect(Rect2(Vector2.ZERO, size), Color(RoutePreview.INK, 0.35), false, 1.0)
		draw_string(font, Vector2(8, 16), "DRAG TO MOVE  ·  WHEEL TO ZOOM  ·  DOUBLE CLICK: WHOLE TRAIL / BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(RoutePreview.INK, 0.6))

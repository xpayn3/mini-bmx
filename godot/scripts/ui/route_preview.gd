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
static var _bcache := {}   # per cell: Vector2(dry, rugged)
static var _pcache := {}   # pathN per cell (the wild side paths are its zero lines)
static var _tcache := {}   # trees per 14 m cell
static var _hseed := ""
const TREE_CELL := 14.0
const NAMES := {"table": "TABLETOP", "double": "DOUBLE", "kicker": "KICKER", "tableLine": "TABLE LINE", "flow": "FLOW LINE", "doubleLine": "DOUBLE LINE",
	"woodKicker": "WOOD KICKER", "rhythm": "ROLLERS", "bridge": "BRIDGE", "gorge": "GORGE BRIDGE", "rope": "ROPE BRIDGE", "skinny": "SKINNY"}


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
		"feats": feats, "step": TrailCourse.STEP, "VA": C.VA.duplicate(),
		"runs": _runs(C),
	}
	out["rows"] = _land_rows(f, C, seed_in)
	_mutex.lock()
	_result = out
	_mutex.unlock()


## worker: the paper map's land for each ROW_M of trail: a shaded picture + contour lines, from the field's land heights
## the trees thinned for zooming out: [all, one per 24 m cell, 48 m, 96 m] (so the map never draws more than a few thousand symbols)
const TREE_GAPS := [8.0, 24.0, 48.0, 96.0]
func _tree_lods(all: PackedVector3Array) -> Array:
	var out := [all]
	for gi in range(1, TREE_GAPS.size()):
		var cell: float = TREE_GAPS[gi]
		var seen := {}
		var arr := PackedVector3Array()
		for t in all:
			var key := int(floorf(t.x / cell)) * 100003 + int(floorf(t.y / cell))
			if seen.has(key): continue
			seen[key] = true
			arr.append(t)
		out.append(arr)
	return out


## [kind, first index, last index] of every run of one section kind (hairpins, esses, rock gardens, jump lines)
func _runs(C: TrailCourse) -> Array:
	var out := []
	var i := 0
	while i < C.n:
		var k: int = C.KD[i]
		var j := i
		while j + 1 < C.n and C.KD[j + 1] == k: j += 1
		if k in [TrailCourse.SWITCH, TrailCourse.ESSES, TrailCourse.ROCKS] and j - i >= 6: out.append([k, i, j])
		i = j + 1
	return out


func _land_rows(f: TerrainField, C: TrailCourse, seed_in: int) -> Array:
	var hk := "%d_%.3f_%.0f_%.0f" % [seed_in, float(f.grade_k), f.biome_dry, f.biome_rug]   # (the land depends on the grade and the biome too)
	if _hseed != hk:
		_hcache = {}
		_bcache = {}
		_pcache = {}
		_tcache = {}
		_hseed = hk
	var n := C.n
	# the trail runs any way (the route spine): the map's box is the trail's own min / max
	var x_start: float = C.X[0]
	var x_end: float = C.X[0]
	for i in n:
		x_start = minf(x_start, C.X[i]); x_end = maxf(x_end, C.X[i])
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
		var w := ceilf((x_end - x_start + 520.0) / GRIDM) * GRIDM
		var h := ceilf((maxf(zmax[r], zmin[r] + 100.0) + 420.0 - z0) / GRIDM) * GRIDM
		var nx := int(w / GRIDM) + 1
		var nz := int(h / GRIDM) + 1
		var hh := PackedFloat32Array()
		hh.resize(nx * nz)
		var dd := PackedFloat32Array()   # dryness / ruggedness per grid vertex (the biome: sand or rock tints)
		var rr := PackedFloat32Array()
		dd.resize(nx * nz); rr.resize(nx * nz)
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
				var bv: Vector2
				if _bcache.has(key): bv = _bcache[key]
				else:
					f.biome(x0 + i * GRIDM, z0 + j * GRIDM)
					bv = Vector2(f.b_dry, f.b_rug)
					_bcache[key] = bv
				dd[j * nx + i] = bv.x; rr[j * nx + i] = bv.y
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
				var dy := lerpf(lerpf(dd[j0 * nx + i0], dd[j0 * nx + i0 + 1], fx), lerpf(dd[(j0 + 1) * nx + i0], dd[(j0 + 1) * nx + i0 + 1], fx), fz)
				var rg := lerpf(lerpf(rr[j0 * nx + i0], rr[j0 * nx + i0 + 1], fx), lerpf(rr[(j0 + 1) * nx + i0], rr[(j0 + 1) * nx + i0 + 1], fx), fz)
				var base := Color(0.78, 0.86, 0.62).lerp(Color(0.86, 0.78, 0.58), t)
				base = base.lerp(Color(0.84, 0.82, 0.76), rg * (1.0 - dy) * 0.7).lerp(Color(0.95, 0.82, 0.52).lerp(Color(0.86, 0.5, 0.32), rg * 0.8), dy * 0.85)   # rock grey / dune sand / canyon red
				base = base.lerp(paper, 0.45)
				img.set_pixel(pxi, py, (base * (0.62 + 0.5 * sh)).clamp())
		# the wild side paths: the zero lines of the path noise (the ground shader draws dirt along them)
		var pp := PackedFloat32Array()
		pp.resize(nx * nz)
		for j in nz:
			for i in nx:
				var key2 := (ix0 + i) * 100003 + (iz0 + j)
				var pv: float
				if _pcache.has(key2): pv = _pcache[key2]
				else:
					pv = f.pathN(x0 + i * GRIDM, z0 + j * GRIDM)
					_pcache[key2] = pv
				pp[j * nx + i] = pv
		var paths := PackedVector2Array()
		for j in nz - 1:
			for i in nx - 1:
				var q0 := pp[j * nx + i]; var q1 := pp[j * nx + i + 1]
				var q2 := pp[(j + 1) * nx + i + 1]; var q3 := pp[(j + 1) * nx + i]
				if minf(minf(q0, q1), minf(q2, q3)) > 0.0 or maxf(maxf(q0, q1), maxf(q2, q3)) < 0.0: continue
				if hh[j * nx + i] < wl: continue
				var cp := PackedVector2Array()
				var cx0 := x0 + i * GRIDM; var cz0 := z0 + j * GRIDM
				if (q0 < 0.0) != (q1 < 0.0): cp.append(Vector2(cx0 + GRIDM * q0 / (q0 - q1), cz0))
				if (q1 < 0.0) != (q2 < 0.0): cp.append(Vector2(cx0 + GRIDM, cz0 + GRIDM * q1 / (q1 - q2)))
				if (q3 < 0.0) != (q2 < 0.0): cp.append(Vector2(cx0 + GRIDM * q3 / (q3 - q2), cz0 + GRIDM))
				if (q0 < 0.0) != (q3 < 0.0): cp.append(Vector2(cx0, cz0 + GRIDM * q0 / (q0 - q3)))
				if cp.size() >= 2:
					paths.append(cp[0]); paths.append(cp[1])
		# trees (the game's forest mask + biome rules, a symbol per few real trees) kept off the trail
		var near := {}
		for ci in n:
			var gx2 := int(C.X[ci] / 8.0); var gz2 := int(floorf(C.Z[ci] / 8.0))
			for ax in range(-2, 3):
				for az in range(-2, 3): near[(gx2 + ax) * 100003 + gz2 + az] = true
		var trees := PackedVector3Array()
		var k0x := int(floorf(x0 / TREE_CELL)); var k0z := int(floorf(z0 / TREE_CELL))
		for kj in int(h / TREE_CELL):
			for ki in int(w / TREE_CELL):
				var ck := (k0x + ki) * 100003 + (k0z + kj)
				var tl: Array
				if _tcache.has(ck): tl = _tcache[ck]
				else:
					tl = _cell_trees(f, k0x + ki, k0z + kj, seed_in)
					_tcache[ck] = tl
				for tv in tl:
					var tvv: Vector3 = tv
					if near.has(int(tvv.x / 8.0) * 100003 + int(floorf(tvv.y / 8.0))): continue
					trees.append(tvv)
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
		rows.append({"x0": x0, "z0": z0, "w": w, "h": h, "img": img, "minor": mi, "major": ma, "paths": paths, "trees": _tree_lods(trees)})
	return rows


## the trees of one 14 m cell, by the chunk builder's own rules (forest mask, roadside, dry = cacti, rugged = pines);
## Vector3(x, z, kind): 0 broadleaf, 1 pine, 2 cactus
func _cell_trees(f: TerrainField, kx: int, kz: int, seed_in: int) -> Array:
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_in, kx, kz])
	var cxm := (kx + 0.5) * TREE_CELL
	var czm := (kz + 0.5) * TREE_CELL
	if f.landform(cxm, czm) < TerrainField.WATER + 0.4: return out
	var hc := f.landform(cxm, czm)
	f.biome(cxm, czm)
	var dry: float = f.b_dry
	var rug: float = f.b_rug
	for i in 6:
		var x := (kx + rng.randf()) * TREE_CELL
		var z := (kz + rng.randf()) * TREE_CELL
		var forest: float = f.n(x + 400, z, TerrainField.I38)
		var p := TerrainField.sm(-0.25, 0.25, forest) * 0.9 + 0.05
		if rng.randf() > p: continue
		if absf(f.pathN(x, z)) < 0.1: continue
		if rng.randf() < dry:
			if rng.randf() < 0.35: out.append(Vector3(x, z, 2.0))
			continue
		out.append(Vector3(x, z, 1.0 if (hc > 4.0 or rng.randf() < 0.3 + rug * 0.6) else 0.0))
	return out


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
	# run time at a good rider's pace (VA: the speed he arrives at each point) and the difficulty from what is on the trail
	var VA: PackedFloat32Array = d["VA"]
	var secs := 0.0
	var vmax := 0.0
	for i in n - 1:
		secs += st / maxf(2.0, VA[i])
		vmax = maxf(vmax, VA[i])
	var km := len_m / 1000.0
	var avgp := fall / maxf(1.0, len_m) * 100.0
	var score := 30.0 * clampf((avgp - 0.5) / 3.0, 0.0, 1.0) + 20.0 * clampf((steepest - 8.0) / 16.0, 0.0, 1.0) 		+ 20.0 * clampf((tight / km - 6.0) / 16.0, 0.0, 1.0) + 15.0 * clampf(jumps / km / 2.5, 0.0, 1.0) 		+ 10.0 * clampf((d["drops"] as Array).size() / 3.0, 0.0, 1.0) + 5.0 * clampf((vmax - 12.0) / 6.0, 0.0, 1.0)
	var rating := 0 if score < 38.0 else (1 if score < 52.0 else (2 if score < 66.0 else 3))
	return {"time": secs, "avg_kmh": len_m / maxf(1.0, secs) * 3.6, "score": score, "rating": rating,
		"length": len_m, "fall": fall, "avg": fall / maxf(1.0, len_m) * 100.0, "steepest": steepest,
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
	var xr := float(maxi(n - 1, 1))   # the strip runs by distance along the trail (points are 2 m apart)
	var prev := Vector2.ZERO
	for i in range(0, n, 2):
		var p := Vector2(ex0 + float(i) / xr * ew, ey + STRIP_H - 8.0 - (E[i] - emin) / er * (STRIP_H - 26.0))
		var colg := _grade_col(G[i])
		draw_line(Vector2(p.x, p.y), Vector2(p.x, ey + STRIP_H - 2.0), Color(colg.r, colg.g, colg.b, 0.22), 2.5)
		if i > 0: draw_line(prev, p, colg.darkened(0.25), 2.0, true)
		prev = p
	for dr in data["drops"]:
		var xi: float = float(mini(n - 1, dr[1])) / xr
		draw_line(Vector2(ex0 + xi * ew, ey + 4), Vector2(ex0 + xi * ew, ey + STRIP_H - 2), Color(TRAIL_C, 0.7), 1.5)
	draw_string(font, Vector2(ex0 + 4, ey + 14), "ELEVATION  %d – %d M   (red tick = cliff drop)" % [roundi(emin), roundi(emax)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.7))
	if view != null and view.size.x > 0.0 and zoom > 0.0:   # the part of the trail the map shows now
		var rg: Dictionary = (data["rows"] as Array)[0]
		var vx0: float = centre.x - view.size.x * 0.5 / zoom
		var vx1: float = centre.x + view.size.x * 0.5 / zoom
		var vz0: float = centre.y - view.size.y * 0.5 / zoom
		var vz1: float = centre.y + view.size.y * 0.5 / zoom
		var ia := n
		var ib := -1
		for i in range(0, n, 4):   # the stretch of trail inside the view
			if X[i] >= vx0 and X[i] <= vx1 and Z[i] >= vz0 and Z[i] <= vz1:
				ia = mini(ia, i); ib = maxi(ib, i)
		var xa2 := clampf(float(ia) / xr, 0.0, 1.0)
		var xb2 := clampf(float(ib) / xr, 0.0, 1.0) if ib >= 0 else xa2
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
	draw_colored_polygon(PackedVector2Array([Vector2(l2 - 105, ly + 17), Vector2(l2 - 93, ly + 17), Vector2(l2 - 99, ly + 26)]), TRAIL_C)
	draw_string(font, Vector2(l2 - 88, ly + 25), "DROP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.8))
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
		var font := ThemeDB.fallback_font
		# everything in world metres goes through one canvas transform (the GPU moves it, no per-point work here);
		# widths are given in pixels / z
		var iz := 1.0 / z
		var vx0 := pv.centre.x - size.x * 0.5 / z - 10.0
		var vx1 := pv.centre.x + size.x * 0.5 / z + 10.0
		var vz0 := pv.centre.y - size.y * 0.5 / z - 10.0
		var vz1 := pv.centre.y + size.y * 0.5 / z + 10.0
		draw_set_transform(size * 0.5 - pv.centre * z, 0.0, Vector2(z, z))
		for kind in ["minor", "major"]:
			var src: PackedVector2Array = rw[kind]
			if src.size() > 1:
				draw_multiline(src, Color(RoutePreview.CONTOUR, 0.5 if kind == "minor" else 0.85), (0.8 if kind == "minor" else 1.5) * iz)
		# 100 m grid
		var gx := ceilf(maxf(x0, vx0) / 100.0) * 100.0
		while gx < minf(x0 + w, vx1):
			draw_line(Vector2(gx, vz0), Vector2(gx, vz1), Color(RoutePreview.GRID_C, 0.2), iz)
			gx += 100.0
		# the other tracks: thin, lighter than the main trail
		var pth: PackedVector2Array = rw["paths"]
		if pth.size() > 1:
			var tw := clampf(z * 1.8, 0.9, 12.0)
			draw_multiline(pth, Color(0.45, 0.33, 0.2, 0.4), (tw + 1.0) * iz)
			draw_multiline(pth, Color(0.94, 0.86, 0.7, 0.85), tw * iz)
		# the trail
		var X: PackedFloat64Array = data["X"]
		var Z: PackedFloat64Array = data["Z"]
		var G: PackedFloat32Array = data["grade"]
		var n: int = data["n"]
		var lines: Array = []
		var line := PackedVector2Array()
		for i in n:
			var px := float(X[i])
			if px < vx0 or px > vx1:
				if line.size() > 1: lines.append(line)
				line = PackedVector2Array()
				continue
			line.append(Vector2(px, float(Z[i])))
		if line.size() > 1: lines.append(line)
		var cw := clampf(z * 5.5, 5.5, 40.0)   # real width (the trail is ~3 m, drawn 5.5 m) with a floor, like a road on a web map
		for ln in lines:
			draw_polyline(ln, Color(0.3, 0.19, 0.1, 0.95), (cw + clampf(cw * 0.35, 1.5, 3.0)) * iz, true)
			draw_polyline(ln, Color(0.97, 0.84, 0.52), cw * iz, true)
		if pv.color_mode == "type":
			for ln in lines: _dash(ln, 8.0 * iz, 6.0 * iz, RoutePreview.TRAIL_C, clampf(cw * 0.2, 1.2, 2.6) * iz)
		else:
			var pts := PackedVector2Array()
			var col_prev := Color.WHITE
			var kprev := -999
			for i in n:
				var px := float(X[i])
				if px < vx0 or px > vx1:
					if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.55 * iz, true)
					pts = PackedVector2Array(); kprev = -999
					continue
				var gq := roundi(G[i])
				var p := Vector2(px, float(Z[i]))
				if gq != kprev and pts.size() > 0:
					pts.append(p)
					if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.55 * iz, true)
					pts = PackedVector2Array([p])
				else: pts.append(p)
				col_prev = pv._grade_col(float(gq)); kprev = gq
			if pts.size() > 1: draw_polyline(pts, col_prev, cw * 0.55 * iz, true)
		# trees: the thinned list for this zoom (symbols stay about 14 px apart), a few thousand at most
		if z >= 0.3:
			var lod := 0
			var gaps: Array = RoutePreview.TREE_GAPS
			while lod < gaps.size() - 1 and float(gaps[lod]) * z < 14.0: lod += 1
			var tl: PackedVector3Array = (rw["trees"] as Array)[lod]
			var rr := clampf(z * 2.4, 1.4, 7.0) * iz
			for tv in tl:
				if tv.x < vx0 or tv.x > vx1 or tv.y < vz0 or tv.y > vz1: continue
				var tp := Vector2(tv.x, tv.y)
				if tv.z < 0.5:
					draw_circle(tp, rr, Color(0.38, 0.6, 0.34, 0.9))
				elif tv.z < 1.5:
					draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -rr * 1.3), tp + Vector2(rr, rr * 0.8), tp + Vector2(-rr, rr * 0.8)]), Color(0.18, 0.4, 0.28, 0.95))
				else:
					draw_line(tp + Vector2(0, -rr), tp + Vector2(0, rr), Color(0.45, 0.55, 0.25), maxf(1.0 * iz, rr * 0.45))
					draw_line(tp + Vector2(-rr * 0.8, 0), tp + Vector2(rr * 0.8, 0), Color(0.45, 0.55, 0.25), maxf(1.0 * iz, rr * 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 500 m numbers, features and labels in screen space
		var gx2 := ceilf(maxf(x0, vx0) / 500.0) * 500.0
		while gx2 < minf(x0 + w, vx1):
			draw_string(font, Vector2(_w(Vector2(gx2, 0)).x + 3, size.y - 5), "%d M" % int(gx2), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(RoutePreview.GRID_C, 0.9))
			gx2 += 500.0
		var k := clampf(z * 1.4, 0.9, 2.2)   # marker size grows a little with the zoom
		var placed: Array = []
		var label := func(at: Vector2, txt: String, col: Color) -> void:
			if z < 0.45: return
			for q in placed:
				if (q as Vector2).distance_to(at) < 70.0: return
			placed.append(at)
			draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(1, 1, 1, 0.9))
			draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		for rn in data["runs"]:
			var mi_: int = (int(rn[1]) + int(rn[2])) / 2
			var mp := _w(Vector2(float(X[mi_]), float(Z[mi_])))
			if mp.x < -40 or mp.x > size.x + 40 or mp.y < -20 or mp.y > size.y + 20: continue
			label.call(mp + Vector2(-26, -16 - cw), ["", "", "HAIRPINS", "ESSES", "ROCK GARDEN"][int(rn[0])], Color(0.55, 0.2, 0.1))
		for f in data["feats"]:
			var fp := _w(Vector2(float(f[0]), float(f[1])))
			if fp.x < -20 or fp.x > size.x + 20: continue
			var t: String = f[4]
			if t in RoutePreview.JUMP_TYPES:
				draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -7) * k, fp + Vector2(6, 4.5) * k, fp + Vector2(-6, 4.5) * k]), RoutePreview.INK)
				draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -3) * k, fp + Vector2(3, 2.5) * k, fp + Vector2(-3, 2.5) * k]), Color(1, 0.85, 0.2))
			elif t == "rhythm":
				draw_circle(fp, 2.4 * k, RoutePreview.INK)
			elif t in RoutePreview.BRIDGE_TYPES:
				draw_rect(Rect2(fp - Vector2(3.5, 3.5) * k, Vector2(7, 7) * k), RoutePreview.INK)
			label.call(fp + Vector2(9, 4) * k, String(RoutePreview.NAMES.get(t, t.to_upper())), RoutePreview.INK)
		for dr in data["drops"]:
			var di: int = mini(int(dr[1]), n - 1)
			var dp := _w(Vector2(float(X[di]), float(Z[di])))
			if dp.x < -20 or dp.x > size.x + 20: continue
			draw_colored_polygon(PackedVector2Array([dp + Vector2(-6, -5) * k, dp + Vector2(6, -5) * k, dp + Vector2(0, 6) * k]), RoutePreview.TRAIL_C)
			label.call(dp + Vector2(9, 4) * k, "CLIFF DROP", RoutePreview.TRAIL_C)
		var sp := _w(Vector2(float(X[0]), float(Z[0])))
		draw_circle(sp, 6.0, Color("2f9e58"))
		draw_circle(sp, 6.0, Color.WHITE, false, 1.5)
		draw_string(font, sp + Vector2(10, -8), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RoutePreview.INK)
		draw_rect(Rect2(Vector2.ZERO, size), Color(RoutePreview.INK, 0.35), false, 1.0)
		draw_string(font, Vector2(8, 16), "DRAG TO MOVE  ·  WHEEL TO ZOOM  ·  DOUBLE CLICK: WHOLE TRAIL / BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(RoutePreview.INK, 0.6))

class_name PaperMap
extends PaperSheet
## The paper trail map (M): a folded map comes up in front of you and unfolds (PaperSheet) to a printed 2D
## topo map of the land, north up. Two layers on the paper:
##  - the world (`World`, set_content): 1.6 x 1 km around where it was printed - the real ground colours washed
##    out + hill shade, 5 m contours (25 m bold), water, a 100 m grid, the trail in red dashes, jumps, the bit you
##    rode, YOU ARE HERE. It scrolls under the paper (left stick / WASD / drag: travel the world on it) and zooms
##    (RT / LT / Q / E / wheel: only the print, the sheet always stays fully in view). Scroll off its edge and it
##    is printed again around the new view (~0.4 s).
##  - the frame (`Frame`, the page, transparent): margin, neat lines, title block, legend, scale bar + scale (they
##    follow the zoom: reprinted when it settles), north arrow, and the cover on the outside.
## The ride is frozen while it is up (Game.open_map / close_map).
## Tests: BMX_MAP=secs opens it in an autotest, BMX_MAP_SHOTS=dir/prefix saves frames of the unfold,
## BMX_MAP_SCROLL=x,y holds the "left stick", BMX_MAP_ZOOM=z zooms the print.

const SHEET_W_M := 800.0         # metres of world across the sheet at zoom 1 (~1 : 1 000)
const SHEET_H_M := 500.0
const IW := 2048                 # the frame page + the cover strip under it
const IH := 1280
const CW := 512
const CH := 640
const C_W := 1600.0              # the world print (m) and its pixels (2.56 px/m)
const C_H := 1000.0
const C_IW := 4096
const C_IH := 2560
const GRID := 5.0                # height samples (m)
const CI := 5.0                  # contour interval (m)
const TRAVEL := 320.0            # m/s across the world at zoom 1, stick fully over

var game
var view_c := Vector2.ZERO       # the world (x, z) at the middle of the sheet (where you want to look)
var _shown_c := Vector2.ZERO     # ... as shown (kept inside the world print)
var _frame: Frame
var _world: World
var _world_vp: SubViewport
var _world_o := Vector2(INF, INF)   # world (x, z) of the world print's top-left
var _world_seed := -1
var _printing := false
var _frame_zoom := 1.0
var _frame_t := 0.0
var _frame_busy := false


func _ready() -> void:
	super._ready()
	cols = 4; rows = 2
	panel = Vector2(0.21, 0.2625)    # 0.84 x 0.525 m, the aspect of the print
	shots = OS.get_environment("BMX_MAP_SHOTS")
	sound_stream = load("res://assets/audio/map_unfold_gravel.ogg")   # the user's pick: gravel crunch for the unfold
	sound_db = -4.0
	tempo = 0.4                       # unfolds at an easy pace (~1.6 s), still springy
	handheld = true                   # right stick tilts it, triggers zoom the print, left stick travels
	page_alpha = true                 # the frame is printed over the world
	setup(Vector2i(IW, IH), Vector2i(CW, CH))
	_frame = Frame.new()
	_frame.size = Vector2(IW, IH + CH)
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	content.add_child(_frame)
	_world_vp = SubViewport.new()
	_world_vp.size = Vector2i(C_IW, C_IH)
	_world_vp.disable_3d = true
	_world_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_world_vp)
	_world = World.new()
	_world.size = Vector2(C_IW, C_IH)
	_world.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_world_vp.add_child(_world)
	if OS.get_environment("BMX_MAP_SCROLL") != "":
		var sv := OS.get_environment("BMX_MAP_SCROLL").split(",")
		test_scroll = Vector2(float(sv[0]), float(sv[1]))


## print what's needed, then unfold - centred on you
func show_map() -> void:
	if busy() or _printing: return
	_printing = true
	var here := Vector2(game.phys.x, game.phys.z)
	view_c = here; _shown_c = here
	var t0 := Time.get_ticks_usec()
	if _world_seed != GameState.seed or not _view_inside(here, 1.0) or here.distance_to(_world_o + Vector2(C_W, C_H) * 0.5) > 60.0:
		await _print_world(here)
	_frame.setup_from(game, 1.0)
	await bake()
	_frame_zoom = 1.0
	_printing = false
	print("PAPERMAP printed in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	open()
	if OS.get_environment("BMX_MAP_ZOOM") != "": _zoom_t = clampf(float(OS.get_environment("BMX_MAP_ZOOM")), ZOOM_MIN, ZOOM_MAX)
	_update_rect()


func _print_world(centre: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	_world_o = centre - Vector2(C_W, C_H) * 0.5
	_world.build(game, _world_o)
	_world_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _world_vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	set_content(ImageTexture.create_from_image(img), Rect2(0, 0, 1, 1))
	_world_seed = GameState.seed
	print("PAPERMAP world printed in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))


## is the view (around c, at zoom z) inside the world print?
func _view_inside(c: Vector2, z: float) -> bool:
	if _world_o.x == INF: return false
	var h := Vector2(SHEET_W_M, SHEET_H_M) / z * 0.5
	return c.x - h.x >= _world_o.x - 0.5 and c.y - h.y >= _world_o.y - 0.5 and c.x + h.x <= _world_o.x + C_W + 0.5 and c.y + h.y <= _world_o.y + C_H + 0.5


func _scroll(amount: Vector2, drag_m: bool) -> void:
	if drag_m:   # metres on the sheet -> metres of world
		amount *= SHEET_W_M / _zoom / (cols * panel.x)
	else:
		amount *= TRAVEL
	view_c += Vector2(amount.x, -amount.y)   # up the sheet = north = -z


func _process(dt: float) -> void:
	super._process(dt)
	if state == 0: return
	_update_rect()
	# the scale bar / title follow the zoom: reprint the frame when it has settled somewhere new
	_frame_t += minf(dt, 0.05) if dt > 0.0 else 0.016
	if not _frame_busy and not _printing and absf(_zoom - _frame_zoom) > 0.03 and absf(_zoom - _zoom_t) < 0.02 and _frame_t > 0.25:
		_rebake_frame()


func _rebake_frame() -> void:
	_frame_busy = true
	_frame_t = 0.0
	_frame_zoom = _zoom
	_frame.setup_from(game, _zoom)
	await bake()
	_frame_busy = false


## where the world print sits on the sheet; scrolled off it -> print the world again around the view
func _update_rect() -> void:
	if _world_o.x == INF: return
	var half := Vector2(SHEET_W_M, SHEET_H_M) / _zoom * 0.5
	var lo := _world_o + half
	var hi := _world_o + Vector2(C_W, C_H) - half
	_shown_c = Vector2(clampf(view_c.x, lo.x, maxf(lo.x, hi.x)), clampf(view_c.y, lo.y, maxf(lo.y, hi.y)))
	if lo.x > hi.x: _shown_c.x = _world_o.x + C_W * 0.5
	if lo.y > hi.y: _shown_c.y = _world_o.y + C_H * 0.5
	if _shown_c.distance_to(view_c) > 1.0 and not _printing and state != 3:   # the view keeps the wish; print around it
		_reprint_world(view_c)
	var tl := _shown_c - half
	set_content_rect(Rect2((tl - _world_o) / Vector2(C_W, C_H), half * 2.0 / Vector2(C_W, C_H)))


func _reprint_world(c: Vector2) -> void:
	_printing = true
	await _print_world(c)
	_printing = false


class Ink extends Control:
	## shared: colours, fonts, dashed lines, labels, boxes
	const INK := Color("1d1f22")
	const CONTOUR := Color(0.62, 0.40, 0.20)
	const WATER := Color(0.55, 0.74, 0.86)
	const TRAIL := Color("d22b25")
	const GRID_C := Color(0.25, 0.42, 0.62)
	var font: Font
	var font_b: Font

	func _init() -> void:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial"])
		f.font_weight = 500
		font = f
		var fb := SystemFont.new()
		fb.font_names = f.font_names
		fb.font_weight = 800
		font_b = fb

	func _dashes(line: PackedVector2Array, on: float, off: float, c: Color, w: float) -> void:
		var acc := 0.0
		var drawing := true
		for i in line.size() - 1:
			var a := line[i]; var b := line[i + 1]
			var seg := a.distance_to(b)
			var pos := 0.0
			while pos < seg:
				var left := (on if drawing else off) - acc
				var step := minf(left, seg - pos)
				if drawing:
					draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), c, w, true)
				pos += step; acc += step
				if acc >= (on if drawing else off) - 0.001:
					acc = 0.0; drawing = not drawing

	func _label(p: Vector2, s: String, size: int, c := INK, f: Font = null) -> void:
		var ff := f if f else font
		draw_string_outline(ff, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, 0.85))
		draw_string(ff, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

	func _box(r: Rect2) -> void:
		draw_rect(r, Color(1, 1, 0.97, 0.93))
		draw_rect(r, INK, false, 2.0)



class Frame extends Ink:
	## the page: transparent where the world shows through; margin, neat lines, title, legend, scale, north;
	## the cover in the strip under it
	var biome := ""
	var seed_n := 0
	var zoom := 1.0

	func setup_from(game, z: float) -> void:
		biome = game.terrain.biome_name(game.phys.x, game.phys.z)
		seed_n = GameState.seed
		zoom = z
		queue_redraw()

	func scale_text() -> String:
		var n := SHEET_W_M / zoom / 0.84
		var mag := pow(10.0, floorf(log(n) / log(10.0)) - 1.0)
		var r := int(roundf(n / mag) * mag)
		var t := str(r)
		if r >= 1000: t = "%s %03d" % [str(r / 1000), r % 1000]
		return "1 : " + t

	func _draw() -> void:
		var m := 26.0
		var W := float(IW); var H := float(IH)
		# white margin round the map (opaque), the inside left clear
		var paper := Color.WHITE
		draw_rect(Rect2(0, 0, W, m + 8), paper)
		draw_rect(Rect2(0, H - m - 8, W, m + 8), paper)
		draw_rect(Rect2(0, 0, m + 8, H), paper)
		draw_rect(Rect2(W - m - 8, 0, m + 8, H), paper)
		draw_rect(Rect2(m, m, W - 2 * m, H - 2 * m), INK, false, 3.0)
		draw_rect(Rect2(m + 8, m + 8, W - 2 * m - 16, H - 2 * m - 16), INK, false, 1.2)
		_title_block(Vector2(m + 40, m + 40))
		_legend(Vector2(W - m - 400, H - m - 300))
		_scale_bar(Vector2(m + 50, H - m - 70))
		_north(Vector2(W - m - 90, m + 110))
		_cover(Rect2(0, IH, CW, CH))

	func _title_block(p: Vector2) -> void:
		_box(Rect2(p, Vector2(470, 190)))
		draw_rect(Rect2(p, Vector2(470, 14)), TRAIL)
		draw_string(font_b, p + Vector2(22, 76), "MINI BMX", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, INK)
		draw_string(font_b, p + Vector2(24, 112), "TRAIL MAP  ·  " + biome.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TRAIL)
		draw_string(font, p + Vector2(24, 146), "Sheet %d  ·  %s  ·  contours 5 m" % [seed_n, scale_text()], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		draw_string(font, p + Vector2(24, 172), "Grid 100 m  ·  heights in metres", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(INK, 0.7))

	func _legend(p: Vector2) -> void:
		_box(Rect2(p, Vector2(370, 262)))
		draw_string(font_b, p + Vector2(20, 38), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
		var y := p.y + 70
		var x0 := p.x + 22
		var x1 := p.x + 100
		draw_line(Vector2(x0, y), Vector2(x0 + 60, y), Color.WHITE, 11)
		_dashes(PackedVector2Array([Vector2(x0, y), Vector2(x0 + 60, y)]), 18, 10, TRAIL, 6)
		draw_string(font, Vector2(x1, y + 7), "Trail", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		y += 36
		draw_line(Vector2(x0, y), Vector2(x0 + 60, y), Color(0.45, 0.12, 0.55, 0.85), 3)
		draw_string(font, Vector2(x1, y + 7), "Ridden (last 90 s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		y += 36
		draw_line(Vector2(x0, y - 4), Vector2(x0 + 60, y - 4), Color(CONTOUR, 0.85), 2.6)
		draw_line(Vector2(x0, y + 5), Vector2(x0 + 60, y + 5), Color(CONTOUR, 0.5), 1.4)
		draw_string(font, Vector2(x1, y + 7), "Contours 25 m / 5 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		y += 36
		draw_rect(Rect2(x0, y - 10, 60, 20), WATER)
		draw_rect(Rect2(x0, y - 10, 60, 20), Color(0.2, 0.45, 0.68), false, 2)
		draw_string(font, Vector2(x1, y + 7), "Water", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		y += 36
		var jp := Vector2(x0 + 30, y)
		draw_colored_polygon(PackedVector2Array([jp + Vector2(0, -11), jp + Vector2(10, 7), jp + Vector2(-10, 7)]), INK)
		draw_colored_polygon(PackedVector2Array([jp + Vector2(0, -5), jp + Vector2(5, 4), jp + Vector2(-5, 4)]), Color(1, 0.85, 0.2))
		draw_string(font, Vector2(x1, y + 7), "Jump / feature", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)

	func _scale_bar(p: Vector2) -> void:
		var k := IW * zoom / SHEET_W_M   # page px per metre
		var step := 100.0
		for s in [10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0]:   # 3 blocks of ~230 px
			if absf(s * k - 230.0) < absf(step * k - 230.0): step = s
		var bw := step * k
		_box(Rect2(p - Vector2(20, 44), Vector2(3 * bw + 100, 80)))
		for i in 3:
			draw_rect(Rect2(p + Vector2(i * bw, 0), Vector2(bw, 12)), INK if i % 2 == 0 else Color.WHITE)
		draw_rect(Rect2(p, Vector2(3 * bw, 12)), INK, false, 2)
		for i in 4:
			draw_string(font, p + Vector2(i * bw - 8, -10), "%d" % int(i * step), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
		draw_string(font, p + Vector2(3 * bw + 14, 12), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)

	func _north(c: Vector2) -> void:
		draw_circle(c, 58, Color(1, 1, 0.97, 0.9))
		draw_arc(c, 58, 0, TAU, 64, INK, 2.0, true)
		draw_arc(c, 50, 0, TAU, 64, INK, 1.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -46), c + Vector2(14, 8), c]), INK)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -46), c, c + Vector2(-14, 8)]), Color(INK, 0.35))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, 40), c + Vector2(-10, 4), c + Vector2(10, 4)]), Color(INK, 0.2))
		draw_string(font_b, c + Vector2(-11, -64), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)

	func _cover(r: Rect2) -> void:
		var green := Color("26443a")
		draw_rect(r, green)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 120)), Color("f2efe4"))
		draw_rect(Rect2(r.position + Vector2(0, 120), Vector2(r.size.x, 12)), TRAIL)
		draw_string(font_b, r.position + Vector2(32, 82), "MINI BMX", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, INK)
		draw_string(font_b, r.position + Vector2(34, 200), "TRAIL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color("f2efe4"))
		draw_string(font, r.position + Vector2(36, 240), biome.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.84, 0.5))
		# mountains + a dashed trail down them
		var base := r.position + Vector2(0, 470)
		var hills := PackedVector2Array([base + Vector2(0, 0), base + Vector2(90, -120), base + Vector2(150, -70),
			base + Vector2(250, -200), base + Vector2(340, -90), base + Vector2(410, -140), base + Vector2(CW, -40), base + Vector2(CW, 60), base + Vector2(0, 60)])
		draw_colored_polygon(hills, Color("3d6b54"))
		draw_colored_polygon(PackedVector2Array([base + Vector2(250, -200), base + Vector2(282, -158), base + Vector2(262, -162), base + Vector2(240, -150), base + Vector2(222, -160)]), Color("f2efe4"))
		_dashes(PackedVector2Array([base + Vector2(250, -196), base + Vector2(300, -120), base + Vector2(230, -60), base + Vector2(330, 10), base + Vector2(280, 58)]), 14, 8, Color(1, 0.84, 0.5), 5)
		draw_rect(Rect2(r.position + Vector2(0, 530), Vector2(r.size.x, 110)), Color("f2efe4"))
		draw_string(font_b, r.position + Vector2(34, 578), "1 : 1 000", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, INK)
		draw_string(font, r.position + Vector2(34, 614), "Sheet %d  ·  contours 5 m" % seed_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.75))


class World extends Ink:
	## the world print: C_IW x C_IH px over C_W x C_H m, north up
	var land: ImageTexture
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var water_lines := PackedVector2Array()
	var trail := []                      # polylines (px)
	var ridden := PackedVector2Array()
	var jumps := []                      # [px, name]
	var me := Vector2.ZERO
	var heading := Vector2.UP
	var origin := Vector2.ZERO           # world (x, z) of the top-left
	var elev := 0.0

	func px(x: float, z: float) -> Vector2:
		return Vector2((x - origin.x) * C_IW / C_W, (z - origin.y) * C_IH / C_H)

	func build(game, o: Vector2) -> void:
		var terrain = game.terrain
		var st = game.phys
		origin = o
		var nx := int(C_W / GRID) + 1
		var nz := int(C_H / GRID) + 1
		var h := PackedFloat32Array(); h.resize(nx * nz)
		for j in nz:
			var z := origin.y + j * GRID
			for i in nx:
				h[j * nx + i] = terrain.height(origin.x + i * GRID, z)
		# land: the real ground colour (every 10 m, smoothed), washed out towards the paper, times a hill shade
		# from the north-west (every 5 m); water flat blue
		var paper := Color(0.97, 0.96, 0.9)
		var light := Vector3(-0.55, 0.62, -0.55).normalized()
		var wl := Terrain.WATER
		var cx := (nx + 1) / 2; var cz := (nz + 1) / 2
		var cimg := Image.create(cx, cz, false, Image.FORMAT_RGB8)
		for j in cz:
			for i in cx:
				var hc := h[mini(j * 2, nz - 1) * nx + mini(i * 2, nx - 1)]
				var g: Color = WATER.lerp(paper, 0.15) if hc < wl - 0.05 else terrain.ground_color(origin.x + i * 2 * GRID, origin.y + j * 2 * GRID).lerp(paper, 0.5)
				cimg.set_pixel(i, j, g)
		cimg.resize(nx, nz, Image.INTERPOLATE_BILINEAR)
		var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
		for j in nz:
			for i in nx:
				var hc := h[j * nx + i]
				if hc < wl - 0.05:
					img.set_pixel(i, j, WATER.lerp(paper, 0.15)); continue
				var hx := h[j * nx + mini(i + 1, nx - 1)] - h[j * nx + maxi(i - 1, 0)]
				var hz := h[mini(j + 1, nz - 1) * nx + i] - h[maxi(j - 1, 0) * nx + i]
				var n := Vector3(-hx, 2.0 * GRID, -hz).normalized()
				var sh := clampf(n.dot(light), 0.0, 1.0)
				var c := cimg.get_pixel(i, j)
				img.set_pixel(i, j, (Color(c.r, c.g, c.b) * (0.62 + 0.5 * sh)).clamp())
		land = ImageTexture.create_from_image(img)
		# contours + the shore (marching squares)
		minor = PackedVector2Array(); major = PackedVector2Array(); water_lines = PackedVector2Array()
		var sx := float(C_IW) / (nx - 1)
		var sz := float(C_IH) / (nz - 1)
		for j in nz - 1:
			for i in nx - 1:
				var h0 := h[j * nx + i]; var h1 := h[j * nx + i + 1]
				var h2 := h[(j + 1) * nx + i + 1]; var h3 := h[(j + 1) * nx + i]
				var lo := minf(minf(h0, h1), minf(h2, h3)); var hi := maxf(maxf(h0, h1), maxf(h2, h3))
				var levels := []
				var lv := ceilf(lo / CI) * CI
				while lv < hi:
					levels.append(lv); lv += CI
				if lo < wl - 0.05 and hi >= wl - 0.05: levels.append(wl - 0.05)
				for L in levels:
					var pts := PackedVector2Array()
					var x := i * sx; var z := j * sz
					if (h0 < L) != (h1 < L): pts.append(Vector2(x + sx * (L - h0) / (h1 - h0), z))
					if (h1 < L) != (h2 < L): pts.append(Vector2(x + sx, z + sz * (L - h1) / (h2 - h1)))
					if (h3 < L) != (h2 < L): pts.append(Vector2(x + sx * (L - h3) / (h2 - h3), z + sz))
					if (h0 < L) != (h3 < L): pts.append(Vector2(x, z + sz * (L - h0) / (h3 - h0)))
					if pts.size() < 2: continue
					if L == wl - 0.05: water_lines.append_array(pts)   # (packed arrays copy on assignment:
					elif L < wl: continue                               #  append to the members themselves)
					elif is_equal_approx(fposmod(L, CI * 5), 0.0): major.append_array(pts)
					else: minor.append_array(pts)
		# the trail, the jumps on it, the bit you rode, you
		trail = []
		jumps = []
		var tc = terrain.field.course if terrain.field else null
		var rect := Rect2(-40, -40, C_IW + 80, C_IH + 80)
		if tc and tc.n > 1:
			var line := PackedVector2Array()
			for i in tc.n:
				var p := px(tc.X[i], tc.Z[i])
				if rect.has_point(p): line.append(p)
				elif line.size() > 0:
					if line.size() > 1: trail.append(line)
					line = PackedVector2Array()
			if line.size() > 1: trail.append(line)
			var names: Dictionary = game.hud.FEAT_NAMES if game.hud else {}
			var last := Vector2(INF, INF)
			for f in terrain.field.route_feats:
				var ci := int(f.s / TrailCourse.STEP)
				if ci < 0 or ci >= tc.n: continue
				var p := px(tc.X[ci], tc.Z[ci])
				if Rect2(0, 0, C_IW, C_IH).has_point(p) and p.distance_to(last) > 60.0:
					var nm: String = names.get(f.type, String(f.type).to_upper())
					jumps.append([p, nm.capitalize()])
					last = p
		ridden = PackedVector2Array()
		if game.hud and "track_hist" in game.hud:
			for q in game.hud.track_hist: ridden.append(px(q.x, q.y))
		me = px(st.x, st.z)
		heading = Vector2(cos(st.heading), -sin(st.heading))   # (x, z): as the bike computer's map
		elev = st.y
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0, 0, C_IW, C_IH), Color.WHITE)
		draw_texture_rect(land, Rect2(0, 0, C_IW, C_IH), false)
		if minor.size() > 1: draw_multiline(minor, Color(CONTOUR, 0.5), 1.4, true)
		if major.size() > 1: draw_multiline(major, Color(CONTOUR, 0.85), 2.6, true)
		if water_lines.size() > 1: draw_multiline(water_lines, Color(0.2, 0.45, 0.68), 2.2, true)
		# grid, 100 m, numbered along every line
		var gstep := 100.0
		var x := ceilf(origin.x / gstep) * gstep
		while x < origin.x + C_W:
			var p := px(x, origin.y).x
			draw_line(Vector2(p, 0), Vector2(p, C_IH), Color(GRID_C, 0.28), 1.5)
			var zz := ceilf(origin.y / 500.0) * 500.0
			while zz < origin.y + C_H:
				draw_string(font, Vector2(p + 4, px(x, zz).y - 4), "%d" % int(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(GRID_C, 0.75))
				zz += 500.0
			x += gstep
		var z := ceilf(origin.y / gstep) * gstep
		while z < origin.y + C_H:
			var p := px(origin.x, z).y
			draw_line(Vector2(0, p), Vector2(C_IW, p), Color(GRID_C, 0.28), 1.5)
			var xx := ceilf(origin.x / 500.0) * 500.0
			while xx < origin.x + C_W:
				draw_string(font, Vector2(px(xx, z).x + 4, p + 18), "%d" % int(-z), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(GRID_C, 0.75))
				xx += 500.0
			z += gstep
		# the trail: white casing, red dashes
		for line in trail:
			draw_polyline(line, Color(1, 1, 1, 0.95), 11.0, true)
		for line in trail:
			draw_polyline(line, Color(TRAIL, 0.35), 3.0, true)
			_dashes(line, 18.0, 10.0, TRAIL, 6.0)
		if ridden.size() > 1:
			draw_polyline(ridden, Color(0.45, 0.12, 0.55, 0.85), 3.0, true)
		for jp in jumps:
			var p: Vector2 = jp[0]
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(10, 7), p + Vector2(-10, 7)]), INK)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 4), p + Vector2(-5, 4)]), Color(1, 0.85, 0.2))
			_label(p + Vector2(14, 6), jp[1], 19)
		# you are here
		var hd := heading.normalized()
		var sd := Vector2(-hd.y, hd.x)
		draw_circle(me, 30, Color(TRAIL, 0.18))
		draw_arc(me, 30, 0, TAU, 48, TRAIL, 3.5, true)
		draw_colored_polygon(PackedVector2Array([me + hd * 22, me - hd * 13 + sd * 13, me - hd * 5, me - hd * 13 - sd * 13]), TRAIL)
		_label(me + Vector2(38, -10), "YOU ARE HERE", 24, TRAIL, font_b)
		_label(me + Vector2(38, 18), "%d m" % roundi(elev), 18, INK)

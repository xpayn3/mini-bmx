class_name PaperMap
extends PaperSheet
## The paper trail map (M): a folded map comes up in front of you and unfolds (PaperSheet) to a printed 2D
## topo map of the land around you, north up: the real ground colours washed out and hill-shaded, 5 m contours
## (25 m bold), water, the trail in red dashes, jumps, the bit you rode, a 100 m grid, title block, legend,
## scale bar, north arrow, YOU ARE HERE, and a cover on the outside. Printed once per opening, only again when
## you've moved 60 m or changed world. The ride is frozen while it is up (Game.open_map / close_map).
## Tests: BMX_MAP=secs opens it in an autotest, BMX_MAP_SHOTS=dir/prefix saves frames of the unfold.

const MAP_W := 800.0             # metres across the printed map
const MAP_H := 500.0
const IW := 2048                 # printed front + the cover strip under it
const IH := 1280
const CW := 512
const CH := 640
const GRID := 4.0                # height samples (m)
const CI := 5.0                  # contour interval (m)

var game
var _printer: Printer
var _printed_at := Vector2(INF, INF)
var _printed_seed := -1
var _printing := false


func _ready() -> void:
	super._ready()
	cols = 4; rows = 2
	panel = Vector2(0.21, 0.2625)    # 0.84 x 0.525 m, the aspect of the print
	shots = OS.get_environment("BMX_MAP_SHOTS")
	setup(Vector2i(IW, IH), Vector2i(CW, CH))
	_printer = Printer.new()
	_printer.size = Vector2(IW, IH + CH)
	_printer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	content.add_child(_printer)


## print (if needed), then unfold
func show_map() -> void:
	if busy() or _printing: return
	var here := Vector2(game.phys.x, game.phys.z)
	if here.distance_to(_printed_at) > 60.0 or _printed_seed != GameState.seed:
		_printing = true
		var t0 := Time.get_ticks_usec()
		_printer.build(game, here)
		await bake()
		_printed_at = here; _printed_seed = GameState.seed
		_printing = false
		print("PAPERMAP printed in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	open()


class Printer extends Control:
	## the printed sheet: IW x IH map (north up, centred on you) + a CW x CH cover under it
	const INK := Color("1d1f22")
	const CONTOUR := Color(0.62, 0.40, 0.20)
	const WATER := Color(0.55, 0.74, 0.86)
	const TRAIL := Color("d22b25")
	const GRID_C := Color(0.25, 0.42, 0.62)
	var land: ImageTexture
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var water_lines := PackedVector2Array()
	var trail := []                      # polylines (px)
	var ridden := PackedVector2Array()
	var jumps := []                      # [px, name]
	var me := Vector2.ZERO
	var heading := Vector2.UP
	var origin := Vector2.ZERO           # world (x, z) of the image's top-left
	var biome := ""
	var seed_n := 0
	var elev := 0.0
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

	func px(x: float, z: float) -> Vector2:
		return Vector2((x - origin.x) * IW / MAP_W, (z - origin.y) * IH / MAP_H)

	func build(game, centre: Vector2) -> void:
		var terrain = game.terrain
		var st = game.phys
		origin = centre - Vector2(MAP_W, MAP_H) * 0.5
		var nx := int(MAP_W / GRID) + 1
		var nz := int(MAP_H / GRID) + 1
		var h := PackedFloat32Array(); h.resize(nx * nz)
		for j in nz:
			var z := origin.y + j * GRID
			for i in nx:
				h[j * nx + i] = terrain.height(origin.x + i * GRID, z)
		# land: the real ground colour, washed out towards the paper, hill-shaded from the north-west
		var img := Image.create(nx, nz, false, Image.FORMAT_RGB8)
		var paper := Color(0.97, 0.96, 0.9)
		var light := Vector3(-0.55, 0.62, -0.55).normalized()   # (x, up, z): from the north-west, high
		var wl := Terrain.WATER
		var cstep := 1   # ground colour at every sample
		var cols := {}
		for j in nz:
			var z := origin.y + j * GRID
			for i in nx:
				var x := origin.x + i * GRID
				var hc := h[j * nx + i]
				if hc < wl - 0.05:
					img.set_pixel(i, j, WATER.lerp(paper, 0.15)); continue
				var ck := Vector2i(i / cstep, j / cstep)
				var g: Color = cols.get(ck, Color(0, 0, 0, 0))
				if g.a == 0.0:
					g = terrain.ground_color(origin.x + ck.x * cstep * GRID, origin.y + ck.y * cstep * GRID)
					g.a = 1.0; cols[ck] = g
				var hx := h[j * nx + mini(i + 1, nx - 1)] - h[j * nx + maxi(i - 1, 0)]
				var hz := h[mini(j + 1, nz - 1) * nx + i] - h[maxi(j - 1, 0) * nx + i]
				var n := Vector3(-hx, 2.0 * GRID, -hz).normalized()
				var sh := clampf(n.dot(light), 0.0, 1.0)
				var c := g.lerp(paper, 0.5)
				c = Color(c.r, c.g, c.b) * (0.62 + 0.5 * sh)
				img.set_pixel(i, j, c.clamp())
		land = ImageTexture.create_from_image(img)
		# contours + the shore (marching squares)
		minor = PackedVector2Array(); major = PackedVector2Array(); water_lines = PackedVector2Array()
		var sx := float(IW) / (nx - 1)
		var sz := float(IH) / (nz - 1)
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
		# the trail, the jumps on it, the bit you rode
		trail = []
		jumps = []
		var tc = terrain.field.course if terrain.field else null
		var rect := Rect2(-40, -40, IW + 80, IH + 80)
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
				if Rect2(30, 30, IW - 60, IH - 60).has_point(p) and p.distance_to(last) > 60.0:
					var nm: String = names.get(f.type, String(f.type).to_upper())
					jumps.append([p, nm.capitalize()])
					last = p
		ridden = PackedVector2Array()
		if game.hud and "track_hist" in game.hud:
			for q in game.hud.track_hist: ridden.append(px(q.x, q.y))
		me = px(st.x, st.z)
		heading = Vector2(cos(st.heading), -sin(st.heading))   # (x, z): as the bike computer's map
		biome = terrain.biome_name(st.x, st.z)
		seed_n = GameState.seed
		elev = st.y
		queue_redraw()

	func _draw() -> void:
		# ----- the map
		draw_rect(Rect2(0, 0, IW, IH), Color.WHITE)
		draw_texture_rect(land, Rect2(0, 0, IW, IH), false)
		draw_rect(Rect2(0, IH, IW, CH), Color.WHITE)
		if minor.size() > 1: draw_multiline(minor, Color(CONTOUR, 0.5), 1.4, true)
		if major.size() > 1: draw_multiline(major, Color(CONTOUR, 0.85), 2.6, true)
		if water_lines.size() > 1: draw_multiline(water_lines, Color(0.2, 0.45, 0.68), 2.2, true)
		# grid, 100 m
		var gstep := 100.0
		var gx0 := ceilf(origin.x / gstep) * gstep
		var x := gx0
		while x < origin.x + MAP_W:
			var p := px(x, origin.y).x
			draw_line(Vector2(p, 0), Vector2(p, IH), Color(GRID_C, 0.28), 1.5)
			draw_string(font, Vector2(p + 4, IH - 52), "%d" % int(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(GRID_C, 0.8))
			x += gstep
		var z := ceilf(origin.y / gstep) * gstep
		while z < origin.y + MAP_H:
			var p := px(origin.x, z).y
			draw_line(Vector2(0, p), Vector2(IW, p), Color(GRID_C, 0.28), 1.5)
			draw_string(font, Vector2(52, p - 4), "%d" % int(-z), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(GRID_C, 0.8))
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
		# neat line + margin
		var m := 26.0
		draw_rect(Rect2(m, m, IW - 2 * m, IH - 2 * m), INK, false, 3.0)
		draw_rect(Rect2(m + 8, m + 8, IW - 2 * m - 16, IH - 2 * m - 16), INK, false, 1.2)
		_title_block(Vector2(m + 40, m + 40))
		_legend(Vector2(IW - m - 400, IH - m - 300))
		_scale_bar(Vector2(m + 50, IH - m - 70))
		_north(Vector2(IW - m - 90, m + 110))
		# ----- the cover (printed on the back of one panel)
		_cover(Rect2(0, IH, CW, CH))

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

	func _title_block(p: Vector2) -> void:
		_box(Rect2(p, Vector2(470, 190)))
		draw_rect(Rect2(p, Vector2(470, 14)), TRAIL)
		draw_string(font_b, p + Vector2(22, 76), "MINI BMX", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, INK)
		draw_string(font_b, p + Vector2(24, 112), "TRAIL MAP  ·  " + biome.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TRAIL)
		draw_string(font, p + Vector2(24, 146), "Sheet %d  ·  1 : 1 000  ·  contours 5 m" % seed_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
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
		var k := IW / MAP_W
		_box(Rect2(p - Vector2(20, 44), Vector2(300 * k + 100, 80)))
		for i in 3:
			draw_rect(Rect2(p + Vector2(i * 100 * k, 0), Vector2(100 * k, 12)), INK if i % 2 == 0 else Color.WHITE)
		draw_rect(Rect2(p, Vector2(300 * k, 12)), INK, false, 2)
		for i in 4:
			draw_string(font, p + Vector2(i * 100 * k - 8, -10), "%d" % (i * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
		draw_string(font, p + Vector2(300 * k + 14, 12), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)

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

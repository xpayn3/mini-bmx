class_name CardFace
extends Control
## The flat faces of the collectible cards, in the CycleIQ style (ported from its badges3d.js): a dark dithered card with a diagonal lattice, a
## coloured ribbon repeating the name along the top, the badge shape in the middle (the 3D viewer floats the real extruded shape over it), the
## name, a line of text and EARNED / LOCKED. Kinds: "card" (a collectible), "badge" (an achievement), "rider" (the athlete card: a giant level
## numeral, name, XP bar, three stats) and "rider_back" (today's date), "back" (the card back), and "mask" (the foil pattern: white where the
## holo shows, drawn by `holo` type: chevron, diamond, bolt, ripple, grid, wave, rays).
## `texture(kind, id, owned, host)` renders one face once into a texture (cached) for the grid thumbnails and the 3D viewer.
## 520 x 752 = the CycleIQ card's 1.8 : 2.6.

const W := 520
const H := 752
var kind := "card"
var card_id := ""
var got := true
var number := 1
var total := 1
## the athlete card's numbers, set by the profile before it asks for the texture
static var rider := {"name": "RIDER", "level": 1, "title": "ROOKIE", "xp": 0.0, "xp_text": "", "stats": [["0", "RIDES"], ["0", "KM"], ["0", "TOP KM/H"]]}

static var _cache := {}

static func texture(kind_: String, id: String, owned: bool, host: Node) -> Texture2D:
	var key := "%s:%s:%d" % [kind_, id, 1 if owned else 0]
	if kind_.begins_with("rider"): key += ":%s:%d:%s" % [rider.name, int(rider.level), str(rider.stats)]
	if _cache.has(key): return _cache[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var f := CardFace.new()
	f.kind = kind_; f.card_id = id; f.got = owned
	var ids: Array = Collection.CARDS.keys()
	f.number = ids.find(id) + 1; f.total = ids.size()
	f.size = Vector2(W, H)
	vp.add_child(f)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

func _look() -> Dictionary:
	if kind == "badge": return Collection.badge_look(card_id)
	if kind == "card": return Collection.card_look(card_id)
	return {}

func _draw() -> void:
	match kind:
		"back": _back()
		"mask": _mask()
		"rider": _rider_front()
		"rider_mask": _rider_mask()
		"rider_back": _rider_back()
		_: _face()

# ---------------------------------------------------------------- shared bits
func _background(seed_s: String) -> void:
	draw_rect(Rect2(0, 0, W, H), Color("080808"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_s)
	for i in 1400:   # the dither
		var v := rng.randf_range(0.0, 0.07)
		draw_rect(Rect2(rng.randf() * W, rng.randf() * H, 2, 2), Color(1, 1, 1, v))
	for i in range(-H, W, 30):   # the lattice
		draw_line(Vector2(i, 0), Vector2(i + H, H), Color(1, 1, 1, 0.05), 1.5)
		draw_line(Vector2(i + H, 0), Vector2(i, H), Color(1, 1, 1, 0.05), 1.5)

func _ribbon(text: String, col: Color) -> void:
	draw_rect(Rect2(0, 30, W, 46), col)
	var f := UITheme.display_font(900, 0.2)
	var s := (text + "   ·   ").repeat(10)
	draw_string(f, Vector2(-6, 64), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0, 0, 0, 0.62))
	draw_string(f, Vector2(-5.5, 64), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0, 0, 0, 0.62))

func _centered(font: Font, text: String, y: float, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2((W - minf(w, W - 40)) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, W - 40, size, col)

## a card shape drawn flat (the 3D viewer floats the real extruded one over it): card units -> pixels
func _flat_shape(shape: String, col: Color, accent: Color) -> void:
	var pts := Collection.shape_points(shape)
	var k := W / 1.8
	var c := Vector2(W * 0.5, H * 0.43)
	var px := PackedVector2Array()
	for p in pts: px.append(c + Vector2(p.x, -p.y) * k)
	var shade := PackedVector2Array()
	for p in px: shade.append(p + Vector2(18, 18))
	draw_colored_polygon(shade, Color(0, 0, 0, 0.5))
	draw_colored_polygon(px, col.darkened(0.25))
	var inner := PackedVector2Array()
	for p in px: inner.append(c + (p - c) * 0.84)
	draw_colored_polygon(inner, Color(col.lightened(0.15), 0.9))
	var closed := px.duplicate(); closed.append(px[0])
	draw_polyline(closed, accent, 4.0, true)

# ---------------------------------------------------------------- badge / collectible card
func _face() -> void:
	var look := _look()
	var col: Color = look.color if got else Color("4a5164")
	var acc: Color = look.accent if got else Color("6b7280")
	_background(card_id)
	_ribbon(String(look.label) if got else "LOCKED", col)
	_flat_shape(look.shape, col, acc)
	var body := UITheme.font(false)
	var disp := UITheme.display_font(900)
	var glyph := String(look.glyph) if got else "?"
	var gf: Font = UITheme.font(true)
	var gw := gf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 170).x
	draw_string(gf, Vector2((W - gw) * 0.5, H * 0.43 + 58), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 170, Color(1, 1, 1, 0.78) if got else Color(1, 1, 1, 0.18))
	_centered(disp, String(look.label) if got else "? ? ?", H * 0.79, 54, Color.WHITE if got else Color("5d667e"))
	var desc := String(look.desc) if got else String(look.get("need", look.desc))
	draw_multiline_string(body, Vector2(30, H * 0.79 + 40), desc, HORIZONTAL_ALIGNMENT_CENTER, W - 60, 26, 2, Color(acc, 0.9) if got else Color("7a8399"))
	_centered(body, ("EARNED" if got else "LOCKED") + "   ·   " + String(look.tag), H * 0.93, 20, Color(1, 1, 1, 0.28))

# ---------------------------------------------------------------- the foil pattern (white = holo shows)
func _mask() -> void:
	var pat := card_id
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	draw_rect(Rect2(0, 30, W, 46), Color(1, 1, 1, 0.5))   # the ribbon always shines
	var lw := 3.0
	var white := Color(1, 1, 1, 0.55)
	match pat:
		"chevron":
			for y in range(120, H - 80, 36):
				draw_polyline(PackedVector2Array([Vector2(0, y + 40), Vector2(W * 0.5, y), Vector2(W, y + 40)]), white, lw, true)
		"diamond":
			for i in range(-8, 12):
				draw_line(Vector2(i * 52, 90), Vector2(i * 52 + 600, 690), white, lw)
				draw_line(Vector2(i * 52 + 600, 90), Vector2(i * 52, 690), white, lw)
		"bolt":
			for x in range(-40, W, 56):
				var pts := PackedVector2Array()
				for j in 14: pts.append(Vector2(x + (22 if j % 2 == 0 else 0), 90 + j * 48))
				draw_polyline(pts, white, lw, true)
		"ripple":
			for r in range(40, 560, 36): draw_arc(Vector2(W * 0.5, H * 0.43), r, 0.0, TAU, 72, white, lw, true)
		"grid":
			for x in range(0, W, 40): draw_line(Vector2(x, 90), Vector2(x, H - 40), white, 2.0)
			for y in range(90, H, 40): draw_line(Vector2(0, y), Vector2(W, y), white, 2.0)
		"wave":
			for k in range(0, 14):
				var pts := PackedVector2Array()
				for x in range(0, W + 10, 10): pts.append(Vector2(x, 110 + k * 44 + sin(x * 0.03 + k * 0.6) * 14))
				draw_polyline(pts, white, lw, true)
		_:   # rays
			for i in 36:
				var a := TAU * i / 36.0
				draw_line(Vector2(W * 0.5, H * 0.43), Vector2(W * 0.5, H * 0.43) + Vector2(cos(a), sin(a)) * 700.0, white, 2.5)
	draw_rect(Rect2(5, 5, W - 10, H - 10), Color(1, 1, 1, 0.7), false, 8.0)   # a bright edge
	draw_rect(Rect2(0, H * 0.74, W, H), Color(0, 0, 0, 0.7))   # the text area stays calm

# ---------------------------------------------------------------- the athlete card
func _rider_front() -> void:
	var d: Dictionary = rider
	_background("rider" + String(d.name))
	var disp := UITheme.display_font(900)
	var body := UITheme.font(true)
	var acc := Tokens.ACCENT
	draw_string(disp, Vector2(W - 36 - disp.get_string_size("RUNOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x, 58), "RUNOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.35))
	_centered(disp, String(d.name), H * 0.17, 66, Color.WHITE)
	_centered(body, String(d.title), H * 0.17 + 48, 34, acc)
	# the giant level numeral, embossed in three layers
	var num := str(int(d.level))
	var size := 330 if num.length() < 3 else 250
	var nw := disp.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var nx := (W - nw) * 0.5
	var ny := H * 0.56 + size * 0.14
	draw_string(disp, Vector2(nx - 4, ny - 4), num, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.22))
	draw_string(disp, Vector2(nx + 5, ny + 5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.75))
	draw_string(disp, Vector2(nx, ny), num, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("3a4152"))
	draw_string(UITheme.font(false), Vector2(36, H * 0.4), "LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.4))
	# XP bar
	var bx := 50.0
	var by := H * 0.745
	var bw := W - 100.0
	draw_rect(Rect2(bx, by, bw, 18), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bx, by, bw * clampf(float(d.xp), 0.0, 1.0), 18), acc)
	draw_string(UITheme.font(false), Vector2(bx, by - 14), "LVL %d" % int(d.level), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.8))
	var xt := String(d.xp_text)
	draw_string(UITheme.font(false), Vector2(bx + bw - UITheme.font(false).get_string_size(xt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x, by - 14), xt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.55))
	# three stats
	var stats: Array = d.stats
	for i in stats.size():
		var cx := W * (0.2 + 0.3 * i)
		var sv := String(stats[i][0])
		var sw := disp.get_string_size(sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 50).x
		draw_string(disp, Vector2(cx - sw * 0.5, H * 0.88), sv, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
		var sl := String(stats[i][1])
		var lw := UITheme.font(false).get_string_size(sl, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(UITheme.font(false), Vector2(cx - lw * 0.5, H * 0.88 + 34), sl, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.45))

func _rider_mask() -> void:
	var d: Dictionary = rider
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	var disp := UITheme.display_font(900)
	var num := str(int(d.level))
	var size := 330 if num.length() < 3 else 250
	var nw := disp.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(disp, Vector2((W - nw) * 0.5, H * 0.56 + size * 0.14), num, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)   # the numeral is the foil
	draw_rect(Rect2(50, H * 0.745, (W - 100.0) * clampf(float(d.xp), 0.0, 1.0), 18), Color.WHITE)
	draw_rect(Rect2(5, 5, W - 10, H - 10), Color(1, 1, 1, 0.7), false, 8.0)

func _rider_back() -> void:
	_background("riderback")
	var t := Time.get_date_dict_from_system()
	var disp := UITheme.display_font(900)
	var body := UITheme.font(false)
	var days := ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
	var months := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
	_centered(body, days[int(t.weekday)], H * 0.2, 30, Tokens.ACCENT)
	_centered(disp, str(int(t.day)), H * 0.55, 300, Color.WHITE)
	_centered(disp, months[int(t.month) - 1], H * 0.7, 44, Color.WHITE)
	_centered(body, str(int(t.year)), H * 0.78, 28, Color(1, 1, 1, 0.55))
	_centered(disp, "RUNOUT", H * 0.93, 28, Color(1, 1, 1, 0.35))

func _back() -> void:
	_background("back")
	var c := Vector2(W, H) * 0.5
	draw_circle(c, 150.0, Color("232a3d"))
	draw_circle(c, 126.0, Color("ffd21f"))
	var disp := UITheme.display_font(900)
	var w := disp.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, 190).x
	draw_string(disp, c + Vector2(-w * 0.5, 66), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, Color("151a23"))
	_centered(disp, "RUNOUT", H - 70, 40, Color("7a8399"))
